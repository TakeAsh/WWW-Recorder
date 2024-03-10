package WWW::Recorder;
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
use List::Util qw(first);
use DBIx::NamedParams;
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder::Util;
use WWW::Recorder::Provider;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

use version 0.77; our $VERSION = version->declare("v0.0.1");

our @EXPORT = qw(
    getProgramsForDisplay
    getProgramUris
    getPrograms
    outputApiResult
    ApiAddPrograms ApiCommand
    record
    retryPrograms
    abortPrograms
    removePrograms
    exportAll
    getProgramById
);

$YAML::Syck::ImplicitUnicode = 1;

my $conf = loadConfig();
my $sql  = loadConfig('sql');

sub getProgramsForDisplay {
    my $provider  = shift or return;
    my $extraKeys = shift or return;
    my $sortBy    = shift || 'Status';
    my $dbh       = connectDB( $conf->{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( join( ' ', $sql->{'GetProgramsForDisplay'}, $sql->{'SortBy'}{$sortBy} ),
        { Provider => $provider, } )
        or die($DBI::errstr);
    $sth->execute() or die($DBI::errstr);
    my @programs = ();
    my $index    = 0;

    while ( my $row = $sth->fetchrow_hashref ) {
        my $p    = WWW::Recorder::Program->new($row);
        my $desc = join( "",
            map  { '<div>' . LfToBr( unifyLf($_) ) . '</div>' }
            grep {$_}
            map  { trim( $row->{$_} || '' ) } qw(Performer Description Info) );
        my $extra = $p->Extra();
        my $p2    = {
            index  => ++$index,
            Class  => join( "_", 'STAT', $row->{'Status'}, $index % 2 ),
            Desc   => $desc,
            Extra2 => [ map { $extra->{$_} // ''; } @{$extraKeys} ],
            %{$p},
        };
        $p2->{'Series'}
            = $extra->can('SeriesUri') ? $extra->SeriesUri()
            : $extra->can('seriesUri') ? $extra->seriesUri()
            : $extra->can('SeriesID')  ? $extra->SeriesID()
            :                            undef;
        push( @programs, $p2 );
    }
    $sth->finish;
    $dbh->disconnect;
    return !@programs
        ? undef
        : [@programs];
}

sub getProgramUris {
    my %uris = map { trim($_) => 1; }
        map {
        my $uri = $_;
        $uri =~ /^(?<pre>.*)\[(?<start>.+)-(?<end>.+)\](?<post>.*)$/
            ? ( map { "$+{pre}${_}$+{post}"; } ( $+{'start'} .. $+{'end'} ) )
            : $uri
        }
        map { split( /\n/, unifyLf($_) ) } @_;
    return sort( keys(%uris) );
}

sub getPrograms {
    my $providerName = shift || '';
    my @providers    = WWW::Recorder::Provider->providers();
    if ($providerName) {
        if ( my $provider = first { $_->name() eq $providerName } @providers ) {
            $provider->getProgramsAndStore();
        } else {
            die("Unknown provider: $providerName\n");
        }
        return;
    }
    foreach my $provider (@providers) {
        my $pid = fork;
        if ( !defined($pid) ) {
            warn("Failed to fork");
        } elsif ( !$pid ) {    # Child process
            $provider->getProgramsAndStore();
            exit;
        }
    }
    while ( wait() >= 0 ) { sleep(1); }
}

sub record {
    my $providerName = shift || '';
    my @providers    = WWW::Recorder::Provider->providers();
    if ($providerName) {
        if ( my $provider = first { $_->name() eq $providerName } @providers ) {
            if ( my $programs = $provider->getStartingPrograms() ) {
                $provider->log( "# " . $provider->name() . ": Start" );
                $provider->setStandBy($programs);
                $provider->record($programs);
                $provider->log( "# " . $provider->name() . ": End" );
                $provider->flush();
            }
        } else {
            die("Unknown provider: $providerName\n");
        }
        return;
    }
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

sub outputApiResult {
    my $q          = shift or return;
    my $result     = shift or return;
    my $callback   = shift;
    my $jsonString = toJson($result);
    chomp($jsonString);
    print $q->header(
        -type                         => $callback ? 'application/javascript' : 'application/json',
        -charset                      => 'utf-8',
        -status                       => $result->{'Code'} . ' ' . $result->{'Message'},
        -expires                      => 'now',
        -cache_control                => 'no-cache, no-store',
        -access_control_allow_origin  => '*',
        -access_control_allow_headers => '*',
        -access_control_allow_methods => 'GET, HEAD, POST, OPTIONS',
    );
    if ($callback) {
        say "${callback}(${jsonString})";
    } else {
        say $jsonString;
    }
}

sub ApiAddPrograms {
    my @programs = map { split( /\n/, unifyLf($_) ) } @_;
    my $result   = {
        Code    => 400,
        Message => 'Bad Request',
        Request => {
            Command  => 'AddPrograms',
            Programs => [@programs],
        },
    };
    if ( !@programs ) { return $result; }
    defined( my $pid = fork() ) or die("Fail to fork: $!");
    if ( !$pid ) {    # Child process
        close(STDOUT);
        close(STDIN);
        my @providers = WWW::Recorder::Provider->providers();
        my $index     = 0;
        foreach my $program ( getProgramUris(@programs) ) {
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
        exit;
    }
    return {
        %{$result},
        Code    => 200,
        Message => 'OK',
    };
}

sub ApiCommand {
    my $command    = shift || '';
    my $provider   = shift || '';
    my $programIds = shift || {};
    my $result     = {
        Code    => 400,
        Message => 'Bad Request',
        Request => {
            Command    => $command,
            Provider   => $provider,
            ProgramIds => $programIds,
        },
    };
    if ( ( !grep { $_ eq $command } qw(Retry Abort Remove) ) || !@{$programIds} ) {
        return $result;
    }
    defined( my $pid = fork() ) or die("Fail to fork: $!");
    if ( !$pid ) {    # Child process
        close(STDOUT);
        close(STDIN);
        if ( $command eq 'Retry' ) {
            retryPrograms( $provider, $programIds );
        } elsif ( $command eq 'Abort' ) {
            abortPrograms( $provider, $programIds );
        } elsif ( $command eq 'Remove' ) {
            removePrograms( $provider, $programIds );
        }
        exit;
    }
    return {
        %{$result},
        Code    => 200,
        Message => 'OK',
    };
}

sub retryPrograms {
    my $provider   = shift or return;
    my $programIds = shift || [];
    my $dbh        = connectDB( $conf->{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( $sql->{'RetryPrograms'}, { Provider => $provider, ID => $programIds, } )
        or die($DBI::errstr);
    my $rv = $sth->execute() or die($DBI::errstr);
    $sth->finish;
    $dbh->disconnect;
    return $rv;
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
    my @providers = WWW::Recorder::Provider->providerNames();
    my $dbh       = connectDB( $conf->{'DbInfo'} );
    my $columns   = getColumnsNames( $dbh, 'Programs' );
    my $sth       = $dbh->prepare_ex( $sql->{'GetProgramsForExport'} ) or die($DBI::errstr);
    my $t         = WWW::Recorder::TimePiece->new();
    my $now       = $t->toPostfix();
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
    my $fname    = "$conf->{LogDir}/${provider}_${now}.tsv";
    if ( -f $fname ) {
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

sub getProgramById {
    my $provider  = shift or return;
    my $programId = shift or return;
    my $dbh       = connectDB( $conf->{'DbInfo'} );
    my $sth
        = $dbh->prepare_ex( $sql->{'GetProgramById'}, { Provider => $provider, ID => $programId, } )
        or die($DBI::errstr);
    my $rv  = $sth->execute() or die($DBI::errstr);
    my $row = $sth->fetchrow_hashref;
    my $p   = WWW::Recorder::Program->new($row);
    $sth->finish;
    $dbh->disconnect;
    return $p;
}

1;
__END__

=encoding utf-8

=head1 NAME

WWW::Recorder - NetRadio recorder with scheduler.

=head1 SYNOPSIS

    use WWW::Recorder;

=head1 DESCRIPTION

WWW::Recorder is ...

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
