// The sidebar of one tab: Chrome keeps a separate one per tab (worker.js opens it for the tab clicked), so what is
// typed here, which app is chosen and what the app prepared stay with this tab and never mix with another's.
const $ = id => document.getElementById(id);
const tab = Number(new URLSearchParams(location.search).get('tab'));
const keys = {tab: 'tab:' + tab, pick: 'pick:' + tab, draft: 'draft:' + tab};
let apps = [], selected = '', clickSeen = 0, revision = '', viewKey = '', busy = false, refreshing = false, transportProblem = false;
let info = {}, drafts = {}, opening = {};
async function call(body) { const r = await chrome.runtime.sendMessage({...body, tab}); if (r?.error) throw new Error(r.error); return r; }
function error(e) { $('error').textContent = e ? e.message : ''; }
function note(text) { $('note').textContent = text || ''; $('note').hidden = !text; }

// The app the click on Lamp found fitting this page comes first; after that the person's own choice holds.
function choose() {
  const fitting = (info.fitting || []).filter(id => apps.some(a => a.id === id));
  if (info.at && info.at !== clickSeen) {
    clickSeen = info.at;
    if (fitting.length && fitting[0] !== selected) { selected = fitting[0]; viewKey = ''; }
  }
  if (!apps.some(a => a.id === selected)) { selected = fitting[0] || apps[0]?.id || ''; viewKey = ''; }
  const sorted = [...apps].sort((a, b) => fitting.includes(b.id) - fitting.includes(a.id) || a.name.localeCompare(b.name));
  const key = JSON.stringify([sorted.map(a => a.id + a.name), selected]);
  if ($('chooser').dataset.key !== key) {
    $('chooser').dataset.key = key; $('chooser').replaceChildren();
    if (apps.length > 1) {
      const menu = document.createElement('select'); menu.ariaLabel = 'App';
      for (const app of sorted) { const o = document.createElement('option'); o.value = app.id; o.textContent = app.name; menu.append(o); }
      menu.value = selected;
      menu.onchange = () => { selected = menu.value; viewKey = ''; chrome.storage.session.set({[keys.pick]: selected}); void refresh(); };
      $('chooser').append(menu);
    } else if (apps.length) $('chooser').textContent = apps[0].name;
  }
  // The strip names the app and nothing it offers: the app's own sidebar makes its offer, and a second one here
  // said the same thing twice.
  return apps.find(a => a.id === selected);
}

// What the person typed is kept against the value the app showed when they typed it: if the app changes that
// field itself, its new value wins; otherwise their words stay, through tab switches and a reopened sidebar.
function shown(field) {
  const draft = drafts[selected]?.[field.id];
  return draft && draft.base === field.value ? draft.typed : field.value;
}
// A draft whose field is gone, or whose value the app has since replaced, is done with: kept, it would come back
// the moment the app showed the old value again (an empty field for the next item, say) and be sent with a click.
function settleDrafts(saved, fields) {
  const kept = {};
  for (const field of fields) {
    const draft = saved?.[field.id];
    if (draft && draft.base === field.value) kept[field.id] = draft;
  }
  return kept;
}
function typed(field, value) {
  drafts[selected] = {...drafts[selected], [field.id]: {base: field.value, typed: value}};
  chrome.storage.session.set({[keys.draft]: drafts});
}

