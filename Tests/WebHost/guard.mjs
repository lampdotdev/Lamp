// Runs a hostile shared page (hostile/) in Chromium, the engine WebView2 is, with the Xbox host's guard (lamp_web_guard.h,
// answered by guard_host.cpp) deciding each request as the host does in WebResourceRequested: Chrome's DevTools pauses
// every request of the page, its frames and its workers, and this asks the guard whether to serve it from the app's
// files (with the guard's policy on the answer), let it go, or refuse it. The page's bridge (chrome.webview) and its
// navigations are put to the guard the same way. Two sites listen on this Mac's loopback: the one the policy lists, and
// one it doesn't; each counts what reaches it. Run by scripts/check-web-host-guard.sh.
//
// Four runs: with no policy (a page the person made: requests reach the unlisted site, which shows the check can fail),
// guarded (nothing reaches it, the listed site still answers), and each of the guard's two layers alone, the policy on
// the answers and the host's look at each request, to show what each holds by itself.
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import readline from 'node:readline';

const [guardBinary, web, scratch, chromePath] = process.argv.slice(2);
const own = 'https://lamp.example';

// The two sites, each counting what reaches it by the host it was asked as.
const hits = [], connections = [];
function site() {
  const server = http.createServer((req, res) => {
    hits.push({ host: req.headers.host, path: req.url });
    res.writeHead(200, { 'Access-Control-Allow-Origin': '*', 'Content-Type': req.url.startsWith('/module') ? 'text/javascript' : 'text/plain' });
    res.end(req.url.startsWith('/weather') ? '{"sunny":true}' : '');
  });
  server.on('upgrade', (req, socket) => { hits.push({ host: req.headers.host, path: req.url }); socket.destroy(); });
  // Every connection, with a request on it or none (a preconnect's).
  server.on('connection', () => connections.push(server.address().port));
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server)));
}
const listedServer = await site(), unlistedServer = await site();
const L = listedServer.address().port, U = unlistedServer.address().port;
const listed = `http://127.0.0.1:${L}`, unlisted = `http://127.0.0.1:${U}`, alias = `http://localhost:${L}`;
const policyPath = path.join(scratch, 'network-policy.json');
fs.writeFileSync(policyPath, JSON.stringify({ format: 1, origins: [listed], lamp: ['http://127.0.0.1:9'] }));

function guardHost(policy) {
  const child = spawn(guardBinary, [web, policy], { stdio: ['pipe', 'pipe', 'inherit'] });
  const waiting = new Map();
  let next = 1;
  readline.createInterface({ input: child.stdout }).on('line', (line) => {
    const m = JSON.parse(line);
    waiting.get(m.id)?.(m);
    waiting.delete(m.id);
  });
  return {
    child,
    ask: (m) => new Promise((resolve) => { const id = next++; waiting.set(id, resolve); child.stdin.write(JSON.stringify({ ...m, id }) + '\n'); }),
  };
}

async function chrome(dir, extra = []) {
  const portFile = path.join(dir, 'DevToolsActivePort');
  fs.rmSync(portFile, { force: true });
  const child = spawn(chromePath, ['--headless=new', '--no-first-run', '--no-default-browser-check', '--disable-background-networking',
    '--disable-component-update', '--disable-sync', '--remote-debugging-port=0', `--user-data-dir=${dir}`,
    // Loopback stands in for the internet here, which Chrome would otherwise keep a public page from reaching.
    '--disable-features=LocalNetworkAccessChecks,PrivateNetworkAccessSendPreflights,BlockInsecurePrivateNetworkRequests,PrivateNetworkAccessRespectPreflightResults',
    ...extra, 'about:blank'], { stdio: 'ignore' });
  for (let i = 0; i < 200 && !fs.existsSync(portFile); i++) await new Promise((r) => setTimeout(r, 50));
  const [port, browserPath] = fs.readFileSync(portFile, 'utf8').trim().split('\n');
  const socket = new WebSocket(`ws://127.0.0.1:${port}${browserPath}`);
  await new Promise((resolve, reject) => { socket.onopen = resolve; socket.onerror = reject; });
  let next = 1;
  const pending = new Map(), handlers = [];
  socket.onmessage = (e) => {
    const m = JSON.parse(e.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); return; }
    for (const h of handlers) h(m);
  };
  const send = (method, params = {}, sessionId) => new Promise((resolve) => {
    const id = next++;
    pending.set(id, resolve);
    socket.send(JSON.stringify({ id, method, params, sessionId }));
  });
  return { child, send, on: (h) => handlers.push(h), close: () => send('Browser.close').catch(() => {}) };
}

