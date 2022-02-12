package Net::Recorder::Util;
use strict;
use warnings;
use Carp qw(croak);
use utf8;
use feature qw( say );
use Encode;
use Exporter 'import';
use YAML::Syck qw( LoadFile DumpFile Dump );
use JSON::XS;
use Try::Tiny;
use Time::Piece;
use Time::Seconds;
use HTML::Entities;
use Lingua::JA::Regular::Unicode qw( alnum_z2h space_z2h );
use Lingua::JA::Numbers;
use Number::Bytes::Human qw(format_bytes parse_bytes);
use File::Share ':all';
use File::HomeDir;
use Filesys::DfPortable;
use List::Util qw(first);
use IPC::Cmd qw(can_run run QUOTE);
use DBIx::NamedParams;
use FindBin::libs "Bin=${FindBin::RealBin}";
use open ':std' => ( $^O eq 'MSWin32' ? ':locale' : ':utf8' );

our @EXPORT = qw(
    loadConfig saveConfig
    decodeUtf8 encodeUtf8 getCookie setCookie
    trim unifyLf trimTextInBytes startsWith endsWith toJson decodeJson
    connectDB getColumnsArray getColumnsHash getColumnsNames
    integrateErrorMessages
    normalizeTitle normalizeSubtitle replaceSubtitle
    getAvailableDisk
    sysQuote optimizeMovie
);
our @EXPORT_OK = qw(
    stringify fromString
);

$YAML::Syck::ImplicitUnicode = 1;

my $regPrePost
    = qr{(?<pre>第)(?<num>[^-\s\+~～「」『』【】\(\)]+?)(?<post>話|章|問|回|ワン|箱|局|席|限|弾|週|憑目|幕|羽|斤|夜|球|膳|怪|R|曲|楽章|奏|番|の怪|首|滑走|殺|面)};
my $regPostOnly
    = qr{(?<num>[^-\s\+~～「」『』【】\(\)]+?)(?<post>話|ノ怪|限目|時限目|時間目|ノ銃|Fr|発目|組目|bit|品目|本目|杯目|さやめ|着目|幕|合目)};
