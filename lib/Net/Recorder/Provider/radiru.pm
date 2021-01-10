package Net::Recorder::Provider::radiru;
use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use Time::Piece;
use Time::Seconds;
use XML::Simple;
use IPC::Cmd qw(can_run run QUOTE);
use List::Util qw(first);
use FindBin::libs;
use Net::Recorder::Util;
use Net::Recorder::Program;
use parent 'Net::Recorder::Provider';

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
            qr{\b(?<channel>r1|r2|fm)\.(?<id>\d+).(?<y>\d{4})-(?<m>\d{2})-(?<d>\d{2})\.(?<area>\d{3})\b},
    );
    $self->{SERVICES} = Net::Recorder::Provider::radiru::Services->new();
    bless( $self, $class );
    return $self;
}

sub ConfigWeb {
    my $self = shift;
    if ( !$self->{CONFIG_WEB} ) {
        $self->{CONFIG_WEB} = Net::Recorder::Provider::radiru::ConfigWeb->new();
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
            my $t = localtime;
            for ( my $i = 0; $i < 7; ++$i, $t += ONE_DAY ) {
                sleep(1);
                my $programDay = $self->getProgramDay( $area, $service, $t->ymd('-') ) or next;
                my $flattened  = $self->flattenPrograms($programDay)                   or next;
                my $prog       = $self->filter($flattened)                             or next;
                map { $programs{ $_->{'ID'} } = $_; } @{$prog};
            }
        }
    }
    my @keys = sort( keys(%programs) );
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
    my $service = $self->Services()->ByChannel( $match->{'channel'} )->{'Service'};
    my $detail  = $self->getProgramDetail(
        {   area    => $match->{'area'},
            service => $service,
            dateid  => join( "", $match->{'y'}, $match->{'m'}, $match->{'d'}, $match->{'id'} ),
        }
    );
    return !$detail
        ? undef
        : [ $self->toProgram($detail) ];
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
    return decodeJson( $res->decoded_content );
}

sub flattenPrograms {
    my $self        = shift;
    my $rawPrograms = shift or return;
    my $now         = Net::Recorder::TimePiece->new();
    my @programs    = ();
    foreach my $service ( keys( %{ $rawPrograms->{'list'} } ) ) {
        foreach my $detail ( @{ $rawPrograms->{'list'}{$service} } ) {
            my $program = $self->toProgram($detail);
            if ( $program->End() < $now ) { next; }
            push( @programs, $program );
        }
    }
    return !@programs
        ? undef
        : [@programs];
}

sub getProgramDetail {
    my $self  = shift;
    my $param = shift;
    my $res   = $self->request( GET => $self->ConfigWeb()->UrlProgramDetail(), $param )->call();
    if ( !$res->is_success || !$res->decoded_content ) {
        $self->log( $res->status_line . ': ' . $res->request->uri );
        return;
    }
    my $detail  = decodeJson( $res->decoded_content ) or return;
    my $service = ( keys( %{ $detail->{'list'} } ) )[0];
    return !$service
        ? $detail->{'list'}
        : $detail->{'list'}{$service}[0];
}

