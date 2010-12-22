package Web::Hippie::Handle::MXHR;
BEGIN {
    eval "use Class::XSAccessor::Compat 'antlers'; 1" or
    eval "use Class::Accessor::Fast 'antlers'; 1" or die $@;
}
has id => (is => "ro");
has boundary => (is => "ro");
has writer => (is => "ro");

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

    my $json = JSON::encode_json($msg);
    $self->writer->write( "Content-Type: application/json\n\n$json\n--" . $self->boundary. "\n" );
}

1;
__END__

=head1 NAME

Web::Hippie::Handle::MXHR - Multi-part XHR handler

=cut
