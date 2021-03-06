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


package Paperpile;

use strict;
use warnings;

use Mouse;

use File::Spec;
use File::HomeDir;
use Cwd qw(abs_path);

use YAML::XS qw(LoadFile DumpFile);

has '_config' => ( is => 'rw' );


# Finds application home directory based on location of Paperpile.pm
sub home_dir {

  my ($self) = @_;

  # Find home directory via location of Paperpile.pm file
  foreach my $i ( 0 .. $#INC ) {
    my $dir = $INC[$i];
    if ( -e File::Spec->catfile( $dir, "Paperpile.pm" ) ) {
      $dir =~ s!(/|\\)lib(/|\\)?$!!;
      return abs_path($dir);
    }
  }
}

# Creates path relative to application home directory. Takes a list of
# components of a path, e.g. path_to('conf','settings.yaml')
sub path_to {

  my $self = shift;

  return File::Spec->catfile( $self->home_dir, @_ );

}

# Gets temporary directory depending on platform
sub tmp_dir {

  my ($self) = @_;

  my $platform = $self->platform;

  if ( $self->platform eq 'win32' ) {
    return ( File::Spec->catfile( File::HomeDir->my_data, "Temp", "paperpile" ) );

  } else {
    my $tmp = $ENV{TMPDIR} || '/tmp';
    return ( File::Spec->catfile( $tmp, "paperpile-" . $ENV{USER} ) );
  }
}

sub platform {

  my ($self) = @_;

  if ( $^O =~ /linux/i ) {
    my @f = `file /bin/ls`;    # More robust way for this??
    if ( $f[0] =~ /64-bit/ ) {
      return ('linux64');
    } else {
      return ('linux32');
    }
  }
  if ( $^O =~ /cygwin/i or $^O =~ /MSWin/i ) {
    return ('win32');
  }

  if ( $^O =~ /(darwin|osx)/i ) {
    return ('osx');
  }

}


# Returns hash with settings from configuration file

sub config {

  my ($self) = @_;

  # If instantiated cache config. However, also allow function calls
  # on class without object
  if ( ref $self ) {
    if ( defined $self->_config ) {
      return $self->_config;
    }
  }

  my $config = $self->_raw_config;

  my $substitutions = $self->_substitutions;

  $self->_substitute_config( $config, $substitutions );

  if ( ref $self ) {
    $self->_config($config);
  }

  return $config;
}

# Get configuration data without substitution of special fields
sub _raw_config {

  my ($self) = @_;

  my $file = $self->path_to( "conf", "settings.yaml" );

  return LoadFile($file);
}

# Replace special fields such as __USERHOME__ in configuration
# data. This function works recursively through the whole data
# structure ($item is the current node and should be initialized with
# the hashref from _raw_config). The replacement values of the special
# fields are given by $substitutions

sub _substitute_config {

  my ( $self, $item, $substitutions ) = @_;

  # If hash, call myself for each item again.
  if ( ref($item) eq "HASH" ) {
    foreach my $value ( values %{$item} ) {
      my $new_item = ref($value) ? $value : \$value;
      $self->_substitute_config( $new_item, $substitutions );
    }
  }

  # If array, also call myself for each item again.
  if ( ref($item) eq "ARRAY" ) {
    foreach my $value ( @{$item} ) {
      my $new_item = ref($value) ? $value : \$value;
      $self->_substitute_config( $new_item, $substitutions );
    }
  }

  # If scalar, we substitute the special fields __XXX__
  if ( ref($item) eq "SCALAR" ) {

    my $value = $$item;

    if ( $value =~ /__(.*)__/ ) {

      foreach my $pattern ( keys %$substitutions ) {
        my $replacement = $substitutions->{$pattern};
        $value =~ s/__$pattern\__/$replacement/;
      }
    }
    $$item = $value;
  }
}

# Return run-time values for substititions as hash

sub _substitutions {

  my ($self) = @_;

  my $platform = $self->platform;

  # Set basic locations based on platform
  my $userhome;
  my $pp_user_dir;
  my $pp_paper_dir;

  my $pp_tmp_dir = $self->tmp_dir;

  if ( $platform =~ /linux/ ) {
    $userhome     = $ENV{HOME};
    $pp_user_dir  = $ENV{HOME} . '/.paperpile';
    $pp_paper_dir = $ENV{HOME} . '/.paperpile/papers';
  }

  if ( $platform eq 'osx' ) {
    $userhome     = $ENV{HOME};
    $pp_user_dir  = $ENV{HOME} . '/Library/Application Support/Paperpile';
    $pp_paper_dir = $ENV{HOME} . '/Documents/Paperpile';
  }

  if ( $platform eq 'win32' ) {
    $userhome = File::HomeDir->my_home;
    $pp_user_dir  = File::Spec->catfile(File::HomeDir->my_data,"Paperpile");
    $pp_paper_dir = File::Spec->catfile(File::HomeDir->my_documents,"Paperpile");
  }

  # If we have a development version (i.e. no build number) we use a
  # different user dir to allow parallel usage of a stable Paperpile
  # installation and development
  if ( $self->_raw_config->{app_settings}->{build_number} == 0 ) {
    $pp_user_dir  = $ENV{HOME} . '/.paperdev';
    $pp_paper_dir = $ENV{HOME} . '/.paperdev/papers';
  }

  return {
    'USERHOME'     => $userhome,
    'PLATFORM'     => $platform,
    'PP_USER_DIR'  => $pp_user_dir,
    'PP_PAPER_DIR' => $pp_paper_dir,
    'PP_TMP_DIR'   => $pp_tmp_dir,
  };
}

1;
