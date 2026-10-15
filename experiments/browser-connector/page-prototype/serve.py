# Stand-in for Lamp's gateway: serves one app's sidebar page on this Mac. Run: python3 -I serve.py
import http.server, pathlib, sys

HOST = 'recipe-box.localhost:47123'
EXTENSION = (pathlib.Path(__file__).parent / 'extension-id.txt').read_text().strip()
PAGE = (pathlib.Path(__file__).parent / 'app-page' / 'index.html').read_bytes()

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        # Only the app's own name is answered (a page that renamed itself to reach this port is refused), and only
        # the extension may put the page in a frame, so another website can't show it inside its own.
        if self.headers.get('Host') != HOST or self.path != '/':
            self.send_error(404); return
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Content-Security-Policy', f"frame-ancestors chrome-extension://{EXTENSION}")
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(PAGE)

http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1]) if len(sys.argv) > 1 else 47123), Handler).serve_forever()
