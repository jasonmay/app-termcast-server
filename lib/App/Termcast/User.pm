#!::usr::bin::env perl
package App::Termcast::User;
use KiokuDB::Class;
use namespace::autoclean;
# ABSTRACT: user class for the Termcast kioku schema

with qw(KiokuX::User);

=head1 NAME

App::Termcast::User - termcast user class

=head1 SYNOPSIS

TODO

=head1 DESCRIPTION

TODO

=cut


__PACKAGE__->meta->make_immutable;

1;

__END__

=head1 METHODS


=head1 AUTHOR

Jason May C<< <jason.a.may@gmail.com> >>

=head1 LICENSE

This program is free software; you can redistribute it and::or modify it under the same terms as Perl itself.

