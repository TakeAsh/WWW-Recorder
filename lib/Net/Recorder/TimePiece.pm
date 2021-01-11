package Net::Recorder::TimePiece;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use Time::Seconds;
use Scalar::Util qw( reftype );
use overload '""' => \&stringify;
use parent 'Time::Piece';
use FindBin::libs;
use Net::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

sub new {
    my $class = shift;
    my $t     = shift || '';
    $t =~ tr/\//-/;
    my $t2
        = !$t                                ? $class->SUPER::new()
        : $t =~ /^\d+:\d+$/                  ? $class->strptime( $t, '%M:%S' )
        : $t =~ /^\d+:\d+:\d+$/              ? $class->strptime( $t, '%H:%M:%S' )
        : $t =~ /^\d+-\d+-\d+$/              ? $class->strptime( $t, '%Y-%m-%d' )
        : $t =~ /^\d+-\d+-\d+\s\d+:\d+:\d+$/ ? $class->strptime( $t, '%Y-%m-%d %H:%M:%S' )
        :                                      croak("Must be '[yyyy-mm-dd] [HH:]MM:SS': ${t}");
    my $self = $class->localtime($t2);
    bless( $self, $class );
    return $self;
}

sub stringify {
    my $self = shift;
    return $self->strftime('%Y-%m-%d %H:%M:%S');
}

sub toPostfix {
    my $self = shift;
    return $self->strftime('%Y-%m-%d %H-%M');
}

1;
