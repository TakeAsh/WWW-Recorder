package WWW::Recorder::Provider::radiru;
use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use Time::Seconds;
use XML::Simple;
use IPC::Cmd   qw(can_run run);
use List::Util qw(first);
use FindBin::libs;
use WWW::Recorder::Util;
use WWW::Recorder::TimePiece;
use WWW::Recorder::Program;
use parent 'WWW::Recorder::Provider';

$YAML::Syck::ImplicitUnicode   = 1;
$XML::Simple::PREFERRED_PARSER = 'XML::Parser';

my $ffmpeg = can_run('ffmpeg') or die("ffmpeg is not found");

sub new {
    my $class  = shift;
    my $params = {@_};
    my $self   = $class->SUPER::_new(
        %{$params},
        name            => 'radiru',
        program_pattern =>
            qr{\b(?<broadcastEventId>(?<service>r1|r2|r3)-(?<area>\d{3})-(?<y>\d{4})(?<m>\d{2})(?<d>\d{2})(?<id>\d+))\b},
    );
    $self->{SERVICES} = WWW::Recorder::Provider::radiru::Services->new();
    bless( $self, $class );
    return $self;
}

sub ConfigWeb {
    my $self = shift;
    if ( !$self->{CONFIG_WEB} ) {
        $self->{CONFIG_WEB} = WWW::Recorder::Provider::radiru::ConfigWeb->new();
    }
    return $self->{CONFIG_WEB};
}

sub Services {
    my $self = shift;
    return $self->{SERVICES};
}

sub getPrograms {
    my $self      = shift;
    my $configWeb = $self->ConfigWeb();
    my @areas     = reverse( $configWeb->Areas()->getListByApiKey() );
    my @services  = $self->Services()->getList();
    my %programs  = ();
    foreach my $area (@areas) {
        foreach my $service (@services) {
            my $t = my $now = localtime;
            $t += ONE_DAY * 6;
            for ( my $i = 0; $i < 7; ++$i, $t -= ONE_DAY ) {
                sleep(1);
                my $programDay = $self->getProgramDay( $area, $service, $t->ymd('-') ) or next;
                my @prog       = grep { $_->End() > $now }
                    map {
                    $_->{'identifierGroup'}{'areaName'} ||= $area->{'areajp'};
                    $self->toProgram($_);
                    }
                    reverse( @{ $programDay->{ $service->{'Service'} }{'publication'} } )
                    or next;
                my $prog = $self->filter( [@prog] ) or next;
                map { $programs{ $_->{'ID'} } = $_; } @{$prog};
            }
        }
    }
    my @keys = keys(%programs);
    return !@keys
        ? undef
        : [ map { $programs{$_} } @keys ];
}

sub getProgramsFromUri {
    my $self    = shift;
    my $index   = shift or return;
    my $total   = shift or return;
    my $uri     = shift or return;
    my $match   = shift or return;
    my $program = $self->getProgramInfo( $uri, $match );
    return !$program
        ? undef
        : [$program];
}

sub getProgramDay {
    my $self    = shift;
    my $area    = shift or return;
    my $service = shift or return;
    my $date    = shift or return;
    my $res     = $self->request(
        GET => $self->ConfigWeb()->UrlProgramDay(),
        { area => $area->{'areakey'}, service => $service->{'Service'}, date => $date, }
    )->call();
    if ( !$res->is_success || !$res->decoded_content ) {
        $self->log( $res->status_line . ': ' . $res->request->uri );
        return;
    }
    return decodeJson( decodeUtf8( $res->decoded_content ) );
}

sub getProgramInfo {
    my $self      = shift;
    my $uri       = shift                                    or return;
    my $match     = shift                                    or return;
    my $videoInfo = $self->getProgramInfoRaw( $uri, $match ) or return;
    return $self->toProgram($videoInfo);
}

sub getProgramInfoRaw {
    my $self    = shift;
    my $uri     = shift or return;
    my $match   = shift or return;
    my $service = $self->Services()->ByService( $match->{'service'} );
    return $self->getProgramDetail( { %{$match}, service => $service, } );
}

