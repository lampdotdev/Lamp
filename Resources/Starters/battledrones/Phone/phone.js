// A phone's command table for a side of a Battle Drones match played together. Everything here goes to the game on
// the screen (the TV, or the Mac) through Lamp's controllers (lamp-controller.js): the game sends this phone its
// side's view a few times a second (`state`) and the map's picture once (a file), and this page sends back what the
// player did: a tap or a box on the map, a quick command, something bought. The game decides what each means, as a
// tap on its own map would.
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var SIDES = { blue: '#7ec1ff', red: '#ff8a7a', green: '#86eea0', purple: '#c9a2ff' };
  var keep = function (k, v) { try { if (v === undefined) return localStorage.getItem(k); localStorage.setItem(k, v); } catch (e) { return null; } };

  // Who this phone is, kept so it finds its side again after a reload or a rematch.
  var id = keep('bd.id');
  if (!id) { id = 'p' + Math.random().toString(36).slice(2, 10); keep('bd.id', id); }
  var nameBox = $('name');
  nameBox.value = keep('bd.name') || '';

  var state = null, tab = 'build', mapImage = null, side = null, number = null;

  function show(screen) {
    ['join', 'lobby', 'match', 'ended'].forEach(function (s) { $(s).hidden = s !== screen; });
  }

  var pad = LampController.connect({
    onPlayer: function (n) { number = n; hello(); },
    onState: function (s) {
      var says = { connecting: 'Connecting…', connected: 'Connected. Waiting for the game…', waiting: "The game isn't open on the screen yet.",
                   ended: 'The game has ended. Scan the code on the screen again to join.', full: 'The game is full.' };
      $('status').textContent = says[s] || s;
      if (s !== 'connected') show('join');
    },
    onMessage: heard,
    onFile: function (file) {
      file.done.then(function (bytes) {
        var img = new Image();
        img.onload = function () { mapImage = img; draw(); };
        img.src = URL.createObjectURL(new Blob([bytes], { type: file.type || 'image/png' }));
      }, function () {});
    }
  });

  function hello() {
    var name = nameBox.value.trim();
    keep('bd.name', name);
    pad.send({ t: 'hi', id: id, name: name });
  }
  nameBox.addEventListener('change', hello);

  function heard(m) {
    if (!m || typeof m !== 'object') return;
    if (m.t === 'lobby') return lobby(m);
    if (m.t === 'state') { state = m; return match(); }
    if (m.t === 'note') return note(m.text);
  }

  // ---------------------------------------------------------------- lobby ---

  function lobby(m) {
    side = m.you;
    if (m.started && side) { show('match'); return; }
    if (m.started) { show('join'); $('status').textContent = 'A battle is under way. You can join the next one.'; return; }
    show('lobby');
    $('lobby-map').textContent = m.map;
    var seats = $('seats');
    seats.innerHTML = '';
    m.seats.forEach(function (s) {
      var b = document.createElement('button');
      b.className = 'seat' + (s.side === side ? ' mine' : '');
      b.style.setProperty('--side', s.color);
      b.innerHTML = '<span class="dot"></span><b></b><span class="who"></span>';
      b.querySelector('b').textContent = s.name;
      b.querySelector('.who').textContent = s.side === side ? 'You' : s.who ? s.icon + ' ' + s.who : 'Computer · tap to take';
      b.addEventListener('click', function () { if (!s.who) pad.send({ t: 'seat', side: s.side }); });
      seats.appendChild(b);
    });
  }
  $('start').addEventListener('click', function () { pad.send({ t: 'start' }); });

  // ---------------------------------------------------------------- match ---

  var canvas = $('mapcanvas'), ctx = canvas.getContext('2d');

  function match() {
    if (!state) return;
    if (state.winner) {
      show('ended');
      $('result').textContent = state.winner === 'draw' ? 'DRAW' : state.winner === state.side ? 'VICTORY' : 'DEFEATED';
      return;
    }
    show('match');
    document.body.style.setProperty('--side', SIDES[state.side] || '#7ec1ff');
    $('me').textContent = state.out ? 'Knocked out: watching' : state.side.charAt(0).toUpperCase() + state.side.slice(1);
    $('scrap').textContent = '⛁ ' + state.scrap;
    $('pending').textContent = state.pending ? (state.pending.ready ? state.pending.name + ' going up' : state.pending.name + ' · ' + state.pending.left + 's') : '';
    if (state.arming) note('Tap the map where the calldown goes.');
    draw();
    shop();
  }

  function draw() {
    if (!state) return;
    var box = $('map').getBoundingClientRect(), ratio = window.devicePixelRatio || 1;
    var S = Math.floor(Math.min(box.width, box.height));
    if (canvas.width !== S * ratio) { canvas.width = canvas.height = S * ratio; canvas.style.width = canvas.style.height = S + 'px'; }
    var k = S * ratio / state.size;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    if (mapImage) ctx.drawImage(mapImage, 0, 0, canvas.width, canvas.height);
    else { ctx.fillStyle = '#26301f'; ctx.fillRect(0, 0, canvas.width, canvas.height); }
    state.buildings.forEach(function (b) {
      ctx.fillStyle = SIDES[b[3]];
      ctx.fillRect(b[0] * k, b[1] * k, b[2] * k, b[2] * k);
      if (b[4]) { ctx.lineWidth = 2 * ratio; ctx.strokeStyle = '#fff'; ctx.strokeRect(b[0] * k, b[1] * k, b[2] * k, b[2] * k); }
    });
    state.foes.forEach(function (u) {
      ctx.fillStyle = SIDES[u[2]];
      ctx.fillRect(u[0] * k - 3 * ratio, u[1] * k - 3 * ratio, 6 * ratio, 6 * ratio);
    });
    var sel = {};
    state.sel.forEach(function (i) { sel[i] = true; });
    state.own.forEach(function (u) {
      ctx.beginPath();
      ctx.arc(u[1] * k, u[2] * k, (u[3] ? 3 : 4) * ratio, 0, Math.PI * 2);
      ctx.fillStyle = sel[u[0]] ? '#fff' : SIDES[state.side];
      ctx.fill();
      if (sel[u[0]]) { ctx.lineWidth = 1.5 * ratio; ctx.strokeStyle = SIDES[state.side]; ctx.stroke(); }
    });
    if (drag && drag.boxing) {
      ctx.lineWidth = 1.5 * ratio;
      ctx.strokeStyle = '#fff';
      ctx.setLineDash([6 * ratio, 4 * ratio]);
      ctx.strokeRect(Math.min(drag.x0, drag.x1) * k, Math.min(drag.y0, drag.y1) * k, Math.abs(drag.x1 - drag.x0) * k, Math.abs(drag.y1 - drag.y0) * k);
      ctx.setLineDash([]);
    }
  }

  // A tap selects or orders, a drag boxes units, a long press shows the spot on the screen.
  var drag = null, holdTimer = null;
  function tile(e) {
    var r = canvas.getBoundingClientRect();
    return { x: (e.clientX - r.left) / r.width * state.size, y: (e.clientY - r.top) / r.height * state.size, px: e.clientX, py: e.clientY };
  }
  canvas.addEventListener('pointerdown', function (e) {
    if (!state) return;
    canvas.setPointerCapture(e.pointerId);
    var t = tile(e);
    drag = { x0: t.x, y0: t.y, x1: t.x, y1: t.y, px: t.px, py: t.py, boxing: false, held: false };
    clearTimeout(holdTimer);
    holdTimer = setTimeout(function () {
      if (!drag || drag.boxing) return;
      drag.held = true;
      pad.send({ t: 'look', x: drag.x0, y: drag.y0 });
      buzz(30);
      note('Showing that spot on the screen.');
    }, 550);
  });
  canvas.addEventListener('pointermove', function (e) {
    if (!drag) return;
    var t = tile(e);
    drag.x1 = t.x; drag.y1 = t.y;
    if (Math.hypot(t.px - drag.px, t.py - drag.py) > 14) { drag.boxing = true; clearTimeout(holdTimer); }
    if (drag.boxing) draw();
  });
  canvas.addEventListener('pointerup', function () {
    clearTimeout(holdTimer);
    if (!drag) return;
    if (drag.boxing) pad.send({ t: 'box', x0: drag.x0, y0: drag.y0, x1: drag.x1, y1: drag.y1 });
    else if (!drag.held) { pad.send({ t: 'tap', x: drag.x0, y: drag.y0 }); buzz(10); }
    drag = null;
    draw();
  });
  canvas.addEventListener('pointercancel', function () { clearTimeout(holdTimer); drag = null; draw(); });

  document.querySelectorAll('[data-cmd]').forEach(function (b) {
    b.addEventListener('click', function () { pad.send({ t: 'cmd', c: b.dataset.cmd }); buzz(10); });
  });
  document.querySelectorAll('[data-tab]').forEach(function (b) {
    b.addEventListener('click', function () {
      tab = b.dataset.tab;
      document.querySelectorAll('[data-tab]').forEach(function (o) { o.classList.toggle('on', o === b); });
      shop();
    });
  });

  // What the side can buy, from the game: a building (put down where it fits once it's built), a unit, a calldown.
  function shop() {
    var list = $('shop'), items = state.shop.filter(function (i) { return i.type === tab; });
    var shown = list.children.length === items.length && Array.prototype.every.call(list.children, function (b, n) { return b.dataset.kind === items[n].kind; });
    if (!shown) {
      list.innerHTML = '';
      items.forEach(function (item) {
        var b = document.createElement('button');
        b.dataset.kind = item.kind;
        b.innerHTML = '<b></b><small></small>';
        b.addEventListener('click', function () { pad.send({ t: 'buy', item: { type: item.type, kind: item.kind } }); buzz(15); });
        list.appendChild(b);
      });
    }
    items.forEach(function (item, n) {
      var b = list.children[n];
      b.querySelector('b').textContent = item.name;
      b.querySelector('small').textContent = item.type === 'power' ? (item.ok ? 'Ready' : item.charge + '%') : item.ok ? '⛁ ' + item.cost : item.why || '⛁ ' + item.cost;
      b.classList.toggle('off', !item.ok);
    });
  }

  var noteTimer = null;
  function note(text) {
    $('note').textContent = text;
    clearTimeout(noteTimer);
    noteTimer = setTimeout(function () { $('note').textContent = ''; }, 3500);
  }
  function buzz(ms) { if (navigator.vibrate) try { navigator.vibrate(ms); } catch (e) {} }

  window.addEventListener('resize', draw);
  // A code scanned again in this same tab only changes the address's #: start over with the new link.
  window.addEventListener('hashchange', function () { if (location.hash.length > 1) location.reload(); });
})();
