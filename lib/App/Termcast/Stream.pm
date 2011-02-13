package App::Termcast::Stream;
use Moose;
use Reflex::Collection;
use Reflex::Stream;

extends 'Reflex::Base';

with 'Reflex::Role::Accepting', 'Reflex::Role::Streaming';

has handle => (
    is        => 'rw',
    isa       => 'FileHandle',
    required  => 1,
);

has listener => (
    is        => 'rw',
    isa       => 'FileHandle',
    required  => 1,
);

has_many unix_sockets => (
    handles => {
        remember_unix_socket => 'remember',
    },
);

has stream_id => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

has lines => (
    is => 'rw',
    isa => 'Num',
    default => 24,
);

has cols => (
    is => 'rw',
    isa => 'Num',
    default => 80,
);

has user => (
    is      => 'ro',
    isa     => 'App::Termcast::User',
    required => 1,
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

has unix_socket_file => (
    is     => 'rw',
    isa    => 'Str',
);

# pass this down for reference
has handle_collection => (
    is     => 'ro',
    isa    => 'Reflex::Collection',
    required => 1,
);

sub on_listener_accept {
    my ($self, $args) = @_;

    $self->remember_unix_socket(
        Reflex::Stream->new(
            handle => $args->{socket},
            rd     => 1,
        ),
    );

    $args->{socket}->syswrite($self->buffer);
}

sub property_data {
    my $self = shift;
    return {
            session_id  => $self->stream_id,
            user        => $self->user->id,
            socket      => $self->unix_socket_file,
            last_active => $self->last_active,
            geometry    => [$self->cols, $self->lines],
    };
}

sub send_connection_notice {
    my $self      = shift;

    my %response = (
        notice     => 'connect',
        connection => $self->property_data,
    );

    foreach my $stream ( values %{$self->handle_collection->objects} ) {
        my $json = JSON::encode_json(\%response);
        $stream->handle->syswrite($json);
    }
}

sub send_disconnection_notice {
    my $self = shift;

    foreach my $handle (values %{$self->handle_collection->objects} ) {
        my %response = (
            notice     => 'disconnect',
            session_id => $self->id,
        );

        my $json = JSON::encode_json(\%response);
        $handle->syswrite($json);
    }
}

sub on_handle_data {
    my ($self, $args) = @_;

    $self->add_to_buffer($args->{data});
    $_->handle->syswrite($args->{data}) for values %{ $self->unix_sockets->objects };

    $self->mark_active();
}

sub on_handle_error {
    my ($self, $args) = @_;
    warn "error";

    $self->send_disconnection_notice(fileno $args->{socket});
    $_->close() for values %{ $self->unix_sockets->objects };
}

sub fix_buffer_length {
    my $self = shift;
    my $len = $self->buffer_length;
    if ($len > 51_200) {
        substr($self->{buffer}, 0, $len-51_200) = '';
    }
}

has last_active => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { time() },
);

sub mark_active { shift->last_active( time() ); }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
