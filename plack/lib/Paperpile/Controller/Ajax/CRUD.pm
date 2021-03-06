# Copyright 2009-2011 Paperpile
#
# This file is part of Paperpile
#
# Paperpile is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.

# Paperpile is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Affero General Public License for more details.  You should have
# received a copy of the GNU Affero General Public License along with
# Paperpile.  If not, see http://www.gnu.org/licenses.

package Paperpile::Controller::Ajax::CRUD;

use strict;
use warnings;
use Paperpile::Library::Publication;
use Paperpile::Job;
use Paperpile::Queue;
use Paperpile::FileSync;
use Data::Dumper;
use HTML::TreeBuilder;
use HTML::FormatText;
use File::Path;
use File::Spec;
use File::Copy;
use File::stat;
use URI::file;
use FreezeThaw;

use 5.010;

sub insert_entry {
  my ( $self, $c ) = @_;

  my $grid_id   = $c->params->{grid_id};
  my ($plugin, $selection) = $self->_get_selection($c);

  my %output    = ();

  my @pub_array   = ();
  my $collection_delta = 0;

  $self->_complete_pubs($c, $plugin, $selection);

  foreach my $pub (@$selection){
    # Make sure we update the labels list when we insert pubs that come with labels
    $collection_delta = 1 if ( $pub->labels_tmp );
    push @pub_array, $pub;
  }

  foreach my $pub (@pub_array) {

    # In case a pdf is present but not imported (e.g. in bibtex file
    # plugin with attachments) we set _pdf_tmp to make sure the PDF is
    # imported

    if ( $pub->pdf_name and !$pub->_imported ) {
      $pub->_pdf_tmp( $pub->pdf_name );
    }

  }

  $c->model('Library')->insert_pubs( \@pub_array, 1 );

  my $pubs = {};
  foreach my $pub (@pub_array) {
    $pub->_imported(1);

    my $old_guid = $pub->guid;

    # If guid has changed because pub was already in database we set
    # the old guid as key to the update hash. The guid field holds the
    # new guid and will update the store in the frontend.
    if ($pub->_old_guid){
      $old_guid = $pub->_old_guid;
    }

    # We also update the backend cache of the plugin with potentially
    # new guids and the new _imported flag
    $plugin->update_cache($pub);

    my $pub_hash = $pub->as_hash;

    $pubs->{ $old_guid } = $pub_hash;

  }

  # If the number of imported pubs is reasonable, we return the updated pub data
  # directly and don't reload the entire grid that triggered the import.
  if ( scalar( keys %$pubs ) < 50 ) {
    $c->stash->{data} = { pubs => $pubs };
    $c->stash->{data}->{pub_delta_ignore} = $grid_id;
  }

  if ($collection_delta) {
    $c->stash->{data}->{collection_delta} = 1;
  }

  # Trigger a complete reload
  $c->stash->{data}->{pub_delta} = 1;

  # Probably not the most efficient way but works for now
  $c->stash->{data}->{file_sync_delta} = $self->_get_sync_collections( $c, \@pub_array );

  $self->_save_plugin($c, $plugin);
  $self->_update_counts($c);

}

# Called by the front-end 'lookup details' button, to fetch more complete data
# for a given reference from an online resource. Basically this is a wrapper
# for the plugin's needs_completing($pub) and complete_details($pub) methods.
sub complete_entry  {

  my ( $self, $c ) = @_;

  my ($plugin, $selection) = $self->_get_selection($c);

  my $cancel_handle = $c->params->{cancel_handle};

  Paperpile::Utils->register_cancel_handle($cancel_handle);

  my @new_pubs = ();
  foreach my $pub (@$selection) {
    if ( $plugin->needs_completing($pub) ) {
      push @new_pubs, $plugin->complete_details($pub);
    }
  }

  $c->model('Library')->exists_pub( \@new_pubs );

  my $results  = {};

  foreach my $pub (@new_pubs){
    my $pub_hash;
    $pub_hash = $pub->as_hash;

    my $old_guid = $pub->guid;

    # Handle guid changes when entry turned out to be already in the
    # database after completion
    if ($pub->_old_guid){
      $old_guid = $pub->_old_guid;
      $plugin->update_cache($pub);
    }

    $results->{ $old_guid } = $pub_hash;

  }

  $self->_save_plugin($c, $plugin);

  $c->stash->{data} = { pubs => $results };

  Paperpile::Utils->clear_cancel($$);

}

