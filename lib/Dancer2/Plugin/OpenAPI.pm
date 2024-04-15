# TODO: then add the template for different responses values
# TODO: override send_error ? 
# TODO: add 'validate_schema'
# TODO: add 'strict_schema'
# TODO: make /openapi.json configurable

package Dancer2::Plugin::OpenAPI;
# ABSTRACT: create OpenAPI documentation of your application

use strict;
use warnings;

use Dancer2::Plugin;
use PerlX::Maybe;
use Scalar::Util qw/ blessed /;

use Dancer2::Plugin::OpenAPI::Path;

use MooseX::MungeHas 'is_ro';

use Path::Tiny;
use File::ShareDir::Tarball;

has doc => (
    is => 'ro',
    lazy => 1,
    default => sub { 
        my $self = shift;

        my $doc = {
            openapi    => '3.1.0',
            paths      => {},
            components => {},
        };

        $doc->{info}{$_} = '' for qw/ title description version /; 

        $doc->{info}{title} = $self->main_api_module if $self->main_api_module;

        if( my( $desc) = $self->main_api_module_content =~ /
                ^(?:\s* \# \s* ABSTRACT: \s* |=head1 \s+ NAME \s+ (?:\w+) \s+ - \s+  ) ([^\n]+) 
                /xm
        ) {
            $doc->{info}{description} = $desc;
        }

        $doc->{info}{version} = eval {
            $self->main_api_module->VERSION
        } // '0.0.0';

        $doc;
        
    },
);

our $FIRST_LOADED = caller(1);

has main_api_module => (
    is => 'ro',
    lazy => 1,
    from_config => 1,
    default => sub { 
        return if $] lt '5.036000';

        $Dancer2::Plugin::OpenAPI::FIRST_LOADED //= caller;
    },
);

has main_api_module_content => (
    is => 'ro',
    lazy => 1,
    default => sub { 
        my $mod = $_[0]->main_api_module or return '';

        $mod =~ s#::#/#g;
        $mod .= '.pm';
        my $path = $INC{$mod} or return '';

        return Path::Tiny::path($path)->slurp;
    }
);

has show_ui => (
    is => 'ro',
    lazy => 1,
    from_config => sub { 1 },
);

has ui_url => (
    is => 'ro',
    lazy => 1,
    from_config => sub { '/doc' },
);

has ui_dir => (
    is => 'ro',
    lazy => 1,
    from_config => sub { 
        Path::Tiny::path(
            File::ShareDir::Tarball::dist_dir('Dancer2-Plugin-OpenAPI')
        )
    },
);

has auto_discover_skip => (
    is => 'ro',
    lazy => 1,
    default => sub { [
            map { /^qr/ ? eval $_ : $_ }
        @{ $_[0]->config->{auto_discover_skip} || [
            '/openapi.json', ( 'qr!' . $_[0]->ui_url . '!' ) x $_[0]->show_ui
        ] }
    ];
    },
);

has validate_response => ( from_config => 1 );
has strict_validation => ( from_config => 1 );


sub BUILD {
    my $self = shift;

    # TODO make the doc url configurable
    $self->app->add_route(
        method => 'get',
        regexp => '/openapi.json',
        code => sub { $self->doc },
    );

    if ( $self->show_ui ) {
        my $base_url = $self->ui_url;

        $self->app->add_route(
            method => 'get',
            regexp => $base_url,
            code => sub {
                $self->app->redirect( $base_url . '/?url=/openapi.json' );
            },
        );

        $self->app->add_route(
            method => 'get',
            regexp => $base_url . '/',
            code => sub {
                my $file = $self->ui_dir->child('index.html');

                $self->app->send_error( "file not found", 404 ) unless -f $file;

                return $self->app->send_as( html => $file->slurp );
            }
        );

        $self->app->add_route(
            method => 'get',
            regexp => $base_url . '/**',
            code => sub {
                my $file = $self->ui_dir->child( @{ ($self->app->request->splat())[0] } );

                $self->app->send_error( "file not found", 404 ) unless -f $file;

                $self->app->send_file( $file, system_path => 1);
            }
        );
    }
    
}

