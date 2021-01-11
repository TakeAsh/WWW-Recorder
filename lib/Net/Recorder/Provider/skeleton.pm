package Net::Recorder::Provider::skeleton;
use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile DumpFile Dump);
use IPC::Cmd qw(can_run run QUOTE);
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Util;
use Net::Recorder::Program;
use parent 'Net::Recorder::Provider';

$YAML::Syck::ImplicitUnicode = 1;

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
