// The family's real things, each only once it's chosen in the settings drawer:
// - the weather where they live, from Open-Meteo (open data: no key or account; its license asks for the credit the
//   drawer shows), filling DATA.weather's 24 hours;
// - their own calendars and photos, read by the app around the page on the Mac, iPhone or iPad (Sources/Native.swift).
//   Elsewhere (a TV, Android, the Xbox, Lamp's preview) LampNative.available is false and the examples stay.
(function () {
  'use strict';
  var D = window.DATA;
  var EXAMPLE = JSON.parse(JSON.stringify(D.weather));

  // ------------------------------------------------------------ weather
  App.findPlaces = function (q) {
    return fetch('https://geocoding-api.open-meteo.com/v1/search?count=6&name=' + encodeURIComponent(q))
      .then(function (r) { return r.json(); })
      .then(function (j) {
        return (j.results || []).map(function (p) {
          return { name: p.name, lat: p.latitude, lon: p.longitude, label: [p.name, p.admin1, p.country].filter(Boolean).join(', ') };
        });
      });
  };

  // WMO weather codes to the dashboard's five looks.
  function look(code, day) {
    if (code >= 51) return 'rain';
    if (code >= 3) return 'cloud';
    if (code >= 1) return 'partly';
    return day ? 'sun' : 'moon';
  }

  App.exampleWeather = function () {
    D.weather = JSON.parse(JSON.stringify(EXAMPLE));
    App.emit('time');
    App.rerender();
  };

  App.loadWeather = function () {
    var p = D.settings.place;
    // No place (any more): the example day, not the last place's weather.
    if (!p) { if (!D.weather.example) App.exampleWeather(); return; }
    var url = 'https://api.open-meteo.com/v1/forecast?latitude=' + p.lat + '&longitude=' + p.lon +
      '&hourly=temperature_2m,precipitation_probability,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min' +
      '&timezone=auto&forecast_days=1';
    fetch(url).then(function (r) { return r.json(); }).then(function (j) {
      var h = j.hourly, n = Math.min(24, h.time.length);
      var w = { example: false, t: [], c: [], p: [], hi: Math.round(j.daily.temperature_2m_max[0]), lo: Math.round(j.daily.temperature_2m_min[0]) };
      for (var i = 0; i < n; i++) {
        w.t.push(Math.round(h.temperature_2m[i]));
        w.c.push(look(h.weather_code[i], h.is_day[i]));
        w.p.push(h.precipitation_probability[i] || 0);
      }
      D.weather = w;
      App.emit('time');
      App.rerender();
    }, function () { /* offline: the last weather stays */ });
  };

  // ------------------------------------------------------------ calendars
  // Every event of the family's shared calendar is the family's: who goes is in the title, for the family to read, not
  // for the screen to guess ("June conference" isn't June's).
  // A calendar as the family sees it: its name, and where it's from when another has the same name ("Family · iCloud").
  // The list is what LampNative's "calendars" gives: { id, title, source }.
  App.calendarLabel = function (list, c) {
    var twin = list.filter(function (x) { return x.title === c.title; }).length > 1;
    return c.title + (twin && c.source ? ' · ' + c.source : '');
  };

  // Which copy of the screen reads the family's calendars and album: the one where they were turned on. The others
  // (another Mac, the iPad, the TV) show what it publishes (js/sync.js) and never read their own, so turning them on
  // once never has every device asking for the person's calendars or photos.
  App.me = function () { return window.Lamp && Lamp.wish && Lamp.wish.copy ? (Lamp.wish.copy() || 'here') : 'here'; };
  // Inside the app around the page, which copy this is arrives a moment after the page opens: until then it can't
  // tell whether it's the one that reads the calendar and album. Asked then, `fn` waits for it (once).
  function whenKnown(fn) {
    if (!(window.Lamp && Lamp.wish && Lamp.wish.copy && Lamp.wish.onState) || Lamp.wish.copy()) return false;
    var waiting = true;
    function check() { if (waiting && Lamp.wish.copy()) { waiting = false; fn(); } }
    // It comes with the app's first word on its link, which is said as a state, a list of the wish's apps or both.
    Lamp.wish.onState(check);
    if (Lamp.wish.onApps) Lamp.wish.onApps(check);
    [1000, 3000, 8000].forEach(function (ms) { setTimeout(check, ms); });
    return true;
  }
  function native() { return !!(window.LampNative && LampNative.available); }
  App.readsCalendars = function () { return native() && !!D.settings.calendars && D.settings.calendarsBy === App.me(); };
  App.readsAlbum = function () { return native() && D.settings.album != null && D.settings.albumBy === App.me(); };

  App.loadCalendars = function () {
    var chosen = D.settings.calendars;
    if (chosen && D.settings.calendarsBy && whenKnown(App.loadCalendars)) return;
    if (chosen && !App.readsCalendars()) return;   // another copy reads them
    D.events = D.events.filter(function (e) { return !e.cal; });
    if (!chosen || !native()) { App.emit('data'); return; }
    var asked = JSON.stringify(chosen);
    LampNative.call('events', { calendars: chosen, days: 45 }).then(function (list) {
      // An answer to a question since changed (calendars turned off or others chosen) is dropped.
      if (!App.readsCalendars() || JSON.stringify(D.settings.calendars) !== asked) return;
      D.events = D.events.filter(function (e) { return !e.cal; }).concat(list.map(function (e) {
        return { id: 'k' + e.id, cal: true, title: e.title, start: new Date(e.start), end: new Date(e.end), allDay: !!e.allDay,
                 loc: e.loc || undefined, notes: e.notes || undefined, people: D.ALL.slice() };
      }));
      App.emit('data');
    }, function () {});
  };

  // ------------------------------------------------------------ photos
  var examples = D.photos.slice();
  App.loadPhotos = function () {
    var album = D.settings.album;
    if (album != null && D.settings.albumBy && whenKnown(App.loadPhotos)) return;
    if (album != null && !App.readsAlbum()) return;   // another copy reads it
    if (album == null || !native()) {
      D.photos = D.cleared ? [] : examples.filter(function (p) { return !D.cleared || !p.ex; });
      App.emit('data');
      return;
    }
    LampNative.call('photos', { album: album, limit: 24 }).then(function (list) {
      if (!list.length || !App.readsAlbum() || D.settings.album !== album) return;
      D.photos = list.map(function (p) { return { id: p.id, src: p.src, o: p.o, date: p.date || '', place: '', fav: !!p.fav, tag: p.date || p.id }; });
      App.emit('data');
    }, function () {});
  };

  App.on('ready', function () {
    App.loadWeather();
    App.loadCalendars();
    if (D.settings.album != null) App.loadPhotos();
    setInterval(App.loadWeather, 30 * 60000);
    setInterval(App.loadCalendars, 15 * 60000);
  });
})();
