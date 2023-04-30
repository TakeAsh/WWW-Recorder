#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";

use_ok $_ for qw(
    WWW::Recorder
    WWW::Recorder::Util
    WWW::Recorder::Program
    WWW::Recorder::Program::Extra
    WWW::Recorder::Keywords
    WWW::Recorder::TimePiece
    WWW::Recorder::Provider
    WWW::Recorder::Provider::skeleton
    WWW::Recorder::Provider::radiko
    WWW::Recorder::Provider::radiru
    WWW::Recorder::Setup
);

done_testing;