sub new_entry  {

  my ( $self, $c ) = @_;

  my %fields = ();

  foreach my $key ( %{ $c->params } ) {
    next if (($key =~ /^_/) && ($key ne '_pdf_tmp'));
    $fields{$key} = $c->params->{$key};
  }

  my $match_job = $c->params->{match_job};

  my $pub = Paperpile::Library::Publication->new( {%fields} );

  $c->model('Library')->exists_pub( [$pub] );

  if ( $pub->_imported ) {
    DuplicateError->throw("Updates duplicate an existing reference in the database");
  }

  $c->model('Library')->insert_pubs( [$pub], 1 );

  $self->_update_counts($c);


  # Inserting a PDF that failed to match automatically and that has a
  # jobid in the queue.
  if ($match_job) {
    my $job = Paperpile::Job->new( { id => $match_job } );
    $job->update_status('DONE');
    $job->error('');
    $job->update_info( 'msg', "Data inserted manually." );
    $job->pub($pub);
    $job->save;
    $c->stash->{data}->{jobs}->{$match_job} = $job->as_hash;
  }

  # That's handled as form on the front-end so we have to explicitly
  # indicate success
  $c->stash->{success} = \1;

  $c->stash->{data}->{pub_delta} = 1;

  $c->stash->{data}->{file_sync_delta} = $self->_get_sync_collections( $c, [$pub] );

}

sub empty_trash  {
  my ( $self, $c ) = @_;

  my $library = $c->model('Library');
  my $data    = $library->get_trashed_pubs;
  $library->delete_pubs($data);

  $c->stash->{data} = { pub_delta => 1 };
  $c->stash->{num_deleted} = scalar @$data;
}

sub delete_entry  {
  my ( $self, $c ) = @_;
  my $mode   = $c->params->{mode};

  my ($plugin, $data) = $self->_get_selection($c);

  # ignore all entries that are not imported
  my @imported = ();
  foreach my $pub (@$data) {
    next if not $pub->_imported;
    push @imported, $pub;
  }

  $data = [@imported];

  $c->model('Library')->delete_pubs($data) if $mode eq 'DELETE';
  $c->model('Library')->trash_pubs( $data, 'RESTORE' ) if $mode eq 'RESTORE';

  if ( $mode eq 'TRASH' ) {
    $c->model('Library')->trash_pubs( $data, 'TRASH' );
    Paperpile::Utils->session($c, {undo_trash  => $data});
  }

  $self->_collect_update_data( $c, $data, [ '_imported', 'trashed' ] );

  $c->stash->{data}->{pub_delta} = 1;
  $c->stash->{num_deleted} = scalar @$data;

  $plugin->total_entries( $plugin->total_entries - scalar(@$data) );

  $self->_update_counts($c);
  $self->_save_plugin($c, $plugin);

  $c->stash->{data}->{file_sync_delta} = $self->_get_sync_collections( $c, $data );
  $c->stash->{data}->{undo_url} = '/ajax/crud/undo_trash';

}

sub undo_trash  {

  my ( $self, $c ) = @_;

  my $data = Paperpile::Utils->session($c)->{undo_trash};

  $c->model('Library')->trash_pubs( $data, 'RESTORE' );

  Paperpile::Utils->session($c, {undo_trash  => undef});

  $self->_update_counts($c);

  $c->stash->{data}->{pub_delta} = 1;

  $c->stash->{data}->{file_sync_delta} = $self->_get_sync_collections( $c, $data )

}

