#!/usr/bin/env python3
"""Exercise real URLSession POST/redirect behavior using only loopback fixtures."""
import http.server
import pathlib
import subprocess
import tempfile
import threading

ROOT = pathlib.Path(__file__).resolve().parents[1]
requests = []


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
        requests.append((self.path, body, self.headers.get("Authorization")))
        self.send_response(307 if self.path.startswith("/redirect") else 200)
        if self.path == "/redirect":
            self.send_header("Location", f"http://127.0.0.1:{self.server.server_port}/must-not-arrive")
        elif self.path == "/redirect-external":
            self.send_header("Location", "https://example.invalid/must-not-arrive")
        self.send_header("Content-Length", "0")
        self.end_headers()

    def log_message(self, *_):
        pass


with tempfile.TemporaryDirectory(prefix="fluidvoice-network-tests-") as folder:
    binary = pathlib.Path(folder) / "network-tests"
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library",
        str(ROOT / "Sources/Fluid/Networking/LocalOnlyNetworking.swift"),
        str(ROOT / "Tests/LocalNetworkTransportTests.swift"), "-o", str(binary),
    ], check=True)
    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            subprocess.run([str(binary), str(server.server_port)], check=True, timeout=30)
        finally:
            server.shutdown()
    assert [row[0] for row in requests] == ["/ok", "/redirect", "/redirect-external"], requests
    assert all(row[1:] == (b"synthetic-private-text", "Bearer synthetic-local-key") for row in requests)
    print("PASS: only the three intended local requests reached the server")
