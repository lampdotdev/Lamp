// Carries out, in one visible tab, the steps Lamp asks for when an app built from a shown task runs. Lamp
// holds the task, the AI and every decision; this fetches one step at a time and reports what the page then shows.
let runBusy=false,runState=null,runAnswer=null;
const runReady=chrome.storage.session.get('runState').then(s=>{runState=s.runState||null;});
const runSleep=ms=>new Promise(done=>setTimeout(done,ms));
async function runLoaded(tabId){
 for(let i=0;i<50;i++){const tab=await chrome.tabs.get(tabId);if(tab.status==='complete')return tab;await runSleep(200);}
 return chrome.tabs.get(tabId);
}
async function runIn(tabId,func,args=[]){
 await chrome.scripting.executeScript({target:{tabId},files:['page.js','task-drive.js']});
 const [reply]=await chrome.scripting.executeScript({target:{tabId},func,args});
 return reply?.result;
}
async function runDo(step){
 if(!await chrome.permissions.contains({origins:[pattern(step.site)]}))return {problem:'permission'};
 if(step.op==='end'){
  if(runState?.run===step.run){await runIn(runState.tab,()=>window.__lampDrive.bar('','off')).catch(()=>{});runState=null;await chrome.storage.session.remove('runState');}
  return {done:true};
 }
 if(runState?.run!==step.run){
  // A tab of its own, in front: the person sees the app at work and their other tabs are left alone.
  const made=await chrome.tabs.create({url:new URL(step.start||'/',step.site+'/').origin===step.site?step.start:step.site+'/',active:true});
  runState={run:step.run,tab:made.id};await chrome.storage.session.set({runState});
 }
 let tab;
 try{tab=await runLoaded(runState.tab);}catch{return {problem:'closed'};}
 if(tab.incognito)return {problem:'closed'};
 if(step.op==='open'){
  if(new URL(step.url).origin!==step.site)return {problem:'outside'};
  await chrome.tabs.update(tab.id,{url:step.url});await runSleep(300);tab=await runLoaded(tab.id);
 }else if(step.op==='back'){
  await chrome.tabs.goBack(tab.id).catch(()=>{});await runSleep(400);tab=await runLoaded(tab.id);
 }
 // Somewhere this app may not go (a sign-in on another site, a redirect): Lamp can't show or do anything there.
 if(!tab.url||new URL(tab.url).origin!==step.site)return {problem:'outside',where:tab.url?new URL(tab.url).host:''};
 let did={};
 if(['click','type','return','scroll'].includes(step.op)){
  did=await runIn(tab.id,s=>window.__lampDrive.act(s),[step]);
  await runSleep(700);tab=await runLoaded(tab.id);
  if(!tab.url||new URL(tab.url).origin!==step.site)return {problem:'outside',where:tab.url?new URL(tab.url).host:''};
 }
 if(step.op==='wait'){
  // The page is the person's until they press Continue: a human check or a sign-in is theirs to do.
  await runIn(tab.id,(app,note)=>window.__lampDrive.bar(app,'person',note),[step.app,step.note]);
  runAnswer=null;
  let i=0;
  for(;i<step.seconds&&!runAnswer;i++){
   await runSleep(1000);
   const alive=await native({op:'runAlive',run:step.run}).catch(()=>({alive:true}));
   if(!alive.alive)runAnswer='stop';
  }
  if(runAnswer!=='continue')return {waited:runAnswer||'timeout',seconds:step.seconds,loops:i};
  tab=await runLoaded(tab.id);
  if(!tab.url||new URL(tab.url).origin!==step.site)return {problem:'outside',where:tab.url?new URL(tab.url).host:''};
 }
 await runIn(tab.id,(app,note)=>window.__lampDrive.bar(app,'working',note),[step.app,step.note]);
 return {...did,page:await runIn(tab.id,()=>window.__lampDrive.look())};
}
async function runPump(){
 await runReady;
 if(runBusy)return;
 runBusy=true;
 let quick=false;
 try{
  const next=await native({op:'runPoll'});
  quick=next.active===true;
  // Lamp has no run for this tab any more (it ended, or Lamp quit): the bar must not go on saying otherwise.
  if(!quick&&runState){await runIn(runState.tab,()=>window.__lampDrive.bar('','off')).catch(()=>{});runState=null;await chrome.storage.session.remove('runState');}
  if(next.step){
   let result;
   try{result=await runDo(next.step);}catch(e){result={problem:'failed',why:String(e?.message||e).slice(0,200)};}
   await native({op:'runResult',run:next.step.run,seq:next.step.seq,result});
  }
 }catch{}finally{runBusy=false;setTimeout(runPump,quick?150:1000);}
}
chrome.runtime.onMessage.addListener((msg,sender)=>{
 if(!['run-stop','run-continue'].includes(msg.op)||sender.id!==chrome.runtime.id||sender.frameId!==0||sender.tab?.id!==runState?.tab)return;
 if(msg.op==='run-continue'){runAnswer='continue';return;}
 runAnswer='stop';void native({op:'runStop',run:runState.run}).catch(()=>{});
});
runPump();
