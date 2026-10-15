// One generic sidebar where each Lamp app draws its own parts. Nothing here reads as the person browses: the toolbar
// icon looks the same on every page, and a page's text is read only when a sidebar button that reads it is clicked,
// with the access that click on the toolbar icon gave.
let port, outstanding, chain = Promise.resolve();
// Which Chrome profile this is, and which run of Chrome: tab ids start again after a restart, so the run keeps a new
// tab from being handed an old tab's draft.
const profileReady = (async () => {
  await chrome.storage.local.setAccessLevel({accessLevel: 'TRUSTED_CONTEXTS'});
  await chrome.storage.session.setAccessLevel({accessLevel: 'TRUSTED_CONTEXTS'});
  const saved = await chrome.storage.local.get('profile'), now = await chrome.storage.session.get('run');
  const profile = saved.profile || crypto.randomUUID(), run = now.run || crypto.randomUUID();
  if (!saved.profile) await chrome.storage.local.set({profile});
  if (!now.run) await chrome.storage.session.set({run});
  return {profile, run};
})();
function connect() {
  if (port) return;
  port = chrome.runtime.connectNative('dev.lamp.prototype');
  port.onMessage.addListener(value => {
    const pending = outstanding; outstanding = null;
    if (value.error) pending?.reject(new Error(value.error)); else pending?.resolve(value);
  });
  port.onDisconnect.addListener(() => {
    outstanding?.reject(new Error('Open Lamp on this Mac, then try again.')); outstanding = null; port = null;
  });
}
// One question to Lamp at a time: the native host answers in order and holds no queue of its own.
function native(body) {
  const next = chain.then(async () => {
    const {profile, run} = await profileReady;
    connect();
    return new Promise((resolve, reject) => { outstanding = {resolve, reject}; port.postMessage({...body, profile, run}); });
  });
  chain = next.catch(() => {});
  return next;
}

// What fits an app is what it declared to Lamp: sites (and a path) and CSS selectors, looked for when Lamp is clicked.
const siteFits = (fit, url) => url.protocol === 'https:' &&
  (!fit.site || url.hostname === fit.site || url.hostname.endsWith('.' + fit.site)) &&
  (!fit.path || url.pathname.startsWith(fit.path));
const list = () => native({op: 'surface-list'});

// Lamp counts the extension as connected while it hears from it.
async function hello() {
  try { await native({op: 'companion-hello', version: 3}); } catch {}
}

// Which apps fit the tab the person clicked Lamp on. The click gives access to that tab until it navigates;
// a declared selector is only asked about (is it there?), so nothing of the page leaves it here.
async function fitting(tab, apps) {
  let url; try { url = new URL(tab.url); } catch { return []; }
  const near = apps.filter(app => (app.fits || []).some(fit => siteFits(fit, url)));
  const selectors = [...new Set(near.flatMap(app => app.fits.filter(fit => fit.selector && siteFits(fit, url)).map(fit => fit.selector)))];
  const present = new Set();
  if (selectors.length) {
    try {
      const [found] = await chrome.scripting.executeScript({target: {tabId: tab.id}, args: [selectors],
        func: list => list.map(s => { try { return !!document.querySelector(s); } catch { return false; } })});
      selectors.forEach((s, i) => { if (found.result[i]) present.add(s); });
    } catch {}
  }
  // The app that named this site comes before one that only matched something common to many pages.
  const score = app => Math.max(...app.fits.filter(fit => siteFits(fit, url) && (!fit.selector || present.has(fit.selector)))
    .map(fit => (fit.site ? 4 : 0) + (fit.path ? 2 : 0) + (fit.selector ? 1 : 0)), -1);
  return near.map(app => [app, score(app)]).filter(([, s]) => s >= 0).sort((a, b) => b[1] - a[1]).map(([app]) => app.id);
}
chrome.action.onClicked.addListener(tab => {
  if (tab.incognito) return;
  // Opening has to happen inside the click, before anything is awaited, or Chrome refuses it.
  chrome.sidePanel.setOptions({tabId: tab.id, path: `sidebar.html?tab=${tab.id}`, enabled: true});
  chrome.sidePanel.open({tabId: tab.id}).catch(() => {});
  (async () => {
    const {apps} = await list().catch(() => ({apps: []}));
    const site = (() => { try { return new URL(tab.url).hostname; } catch { return ''; } })();
    await chrome.storage.session.set({['tab:' + tab.id]: {fitting: await fitting(tab, apps), site, at: Date.now()}});
  })();
});
// A tab that moves on loses the click's access; its sidebar says to click Lamp again to use the new page.
chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (change.status !== 'loading') return;
  const key = 'tab:' + tabId;
  chrome.storage.session.get(key).then(saved => { if (saved[key] && !saved[key].moved) chrome.storage.session.set({[key]: {...saved[key], moved: true}}); });
});
chrome.tabs.onRemoved.addListener(tabId => { chrome.storage.session.remove(['tab:' + tabId, 'draft:' + tabId, 'pick:' + tabId]); });

