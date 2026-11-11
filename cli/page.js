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

  // MARK: The light on a change
  // The same light Lamp's app puts on an open app as a change goes in (`LampTransition.Look`, TransitionLook.swift, which
  // says how it looks: keep the two in step), drawn over the page: a faint glow round the edge and smoke in Lamp's stripe
  // colors rising from the bottom once a change comes, and Lamp's stripes rolling up on the slant as it goes in. While the
  // game stands still taking it in (running its code again, or opening again), the stripes roll up every few seconds
  // until its new code draws. The stripes and the smoke's puffs move by the browser's compositor, so they keep moving
  // while the page is busy with the new code. Never in a picture lamp takes (`__lampLightHidden`), and only the glow,
  // still, where less motion is asked for.
  const light = (() => {
    const HUES = ['#1f8a4a', '#7cbf3a', '#f6b81c', '#f08a1c', '#e2402a', '#d23778'];
    const SLANT = Math.PI / 6, ROLL = 1.1, TURN_EVERY = 3.2, STEPS = 60;
    const still = () => { try { return matchMedia('(prefers-reduced-motion: reduce)').matches; } catch (e) { return false; } };
    let root = null, glowEl = null, stripesEl = null, smoke = null, turning = null, rolls = [], gone = null, wisps = 0;
    const make = () => {
      if (root && root.isConnected) return;
      root = document.createElement('div');
      root.setAttribute('aria-hidden', 'true');
      root.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:2147483647;overflow:hidden;contain:strict';
      glowEl = document.createElement('div');
      glowEl.style.cssText = 'position:absolute;inset:0;opacity:0';
      stripesEl = document.createElement('div');
      stripesEl.style.cssText = 'position:absolute;opacity:0';
      smoke = document.createElement('div');
      smoke.style.cssText = 'position:absolute;inset:0;opacity:0';
      root.append(glowEl, smoke, stripesEl);
      // Beside the body rather than in it: a game running its code again clears what its body held.
      document.documentElement.appendChild(root);
      if (hidden) root.style.visibility = 'hidden';
    };
    // Where a stripe's edges are at a point of the roll, as in `LampTransition.Look.edges`.
    const edges = (index, roll, across) => {
      const share = Math.PI / HUES.length, height = a => (1 - Math.cos(Math.min(Math.max(a, 0), Math.PI))) / 2 * across;
      return [height(roll - (index + 1) * share), height(roll - index * share)];
    };
    const lay = () => {
      const w = innerWidth, h = innerHeight;
      const along = w * Math.cos(SLANT) + h * Math.sin(SLANT), across = w * Math.sin(SLANT) + h * Math.cos(SLANT);
      stripesEl.style.cssText = `position:absolute;left:${(w - along) / 2}px;top:${(h - across) / 2}px;width:${along}px;height:${across}px;transform:rotate(${-SLANT}rad);opacity:${stripesEl.style.opacity || 0}`;
      stripesEl.textContent = '';
      for (const hue of HUES) {
        const stripe = document.createElement('div');
        stripe.style.cssText = `position:absolute;left:0;bottom:0;width:100%;height:${across}px;background:${hue};transform-origin:50% 100%;transform:scaleY(0);will-change:transform`;
        stripesEl.appendChild(stripe);
      }
      return across;
    };
    // The stripes roll up from now, `turns` times, a turn coming round `every` seconds, the page clear between rolls.
    const roll = (turns, every, delay = 0) => {
      rolls.forEach(a => a.cancel());
      const across = lay();
      stripesEl.style.opacity = 1;
      const share = ROLL / Math.max(every, ROLL);
      rolls = [...stripesEl.children].map((stripe, index) => {
        const frames = [];
        for (let n = 0; n <= STEPS; n++) {
          const [bottom, top] = edges(index, 2 * Math.PI * n / STEPS, across);
          const tall = top > bottom ? top - bottom + 1 : 0;
          frames.push({ offset: share * n / STEPS, transform: `translateY(${-bottom}px) scaleY(${tall / across})` });
        }
        if (share < 1) frames.push({ offset: 1, transform: 'scaleY(0)' });
        return stripe.animate(frames, { duration: every * 1000, iterations: turns, delay: delay * 1000, fill: 'backwards' });
      });
    };
    // A puff of smoke rising from below the bottom edge, about a third of the way up, as `wisps` in the Look.
    const puff = (fast) => {
      if (!smoke || !wisps) return;
      const w = innerWidth, h = innerHeight, hue = HUES[Math.floor(Math.random() * HUES.length)];
      const size = 128 * (0.8 + (Math.random() - 0.5) * 0.7), life = 6 + (Math.random() - 0.5) * 3;
      const rise = h * 0.1 * (1 + (Math.random() - 0.5) * 0.9) * life * (fast ? 3.5 : 1);
      const x = (Math.random() * 1.1 - 0.05) * w, drift = (Math.random() - 0.5) * 2 * Math.tan(0.55) * rise;
      const el = document.createElement('div');
      el.style.cssText = `position:absolute;left:${x - size / 2}px;top:${h + 24 - size / 2}px;width:${size}px;height:${size}px;border-radius:50%;background:radial-gradient(circle, ${hue}e6 0%, ${hue}73 45%, ${hue}00 70%);opacity:0.42;will-change:transform,opacity`;
      smoke.appendChild(el);
      el.animate([{ transform: 'translate(0,0) scale(1)', opacity: 0.42 }, { transform: `translate(${drift}px,${-rise}px) scale(${1 + 0.16 * life})`, opacity: 0 }],
        { duration: life * 1000, easing: 'linear' }).onfinish = () => el.remove();
    };
    let breathing = null;
    const breathe = () => {
      clearInterval(breathing);
      // As the Look's birth rate: a puff in each color for every 66 points of the page's width, each second.
      const every = 1000 / Math.max(1, innerWidth / 66 * HUES.length / 3);
      breathing = setInterval(() => puff(false), every);
    };
    const fadeTo = (el, to, ms, delay = 0) => {
      const from = getComputedStyle(el).opacity;
      el.animate([{ opacity: from }, { opacity: to }], { duration: ms, delay, fill: 'forwards', easing: 'ease-out' });
    };
    const goAfter = seconds => {
      clearTimeout(gone);
      gone = setTimeout(() => { clearInterval(breathing); wisps = 0; rolls.forEach(a => a.cancel()); rolls = []; turning = null; root && root.remove(); root = null; }, seconds * 1000);
    };
    let hidden = false;
    const api = {
      // A change came: the glow and the smoke come up.
      glow() {
        make();
        clearTimeout(gone);
        glowEl.style.boxShadow = `inset 0 0 54px 6px ${HUES[0]}cc, inset 0 0 24px 2px ${HUES[0]}`;
        glowEl.animate(HUES.concat(HUES[0]).map(hue => ({ boxShadow: `inset 0 0 54px 6px ${hue}cc, inset 0 0 24px 2px ${hue}` })), { duration: 5000, iterations: Infinity });
        fadeTo(glowEl, 0.22, 600);
        if (still()) return;
        if (!wisps) { wisps = 1; fadeTo(smoke, 1, 1200); breathe(); }
      },
      // The game stands still taking it in: the stripes roll up every few seconds until `reveal`.
      turn() {
        make();
        clearTimeout(gone);
        if (still() || turning) return;
        turning = performance.now();
        roll(Infinity, TURN_EVERY);
      },
      // The change is on screen: the smoke surges and the stripes roll up once (or the turn under way finishes), and it all goes.
      reveal() {
        if (!root) return;
        clearInterval(breathing);
        if (still()) { fadeTo(glowEl, 0, 600); fadeTo(smoke, 0, 600); wisps = 0; return goAfter(0.8); }
        let left;
        if (turning !== null) {
          const into = (performance.now() - turning) / 1000 % TURN_EVERY;
          turning = null;
          if (into < ROLL) { rolls.forEach(a => a.effect.updateTiming({ iterations: Math.floor((performance.now() - (a.startTime || 0)) / (TURN_EVERY * 1000)) + 1 })); left = ROLL - into; }
          else { roll(1, ROLL); left = ROLL; }
        } else {
          for (let n = 0; n < 24 && wisps; n++) puff(true);
          roll(1, ROLL, 0.3);
          left = 0.3 + ROLL;
        }
        wisps = 0;
        fadeTo(smoke, 0, 600, 400);
        fadeTo(glowEl, 0, 600, 300);
        goAfter(Math.max(left, 0.6) + 0.3);
      },
      // The change didn't go in now (held for a pause or a Reload): the glow and the smoke go.
      fade() {
        if (!root) return;
        clearInterval(breathing);
        wisps = 0;
        turning = null;
        fadeTo(glowEl, 0, 500);
        fadeTo(smoke, 0, 1000);
        goAfter(1.1);
      },
      hide(on) { hidden = !!on; if (root) root.style.visibility = on ? 'hidden' : ''; },
    };
    return api;
  })();
  // Left out of the pictures lamp takes of the page.
  window.__lampLightHidden = on => light.hide(on);
  // A page opening again for a change goes on turning until its new code draws, as it was when it went.
  const TURNING = 'lamp.dev.turning';
  const turnAcross = () => { try { sessionStorage.setItem(TURNING, String(Date.now())); } catch (e) {} };
  try {
    const since = Number(sessionStorage.getItem(TURNING));
    sessionStorage.removeItem(TURNING);
    if (since && Date.now() - since < 30000) light.turn();
  } catch (e) {}
  // How the game said a change went, read for the light: it goes in now, stands still taking it in, waits, or is on screen.
  const lit = message => {
    const state = message && message.state;
    if (state === 'swapped') light.reveal();
    else if (state === 'rerun') light.turn();
    else if (state === 'reloading') { light.turn(); turnAcross(); }
    else if (state === 'held') light.fade();
    else if (['shown', 'restored', 'fresh', 'started'].includes(state)) light.reveal();
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
  // A page with the game runtime logs its own errors; any other page's are logged here.
  addEventListener('error', e => { if (!window.__lampLive) say('error', [e.message + ' (' + (String(e.filename || '').split('/').pop() || 'the page') + ':' + e.lineno + ')']); });
  addEventListener('unhandledrejection', e => { if (!window.__lampLive) say('error', [String(e.reason && e.reason.message || e.reason)]); });
  // A page without the game runtime is on screen once it has loaded.
  addEventListener('load', () => { said({ state: 'page-loaded' }); if (!window.__lampLive) light.reveal(); });

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
    light.glow();
    // A game takes the change and keeps the player's place; any other page opens again.
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
    if (window.__lampLive) {
      const canvas = [...document.querySelectorAll('canvas')].map(c => [c, c.getBoundingClientRect()]).sort((a, b) => b[1].width * b[1].height - a[1].width * a[1].height)[0];
      if (canvas && canvas[0].width > 1 && canvas[0].height > 1 && (width - canvas[1].width >= 2 || height - canvas[1].height >= 2)) stage = [canvas[0].width, canvas[0].height];
    }
    return { tab, stage, title: document.title, path: location.pathname + location.search, width, height, dpr: devicePixelRatio || 1, game: !!window.__lampLive, screen: lines.join('\n') };
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