sub getProgramDetail {
    my $self  = shift;
    my $param = shift;
    my $res   = $self->request( GET => $self->ConfigWeb()->UrlProgramDetail(), $param )->call();
    if ( !$res->is_success || !$res->decoded_content ) {
        $self->log( $res->status_line . ': ' . $res->request->uri );
        return;
    }
    my $detail = decodeJson( decodeUtf8( $res->decoded_content ) ) or return;
    return $detail;
}

sub makeFilenameRawBase {
    my $self  = shift;
    my $match = shift or return;
    return "$match->{channel}_$match->{y}$match->{m}$match->{d}_$match->{area}";
}

sub toProgram {
    my $self         = shift;
    my $d            = shift or return;
    my $idGroup      = $d->{'identifierGroup'};
    my $partOfSeries = $d->{'about'}{'partOfSeries'};
    my $id           = joinValid( "-", $idGroup->{'radioSeriesId'}, $idGroup->{'radioEpisodeId'} )
        || $d->{'id'};
    $d->{'startDate'} =~ s/([-+])(\d{2}):(\d{2})$//;    # drop timezone, force localtime
    $d->{'endDate'}   =~ s/([-+])(\d{2}):(\d{2})$//;
    my $start     = WWW::Recorder::TimePiece->strptime( $d->{'startDate'}, '%Y-%m-%dT%H:%M:%S' );
    my $end       = WWW::Recorder::TimePiece->strptime( $d->{'endDate'},   '%Y-%m-%dT%H:%M:%S' );
    my $service   = $self->Services()->ByService( $idGroup->{'serviceId'} );
    my $seriesUri = $partOfSeries->{'canonical'} || $partOfSeries->{'sameAs'}[0]{'url'};
    return WWW::Recorder::Program->new(
        Provider => $self->name(),
        ID       => $id,
        Extra    => {
            Id             => $d->{'id'},
            SeriesId       => $idGroup->{'radioSeriesId'},
            SeriesName     => $idGroup->{'radioSeriesName'} || $partOfSeries->{'sameAs'}[0]{'name'},
            SeriesUri      => $seriesUri,
            EpisodeId      => $idGroup->{'radioEpisodeId'},
            EpisodeName    => $idGroup->{'radioEpisodeName'},
            AreaId         => $idGroup->{'areaId'},
            AreaName       => $idGroup->{'areaName'},
            ServiceId      => $idGroup->{'serviceId'},
            ServiceChannel => $service->{'Channel'},
        },
        Start    => $start,
        End      => $end,
        Duration => ( $end - $start )->seconds,
        Title    => joinValid( " ", $idGroup->{'radioSeriesName'}, $idGroup->{'radioEpisodeName'} )
            || $d->{'name'},
        Description => joinValid( "\n", $d->{'about'}{'description'}, $d->{'description'} ),
        Info        => $self->flattenMusicList( $d->{'misc'}{'musicList'} ),
        Performer   => $self->flattenActList( $d->{'misc'}{'actList'} ),
        Uri         => $d->{'about'}{'canonical'}
            || $seriesUri
            || "https://www.nhk.or.jp/radio/hensei/detail.html?$d->{id}",
    );
}

sub flattenMusicList {
    my $self      = shift;
    my $musicList = shift or return;
    my $basic     = {
        lyricist => '作詞',
        composer => '作曲',
        arranger => '編曲',
    };
    return joinValid(
        "\n",
        map {
            my $info     = $_;
            my @artists1 = map { $basic->{$_} . ':' . $self->normalizeName( $info->{$_} ) }
                grep { $info->{$_} } qw(lyricist composer arranger);
            my @artists2
                = map { joinValid( ':', $_->{'part'}, $self->normalizeName( $_->{'name'} ) ); }
                @{ $info->{'byArtist'} };
            joinValid(
                " / ",
                normalizeTitle( $_->{'name'} ),
                joinValid( ", ", @artists1, @artists2 )
            );
        } @{$musicList}
    );
}

