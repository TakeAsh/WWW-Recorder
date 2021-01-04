requires 'Const::Fast';
requires 'DBIx::NamedParams';
requires 'Digest::SHA2';
requires 'Encode';
requires 'File::HomeDir';
requires 'File::Temp';
requires 'Filesys::DfPortable';
requires 'FindBin::libs';
requires 'HTML::Entities';
requires 'IPC::Cmd';
requires 'JSON::XS';
requires 'LWP::UserAgent';
requires 'Lingua::JA::Numbers';
requires 'Lingua::JA::Regular::Unicode';
requires 'List::Util';
requires 'MIME::Base64';
requires 'Module::Find';
requires 'Number::Bytes::Human';
requires 'Scalar::Util';
requires 'Template';
requires 'Term::Encoding';
requires 'Time::Piece';
requires 'Time::Seconds';
requires 'Try::Tiny';
requires 'URI';
requires 'URI::Escape';
requires 'XML::Simple';
requires 'YAML::Syck';
requires 'feature';
requires 'parent';
requires 'perl', '5.008001';
requires 'version', '0.77';

on configure => sub {
    requires 'Module::Build::Tiny', '0.035';
};

on test => sub {
    requires 'Test::More';
    requires 'Test::More::UTF8';
};
