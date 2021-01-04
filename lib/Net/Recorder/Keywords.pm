package Net::Recorder::Keywords;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump);
use Scalar::Util qw( reftype );
use FindBin::libs;
use Net::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

$YAML::Syck::ImplicitUnicode = 1;

sub new {
    my $class    = shift;
    my $keywords = shift || [];
    if ( ( reftype($keywords) || '' ) ne 'ARRAY' ) {
        croak("Must be array");
    }
    my %hash = map {
        my $item = $_;
        if ( my $not = $item->{Not} ) {
            my $patternNot = join( "|", map { quotemeta($_) } split( /\n/, $not ) );
            $item->{NotReg} = qr/$patternNot/;
        }
        $item->{Key} => $item;
    } @{$keywords};
    my $patternHit = join( "|", map { quotemeta($_) } keys(%hash) );
    my $self       = {
        Hash   => {%hash},
        HitReg => qr/($patternHit)/,
    };
    bless( $self, $class );
    return $self;
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
