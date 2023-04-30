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
my $cookie       = getCookie($q);
my $showSkeleton = $cookie->{'ShowSkeleton'}
    = defined( $q->param('ShowSkeleton') )
    ? !!$q->param('ShowSkeleton')
    : $cookie->{'ShowSkeleton'} || '';
my @providers = grep { $showSkeleton || $_ ne 'skeleton' } WWW::Recorder::Provider->providerNames();
my $provider  = $q->param('Provider') || $cookie->{'Provider'};

if ( !grep { $_ eq $provider } @providers ) {
    $provider = $providers[0] || '';
}
my $callback = $q->param('Callback') || '';
my $result = ApiCommand( scalar $q->param('Command'), $provider, [ $q->multi_param('ProgramId') ] );
outputApiResult( $q, $result, $callback );
