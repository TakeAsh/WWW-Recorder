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
use Net::Recorder;
use Net::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $q = new CGI;
$q->charset(term_encoding);
my $cookie = getCookie($q);
my $tt     = Template->new(
    {   INCLUDE_PATH => dist_dir('Net-Recorder') . '/templates',
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
my @programUris = getProgramUris( $q->multi_param('ProgramUris') );
my @programIds  = $q->multi_param('ProgramId');

if ( !!@programUris ) {
    $query->{'ProgramUris_'} = [@programUris];
}
my @providers = grep { $showSkeleton || $_ ne 'skeleton' } Net::Recorder::Provider->providerNames();
my $provider  = $q->param('Provider') || $cookie->{'Provider'};
if ( !grep { $_ eq $provider } @providers ) {
    $provider = $providers[0] || '';
}
$cookie->{'Provider'} = $provider;
my $extraKeys      = "Net::Recorder::Provider::${provider}"->keysShort();
my $extraKeyLabels = $extraKeys->getLabels();
defined( my $pid = fork() ) or die("Fail to fork: $!");
if ( !$pid ) {    # Child process
    close(STDOUT);
    close(STDIN);
    if ( $command eq 'Add' && !!@programUris ) {
        addPrograms(@programUris);
    } elsif ( $command eq 'Retry' && !!@programIds ) {
        retryPrograms( $provider, [@programIds] );
    } elsif ( $command eq 'Abort' && !!@programIds ) {
        abortPrograms( $provider, [@programIds] );
    } elsif ( $command eq 'Remove' && !!@programIds ) {
        removePrograms( $provider, [@programIds] );
    }
    exit;
}
my $out = $q->header(
    -type    => 'text/html',
    -charset => 'utf-8',
    -cookie  => setCookie( $q, $cookie ),
);
$tt->process(
    'index.html',
    {   title     => "${provider} - Net-Recorder",
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
