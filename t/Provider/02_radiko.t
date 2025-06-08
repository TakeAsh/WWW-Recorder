#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use YAML::Syck qw(LoadFile DumpFile Dump);
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;

subtest 'radiko' => sub {
    my $station   = 'JOAK-FM';
    my $radiko    = new_ok( 'WWW::Recorder::Provider::radiko', undef, '$radiko' );
    my $authToken = $radiko->getAuthToken();
    diag( Dump($authToken) );
    isnt( $authToken, undef, 'getAuthToken' ) or diag( $radiko->flush() );
    my $streamUris = $radiko->getStreamUris($station);
    isa_ok( $streamUris, 'ARRAY', 'getStreamUris' ) or diag( $radiko->flush() );
    my $streamUri = $radiko->getStreamUri($station);
    isnt( $streamUri, undef, 'getStreamUri' ) or diag( Dump($streamUris) );
    my $playlistUri = $radiko->makePlaylistUri( $station, $authToken, $streamUri );
    isnt( $playlistUri, undef, 'makePlaylistUri' );
    my $res = $radiko->request(
        GET => $playlistUri->{'Uri'},
        undef,
        $playlistUri->{'Headers'},
        $playlistUri->{'Query'},
    )->call();
    ok( $res->is_success && ( $res->decoded_content =~ /^#EXTM3U\n/ ), 'callPlaylistUri' )
        or diag(
        Dump(
            {   Request  => $playlistUri,
                Response => {
                    Status  => $res->status_line,
                    Headers => $res->headers,
                    Content => $res->decoded_content,
                }
            }
        )
        );
};

done_testing();
