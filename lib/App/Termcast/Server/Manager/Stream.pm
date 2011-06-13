package App::Termcast::Server::Manager::Stream;
use Moose;
# ABSTRACT: Reflex stream for manager socket I/O

extends 'Reflex::Stream';

use JSON;

has stream_collection => (
    is       => 'ro',
    isa      => 'Reflex::Collection',
    required => 1,
);

has json => (
    is      => 'ro',
    isa     => 'JSON',
    default => sub { JSON->new },
    lazy    => 1,
);

=for Pod::Coverage on_data handle_server

=cut

sub on_data {
    my ($self, $args) = @_;

    my @data = $self->json->incr_parse($args->{data});

    $self->handle_server($_) for @data;
}

sub handle_server {
    my $self = shift;
    my $data = shift;

    if ($data->{request} eq 'sessions') {
        my %response = (
            response => 'sessions',
            sessions => [
                map {
                $_->property_data
                } values %{$self->stream_collection->objects}
            ],
        );

        my $json = $self->json->encode(\%response);
        $self->handle->syswrite($json);
    }
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
