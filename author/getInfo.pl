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
if ( @ARGV < 1 ) { die("usage: ${exec} <provider> <uri> [<uri>...]\n"); }
my $name     = shift;
my $provider = WWW::Recorder::Provider->new($name) or die("Failed to get ${name}");
my $conf     = loadConfig();
my $dir      = "$conf->{LogDir}/${name}";
if ( !( -d $dir ) ) {
    mkdir($dir) or die("Failed to make directory '${name}': $!");
}
foreach my $uri (@ARGV) {
    my $match     = $provider->isSupported($uri) or next;
    my $fnameBase = "${dir}/" . $provider->makeFilenameRawBase($match);
    if ( $provider->can('getProgramInfoRaw')
        && ( my $infoRaw = $provider->getProgramInfoRaw( $uri, $match ) ) )
    {
        DumpFile( "${fnameBase}_Info_raw.yml", $infoRaw );
    }
    if ( $provider->can('getProgramInfo') ) {
        if ( my $info = $provider->getProgramInfo( $uri, $match ) ) {
            DumpFile( "${fnameBase}_Info.yml", $info );
        } else {
            warn("No Info: ${uri}\n");
        }
    }
    if ( $provider->can('getDescriptionFromUri') ) {
        if ( my $desc = $provider->getDescriptionFromUri( $uri, $match ) ) {
            DumpFile( "${fnameBase}_Desc.yml", $desc );
        } else {
            warn("No Description: ${uri}\n");
        }
    }
}
