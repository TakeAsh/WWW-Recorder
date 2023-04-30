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
use WWW::Recorder::TimePiece;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

@ARGV = map { decodeUtf8($_) } @ARGV;

my $exec = basename($0);
if ( @ARGV < 1 ) { die("usage: ${exec} <channelName> [<channelName>...]\n"); }
my $now      = WWW::Recorder::TimePiece->new();
my $date     = $now->strftime('%Y-%m-%d');
my $conf     = loadConfig();
my $name     = 'ListenRadio';
my $provider = WWW::Recorder::Provider->new($name) or die("Failed to get ${name}");
my $channels = $provider->Channels()               or die("Failed to get Channels");
DumpFile( "$conf->{LogDir}/${name}/Channels_${date}.yml", $channels );
my $matched = $channels->byNames(@ARGV) or die("Failed to get Channel");

foreach my $channel ( @{$matched} ) {
    my $channelId = $channel->{'ChannelId'}                or die("Failed to get ChannelId");
    my $schedule  = $provider->Api()->Schedule($channelId) or die("Failed to get Schedule");
    DumpFile( "$conf->{LogDir}/${name}/Schedule_$channel->{ChannelName}_${date}.yml", $schedule );
}
