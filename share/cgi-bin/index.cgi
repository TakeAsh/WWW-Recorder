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

my $query       = { map { $_ => [ $q->multi_param($_) ]; } $q->multi_param() };
my $command     = $q->param('Command') || '';
my $sortBy      = $q->param('SortBy')  || 'Status';
my @programUris = getProgramUris( $q->multi_param('ProgramUris') );
my @programIds  = $q->multi_param('ProgramId');
if ( !!@programUris ) {
    $query->{'ProgramUris_'} = [@programUris];
}
my @providers = Net::Recorder::Provider->providerNames();
my $provider
    = $cookie->{'Provider'}
    = $q->param('Provider')
    || $cookie->{'Provider'}
    || $providers[0]
    || '';

defined( my $pid = fork() ) or die("Fail to fork: $!");
if ( !$pid ) {    # Child process
    if ( $command eq 'Add' && !!@programUris ) {
        addPrograms(@programUris);
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
        info     => undef,                                         # Dump($query),
        programs => getProgramsForDisplay( $provider, $sortBy ),
    },
    \$out
) or die( $tt->error );

say $out;
