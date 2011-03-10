package App::Termcast::Stream;
use Moose;
use Reflex::Collection;
use Reflex::Stream;
use Try::Tiny;

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
    };
}

sub _send_to_service_handles {
    my $self = shift;
    my $data = shift;

    if (not ref $data) {
        warn "$data is not a reference. Can't be encoded";
        return;
    }

    my @service_handles = values %{$self->handle_collection->objects};

    foreach my $stream (@service_handles) {
        my $json = JSON::encode_json($data);
        $stream->handle->syswrite($json);
    }
}
sub send_connection_notice {
    my $self      = shift;

    my %response = (
        notice     => 'connect',
        connection => $self->property_data,
    );

    $self->_send_to_service_handles(\%response);
}

sub send_disconnection_notice {
    my $self = shift;

    my %response = (
        notice     => 'disconnect',
        session_id => $self->id,
    );

    $self->_send_to_service_handles(\%response);
}

sub on_handle_data {
    my ($self, $args) = @_;

    my $cleared = 0;
    if ($args->{data} =~ s/\e\[H\x00(.*?)\xff\e\[H\e\[2J//) {
        my $metadata;
        if (
            $1 && try { $metadata = JSON::decode_json( $1 ) }
               && ref($metadata)
               && ref($metadata) eq 'HASH'
        ) {
            my %data = (
                notice     => 'metadata',
                session_id => $self->stream_id,
                metadata   => $metadata,
            );

            $self->_send_to_service_handles(\%data);
        }
        #(my $edata = $args->{data}) =~ s/\e/\\e/g;
        #warn $edata;
        $cleared = 1;
    }

    #substr($self->{buffer}, 0, 0) = "\e[H\e[2J" if $cleared;


    $_->handle->syswrite($args->{data}) for values %{ $self->unix_sockets->objects };
    $self->add_to_buffer($args->{data});

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
