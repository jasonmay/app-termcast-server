#!/usr/bin/env perl
package App::Termcast::Server;

use Reflex::Collection;

use Moose;

use KiokuDB;
use KiokuX::User::Util qw(crypt_password);

use Data::UUID::LibUUID;

use App::Termcast::User;
use App::Termcast::Stream;
use App::Termcast::Service::Stream;

use File::Temp qw(tempfile);

use IO qw(Socket::INET Socket::UNIX);

use namespace::autoclean;

extends 'Reflex::Base';

with 'Reflex::Role::Accepting' => { listener => 'termcast_listener' },
     'Reflex::Role::Accepting' => { listener => 'service_listener'  };

$|++;

=head1 NAME

App::Termcast::Server - a centralized, all-purpose termcast server

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

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
    );

    return $listener;
}

has service_listener => (
    is  => 'ro',
    isa => 'FileHandle',
    lazy => 1,
    builder => '_build_service_listener',
);


sub _build_service_listener {
    my $self = shift;

    unlink $self->server_socket;
    my $listener = IO::Socket::UNIX->new(
        Local => $self->server_socket,
        Listen    => 1,
    ) or die $!;

    return $listener;
}

has termcast_port => (
    is  => 'ro',
    isa => 'Int',
    default => 31337,
);

has server_socket => (
    is      => 'ro',
    isa     => 'Str',
    default => 'connections.sock',
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

has_many streams => (
    handles => {
        remember_stream => 'remember',
        forget_stream   => 'forget',
    }
);

has_many handles => (
    handles => {
        remember_handle => 'remember',
        forget_handle   => 'forget',
    }
);

# TODO: session timer?

sub on_service_listener_accept {
    warn "on_service_listener_accept";
    my ($self, $args) = @_;

    $self->remember_handle(
        App::Termcast::Service::Stream->new(
            handle => $args->{socket},
            stream_collection => $self->streams,
        )
    );
}

sub on_termcast_listener_accept {
    warn "on_termcast_listener_accept";
    my ($self, $args) = @_;

    # handle metadata here
    $self->handle_metadata($args->{socket})
        or do { close $args->{socket}; return };

    my $file = ( tempfile() )[1]; unlink $file;

    my $listener = IO::Socket::UNIX->new(
        Local => $file,
        Listen => 1,
    );

    # FIXME
    my $user_object = $self->handle_auth($args->{socket}, 'anon asdf');

    $self->remember_stream(
        App::Termcast::Stream->new(
            handle      => $args->{socket},
            listener    => $listener,
            user        => $user_object,
            handle_collection => $self->handles,
            stream_id    => new_uuid_string(),
            unix_socket_file => $file,
        )
    );
}

sub shorten_buffer {
    my $self = shift;
    my $handle = shift;

    return unless $handle->session;
    $handle->session->fix_buffer_length();
    $handle->session->{buffer} =~ s/.+\e\[2J//s;
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

sub handle_metadata {
    my $self   = shift;
    my $handle = shift;

    return 1; #XXX
    #my $get_next_line;

    #my %properties;

    #my $settings_threshold = 30; # 30 lines of settings should be plenty
    #my $settings_lines = 0;

    #my $returned_line;
    #my $buf;
    #do {
    #    chomp( $buf = $handle->sysread() );

    #    ++$settings_lines;

    #    my ($key, $value) = split ' ', $buf, 2;
    #    $properties{$key} = $value;

    #} until lc($buf) eq 'finish'
    #    or $settings_lines > $settings_threshold;

    #while (my ($p_key, $p_value) = each %properties) {
    #    $self->dispatch_metadata($handle, $p_key, $p_value)
    #    or do {
    #        close $handle;
    #        return undef;
    #    };
    #}
}

sub dispatch_metadata {
    my $self = shift;
    my ($handle, $property_key, $property_value) = @_;

    my %dispatch = (

        hello => sub {
            return $self->handle_auth($handle, $property_value);
        },

        geometry => sub {
        }
    );
}

sub handle_geometry {
    my $self = shift;
    my $line = shift;

    my ($cols, $lines) = $line =~ /(\S+) \s+ (\S+)/x;
    #TODO
}

sub handle_auth {
    my $self   = shift;
    my $handle = shift;
    my $line   = shift;

    my ($user, $pass) = $line =~ /(\S+) \s+ (\S+)/x;

    my $user_object;
    {
        my $scope = $self->kiokudb->new_scope;
        $user_object = $self->kiokudb->lookup($user)
                    || $self->create_user($user, $pass);
    }

    # XXX probably no crypt_password here
    if ($user_object->check_password(crypt_password $pass)) {
        warn "Authentication failed";
        $handle->close();
        return undef;
    }
    else {
        return $user_object;
    }
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

