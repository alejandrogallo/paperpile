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


package Paperpile::Controller::Ajax::Queue;

use strict;
use warnings;
use Paperpile::Library::Publication;

use Data::Dumper;

sub grid  {

  my ( $self, $c ) = @_;

  my $start  = $c->params->{start}  || 0;
  my $limit  = $c->params->{limit}  || 0;
  my $filter = $c->params->{filter} || 'all';

  my @data = ();

  my $q = Paperpile::Queue->new();

  $q->update_stats;

  my $jobs;

  if ( $filter eq 'all' ) {

    $jobs = $q->get_jobs();

  } elsif ( $filter eq 'done' ) {

    $jobs = $q->get_jobs('DONE');

  } elsif ( $filter eq 'error' ) {

    $jobs = $q->get_jobs('ERROR');

  }

  foreach my $job ( @{$jobs} ) {
    next if ($job->hidden);

    my $tmp = $job->as_hash;

    $tmp->{size}       = $tmp->{info}->{size};
    $tmp->{downloaded} = $tmp->{info}->{downloaded};

    delete( $tmp->{info} );
    push @data, $tmp;

  }

  my $total_entries = scalar @data;

  my $end = ( $start + $limit - 1 );

  @data = @data[ $start .. ( ( $end > $#data ) ? $#data : $end ) ];

  my %metaData = (
    totalProperty => 'total_entries',
    root          => 'data',
    id            => 'id',
    fields        => [
      'id',              'type',    'status',  'progress', 'error',    'size', 'interrupt',
      'downloaded',     'message', 'citekey', 'title',    'citation', 'authors', 'year',
      'authors_display', 'linkout', 'journal', 'pdf', 'pdf_name', '_pdf_tmp', 'doi', 'guid'
    ]
  );

  $c->stash->{total_entries} = $total_entries;
  $c->stash->{data}          = [@data];
  $c->stash->{metaData}      = {%metaData};

}

sub update  {
  my ( $self, $c ) = @_;

  # Not in use at the moment. We always return the queue.
  #my $get_queue = $c->params->{get_queue};

  my $data = {};

  my $q = Paperpile::Queue->new();
  $q->update_stats;
  $data->{queue} = $q->as_hash;

  my $jobs = {};
  my $pubs = {};

  my @pub_list = ();

  my $status = $data->{queue}->{status};

  # If queue is finished we return all jobs to make sure everything is
  # updated
  if ($status ne 'RUNNING' && $status ne 'PAUSED') {

    my $all = $q->get_jobs();

    foreach my $job (@$all){
      if (defined $job->pub) {
        my $pub = $job->pub;
        push @pub_list, $pub;
        $jobs->{$job->id} = $job->as_hash;
      }
    }
  } else {

    #my $ids = $c->params->{ids} || [];

    my @ids = $c->params->get_all('ids');

    #if ( ref($ids) ne 'ARRAY' ) {
    #  $ids = [$ids];
    #}

    foreach my $id ( @ids ) {
      my $job = Paperpile::Job->new( { id => $id } );
      if (defined $job->pub) {
        my $pub = $job->pub;
        push @pub_list, $pub;
        $jobs->{$id} = $job->as_hash;
      }
    }
  }

  $pubs = $self->_collect_pub_data( \@pub_list, [ 'guid','pdf', 'pdf_name', '_search_job', '_metadata_job' ] );
  $data->{jobs} = $jobs;
  $data->{pubs} = $pubs;

  $c->stash->{data} = $data;
}

sub cancel_all_jobs  {

  my ( $self, $c ) = @_;

  my $q = Paperpile::Queue->new();
  $q->cancel_all;

}


## Cancel one or more jobs

sub cancel_jobs  {

  my ( $self, $c ) = @_;

  my $ids = $c->params->{ids};

  if ( ref($ids) ne 'ARRAY' ) {
    $ids = [$ids];
  }

  my @pub_list = ();
  foreach my $id (@$ids) {
    my $job = Paperpile::Job->new( { id => $id } );
    my $pub = $job->pub;
    push @pub_list, $pub;
    $job->cancel;
  }

  my $q = Paperpile::Queue->new();
  $q->run;

  my $pubs = $self->_collect_pub_data( \@pub_list, [ 'pdf', 'pdf_name', '_pdf_tmp', '_search_job','_metadata_job' ] );
  my $data = {};
  $data->{pubs}      = $pubs;
  $data->{job_delta} = 1;
  $c->stash->{data}  = $data;
}

# Removes finished (successful OR failed) jobs from the queue.

sub clear_jobs  {

  my ( $self, $c ) = @_;
  my $q     = Paperpile::Queue->new();
  my $guids = $q->clear;

  my $pubs;
  foreach my $guid (@$guids) {
    $pubs->{$guid} = { _search_job => undef, _metadata_job => undef };
  }
  $c->stash->{data}->{pubs}      = $pubs;
  $c->stash->{data}->{job_delta} = 1;
}

sub remove_jobs  {

  my ( $self, $c ) = @_;

  my $ids = $c->params->{ids};

  if ( ref($ids) ne 'ARRAY' ) {
    $ids = [$ids];
  }

  my @pub_list = ();
  foreach my $id (@$ids) {
    my $job = Paperpile::Job->new( { id => $id } );
    my $pub = $job->pub;
    $pub->_search_job(undef);
    $pub->_metadata_job(undef);
    push @pub_list, $pub;
    $job->interrupt('CANCEL');
    $job->remove;
  }

  my $pubs = $self->_collect_pub_data( \@pub_list, ['_search_job','_metadata_job'] );

  my $q = Paperpile::Queue->new();
  $q->update_stats;

  my $data;
  $data->{pubs}  = $pubs;
  $data->{queue} = $q->as_hash;

  $c->stash->{data} = $data;
  $c->stash->{data}->{job_delta} = 1;
}

sub retry_jobs  {

  my ( $self, $c ) = @_;

  my $ids = $c->params->{ids};

  if ( ref($ids) ne 'ARRAY' ) {
    $ids = [$ids];
  }

  my $q   = Paperpile::Queue->new();
  my $dbh = Paperpile::Utils->get_model("Queue")->dbh;

  my @pub_list = ();
  foreach my $id (@$ids) {
    my $job = Paperpile::Job->new( { id => $id } );

    $job->reset();

    my $idq = $dbh->quote( $job->id );
    ( my $rowid ) = $dbh->selectrow_array("SELECT rowid FROM queue WHERE jobid=$idq");

    $job->_rowid($rowid);

    #$dbh->do("DELETE FROM Queue WHERE jobid=$id;");

    $q->submit($job);

    my $pub = $job->pub;
    push @pub_list, $pub;
  }

  $q->run();

  my $pubs = $self->_collect_pub_data( \@pub_list, [ '_job_id', '_search_job','_metadata_job' ] );
  my $data = {};
  $data->{queue} = $q->as_hash;
  $data->{pubs} = $pubs;
  $data->{job_delta} = 1;
  $c->stash->{data} = $data;
}

sub clear  {

  my ( $self, $c ) = @_;

  my $q = Paperpile::Queue->new();
  $q->clear;

  $c->stash->{data}->queue       = $q->as_hash;
  $c->stash->{data}->{job_delta} = 1;
}

## Pauses the queue

sub pause_resume  {
  my ( $self, $c ) = @_;

  my $q = Paperpile::Queue->new();

  if ( $q->status eq 'PAUSED' ) {
    $q->resume;
  } else {
    $q->pause;
  }

  $c->stash->{data}->{queue}     = $q->as_hash;
  $c->stash->{data}->{job_delta} = 1;
}

# Duplicated from controller/ajax/crud.pm . Should combine somewhere.
sub _collect_pub_data {
  my ( $self, $pubs, $fields ) = @_;

  my %output = ();
  foreach my $pub (@$pubs) {
    my $hash       = $pub->as_hash;

    next if !defined $hash->{guid};

    my $pub_fields = {};
    if ($fields) {
      map { $pub_fields->{$_} = $hash->{$_} } @$fields;
    } else {
      $pub_fields = $hash;
    }
    $output{ $hash->{guid} } = $pub_fields;
  }

  return \%output;
}

1;
