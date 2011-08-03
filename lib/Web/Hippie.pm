package Web::Hippie;

use strict;
use 5.008_001;
our $VERSION = '0.38';
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw( on_error on_message trusted_origin );
use AnyEvent;
use AnyEvent::Handle;
use Plack::Request;
use JSON;
use HTTP::Date;
use Digest::MD5 qw(md5);

sub call {
    my ($self, $env) = @_;

    my (undef, $type, $arg) = split('/', $env->{PATH_INFO}, 3);

    $env->{'hippie.args'} = $arg;

    my $code = $self->can("handler_$type");
    unless ($code) {
        $env->{'PATH_INFO'} = "/$type";
        return $self->app->($env);
    }

    return $code->($self, $env, $self->app);

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
            ({ id       => $client_id,
               boundary => $boundary,
               writer   => $writer });
        $env->{'PATH_INFO'} = '/init';

        $handler->($env);
    };
}

use Protocol::WebSocket::Frame;
use Protocol::WebSocket::Handshake::Server;
use Web::Hippie::Handle::WebSocket;

sub handler_ws {
    my ($self, $env, $handler) = @_;

    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    my $trusted_origin = $self->trusted_origin || '.*';
    if ($env->{HTTP_ORIGIN} !~ m/^$trusted_origin/) {
        $env->{'psgi.errors'}->print("Client origin $env->{HTTP_ORIGIN} not allowed.\n");
        return [403, ['Content-Type' => 'text/plain'], ['origin not allowed']];
    }

    my $hs = Protocol::WebSocket::Handshake::Server->new_from_psgi($env);
    my $client_id = $req->param('client_id') || rand(1);

    my $fh = $env->{'psgix.io'}
        or return [ 501, [ "Content-Type", "text/plain" ], [ "This server does not support psgix.io extension" ] ];

    return [ 501, [ "Content-Type", "text/plain" ],
             [ "Failed to initialize websocket" ] ]
        unless $hs->parse($fh);

    return [ 501, [ "Content-Type", "text/plain" ],
             [ "websocket handshake incomplete" ] ]
        unless $hs->is_done;

    my $version = $hs->version;
    my $frame = Protocol::WebSocket::Frame->new(version => $version);

    my $h = AnyEvent::Handle->new( fh => $fh, autocork => 1 );
    return sub {
        my $responder = shift;

        $h->push_write($hs->to_string);
        $h->on_read(sub {
                        shift->push_read(
                            sub {
                                $frame->append($_[0]->rbuf);
                                while (my $message = $frame->next_bytes) {
                                    $env->{'hippie.message'} = eval { JSON::decode_json($message) };
                                    if ($@) {
                                        warn $@;
                                        return $h->on_error();
                                    }

                                    $env->{'PATH_INFO'} = '/message';
                                    $handler->($env);
                                }
                            }
                        );
                    });
        $env->{'hippie.handle'} = Web::Hippie::Handle::WebSocket->new
            ({ id => $client_id,
               version => $version,
               h  => $h });
        $h->on_error( $self->connection_cleanup($env, $handler, $h) );

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
