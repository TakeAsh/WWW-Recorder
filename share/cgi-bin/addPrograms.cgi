#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile Dump );
use CGI;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;
use WWW::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $q = new CGI;
$q->charset(term_encoding);
my $callback = $q->param('Callback') || '';
my $result   = ApiAddPrograms( $q->multi_param('ProgramUris') );
outputApiResult( $q, $result, $callback );
