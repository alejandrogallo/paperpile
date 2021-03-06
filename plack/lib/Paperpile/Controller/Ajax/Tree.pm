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


package Paperpile::Controller::Ajax::Tree;

use strict;
use warnings;
use Paperpile::Utils;
use Paperpile::Library::Publication;
use Paperpile::Plugins::Import::Feed;
use Data::Dumper;
use URI::Escape;
use 5.010;


sub get_node  {
  my ( $self, $c ) = @_;

  my $node = $c->params->{node};

  my $tree = $c->model('Library')->get_setting('_tree');

  if ( not $tree ) {
    $tree = $self->get_default_tree($c);
    $c->model('Library')->set_setting('_tree', $tree);
  }

  if ( $node eq 'ROOT' ) {
    $c->stash->{tree} = $self->get_complete_tree( $c, $tree );
    return;
  }

  my $subtree = $self->get_subtree($c, $tree, $node );


  my @data = ();
  foreach my $child ( $subtree->getAllChildren ) {
    push @data, $self->_get_js_object( $child, $c->params->{checked} );
  }
  $c->stash->{tree} = [@data];

}

sub get_complete_tree {

  my ( $self, $c, $tree ) = @_;

  # Collections always generated dynamically
  $self->get_subtree($c, $tree, 'LABEL_ROOT' );
  $self->get_subtree($c, $tree, 'FOLDER_ROOT' );

  my $dump = '';

  # Simple way of getting the complete tree. We just create perl
  # expression and eval it. Not elegant but easy to implement starting
  # from the example in the Tree::Simple docs.
  $tree->traverse(
    sub {
      my ($_tree) = @_;
      my $_dump = Dumper( $self->_get_js_object( $_tree, 0 ) );

      # Remove first and last line with "$VAR1={" and "};", resp.
      my @t = split( /\n/, $_dump );
      my @tmp = @t[ 1 .. $#t - 1 ];
      $dump .= '{' . join( "\n", @tmp );
      if ( $_tree->isLeaf ) {
        $dump .= '},';
      } else {
        $dump .= ', children=>[';
      }
    },
    sub {
      my ($_tree) = @_;
      if ( !$_tree->isLeaf ) {
        $dump .= ']},';
      }
    }
  );

  return eval( '[' . $dump . ']' );

}

sub new_active  {
  my ( $self, $c ) = @_;

  my $node_id   = $c->params->{node_id};
  my $parent_id = $c->params->{parent_id};

  my $tree = $c->model('Library')->get_setting('_tree');

  my $sub_tree = $self->get_subtree($c, $tree, $parent_id );

  my %params = ();

  foreach my $key ( keys %{ $c->params } ) {
    next if $key =~ /^_/;
    $params{$key} = $c->params->{$key};
  }

  $params{id} = $node_id;
  delete( $params{node_id} );

  my $new = Tree::Simple->new( {%params} );
  $new->setUID($node_id);
  $sub_tree->addChild($new);

  $c->model('Library')->set_setting( '_tree', $tree );
}

sub new_rss  {

  my ( $self, $c ) = @_;

  my $node_id   = $c->params->{node_id};
  my $parent_id = $c->params->{parent_id};

  my $tree = $c->model('Library')->get_setting('_tree');

  my $sub_tree = $self->get_subtree($c, $tree, $parent_id );

  my %params        = ();
  my %plugin_params = ();

  foreach my $key ( keys %{ $c->params } ) {
    next if $key =~ /^_/;
    $params{$key} = $c->params->{$key};

    if ( $key =~ /^plugin_/ ) {
      my $newKey = $key;
      $newKey =~ s/^plugin_//;
      $plugin_params{$newKey} = $c->params->{$key};
    }
  }

  $params{id} = $node_id;
  delete( $params{node_id} );

  my $plugin = Paperpile::Plugins::Import::Feed->new( {%plugin_params} );
  $plugin->connect();

  my $title = $plugin->title;

  if ( length($title) > 20 ) {
    ($title) = $title =~ /(.{1,20}\W)/gms;
    $title .= "...";
  }

  $params{text}         = $title;
  $params{plugin_title} = $title;
  $params{qtip}         = uri_unescape($params{plugin_url});

  my $new = Tree::Simple->new( {%params} );
  $new->setUID($node_id);
  $sub_tree->addChild($new);

  $c->model('Library')->set_setting( '_tree', $tree );

  $c->stash->{title}   = $title;

}

sub delete_active  {
  my ( $self, $c ) = @_;

  my $node_id = $c->params->{node_id};

  my $tree = $c->model('Library')->get_setting('_tree');

  my $subtree = $self->get_subtree->($self, $tree, $node_id );

  if ( $subtree->getNodeValue->{plugin_name} eq 'Feed' ) {
    my $plugin = Paperpile::Plugins::Import::Feed->new( id => $subtree->getNodeValue->{plugin_id} );
    $plugin->cleanup();
  }

  $subtree->getParent->removeChild($subtree);

  $c->model('Library')->set_setting( '_tree', $tree );

}

sub save_node_params  {
  my ( $self, $c ) = @_;

  my $request_params = $c->params;
  my $node_id        = delete $request_params->{node_id};

  my $tree = $c->model('Library')->get_setting('_tree');

  my $subtree = $self->get_subtree($c, $tree, $node_id );

  my $node_params = $subtree->getNodeValue();

  foreach my $key ( keys %$request_params ) {
    $node_params->{$key} = $request_params->{$key};
  }

  $c->model('Library')->set_setting( '_tree', $tree );
}

sub rename_node  {
  my ( $self, $c ) = @_;

  my $node_id  = $c->params->{node_id};
  my $new_text = $c->params->{new_text};

  my $tree = $c->model('Library')->get_setting('_tree');

  my $subtree = $self->get_subtree($c, $tree, $node_id );

  my $pars = $subtree->getNodeValue();

  $pars->{text}         = $new_text;
  $pars->{plugin_title} = $new_text;

  $c->model('Library')->set_setting( '_tree', $tree );

}

sub set_node_order  {
  my ( $self, $c ) = @_;

  my $target_node   = $c->params->{target_node};
  my $node_id_order = $c->params->{node_id_order};
  my @id_order;
  if ( ref $node_id_order eq 'ARRAY' ) {
    @id_order = @{$node_id_order};
  } else {
    @id_order = ($node_id_order);
  }

  my $tree = $c->model('Library')->get_setting('_tree');

  my $root = $self->get_subtree($c,  $tree, $target_node );

  my @nodes;
  my $i = 0;
  foreach my $id (@id_order) {
    my $node = $self->get_subtree($c, $tree, $id );
    push @nodes, $root->removeChild($node);
  }

  $i = 0;
  foreach my $node (@nodes) {
    $root->insertChild( $i, $node );
    $i++;
  }

  $c->model('Library')->set_setting( '_tree', $tree );

}

sub move_node  {
  my ( $self, $c ) = @_;

  # The node that was moved
  my $drop_node = $c->params->{drop_node};

  # The node to which it was moved
  my $target_node = $c->params->{target_node};

  # Either 'append' for dropping into the node, or 'below' or 'above'
  # for moving nodes on the same level
  my $point = $c->params->{point};

  my $tree = $c->model('Library')->get_setting('_tree');

  # Get nodes from the ids
  my $drop_subtree   = $self->get_subtree($c, $tree, $drop_node );
  my $target_subtree = $self->get_subtree($c, $tree, $target_node );

  # Remove the subtree that was moved
  $drop_subtree = $drop_subtree->getParent->removeChild($drop_subtree);

  # Re-insert at the appropriate node
  if ( $point eq 'append' ) {
    $target_subtree->addChild($drop_subtree);
  } else {
    my $target_index = $target_subtree->getIndex();
    $target_index++ if ( $point eq 'below' );
    $target_subtree->getParent->insertChild( $target_index, $drop_subtree );
  }

  $c->model('Library')->set_setting( '_tree', $tree );

}

sub _get_js_object {

  my ( $self, $node, $checked ) = @_;

  # make deep copy to avoid touching the tree structure which gave
  # unexpected results...
  my $h = { %{ $node->getNodeValue() } };

  # we store node ids explicitely as "UID"s in backend and as
  # "node.id" in frontend
  $h->{id} = $node->getUID;

  if ( $node->isLeaf() ) {
    $h->{expanded} = \1;
    $h->{children} = [];
  }

  $h->{hidden} = \0;
  $h->{nodeType} = 'async';
  $h->{leaf}     = \0;
  delete $h->{uiProvider};

  return $h;

}

sub get_subtree  {

  my ( $self, $c, $tree, $UID ) = @_;

  my $subtree = undef;

  # return the whole tree if it has the given UID
  # (only in case of 'root')
  if ( $tree->getUID eq $UID ) {
    return $tree;
  }

  # Search the tree recursively otherwise
  else {
    $tree->traverse(
      sub {
        my ($_tree) = @_;
        $subtree = $_tree if $_tree->getUID eq $UID;
      }
    );
  }

  # Collections always generated dynamically
  if ( $subtree->getUID eq 'LABEL_ROOT' ) {
    $self->get_collections($c, $subtree,'LABEL' );
  }

  if ( $subtree->getUID eq 'FOLDER_ROOT' ) {
    $self->get_collections($c, $subtree,'FOLDER' );
  }

  return $subtree;
}

# Restore subtree for labels and folders from database

sub get_collections  {

  my ( $self, $c, $tree, $type ) = @_;

  # First remove old children
  foreach my $child ( $tree->getAllChildren ) {
    $tree->removeChild($child);
  }

  # Collect all data from the database table
  my @collections = ();
  my $sth = $c->model('Library')->dbh->prepare("SELECT * from Collections WHERE type='$type';");
  $sth->execute();
  while ( my $row = $sth->fetchrow_hashref() ) {
#    push @collections, $row;
  }

  # Recursively fill subtree
  _add_collection_subtree( $tree, [@collections], 'ROOT', $type );

}

# Recursive function that adds all children in the right order for the
# current parent node

sub _add_collection_subtree {
  my ( $tree, $collections, $parent, $type ) = @_;


  my @nodes = grep { $_->{parent} eq $parent } @$collections;

  @nodes = sort { $a->{sort_order} <=> $b->{sort_order} } @nodes;

  foreach my $node (@nodes) {
    my $new_node = Tree::Simple->new( _get_collection_pars( $node, $type ) );
    $new_node->setUID( $node->{guid} );
    _add_collection_subtree( $new_node, $collections, $node->{guid}, $type );
    $tree->addChild($new_node);
  }
}

# Helper function to create a node object for a label or folder node

sub _get_collection_pars {

  my ( $coll, $type ) = @_;

  my $pars = {
    text         => $coll->{name},
    type         => $type eq 'FOLDER' ? 'FOLDER' : 'LABEL',
    hidden       => 0,
    plugin_name  => 'DB',
    plugin_mode  => 'FULLTEXT',
    plugin_title => $coll->{name},
  };

  if ( $type eq 'FOLDER' ) {
    $pars->{plugin_query}      = "folderid:" . $coll->{guid};
    $pars->{plugin_base_query} = "folderid:" . $coll->{guid};
    $pars->{iconCls}           = 'pp-icon-folder';
    $pars->{plugin_iconCls}    = 'pp-icon-folder';
  } else {
    $pars->{plugin_query}      = "labelid:" . $coll->{guid};
    $pars->{plugin_base_query} = "labelid:" . $coll->{guid};
    $pars->{iconCls}           = 'pp-icon-empty';
    $pars->{plugin_iconCls}    = 'pp-icon-label';
    $pars->{cls} ='pp-label-tree-node pp-label-tree-style-'.$coll->{style};
    $pars->{labelStyle} = $coll->{style};
  }

  return $pars;
}

sub get_default_tree  {

  my ( $self, $c ) = @_;

  #### Root

  my $root = Tree::Simple->new( {
      text    => 'Root',
      hidden  => 0,
      builtin => 1,
    },
    Tree::Simple->ROOT
  );

  $root->setUID('ROOT');

  #### / Local Library

  my $local_lib = Tree::Simple->new( {
      text    => 'Library',
      type    => 'DB',
      query   => '',
      cls     => 'pp-tree-heading',
      iconCls => 'pp-icon-empty',
      hidden  => 0,
      builtin => 1,
    },
    $root
  );

  $local_lib->setUID('LOCAL_ROOT');

  #### / Local Library / Folders

  my $folders = Tree::Simple->new( {
      text    => 'All Papers',
      type    => "FOLDER_ROOT",
      path    => '/',
      iconCls => 'pp-icon-page',
      hidden  => 0,
      builtin => 1,
    },
    $local_lib
  );

  $folders->setUID('FOLDER_ROOT');

  #### / Local Library / Labels

  my $labels = Tree::Simple->new( {
      text    => 'Labels',
      type    => "LABEL_ROOT",
      iconCls => 'pp-icon-label',
      hidden  => 0,
      builtin => 1,
    },
    $local_lib
  );
  $labels->setUID('LABEL_ROOT');

  #### / Local Library / Trash

  $folders = Tree::Simple->new( {
      text        => 'Trash',
      type        => "TRASH",
      iconCls     => 'pp-icon-trash',
      plugin_name => 'Trash',
      hidden      => 0,
      builtin     => 1,
    },
    $local_lib
  );

  $folders->setUID('TRASH');

  #### / Live & Feeds

  my $active = Tree::Simple->new( {
      text    => 'Live Folders & Feeds',
      type    => "ACTIVE",
      path    => '/',
      iconCls => 'pp-icon-empty',
      cls     => 'pp-tree-heading',
      hidden  => 0,
      builtin => 1,
    }
  );
  $active->setUID('ACTIVE_ROOT');

  $root->addChild($active);

  $active->addChild(
    Tree::Simple->new( {
        type         => 'ACTIVE',
        text         => 'Nature',
        plugin_title => 'Nature',
        plugin_name  => 'Feed',
        plugin_id    => 'NatureRSS',
        plugin_mode  => 'FULLTEXT',
        plugin_url   => 'http://feeds.nature.com/nature/rss/current?format=xml',
        qtip         => 'http://feeds.nature.com/nature/rss/current?format=xml',
        iconCls      => 'pp-icon-feed',
        hidden       => 0,
        builtin      => 1,
      }
    )
  );

  $active->addChild(
    Tree::Simple->new( {
        type         => 'ACTIVE',
        text         => 'Science',
        plugin_title => 'Science',
        plugin_name  => 'Feed',
        plugin_id    => 'ScienceRSS',
        plugin_mode  => 'FULLTEXT',
        plugin_url   => 'http://www.sciencemag.org/rss/current.xml',
        qtip         => 'http://www.sciencemag.org/rss/current.xml',
        iconCls      => 'pp-icon-feed',
        hidden       => 0,
        builtin      => 1,
      }
    )
  );

  $active->addChild(
    Tree::Simple->new( {
        type         => 'ACTIVE',
        text         => 'PLoS One',
        plugin_title => 'PLoS One',
        plugin_name  => 'Feed',
        plugin_mode  => 'FULLTEXT',
        plugin_id    => 'PLoSOneRSS',
        plugin_url   => 'http://feeds.plos.org/plosone/PLoSONE?format=xml',
        qtip         => 'http://feeds.plos.org/plosone/PLoSONE?format=xml',
        iconCls      => 'pp-icon-feed',
        hidden       => 0,
        builtin      => 1,
      }
    )
  );

  ##### / Tools & Resources

  my $plugins = Tree::Simple->new( {
      text    => 'Resources & Tools',
      type    => 'IMPORT_PLUGIN',
      cls     => 'pp-tree-heading',
      iconCls => 'pp-icon-empty',
      hidden  => 0,
      builtin => 1,
    },
    $root
  );

  $plugins->setUID('IMPORT_PLUGIN_ROOT');

  $plugins->addChild(
    Tree::Simple->new( {
        type         => 'IMPORT_PLUGIN',
        plugin_name  => 'PubMed',
        text         => 'PubMed',
        plugin_query => '',
        iconCls      => 'pp-icon-pubmed',
        hidden       => 0,
        builtin      => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        type         => 'IMPORT_PLUGIN',
        plugin_name  => 'GoogleScholar',
        text         => 'Google Scholar',
        plugin_query => '',
        iconCls      => 'pp-icon-google',
        hidden       => 0,
        builtin      => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        type         => 'IMPORT_PLUGIN',
        plugin_name  => 'ArXiv',
        text         => 'ArXiv',
        plugin_query => '',
        iconCls      => 'pp-icon-arxiv',
        hidden       => 0,
        builtin      => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        text    => 'Import PDFs',
        type    => 'PDFEXTRACT',
        iconCls => 'pp-icon-import-pdf',
        qtip    => 'Import one or more PDFs to your library',
        hidden  => 0,
        builtin => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        text    => 'Import File',
        type    => 'FILE_IMPORT',
        iconCls => 'pp-icon-import-file',
        qtip    => 'Import references from EndNote, BibTeX <br> and other bibliography files.',
        hidden  => 0,
        builtin => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        type    => 'CLOUDS',
        text    => 'Cloud View',
        iconCls => 'pp-icon-clouds',
        hidden  => 0,
        builtin => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        type    => 'DUPLICATES',
        text    => 'Find Duplicates',
        iconCls => 'pp-icon-duplicates',
        hidden  => 0,
        builtin => 1,
      }
    )
  );

  $plugins->addChild(
    Tree::Simple->new( {
        type    => 'FEEDBACK',
        text    => 'Feedback',
        iconCls => 'pp-icon-feedback',
        hidden  => 0,
        builtin => 1,
      }
    )
  );

  return $root;
}



1;

