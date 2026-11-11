// Given to every page lamp dev serves, before any script of its own. The server puts `LAMP` in front of it: `gen` the
// last change the page's files had when they were served, `run` which run of the server served them.
(() => {
  // The browser's own functions, kept before the page changes them. The game runtime takes away the timers the
  // game's code left running each time that code runs again, and a timer of lamp's set through the page's
  // `setTimeout` would go with them, and the log with it.
  const later = window.setTimeout.bind(window), ask = window.fetch.bind(window);
  const unlater = window.clearTimeout.bind(window), every = window.setInterval.bind(window), unevery = window.clearInterval.bind(window);
  // A page opened again to show its beginning (`lamp look --reopen`) says so to the game runtime, which then starts
  // the game from its start, its saves kept (`window.lampFreshStart` in lamp-game.js).
  const FRESH = 'lamp.dev.fresh';
  try { if (sessionStorage.getItem(FRESH)) { sessionStorage.removeItem(FRESH); window.lampFreshStart = true; } } catch (e) {}
  const id = Math.random().toString(36).slice(2, 10);
  // The tab, which stays the same as its page opens again: how a change went is told of the tab.
  let tab = id;
  try { tab = sessionStorage.getItem('lamp.dev.tab') || id; sessionStorage.setItem('lamp.dev.tab', tab); } catch (e) {}
  window.__lampTab = tab;
  const post = (path, body, lasting) => {
    try { ask('/__lamp/' + path, { method: 'POST', body: JSON.stringify({ page: id, ...body }), keepalive: !!lasting }).catch(() => {}); } catch (e) {}
  };
  const said = message => post('said', message, true);

  // MARK: The card on a change
  // The same card Lamp's app puts on an open app as a change goes in (`LampTransition.Look`, TransitionLook.swift, which
  // says how it looks: keep the two in step), at the foot of the page: Lamp's mark turning, "Updating" and what's
  // changing (the words the coding agent gave with `lamp changing`, if it did), then "Updated" for a moment once the
  // change is on screen, so every change is seen to land. It covers nothing but itself and lets every click through.
  // The mark turns by the browser's compositor, so it keeps turning while the page is busy with the new code. Never in
  // a picture lamp takes (`__lampLightHidden`), and still where less motion is asked for.
  const light = (() => {
    const HUES = ['#1f8a4a', '#7cbf3a', '#f6b81c', '#f08a1c', '#e2402a', '#d23778'];
    // As in the Look: the card stays at least this long, "Updated" this long, and the mark turns once in this long.
    const SHOWN_AT_LEAST = 1.2, HELD_AFTER = 1.4, SPIN_EVERY = 1.4;
    const still = () => { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } };
    let root = null, card = null, bands = null, title = null, detail = null, spinning = null, shownAt = 0, gone = null, hidden = false, safety = null;
    // The card's way out ("Updated" fading, or a fade), which a change coming meanwhile stops.
    let outgoing = null;
    const make = () => {
      if (root && root.isConnected) return;
      root = document.createElement('div');
      root.setAttribute('aria-hidden', 'true');
      root.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647;overflow:hidden;contain:strict';
      card = document.createElement('div');
      card.style.cssText = 'position:absolute;left:50%;bottom:min(20px,6vh);transform:translateX(-50%);display:flex;align-items:center;gap:8px;' +
        'height:36px;box-sizing:border-box;padding:0 16px 0 12px;max-width:min(460px,calc(100vw - 32px));border-radius:18px;' +
        'background:rgba(20,20,20,.86);border:1px solid rgba(255,255,255,.12);box-shadow:0 3px 12px rgba(0,0,0,.3);' +
        'font:13px/17px -apple-system,BlinkMacSystemFont,"Segoe UI",system-ui,sans-serif;color:#fff;white-space:nowrap;opacity:0';
      // Lamp's mark: its stripes on their slant, in a disc, which turns while the change is under way.
      const mark = document.createElement('div');
      mark.style.cssText = 'flex:none;width:18px;height:18px;border-radius:50%;overflow:hidden;position:relative';
      bands = document.createElement('div');
      bands.style.cssText = `position:absolute;left:-5.4px;top:-5.4px;width:28.8px;height:28.8px;transform:rotate(${-30}deg);` +
        `background:linear-gradient(to bottom, ${HUES.map((hue, i) => `${hue} ${i * 100 / 6}% ${(i + 1) * 100 / 6}%`).join(', ')})`;
      mark.appendChild(bands);
      title = document.createElement('span');
      title.style.cssText = 'flex:none;font-weight:600';
      detail = document.createElement('span');
      detail.style.cssText = 'min-width:0;overflow:hidden;text-overflow:ellipsis;opacity:.72';
      card.append(mark, title, detail);
      root.appendChild(card);
      // Beside the body rather than in it: a game running its code again clears what its body held.
      document.documentElement.appendChild(root);
      if (hidden) root.style.visibility = 'hidden';
    };
    const goAfter = seconds => {
      unlater(gone);
      gone = later(() => { spinning = null; root && root.remove(); root = null; shownAt = 0; }, seconds * 1000);
    };
    const show = () => {
      make();
      unlater(gone);
      if (outgoing) { outgoing.cancel(); outgoing = null; }
      if (shownAt) return;
      shownAt = performance.now();
      card.animate([{ opacity: 0, transform: still() ? 'translateX(-50%)' : 'translate(-50%, 10px)' }, { opacity: 1, transform: 'translateX(-50%)' }],
        { duration: 250, easing: 'ease-out', fill: 'forwards' });
    };
    const spin = () => {
      if (still() || spinning) return;
      spinning = bands.animate([{ transform: 'rotate(-30deg)' }, { transform: 'rotate(330deg)' }], { duration: SPIN_EVERY * 1000, iterations: Infinity });
    };
    // Never left over a page that doesn't say its change is on screen (a game stopped by an error): it goes after a
    // minute, as the card in Lamp's app goes when Lamp stops renewing it.
    const watch = () => { unlater(safety); safety = later(() => api.fade(), 60000); };
    let words = '';
    const api = {
      // A change came: the card comes up with "Updating", what's changing, and the mark turning.
      glow(given) {
        if (typeof given === 'string') words = given;
        show();
        watch();
        title.textContent = 'Updating';
        detail.textContent = words;
        spin();
      },
      // The game stands still taking it in: the card stays as it is until `reveal`.
      turn() { api.glow(); },
      // The change is on screen: "Updated" for a moment, then the card goes.
      reveal() {
        if (!root) return;
        unlater(safety);
        title.textContent = 'Updated';
        if (spinning) { spinning.cancel(); spinning = null; }
        if (!still()) bands.parentNode.animate([{ transform: 'scale(1.25)' }, { transform: 'scale(1)' }], { duration: 300, easing: 'ease-out' });
        const wait = Math.max(HELD_AFTER, SHOWN_AT_LEAST - (performance.now() - shownAt) / 1000);
        if (outgoing) outgoing.cancel();
        outgoing = card.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 300, delay: wait * 1000, fill: 'forwards', easing: 'ease-in-out' });
        words = '';
        goAfter(wait + 0.35);
      },
      // The change didn't go in now (held for a pause or a Reload): the card goes.
      fade() {
        unlater(safety);
        if (!root) return;
        if (outgoing) outgoing.cancel();
        outgoing = card.animate([{ opacity: getComputedStyle(card).opacity }, { opacity: 0 }], { duration: 250, fill: 'forwards' });
        words = '';
        goAfter(0.3);
      },
      hide(on) { hidden = !!on; if (root) root.style.visibility = on ? 'hidden' : ''; },
      get words() { return words; },
    };
    return api;
  })();
  // Left out of the pictures lamp takes of the page.
  window.__lampLightHidden = on => light.hide(on);
  // A page opening again for a change goes on saying so until its new code draws, with the same words.
  const TURNING = 'lamp.dev.turning', WORDS = 'lamp.dev.words';
  const turnAcross = () => { try { sessionStorage.setItem(TURNING, String(Date.now())); sessionStorage.setItem(WORDS, light.words); } catch (e) {} };
  try {
    const since = Number(sessionStorage.getItem(TURNING)), carried = sessionStorage.getItem(WORDS) || '';
    sessionStorage.removeItem(TURNING);
    sessionStorage.removeItem(WORDS);
    if (since && Date.now() - since < 30000) light.glow(carried);
  } catch (e) {}
  // How the game said a change went, read for the card: it goes in now, stands still taking it in, waits, or is on screen.
  const lit = message => {
    const state = message && message.state;
    if (state === 'swapped') light.reveal();
    else if (state === 'rerun') light.turn();
    else if (state === 'reloading') { light.turn(); turnAcross(); }
    else if (state === 'held') light.fade();
    // Once its new frames can show, as Lamp's app reads it (`PageLive`): a game put back where it was says so before its
    // first frame and its shaders.
    else if (state === 'shown') light.reveal();
  };

  // What Lamp's app around a page gives it: with these the game runtime knows changes come while it's played, and says
  // how each one went and when the game is past its loading screen.
  const handlers = {
    lampLive: { postMessage: message => { lit(message); said(message); } }, lampPlaying: { postMessage: state => said({ state: 'page-' + state }) },
    // The person played while lamp held the game's controller (`lamp use stick`), and has it back.
    lampDriveTakenOver: { postMessage: why => said({ state: 'taken-over', why: String(why || '') }) },
  };
  try { window.webkit = window.webkit || {}; window.webkit.messageHandlers = Object.assign(window.webkit.messageHandlers || {}, handlers); }
  catch (e) { try { Object.defineProperty(window, 'webkit', { value: { messageHandlers: handlers }, configurable: true }); } catch (e) {} }

  // The page's log, sent on a few lines at a time.
  let lines = [], timer = null;
  const say = (level, parts) => {
    let text;
    try { text = parts.map(p => typeof p === 'string' ? p : p instanceof Error ? (p.stack || p.message) : JSON.stringify(p)).join(' '); } catch (e) { text = String(parts[0]); }
    lines.push({ level, text: String(text).slice(0, 4000) });
    if (!timer) timer = later(() => { timer = null; const batch = lines; lines = []; post('log', { lines: batch }); }, 250);
  };
  for (const level of ['log', 'info', 'warn', 'error']) {
    const real = console[level];
    console[level] = (...parts) => { real.apply(console, parts); say(level === 'info' ? 'log' : level, parts); };
  }
  // Whether the page runs on the game runtime (lamp-game.js), which says so. A game's page without it has `__lampLive`
  // too (lamp-live.js, given after this script), so that alone doesn't tell; a runtime from before it said so does have
  // its own `__lampLive`, never lamp-live.js's.
  const runtime = () => !!window.__lampRuntime || (!!window.__lampLive && !window.__lampLive.lampHelper);
  // A page with the game runtime logs its own errors; any other page's are logged here.
  addEventListener('error', e => { if (!runtime()) say('error', [e.message + ' (' + (String(e.filename || '').split('/').pop() || 'the page') + ':' + e.lineno + ')']); });
  addEventListener('unhandledrejection', e => { if (!runtime()) say('error', [String(e.reason && e.reason.message || e.reason)]); });
  // A page without the game runtime is on screen once it has loaded.
  addEventListener('load', () => { said({ state: 'page-loaded' }); if (!runtime()) light.reveal(); });

  // Changes. The line says which change this copy's files had, so one saved while the page was opening comes as soon
  // as the line is open; the browser says the last it heard when the line is opened again after a break.
  // Opened again from where the player is, or from the game's beginning when that's asked: the page that opens next
  // is told so before the runtime loads (see `FRESH` above). Any other page always starts over.
  const reopen = e => {
    if (e && e.data === 'fresh') {
      try { sessionStorage.setItem(FRESH, '1'); } catch (e2) {}
      return location.reload();
    }
    (window.__lampReloadNow || (() => location.reload()))();
  };
  const events = new EventSource('/__lamp/events?page=' + id + '&tab=' + tab + '&since=' + LAMP.gen);
  // A server started again doesn't know what changed while it was away: the page opens again from the files as they are.
  events.addEventListener('hello', e => { if (e.data !== LAMP.run) location.reload(); });
  events.addEventListener('change', e => {
    const change = JSON.parse(e.data);
    light.glow(typeof change.words === 'string' ? change.words : '');
    // A game takes the change and keeps the player's place (on the runtime, or where lamp-live.js can); any other page
    // opens again.
    let taken = false;
    try { taken = !!(window.__lampLive && window.__lampLive(change)); } catch (e) {}
    if (!taken) { light.turn(); turnAcross(); said({ gen: change.gen, state: 'reloading' }); location.reload(); }
  });
  events.addEventListener('reload', reopen);
  // With no browser lamp can look into, the page says what's on it itself.
  events.addEventListener('look', e => post('looked', { ask: e.data, seen: window.__lampLook() }));

  // What's on the page, as text: each control and canvas with the point at its middle, and the words shown.
  const CONTROLS = 'button, a[href], input, select, textarea, summary, [role=button], [role=link], [role=tab], [role=checkbox], [role=switch], [role=slider], [role=menuitem], [contenteditable=""], [contenteditable=true]';
  const words = text => String(text || '').replace(/\s+/g, ' ').trim().slice(0, 90);
  const kind = el => {
    const tag = el.tagName.toLowerCase(), role = el.getAttribute('role');
    if (role) return role;
    if (tag === 'a') return 'link';
    if (tag === 'select') return 'choice';
    if (tag === 'textarea' || el.isContentEditable) return 'field';
    if (tag === 'input') return ({ checkbox: 'checkbox', radio: 'radio', range: 'slider', button: 'button', submit: 'button' })[el.type] || 'field';
    return 'button';
  };
  const named = el => `${kind(el)} "${words(el.getAttribute('aria-label') || el.innerText || el.getAttribute('title') || el.getAttribute('placeholder') || el.getAttribute('alt') || el.name)}"`;

  window.__lampLook = () => {
    const lines = [], width = innerWidth, height = innerHeight;
    const box = el => {
      const r = el.getBoundingClientRect();
      return r.width < 2 || r.height < 2 || r.bottom <= 0 || r.right <= 0 || r.top >= height || r.left >= width ? null : r;
    };
    const middle = r => Math.round(Math.min(Math.max(r.left + r.width / 2, 0), width - 1)) + ',' + Math.round(Math.min(Math.max(r.top + r.height / 2, 0), height - 1));
    const walk = parent => {
      for (const el of parent.children) {
        if (lines.length > 160) return;
        const tag = el.tagName.toLowerCase();
        if (tag === 'script' || tag === 'style' || tag === 'template' || tag === 'noscript') continue;
        const look = getComputedStyle(el);
        // What's faded out, or nearly (a loading screen on its way out), isn't on the screen.
        if (look.display === 'none' || Number(look.opacity) < 0.1) continue;
        const hidden = look.visibility === 'hidden', r = hidden ? null : box(el);
        if (r && tag === 'canvas') {
          // A canvas drawn at another size than it's shown (a game's stage) says how a point of what's drawn is found
          // in the picture.
          const scale = el.width ? r.width / el.width : 1, round = n => Math.round(n * 100) / 100;
          const drawn = Math.abs(scale - 1) > 0.02 && el.width > 1 ? ` (drawn at ${el.width}×${el.height}: its point x,y is at ${Math.round(r.left)}+x×${round(scale)}, ${Math.round(r.top)}+y×${round(r.height / el.height)} in the picture)` : '';
          lines.push(`canvas ${Math.round(r.width)}×${Math.round(r.height)} at ${middle(r)}${drawn}`);
          continue;
        }
        if (r && el.matches(CONTROLS)) {
          const holds = el.type === 'checkbox' || el.type === 'radio' ? (el.checked ? ' (on)' : ' (off)')
            : 'value' in el && typeof el.value === 'string' && el.value && tag !== 'button' ? ` = "${words(el.value)}"` : '';
          lines.push(`${named(el)}${holds}${el.disabled ? ' (off for now)' : ''} at ${middle(r)}`);
          continue;
        }
        if (r && tag === 'img') { const alt = words(el.alt); if (alt) lines.push(`picture "${alt}"`); continue; }
        if (r) {
          // Words set in pieces (a number in a span of its own, a heading in two colors) are one line, as they read.
          const pieces = [...el.children];
          const whole = pieces.length && (/^h[1-6]$/.test(tag) ? !el.querySelector(CONTROLS + ', canvas')
            : pieces.every(c => getComputedStyle(c).display.startsWith('inline') && !c.children.length && !c.matches(CONTROLS) && c.tagName.toLowerCase() !== 'canvas'));
          const own = words(whole ? el.innerText : [...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' '));
          if (own) lines.push(`${/^h[1-6]$/.test(tag) ? 'heading' : 'text'} "${own}"`);
          if (whole) continue;
        }
        walk(el);
      }
    };
    if (document.body) walk(document.body);
    if (lines.length > 160) lines.push('… and more');
    // A game drawn on a stage of its own shape, fitted in the window with bars beside or above it: the stage's size.
    // One that fills the window, whatever its shape, has none.
    let stage = null;
    if (runtime()) {
      const canvas = [...document.querySelectorAll('canvas')].map(c => [c, c.getBoundingClientRect()]).sort((a, b) => b[1].width * b[1].height - a[1].width * a[1].height)[0];
      if (canvas && canvas[0].width > 1 && canvas[0].height > 1 && (width - canvas[1].width >= 2 || height - canvas[1].height >= 2)) stage = [canvas[0].width, canvas[0].height];
    }
    return { tab, stage, title: document.title, path: location.pathname + location.search, width, height, dpr: devicePixelRatio || 1, game: runtime(), screen: lines.join('\n') };
  };

  // The point of the control called this in the screen as text (`button "Add"`, or just `Add`), for a click by name.
  window.__lampPoint = called => {
    const wanted = String(called).trim();
    for (const el of document.querySelectorAll(CONTROLS)) {
      const r = el.getBoundingClientRect(), look = getComputedStyle(el);
      if (r.width < 2 || r.height < 2 || look.display === 'none' || look.visibility === 'hidden') continue;
      const name = named(el), label = name.slice(name.indexOf('"') + 1, -1);
      if (name === wanted || label === wanted) return [Math.round(r.left + r.width / 2), Math.round(r.top + r.height / 2)];
    }
    return null;
  };

  // What's at a point of the page, in the screen's own words, so a click says what it landed on.
  window.__lampAt = (x, y) => {
    const el = document.elementFromPoint(x, y);
    if (!el || el === document.documentElement || el === document.body) return 'nothing: the page\'s background';
    const control = el.closest(CONTROLS);
    if (control) return named(control);
    if (el.tagName.toLowerCase() === 'canvas') return 'the canvas';
    const text = words(el.innerText).slice(0, 50);
    return text ? `the text "${text}", which isn't a control` : 'nothing that\'s a control';
  };
})();
