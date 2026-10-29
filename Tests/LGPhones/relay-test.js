/* The LG phone service (Resources/LGPhones) on real sockets: the page and relay a game's phones use, and the service's
 * door on the TV's bus. Run with `node Tests/LGPhones/relay-test.js` under each Node an LG TV that takes the service has
 * (8.12 on webOS TV 5.0 and 6.0, 12 on 22 and 23, 16 on 24 and 25, 20 on 26). webos-service, which only the TV has, is
 * stood in for by a stub that records what the service registers and answers: what's tested of it is who it lets start
 * the game's phones and when it ends them, not the TV's bus.
 */
'use strict';
var assert = require('assert');
var fs = require('fs');
var http = require('http');
var os = require('os');
var path = require('path');
var Module = require('module');

// LG_SERVICE_DIR runs the checks against another copy of the service (an earlier one, to see a check fail without a fix).
var service = process.env.LG_SERVICE_DIR || path.join(__dirname, '../../Resources/LGPhones');
var net = require('net');
var WebSocket = require(path.join(service, 'node_modules/ws'));
var relay = require(path.join(service, 'relay.js'));

var root = fs.mkdtempSync(path.join(os.tmpdir(), 'lg-phones-'));
fs.writeFileSync(path.join(root, 'index.html'), '<p>pad</p>');
fs.writeFileSync(path.join(root, 'lamp-controller.js'), '// pad');
fs.writeFileSync(path.join(root, '.hidden'), 'no');
fs.writeFileSync(path.join(os.tmpdir(), 'lg-phones-outside.txt'), 'outside');
fs.symlinkSync(path.join(os.tmpdir(), 'lg-phones-outside.txt'), path.join(root, 'link.txt'));

function get(port, p, host) {
  return new Promise(function (resolve, reject) {
    http.get({ port: port, path: p, headers: { Host: host || '127.0.0.1:' + port } }, function (res) {
      var body = '';
      res.on('data', function (d) { body += d; });
      res.on('end', function () { resolve({ status: res.statusCode, body: body }); });
    }).on('error', reject);
  });
}
function client(url, origin) {
  var socket = new WebSocket(url, origin ? { origin: origin } : {});
  socket.heard = [];
  socket.waiters = [];
  socket.on('message', function (data) {
    var m = typeof data === 'string' ? JSON.parse(data) : { binary: data };
    socket.heard.push(m);
    socket.waiters = socket.waiters.filter(function (w) { if (w.test(m)) { w.resolve(m); return false; } return true; });
  });
  socket.closed = new Promise(function (resolve) { socket.on('close', function (code) { resolve(code); }); });
  socket.failed = new Promise(function (resolve) { socket.on('error', function (e) { resolve(e); }); socket.on('unexpected-response', function (req, res) { resolve(res.statusCode); }); });
  socket.opened = new Promise(function (resolve) { socket.on('open', resolve); });
  socket.wait = function (test) {
    var seen = socket.heard.filter(test)[0];
    if (seen) { socket.heard.splice(socket.heard.indexOf(seen), 1); return Promise.resolve(seen); }
    return new Promise(function (resolve, reject) {
      socket.waiters.push({ test: test, resolve: function (m) { socket.heard.splice(socket.heard.indexOf(m), 1); resolve(m); } });
      setTimeout(function () { reject(new Error('timed out waiting')); }, 3000);
    });
  };
  socket.say = function (m) { socket.send(JSON.stringify(m)); };
  return socket;
}
function t(kind) { return function (m) { return m.t === kind; }; }
function start(session) { return new Promise(function (resolve, reject) { session.start(function (e, a) { if (e) reject(e); else resolve(a); }); }); }
function stop(session) { return new Promise(function (resolve) { session.stop(resolve); }); }
function listening(port) {
  return new Promise(function (resolve) {
    var r = http.get({ port: port, path: '/' }, function () { resolve(true); });
    r.on('error', function () { resolve(false); });
  });
}