sub update_entry  {
  my ( $self, $c ) = @_;

  my $guid = $c->params->{guid};

  my $match_job = $c->params->{match_job};

  my $new_data = {};
  foreach my $field ( keys %{ $c->params } ) {
    next if $field =~ /grid_id/;
    $new_data->{$field} = $c->params->{$field};
  }

  my $new_pub = $c->model('Library')->update_pub( $guid, $new_data );

  foreach my $var ( keys %{ Paperpile::Utils->session($c) } ) {
    next if !( $var =~ /^grid_/ );
    my $plugin = Paperpile::Utils->session($c)->{$var};
    if ( $plugin->plugin_name eq 'DB' or $plugin->plugin_name eq 'Trash' ) {
      if ( $plugin->_hash->{$guid} ) {
        delete( $plugin->_hash->{$guid} );
        $plugin->_hash->{ $new_pub->guid } = $new_pub;
      }
    }
    Paperpile::Utils->session($c, {$var => $plugin});
  }


  # Inserting a PDF that failed to match automatically and that has a
  # jobid in the queue.
  if ($match_job) {
    my $job = Paperpile::Job->new( { id => $match_job } );
    $job->update_status('DONE');
    $job->error('');
    $job->update_info( 'msg', "Data inserted manually." );
    $job->pub($new_pub);
    $job->save;
    $c->stash->{data}->{jobs}->{$match_job} = $job->as_hash;
  }

  # That's handled as form on the front-end so we have to explicitly
  # indicate success
  $c->stash->{success} = \1;

  my $hash = $new_pub->as_hash;

  $c->stash->{data}->{pubs} = { $guid => $hash };

  $c->stash->{data}->{file_sync_delta} = $self->_get_sync_collections( $c, [$new_pub] )

}

sub lookup_entry  {
  my ( $self, $c ) = @_;

  my $old_data = {};
  foreach my $field ( keys %{ $c->params } ) {
    $old_data->{$field} = $c->params->{$field};
  }

  my $pub = Paperpile::Library::Publication->new($old_data);

  # Get default plugin order
  my @plugin_list = split( /,/, $c->model('Library')->get_setting('search_seq') );

  my $success_plugin;


  eval { $success_plugin = $pub->auto_complete( [@plugin_list] ); };

  my $e;

  if ( $e = Exception::Class->caught ) {
    if ( ref $e ) {
      $c->stash->{error} = $e->error;
    } else {
      die($@);
    }
  }

  if ($success_plugin) {

    $c->stash->{success_plugin} = $success_plugin;

    my $new_data = $pub->as_hash;

    $new_data->{guid} = '';

    $c->stash->{data} = $new_data;
  }

  # We always set success unless an unexpected exception occured and
  # handle everything in the success callback in the front-end.
  $c->stash->{success} = \1;

}

sub _match_single {

  my ( $self, $match_plugin ) = @_;

  my $plugin_module = "Paperpile::Plugins::Import::" . $match_plugin;
  my $plugin        = eval( "use $plugin_module; $plugin_module->" . 'new()' );

  my $pub = $self->pub;

  $pub = $plugin->match($pub);

  $self->pub($pub);

}

sub update_notes  {
  my ( $self, $c ) = @_;

  my $guid = $c->params->{guid};
  my $html = $c->params->{html};

  # If input field in rich text editor is empty it still contains a
  # "<br>"
  $html = '' if $html eq '<br>';

  $c->model('Library')->update_note($guid, $html);

  $c->stash->{data} = { pubs => { $guid => { annote => $html } } };

}

sub new_collection  {
  my ( $self, $c ) = @_;

  my $guid   = $c->params->{node_id};
  my $parent = $c->params->{parent_id};
  my $name   = $c->params->{text};
  my $type   = $c->params->{type};
  my $style  = $c->params->{style} || '0';

  $c->model('Library')->new_collection( $guid, $name, $type, $parent, $style );

  # Reload tree representation of collections -- Don't think we need that any more
  # my $tree = $c->model('Library')->get_setting('_tree');
  #if ($type eq 'LABEL'){
  #  $c->forward( '/ajax/tree/get_subtree', [ $tree, "LABEL_ROOT" ] );
  #} else {
  #  $c->forward( '/ajax/tree/get_subtree', [ $tree, "FOLDER_ROOT" ] );
  #}

}

