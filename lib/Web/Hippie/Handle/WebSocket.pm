package Web::Hippie::Handle::WebSocket;
use Class::Accessor::Fast 'antlers';

has id => (is => "ro");
has h => (is => "ro", isa => "AnyEvent::Handle");

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
    $self->h->push_write(("\x00" . JSON::encode_json($msg) . "\xff"));
}

1;
__END__

=head1 NAME

Web::Hippie::Handle::WebSocket - Websocket handler

=cut

