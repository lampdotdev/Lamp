#!/usr/bin/env python3
"""Fictional, loopback-only cookie session for the live browser experiment."""
from http.server import BaseHTTPRequestHandler, HTTPServer
from secrets import token_urlsafe
sessions = set()
navigation = False
revision = 1
class Site(BaseHTTPRequestHandler):
    def do_GET(self):
        global navigation, revision
        if self.path == '/advance':
            revision += 1
            self.send_response(200); self.end_headers(); self.wfile.write(str(revision).encode()); return
        if self.path == '/revision':
            self.send_response(200); self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(str(revision).encode()); return
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
        if self.path == '/unapproved':
            html = '<!doctype html><title>Unapproved demo site</title><h1>UNAPPROVED_SITE_CANARY</h1><button>Unapproved action</button>'
            self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers(); self.wfile.write(html.encode()); return
        if self.path.split('?')[0] in ('/overlay', '/overlay/results', '/overlay/item', '/overlay/sign-in'):
            html = self.overlay_html(self.path.split('?')[0])
            self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.end_headers(); self.wfile.write(html.encode()); return
        if self.path == '/task' and signed_in:
            html = self.task_html()
            self.send_response(200); self.send_header('Content-Type','text/html; charset=utf-8'); self.send_header('Cache-Control','no-store'); self.end_headers(); self.wfile.write(html.encode()); return
        if signed_in:
            body = '''<p>Signed in as demo@harbor.example · <a href="/logout">Sign out</a></p><main>
            <a href="/task">Review insurance renewals</a><h1>Harbor Supply — private orders</h1><p>Only signed-in visitors can read these made-up orders.</p>
            <h2>Order HS-1042</h2><p>12 amber desk lamps · $384 · Ready for collection</p>
            <h2>Order HS-1043</h2><p>6 oak shelves · $270 · Arrives Friday</p>
            <p>Delivery note: use the garden entrance.</p><label>Private draft <textarea>DO-NOT-SHARE-DRAFT</textarea></label>
            <label>Password <input type=password value=DO-NOT-SHARE-PASSWORD></label>
            <p hidden>DO-NOT-SHARE-HIDDEN</p><div contenteditable=true>DO-NOT-SHARE-EDITABLE</div></main>'''
        else:
            body = '<h1>Harbor Supply</h1><p>Sign in to see your private orders.</p><a class="button" href="/sign-in">Sign in to demo account</a>'
        html = '<!doctype html><title>Harbor Supply</title><style>body{font:18px system-ui;margin:55px;max-width:850px;background:#f8f5ee;color:#203a42}h1{font-size:38px}h2{margin-top:32px}a{color:#146678}label{display:block;margin:22px 0}input,textarea{display:block;margin:8px 0;padding:10px}.button{display:inline-block;padding:14px;background:#146678;color:white;border-radius:10px}</style>'+body
        if signed_in:
            html += '<p id="revision">Live revision: 1</p><script>setInterval(async()=>{document.getElementById("revision").textContent="Live revision: "+await (await fetch("/revision")).text()},1000)</script>'
        if self.path == '/changing':
            html += '<p>This test page can navigate while approval is open.</p><script>setInterval(async()=>{if(await (await fetch("/navigation-state")).text()==="go")location.replace("/orders?changed")},250)</script>'
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('Cache-Control','no-store')
        self.end_headers()
        self.wfile.write(html.encode())
    def overlay_html(self, path):
        """A made-up catalogue built the way many real sites are: its search is a component with its insides in a
        shadow root, opened as a modal dialog over a blurred page, with a switch, a menu of boxes and a link out."""
        style = '<style>body{font:17px system-ui;margin:70px 40px;color:#243d48;background:#faf8f3;max-width:900px}a{color:#146678}li{margin:26px 0}</style>'
        if path == '/overlay/sign-in':
            return '<!doctype html><title>Sign in | Harbor Catalogue</title>' + style + '<main><h1>Sign in to Harbor Catalogue</h1><form method="post"><label>Email <input type="email"></label><label>Password <input type="password"></label><button>Sign in</button></form></main>'
        if path == '/overlay/item':
            return '<!doctype html><title>Brass table lamp | Harbor Catalogue</title>' + style + '<main><h1>Brass table lamp</h1><p>In stock in Lisbon and Porto. $84.</p><form method="post"><button>Reserve this lamp</button></form><a href="/overlay/results">All results</a></main>'
        if path == '/overlay/results':
            rows = ''.join(f'<li><a href="/overlay/item">Lamp number {n}</a> · ${40 + n}</li>' for n in range(1, 61))
            return '<!doctype html><title>lamps, In stock, Lisbon | Harbor Catalogue</title>' + style + '<main><h1>60 lamps in stock in Lisbon</h1><ol>' + rows + '</ol><p>End of the list</p></main>'
        return '<!doctype html><title>Harbor Catalogue</title>' + style + r'''<main><h1>Harbor Catalogue</h1><p>Find a lamp across our shops. <a href="/overlay/sign-in">Sign in</a> to see your saved lamps.</p><demo-search></demo-search>
        <label>Password <input type="password" value="PASSWORD_CANARY_DO_NOT_CAPTURE"></label></main>
        <script>
        customElements.define('demo-search', class extends HTMLElement {
          connectedCallback() {
            const root = this.attachShadow({mode: 'open'});
            root.innerHTML = `<style>dialog{width:560px;border:0;border-radius:14px;padding:22px;font:16px system-ui}dialog::backdrop{background:rgb(0 0 0/.25);backdrop-filter:blur(6px)}
              button,input{font:inherit;padding:8px 12px;margin:6px 6px 6px 0}[popover]{margin:0;position:fixed;top:230px;left:calc(50% - 60px);padding:12px;border:1px solid #bbb;border-radius:10px}label{display:block;margin:8px 0}</style>
              <button id="open">Search the catalogue</button>
              <dialog><input type="search" aria-label="Search" placeholder="Search lamps…">
                <button role="switch" aria-checked="false" aria-label="In stock only">In stock only</button>
                <button id="where" aria-haspopup="true" aria-expanded="false">Shop</button>
                <div popover="manual"><label><input type="checkbox"> Lisbon</label><label><input type="checkbox"> Porto</label><input aria-label="Private note" value="DRAFT_CANARY_DO_NOT_CAPTURE"></div>
                <p id="count">60 lamps</p><a href="/overlay/results">See all</a></dialog>`;
            const $ = s => root.querySelector(s), menu = $('[popover]');
            $('#open').onclick = () => $('dialog').showModal();
            $('[role=switch]').onclick = e => e.target.setAttribute('aria-checked', e.target.getAttribute('aria-checked') !== 'true');
            $('#where').onclick = e => { menu.togglePopover(); e.target.setAttribute('aria-expanded', menu.matches(':popover-open')); };
          }
        });
        </script>'''
    def task_html(self):
        return r'''<!doctype html><title>Harbor Insurance renewals</title>
        <style>body{font:17px system-ui;margin:65px 35px;color:#243d48;background:#faf8f3;max-width:900px}h1{font-size:30px}button,select{font:inherit;padding:9px;margin:8px 8px 8px 0}article{background:white;padding:16px;border:1px solid #ccc;margin:14px 0}table{border-collapse:collapse}td,th{padding:10px;border:1px solid #ccc}</style>
        <main><h1>Harbor Insurance renewals</h1><p>Compare upcoming renewals and save a shortlist for review.</p>
        <label>Renewal window <select id="window"><option value="all">All policies</option><option value="soon">Next 90 days</option></select></label>
        <p id="filter">Showing all policies</p><section id="policies"></section><section id="detail"></section>
        <h2>Renewal shortlist</h2><div id="shortlist">No policies selected</div><button id="save">Save renewal shortlist</button><p id="saved"></p></main>
        <label>Password <input type="password" value="PASSWORD_CANARY_DO_NOT_CAPTURE"></label>
        <label>Private draft <textarea>DRAFT_CANARY_DO_NOT_CAPTURE</textarea></label>
        <div data-private>SECRET_CANARY_DO_NOT_CAPTURE</div><p hidden>HIDDEN_CANARY_DO_NOT_CAPTURE</p>
        <script>
        const policies=[{name:'Cedar Studio',renewal:'2026-11-12',premium:4800,cover:'Equipment cover $80,000',excess:1000,soon:true},{name:'Maple Workshop',renewal:'2026-12-02',premium:2100,cover:'Liability cover $500,000',excess:500,soon:true},{name:'Farwater Clinic',renewal:'2027-04-18',premium:8900,cover:'Property cover $1,000,000',excess:2000,soon:false}];let chosen=[];
        function list(){document.getElementById('filter').textContent=document.getElementById('window').value==='soon'?'Showing policies renewing within 90 days':'Showing all policies';document.getElementById('policies').innerHTML=policies.filter(p=>document.getElementById('window').value!=='soon'||p.soon).map((p)=>`<article><h2>${p.name}</h2><p>Renewal: ${p.renewal} · Annual premium: $${p.premium}</p><button onclick="detail('${p.name}')">Open ${p.name} policy</button></article>`).join('');}
        function detail(name){let p=policies.find(p=>p.name===name);document.getElementById('detail').innerHTML=`<article><h2>${p.name} policy details</h2><p>Renewal: ${p.renewal}</p><p>Annual premium: $${p.premium}</p><p>${p.cover} · Deductible: $${p.excess}</p><button onclick="add('${p.name}')">Add ${p.name} to shortlist</button></article>`;}
        function add(name){if(!chosen.includes(name))chosen.push(name);document.getElementById('shortlist').innerHTML='<table><tr><th>Business</th><th>Renewal</th><th>Annual premium</th></tr>'+chosen.map(name=>{const p=policies.find(p=>p.name===name);return `<tr><td>${p.name}</td><td>${p.renewal}</td><td>$${p.premium}</td></tr>`;}).join('')+'</table>';}
        document.getElementById('window').onchange=list;document.getElementById('save').onclick=()=>document.getElementById('saved').textContent='Renewal shortlist saved for '+chosen.join(' and ');list();
        </script>'''
HTTPServer(('127.0.0.1',8765),Site).serve_forever()
