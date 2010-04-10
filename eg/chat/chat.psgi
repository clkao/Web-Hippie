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
use Plack::App::Cascade;
use Web::Hippie::App::JSFiles;

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
        $res->content($mtf->render_file('index.mt', $env));
    } elsif ($req->path =~ m!^/chat!) {
        my $room = ($req->path =~ m!^/chat/(.+)!)[0];
        my $host = $req->header('Host');
        $res->content_type('text/html;charset=utf-8');
        $res->content($mtf->render_file('room.mt', $env, $host, $room));
    } else {
        $res->code(404);
    }

    $res->finalize;
};

builder {
#    enable "JSConcat",
#        files => [<share/*.js>];
#          filter => '/usr/local/bin/jsmin';
    mount '/_hippie' => builder {
        enable "+Web::Hippie";
        enable "+Web::Hippie::Pipe";
        sub {
            my $env = shift;
            my $room = $env->{'hippie.args'};
            my $topic = $env->{'hippie.bus'}->topic($room);

            if ($env->{PATH_INFO} eq '/new_listener') {
                $env->{'hippie.listener'}->subscribe( $topic );
            }
            elsif ($env->{PATH_INFO} eq '/message') {
                my $msg = $env->{'hippie.message'};
                $msg->{time} = time;
                $msg->{address} = $env->{REMOTE_ADDR};
                $topic->publish($msg);
            }
            else {
                my $h = $env->{'hippie.handle'}
                    or return [ '400', [ 'Content-Type' => 'text/plain' ], [ "" ] ];

                if ($env->{PATH_INFO} eq '/error') {
                    warn "==> disconnecting $h";
                }
                else {
                    die "unknown hippie message";
                }
            }
            return [ '200', [ 'Content-Type' => 'application/hippie' ], [ "" ] ]
        };
    };
    mount '/static' =>
        Plack::App::Cascade->new
                ( apps => [ Web::Hippie::App::JSFiles->new->to_app,
                            Plack::App::File->new( root => 'static' )->to_app,
                        ] );
    mount '/' => $app;
};
