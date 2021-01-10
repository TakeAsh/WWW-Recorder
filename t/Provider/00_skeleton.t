#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder;

subtest 'skeleton/Class method/keysShort' => sub {
    my $key1 = 'Net::Recorder::Provider::skeleton'->keysShort();
    isa_ok( $key1, 'Net::Recorder::Program::Extra::Keys', '$key1' );
    is( $key1->stringify(), 'series=>; sequence=>Seq.', 'stringify' );
    is_deeply( $key1->getKeys(),   [qw(series sequence)], 'getKeys' );
    is_deeply( $key1->getLabels(), [qw(series Seq.)],     'getLabels' );
};

subtest 'skeleton/Class method/new' => sub {
    my $skeleton1 = new_ok( 'Net::Recorder::Provider::skeleton', undef, '$skeleton1' );
    can_ok( $skeleton1, qw(new getPrograms getProgramsFromUri record) );
};

subtest 'skeleton/Instance method/keysShort' => sub {
    my $skeleton1 = new_ok( 'Net::Recorder::Provider::skeleton', undef, '$skeleton1' );
    my $key1      = $skeleton1->keysShort();
    isa_ok( $key1, 'Net::Recorder::Program::Extra::Keys', '$key1' );
    is( $key1->stringify(), 'series=>; sequence=>Seq.', 'stringify' );
    is_deeply( $key1->getKeys(),   [qw(series sequence)], 'getKeys' );
    is_deeply( $key1->getLabels(), [qw(series Seq.)],     'getLabels' );
};

subtest 'skeleton::Extra/Class method/keysShort' => sub {
    my $key1 = 'Net::Recorder::Provider::skeleton::Extra'->keysShort();
    isa_ok( $key1, 'Net::Recorder::Program::Extra::Keys', '$key1' );
    is( $key1->stringify(), 'series=>; sequence=>Seq.', 'stringify' );
    is_deeply( $key1->getKeys(),   [qw(series sequence)], 'getKeys' );
    is_deeply( $key1->getLabels(), [qw(series Seq.)],     'getLabels' );
};

subtest 'skeleton::Extra' => sub {
    my $expected      = "sequence=1; series=series1; thumb=thumb1.jpg";
    my $expectedShort = "sequence=1; series=series1";
    my $extra1        = new_ok( 'Net::Recorder::Provider::skeleton::Extra', undef, '$extra1' );
    can_ok( $extra1, qw(new series sequence thumb) );
    is( $extra1->stringify(),      "",    'stringify' );
    is( $extra1->stringifyShort(), "",    'stringifyShort' );
    is( $extra1->series(),         undef, 'series' );
    is( $extra1->sequence(),       undef, 'sequence' );
    is( $extra1->thumb(),          undef, 'thumb' );
    my $extra2 = new_ok( 'Net::Recorder::Provider::skeleton::Extra',
        [ series => 'series1', sequence => 1, thumb => 'thumb1.jpg', ], '$extra2' );
    is( $extra2->stringify(),      $expected,      'stringify' );
    is( $extra2->stringifyShort(), $expectedShort, 'stringifyShort' );
    is( $extra2->series(),         'series1',      'series' );
    is( $extra2->sequence(),       1,              'sequence' );
    is( $extra2->thumb(),          'thumb1.jpg',   'thumb' );
    my $keys2 = $extra2->keysShort();
    isa_ok( $keys2, 'Net::Recorder::Program::Extra::Keys', 'keysShort' );
    is( $keys2->stringify(), 'series=>; sequence=>Seq.', 'keysShort/stringify' );
    is_deeply( $keys2->getKeys(),   [qw(series sequence)], 'keysShort/getKeys' );
    is_deeply( $keys2->getLabels(), [qw(series Seq.)],     'keysShort/getLabels' );
};

done_testing();
