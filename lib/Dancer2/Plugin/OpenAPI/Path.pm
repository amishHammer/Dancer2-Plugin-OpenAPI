package Dancer2::Plugin::OpenAPI::Path;
# ABSTRACT: Internal representation of a OpenAPI path

=head1 DESCRIPTION

Objects of this class are used by L<Dancer2::Plugin::OpenAPI> to represent
a path in the OpenAPI document.

=cut

use strict;
use warnings;

use Moo;

use MooseX::MungeHas 'is_ro';

use Carp;
use Hash::Merge;
use Clone 'clone';
use List::AllUtils qw/ first any none /;
use JSON;
use Class::Load qw/ load_class /;

has route => ( handles => [ 'pattern' ] );

has tags => ( predicate => 1 );

has plugin => ();

has method => sub {
    eval { $_[0]->route->method } 
        or croak "no route or explicit method provided to path";
};

has path => sub {
    dancer_pattern_to_swagger_path( $_[0]->route->spec_route );
};

has responses => ( predicate => 1);

has description => ( predicate => 1 );
has operationId => ( predicate => 1 );

has requestBody => ( predicate => 1 );

has parameters => 
    lazy => 1,
    default => sub { [] },
    predicate => 1,
;

# TODO allow to pass a hashref instead of an arrayref
sub parameter {
    my( $self, $param, $args ) = @_;

    $args ||= {};
    $args->{name} ||= $param;

    my $p = first { $_->{name} eq $param } @{ $self->parameters };
   
    push @{ $self->parameters || [] }, $p = { name => $param }
        unless $p;

    %$p = %{Hash::Merge::merge( $p, $args )};
}

sub dancer_pattern_to_swagger_path {
    my $pattern = shift;
    $pattern =~ s#(?<=/):(\w+)\??(?=/|$)#{$1}#g;
    return $pattern;
}

sub add_to_doc {
    my( $self, $doc ) = @_;

    my $path = $self->path;
    my $method = $self->method;

    # already there
    next if $doc->{paths}{$path}{$method};

    my $m = $doc->{paths}{$path}{$method} ||= {};

    $m->{description} = $self->description if $self->has_description;
    $m->{parameters} = $self->parameters if $self->has_parameters;
    $m->{tags} = $self->tags if $self->has_tags;
    $m->{requestBody} = $self->requestBody if $self->has_requestBody;
    $m->{operationId} = $self->operationId if $self->has_operationId;

    if( $self->has_responses ) {
        $m->{responses} = clone $self->responses;

=begin1
        This code is broken and does not generate OpenAPI 3.1 compatible output
        for my $r ( values %{$m->{responses}} ) {
            delete $r->{template};

            if( my $example = delete $r->{example} ) {
                my $serializer = 
                    $self->plugin->app->serializer_engine;
                die "Don't know content type for serializer ", ref $serializer
                    if none { $serializer->isa($_) } qw/ Dancer2::Serializer::JSON Dancer2::Serializer::YAML /;
                $r->{examples}{$serializer->content_type} = $example;
            }
        }
=cut
    }


}

sub validate_response {
    my( $self, $code, $data, $strict ) = @_;

    my $schema = $self->responses->{$code}{schema};

    die "no schema found for return code $code for ", join ' ' , uc($self->method), $self->path
        unless $schema or not $strict;

    return unless $schema;

    my $plugin = Dancer2::Plugin::OpenAPI->instance;

    $schema = {
        definitions => $plugin->doc->{definitions},
        properties => { response => $schema },
    };

    my $result = load_class('JSON::Schema::AsType')->new( schema => $schema)->validate_explain({ response => $data });

    return unless $result;

    die join "\n", map { "* " . $_ } @$result;
}

sub BUILD {
    my $self = shift;

    for my $param ( eval { @{ $self->route->{_params} } } ) {
        $self->parameter( $param => {
            in       => 'path',
            required => JSON::true,
            schema => { type => 'string' }
        } );
    }
}

1;


