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
use WWW::Recorder;
use WWW::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $exec = basename($0);
if ( @ARGV < 3 ) { die("usage: ${exec} <area> <channel> <yyyy-mm-dd>\n"); }
my ( $areaName, $channel, $date ) = @ARGV;
my $name     = 'radiru';
my $provider = WWW::Recorder::Provider->new($name)            or die("Failed to get ${name}");
my $area = $provider->ConfigWeb()->Areas()->ByName($areaName) or die("Invalid area: ${areaName}");
my $service = $provider->Services()->ByChannel($channel)      or die("Invalid channel: ${channel}");
my $prog    = $provider->getProgramDay( $area, $service, $date ) or die("No Program\n");
my $conf    = loadConfig();
DumpFile( "$conf->{LogDir}/${name}_${areaName}_${channel}_${date}.yml", $prog );
