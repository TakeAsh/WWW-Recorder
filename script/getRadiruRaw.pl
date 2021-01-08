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
use Net::Recorder::Provider;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $exec = basename($0);
if ( @ARGV < 3 ) { die("usage: ${exec} <area> <channel> <yyyy-mm-dd>\n"); }
my ( $areaName, $channel, $date ) = @ARGV;
my $radiru  = Net::Recorder::Provider->new('radiru')           or die("Failed to get radiru");
my $area    = $radiru->ConfigWeb()->Areas()->ByName($areaName) or die("Invalid area: ${areaName}");
my $service = $radiru->Services()->ByChannel($channel) or die("Invalid channel: ${channel}");
my $prog    = $radiru->getProgramDay( $area, $service, $date );
DumpFile( "${FindBin::RealBin}/../log/radiru_${areaName}_${channel}_$date.yml", $prog );