async function run(mode) {
  const before = hits.length, connectedBefore = connections.length;
  const guard = guardHost(mode === 'unguarded' ? '-' : policyPath);
  const dir = path.join(scratch, 'chrome-' + mode);
  fs.mkdirSync(dir, { recursive: true });
  // The whole host starts its web view with the guard's arguments; each layer alone is run without them.
  const { script, arguments: flags } = await guard.ask({ op: 'script' });
  const browser = await chrome(dir, mode === 'guarded' ? flags.split(' ') : []);
  const out = { results: null, bridge: [], navigations: [] };
  let mainFrame = null;

  // Every target the page opens (its frames in other processes, its workers) is held until the guard watches it too,
  // as the host's filter covers documents, shared and service workers alike.
  async function watch(sessionId) {
    await browser.send('Fetch.enable', { patterns: [{ urlPattern: '*', requestStage: 'Request' }] }, sessionId);
    await browser.send('Target.setAutoAttach', { autoAttach: true, waitForDebuggerOnStart: true, flatten: true }, sessionId);
    await browser.send('Runtime.runIfWaitingForDebugger', {}, sessionId);
  }

  browser.on(async (m) => {
    if (m.method === 'Target.attachedToTarget') return watch(m.params.sessionId);
    if (m.method === 'Runtime.bindingCalled' && m.params.name === 'lampHostBridge') {
      const message = JSON.parse(m.params.payload);
      const answer = await guard.ask({ op: message.lamp === 'http' ? 'http' : 'ws', url: message.url });
      out.bridge.push({ kind: message.lamp, url: message.url, ok: answer.ok });
      return;
    }
    if (process.env.GUARD_DEBUG && m.method?.startsWith('Log.')) console.error(mode, JSON.stringify(m.params).slice(0, 400));
    if (m.method !== 'Fetch.requestPaused') return;
    if (process.env.GUARD_DEBUG) console.error(mode, m.params.resourceType, m.params.request.url.slice(0, 120));
    const { requestId, request, resourceType, frameId } = m.params, sessionId = m.sessionId;
    const url = request.url;
    const fulfill = (status, headers, body = '') => browser.send('Fetch.fulfillRequest', { requestId, responseCode: status,
      responseHeaders: Object.entries(headers).map(([name, value]) => ({ name, value })), body }, sessionId);
    const pass = () => browser.send('Fetch.continueRequest', { requestId }, sessionId);
    const fail = () => browser.send('Fetch.failRequest', { requestId, errorReason: 'BlockedByClient' }, sessionId);
    if (url === own + '/__result') {
      out.results = JSON.parse(Buffer.from(request.postData ?? '', 'utf8').toString() || '{}');
      return fulfill(204, {});
    }
    // A navigation of the page or of a frame, as NavigationStarting and FrameNavigationStarting see it.
    if (resourceType === 'Document' && !url.startsWith(own + '/')) {
      if (mode === 'csp-only') return pass();
      const top = frameId === mainFrame;
      if (top) {
        const { where } = await guard.ask({ op: 'navigate', url });
        out.navigations.push({ url, where });
        if (where !== 'stay') return fail();
      } else if (!(await guard.ask({ op: 'frame', url })).ok) return fail();
    }
    if (mode === 'csp-only' && !url.startsWith(own + '/')) return pass();
    const range = Object.entries(request.headers).find(([k]) => k.toLowerCase() === 'range')?.[1];
    const answer = await guard.ask({ op: 'request', url, ...(range ? { range } : {}) });
    if (answer.verdict === 'allowed') return pass();
    if (mode === 'intercept-only') delete answer.headers['Content-Security-Policy'];
    return fulfill(answer.status, answer.headers, answer.body ?? '');
  });

  const { targetId } = await browser.send('Target.createTarget', { url: 'about:blank' }).then((r) => r.result);
  const { sessionId } = await browser.send('Target.attachToTarget', { targetId, flatten: true }).then((r) => r.result);
  mainFrame = targetId;
  await browser.send('Page.enable', {}, sessionId);
  await browser.send('Runtime.enable', {}, sessionId);
  if (process.env.GUARD_DEBUG) await browser.send('Log.enable', {}, sessionId);
  await browser.send('Runtime.addBinding', { name: 'lampHostBridge' }, sessionId);
  // What the host gives every frame before the page's own scripts: WebView2's bridge (here, to this script), and for a
  // guarded app the end of WebRTC.
  const shim = "window.chrome=window.chrome||{};window.chrome.webview={postMessage:function(m){lampHostBridge(JSON.stringify(m))}," +
    "addEventListener:function(){}};";
  await browser.send('Page.addScriptToEvaluateOnNewDocument', { source: shim + script, runImmediately: true }, sessionId);
  await watch(sessionId);
  const page = `${own}/index.html?listed=${encodeURIComponent(listed)}&unlisted=${encodeURIComponent(unlisted)}&alias=${encodeURIComponent(alias)}`;
  await browser.send('Page.navigate', { url: page }, sessionId);
  for (let i = 0; i < 300 && !(out.results && out.navigations.length + (mode === 'csp-only' ? 1 : 0) > 0); i++) await new Promise((r) => setTimeout(r, 50));
  await new Promise((r) => setTimeout(r, 1500));
  await browser.close();
  await new Promise((r) => { browser.child.once('exit', r); setTimeout(() => { browser.child.kill('SIGKILL'); r(); }, 5000); });
  guard.child.stdin.end();
  guard.child.kill();
  const mine = hits.slice(before);
  out.unlisted = mine.filter((h) => h.host === `127.0.0.1:${U}`).map((h) => h.path);
  out.alias = mine.filter((h) => h.host === `localhost:${L}`).map((h) => h.path);
  out.listed = mine.filter((h) => h.host === `127.0.0.1:${L}`).map((h) => h.path);
  out.unlistedConnections = connections.slice(connectedBefore).filter((p) => p === U).length;
  return out;
}

