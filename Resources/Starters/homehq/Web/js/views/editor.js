// The family and the chore list, changed on the screen itself: two sheets opened from Settings. Each change is saved
// as it's made (App.emit('data') → DATA.save) and every view is drawn again with it.
(function () {
  'use strict';
  var D = window.DATA;
  var COLORS = [
    ['#2D5BFF', '45 91 255', '#FFFFFF'], ['#E4007C', '228 0 124', '#FFFFFF'], ['#00A36C', '0 163 108', '#FFFFFF'],
    ['#FFB000', '255 176 0', '#111111'], ['#7A3CFF', '122 60 255', '#FFFFFF'], ['#E5261E', '229 38 30', '#FFFFFF'],
    ['#00A3C4', '0 163 196', '#FFFFFF'], ['#8A5A2B', '138 90 43', '#FFFFFF']
  ];
  var EMOJI = ['🛏️', '🪥', '🎒', '🍽️', '🧺', '🐶', '🪴', '📚', '🎹', '🗑️', '🧽', '🛁', '👕', '♻️', '🧹', '⭐'];

  function changed(what) {
    D.edited[what] = true;
    D.ALL = D.humanIds();
    App.emit('data');
    App.rerender();
  }
  function paint(p, c) { p.color = c[0]; p.rgb = c[1]; p.ink = c[2]; }
  App.colors = COLORS; App.paint = paint;   // for the first-run setup (js/views/setup.js)
  var PETS = ['🐶', '🐱', '🐰', '🐹', '🐦', '🐟'];
  function colorOf(p) { for (var i = 0; i < COLORS.length; i++) if (COLORS[i][0] === p.color) return i; return 0; }

  // ------------------------------------------------------------ family
  function familyHTML() {
    return '<div class="sheet-pad ed">' +
      '<div class="label">Settings</div><h2 class="sheet-h serif">Family</h2>' +
      '<div class="ed-list">' + D.people.map(function (p) {
        var kid = D.stars[p.id] != null;
        return '<div class="ed-row" data-pid="' + p.id + '">' +
          '<button class="ed-swatch" data-color aria-label="Color" style="' + App.pstyle(p) + '">' + App.avatar(p, 44) + '</button>' +
          '<input class="ed-name" data-name value="' + App.esc(p.name) + '" placeholder="Name" maxlength="24">' +
          '<button class="chip' + (kid ? ' is-on' : '') + '" data-kid>' + App.icon('star', 18, kid ? 'i--fill' : '') + 'Stars</button>' +
          '<button class="chip' + (p.pet ? ' is-on' : '') + '" data-pet>' + (p.pet ? p.emoji || '🐾' : '🐾') + 'Pet</button>' +
          (D.people.length > 1 ? '<button class="icon-btn" data-remove aria-label="Remove">' + App.icon('x', 22) + '</button>' : '') +
          '</div>';
      }).join('') + '</div>' +
      (D.people.length < 8 ? '<button class="btn btn--ghost ed-add" data-add>' + App.icon('plus', 22) + 'Add someone</button>' : '') +
      '<p class="ed-note">A color each; Stars for someone who earns them for chores. A pet has no day of its own in the calendar; tap its picture for another.</p>' +
      '</div>';
  }

  App.editFamily = function () {
    App.sheet('<div class="ed-body">' + familyHTML() + '</div>', {
      cls: 'sheet--wide',
      onMount: function (s) {
        function again() { s.querySelector('.ed-body').innerHTML = familyHTML(); }
        function person(el) { var row = el.closest('[data-pid]'); return row && App.person(row.dataset.pid); }
        s.addEventListener('change', function (e) {
          if (!e.target.hasAttribute('data-name')) return;
          var p = person(e.target), name = e.target.value.trim();
          if (p && name) { p.name = name; changed('people'); }
        });
        s.addEventListener('click', function (e) {
          var b = e.target.closest('button');
          if (!b) return;
          if (b.hasAttribute('data-close')) return;
          var p = person(b);
          if (b.hasAttribute('data-color') && p) {
            if (p.pet) p.emoji = PETS[(PETS.indexOf(p.emoji) + 1) % PETS.length];
            else paint(p, COLORS[(colorOf(p) + 1) % COLORS.length]);
            changed('people'); again();
          }
          if (b.hasAttribute('data-pet') && p) {
            if (p.pet) { delete p.pet; delete p.emoji; } else { p.pet = true; p.emoji = PETS[0]; }
            changed('people'); again();
          }
          if (b.hasAttribute('data-kid') && p) {
            if (D.stars[p.id] != null) { delete D.stars[p.id]; delete D.week[p.id]; delete p.age; }
            else { D.stars[p.id] = 0; D.week[p.id] = [0, 0, 0, 0, 0, 0, 0]; p.age = 8; }
            changed('people'); again();
          }
          if (b.hasAttribute('data-remove') && p) {
            D.people = D.people.filter(function (x) { return x !== p; });
            D.chores = D.chores.filter(function (c) { return c.who !== p.id; });
            D.events.forEach(function (ev) {
              ev.people = ev.people.filter(function (id) { return id !== p.id; });
              if (!ev.people.length) ev.people = D.people.map(function (x) { return x.id; });
            });
            delete D.stars[p.id];
            changed('people'); changed('chores'); again();
          }
          if (b.hasAttribute('data-add')) {
            var used = D.people.map(colorOf), free = COLORS.filter(function (c, i) { return used.indexOf(i) < 0; })[0] || COLORS[0];
            var np = { id: 'p' + Date.now().toString(36), name: 'New' };
            paint(np, free);
            D.people.push(np);
            changed('people'); again();
            var inputs = s.querySelectorAll('[data-name]'), last = inputs[inputs.length - 1];
            if (last) { last.focus(); last.select(); }
          }
        });
      }
    });
  };

  // ------------------------------------------------------------ chores
  var R = { routine: null };
  function choresHTML() {
    var r = R.routine || App.currentRoutine().id;
    var list = D.chores.filter(function (c) { return c.r === r; });
    var who = D.people.map(function (p) { return [p.id, p.name]; }).concat([['any', 'Anyone']]);
    return '<div class="sheet-pad ed">' +
      '<div class="label">Settings</div><h2 class="sheet-h serif">Chores</h2>' +
      '<div class="seg">' + D.routines.map(function (x) { return '<button class="' + (x.id === r ? 'is-on' : '') + '" data-r="' + x.id + '">' + x.name + '</button>'; }).join('') + '</div>' +
      '<div class="ed-list">' + (list.length ? list.map(function (c) {
        return '<div class="ed-row" data-cid="' + c.id + '">' +
          '<button class="ed-emoji" data-emoji aria-label="Picture">' + c.emoji + '</button>' +
          '<input class="ed-name" data-title value="' + App.esc(c.title) + '" placeholder="Chore" maxlength="40">' +
          '<select class="ed-select" data-who aria-label="Whose">' + who.map(function (w) {
            return '<option value="' + w[0] + '"' + (w[0] === c.who ? ' selected' : '') + '>' + App.esc(w[1]) + '</option>';
          }).join('') + '</select>' +
          '<select class="ed-select ed-stars" data-stars aria-label="Stars">' + [0, 1, 2, 3].map(function (n) {
            return '<option value="' + n + '"' + (n === (c.stars || 0) ? ' selected' : '') + '>' + (n ? n + ' ★' : 'No ★') + '</option>';
          }).join('') + '</select>' +
          '<button class="icon-btn" data-remove aria-label="Remove">' + App.icon('x', 22) + '</button>' +
          '</div>';
      }).join('') : '<p class="ed-note">Nothing in the ' + App.esc(D.routines.filter(function (x) { return x.id === r; })[0].name.toLowerCase()) + ' yet.</p>') + '</div>' +
      '<button class="btn btn--ghost ed-add" data-add>' + App.icon('plus', 22) + 'Add a chore</button>' +
      '</div>';
  }

  App.editChores = function () {
    R.routine = null;
    App.sheet('<div class="ed-body">' + choresHTML() + '</div>', {
      cls: 'sheet--wide',
      onMount: function (s) {
        function again() { s.querySelector('.ed-body').innerHTML = choresHTML(); }
        function chore(el) {
          var row = el.closest('[data-cid]');
          return row && D.chores.filter(function (c) { return c.id === row.dataset.cid; })[0];
        }
        s.addEventListener('change', function (e) {
          var c = chore(e.target);
          if (!c) return;
          if (e.target.hasAttribute('data-title') && e.target.value.trim()) c.title = e.target.value.trim();
          if (e.target.hasAttribute('data-who')) c.who = e.target.value;
          if (e.target.hasAttribute('data-stars')) c.stars = +e.target.value;
          changed('chores');
        });
        s.addEventListener('click', function (e) {
          var b = e.target.closest('button');
          if (!b || b.hasAttribute('data-close')) return;
          if (b.dataset.r) { R.routine = b.dataset.r; return again(); }
          var c = chore(b);
          if (b.hasAttribute('data-emoji') && c) { c.emoji = EMOJI[(EMOJI.indexOf(c.emoji) + 1) % EMOJI.length]; changed('chores'); return again(); }
          if (b.hasAttribute('data-remove') && c) { D.chores = D.chores.filter(function (x) { return x !== c; }); changed('chores'); return again(); }
          if (b.hasAttribute('data-add')) {
            D.chores.push({ id: 'c' + Date.now().toString(36), r: R.routine || App.currentRoutine().id, who: 'any', title: 'New chore', emoji: '⭐', stars: 1, done: false });
            changed('chores'); again();
            var inputs = s.querySelectorAll('[data-title]'), last = inputs[inputs.length - 1];
            if (last) { last.focus(); last.select(); }
          }
        });
      }
    });
  };
})();
