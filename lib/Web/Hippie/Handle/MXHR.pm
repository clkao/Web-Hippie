package Web::Hippie::Handle::MXHR;
use Moose;

has id => (is => "ro");
has boundary => (is => "ro");
has writer => (is => "ro");

sub send_msg {
    my ($self, $msg) = @_;

    my $json = JSON::encode_json($msg);
    $self->writer->write( "Content-Type: application/json\n\n$json\n--" . $self->boundary. "\n" );
}

__PACKAGE__->meta->make_immutable;
no Moose;
1;
__END__

=head1 NAME

Web::Hippie::Handle::MXHR - Multi-part XHR handler

=cut
