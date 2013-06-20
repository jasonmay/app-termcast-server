requires 'Moose';
requires 'KiokuX::User';
requires 'KiokuDB';
requires 'KiokuDB::Backend::DBI';
requires 'Number::RecordLocator';
requires 'Try::Tiny';
requires 'Reflex';
requires 'namespace::autoclean';
requires 'YAML';

on test => sub {
    requires 'Test::More';
    requires 'Test::TCP';
};
