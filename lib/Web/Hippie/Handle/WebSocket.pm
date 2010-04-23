package Web::Hippie::Handle::WebSocket;
use Moose;

has id => (is => "ro");
has h => (is => "ro", isa => "AnyEvent::Handle");

sub send_msg {
    my ($self, $msg) = @_;
    $self->h->push_write(("\x00" . JSON::encode_json($msg) . "\xff"));
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

=head1 NAME

Web::Hippie::Handle::WebSocket - Websocket handler

=cut

