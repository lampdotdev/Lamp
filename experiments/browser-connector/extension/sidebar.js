const $ = id => document.getElementById(id);
let selected = '', revision = '', appsKey = '', viewKey = '', busy = false, refreshing = false, transportProblem = false, context;
const windowID = chrome.windows.getCurrent().then(w => w.id);
async function call(body) { const r = await chrome.runtime.sendMessage(body); if (r?.error) throw new Error(r.error); return r; }
function error(e) { $('error').textContent = e.message; }
async function pageContext() {
  const windowId = await windowID;
  const [tab] = await chrome.tabs.query({active:true, windowId});
  context = tab && !tab.incognito && tab.url ? {windowId,tabId:tab.id,url:tab.url} : null;
  let site = '';
  try { const u = new URL(context?.url); if (['http:','https:'].includes(u.protocol)) site = u.host; } catch {}
  $('page').textContent = site || 'Click the Lamp toolbar button on a website to use it here.';
}
function render(state) {
  const s = state.surface, key = state.revision + ':' + state.busy;
  revision = state.revision;
  if (key === viewKey) return;
  viewKey = key;
  $('title').textContent = s.title; $('detail').textContent = s.detail;
  $('sections').replaceChildren(); $('fields').replaceChildren(); $('actions').replaceChildren();
  for (const section of s.sections) {
    const h = document.createElement('h2'), p = document.createElement('p');
    h.textContent = section.title; p.textContent = section.text; $('sections').append(h,p);
  }
  for (const field of s.fields) {
    const label = document.createElement('label'), input = document.createElement('input');
    label.textContent = field.label; input.value = field.value; input.dataset.field = field.id; input.maxLength = 4000;
    label.append(input); $('fields').append(label);
  }
  $('consent').textContent = s.actions.some(a => a.readsPage) ? 'Using this page shares its text with this app and its AI.' : '';
  for (const action of s.actions) {
    const button = document.createElement('button'); button.textContent = action.label;
    button.disabled = busy || state.busy || s.busy;
    button.onclick = () => act(action); $('actions').append(button);
  }
}
async function act(action) {
  if (busy) return;
  busy = true; $('error').textContent = '';
  const app = selected, rev = revision, current = context;
    const fields = Object.fromEntries([...$('fields').querySelectorAll('input')].map(e => [e.dataset.field,e.value]));
  for (const button of $('actions').children) button.disabled = true;
  try {
    // Called directly from the click, before any await, so Chrome retains the permission gesture.
    if (action.readsPage) {
      if (!current) throw new Error('Click Lamp on the website first.');
      const origin = new URL(current.url).origin;
      if (!await chrome.permissions.request({origins:[origin+'/*']})) throw new Error('The page was not shared.');
    }
    await call({op:'surface-action', app, revision:rev, id:crypto.randomUUID(), action:action.id, fields, ...current});
  } catch(e) { error(e); }
  finally { busy = false; viewKey = ''; await refresh(); }
}
async function refresh() {
  if (refreshing || busy) return; refreshing = true;
  try {
    await pageContext();
    const {apps} = await call({op:'surface-list'});
    const key = JSON.stringify(apps);
    if (key !== appsKey) {
      appsKey = key; $('chooser').replaceChildren();
      if (!apps.some(a => a.id === selected)) { selected = apps[0]?.id || ''; viewKey = ''; }
      if (apps.length > 1) {
        const menu = document.createElement('select'); menu.ariaLabel = 'Companion app';
        for (const app of apps) { const o = document.createElement('option'); o.value = app.id; o.textContent = app.name; menu.append(o); }
        menu.value = selected; menu.onchange = () => {selected = menu.value; viewKey = ''; void refresh();}; $('chooser').append(menu);
      } else if (apps.length) $('chooser').textContent = apps[0].name;
    }
    document.querySelector('main').hidden = !selected; $('empty').hidden = !!selected;
    if (selected) render(await call({op:'surface-view', app:selected}));
    if (transportProblem) { $('error').textContent = ''; transportProblem = false; }
  } catch(e) { document.querySelector('main').hidden = true; transportProblem = true; error(e); }
  finally { refreshing = false; }
}
void refresh(); setInterval(refresh,750);
