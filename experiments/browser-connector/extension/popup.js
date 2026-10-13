const $=id=>document.getElementById(id);
let requests=[],chosen,lastState="";
async function send(body){const value=await chrome.runtime.sendMessage(body);if(value.error)throw new Error(value.error);return value;}
function choose(){const next=requests.find(r=>r.id===$('destination').value);if(chosen?.id!==next?.id)$('openClosed').checked=false;chosen=next;$('consent').textContent=`Allow ${chosen.name} to read pages on ${chosen.origin} without asking each time? These prototype apps save text locally. Revoke access here at any time.`;}
async function refresh(){
  const state=await send({op:'status'});
  const current=JSON.stringify({requests:state.requests,grants:state.grants});
  if(current===lastState)return;
  lastState=current;requests=state.requests;
  $('destination').replaceChildren();
  for(const r of requests){const o=document.createElement('option');o.value=r.id;o.textContent=r.name;$('destination').append(o);}
  $('request').hidden=!requests.length;$('destination').hidden=requests.length<2;
  if(requests.length)choose();
  $('grants').replaceChildren();
  if(!state.grants.length)$('grants').textContent='No apps have standing access.';
  for(const g of state.grants){
    const row=document.createElement('div');row.className='grant';
    const label=document.createElement('p');label.textContent=`${g.name} · ${g.origin}\n${g.openClosed?'May open a background tab.':'Reads only an already open page.'}`;
    const button=document.createElement('button');button.textContent=`Revoke ${g.name}`;
    button.onclick=async()=>{try{await send({op:'revoke',grant:g.id});$('status').textContent=`Access revoked for ${g.name}. Saved copies in the app remain.`;await refresh();}catch(e){$('status').textContent=e.message;}};
    row.append(label,button);$('grants').append(row);
  }
}
$('destination').onchange=choose;
$('approve').onclick=async()=>{
  const request={...chosen}, openClosed=$('openClosed').checked;
  $('destination').disabled=true;$('openClosed').disabled=true;$('approve').disabled=true;
  try{
    // Invoke directly inside this click, before an async message can lose the user gesture.
    const granted=await chrome.permissions.request({origins:[request.origin+'/*']});
    if(!granted){$('status').textContent='Chrome permission declined. No app grant was created.';return;}
    await send({op:'grant',id:request.id,origin:request.origin,openClosed});
    $('status').textContent=`Approved ${request.name}. Future reads need no extension click.`;
    await refresh();
  }catch(e){$('status').textContent=e.message;}
  finally{$('destination').disabled=false;$('openClosed').disabled=false;$('approve').disabled=false;}
};
refresh().then(()=>{$('status').textContent=requests.length?'Choose the access you want to allow.':'Ask for access from a Lamp-made app.';}).catch(e=>{$('status').textContent=e.message;});
window.addEventListener('focus',()=>{refresh().catch(e=>{$('status').textContent=e.message;});});
document.addEventListener('visibilitychange',()=>{if(!document.hidden)refresh().catch(e=>{$('status').textContent=e.message;});});
