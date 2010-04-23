use strict;
use warnings;
use File::Path;
use Test::Requires qw(Test::TCP AnyEvent::HTTP AnyEvent::HTTP::MXHR);
use Test::More;
use Plack::Builder;
use Plack::Loader;
use Time::HiRes 'time';

my @handles;
my $app = builder {
    enable '+Web::Hippie';
    sub { my $env = shift;
          my $args = $env->{'hippie.args'};
          my $handle = $env->{'hippie.handle'};
          # Your handler based on PATH_INFO: /init, /error, /message
          if ($env->{PATH_INFO} eq '/init') {
              $handle->{cnt} = 2;
              $handle->{w} = AnyEvent->timer(
                  interval => 1,
                  cb => sub { $handle->send_msg({ type => 'clock', time => time() });
                              --$handle->{cnt} || delete $handle->{w}
                          }
              );
              push @handles, $handle;
          }
          elsif ($env->{PATH_INFO} eq '/message') {
              my $msg = $env->{'hippie.message'};
              for (@handles) {
                  $_->send_msg({ type => 'broadcast', payload => JSON::to_json($msg) });
              }
          }
          elsif ($env->{PATH_INFO} eq '/error') {
              diag 'client disconnected';
          }
          return [ '200', [ 'Content-Type' => 'application/hippie' ], [ "" ] ]
    };
};

test_tcp(
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $t  = AE::timer 10, 0, sub { $cv->croak( "timeout" ); };
        my $cnt = 0;
        my $http_guard;
        my $guard = mxhr_get "http://localhost:$port/mxhr", sub {
            my ($body, $headers) = @_;
            ++$cnt;
            is ($headers->{'content-type'}, 'application/json', 'mxhr part is json');
            my $msg = JSON::from_json($body);

            if ($cnt == 3) {
                is ($msg->{type}, 'broadcast', 'got broadcast response');
                is_deeply(scalar JSON::from_json($msg->{payload}),
                          { foo1 => 'bar',
                            foo2 => 'baz'},
                          'payload matches');
                $cv->send;
                return;
            }
            elsif ($cnt == 2) {
                my $data = JSON::to_json({foo1 => 'bar', foo2 => 'baz'});
                $http_guard = http_get "http://localhost:$port/pub?message=$data",
                    sub {
                        my ($body, $hdr) = @_;
                        diag $body;
                    };
            }
            is ($msg->{type}, 'clock');
            diag time - $msg->{time};
            # return true if you want to keep reading. return false
            # if you would like to stop
            return 1;
        };
        $cv->recv;
    },
    server => sub {
        my $port = shift;
        Plack::Loader->load( Twiggy => port => $port )->run($app);
    },
);

done_testing;
