#!/usr/bin/env  perl
use strict;
use warnings;
use lib 'local/lib/perl5'; 
use 5.008;
 
use ExtUtils::MakeMaker;
WriteMakefile
(
    NAME          => 'Dancer2::Plugin::OpenAPI',
    AUTHOR        => 'T',
    VERSION       => '1.0.2.1',
    LICENSE       => 'perl',
    META_MERGE    => {
        'meta-spec' => { version => 2 },
    },
    META_ADD => {
        provides => {
            'Dancer2::Plugin::OpenAPI' => {
                file => 'lib/Dancer2/Plugin/OpenAPI.pm',
                version => '1.0.2.1',
            },
        },
    },
    PREREQ_PM => {
"Carp" => "0",
"Class::Load" => "0",
"Clone" => "0",
"Dancer2::Plugin" => "0",
"File::ShareDir::Tarball" => "0",
"Hash::Merge" => "0",
"JSON" => "0",
"List::AllUtils" => "0",
"Moo" => "0",
"MooseX::MungeHas" => "0",
"Path::Tiny" => "0",
"PerlX::Maybe" => "0",
"Scalar::Util" => "0",
"strict" => "0",
"warnings" => "0",
"Dancer2" => "0",
"ExtUtils::MakeMaker" => "0",
"File::Spec" => "0",
"IO::Handle" => "0",
"IPC::Open3" => "0",
"Test2::V0" => "0",
"Test::Deep" => "0",
"Test::More" => "0",
"Test::WWW::Mechanize::PSGI" => "0",
"perl" => "5.006",

    } 
);


