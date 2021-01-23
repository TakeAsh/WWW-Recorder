package Net::Recorder::Provider::radiko;
use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use Time::Seconds;
use XML::Simple;
use MIME::Base64;
use IPC::Cmd qw(can_run run QUOTE);
use List::Util qw(first);
use Digest::SHA2;
use FindBin::libs;
use Net::Recorder::Util;
use Net::Recorder::TimePiece;
use Net::Recorder::Program;
use parent 'Net::Recorder::Provider';

$YAML::Syck::ImplicitUnicode   = 1;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

my $conf = {
    Uris => {
        Area              => 'https://radiko.jp/area',
        ProgramsByArea    => 'https://radiko.jp/v3/program/date/{date}/{area}.xml',
        ProgramsByStation => 'https://radiko.jp/v3/program/station/date/{date}/{station}.xml',
        Auth1             => 'https://radiko.jp/v2/api/auth1',
        Auth2             => 'https://radiko.jp/v2/api/auth2',
        Streams           => 'https://radiko.jp/v3/station/stream/{App}/{Station}.xml',
    },
    AuthKey     => 'bcd151073c03b352e1ef2fd66c32209da9ca0afa',
    AuthHeaders => {
        'X-Radiko-App'         => 'pc_html5',
        'X-Radiko-App-Version' => '0.0.1',
        'X-Radiko-Device'      => 'pc',
        'X-Radiko-User'        => 'dummy_user',
    },
    Separator => ';',
};
my $ffmpeg = can_run('ffmpeg') or die("ffmpeg is not found");

sub new {
    my $class  = shift;
    my $params = {@_};
    my $self   = $class->SUPER::_new(
        %{$params},
        name            => 'radiko',
        program_pattern =>
            qr{^https://radiko.jp/#!/ts/(?<station>[^/]+)/(?<date>\d{8})(?<time>\d{6})\b},
    );
    bless( $self, $class );
    $self->area( $params->{'area'} );
    return $self;
}

sub area {
    my $self = shift;
    if (@_) {
        $self->{AREA} = shift;
    } elsif ( !$self->{AREA} ) {
        my $res = $self->request( GET => $conf->{'Uris'}{'Area'} )->call();
        if ( $res->decoded_content =~ m{<span class="(?<code>[^"]+)">(?<name>[^<]+)</span>} ) {
            $self->{AREA} = $+{code};
        }
    }
    return $self->{AREA};
}

