#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;

subtest 'Areas' => sub {
    my $areas = new_ok(
        'WWW::Recorder::Provider::radiru::Areas',
        [   [   {   apikey  => '700',
                    area    => 'sapporo',
                    areakey => '010',
                    fmhls   => 'https://example.net/path/fm.m3u8',
                    r1hls   => 'https://example.net/path/r1.m3u8',
                    r2hls   => 'https://example.net/path/r2.m3u8',
                },
                {   apikey  => '001',
                    area    => 'tokyo',
                    areakey => '130',
                    fmhls   => 'https://example.net/path/fm.m3u8',
                    r1hls   => 'https://example.net/path/r1.m3u8',
                    r2hls   => 'https://example.net/path/r2.m3u8',
                },
                {   apikey  => '300',
                    area    => 'nagoya',
                    areakey => '230',
                    fmhls   => 'https://example.net/path/fm.m3u8',
                    r1hls   => 'https://example.net/path/r1.m3u8',
                    r2hls   => 'https://example.net/path/r2.m3u8',
                },
                {   apikey  => '200',
                    area    => 'osaka',
                    areakey => '270',
                    fmhls   => 'https://example.net/path/fm.m3u8',
                    r1hls   => 'https://example.net/path/r1.m3u8',
                    r2hls   => 'https://example.net/path/r2.m3u8',
                },
                {   apikey  => '501',
                    area    => 'fukuoka',
                    areakey => '400',
                    fmhls   => 'https://example.net/path/fm.m3u8',
                    r1hls   => 'https://example.net/path/r1.m3u8',
                    r2hls   => 'https://example.net/path/r2.m3u8',
                },
            ],
        ],
        '$areas'
    );
    my @testcases_ByAreaKey = (
        { input => '010', expected => 'sapporo', },
        { input => '130', expected => 'tokyo', },
        { input => '270', expected => 'osaka', },
        { input => '230', expected => 'nagoya', },
        { input => '400', expected => 'fukuoka', },
    );
    foreach my $testcase_ByAreaKey (@testcases_ByAreaKey) {
        is( $areas->ByAreaKey( $testcase_ByAreaKey->{'input'} )->{'area'},
            $testcase_ByAreaKey->{'expected'},
            'ByAreaKey:' . $testcase_ByAreaKey->{'input'}
        );
    }
    my @testcases_ByName = (
        { input => 'tokyo',   expected => 'tokyo', },
        { input => 'osaka',   expected => 'osaka', },
        { input => 'nagoya',  expected => 'nagoya', },
        { input => 'fukuoka', expected => 'fukuoka', },
        { input => 'sapporo', expected => 'sapporo', },
    );
    foreach my $testcase_ByName (@testcases_ByName) {
        is( $areas->ByName( $testcase_ByName->{'input'} )->{'area'},
            $testcase_ByName->{'expected'},
            'ByName:' . $testcase_ByName->{'input'}
        );
    }
    is_deeply(
        [ map { $_->{'area'} } $areas->getListByApiKey() ],
        [qw(tokyo osaka nagoya fukuoka sapporo)],
        'getListByApiKey'
    );
};

subtest 'Services' => sub {
    my $services = new_ok( 'WWW::Recorder::Provider::radiru::Services', undef, '$services' );
    my @testcases_ByService = (
        { input => 'r1', expected => 'r1', },
        { input => 'r2', expected => 'r2', },
        { input => 'r3', expected => 'r3', },
    );
    foreach my $testcase_ByService (@testcases_ByService) {
        my $service = $services->ByService( $testcase_ByService->{'input'} );
        isnt( $service, undef, '$service' );
        is( $service->{'Service'},
            $testcase_ByService->{'expected'},
            'ByService:' . $testcase_ByService->{'input'}
        );
    }
    my @testcases_ByChannel = (
        { input => 'r1', expected => 'r1', },
        { input => 'r2', expected => 'r2', },
        { input => 'fm', expected => 'r3', },
    );
    foreach my $testcase_ByChannel (@testcases_ByChannel) {
        my $service = $services->ByChannel( $testcase_ByChannel->{'input'} );
        isnt( $service, undef, '$service' );
        is( $service->{'Service'},
            $testcase_ByChannel->{'expected'},
            'ByChannel:' . $testcase_ByChannel->{'input'}
        );
    }
    is_deeply( [ map { $_->{'Service'} } $services->getList() ], [qw(r1 r2 r3)], 'getList' );
};

subtest 'ConfigWeb' => sub {
    my $configWeb = new_ok( 'WWW::Recorder::Provider::radiru::ConfigWeb', undef, '$configWeb' );
    isa_ok( $configWeb->Areas(), 'WWW::Recorder::Provider::radiru::Areas', 'Areas()' );
    is( $configWeb->UrlProgramDay(),
        'https://api.nhk.jp/r7/pg/date/{service}/{area}/{date}.json',
        'UrlProgramDay()'
    );
    is( $configWeb->UrlProgramDetail(),
        'https://api.nhk.jp/r7/t/broadcastevent/be/{broadcastEventId}.json',
        'UrlProgramDetail()'
    );
};

subtest 'radiru' => sub {
    my $radiru = new_ok( 'WWW::Recorder::Provider::radiru', undef, '$radiru' );
    can_ok( $radiru, qw(new getPrograms getProgramsFromUri record) );
    isa_ok( $radiru->ConfigWeb(), 'WWW::Recorder::Provider::radiru::ConfigWeb', 'ConfigWeb()' );
    isa_ok( $radiru->Services(),  'WWW::Recorder::Provider::radiru::Services',  'Services()' );
};

done_testing();
