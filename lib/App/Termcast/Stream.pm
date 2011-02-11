package App::Termcast::Stream;
use Moose;
use Set::Object;

has termcast_handle => (
    is => 'ro',
    isa => 'AnyEvent::Handle',
    required => 1,
);

has unix_handles => (
    is => 'ro',
    isa => 'Set::Object',
    default => sub { Set::Object::set() },
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
    isa     => 'Str',
    required => 1,
);

has buffer => (
    is  => 'rw',
    isa => 'Str',

    traits  => ['String'],
    default => '',
    handles => {
        add_text      => 'append',
        buffer_length => 'length',
        clear_buffer  => 'clear',
    },
);

has unix_socket_file => (
    is     => 'rw',
    isa    => 'Path::Class::File',
    lazy   => 1,
    coerce => 1,
);

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