sub move_in_collection  {
  my ( $self, $c ) = @_;

  my $grid_id = $c->params->{grid_id};
  my $guid    = $c->params->{guid};
  my $type    = $c->params->{type};
  my ($plugin, $data) = $self->_get_selection($c);

  my $what = $type eq 'FOLDER' ? 'folders' : 'labels';

  # First import entries that are not already in the database. Note:
  # Pushing on @to_be_imported actually copies the pub objects and
  # modifications are not reflected in $data. That's why we need this
  # clumsy code
  my @to_be_imported = ();
  foreach my $i (0..@$data-1){
    my $pub=$data->[$i];
    if (!$pub->_imported){
      push @to_be_imported, $pub;
      $data->[$i]=undef;
    }
  }

  if (@to_be_imported){
    $self->_complete_pubs($c, $plugin, \@to_be_imported);
    $c->model('Library')->insert_pubs( \@to_be_imported, 1 );
    my @new_data =();
    foreach my $pub (@to_be_imported){
      push @new_data, $pub;
    }
    foreach my $pub (@$data){
      next if !defined $pub;
      push @new_data, $pub;
    }
    $data=\@new_data;
  }

  my $dbh = $c->model('Library')->dbh;

  if ( $guid ne 'FOLDER_ROOT' ) {
    my $new_guid = $guid;
    $c->model('Library')->add_to_collection( $data, $new_guid );
  }

  if (@to_be_imported) {
    $self->_update_counts($c);
    my $pubs={};

    foreach my $pub (@to_be_imported) {
      my $pub_hash = $pub->as_hash;

      my $old_guid = $pub->guid;

      # Handle cases where guids have changed because it turned out to
      # be already in database after completing a partial ref
      if ($pub->_old_guid){
        $old_guid = $pub->_old_guid;
        $plugin->update_cache($pub);
      }

      $pubs->{ $old_guid} = $pub_hash;
    }

    $c->stash->{data}->{pubs} = $pubs;
    $c->stash->{data}->{pub_delta}        = 1;
    $c->stash->{data}->{pub_delta_ignore} = $grid_id;
  } else {
    $self->_collect_update_data( $c, $data, [$what] );
  }

  $self->_save_plugin($c, $plugin);

  $c->stash->{data}->{collection_delta} = 1;

  $c->stash->{data}->{file_sync_delta} = $self->_get_sync_collections( $c, undef, $guid );
}

sub remove_from_collection  {
  my ( $self, $c ) = @_;

  my $collection_guid = $c->params->{collection_guid};
  my $type            = $c->params->{type};

  my ($plugin, $data) = $self->_get_selection($c);

  my $what = $type eq 'FOLDER' ? 'folders' : 'labels';

  $c->model('Library')->remove_from_collection( $data, $collection_guid );

  $self->_collect_update_data( $c, $data, [$what] );
  $c->stash->{data}->{collection_delta} = 1;

  $c->stash->{data}->{file_sync_delta} =
    $self->_get_sync_collections( $c, undef, $collection_guid );

  $self->_save_plugin($c, $plugin);

}

sub delete_collection  {
  my ( $self, $c ) = @_;

  my $guid = $c->params->{guid};
  my $type = $c->params->{type};

  $c->model('Library')->delete_collection( $guid, $type );

  # Not sure if we need to update the tree structure in the
  # backend in some way here.

  my $what = $type eq 'FOLDER' ? 'folders' : 'labels';

  my $pubs = $self->_get_cached_data($c);
  foreach my $pub (@$pubs) {
    my $new_list = $pub->$what;
    $new_list =~ s/^$guid,//g;
    $new_list =~ s/^$guid$//g;
    $new_list =~ s/,$guid$//g;
    $new_list =~ s/,$guid,/,/g;
    $pub->$what($new_list);
  }

  $self->_collect_update_data( $c, $pubs, [$what] );
  $c->stash->{data}->{collection_delta} = 1;
}

sub rename_collection  {
  my ( $self, $c ) = @_;

  my $guid     = $c->params->{guid};
  my $new_name = $c->params->{new_name};

  $c->model('Library')->rename_collection( $guid, $new_name );

  my $type = 'LABELS';
  my $what = $type eq 'FOLDER' ? 'folders' : 'labels';
  my $pubs = $self->_get_cached_data($c);
  $self->_collect_update_data( $c, $pubs, [$what] );
  $c->stash->{data}->{collection_delta} = 1;
}

