#!/usr/bin/env python3
# Dev helper: a TCP server that accepts connections on 127.0.0.1:2222 and
# never responds, stalling any SSH handshake. Used by
# HetzlyTests/Terminal/SSHConnectionLifecycleTests to reproduce the
# "endless connecting, then crash on close" case without a real server.
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 2222)); s.listen(16)
print("ssh_blackhole on 127.0.0.1:2222", flush=True)
held = []
while True:
    c, _ = s.accept()
    held.append(c)  # hold open, never read/write
