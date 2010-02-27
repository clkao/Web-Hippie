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
builder {
    enable "Static", path => sub { s!^/static/!! }, root => 'static';
    enable "Hippie", root => '/_hippie',
        init => sub {
            my $room = shift;
            my $h = shift;
            my $sub = $bus->new_listener($h->id);
            $sub->subscribe($bus->topic($room));
            $sub->poll(sub { $h->send_msg($_[0]) });
        },
        on_error => sub {
            my $room = shift;
            # $sub->destroyed(1)
        },
        on_message => sub {
            my $room = shift;
            my $msg = shift;
#            $msg->{address} = $req->address;
            $msg->{time} = time;
            $bus->topic($room)->publish($msg);
        }
        ;
    $app;
};
