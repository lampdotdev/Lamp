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
  const app = apps.find(a => a.id === selected);
  $('offer').textContent = app && fitting.includes(app.id) ? app.offer : '';
  $('offer').hidden = !$('offer').textContent;
  return app;
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
    if (app.page?.url) return showPage(app);
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
let lampClosed = false, framed = '', frameReady = false, frameAsked = 0, tabKey = '';
function showPage(app) {
  const frame = $('page');
  document.body.classList.toggle('framed', !!app);
  if (!app) { if (framed) { frame.src = 'about:blank'; framed = ''; } frame.hidden = true; return; }
  document.querySelector('main').hidden = true;
  const now = Date.now();
  // Not answering: tried again every few seconds, so the page shows once the app is open.
  if (framed !== app.id || (!frameReady && now - frameAsked > 5000)) {
    if (framed !== app.id) frameReady = false;
    framed = app.id; frameAsked = now;
    frame.dataset.origin = new URL(app.page.url).origin;
    frame.src = app.page.url + '#' + new URLSearchParams({key: app.page.key, tab: tabKey}).toString();
  }
  if (frameReady) { frame.hidden = false; note(info.moved ? 'This tab is on a new page. Click Lamp in Chrome’s toolbar to use it here.' : ''); return; }
  frame.hidden = true;
  if (now - frameAsked < 2500 && !opening[app.id]) return;
  if (!lampClosed) opening[app.id] ??= {at: now, asked: call({op: 'surface-open', app: app.id}).catch(() => {})};
  note(lampClosed || (opening[app.id] && now - opening[app.id].at > 30000) ? `Open ${app.name} on your Mac to use it here.` : `Opening ${app.name}…`);
}
window.addEventListener('message', async event => {
  const frame = $('page');
  if (event.source !== frame.contentWindow || event.origin !== frame.dataset.origin) return;
  const message = event.data || {};
  const answer = value => frame.contentWindow.postMessage({lamp: 'answer', id: message.id, ...value}, frame.dataset.origin);
  if (message.lamp === 'hello') {
    frameReady = true; delete opening[framed]; frame.hidden = false; note(info.moved ? 'This tab is on a new page. Click Lamp in Chrome’s toolbar to use it here.' : '');
    const name = apps.find(a => a.id === framed)?.name || 'this app';
    $('consent-top').textContent = message.reads === 'selection' ? `Using a selection shares only that passage with ${name}.`
      : message.reads ? `Using this page shares its text with ${name}.` : '';
    return answer({});
  }
  if (message.lamp !== 'read') return;
  // A click in the frame counts here too (Chrome passes a click's activation up to the frames above it): the page
  // can read only right after the person clicked something, never by itself.
  if (!navigator.userActivation.isActive) return answer({error: 'Reading the page needs a click.'});
  try { answer({page: await call({op: 'page-read', scope: message.scope})}); } catch (e) { answer({error: e.message}); }
});

chrome.storage.session.onChanged.addListener(changes => { if (changes[keys.tab]) void refresh(); });
call({op: 'tab-key'}).then(r => { tabKey = r.key; }).catch(() => {}).finally(() => { void refresh(); setInterval(refresh, 750); });
