package Net::Recorder::Provider;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use JSON::XS;
use Try::Tiny;
use Const::Fast;
use Module::Find qw(usesub);
use URI;
use URI::Escape;
use LWP::UserAgent;
use DBIx::NamedParams;
use FindBin::libs;
use Net::Recorder::Util;
use Net::Recorder::Keywords;
use Net::Recorder::Program;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

my $package = __PACKAGE__;
const my @providerNames => sort( grep { !startsWith( $_, '_' ) }
        map { s/^${package}:://; $_; } usesub($package) );
const my $default => { AGENT => 'Mozilla/5.0', };

sub providerNames {
    my $class = shift;
    return @providerNames;
}

sub providers {
    my $class = shift;
    return map { $class->new($_); } @providerNames;
}

sub keysShort {
    my $both  = shift;
    my $class = ( ref($both) || $both ) or return;
    return "${class}::Extra"->keysShort();
}

sub new {
    my ( $class, $provider, @params ) = @_;
    if ( !grep { $_ eq $provider } @providerNames ) {
        croak("Provider not defined: $provider");
    }
    return "${class}::${provider}"->new(@params);
}

sub _new {
    my $class  = shift;
    my $params = {@_};
    my $conf   = loadConfig();
    my $self   = {};
    $self->{CONF}            = $conf;
    $self->{SQL}             = loadConfig('sql');
    $self->{NAME}            = $params->{'name'};
    $self->{PROGRAM_PATTERN} = $params->{'program_pattern'};
    $self->{KEYWORDS}        = undef;
    $self->{AGENT}           = LWP::UserAgent->new(
        keep_alive            => 4,
        timeout               => 600,
        requests_redirectable => [ 'GET', 'HEAD', 'POST' ],
        agent                 => $params->{'agent'} || $default->{'AGENT'},
        cookie_jar            => {},
    );
    $self->{REQUEST} = undef;
    $self->{LOG}     = [];
    bless( $self, $class );
    $self->keywords( $params->{'keywords'} || $conf->{'Keywords'} );
    return $self;
}

sub name {
    my $self = shift;
    return $self->{NAME};
}

sub program_pattern {
    my $self = shift;
    if (@_) {
        $self->{PROGRAM_PATTERN} = shift;
    }
    return $self->{PROGRAM_PATTERN};
}

sub keywords {
    my $self = shift;
    if (@_) {
        $self->{KEYWORDS} = Net::Recorder::Keywords->new(@_);
    }
    return $self->{KEYWORDS};
}

sub match {
    my $self = shift;
    if ( !$self->{KEYWORDS} ) {
        $self->log("'keywords' undefined.");
        return;
    }
    return $self->{KEYWORDS}->match(@_);
}

sub filter {
    my $self     = shift;
    my $programs = shift or return;
    my @matched  = grep { $_->Keyword() } map {
        $_->Keyword( $self->match( $_->Title, $_->Description, $_->Info, $_->Performer ) );
        $_;
    } @{$programs};
    return !@matched
        ? undef
        : [@matched];
}

sub agent {
    my $self = shift;
    my $name = shift || $default->{'AGENT'};
    $self->{AGENT}->agent($name);
    return $self;
}

sub request {
    my $self    = shift;
    my $method  = shift or return;
    my $uri     = shift or return;
    my $params  = shift || {};
    my $headers = shift || {};
    my $query   = shift || {};
    my $content = shift;
    $uri =~ s/\{$_\}/$params->{$_}/ for keys( %{$params} );
    $uri = URI->new($uri);
    $uri->query_form( %{$query} );
    $self->{REQUEST} = HTTP::Request->new(
        $method => $uri,
        [ %{$headers} ],
        $content
    );
    return $self;
}

sub call {
    my $self = shift;
    if ( !$self->{REQUEST} ) {
        return;
    }
    return $self->{AGENT}->request( $self->{REQUEST} );
}

sub getPrograms {
    my $self = shift;
    return undef;
}

sub getProgramsFromUri {
    my $self  = shift;
    my $index = shift or return;
    my $total = shift or return;
    my $uri   = shift or return;
    my $match = shift or return;
    return undef;
}

sub store {
    my $self     = shift;
    my $programs = shift or return;
    my $dbh      = connectDB( $self->{CONF}{'DbInfo'} );
    my $columns  = getColumnsHash( $dbh, 'Programs' );
    my $sth      = $dbh->prepare_ex( $self->{SQL}{'InsertProgram'} ) or die($DBI::errstr);
    foreach my $program ( @{$programs} ) {
        if ( $self->checkProgram( $dbh, $program ) ) { next; }
        foreach my $key ( $program->keys ) {
            my $max = $columns->{$key}{'CHARACTER_MAXIMUM_LENGTH'} || 0;
            if ( $max && ( my $len = length( $program->{$key} ) || 0 ) >= $max ) {
                $self->log( "'$key' too long, $len" . $program->{$key} );
                $program->{$key} = substr( $program->{$key}, 0, $max );
            }
        }
        $sth->bind_param_ex($program) or die($DBI::errstr);
        $sth->execute()               or die($DBI::errstr);
    }
    $sth->finish;
    $dbh->disconnect;
    return $programs;
}

sub checkProgram {
    my $self    = shift;
    my $dbh     = shift                                                      or return;
    my $program = shift                                                      or return;
    my $sth     = $dbh->prepare_ex( $self->{SQL}{'CheckProgram'}, $program ) or die($DBI::errstr);
    $sth->execute() or die($DBI::errstr);
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
    return $row;
}

sub isSupported {
    my $self    = shift;
    my $program = shift or return;
    return !$self->{PROGRAM_PATTERN} || $program !~ /$self->{PROGRAM_PATTERN}/
        ? 0
        : {%+};
}

sub getStartingPrograms {
    my $self = shift;
    my $dbh  = connectDB( $self->{CONF}{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( $self->{SQL}{'GetProgramsForRecord'}, { Provider => $self->name(), } )
        or die($DBI::errstr);
    $sth->execute() or die($DBI::errstr);
    my @programs = ();
    while ( my $row = $sth->fetchrow_hashref ) {
        push( @programs, Net::Recorder::Program->new($row) );
    }
    $sth->finish;
    $dbh->disconnect;
    return !@programs
        ? undef
        : [@programs];
}

sub setStandBy {
    my $self     = shift;
    my $programs = shift or return;
    my $dbh      = connectDB( $self->{CONF}{'DbInfo'} );
    my $sth      = $dbh->prepare_ex( $self->{SQL}{'SetStatus'} ) or die($DBI::errstr);
    foreach my $program ( @{$programs} ) {
        $program->Status('STANDBY');
        $sth->bind_param_ex($program) or die($DBI::errstr);
        $sth->execute()               or die($DBI::errstr);
    }
    $sth->finish;
    $dbh->disconnect;
    return;
}

sub setStatus {
    my $self    = shift;
    my $dbh     = shift                                                   or return;
    my $program = shift                                                   or return;
    my $sth     = $dbh->prepare_ex( $self->{SQL}{'SetStatus'}, $program ) or die($DBI::errstr);
    $sth->execute() or die($DBI::errstr);
    $sth->finish;
    return;
}

sub record {
    my $self     = shift;
    my $programs = shift or return;
    return undef;
}

sub log {
    my $self    = shift;
    my $message = shift or return;
    push( @{ $self->{LOG} }, $message );
}

sub flush {
    my $self = shift;
    say join( "\n", @{ $self->{LOG} } );
    $self->{LOG} = [];
}

1;
