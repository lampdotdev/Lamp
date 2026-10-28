// Ask Home HQ: say or type what you want ("Add milk", "Mark the dishes done", "What do we need before school?") and it
// does it with the family's own data through LampAI.act, using the reads and writes in js/actions.js. Every copy of the
// screen shows the change through sync; the copy that heard you says what happened, built from what actually ran
// (never from the AI's own words), and offers Undo for what's still as the turn left it.
//
// The Ask button shows wherever it works: LampAI.isAvailable('act') (this page, the app around it and the AI set up in
// Lamp can all take it). Where the app around the page can hear (LampVoice: the Mac, iPhone and iPad, Android and
// Android TV, a TV remote's microphone included) and Lamp can transcribe (LampAI.isAvailable('hear')), opening Ask
// listens straight away: one press on the rail's Ask, then talk. Typing stays one press away everywhere (Type instead).
(function () {
  'use strict';
  var D = window.DATA;
  // `session` counts each time Ask opens, closes or the page hides: what started under one session (a follow-up listen,
  // what was heard, an answer) does nothing once it has changed. `pending` is a question back in progress: the request
  // it came from, every question and answer of the chain so far, what's asked now and what was already done, so the
  // answer is read against all of them. `heard` counts what was said: a recording, its transcription, and typing all
  // take a new count, so a transcription that comes back after the person has typed or talked again is dropped.
  var S = { turn: null, voice: null, hear: false, listening: false, listenTag: '', armedAt: 0, pending: null, last: null,
            el: null, session: 0, followUp: null, tags: 0, heard: 0, ready: null, lines: 0 };

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

  // ------------------------------------------------------------ voice (the app around the page's, where it has one)
  function canHear() { return !!(S.voice && S.voice.listen && S.hear); }
  // Resolves true once the words have been said to the end; false when there's no voice, or they were cut off.
  function speak(text) {
    if (!(S.voice && S.voice.speak && text)) return Promise.resolve(false);
    return LampVoice.speak(text).then(function (done) { return done === true; }, function () { return false; });
  }
  function hush() { if (S.voice && S.voice.speak) LampVoice.hush(); }
  function live(session) { return session === S.session && !!S.el && !document.hidden; }
  // Ends this session: nothing it started (a follow-up listen, a recording, a transcription, a turn) carries on.
  function end() {
    S.session++;
    clearTimeout(S.followUp);
    S.followUp = null;
    if (S.turn) { S.turn.cancel(); S.turn = null; busy(false); }
    if (S.listening) { S.listening = false; LampVoice.cancel(S.listenTag); }
    hush();
  }

  // ------------------------------------------------------------ the sheet
  function line(cls, html) {
    if (!S.el) return;
    S.lines++;
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
        if (!said || !r.ask || !canHear() || !live(session)) return;
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

  // The voice controls: Talk when idle, Stop while listening, the level as it's heard, and what's happening.
  function voiceState(kind, words) {
    if (!S.el) return;
    var talk = S.el.querySelector('[data-ask-talk]'), stop = S.el.querySelector('[data-ask-stop]');
    if (talk) talk.hidden = kind === 'listening';
    if (stop) stop.hidden = kind !== 'listening';
    S.el.classList.toggle('is-listening', kind === 'listening');
    var said = S.el.querySelector('[data-ask-voice-state]');
    if (said) said.textContent = words || '';
    if (kind !== 'listening') meter(0);
  }
  function meter(level) { var m = S.el && S.el.querySelector('[data-meter]'); if (m) m.style.width = Math.round(Math.min(1, level) * 100) + '%'; }

  function listen() {
    if (!canHear() || S.listening || S.turn || !S.el || document.hidden) return;
    var session = S.session, tag = 'ask' + session + '-' + (++S.tags), heard = ++S.heard;
    hush();
    S.listening = true; S.listenTag = tag; S.armedAt = Date.now();
    voiceState('listening', 'Listening… say what you want.');
    var stop = S.el.querySelector('[data-ask-stop]');
    if (stop) stop.focus();
    LampVoice.listen({ session: tag, onLevel: function (l) { if (live(session)) meter(l.level); } }).then(function (audio) {
      // Heard after Ask closed or the page hid: dropped, never transcribed, never a turn.
      if (session !== S.session || tag !== S.listenTag) return;
      S.listening = false;
      if (!live(session)) return;
      var ended = audio.ended;
      if (ended === 'cancelled') return voiceState('idle', '');
      if (ended === 'denied') { voiceState('idle', ''); line('ask-them', 'Home HQ can’t use the microphone. Allow it in Settings, or type instead.'); return showTyping(); }
      if (ended === 'nothing') {
        voiceState('idle', '');
        return line('ask-them', audio.peak < 0.01 ? 'I didn’t hear anything: no sound reached the microphone.' : 'I didn’t hear anything. Press Talk and try again.');
      }
      // Fifteen seconds may have cut the request off: never act on half of it.
      if (ended === 'cap') { voiceState('idle', ''); return line('ask-them is-partly', 'That was longer than I can take at once. Say it again, a little shorter.'); }
      if (ended === 'error' || !audio.audio) { voiceState('idle', ''); return line('ask-them is-partly', App.esc(audio.error || 'The microphone didn’t work.')); }
      voiceState('hearing', 'Working out what you said…');
      // Only while it's still the last thing said: talking again or typing meanwhile drops it.
      function current() { return live(session) && heard === S.heard; }
      LampAI.hear(audio.audio).then(function (r) {
        if (!current()) return;
        voiceState('idle', '');
        if (r.nothing) return line('ask-them', 'I didn’t catch that. Press Talk and try again.');
        ask(r.text);
      }, function (e) {
        if (!current()) return;
        voiceState('idle', '');
        line('ask-them is-partly', App.esc(e && e.message || 'I couldn’t hear that.'));
      });
    });
  }

  // Stop keeps what was said so far. Not in the first moment after listening starts: the press that opened Ask (its key
  // coming up, or repeating) mustn't also end what it began.
  function stopListening(e) {
    if (e && e.repeat) return;
    if (!S.listening || Date.now() - S.armedAt < 700) return;
    LampVoice.stop(S.listenTag);
  }
  // Typing instead: a recording is let go, and what was being worked out from one is dropped.
  function typeInstead() {
    S.heard++;
    if (S.listening) { S.listening = false; LampVoice.cancel(S.listenTag); }
    voiceState('idle', '');
    showTyping();
  }
  function showTyping() {
    if (!S.el) return;
    var form = S.el.querySelector('[data-ask-form]');
    form.hidden = false;
    S.el.querySelector('[data-ask-input]').focus();
  }

  // Talking or typing: the voice row (Talk, Stop, the level, Type instead) where it can hear, the typed box otherwise, and
  // a word when only transcription is missing.
  function setMode(voice) {
    if (!S.el) return;
    S.el.querySelector('[data-ask-voice]').hidden = !voice;
    S.el.querySelector('[data-ask-form]').hidden = voice;
    S.el.querySelector('[data-ask-note]').hidden = !(S.voice && S.voice.listen && !S.hear);
  }
  // With a voice, opening Ask is listening (one press), unless the microphone was refused; otherwise it's typing.
  function begin() {
    var voice = canHear();
    setMode(voice);
    if (voice && S.voice.permission !== 'denied') listen();
    else if (voice) { voiceState('idle', ''); S.el.querySelector('[data-ask-talk]').focus(); }
    else S.el.querySelector('[data-ask-input]').focus();
  }

  function open() {
    App.sheet('<div class="sheet-pad ask"><div class="label">Ask Home HQ</div>' +
      '<div class="ask-log" aria-live="polite"></div>' +
      '<div class="ask-voice" data-ask-voice hidden><button type="button" class="btn btn--solid ask-talk" data-ask-talk>' + App.icon('mic', 26) + 'Talk</button>' +
        '<button type="button" class="btn btn--solid ask-stop" data-ask-stop hidden>Stop</button>' +
        '<div class="ask-meter"><i data-meter></i></div><span class="ask-voice-state" data-ask-voice-state></span>' +
        '<button type="button" class="btn btn--ghost ask-type" data-ask-type>Type instead</button></div>' +
      '<form class="ask-row" data-ask-form>' +
      '<input class="ask-input" data-ask-input placeholder="Add milk · Mark the dishes done · What\'s on after school?" autocomplete="off">' +
      '<button class="btn btn--solid" data-ask-send>Ask</button></form>' +
      '<button class="btn btn--ghost ask-undo" data-ask-undo hidden>' + App.icon('undo', 22) + 'Undo</button>' +
      '<p class="sheet-p ask-note" data-ask-note hidden>Talking needs OpenRouter set up in Lamp on the Mac. You can type instead.</p>' +
      '</div>', {
      cls: 'sheet--wide',
      onClose: function () {
        // Closing ends the session: a recording is thrown away, and an answer, a transcript, a follow-up listen or
        // the voice answering late that comes after does nothing.
        end();
        S.pending = null;
        clearInterval(S.awake);
        S.el = null;
      },
      onMount: function (sheet) {
        S.session++;
        S.pending = null;
        S.el = sheet;
        S.lines = 0;
        var session = S.session;
        // Talking isn't touching: while Ask is open the screen stays as it is, not off to the photo frame or the night
        // clock (which would close the sheet and cancel the turn).
        App.resetIdle();
        clearInterval(S.awake);
        S.awake = setInterval(App.resetIdle, 1000);
        var input = sheet.querySelector('[data-ask-input]');
        sheet.querySelector('[data-ask-form]').addEventListener('submit', function (e) { e.preventDefault(); var t = input.value; input.value = ''; S.heard++; if (!S.listening) voiceState('idle', ''); ask(t); });
        sheet.querySelector('[data-ask-undo]').addEventListener('click', undo);
        var talk = sheet.querySelector('[data-ask-talk]'), stop = sheet.querySelector('[data-ask-stop]'), type = sheet.querySelector('[data-ask-type]');
        talk.addEventListener('click', listen);
        stop.addEventListener('click', stopListening);
        stop.addEventListener('keydown', function (e) { if (e.repeat) e.preventDefault(); });
        type.addEventListener('click', typeInstead);
        if (!S.ready) return begin();
        // Opened just after the page loaded, before the app around it has said whether it can hear: the sheet is up
        // and typed at once, so Back and closing work as ever, and it turns to listening when the answer comes, only
        // while this same sheet is still open and untouched.
        setMode(false);
        input.focus();
        S.ready.then(function () {
          if (!live(session) || S.turn || S.listening || input.value || S.lines) return;
          begin();
        });
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
    // Voice: asked of the app around the page (never prompting), and whether Lamp can transcribe.
    if (window.LampVoice) S.ready = LampVoice.status().then(function (v) {
      S.voice = v;
      if (v.listen) return LampAI.isAvailable('hear').then(function (yes) { S.hear = yes; });
    }).then(function () { S.ready = null; }, function () { S.ready = null; });
  });
})();
