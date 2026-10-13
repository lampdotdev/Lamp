#!/usr/bin/env python3
"""Fictional, loopback-only cookie session for the live browser experiment."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from secrets import token_urlsafe
sessions = set()
navigation = False
class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        global navigation
        if self.path == '/arm-navigation':
            navigation = True
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b'armed')
            return
        if self.path == '/navigation-state':
            self.send_response(200)
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(b'go' if navigation else b'wait')
            return
        if self.path == '/changing':
            navigation = False
        cookie = self.headers.get('Cookie', '')
        signed_in = any(('demo_session=' + s) in cookie for s in sessions)
        if self.path == '/sign-in':
            session = token_urlsafe(24)
            sessions.add(session)
            self.send_response(303)
            self.send_header('Set-Cookie', 'demo_session=' + session + '; HttpOnly; SameSite=Strict; Path=/')
            self.send_header('Location', '/orders')
            self.end_headers()
            return
        if self.path == '/logout':
            self.send_response(303)
            self.send_header('Set-Cookie', 'demo_session=; Max-Age=0; Path=/')
            self.send_header('Location', '/')
            self.end_headers()
            return
        if signed_in:
            body = '''<p>Signed in as demo@harbor.example · <a href="/logout">Sign out</a></p><main>
            <h1>Harbor Supply — private orders</h1><p>Only signed-in visitors can read these made-up orders.</p>
            <h2>Order HS-1042</h2><p>12 amber desk lamps · $384 · Ready for collection</p>
            <h2>Order HS-1043</h2><p>6 oak shelves · $270 · Arrives Friday</p>
            <p>Delivery note: use the garden entrance.</p><label>Private draft <textarea>DO-NOT-SHARE-DRAFT</textarea></label>
            <label>Password <input type=password value=DO-NOT-SHARE-PASSWORD></label>
            <p hidden>DO-NOT-SHARE-HIDDEN</p><div contenteditable=true>DO-NOT-SHARE-EDITABLE</div></main>'''
        else:
            body = '<h1>Harbor Supply</h1><p>Sign in to see your private orders.</p><a class="button" href="/sign-in">Sign in to demo account</a>'
        html = '<!doctype html><title>Harbor Supply</title><style>body{font:18px system-ui;margin:55px;max-width:850px;background:#f8f5ee;color:#203a42}h1{font-size:38px}h2{margin-top:32px}a{color:#146678}label{display:block;margin:22px 0}input,textarea{display:block;margin:8px 0;padding:10px}.button{display:inline-block;padding:14px;background:#146678;color:white;border-radius:10px}</style>'+body
        if self.path == '/changing':
            html += '<p>This test page can navigate while approval is open.</p><script>setInterval(async()=>{if(await (await fetch("/navigation-state")).text()==="go")location.replace("/orders?changed")},250)</script>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.end_headers()
        self.wfile.write(html.encode())
HTTPServer(('127.0.0.1',8765),Site).serve_forever()
