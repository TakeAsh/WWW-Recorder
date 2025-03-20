#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder::Util;

subtest 'joinValid' => sub {
    my @testcases = (
        {   input    => [],
            expected => '',
        },
        {   input    => [','],
            expected => '',
        },
        {   input    => [ ',', undef ],
            expected => '',
        },
        {   input    => [ ',', undef, undef ],
            expected => '',
        },
        {   input    => [ ',', undef, 'A' ],
            expected => 'A',
        },
        {   input    => [ ',', 'B', undef ],
            expected => 'B',
        },
        {   input    => [ ',', 'A', 'B', 'C' ],
            expected => 'A,B,C',
        },
        {   input    => [ ',', undef, 'A', undef, undef, 'B', undef, 'C', undef, undef ],
            expected => 'A,B,C',
        },
        {   input    => [ ',', '', 'A', '', '', 'B', '', 'C', '', '' ],
            expected => 'A,B,C',
        },
    );
    foreach my $testcase (@testcases) {
        is( joinValid( @{ $testcase->{'input'} } ),
            $testcase->{'expected'},
            join( ",", map { $_ || '_' } @{ $testcase->{'input'} } )
        );
    }
};

subtest 'normalizeSubtitle' => sub {
    my @testcases = (
        {   input    => '第0話',
            expected => '第00話',
        },
        {   input    => '第1話',
            expected => '第01話',
        },
        {   input    => '第7話',
            expected => '第07話',
        },
        {   input    => '第8話',
            expected => '第08話',
        },
        {   input    => '第9話',
            expected => '第09話',
        },
        {   input    => '第07話',
            expected => '第07話',
        },
        {   input    => '第08話',
            expected => '第08話',
        },
        {   input    => '第09話',
            expected => '第09話',
        },
        {   input    => '第10話',
            expected => '第10話',
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
        {   input    => 'CHAPTER 1',
            expected => 'CHAPTER 01',
        },
        {   input    => 'CHAPTER.1',
            expected => 'CHAPTER.01',
        },
        {   input    => '第一場',
            expected => '第01場',
        },
        {   input    => '週替わり番組　第２木曜日の夜（第２）、 hiro-t（第４）、第５木曜の夜（第５）',
            expected => '週替わり番組 第2木曜日の夜(第2)、 hiro-t(第4)、第5木曜の夜(第5)',
        },
    );
    my $handler = sub {
        my ( $message, $match, $full ) = @_;
        note("${message}: ${match} / ${full}");
    };
    foreach my $testcase (@testcases) {
        is( normalizeSubtitle( $testcase->{'input'}, $handler ),
            $testcase->{'expected'},
            $testcase->{'input'}
        );
    }
};

done_testing();