function run() {
  var session = new relay.Session({ root: root, app: 'dev.lamp.app.pong', addresses: function () { return ['192.168.1.40']; }, bind: '127.0.0.1' });
  var answer, pagePort, relayPort, host, a, b, link, join;
  return start(session).then(function (got) {
    answer = got;
    pagePort = session.pagePort;
    relayPort = session.relayPort;
    assert.strictEqual(answer.page, 'http://192.168.1.40:' + pagePort + '/', 'the link phones open is the TV\'s address, never loopback');
    assert.strictEqual(answer.links[0].socket, 'ws://127.0.0.1:' + relayPort + '/');
    return Promise.all([get(pagePort, '/'), get(pagePort, '/lamp-relay.json', '192.168.1.40:' + pagePort), get(pagePort, '/', 'attacker.example:' + pagePort),
                        get(pagePort, '/.hidden'), get(pagePort, '/link.txt'), get(pagePort, '/%2e%2e/lg-phones-outside.txt')]);
  }).then(function (pages) {
    assert.strictEqual(pages[0].body, '<p>pad</p>');
    assert.deepStrictEqual(JSON.parse(pages[1].body), { port: relayPort, app: 'dev.lamp.app.pong' });
    assert.strictEqual(pages[2].status, 403, 'a name that isn\'t the TV\'s reads nothing');
    assert.strictEqual(pages[3].status, 404, 'hidden files are never served');
    assert.strictEqual(pages[4].status, 404, 'a link is never followed');
    assert.strictEqual(pages[5].status, 404, 'nothing above the page');

    // The game's page: no origin it could prove, so its credential lets it in.
    host = client(answer.links[0].socket, 'file://');
    return host.opened;
  }).then(function () {
    host.say({ t: 'hello', app: 'dev.lamp.app.pong', credential: answer.links[0].credential });
    return host.wait(t('welcome'));
  }).then(function (welcome) {
    assert.strictEqual(welcome.role, 'host');
    host.say({ t: 'link' });
    return host.wait(t('link'));
  }).then(function (m) {
    link = m.url;
    assert.ok(link.indexOf('http://192.168.1.40:' + pagePort + '/#') === 0);
    join = link.split('#')[1];

    // A page from elsewhere is turned away before its socket opens.
    var stranger = client('ws://127.0.0.1:' + relayPort + '/', 'http://attacker.example:' + pagePort);
    return stranger.failed;
  }).then(function (failure) {
    assert.ok(failure, 'another site\'s page can\'t open a socket');
    // The game's own phone page joins with its link.
    a = client('ws://127.0.0.1:' + relayPort + '/', 'http://192.168.1.40:' + pagePort);
    return a.opened;
  }).then(function () {
    a.say({ t: 'hello', app: 'dev.lamp.app.pong', credential: join });
    return Promise.all([a.wait(t('welcome')), host.wait(t('joined'))]);
  }).then(function (both) {
    assert.strictEqual(both[0].place, 1);
    assert.strictEqual(both[0].host, true);
    assert.strictEqual(both[1].player, 1);
    a.say({ t: 'button', name: 'a', down: true, seq: 1 });
    return host.wait(t('button'));
  }).then(function (button) {
    assert.deepStrictEqual([button.player, button.name, button.down], [1, 'a', true]);
    // A second phone, which has never seen the first, joins as player 2 with the same link.
    b = client('ws://127.0.0.1:' + relayPort + '/', 'http://192.168.1.40:' + pagePort);
    return b.opened;
  }).then(function () {
    b.say({ t: 'hello', app: 'dev.lamp.app.pong', credential: join });
    return b.wait(t('welcome'));
  }).then(function (welcome) {
    assert.strictEqual(welcome.place, 2);
    // A file from the phone, held to the size it said.
    b.say({ t: 'file', id: 7, name: 'pic.png', type: 'image/png', size: 4 });
    return host.wait(t('file'));
  }).then(function (file) {
    assert.deepStrictEqual([file.player, file.id, file.size], [2, 7, 4]);
    var piece = Buffer.from([1, 0, 0, 0, 0, 0, 0, 7, 9, 9, 9, 9]);
    b.send(piece);
    return host.wait(function (m) { return m.binary; });
  }).then(function (got) {
    assert.strictEqual(got.binary[1], 2, 'the piece says which player it\'s from');
    host.say({ t: 'file-ack', player: 2, id: 7, got: 4 });
    return b.wait(t('file-ack'));
  }).then(function (ack) {
    assert.strictEqual(ack.got, 4);
    // A message over the limit closes the socket that sent it.
    b.say({ t: 'message', data: new Array(16 * 1024 + 10).join('x') });
    return Promise.all([b.closed, host.wait(t('left'))]);
  }).then(function (both) {
    assert.strictEqual(both[0], 1009);
    assert.strictEqual(both[1].player, 2);
    // A credential that isn't the session's gets nowhere.
    var forged = client('ws://127.0.0.1:' + relayPort + '/', 'http://192.168.1.40:' + pagePort);
    forged.on('open', function () { forged.say({ t: 'hello', app: 'dev.lamp.app.pong', credential: join.slice(0, -2) + 'AA' }); });
    return forged.closed;
  }).then(function (code) {
    assert.strictEqual(code, 4003);
    // Stopping ends every socket and closes both ports.
    return Promise.all([stop(session), host.closed, a.closed]);
  }).then(function (codes) {
    assert.strictEqual(codes[1], 4005);
    assert.strictEqual(codes[2], 4005);
    return Promise.all([listening(pagePort), listening(relayPort)]);
  }).then(function (open) {
    assert.deepStrictEqual(open, [false, false], 'nothing listens once the session stops');
    // A new session has a new key: the old link is worthless.
    return start(session);
  }).then(function (fresh) {
    var again = client(fresh.links[0].socket, 'http://192.168.1.40:' + session.pagePort);
    again.on('open', function () { again.say({ t: 'hello', app: 'dev.lamp.app.pong', credential: join }); });
    return again.closed;
  }).then(function (code) {
    assert.strictEqual(code, 4003, 'a link from an earlier session gets nowhere');
    return stop(session);
  });
}

