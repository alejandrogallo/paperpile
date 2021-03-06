# This file was created by configpm when Perl was built. Any changes
# made to this file will be lost the next time perl is built.

package Config;
use strict;
# use warnings; Pulls in Carp
# use vars pulls in Carp
@Config::EXPORT = qw(%Config);
@Config::EXPORT_OK = qw(myconfig config_sh config_vars config_re);

# Need to stub all the functions to make code such as print Config::config_sh
# keep working

sub myconfig;
sub config_sh;
sub config_vars;
sub config_re;

my %Export_Cache = map {($_ => 1)} (@Config::EXPORT, @Config::EXPORT_OK);

our %Config;

# Define our own import method to avoid pulling in the full Exporter:
sub import {
    my $pkg = shift;
    @_ = @Config::EXPORT unless @_;

    my @funcs = grep $_ ne '%Config', @_;
    my $export_Config = @funcs < @_ ? 1 : 0;

    no strict 'refs';
    my $callpkg = caller(0);
    foreach my $func (@funcs) {
	die sprintf qq{"%s" is not exported by the %s module\n},
	    $func, __PACKAGE__ unless $Export_Cache{$func};
	*{$callpkg.'::'.$func} = \&{$func};
    }

    *{"$callpkg\::Config"} = \%Config if $export_Config;
    return;
}

die "Perl lib version (5.10.0) doesn't match executable version ($])"
    unless $^V;

$^V eq 5.10.0
    or die "Perl lib version (5.10.0) doesn't match executable version (" .
	sprintf("v%vd",$^V) . ")";


sub relocate_inc {
  my $libdir = shift;
  return $libdir unless $libdir =~ s!^\.\.\./!!;
  my $prefix = $^X;
  if ($prefix =~ s!/[^/]*$!!) {
    while ($libdir =~ m!^\.\./!) {
      # Loop while $libdir starts "../" and $prefix still has a trailing
      # directory
      last unless $prefix =~ s!/([^/]+)$!!;
      # but bail out if the directory we picked off the end of $prefix is .
      # or ..
      if ($1 eq '.' or $1 eq '..') {
	# Undo! This should be rare, hence code it this way rather than a
	# check each time before the s!!! above.
	$prefix = "$prefix/$1";
	last;
      }
      # Remove that leading ../ and loop again
      substr ($libdir, 0, 3, '');
    }
    $libdir = "$prefix/$libdir";
  }
  $libdir;
}

sub FETCH {
    my($self, $key) = @_;

    # check for cached value (which may be undef so we use exists not defined)
    return $self->{$key} if exists $self->{$key};

    return $self->fetch_string($key);
}
sub TIEHASH {
    bless $_[1], $_[0];
}

sub DESTROY { }

sub AUTOLOAD {
    require 'Config_heavy.pl';
    goto \&launcher unless $Config::AUTOLOAD =~ /launcher$/;
    die "&Config::AUTOLOAD failed on $Config::AUTOLOAD";
}

# tie returns the object, so the value returned to require will be true.
tie %Config, 'Config', {
    archlibexp => relocate_inc('.../../base'),
    archname => 'linux32',
    cc => 'cc',
    d_readlink => 'define',
    d_symlink => 'define',
    dlsrc => 'dl_dlopen.xs',
    dont_use_nlink => undef,
    exe_ext => '',
    inc_version_list => ' ',
    intsize => '4',
    ldlibpthname => 'LD_LIBRARY_PATH',
    libpth => '/usr/local/lib /lib /usr/lib /lib64 /usr/lib64',
    osname => 'linux',
    osvers => '2.6.28-11-generic',
    path_sep => ':',
    privlibexp => relocate_inc('.../../base'),
    scriptdir => '/usr/local/bin',
    sitearchexp => relocate_inc('.../../cpan'),
    sitelibexp => relocate_inc('.../../cpan'),
    useithreads => undef,
    usevendorprefix => undef,
    version => '5.10.0',
};
