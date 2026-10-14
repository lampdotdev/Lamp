const $=id=>document.getElementById(id);
let here='',lastSites=null,problem='';
// A site as a person reads it in the address bar, without the scheme.
const plain=origin=>origin.replace(/^https?:\/\//,'');
async function call(body){const r=await chrome.runtime.sendMessage(body);if(r?.error)throw new Error(r.error);return r;}
function show(id){for(const s of ['closed','idle','recording','paused','waiting'])$(s).hidden=s!==id;}
function fail(e){problem=e.message;$('problem').textContent=problem;$('problem').hidden=false;}
function clear(){problem='';$('problem').hidden=true;}
function list(sites,users={}){
 const key=JSON.stringify([sites,users]);if(key===lastSites)return;lastSites=key;
 $('sites').replaceChildren();
 for(const site of sites){
  const row=document.createElement('label'),box=document.createElement('input'),name=document.createElement('span'),remove=document.createElement('button');
  // Only the site in front starts ticked: another site is watched because the person chose it for this recording.
  box.type='checkbox';box.value=site;box.checked=site===here||sites.length===1;box.onchange=choice;
  name.textContent=plain(site);remove.className='link';remove.textContent='Remove';
  remove.onclick=async e=>{e.preventDefault();clear();try{await call({op:'task-revoke',origin:site});await refresh();}catch(e){fail(e);}};
  row.append(box,name,remove);$('sites').append(row);
  // An app built from a task shown here may use the site for the person; removing the site ends that too.
  for(const app of users[site]||[]){const used=document.createElement('p');used.className='used';used.textContent=`${app} can use this site for you.`;$('sites').append(used);}
 }
 choice();
}
const chosen=()=>[...$('sites').querySelectorAll('input:checked')].map(x=>x.value);
async function choice(){
 const pinned=(await chrome.action.getUserSettings()).isOnToolbar;
 $('pin').hidden=pinned;$('start').hidden=!pinned||!chosen().length;
}
async function refresh(){
 let s;
 try{s=await call({op:'task-status'});}catch{show('closed');return;}
 if(s.active){
  const {taskRecording}=await chrome.storage.session.get('taskRecording');
  const clock=`${Math.floor(s.elapsed/60)}:${String(s.elapsed%60).padStart(2,'0')}`;
  if(s.paused){$('pausedClock').textContent=`at ${clock}`;show('paused');return;}
  $('clock').textContent=clock;
  $('watching').textContent=(taskRecording?.origins||[]).map(plain).join(' and ')||'this site';
  show('recording');return;
 }
 if(s.phase==='analyzing'||s.phase==='review'){
  $('waitingText').textContent=s.phase==='analyzing'?'Lamp is working out what you did. Switch to Lamp to see.':'Your steps are ready. Switch to Lamp to look them over.';
  show('waiting');return;
 }
 const approved=here&&s.sites.includes(here);
 $('ask').hidden=!here||approved;$('here').textContent=plain(here);
 $('elsewhere').hidden=!!here||s.sites.length>0;
 $('ready').hidden=!s.sites.length;$('lead').hidden=s.sites.length>0&&approved;
 list(s.sites,s.users);show('idle');
}
$('approveSite').onclick=async()=>{
 clear();
 // Asked inside this click, before anything is awaited. Chrome's question can close this window, so the
 // worker is told which site is being asked about and finishes the approval if this page is gone by then.
 const asked=chrome.permissions.request({origins:[here+'/*']});
 chrome.runtime.sendMessage({op:'task-asking',origin:here}).catch(()=>{});
 try{if(!await asked)throw new Error('Chrome didn’t allow that site, so nothing changed.');await call({op:'task-approve',origin:here});await refresh();}catch(e){fail(e);}
};
$('start').onclick=async()=>{clear();try{await call({op:'task-start',origins:chosen()});window.close();}catch(e){fail(e);}};
$('stop').onclick=async()=>{clear();try{await call({op:'task-stop'});window.close();}catch(e){fail(e);}};
$('discard').onclick=async()=>{clear();try{await call({op:'task-discard'});await refresh();}catch(e){fail(e);}};
// Paused, the same two choices: nothing was sent at the limit, so these clicks are the only way on.
$('show').onclick=$('stop').onclick;$('drop').onclick=$('discard').onclick;
(async()=>{
 const [tab]=await chrome.tabs.query({active:true,currentWindow:true});
 try{if(tab?.url&&/^https?:/.test(tab.url)&&!tab.incognito)here=new URL(tab.url).origin;}catch{}
 await refresh();setInterval(()=>refresh().catch(()=>{}),1000);
})();