sub getPrograms {
    my $self     = shift;
    my $t        = localtime;
    my @programs = ();
    for ( my $i = 0; $i < 7; ++$i, $t += ONE_DAY ) {
        sleep(1);
        my $infos = $self->getInfos(
            api  => 'ProgramsByArea',
            date => $t->ymd(''),
            area => $self->area(),
        ) or next;
        my $progs   = $self->toPrograms($infos) or next;
        my $filered = $self->filter($progs)     or next;
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
    my $infos    = $self->getInfos(
        api     => 'ProgramsByStation',
        date    => $match->{'date'},
        station => $match->{'station'},
    ) or return;
    my $prog = $self->matchStart( $infos, $match->{'date'} . $match->{'time'} ) or return;
    return [ $self->toProgram($prog) ];
}

sub getInfos {
    my $self  = shift;
    my $param = {@_};
    my $res   = $self->request( GET => $conf->{'Uris'}{ $param->{'api'} }, $param )->call();
    if ( !$res->is_success || !$res->decoded_content ) {
        $self->log( $res->status_line . ': ' . $res->request->uri );
        return;
    }
    my $content = $res->decoded_content;

    # workaround for XML::Simple. 'name' and 'id' are special keyword.
    $content =~ s/<name>([^<]+)<\/name>/<station_name>$1<\/station_name>/g;
    $content =~ s/<prog\sid=/<prog prog_id=/g;
    $content =~ s/<meta\sname=/<meta meta_name=/g;
    my $raw = XMLin(
        $content,
        ForceArray => [ 'station', 'prog', 'meta', ],
        GroupTags  => {
            'stations' => 'station',
            'progs'    => 'prog',
            'metas'    => 'meta',
        },
        NormaliseSpace => 2,
    );
    return !$raw
        ? undef
        : $self->flattenPrograms($raw);
}

sub flattenPrograms {
    my $self        = shift;
    my $rawPrograms = shift or return;
    my $now         = Net::Recorder::TimePiece->new();
    my @programs    = ();
    foreach my $station ( keys( %{ $rawPrograms->{'stations'} } ) ) {
        my $stationName = $rawPrograms->{'stations'}{$station}{'station_name'};
        my $date        = $rawPrograms->{'stations'}{$station}{'progs'}{'date'};
        foreach my $p ( @{ $rawPrograms->{'stations'}{$station}{'progs'}{'prog'} } ) {
            $p->{'station'}      = $station;
            $p->{'station_name'} = $stationName;
            $p->{'date'}         = $date;
            push( @programs, $p );
        }
    }
    return !@programs
        ? undef
        : [@programs];
}

sub matchStart {
    my $self        = shift;
    my $rawPrograms = shift or return;
    my $start       = shift or return;
    return first { $_->{'ft'} eq $start } @{$rawPrograms};
}

sub toPrograms {
    my $self        = shift;
    my $rawPrograms = shift or return;
    return [ map { $self->toProgram($_); } @{$rawPrograms} ];
}

sub toProgram {
    my $self = shift;
    my $p    = shift or return;
    while ( $p->{'desc'} =~ s{^<br\s?/>}{}g ) { }
    $p->{'desc'} =~ s{\\"}{"}g;
    my $start = $self->toDateTime( $p->{'ft'} );
    my $end   = $self->toDateTime( $p->{'to'} );
    my $title = normalizeSubtitle( $self->toText( $p->{'title'} ) );
    my $sha2  = new Digest::SHA2;
    $sha2->add( $p->{'station'}, $start, $end, $title );
    return Net::Recorder::Program->new(
        Provider => $self->name(),
        ID       => $self->toText( $sha2->b64digest() ),    # $p->{'prog_id'} is not rigid
        Extra    => {
            Station     => $p->{'station'},
            StationName => $p->{'station_name'},
            Date        => $p->{'date'},
            DateTime    => $p->{'ft'},
        },
        Start       => $start,
        End         => $end,
        Duration    => $self->toText( $p->{'dur'} ),
        Title       => $title,
        Description => $self->toText( $p->{'desc'} ),
        Info        => $self->toText( $p->{'info'} ),
        Performer   => $self->toText( $p->{'pfm'} ),
        Uri         => $self->toText( $p->{'url'} ),
    );
}

sub toDateTime {
    my $self     = shift;
    my $datetime = shift or return;
    return
          $datetime =~ s/^(\d{4})(\d{2})(\d{2})$/$1-$2-$3/                               ? $datetime
        : $datetime =~ s/^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/$1-$2-$3 $4:$5:$6/ ? $datetime
        :             $datetime;
}

sub toText {
    my $self  = shift;
    my $value = shift or return '';
    return ref($value) eq 'HASH'
        ? ''
        : $value;
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
    my $sleep   = ( $start - $now )->seconds;
    if ( $sleep > 0 ) { sleep($sleep); }
    my $station = $program->Extra()->Station();
    my $detail  = $self->matchStart(
        $self->getInfos(
            api     => 'ProgramsByStation',
            date    => $program->Extra()->Date(),
            station => $station,
        ),
        $program->Extra()->DateTime()
    ) || $program;
    my $fnameBase   = join( " ", $program->Title(), $station );
    my $fnameDetail = join( " ", $fnameBase,        $start->toPostfix() );
    DumpFile( "${dest}/${fnameDetail}.yml", $detail );
    $program->Status('RECORDING');
    $self->setStatus( $dbh, $program );
    $program->Status('FAILED');
    my $success = 0;

    while (1) {
        $start = Net::Recorder::TimePiece->new();
        my $duration = ( $end - $start )->seconds;
        if ( $duration < 0 ) { last; }
        my $fname      = join( " ", $fnameBase, $start->toPostfix() ) . '.m4a';
        my $pathWork   = "${dest}/.${fname}";
        my $pathFinish = "${dest}/${fname}";
        my $authToken  = $self->getAuthToken()          or next;
        my $streamUris = $self->getStreamUris($station) or next;
        my $streamUri  = (
            first {
                index( $_->{'playlist_create_url'}, $station ) >= 0
                    && $_->{'timefree'} == 0
                    && $_->{'areafree'} == 0
            }
            @{$streamUris}
        ) or next;
        my $cmd = sprintf(
            '%s -y -headers %sX-Radiko-AuthToken: %s%s -i %s%s%s -t %d -c copy -movflags faststart %s%s%s',
            $ffmpeg, QUOTE, $authToken, QUOTE, QUOTE, $streamUri->{'playlist_create_url'},
            QUOTE,   $duration + 60,
            QUOTE,   $pathWork, QUOTE
        );
        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
            = run( command => $cmd, verbose => 0, timeout => 120 * 60 );
        my $messages = integrateErrorMessages( $error_message, $stdout_buf, $stderr_buf );

        if ( !( -f $pathWork ) ) {
            $self->log( $messages->{'All'} );
            $self->log("Failed to get stream");
            return 0;
        }
        chmod( 0666, $pathWork );
        rename( $pathWork, $pathFinish );
        $success = 1;
        $program->Status('DONE');
    }
    return $success;
}

sub getAuthToken {
    my $self = shift;
    my $res1 = $self->request(
        GET => $conf->{'Uris'}{'Auth1'},
        undef,
        $conf->{'AuthHeaders'},
    )->call();
    if ( !$res1->is_success ) {
        $self->log( 'Failed Auth1: ' . $res1->status_line );
        return;
    }
    my $authToken  = $res1->header('X-RADIKO-AUTHTOKEN');
    my $keyOffset  = $res1->header('X-Radiko-KeyOffset');
    my $keyLength  = $res1->header('X-Radiko-KeyLength');
    my $tmpAuthKey = substr( $conf->{'AuthKey'}, $keyOffset, $keyLength );
    my $partialKey = decode( 'utf8', encode_base64( encode( 'utf8', $tmpAuthKey ) ) );
    my $header2    = {
        'X-Radiko-AuthToken'  => $authToken,
        'X-Radiko-PartialKey' => $partialKey,
        'X-Radiko-Device'     => 'pc',
        'X-Radiko-User'       => 'dummy_user',
    };
    my $res2 = $self->request(
        GET => $conf->{'Uris'}{'Auth2'},
        undef,
        $header2,
    )->call();

    if ( !$res2->is_success ) {
        $self->log( 'Failed Auth2: ' . $res2->status_line );
        return;
    }
    return $authToken;
}

sub getStreamUris {
    my $self    = shift;
    my $station = shift or return;
    my $res     = $self->request(
        GET => $conf->{'Uris'}{'Streams'},
        {   App     => 'pc_html5',
            Station => $station,
        },
    )->call();
    if ( !$res->is_success ) {
        $self->log( 'Failed to get stream: ' . $res->status_line );
        return;
    }
    my $urls = XMLin(
        $res->decoded_content,
        ForceArray => [ 'url', ],
        GroupTags  => { 'urls' => 'url', },
    );
    return !$urls
        ? undef
        : $urls->{'url'};
}

package Net::Recorder::Program::Extra::radiko;
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

__PACKAGE__->keysShort( 'Station', );

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    bless( $self, $class );
    return $self;
}

sub Station {
    my $self = shift;
    if (@_) { $self->{Station} = shift; }
    return $self->{Station};
}

sub StationName {
    my $self = shift;
    if (@_) { $self->{StationName} = shift; }
    return $self->{StationName};
}

sub Date {
    my $self = shift;
    if (@_) { $self->{Date} = shift; }
    return $self->{Date};
}

sub DateTime {
    my $self = shift;
    if (@_) { $self->{DateTime} = shift; }
    return $self->{DateTime};
}

1;
