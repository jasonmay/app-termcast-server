#!::usr::bin::env perl
package App::Termcast::Server;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Moose;
use KiokuDB;
use KiokuX::User::Util qw(crypt_password);

use Set::Object;

use Data::UUID::LibUUID;

use App::Termcast::Session;
use App::Termcast::User;
use App::Termcast::Handle;

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

has server_port => (
    is      => 'ro',
    isa     => 'Int',
    default => 9092,
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

has termcast_handles => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    handles => {
        set_termcast_handle    => 'set',
        get_termcast_handle    => 'get',
        delete_termcast_handle => 'delete',
        termcast_handle_ids    => 'keys',
        termcast_handle_list   => 'values',
    },
    default => sub { +{} },
);

has server_handles => (
    is      => 'rw',
    isa     => 'HashRef',
    traits  => ['Hash'],
    handles => {
        set_server_handle    => 'set',
        get_server_handle    => 'get',
        delete_server_handle => 'delete',
        server_handle_ids    => 'keys',
        server_handle_list   => 'values',
    },
    default => sub { +{} },
);

has timer => (
    is  => 'ro',
    builder => '_build_timer',
);

sub _build_timer {
    my $self = shift;
    AE::timer 0, 2, sub {
        foreach my $handle ($self->termcast_handle_list) {
            $self->shorten_buffer($handle);
        }
    };
}


sub BUILD {
    my $self = shift;

    weaken(my $weakself = $self);
    tcp_server undef, $self->termcast_port, sub {
        my ($fh, $host, $port) = @_;
        my $h = App::Termcast::Handle->new(
            fh => $fh,
            on_read => sub {
                my $h = shift;
                $weakself->handle_termcast($h);
            },
            on_error => sub {
                my ($h, $fatal, $error) = @_;

                if ($fatal) {
                    $weakself->delete_termcast_handle($h->handle_id);
                    $weakself->send_disconnection_notice($h->handle_id);

                    $_->destroy for $h->session->stream_handles->members;

                    unlink $h->handle_id;
                    $h->destroy;
                }
                else {
                    warn $error;
                }
            },
            handle_id => new_uuid_string(),
        );
        my $cv = AnyEvent->condvar;
        my $user_object;

        $self->set_termcast_handle($h->handle_id => $h);

        $h->push_read(
            line => sub {
                my ($h, $line) = @_;
                chomp $line;
                my $user_object = $self->handle_auth($h, $line);
                #$cv->send;
                if (not defined $user_object) {
                    warn "Authentication failed";
                    $self->delete_termcast_handle($h->handle_id);
                    $h->destroy;
                }
                else {
                    my $session = App::Termcast::Session->with_traits(
                        'App::Termcast::SessionData',
                    )->new(
                        user => $user_object,
                    );

                    $h->session($session);


                    (undef, my $file) = tempfile();
                    unlink $file;
                    tcp_server 'unix/', $file, sub {
                        my ($fh, $host, $port) = @_;

                        # we want to close over data from $h
                        my $u_h = AnyEvent::Handle->new(
                            fh => $fh,
                            on_error => sub {
                                my ($u_h, $fatal, $error) = @_;
                                $h->session->stream_handles->remove($u_h);
                                if ($fatal) {
                                    $u_h->destroy;
                                }
                                else {
                                    warn $error;
                                }
                            },
                        );

                        #catch up
                        $u_h->push_write($h->session->buffer);

                        $self->get_termcast_handle($h->handle_id)->session->stream_handles->insert($u_h);
                    };

                    require Path::Class::File;
                    $self->get_termcast_handle($h->handle_id)->session->stream_socket($file);
                    $self->send_connection_notice($h->handle_id);
                }
            },
        );

    };

    tcp_server undef, $self->server_port, sub {
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

        $self->set_server_handle($handle_id => $h);
    };
}

sub shorten_buffer {
    my $self = shift;
    my $handle = shift;

    my $buffer = $handle->session->buffer;
    $handle->session->fix_buffer_length();
    $buffer =~ s/.+\e\[2[HJ]//sm
        and $handle->session->buffer($buffer);
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

sub handle_auth {
    my $self   = shift;
    my $handle = shift;
    my $line   = shift;

    my ($user, $pass) = $line =~ /hello \s+ (\S+) \s+ (\S+)/x;

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
                            my $tc_handle = $self->get_termcast_handle($_);

                            +{
                                session_id => $_,
                                user       => $tc_handle->session->user->id,
                                socket     => $tc_handle->session->stream_socket->stringify,
                                last_active => $tc_handle->session->last_active,
                            }
                            } $self->termcast_handle_ids
                        ],
                    }
                );
            }
        }
    );
}

sub send_connection_notice {
    my $self      = shift;
    my $handle_id = shift;

    my $data = {
        session_id => $handle_id,
        user       => $self->get_termcast_handle($handle_id)->session->user->id,
        socket     => $self->get_termcast_handle($handle_id)->session->stream_socket->stringify,
        last_active => $self->get_termcast_handle($handle_id)->session->last_active,
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
    my $handle_id = shift;

    foreach my $handle ($self->server_handle_list) {
        $handle->push_write(
            json => {
                notice     => 'disconnect',
                session_id => $handle_id,
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

