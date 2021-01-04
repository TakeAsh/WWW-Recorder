#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use Time::Piece;
use Time::Seconds;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Program;

subtest 'Extra' => sub {
    my $expected = "sequence=1; series=series1; thumb=thumb1.jpg";
    my $extra1   = new_ok( 'Net::Recorder::Program::Extra', undef, '$extra1' );
    is( $extra1->stringify(), "", 'null' );
    my $extra2 = new_ok(
        'Net::Recorder::Program::Extra',
        [   series   => 'series1',
            sequence => 1,
            thumb    => 'thumb1.jpg',
        ],
        '$extra2'
    );
    is( $extra2->stringify(), "${expected}", 'List' );
    my @testcases = (
        {   input    => undef,
            expected => "",
            name     => 'undef'
        },
        {   input    => { series => 'series1', sequence => 1, thumb => 'thumb1.jpg', },
            expected => "${expected}",
            name     => 'Hash'
        },
        {   input    => 'series=series1; sequence=1; thumb=thumb1.jpg',
            expected => "${expected}",
            name     => 'String'
        },
        {   input    => $extra2,
            expected => "${expected}",
            name     => 'Extra'
        },
    );
    foreach my $testcase (@testcases) {
        my $extra3 = new_ok( 'Net::Recorder::Program::Extra', [ $testcase->{'input'} ], '$extra3' );
        is( $extra3->stringify(), $testcase->{'expected'}, $testcase->{'name'} );
    }
};

subtest 'Program/new' => sub {
    my $input = {
        Provider => 'Provider1',
        ID       => '001',
        Start    => '2021/02/03 01:02:03',
        Title    => 'Title1',
    };
    my $common = join( "\n",
        "ID\t001",         "Provider\tProvider1", "Start\t2021-02-03 01:02:03",
        "Status\tWAITING", "Title\tTitle1" );
    my $extra = "Extra\tsequence=1; series=series1; thumb=thumb1.jpg";
    is( Net::Recorder::Program->new($input)->stringify(), "${common}", 'null' );
    my $extra1 = new_ok(
        'Net::Recorder::Program::Extra',
        [   series   => 'series1',
            sequence => 1,
            thumb    => 'thumb1.jpg',
        ],
        '$extra1'
    );
    my @testcases = (
        {   input    => undef,
            expected => "Extra\t\n${common}",
            name     => 'undef'
        },
        {   input    => { series => 'series1', sequence => 1, thumb => 'thumb1.jpg', },
            expected => "${extra}\n${common}",
            name     => 'Hash'
        },
        {   input    => 'series=series1; sequence=1; thumb=thumb1.jpg',
            expected => "${extra}\n${common}",
            name     => 'String'
        },
        {   input    => $extra1,
            expected => "${extra}\n${common}",
            name     => 'Extra'
        },
    );
    foreach my $testcase (@testcases) {
        is( Net::Recorder::Program->new( %{$input}, Extra => $testcase->{'input'} )->stringify(),
            $testcase->{'expected'},
            $testcase->{'name'}
        );
    }
};

subtest 'Program/Extra' => sub {
    my $input = {
        Provider => 'Provider1',
        ID       => '001',
        Start    => '2021/02/03 01:02:03',
        Title    => 'Title1',
    };
    my $common = join( "\n",
        "ID\t001",         "Provider\tProvider1", "Start\t2021-02-03 01:02:03",
        "Status\tWAITING", "Title\tTitle1" );
    my $extra  = "Extra\tsequence=1; series=series1; thumb=thumb1.jpg";
    my $extra1 = new_ok(
        'Net::Recorder::Program::Extra',
        [   series   => 'series1',
            sequence => 1,
            thumb    => 'thumb1.jpg',
        ],
        '$extra1'
    );
    my @testcases = (
        {   input    => undef,
            expected => "Extra\t\n${common}",
            name     => 'undef'
        },
        {   input    => { series => 'series1', sequence => 1, thumb => 'thumb1.jpg', },
            expected => "${extra}\n${common}",
            name     => 'Hash'
        },
        {   input    => 'series=series1; sequence=1; thumb=thumb1.jpg',
            expected => "${extra}\n${common}",
            name     => 'String'
        },
        {   input    => $extra1,
            expected => "${extra}\n${common}",
            name     => 'Extra'
        },
    );
    foreach my $testcase (@testcases) {
        my $program = Net::Recorder::Program->new($input);
        $program->Extra( $testcase->{'input'} );
        is( $program->stringify(), $testcase->{'expected'}, $testcase->{'name'} );
    }
    my $program2 = Net::Recorder::Program->new($input);
    $program2->Extra( series => 'series1', sequence => 1, thumb => 'thumb1.jpg', );
    is( $program2->stringify(), "${extra}\n${common}", 'List' );
};

done_testing();
