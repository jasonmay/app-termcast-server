package App::Termcast::Server::UNIX;
use Moose;
use Reflex::Collection;

extends 'Reflex::Acceptor';

has_many sockets => (
    handles => {
        remember_unix_socket => 'remember',
    },
);

has buffer => (
    is  => 'rw',
    isa => 'Str',

    traits  => ['String'],
    default => '',
    handles => {
        add_to_buffer => 'append',
        buffer_length => 'length',
        clear_buffer  => 'clear',
    },
);


has file => (
    is       => 'rw',
    isa      => 'Str',
    required => 1,
);

sub on_accept {
    my ($self, $args) = @_;

    $self->remember_unix_socket(
        Reflex::Stream->new(
            handle => $args->{socket},
            rd     => 1,
        ),
    );

    $args->{socket}->syswrite($self->buffer);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
