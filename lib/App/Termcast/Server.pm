#!::usr::bin::env perl
package App::Termcast::Server;
use Moose;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use KiokuDB;
use namespace::autoclean;

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

has termcasts => (
    is  => 'ro',
    isa => 'HashRef',
    traits => ['Hash'],
    default => sub { +{} },
);

sub _build_termcast_guard {
    my $self = shift;

    my $h;
    tcp_server undef, $self->termcast_port, sub {
        my ($fh, $host, $port) = @_;
        $h = AnyEvent::Handle->new(
            fh => $fh,
            on_read => sub {
                my $h = shift;
                $self->handle_termcast($h);
            },
            on_error => sub {
                warn "aaah!";
            },
        );
        $h->push_read(
            line => sub {
                my ($h, $line) = @_;
                chomp $line;
                warn "$line!!!!";
            },
        )
    };
}

has server_guard   => (
    is      => 'ro',
    builder => '_build_server_guard'
);

sub _build_server_guard {
    my $self = shift;

    tcp_server undef, $self->server_port, sub {
        $self->handle_server();
    };
}

has timer_guard    => (
    is      => 'ro',
    builder => '_build_timer_guard'
);

sub _build_timer_guard {
    my $self = shift;

    AE::timer 0, 10, sub { warn "foo"; };
}

sub handle_termcast {
    my $self = shift;
    my $h    = shift;

    $h->push_read(
        chunk => 1,
        sub {
            my ($h, $char) = @_;
            warn ord($char);
        },
    );
}

sub create_user {
    my $self = shift;
}

sub get_user_auth {
    my $self = shift;
}

sub handle_server {
    my $self = shift;
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

