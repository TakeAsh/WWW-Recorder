package WWW::Recorder::Program::Extra;
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
use WWW::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

my $keysShort = {};

sub new {
    my $class = shift;
    my $self  = {
        _OPTIONS => {
            ITEM_SEPARATOR   => '; ',
            KEYVAL_SEPARATOR => '=',
        },
    };
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

sub keysShort {
    my $both  = shift;
    my $class = ( ref($both) || $both ) or return;
    if (@_) {
        $keysShort->{$class} = WWW::Recorder::Program::Extra::Keys->new(@_);
    }
    return $keysShort->{$class} || WWW::Recorder::Program::Extra::Keys->new();
}

sub add {
    my $self = shift;
    my $args = shift or return;
    map { $self->{$_} = $args->{$_}; } keys( %{$args} );
}

sub parse {
    my $self = shift;
    my $text = shift or return;
    my $args = WWW::Recorder::Util::fromString(
        $text,
        ITEM_SEPARATOR   => qr/;\s*/,
        KEYVAL_SEPARATOR => qr/=/,
    );
    $self->add($args);
}

sub stringify {
    my $self = shift;
    return WWW::Recorder::Util::stringify(
        { %{$self} },
        ITEM_SEPARATOR   => $self->{_OPTIONS}{ITEM_SEPARATOR},
        KEYVAL_SEPARATOR => $self->{_OPTIONS}{KEYVAL_SEPARATOR},
    );
}

sub stringifyShort {
    my $self = shift;
    return WWW::Recorder::Util::stringify(
        {   map  { $_ => $self->{$_}; }
            grep { exists( $self->{$_} ) } @{ ref($self)->keysShort()->getKeys() }
        },
        ITEM_SEPARATOR   => $self->{_OPTIONS}{ITEM_SEPARATOR},
        KEYVAL_SEPARATOR => $self->{_OPTIONS}{KEYVAL_SEPARATOR},
    );
}

sub keys {
    my $self = shift;
    return sort( grep { !startsWith( $_, '_' ) } keys( %{$self} ) );
}

package WWW::Recorder::Program::Extra::Keys;
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
use WWW::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

sub new {
    my $class = shift;
    my $self  = [];
    while ( my ( $key, $label ) = splice( @_, 0, 2 ) ) {
        push( @{$self}, { Key => $key, Label => $label || '', } );
    }
    bless( $self, $class );
    return $self;
}

sub stringify {
    my $self = shift;
    return join( "; ", map { $_->{'Key'} . '=>' . $_->{'Label'} } @{$self} );
}

sub getKeys {
    my $self = shift;
    return [ map { $_->{'Key'} } @{$self} ];
}

sub getLabels {
    my $self = shift;
    return [ map { $_->{'Label'} || $_->{'Key'} } @{$self} ];
}

1;
