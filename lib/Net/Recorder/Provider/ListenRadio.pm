package Net::Recorder::Provider::ListenRadio;
use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use Time::Seconds;
use IPC::Cmd qw(can_run run QUOTE);
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Util;
use Net::Recorder::TimePiece;
use Net::Recorder::Program;
use parent 'Net::Recorder::Provider';

$YAML::Syck::ImplicitUnicode = 1;

my $package = __PACKAGE__;
my $conf    = {
    FormatId       => '%Y%m%d-%H%M00',
    FormatDateTime => '%Y/%m/%d %H:%M:00',
    Series         => 'Dummy',
    Thumb          => 'https://example.com/Dummy/thumb/%s_%02d.jpg',
    Uri            => 'https://example.com/Dummy/story/%s_%03d/',
};

my $ffmpeg = can_run('ffmpeg') or die("ffmpeg is not found");

sub new {
    my $class  = shift;
    my $params = {@_};
    my $self   = $class->SUPER::_new(
        %{$params},
        name            => 'ListenRadio',
        program_pattern => undef,
    );
    bless( $self, $class );
    return $self;
}

sub Api {
    my $self = shift;
    if ( !$self->{API} ) {
        $self->{API} = "${package}::Api"->new();
    }
    return $self->{API};
}

sub Channels {
    my $self = shift;
    if ( !$self->{CHANNELS} ) {
        $self->{CHANNELS} = "${package}::Channels"->new( $self->Api()->Channel() );
    }
    return $self->{CHANNELS};
}

sub getPrograms {
    my $self     = shift;
    my @programs = ();
    foreach my $channel ( @{ $self->Channels() } ) {
        sleep(1);
        my $rawPrograms = $self->Api()->Schedule( $channel->{'ChannelId'} ) or next;
        my $progs       = $self->toPrograms($rawPrograms)                   or next;
        my $filered     = $self->filter($progs)                             or next;
        push( @programs, @{$filered} );
    }
    return !@programs
        ? undef
        : [@programs];
}

sub getProgramsFromUri {
    my $self     = shift;
    my $index    = shift or return;
    my $total    = shift or return;
    my $uri      = shift or return;
    my $match    = shift or return;
    my @programs = ();
    return !@programs
        ? undef
        : [@programs];
}

sub toPrograms {
    my $self        = shift;
    my $rawPrograms = shift or return;
    return [ map { $self->toProgram($_); } @{$rawPrograms} ];
}

sub toProgram {
    my $self = shift;
    my $p    = shift or return;
    return Net::Recorder::Program->new(
        Provider => $self->name(),
        ID       => $p->{'ProgramScheduleId'},
        Extra    => {
            StationId   => $p->{'StationId'},
            StationName => $p->{'StationName'},
            ProgramId   => $p->{'ProgramId'},
        },
        Start       => $self->toDateTime( $p->{'StartDate'} ),
        End         => $self->toDateTime( $p->{'EndDate'} ),
        Title       => $p->{'ProgramName'},
        Description => $p->{'ProgramSummary'},
    );
}

sub toDateTime {
    my $self     = shift;
    my $datetime = shift or return;
    return
          $datetime =~ s/^(\d{4})(\d{2})(\d{2})$/$1-$2-$3/                        ? $datetime
        : $datetime =~ s/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})$/$1-$2-$3 $4:$5:00/ ? $datetime
        :                                                                           $datetime;
}

sub record {
    my $self     = shift;
    my $programs = shift or return;
    my @programs = @{$programs};
    my $dest     = getAvailableDisk('2GiB');
    if ( !$dest ) {
        $self->log("Disk full");
        return;
    }
    my $index = 0;
    foreach my $program (@programs) {
        ++$index;
        $self->log( sprintf( "%d/%d\t%s", $index, scalar(@programs), $program->Title() ) );
        my $pid = fork;
        if ( !defined($pid) ) {
            $self->log("Failed to fork");
        } elsif ( !$pid ) {    # Child process
            my $dbh = connectDB( $self->{CONF}{'DbInfo'} );
            $program->Status('FAILED');
            $self->getStream( $dbh, $program, $dest );
            $self->setStatus( $dbh, $program );
            $dbh->disconnect;
            exit;
        }
    }
    while ( wait() >= 0 ) { sleep(1); }
}