sub move_collection  {
  my ( $self, $c ) = @_;

  # The node that was moved
  my $drop_guid = $c->params->{drop_node};

  # The node to which it was moved
  my $target_guid = $c->params->{target_node};

  my $type = $c->params->{type};

  # Either 'append' for dropping into the node, or 'below' or 'above'
  # for moving nodes on the same level
  my $position = $c->params->{point};

  $c->model('Library')->move_collection( $target_guid, $drop_guid, $position, $type );

  $c->stash->{data}->{collection_delta} = 1;
}

# Sorts a set of sibling collection nodes by the given order of IDs.
sub sort_collection  {
  my ( $self, $c ) = @_;

  my $m = $c->model('Library');

  ## If still in use needs to be rewritten with $c->params->get_all('node_id_order')!!

  # The desired order of nodes, given as a list of GUIDs.
  my $node_id_order = $c->params->{node_id_order};
  my @id_order;
  if ( ref $node_id_order eq 'ARRAY' ) {
    @id_order = @{$node_id_order};
  } else {
    @id_order = ($node_id_order);
  }

  # The parent node under which all these nodes live, given as a GUID.
  my $parent_id = $c->params->{parent_id};
  my $type      = $m->get_collection_type($parent_id);

  # Go in order, putting each sub-node at the end of the parent node's child list.
  foreach my $id (@id_order) {
    $m->move_collection( $parent_id, $id, 'append', $type );
  }
}

sub update_collection  {
  my ( $self, $c ) = @_;

  my $guid = $c->params->{guid};

  my $data = {};

  foreach my $field ('name','style','sort_order','hidden'){
    if (defined $c->params->{$field}){
      $data->{$field} = $c->params->{$field};
    }
  }

  $c->model('Library')->update_collection_fields( $guid, $data);

  $c->stash->{data}->{collection_update} = 1;
}

sub list_collections  {

  my ( $self, $c ) = @_;

  my $type = $c->params->{type};

  my $model = $c->model('Library');

  my ($dbh, $in_prev_tx) = $model->begin_or_continue_tx;

  my $hist = $model->histogram('labels');

  my $sth = $dbh->prepare("SELECT * FROM Collections WHERE type='$type' order by sort_order");

  my @data = ();

  $sth->execute;
  while ( my $row = $sth->fetchrow_hashref() ) {
    my $name = $row->{name};
    if ( length($name) >= 18 ) {
      $name = substr($name,0,15) . '...';
    }

    push @data, {
      guid       => $row->{guid},
      name       => $row->{name},
      display_name => $name,
      type       => $row->{type},
      parent     => $row->{parent},
      sort_order => $row->{sort_order},
      hidden     => $row->{hidden},
      style      => $row->{style},
      count      => $hist->{ $row->{guid} }->{count}
      };
  }

  $model->commit_or_continue_tx($in_prev_tx);

  my %metaData = (
    root   => 'data',
    fields => [ 'guid', 'name', 'display_name', 'type', 'parent', 'sort_order', 'hidden', 'style', 'count' ],
  );

  $c->stash->{data}     = [@data];
  $c->stash->{metaData} = {%metaData};
}

# Returns the list of labels sorted by name.
sub sort_labels_by_name  {
  my ( $self, $c ) = @_;

  $c->model('Library')->sort_labels('name');

  $c->stash->{data}->{collection_delta} = 1;
}

# Returns the list of labels sorted by paper count.
sub sort_labels_by_count  {
  my ( $self, $c ) = @_;

  my $dbh = $c->model('Library')->dbh;

  $c->model('Library')->sort_labels('count');

  $c->stash->{data}->{collection_delta} = 1;
}

sub batch_update  {
  my ( $self, $c ) = @_;

  my ($plugin, $data) = $self->_get_selection($c);

  my $q    = Paperpile::Queue->new();
  my @jobs = ();
  foreach my $pub (@$data) {
    my $j = Paperpile::Job->new(
      job_type => 'METADATA_UPDATE',
      pub  => $pub,
    );

    $j->hidden(1) if ( scalar(@$data) == 1 );

    $j->pub->_metadata_job(
      { id => $j->id, status => $j->status, msg => $j->info->{msg}, hidden => $j->hidden } );

    push @jobs, $j;
  }

  $q->submit( \@jobs );
  $q->save;
  $q->run;
  $self->_collect_update_data( $c, $data, ['_metadata_job'] );

  $self->_save_plugin($c, $plugin);

  $c->stash->{data}->{job_delta} = 1;
}

