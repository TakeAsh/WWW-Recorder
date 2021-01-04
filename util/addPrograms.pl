#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile Dump );
use File::Basename;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $exec = basename($0);
if ( !@ARGV ) { die("usage: ${exec} <program> [<program>...]\n"); }
addPrograms(@ARGV);