// The rules themselves, as the host asks them.
{
  const guard = guardHost(policyPath);
  const ask = guard.ask;
  const origin = async (url) => (await ask({ op: 'origin', url })).origin;
  assert.equal(await origin('HTTPS://API.Example.COM:443/x?y'), 'https://api.example.com');
  assert.equal(await origin('http://127.0.0.1:80'), 'http://127.0.0.1');
  assert.equal(await origin('wss://[FE80::1]:8443/'), 'wss://[fe80::1]:8443');
  // Addresses two readers could take for different hosts are no one's origin.
  for (const url of ['https://listed@evil.example/', 'https://evil.example\\@listed/', 'https://ev%69l.example/', 'https://evil.example:99999/',
                     'https:evil.example', 'javascript:alert(1)', 'ftp://evil.example/', 'https://évil.example/', 'https://evil.example:+80/'])
    assert.equal(await origin(url), null, url);
  const verdict = async (url) => (await ask({ op: 'request', url })).verdict;
  assert.equal(await verdict(listed + '/a'), 'allowed');
  assert.equal(await verdict(listed + ':80/a'.replace(':80', '')), 'allowed');
  assert.equal(await verdict(`https://127.0.0.1:${L}/a`), 'blocked', 'another scheme is another site');
  assert.equal(await verdict(`http://127.0.0.1:${L + 1}/a`), 'blocked', 'another port is another site');
  assert.equal(await verdict(alias + '/a'), 'blocked');
  assert.equal(await verdict('data:text/plain,hi'), 'allowed');
  assert.equal(await verdict('blob:https://lamp.example/1234'), 'allowed');
  assert.equal(await verdict('file:///C:/Windows/win.ini'), 'blocked');
  // The app's own files: a folder is its index.html, and nothing outside Web/ or hidden is served.
  const local = async (url, range) => ask({ op: 'request', url, ...(range ? { range } : {}) });
  assert.equal((await local(own + '/')).status, 200);
  assert.match((await local(own + '/')).headers['Content-Security-Policy'], new RegExp(`connect-src 'self' ${listed} data: blob:`));
  for (const url of ['/../guard.mjs', '/%2e%2e/guard.mjs', '/..%2fguard.mjs', '/.hidden', '/a%5c..%5cguard.mjs', '/CON', '/index.html::$DATA', '/INDEX~1.HTM', '/COM%C2%B9', '/lpt%C2%B2.txt', '/CONIN$', '/clock$'])
    assert.equal((await local(own + url)).status, 404, url);
  const part = await local(own + '/app.css', 'bytes=0-3');
  assert.equal(part.status, 206);
  assert.equal(Buffer.from(part.body, 'base64').toString(), 'body');
  assert.match(part.headers['Content-Range'], /^bytes 0-3\/\d+$/);
  assert.equal((await local(own + '/app.css', 'bytes=999999-')).status, 416);
  // Navigations, frames and the bridges.
  assert.equal((await ask({ op: 'navigate', url: own + '/other.html' })).where, 'stay');
  assert.equal((await ask({ op: 'navigate', url: listed + '/' })).where, 'browser');
  assert.equal((await ask({ op: 'navigate', url: 'https://evil.example/?d=1' })).where, 'refuse');
  assert.equal((await ask({ op: 'frame', url: 'https://evil.example/' })).ok, false);
  // A site the page may fetch from is never a frame of it (NetworkPolicy.allowsFrame).
  assert.equal((await ask({ op: 'frame', url: listed + '/' })).ok, false);
  assert.equal((await ask({ op: 'frame', url: own + '/menu.html' })).ok, true);
  assert.equal((await ask({ op: 'http', url: 'http://127.0.0.1:9/ai/chat' })).ok, true, "Lamp's own address");
  assert.equal((await ask({ op: 'http', url: 'http://127.0.0.1:10/ai/chat' })).ok, false);
  // A relay is reachable over the ws bridge once Lamp's own answer names it (phones Lamp holds, a wish's room).
  assert.equal((await ask({ op: 'ws', url: 'ws://192.168.1.5:50123/' })).ok, false);
  const relayAnswer = JSON.stringify({ links: [{ kind: 'relay', socket: 'ws://192.168.1.5:50123/', app: 'x' }], renew: 15 });
  // An AI's answer, which the page can steer into naming any socket, names none.
  await ask({ op: 'told', path: '/ai/chat', body: relayAnswer });
  assert.equal((await ask({ op: 'ws', url: 'ws://192.168.1.5:50123/' })).ok, false);
  await ask({ op: 'told', path: '/app/controller', body: relayAnswer });
  assert.equal((await ask({ op: 'ws', url: 'ws://192.168.1.5:50123/' })).ok, true);
  assert.equal((await ask({ op: 'ws', url: 'ws://192.168.1.5:50124/' })).ok, false);
  guard.child.stdin.end();
  // A policy file that's there but can't be read guards the app with nothing listed; a wider entry is left out.
  for (const text of ['not json', '{"format":2,"origins":["http://127.0.0.1:1"]}', '{"format":1,"origins":["HTTP://127.0.0.1:1", "http://*.example"]}']) {
    const broken = path.join(scratch, 'broken-policy.json');
    fs.writeFileSync(broken, text);
    const g = guardHost(broken);
    const p = await g.ask({ op: 'policy' });
    assert.equal(p.guarded, true, text);
    assert.deepEqual(p.origins, [], text);
    assert.equal((await g.ask({ op: 'request', url: 'http://127.0.0.1:1/' })).verdict, 'blocked', text);
    g.child.stdin.end();
  }
  console.log('rule checks passed');
}

