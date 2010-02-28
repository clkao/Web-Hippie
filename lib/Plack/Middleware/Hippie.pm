package Plack::Middleware::Hippie;

use strict;
use 5.008_001;
our $VERSION = '0.01';
use parent 'Plack::Middleware';

use Plack::Util::Accessor qw( root init on_error on_message );

sub call {
    my ($self, $env) = @_;

    my $path_match = $self->root or return;
    my $path = $env->{PATH_INFO};

    my ($type, $arg) = $path =~ m|^\Q$path_match\E/(\w+)(?:/(.*))?$|;
    unless ($type) {
        return $self->app->($env);
    }

    my $code = $self->can("handler_$type");
    unless ($code) {
        return $self->app->($env);
    }
    return $code->($self, $env, $arg);
}

sub handler_pub {
    my ($self, $env, $arg) = @_;
    my $req = Plack::Request->new($env);
    $self->on_message->($arg, $req->parameters->mixed);
    my $res = $req->new_response(200);
    $res->finalize;
}

sub handler_mxhr {
    my ($self, $env, $arg) = @_;
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
        my $handle = Plack::Middleware::Hippie::MXHR->new( id => $client_id,
                                                           boundary => $boundary,
                                                           writer => $writer );
        $self->init->($arg, $handle);

    };
}

sub handler_ws {
    my $self = shift;
    my $env = shift;
    my $arg = shift;

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

        my $hs = join "\015\012",
                "HTTP/1.1 101 Web Socket Protocol Handshake",
                "Upgrade: WebSocket",
                "Connection: Upgrade",
                "WebSocket-Origin: $env->{HTTP_ORIGIN}",
                "WebSocket-Location: ws://$env->{HTTP_HOST}$env->{SCRIPT_NAME}$env->{PATH_INFO}",
                '', '';

        my $fh = $env->{'psgix.io'}
            or return $respond->([ 501, [ "Content-Type", "text/plain" ], [ "This server does not support psgix.io extension" ] ]);

        my $h = AnyEvent::Handle->new( fh => $fh );

        use Plack::Middleware::Hippie::WebSocket;
        my $handle = Plack::Middleware::Hippie::WebSocket->new( id => $client_id,
                                                            h => $h);
        $h->on_error( sub { $self->on_error->($arg, $handle); undef $handle } );

        $h->push_write($hs);

        $self->init->($arg, $handle);

        $h->on_read(sub {
                        shift->push_read( line => "\xff", sub {
                                              my ($h, $json) = @_;
                                              $json =~ s/^\0//;

                                              my $data = JSON::decode_json($json);
                                              $self->on_message->($arg, $data);
                });
            });
    };
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Plack::Middleware::Hippie - Plack helpers or the long hair, or comet

=head1 SYNOPSIS

  use Plack::Builder;

  builder {
    enable "Hippie", root => '/_hippie',
        init => sub { my ($arg, $handle) = @_;
                      # ...
                    },
        on_error => sub { my $arg = shift;
                          # ...
                    },
        on_message => sub { my ($arg, $msg) = @_;

                    },

    $app;
  };

=head1 DESCRIPTION

Plack::Middleware::Hippie provides unified bidirectional communication
over HTTP via websocket or xmhr.

=head1 SEE ALSO

L<hippie.js>

=head1 AUTHOR

Chia-liang Kao E<lt>clkao@clkao.orgE<gt>

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

=cut
