package Plack::Middleware::Hippie::Pipe;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw( bus client_mgr );
use Plack::Request;
use Plack::Response;
use AnyMQ;

sub prepare_app {
    my $self = shift;
    $self->client_mgr({});
    $self->bus(AnyMQ->new) unless $self->bus;
}

sub call {
    my ($self, $env) = @_;

    $env->{'hippie.bus'} = $self->bus;

    my $client_id = $env->{'hippie.client_id'} = Plack::Request->new($env)->param('client_id') || $env->{HTTP_X_HIPPIE_CLIENTID};
    if ($env->{PATH_INFO} eq '/poll') {
        my $args = $env->{'hippie.args'};

        # redirect to poll url again with client_id
        unless ($client_id) {
            my $res = Plack::Response->new;
            my $req = Plack::Request->new($env);
            my $uri = $req->uri;
            $uri->path( $uri->path . '/' . $args );
            $uri->query_form(client_id => rand(1));
            $res->redirect($uri);
            return $res->finalize;
        }

        # now we are sure there's client_id
        my $sub = $self->get_listener($env);

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

        my $sub = $self->get_listener($env);
        $sub->poll(sub { $h->send_msg($_) for @_ });
    }
    elsif ($env->{PATH_INFO} eq '/error') {
        $env->{'hippie.listener'}->cv->cb(undef);
        $self->app->($env);
    }
    else {
        $self->get_listener($env);
        return $self->app->($env);
    }
}

sub get_listener {
    my ($self, $env) = @_;
    my $client_id = $env->{'hippie.client_id'} ||= rand(1);
    my $sub = $self->client_mgr->{$client_id};

    my $new = !$sub || $sub->destroyed;
    if ($new) {
        $sub = $self->client_mgr->{$client_id} = $self->bus->new_listener();
        $env->{'hippie.listener'} = $sub;
        # XXX the recycling should be done in anymq
        $env->{PATH_INFO} = '/new_listener';
        $self->app->($env);
        $sub->append({ type => 'hippie.pipe.set_client_id',
                       client_id => $client_id} );
    }

    # XXX: callback to verify we have access to this listener.
    $env->{'hippie.listener'} = $sub;
    return $sub;

}

1;