function render(state) {
  const s = state.surface, key = selected + ':' + state.revision + ':' + state.busy;
  revision = state.revision;
  if (key === viewKey) return;
  viewKey = key;
  $('title').textContent = s.title; $('detail').textContent = s.detail;
  $('sections').replaceChildren(); $('fields').replaceChildren(); $('actions').replaceChildren();
  for (const section of s.sections) {
    const h = document.createElement('h2'); h.textContent = section.title; $('sections').append(h);
    if (section.text) { const p = document.createElement('p'); p.textContent = section.text; $('sections').append(p); }
    if (section.items?.length) {
      const list = document.createElement('ul');
      for (const item of section.items) { const li = document.createElement('li'); li.textContent = item; list.append(li); }
      $('sections').append(list);
    }
  }
  const kept = settleDrafts(drafts[selected], s.fields);
  if (JSON.stringify(kept) !== JSON.stringify(drafts[selected] || {})) {
    drafts[selected] = kept;
    chrome.storage.session.set({[keys.draft]: drafts});
  }
  for (const field of s.fields) {
    const label = document.createElement('label');
    const input = document.createElement((field.lines || 1) > 1 ? 'textarea' : 'input');
    if (input.localName === 'textarea') input.rows = Math.min(field.lines, 12);
    label.textContent = field.label; input.value = shown(field); input.dataset.field = field.id; input.maxLength = 4000;
    input.oninput = () => typed(field, input.value);
    label.append(input); $('fields').append(label);
  }
  // Named as Lamp knows the app, not by the title it gives its own sidebar.
  const name = apps.find(a => a.id === selected)?.name || 'this app';
  $('consent').textContent = s.actions.some(a => a.readsPage) ? `Using this page shares its text with ${name} and its AI.`
    : s.actions.some(a => a.readsSelection) ? `Using a selection shares only that passage with ${name} and its AI.` : '';
  for (const action of s.actions) {
    const button = document.createElement('button'); button.textContent = action.label;
    button.disabled = busy || state.busy || s.busy;
    button.onclick = () => act(action); $('actions').append(button);
  }
}

async function act(action) {
  if (busy) return;
  busy = true; error();
  const app = selected, rev = revision;
  const fields = Object.fromEntries([...$('fields').querySelectorAll('input,textarea')].map(e => [e.dataset.field, e.value]));
  for (const button of $('actions').children) button.disabled = true;
  try { await call({op: 'surface-action', app, revision: rev, id: crypto.randomUUID(), action: action.id, fields}); }
  catch (e) { error(e); }
  finally { busy = false; viewKey = ''; await refresh(); }
}

