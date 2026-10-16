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
// The list is kept for when Lamp is closed: an app that serves its own page works while it's open, Lamp or not.
async function list() {
  let state;
  try { state = await native({op: 'surface-list'}); }
  catch (error) {
    const saved = (await chrome.storage.local.get('apps')).apps;
    if (!saved) throw error;
    return {apps: saved, lampClosed: true};
  }
  await chrome.storage.local.set({apps: state.apps});
  return state;
}

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
    const origin = (() => { try { return new URL(tab.url).origin; } catch { return ''; } })();
    await chrome.storage.session.set({['tab:' + tab.id]: {fitting: await fitting(tab, apps), site, origin, at: Date.now()}});
  })();
});
// A tab that moves to another site loses the click's access; its sidebar says to click Lamp again to use the new
// page. Chrome keeps the access while the tab stays on the same site (a reload, another page there), and once it's
// gone the tab's address isn't given to the extension at all.
chrome.tabs.onUpdated.addListener((tabId, change, tab) => {
  if (change.status !== 'loading') return;
  const key = 'tab:' + tabId;
  chrome.storage.session.get(key).then(saved => {
    const info = saved[key];
    if (!info || info.moved) return;
    const origin = (() => { try { return new URL(tab?.url).origin; } catch { return ''; } })();
    if (origin && origin === info.origin) return;
    chrome.storage.session.set({[key]: {...info, moved: true}});
  });
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
    // The name an app's page is told for this tab: opaque, the same for one tab in one run of this profile.
    if (message.op === 'tab-key') {
      const {profile, run} = await profileReady;
      const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${profile}:${run}:${tab}`)));
      return {key: 't' + [...digest.slice(0, 6)].map(b => b.toString(16).padStart(2, '0')).join('')};
    }
    // An app's own page asks for the page the person is on; the sidebar passes that on only right after a click.
    if (message.op === 'page-read') return capture(tab, message.scope === 'selection' ? 'selection' : 'page');
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
// An earlier version gave Chrome rules that lit the icon on matching pages, and Chrome keeps registered rules
// through an update and adds them back when the extension loads. They're taken out once here, which is all the
// declarativeContent permission is still for.
chrome.runtime.onInstalled.addListener(() => {
  chrome.declarativeContent?.onPageChanged.removeRules(undefined, () => void chrome.runtime.lastError);
  chrome.storage.local.remove('rulesKey');
  void hello();
});
// A connected native port keeps the worker alive, so Lamp hears from it every two seconds while Chrome is open.
setInterval(hello, 2000);
void hello();
