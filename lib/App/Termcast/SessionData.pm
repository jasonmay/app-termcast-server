#!::usr::bin::env perl
package App::Termcast::SessionData;
use Moose::Role;

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


no Moose::Role;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

