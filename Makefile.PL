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
    PREREQ_PM => {} 
);


