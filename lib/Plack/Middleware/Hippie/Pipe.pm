package Plack::Middleware::Hippie::Pipe;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw( bus client_mgr );

sub prepare_app {
    my $self = shift;
    $self->client_mgr({});
    $self->bus(AnyMQ->new) unless $self->bus;
}

sub call {
    my ($self, $env) = @_;

    $env->{'hippie.bus'} = $self->bus;

    if ($env->{PATH_INFO} eq '/poll') {
        my $client_id = Plack::Request->new($env)->param('client_id') || rand(1);
        my $sub = $self->client_mgr->{$client_id} ||= $self->bus->new_listener();
        # XXX the recycling should be done in anymq
        $sub = $self->bus->new_listener() if $sub->destroyed;
        $env->{'hippie.listener'} = $sub;
        $env->{PATH_INFO} = '/new_listener';
        $self->app->($env);

        return sub {
            my $responder = shift;
            my $writer = $responder->([200, [ 'Content-Type' => 'application/json']]);
            # XXX: callback for nuregistering clieng_mgr not yet invoked.
            $sub->poll_once(sub { $writer->write(JSON::encode_json(\@_));
                                  $writer->close },
                            30,
                            sub { delete $self->client_mgr->{$client_id} },
                        );
        }
    }
    elsif ($env->{PATH_INFO} eq '/init') {
        my $h = $env->{'hippie.handle'}
            or return [ '400', [ 'Content-Type' => 'text/plain' ], [ "" ] ];

        my $sub = $env->{'hippie.listener'} = $self->bus->new_listener();
        $env->{PATH_INFO} = '/new_listener';
        $self->app->($env);
        $sub->poll(sub { $h->send_msg($_[0]) });
    }
    else {
        return $self->app->($env);
    }
}

1;
