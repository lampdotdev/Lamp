// One Home HQ on every screen: the copies of this screen (the Mac, the kitchen iPad, the TV, the photo frame) keep the
// same family, chores, shopping list and settings, through Lamp.wish in Web/lamp.js. Each part of DATA.snapshot() is
// a value the copies share (the later change wins where two were made apart); the calendars and photos are read by
// a copy that can read them (the Mac, an iPhone or iPad: LampNative) and handed to the others, the calendars as values
// and the pictures as files. A copy alone keeps working on what it saved, and catches up when it next meets the others.
// A copy shares only what changes on it: one opened for the first time (still showing the examples) takes what the
// others have rather than putting its examples over them, and gives a part only no copy has shared yet.
(function () {
  'use strict';
  var D = window.DATA;
  var W = window.Lamp && window.Lamp.wish;
  if (!W) return;
  var PARTS = ['cleared', 'events', 'groceries', 'people', 'chores', 'done', 'stars', 'favs', 'settings'];
  var CHUNKS = 4;                     // the calendars, in up to four values of at most 8 KB each
  var known = {};                     // each value as JSON, as last set here or heard from another copy
  var base = {};                      // each part of this copy's data as JSON, as it was when last in step with the others
  var ready = false;

  function json(v) { return JSON.stringify(v === undefined ? null : v); }
  function native() { return !!(window.LampNative && LampNative.available); }

  function set(key, value) {
    var text = json(value);
    if (known[key] === text) return;
    if (text.length > W.valueLimit) { if (window.console) console.warn('Home HQ: ' + key + ' is too big to share (' + text.length + ' bytes)'); return; }
    known[key] = text;
    W.set(key, value);
  }

  // In step: what this copy has now is what the others have (after taking their values, or sharing its own).
  function settle() {
    var snap = D.snapshot();
    PARTS.forEach(function (k) { base[k] = json(snap[k]); });
  }

  // What changed here, and only that, goes to the other copies.
  function share() {
    if (!ready) return;
    var snap = D.snapshot();
    PARTS.forEach(function (k) {
      var text = json(snap[k]);
      if (text === base[k]) return;
      base[k] = text;
      if (snap[k] != null) set(k, snap[k]);
    });
    if (native() && D.settings.calendars) shareCalendars();
  }

  // A part no copy has shared yet (the first copy ever, or a part a newer version added) is given as this copy has it.
  function seed() {
    var have = W.values() || {}, snap = D.snapshot();
    PARTS.forEach(function (k) { if (have[k] === undefined && snap[k] != null) set(k, snap[k]); });
  }

  // The calendars this copy read, short enough to share: [title, start, end, allDay, people, loc], split across values.
  function shareCalendars() {
    var rows = D.events.filter(function (e) { return e.cal; }).map(function (e) {
      return [e.title, +e.start, +e.end, e.allDay ? 1 : 0, e.people, e.loc || ''];
    });
    var chunks = [], cur = [], size = 2;
    rows.forEach(function (r) {
      var n = json(r).length + 1;
      if (size + n > W.valueLimit - 64) { chunks.push(cur); cur = []; size = 2; }
      if (chunks.length < CHUNKS) { cur.push(r); size += n; }
    });
    if (cur.length && chunks.length < CHUNKS) chunks.push(cur);
    for (var i = 0; i < CHUNKS; i++) set('cal' + i, chunks[i] || null);
  }

  // What another copy shared comes in here.
  function take(key, value) {
    var text = json(value);
    if (known[key] === text) return;
    known[key] = text;
    if (value == null) return;
    if (/^cal\d$/.test(key)) {
      if (native() && D.settings.calendars) return;   // this copy reads them itself
      var all = [];
      for (var i = 0; i < CHUNKS; i++) { try { all = all.concat(JSON.parse(known['cal' + i] || 'null') || []); } catch (e) {} }
      D.events = D.events.filter(function (e) { return !e.cal; }).concat(all.map(function (r, n) {
        return { id: 'k' + n, cal: true, title: r[0], start: new Date(r[1]), end: new Date(r[2]), allDay: !!r[3], people: r[4], loc: r[5] || undefined };
      }));
    } else if (key === 'photos') {
      havePhotos(value);
      return;
    } else if (PARTS.indexOf(key) > -1) {
      var part = {};
      part[key] = value;
      D.restore(part);
      if (key === 'settings') { App.loadWeather(); App.loadCalendars(); }
    } else return;
    settle();
    D.save();
    App.emit('data');
    App.rerender();
  }

  // ------------------------------------------------------------ photos
  // A copy that reads the album sends each picture to the copies that can't, once each time they meet; the pictures
  // listed in the 'photos' value show as they arrive.
  var sentTo = {}, arrived = {};
  function sendPhotos() {
    if (!native() || D.settings.album == null) return;
    var mine = D.photos.filter(function (p) { return p.src && p.id; });
    if (!mine.length) return;
    set('photos', mine.map(function (p) { return { id: p.id, o: p.o, date: p.date, fav: !!p.fav }; }));
    var me = W.copy();
    var others = (W.apps() || []).filter(function (a) { return a.peer === W.me(); })
      .concat((W.peers() || []).filter(function (a) { return a.peer === W.me(); }));
    others.forEach(function (app) {
      (app.copies || []).forEach(function (c) {
        if (c.id === me || sentTo[c.id]) return;
        sentTo[c.id] = true;
        mine.forEach(function (p) {
          var bytes = atob(p.src.split(',')[1]), buf = new Uint8Array(bytes.length);
          for (var i = 0; i < bytes.length; i++) buf[i] = bytes.charCodeAt(i);
          W.sendFile(buf, c.id, { name: p.id, type: 'image/jpeg' });
        });
      });
    });
  }
  function havePhotos(list) {
    if (native() && D.settings.album != null) return;   // this copy shows its own
    var byId = {};
    D.photos.forEach(function (p) { if (p.id) byId[p.id] = p; });
    D.photos = list.map(function (m) { return byId[m.id] || { id: m.id, o: m.o, date: m.date, fav: m.fav, place: '', tag: m.date || m.id, src: arrived[m.id] }; })
      .filter(function (p) { return p.src; });
    App.emit('data');
  }

  W.onFile(function (from, file) {
    if (from !== W.me() || !/^[\w.:\/+=-]{1,200}$/.test(file.name)) return file.cancel();
    file.done.then(function (buf) {
      arrived[file.name] = URL.createObjectURL(new Blob([buf], { type: 'image/jpeg' }));
      try { havePhotos(JSON.parse(known.photos || '[]')); } catch (e) {}
    }, function () {});
  });

  // ------------------------------------------------------------ joining
  W.onChange(function (key, value) { take(key, value); });
  W.onPeers(function () { sendPhotos(); share(); });
  App.on('data', share);
  App.on('ready', function () {
    W.start();
    // The values kept on this device from last time come first; then whatever this copy has that they don't goes out.
    var kept = W.values() || {};
    Object.keys(kept).forEach(function (k) { take(k, kept[k]); });
    settle();
    ready = true;
    // Once the others have had time to say what they have, anything none of them has shared goes from here.
    setTimeout(seed, 6000);
    sendPhotos();
  });
  // A copy that reads calendars or the album shares them again once they're read.
  App.on('data', function () { if (native()) sendPhotos(); });
})();
