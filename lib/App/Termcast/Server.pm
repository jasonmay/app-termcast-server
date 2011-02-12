#!/usr/bin/env perl
package App::Termcast::Server;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Moose;
use KiokuDB;
use KiokuX::User::Util qw(crypt_password);

use Set::Object;

use Data::UUID::LibUUID;

use App::Termcast::User;

use Scalar::Util qw(weaken);

use File::Temp qw(tempfile);

use namespace::autoclean;

$|++;

=head1 NAME

App::Termcast::Server - a centralized, all-purpose termcast server

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

=cut

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

has termcasts => (
    is      => 'ro',
    isa     => 'HashRef',
    traits  => ['Hash'],
    default => sub { +{} },
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
    KiokuDB->connect($self->dsn);
}

# fd => Stream object
has streams => (
    is      => 'rw',
    isa     => 'HashRef[App::Termcast::Stream]',
    traits  => ['Hash'],
    default => sub { +{} },
    handles => {
        delete_stream => 'delete',
        stream        => 'get',
    }
);

has timer => (
    is  => 'ro',
    builder => '_build_timer',
);

has server_handles => (
    is      => 'ro',
    isa     => 'Set::Object',
    default => sub { Set::Object::set() },
);

sub _build_timer {
    my $self = shift;
    AE::timer 0, 2, sub {
        # XXX XXX XXX XXX
        #foreach my $handle ($self->termcast_handle_list) {
        #    $self->shorten_buffer($handle);
        #}
    };
}


sub BUILD {
    my $self = shift;

    weaken(my $weakself = $self);
    tcp_server undef, $self->termcast_port, sub {
        my ($fh, $host, $port) = @_;
        my $h = AnyEvent::Handle->new(
            fh => $fh,
            on_read => sub {
                my $h = shift;
                $weakself->handle_termcast($h);
            },
            on_error => sub {
                my ($h, $fatal, $error) = @_;

                if ($fatal) {
                    my $fd = fileno $h->fh;
                    $weakself->delete_stream($fd);
                    $weakself->send_disconnection_notice($fd);

                    $_->destroy for $self->stream($fd)->unix_handles->members;

                    $h->destroy;
                }
                else {
                    warn $error;
                }
            },
        );
        my $user_object;

        $self->handle_metadata($h) or return;

        my $file = ( tempfile() )[1];

        # create stream object before unlinking $file
        # so type checking on socket_file doesn't explode
        my $stream
        = $self->streams->{fileno $h->fh}
        = App::Termcast::Stream->new(
            user        => $user_object,
            id          => new_uuid_string(),
            socket_file => $file,
        );

        unlink $file; # tempfile() generated
        tcp_server 'unix/', $file, sub {
            my ($fh, $host, $port) = @_;

            my $u_h = AnyEvent::Handle->new(
                fh => $fh,
                on_error => sub {
                    my ($u_h, $fatal, $error) = @_;
                    $stream->unix_handles->remove($u_h);
                    if ($fatal) {
                        $u_h->destroy;
                        unlink $file;
                    }
                    else {
                        warn $error;
                    }
                },
            );

            #catch up
            syswrite($u_h->fh, $stream->buffer);

            $stream->unix_handles->insert($u_h);
        };

        $self->send_connection_notice($h);
    };

    tcp_server 'unix/', $self->server_socket, sub {
        my ($fh, $host, $port) = @_;
        my $h = AnyEvent::Handle->new(
            fh => $fh,
            on_read => sub {
                my $h = shift;
                $self->handle_server($h);
            },
            on_error => sub {
                my ($h, $fatal, $error) = @_;

                if ($fatal) {
                    $h->destroy;
                }
                else {
                    warn $error;
                }
            }
        );
        my $handle_id = new_uuid_string();

        $self->server_handles->insert($h);
    };
}

sub shorten_buffer {
    my $self = shift;
    my $handle = shift;

    return unless $handle->session;
    $handle->session->fix_buffer_length();
    $handle->session->{buffer} =~ s/.+\e\[2J//s;
}

sub handle_termcast {
    my $self = shift;
    my $h    = shift;

    my $session = $h->session;

    $session->add_text($h->rbuf);
    $session->mark_active();

    for ($session->stream_handles->members) {
        syswrite($_->fh, $h->rbuf);
    }

    $h->{rbuf} = '';
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

    my $get_next_line;

    my %properties;

    my $settings_threshold = 30; # 30 lines of settings should be plenty
    my $settings_lines = 0;

    my $returned_line;
    do {
        my $cv = AnyEvent->condvar;
        $handle->push_read(
            line => sub {
                my ($handle, $line) = @_;

                ++$settings_lines;
                my ($key, $value) = split ' ', $line, 2;
                $properties{$key} = $value;

                $returned_line = $line;
                $cv->send;
            }
        );
        $cv->recv();
    } until lc($returned_line) eq 'finish'
        or $settings_lines > $settings_threshold;

    while (my ($p_key, $p_value) = each %properties) {
        $self->dispatch_metadata($handle, $p_key, $p_value)
        or do {
            $handle->destroy;
            return undef;
        };
    }
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

    if ($user_object->check_password($pass)) {
        warn "Authentication failed";
        $self->delete_stream(fileno $handle->fh);
        $handle->destroy;
        return undef;
    }
    else {
        return $user_object;
    }
}

sub handle_server {
    my $self = shift;
    my $handle = shift;

    $handle->push_read(
        json => sub {
            my ($h, $data) = @_;

            if ($data->{request} eq 'sessions') {
                $h->push_write(
                    json => {
                        response => 'sessions',
                        sessions => [
                            map {
                            +{
                                session_id  => $_->id,
                                user        => $_->user->id,
                                socket      => $_->stream_socket->stringify,
                                last_active => $_->last_active,
                            }
                            } values %{$self->streams}
                        ],
                    }
                );
            }
        }
    );
}

sub send_connection_notice {
    my $self      = shift;
    my $handle = shift;

    my $stream = $self->stream(fileno $handle->fh);
    my $data = {
        session_id  => $stream->id,
        user        => $stream->user->id,
        socket      => $stream->unix_socket_file->stringify,
        last_active => $stream->last_active,
    };

    foreach my $handle ($self->server_handle_list) {
        $handle->push_write(
            json => {
                notice     => 'connect',
                connection => $data,
            }
        );
    }
}

sub send_disconnection_notice {
    my $self      = shift;
    my $stream_id = shift;

    foreach my $server_handle ($self->server_handles->members) {
        $server_handle->push_write(
            json => {
                notice     => 'disconnect',
                session_id => $stream_id,
            }
        );
    }
}

sub run {
    AE::cv->recv;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

