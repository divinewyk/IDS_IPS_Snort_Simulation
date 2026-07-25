#!/usr/bin/env bash
# ---------------------------------------------------------------------
# 02_start_victim_server.sh
# Starts a throwaway HTTP server inside ns-victim (10.0.0.2:80) so the
# attacker has something to send SQLi/XSS/EICAR payloads at. Also
# starts a fake SSH-banner listener on port 22 for the brute-force demo
# (no real sshd needed — Snort only inspects the SYN packets anyway).
#
# Leave this running in its own terminal throughout the demo.
# Run with: sudo bash 02_start_victim_server.sh
# ---------------------------------------------------------------------
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo bash $0" >&2
    exit 1
fi

echo "Starting HTTP test server on 10.0.0.2:80 (ns-victim)..."
echo "Press Ctrl+C to stop."
echo

# Minimal HTTP server that just echoes what it received (port 80 needs root)
ip netns exec ns-victim python3 -c '
import http.server, socketserver

class Handler(http.server.BaseHTTPRequestHandler):
    def _reply(self):
        self.send_response(200)
        self.send_header("Content-type", "text/plain")
        self.end_headers()
        self.wfile.write(b"received: " + self.path.encode() + b"\n")
    def do_GET(self):
        self._reply()
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        self._reply()
    def log_message(self, fmt, *args):
        print("[victim:80]", fmt % args)

with socketserver.TCPServer(("10.0.0.2", 80), Handler) as httpd:
    httpd.serve_forever()
'
