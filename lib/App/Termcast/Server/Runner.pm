package App::Termcast::Server::Runner;
use Moose;

use App::Termcast::Server;

# ABSTRACT: getopt layer for the temcast-server command

with 'MooseX::Getopt';

has socket => (
    is            => 'ro',
    isa           => 'Str',
    required      => 1,
    documentation => 'UNIX domain socket path for components to connect to',
);

has port => (
    is            => 'ro',
    isa           => 'Int',
    default       => 31337,
    documentation => 'TCP port that streamers will use termcast to connect to',
);

=for Pod::Coverage run

=cut

sub run {
    my $self = shift;

    my $server = App::Termcast::Server->new(
        manager_listener_path => $self->socket,
        termcast_port => $self->port,
    );

    $server->run_all();
}

no Moose;

1;
