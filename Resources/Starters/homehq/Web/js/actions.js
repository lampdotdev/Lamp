// What Home HQ can be asked to do, in words (js/agent.js, through LampAI.act): reads that change nothing, and writes
// that change the family's data the way the screen's own buttons do, each checked against the data as it is right
// then. A write looks its item up again by id (sync rebuilds the lists whenever another copy changes them), makes the
// ids of what it adds from the call's key (so the same request made again finds what it added instead of adding a
// second), and gives back the item as it is after the change, which is what the reply is built from.
//
// The chore and grocery rules here are the ones the Chores and Shopping views use (App.chore, App.categorize).
(function () {
  'use strict';
  var D = window.DATA;

  function changed() { App.emit('data'); App.rerender(); }
  function sameName(a, b) { return String(a).trim().toLowerCase() === String(b).trim().toLowerCase(); }
  function nice(name) { name = String(name).trim(); return name.charAt(0).toUpperCase() + name.slice(1); }
  function person(id) { return D.people.filter(function (p) { return p.id === id; })[0] || null; }
  function day(d) { return d.getFullYear() + '-' + ('0' + (d.getMonth() + 1)).slice(-2) + '-' + ('0' + d.getDate()).slice(-2); }
  function parseDay(text) { var p = String(text).split('-'); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function names(ids) { return ids.map(function (id) { return (person(id) || { name: id }).name; }); }
  function routineOf(id) { return D.routines.filter(function (r) { return r.id === id; })[0]; }

  // ------------------------------------------------------------ shared with the views
  // Which aisle a grocery goes in, by the catalog; Other when it doesn't know (Shopping then asks the AI).
  App.categorize = function (name) {
    var n = name.toLowerCase();
    var hit = D.catalog.filter(function (c) { return c[0].toLowerCase() === n; })[0] ||
      D.catalog.filter(function (c) { var a = c[0].toLowerCase(); return a.indexOf(n) > -1 || n.indexOf(a) > -1; })[0] ||
      D.catalog.filter(function (c) { return n.split(/\s+/).some(function (w) { return w.length > 3 && c[0].toLowerCase().indexOf(w) > -1; }); })[0];
    return hit ? hit[1] : 'Other';
  };
  // A chore ticked off and taken back: the stars go to the kid it's for, or for an Anyone chore to the kid who did it.
  App.chore = {
    earner: function (c, by) { return D.stars[c.who] != null ? c.who : (by && D.stars[by] != null ? by : null); },
    complete: function (c, by) {
      c.done = true;
      if (by) c.doneBy = by;
      var earner = App.chore.earner(c, by);
      if (earner && c.stars) D.stars[earner] += c.stars;
      return earner;
    },
    undo: function (c) {
      var earner = App.chore.earner(c, c.doneBy);
      if (earner && c.stars) D.stars[earner] -= c.stars;
      c.done = false;
      delete c.doneBy;
      return earner;
    }
  };

  // ------------------------------------------------------------ what the agent sees
  function grocery(g) { return { id: g.id, name: g.name, aisle: g.cat, qty: g.qty, store: g.store, done: !!g.done, note: g.note || '' }; }
  function chore(c) {
    var r = routineOf(c.r);
    return { id: c.id, title: c.title, part: r ? r.name : c.r, who: c.who === 'any' ? 'anyone' : c.who, stars: c.stars || 0,
             done: !!c.done, by: c.doneBy || '' };
  }
  function event(e) {
    return { id: e.id, title: e.title, start: LampAI.whenText(e.start), end: LampAI.whenText(e.end), allDay: !!e.allDay,
             who: names(e.people), place: e.loc || '', notes: e.notes || '',
             // The family's shared calendar is read here, never changed: that's changed where it lives.
             onHomeHQ: !e.cal };
  }

  App.read = {
    today: function () {
      var now = App.now(), r = App.currentRoutine(), w = App.weatherNow(), next = App.nextEvent();
      return {
        now: LampAI.whenText(now), partOfDay: r.name, weather: w.summary + '. ' + w.advice + '.',
        next: next ? { title: next.title, start: LampAI.whenText(next.start), who: names(next.people), leaveBy: LampAI.whenText(App.leaveBy(next)) } : null,
        today: App.events().filter(function (e) { return e.start < App.addDays(App.dayStart(now), 1) && e.end > App.dayStart(now); })
          .sort(function (a, b) { return a.start - b.start; }).map(event),
        chores: D.chores.filter(function (c) { return c.r === r.id; }).map(chore),
        shopping: D.groceries.filter(function (g) { return !g.done; }).length + ' things on the list'
      };
    },
    people: function () {
      return D.people.map(function (p) {
        return { id: p.id, name: p.name, kind: p.pet ? 'pet' : D.stars[p.id] != null ? 'kid who earns stars' : 'grown-up',
                 stars: D.stars[p.id] != null ? D.stars[p.id] : null };
      });
    },
    events: function (a) {
      var from = a.from ? parseDay(a.from) : App.dayStart(App.now());
      var to = a.to ? App.addDays(parseDay(a.to), 1) : App.addDays(from, 1);
      return App.events().filter(function (e) {
        return e.start < to && e.end > from && (!a.who || e.people.indexOf(a.who) > -1);
      }).sort(function (x, y) { return x.start - y.start; }).slice(0, 40).map(event);
    },
    chores: function (a) {
      var part = a.part && a.part !== 'all' ? a.part : null;
      return D.chores.filter(function (c) {
        return (!part || c.r === part) && (!a.who || c.who === a.who || (a.who === 'anyone' && c.who === 'any'));
      }).map(chore);
    },
    groceries: function (a) {
      return D.groceries.filter(function (g) { return a.all || !g.done; }).map(grocery);
    }
  };

  // ------------------------------------------------------------ what the agent can change
  // Each write is { check(args, call) → null or why not, run(args, call) → what's there now }. What each change was
  // is kept for the turn's Undo (`App.changesOf`), which is only done while the item is still as the change left it.
  // Rows of this name, open or bought, at `store` (any store when null).
  function sameItems(name, store, bought) {
    return D.groceries.filter(function (g) {
      return !g.gone && !!g.done === bought && sameName(g.name, name) && (!store || g.store === store);
    });
  }
  function stores(rows) { var seen = {}; return rows.map(function (g) { return g.store; }).filter(function (s) { return !seen[s] && (seen[s] = true); }); }
  function storeName(id) { var s = D.stores.filter(function (x) { return x.id === id; })[0]; return s ? s.name : id; }
  function groceryById(id) { return D.groceries.filter(function (g) { return g.id === id && !g.gone; })[0] || null; }
  function choreById(id) { return D.chores.filter(function (c) { return c.id === id; })[0] || null; }
  function eventById(id) { return D.events.filter(function (e) { return e.id === id; })[0] || null; }
  // An item as text with its keys in order, since sync may rebuild it with them in another order.
  function snap(x) {
    if (x === null || x === undefined) return 'null';
    if (x instanceof Date) return JSON.stringify(+x);
    if (Object.prototype.toString.call(x) === '[object Array]') return '[' + x.map(snap).join(',') + ']';
    if (typeof x === 'object') return '{' + Object.keys(x).sort().filter(function (k) { return x[k] !== undefined; }).map(function (k) { return JSON.stringify(k) + ':' + snap(x[k]); }).join(',') + '}';
    return JSON.stringify(x);
  }
  // What of an item a change is about, to tell whether it's still as the change left it: not its aisle (the AI may file
  // it a moment later) or anything sync fills in on its own.
  function pick(o, keys) { var r = {}; keys.forEach(function (k) { if (o && o[k] !== undefined) r[k] = o[k]; }); return r; }
  var FIELDS = { grocery: ['name', 'qty', 'done', 'store', 'note'], chore: ['done', 'doneBy'], event: ['title', 'start', 'end', 'people'] };
  function state(kind, x) { return x ? snap(pick(x, FIELDS[kind])) : 'null'; }

  // What each turn changed, for its Undo: kept here rather than in what the model is told.
  var undos = {};
  function keep(call, u) { if (u) (undos[call.turn] = undos[call.turn] || []).push(u); }
  App.changesOf = function (turn) { return undos[turn] || []; }

  App.write = {
    addGrocery: {
      // An item of the same name, open or bought, at the store asked for. With no store asked for, one at either; two
      // stores' rows of the same name are a question, never a guess.
      check: function (a) {
        if (!String(a.name).trim()) return 'It needs a name.';
        if (String(a.name).length > 60) return 'That name is too long for the list.';
        if (!a.store) {
          var open = sameItems(a.name, null, false);
          var rows = open.length ? open : sameItems(a.name, null, true);
          if (stores(rows).length > 1) {
            return (rows[0].name) + ' is on the list for ' + stores(rows).map(storeName).join(' and ') + ': ask which store.';
          }
        }
        return null;
      },
      run: function (a, call) {
        var id = 'v' + call.key, qty = a.qty || 1;
        // Asked again (the same turn tried again, or a copy that already has it): what it added is there.
        var mine = groceryById(id);
        if (mine) return { already: true, item: grocery(mine) };
        var open = sameItems(a.name, a.store, false)[0];
        if (open) {
          var before = state('grocery', open);
          if (a.qty) open.qty += qty;
          changed();
          if (a.qty) keep(call, { kind: 'grocery', id: open.id, before: before, after: state('grocery', open) });
          return { already: true, item: grocery(open) };
        }
        var bought = sameItems(a.name, a.store, true)[0];
        if (bought) {
          var was = state('grocery', bought);
          bought.done = false; bought.qty = qty;
          changed();
          keep(call, { kind: 'grocery', id: bought.id, before: was, after: state('grocery', bought) });
          return { addedBack: true, item: grocery(bought) };
        }
        var known = D.catalog.filter(function (c) { return sameName(c[0], a.name); })[0];
        var g = { id: id, name: known ? known[0] : nice(a.name), cat: App.categorize(a.name), qty: qty,
                  store: a.store === 'costco' ? 'costco' : 'grocer', done: false, note: a.note || '' };
        D.groceries.push(g);
        changed();
        keep(call, { kind: 'grocery', id: g.id, before: null, after: state('grocery', g) });
        if (App.aisleByAI) App.aisleByAI(g);
        return { added: true, item: grocery(g) };
      }
    },
    checkGrocery: {
      check: function (a) {
        var g = groceryById(a.id);
        if (!g) return 'That item isn\'t on the list any more.';
        if (g.done) return g.name + ' is already ticked off.';
        return null;
      },
      run: function (a, call) {
        var g = groceryById(a.id), before = state('grocery', g);
        g.done = true;
        changed();
        keep(call, { kind: 'grocery', id: g.id, before: before, after: state('grocery', g) });
        return { item: grocery(g) };
      }
    },
    completeChore: {
      check: function (a) {
        var c = choreById(a.id);
        if (!c) return 'There\'s no such chore any more.';
        if (c.done) return c.title + ' is already done today' + (c.doneBy ? ', by ' + (person(c.doneBy) || { name: c.doneBy }).name : '') + '.';
        if (a.by) {
          var p = person(a.by);
          if (!p) return 'There\'s nobody in the family with the id ' + a.by + '.';
          if (p.pet) return p.name + ' is a pet and can\'t do chores.';
        }
        if (c.who === 'any' && c.stars && !a.by) return 'Ask who did it: this one earns stars for whoever did it.';
        return null;
      },
      run: function (a, call) {
        var c = choreById(a.id), before = state('chore', c), stars = snap(D.stars);
        var earner = App.chore.complete(c, a.by);
        changed();
        keep(call, { kind: 'chore', id: c.id, before: before, after: state('chore', c), stars: stars, afterStars: snap(D.stars) });
        return { item: chore(c), stars: earner && c.stars ? { who: earner, now: D.stars[earner] } : null };
      }
    },
    uncompleteChore: {
      check: function (a) {
        var c = choreById(a.id);
        if (!c) return 'There\'s no such chore any more.';
        if (!c.done) return c.title + ' isn\'t done yet today.';
        return null;
      },
      run: function (a, call) {
        var c = choreById(a.id), before = state('chore', c), stars = snap(D.stars);
        App.chore.undo(c);
        changed();
        keep(call, { kind: 'chore', id: c.id, before: before, after: state('chore', c), stars: stars, afterStars: snap(D.stars) });
        return { item: chore(c) };
      }
    },
    addEvent: {
      check: function (a) {
        if (!String(a.title).trim()) return 'It needs a title.';
        var start = LampAI.date(a.start), now = App.now();
        if (!start) return 'That start isn\'t a date and time.';
        if (start < new Date(+now - 5 * 60000)) return 'That time has already passed.';
        if (start > App.addDays(now, 366)) return 'That\'s more than a year away.';
        var minutes = a.minutes == null ? 60 : a.minutes;
        if (minutes < 5 || minutes > 1440) return 'An event lasts from 5 minutes to a day.';
        var who = a.who || [];
        for (var i = 0; i < who.length; i++) {
          var p = person(who[i]);
          if (!p) return 'There\'s nobody in the family with the id ' + who[i] + '.';
          if (p.pet) return p.name + ' is a pet; put the event on whoever takes them.';
        }
        return null;
      },
      run: function (a, call) {
        var id = 'v' + call.key, mine = eventById(id);
        if (mine) return { already: true, item: event(mine) };
        var start = LampAI.date(a.start), minutes = a.minutes == null ? 60 : a.minutes;
        // On Home HQ's own calendar, as New event makes them: never the family's Apple or Google calendar.
        var e = { id: id, title: String(a.title).trim(), people: a.who && a.who.length ? a.who.slice() : D.ALL.slice(),
                  start: start, end: new Date(+start + minutes * 60000), loc: a.place || '', notes: '' };
        D.events.push(e);
        changed();
        keep(call, { kind: 'event', id: e.id, before: null, after: state('event', e) });
        return { added: true, item: event(e) };
      }
    }
  };

  // Takes back one change, only while its item is still as the change left it. Says what it did, or why it didn't.
  App.undoChange = function (u) {
    if (u.kind === 'grocery') {
      var g = D.groceries.filter(function (x) { return x.id === u.id; })[0];
      if (!g || state('grocery', g) !== u.after) return { ok: false, what: g ? g.name : 'an item', why: 'changed since' };
      if (u.before === null) D.groceries.splice(D.groceries.indexOf(g), 1);
      else { var b = JSON.parse(u.before); for (var k in b) g[k] = b[k]; }
      return { ok: true, what: g.name };
    }
    if (u.kind === 'chore') {
      var c = choreById(u.id);
      if (!c || state('chore', c) !== u.after || snap(D.stars) !== u.afterStars) return { ok: false, what: c ? c.title : 'a chore', why: 'changed since' };
      var was = JSON.parse(u.before);
      c.done = was.done; if (was.doneBy) c.doneBy = was.doneBy; else delete c.doneBy;
      var stars = JSON.parse(u.stars);
      for (var s in stars) D.stars[s] = stars[s];
      return { ok: true, what: c.title };
    }
    if (u.kind === 'event') {
      var e = eventById(u.id);
      if (!e || state('event', e) !== u.after) return { ok: false, what: e ? e.title : 'an event', why: 'changed since' };
      D.events.splice(D.events.indexOf(e), 1);
      return { ok: true, what: e.title };
    }
    return { ok: false, what: 'that', why: 'unknown' };
  };

  App.dayText = day;
})();
