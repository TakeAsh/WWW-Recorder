#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use Test::More;
use Test::More::UTF8;
use FindBin::libs "Bin=${FindBin::RealBin}";

use_ok $_ for qw(
    Net::Recorder
    Net::Recorder::Util
    Net::Recorder::Program
    Net::Recorder::Program::Extra
    Net::Recorder::Keywords
    Net::Recorder::TimePiece
    Net::Recorder::Provider
    Net::Recorder::Provider::skeleton
    Net::Recorder::Provider::radiko
    Net::Recorder::Provider::radiru
    Net::Recorder::Setup
);

done_testing;