sub getStream {
    my $self    = shift;
    my $dbh     = shift or return;
    my $program = shift or return;
    my $dest    = shift or return;
    my $now     = Net::Recorder::TimePiece->new();
    my $start   = $program->Start();
    my $end     = $program->End();
    my $sleep   = ( $start - $now )->seconds - 5;
    if ( $sleep > 0 ) { sleep($sleep); }
    my $fnameBase = join( " ", $program->Title(), $program->Provider() );
    my $fnameInfo = join( " ", $fnameBase,        $start->toPostfix() );
    DumpFile( "${dest}/${fnameInfo}_Info.yml", $program );
    $program->Status('RECORDING');
    $self->setStatus( $dbh, $program );
    $program->Status('FAILED');
    my $success = 0;

    while (1) {
        $start = Net::Recorder::TimePiece->new();
        my $duration = ( $end - $start )->seconds;
        if ( $duration < 0 ) { last; }
        my $fnameMain = join( " ", $fnameBase, $start->toPostfix() );
        sleep(70);
        DumpFile( "${dest}/${fnameMain}_Main.yml", $program );
        $success = 1;
        $program->Status('DONE');
    }
    return $success;
}

package Net::Recorder::Provider::ListenRadio::Api;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use LWP::UserAgent;
use URI;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

# https://listenradio.jp/Scripts/listenradio_api.js

my $confApi = {
    Agent => 'Mozilla/5.0',
    Uris  => { Service => 'https://listenradio.jp/service/{Api}.aspx', },
};

sub new {
    my $class = shift;
    my $self  = {
        AGENT => LWP::UserAgent->new(
            keep_alive            => 4,
            timeout               => 600,
            requests_redirectable => [ 'GET', 'HEAD', 'POST' ],
            agent                 => $confApi->{'Agent'},
            cookie_jar            => {},
        ),
    };
    bless( $self, $class );
    return $self;
}

sub call {
    my $self  = shift;
    my $api   = shift or return;
    my $query = shift || {};
    my $uri   = $confApi->{'Uris'}{'Service'};
    $uri =~ s/\{Api\}/${api}/;
    $uri = URI->new($uri);
    $uri->query_form( %{$query} );
    my $res = $self->{AGENT}->get($uri);

    if ( !$res->is_success ) {
        croak( "Failed to call API: ${api} " . $res->status_line );
    }
    return decodeJson( decodeUtf8( $res->decoded_content ) );
}

sub Channel {
    my $self   = shift;
    my $result = $self->call('channel') or return;
    return !exists( $result->{'Channel'} )
        ? undef
        : $result->{'Channel'};
}

sub Schedule {
    my $self      = shift;
    my $channelId = shift                                                   or return;
    my $result    = $self->call( 'schedule', { channelid => $channelId, } ) or return;
    return !exists( $result->{'ProgramSchedule'} )
        ? undef
        : $result->{'ProgramSchedule'};
}

package Net::Recorder::Provider::ListenRadio::Channels;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use Scalar::Util qw(reftype);
use List::Util qw(first);
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

sub new {
    my $class = shift;
    my $self  = shift || [];
    if ( ( reftype($self) || '' ) ne 'ARRAY' ) {
        croak("Must be array");
    }
    bless( $self, $class );
    return $self;
}

sub byId {
    my $self = shift;
    my $id   = shift or return;
    return first { $_->{'ChannelId'} == $id } @{$self};
}

sub byNames {
    my $self    = shift;
    my $names   = join( "|", map { quotemeta($_) } @_ );
    my @matched = grep { $_->{'ChannelName'} =~ /$names/ } @{$self};
    return !@matched
        ? undef
        : [@matched];
}

package Net::Recorder::Program::Extra::ListenRadio;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use FindBin::libs;
use parent 'Net::Recorder::Program::Extra';
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

__PACKAGE__->keysShort( 'StationName' => undef, );

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    bless( $self, $class );
    if ( $self->{StationId} )   { $self->StationId( $self->{StationId} ); }
    if ( $self->{StationName} ) { $self->StationName( $self->{StationName} ); }
    if ( $self->{ProgramId} )   { $self->ProgramId( $self->{ProgramId} ); }
    return $self;
}

sub StationId {
    my $self = shift;
    if (@_) { $self->{StationId} = shift; }
    return $self->{StationId};
}

sub StationName {
    my $self = shift;
    if (@_) { $self->{StationName} = shift; }
    return $self->{StationName};
}

sub ProgramId {
    my $self = shift;
    if (@_) { $self->{ProgramId} = shift; }
    return $self->{ProgramId};
}

1;
