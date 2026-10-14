let taskAsking=null, taskRecording=null, taskBuffer=[], taskFlushPromise=null, taskSyncing=false, taskFinishing=false, taskChecks=new Set(), taskEnding=null;
const taskStateReady=chrome.storage.session.get('taskRecording').then(s=>{taskRecording=s.taskRecording||null;});
const taskURL=url=>{const u=new URL(url);return u.origin+u.pathname;};
async function taskStatus(){
 const s=await native({op:'taskStatus'});
 if(taskRecording && (!s.active || s.id!==taskRecording.id)){await taskClear();}
 else if(taskRecording&&s.paused)await taskPause();
 return s;
}
// Lamp says when a recording has reached its limit. It is kept as it is and nothing is sent: watching ends
// on every page, the bar and the badge say it is paused, and the popup comes forward to ask what to do.
async function taskPause(){
 if(!taskRecording||taskRecording.paused)return;
 taskRecording.paused=true;taskBuffer=[];
 await chrome.storage.session.set({taskRecording});
 await chrome.action.setBadgeBackgroundColor({color:'#b26a00'});
 await chrome.action.setBadgeText({text:'II'});
 await chrome.action.setTitle({title:'Lamp paused. Click to choose what to do.'});
 for(const tab of await chrome.tabs.query({})){if(tab.incognito||!tab.url||!/^https?:/.test(tab.url))continue;
  try{await chrome.scripting.executeScript({target:{tabId:tab.id},func:()=>{window.__lampTaskCapture?.pause();}});}catch{}
 }
 chrome.action.openPopup().catch(()=>{});
}
async function taskClear(){
 taskRecording=null;taskBuffer=[];
 await chrome.storage.session.remove('taskRecording');
 await chrome.action.setBadgeText({text:''});
 await chrome.action.setTitle({title:'Lamp'});
 for(const tab of await chrome.tabs.query({})){if(tab.incognito||!tab.url||!/^https?:/.test(tab.url))continue;
  try{await chrome.scripting.executeScript({target:{tabId:tab.id},func:()=>{window.__lampTaskCapture?.stop();}});}catch{}
 }
}
function taskFlush(){
 if(taskFlushPromise)return taskFlushPromise;
 if(!taskRecording||taskRecording.paused||!taskBuffer.length)return Promise.resolve();
 const session=taskRecording,epoch=permissionEpoch,batch=taskBuffer.splice(0,30);
 taskFlushPromise=(async()=>{
  try{
   const kept=await native({op:'taskEvents',id:session.id,events:batch},()=>taskRecording?.id===session.id&&epoch===permissionEpoch);
   if(kept.paused&&taskRecording?.id===session.id)await taskPause();
  }
  catch{if(taskRecording?.id===session.id){await native({op:'taskDiscard',id:session.id}).catch(()=>{});await taskClear();}}
  finally{taskFlushPromise=null;}
 })();
 return taskFlushPromise;
}
async function taskFinish(discard){
 await taskStateReady;
 if(discard&&taskFinishing&&taskEnding){
  const ending=taskEnding;ending.discarded=true;
  await taskClear();await native({op:'taskDiscard',id:ending.id});return;
 }
 if(!taskRecording)throw new Error('Nothing is recording. If a task is waiting, switch to Lamp.');
 if(taskFinishing)throw new Error('The recording is already stopping.');
 taskFinishing=true;const session=taskRecording,epoch=permissionEpoch;taskEnding=session;
 try{
  // Block new observations at once, but retain the identity while Stop drains already-observed events.
  if(!discard){
   await Promise.allSettled([...taskChecks]);
   if(taskFlushPromise)await taskFlushPromise;
   if(taskRecording?.id!==session.id)throw new Error('The recording was interrupted.');
   await taskFlush();
  }
  await taskClear();
  await native({op:discard?'taskDiscard':'taskStop',id:session.id},()=>discard||(!session.discarded&&epoch===permissionEpoch));
 }finally{taskFinishing=false;taskEnding=null;}
}
async function taskInject(tab){
 if(!taskRecording||tab.incognito||!tab.url||!/^https?:/.test(tab.url))return;
 const site=new URL(tab.url).origin;
 if(!taskRecording.origins.includes(site)||!await chrome.permissions.contains({origins:[pattern(site)]}))return;
 await chrome.scripting.executeScript({target:{tabId:tab.id},files:['task-capture.js']});
 await chrome.scripting.executeScript({target:{tabId:tab.id},args:[taskRecording.id,site,taskRecording.started,taskRecording.paused===true],func:(id,site,started,paused)=>window.__lampTaskCapture?.start(id,site,started,paused)});
}
async function taskSync(){
 await taskStateReady;
 if(!taskRecording||taskSyncing||taskFinishing)return;
 taskSyncing=true;
 try{
  if(!(await chrome.action.getUserSettings()).isOnToolbar){await taskFinish(true);return;}
  for(const site of taskRecording.origins)if(!await chrome.permissions.contains({origins:[pattern(site)]})){await native({op:'taskRevoke',origin:site});await taskFinish(true);return;}
  await taskStatus();
  if(taskRecording)for(const tab of await chrome.tabs.query({}))await taskInject(tab).catch(()=>{});
  await taskFlush();
 }finally{taskSyncing=false;}
}
chrome.runtime.onMessage.addListener((msg,sender,reply)=>{
 const fromUI=sender.id===chrome.runtime.id&&sender.url===chrome.runtime.getURL('recorder.html');
 const fromPage=sender.id===chrome.runtime.id&&sender.frameId===0&&sender.tab&&!sender.tab.incognito&&taskRecording&&
   taskRecording.origins.includes(sender.origin||new URL(sender.url).origin);
 if(msg.op==='task-event'){
  if(!fromPage||taskFinishing||taskRecording.paused||msg.id!==taskRecording.id||taskBuffer.length>=30)return;
  const site=sender.origin||new URL(sender.url).origin;
  if(new URL(msg.event.url).origin!==site||!taskRecording.origins.includes(site))return;
  // Verify persistent browser permission again before admitting the event to the local buffer.
  const id=taskRecording.id;
  const check=chrome.permissions.contains({origins:[pattern(site)]}).then(ok=>{if(ok&&taskRecording?.id===id&&taskBuffer.length<30)taskBuffer.push(msg.event);});
  taskChecks.add(check);check.finally(()=>taskChecks.delete(check));
  return;
 }
 if(!fromUI&&!(fromPage&&['task-stop','task-discard'].includes(msg.op)))return;
 (async()=>{
  await taskStateReady;
  if(msg.op==='task-status')return taskStatus();
  if(msg.op==='task-asking'){taskAsking={origin:msg.origin,until:Date.now()+120000};return {};}
  if(msg.op==='task-approve'){
   if(!await chrome.permissions.contains({origins:[pattern(msg.origin)]}))throw new Error('Chrome hasn’t allowed that site yet.');
   return native({op:'taskApprove',origin:msg.origin});
  }
  if(msg.op==='task-revoke'){
   const result=await native({op:'taskRevoke',origin:msg.origin});
   // Removing a site takes Chrome's permission with it, unless an app the person approved still reads that site.
   if(!(await status()).grants.some(g=>g.origin===msg.origin))await chrome.permissions.remove({origins:[pattern(msg.origin)]});
   return result;
  }
  if(msg.op==='task-start'){
   const setting=await chrome.action.getUserSettings();
   if(!setting.isOnToolbar)throw new Error('Pin Lamp to Chrome’s toolbar first, so you can always see when it’s recording.');
   const allowed=await taskStatus();
   if(!msg.origins?.length||!msg.origins.every(x=>allowed.sites.includes(x)))throw new Error('Choose at least one site for Lamp to watch.');
   for(const site of msg.origins)if(!await chrome.permissions.contains({origins:[pattern(site)]}))throw new Error('Chrome no longer allows Lamp on that site. Allow it again.');
   const result=await native({op:'taskStart',origins:msg.origins});
   taskRecording={id:result.id,origins:msg.origins,started:Date.now()};
   await chrome.storage.session.set({taskRecording});
   await chrome.action.setBadgeBackgroundColor({color:'#b42916'});
   await chrome.action.setBadgeText({text:'REC'});
   await chrome.action.setTitle({title:'Lamp is recording. Click to stop or discard.'});
   await taskSync();return result;
  }
  if(msg.op==='task-stop'){await taskFinish(false);return {stopped:true};}
  if(msg.op==='task-discard'){await taskFinish(true);return {discarded:true};}
  throw new Error('Unknown task action.');
 })().then(reply,e=>reply({error:e.message}));return true;
});
chrome.tabs.onUpdated.addListener((id,change,tab)=>{if(change.status==='complete')void taskInject(tab).catch(()=>{});});
chrome.permissions.onRemoved.addListener(()=>{const session=taskRecording||taskEnding;if(session)void(async()=>{await taskClear();await native({op:'taskDiscard',id:session.id}).catch(()=>{});})();});
setInterval(()=>taskSync().catch(()=>{}),1000);
// Chrome's own question can close the window that asked, taking the rest of the approval with it. The site
// the person was asked about is finished here, and the window is brought back to show what happens next.
chrome.permissions.onAdded.addListener(added=>{
 const asking=taskAsking;taskAsking=null;
 if(!asking||Date.now()>asking.until||!(added.origins||[]).includes(pattern(asking.origin)))return;
 void native({op:'taskApprove',origin:asking.origin}).then(()=>chrome.action.openPopup()).catch(()=>{});
});
