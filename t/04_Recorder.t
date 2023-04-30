#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;

subtest 'getProgramUris' => sub {
    my @testcases = (
        {   input =>
                [ "fm.74909.2022-02-12.130", "fm.74913.2022-02-12.130", "fm.74911.2022-02-12.130" ],
            expected =>
                [ "fm.74909.2022-02-12.130", "fm.74911.2022-02-12.130", "fm.74913.2022-02-12.130" ],
            name => 'Plain',
        },
        {   input => ["fm.74909.2022-02-12.130\nfm.74911.2022-02-12.130\nfm.74913.2022-02-12.130"],
            expected =>
                [ "fm.74909.2022-02-12.130", "fm.74911.2022-02-12.130", "fm.74913.2022-02-12.130" ],
            name => 'NewLine',
        },
        {   input => [
                "fm.[74909-74911].2022-02-12.130", "fm.[74915-74917].2022-02-12.130",
                "fm.74913.2022-02-12.130"
            ],
            expected => [
                "fm.74909.2022-02-12.130", "fm.74910.2022-02-12.130",
                "fm.74911.2022-02-12.130", "fm.74913.2022-02-12.130",
                "fm.74915.2022-02-12.130", "fm.74916.2022-02-12.130",
                "fm.74917.2022-02-12.130"
            ],
            name => 'Expand_Number',
        },
        {   input    => ["fm.74909[a-d].2022-02-12.130"],
            expected => [
                "fm.74909a.2022-02-12.130", "fm.74909b.2022-02-12.130",
                "fm.74909c.2022-02-12.130", "fm.74909d.2022-02-12.130"
            ],
            name => 'Expand_Alphabet',
        },
    );
    foreach my $testcase (@testcases) {
        is_deeply(
            [ getProgramUris( @{ $testcase->{'input'} } ) ],
            $testcase->{'expected'},
            $testcase->{'name'}
        );
    }
};

done_testing();
