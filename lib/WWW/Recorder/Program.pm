package WWW::Recorder::Program;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use Const::Fast;
use YAML::Syck   qw(LoadFile Dump);
use Scalar::Util qw( reftype );
use overload '""' => \&stringify;
use FindBin::libs;
use WWW::Recorder::Util;
use WWW::Recorder::TimePiece;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

const my @validStatuses => qw(RECORDING STANDBY WAITING DONE ABORT FAILED NO_INFO);

sub new {
    my $class = shift;
    my $self  = { Status => 'WAITING', };
    bless( $self, $class );
    if ( @_ >= 2 ) {
        $self->add( {@_} );
    } elsif ( ( reftype( $_[0] ) || '' ) eq 'HASH' ) {
        $self->add( $_[0] );
    } else {
        $self->parse( $_[0] );
    }
    if ( exists( $self->{'Extra'} ) ) { $self->Extra( $self->{'Extra'} ); }
    if ( exists( $self->{'Start'} ) ) { $self->Start( $self->{'Start'} ); }
    if ( exists( $self->{'End'} ) )   { $self->End( $self->{'End'} ); }
    if ( $self->Start() && $self->End() && !exists( $self->{'Duration'} ) ) {
        $self->Duration( ( $self->End() - $self->Start() )->seconds );
    }
    if ( $self->Start() && $self->Duration() && !exists( $self->{'End'} ) ) {
        $self->End( $self->Start() + $self->Duration() );
    }
    if ( exists( $self->{'Title'} ) ) { $self->Title( $self->{'Title'} ); }
    return $self;
}

sub add {
    my $self = shift;
    my $args = shift or return;
    map { $self->{$_} = $args->{$_}; } keys( %{$args} );
}

sub parse {
    my $self = shift;
    my $text = shift or return;
    my $args = WWW::Recorder::Util::fromString($text);
    $self->add($args);
}

sub Provider {
    my $self = shift;
    if (@_) {
        $self->{Provider} = shift;
    }
    return $self->{Provider};
}

sub ID {
    my $self = shift;
    if (@_) {
        $self->{ID} = shift;
    }
    return $self->{ID};
}

sub Extra {
    my $self = shift;
    if (@_) {
        my $package = "WWW::Recorder::Program::Extra::$self->{Provider}";
        $self->{Extra}
            = !$self->{Provider}
            ? WWW::Recorder::Program::Extra->new(@_)
            : $package->new(@_);
    }
    return $self->{Extra};
}

sub Start {
    my $self = shift;
    if (@_) {
        $self->{Start} = WWW::Recorder::TimePiece->new(@_)
            or croak( "Invalid data: " . join( ", ", @_ ) );
    }
    return $self->{Start};
}

sub StartDate {
    my $self = shift;
    return $self->{Start} ? $self->{Start}->ymd : '';
}

sub StartTime {
    my $self = shift;
    return $self->{Start} ? $self->{Start}->strftime('%H:%M') : '';
}

sub End {
    my $self = shift;
    if (@_) {
        $self->{End} = WWW::Recorder::TimePiece->new(@_)
            or croak( "Invalid data: " . join( ", ", @_ ) );
    }
    return $self->{End};
}

sub EndDate {
    my $self = shift;
    return $self->{End} ? $self->{End}->ymd : '';
}

sub EndTime {
    my $self = shift;
    return $self->{End} ? $self->{End}->strftime('%H:%M') : '';
}

sub Duration {
    my $self = shift;
    if (@_) {
        $self->{Duration} = shift;
    }
    return $self->{Duration};
}

sub Title {
    my $self = shift;
    if (@_) {
        my $arg = shift;
        if ( ref($arg) eq 'ARRAY' ) {
            my $title   = shift( @{$arg} );
            my $options = { @{$arg} };
            $self->{Title} = normalizeSubtitle( $title, $options->{'Handler'} );
        } else {
            $self->{Title} = normalizeSubtitle($arg);
        }
    }
    return $self->{Title} || '';
}

sub TitleLimited {
    my $self = shift;
    return trimTextInBytes( $self->{Title} || '', 250 );    # Linux filename limit
}

sub Description {
    my $self = shift;
    if (@_) {
        $self->{Description} = shift;
    }
    return $self->{Description} || '';
}

sub Info {
    my $self = shift;
    if (@_) {
        $self->{Info} = shift;
    }
    return $self->{Info} || '';
}

sub Performer {
    my $self = shift;
    if (@_) {
        $self->{Performer} = shift;
    }
    return $self->{Performer} || '';
}

sub Uri {
    my $self = shift;
    if (@_) {
        $self->{Uri} = shift;
    }
    return $self->{Uri} || '';
}

sub Status {
    my $self = shift;
    if (@_) {
        my $state = shift;
        if ( !grep { $state eq $_ } @validStatuses ) {
            croak("Invalid status: $state");
        }
        $self->{Status} = $state;
    }
    return $self->{Status} || '';
}

sub Keyword {
    my $self = shift;
    if (@_) {
        $self->{Keyword} = shift;
    }
    return $self->{Keyword} || '';
}

sub stringify {
    my $self = shift;
    return WWW::Recorder::Util::stringify( { %{$self} } );
}

sub keys {
    my $self = shift;
    return sort( grep { !startsWith( $_, '_' ) } keys( %{$self} ) );
}

1;