const CLICK_AGAIN = 'Click Lamp in Chrome’s toolbar, then try again.';
async function capture(tabId, scope) {
  const tab = await chrome.tabs.get(tabId).catch(() => null);
  if (!tab || !tab.active || tab.incognito) throw new Error('Open that tab to use this.');
  let url; try { url = new URL(tab.url); } catch { throw new Error(CLICK_AGAIN); }   // no address means no access
  if (url.protocol !== 'https:' || url.username || url.password) throw new Error('Open a website to use this.');
  const [metadata] = await chrome.scripting.executeScript({target: {tabId}, func: () => location.href}).catch(() => { throw new Error(CLICK_AGAIN); });
  if (metadata.result !== tab.url) throw new Error('The page changed. Try again.');
  const target = {tabId, documentIds: [metadata.documentId]};
  await chrome.scripting.executeScript({target, files: ['surface-capture.js']});
  const [read] = await chrome.scripting.executeScript({target, args: [scope], func: scope => {
    try { return globalThis.__lampCaptureSurface(scope); } catch (error) { return {url: location.href, error: error.message}; }
  }});
  const now = await chrome.tabs.get(tabId).catch(() => null);
  if (!now?.active || now.url !== tab.url || read.documentId !== metadata.documentId || read.result?.url !== tab.url) throw new Error('The page changed while it was read. Try again.');
  if (read.result.error) throw new Error(read.result.error);
  return read.result;
}

// Only the extension's own sidebar speaks to Lamp. Websites have no way in: there is no external or page listener.
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL('sidebar.html?'))) return;
  (async () => {
    const tab = Number(message.tab);
    if (message.op === 'surface-list') return list();
    if (message.op === 'surface-open') return native({op: 'surface-open', app: message.app});
    if (message.op === 'surface-view') return native({op: 'surface-view', app: message.app, tab});
    if (message.op !== 'surface-action') throw new Error('Unknown action.');
    const state = await native({op: 'surface-view', app: message.app, tab});
    const action = state.surface?.actions.find(a => a.id === message.action);
    if (!action || state.revision !== message.revision || state.busy || state.surface.busy) throw new Error('The app changed. Try again.');
    const request = {op: 'surface-action', app: message.app, tab, revision: message.revision, action: action.id, id: message.id, fields: message.fields};
    if (action.readsPage || action.readsSelection) request.page = await capture(tab, action.readsSelection ? 'selection' : 'page');
    return native(request);
  })().then(reply, error => reply({error: error.message}));
  return true;
});

chrome.alarms.create('hello', {periodInMinutes: 0.5});
chrome.alarms.onAlarm.addListener(() => { void hello(); });
chrome.runtime.onStartup.addListener(() => { void hello(); });
// The rules an earlier version gave Chrome would keep lighting its icon after an update, so they go.
chrome.runtime.onInstalled.addListener(() => { chrome.storage.local.remove('rulesKey'); void hello(); });
// A connected native port keeps the worker alive, so Lamp hears from it every two seconds while Chrome is open.
setInterval(hello, 2000);
void hello();
