#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile Dump );
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder::Setup;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

setup();
