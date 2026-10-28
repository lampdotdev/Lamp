// Ask Home HQ: say or type what you want ("Add milk", "Mark the dishes done", "What do we need before school?") and it
// does it with the family's own data through LampAI.act, using the reads and writes in js/actions.js. Every copy of the
// screen shows the change through sync; the copy that heard you says what happened, built from what actually ran
// (never from the AI's own words), and offers Undo for what's still as the turn left it.
//
// The Ask button shows wherever it works: LampAI.isAvailable('act') (this page, the app around it and the AI set up in
// Lamp can all take it). Where the app around the page can hear (LampVoice: the Mac, iPhone and iPad, Android and
// Android TV, a TV remote's microphone included) and Lamp can transcribe (LampAI.isAvailable('hear')), opening Ask
// listens straight away: one press on the rail's Ask, then talk. Typing stays one press away everywhere (Type).
//
// Ask floats over the page, a small panel at the bottom: what was said, what's happening or what happened, and its few
// buttons. While it's open the remote's focus stays in it (Lamp.scope, and Tab on the Mac), something in it always has
// focus, and the page's own shortcuts wait. A question back is read out, offers the AI's choices as buttons with the
// first focused, and listens again by itself: the first answer, said or pressed, is the one taken.
(function () {
  'use strict';
  var D = window.DATA;
  // `session` counts each time Ask opens, closes or the page hides: what started under one session (a follow-up listen,
  // what was heard, an answer) does nothing once it has changed. `pending` is a question back in progress: the request
  // it came from, every question and answer of the chain so far, what's asked now and what was already done, so the
  // answer is read against all of them. `heard` counts what was said: a recording, its transcription, and typing all
  // take a new count, so a transcription that comes back after the person has typed or talked again is dropped.
  // `q` is the question on screen, open until its first answer (a button, what was heard, or typing) claims it.
  var S = { turn: null, voice: null, hear: false, listening: false, listenTag: '', armedAt: 0, pending: null, last: null,
            el: null, session: 0, followUp: null, tags: 0, heard: 0, ready: null, lines: 0, q: null, qs: 0, touches: 0,
            closer: null, before: null, offBack: null, acts: [], focusKey: '' };

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
    S.heard++;
    clearTimeout(S.followUp);
    S.followUp = null;
    stayOpen();
    if (S.turn) { S.turn.cancel(); S.turn = null; }
    if (S.listening) { S.listening = false; LampVoice.cancel(S.listenTag); }
    if (S.q) S.q.open = false;
    hush();
  }

  // ------------------------------------------------------------ the panel
  function el(sel) { return S.el && S.el.querySelector(sel); }
  // What's happening now: what was said, and what it's doing or what it did. The exchange before moves up, dimmed; the
  // line here always says in full what changed.
  function show(now, cls) {
    var box = el('[data-ask-now]');
    if (!box) return;
    box.className = 'ask-now' + (cls ? ' ' + cls : '');
    box.innerHTML = now ? App.esc(now) : '';
    note('');
  }
  function note(text) { var n = el('[data-ask-note]'); if (n) n.innerHTML = text ? App.esc(text) : ''; }
  function youSaid(text) {
    var you = el('[data-ask-you]'), now = el('[data-ask-now]'), past = el('[data-ask-past]');
    if (!you) return;
    if (you.innerHTML || (now && now.innerHTML && S.lines)) {
      var d = document.createElement('div');
      d.className = 'ask-was';
      d.innerHTML = (you.innerHTML ? '<span class="ask-was-you">' + you.innerHTML + '</span> ' : '') + (now ? now.innerHTML : '');
      past.appendChild(d);
      while (past.children && past.children.length > 2) past.removeChild(past.children[0]);
    }
    you.innerHTML = text ? App.esc(text) : '';
    S.lines++;
  }
  function meter(level) { var m = el('[data-meter]'); if (m) m.style.width = Math.round(Math.min(1, level) * 100) + '%'; }
  function listeningLook(on) {
    if (!S.el) return;
    S.el.classList.toggle('is-listening', on);
    var m = el('[data-ask-meter]');
    if (m) m.hidden = !on;
    if (!on) meter(0);
  }

  // The panel's buttons, by key: `mic` (Talk, or Stop while listening), `type`, `undo`, `close` and `choice:N`. Focus
  // stays on the button that has it (wherever the arrows took it) across a change, the mic turning from Talk to Stop
  // included; otherwise it goes where asked, or to the first. A button newly given focus ignores OK for a moment, so a held or repeated press that came before
  // it never presses it.
  function focusedKey() {
    var f = document.activeElement;
    return f && S.el && S.el.contains(f) && f.getAttribute ? f.getAttribute('data-ask-act') || '' : '';
  }
  function acts(list, focusKey) {
    var box = el('[data-ask-acts]');
    if (!box) return;
    S.acts = list;
    S.focusKey = focusedKey() || S.focusKey;
    box.innerHTML = list.map(function (b) {
      return '<button type="button" class="btn ' + (b.solid ? 'btn--solid' : 'btn--ghost') + ' ask-act" data-ask-act="' + b.key + '">' +
        (b.icon ? App.icon(b.icon, 24) : '') + App.esc(b.label) + '</button>';
    }).join('');
    var typing = document.activeElement && document.activeElement.tagName === 'INPUT' && S.el.contains(document.activeElement);
    if (typing && !focusKey) return;
    var keys = list.map(function (b) { return b.key; });
    var key = focusKey && keys.indexOf(focusKey) >= 0 ? focusKey : keys.indexOf(S.focusKey) >= 0 ? S.focusKey : keys[0];
    if (!key) return;
    if (key !== S.focusKey) S.armedAt = Date.now();
    S.focusKey = key;
    var b = box.querySelector('[data-ask-act="' + key + '"]');
    if (b) b.focus();
  }
  function mic() { return { key: 'mic', label: S.listening ? 'Stop' : 'Talk', icon: S.listening ? '' : 'mic', solid: true }; }
  function questionActs() {
    var list = (S.q && S.q.open ? S.q.choices : []).map(function (c, i) { return { key: 'choice:' + i, label: c, solid: i === 0 }; });
    if (canHear()) list.push(mic());
    list.push({ key: 'type', label: 'Type' });
    return list;
  }
  function idleActs(undoable) {
    var list = [];
    if (undoable) list.push({ key: 'undo', label: 'Undo', icon: 'undo', solid: true });
    if (canHear()) list.push(mic());
    list.push({ key: 'type', label: 'Type' });
    list.push({ key: 'close', label: 'Close' });
    return list;
  }
  function settle(undoable) { acts(S.q && S.q.open ? questionActs() : idleActs(undoable)); }
  // After an answer, focus goes to what comes next: Undo when something changed, then Talk, then Close.
  function afterAnswer(undoable) { acts(idleActs(undoable), undoable ? 'undo' : canHear() ? 'mic' : 'close'); }

  function press(key) {
    touched();
    if (key === 'mic') return S.listening ? stopListening() : listen(S.q && S.q.open ? S.q.id : 0);
    if (key === 'type') return typeInstead();
    if (key === 'close') return close();
    if (key === 'undo') return undo();
    if (key.indexOf('choice:') === 0) {
      var q = S.q, choice = q && q.choices[+key.slice(7)];
      if (choice && claim(q.id)) ask(choice);
    }
  }

  // The question on screen is answered once: the first of a button, what was heard or what was typed claims it, and
  // ends whatever else was answering it (the recording, its transcription, the voice still reading it, a listen to come).
  function claim(id) {
    var q = S.q;
    if (!q || q.id !== id || !q.open) return false;
    q.open = false;
    clearTimeout(S.followUp);
    S.followUp = null;
    S.heard++;
    if (S.listening) { S.listening = false; LampVoice.cancel(S.listenTag); listeningLook(false); }
    hush();
    return true;
  }

  // Closing by itself: only after a finished answer that was read out to the end with nothing done meanwhile, counted
  // from then. Anything the person does (a key, a press, typing, Type) calls it off for that answer, and it never
  // closes over something being typed. Never while a question waits, nor after a failure or a part done. With Undo
  // there's longer.
  function quietAfter(undoable, session) {
    var touches = S.touches;
    return function (done) {
      if (done !== true || !live(session) || S.touches !== touches || S.turn || S.listening || (S.q && S.q.open)) return;
      stayOpen();
      S.closer = setTimeout(function () {
        var input = el('[data-ask-input]');
        if (!live(session) || S.touches !== touches || (input && (input.value || document.activeElement === input))) return;
        close();
      }, undoable ? 20000 : 8000);
    };
  }
  function stayOpen() { clearTimeout(S.closer); S.closer = null; }
  function touched() { S.touches = (S.touches || 0) + 1; stayOpen(); }

  function ask(text) {
    text = String(text || '').trim();
    if (!text || S.turn || !S.el) return;
    hush();
    stayOpen();
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
    S.q = null;
    youSaid(text);
    show('Thinking…', 'is-doing');
    acts([{ key: 'close', label: 'Close' }]);
    S.turn = LampAI.act(request, {
      about: ABOUT, tools: tools, history: history,
      context: { people: App.read.people(), today: App.dayText(App.now()) },
      onStep: function (s) { if (live(session) && !s.result) show((DOING[s.name] || s.name) + (s.args.name || s.args.title ? ' ' + (s.args.name || s.args.title) : '') + '…', 'is-doing'); }
    });
    var id = S.turn.id;
    S.turn.result.then(function (r) {
      // Cancelled by a close or the page hiding: nothing more.
      if (!S.turn || S.turn.id !== id || session !== S.session) return;
      S.turn = null;
      var spoken = words(r), did = receipt(r), partly = !!(r.failed.length || r.stopped);
      S.pending = r.ask ? { request: pending ? pending.request : text, answered: answered, question: r.reply,
                            done: [pending && pending.done, did].filter(function (x) { return x; }).join(' ') } : null;
      S.last = r.turn;
      var undoable = App.changesOf(r.turn).length > 0;
      show(spoken, partly ? 'is-partly' : '');
      if (r.ask) {
        var q = S.q = { id: ++S.qs, open: true, choices: (r.choices || []).slice(0, 4) };
        acts(questionActs(), q.choices.length ? 'choice:0' : canHear() ? 'mic' : 'type');
        // Read out, then listen for the answer by itself, while this same question is still waiting.
        speak(spoken).then(function (done) {
          if (!done || !canHear() || !live(session) || S.q !== q || !q.open) return;
          S.followUp = setTimeout(function () { if (live(session) && S.q === q && q.open) listen(q.id); }, 250);
        });
        return;
      }
      afterAnswer(undoable);
      var later = quietAfter(undoable, session);
      speak(spoken).then(function (done) { if (!partly) later(done); });
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
    var text = ((back.length ? 'Undid ' + back.join(', ') + '.' : '') + (kept.length ? ' Left ' + kept.join(', ') + ': changed since.' : '')).trim();
    youSaid('');
    show(text, kept.length ? 'is-partly' : '');
    afterAnswer(false);
    var later = quietAfter(false, S.session);
    speak(text).then(function (done) { if (!kept.length) later(done); });
  }

  // Listening, for a new request or (with `answering`) for the answer to the question on screen. Opening Ask gives the
  // mic (Stop) focus; listening again for an answer leaves focus where it is, on the first choice.
  function listen(answering) {
    if (!canHear() || S.listening || S.turn || !S.el || document.hidden) return;
    if (answering && !(S.q && S.q.id === answering && S.q.open)) return;
    var session = S.session, tag = 'ask' + session + '-' + (++S.tags), heard = ++S.heard;
    hush();
    stayOpen();
    S.listening = true; S.listenTag = tag;
    listeningLook(true);
    if (answering) { note('Listening… say your answer, or choose.'); acts(questionActs()); }
    else { youSaid(''); show('Listening… say what you want.'); S.armedAt = Date.now(); acts(S.q && S.q.open ? questionActs() : [mic(), { key: 'type', label: 'Type' }], S.q && S.q.open ? '' : 'mic'); }
    LampVoice.listen({ session: tag, onLevel: function (l) { if (live(session) && heard === S.heard) meter(l.level); } }).then(function (audio) {
      // Heard after Ask closed, the page hid, or something else answered or replaced it: dropped, never a turn.
      if (session !== S.session || tag !== S.listenTag || heard !== S.heard) return;
      S.listening = false;
      listeningLook(false);
      if (!live(session)) return;
      var ended = audio.ended, waiting = S.q && S.q.open;
      settle(false);
      function again(text, cls) { if (waiting) note(text); else show(text, cls); settle(false); }
      if (ended === 'cancelled') return settle(false);
      if (ended === 'denied') { again('Home HQ can’t use the microphone. Allow it in Settings, or type.'); return showTyping(); }
      // Nothing said: the question and its buttons stay, with Talk to say it again.
      if (ended === 'nothing') return again(audio.peak < 0.01 ? 'I didn’t hear anything: no sound reached the microphone.' : 'I didn’t hear anything. Say it again with Talk' + (waiting ? ', or choose.' : '.'));
      // Fifteen seconds may have cut the request off: never act on half of it.
      if (ended === 'cap') return again('That was longer than I can take at once. Say it again, a little shorter.', 'is-partly');
      if (ended === 'error' || !audio.audio) return again(audio.error || 'The microphone didn’t work.', 'is-partly');
      if (waiting) note('Working out what you said…'); else show('Working out what you said…', 'is-doing');
      // Only while it's still the last thing said: talking again, typing or a button meanwhile drops it.
      function current() { return live(session) && heard === S.heard; }
      LampAI.hear(audio.audio).then(function (r) {
        if (!current()) return;
        if (r.nothing) return again('I didn’t catch that. Say it again with Talk' + (waiting ? ', or choose.' : '.'));
        if (answering && !claim(answering)) return;
        ask(r.text);
      }, function (e) {
        if (!current()) return;
        again(e && e.message || 'I couldn’t hear that.', 'is-partly');
      });
    });
  }

  // Stop keeps what was said so far. Not in the first moment after listening starts: the press that opened Ask (its key
  // coming up, or repeating) mustn't also end what it began.
  function stopListening() {
    if (!S.listening || Date.now() - S.armedAt < 700) return;
    LampVoice.stop(S.listenTag);
  }
  // Typing: a recording is let go, and what was being worked out from one is dropped. A question on screen stays open
  // for the typed answer.
  function typeInstead() {
    S.heard++;
    clearTimeout(S.followUp);
    if (S.listening) { S.listening = false; LampVoice.cancel(S.listenTag); listeningLook(false); }
    hush();
    note('');
    settle(false);
    showTyping();
  }
  function showTyping() {
    if (!S.el) return;
    el('[data-ask-form]').hidden = false;
    el('[data-ask-input]').focus();
  }
  function typed(text) {
    if (!String(text || '').trim()) return;
    if (S.q && S.q.open && !claim(S.q.id)) return;
    S.heard++;
    ask(text);
  }

  // Talking or typing: the mic where it can hear, the typed box otherwise, and a word when only transcription is missing.
  function begin() {
    var voice = canHear();
    el('[data-ask-form]').hidden = voice;
    if (S.voice && S.voice.listen && !S.hear) note('Talking needs OpenRouter set up in Lamp on the Mac. You can type.');
    if (voice && S.voice.permission !== 'denied') return listen();
    show('');
    acts(idleActs(false), voice ? 'mic' : '');
    if (!voice) el('[data-ask-input]').focus();
  }

  // The panel keeps the keys: the arrows move only between its own buttons (Lamp.scope) and stop at its edges, where
  // nothing else may take them (Android's own focus search would leave the panel); Tab goes round them; a held or
  // repeated OK presses nothing new; and anything pressed calls off closing by itself.
  var ARROWS = { 37: 'left', 38: 'up', 39: 'right', 40: 'down' };
  function keys(e) {
    touched();
    if ((e.key === 'Enter' || e.keyCode === 13) && e.repeat && e.target && e.target.tagName !== 'INPUT') { e.preventDefault(); e.stopPropagation(); return; }
    var arrow = ARROWS[e.keyCode];
    if (arrow) {
      // Left and right move the caret in the typed box; everything else is the panel's.
      if (!(e.target && e.target.tagName === 'INPUT' && (arrow === 'left' || arrow === 'right'))) e.preventDefault();
      return;
    }
    if (e.key !== 'Tab') return;
    var list = Array.prototype.slice.call(S.el.querySelectorAll('button, input')).filter(function (b) { return !b.disabled && b.offsetParent !== null; });
    if (!list.length) return;
    var i = list.indexOf(document.activeElement);
    e.preventDefault();
    list[(i + (e.shiftKey ? -1 : 1) + list.length) % list.length].focus();
  }

  function open() {
    if (S.el) return;
    var layer = document.createElement('div');
    layer.className = 'ask-float';
    layer.setAttribute('role', 'dialog');
    layer.setAttribute('aria-label', 'Ask Home HQ');
    layer.innerHTML = '<div class="ask-past" data-ask-past></div><div class="ask-you" data-ask-you></div>' +
      '<div class="ask-now" data-ask-now aria-live="polite"></div><div class="ask-note" data-ask-note></div>' +
      '<div class="ask-meter" data-ask-meter hidden><i data-meter></i></div>' +
      '<div class="ask-acts" data-ask-acts></div>' +
      '<form class="ask-row" data-ask-form hidden><input class="ask-input" data-ask-input placeholder="Add milk · Mark the dishes done · What\'s on after school?" autocomplete="off">' +
      '<button class="btn btn--solid" data-ask-send>Ask</button></form>';
    (document.getElementById('stage') || document.body).appendChild(layer);
    S.session++;
    S.el = layer;
    S.pending = null; S.q = null; S.lines = 0; S.focusKey = '';
    var session = S.session;
    // The remote stays in the panel; what had focus, and any narrower scope, come back when it closes.
    S.before = { focus: document.activeElement, scope: window.Lamp ? Lamp.scope : null };
    if (window.Lamp) Lamp.scope = layer;
    S.offBack = window.Lamp && Lamp.onBack ? Lamp.onBack(function () { close(); return true; }) : null;
    // Talking isn't touching: while Ask is open the screen stays as it is, not off to the photo frame or the night clock.
    App.resetIdle();
    clearInterval(S.awake);
    S.awake = setInterval(App.resetIdle, 1000);
    var input = el('[data-ask-input]');
    el('[data-ask-form]').addEventListener('submit', function (e) { e.preventDefault(); var t = input.value; input.value = ''; typed(t); });
    el('[data-ask-acts]').addEventListener('click', function (e) {
      var b = e.target && e.target.closest ? e.target.closest('[data-ask-act]') : null;
      if (!b) return;
      if (Date.now() - S.armedAt < 700) return;
      press(b.getAttribute('data-ask-act'));
    });
    layer.addEventListener('keydown', keys, true);
    layer.addEventListener('pointerdown', touched);
    layer.addEventListener('focusin', function () { var k = focusedKey(); if (k) S.focusKey = k; });
    if (!S.ready) return begin();
    // Opened just after the page loaded, before the app around it has said whether it can hear: typed at once, and it
    // turns to listening when the answer comes, only while this same panel is still open and untouched.
    el('[data-ask-form]').hidden = false;
    acts([{ key: 'close', label: 'Close' }]);
    input.focus();
    S.ready.then(function () {
      if (!live(session) || S.turn || S.listening || input.value || S.lines) return;
      begin();
    });
  }

  // Closing ends the session: a recording is thrown away, and an answer, a transcript, a follow-up listen or the
  // voice answering late that comes after does nothing. Focus goes back to where it was (the rail's Ask).
  function close() {
    if (!S.el) return;
    end();
    S.pending = null;
    S.q = null;
    clearInterval(S.awake);
    if (S.offBack) S.offBack();
    S.offBack = null;
    var layer = S.el, before = S.before || {};
    S.el = null;
    if (layer.parentNode) layer.parentNode.removeChild(layer);
    if (window.Lamp) Lamp.scope = before.scope || null;
    var back = before.focus && document.body.contains && document.body.contains(before.focus) ? before.focus : document.querySelector('.rail-ask');
    if (back && back.focus) back.focus();
  }

  // The page going away (the phone locked, the app hidden) closes Ask: a turn still thinking is cancelled, the mic is
  // let go and no follow-up listen starts.
  document.addEventListener('visibilitychange', function () { if (document.hidden) close(); });

  App.openAsk = open;
  App.askOpen = function () { return !!S.el; };
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
