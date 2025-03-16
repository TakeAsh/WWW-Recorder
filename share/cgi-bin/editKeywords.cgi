#!/usr/bin/perl

use strict;
use warnings;
use utf8;
use feature qw(say);
use Encode;
use YAML::Syck qw(LoadFile Dump DumpFile);
use Template;
use CGI;
use File::Share ':all';
use FindBin::libs "Bin=${FindBin::RealBin}";
use WWW::Recorder;
use WWW::Recorder::Util;
use WWW::Recorder::Keywords;
use Term::Encoding qw(term_encoding);
use open ':std' => ':utf8';

$|                           = 1;
$YAML::Syck::ImplicitUnicode = 1;

my $q = new CGI;
$q->charset(term_encoding);
my $cookie = getCookie($q);
my $tt     = Template->new(
    {   INCLUDE_PATH => dist_dir('WWW-Recorder') . '/templates',
        ENCODING     => 'utf-8',
    }
) or die( Template->error() );

my $query    = { Cookie => $cookie, map { $_ => [ $q->multi_param($_) ]; } $q->multi_param() };
my $command  = $q->param('Command') || '';
my $key      = unifyLf( decodeUtf8( $q->param('Key') || '' ) );
my $not      = unifyLf( decodeUtf8( $q->param('Not') || '' ) );
my $callback = $q->param('Callback') || '';
my $keywords = WWW::Recorder::Keywords->new(@_);
my $result   = {
    Code    => 200,
    Message => 'OK',
    Request => {
        Command => $command,
        Key     => $key,
        Not     => $not,
    },
};

if ( $command eq 'Add' ) {
    $keywords->add( [ { Key => $key, Not => $not, }, ] );
    $keywords->save();
    outputApiResult( $q, $result, $callback );
} elsif ( $command eq 'Remove' ) {
    $keywords->remove($key);
    $keywords->save();
    outputApiResult( $q, $result, $callback );
} else {
    my $out = $q->header(
        -type    => 'text/html',
        -charset => 'utf-8',
        -cookie  => setCookie( $q, $cookie ),
    );
    $tt->process( 'editKeywords.html', { keywords => toJson( $keywords->raw() ), }, \$out )
        or die( $tt->error );
    say $out;
}
