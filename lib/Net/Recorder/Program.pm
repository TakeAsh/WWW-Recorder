package Net::Recorder::Program;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use Scalar::Util qw( reftype );
use overload '""' => \&stringify;
use FindBin::libs;
use Net::Recorder::Util;
use Net::Recorder::TimePiece;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

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
    my $args = Net::Recorder::Util::fromString($text);
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
        $self->{Extra} = Net::Recorder::Program::Extra->new(@_);
    }
    return $self->{Extra};
}

sub Start {
    my $self = shift;
    if (@_) {
        $self->{Start} = Net::Recorder::TimePiece->new(@_);
    }
    return $self->{Start};
}

sub End {
    my $self = shift;
    if (@_) {
        $self->{End} = Net::Recorder::TimePiece->new(@_);
    }
    return $self->{End};
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
        $self->{Title} = normalizeSubtitle(shift);
    }
    return $self->{Title};
}

sub Description {
    my $self = shift;
    if (@_) {
        $self->{Description} = shift;
    }
    return $self->{Description};
}

sub Info {
    my $self = shift;
    if (@_) {
        $self->{Info} = shift;
    }
    return $self->{Info};
}

sub Performer {
    my $self = shift;
    if (@_) {
        $self->{Performer} = shift;
    }
    return $self->{Performer};
}

sub Uri {
    my $self = shift;
    if (@_) {
        $self->{Uri} = shift;
    }
    return $self->{Uri};
}

sub Status {
    my $self = shift;
    if (@_) {
        $self->{Status} = shift;
    }
    return $self->{Status};
}

sub Keyword {
    my $self = shift;
    if (@_) {
        $self->{Keyword} = shift;
    }
    return $self->{Keyword};
}

sub stringify {
    my $self = shift;
    return Net::Recorder::Util::stringify( { %{$self} } );
}

sub keys {
    my $self = shift;
    return sort( grep { !startsWith( $_, '_' ) } keys( %{$self} ) );
}

package Net::Recorder::Program::Extra;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use Scalar::Util qw( reftype );
use overload '""' => \&stringify;
use FindBin::libs;
use Net::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

sub new {
    my $class = shift;
    my $self  = {};
    bless( $self, $class );
    if ( @_ >= 2 ) {
        $self->add( {@_} );
    } elsif ( ( reftype( $_[0] ) || '' ) eq 'HASH' ) {
        $self->add( $_[0] );
    } else {
        $self->parse( $_[0] );
    }
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
    my $args = Net::Recorder::Util::fromString(
        $text,
        ITEM_SEPARATOR   => qr/;\s*/,
        KEYVAL_SEPARATOR => qr/=/,
    );
    $self->add($args);
}

sub stringify {
    my $self = shift;
    return Net::Recorder::Util::stringify(
        { %{$self} },
        ITEM_SEPARATOR   => '; ',
        KEYVAL_SEPARATOR => '=',
    );
}

sub keys {
    my $self = shift;
    return sort( grep { !startsWith( $_, '_' ) } keys( %{$self} ) );
}

1;
