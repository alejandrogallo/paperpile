# Copyright 2009, 2010 Paperpile
#
# This file is part of Paperpile
#
# Paperpile is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# Paperpile is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.  You should have received a
# copy of the GNU General Public License along with Paperpile.  If
# not, see http://www.gnu.org/licenses.

package Paperpile::Controller::Ajax::WebImport;

use strict;
use warnings;
use Paperpile::Utils;
use Paperpile::MetaCrawler;
use Encode;

use parent 'Catalyst::Controller';

# Imports one or more
sub import_refs : Local {
  my ( $self, $c ) = @_;

  $c->component('View::JSON')->allow_callback(1);

  my @link_ids = $self->_as_array( $c->request->params->{link_ids} );
  my $page_url = $c->request->params->{page_url};

  # We use the page's URL as the key for the session-based cache of our link objects.
  my $key   = $self->_url_to_key($page_url);
  my $cache = $c->session->{import_cache}->{$key};
  print STDERR "Cache size: " . scalar( keys %$cache ) . "\n";

  # Create a MetaCrawler.
  my $model   = Paperpile::Utils->get_library_model();
  my $crawler = new Paperpile::MetaCrawler();
  $crawler->driver_file( Paperpile::Utils->path_to( 'data', 'meta-crawler.xml' )->stringify );
  $crawler->load_driver();

  my @results;

  for ( my $i = 0 ; $i < scalar(@link_ids) ; $i++ ) {
    my $link_id = $link_ids[$i];
    my $link    = $cache->{$link_id};

    # This call does all the work.
    my $result = $self->_import_single_pub( $crawler, $link );
    push @results, $result;
  }
  $c->stash->{results} = \@results;
  $c->forward('View::JSON');
}

# Convert a single or array parameter into an array.
sub _as_array {
  my $self = shift;
  my $obj  = shift;

  my @arr;
  if ( ref $obj eq 'ARRAY' ) {
    @arr = @$obj;
  } else {
    @arr = ($obj);
  }
  return @arr;
}

# Strips a URL of all the crap in order to have a very safe hash key.
sub _url_to_key {
  my $self = shift;
  my $url  = shift;

  my $key = $url;
  $key =~ s/[^a-z0-9]/x/g;
  return $key;
}

# Take the URL and content of a given page and return a list of
sub submit_page : Local {

  my ( $self, $c ) = @_;

  $c->component('View::JSON')->allow_callback(1);

  my $url = $c->request->params->{url};

  $c->session->{import_cache} = {};    # if ( !defined $c->session->{import_cache} );

  my $key = $self->_url_to_key($url);
  $c->session->{import_cache}->{$key} = {};

  my $browser  = Paperpile::Utils->get_browser;
  my $response = $browser->get($url);

  if ( $response->is_error ) {
    NetGetError->throw(
      error => 'Network error while scanning page for links: ' . $response->message,
      code  => $response->code
    );
  }

  # This method stores the page_type and list_type values in the stash.
  $self->_detect_page_type( $c, $response );

  my $page_type = $c->stash->{page_type};

  if ( $page_type eq 'list' ) {
    $self->_get_links_from_page( $c, $response, $key );
  } elsif ( $page_type eq 'single' ) {
    $self->_import_single_page( $c, $response );
  } elsif ( $page_type eq 'hybrid' ) {

    # This might occur if we're looking at the HTML page of a journal article.
    # We want to import the current article, but might also be able to collect
    # link_objs for the 'cited works' or 'cited by' articles at the bottom.
    #
    # TODO: provide a nice front-end for dealing with this case. Maybe a status
    # message like "Reference successfully imported, and 12 additional
    # items found. (Import all, Clear)"
    $self->_get_links_from_page( $c, $response, $key );
    $self->_import_single_page( $c, $response );
  }

  $c->forward('View::JSON');
}

# Once we know it's a list page, we need to know which supported
# site it's coming from.
sub _classify_list_page {
  my $self     = shift;
  my $url      = shift;
  my $response = shift;

  if ( $url =~ m^scholar.google^gi ) {
    return 'google_scholar';
  } elsif ( $url =~ m^ncbi.nlm.nih.gov.*pubmed^gi ) {
    return 'pubmed_list';
  } elsif ( $url =~ m^citeulike.org^gi ) {
    return 'citeulike_list';
  } elsif ( $url =~ m^arxiv.org^gi ) {
    return 'arxiv_list';
  }

  return 'unknown';
}

