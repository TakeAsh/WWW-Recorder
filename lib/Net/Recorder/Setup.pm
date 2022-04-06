package Net::Recorder::Setup;
use strict;
use warnings;
use Carp;
use utf8;
use feature qw( say );
use Encode;
use Exporter 'import';
use YAML::Syck qw( LoadFile DumpFile Dump );
use DBIx::NamedParams;
use FindBin::libs;
use Net::Recorder::Util;
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

our @EXPORT = qw(
    setup makePassword inputOne setupMysql
);

$YAML::Syck::ImplicitUnicode = 1;

my $conf = loadConfig('config_default');
my $sql  = loadConfig('sql');

sub setup {
    say "\nStart setting up.";
    my $tmp = {};

    say "\n# MySQL settings";
    my $db = $conf->{'DbInfo'};
    $db->{'Password'} = makePassword(8);
    inputOne( $db, 'server',   'Server' );
    inputOne( $db, 'port',     'Port' );
    inputOne( $db, 'client',   'Client' );
    inputOne( $db, 'database', 'DB' );
    inputOne( $db, 'user',     'User' );
    inputOne( $db, 'password', 'Password' );
    $tmp->{'RootPassword'} = '';
    inputOne( $tmp, 'root password', 'RootPassword' );
    setupMysql( $db, $tmp );
    saveConfig( 'config', $conf );
}

sub makePassword {
    my $lenPasswd = shift || 8;
    my $chars     = shift || join( "", map { chr($_); } ( 0x20 .. 0x7e ) );
    my $lenChars  = length($chars);
    my $passwd    = '';
    while ( length($passwd) < $lenPasswd ) {
        $passwd .= substr( $chars, int( rand($lenChars) ), 1 );
    }
    return $passwd;
}

sub inputOne {
    my ( $ref, $label, $key ) = @_;
    my $input = undef;
    say "Enter $label [$ref->{$key}]:";
    chomp( $input = <STDIN> );
    $ref->{$key} = $input || $ref->{$key};
}

sub setupMysql {
    my ( $db, $tmp ) = @_;
    $db->{'DSN'} = 'DBI:{Driver}:host={Server};port={Port};';
    map { $db->{'DSN'} =~ s/\{$_\}/$db->{$_}/e; } keys( %{$db} );
    my $statements = $sql->{'SetupDatabase'};
    map { $statements =~ s/\{$_\}/$db->{$_}/eg; } keys( %{$db} );
    my $dbh = DBI->connect( $db->{'DSN'}, 'root', $tmp->{'RootPassword'}, $db->{'Options'} )
        or die($DBI::errstr);
    my $sth = $dbh->prepare_ex($statements) or die($DBI::errstr);
    $sth->execute()                         or die($DBI::errstr);
    $sth->finish;
    $dbh->disconnect;
}

1;
