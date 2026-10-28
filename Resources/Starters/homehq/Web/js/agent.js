// Ask Home HQ: say or type what you want ("Add milk", "Mark the dishes done", "What do we need before school?") and it
// does it with the family's own data through LampAI.act, using the reads and writes in js/actions.js. Every copy of the
// screen shows the change through sync; the copy that heard you says what happened, built from what actually ran
// (never from the AI's own words), and offers Undo for what's still as the turn left it.
//
// The Ask button shows only where it works: LampAI.isAvailable('act') (this page, the app around it and the AI set up in
// Lamp can all take it). Speaking and listening are the app's own (Sources/Native.swift: voice, listen, stop, speak),
// on the Mac, iPhone and iPad; elsewhere it's typed.
(function () {
  'use strict';
  var D = window.DATA;
  // `session` counts each time Ask opens, closes or the page hides: what started under one session (a follow-up listen,
  // what was heard, an answer) does nothing once it has changed. `pending` is a question back in progress: the request
  // it came from, every question and answer of the chain so far, what's asked now and what was already done, so the
  // answer is read against all of them.
  var S = { turn: null, voice: null, listening: false, pending: null, last: null, el: null, session: 0, followUp: null };

  var ABOUT = 'Home HQ is a family dashboard on the kitchen wall: the family, today and the calendar, the chores for ' +
    'each part of the day, and the shopping list. You act for whoever is talking to it.\n' +
    '- People: use ids from people(). "The kids" are the ones who earn stars; "everyone" is all the humans. "I" or ' +
    '"me" is unknown (a screen isn\'t a person): ask who. A name that isn\'t in the family: ask.\n' +
    '- Dates: "Friday" is the next Friday, today only if it\'s still ahead. "Tonight" is after 5 PM today. A time ' +
    'with no AM or PM is read as a family means it (7 to 11 morning, 1 to 6 afternoon); otherwise ask. An event with ' +
    'no time: ask "What time?". Never put something in the past.\n' +
    '- Two chores or items that both fit (Dishes in the morning and the evening): ask which, saying the difference.\n' +
    '- An Anyone chore that earns stars needs who did it: ask.\n' +
    '- New events go on Home HQ\'s own calendar. Events with onHomeHQ false are on the family\'s shared calendar and ' +
    'can\'t be changed here: say to change them there. Nothing can be deleted here.';

  var tools = {
    today: { about: 'The time, the part of the day, the weather, what\'s next, today\'s events and this part of the day\'s chores.',
             reads: true, args: {}, run: function () { return App.read.today(); } },
    people: { about: 'The family: ids, names, who earns stars, pets.', reads: true, args: {}, run: function () { return App.read.people(); } },
    events: { about: 'Events from one day to another (both included; today when left out), for one person or everyone.', reads: true,
              args: { from: { type: 'date', optional: true }, to: { type: 'date', optional: true }, who: { type: 'string', optional: true, about: 'A person\'s id.' } },
              run: function (a) { return App.read.events(a); } },
    chores: { about: 'Chores with whether each is done today. part: morning, after (after school), evening or all.', reads: true,
              args: { part: { type: 'string', oneOf: ['morning', 'after', 'evening', 'all'], optional: true },
                      who: { type: 'string', optional: true, about: 'A person\'s id, or anyone.' } },
              run: function (a) { return App.read.chores(a); } },
    groceries: { about: 'The shopping list: what\'s still to buy, or everything with all.', reads: true,
                 args: { all: { type: 'boolean', optional: true } }, run: function (a) { return App.read.groceries(a); } },
    addGrocery: { about: 'Put something on the shopping list. Already on it: qty adds to it. Bought: it goes back on.',
                  args: { name: { type: 'string' }, qty: { type: 'integer', min: 1, max: 99, optional: true },
                          store: { type: 'string', oneOf: ['grocer', 'costco'], optional: true }, note: { type: 'string', optional: true } } },
    checkGrocery: { about: 'Tick an item off the shopping list (bought).', args: { id: { type: 'string' } } },
    completeChore: { about: 'Mark a chore done today. by: who did it (a person\'s id), needed for an Anyone chore that earns stars.',
                     args: { id: { type: 'string' }, by: { type: 'string', optional: true } } },
    uncompleteChore: { about: 'Take back a chore marked done today.', args: { id: { type: 'string' } } },
    addEvent: { about: 'Add an event to Home HQ\'s calendar.',
                args: { title: { type: 'string' }, start: { type: 'datetime' }, minutes: { type: 'integer', min: 5, max: 1440, optional: true },
                        who: { type: 'list', of: { type: 'string' }, max: 12, optional: true, about: 'People\'s ids; everyone when left out.' },
                        place: { type: 'string', optional: true } } }
  };
  Object.keys(App.write).forEach(function (name) { tools[name].check = App.write[name].check; tools[name].run = App.write[name].run; });

  // ------------------------------------------------------------ what happened, in words
  var DOING = { today: 'Looking at today', people: 'Looking at the family', events: 'Looking at the calendar', chores: 'Looking at the chores',
                groceries: 'Looking at the list', addGrocery: 'Adding', checkGrocery: 'Ticking off', completeChore: 'Marking done',
                uncompleteChore: 'Taking back', addEvent: 'Adding to the calendar' };
  function itemName(d) { var r = d.result || {}; return (r.item && (r.item.name || r.item.title)) || d.args.name || d.args.title || 'it'; }
  function said(d) {
    var r = d.result || {}, name = itemName(d);
    switch (d.name) {
      case 'addGrocery': return r.already ? (d.args.qty ? name + ' was on the list already, now ×' + r.item.qty : name + ' is already on the list') : r.addedBack ? 'Put ' + name + ' back on the list' : 'Added ' + name;
      case 'checkGrocery': return 'Ticked off ' + name;
      case 'completeChore': return 'Marked ' + name + ' done' + (r.stars ? ': ' + (App.person(r.stars.who).name) + ' has ' + r.stars.now + ' stars' : '');
      case 'uncompleteChore': return 'Took back ' + name;
      case 'addEvent': return r.already ? name + ' is already on Home HQ\'s calendar' : 'Added ' + name + ' to Home HQ\'s calendar, ' + LampAI.whenText(LampAI.date(d.args.start)).replace(/ \(.*\)$/, '');
    }
    return 'Did ' + d.name;
  }
  function receipt(r) {
    var lines = r.done.map(said);
    r.failed.forEach(function (f) { lines.push('Couldn\'t ' + (DOING[f.name] || f.name).toLowerCase() + ' ' + (f.args.name || f.args.title || '') + ': ' + f.reason.replace(/\.$/, '')); });
    r.skipped.forEach(function (s) { lines.push('Didn\'t get to ' + (s.args.name || s.args.title || s.name)); });
    return lines.map(function (l) { return l.replace(/\s+:/, ':') + '.'; }).join(' ');
  }
  // What's said: what ran, then the AI's own words only when it asks something or nothing was changed.
  function words(r) {
    if (r.stopped === 'cancelled') return '';
    var text = receipt(r);
    if (r.reply && (r.ask || (!r.done.length && !r.failed.length))) text = (text ? text + ' ' : '') + r.reply;
    if (r.stopped === 'time') text += (text ? ' ' : '') + 'That took too long, so I stopped there.';
    else if (r.stopped === 'steps') text += (text ? ' ' : '') + 'I stopped there.';
    else if (r.stopped === 'unreachable' || r.stopped === 'error') text += (text ? ' ' : '') + (r.error || 'Something went wrong.');
    return text || 'Done.';
  }

  // ------------------------------------------------------------ voice (the app's own, where there is one)
  function native() { return !!(window.LampNative && LampNative.available); }
  // Resolves true once the words have been said to the end; false when there's no voice, or they were cut off.
  function speak(text) {
    if (!(S.voice && S.voice.speak && text)) return Promise.resolve(false);
    return LampNative.call('speak', { text: text }).then(function (done) { return done === true; }, function () { return false; });
  }
  function live(session) { return session === S.session && !!S.el && !document.hidden; }
  // Ends this session: nothing it started (a follow-up listen, a turn, what was being heard) carries on.
  function end() {
    S.session++;
    clearTimeout(S.followUp);
    S.followUp = null;
    if (S.turn) { S.turn.cancel(); S.turn = null; busy(false); }
    if (S.listening) { S.listening = false; LampNative.call('stop', { cancel: true }).then(null, function () {}); }
    hush();
  }
  function hush() { if (S.voice && S.voice.speak) LampNative.call('stop', { cancel: true }).then(null, function () {}); }

  // ------------------------------------------------------------ the sheet
  function line(cls, html) {
    if (!S.el) return;
    var log = S.el.querySelector('.ask-log'), d = document.createElement('div');
    d.className = 'ask-line ' + cls;
    d.innerHTML = html;
    log.appendChild(d);
    log.scrollTop = log.scrollHeight;
    return d;
  }
  function busy(on) {
    if (!S.el) return;
    S.el.classList.toggle('is-busy', on);
    S.el.querySelector('[data-ask-send]').disabled = on;
  }

  function ask(text) {
    text = String(text || '').trim();
    if (!text || S.turn || !S.el) return;
    hush();
    clearTimeout(S.followUp);
    // An answer to a question back goes with the request it came from, so "Maya" after "Who did it?" still means the
    // dishes, and what that request already did isn't done again.
    // Every question and answer of the chain goes, in order: "Evening" still counts once "Maya" answers the next one.
    var pending = S.pending, request = text, history = [], answered = [];
    if (pending) {
      answered = pending.answered.concat([{ question: pending.question, answer: text }]).slice(-6);
      request = pending.request + '\n\n' + answered.map(function (x) {
        return 'You asked: "' + x.question + '" The person answered: "' + x.answer + '".';
      }).join('\n') + (pending.done ? '\nAlready done for this request: ' + pending.done : '');
      history = answered.slice(-3).map(function (x) { return { said: x.question, heard: x.answer }; });
    }
    var session = S.session;
    line('ask-you', App.esc(text));
    var doing = line('ask-doing', 'Thinking…');
    busy(true);
    var undoBox = S.el && S.el.querySelector('[data-ask-undo]');
    if (undoBox) undoBox.hidden = true;
    S.turn = LampAI.act(request, {
      about: ABOUT, tools: tools, history: history,
      context: { people: App.read.people(), today: App.dayText(App.now()) },
      onStep: function (s) { if (doing && !s.result) doing.textContent = (DOING[s.name] || s.name) + (s.args.name || s.args.title ? ' ' + (s.args.name || s.args.title) : '') + '…'; }
    });
    var id = S.turn.id;
    S.turn.result.then(function (r) {
      // Cancelled by a close or the page hiding: only its "Thinking…" line goes.
      if (!S.turn || S.turn.id !== id || session !== S.session) { if (doing && doing.parentNode) doing.parentNode.removeChild(doing); return; }
      S.turn = null;
      busy(false);
      if (doing && doing.parentNode) doing.parentNode.removeChild(doing);
      var spoken = words(r);
      if (r.stopped !== 'cancelled') line('ask-them' + (r.failed.length || r.stopped ? ' is-partly' : ''), App.esc(spoken));
      var did = receipt(r);
      S.pending = r.ask ? { request: pending ? pending.request : text, answered: answered, question: r.reply,
                            done: [pending && pending.done, did].filter(function (x) { return x; }).join(' ') } : null;
      S.last = r.turn;
      if (App.changesOf(r.turn).length && S.el) S.el.querySelector('[data-ask-undo]').hidden = false;
      // A question back: listen for the answer once it has been said to the end, while Ask is still open.
      speak(spoken).then(function (said) {
        if (!said || !r.ask || !S.voice || !S.voice.listen || !live(session)) return;
        S.followUp = setTimeout(function () { if (live(session)) listen(); }, 300);
      });
    });
  }

  function undo() {
    var changes = App.changesOf(S.last).slice().reverse();
    if (!changes.length) return;
    var back = [], kept = [];
    changes.forEach(function (u) { var r = App.undoChange(u); (r.ok ? back : kept).push(r.what); });
    App.changesOf(S.last).length = 0;
    App.emit('data');
    App.rerender();
    var text = (back.length ? 'Undid ' + back.join(', ') + '.' : '') + (kept.length ? ' Left ' + kept.join(', ') + ': changed since.' : '');
    line('ask-them', App.esc(text.trim()));
    speak(text.trim());
    S.el.querySelector('[data-ask-undo]').hidden = true;
  }

  function listen() {
    if (!S.voice || !S.voice.listen || S.listening || S.turn || !S.el || document.hidden) return;
    var session = S.session;
    hush();
    S.listening = true;
    if (S.el) S.el.classList.add('is-listening');
    var words = D.people.map(function (p) { return p.name; }).concat(D.chores.map(function (c) { return c.title; }));
    LampNative.call('listen', { words: words.slice(0, 80) }).then(function (heard) {
      // Heard after Ask closed or the page hid: dropped, never a new turn.
      if (session !== S.session) return;
      S.listening = false;
      if (S.el) S.el.classList.remove('is-listening');
      if (!live(session) || !heard || heard.ended === 'cancelled' || heard.ended === 'interrupted' || !heard.text) return;
      ask(heard.text);
    }, function () {
      if (session !== S.session) return;
      S.listening = false;
      if (S.el) S.el.classList.remove('is-listening');
    });
  }

  function open() {
    App.sheet('<div class="sheet-pad ask"><div class="label">Ask Home HQ</div>' +
      '<div class="ask-log" aria-live="polite"></div>' +
      '<form class="ask-row" data-ask-form>' +
      (S.voice && S.voice.listen ? '<button type="button" class="btn ask-mic" data-ask-mic aria-label="Talk">' + App.icon('mic', 26) + '</button>' : '') +
      '<input class="ask-input" data-ask-input placeholder="Add milk · Mark the dishes done · What\'s on after school?" autocomplete="off">' +
      '<button class="btn btn--solid" data-ask-send>Ask</button></form>' +
      '<button class="btn btn--ghost ask-undo" data-ask-undo hidden>' + App.icon('undo', 22) + 'Undo</button>' +
      (S.voice && S.voice.permission === 'denied' ? '<p class="sheet-p">To talk to Home HQ, turn on the microphone and speech recognition for it in System Settings.</p>' : '') +
      '</div>', {
      cls: 'sheet--wide',
      onClose: function () {
        // Closing ends the session: an answer, what's heard or a follow-up listen that comes after does nothing.
        end();
        S.pending = null;
        clearInterval(S.awake);
        S.el = null;
      },
      onMount: function (sheet) {
        S.session++;
        S.pending = null;
        S.el = sheet;
        // Talking isn't touching: while Ask is open the screen stays as it is, not off to the photo frame or the night
        // clock (which would close the sheet and cancel the turn).
        App.resetIdle();
        clearInterval(S.awake);
        S.awake = setInterval(App.resetIdle, 1000);
        var input = sheet.querySelector('[data-ask-input]');
        sheet.querySelector('[data-ask-form]').addEventListener('submit', function (e) { e.preventDefault(); var t = input.value; input.value = ''; ask(t); });
        sheet.querySelector('[data-ask-undo]').addEventListener('click', undo);
        var mic = sheet.querySelector('[data-ask-mic]');
        if (mic) mic.addEventListener('click', function () {
          if (S.listening) LampNative.call('stop', {}).then(null, function () {});
          else listen();
        });
        if (mic && S.voice.permission !== 'denied') listen(); else input.focus();
      }
    });
  }

  // The page going away (the phone locked, the app hidden) ends the session: a turn still thinking is cancelled, the mic
  // is let go and no follow-up listen starts.
  document.addEventListener('visibilitychange', function () { if (document.hidden) end(); });

  App.openAsk = open;
  App.on('ready', function () {
    if (!window.LampAI || !LampAI.act) return;
    LampAI.isAvailable('act').then(function (yes) {
      if (!yes) return;
      var rail = document.getElementById('rail'), settings = document.getElementById('railSettings');
      var b = document.createElement('button');
      b.className = 'rail-item rail-ask';
      b.innerHTML = App.icon('mic', 26) + '<span>Ask</span>';
      b.addEventListener('click', open);
      rail.insertBefore(b, settings);
    });
    // Voice: asked of the app itself, since LampNative.available only says there's an app around the page.
    if (native()) LampNative.call('voice', {}).then(function (v) { S.voice = v || null; }, function () { S.voice = null; });
  });
})();
