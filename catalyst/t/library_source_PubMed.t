use strict;
use warnings;
use Data::Dumper;
use Test::More 'no_plan';
use lib "../lib";


BEGIN { use_ok 'PaperPile::Library::Source::PubMed' }

my $source=PaperPile::Library::Source::PubMed->new(query=>'Stadler PF');

$source->connect;

my $pubs=$source->page_from_offset(0,10);


print Dumper($pubs);