sub batch_download  {
  my ( $self, $c ) = @_;

  my ($plugin, $data) = $self->_get_selection($c);

  my $q = Paperpile::Queue->new();

  my @jobs = ();

  foreach my $pub (@$data) {

    my $hidden = ( scalar(@$data) == 1 ) ? 1 : 0;

    my $j = Paperpile::Job->new(
      job_type   => 'PDF_SEARCH',
      pub    => $pub,
      hidden => $hidden
    );

    $j->pub->_search_job(
      { id => $j->id, status => $j->status, msg => $j->info->{msg}, hidden => $j->hidden } );

    push @jobs, $j;
  }

  $q->submit( \@jobs );
  $q->save;
  $q->run;
  $self->_collect_update_data( $c, $data, ['_search_job'] );

  $self->_save_plugin($c, $plugin);

  $c->stash->{data}->{job_delta} = 1;

}

sub attach_file  {
  my ( $self, $c ) = @_;

  my $guid   = $c->params->{guid};
  my $file   = $c->params->{file};
  my $is_pdf = $c->params->{is_pdf};

  my $grid_id = $c->params->{grid_id};
  my $plugin  = Paperpile::Utils->session($c)->{"grid_$grid_id"};

  my $pub = $plugin->find_guid($guid);

  $c->model('Library')->attach_file( $file, $is_pdf, $pub );

  $self->_collect_update_data( $c, [$pub],
    [ 'pdf', 'pdf_name', 'attachments', '_attachments_list' ] );

}

sub delete_file  {
  my ( $self, $c ) = @_;

  my $file_guid = $c->params->{file_guid};
  my $pub_guid  = $c->params->{pub_guid};
  my $is_pdf    = $c->params->{is_pdf};

  my $grid_id = $c->params->{grid_id};
  my $plugin  = Paperpile::Utils->session($c)->{"grid_$grid_id"};

  my $pub = $plugin->find_guid($pub_guid);

  my $undo_path = $c->model('Library')->delete_attachment( $file_guid, $is_pdf, $pub, 1 );

  Paperpile::Utils->session(
    $c, {
      undo_delete_attachment => {
        file      => $undo_path,
        is_pdf    => $is_pdf,
        grid_id   => $grid_id,
        pub_guid  => $pub_guid,
        file_guid => $file_guid
      }
    }
  );

  # Kind of a hack: delete the _search_job info before sending back our JSON update.
  if ($is_pdf) {
    delete $pub->{_search_job};
    $pub->pdf('');
  }

  $self->_collect_update_data( $c, [$pub],
    [ 'attachments', '_attachments_list', 'pdf', '_search_job'] );

}

sub undo_delete  {
  my ( $self, $c ) = @_;

  my $undo_data = Paperpile::Utils->session($c)->{"undo_delete_attachment"};

  Paperpile::Utils->session( $c, { undo_delete_attachment => undef } );

  my $file   = $undo_data->{file};
  my $is_pdf = $undo_data->{is_pdf};

  my $grid_id   = $undo_data->{grid_id};
  my $pub_guid  = $undo_data->{pub_guid};
  my $file_guid = $undo_data->{file_guid};

  my $plugin = Paperpile::Utils->session($c) ->{"grid_$grid_id"};

  my $pub = $plugin->find_guid($pub_guid);

  my $attached_file = $c->model('Library')->attach_file( $file, $is_pdf, $pub, $file_guid );

  $self->_collect_update_data( $c, [$pub], [ 'pdf', 'attachments', '_attachments_list' ] );

}

