// Given to every page lamp dev serves, before any script of its own. The server puts `LAMP` in front of it: `gen` the
// last change the page's files had when they were served, `run` which run of the server served them.
(() => {
  const id = Math.random().toString(36).slice(2, 10);
  // The tab, which stays the same as its page opens again: how a change went is told of the tab.
  let tab = id;
  try { tab = sessionStorage.getItem('lamp.dev.tab') || id; sessionStorage.setItem('lamp.dev.tab', tab); } catch (e) {}
  window.__lampTab = tab;
  const post = (path, body, lasting) => {
    try { fetch('/__lamp/' + path, { method: 'POST', body: JSON.stringify({ page: id, ...body }), keepalive: !!lasting }).catch(() => {}); } catch (e) {}
  };
  const said = message => post('said', message, true);

  // The two things Lamp's app around a page gives it: with them the game runtime knows changes come while it's played,
  // and says how each one went and when the game is past its loading screen.
  const handlers = { lampLive: { postMessage: said }, lampPlaying: { postMessage: state => said({ state: 'page-' + state }) } };
  try { window.webkit = window.webkit || {}; window.webkit.messageHandlers = Object.assign(window.webkit.messageHandlers || {}, handlers); }
  catch (e) { try { Object.defineProperty(window, 'webkit', { value: { messageHandlers: handlers }, configurable: true }); } catch (e) {} }

  // The page's log, sent on a few lines at a time.
  let lines = [], timer = null;
  const say = (level, parts) => {
    let text;
    try { text = parts.map(p => typeof p === 'string' ? p : p instanceof Error ? (p.stack || p.message) : JSON.stringify(p)).join(' '); } catch (e) { text = String(parts[0]); }
    lines.push({ level, text: String(text).slice(0, 4000) });
    if (!timer) timer = setTimeout(() => { timer = null; const batch = lines; lines = []; post('log', { lines: batch }); }, 250);
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
  const reopen = () => (window.__lampReloadNow || (() => location.reload()))();
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
  window.__lampLook = () => {
    const lines = [], width = innerWidth, height = innerHeight;
    const CONTROLS = 'button, a[href], input, select, textarea, summary, [role=button], [role=link], [role=tab], [role=checkbox], [role=switch], [role=slider], [role=menuitem], [contenteditable=""], [contenteditable=true]';
    const words = text => String(text || '').replace(/\s+/g, ' ').trim().slice(0, 90);
    const box = el => {
      const r = el.getBoundingClientRect();
      return r.width < 2 || r.height < 2 || r.bottom <= 0 || r.right <= 0 || r.top >= height || r.left >= width ? null : r;
    };
    const middle = r => Math.round(Math.min(Math.max(r.left + r.width / 2, 0), width - 1)) + ',' + Math.round(Math.min(Math.max(r.top + r.height / 2, 0), height - 1));
    const kind = el => {
      const tag = el.tagName.toLowerCase(), role = el.getAttribute('role');
      if (role) return role;
      if (tag === 'a') return 'link';
      if (tag === 'select') return 'choice';
      if (tag === 'textarea' || el.isContentEditable) return 'field';
      if (tag === 'input') return ({ checkbox: 'checkbox', radio: 'radio', range: 'slider', button: 'button', submit: 'button' })[el.type] || 'field';
      return 'button';
    };
    const walk = parent => {
      for (const el of parent.children) {
        if (lines.length > 160) return;
        const tag = el.tagName.toLowerCase();
        if (tag === 'script' || tag === 'style' || tag === 'template' || tag === 'noscript') continue;
        const look = getComputedStyle(el);
        if (look.display === 'none' || Number(look.opacity) === 0) continue;
        const hidden = look.visibility === 'hidden', r = hidden ? null : box(el);
        if (r && tag === 'canvas') { lines.push(`canvas ${Math.round(r.width)}×${Math.round(r.height)} at ${middle(r)}`); continue; }
        if (r && el.matches(CONTROLS)) {
          const name = words(el.getAttribute('aria-label') || el.innerText || el.getAttribute('title') || el.getAttribute('placeholder') || el.getAttribute('alt') || el.name);
          const holds = el.type === 'checkbox' || el.type === 'radio' ? (el.checked ? ' (on)' : ' (off)')
            : 'value' in el && typeof el.value === 'string' && el.value && tag !== 'button' ? ` = "${words(el.value)}"` : '';
          lines.push(`${kind(el)} "${name}"${holds}${el.disabled ? ' (off for now)' : ''} at ${middle(r)}`);
          continue;
        }
        if (r && tag === 'img') { const alt = words(el.alt); if (alt) lines.push(`picture "${alt}"`); continue; }
        if (r) {
          const own = words([...el.childNodes].filter(n => n.nodeType === 3).map(n => n.textContent).join(' '));
          if (own) lines.push(`${/^h[1-6]$/.test(tag) ? 'heading' : 'text'} "${own}"`);
        }
        walk(el);
      }
    };
    if (document.body) walk(document.body);
    if (lines.length > 160) lines.push('… and more');
    return { tab, title: document.title, path: location.pathname + location.search, width, height, dpr: devicePixelRatio || 1, game: !!window.__lampLive, screen: lines.join('\n') };
  };
})();
