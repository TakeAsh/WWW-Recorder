package Net::Recorder;
use 5.010;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use Exporter 'import';
use YAML::Syck qw( LoadFile DumpFile Dump );
use Time::Piece;
use File::Basename;
use File::Spec;
use DBIx::NamedParams;
use FindBin::libs "Bin=${FindBin::RealBin}";
use Net::Recorder::Util;
use Net::Recorder::Provider;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

use version 0.77; our $VERSION = version->declare("v0.0.1");

our @EXPORT = qw(
    getProgramsForDisplay
    getProgramUris addPrograms
    getPrograms
    record
    abortPrograms
    removePrograms
    exportAll
);

$YAML::Syck::ImplicitUnicode = 1;

my $conf = loadConfig();
my $sql  = loadConfig('sql');

sub getProgramsForDisplay {
    my $provider = shift or return;
    my $sortBy   = shift || 'Status';
    my $dbh      = connectDB( $conf->{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( join( ' ', $sql->{'GetProgramsForDisplay'}, $sql->{'SortBy'}{$sortBy} ),
        { Provider => $provider, } )
        or die($DBI::errstr);
    $sth->execute() or die($DBI::errstr);
    my @programs = ();
    my $index    = 0;
    while ( my $row = $sth->fetchrow_hashref ) {
        my $desc = join( "",
            map { '<div>' . ( $row->{$_} || '' ) . '</div>' } qw(Performer Description Info) );
        push(
            @programs,
            {   index => ++$index,
                Class => join( "_", 'STAT', $row->{'Status'}, $index % 2 ),
                Desc  => $desc,
                %{$row},
            }
        );
    }
    $sth->finish;
    $dbh->disconnect;
    return !@programs
        ? undef
        : [@programs];
}

sub getProgramUris {
    my %uris = map { trim($_) => 1; } map { split( /\n/, $_ ) } @_;
    return sort( keys(%uris) );
}

sub addPrograms {
    my @programs  = @_;
    my @providers = Net::Recorder::Provider->providers();
    my $index     = 0;
    foreach my $program (@programs) {
        ++$index;
        foreach my $provider (@providers) {
            my $match = $provider->isSupported($program) or next;
            my $programs
                = $provider->getProgramsFromUri( $index, scalar(@programs), $program, $match )
                or next;
            $provider->store($programs);
            $provider->flush();
            last;
        }
    }
}

sub getPrograms {
    my @providers = Net::Recorder::Provider->providers();
    foreach my $provider (@providers) {
        my $pid = fork;
        if ( !defined($pid) ) {
            warn("Failed to fork");
        } elsif ( !$pid ) {    # Child process
            $provider->log( "# " . $provider->name() . ": Start" );
            if ( my $programs = $provider->getPrograms() ) {
                $provider->store($programs);
            }
            $provider->log( "# " . $provider->name() . ": End" );
            $provider->flush();
            exit;
        }
    }
    while ( wait() >= 0 ) { sleep(1); }
}

sub record {
    my @providers = Net::Recorder::Provider->providers();
    foreach my $provider (@providers) {
        my $pid = fork;
        if ( !defined($pid) ) {
            warn("Failed to fork");
        } elsif ( !$pid ) {    # Child process
            if ( my $programs = $provider->getStartingPrograms() ) {
                $provider->log( "# " . $provider->name() . ": Start" );
                $provider->setStandBy($programs);
                $provider->record($programs);
                $provider->log( "# " . $provider->name() . ": End" );
                $provider->flush();
            }
            exit;
        }
    }
    while ( wait() >= 0 ) { sleep(1); }
}

sub abortPrograms {
    my $provider   = shift or return;
    my $programIds = shift || [];
    my $dbh        = connectDB( $conf->{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( $sql->{'AbortPrograms'}, { Provider => $provider, ID => $programIds, } )
        or die($DBI::errstr);
    my $rv = $sth->execute() or die($DBI::errstr);
    $sth->finish;
    $dbh->disconnect;
    return $rv;
}

sub removePrograms {
    my $provider   = shift or return;
    my $programIds = shift || [];
    my $dbh        = connectDB( $conf->{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( $sql->{'RemovePrograms'},
        { Provider => $provider, ID => $programIds, } )
        or die($DBI::errstr);
    my $rv = $sth->execute() or die($DBI::errstr);
    $sth->finish;
    $dbh->disconnect;
    return $rv;
}

sub exportAll {
    my @providers = Net::Recorder::Provider->providerNames();
    my $dbh       = connectDB( $conf->{'DbInfo'} );
    my $columns   = [
        map      { $_->{'COLUMN_NAME'} }
            sort { $a->{'ORDINAL_POSITION'} <=> $b->{'ORDINAL_POSITION'} }
            @{ getColumnsArray( $dbh, 'Programs' ) }
    ];
    my $sth = $dbh->prepare_ex( $sql->{'GetProgramsForExport'} ) or die($DBI::errstr);
    my $t   = localtime;
    my $now = $t->strftime('%Y%m%d%H%M%S');
    foreach my $provider (@providers) {
        my $programs = getProgramsForExport( $sth, $provider ) or next;
        savePrograms( $provider, $now, $columns, $programs );
    }
    $sth->finish;
    $dbh->disconnect;

}

sub getProgramsForExport {
    my $sth      = shift or return;
    my $provider = shift or return;
    $sth->bind_param_ex( { Provider => $provider, } ) or die($DBI::errstr);
    $sth->execute()                                   or die($DBI::errstr);
    my @programs = ();
    while ( my $program = $sth->fetchrow_hashref ) {
        push( @programs, $program );
    }
    return !@programs
        ? undef
        : [@programs];
}

sub savePrograms {
    my $provider = shift or return;
    my $now      = shift or return;
    my $columns  = shift or return;
    my $programs = shift or return;
    my $dir      = File::Spec->rel2abs( dirname(__FILE__) );
    my $fname    = "${dir}/../../log/${provider}_${now}.tsv";
    if ( -e $fname ) {
        die("$fname: already exist");
    }
    open( my $fh, '>:utf8', $fname ) or die("$fname: $!");
    say $fh join( "\t", @{$columns} );
    foreach my $program ( @{$programs} ) {
        say $fh join( "\t", map { escapeForTsv( $program->{$_} ) } @{$columns} );
    }
    close($fh);
}

sub escapeForTsv {
    my $text = shift // return '';
    $text =~ s/([\\\n\r\t"'])/sprintf("\\x%02X", ord($1))/egmos;
    return $text;
}

1;
__END__

=encoding utf-8

=head1 NAME

Net::Recorder - NetRadio recorder with scheduler.

=head1 SYNOPSIS

    use Net::Recorder;

=head1 DESCRIPTION

Net::Recorder is ...

=head1 SEE ALSO

L<Rec-adio|https://github.com/sun-yryr/Rec-adio>

L<rec_radiko_ts|https://github.com/uru2/rec_radiko_ts>

=head1 LICENSE

Copyright (C) TakeAsh68k.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

L<TakeAsh68k|https://github.com/TakeAsh/>

=cut
