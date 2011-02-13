package App::Termcast::Service::Stream;
use Moose;

extends 'Reflex::Stream';

use JSON;

has stream_collection => (
    is       => 'ro',
    isa      => 'Reflex::Collection',
    required => 1,
);

sub on_data {
    my ($self, $args) = @_;

    my $data = JSON::decode_json( $args->{data} );

    $self->handle_server($data);
}

sub handle_server {
    my $self = shift;
    my $data = shift;

    if ($data->{request} eq 'sessions') {
        my %response = (
            response => 'sessions',
            sessions => [
                map {
                +{
                    session_id  => $_->stream_id,
                    user        => $_->user->id,
                    socket      => $_->unix_socket_file,
                    last_active => $_->last_active,
                }
                } values %{$self->stream_collection->objects}
            ],
        );

        my $json = JSON::encode_json(\%response);
        $self->handle->syswrite($json);
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
