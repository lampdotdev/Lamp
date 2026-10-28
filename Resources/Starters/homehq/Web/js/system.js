// Banners, the example pictures, and the settings drawer (the clock at the bottom of the rail, or D).
(function () {
  'use strict';
  var D = window.DATA, $ = App.$;

  // ------------------------------------------------------------ example pictures
  // An example photo is a landscape drawn from its seed (sky, sun or moon, hills, water), so the screen ships no
  // pictures and fetches none. A seed's words pick its light: snow, night, autumn, beach, garden…
  var LOOKS = [
    [/snow|winter/, ['#BFD3E6', '#EEF3F8'], '#FFFFFF', ['#DCE6EF', '#C3D2E0', '#A9BCCD'], '#9FB6CB'],
    [/night|city|xmas|candles/, ['#0E1633', '#2B2D5C'], '#F5E7B8', ['#1C2448', '#151B38', '#0D1128'], '#1A2244'],
    [/autumn|pumpkin|fall|harvest/, ['#F6B26B', '#FBE3C4'], '#FFF4E0', ['#C8642D', '#9B4A26', '#6E3420'], '#B98A5E'],
    [/beach|surf|dune|sail|harbour/, ['#7EC8E3', '#F3E9D2'], '#FFFDF2', ['#E8D3A4', '#D8BD86', '#C2A46E'], '#3E8FB5'],
    [/garden|bloom|tomato|kite|spring/, ['#9AD3F5', '#E7F6FF'], '#FFFBE8', ['#8CCB73', '#5FAE57', '#3F8A45'], '#6FB0D6'],
    [/campfire|sugar|pancake|cake/, ['#F28C5B', '#FFD9A8'], '#FFF1D6', ['#7A4B3A', '#5B372B', '#3E261E'], '#9C6A4E'],
    [/./, ['#86B7E8', '#E9F1F8'], '#FFF8E1', ['#6F9E7F', '#4F7F62', '#355E48'], '#5D93B8']
  ];
  function hash(s) { var h = 2166136261; for (var i = 0; i < s.length; i++) { h ^= s.charCodeAt(i); h = Math.imul(h, 16777619); } return h >>> 0; }
  function ridge(w, h, base, amp, seed, k) {
    var d = 'M0 ' + h + ' L0 ' + Math.round(base), steps = 12;
    for (var i = 1; i <= steps; i++) {
      var x = Math.round(w * i / steps);
      var y = base - amp * (0.5 + 0.5 * Math.sin(i * 0.9 + (seed % 97) / 15 + k * 1.7)) * (0.6 + ((seed >> (i % 16)) & 7) / 14);
      d += ' L' + x + ' ' + Math.round(y);
    }
    return d + ' L' + w + ' ' + h + ' Z';
  }
  var cache = {};
  function img(seed, w, h) {
    var key = seed + w + 'x' + h;
    if (cache[key]) return cache[key];
    var look = LOOKS.filter(function (l) { return l[0].test(seed); })[0], r = hash(seed);
    var water = /lake|dock|surf|beach|harbour|sail|pool/.test(seed);
    var sx = Math.round(w * (0.2 + (r % 60) / 100)), sy = Math.round(h * (0.18 + (r % 17) / 100)), sr = Math.round(Math.min(w, h) * 0.07);
    var svg = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '" preserveAspectRatio="xMidYMid slice">' +
      '<defs><linearGradient id="s" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="' + look[1][0] + '"/><stop offset="1" stop-color="' + look[1][1] + '"/></linearGradient></defs>' +
      '<rect width="' + w + '" height="' + h + '" fill="url(#s)"/>' +
      '<circle cx="' + sx + '" cy="' + sy + '" r="' + sr + '" fill="' + look[2] + '" opacity=".9"/>' +
      '<path d="' + ridge(w, h, h * 0.58, h * 0.22, r, 0) + '" fill="' + look[3][0] + '"/>' +
      '<path d="' + ridge(w, h, h * 0.70, h * 0.16, r >> 3, 1) + '" fill="' + look[3][1] + '"/>' +
      (water ? '<rect y="' + Math.round(h * 0.78) + '" width="' + w + '" height="' + Math.round(h * 0.22) + '" fill="' + look[4] + '" opacity=".92"/>'
        : '<path d="' + ridge(w, h, h * 0.84, h * 0.1, r >> 5, 2) + '" fill="' + look[3][2] + '"/>') +
      '</svg>';
    return (cache[key] = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg));
  }
  App.img = img;

  // ------------------------------------------------------------ banners (amber, actionable)
  App.banner = function (opts) {
    var box = $('#banners');
    var b = document.createElement('div');
    b.className = 'banner banner--' + (opts.tone || 'amber');
    b.innerHTML = App.icon(opts.icon || 'bell', 30) + '<div class="banner-text"><b>' + opts.title + '</b><span>' + (opts.sub || '') + '</span></div>' +
      (opts.action ? '<button class="banner-btn banner-btn--solid" data-act>' + opts.action + '</button>' : '') +
      '<button class="banner-btn" data-x>' + (opts.dismiss || 'Dismiss') + '</button>';
    box.appendChild(b);
    b.classList.add('is-in');
    function kill() { b.remove(); }
    b.querySelector('[data-x]').onclick = kill;
    if (opts.action) b.querySelector('[data-act]').onclick = function () { kill(); opts.onAction(); };
    if (opts.ms) setTimeout(kill, opts.ms);
    return kill;
  };

  // ------------------------------------------------------------ settings drawer
  var S = { places: null, calendars: null, albums: null, finding: false };
  var UPSTREAM = 'https://github.com/wesbos/photo-frame-dashboard';
  function native() { return !!(window.LampNative && LampNative.available); }

  function sec(title, body) { return '<div class="demo-sec"><div class="label label--light">' + title + '</div>' + body + '</div>'; }
  function grid(buttons) { return '<div class="demo-grid">' + buttons.join('') + '</div>'; }
  function btn(attrs, text, on) { return '<button ' + attrs + (on ? ' class="is-on"' : '') + '>' + App.esc(text) + '</button>'; }

  function weatherSec() {
    var place = D.settings.place;
    var body = '<p class="demo-line">' + (place ? App.esc(place.name) : 'Example weather') + '</p>';
    if (S.finding) {
      body += '<div class="demo-find"><input class="demo-input" data-place-q placeholder="Town or city" value="' + App.esc(S.query || '') + '"><button data-place-find>Find</button></div>';
      if (S.places) body += S.places.length ? grid(S.places.map(function (p, i) { return btn('data-place="' + i + '"', p.label); })) : '<p class="demo-note">Nothing by that name.</p>';
    } else {
      body += grid([btn('data-place-choose', place ? 'Change place' : 'Choose place')].concat(place ? [btn('data-place-clear', 'Use example')] : []));
    }
    if (place) body += '<p class="demo-note">Weather data by Open-Meteo.com</p>';
    return sec('Weather', body);
  }

  function calendarsSec() {
    if (!native()) return '';
    var chosen = D.settings.calendars;
    // Turned on at another screen: this one shows what that one reads.
    if (chosen && !App.readsCalendars() && !S.calendars) return sec('Calendars', '<p class="demo-line">From another screen</p>' + grid([btn('data-cal-here', 'Read it here'), btn('data-cal-off', 'Stop showing it')]));
    // The family's one shared calendar: its events are everyone's (js/live.js).
    var body = chosen ? '<p class="demo-line">' + App.esc(chosen.length === 1 ? D.settings.calendarName || chosen[0] : 'All calendars') + '</p>' : '';
    if (S.calendars) body += grid(S.calendars.map(function (c) {
      return btn('data-cal="' + App.esc(c.id) + '"', App.calendarLabel(S.calendars, c), !!chosen && chosen.length === 1 && chosen[0] === c.id);
    }));
    else body += grid([btn('data-cal-on', chosen ? 'Change calendar' : 'Show our calendar')]);
    if (chosen) body += grid([btn('data-cal-off', 'Stop showing it')]);
    return sec('Calendars', body);
  }

  function photosSec() {
    if (!native()) return '';
    var album = D.settings.album;
    var body = album != null && !App.readsAlbum() ? '<p class="demo-line">From another screen</p>' : '';
    if (S.albums) body += grid(S.albums.map(function (a) { return btn('data-album="' + App.esc(a.id) + '"', a.title, album === a.id); }));
    else body += grid([btn('data-albums', album != null ? 'Change album' : 'Show my photos')]);
    if (album != null) body += grid([btn('data-album-off', 'Stop showing them')]);
    return sec('Photos', body);
  }

  function settingsHTML() {
    return '<div class="demo-panel">' +
      '<div class="demo-head"><div><div class="label label--light">Home HQ</div><h2 class="serif">Settings</h2></div><button class="demo-x" data-demo-close>' + App.icon('x', 28) + '</button></div>' +
      weatherSec() + calendarsSec() + photosSec() +
      sec('Your family', grid([btn('data-family', 'Family'), btn('data-chores', 'Chores')])) +
      (D.isSetUp() && D.edited.people ? '' : sec(D.isSetUp() ? 'Your family' : 'Example family', grid([btn('data-setup', 'Set up my family')]))) +
      sec('Screen', grid([btn('data-mode="ambient"', 'Photo frame'), btn('data-mode="night"', 'Night clock')])) +
      '<p class="demo-note">Based on <a href="' + UPSTREAM + '" target="_blank" rel="noopener">photo-frame-dashboard</a> by <a href="https://wesbos.com" target="_blank" rel="noopener">Wes Bos</a> (MIT)</p>' +
      '</div>';
  }
  App.openSettings = function () {
    var el = $('#demo');
    var focused = document.activeElement && document.activeElement.closest && document.activeElement.closest('#demo [data-place-q]');
    el.innerHTML = settingsHTML();
    el.classList.add('is-open');
    if (window.Lamp) Lamp.scope = el;
    if (focused) { var q = el.querySelector('[data-place-q]'); if (q) q.focus(); }
    else if (window.Lamp && Lamp.focusFirst) Lamp.focusFirst();
  };
  function closeSettings() {
    $('#demo').classList.remove('is-open');
    S.finding = false; S.places = null; S.albums = null; S.calendars = null;
    if (window.Lamp) { Lamp.scope = null; Lamp.focus('.rail-clock'); }
  }
  App.closeSettings = closeSettings;

  function findPlace() {
    var q = $('#demo [data-place-q]').value.trim();
    if (!q) return;
    S.query = q;
    App.findPlaces(q).then(function (list) { S.places = list; App.openSettings(); }, function () { S.places = []; App.openSettings(); });
  }

  function settingsClick(e) {
    var b = e.target.closest('button');
    if (!b) { if (e.target === $('#demo')) closeSettings(); return; }
    var d = b.dataset;
    if (b.hasAttribute('data-demo-close')) return closeSettings();
    if (b.hasAttribute('data-place-choose')) { S.finding = true; S.places = null; App.openSettings(); var q = $('#demo [data-place-q]'); if (q) q.focus(); return; }
    if (b.hasAttribute('data-place-find')) return findPlace();
    if (d.place != null) {
      var p = S.places[+d.place];
      D.settings.place = { name: p.name, lat: p.lat, lon: p.lon };
      S.finding = false; S.places = null;
      App.emit('data'); App.loadWeather();
      return App.openSettings();
    }
    if (b.hasAttribute('data-place-clear')) { D.settings.place = null; App.exampleWeather(); App.emit('data'); return App.openSettings(); }
    // This screen reads the family's calendar from now on (the one that did may be gone), and shares it with the others.
    // This screen reads the family's calendar from now on (the one that did may be gone): chosen from its own list, since
    // a calendar's id is the device's own.
    if (b.hasAttribute('data-cal-here')) {
      LampNative.call('calendars', {}).then(function (list) { S.calendars = list; App.openSettings(); },
        function () { App.toast('Calendars aren’t allowed. Turn them on in System Settings → Privacy.', { icon: 'calendar' }); });
      return;
    }
    if (b.hasAttribute('data-cal-on')) {
      LampNative.call('calendars', {}).then(function (names) { S.calendars = names; App.openSettings(); },
        function () { App.toast('Calendars aren’t allowed. Turn them on in System Settings → Privacy.', { icon: 'calendar' }); });
      return;
    }
    if (d.cal != null) {
      var picked = S.calendars.filter(function (c) { return c.id === d.cal; })[0];
      D.settings.calendars = [d.cal]; D.settings.calendarName = picked ? picked.title : d.cal; D.settings.calendarsBy = App.me(); S.calendars = null;
      App.emit('data'); App.loadCalendars();
      return App.openSettings();
    }
    if (b.hasAttribute('data-cal-off')) { D.settings.calendars = null; App.loadCalendars(); App.emit('data'); return App.openSettings(); }
    if (b.hasAttribute('data-albums')) {
      LampNative.call('albums', {}).then(function (list) { S.albums = list; App.openSettings(); },
        function () { App.toast('Photos aren’t allowed. Turn them on in System Settings → Privacy.', { icon: 'photo' }); });
      return;
    }
    if (d.album != null) { D.settings.album = d.album; D.settings.albumBy = App.me(); S.albums = null; App.emit('data'); App.loadPhotos(); return App.openSettings(); }
    if (b.hasAttribute('data-album-off')) { D.settings.album = null; App.loadPhotos(); App.emit('data'); return App.openSettings(); }
    if (b.hasAttribute('data-family')) { closeSettings(); return App.editFamily(); }
    if (b.hasAttribute('data-chores')) { closeSettings(); return App.editChores(); }
    if (b.hasAttribute('data-setup')) { closeSettings(); return App.setup('family'); }
    if (d.mode) { closeSettings(); App.setMode(d.mode); }
  }

  App.on('ready', function () {
    $('#demo').addEventListener('click', settingsClick);
    $('#demo').addEventListener('keydown', function (e) { if (e.target.hasAttribute('data-place-q') && e.keyCode === 13) { e.preventDefault(); findPlace(); } });
    $('#railClock').addEventListener('click', App.openSettings);
    $('#railSettings').addEventListener('click', App.openSettings);
    if (window.Lamp && Lamp.onBack) Lamp.onBack(function () {
      if ($('#demo').classList.contains('is-open')) { closeSettings(); return true; }
      if ($('#sheetLayer').classList.contains('is-open')) { App.closeSheet(); return true; }
      if (App.mode !== 'day') { App.setMode('day'); return true; }
      if (App.current !== 'home') { App.go('home'); return true; }
      return false;
    });
    document.addEventListener('keydown', function (e) {
      // Ask has the keys while it's open (js/agent.js).
      if (e.target.tagName === 'INPUT' || (App.askOpen && App.askOpen())) return;
      var k = (e.key || '').toLowerCase();
      if (k === 'd') { $('#demo').classList.contains('is-open') ? closeSettings() : App.openSettings(); }
      if (k === 'a') App.setMode('ambient');
      if (k === 'n') App.setMode('night');
      var views = ['home', 'calendar', 'tasks', 'shopping', 'photos'];
      if (k >= '1' && k <= '5') App.go(views[+k - 1]);
    });
  });
})();
