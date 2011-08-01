#!/usr/bin/env perl
package App::Termcast::Server;

use Reflex::Collection;
use Reflex::Interval;
use Reflex::Trait::Watched;

use Moose;

use KiokuDB;
use KiokuX::User::Util qw(crypt_password);

use Data::UUID::LibUUID;

use App::Termcast::Server::User;
use App::Termcast::Server::Stream;
use App::Termcast::Server::Manager::Stream;
use App::Termcast::Server::UNIX;

use File::Temp qw(tempfile);

use IO qw(Socket::INET Socket::UNIX);

use YAML;

use namespace::autoclean;

# ABSTRACT: core of the Termcast server

extends 'Reflex::Base';

$|++;

=head1 SYNOPSIS

    my $server = App::Termcast::Server->new(
        manager_listener_path => $self->socket,
        termcast_port => $self->port,
    );

    # For a CLI approach, see the documentation for
    # the 'termcast-server' command.

=head1 DESCRIPTION

Familiar with L<http://termcast.org>? If not, it's a managed termcast server
where people can use a termcast client to broadcast their terminal sessions,
viewed by connecting to the server with a telnet client. This module is
inspired by that website, taking the idea of a centralized, headless
Termcast server, decoupled from actual hosted applications for optimal
flexibility.

=head1 ARCHITECTURE

App::Termcast::Server sets up two listening sockets: a TCP socket (default
port: 31337), and a UNIX domain socket (required by you to set up).

=over

=item The TCP socket

The TCP socket is what termcast clients will connect to and send its ANSI
data.

=item The "manager" UNIX socket

This socket communicates with other applications, (telnet apps, web apps, etc.).
It relays information about the broadcasters, i.e. new connections, disconnects,
terminal metadata updates (currently just terminal geometry). You can also ask
for a list of sessions. All communication is done over L<JSON>. A sample of
this communication can be found in C<t/server.t> in this distribution.
Alternatively, you can also use C<App::Termcast::Connector> instead of
processing everything manually.

=item Representative UNIX sockets

This module stores a set of UNIX sockets mapped as a 1:1 representation of
each person broadcasting. Since each session is identified by a UUID, a mapping
of sessions IDs to its represented UNIX socket path can be stored and used
by external applications. This can be done with a simple JSON message to the
manager soceket:

  {"request":"sessions"}

For more details, see C<t/server.t>.

=back

=cut

=attr manager_listener_path

Filepath where the "manager" UNIX socket will be run.

=cut

has manager_listener_path => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

=attr manager_listener

"Manager" UNIX socket where communication between the apps and the broadcasters
occur. By default it is built automatically by using the
C<manager_listener_path> attribute as its peer address.

=cut

has manager_listener => (
    is  => 'ro',
    isa => 'FileHandle',
    lazy => 1,
    builder => '_build_manager_listener',
);

sub _build_manager_listener {
    my $self = shift;

    unlink $self->manager_listener_path;
    my $listener = IO::Socket::UNIX->new(
        Local => $self->manager_listener_path,
        Listen    => 1,
    ) or die $!;

    return $listener;
}

=attr termcast_port

Port to which the broadcasters will point their termcast clients

=cut

has termcast_port => (
    is  => 'ro',
    isa => 'Int',
    default => 31337,
);

=attr termcast_listener

TCP socket to which broadcasters will connect. By default, it is built
automatically using the C<termcast_port> attribute as the remote port.

=cut

has termcast_listener => (
    is  => 'ro',
    isa => 'FileHandle',
    lazy => 1,
    builder => '_build_termcast_listener',
);

sub _build_termcast_listener {
    my $self = shift;

    my $listener = IO::Socket::INET->new(
        LocalPort => $self->termcast_port,
        Listen    => 1,
        Reuse     => 1,
    ) or die $!;

    return $listener;
}

=attr dsn

A KiokuDB-type DSN for where user auth data is stored

=cut

has dsn => (
    is      => 'ro',
    isa     => 'Str',
    default => 'dbi:SQLite:dbname=termcast.sqlite',
);

=attr kiokudb

A L<KiokuDB> object used for the storage logic

=cut

has kiokudb => (
    is       => 'ro',
    isa      => 'KiokuDB',
    builder  => '_build_kiokudb',
    init_arg => undef,
    lazy     => 1,
);

sub _build_kiokudb {
    my $self = shift;
    die "DSN must be provided" unless $self->dsn;
    KiokuDB->connect($self->dsn, create => 1);
}

has config => (
    is  => 'ro',
    isa => 'HashRef',
    default => sub { YAML::LoadFile('etc/config.yml') },
);

has ['termcast_is_active', 'manager_is_active'] => (
    is      => 'ro',
    isa     => 'Bool',
    default => 1
);

has_many streams => (
    handles => {
        remember_stream => 'remember',
        forget_stream   => 'forget',
    },
);

has_many handles => (
    handles => {
        remember_handle => 'remember',
        forget_handle   => 'forget',
    },
);

=for Pod::Coverage config streams handles

=cut

has session_timer => (
    is     => 'ro',
    isa    => 'Reflex::Interval',
    traits => ['Reflex::Trait::Watched'],
    default => sub {
        my $self = shift;
        # TODO stick interval/idle metrics into config
        Reflex::Interval->new(
            interval    => 300,
            auto_repeat => 1,
            on_tick     => sub {
                foreach my $session ($self->streams->get_objects) {
                    my $seconds_idle = time() - $session->last_active;
                    if ($seconds_idle > 3600 * 4) {
                        $session->_disconnect();
                        $session->stopped();
                    }
                }
            },
        );
    }
);

=for Pod::Coverage on_manager_listener_accept on_termcast_listener_accept

=cut

sub on_manager_listener_accept {
    my ($self, $args) = @_;

    $self->remember_handle(
        App::Termcast::Server::Manager::Stream->new(
            handle => $args->{socket},
            stream_collection => $self->streams,
        )
    );
}

sub on_termcast_listener_accept {
    my ($self, $args) = @_;

    my $file = ( tempfile() )[1]; unlink $file;

    my $listener = IO::Socket::UNIX->new(
        Local => $file,
        Listen => 1,
    );

    my $unix = App::Termcast::Server::UNIX->new(
        listener => $listener,
        file     => $file,
    );

    my %stream_params = (
        handle            => $args->{socket},
        handle_collection => $self->handles,
        stream_id         => new_uuid_string(),
        kiokudb           => $self->kiokudb,
        unix              => $unix,
    );

    my $stream = App::Termcast::Server::Stream->new(%stream_params);

    $self->remember_stream($stream);
}

sub on_termcast_listener_error {
    die "@_";
}

sub on_manager_listener_error {
    die "@_";
}

with
    'Reflex::Role::Accepting' => {
        att_listener => 'termcast_listener',
        att_active   => 'termcast_is_active',
    },
    'Reflex::Role::Accepting' => {
        att_listener => 'manager_listener',
        att_active   => 'manager_is_active',
    };

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

