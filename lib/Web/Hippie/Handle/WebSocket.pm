package Web::Hippie::Handle::WebSocket;

use strict;
use warnings;
use Web::Hippie;

BEGIN {
    eval "use Class::XSAccessor::Compat 'antlers'; 1" or
    eval "use Class::Accessor::Fast 'antlers'; 1" or die $@;
}

has h => (is => "ro", isa => "AnyEvent::Handle");
has version => (is => "rw", isa => "Str");

sub new {
    my $class = shift;
    unless (ref $_[0] eq 'HASH') {
        Carp::carp "use of hash in constructor is deprecated. use hashref please instead.";
        @_ = { @_ };
    }
    return $class->SUPER::new(@_);
}

sub send_msg {
    my ($self, $msg) = @_;

    my $bytes = Protocol::WebSocket::Frame->new
        ( buffer => Web::Hippie->encode_message($msg),
          version => $self->version)->to_bytes;
    $self->h->push_write($bytes);
}

1;
__END__

=head1 NAME

Web::Hippie::Handle::WebSocket - Websocket handler

=cut

