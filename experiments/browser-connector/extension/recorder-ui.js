const $=id=>document.getElementById(id);
let lastSites='',uiError='';
async function call(body){const r=await chrome.runtime.sendMessage(body);if(r?.error)throw new Error(r.error);return r;}
async function refresh(){
 const s=await call({op:'task-status'});
 if(!$('site').value){const candidate=await chrome.storage.session.get('taskCandidate');$('site').value=candidate.taskCandidate||'';}
 const key=JSON.stringify(s.sites);
 if(key!==lastSites){lastSites=key;$('sites').replaceChildren();for(const site of s.sites){const row=document.createElement('label'),box=document.createElement('input');box.type='checkbox';box.checked=true;box.value=site;row.append(box,document.createTextNode(site));const revoke=document.createElement('button');revoke.textContent='Remove site';revoke.onclick=async()=>{await call({op:'task-revoke',origin:site});await refresh();};row.append(revoke);$('sites').append(row);}}
 $('start').hidden=s.active;$('stop').hidden=!s.active;$('discard').hidden=!s.active;
 $('status').textContent=uiError||(s.active?`Recording is on · ${Math.floor(s.elapsed/60)}:${String(s.elapsed%60).padStart(2,'0')} · ${s.count} events · Stop or discard at any time.`:s.phase==='analyzing'?'Stopped. Lamp is understanding the task.':'Recording is off.');
}
$('approveSite').onclick=async()=>{uiError='';try{const origin=new URL($('site').value).origin;const granted=await chrome.permissions.request({origins:[origin+'/*']});if(!granted)throw new Error('Site permission declined.');await call({op:'task-approve',origin});await refresh();}catch(e){uiError=e.message;$('status').textContent=e.message;}};
$('start').onclick=async()=>{uiError='';try{const origins=[...$('sites').querySelectorAll('input:checked')].map(x=>x.value);await call({op:'task-start',origins});await refresh();}catch(e){uiError=e.message;$('status').textContent=e.message;}};
$('stop').onclick=async()=>{uiError='';try{await call({op:'task-stop'});await refresh();}catch(e){uiError=e.message;$('status').textContent=e.message;}};
$('discard').onclick=async()=>{uiError='';try{await call({op:'task-discard'});await refresh();}catch(e){uiError=e.message;$('status').textContent=e.message;}};
chrome.storage.session.get('taskCandidate').then(s=>{$('site').value=s.taskCandidate||'';});
refresh().catch(e=>{$('status').textContent=e.message;});
setInterval(()=>refresh().catch(()=>{}),1000);
