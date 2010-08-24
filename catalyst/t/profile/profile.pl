<<<<<<< HEAD
#!/home/wash/play/paperpile/catalyst/perl5/linux64/bin/paperperl -w
=======
#!/Users/wash/play/paperpile/catalyst/perl5/osx/bin/perl -w
>>>>>>> osx

##!/home/wash/play/paperpile/catalyst/perl5/linux64/bin/paperperl -d:NYTProf -w

BEGIN {
  $ENV{CATALYST_DEBUG} = 0;
}

use strict;
use Data::Dumper;
use lib '../../lib';

use Paperpile;
use Paperpile::Plugins::Import;
use Paperpile::Plugins::Import::Duplicates;
use Text::LevenshteinXS qw(distance);

my $plugin = Paperpile::Plugins::Import::Duplicates->new(file=>'/home/wash/.paperdev/paperpile.ppl');

$plugin->connect();

#my $distance = distance('CONSERVEDRNASECONDARYSTRUCTURESINPICORNAVIRIDAEGENOMES','CONSERVEDRNASECONDARYSTRUCTURESINFLAVIVIRIDAEGENOMES');
#print "$distance\n";
