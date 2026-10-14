let port, outstanding, chain = Promise.resolve(), pumping = false, permissionEpoch = 0;
const profileReady = (async () => {
  const saved = await chrome.storage.local.get('profile');
  const profile = saved.profile || crypto.randomUUID();
  if (!saved.profile) await chrome.storage.local.set({profile});
  await chrome.storage.local.setAccessLevel({accessLevel:'TRUSTED_CONTEXTS'});
  return profile;
})();
function connect() {
  if (port) return;
  port = chrome.runtime.connectNative('dev.lamp.prototype');
  port.onMessage.addListener(value => {
    const pending = outstanding; outstanding = null;
    if (value.error) pending?.reject(new Error(value.error)); else pending?.resolve(value);
  });
  port.onDisconnect.addListener(() => {
    const error = new Error(chrome.runtime.lastError?.message || 'Lamp disconnected.');
    outstanding?.reject(error); outstanding = null; port = null;
  });
}
function native(body, stillValid = () => true) {
  const next = chain.then(async () => {
    const profile = await profileReady;
    connect();
    if (!stillValid()) throw new Error('Site permission changed during this read.');
    return new Promise((resolve,reject) => { outstanding={resolve,reject}; port.postMessage({...body,profile}); });
  });
  chain = next.catch(() => {});
  return next;
}
const pattern = origin => origin + '/*';
async function status() {
  const state = await native({op:'list'});
  const removed=[];
  for (const g of state.grants) if (!await chrome.permissions.contains({origins:[pattern(g.origin)]})) removed.push(g.id);
  if (removed.length) { await native({op:'permissionRemoved',grants:removed}); return native({op:'list'}); }
  return state;
}
async function allowed(job) {
  const state=await status();
  if (!state.grants.some(g=>g.id===job.grant && g.app===job.app && g.origin===job.origin)) throw new Error('Access was revoked.');
}
async function read(job) {
  const epoch = permissionEpoch;
  try {
    await allowed(job);
    let tabs=(await chrome.tabs.query({})).filter(t=>t.url===job.url && !t.incognito);
    if (tabs.length>1) throw new Error('More than one matching page is open. Close the extra tabs.');
    let tab=tabs[0];
    if (!tab) {
      if (!job.openClosed) throw new Error('That page is closed. Open it in Chrome, or approve opening a background tab.');
      tab=await chrome.tabs.create({url:job.url,active:false});
    }
    const deadline=Date.now()+10000;
    while ((tab=await chrome.tabs.get(tab.id)).status!=='complete') {
      if (Date.now()>deadline) throw new Error('The page took too long to load.');
      await new Promise(r=>setTimeout(r,100));
    }
    if (tab.url!==job.url || new URL(tab.url).origin!==job.origin) throw new Error('The page moved to another address.');
    await allowed(job);
    const [metadata]=await chrome.scripting.executeScript({target:{tabId:tab.id},func:()=>location.href});
    if (metadata.result!==job.url) throw new Error('The page changed before reading.');
    const [capture]=await chrome.scripting.executeScript({target:{tabId:tab.id,documentIds:[metadata.documentId]},args:[job.url],func:expected=>{
      // Check inside the document before touching its text, including same-document navigation.
      if (location.href!==expected) throw new Error('The page changed before reading.');
      const readText=root=>{
        const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
        const parts=[];let n,count=0;
        while ((n=walker.nextNode()) && count<24000) {
          const el=n.parentElement;
          if (!el || el.closest('input,textarea,select,script,style,noscript,iframe,[contenteditable]:not([contenteditable="false"]),[hidden],[aria-hidden="true"]')) continue;
          if (!el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})) continue;
          const text=n.textContent.replace(/\s+/g,' ').trim();
          if (text) {parts.push(text);count+=text.length+1;}
        }
        return parts.join('\n').slice(0,24000);
      };
      const main=document.querySelector('main,article,[role="main"]');
      let text=readText(main||document.body);
      if (main && text.length<500) text=readText(document.body);
      return {url:location.href,title:document.title.slice(0,1000),text};
    }});
    if (capture.documentId!==metadata.documentId || capture.result.url!==job.url) throw new Error('The page changed during reading.');
    await allowed(job);
    await native({op:'deliver',...job,page:capture.result}, () => epoch === permissionEpoch);
    await chrome.storage.local.set({lastRead:{app:job.app,url:job.url,at:new Date().toISOString(),background:!tab.active}});
  } catch(error) { await native({op:'failure',...job,error:error.message}).catch(()=>{}); }
}
async function pump() {
  if (pumping) return;
  pumping=true;
  try {
    await status();
    const state=await native({op:'poll'});
    for (const job of state.jobs) await read(job);
  } catch {} finally {pumping=false;}
}
chrome.runtime.onMessage.addListener((message,sender,reply)=>{
  if (sender.id!==chrome.runtime.id || !['access.html','inspect.html'].some(p=>sender.url===chrome.runtime.getURL(p))) return;
  (async()=>{
    if (message.op==='status') return status();
    if (message.op==='grant') {
      const state=await status(), req=state.requests.find(r=>r.id===message.id);
      if (!req || req.origin!==message.origin || !await chrome.permissions.contains({origins:[pattern(req.origin)]})) throw new Error('Allow this site in Chrome first.');
      return native({op:'grant',id:req.id,url:req.url,origin:req.origin,openClosed:message.openClosed===true});
    }
    if (message.op==='revoke') {
      const state=await status(), grant=state.grants.find(g=>g.id===message.grant);
      if (!grant) throw new Error('That grant has already ended.');
      await native({op:'revoke',grant:grant.id});
      const after=await status();
      if (!after.grants.some(g=>g.origin===grant.origin)) await chrome.permissions.remove({origins:[pattern(grant.origin)]});
      return {revoked:true};
    }
    throw new Error('Unknown action.');
  })().then(reply,error=>reply({error:error.message}));
  return true;
});
chrome.permissions.onRemoved.addListener(()=>{permissionEpoch++;void status().catch(()=>{});});
chrome.runtime.onInstalled.addListener(()=>{void pump();});
chrome.runtime.onStartup.addListener(()=>{void pump();});
chrome.alarms.onAlarm.addListener(()=>{void pump();});
chrome.alarms.create('reconnect',{periodInMinutes:0.5});
// A native port keeps MV3 alive through Chrome's documented native-messaging lifetime rule.
setInterval(pump,1000);
void pump();

importScripts('recorder-worker.js');
importScripts('run-worker.js');

importScripts('surface-worker.js');

// Connection readiness is independent of long-running page reads.
const companionHello = () => native({op:'companion-hello',version:1}).catch(() => {});
setInterval(companionHello, 2000);
void companionHello();
