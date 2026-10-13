(()=>{
 if(window.__lampTaskCapture)return;
 let id=null,site=null,banner=null,lastURL='',lastPage='';
 const privateSelector='input,textarea,select,[contenteditable]:not([contenteditable="false"]),[data-private],[hidden],[aria-hidden="true"],script,style,noscript,iframe';
 const address=()=>location.origin+location.pathname;
 const clean=(s,n)=>String(s||'').replace(/\s+/g,' ').trim().slice(0,n);
 function visibleText(root,max){
  const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);let node,parts=[],length=0;
  while((node=walker.nextNode())&&length<max){const el=node.parentElement;if(!el||el.closest(privateSelector)||el.closest('#lamp-task-indicator')||!el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true}))continue;const s=clean(node.textContent,300);if(s){parts.push(s);length+=s.length+1;}}
  return parts.join('\n').slice(0,max);
 }
 function excerpt(){return visibleText(document.querySelector('main,article,[role="main"]')||document.body,1500);}
 function fieldLabel(el){const label=el.labels?.[0];return label?visibleText(label,120):clean(el.getAttribute('aria-label')||'field',120);}
 function send(kind,label=''){
  if(!id||location.origin!==site||document.visibilityState!=='visible'||!banner?.isConnected||!banner.checkVisibility({checkOpacity:true,checkVisibilityCSS:true}))return;
  const text=excerpt();
  if(kind==='page'&&lastURL===address()&&lastPage===text)return;
  lastURL=address();lastPage=text;
  chrome.runtime.sendMessage({op:'task-event',id,event:{kind,url:address(),title:clean(document.title,160),label:clean(label,120),excerpt:text}}).catch(()=>{});
 }
 function onClick(event){if(!event.isTrusted)return;const el=event.target.closest('button,a,[role="button"],[role="tab"],input,select');if(!el||el.closest('#lamp-task-indicator')||el.closest('[data-private],[contenteditable]')||el.matches('input[type="password"]'))return;
  const label=el.matches('input,select')?fieldLabel(el):el.getAttribute('aria-label')||visibleText(el,120);
  if(/password|secret|token|one.time.code/i.test(label||''))return;send('click',label);
 }
 function onChange(event){if(!event.isTrusted)return;const el=event.target;if(!el.matches('input,select,textarea')||el.closest('[data-private]')||el.matches('input[type="password"]'))return;
  const label=fieldLabel(el);if(/password|secret|token|one.time.code/i.test(label))return;send('change',label);
 }
 function stop(){id=null;banner?.remove();banner=null;document.removeEventListener('click',onClick,true);document.removeEventListener('change',onChange,true);}
 function start(next,origin){
  if(id===next&&banner?.isConnected)return;
  stop();if(location.origin!==origin)return;id=next;site=origin;lastURL='';lastPage='';
  banner=document.createElement('div');banner.id='lamp-task-indicator';banner.style.cssText='position:fixed;top:0;left:0;right:0;z-index:2147483647;background:#982717;color:white;padding:8px 16px;font:14px system-ui;display:flex;align-items:center;gap:16px';
  const label=document.createElement('strong');label.textContent='Recording for Lamp · approved site';banner.append(label);
  for(const [text,op] of [['Stop and show Lamp','task-stop'],['Discard recording','task-discard']]){const button=document.createElement('button');button.textContent=text;button.style.cssText='font:14px system-ui;padding:5px 10px';button.onclick=e=>{if(!e.isTrusted)return;chrome.runtime.sendMessage({op}).catch(()=>{});};banner.append(button);}
  document.documentElement.append(banner);document.addEventListener('click',onClick,true);document.addEventListener('change',onChange,true);send('page');
 }
 window.__lampTaskCapture={start,stop};
 setInterval(()=>{if(id)send('page');},5000);
})();
