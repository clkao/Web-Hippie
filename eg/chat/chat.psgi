#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

use Pod::Usage;

use AnyEvent::Socket;
use AnyEvent::Handle;
use Text::MicroTemplate::File;
use Path::Class qw/file dir/;
use JSON;
use Plack::Request;
use Plack::Builder;
use AnyMQ;

my $mtf = Text::MicroTemplate::File->new(
    include_path => ["templates"],
);

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    if ($req->path eq '/') {
        $res->content_type('text/html; charset=utf-8');
        $res->content($mtf->render_file('index.mt'));
    } elsif ($req->path =~ m!^/chat!) {
        my $room = ($req->path =~ m!^/chat/(.+)!)[0];
        my $host = $req->header('Host');
        $res->content_type('text/html;charset=utf-8');
        $res->content($mtf->render_file('room.mt', $host, $room));
    } else {
        $res->code(404);
    }

    $res->finalize;
};

my $bus = AnyMQ->new;
my $client_mgr;
builder {
    mount '/_hippie' => builder {
        enable "Hippie";
        sub {
            my $env = shift;
            my $room = $env->{'hippie.args'};
            my $topic = $bus->topic($room);

            if ($env->{PATH_INFO} eq '/message') {
                my $msg = $env->{'hippie.message'};
                $msg->{time} = time;
                $msg->{address} = $env->{REMOTE_ADDR};
                $topic->publish($msg);
            }
            elsif ($env->{PATH_INFO} eq '/poll') {
                # XXX: probably fatal here for not having client_id.
                my $client_id = Plack::Request->new($env)->param('client_id') || rand(1);
                my $sub = $client_mgr->{$client_id} ||= $bus->new_listener( $topic );
                # XXX the recycling should be done in anymq
                $sub = $bus->new_listener( $topic ) if $sub->destroyed;
                return sub {
                    my $responder = shift;
                    my $writer = $responder->([200, [ 'Content-Type' => 'application/json']]);
                    # XXX: callback for nuregistering clieng_mgr not yet invoked.
                    $sub->poll_once(sub { $writer->write(JSON::encode_json(\@_));
                                          $writer->close },
                                    30,
                                    sub { delete $client_mgr->{$client_id} },
                                );
                }
            }
            else {
                my $h = $env->{'hippie.handle'}
                    or return [ '400', [ 'Content-Type' => 'text/plain' ], [ "" ] ];

                if ($env->{PATH_INFO} eq '/init') {
                    my $sub = $bus->new_listener( $topic );
                    $sub->poll(sub { $h->send_msg($_[0]) });
                }
                elsif ($env->{PATH_INFO} eq '/error') {
                    warn "==> disconnecting $h";
                }
                else {
                    die "unknown hippie message";
                }
            }
            return [ '200', [ 'Content-Type' => 'text/plain' ], [ "" ] ]
        };
    };
    mount '/' => builder {
        enable "Static", path => sub { s!^/static/!! }, root => 'static';
        $app;
    };
};
