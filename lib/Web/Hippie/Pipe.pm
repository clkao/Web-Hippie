package Web::Hippie::Pipe;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use parent 'Plack::Middleware';

use HTTP::Date;
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

    my $client_id = $env->{'hippie.client_id'} ||=
        Plack::Request->new($env)->param('client_id') || $env->{HTTP_X_HIPPIE_CLIENTID};
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
            my $writer = $responder->
                ([200,
                  [ 'Content-Type' => 'application/json',
                    'Cache-Control' => 'no-cache, must-revalidate',
                    'Pragma' => 'no-cache',
                    'Expires' => HTTP::Date::time2str(0),
                    'Last-Modified' => HTTP::Date::time2str(time())
                ]]);
            $sub->poll_once(sub { $writer->write(JSON::encode_json(\@_));
                                  $writer->close });
        }
    }
    elsif ($env->{PATH_INFO} eq '/init') {
        my $h = $env->{'hippie.handle'}
            or return [ '400', [ 'Content-Type' => 'text/plain' ], [ "" ] ];

        my $sub = $self->get_listener($env);
        if ($env->{'hippie.handle'} &&
            $env->{'hippie.handle'}->isa('Web::Hippie::Handle::WebSocket')) {
            $sub->timeout(15);
        }

        $sub->on_error(sub {
                           my ($queue, $error, @msg) = @_;
                           $queue->persistent(0);
                           $queue->append(@msg);
                       });
        $sub->poll(sub { $h->send_msg($_) for @_ });
    }
    elsif ($env->{PATH_INFO} eq '/error') {
        my $sub = $env->{'hippie.listener'} or die;
        # XXX: AnyMQ should provide unpoll method.
        $sub->cv->cb(undef);
        $sub->persistent(0);
        $sub->{timer} = $sub->_reaper;
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
        $sub->on_timeout(sub { $_[0]->destroyed(1);
                               $env->{PATH_INFO} = '/error';
                               $self->app->($env);
                               delete $self->client_mgr->{$client_id};
                           });
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

=head1 NAME

Web::Hippie::Pipe - Persistent Connection Abstraction for Hippie

=head1 SYNOPSIS

  use Plack::Builder;
  use AnyMQ;

  builder {
    mount '/_hippie' => builder {
      enable "+Web::Hippie";
      enable "+Web::Hippie::Pipe", bus => AnyMQ->new;
      sub { my $env = shift;
            my $bus       = $env->{'hippie.bus'}; # AnyMQ bus
            my $listener  = $env->{'hippie.listener'}; # AnyMQ::Queue
            my $client_id = $env->{'hippie.client_id'}; # client id

            # Your handler based on PATH_INFO: /new_listener, /error, /message
      }
    };
    mount '/' => my $app;
  };

=head1 DESCRIPTION

Web::Hippie::Pipe provides unified bidirectional communication over
HTTP via websocket, mxhr, or long-poll, for your C<PSGI> applications.

=head1 SEE ALSO

L<Web::Hippie>

=head1 AUTHOR

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