const report = {};
for (const mode of ['unguarded', 'guarded', 'csp-only', 'intercept-only']) {
  report[mode] = await run(mode);
  console.log(mode + ': ' + JSON.stringify(report[mode]));
}
listedServer.close();
unlistedServer.close();

// With no policy the page's requests reach the unlisted site: without the guard, nothing here stops it.
const loose = report.unguarded;
assert.ok(loose.unlisted.some((p) => p.startsWith('/fetch')), 'with no policy the unlisted site should be reached');
assert.ok(loose.alias.length > 0, 'with no policy the listed site under another name should be reached');

assert.equal(loose.results['webrtc'], 'sent');
assert.ok(loose.bridge.every((b) => b.ok), 'with no policy the bridges keep their own rules');

// Guarded: the listed site answers, and nothing the page tries reaches the unlisted one, or the listed one by another name.
const held = report.guarded;
assert.equal(held.results['listed fetch'], 'sent');
assert.ok(held.listed.some((p) => p.startsWith('/weather')));
assert.deepEqual(held.unlisted, [], 'nothing may reach the unlisted site');
assert.equal(held.unlistedConnections, 0, 'not even a connection with no request on it');
assert.deepEqual(held.alias, [], 'the listed site by another name is another site');
// What the page saw, beside what the sites counted: a beacon is only queued, and a frame says nothing, so those two
// are left to the counts.
for (const [name, result] of Object.entries(held.results)) if (!['listed fetch', 'frame', 'beacon', 'preconnect'].includes(name)) assert.equal(result, 'refused', name);
assert.equal(held.bridge.length, 2);
assert.ok(held.bridge.every((b) => !b.ok), 'the bridges refuse an unlisted site');
assert.deepEqual(held.navigations.map((n) => n.where), ['refuse']);

// The policy on the answers alone holds every request; a top-level navigation is the host's to stop, which is why it
// watches them.
const policyOnly = report['csp-only'];
assert.deepEqual(policyOnly.unlisted.filter((p) => !p.startsWith('/navigate') && p !== '/favicon.ico'), []);
assert.ok(policyOnly.unlisted.some((p) => p.startsWith('/navigate')));
assert.deepEqual(policyOnly.alias, []);
assert.equal(policyOnly.results['listed fetch'], 'sent');

// The host's look at each request alone holds every request it is shown; a WebSocket isn't one of them here, which is
// why the answers carry the policy too.
const lookOnly = report['intercept-only'];
assert.deepEqual(lookOnly.unlisted.filter((p) => !p.startsWith('/ws')), []);
// Nor does it see a preconnect, a connection with no request on it, which is why the web view itself is started so it
// connects only to listed sites.
assert.ok(lookOnly.unlistedConnections > lookOnly.unlisted.length, 'a preconnect opens connections that carry no request');
assert.deepEqual(lookOnly.alias, []);
assert.equal(lookOnly.results['listed fetch'], 'sent');

console.log('guard checks passed');
