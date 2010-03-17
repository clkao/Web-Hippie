package Plack::Middleware::Hippie;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw( root init on_error on_message );
use AnyEvent;
use AnyEvent::Handle;

sub call {
    my ($self, $env) = @_;

    if ($self->root) {
        warn "deprecated usage";
        return $self->compat_call($env);
    }

    my (undef, $type, $arg) = split('/', $env->{PATH_INFO}, 3);

    $env->{'hippie.args'} = $arg;

    my $code = $self->can("handler_$type");
    unless ($code) {
        $env->{'PATH_INFO'} = "/$type";
        return $self->app->($env);
    }

    return $code->($self, $env, $self->app);

}
sub compat_call {
    my ($self, $env) = @_;
    my $path_match = $self->root or return;
    my $path = $env->{PATH_INFO};

    my ($type, $arg) = $path =~ m|^\Q$path_match\E/(\w+)(?:/(.*))?$|;
    unless ($type) {
        return $self->app->($env);
    }

    $env->{'hippie.args'} = $arg;

    my $code = $self->can("handler_$type");
    unless ($code) {
        return $self->app->($env);
    }

    return $code->($self, $env, $self->compat_handler);
}

sub compat_handler {
    my $self = shift;
    return sub {
        my $env = shift;
        my $arg = $env->{'hippie.args'};
        if ($env->{PATH_INFO} eq '/message') {
            $self->on_message->($arg, $env->{'hippie.message'});
        }
        else {
            my $h = $env->{'hippie.handle'}
                or return [ '400', [ 'Content-Type' => 'text/plain' ], [ "" ] ];

            if ($env->{PATH_INFO} eq '/init') {
                $self->init->($arg, $h);
            }
            elsif ($env->{PATH_INFO} eq '/error') { 
                $self->on_error->($arg, $h);
            }
            else {
                die "unknown hippie message";
            }
        }
        return [ '200', [ 'Content-Type' => 'text/plain' ], [ "" ] ]
    };
}

sub handler_pub {
    my ($self, $env, $handler) = @_;
    my $req = Plack::Request->new($env);
    $env->{'hippie.message'} = $req->parameters->mixed;
    $env->{'PATH_INFO'} = '/message';

    $handler->($env);
}

sub handler_mxhr {
    my ($self, $env, $handler) = @_;
    my $req = Plack::Request->new($env);
    my $client_id = $req->param('client_id') || rand(1);

    my $size = 2;
    use MIME::Base64;
    my $boundary = MIME::Base64::encode(join("", map chr(rand(256)), 1..$size*3), "");
    $boundary =~ s/[\W]/X/g;  # ensure alnum only

    use Plack::Middleware::Hippie::MXHR;

    return sub {
        my $writer = $_[0]->([ 200, [ 'Content-Type' => 'multipart/mixed; boundary="' . $boundary . '"']]);
        $writer->write("--" . $boundary. "\n");
        $env->{'hippie.handle'} = Plack::Middleware::Hippie::MXHR->new( id => $client_id,
                                                                        boundary => $boundary,
                                                                        writer => $writer );
        $env->{'PATH_INFO'} = '/init';
        $handler->($env);
    };
}

sub handler_ws {
    my ($self, $env, $handler) = @_;

    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);
    unless (    $env->{HTTP_CONNECTION} eq 'Upgrade'
            and $env->{HTTP_UPGRADE}    eq 'WebSocket') {
        $res->code(400);
        return $res->finalize;
    }

    my $client_id = $req->param('client_id') || rand(1);

    return sub {
        my $respond = shift;

        # XXX: we could use $respond to send handshake response
        # headers, but 101 status message should be 'Web Socket
        # Protocol Handshake' rather than 'Switching Protocols'
        # and we should send HTTP/1.1 response which Twiggy
        # doesn't implement yet.

        my $request_uri = $req->request_uri;
        my $hs = join "\015\012",
                "HTTP/1.1 101 Web Socket Protocol Handshake",
                "Upgrade: WebSocket",
                "Connection: Upgrade",
                "WebSocket-Origin: $env->{HTTP_ORIGIN}",
                "WebSocket-Location: ws://$env->{HTTP_HOST}$request_uri",
                '', '';

        my $fh = $env->{'psgix.io'}
            or return $respond->([ 501, [ "Content-Type", "text/plain" ], [ "This server does not support psgix.io extension" ] ]);

        my $h = AnyEvent::Handle->new( fh => $fh );

        use Plack::Middleware::Hippie::WebSocket;
        $env->{'hippie.handle'} = Plack::Middleware::Hippie::WebSocket->new( id => $client_id,
                                                                             h => $h);
        $h->on_error( sub {
                          $env->{'PATH_INFO'} = '/error';
                          $handler->($env);
                          undef $env->{'hippie.handle'};
                      });

        $h->push_write($hs);

        $h->on_read(sub {
                        shift->push_read( line => "\xff", sub {
                                              my ($h, $json) = @_;
                                              $json =~ s/^\0//;

                                              $env->{'hippie.message'} = JSON::decode_json($json);
                                              $env->{'PATH_INFO'} = '/message';
                                              $handler->($env);
                });
            });

        $env->{'PATH_INFO'} = '/init';
        $handler->($env);
    };
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Plack::Middleware::Hippie - Plack helpers for the long hair, or comet

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
    mount '/_hippie' => builder {
      enable "Hippie";
      sub { my $env = shift;
            my $args = $env->{'hippie.args'};
            my $handle = $env->{'hippie.handle'};
            # Your handler based on PATH_INFO: /init, /error, /message
    };
    mount '/' => $app;
  };

=head1 DESCRIPTION

Plack::Middleware::Hippie provides unified bidirectional communication
over HTTP via websocket or mxhr.

=head1 SEE ALSO

L<hippie.js>

=head1 AUTHOR

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
