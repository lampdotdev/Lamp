// Drives the Xbox host's phones protocol (lamp_controllers.h, run by posix_host.cpp) as a game's page and its phones
// would: the page over the host's link, the phones over real WebSockets (Node's own client) and plain HTTP. Run by
// scripts/check-web-host-controllers.sh.
import { spawn } from 'node:child_process';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const [binary, root] = process.argv.slice(2);
const host = spawn(binary, [root], { stdio: ['pipe', 'pipe', 'inherit'] });
let lines = [], waiters = [], buffered = '';
host.stdout.on('data', (d) => {
  buffered += d;
  let nl;
  while ((nl = buffered.indexOf('\n')) >= 0) {
    const m = JSON.parse(buffered.slice(0, nl));
    buffered = buffered.slice(nl + 1);
    lines.push(m);
    waiters = waiters.filter((w) => !w(m));
  }
});
const tell = (m) => host.stdin.write(JSON.stringify(m) + '\n');
// The next line from the host the test is waiting for, taken from what has come.
function hear(match, ms = 3000) {
  const i = lines.findIndex(match);
  if (i >= 0) return Promise.resolve(lines.splice(i, 1)[0]);
  return new Promise((resolve, reject) => {
    const t = setTimeout(() => reject(new Error('host never said: ' + match)), ms);
    waiters.push((m) => { if (!match(m)) return false; clearTimeout(t); lines.splice(lines.indexOf(m), 1); resolve(m); return true; });
  });
}
const pageSaid = (t) => hear((m) => m.ev === 'message' && m.text && JSON.parse(m.text).t === t).then((m) => JSON.parse(m.text));

function get(port, path, hostHeader = `127.0.0.1:${port}`) {
  return new Promise((resolve, reject) => {
    http.get({ host: '127.0.0.1', port, path, headers: { Host: hostHeader } }, (res) => {
      let body = '';
      res.on('data', (d) => (body += d));
      res.on('end', () => resolve({ status: res.statusCode, body, type: res.headers['content-type'], policy: res.headers['content-security-policy'] }));
    }).on('error', reject);
  });
}

class Phone {
  constructor(port) {
    this.said = [];
    this.waiters = [];
    this.ws = new WebSocket(`ws://127.0.0.1:${port}/`);
    this.ws.binaryType = 'arraybuffer';
    this.opened = new Promise((resolve, reject) => { this.ws.onopen = resolve; this.ws.onerror = reject; });
    this.closed = new Promise((resolve) => { this.ws.onclose = (e) => resolve(e.code); });
    this.ws.onmessage = (e) => {
      const m = typeof e.data === 'string' ? JSON.parse(e.data) : { binary: new Uint8Array(e.data) };
      this.said.push(m);
      this.waiters = this.waiters.filter((w) => !w(m));
    };
  }
  send(m) { this.ws.send(typeof m === 'string' ? m : JSON.stringify(m)); }
  hear(t, ms = 3000) {
    const i = this.said.findIndex((m) => m.t === t);
    if (i >= 0) return Promise.resolve(this.said.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('phone never heard ' + t)), ms);
      this.waiters.push((m) => { if (m.t !== t) return false; clearTimeout(timer); this.said.splice(this.said.indexOf(m), 1); resolve(m); return true; });
    });
  }
}
const joined = async (phone, app, credential) => { await phone.opened; phone.send({ t: 'hello', app, credential }); return phone.hear('welcome'); };
const step = (name) => console.log('ok - ' + name);

