#!/usr/bin/env perl
package App::Termcast::Server;

use Reflex::Collection;

use Moose;

use KiokuDB;
use KiokuX::User::Util qw(crypt_password);

use Data::UUID::LibUUID;

use App::Termcast::User;
use App::Termcast::Stream;
use App::Termcast::Manager::Stream;
use App::Termcast::Server::UNIX;

use File::Temp qw(tempfile);

use IO qw(Socket::INET Socket::UNIX);

use YAML;

use namespace::autoclean;

# ABSTRACT: core of the Termcast server

extends 'Reflex::Base';

with 'Reflex::Role::Accepting' => { listener => 'termcast_listener' },
     'Reflex::Role::Accepting' => { listener => 'manager_listener'  };

$|++;

=head1 NAME

App::Termcast::Server - a centralized, all-purpose termcast server

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

=cut

has manager_listener_path => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

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

has termcast_port => (
    is  => 'ro',
    isa => 'Int',
    default => 31337,
);

has dsn => (
    is      => 'ro',
    isa     => 'Str',
    default => 'dbi:SQLite:dbname=termcast.sqlite',
);

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

# TODO: session timer?

sub on_manager_listener_accept {
    my ($self, $args) = @_;

    $self->remember_handle(
        App::Termcast::Manager::Stream->new(
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

    my $stream = App::Termcast::Stream->new(%stream_params);

    $self->remember_stream($stream);

}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

