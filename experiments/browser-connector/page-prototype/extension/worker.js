// Prototype: the side panel is still the extension's own page, but most of it is an iframe of a page Lamp serves
// on this Mac. The click on the toolbar icon opens the panel for that tab and grants activeTab, as in the real
// extension; reading the page stays here, behind the panel's bridge, never in the app's page.
chrome.action.onClicked.addListener(tab => {
  chrome.sidePanel.setOptions({tabId: tab.id, path: `panel.html?tab=${tab.id}`, enabled: true});
  chrome.sidePanel.open({tabId: tab.id}).catch(() => {});
});

async function capture(tabId, scope) {
  const tab = await chrome.tabs.get(tabId);
  if (!tab.active) throw new Error('Open that tab to use this.');
  const target = {tabId};
  await chrome.scripting.executeScript({target, files: ['surface-capture.js']});
  const [read] = await chrome.scripting.executeScript({target, args: [scope], func: scope => {
    try { return globalThis.__lampCaptureSurface(scope); } catch (error) { return {url: location.href, error: error.message}; }
  }});
  if (read.result.error) throw new Error(read.result.error);
  return read.result;
}

// Only the extension's own panel asks; the app's page has no chrome.runtime and can only ask the panel.
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL('panel.html?'))) return;
  capture(Number(message.tab), message.scope === 'selection' ? 'selection' : 'page')
    .then(reply, error => reply({error: error.message.includes('activeTab') || error.message.includes('Cannot access')
      ? 'Click Lamp in Chrome’s toolbar, then try again.' : error.message}));
  return true;
});