// Connections that never prove themselves: held to a few from one address, and let go when the session stops, upgraded
// or not, so nothing from an ended session (its key among it) is still reachable.
function runRaw() {
  var session = new relay.Session({ root: root, app: 'dev.lamp.app.pong', addresses: function () { return ['192.168.1.40']; }, bind: '127.0.0.1' });
  var held = [];
  function open(port) {
    var s = net.connect(port, '127.0.0.1');
    s.on('error', function () {});
    s.gone = new Promise(function (resolve) { s.on('close', function () { resolve(true); }); });
    return s;
  }
  function settle(ms) { return new Promise(function (resolve) { setTimeout(resolve, ms); }); }
  return start(session).then(function () {
    for (var i = 0; i < 8; i++) held.push(open(session.relayPort));
    return settle(200);
  }).then(function () {
    var ninth = open(session.relayPort);
    return Promise.race([ninth.gone, settle(1000).then(function () { return false; })]);
  }).then(function (gone) {
    assert.strictEqual(gone, true, 'a ninth connection waiting from one address is let go');
    return stop(session);
  }).then(function () {
    return Promise.race([Promise.all(held.map(function (s) { return s.gone; })), settle(1000).then(function () { return false; })]);
  }).then(function (gone) {
    assert.ok(gone, 'every connection to the relay goes when the session stops');
    // One device's IPv6 addresses count as one place.
    var a = relay.addressOf({ remoteAddress: 'fe80::1:2:3:4' }), b = relay.addressOf({ remoteAddress: 'fe80::5:6:7:8' });
    assert.strictEqual(a, b, 'two addresses in one /64 are one place');
    assert.notStrictEqual(relay.addressOf({ remoteAddress: '2001:db8:0:1::1' }), relay.addressOf({ remoteAddress: '2001:db8:0:2::1' }));
    // A port that can't open is said, not thrown: the service goes on, and the next start can work.
    var nowhere = new relay.Session({ root: root, app: 'dev.lamp.app.pong', addresses: function () { return []; }, bind: '203.0.113.9' });
    return new Promise(function (resolve) { nowhere.start(function (error) { resolve(error); }); });
  }).then(function (error) {
    assert.ok(error && /couldn't open/.test(error.message), 'a listener that can\'t open is an error the caller hears');
  });
}