my $regPreOnly
    = qr{(?<pre>(#|Lesson|page\.|EPISODE\.?|COLLECTION|session|PHASE|巻ノ|ドキドキ\N{U+2661}|その|Stage[：\.]?|エピソード|File\.?|trip|trap：|ページ|act\.|Step|Line\.|ろ~る|説|ブラッド|\sEX|CHAPTER)\s*)(?<num>[^-\s\+~～「」『』【】\(\)]+)}i;
my $json       = JSON::XS->new->utf8(0)->allow_nonref(1);
my $cookieName = encodeUtf8('NetRecorder');
my $ffmpeg     = can_run('ffmpeg') or die("ffmpeg is not found");

sub loadConfig {
    my $fname = shift || 'config';
    my $dir   = dist_dir('Net-Recorder');
    my $file  = "${dir}/conf/${fname}.yml";
    if ( !( -f $file ) && $fname eq 'config' ) {
        $file = "${dir}/conf/config_default.yml";
    }
    my $conf = LoadFile($file) or die("${file}: $!");
    if ( my $db = $conf->{'DbInfo'} ) {
        map { $db->{'DSN'} =~ s/\{$_\}/$db->{$_}/e; } keys( %{$db} );
    }
    if ( exists( $conf->{'SaveDirs'} ) ) {
        push( @{ $conf->{'SaveDirs'} }, File::HomeDir->my_home . '/Video' );
    }
    return $conf;
}

sub saveConfig {
    my $conf = shift or return;
    $conf->{'DbInfo'}{'DSN'} = 'DBI:{Driver}:host={Server};port={Port};database={DB};';
    my $file = "${FindBin::RealBin}/conf/config.yml";
    DumpFile( $file, $conf );
}

sub decodeUtf8 {
    my $text = shift or return '';
    return Encode::is_utf8($text)
        ? $text
        : decode( 'UTF-8', $text );
}

sub encodeUtf8 {
    my $text = shift or return;
    return encode( 'UTF-8', $text );
}

sub getCookie {
    my $q      = shift or return;
    my $cookie = decodeUtf8( $q->cookie($cookieName) );
    $cookie = !$cookie ? {} : decodeJson($cookie) || {};
}

sub setCookie {
    my $q      = shift or return;
    my $cookie = shift or return;
    return [
        $q->cookie(
            -name    => $cookieName,
            -value   => toJson($cookie),
            -expires => '+1y',
            -path    => $q->url( -absolute => 1 ),
        )
    ];
}

sub trim {
    my $str = shift or return '';
    $str =~ s/^\s+//;
    $str =~ s/\s+$//;
    return $str;
}

sub unifyLf {
    my $text = shift or return '';
    $text =~ s/\r\n/\n/g;
    $text =~ s/\r/\n/g;
    return $text;
}

# [perlの文字列をバイト数で切り取るヤツ - itochin2の日記（仮）](http://itochin2.hatenablog.com/entry/2014/05/16/135830)
sub trimTextInBytes {
    my $text = shift or return '';
    my $len  = shift or return '';
    if ( length( encode( 'UTF-8', $text ) ) <= $len ) {
        return $text;
    }
    while ( length( encode( 'UTF-8', $text ) ) > $len ) {
        $text = substr( $text, 0, -1 );
    }
    return $text;
}

sub startsWith {
    my $text   = shift or return;
    my $prefix = shift or return;
    return $prefix eq substr( $text, 0, length($prefix) );
}

sub endsWith {
    my $text   = shift or return;
    my $suffix = shift or return;
    return $suffix eq substr( $text, -length($suffix) );
}

sub toJson {
    my $obj = shift or return;
    return $json->encode($obj);
}

sub decodeJson {
    my $text = shift or return;
    return try { $json->decode($text) } catch {undef};
}

sub connectDB {
    my $db  = shift or return;
    my $dbh = DBI->connect( $db->{'DSN'}, $db->{'User'}, $db->{'Password'}, $db->{'Options'} )
        or croak($DBI::errstr);
    return $dbh;
}

sub getColumnsArray {
    my $dbh       = shift or return;
    my $tableName = shift or return;
    my $sql       = loadConfig('sql');
    my $sth       = $dbh->prepare_ex( $sql->{'GetColumns'}, { TableName => $tableName, } )
        or croak($DBI::errstr);
    $sth->execute() or croak($DBI::errstr);
    my @columns = ();
    while ( my $column = $sth->fetchrow_hashref ) {
        push( @columns, $column );
    }
    $sth->finish;
    return !@columns
        ? undef
        : [@columns];
}

sub getColumnsHash {
    my $dbh       = shift                               or return;
    my $tableName = shift                               or return;
    my $columns   = getColumnsArray( $dbh, $tableName ) or return;
    return { map { $_->{'COLUMN_NAME'} => $_; } @{$columns} };
}

sub getColumnsNames {
    my $dbh       = shift                               or return;
    my $tableName = shift                               or return;
    my $columns   = getColumnsArray( $dbh, $tableName ) or return;
    return [ map { $_->{'COLUMN_NAME'} } @{$columns} ];
}

sub integrateErrorMessages {
    my ( $error_message, $stdout_buf, $stderr_buf ) = @_;
    my @stdOuts = @{$stdout_buf} <= 10 ? @{$stdout_buf} : splice( @{$stdout_buf}, -10 );
    my @stdErrs = @{$stderr_buf} <= 10 ? @{$stderr_buf} : splice( @{$stderr_buf}, -10 );
    my $error   = decodeUtf8($error_message);
    my $stdOut  = unifyLf( decodeUtf8( join( "\n", @stdOuts ) ) );
    my $stdErr  = unifyLf( decodeUtf8( join( "\n", @stdErrs ) ) );
    return {
        Error  => $error,
        StdOut => $stdOut,
        StdErr => $stdErr,
        All    => join(
            "\n",
            "\nError:"  => $error,
            "\nStdOut:" => $stdOut,
            "\nStdErr:" => $stdErr,
        )
    };
}

sub normalizeTitle {
    my $title = shift or return;
    $title = decode_entities( trim( alnum_z2h( space_z2h($title) ) ) );
    $title =~ tr/！＃♯＄％＆（）．/!\##$%&\(\)\./;
    $title =~ tr/:;<>'"?*|\/\\/：；＜＞’”？＊｜／￥/;
    $title =~ s/\s{2,}/ /g;
    $title =~ s/〜/～/g;
    $title =~ s/\s-\s-\s/ - /;
    return $title;
}

sub normalizeSubtitle {
    my $title   = shift or return;
    my $handler = shift;
    $title = normalizeTitle($title);
    foreach my $reg ( $regPrePost, $regPostOnly, $regPreOnly ) {
        if ( $title =~ s/$reg/replaceSubtitle($+{pre},$+{num},$+{post},$handler,$&,$title)/eg ) {
            last;
        }
    }
    return $title;
}

sub replaceSubtitle {
    my $pre     = shift || '';
    my $num     = shift // '';
    my $post    = shift || '';
    my $handler = shift;
    my $match   = shift || '';
    my $full    = shift || '';
    local $SIG{__WARN__} = sub {
        my $message = shift;
        if ( ref($handler) ne 'CODE' ) { return; }
        &{$handler}( $message, $match, $full );
    };
    my $num2 = ja2num($num);
    return
          $num =~ /^\d+$/               ? sprintf( '%s%02d%s', $pre, $num, $post )
        : defined($num2) && $num2 ne '' ? sprintf( '%s%02d%s', $pre, $num2, $post )
        :                                 "${pre}${num}${post}";
}

sub getAvailableDisk {
    my $space = shift               or return;                           # least free space size
    my $byte  = parse_bytes($space) or die("Invalid Space: ${space}");
    my $conf  = loadConfig();
    my $dir   = first { $_->{'bavail'} > $byte }
    map {
        my $info = dfportable($_) or die("$_: $!");
        {   dir    => $_,
            bavail => $info->{'bavail'},
        };
    } grep { $_ && -d "$_/" } @{ $conf->{'SaveDirs'} };
    return !$dir
        ? undef
        : $dir->{'dir'};
}

sub sysQuote {
    return QUOTE . $_[0] . QUOTE;
}

sub optimizeMovie {
    my $work        = shift or return;
    my $out         = shift or return;
    my $message_ref = shift or return;
    my $cmd         = sprintf( '%s -y -i %s -bsf:a aac_adtstoasc -c copy -movflags faststart %s',
        $ffmpeg, sysQuote($work), sysQuote($out) );
    my ( $success, $error_message, $full_buf, $stdout_buf, $stderr_buf )
        = run( command => $cmd, verbose => 0 );
    unlink($work);
    if ( !( -f $out ) ) {
        ${$message_ref} = integrateErrorMessages( $error_message, $stdout_buf, $stderr_buf );
        return 0;
    }
    chmod( 0666, $out );
    return 1;
}

sub stringify {
    my $obj     = shift or return;
    my %options = (
        ITEM_SEPARATOR   => "\n",
        KEYVAL_SEPARATOR => "\t",
        SHOW_PRIVATE     => 0,
        @_
    );
    return join(
        $options{ITEM_SEPARATOR},
        map { join( $options{KEYVAL_SEPARATOR}, $_, !defined( $obj->{$_} ) ? '' : $obj->{$_} ) }
            sort( grep { $options{SHOW_PRIVATE} || !startsWith( $_, '_' ) } keys( %{$obj} ) )
    );
}

sub fromString {
    my $str     = shift or return;
    my %options = (
        ITEM_SEPARATOR   => qr/\n/,
        KEYVAL_SEPARATOR => qr/\t/,
        @_
    );
    return {
        map { splice( @{ [ split( $options{KEYVAL_SEPARATOR}, $_ ), undef ] }, 0, 2 ); }
            split( $options{ITEM_SEPARATOR}, $str )
    };
}

1;
