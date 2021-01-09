#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use File::Basename;
use List::Util qw(first);
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder;
use Net::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $exec = basename($0);
if ( @ARGV < 1 ) { die("usage: ${exec} <yyyy-mm-dd> [<area>]\n"); }
my $name     = 'radiko';
my $provider = Net::Recorder::Provider->new($name) or die("Failed to get ${name}");
my $date     = shift;
my $area     = shift || $provider->area();
my $date2    = $date;
$date2 =~ s/-//g;
my $prog = $provider->getInfos(
    api  => 'ProgramsByArea',
    date => $date2,
    area => $area,
) or die("No Program\n");
my $conf = loadConfig();
DumpFile( "$conf->{LogDir}/${name}_${area}_${date}.yml", $prog );
