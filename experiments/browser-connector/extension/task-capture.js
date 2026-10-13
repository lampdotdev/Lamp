(()=>{
 if(window.__lampTaskCapture)return;
 let id=null,site=null,banner=null,ticking=null,lastURL='',lastPage='';
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
 function stop(){id=null;clearInterval(ticking);banner?.remove();banner=null;document.removeEventListener('click',onClick,true);document.removeEventListener('change',onChange,true);}
 function start(next,origin,started){
  if(id===next&&banner?.isConnected)return;
  stop();if(location.origin!==origin)return;id=next;site=origin;lastURL='';lastPage='';
  // The bar floats over the page instead of sitting on its first lines, in a closed shadow root so the
  // page's own styles can't hide or restyle it. Nothing is recorded while it isn't on screen (see send).
  banner=document.createElement('div');banner.id='lamp-task-indicator';
  banner.style.cssText='all:initial;position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647';
  const root=banner.attachShadow({mode:'closed'});
  root.innerHTML=`<style>
   .bar{display:flex;align-items:center;gap:10px;padding:7px 8px 7px 14px;border-radius:999px;background:#17182b;color:white;font:13px/1.2 -apple-system,system-ui,sans-serif;box-shadow:0 6px 24px rgb(0 0 0/.28),0 0 0 1px rgb(255 255 255/.14);white-space:nowrap}
   .dot{width:9px;height:9px;border-radius:50%;background:#ff4b33;animation:pulse 1.6s ease-in-out infinite}
   @keyframes pulse{50%{opacity:.55}}
   @media (prefers-reduced-motion:reduce){.dot{animation:none}}
   b{font-weight:600}
   .clock{font-variant-numeric:tabular-nums;opacity:.7;margin-right:4px}
   button{font:inherit;font-weight:600;border:0;border-radius:999px;padding:6px 12px;cursor:pointer}
   .stop{background:white;color:#17182b}
   .discard{background:rgb(255 255 255/.14);color:white}
   button:hover{filter:brightness(.92)}
   button:focus-visible{outline:2px solid #ff8a24;outline-offset:2px}
  </style><div class="bar" role="status"><span class="dot"></span><b>Lamp is recording</b><span class="clock"></span></div>`;
  const bar=root.querySelector('.bar'),clock=root.querySelector('.clock');
  for(const [text,kind,op] of [['Stop and Show Lamp','stop','task-stop'],['Discard','discard','task-discard']]){const button=document.createElement('button');button.textContent=text;button.className=kind;button.onclick=e=>{if(!e.isTrusted)return;chrome.runtime.sendMessage({op}).catch(()=>{});};bar.append(button);}
  const tick=()=>{const t=Math.max(0,Math.floor((Date.now()-started)/1000));clock.textContent=`${Math.floor(t/60)}:${String(t%60).padStart(2,'0')}`;};
  tick();ticking=setInterval(tick,1000);
  document.documentElement.append(banner);document.addEventListener('click',onClick,true);document.addEventListener('change',onChange,true);send('page');
 }
 window.__lampTaskCapture={start,stop};
 setInterval(()=>{if(id)send('page');},5000);
})();
