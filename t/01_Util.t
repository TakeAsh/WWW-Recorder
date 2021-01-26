#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Util;

subtest 'normalizeSubtitle' => sub {
    my @testcases = (
        {   input    => '第0話',
            expected => '第0話',
        },
        {   input    => '第1話',
            expected => '第01話',
        },
        {   input    => '第12話',
            expected => '第12話',
        },
        {   input    => '第123話',
            expected => '第123話',
        },
        {   input    => '第壱話',
            expected => '第01話',
        },
        {   input    => '第壱拾弐話',
            expected => '第12話',
        },
        {   input    => '第壱百弐拾参話',
            expected => '第123話',
        },
        {   input    => '1話',
            expected => '01話',
        },
        {   input    => '12話',
            expected => '12話',
        },
        {   input    => '123話',
            expected => '123話',
        },
        {   input    => 'ブラッド 1',
            expected => 'ブラッド 01',
        },
        {   input    => 'EX EX1',
            expected => 'EX EX01',
        },
        {   input    => 'STAGE 1',
            expected => 'STAGE 01',
        },
        {   input    => 'Stage：1',
            expected => 'Stage：01',
        },
        {   input    => 'Stage.1',
            expected => 'Stage.01',
        },
    );
    foreach my $testcase (@testcases) {
        is( normalizeSubtitle( $testcase->{'input'} ),
            $testcase->{'expected'},
            $testcase->{'input'}
        );
    }
};

done_testing();