# Extracts all the links from a list page.
sub _get_links_from_page {
  my ( $self, $c, $response, $cache_key ) = @_;

  my @entries = ();
  $c->session->{import_cache}->{$cache_key} = {};

  my $url = $response->request->url;
  my $list_type = $self->_classify_list_page( $url, $response );

  if ( $list_type eq 'google_scholar' ) {
    my $gs   = Paperpile::Plugins::Import::GoogleScholar->new();
    my $page = $gs->_parse_googlescholar_page( $response->content );

    foreach my $pub (@$page) {
      my $link = {
        selector   => $pub->_web_import_selector,
        import_url => $pub->linkout,
        pub        => $pub->as_hash
      };
      push @entries, $link;
    }
  } elsif ( $list_type eq 'pubmed_list' ) {

    # Remember: we can't get URLs from PubMed search result pages,
    # so we sent along the whole page's contents via the pubmed_content
    # POST variable.
    my $pubmed_content = $c->request->params->{pubmed_content};
    if ( $pubmed_content ne '' ) {
      @entries = $self->_parse_pubmed_page($pubmed_content);
    } else {
      @entries = $self->_parse_pubmed_page( $response->content );
    }
  } elsif ( $list_type eq 'citeulike_list' ) {
    @entries = $self->_parse_citeulike_page( $response->content );
  } elsif ( $list_type eq 'arxiv_list' ) {
    @entries = $self->_parse_arxiv_page( $response->content );
  }

  # Create link_ids for each entry and store each entry hash in the session cache.
  my $link_id = 0;
  foreach my $entry (@entries) {
    $entry->{link_id} = $link_id;
    $c->session->{import_cache}->{$cache_key}->{$link_id} = $entry;
    $link_id++;
  }
  $c->stash->{entries} = \@entries;
}

# Pretty standard style for this parsing. CiteULike and GScholar are very similar,
# and it's *very* quick to cut-copy and implement a new page type when needed.
sub _parse_arxiv_page {
  my $self         = shift;
  my $page_content = shift;

  my $tree = HTML::TreeBuilder::XPath->new;
  $tree->utf8_mode(0);
  $page_content = decode_utf8($page_content);
  $tree->parse_content($page_content);

  my @objs;
  my @nodes = $tree->findnodes('//div[@id="dlpage"]/dl/dt');

  my $i = 1;
  foreach my $node (@nodes) {
    my $arxiv_link = $node->findvalue('./span/a[@title="Abstract"]');
    my $title      = $node->findvalue('../dd//div[@class="list-title"]');
    my $authors    = $node->findvalue('../dd//div[@class="list-authors"]');

    my $arxivid = $arxiv_link;
    $arxivid =~ s/arxiv://gi;

    my $pub = new Paperpile::Library::Publication();
    $pub->title($title);
    $pub->authors($authors);
    $pub->arxivid($arxivid);

    my $obj = {
      selector   => '#dlpage span.list-identifier:nth(' . $i++ . ')',
      import_url => 'http://arxiv.org' . $arxiv_link,
      pub        => $pub->as_hash,
    };
    push @objs, $obj;
  }
  return @objs;
}

# Note that there's also a new CiteULike entry in the MetaCrawler XML definition,
# which gives us very quick access to the Ris file given a CiteULike article URL.
sub _parse_citeulike_page {
  my $self         = shift;
  my $page_content = shift;

  my $tree = HTML::TreeBuilder::XPath->new;
  $tree->utf8_mode(0);
  $page_content = decode_utf8($page_content);
  $tree->parse_content($page_content);

  print STDERR "-> Finished parsing!\n";
  my @objs;
  my @nodes = $tree->findnodes('//a[@class="title"]');

  my $i = 1;
  foreach my $node (@nodes) {

    #print STDERR "->NODE!\n";
    my $cul_link = $node->findvalue('@href');
    $cul_link = 'http://www.citeulike.org' . $cul_link;
    my $cul_title = $node->findvalue('.');

    my $pub = new Paperpile::Library::Publication();
    $pub->title($cul_title);

    my $obj = {
      selector   => 'a.title:nth(' . $i++ . ')',
      import_url => $cul_link,
      pub        => $pub->as_hash,
    };
    push @objs, $obj;
  }
  return @objs;
}

