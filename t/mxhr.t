use strict;
use warnings;
use File::Path;
use Test::Requires qw(Test::TCP AnyEvent::HTTP::MXHR);
use Test::More;
use Plack::Builder;
use Plack::Loader;
use Time::HiRes 'time';

my $app = builder {
    enable 'Hippie';
    sub { my $env = shift;
          my $args = $env->{'hippie.args'};
          my $handle = $env->{'hippie.handle'};
          # Your handler based on PATH_INFO: /init, /error, /message
          warn "==> reg timer";
          $handle->{w} = AnyEvent->timer(
              interval => 1,
              cb => sub { $handle->send_msg({ type => 'clock', time => time() }) }
          );
    };
};

test_tcp(
    client => sub {
        my $port = shift;
        my $cv = AE::cv;
        my $t  = AE::timer 10, 0, sub { $cv->croak( "timeout" ); };
        my $cnt = 0;
        my $guard = mxhr_get "http://localhost:$port/mxhr", sub {
            my ($body, $headers) = @_;
            if (++$cnt == 3) {
                $cv->send;
            }
            is ($headers->{'content-type'}, 'application/json');
            my $msg = JSON::from_json($body);
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
