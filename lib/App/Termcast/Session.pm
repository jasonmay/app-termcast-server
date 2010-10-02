#!::usr::bin::env perl
package App::Termcast::Session;
use Moose;
use DateTime;
use AnyEvent::Handle;
use HTML::FromANSI;
use namespace::autoclean;

with qw(MooseX::Traits);

=head1 NAME

App::Termcast::Session -

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

=cut

has last_active => (
    is      => 'rw',
    isa     => 'Int',
    default => sub { time() },
);

sub mark_active { shift->last_active( time() ); }

__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

