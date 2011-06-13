#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::TCP;

use IO::Socket::INET;
use File::Temp;
use JSON ();

use App::Termcast::Server;

my $unix_file;
(undef, $unix_file) = File::Temp::tempfile(); unlink $unix_file;

test_tcp(
    client => sub {
        my $port = shift;

        my $json = JSON->new;
        my $manager = IO::Socket::UNIX->new(
            Peer => $unix_file,
        ) or die  $!;
        my @res = ();
        my $get_next = sub {
            my $num = shift;

            while (@res < $num) {
                my $buf;
                sysread $manager, $buf, 4096 until $buf;
                push @res, $json->incr_parse($buf);
            }
        };

        # disconnect false-alarm, due to test_tcp
        $get_next->(1); shift @res;

        $manager->syswrite('{"request":"sessions"}');
        $get_next->(1);

        is_deeply(
            shift(@res), {
                response => 'sessions',
                sessions => [],
            }, 'nothing in sessions response yet'
        );

        my $socket = IO::Socket::INET->new(
            PeerAddr => '127.0.0.1',
            PeerPort => $port,
        ) or die $!;

        $socket->syswrite("hello test tset\n");

        $get_next->(1);

        my $cur = shift(@res);
        is $cur->{notice}, 'connect', 'next packet was a connect notice';

        my $last_active = delete $cur->{connection}->{last_active};
        ok $last_active, 'sees connections:last_active in packet';

        for (qw/session_id geometry socket user/) {
            ok $cur->{connection}->{$_}, "sees connection:$_ in packet";
        }

        my $conn = $cur->{connection};

        $manager->syswrite('{"request":"sessions"}');
        $get_next->(1);

        $cur = shift @res;
        ok delete($cur->{sessions}->[0]->{last_active});
        is_deeply(
            $cur, {
                response => 'sessions',
                sessions => [$conn],
            }, 'connection shows in sessions response'
        );


        my $stream = IO::Socket::UNIX->new(
            Peer => $cur->{sessions}->[0]->{socket},
        ) or die $!;

        my $stream_buf;
        $socket->syswrite('ansi');
        $stream->read($stream_buf, 4);

        is $stream_buf, 'ansi', 'was successfully able to read the ansi';

        $socket->close();

        $get_next->(1);

        is_deeply(
            shift(@res), {
                notice     => 'disconnect',
                session_id => $conn->{session_id},
            }, 'got disconnect notice'
        );

        $manager->syswrite('{"request":"sessions"}');
        $get_next->(2);
        if ($res[0]->{notice}) {
            shift @res; # XXX FIXME - why is it seeing the notice twice?
        }

        is_deeply(
            shift(@res), {
                response => 'sessions',
                sessions => [],
            }, 'no longer in sessions response'
        );
    },
    server => sub {
        my $port = shift;

        App::Termcast::Server->new(
            manager_listener_path => $unix_file,
            termcast_port         => $port,
            dsn                   => 'dbi:SQLite:dbname=:memory:',
        )->run_all();
    },
);

done_testing;