sub openapi_auto_discover :PluginKeyword {
    my( $plugin, %args ) = @_;

    $args{skip} ||= $plugin->auto_discover_skip;

    my $routes = Dancer2::App->current->registry->routes;

    # my $doc = $plugin->doc->{paths};

    for my $method ( qw/ get post put delete / ) {
        for my $r ( @{ $routes->{$method} } ) {
            my $pattern = $r->pattern;

            next if ref $pattern eq 'Regexp';

            next if grep { ref $_ ? $pattern =~ $_ : $pattern eq $_ } @{ $args{skip} };

            my $path = Dancer2::Plugin::OpenAPI::Path->new( 
                plugin => $plugin,
                route => $r );

            $path->add_to_doc($plugin->doc);
        }
    }
};

sub openapi_tag :PluginKeyword {
    my ($plugin) = shift;

    my( $name, $tag ) = @_;
    push @{ $plugin->doc->{tags} }, $tag;
    return $tag->{name};
};

sub openapi_path :PluginKeyword {
    my $plugin = shift;

    $DB::single = 1;
    my @routes;
    push @routes, pop @_ while eval { $_[-1]->isa('Dancer2::Core::Route') };

    # we don't process HEAD
    @routes = grep { $_->method ne 'head' } @routes;


    my $description;
    if( @_ and not ref $_[0] ) {
        $description = shift;
        $description =~ s/^\s*\n//;
        
        $description =~ s/^$1//mg
            if $description =~ /^(\s+)/;
    }

    my $arg = shift @_ || {}; 

    $arg->{description} = $description if $description;

    # groom the parameters
    if ( my $p = $arg->{parameters} ) {
        if( ref $p eq 'HASH' ) {
            $_ = { description => $_ } for grep { ! ref } values %$p;
            $p = [ map { +{ name => $_, %{$p->{$_}} } } sort keys %$p ];
        }

        # deal with named parameters
        my @p;
        while( my $k = shift @$p ) {
            unless( ref $k ) { 
                my $value = shift @$p;
                $value = { description => $value } unless ref $value;
                $value->{name} = $k;
                $k = $value;
            }
            push @p, $k;
        }
        $p = \@p;

        # set defaults
        $p = [ map { +{ in => 'query', type => 'string', %$_ } } @$p ];
        
        $arg->{parameters} = $p;
    }


    for my $route ( @routes ) {
        my $path = Dancer2::Plugin::OpenAPI::Path->new(%$arg, route => $route, plugin => $plugin );

        $path->add_to_doc( $plugin->doc );

        my $code = $route->{code};
        # TODO change this so I don't play in D2's guts directly
        $route->{code} = sub {
            local $Dancer2::Plugin::OpenAPI::THIS_ACTION = $path;
            $code->();
        };
    }
};

sub openapi_template :PluginKeyword {
    my $plugin = shift;

    my $vars = pop;
    my $status = shift || $Dancer2::Core::Route::RESPONSE->status( @_ );

    my $template = $Dancer2::Plugin::OpenAPI::THIS_ACTION->{responses}{$status}{template};

    $Dancer2::Core::Route::RESPONSE->status( $status ) if $status =~ /^\d{3}$/;

    return $plugin->openapi_response( $status, $template ? $template->($vars) : $vars );
};

sub openapi_response :PluginKeyword {
    my $plugin = shift;

    my $data = pop;

    my $status = $Dancer2::Core::Route::RESPONSE->status(@_);
#    $Dancer2::Plugin::OpenAPI::THIS_ACTION->validate_response( 
            my $path = Dancer2::Plugin::OpenAPI::Path->new(plugin=>$plugin);
$path->validate_response(
        $status => $data, $plugin->strict_validation 
    ) if $plugin->validate_response;

    $data;
}

sub openapi_definition :PluginKeyword {
    my $plugin = shift;

    my( $name, $def ) = @_;

    $plugin->doc->{components}{schemas} ||= {};
    $plugin->doc->{components}{schemas}{$name} = $def;

    return { '$ref', => '#/components/schemas/'.$name };

}

