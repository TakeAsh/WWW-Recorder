package WWW::Recorder::Provider::radiko;
use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use Time::Seconds;
use XML::Simple;
use MIME::Base64;
use IPC::Cmd   qw(can_run run);
use List::Util qw(first);
use Digest::SHA2;
use URI;
use File::Path    qw(rmtree);
use File::Slurper qw(write_text write_binary);
use FindBin::libs;
use WWW::Recorder::Util;
use WWW::Recorder::TimePiece;
use WWW::Recorder::Program;
use parent 'WWW::Recorder::Provider';

$YAML::Syck::ImplicitUnicode   = 1;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

my $conf = {
    Uris => {
        Area              => 'https://radiko.jp/area',
        ProgramsByArea    => 'https://radiko.jp/v3/program/date/{date}/{area}.xml',
        ProgramsByStation => 'https://radiko.jp/v3/program/station/date/{date}/{station}.xml',
        Check             => 'https://radiko.jp/ap/member/webapi/v2/member/login/check',
        Auth1             => 'https://radiko.jp/v2/api/auth1',
        Auth2             => 'https://radiko.jp/v2/api/auth2',
        Streams           => 'https://radiko.jp/v3/station/stream/{App}/{Station}.xml',
    },
    AuthKey     => 'bcd151073c03b352e1ef2fd66c32209da9ca0afa',
    AuthHeaders => {
        'X-Radiko-App'         => 'pc_html5',
        'X-Radiko-App-Version' => '0.0.1',
        'X-Radiko-Connection'  => 'wifi',
        'X-Radiko-Device'      => 'pc',
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
            qr{^https://radiko\.jp/(#!/ts/(?<station>[^/]+)/(?<date>\d{8})(?<time>\d{6})|share/\?sid=(?<station2>[^&]+)&t=(?<date2>\d{8})(?<time2>\d{6}))\b},
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
        my $progs    = $self->toPrograms($infos) or next;
        my $filtered = $self->filter($progs)     or next;
        push( @programs, @{$filtered} );
    }
    return !@programs
        ? undef
        : [@programs];
}

sub getProgramsFromUri {
    my $self  = shift;
    my $index = shift                                 or return;
    my $total = shift                                 or return;
    my $uri   = shift                                 or return;
    my $match = shift                                 or return;
    my $prog  = $self->getProgramInfo( $uri, $match ) or return;
    return [$prog];
}

sub getProgramInfo {
    my $self  = shift;
    my $uri   = shift                                    or return;
    my $match = shift                                    or return;
    my $info  = $self->getProgramInfoRaw( $uri, $match ) or return;
    return $self->toProgram($info);
}

sub getProgramInfoRaw {
    my $self     = shift;
    my $uri      = shift or return;
    my $match    = shift or return;
    my $date     = $match->{'date'} || $match->{'date2'} || '';
    my $time     = $match->{'time'} || $match->{'time2'} || '';
    my $datetime = "${date}${time}";
    $date =~ s{(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})}{$+{y}-$+{m}-$+{d}};
    $date = WWW::Recorder::TimePiece->new($date);

    if ( '000000' le $time && $time lt '050000' ) {
        $date -= ONE_DAY;
    }
    my $infos = $self->getInfos(
        api     => 'ProgramsByStation',
        date    => $date->ymd(''),
        station => $match->{'station'} || $match->{'station2'} || '',
    ) or return;
    return $self->matchStart( $infos, $datetime );
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
    my $now         = WWW::Recorder::TimePiece->new();
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

sub makeFilenameRawBase {
    my $self  = shift;
    my $match = shift or return;
    return "$match->{station}_$match->{date}_$match->{time}";
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
    my $sha2  = new Digest::SHA2;
    $sha2->add( $p->{'station'}, $start, $end );
    return WWW::Recorder::Program->new(
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
        Title       => $self->toText( $p->{'title'} ),
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
    my $dbh      = connectDB( $self->{CONF}{'DbInfo'} );
    my $index    = 0;
    foreach my $program (@programs) {
        ++$index;
        my $dest = getAvailableDisk('2GiB');
        if ( !$dest ) {
            $self->log(
                sprintf( "%d/%d\tDisk full: %s", $index, scalar(@programs), $program->Title() ) );
            $program->Status('WAITING');
            $self->setStatus( $dbh, $program );
            next;
        }
        $self->log( sprintf( "%d/%d\t%s", $index, scalar(@programs), $program->Title() ) );
        my $pid = fork;
        if ( !defined($pid) ) {
            $self->log("Failed to fork");
        } elsif ( !$pid ) {    # Child process
            my $dbhChild = connectDB( $self->{CONF}{'DbInfo'} );
            $program->Status('FAILED');
            $self->getStream( $dbhChild, $program, $dest );
            $self->setStatus( $dbhChild, $program );
            $dbhChild->disconnect;
            exit;
        }
    }
    $dbh->disconnect;
    while ( wait() >= 0 ) { sleep(1); }
}

sub getStream {
    my $self    = shift;
    my $dbh     = shift or return;
    my $program = shift or return;
    my $dest    = shift or return;
    my $now     = WWW::Recorder::TimePiece->new();
    my $start   = $program->Start();
    my $end     = $program->End();
    my $sleep   = ( $start - $now )->seconds;
    if ( $sleep > 0 ) { sleep($sleep); }
    my $extra   = $program->Extra();
    my $station = $extra->Station();
    my $detail  = $self->matchStart(
        $self->getInfos(
            api     => 'ProgramsByStation',
            date    => $extra->Date(),
            station => $station,
        ),
        $extra->DateTime()
    ) || $program;
    my $fnameBase   = join( " ", $program->Title(), $station );
    my $fnameDetail = join( " ", $fnameBase,        $start->toPostfix() );
    DumpFile( "${dest}/${fnameDetail}.yml", $detail );
    $program->Status('RECORDING');
    $self->setStatus( $dbh, $program );
    $program->Status('FAILED');
    my $success = 0;

    while (1) {
        $now = WWW::Recorder::TimePiece->new();
        my $duration = ( $end - $now )->seconds;
        if ( $duration < 0 ) { last; }
        if ( $duration >= 2 * 60 * 60 - 5 ) {    # over 2hr
            $duration = 1 * 60 * 60;             # limit 1hr
        }
        my $dirWork = "${dest}/" . join( '_', $self->name, $extra->Station, $now->toPostfix('_') );
        if ( !( -d $dirWork ) ) {
            mkdir($dirWork) or die("Failed to make directory '${dirWork}': $!");
        }
        my $fname       = join( " ", $fnameBase, $now->toPostfix() ) . '.m4a';
        my $pathWork    = "${dest}/.${fname}";
        my $pathFinish  = "${dest}/${fname}";
        my $authToken   = $self->getAuthToken()         or next;
        my $streamUri   = $self->getStreamUri($station) or next;
        my $playlistUri = $self->makePlaylistUri( $station, $authToken, $streamUri, $start, $end );
        my $res         = $self->request(
            GET => $playlistUri->{'UriFull'},
            undef,
            $playlistUri->{'Headers'},
        )->call();

        if ( !$res->is_success ) {
            $self->log( 'Failed to get playlist: ' . $res->decoded_content );
            return 0;
        }
        my @uriMedia = grep { !startsWith( $_, '#' ) } split( "\n", $res->decoded_content );
        my %medias   = ();
        while ( ( $now = WWW::Recorder::TimePiece->new() ) < ( $end + 1.5 * ONE_MINUTE ) ) {
            $res = $self->request(
                GET => $uriMedia[0] . '&_=' . $now->epoch . '999',
                undef,
                $playlistUri->{'Headers'},
            )->call();
            if ( !$res->is_success ) { last; }
            my @medias2 = split( "\n", $res->decoded_content );
            while ( my $media3 = $self->getMediaInfo( \@medias2 ) ) {
                if ( exists $medias{ $media3->{'Datetime'} } ) { next; }
                $medias{ $media3->{'Datetime'} } = $media3;
                $res = $self->request(
                    GET => $media3->{'Uri'},
                    undef,
                    $playlistUri->{'Headers'},
                )->call();
                if ( $res->is_success ) {
                    write_binary( "${dirWork}/$media3->{File}", $res->content );
                }
            }
            sleep(5);
        }
        if ( scalar(%medias) <= 0 ) { next; }
        my $fnameList = "${dirWork}/files.txt";
        my $medialist
            = join( "\n", map { "file ${dirWork}/" . $medias{$_}{'File'} } sort( keys(%medias) ) )
            . "\n";
        write_text( $fnameList, $medialist );
        my $cmd = sprintf( '%s -y -f concat -safe 0 -i %s -c copy -movflags faststart %s',
            $ffmpeg, sysQuote($fnameList), sysQuote($pathWork) );
        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
            = run( command => $cmd, verbose => 0, timeout => 120 * 60 );
        my $messages = integrateErrorMessages( $error_message, $stdout_buf, $stderr_buf );

        if ($success) {
            rmtree($dirWork);
        }
        if ( !( -f $pathWork ) ) {
            $self->log( "Failed to get stream", $messages->{'All'} );
            return 0;
        }
        chmod( 0666, $pathWork );
        rename( $pathWork, $pathFinish );
        $success = 1;
        $program->Status('DONE');
    }
    return $success;
}

sub getMediaInfo {
    my $self  = shift;
    my $media = shift or return undef;
    while ( my $line = shift( @{$media} ) ) {
        if ( !startsWith( $line, '#EXT-X-PROGRAM-DATE-TIME:' ) ) { next; }
        unshift( @{$media}, $line );
        last;
    }
    if ( !@{$media} ) { return undef; }
    my $datetime = trim( shift( @{$media} ) );
    my $len      = trim( shift( @{$media} ) );
    my $uri      = trim( shift( @{$media} ) );
    $datetime =~ s{^#EXT-X-PROGRAM-DATE-TIME:}{};
    $len      =~ s{^#EXTINF:}{};
    $uri      =~ m{(?<file>[^\/]+)$};
    return {
        Datetime => $datetime,
        Len      => $len,
        Uri      => $uri,
        File     => $+{'file'},
    };
}

sub getAuthToken {
    my $self    = shift;
    my $userId  = $self->generateUserId();
    my $headers = { %{ $conf->{'AuthHeaders'} }, 'X-Radiko-User' => $userId, };
    my $res1    = $self->request(
        GET => $conf->{'Uris'}{'Check'},
        undef,
        $headers,
    )->call();
    my $session = '';
    my @cookies = $res1->header('Set-Cookie');
    foreach my $c (@cookies) {
        if ( $c =~ /radiko_session=(?<Session>[^;]+)/ ) {
            $session = $+{'Session'};
            last;
        }
    }
    my $res2 = $self->request(
        GET => $conf->{'Uris'}{'Auth1'},
        undef,
        $headers,
    )->call();
    if ( !$res2->is_success || $res2->code != 200 ) {
        $self->log( 'Failed Auth1: ' . $res2->status_line . ', ' . $res2->decoded_content );
        return;
    }
    my $authToken  = $res2->header('X-Radiko-Authtoken');
    my $keyOffset  = $res2->header('X-Radiko-KeyOffset');
    my $keyLength  = $res2->header('X-Radiko-KeyLength');
    my $tmpAuthKey = substr( $conf->{'AuthKey'}, $keyOffset, $keyLength );
    my $partialKey = trim( decode( 'utf8', encode_base64( encode( 'utf8', $tmpAuthKey ) ) ) );
    $headers = {
        %{$headers},
        'X-Radiko-AuthToken'  => $authToken,
        'X-Radiko-PartialKey' => $partialKey,
        'X-Radiko-Session'    => $session,
    };
    my $res3 = $self->request(
        GET => $conf->{'Uris'}{'Auth2'},
        undef,
        $headers,
    )->call();

    if ( !$res3->is_success || $res3->code != 200 ) {
        $self->log( 'Failed Auth2: ' . $res3->status_line . ', ' . $res3->decoded_content );
        return;
    }
    $res3->decoded_content =~ /(?<Id>[^,]+),(?<NameJp>[^,]+),(?<NameEn>[^,]+?)\s*$/;
    return { User => $userId, Token => $authToken, Area => {%+}, };
}

sub generateUserId {
    my $self   = shift;
    my $hex    = '0123456789abcdef';
    my $lenHex = length($hex);
    my $lenId  = 32;
    return join( '', map { substr( $hex, int( rand($lenHex) ), 1 ) } ( 0 .. ( $lenId - 1 ) ) );
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

sub getStreamUri {
    my $self       = shift;
    my $station    = shift                          or return;
    my $streamUris = $self->getStreamUris($station) or return;
    my $streamUri  = first {
               $_->{'timefree'} == 0
            && $_->{'areafree'} == 0
            && ( index( $_->{'playlist_create_url'}, 'smartstream.ne.jp' ) >= 0 )
    } @{$streamUris};
    return $streamUri && $streamUri->{'playlist_create_url'};
}

sub makePlaylistUri {
    my $self      = shift;
    my $station   = shift or return;
    my $authToken = shift or return;
    my $streamUri = shift or return;
    my $start     = shift or return;
    my $end       = shift or return;
    $start = $start->strftime('%Y%m%d%H%M00');
    $end   = $end->strftime('%Y%m%d%H%M00');
    my $uri   = URI->new($streamUri);
    my $query = {
        l          => 15,
        type       => 'b',
        lsid       => $authToken->{'User'},
        station_id => $station,
        start_at   => $start,
        ft         => $start,
        end_at     => $end,
        to         => $end,
        preroll    => 2,
    };
    $uri->query_form( %{$query} );
    my $h = {
        Host                 => $uri->host(),
        Origin               => 'https://radiko.jp',
        Referer              => 'https://radiko.jp/',
        'X-Radiko-AreaId'    => $authToken->{'Area'}{'Id'} || '',
        'X-Radiko-AuthToken' => $authToken->{'Token'}      || '',
    };
    my $flatten = join( "\r\n", map {"$_: $h->{$_}"} sort( keys( %{$h} ) ) );    # for ffmpeg
    return {
        Uri            => $streamUri,
        Query          => $query,
        UriFull        => "$uri",
        Headers        => $h,
        FlattenHeaders => $flatten,
    };
}

package WWW::Recorder::Program::Extra::radiko;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use FindBin::libs;
use parent 'WWW::Recorder::Program::Extra';
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
