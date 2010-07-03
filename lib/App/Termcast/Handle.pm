#!::usr::bin::env perl
package App::Termcast::Handle;
use Moose;
use MooseX::NonMoose;
use namespace::autoclean;
extends 'AnyEvent::Handle';

=head1 NAME

App::Termcast::Handle -

=head1 SYNOPSIS


=head1 DESCRIPTION


=cut

has session_id => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has session => (
    is       => 'rw',
    isa      => 'App::Termcast::Session',
);

sub BUILDARGS {
    my $class = shift;
    my %args  = @_;

    my @foreign_args = qw(fh on_read on_error);

    delete @args{@foreign_args}; # just to be clean

    return \%args;
}

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

