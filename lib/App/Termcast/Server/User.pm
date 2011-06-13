#!::usr::bin::env perl
package App::Termcast::Server::User;
use KiokuDB::Class;
use namespace::autoclean;
# ABSTRACT: user class for the Termcast kioku schema

with qw(KiokuX::User);

1;

