package App::Termcast::Stream;
use Moose;
use Reflex::Collection;
use Reflex::Stream;
use Try::Tiny;

use KiokuX::User::Util qw(crypt_password);

extends 'Reflex::Stream';

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

has kiokudb => (
    is       => 'ro',
    isa      => 'KiokuDB',
    required => 1,
);

has user => (
    is       => 'rw',
    isa      => 'App::Termcast::User',
);

# pass this down for reference
has handle_collection => (
    is     => 'ro',
    isa    => 'Reflex::Collection',
    required => 1,
);

has last_active => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { time() },
);

has unix => (
    is       => 'ro',
    isa      => 'App::Termcast::Server::UNIX',
    required => 1,
);


sub property_data {
    my $self = shift;

    return {
            session_id  => $self->stream_id,
            user        => $self->user->id,
            socket      => $self->unix->file,
            geometry    => [$self->cols, $self->lines],
            last_active => $self->last_active,
    };
}

sub _send_to_manager_handles {
    my $self = shift;
    my $data = shift;

    if (not ref $data) {
        warn "$data is not a reference. Can't be encoded";
        return;
    }

    my @manager_handles = values %{$self->handle_collection->objects};

    my $json = JSON::encode_json($data);
    foreach my $stream (@manager_handles) {
        $stream->handle->syswrite($json);
    }
}
sub send_connection_notice {
    my $self      = shift;

    my %response = (
        notice     => 'connect',
        connection => $self->property_data,
    );

    $self->_send_to_manager_handles(\%response);
}

sub send_disconnection_notice {
    my $self = shift;

    my %response = (
        notice     => 'disconnect',
        session_id => $self->stream_id,
    );

    $self->_send_to_manager_handles(\%response);
}

sub on_data {
    my ($self, $args) = @_;

    if (!$self->user) {
        (my $auth_line, $args->{data}) = split /\n/, $args->{data}, 2;
        my $user = $self->handle_auth($auth_line) or do {
            $self->stopped();
            return;
        };

        $self->handle->syswrite("hello, ".$user->id."\n");
        $self->user($user);

        $self->send_connection_notice;
    }

    my $cleared = 0;
    if ($args->{data} =~ s/\e\[H\x00(.*?)\xff\e\[H\e\[2J//) {
        my $metadata;
        if (
            $1 && try { $metadata = JSON::decode_json( $1 ) }
               && ref($metadata)
               && ref($metadata) eq 'HASH'
        ) {
            $self->handle_metadata($metadata);

            my %data = (
                notice     => 'metadata',
                session_id => $self->stream_id,
                metadata   => $metadata,
            );

            $self->_send_to_manager_handles(\%data);
        }
        $cleared = 1;
    }

    $_->handle->syswrite($args->{data}) for values %{ $self->unix->sockets->objects };
    $self->unix->add_to_buffer($args->{data});

    $self->shorten_buffer();

    $self->mark_active();
}

sub handle_metadata {
    my $self     = shift;
    my $metadata = shift;

    return unless ref($metadata) eq 'HASH';

    if ($metadata->{geometry}) {
        $self->handle_geometry($metadata);
    }
}

sub handle_geometry {
    my $self     = shift;
    my $metadata = shift;

    my ($cols, $lines) = @{ $metadata->{geometry} };

    $self->cols($cols);
    $self->lines($lines);
}

sub handle_auth {
    my $self   = shift;
    my $line   = shift;

    my ($type, $user, $pass) = split(' ', $line, 3);

    return unless $type eq 'hello';

    my $user_object;
    {
        my $scope = $self->kiokudb->new_scope;
        $user_object = $self->kiokudb->lookup($user)
                    || $self->create_user($user, $pass);
    }

    if ($user_object->check_password($pass)) {
        return $user_object;
    }
    else {
        return undef;
    }
}

sub create_user {
    my $self = shift;
    my $user = shift;
    my $pass = shift;

    my $user_object;

    $user_object = App::Termcast::User->new(
        id       => $user,
        password => crypt_password($pass),
    );

    {
        my $s = $self->kiokudb->new_scope;
        $self->kiokudb->store($user => $user_object);
    }

    return $user_object;
}

sub _disconnect {
    my ($self) = @_;
    $self->send_disconnection_notice();
    $_->stopped() for values %{ $self->unix->sockets->objects };
}
sub on_closed {
    my ($self, $args) = @_;
    $self->_disconnect();
    $self->stopped();
}

sub on_error {
    my ($self, $args) = @_;
    $self->_disconnect();
}

sub shorten_buffer {
    my $self = shift;

    $self->fix_buffer_length();
    $self->unix->{buffer} =~ s/.+\e\[2J//s;
}

sub fix_buffer_length {
    my $self = shift;
    my $len = $self->unix->buffer_length;
    if ($len > 51_200) {
        substr($self->unix->{buffer}, 0, $len-51_200) = '';
    }
}

sub mark_active { shift->last_active( time() ); }

__PACKAGE__->meta->make_immutable;
no Moose;

1;