async function refresh() {
  if (refreshing || busy) return; refreshing = true;
  try {
    const saved = await chrome.storage.session.get([keys.tab, keys.pick, keys.draft]);
    info = saved[keys.tab] || {}; drafts = saved[keys.draft] || {};
    if (!selected && saved[keys.pick]) selected = saved[keys.pick];
    const listed = await call({op: 'surface-list'});
    apps = listed.apps; lampClosed = !!listed.lampClosed;
    const app = choose();
    $('empty').hidden = apps.length > 0;
    if (transportProblem) { error(); transportProblem = false; }
    if (!app) { document.querySelector('main').hidden = true; showPage(null); note(''); return; }
    if (app.page?.urls?.length) return showPage(app);
    showPage(null);
    if (lampClosed) throw new Error('Open Lamp on this Mac, then try again.');
    const state = await call({op: 'surface-view', app: app.id});
    if (!state.surface) {
      // An app that isn't open on the Mac is opened when chosen, once; it shows here as soon as it's up.
      document.querySelector('main').hidden = true; viewKey = '';
      opening[app.id] ??= {at: Date.now(), asked: call({op: 'surface-open', app: app.id}).catch(e => { error(e); })};
      note(Date.now() - opening[app.id].at < 30000 ? `Opening ${app.name}…` : `${app.name} didn’t open. Open it on your Mac, then come back.`);
      return;
    }
    delete opening[app.id];
    note(info.moved ? 'This tab is on a new page. Click Lamp in Chrome’s toolbar to use it here.' : '');
    document.querySelector('main').hidden = false;
    render(state);
  } catch (e) { document.querySelector('main').hidden = true; transportProblem = true; error(e); }
  finally { refreshing = false; }
}
// An app that serves its own page: the sidebar frames it, keeps the app's name and the consent line above it, and
// is the page's only way to the person's tab. A frame that fails to load says nothing, so the page says hello.
let lampClosed = false, framed = '', frameReady = false, frameAsked = 0, tabKey = '', tried = 0;
function clearLook() { for (const name of ['bg', 'ink', 'muted', 'line', 'accent']) document.body.style.removeProperty('--page-' + name); }
function showPage(app) {
  const frame = $('page');
  document.body.classList.toggle('framed', !!app);
  if (!app) { if (framed) { frame.src = 'about:blank'; framed = ''; } frame.hidden = true; clearLook(); return; }
  document.querySelector('main').hidden = true;
  const now = Date.now();
  // Not answering: the app's next port is tried (another program may have its first), and round again every few
  // seconds, so the page shows once the app is open. Only the app answers its own name, on whichever port it has.
  if (framed !== app.id || (!frameReady && now - frameAsked > 2500)) {
    if (framed !== app.id) { frameReady = false; tried = 0; } else tried++;
    framed = app.id; frameAsked = now;
    const url = app.page.urls[tried % app.page.urls.length];
    frame.dataset.origin = new URL(url).origin;
    frame.src = url + '#' + new URLSearchParams({tab: tabKey}).toString();
    clearLook();   // another page's colours never stay on the strip; a page that sends none gets the strip's own
    readSpent = true; if (document.activeElement === frame) takeFocusBack();
  }
  // A page that stopped answering (its app quit, or reopened at another of its ports) is looked for again.
  if (frameReady && now - lastAlive > 8000) { frameReady = false; pageToken = ''; frameAsked = 0; }
  if (frameReady) { void deliverMenu(); frame.hidden = false; note(info.moved ? 'This tab is on a new page. Click Lamp in Chrome’s toolbar to use it here.' : ''); return; }
  frame.hidden = true;
  if (tried < app.page.urls.length && !opening[app.id]) return;
  if (!lampClosed) opening[app.id] ??= {at: now, asked: call({op: 'surface-open', app: app.id}).catch(() => {})};
  note(lampClosed || (opening[app.id] && now - opening[app.id].at > 30000) ? `Open ${app.name} on your Mac to use it here.` : `Opening ${app.name}…`);
}
// What a page may read is what Lamp found its file declares (`page.reads`), never what the page says as it runs, and
// the consent line says the same. One read per click in the page.
// `nonces`: one per hello still waiting for its proof. `pageToken`: given to the page that proved itself, held only in
// that page's memory, and asked of every read, so a document that replaced it (it navigated, the app went and
// another program took its port) can't read on what the app's page proved.
let readSpent = false, nonces = new Set(), pageToken = '';
// The app's right-click item, chosen for this tab, stands for the person's click in its page: the proved page is told
// once (`lamp.onMenu`), and may read once without a click, within a few seconds, only the page it was chosen on.
let menuSeen = 0, menuRead = null;
async function deliverMenu() {
  const menu = info.menu, frame = $('page');
  if (!menu || !frameReady || !pageToken || menu.app !== framed || menu.at === menuSeen) return;
  menuSeen = menu.at;
  const {menu: _, ...rest} = info; info = rest;
  await chrome.storage.session.set({[keys.tab]: rest});
  if (info.moved || Date.now() - menu.at > 30000) return;
  menuRead = {token: pageToken, url: menu.url, until: Date.now() + 15000};
  frame.contentWindow.postMessage({lamp: 'menu'}, frame.dataset.origin);
}
// Every document the frame loads proves itself again, so a page that replaced the app's (the app gone, another
// program on its port) can't use what the app's page proved.
$('page').addEventListener('load', () => {
  pageToken = '';
  if (!frameReady) return;
  frameReady = false; frameAsked = Date.now();
  $('page').contentWindow.postMessage({lamp: 'prove'}, $('page').dataset.origin);
});
// A click in the page gives one read. Presses inside the frame never reach this document, but the focus moving into
// the frame does: that is a click (or a tab) into the page, and arms one read. After a read the sidebar takes focus
// back, so the next click in the page arms the next one. A press on the sidebar's own parts (the app menu, the strip)
// isn't a click in the page and arms nothing.
let lastAlive = 0;
window.addEventListener('blur', () => setTimeout(() => { if (document.activeElement === $('page')) readSpent = false; }));
for (const kind of ['pointerdown', 'keydown']) document.addEventListener(kind, () => { readSpent = true; }, true);
function takeFocusBack() { $('top').tabIndex = -1; $('top').focus({preventScroll: true}); }
const hex = bytes => [...new Uint8Array(bytes)].map(b => b.toString(16).padStart(2, '0')).join('');
async function proves(app, origin, nonce, proof) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(app.page.key), {name: 'HMAC', hash: 'SHA-256'}, false, ['sign']);
  return proof === hex(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${nonce}:${new URL(origin).port}`)));
}
window.addEventListener('message', async event => {
  const frame = $('page');
  if (event.source !== frame.contentWindow || event.origin !== frame.dataset.origin) return;
  const message = event.data || {};
  // Bound to the app and page that asked: if the sidebar moves to another app meanwhile, the answer is dropped.
  const app = apps.find(a => a.id === framed), origin = frame.dataset.origin, asker = framed;
  const answer = value => { if (framed === asker && frame.dataset.origin === origin) frame.contentWindow.postMessage({lamp: 'answer', id: message.id, ...value}, origin); };
  // The page says hello and gets a nonce; it shows the app's signature over it and its port, and only then is it
  // the app's page: another program that took one of the app's ports can't make that, and is passed over.
  if (message.lamp === 'alive') { if (frameReady) lastAlive = Date.now(); return; }
  // The page's colours for the strip above it: plain colours only (hex or rgb), each checked before it's used.
  if (message.lamp === 'look') {
    clearLook();
    const colour = value => typeof value === 'string' && /^(#[0-9a-f]{3,8}|rgba?\(\s*\d{1,3}(\.\d+)?%?\s*,\s*\d{1,3}(\.\d+)?%?\s*,\s*\d{1,3}(\.\d+)?%?\s*(,\s*[\d.]+\s*)?\))$/i.test(value.trim()) ? value.trim() : '';
    // The words' colours only with the background they were chosen for, and never on a see-through one.
    const bg = colour(message.bg);
    if (!bg || /^rgba\(.*,\s*0?\.\d+\s*\)$|^rgba\(.*,\s*0\s*\)$|^#([0-9a-f]{4}|[0-9a-f]{8})$/i.test(bg)) return;
    for (const name of ['bg', 'ink', 'muted', 'line', 'accent']) {
      const value = colour(message[name]);
      if (value) document.body.style.setProperty('--page-' + name, value);
    }
    return;
  }
  if (message.lamp === 'hello') {
    const nonce = crypto.randomUUID();
    nonces.add(nonce); if (nonces.size > 8) nonces.delete(nonces.values().next().value);
    return answer({nonce});
  }
  if (message.lamp === 'proof') {
    const nonce = String(message.nonce || ''), had = nonces.delete(nonce);   // each nonce is good for one try
    const ok = !!app && had && await proves(app, origin, nonce, String(message.proof || ''));
    // Only for the frame that asked: the sidebar may have moved to another address or app meanwhile.
    if (framed !== asker || frame.dataset.origin !== origin) return;
    if (!ok) { frameAsked = 0; return answer({}); }
    frameReady = true; delete opening[framed]; frame.hidden = false; note(info.moved ? 'This tab is on a new page. Click Lamp in Chrome’s toolbar to use it here.' : '');
    const reads = app.page.reads, name = app.name;
    $('consent-top').textContent = reads === 'selection' ? `Using a selection shares only that passage with ${name}.`
      : reads === 'page' ? `Using this page shares its text with ${name}.` : '';
    pageToken = crypto.randomUUID(); lastAlive = Date.now();
    answer({key: app.page.key, token: pageToken});
    return void deliverMenu();
  }
  if (message.lamp !== 'read' || !frameReady || !pageToken || message.token !== pageToken) return answer({error: 'Open the app’s sidebar again, then try again.'});
  const reads = app?.page?.reads;
  if (!reads) return answer({error: 'This sidebar doesn’t read pages.'});
  // A click in the frame counts here too (Chrome passes a click's activation up to the frames above it).
  // Refused, the sidebar takes focus back too, so the person's next click in the page arms a read.
  const chosen = menuRead && menuRead.token === pageToken && Date.now() < menuRead.until ? menuRead : null;
  menuRead = null;   // the item's one read, used or not, goes with the first read asked
  if (!chosen && (!navigator.userActivation.isActive || readSpent)) { takeFocusBack(); return answer({error: 'Reading the page needs a click.'}); }
  readSpent = true;
  try { answer({page: await call({op: 'page-read', scope: reads === 'selection' ? 'selection' : message.scope, ...(chosen ? {expect: chosen.url} : {})})}); } catch (e) { answer({error: e.message}); }
  finally { takeFocusBack(); }
});

chrome.storage.session.onChanged.addListener(changes => { if (changes[keys.tab]) void refresh(); });
call({op: 'tab-key'}).then(r => { tabKey = r.key; }).catch(() => {}).finally(() => { void refresh(); setInterval(refresh, 750); });
