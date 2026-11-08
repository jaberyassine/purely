"""Keep Azure LB health probes ready without serving files or application traffic."""
from http.server import BaseHTTPRequestHandler, HTTPServer

class Warmup(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(404)
        self.end_headers()
        self.wfile.write(b'Certificate bootstrap only\n')
    def log_message(self, *args):
        pass

HTTPServer(('0.0.0.0', 8080), Warmup).serve_forever()