sub openapi_security :PluginKeyword {
    my $plugin = shift;

    my( $name, $def ) = @_;
    my $global = delete $def->{global};

    $plugin->doc->{components}{securitySchemes} ||= {};
    $plugin->doc->{components}{securitySchemes}{$name} = $def;

    if (defined($global) && $global) {
        $plugin->doc->{security} ||= [];

        push @{$plugin->doc->{security}}, { $name => [] };
    }

    return $name;
}

sub openapi_example :PluginKeyword {
    my $plugin = shift;

    my( $name, $def ) = @_;

    $plugin->doc->{components}{examples} ||= {};
    $plugin->doc->{components}{examples}{$name} = $def;


    return { '$ref', => '#/components/examples/'.$name };
}

sub openapi_response_ref :PluginKeyword {
    my $plugin = shift;

    my( $name, $def ) = @_;

    $plugin->doc->{components}{response} ||= {};
    $plugin->doc->{components}{response}{$name} = $def;


    return { '$ref', => '#/components/response/'.$name };
}

1;

__END__


=head1 SYNOPSIS

    package MyApp;

    use Dancer;
    use Dancer2::Plugin::OpenAPI;

    our $VERSION = "0.1";

    get '/choreograph/:name' => sub { ... };

    1;


=head1 DESCRIPTION

This plugin provides tools to create and access a L<OpenApi|https://spec.openapis.org> specification file for a
Dancer REST web service. Originally was L<Dancer::Plugin::Swagger>.

Overview of C<Dancer2::Plugin::OpenAPI>'s features:

=over

=item Can create a F</openapi.json> REST specification file.

=item Can auto-discover routes and add them to the OpenAPI file.

=item Can provide a OpenAPI UI version of the OpenAPI documentation.

=back


=head1 CONFIGURATION

    plugins:
        OpenApi
           main_api_module: MyApp
           show_ui: 1
           ui_url: /doc
           ui_dir: /path/to/files
           auto_discover_skip:
            - /openapi.json
            - qr#^/doc/#

=head2 main_api_module

If not provided explicitly, the OpenApi document's title and version will be set
to the abstract and version of this module. 

For Perl >= 5.36.0, defaults to the first module to import L<Dancer2::Plugin::OpenAPI>.

=head2 show_ui