sub merge_duplicates  {
  my ( $self, $c ) = @_;

  my $grid_id     = $c->params->{grid_id};
  my $ref_guid    = $c->request->param('ref_guid');
  my @other_guids = $c->request->param('other_guids');

  my $plugin  = Paperpile::Utils->session($c)->{"grid_$grid_id"};
  my $library = $c->model('Library');

  my $ref_pub = $plugin->find_guid($ref_guid);
  my $dup_id  = $ref_pub->_dup_id;

  # Create new object from reference pub
  my $merged_pub = Paperpile::Library::Publication->new( $ref_pub->as_hash );
  $merged_pub->refresh_fields;
  $merged_pub->_imported(0);
  $merged_pub->guid(undef);

  # Use dummy title to avoid sha1 clash
  my $title = $merged_pub->title;
  $merged_pub->title('dummy');
  $library->insert_pubs( [$merged_pub], 1 );
  $merged_pub->title($title);

  my @other_pubs;

  foreach my $other_guid ( $ref_guid, @other_guids ) {
    my $pub = $plugin->find_guid($other_guid);
    if ($pub) {
      $merged_pub->merge_into_me( $pub, $library );
      $pub->title( '[Discarded Duplicate] ' . $pub->title );
      $library->update_pub( $pub->guid, $pub->as_hash );
      push @other_pubs, $pub;
    }
  }

  # Trash all the pre-merge pubs.
  $library->trash_pubs( \@other_pubs, 'TRASH' );

  # Make sure a new citation key is generated
  $merged_pub->citekey('');
  $merged_pub = $library->update_pub( $merged_pub->guid, $merged_pub->as_hash );
  $plugin->replace_merged_items( $dup_id, $merged_pub );

  $self->_save_plugin($c, $plugin);

  $self->_collect_update_data( $c, [$merged_pub] );
  $c->stash->{data}->{pub_delta} = 1;
}

sub sync_files  {

  my ( $self, $c ) = @_;

  # Get non-redundant list of collections
  my %tmp;
  foreach my $collection ( split( /,/, $c->params->{collections} ) ) {
    $tmp{$collection} = 1;
  }
  my @collections = keys %tmp;

  my $map = $c->model('User')->get_setting('file_sync');

  my $sync = Paperpile::FileSync->new( map => $map );

  my %warnings;

  foreach my $collection (@collections) {
    eval { $sync->sync_collection($collection); };
    my $warning = 'A problem occured during BibTeX export. ';

    if ($@) {
      my $e = Exception::Class->caught();
      if ( ref $e ) {
        $warning = $e->error;
      } else {
        $warning .= $@;
      }
      $warnings{$collection} = $warning;
      $c->log->error($warning);
    }
  }

  $c->stash->{data}->{warnings} = {%warnings};

}

# Returns list of all collection guids that need to be re-synced when
# references in $data change. If $guid is given and $data is undefined
# the function checks if $guid or its parents need to be synced,

sub _get_sync_collections {
  my ( $self, $c, $data, $guid ) = @_;

  my $sync_files = $c->model('User')->get_setting('file_sync');

  return [] if !( ref $sync_files );

  my $model = $c->model('Library');
  my $dbh   = $model->dbh;

  my %collections;

  # Either take $guid or search folders or labels field of publications
  # in $data
  if ( defined $guid ) {
    $collections{$guid} = 1;
  } else {
    foreach my $pub (@$data) {
      my @tmp;
      if ( $pub->folders ) {
        push @tmp, split( /,/, $pub->folders );
      }
      if ( $pub->labels ) {
        push @tmp, split( /,/, $pub->labels );
      }
      foreach my $collection (@tmp) {
        $collections{$collection} = 1;
      }
    }
  }

  # Add parents for subfolder and only consider collections whith an
  # active fileync setting
  my %final_collections;

  foreach my $collection ( keys %collections ) {
    my @parents = $model->find_collection_parents( $collection );

    foreach my $parent (@parents) {
      if ( $sync_files->{$parent}->{active} ) {
        $final_collections{$parent} = 1;
      }
    }

    if ( $sync_files->{$collection}->{active} ) {
      $final_collections{$collection} = 1;
    }
  }

  # Always add FOLDER_ROOT if active
  if ( $sync_files->{'FOLDER_ROOT'}->{active} ) {
    $final_collections{'FOLDER_ROOT'} = 1;
  }

  return [ keys %final_collections ];

}


