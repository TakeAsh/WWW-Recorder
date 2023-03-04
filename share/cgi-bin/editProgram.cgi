#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump DumpFile);
use Template;
use CGI;
use File::Share ':all';
use Data::UUID;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder;
use Net::Recorder::Util;
use Term::Encoding qw(term_encoding);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $Statuses = [qw(RECORDING STANDBY WAITING DONE ABORT FAILED NO_INFO)];

my $q = new CGI;
$q->charset(term_encoding);
my $cookie = getCookie($q);
my $tt     = Template->new(
    {   INCLUDE_PATH => dist_dir('Net-Recorder') . '/templates',
        ENCODING     => 'utf-8',
    }
) or die( Template->error() );

my $query        = { Cookie => $cookie, map { $_ => [ $q->multi_param($_) ]; } $q->multi_param() };
my $showSkeleton = $cookie->{'ShowSkeleton'}
    = defined( $q->param('ShowSkeleton') )
    ? !!$q->param('ShowSkeleton')
    : $cookie->{'ShowSkeleton'} || '';
my @providers = grep { $showSkeleton || $_ ne 'skeleton' } Net::Recorder::Provider->providerNames();
my $command   = $q->param('Command')  || '';
my $provider  = $q->param('Provider') || '';
my $id        = $q->param('ID')       || Data::UUID->new->create_str();

if ( !grep { $_ eq $provider } @providers ) {
    $provider = $providers[0] || '';
}
$cookie->{'Provider'} = $provider;
if ( $command eq 'Update' ) {
    update(
        $provider,
        $id,
        scalar $q->param('Extra'),
        join( " ", scalar $q->param('StartDate'), scalar $q->param('StartTime') ),
        join( " ", scalar $q->param('EndDate'),   scalar $q->param('EndTime') ),
        scalar $q->param('Title'),
        scalar $q->param('Description'),
        scalar $q->param('Info'),
        scalar $q->param('Performer'),
        scalar $q->param('Uri'),
        scalar $q->param('Keyword'),
    );
}
my $program = getProgramById( $provider, $id );
my $extra   = Net::Recorder::Util::stringify(
    $program->Extra(),
    ITEM_SEPARATOR   => "\n",
    KEYVAL_SEPARATOR => "="
);
my $out = $q->header(
    -type    => 'text/html',
    -charset => 'utf-8',
    -cookie  => setCookie( $q, $cookie ),
);
$tt->process(
    'editProgram.html',
    {   title     => "${provider} - Net-Recorder",
        provider  => $provider,
        providers => [@providers],
        info      => undef,                          # Dump($query),
        program   => $program,
        extra     => $extra,
        statuses  => $Statuses,
    },
    \$out
) or die( $tt->error );
say $out;

sub update {
    my ($providerName, $id,   $extra,     $start, $end, $title,
        $description,  $info, $performer, $uri,   $keyword
    ) = @_;
    $extra = unifyLf($extra);
    $extra =~ s/\n/; /g;
    my $program = Net::Recorder::Program->new(
        Provider    => $providerName,
        ID          => $id,
        Extra       => $extra,
        Start       => $start,
        End         => $end,
        Title       => $title,
        Description => $description,
        Info        => $info,
        Performer   => $performer,
        Uri         => $uri,
        Keyword     => $keyword,
    );
    my $provider = Net::Recorder::Provider->new($providerName);
    $provider->store( [$program], Force => 1 );
}
