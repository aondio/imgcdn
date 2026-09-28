from http.server import BaseHTTPRequestHandler, HTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            self.send_response(200)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write(f"IMGPROXY-STUB received path: {self.path}".encode())

    def log_message(self, fmt, *args):
        pass  # quiet

HTTPServer(("127.0.0.1", 8080), Handler).serve_forever()
