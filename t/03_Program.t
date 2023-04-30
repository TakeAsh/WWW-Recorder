#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use Time::Piece;
use Time::Seconds;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder::Program;
use WWW::Recorder::Provider;

subtest 'Extra' => sub {
    my $expected      = "sequence=1; series=series1; thumb=thumb1.jpg";
    my $expectedShort = "sequence=1; series=series1";
    my $extra1        = new_ok( 'WWW::Recorder::Program::Extra', undef, '$extra1' );
    is( $extra1->stringify(), "", 'null' );
    my $extra2 = new_ok(
        'WWW::Recorder::Program::Extra',
        [   series   => 'series1',
            sequence => 1,
            thumb    => 'thumb1.jpg',
        ],
        '$extra2'
    );
    is( $extra2->stringify(), $expected, 'List' );
    my $keys2 = $extra2->keysShort( 'series' => undef, 'sequence' => 'Seq.', );
    isa_ok( $keys2, 'WWW::Recorder::Program::Extra::Keys', 'keysShort' );
    is( $keys2->stringify(), 'series=>; sequence=>Seq.', 'keysShort/stringify' );
    is_deeply( $keys2->getKeys(),   [qw(series sequence)], 'keysShort/getKeys' );
    is_deeply( $keys2->getLabels(), [qw(series Seq.)],     'keysShort/getLabels' );
    is( $extra2->stringifyShort(), $expectedShort, 'stringifyShort' );
    my @testcases = (
        {   input         => undef,
            expected      => "",
            expectedShort => "",
            name          => 'undef'
        },
        {   input         => { series => 'series1', sequence => 1, thumb => 'thumb1.jpg', },
            expected      => $expected,
            expectedShort => $expectedShort,
            name          => 'Hash'
        },
        {   input         => 'series=series1; sequence=1; thumb=thumb1.jpg',
            expected      => $expected,
            expectedShort => $expectedShort,
            name          => 'String'
        },
        {   input         => $extra2,
            expected      => $expected,
            expectedShort => $expectedShort,
            name          => 'Extra'
        },
    );

    foreach my $testcase (@testcases) {
        my $extra3 = new_ok( 'WWW::Recorder::Program::Extra', [ $testcase->{'input'} ], '$extra3' );
        is( $extra3->stringify(), $testcase->{'expected'}, "stringify/$testcase->{name}" );
        is( $extra3->stringifyShort(),
            $testcase->{'expectedShort'},
            "stringifyShort/$testcase->{name}"
        );
    }
};

subtest 'Program/new' => sub {
    my $input = {
        Provider => 'skeleton',
        ID       => '001',
        Start    => '2021/02/03 01:02:03',
        Title    => 'Title1',
    };
    my $common = join( "\n",
        "ID\t001",         "Provider\tskeleton", "Start\t2021-02-03 01:02:03",
        "Status\tWAITING", "Title\tTitle1" );
    my $extra = "Extra\tsequence=1; series=series1; thumb=thumb1.jpg";
    is( WWW::Recorder::Program->new($input)->stringify(), "${common}", 'null' );
    my $extra1 = new_ok(
        'WWW::Recorder::Program::Extra',
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
        is( WWW::Recorder::Program->new( %{$input}, Extra => $testcase->{'input'} )->stringify(),
            $testcase->{'expected'},
            $testcase->{'name'}
        );
    }
    is( WWW::Recorder::Program->new( %{$input}, End => '2021/02/03 01:23:45' )->stringify(),
        "Duration\t1302\nEnd\t2021-02-03 01:23:45\n${common}",
        'auto calc Duration'
    );
    is( WWW::Recorder::Program->new( %{$input}, Duration => 5 * 60 )->stringify(),
        "Duration\t300\nEnd\t2021-02-03 01:07:03\n${common}",
        'auto calc End'
    );
    is( WWW::Recorder::Program->new( %{$input}, End => '2021/02/04 02:03:04', Duration => 10 * 60 )
            ->stringify(),
        "Duration\t600\nEnd\t2021-02-04 02:03:04\n${common}",
        'keep Duration/End'
    );
    my $titleHandler = sub {
        my ( $message, $match, $full ) = @_;
        note("${message}: ${match} / ${full}");
    };
    my $expected2 = join( "\n",
        "ID\t001",         "Provider\tskeleton", "Start\t2021-02-03 01:02:03",
        "Status\tWAITING", "Title\t週替わり番組 第2木曜日の夜" );
    is( WWW::Recorder::Program->new( %{$input}, Title => '週替わり番組　第２木曜日の夜' )->stringify(),
        $expected2, 'Title warning (ignore warning)' );
    is( WWW::Recorder::Program->new( %{$input},
            Title => [ '週替わり番組　第２木曜日の夜', Handler => $titleHandler, ] )->stringify(),
        $expected2,
        'Title warning (handle warning)'
    );
};

subtest 'Program/Extra' => sub {
    my $input = {
        Provider => 'skeleton',
        ID       => '001',
        Start    => '2021/02/03 01:02:03',
        Title    => 'Title1',
    };
    my $common = join( "\n",
        "ID\t001",         "Provider\tskeleton", "Start\t2021-02-03 01:02:03",
        "Status\tWAITING", "Title\tTitle1" );
    my $extra  = "Extra\tsequence=1; series=series1; thumb=thumb1.jpg";
    my $extra1 = new_ok(
        'WWW::Recorder::Program::Extra',
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
        my $program = WWW::Recorder::Program->new($input);
        $program->Extra( $testcase->{'input'} );
        is( $program->stringify(), $testcase->{'expected'}, $testcase->{'name'} );
    }
    my $program2 = WWW::Recorder::Program->new($input);
    $program2->Extra( series => 'series1', sequence => 1, thumb => 'thumb1.jpg', );
    is( $program2->stringify(), "${extra}\n${common}", 'List' );
};

done_testing();
