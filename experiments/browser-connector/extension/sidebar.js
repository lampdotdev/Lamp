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
    ({apps} = await call({op: 'surface-list'}));
    const app = choose();
    $('empty').hidden = apps.length > 0;
    if (transportProblem) { error(); transportProblem = false; }
    if (!app) { document.querySelector('main').hidden = true; note(''); return; }
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
chrome.storage.session.onChanged.addListener(changes => { if (changes[keys.tab]) void refresh(); });
void refresh(); setInterval(refresh, 750);
