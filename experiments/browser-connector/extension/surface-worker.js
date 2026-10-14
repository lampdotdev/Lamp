// Only the extension's own sidebar can request a companion action. Websites never speak this protocol.
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL('sidebar.html')) return;
  (async () => {
    if (message.op === 'surface-list' || message.op === 'surface-view') return native(message);
    if (message.op !== 'surface-action') throw new Error('Unknown companion action.');
    const state = await native({op:'surface-view', app:message.app});
    const action = state.surface.actions.find(a => a.id === message.action);
    if (!action || state.revision !== message.revision || state.busy || state.surface.busy) throw new Error('The app changed. Try again.');
    const request = {op:'surface-action', app:message.app, revision:message.revision,
      action:action.id, id:message.id, fields:message.fields};
    if (action.readsPage) {
      const epoch = permissionEpoch;
      const [tab] = await chrome.tabs.query({active:true, windowId:message.windowId});
      if (!tab || tab.incognito || !tab.url || tab.id !== message.tabId || tab.url !== message.url) throw new Error('The page changed. Try again.');
      const url = new URL(tab.url);
      if (url.username || url.password || !(url.protocol === 'https:' || (url.protocol === 'http:' && ['localhost','127.0.0.1'].includes(url.hostname)))) throw new Error('Open a website to use this action.');
      if (!await chrome.permissions.contains({origins:[pattern(url.origin)]})) throw new Error('Allow this site in Chrome first.');
      const [metadata] = await chrome.scripting.executeScript({target:{tabId:tab.id}, func:() => location.href});
      if (metadata.result !== tab.url) throw new Error('The page changed. Try again.');
      const [capture] = await chrome.scripting.executeScript({target:{tabId:tab.id, documentIds:[metadata.documentId]}, files:['surface-capture.js']});
      const [current] = await chrome.tabs.query({active:true, windowId:message.windowId});
      if (epoch !== permissionEpoch || current?.id !== tab.id || current?.url !== tab.url ||
          capture.documentId !== metadata.documentId || capture.result?.url !== tab.url) throw new Error('The page changed during reading. Try again.');
      request.page = capture.result;
      return native(request, () => epoch === permissionEpoch);
    }
    return native(request);
  })().then(reply, error => reply({error:error.message}));
  return true;
});
