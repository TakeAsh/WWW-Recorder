#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use Time::Piece;
use Time::Seconds;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder::TimePiece;

subtest 'TimePiece/new' => sub {
    my $tp1 = new_ok( 'WWW::Recorder::TimePiece', undef, '$tp1' );
    is( $tp1->stringify(), localtime->strftime('%Y-%m-%d %H:%M:%S'), 'null' );
    my @testcases = (
        {   input    => '00:00',
            expected => '1970-01-01 00:00:00',
        },
        {   input    => '01:02',
            expected => '1970-01-01 00:01:02',
        },
        {   input    => '01:02:03',
            expected => '1970-01-01 01:02:03',
        },
        {   input    => '2021-02-03',
            expected => '2021-02-03 00:00:00',
        },
        {   input    => '2021-02-03 00:00:00',
            expected => '2021-02-03 00:00:00',
        },
        {   input    => '2021-02-03 01:02:03',
            expected => '2021-02-03 01:02:03',
        },
        {   input    => '2021/02/03',
            expected => '2021-02-03 00:00:00',
        },
        {   input    => '2021/02/03 00:00:00',
            expected => '2021-02-03 00:00:00',
        },
        {   input    => '2021/02/03 01:02:03',
            expected => '2021-02-03 01:02:03',
        },
        {   input    => WWW::Recorder::TimePiece->new('2021/02/03 01:02:03'),
            expected => '2021-02-03 01:02:03',
        },
    );
    foreach my $testcase (@testcases) {
        my $tp2 = new_ok( 'WWW::Recorder::TimePiece', [ $testcase->{'input'} ], '$tp2' );
        is( $tp2->stringify(), $testcase->{'expected'}, $testcase->{'input'} );
    }
};

subtest 'TimePiece/toPostfix' => sub {
    my $tp1 = new_ok( 'WWW::Recorder::TimePiece', undef, '$tp1' );
    is( $tp1->toPostfix(), localtime->strftime('%Y-%m-%d %H-%M'), 'null' );
    my @testcases = (
        {   input    => '00:00',
            expected => '1970-01-01 00-00',
        },
        {   input    => '01:02',
            expected => '1970-01-01 00-01',
        },
        {   input    => '01:02:03',
            expected => '1970-01-01 01-02',
        },
        {   input    => '2021-02-03',
            expected => '2021-02-03 00-00',
        },
        {   input    => '2021-02-03 00:00:00',
            expected => '2021-02-03 00-00',
        },
        {   input    => '2021-02-03 01:02:03',
            expected => '2021-02-03 01-02',
        },
        {   input    => '2021/02/03',
            expected => '2021-02-03 00-00',
        },
        {   input    => '2021/02/03 00:00:00',
            expected => '2021-02-03 00-00',
        },
        {   input    => '2021/02/03 01:02:03',
            expected => '2021-02-03 01-02',
        },
        {   input    => WWW::Recorder::TimePiece->new('2021/02/03 01:02:03'),
            expected => '2021-02-03 01-02',
        },
    );
    foreach my $testcase (@testcases) {
        my $tp2 = new_ok( 'WWW::Recorder::TimePiece', [ $testcase->{'input'} ], '$tp2' );
        is( $tp2->toPostfix(), $testcase->{'expected'}, $testcase->{'input'} );
    }
};

done_testing();