try {
  tell({ op: 'start' });
  let session = await hear((m) => m.ev === 'session');
  assert.equal(session.status, 200);
  const link = session.body.links[0];
  assert.equal(link.socket, 'ws://lamp-controllers.invalid/');
  const { relayPort, pagePort } = session;

  // The phone page: its own files, only by the console's names; where the relay is.
  let r = await get(pagePort, '/');
  assert.equal(r.status, 200); assert.match(r.type, /text\/html/); assert.match(r.body, /test phone page/);
  assert.equal((await get(pagePort, '/', 'evil.example:80')).status, 403);
  for (const path of ['/../secret.txt', '/%2e%2e/secret.txt', '/.hidden', '/a%2fb', '/CON', '/index.html:stream', '/missing.js'])
    assert.equal((await get(pagePort, path)).status, 404, path);
  r = await get(pagePort, '/lamp-relay.json');
  assert.deepEqual(JSON.parse(r.body), { app: 'game.test', port: relayPort, policy: true });
  step('the page is served as its own files, to the console\'s names only');

  // The page's rules, word for word those of the LG service and of Lamp (PhonePagePolicyTests holds Swift to relay.js):
  // its relay where it is, by the name the phone used, and only the sites the reach file names.
  const lg = createRequire(import.meta.url)(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../Resources/LGPhones/relay.js'));
  const reach = lg.readReachJSON(fs.readFileSync(path.join(root, 'lamp-reach.json'), 'utf8'));
  for (const name of [`127.0.0.1:${pagePort}`, 'localhost']) {
    r = await get(pagePort, '/', name);
    assert.equal(r.policy, lg.policy(name, relayPort, reach), name);
  }
  assert.match((await get(pagePort, '/')).policy, new RegExp(`connect-src 'self' ws://127\\.0\\.0\\.1:${relayPort} api\\.example\\.com;`));
  // An app the person made: no policy at all, as before phone pages had one.
  const shared = fs.readFileSync(path.join(root, 'lamp-reach.json'));
  fs.unlinkSync(path.join(root, 'lamp-reach.json'));
  r = await get(pagePort, '/');
  assert.equal(r.status, 200);
  assert.equal(r.policy, undefined, 'an own app\'s phone page has no policy');
  assert.deepEqual(JSON.parse((await get(pagePort, '/lamp-relay.json')).body), { app: 'game.test', port: relayPort });
  fs.writeFileSync(path.join(root, 'lamp-reach.json'), shared);
  step('the page\'s rules name only its relay and the sites its reach file names, as the LG service writes them; an own app\'s page has none');

  // A socket from another site's page is refused before it's a WebSocket.
  const refused = await new Promise((resolve) => {
    const s = net.connect(relayPort, '127.0.0.1', () => s.write(`GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nOrigin: http://evil.example:${pagePort}\r\n\r\n`));
    let got = ''; s.on('data', (d) => (got += d)); s.on('close', () => resolve(got));
  });
  assert.match(refused, /^HTTP\/1.1 403/);
  // RFC 6455's own example: this key's accept value is s3pPLMBiTxaQ9kYGzzhZRbK+xOo=.
  const accepted = await new Promise((resolve) => {
    const s = net.connect(relayPort, '127.0.0.1', () => s.write(`GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nOrigin: http://127.0.0.1:${pagePort}\r\n\r\n`));
    let got = ''; s.on('data', (d) => { got += d; if (got.includes('\r\n\r\n')) { s.destroy(); resolve(got); } });
  });
  assert.match(accepted, /^HTTP\/1.1 101/); assert.match(accepted, /Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK\+xOo=/);
  step('another site\'s page is refused; the game\'s page is upgraded with RFC 6455\'s accept value');

  // A frame claiming a length near 2^64 after a fragment is let go at once, not waited for while its bytes pile up.
  const huge = await new Promise((resolve) => {
    const s = net.connect(relayPort, '127.0.0.1', () => s.write(`GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`));
    let got = Buffer.alloc(0), sent = false;
    const timer = setTimeout(() => { s.destroy(); resolve('still open'); }, 2000);
    s.on('data', (d) => {
      got = Buffer.concat([got, d]);
      const end = got.indexOf('\r\n\r\n');
      if (!sent && end >= 0) {
        sent = true;
        const fragment = Buffer.from([0x01, 0x8f, 0, 0, 0, 0, ...Buffer.alloc(15)]);
        const length = Buffer.alloc(8); length.writeBigUInt64BE(2n ** 64n - 15n);
        s.write(Buffer.concat([fragment, Buffer.from([0x00, 0xff]), length, Buffer.from([0, 0, 0, 0])]));
        s.write(Buffer.alloc(1 << 20));
        got = got.subarray(end + 4);
      } else if (sent && got.length >= 4 && got[0] === 0x88) { clearTimeout(timer); s.destroy(); resolve('closed ' + got.readUInt16BE(2)); }
    });
    s.on('close', () => { clearTimeout(timer); resolve(sent && got[0] === 0x88 ? 'closed ' + got.readUInt16BE(2) : 'closed'); });
  });
  assert.equal(huge, 'closed 1009');
  step('a frame longer than any message is refused before its bytes are kept');

  // The host's credential works only over the page's own link, never from the network.
  const thief = new Phone(relayPort);
  await thief.opened; thief.send({ t: 'hello', app: 'game.test', credential: link.credential });
  assert.equal(await thief.closed, 4003);
  tell({ op: 'open' });
  await hear((m) => m.ev === 'open');
  tell({ op: 'send', text: JSON.stringify({ t: 'hello', app: 'game.test', credential: link.credential }) });
  assert.deepEqual((await pageSaid('welcome')).players, []);
  step('the host\'s credential is turned away from the network and taken over the page\'s link');

  // A phone joins with the link's credential, presses, and is numbered by the page.
  tell({ op: 'send', text: '{"t":"link"}' });
  const url = (await pageSaid('link')).url;
  assert.ok(url.startsWith(`http://127.0.0.1:${pagePort}/#`));
  const join = url.split('#')[1];
  const a = new Phone(relayPort);
  const welcomeA = await joined(a, 'game.test', join);
  assert.equal(welcomeA.place, 1); assert.equal(welcomeA.host, true);
  assert.equal((await pageSaid('joined')).player, 1);
  a.send({ t: 'button', name: 'A', down: true, seq: 1 });
  const press = await pageSaid('button');
  assert.deepEqual([press.player, press.name, press.down, press.seq], [1, 'A', true, 1]);
  a.send({ t: 'axis', name: 'stick', x: 3, y: -0.25, seq: 2 });
  const axis = await pageSaid('axis');
  assert.deepEqual([axis.x, axis.y], [1, -0.25]);
  a.send({ t: 'button', name: 'bad name!', down: true, seq: 3 });
  tell({ op: 'send', text: JSON.stringify({ t: 'player', player: 1, number: 1 }) });
  assert.equal((await a.hear('player')).number, 1);
  tell({ op: 'send', text: JSON.stringify({ t: 'send', player: 0, data: { score: 7, name: 'ünï/code' } }) });
  assert.deepEqual((await a.hear('message')).data, { score: 7, name: 'ünï/code' });
  // null is a message too, both ways.
  a.send({ t: 'message', data: null });
  assert.equal((await pageSaid('message')).data, null);
  tell({ op: 'send', text: JSON.stringify({ t: 'send', player: 1, data: null }) });
  assert.equal((await a.hear('message')).data, null);
  step('a phone joins by the link, its presses and sticks reach the page, and the page\'s messages reach it');

  // A second phone, then the first drops and comes back as the same player with its controller credential.
  const b = new Phone(relayPort);
  assert.equal((await joined(b, 'game.test', join)).place, 2);
  assert.equal((await pageSaid('joined')).player, 2);
  a.ws.close();
  assert.equal((await pageSaid('left')).player, 1);
  const again = new Phone(relayPort);
  assert.equal((await joined(again, 'game.test', welcomeA.credential)).place, 1);
  assert.equal((await pageSaid('joined')).player, 1);
  step('a second phone is player 2; a phone that drops comes back as the same player');

  // A file from a phone: announced, passed piece by piece, held to its size.
  again.send({ t: 'file', id: 5, name: 'pic.png', type: 'image/png', size: 10 });
  const announced = await pageSaid('file');
  assert.deepEqual([announced.player, announced.id, announced.size], [1, 5, 10]);
  const piece = new Uint8Array([1, 0, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5, 6]);
  again.ws.send(piece);
  const got = await hear((m) => m.ev === 'message' && m.data);
  const bytes = Buffer.from(got.data, 'base64');
  assert.deepEqual([...bytes], [1, 1, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5, 6]);
  tell({ op: 'send', text: JSON.stringify({ t: 'file-ack', player: 1, id: 5, got: 6 }) });
  assert.equal((await again.hear('file-ack')).got, 6);
  again.ws.send(new Uint8Array([1, 0, 0, 0, 0, 0, 0, 5, 1, 2, 3, 4, 5]));
  assert.equal((await pageSaid('file-cancel')).id, 5);
  assert.equal((await again.hear('file-refuse')).reason, "The file didn't keep to its size.");
  step('a phone\'s file reaches the page in pieces and is held to the size it announced');

  // Nine phones: the ninth finds the game full.
  const more = [];
  for (let i = 0; i < 6; i++) more.push(new Phone(relayPort));
  for (const p of more) await joined(p, 'game.test', join);
  const ninth = new Phone(relayPort);
  await ninth.opened; ninth.send({ t: 'hello', app: 'game.test', credential: join });
  await ninth.hear('full');
  assert.equal(await ninth.closed, 4004);
  step('eight players at most');

  // Stopping ends it all; a new session takes nothing from the old one.
  const codes = Promise.all([again.closed, b.closed]);
  tell({ op: 'stop' });
  assert.deepEqual(await codes, [4005, 4005]);
  await hear((m) => m.ev === 'close' && m.code === 4005);
  await new Promise((resolve) => net.connect(relayPort, '127.0.0.1').on('error', resolve).on('connect', () => assert.fail('the relay still listens')));
  await new Promise((resolve) => net.connect(pagePort, '127.0.0.1').on('error', resolve).on('connect', () => assert.fail('the page still listens')));
  tell({ op: 'start' });
  session = await hear((m) => m.ev === 'session');
  assert.notEqual(session.body.links[0].credential, link.credential);
  for (const old of [welcomeA.credential, join]) {
    const p = new Phone(session.relayPort);
    await p.opened; p.send({ t: 'hello', app: 'game.test', credential: old });
    assert.equal(await p.closed, 4003);
  }
  step('stopping closes every phone, the page\'s link and both listeners; the next session turns the old credentials away');
  console.log('all passed');
  host.kill();
  process.exit(0);
} catch (e) {
  console.error('FAIL:', e.message);
  host.kill();
  process.exit(1);
}
