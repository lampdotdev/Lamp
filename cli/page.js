// Given to every page lamp dev serves, before any script of its own. The server puts `LAMP` in front of it: `gen` the
// last change the page's files had when they were served, `run` which run of the server served them.
(() => {
  // The browser's own functions, kept before the page changes them. The game runtime takes away the timers the
  // game's code left running each time that code runs again, and a timer of lamp's set through the page's
  // `setTimeout` would go with them, and the log with it.
  const later = window.setTimeout.bind(window), ask = window.fetch.bind(window);
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

  // What Lamp's app around a page gives it: with these the game runtime knows changes come while it's played, and says
  // how each one went and when the game is past its loading screen.
  const handlers = {
    lampLive: { postMessage: said }, lampPlaying: { postMessage: state => said({ state: 'page-' + state }) },
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
  // A page with the game runtime logs its own errors; any other page's are logged here.
  addEventListener('error', e => { if (!window.__lampLive) say('error', [e.message + ' (' + (String(e.filename || '').split('/').pop() || 'the page') + ':' + e.lineno + ')']); });
  addEventListener('unhandledrejection', e => { if (!window.__lampLive) say('error', [String(e.reason && e.reason.message || e.reason)]); });
  addEventListener('load', () => said({ state: 'page-loaded' }));

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
    // A game takes the change and keeps the player's place; any other page opens again.
    let taken = false;
    try { taken = !!(window.__lampLive && window.__lampLive(change)); } catch (e) {}
    if (!taken) { said({ gen: change.gen, state: 'reloading' }); location.reload(); }
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
    if (window.__lampLive) {
      const canvas = [...document.querySelectorAll('canvas')].map(c => [c, c.getBoundingClientRect()]).sort((a, b) => b[1].width * b[1].height - a[1].width * a[1].height)[0];
      if (canvas && canvas[0].width > 1 && canvas[0].height > 1 && (width - canvas[1].width >= 2 || height - canvas[1].height >= 2)) stage = [canvas[0].width, canvas[0].height];
    }
    return { tab, stage, title: document.title, path: location.pathname + location.search, width, height, dpr: devicePixelRatio || 1, game: !!window.__lampLive, screen: lines.join('\n') };
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
