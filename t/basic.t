package TestMe;

use strict;
use warnings;

use  Test::WWW::Mechanize::PSGI;

use Test::More tests => 7;
use Test::Deep;

    use Dancer2;
    use Dancer2::Plugin::OpenAPI;

    set serializer => 'JSON';

    swagger_path
        get '/stuff' => sub { };

    swagger_path {
        description => 'standard',
    },
    get '/description/standard' => sub {};

    swagger_path q{
        shortcut

        with some blahs

            And this is inlined
    }, 
    get '/description/first_arg' => sub {};


    get '/swagger_template' => sub {
        return swagger_template;
    };

#swagger_auto_discover;

my $app = TestMe->to_app;
$::mech = Test::WWW::Mechanize::PSGI->new( app => $app );

sub swagger_path_test {
    my $name = shift;
    my $test = pop;
    my $args = shift;
    subtest $name => sub {
        swagger_path $args, get $name, sub { $test->() };
        $::mech->get_ok( $name );
    };
}

$::mech->get_ok( '/swagger_template' );

swagger_path_test '/parameters/standard' => {
    parameters => [
        { name => 'foo', in => 'query', type => 'string' },
        { name => 'bar', in => 'query', type => 'string' },
    ],
}, sub {
    cmp_deeply $Dancer2::Plugin::OpenAPI::THIS_ACTION->parameters, [
        { name => 'foo', in => 'query', type => 'string' },
        { name => 'bar', in => 'query', type => 'string' },
    ];
};

swagger_path_test '/parameters/hash', {
    parameters => {
        foo => { in => 'query', type => 'string' },
        bar => { in => 'query', type => 'string' },
    },
}, sub {
    cmp_deeply $Dancer2::Plugin::OpenAPI::THIS_ACTION->{parameters}, [
        { name => 'bar', in => 'query', type => 'string' },
        { name => 'foo', in => 'query', type => 'string' },
    ];
};

swagger_path_test '/parameters/defaults', {
    parameters => {
        foo => 'FOO',
        bar => { type => 'string' },
    },
}, sub {
    cmp_deeply $Dancer2::Plugin::OpenAPI::THIS_ACTION->parameters, [
        { name => 'bar', in => 'query', type => 'string' },
        { name => 'foo', in => 'query', type => 'string', description => 'FOO' },
    ];
};

swagger_path_test '/parameters/array_with_keys', {
    parameters => [
        foo => 'FOO',
        bar => { type => 'string' },
        { name => 'baz' },
    ],
}, sub {
    cmp_deeply $Dancer2::Plugin::OpenAPI::THIS_ACTION->parameters, [
        { name => 'foo', in => 'query', type => 'string', description => 'FOO' },
        { name => 'bar', in => 'query', type => 'string' },
        { name => 'baz', in => 'query', type => 'string' },
    ];
};

my ( $instance ) = grep { ref($_) =~ /OpenAPI/ } @{ app->plugins };
my $doc = $instance->doc;

is $doc->{paths}{'/description/standard'}{get}{description} => 'standard', '{ desc => blahblah }';
like $doc->{paths}{'/description/first_arg'}{get}{description} => qr/^shortcut/, ' blahblah => { ... }';

TestMe::dance if @ARGV and shift eq 'RUN';
