package App::Termcast::Server::Runner;
use Moose;
use YAML;

use App::Termcast::Server;

# ABSTRACT: getopt layer for the temcast-server command

with 'MooseX::Getopt';

has _config => (
    is  => 'ro',
    isa => 'HashRef',
    default => sub { YAML::LoadFile('etc/config.yml') },
    traits => ['NoGetopt'],
);

has socket => (
    is            => 'ro',
    isa           => 'Str',
    lazy          => 1,
    builder       => '_build_socket',
    documentation => 'UNIX domain socket path for components to connect to',
);

sub _build_socket {
    my $self = shift;
    return $self->_config->{socket};
}

has port => (
    is            => 'ro',
    isa           => 'Int',
    default       => 31337,
    documentation => 'TCP port that streamers will use termcast to connect to',
);

has interval => (
    is      => 'ro',
    isa     => 'Num',
    default => 0,
);

=for Pod::Coverage run

=cut

sub run {
    my $self = shift;

    my $server = App::Termcast::Server->new(
        manager_listener_path => $self->socket,
        termcast_port         => $self->port,
        interval              => $self->interval,
    );

    $server->run_all();
}

no Moose;

1;
