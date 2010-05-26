#!/usr/bin/env perl
use strict;
use warnings;

use Plack::Request;
use Plack::Builder;
use Plack::App::Cascade;
use Web::Hippie::App::JSFiles;

my $app = sub {
    my $env = shift;
    my $req = Plack::Request->new($env);
    my $res = $req->new_response(200);

    if ($req->path eq '/') {
        $res->redirect('/static/index.html');
    } else {
        $res->code(404);
    }

    $res->finalize;
};

builder {
    mount '/_hippie' => builder {
        enable "+Web::Hippie";
        sub {
            my $env = shift;
            my $interval = $env->{'hippie.args'} || 5;
            my $h = $env->{'hippie.handle'};

            if ($env->{PATH_INFO} eq '/init') {
                my $w; $w = AnyEvent->timer( interval => $interval,
                                             cb => sub {
                                                 $h->send_msg({
                                                     type => 'timer',
                                                     time => AnyEvent->now,
                                                 });
                                                 $w;
                                             });
            }
            elsif ($env->{PATH_INFO} eq '/message') {
                my $msg = $env->{'hippie.message'};
                warn "==> got msg from client: ".Dumper($msg);
            }
            else {
                return [ '400', [ 'Content-Type' => 'text/plain' ], [ "" ] ]
                    unless $h;

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
