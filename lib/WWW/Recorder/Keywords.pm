package WWW::Recorder::Keywords;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use Const::Fast;
use Scalar::Util qw(reftype);
use FindBin::libs;
use WWW::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

const my $file => 'Keywords';

sub new {
    my $class    = shift;
    my $keywords = shift;
    my $self     = {
        Hash   => {},
        HitReg => undef,
    };
    bless( $self, $class );
    $self->load();
    $self->add($keywords);
    return $self;
}

sub load {
    my $self = shift;
    $self->add( loadConfig($file) );
}

sub save {
    my $self = shift;
    my %hash = %{ $self->{Hash} };
    my @raw  = map { { Key => $_, Not => $hash{$_}{Not} } } @{ sortByUnicode( [ keys(%hash) ] ) };
    saveConfig( $file, [@raw] );
}

sub add {
    my $self     = shift;
    my $keywords = shift or return;
    if ( ( reftype($keywords) || '' ) ne 'ARRAY' ) {
        croak("Must be array");
    }
    my %hash = (
        %{ $self->{Hash} },
        map {
            my $item = $_;
            if ( my $not = $item->{Not} ) {
                my $patternNot = join( "|", map { quotemeta($_) } split( /\n/, $not ) );
                $item->{NotReg} = qr/$patternNot/;
            }
            $item->{Key} => $item;
        } @{$keywords}
    );
    my $patternHit = join( "|", map { quotemeta($_) } keys(%hash) );
    $self->{Hash}   = {%hash};
    $self->{HitReg} = qr/($patternHit)/;
}

sub match {
    my $self   = shift;
    my $fields = join( "\n", @_ );
    if ( $fields !~ $self->{HitReg} ) {
        return;
    }
    my $keyword = $1;
    my $item    = $self->{Hash}{$keyword};
    return $item->{Not} && $fields =~ $item->{NotReg}
        ? undef
        : $keyword;
}

1;
