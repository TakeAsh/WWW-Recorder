package Net::Recorder::Provider::skeleton;
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

my $conf = {
    FormatId       => '%Y%m%d-%H%M00',
    FormatDateTime => '%Y/%m/%d %H:%M:00',
    Series         => 'Dummy',
    Thumb          => 'https://example.com/Dummy/thumb/%s_%02d.jpg',
    Uri            => 'https://example.com/Dummy/story/%s_%03d/',
};

#my $ffmpeg = can_run('ffmpeg') or die("ffmpeg is not found");

sub new {
    my $class  = shift;
    my $params = {@_};
    my $self   = $class->SUPER::_new(
        %{$params},
        name            => 'skeleton',
        program_pattern => qr{\bp1:\s*(?<p1>[^;]*);\s*p2:(?<p2>[^;]*)\b},
    );
    bless( $self, $class );
    return $self;
}

sub getPrograms {
    my $self = shift;
    return undef;
}

sub getProgramsFromUri {
    my $self     = shift;
    my $index    = shift or return;
    my $total    = shift or return;
    my $uri      = shift or return;
    my $match    = shift or return;
    my $now      = Net::Recorder::TimePiece->new();
    my $id       = $now->strftime( $conf->{'FormatId'} );
    my @programs = ();

    for ( my $i = 1; $i <= 3; ++$i ) {
        my $id2   = join( "/", $id, $match->{'p1'}, $match->{'p2'}, "000${i}" );
        my $uri   = sprintf( $conf->{'Uri'},   $match->{'p1'}, $i );
        my $thumb = sprintf( $conf->{'Thumb'}, $match->{'p2'}, $i );
        my $start = ( $now + ONE_MINUTE * ( $i * 3 + 10 ) )->strftime( $conf->{'FormatDateTime'} );
        my $end   = ( $now + ONE_MINUTE * ( $i * 3 + 11 ) )->strftime( $conf->{'FormatDateTime'} );
        push(
            @programs,
            Net::Recorder::Program->new(
                {   Provider => $self->name(),
                    ID       => $id2,
                    Extra    => {
                        series   => $conf->{'Series'},
                        sequence => $i,
                        thumb    => $thumb,
                    },
                    Start       => $start,
                    End         => $end,
                    Duration    => 60,
                    Title       => join( " ",      $conf->{'Series'}, "#${i}", $id2 ),
                    Description => join( "<br>\n", $id2,              $uri,    $thumb ),
                    Info        => undef,
                    Performer   => undef,
                    Uri         => $uri,
                }
            )
        );
    }
    return !@programs
        ? undef
        : [@programs];
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
    $program->Status('DOWNLOADING');
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

package Net::Recorder::Program::Extra::skeleton;
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

__PACKAGE__->keysShort( 'series' => undef, 'sequence' => 'Seq.', );

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new(@_);
    bless( $self, $class );
    if ( $self->{series} )   { $self->series( $self->{series} ); }
    if ( $self->{sequence} ) { $self->sequence( $self->{sequence} ); }
    if ( $self->{thumb} )    { $self->thumb( $self->{thumb} ); }
    return $self;
}

sub series {
    my $self = shift;
    if (@_) { $self->{series} = shift; }
    return $self->{series};
}

sub sequence {
    my $self = shift;
    if (@_) { $self->{sequence} = shift; }
    return $self->{sequence};
}

sub thumb {
    my $self = shift;
    if (@_) { $self->{thumb} = shift; }
    return $self->{thumb};
}

1;