sub toProgram {
    my $self = shift;
    my $d    = shift or return;
    $d->{'start_time'} =~ s/([-+])(\d{2}):(\d{2})$//;    # drop timezone, force localtime
    $d->{'end_time'}   =~ s/([-+])(\d{2}):(\d{2})$//;
    my $start   = Net::Recorder::TimePiece->strptime( $d->{'start_time'}, '%Y-%m-%dT%H:%M:%S' );
    my $end     = Net::Recorder::TimePiece->strptime( $d->{'end_time'},   '%Y-%m-%dT%H:%M:%S' );
    my $desc    = join( "\n", grep {$_} map { $d->{$_} } qw(subtitle content music free rate) );
    my $channel = $self->Services()->ByService( $d->{'service'}{'id'} )->{'Channel'};
    return Net::Recorder::Program->new(
        Provider => $self->name(),
        ID       => $d->{'id'},
        Extra    => {
            AreaId         => $d->{'area'}{'id'},
            AreaName       => $d->{'area'}{'name'},
            ServiceId      => $d->{'service'}{'id'},
            ServiceName    => $d->{'service'}{'name'},
            ServiceChannel => $channel,
            SubTitle       => $d->{'subtitle'},
            Content        => $d->{'content'},
            Music          => $d->{'music'},
            Free           => $d->{'free'},
            Rate           => $d->{'rate'},
        },
        Start       => $start,
        End         => $end,
        Duration    => ( $end - $start )->seconds,
        Title       => $d->{'title'},
        Description => $desc,
        Info        => $d->{'info'},
        Performer   => $d->{'act'},
        Uri         => $d->{'url'}{'episode'},
    );
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
    my $now     = localtime;
    my $start   = $program->Start();
    my $end     = $program->End();
    my $sleep   = ( $start - $now )->seconds - 5;
    if ( $sleep > 0 ) { sleep($sleep); }
    my $detail = $self->getProgramDetail(
        {   area    => $program->Extra()->AreaId(),
            service => $program->Extra()->ServiceId(),
            dateid  => $program->ID(),
        }
    ) || $program;
    my $fnameBase   = join( " ", $program->Title(), $program->Extra()->ServiceChannel() );
    my $fnameDetail = join( " ", $fnameBase,        $start->toPostfix() );
    DumpFile( "${dest}/${fnameDetail}.yml", $detail );
    $program->Status('DOWNLOADING');
    $self->setStatus( $dbh, $program );
    $program->Status('FAILED');
    my $extra     = $program->Extra();
    my $area      = $self->ConfigWeb()->Areas()->ByAreaKey( $extra->AreaId() ) or return;
    my $service   = $self->Services()->ByService( $extra->ServiceId() )        or return;
    my $streamUri = $area->{ $service->{'StreamKey'} }                         or return;
    my $success   = 0;

    while (1) {
        $start = Net::Recorder::TimePiece->new();
        my $duration = ( $end - $start )->seconds;
        if ( $duration < 0 ) { last; }
        my $fname      = join( " ", $fnameBase, $start->toPostfix() );
        my $pathWork   = "${dest}/.${fname}.m4a";
        my $pathFinish = "${dest}/${fname}.m4a";
        my $cmd        = sprintf(
            '%s -y -i %s%s%s -t %d -bsf:a aac_adtstoasc -c copy -movflags faststart %s%s%s',
            $ffmpeg, QUOTE,     $streamUri, QUOTE, $duration + 60,
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

package Net::Recorder::Provider::radiru::ConfigWeb;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
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
    $self->{AREAS} = Net::Recorder::Provider::radiru::Areas->new( $self->{'stream_url'} );
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

package Net::Recorder::Provider::radiru::Areas;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use Scalar::Util qw( reftype );
use List::Util qw(first);
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

package Net::Recorder::Provider::radiru::Services;
use strict;
use warnings;
use utf8;
use feature qw( say );
use Encode;
use YAML::Syck qw( LoadFile DumpFile Dump );
use List::Util qw(first);
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

my $confServices = {
    Services => [
        { Service => 'n1', Channel => 'r1', StreamKey => 'r1hls', },
        { Service => 'n2', Channel => 'r2', StreamKey => 'r2hls', },
        { Service => 'n3', Channel => 'fm', StreamKey => 'fmhls', },
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

package Net::Recorder::Provider::radiru::Extra;
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

__PACKAGE__->keysShort( 'AreaName' => 'Area', 'ServiceChannel' => 'Channel', );

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    bless( $self, $class );
    return $self;
}

sub AreaId {
    my $self = shift;
    if (@_) { $self->{AreaId} = shift; }
    return $self->{AreaId};
}

sub AreaName {
    my $self = shift;
    if (@_) { $self->{AreaName} = shift; }
    return $self->{AreaName};
}

sub ServiceId {
    my $self = shift;
    if (@_) { $self->{ServiceId} = shift; }
    return $self->{ServiceId};
}

sub ServiceName {
    my $self = shift;
    if (@_) { $self->{ServiceName} = shift; }
    return $self->{ServiceName};
}

sub ServiceChannel {
    my $self = shift;
    if (@_) { $self->{ServiceChannel} = shift; }
    return $self->{ServiceChannel};
}

sub SubTitle {
    my $self = shift;
    if (@_) { $self->{SubTitle} = shift; }
    return $self->{SubTitle};
}

sub Content {
    my $self = shift;
    if (@_) { $self->{Content} = shift; }
    return $self->{Content};
}

sub Music {
    my $self = shift;
    if (@_) { $self->{Music} = shift; }
    return $self->{Music};
}

sub Free {
    my $self = shift;
    if (@_) { $self->{Free} = shift; }
    return $self->{Free};
}

sub Rate {
    my $self = shift;
    if (@_) { $self->{Rate} = shift; }
    return $self->{Rate};
}

1;