If C<true>, a route will be created for the Swagger UI (see L<http://swagger.io/swagger-ui/>).

Defaults to C<true>.

=head2 ui_url

Path of the swagger ui route. Will also be the prefix for all the CSS/JS dependencies of the page.

Defaults to C</doc>.

=head2 ui_dir

Filesystem path to the directory holding the assets for the Swagger UI page.

Defaults to a copy of the Swagger UI code bundled with the L<Dancer2::Plugin::OpenAPI> distribution.

=head2 auto_discover_skip

List of urls that should not be added to the OpenApi document by C<openapi_auto_discover>.
If an url begins with C<qr>, it will be compiled as a regular expression.

Defauls to C</openapi.json> and, if C<show_ui> is C<true>, all the urls under C<ui_url>.

=head2 validate_response 

If set to C<true>, calls to C<openapi_response> will verify if a schema is defined 
for the response, and if so validate against it. L<JSON::Schema::AsType> is used for the
validation (and this required if this option is used).

Defaults to C<false>.

=head2 strict_validation

If set to C<true>, dies if a call to C<openapi_response> doesn't find a schema for its response.

Defaults to C<false>.

=head1 PLUGIN KEYWORDS

=head2 openapi_path $description, \%args, $route

    openapi_path {
        description => 'Returns info about a judge',
    },
    get '/judge/:judge_name' => sub {
        ...;
    };

Registers a route as a OpenAPI path item in the OpenAPI document.

C<%args> is optional.

The C<$description> is optional as well, and can also be defined as part of the 
C<%args>.

    # equivalent to the main example
    openapi_path 'Returns info about a judge',
    get '/judge/:judge_name' => sub {
        ...;
    };

If the C<$description> spans many lines, it will be left-trimmed.

    openapi_path q{ 
        Returns info about a judge.

        Some more documentation can go here.

            And this will be seen as a performatted block
            by OpenAPI.
    }, 
    get '/judge/:judge_name' => sub {
        ...;
    };

=head3 Supported arguments

=over

=item method

The HTTP method (GET, POST, etc) for the path item.

Defaults to the route's method.

=item path

The url for the path item.

Defaults to the route's path.

=item description

The path item's description.

=item tags

Optional arrayref of tags assigned to the path.

=item parameters

List of parameters for the path item. Must be an arrayref or a hashref.

Route parameters are automatically populated. E.g., 

    openapi_path
    get '/judge/:judge_name' => { ... };

is equivalent to

    openapi_path {
        parameters => [
            { name => 'judge_name', in => 'path', required => 1, type => 'string' },
        ] 
    },
    get '/judge/:judge_name' => { ... };

Parameters are passed as an arrayref, they will appear in the document in a random order
as JSON arrays are unordered, it is up to the display layer to order them. Each item in
the array can be parameter object, or a ref object.

Finally, if not specified explicitly, the C<in> argument of a parameter defaults to C<query>,
and its type to C<string>.

    parameters => [
        { name => 'bar', in => 'path', required => 1, type => 'string' },
        { name => 'foo', in => 'query', type => 'string', description => 'yadah' },
    ],

    # equivalent arrayref with mixed pairs/non-pairs

    parameters => [
        { name => 'bar', in => 'path', required => 1, type => 'string' },
        foo => { in => 'query', type => 'string', description => 'yadah' },
    ],

    # equivalent hashref format 
    
    parameters => {
        bar => { in => 'path', required => 1, type => 'string' },
        foo => { in => 'query', type => 'string', description => 'yadah' },
    },

    # equivalent, using defaults
    parameters => {
        bar => { in => 'path', required => 1 },
        foo => 'yadah',
    },

=item responses

Possible responses from the path. Must be a hashref.

    openapi_path {
        responses => {
            200 => {
                content => {
                    'application/json' => {
                        examples => {
                            'Example Name' => {
                                summary => 'Example Name',
                                value => { fullname => 'Mary Ann Murphy' }
                            }
                        }
                    }
                }
            }
        }
    },
    get '/judge/:judge_name' => { ... };

The special key C<template> will not appear in the OpenAPI doc, but will be
used by the C<openapi_template> plugin keyword.

=item requestBody

The request body of the path item. Must be a hashref. Must be a valid request
body object, or a ref object.

     openapi_path {
        requestBody => {
            content => {
                'application/json' => {
                    type => 'object',
                    properties => {
                        fullname => {
                            type => 'string'
                            description => "The judge's full name",
                        },
                    }
                }
            }
        }
    },
    post '/judge' => { ... };

=back

=head2 openapi_template $code, $args

    openapi_path {
        responses => {
            404 => { template => sub { +{ error => "judge '$_[0]' not found" } }  
        },
    },
    get '/judge/:judge_name' => {  
        my $name = param('judge_name');
        return openapi_template 404, $name unless in_db($name);
        ...;
    };

Calls the template for the C<$code> response, passing it C<$args>. If C<$code> is numerical, also set
the response's status to that value. 


=head2 openapi_auto_discover skip => \@list

Populates the OpenAPI document with information of all
the routes of the application.

Accepts an optional C<skip> parameter that takes an arrayref of
routes that shouldn't be added to the OpenAPI document. The routes
can be specified as-is, or via regular expressions. If no skip list is given, defaults to 
the c<auto_discover_skip> configuration value.

    openapi_auto_discover skip => [ '/openapi.json', qr#^/doc/# ];

The information of a route won't be altered if it's 
already present in the document.

If a route has path parameters, they will be automatically
added as such in the C<parameters> section.

Routes defined as regexes are skipped, as there is no clean way
to automatically make them look nice.

        # will be picked up
    get '/user' => ...;

        # ditto, as '/user/{user_id}'
    get '/user/:user_id => ...;

        # won't be picked up
    get qr#/user/(\d+)# => ...;


Note that routes defined after C<openapi_auto_discover> has been called won't 
be added to the OpenAPI document. Typically, you'll want C<openapi_auto_discover>
to be called at the very end of your module. Alternatively, C<openapi_auto_discover>
can be called more than once safely -- which can be useful if an application creates
routes dynamically.

=head2 openapi_definition $name => $definition, ...

Adds a schema (or more) to the definition section of the OpenAPI document.

    my $Judge = openapi_definition 'Judge' => {
        type => 'object',
        required => [ 'fullname' ],
        properties => {
            fullname => { type => 'string' },
            seasons => { type => 'array', items => { type => 'integer' } },
        }
    };

The function returns the reference to the definition that can be then used where
schemas are used.

    my $Judge = openapi_definition 'Judge' => { ... };
    # $Judge is now the hashref '{ '$ref' => '#/components/schema/Judge' }'
    
    # later on...
    openapi_path {
        responses => {
            content => {
                200 => {
                    'application/json' => { schema => $Judge },
                }
            }
        },
    },
    get '/judge/:name' => sub { ... };

Reference objects can override the description of the parent type, to this
dereference the ref object into a new hashref with the new description.

    my $Timestamp = openapi_definition 'Timestamp' => {
        type => 'string',
        description => 'A timestamp in ISO 8601 format',
    };
    my $Judge = openapi_definition 'Judge' => {
        type => 'object',
        required => [ 'fullname' ],
        properties => {
            fullname => { type => 'string' },
            seasons => { type => 'array', items => { type => 'integer' } },
            created => {
                description => 'When the judge was created',
                %$Timestamp,
            },
        }
    };

=head2 openapi_tag $description, \%args, $route

Add a tag object to the API tags section, this will be used in some
viewers to provide a better description of tags..

    my $JudgeTag = openapi_tag 'Judge' => {
        name => 'Judge',
        description => 'Operations about judges'
    };

=head2 openapi_example $description, \%args, $route

Add an example object to the examples section to be re-used in multiple
objects. The return is a ref object.

    my $JudgeExample = openapi_example 'JudgeExample' => {
        summary => 'Example Judge',
        value => { fullname => 'Mary Ann Murphy' }
    };
    openapi_path {
        responses => {
            content => {
                200 => {
                    'application/json' => {
                        schema => $Judge
                        examples => { 'ExampleJudge' => $JudgeExample }
                    },
                }
            }
        },
    },
    get '/judge/:name' => sub { ... };


=head2 openapi_response_ref $description, \%args, $route

Add a response object to the responses section to be re-used in multiple
paths.

    my $ErrorSchema = openapi_definition 'Error' => {
        type => 'object',
        properties => {
            error => { type => 'string' },
        }
    };

    my $NotFound = openapi_response_ref 'NotFound' => {
        description => 'The judge was not found',
        content => {
            'application/json' => {
                schema => $ErrorSchema,
                example => { error => 'Not found' }
            }
        }
    };
    openapi_path {
        responses => {
            404 => $NotFound
        },
    },
    get '/judge/:name' => sub { ... };

    openapi_path {
        responses => {
            404 => $NotFound
        },
    },
    get '/assistant/:name' => sub { ... };


=head2 openapi_security $description, \%args, $route

Add a security object to the securitySchemes section, this returns the security
schema name so it can be re-used. If the global key is set to true, it will be
added to the global security array to be applied to all paths.

Enable an API key security scheme for all requests in the query string.

    my $ApiKey = openapi_security 'ApiKey' => {
        type        => "apiKey",
        name        => "apikey",
        in          => "query",
        description => "Your API Key",
        global      =>1,
    };

Enable an API key for one path:

    my $ApiKey = openapi_security 'ApiKey' => {
        type        => "apiKey",
        name        => "apikey",
        in          => "query",
        description => "Your API Key",
    };
    openapi_path {
        security => [
            $ApiKey => []
        ],
    },
    get '/judge/:name' => sub { ... };

=head1 EXAMPLES

See the F<examples/> directory of the distribution for a working example.

=head1 SEE ALSO

=over

=item L<http://swagger.io/|Swagger>

=item L<Dancer2::Plugin::OpenAPI>

The original plugin, for Dancer1.


=back

=cut