# Gets data for a selection in the frontend from the plugin object
# cache. Returns ($plugin,$data) where $plugin is the plugin object
# and $data the list of pulication objects.

sub _get_selection {

  my ( $self, $c, $light_objects ) = @_;

  my $grid_id   = $c->params->{grid_id};
  my $plugin    = Paperpile::Utils->session($c)->{"grid_$grid_id"};
  my @selection = $c->params->get_all('selection');

  $plugin->light_objects( $light_objects ? 1 : 0 );

  my @data = ();

  if ( $selection[0] eq 'ALL' ) {
    @data = @{ $plugin->all };
    my $model = $c->model('Library');
    $model->exists_pub( \@data );
    foreach my $pub (@data) {
      $pub->refresh_attachments($model);
    }
  } else {
    for my $guid (@selection) {
      my $pub = $plugin->find_guid($guid);
      if ( defined $pub ) {
        push @data, $pub;
      }
    }
  }

  return ( $plugin, [@data] );
}

# Our custom session handling does not transparently save changes to
# session variables, so we have to save the plugin object manually
# whenever we have changed it

sub _save_plugin {
  my ( $self, $c, $plugin ) = @_;
  my $grid_id = $c->params->{grid_id};

  return Paperpile::Utils->session($c, {"grid_$grid_id"=>$plugin});
}

# Complete details for plugins that don't provide full information
# Plugins like GoogleScholar might want to fetch some more details
# before importing by using their complete_details($pub) method,
# and plugins like Feed.pm may or may not have already matched the 
# reference (after a 'lookup details' click).
sub _complete_pubs {

  my ( $self, $c, $plugin, $pubs ) = @_;

  my $plugin_list = undef;

  foreach my $pub (@$pubs) {

    next if $pub->_imported;

    if ( $plugin->needs_completing($pub) ) {
      $pub = $plugin->complete_details($pub);
    }

    if ( $plugin->needs_match_before_import($pub) ) {
      if ( !defined $plugin_list ) {
        $plugin_list = [ split( /,/, $c->model('Library')->get_setting('search_seq') ) ];
      }
      $pub->auto_complete($plugin_list);
    }
  }
}


# Returns a list of all publications objects from all current plugin
# objects (i.e. all open grid tabs in the frontend)
sub _get_cached_data {

  my ( $self, $c ) = @_;

  my @list = ();

  foreach my $var ( keys %{ Paperpile::Utils->session($c) } ) {
    next if !( $var =~ /^grid_/ );
    my $plugin = Paperpile::Utils->session($c)->{$var};
    foreach my $pub ( values %{ $plugin->_hash } ) {
      push @list, $pub;
    }
  }

  return [@list];
}

# If we add or delete items we need to update the overall count in the
# database plugins to make sure the number is up-to-date when it is
# reloaded the next time by the frontend.

sub _update_counts {

  my ( $self, $c ) = @_;

  foreach my $var ( keys %{ Paperpile::Utils->session($c) } ) {
    next if !( $var =~ /^grid_/ );
    my $plugin = Paperpile::Utils->session($c)->{$var};
    if ( $plugin->plugin_name eq 'DB' or $plugin->plugin_name eq 'Trash' ) {
      $plugin->update_count();
      Paperpile::Utils->session($c, {$var => $plugin});
    }
  }
}

sub _collect_update_data {
  my ( $self, $c, $pubs, $fields ) = @_;

  $c->stash->{data} = {} unless ( defined $c->stash->{data} );

  my @pubs_copy;

  my $max_output_size = 30;
  if ( scalar(@$pubs) > $max_output_size ) {
    $c->stash->{data}->{pub_delta} = 1;
    @pubs_copy = @$pubs[ 0 .. $max_output_size ];
  } else {
    @pubs_copy = @$pubs;
  }

  my %output = ();
  foreach my $pub (@pubs_copy) {
    my $hash = $pub->as_hash;

    my $pub_fields = {};
    if ($fields) {
      map { $pub_fields->{$_} = $hash->{$_} } @$fields;
    } else {
      $pub_fields = $hash;
    }
    $output{ $hash->{guid} } = $pub_fields;
  }

  $c->stash->{data}->{pubs} = \%output;
}

1;