sub flattenActList {
    my $self    = shift;
    my $actList = shift or return;
    return joinValid(
        ", ",
        map {
            joinValid(
                ':',
                $self->normalizeName( $_->{'role'} ),
                $self->normalizeName( $_->{'name'} )
            )
        } @{$actList}
    );
}

sub normalizeName {
    my $self = shift;
    my $name = shift or return;
    $name =~ s/\x{3000}//;
    return normalizeTitle($name);
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
    my $extra  = $program->Extra();
    my $detail = $self->getProgramDetail(
        {   area    => $extra->AreaId(),
            service => $extra->ServiceId(),
            dateid  => $program->ID(),
        }
    ) || $program;
    my $fnameBase   = join( " ", $program->Title(), $extra->ServiceChannel() );
    my $fnameDetail = join( " ", $fnameBase,        $start->toPostfix() );
    DumpFile( "${dest}/${fnameDetail}.yml", $detail );
    $program->Status('RECORDING');
    $self->setStatus( $dbh, $program );
    $program->Status('FAILED');
    my $area      = $self->ConfigWeb()->Areas()->ByAreaKey( $extra->AreaId() ) or return;
    my $service   = $self->Services()->ByService( $extra->ServiceId() )        or return;
    my $streamUri = $area->{ $service->{'StreamKey'} }                         or return;
    my $success   = 0;

    while (1) {
        $start = WWW::Recorder::TimePiece->new();
        my $duration = ( $end - $start )->seconds;
        if ( $duration < 0 ) { last; }
        if ( $duration >= 2 * 60 * 60 - 5 ) {    # over 2hr
            $duration = 1 * 60 * 60;             # limit 1hr
        }
        my $fname      = join( " ", $fnameBase, $start->toPostfix() );
        my $pathWork   = "${dest}/.${fname}.m4a";
        my $pathFinish = "${dest}/${fname}.m4a";
        my $cmd        = sprintf(
            '%s -y -i %s -t %d -bsf:a aac_adtstoasc -c copy -movflags faststart %s',
            $ffmpeg, sysQuote($streamUri), $duration + 60,
            sysQuote($pathWork)
        );
        my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
            = run( command => $cmd, verbose => 0, timeout => 120 * 60 );
        my $messages = integrateErrorMessages( $error_message, $stdout_buf, $stderr_buf );

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

package WWW::Recorder::Provider::radiru::ConfigWeb;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use LWP::UserAgent;
use XML::Simple;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

my $confWeb = {
    Agent => 'Mozilla/5.0',
    Uris  => { config_web => 'https://www.nhk.or.jp/radio/config/config_web.xml', },
};

sub new {
    my $class = shift;
    my $agent = LWP::UserAgent->new(
        keep_alive            => 4,
        timeout               => 600,
        requests_redirectable => [ 'GET', 'HEAD', 'POST' ],
        agent                 => $confWeb->{'Agent'},
        cookie_jar            => {},
    );
    my $res = $agent->get( $confWeb->{'Uris'}{'config_web'} );
    if ( !$res->is_success || !$res->decoded_content ) {
        croak( $res->status_line . ': ' . $res->request->uri );
    }
    my $self = XMLin(
        $res->decoded_content,
        ForceArray     => [ 'data', ],
        GroupTags      => { 'stream_url' => 'data', },
        NormaliseSpace => 2,
    );
    $self->{AREAS} = WWW::Recorder::Provider::radiru::Areas->new( $self->{'stream_url'} );
    $self->{'url_program_day'} =~ s/\[YYYY-MM-DD\]/{date}/;
    $self->{URL_PROGRAM_DAY}    = 'https:' . $self->{'url_program_day'};
    $self->{URL_PROGRAM_DETAIL} = 'https:' . $self->{'url_program_detail'};
    bless( $self, $class );
    return $self;
}

sub Areas {
    my $self = shift;
    return $self->{AREAS};
}

sub UrlProgramDay {
    my $self = shift;
    return $self->{URL_PROGRAM_DAY};
}

sub UrlProgramDetail {
    my $self = shift;
    return $self->{URL_PROGRAM_DETAIL};
}

package WWW::Recorder::Provider::radiru::Areas;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck   qw(LoadFile DumpFile Dump);
use Scalar::Util qw(reftype);
use List::Util   qw(first);
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

sub ByAreaKey {
    my $self = shift;
    my $id   = shift or return;
    return first { $_->{'areakey'} eq $id } @{$self};
}

sub ByName {
    my $self = shift;
    my $name = shift or return;
    return first { $_->{'area'} eq $name } @{$self};
}

sub getListByApiKey {
    my $self = shift;
    return sort { $a->{'apikey'} <=> $b->{'apikey'} } @{$self};
}

package WWW::Recorder::Provider::radiru::Services;
use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use List::Util qw(first);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

my $confServices = {
    Services => [
        { Service => 'r1', Channel => 'r1', StreamKey => 'r1hls', },
        { Service => 'r2', Channel => 'r2', StreamKey => 'r2hls', },
        { Service => 'r3', Channel => 'fm', StreamKey => 'fmhls', },
    ],
};

sub new {
    my $class = shift;
    my $self  = $confServices->{'Services'},;
    bless( $self, $class );
    return $self;
}

sub ByService {
    my $self = shift;
    my $id   = shift or return;
    return first { $_->{'Service'} eq $id } @{$self};
}

sub ByChannel {
    my $self    = shift;
    my $channel = shift or return;
    return first { $_->{'Channel'} eq $channel } @{$self};
}

sub getList {
    my $self = shift;
    return @{$self};
}

package WWW::Recorder::Program::Extra::radiru;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use FindBin::libs;
use WWW::Recorder::Util;
use parent 'WWW::Recorder::Program::Extra';
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

__PACKAGE__->keysShort(
    'SeriesLink'     => 'Series',
    'AreaName'       => 'Area',
    'ServiceChannel' => 'Channel',
);

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    bless( $self, $class );
    if ( my $SeriesName = $self->{SeriesName} || $self->{SeriesTitle} ) {
        $self->SeriesName($SeriesName);
    }
    if ( $self->{SeriesUri} ) { $self->SeriesUri( $self->{SeriesUri} ); }
    if ( my $EpisodeName = $self->{EpisodeName} || $self->{SubTitle} ) {
        $self->EpisodeName($EpisodeName);
    }
    return $self;
}

sub SeriesId {
    my $self = shift;
    if (@_) { $self->{SeriesId} = shift; }
    return $self->{SeriesId} || '';
}

sub SeriesName {
    my $self = shift;
    if (@_) {
        $self->{SeriesName} = normalizeSubtitle(shift);
        $self->SeriesLink(1);
    }
    return $self->{SeriesName} || '';
}

sub SeriesUri {
    my $self = shift;
    if (@_) {
        $self->{SeriesUri} = shift;
        $self->SeriesLink(1);
    }
    return $self->{SeriesUri} || '';
}

sub SeriesLink {
    my $self = shift;
    if ( @_ && $self->{SeriesName} && $self->{SeriesUri} ) {
        $self->{SeriesLink}
            = "<a href=\"$self->{SeriesUri}\" data-link-type=\"Series\">$self->{SeriesName}</a>";
    }
    return $self->{SeriesLink} || '';
}

sub EpisodeId {
    my $self = shift;
    if (@_) { $self->{EpisodeId} = shift; }
    return $self->{EpisodeId} || '';
}

sub EpisodeName {
    my $self = shift;
    if (@_) { $self->{EpisodeName} = normalizeSubtitle(shift); }
    return $self->{EpisodeName} || '';
}

sub AreaId {
    my $self = shift;
    if (@_) { $self->{AreaId} = shift; }
    return $self->{AreaId} || '';
}

sub AreaName {
    my $self = shift;
    if (@_) { $self->{AreaName} = shift; }
    return $self->{AreaName} || '';
}

sub ServiceId {
    my $self = shift;
    if (@_) { $self->{ServiceId} = shift; }
    return $self->{ServiceId} || '';
}

sub ServiceChannel {
    my $self = shift;
    if (@_) { $self->{ServiceChannel} = shift; }
    return $self->{ServiceChannel} || '';
}

1;
