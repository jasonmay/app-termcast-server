#!::usr::bin::env perl
package App::Termcast::SessionData;
use Moose::Role;
use Set::Object qw(set);
use MooseX::Types::Path::Class;

=head1 NAME

App::Termcast::SessionData -

=head1 SYNOPSIS


=head1 DESCRIPTION


=cut

has user => (
    is  => 'ro',
    isa => 'App::Termcast::User',
);

has buffer => (
    is  => 'rw',
    isa => 'Str',

    traits  => ['String'],
    handles => {
        add_text      => 'append',
        buffer_length => 'length',
        clear_buffer  => 'clear',
    },
);

has streaming => (
    is     => 'rw',
    isa    => 'Bool',
    traits => ['Bool'],
    handles => {
        start_streaming => 'set',
        stop_streaming  => 'unset',
    }
);

has stream_handles => (
    is      => 'ro',
    isa     => 'Set::Object',
    default => sub { set() },
);

has stream_socket => (
    is     => 'rw',
    isa    => 'Path::Class::File',
    coerce => 1,
);

has last_active => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { time() },
);

sub mark_active { shift->last_active( time() ); }

no Moose::Role;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

