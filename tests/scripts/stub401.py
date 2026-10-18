#!/usr/bin/env python3
"""Stub HTTP server: first request returns 401, later ones 200.
Usage: stub401.py PORTFILE HITSFILE. Binds a free port, writes it to PORTFILE,
appends one line per request to HITSFILE."""
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

portfile, hitsfile = sys.argv[1], sys.argv[2]
count = 0


class H(BaseHTTPRequestHandler):
    def do_GET(self):
        global count
        count += 1
        with open(hitsfile, "a") as f:
            f.write(self.path + "\n")
        code = 401 if count == 1 else 200
        body = b"{}"
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


srv = HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