sub _parse_pubmed_page {
  my $self         = shift;
  my $page_content = shift;

  my $tree = HTML::TreeBuilder::XPath->new;
  $tree->utf8_mode(0);
  $page_content = decode_utf8($page_content);
  $tree->parse_content($page_content);

  my @objs;
  my @nodes = $tree->findnodes('//div[@class="rslt"]');
  my $i     = 1;
  foreach my $node (@nodes) {
    my $pm_link  = $node->findvalue('./p[@class="title"]/a/@href');
    my $pm_title = $node->findvalue('./p[@class="title"/a');
    $pm_link =~ m^/pubmed/(.*)^;
    my $pm_id = $1;

    my $pub = new Paperpile::Library::Publication();
    $pub->title($pm_title);
    $pub->pmid($pm_id);

    my $obj = {
      selector   => '.rslt:nth(' . $i++ . ') p a',
      import_url => $pm_link,
      pub        => $pub->as_hash,
    };
    push @objs, $obj;
  }
  return @objs;
}

sub _import_single_pub {
  my $self      = shift;
  my $crawler   = shift;
  my $link_data = shift;

  my $result;
  my $pub;

  # Try searching by the given import_url.
  print STDERR "  -> Trying to use MetaCrawler...\n";
  my $url = $link_data->{import_url};
  $pub = eval { $crawler->search_file($url) };

  # There might be a publication object associated with this link data,
  # collected by the page-scraping mechanism. If the MetaCrawler doesn't
  # work but we have this pub data, try using the Metadata update script
  # to match an online plugin using the title, etc.
  if ( !defined $pub && defined $link_data->{pub} ) {
    print STDERR "  -> Trying to use Metadata update...\n";

    # If that fails, try matching the input pub using our online resources.
    my $link_pub = $link_data->{pub};
    my $j        = Paperpile::Job->new(
      type => 'METADATA_UPDATE',
      pub  => new Paperpile::Library::Publication($link_pub),
    );
    my $success = $j->_match;
    if ($success) {
      $pub = $j->pub;
    }
  }

  my $e;
  if ( !defined $pub && ( $e = Exception::Class->caught ) ) {

    # Provide the UI with some info on the caught exception.
    $result = {
      status => 'failure',
      error  => $e->error
    };
  } elsif ( !defined $pub ) {

    # No exception, it just didn't find anything.
    $result = {
      status => 'failure',
      error  => 'Unable to find metadata for this reference.'
    };
  } else {

    # Success!
    $pub->_light(0);         # Make sure it's not a 'light' object.
    $pub->refresh_fields;    # Refresh the citation field.

    my $model = Paperpile::Utils->get_library_model();
    $model->exists_pub( [$pub] )
      ; # Trigger the library to search for an existing version of the same. This result gets stored in the $pub->_imported field.

    if ( $pub->_imported ) {
      $result = {
        pub    => $pub->as_hash,
        status => 'exists'
      };
    } else {
      $model->insert_pubs( [$pub], 1 );    # Insert into the library.
      $result = {
        pub    => $pub->as_hash,
        status => 'success',
      };
    }
  }

  $result->{link_id} = $link_data->{link_id};
  return $result;
}

sub _import_single_page {
  my ( $self, $c, $response ) = @_;

  my $url = $response->request->url;

  my $link_data = { import_url => $url };

  my $crawler = new Paperpile::MetaCrawler();
  $crawler->driver_file( Paperpile::Utils->path_to( 'data', 'meta-crawler.xml' )->stringify );
  $crawler->load_driver();

  my $result = $self->_import_single_pub( $crawler, $link_data );
  $c->stash->{result} = $result;
}

# Detects the page 'type' given its HTML content.
# We need to distinguish between 'single' pages, where the current page
# is a single reference, and 'list' pages, where the current page
# is listing links to a variety of references.
sub _detect_page_type {
  my ( $self, $c, $response ) = @_;

  my $url = $response->request->uri;

  my $list   = 'list';
  my $single = 'single';

  my $page_type = 'single';

  # Delegate to the list classification method. Returns 'unknown' when not
  # recognized as one of the list types.
  my $list_type = $self->_classify_list_page( $url, $response );
  if ( $list_type ne 'unknown' ) {
    $page_type = $list;
  }

  $c->stash->{page_type} = $page_type;
  $c->stash->{list_type} = $list_type;

  return $page_type;
}

1;