// The service's door on the TV's bus, with webos-service stood in for.
function runService() {
  var folder = fs.mkdtempSync(path.join(os.tmpdir(), 'lg-service-'));
  ['service.js', 'relay.js'].forEach(function (f) { fs.copyFileSync(path.join(service, f), path.join(folder, f)); });
  fs.symlinkSync(path.join(service, 'node_modules'), path.join(folder, 'node_modules'));
  fs.mkdirSync(path.join(folder, 'phone'));
  fs.writeFileSync(path.join(folder, 'phone/index.html'), 'pad');
  fs.writeFileSync(path.join(folder, 'package.json'), JSON.stringify({ name: 'dev.lamp.app.pong.phones', main: 'service.js',
    lamp: { service: 'dev.lamp.app.pong.phones', owner: 'dev.lamp.app.pong', app: 'dev.lamp.app.pong' } }));
  var methods = {};
  function FakeService(id) { assert.strictEqual(id, 'dev.lamp.app.pong.phones'); }
  FakeService.prototype.register = function (name, request, cancel) { methods[name] = { request: request, cancel: cancel }; };
  var load = Module._load;
  Module._load = function (request) { return request === 'webos-service' ? FakeService : load.apply(this, arguments); };
  require(path.join(folder, 'service.js'));
  Module._load = load;
  var token = 0;
  function call(name, sender, subscribe) {
    var message = { sender: sender, isSubscription: !!subscribe, uniqueToken: String(++token), answers: [] };
    message.respond = function (a) { message.answers.push(a); if (message.wake) message.wake(); };
    message.next = function () {
      if (message.answers.length) return Promise.resolve(message.answers.shift());
      return new Promise(function (resolve) { message.wake = function () { message.wake = null; resolve(message.answers.shift()); }; });
    };
    methods[name].request(message);
    return message;
  }
  var stranger = call('start', 'com.someone.else', true), once = call('start', 'dev.lamp.app.pong', false), game, port;
  return Promise.all([stranger.next(), once.next()]).then(function (answers) {
    assert.strictEqual(answers[0].returnValue, false, 'another app can\'t start the game\'s phones');
    assert.ok(!answers[0].links);
    assert.strictEqual(answers[1].returnValue, false, 'only a subscription starts them');
    assert.strictEqual(call('session', 'com.someone.else').answers[0].returnValue, false, 'nor be given the host\'s credential');
    game = call('start', 'dev.lamp.app.pong', true);
    return game.next();
  }).then(function (answer) {
    assert.strictEqual(answer.returnValue, true);
    port = +/:(\d+)\/$/.exec(answer.links[0].socket)[1];
    return listening(port);
  }).then(function (open) {
    assert.strictEqual(open, true);
    // The game closes: its subscription is cancelled, and the session ends with it.
    methods.start.cancel(game);
    return new Promise(function (resolve) { setTimeout(resolve, 100); });
  }).then(function () { return listening(port); }).then(function (open) {
    assert.strictEqual(open, false, 'the game gone, nothing listens');
  });
}

// A check that waits for something that never comes fails rather than hangs.
setTimeout(function () { console.error('A check timed out.'); process.exit(1); }, 20000);

run().then(runRaw).then(runService).then(function () {
  console.log('LG phone service: all checks passed on Node ' + process.version);
  process.exit(0);
}, function (error) {
  console.error(error && error.stack || error);
  process.exit(1);
});
