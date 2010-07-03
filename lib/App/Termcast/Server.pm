#!::usr::bin::env perl
package App::Termcast::Server;

use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;

use Moose;
use KiokuDB;
use KiokuX::User::Util qw(crypt_password);

use Digest::SHA1;
use Data::UUID::LibUUID;

use App::Termcast::Session;
use App::Termcast::User;
use App::Termcast::Handle;

use Scalar::Util qw(weaken);

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
    default => 9091,
);

has server_port => (
    is      => 'ro',
    isa     => 'Int',
    default => 9092,
);

has termcast_guard => (
    is      => 'ro',
    builder => '_build_termcast_guard'
);

sub _build_termcast_guard {
    my $self = shift;

    my $h;
    tcp_server undef, $self->termcast_port, sub {
        my ($fh, $host, $port) = @_;
        $h = App::Termcast::Handle->new(
            fh => $fh,
            on_read => sub {
                my $h = shift;
                $self->handle_termcast($h);
            },
            on_error => sub {
                my ($h, $fatal, $error) = @_;

                if ($fatal) {
                    weaken(my $weakself = $self);
                    $weakself->delete_termcast_handle($h->handle_id);
                }
                else {
                    warn $error;
                }
            },
            handle_id => new_uuid_string(),
        );
        my $cv = AnyEvent->condvar;
        my $user_object;
        $h->push_read(
            line => sub {
                my ($h, $line) = @_;
                chomp $line;
                my $user_object = $self->handle_auth($h, $line);
                $cv->send;
                if (not defined $user_object) {
                    warn "Authentication failed";
                    $h->destroy;
                }
                else {
                    my $session = App::Termcast::Session->with_traits(
                        'App::Termcast::SessionData',
                    )->new(
                        user => $user_object,
                    );

                    $h->session($session);

                    $self->set_termcast_handle($h->handle_id => $h);
                }
            },
        );

    };
}

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

has server_guard   => (
    is      => 'ro',
    builder => '_build_server_guard'
);

sub _build_server_guard {
    my $self = shift;

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

                warn $error;
                if ($fatal) {
                    $h->destroy;
                }
            }
        );
        my $handle_id = new_uuid_string();

        $self->set_server_handle($handle_id => $h);
    };
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
    },
    default => sub { +{} },
);

sub handle_termcast {
    my $self = shift;
    my $h    = shift;

    $h->push_read(
        chunk => 1,
        sub {
            my ($h, $char) = @_;
            $h->session->add_text($char);
        },
    );
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
            require YAML; warn YAML::Dump($data);

            if ($data->{request} eq 'sessions') {
                $h->push_write(
                    json => {
                        sessions => [
                            map {
                            +{
                                session_id => $_,
                                user       => $self->get_termcast_handle($_)->session->user->id,
                            }
                            } $self->termcast_handle_ids
                        ],
                    }
                );
            }
            elsif ($data->{request} eq 'stream') {
                return unless $data->{session};

                my $session;
                return unless $session = $self->get_termcast_handle($data->{session});
                my $buffer = $session->buffer;

                if ($data->{since}) {
                    $buffer = substr($buffer, length($buffer) - $data->{since});
                }

                $h->push_write(
                    json => {
                        response => {
                            stream => $buffer
                        }
                    }
                );
            }
        }
    );
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

