#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use File::Basename;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;
use WWW::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

@ARGV = map { decodeUtf8($_) } @ARGV;

my $exec = basename($0);
if ( @ARGV < 1 ) { die("usage: ${exec} <subtitle>\n"); }
my ($subtitle) = @ARGV;
say join( "\n", $subtitle, normalizeSubtitle($subtitle) );
