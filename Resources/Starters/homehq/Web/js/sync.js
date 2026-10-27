// One Home HQ on every screen: the copies of this screen (the Mac, the kitchen iPad, the TV, the photo frame) keep the
// family's own data the same through Lamp's shared collections (LampStore.shared in Web/lamp.js), merged item by item,
// so two devices changing different things never lose either. What's here is only the family's own: the examples are
// made on each device and never shared, so a copy opened for the first time can't put them over real data.
//
//   people, chores      the family and the chore list, once changed in the editor (until then, the examples)
//   groceries, events   the shopping list and the events added on the screen (an example changed is kept as theirs;
//                       one taken away is kept as { id, gone: true }, so it stays away)
//   ticks               a chore ticked off: one item per chore per day
//   stars               each kid's stars and week
//   settings            one item per setting: place, calendars, album, cleared
//   favs                photos marked as favourites
//   calendar, photos    what a copy that can read them (LampNative: the Mac, an iPhone or iPad) publishes for the
//                       others: the chosen calendars' events, and the album's pictures (their bytes in
//                       LampStore.sharedFiles('photos'))
//
// The views change DATA as they always have and say so with App.emit('data'); this works out which items changed and
// puts just those. What another copy changes comes in through onChange and is drawn again.
(function () {
  'use strict';
  var D = window.DATA;
  if (!window.LampStore || !LampStore.shared) return;
  var S = {};
  ['people', 'chores', 'groceries', 'events', 'ticks', 'stars', 'settings', 'favs', 'calendar', 'photos'].forEach(function (n) {
    S[n] = LampStore.shared(n);
  });
  var pictures = LampStore.sharedFiles('photos');
  var known = {};          // collection -> id -> the item as JSON, as last put here or taken from another copy
  var taking = false;

  function json(v) { return JSON.stringify(v); }
  function today() { var d = App.now(); return d.getFullYear() + '-' + (d.getMonth() + 1) + '-' + d.getDate(); }
  function mine(name) { return known[name] || (known[name] = {}); }

  // ------------------------------------------------------------ what this copy changed
  // Puts the items that differ from what this copy last held; `gone` ids are deleted, or kept as gone for an example.
  // `dry` only notes what it holds now, putting nothing: after taking the others' items, and as a copy opens, so
  // what's shared is only what then changes here (never a new copy's examples or empty settings over real ones).
  function sync(name, items, examples, dry) {
    if (dry) { known[name] = {}; items.forEach(function (item) { known[name][item.id] = json(item); }); return; }
    var k = mine(name), now = {};
    items.forEach(function (item) {
      now[item.id] = true;
      var text = json(item);
      if (k[item.id] !== text) { k[item.id] = text; S[name].put(item); }
    });
    Object.keys(k).forEach(function (id) {
      if (now[id]) return;
      var was = JSON.parse(k[id]);
      if (was && was.gone) return;
      if (examples && (examples === ALL_GONE || examples[id])) { var g = { id: id, gone: true }; k[id] = json(g); S[name].put(g); }
      else { delete k[id]; S[name]['delete'](id); }
    });
  }

  function exampleIds(list) { var o = {}; list.forEach(function (x) { if (x.ex) o[x.id] = true; }); return o; }
  function plain(o, keys) { var r = {}; keys.forEach(function (key) { if (o[key] !== undefined) r[key] = o[key]; }); return r; }

  var ALL_GONE = { hasOwnProperty: function () { return true; } };
  var GROCERY = ['id', 'name', 'cat', 'qty', 'store', 'done', 'note', 'ex'];
  var original = {};       // each example grocery as made, to tell one the family changed
  D.examples.groceries.forEach(function (g) { original[g.id] = json(plain(g, GROCERY)); });

  function share(dry) {
    if (taking) return;
    if (D.edited.people) sync('people', D.people.map(function (p, i) { return Object.assign(plain(p, ['id', 'name', 'color', 'rgb', 'ink', 'age']), { order: i }); }), null, dry);
    if (D.edited.chores || D.cleared) sync('chores', D.chores.map(function (c) { return plain(c, ['id', 'r', 'who', 'title', 'emoji', 'stars']); }), null, dry);
    sync('groceries', D.groceries.map(function (g) { return plain(g, GROCERY); }).filter(function (g) { return !g.ex || original[g.id] !== json(g); }),
         exampleIds(D.examples.groceries), dry);
    sync('events', D.events.filter(function (e) { return !e.ex && !e.cal; }).map(function (e) {
      return { id: e.id, title: e.title, people: e.people, allDay: !!e.allDay, start: +e.start, end: +e.end, loc: e.loc || '', notes: e.notes || '' };
    }), null, dry);
    var day = today();
    // A tick taken back stays as gone, so the copies can tell "not ticked" from "nothing heard yet".
    sync('ticks', D.chores.filter(function (c) { return c.done; }).map(function (c) { return { id: day + ':' + c.id, day: day, chore: c.id, by: c.doneBy || '' }; }), ALL_GONE, dry);
    sync('stars', Object.keys(D.stars).map(function (k) { return { id: k, stars: D.stars[k], week: D.week[k] || [0, 0, 0, 0, 0, 0, 0] }; }), null, dry);
    sync('settings', [{ id: 'place', value: D.settings.place }, { id: 'calendars', value: D.settings.calendars },
                      { id: 'calendarsBy', value: D.settings.calendarsBy || null }, { id: 'album', value: D.settings.album },
                      { id: 'albumBy', value: D.settings.albumBy || null }, { id: 'cleared', value: D.cleared }], null, dry);
    sync('favs', D.photos.filter(function (p) { return p.fav; }).map(function (p) { return { id: p.id || p.seed }; }), null, dry);
    if (App.readsCalendars() && !dry) publishCalendar();
  }

  function publishCalendar() {
    if (!App.readsCalendars()) return;
    var items = D.events.filter(function (e) { return e.cal; }).map(function (e) {
      return { id: e.id, title: e.title, start: +e.start, end: +e.end, allDay: !!e.allDay, people: e.people, loc: e.loc || '' };
    });
    var text = json(items);
    if (known.publishedCalendar === text) return;
    known.publishedCalendar = text;
    S.calendar.publish(items);
  }

  // The album's pictures, for the copies that can't read it: each one's bytes once, and the list in the album's order.
  function publishPhotos() {
    if (!App.readsAlbum()) return;
    var list = D.photos.filter(function (p) { return p.src && p.id; });
    if (!list.length) return;
    var have = {};
    pictures.all().forEach(function (f) { have[f.name] = true; });
    list.forEach(function (p) {
      if (have[p.id]) return;
      var bytes = atob(p.src.split(',')[1]), buf = new Uint8Array(bytes.length);
      for (var i = 0; i < bytes.length; i++) buf[i] = bytes.charCodeAt(i);
      pictures.put(p.id, buf, 'image/jpeg');
    });
    S.photos.publish(list.map(function (p, i) { return { id: p.id, o: p.o, date: p.date, order: i }; }));
  }

  // ------------------------------------------------------------ what the copies have, into DATA
  function take() {
    taking = true;
    try {
      var settings = {};
      S.settings.all().forEach(function (s) { settings[s.id] = s.value; });
      ['place', 'calendars', 'calendarsBy', 'album', 'albumBy'].forEach(function (k) { if (k in settings) D.settings[k] = settings[k]; });
      if (settings.cleared && !D.cleared) D.clearExamples();

      var people = S.people.all().sort(function (a, b) { return a.order - b.order; });
      if (people.length) { D.people = people; D.edited.people = true; D.ALL = people.map(function (p) { return p.id; }); }

      var chores = S.chores.all();
      if (chores.length || D.cleared) { D.chores = chores; D.edited.chores = true; }
      // Today's ticks, once any copy has ticked or unticked something today; until then the examples' own.
      var ticks = {}, heard = false;
      S.ticks.all().forEach(function (t) { if (t.day === today()) { heard = true; if (!t.gone) ticks[t.chore] = t.by || true; } });
      if (heard || D.edited.chores || D.cleared) {
        D.chores.forEach(function (c) { c.done = !!ticks[c.id]; c.doneBy = typeof ticks[c.id] === 'string' && ticks[c.id] ? ticks[c.id] : undefined; });
      }

      var groceries = {};
      S.groceries.all().forEach(function (g) { groceries[g.id] = g; });
      if (Object.keys(groceries).length || D.cleared) {
        D.groceries = (D.cleared ? [] : D.examples.groceries.filter(function (g) { return !groceries[g.id]; }).map(function (g) { return Object.assign({}, g); }))
          .concat(Object.keys(groceries).map(function (id) { return groceries[id]; }).filter(function (g) { return !g.gone; }));
      }

      D.events = D.events.filter(function (e) { return e.ex || e.cal; }).concat(S.events.all().map(function (e) {
        return Object.assign({}, e, { start: new Date(e.start), end: new Date(e.end) });
      }));
      if (!App.readsCalendars()) {
        D.events = D.events.filter(function (e) { return !e.cal; }).concat(S.calendar.all().map(function (e) {
          return Object.assign({}, e, { cal: true, start: new Date(e.start), end: new Date(e.end) });
        }));
      }

      S.stars.all().forEach(function (s) { D.stars[s.id] = s.stars; D.week[s.id] = s.week; });
      var favs = {};
      S.favs.all().forEach(function (f) { favs[f.id] = true; });
      D.photos.forEach(function (p) { p.fav = !!favs[p.id || p.seed]; });
      if (!App.readsAlbum()) takePhotos();

      D.save();
    } finally { taking = false; }
    // What this copy holds now is in step with the others: nothing of it to put back.
    share(true);
    App.emit('data');
    App.rerender();
  }

  // The album another copy published: each picture shows once its bytes are here.
  function takePhotos() {
    var list = S.photos.all().sort(function (a, b) { return a.order - b.order; });
    if (!list.length) return;
    var byId = {};
    D.photos.forEach(function (p) { if (p.id) byId[p.id] = p; });
    D.photos = list.map(function (m) { return byId[m.id] || { id: m.id, o: m.o, date: m.date, place: '', tag: m.date || m.id }; })
      .filter(function (p) { return p.src; });
    list.forEach(function (m) {
      if (byId[m.id] && byId[m.id].src) return;
      pictures.url(m.id).then(function (url) {
        if (!url) return;
        var p = { id: m.id, o: m.o, date: m.date, place: '', tag: m.date || m.id, src: url };
        D.photos = D.photos.filter(function (x) { return x.id !== m.id; }).concat([p]);
        App.emit('data');
      });
    });
  }

  var again = null;
  function soon() { clearTimeout(again); again = setTimeout(take, 50); }
  Object.keys(S).forEach(function (n) { S[n].onChange(soon); });
  pictures.onChange(soon);
  App.on('data', share);
  App.on('data', function () { if (!taking) publishPhotos(); });
  App.on('ready', take);
})();
