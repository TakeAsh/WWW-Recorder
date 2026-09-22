#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump DumpFile);
use IPC::Cmd   qw(can_run run);
use Cwd        qw(getcwd);
use File::Basename;
use File::Path    qw(rmtree);
use File::Slurper qw(write_text);
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;
use WWW::Recorder::Util;
use open ':std' => ':utf8';

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $ffmpeg = can_run('ffmpeg') or die("ffmpeg is not found");

@ARGV = map { decodeUtf8($_) } @ARGV;
my $exec = basename($0);
if ( @ARGV < 2 ) { die("usage: ${exec} <filename> <dir>\n"); }
my $fname = shift(@ARGV);
my $dir   = join( '/', getcwd(), shift(@ARGV) );
if ( !( -d $dir ) ) { die("Not exist '${dir}': $!\n"); }
my @parts = sort( grep { $_ !~ /\/files\.txt$/ } glob("${dir}/*") );
if ( !@parts ) { die("No file in ${dir}\n"); }
my $list      = join( "\n", map {"file $_"} @parts ) . "\n";
my $fnameList = "${dir}/files.txt";
write_text( $fnameList, $list );
my $cmd = sprintf( '%s -y -f concat -safe 0 -i %s -c copy -movflags faststart %s',
    $ffmpeg, sysQuote($fnameList), sysQuote($fname) );
my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
    = run( command => $cmd, verbose => 0, timeout => 120 * 60 );
my $messages = integrateErrorMessages( $error_message, $stdout_buf, $stderr_buf );
say $messages->{'All'};

if ( $success && -f $fname ) {
    rmtree($dir);
}
