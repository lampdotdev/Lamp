// The first run: a welcome, then the family's own Home HQ in a few steps (who's at home, pets too; where they live;
// their family calendar; an album; a few chores to start), or the example family to look around.
// Finishing takes the examples away for good (DATA.clearExamples) and every other copy of the screen follows
// (js/sync.js), so a family sets it up once, on whichever screen is handiest.
(function () {
  'use strict';
  var D = window.DATA;
  var PETS = ['🐶', '🐱', '🐰', '🐹', '🐦', '🐟'];
  var F = null;   // the setup under way

  function native() { return !!(window.LampNative && LampNative.available); }
  function steps() { return ['welcome', 'family', 'place'].concat(native() ? ['calendars', 'photos'] : []).concat(['chores']); }
  function named() { return F.people.filter(function (p) { return p.name.trim(); }); }
  function humans() { return named().filter(function (p) { return !p.pet; }); }

  function newPerson(pet) {
    var used = F.people.map(function (p) { return p.color; });
    var c = App.colors.filter(function (x) { return used.indexOf(x[0]) < 0; })[0] || App.colors[F.people.length % App.colors.length];
    var p = { id: 'p' + Date.now().toString(36) + F.people.length, name: '', stars: false, pet: !!pet };
    App.paint(p, c);
    if (pet) { p.emoji = PETS[0]; p.stars = true; }
    return p;
  }

  // ------------------------------------------------------------ chores to start with
  // A few for each star earner, the house's own, and each pet's: the family ticks what fits.
  function suggestions() {
    var list = [];
    named().forEach(function (p) {
      if (p.pet) {
        list.push({ key: 'feed:' + p.id, r: 'morning', who: 'any', title: 'Feed ' + p.name, emoji: p.emoji, stars: 1 });
        if (p.emoji === '🐶') list.push({ key: 'walk:' + p.id, r: 'after', who: 'any', title: 'Walk ' + p.name, emoji: '🐕', stars: 2 });
      } else if (p.stars) {
        list.push({ key: 'bed:' + p.id, r: 'morning', who: p.id, title: 'Make bed', emoji: '🛏️', stars: 1 });
        list.push({ key: 'teeth:' + p.id, r: 'morning', who: p.id, title: 'Brush teeth', emoji: '🪥', stars: 1 });
        list.push({ key: 'homework:' + p.id, r: 'after', who: p.id, title: 'Homework', emoji: '📚', stars: 2 });
        list.push({ key: 'tidy:' + p.id, r: 'evening', who: p.id, title: 'Tidy room', emoji: '🧹', stars: 1 });
      }
    });
    list.push({ key: 'dishwasher', r: 'after', who: 'any', title: 'Empty dishwasher', emoji: '🍽️', stars: 2 });
    list.push({ key: 'garbage', r: 'evening', who: 'any', title: 'Take out garbage', emoji: '🗑️', stars: 1 });
    list.push({ key: 'plants', r: 'after', who: 'any', title: 'Water the plants', emoji: '🪴', stars: 1 });
    return list;
  }

  // ------------------------------------------------------------ each step
  function head(title, sub) {
    var i = steps().indexOf(F.step);
    return '<div class="label">Set up · ' + i + ' of ' + (steps().length - 1) + '</div>' +
      '<h2 class="sheet-h serif">' + title + '</h2>' + (sub ? '<p class="sheet-p">' + sub + '</p>' : '');
  }
  function actions(next, opts) {
    opts = opts || {};
    return '<div class="sheet-actions">' +
      '<button class="btn btn--ghost" data-back>Back</button>' +
      (opts.skip ? '<button class="btn btn--ghost" data-next>Skip</button>' : '') +
      '<button class="btn btn--solid" data-next' + (opts.disabled ? ' disabled' : '') + '>' + next + '</button></div>';
  }

  function welcomeHTML() {
    return '<div class="setup-welcome">' +
      '<div class="label">Home HQ</div>' +
      '<h2 class="setup-title serif">Your family’s day, on every screen.</h2>' +
      '<p class="sheet-p">The calendar, chores and stars, the shopping list and your photos, the same on the TV, the kitchen tablet and the Mac.</p>' +
      '<div class="sheet-actions sheet-actions--start">' +
      '<button class="btn btn--solid" data-start>Set up my family</button>' +
      '<button class="btn btn--ghost" data-example>Show me an example</button></div>' +
      (native() ? '' : '<p class="ed-note">Or set it up on your Mac, iPhone or iPad: this screen follows.</p>') +
      '</div>';
  }

  function familyHTML() {
    return head('Who’s at home?', 'Everyone gets a color. Stars are for whoever earns them for chores, pets included.') +
      '<div class="ed-list">' + F.people.map(function (p, i) {
        return '<div class="ed-row" data-i="' + i + '">' +
          '<button class="ed-swatch" data-color aria-label="Color" style="' + App.pstyle(p) + '">' + App.avatar(Object.assign({}, p, { name: p.name || '?' }), 44) + '</button>' +
          '<input class="ed-name" data-name value="' + App.esc(p.name) + '" placeholder="' + (p.pet ? 'Pet’s name' : i ? 'Name' : 'Your name') + '" maxlength="24">' +
          '<button class="chip' + (p.stars ? ' is-on' : '') + '" data-stars>' + App.icon('star', 18, p.stars ? 'i--fill' : '') + 'Stars</button>' +
          (F.people.length > 1 ? '<button class="icon-btn" data-remove aria-label="Remove">' + App.icon('x', 22) + '</button>' : '') +
          '</div>';
      }).join('') + '</div>' +
      (F.people.length < 10 ? '<div class="chips"><button class="btn btn--ghost" data-add>' + App.icon('plus', 22) + 'Someone</button>' +
        '<button class="btn btn--ghost" data-add-pet>' + App.icon('plus', 22) + 'A pet</button></div>' : '') +
      actions('Next', { disabled: !humans().length });
  }

  function placeHTML() {
    var body = F.place ? '<p class="demo-line setup-chosen">' + App.icon('pin', 22) + App.esc(F.place.label || F.place.name) + '</p>' : '';
    body += '<div class="demo-find"><input class="ed-name" data-place-q placeholder="Town or city" value="' + App.esc(F.query || '') + '"><button class="btn" data-place-find>Find</button></div>';
    if (F.places) {
      body += F.places.length ? '<div class="chips setup-results">' + F.places.map(function (p, i) {
        return '<button class="chip' + (F.place && F.place.label === p.label ? ' is-on' : '') + '" data-place="' + i + '">' + App.esc(p.label) + '</button>';
      }).join('') + '</div>' : '<p class="ed-note">Nothing by that name.</p>';
    }
    return head('Where do you live?', 'For the weather on the dashboard.') + body + actions('Next', { skip: !F.place });
  }

  function calendarsHTML() {
    var body;
    if (!F.calendars) body = '<div class="chips"><button class="btn" data-cals>' + App.icon('calendar', 22) + 'Choose our calendar</button></div>';
    else if (!F.calendars.length) body = '<p class="ed-note">No calendars on this device.</p>';
    else body = '<div class="chips setup-results">' + F.calendars.map(function (c) {
      return '<button class="chip' + (F.calendar && F.calendar.id === c.id ? ' is-on' : '') + '" data-cal="' + App.esc(c.id) + '">' + App.esc(App.calendarLabel(F.calendars, c)) + '</button>';
    }).join('') + (F.listed ? '' : '<button class="chip chip--ghost" data-cals>Choose another</button>') + '</div>';
    return head('Your family calendar', 'The one you all share. Its events show for the whole family.') +
      body + actions('Next', { skip: !F.calendar });
  }

  function photosHTML() {
    var body;
    if (!F.albums) body = '<div class="chips"><button class="btn" data-albums>' + App.icon('photo', 22) + 'Choose an album</button></div>';
    else if (!F.albums.length) body = '<p class="ed-note">No albums with pictures in them.</p>';
    else body = '<div class="chips setup-results">' + F.albums.map(function (a) {
      return '<button class="chip' + (F.album === a.id ? ' is-on' : '') + '" data-album="' + App.esc(a.id) + '">' + App.esc(a.title) + '</button>';
    }).join('') + '</div>';
    return head('Your photos', 'An album to show on the dashboard and as a photo frame.') + body + actions('Next', { skip: F.album == null });
  }

  function choresHTML() {
    var list = suggestions();
    return head('A few chores to start', 'Tap the ones that fit. You can change them any time in Settings.') +
      '<div class="chips setup-chores">' + list.map(function (c) {
        var on = !!F.chores[c.key], whose = named().filter(function (p) { return p.id === c.who; })[0];
        var who = whose ? ' · ' + App.esc(whose.name.trim()) : '';
        return '<button class="chip' + (on ? ' is-on' : '') + '" data-chore="' + c.key + '"><span>' + c.emoji + '</span>' + App.esc(c.title) + who + '</button>';
      }).join('') + '</div>' +
      actions('Done');
  }

  var VIEWS = { welcome: welcomeHTML, family: familyHTML, place: placeHTML, calendars: calendarsHTML, photos: photosHTML, chores: choresHTML };
  function html() { return '<div class="sheet-pad ed setup">' + VIEWS[F.step]() + '</div>'; }

  // ------------------------------------------------------------ finishing
  function finish() {
    // Never a family of no one: back to who's at home.
    if (!humans().length) { F.step = 'family'; return false; }
    var people = named().map(function (p) {
      var x = { id: p.id, name: p.name.trim(), color: p.color, rgb: p.rgb, ink: p.ink };
      if (p.pet) { x.pet = true; x.emoji = p.emoji; }
      if (p.stars) x.age = 8;   // what marks a star earner (js/views/editor.js)
      return x;
    });
    var chores = suggestions().filter(function (c) { return F.chores[c.key]; }).map(function (c, i) {
      return { id: 'c' + Date.now().toString(36) + i, r: c.r, who: c.who, title: c.title, emoji: c.emoji, stars: c.stars, done: false };
    });
    D.clearExamples();
    D.people = people;
    D.ALL = D.humanIds();
    D.stars = {}; D.week = {};
    people.forEach(function (p) { if (p.age) { D.stars[p.id] = 0; D.week[p.id] = [0, 0, 0, 0, 0, 0, 0]; } });
    D.chores = chores;
    D.edited.people = true; D.edited.chores = true;
    if (F.place) D.settings.place = { name: F.place.name, lat: F.place.lat, lon: F.place.lon };
    // A calendar chosen from this device's own list is read here from now on. The one already chosen, left as it was,
    // stays with the device that reads it (its id may be that device's alone); deselected, the calendar is off.
    if (F.calendar && (F.listed || F.calendar.id !== F.prefilled)) {
      D.settings.calendars = [F.calendar.id]; D.settings.calendarName = F.calendar.title; D.settings.calendarsBy = App.me();
    } else if (!F.calendar && F.prefilled) {
      D.settings.calendars = null;
    }
    if (F.album != null) { D.settings.album = F.album; D.settings.albumBy = App.me(); }
    D.settings.example = false;
    F = null;
    App.closeSheet();
    App.emit('data');
    App.loadWeather(); App.loadCalendars(); App.loadPhotos();
    App.go('home');
    App.rerender();
    App.toast('Home HQ is yours.', { icon: 'check' });
  }

  // ------------------------------------------------------------ the sheet
  App.setup = function (step) {
    F = {
      step: step || 'welcome', people: [], place: D.settings.place, places: null, query: '',
      calendars: null, calendar: null,
      albums: null, album: D.settings.album, chores: {}
    };
    // The family already made in the editor (the example's people renamed, say) is where the setup starts; otherwise
    // one empty row for the person setting it up. So is a calendar or album already chosen in Settings.
    if (D.edited.people) {
      F.people = D.people.map(function (p) {
        var x = { id: p.id, name: p.name, color: p.color, rgb: p.rgb, ink: p.ink, stars: D.stars[p.id] != null, pet: !!p.pet };
        if (p.pet) x.emoji = p.emoji;
        return x;
      });
    }
    if (!F.people.length) F.people.push(newPerson(false));
    if (D.settings.calendars && D.settings.calendars.length === 1) {
      F.calendar = { id: D.settings.calendars[0], title: D.settings.calendarName || D.settings.calendars[0], source: '' };
      F.calendars = [F.calendar];
      F.prefilled = F.calendar.id;
    }
    var scope = window.Lamp ? Lamp.scope : null;
    App.sheet('<div class="setup-body">' + html() + '</div>', {
      cls: 'sheet--wide',
      // Closed before it's done: the example family stays, until Settings starts it again.
      onClose: function () {
        if (F) { D.settings.example = true; F = null; App.emit('data'); }
        // The remote's arrows back on the screen below, however the setup ended.
        if (window.Lamp) { Lamp.scope = scope; if (Lamp.focusFirst) setTimeout(Lamp.focusFirst, 0); }
      },
      onMount: function (s) {
        function again(focus) {
          s.querySelector('.setup-body').innerHTML = html();
          s.scrollTop = 0;
          var el = focus && s.querySelector(focus);
          if (el) el.focus(); else if (window.Lamp && Lamp.focusFirst) Lamp.focusFirst();
        }
        function go(dir) {
          var list = steps(), i = list.indexOf(F.step) + dir;
          if (i >= list.length) { if (finish() === false) again('[data-name]'); return; }
          F.step = list[Math.max(0, i)];
          again(F.step === 'family' ? '[data-name]' : F.step === 'place' ? '[data-place-q]' : null);
        }
        function findPlace() {
          var q = s.querySelector('[data-place-q]').value.trim();
          if (!q) return;
          F.query = q;
          App.findPlaces(q).then(function (list) { F.places = list; again(); }, function () { F.places = []; again(); });
        }
        if (window.Lamp) Lamp.scope = s;
        s.addEventListener('input', function (e) {
          if (!e.target.hasAttribute('data-name')) return;
          F.people[+e.target.closest('[data-i]').dataset.i].name = e.target.value;
          var next = s.querySelector('.sheet-actions [data-next]:last-child');
          if (next) next.disabled = !humans().length;
        });
        s.addEventListener('keydown', function (e) {
          if (e.keyCode !== 13) return;
          if (e.target.hasAttribute('data-place-q')) { e.preventDefault(); findPlace(); }
          if (e.target.hasAttribute('data-name')) { e.preventDefault(); if (humans().length) go(1); }
        });
        s.addEventListener('click', function (e) {
          // The setup's own: the views below answer some of the same buttons (an "add") page-wide.
          e.stopPropagation();
          var b = e.target.closest('button');
          if (!b || b.disabled || b.hasAttribute('data-close')) return;
          var d = b.dataset, row = b.closest('[data-i]'), p = row && F.people[+row.dataset.i];
          if (b.hasAttribute('data-start')) return go(1);
          if (b.hasAttribute('data-example')) { D.settings.example = true; F = null; App.emit('data'); return App.closeSheet(); }
          if (b.hasAttribute('data-next')) return go(1);
          if (b.hasAttribute('data-back')) return go(-1);
          if (b.hasAttribute('data-add') || b.hasAttribute('data-add-pet')) {
            F.people.push(newPerson(b.hasAttribute('data-add-pet')));
            again(); var inputs = s.querySelectorAll('[data-name]'); inputs[inputs.length - 1].focus();
            return;
          }
          if (b.hasAttribute('data-remove') && p) { F.people.splice(F.people.indexOf(p), 1); return again(); }
          if (b.hasAttribute('data-stars') && p) { p.stars = !p.stars; return again(); }
          if (b.hasAttribute('data-color') && p) {
            if (p.pet) p.emoji = PETS[(PETS.indexOf(p.emoji) + 1) % PETS.length];
            else { var i = App.colors.map(function (c) { return c[0]; }).indexOf(p.color); App.paint(p, App.colors[(i + 1) % App.colors.length]); }
            return again();
          }
          if (b.hasAttribute('data-place-find')) return findPlace();
          if (d.place != null) { F.place = F.places[+d.place]; return again(); }
          if (b.hasAttribute('data-cals')) {
            LampNative.call('calendars', {}).then(function (list) {
              F.calendars = list; F.listed = true;
              // The one called Family, if there's just one.
              var family = list.filter(function (c) { return /family/i.test(c.title); });
              var kept = F.calendar && list.filter(function (c) { return c.id === F.calendar.id; })[0];
              F.calendar = kept || (family.length === 1 ? family[0] : null);
              again();
            }, function () { App.toast('Calendars aren’t allowed. Turn them on in System Settings → Privacy.', { icon: 'calendar' }); });
            return;
          }
          if (d.cal != null) {
            var picked = F.calendars.filter(function (c) { return c.id === d.cal; })[0];
            F.calendar = F.calendar && picked && F.calendar.id === picked.id ? null : picked;
            return again();
          }
          if (b.hasAttribute('data-albums')) {
            LampNative.call('albums', {}).then(function (list) { F.albums = list; again(); },
              function () { App.toast('Photos aren’t allowed. Turn them on in System Settings → Privacy.', { icon: 'photo' }); });
            return;
          }
          if (d.album != null) { F.album = F.album === d.album ? null : d.album; return again(); }
          if (d.chore) { F.chores[d.chore] = !F.chores[d.chore]; return again(); }
        });
      }
    });
  };

  // A screen that isn't set up opens on the welcome, unless it was asked for the example. Set up on another screen
  // meanwhile, the welcome goes: this one follows.
  App.on('ready', function () {
    if (!D.isSetUp() && !D.settings.example) App.setup('welcome');
  });
  // The examples are only a first look: the moment something is the family's own, they go, here and on every copy.
  function examplesGo() {
    if (D.cleared || !D.ownsSomething()) return false;
    D.clearExamples();
    App.loadPhotos();
    App.rerender();
    return true;
  }
  App.on('ready', function () { if (examplesGo()) App.emit('data'); });
  App.on('data', function () {
    if (!F) examplesGo();
    if (F && F.step === 'welcome' && D.isSetUp()) { F = null; App.closeSheet(); }
  });
})();
