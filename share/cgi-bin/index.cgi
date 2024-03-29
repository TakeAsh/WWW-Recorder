#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile Dump );
use Template;
use CGI;
use File::Share ':all';
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;
use WWW::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $q = new CGI;
$q->charset(term_encoding);
my $cookie = getCookie($q);
my $tt     = Template->new(
    {   INCLUDE_PATH => dist_dir('WWW-Recorder') . '/templates',
        ENCODING     => 'utf-8',
    }
) or die( Template->error() );

my $query        = { Cookie => $cookie, map { $_ => [ $q->multi_param($_) ]; } $q->multi_param() };
my $command      = $q->param('Command') || '';
my $sortBy       = $q->param('SortBy')  || 'Status';
my $showSkeleton = $cookie->{'ShowSkeleton'}
    = defined( $q->param('ShowSkeleton') )
    ? !!$q->param('ShowSkeleton')
    : $cookie->{'ShowSkeleton'} || '';
my @programIds = $q->multi_param('ProgramId');
my @providers = grep { $showSkeleton || $_ ne 'skeleton' } WWW::Recorder::Provider->providerNames();
my $provider  = $q->param('Provider') || $cookie->{'Provider'} || '';

if ( !grep { $_ eq $provider } @providers ) {
    $provider = $providers[0] || '';
}
$cookie->{'Provider'} = $provider;
my $extraKeys      = "WWW::Recorder::Provider::${provider}"->keysShort();
my $extraKeyLabels = $extraKeys->getLabels();
defined( my $pid = fork() ) or die("Fail to fork: $!");
if ( !$pid ) {    # Child process
    close(STDOUT);
    close(STDIN);
    exit;
}
my $out = $q->header(
    -type    => 'text/html',
    -charset => 'utf-8',
    -cookie  => setCookie( $q, $cookie ),
);
$tt->process(
    'index.html',
    {   title     => "${provider} - WWW-Recorder",
        provider  => $provider,
        providers =>
            [ map { { name => $_, selected => $_ eq $provider ? 'selected' : '', } } @providers ],
        sortBy       => $sortBy,
        info         => undef,                    # Dump($query),
        numOfColumns => 7 + @{$extraKeyLabels},
        extraKeys    => $extraKeyLabels,
        programs     => getProgramsForDisplay( $provider, $extraKeys->getKeys(), $sortBy ),
    },
    \$out
) or die( $tt->error );

say $out;
