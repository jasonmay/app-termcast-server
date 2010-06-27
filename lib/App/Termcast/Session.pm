#!::usr::bin::env perl
package App::Termcast::Session;
use Moose;
use AnyEvent::Handle;
use HTML::FromANSI;
use namespace::autoclean;

=head1 NAME

App::Termcast::Session -

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

=cut

has handle => (
    is  => 'ro',
    isa => 'AnyEvent::Handle',
);

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

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

