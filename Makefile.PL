use inc::Module::Install;

name           'App::Termcast::Server';
all_from       'lib/App/Termcast/Server.pm';

build_requires 'Test::More';

requires 'KiokuX::User';
requires 'KiokuDB';
requires 'KiokuDB::Backend::DBI';
requires 'Moose';
requires 'Data::UUID::LibUUID';
requires 'HTML::FromANSI';
requires 'AnyEvent';
requires 'MooseX::NonMoose';
requires 'Set::Object';
requires 'namespace::autoclean';

auto_install();
WriteAll();
