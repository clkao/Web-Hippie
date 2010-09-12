package Web::Hippie;

use strict;
use 5.008_001;
our $VERSION = '0.34';
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw( root init on_error on_message trusted_origin );
use AnyEvent;
use AnyEvent::Handle;
use Plack::Request;
use JSON;
use HTTP::Date;
use Digest::MD5 qw(md5);

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

use Encode;

sub handler_pub {
    my ($self, $env, $handler) = @_;
    my $req = Plack::Request->new($env);
    $env->{'hippie.message'} =
        JSON::from_json($req->parameters->mixed->{'message'}, { utf8 => 1 });
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

    use Web::Hippie::Handle::MXHR;

    return sub {
        my $respond = shift;
        my $fh = $env->{'psgix.io'}
            or return $respond->([ 501, [ "Content-Type", "text/plain" ], [ "This server does not support psgix.io extension" ] ]);

        my $h = AnyEvent::Handle->new( fh => $fh );
        $h->on_eof(   $self->connection_cleanup($env, $handler, $h) );
        $h->on_error( $self->connection_cleanup($env, $handler, $h) );

        # XXX: on_error or on_eof are not triggered if there's no rw events registered
        $h->on_read(sub { die "this should not happen" });

        my $writer = $respond->
            ([ 200,
               [ 'Content-Type' => 'multipart/mixed; boundary="' . $boundary . '"',
                 'Cache-Control' => 'no-cache, must-revalidate',
                 'Pragma' => 'no-cache',
                 'Expires' => HTTP::Date::time2str(0),
                 'Last-Modified' => HTTP::Date::time2str(time())
             ]]);
        $writer->write("--" . $boundary. "\n");
        $env->{'hippie.handle'} = Web::Hippie::Handle::MXHR->new
            ( id       => $client_id,
              boundary => $boundary,
              writer   => $writer );
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

    if ($env->{HTTP_SEC_WEBSOCKET_KEY1}) { # ver 76+

        my $trusted_origin = $self->trusted_origin || '.*';
        if ($env->{HTTP_ORIGIN} !~ m/^$trusted_origin/) {
            $env->{'psgi.errors'}->print("Client origin $env->{HTTP_ORIGIN} not allowed.\n");
            return [403, ['Content-Type' => 'text/plain'], ['origin not allowed']];
        }

        my $ws = $env->{HTTPS} ? 'wss' : 'ws';
        return sub {
            my $respond = shift;
            my $protocol = $env->{HTTP_SEC_WEBSOCKET_PROTOCOL};
            my $request_uri = $req->request_uri;
            my $hs = join "\015\012",
                "HTTP/1.1 101 Web Socket Protocol Handshake",
                "Upgrade: WebSocket",
                "Connection: Upgrade",
                "Sec-WebSocket-Origin: $env->{HTTP_ORIGIN}",
                "Sec-WebSocket-Location: $ws://$env->{HTTP_HOST}$request_uri",
                ($protocol ? "Sec-WebSocket-Protocol: $protocol" : ()),
                '', '';

            my $fh = $env->{'psgix.io'}
                or return $respond->([ 501, [ "Content-Type", "text/plain" ], [ "This server does not support psgix.io extension" ] ]);
            # XXX: it seems AnyEvent::Handle is not happy with the 8
            # bytes already in the buffer, so we have to read it
            # rather than using push_read
            my $key3;
            read $fh, $key3, 8 or warn $!;
            my $h = AnyEvent::Handle->new( fh => $fh, autocork => 1 );

            use Web::Hippie::Handle::WebSocket;
            $env->{'hippie.handle'} = Web::Hippie::Handle::WebSocket->new
                ( id => $client_id,
                  h  => $h );
            $h->on_error( $self->connection_cleanup($env, $handler, $h) );

            my @keys = map {
                my $k = $env->{'HTTP_SEC_WEBSOCKET_KEY'.$_};
                join('', $k =~ m/\d/g) / scalar @{[$k =~ m/ /g]};
            } (1,2);

            $h->push_write($hs);

            $h->push_write(md5(pack('NN', @keys) . $key3));

            $h->on_read(sub {
                            shift->push_read( line => "\xff", sub {
                                                  my ($h, $json) = @_;
                                                  unless ($json =~ s/^\0//) {
                                                      # closing
                                                      return $h->on_error();
                                                  }

                                                  $env->{'hippie.message'} = eval { JSON::decode_json($json) };
                                                  if ($@) {
                                                      warn $@;
                                                      return $h->on_error();
                                                  }

                                                  $env->{'PATH_INFO'} = '/message';
                                                  $handler->($env);
                                              });
                        });

            $env->{'PATH_INFO'} = '/init';
            $handler->($env);

        };
    }


    # XXX v75 is deprecated.  This is intentionally not refactored
    # into common code shared with the above, as this is to be removed at some point.
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

        use Web::Hippie::Handle::WebSocket;
        $env->{'hippie.handle'} = Web::Hippie::Handle::WebSocket->new
            ( id => $client_id,
              h  => $h );
        $h->on_error( $self->connection_cleanup($env, $handler, $h) );

        $h->push_write($hs);

        $h->on_read(sub {
                        shift->push_read( line => "\xff", sub {
                                              my ($h, $json) = @_;
                                              $json =~ s/^\0//;

                                              $env->{'hippie.message'} = eval { JSON::decode_json($json) };
                                              if ($@) {
                                                  warn $@;
                                                  return $h->on_error();
                                              }

                                              $env->{'PATH_INFO'} = '/message';
                                              $handler->($env);
                });
            });

        $env->{'PATH_INFO'} = '/init';
        $handler->($env);
    };
}

sub connection_cleanup {
    my ($self, $env, $handler, $h) = @_;
    return sub {
        $env->{'PATH_INFO'} = '/error';
        $handler->($env);
        $h->destroy;
        undef $env->{'hippie.handle'};
    };
}


1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Web::Hippie - Web toolkit for the long hair, or comet

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
    mount '/_hippie' => builder {
      enable "+Web::Hippie";
      sub { my $env = shift;
            my $args = $env->{'hippie.args'};
            my $handle = $env->{'hippie.handle'};
            # Your handler based on PATH_INFO: /init, /error, /message
      }
    };
    mount '/' => my $app;
  };

=head1 DESCRIPTION

Web::Hippie provides unified persistent and streamy communication
channel over HTTP via websocket (bidirectional) or mxhr
(uni-directional) for your <PSGI> application.  See
L<Web::Hippie::Pipe> for unified bidirectional abstraction with
message bus.

=head1 SEE ALSO

L<Web::Hippie::Pipe>, L<Web::Hippie::App::JSFiles>

=head1 AUTHOR

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
