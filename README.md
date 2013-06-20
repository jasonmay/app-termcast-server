App::Termcast::Server
=====================

Server for App::Termcast clients to pipe to unix sockets that other servers
can interact with. By default it hosts a socket called 'connections.sock' in the
base of this distribution. It takes requests and responds with stream information
and will send updates, such as connects, disconnects, and property alterations.

Installation
------------

```
cp etc/config.yml.sample etc/config.yml
<edit etc/config.yml>

cpanm --installdeps .
perl -Ilib bin/termcast-server
```
