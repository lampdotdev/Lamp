(()=>{
 if(window.__lampTaskCapture)return;
 let id=null,site=null,banner=null,bar=null,clock=null,ticking=null,placing=null,paused=false,lastURL='',lastPage='';
 let lastClick=null,lastClickAt=0,typedIn=null,modalSeen=null,coveredBy=null,scannedAt=0,moved=0,scrollTimer=null,arrived=false;
 const scrolledTo=new WeakMap();
 const skipped='input,textarea,select,[contenteditable]:not([contenteditable="false"]),[data-private],[hidden],[aria-hidden="true"],script,style,noscript,iframe,template';
 const guarded='[data-private],[contenteditable]:not([contenteditable="false"])';
 // What a person works a page with. Sites build these from plain elements with a role as often as from the real thing.
 const controls='button,a[href],summary,select,option,input,label,[role="button"],[role="link"],[role="tab"],[role="checkbox"],[role="switch"],[role="radio"],[role="menuitem"],[role="menuitemcheckbox"],[role="menuitemradio"],[role="option"],[role="combobox"],[role="treeitem"],[aria-haspopup],[aria-expanded],[aria-pressed]';
 const secret=/password|secret|token|one.time.code/i;
 const address=()=>location.origin+location.pathname;
 const clean=(s,n)=>String(s||'').replace(/\s+/g,' ').trim().slice(0,n);
 // A component keeps its insides in a shadow root, where the page's own queries and text walks don't reach.
 const inside=el=>{try{return el.shadowRoot||globalThis.chrome?.dom?.openOrClosedShadowRoot?.(el)||null;}catch{return null;}};
 // An element with no box of its own (a slot, a wrapper) counts as hidden to the browser though what it holds is shown.
 const shown=el=>el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})||getComputedStyle(el).display==='contents';
 const elements=event=>event.composedPath().filter(n=>n.nodeType===1);
 // The words a person can see under root, through components and their slots; inView keeps to what is on screen.
 function words(root,max,inView){
  const parts=[];let length=0;
  (function walk(node){
   if(length>=max)return;
   if(node.nodeType===3){const s=clean(node.textContent,300);if(s){parts.push(s);length+=s.length+1;}return;}
   if(node.nodeType!==1&&node.nodeType!==11)return;
   if(node.nodeType===1){
    if(node===banner||node.matches(skipped)||!shown(node))return;
    if(inView){const r=node.getBoundingClientRect();if(r.width&&r.height&&(r.bottom<0||r.top>innerHeight||r.right<0||r.left>innerWidth))return;}
    if(node.localName==='slot'){const given=node.assignedNodes({flatten:true});if(given.length){given.forEach(walk);return;}}
   }
   // What a component is given to show comes through its slots, so its own children aren't walked a second time.
   for(const child of ((node.nodeType===1&&inside(node))||node).childNodes)walk(child);
  })(root);
  return parts.join('\n').slice(0,max);
 }
 function openDialog(){
  if(modalSeen?.isConnected&&modalSeen.matches(':modal'))return modalSeen;
  const el=document.querySelector('dialog[open],[role="dialog"],[aria-modal="true"]');
  return el&&shown(el)?el:null;
 }
 // A dialog over the page is what the person is looking at, so its words come first.
 function excerpt(inView){
  const main=document.querySelector('main,article,[role="main"]')||document.body,dialog=openDialog();
  if(!dialog)return words(main,1500,inView);
  const front=words(dialog,1000,inView);
  return (front+'\n'+words(main,1500-front.length,inView)).slice(0,1500);
 }
 function named(el){
  if(el.matches('input,select,textarea')){const label=el.labels?.[0];return clean(label?words(label,120):el.getAttribute('aria-label')||el.getAttribute('placeholder')||el.getAttribute('title')||'field',120);}
  const by=el.getAttribute('aria-labelledby');
  const told=by?by.split(/\s+/).map(i=>el.getRootNode().getElementById?.(i)).filter(Boolean).map(n=>words(n,120)).join(' '):'';
  return clean(el.getAttribute('aria-label')||told||words(el,120)||el.getAttribute('title')||el.querySelector('img[alt]')?.alt,120);
 }
 // Whether a switch or box is on: the setting, which the person chose by clicking, never anything typed. Whether a
 // menu is open isn't read: sites say so too late or not at all, and its name is enough.
 function setting(el){
  if(el.matches('input[type="checkbox"],input[type="radio"]'))return el.checked?'on':'off';
  for(const name of ['aria-checked','aria-pressed','aria-selected'])if(el.hasAttribute(name))return el.getAttribute(name)==='true'?'on':'off';
  return '';
 }
 function send(kind,label='',inView=false){
  if(!id||paused||location.origin!==site||document.visibilityState!=='visible'||!banner?.isConnected||!banner.checkVisibility({checkOpacity:true,checkVisibilityCSS:true}))return;
  const text=excerpt(inView);
  if(kind==='page'&&lastURL===address()&&lastPage===text)return;
  if(!inView){lastURL=address();lastPage=text;}
  chrome.runtime.sendMessage({op:'task-event',id,event:{kind,url:address(),title:clean(document.title,160),label:clean(label,120),excerpt:text}}).catch(()=>{});
 }
 function onClick(event){
  if(!event.isTrusted)return;
  // The path, not the target: from outside a component a click looks as if it landed on the component itself.
  const path=elements(event);
  if(path.includes(banner))return;
  const dialog=path.find(n=>n.localName==='dialog'&&n.matches(':modal'));if(dialog)modalSeen=dialog;
  setTimeout(place,60);
  if(path.some(n=>n.matches(guarded)))return;
  let el=path.slice(0,12).find(n=>n.matches(controls));if(!el)return;
  if(el.localName==='label'&&el.control)el=el.control;
  if(el.localName==='option')el=el.closest('select')||el;
  if(el.matches('input[type="password"]'))return;
  // A click on a box's label reaches the box as a second click.
  const now=Date.now();if(el===lastClick&&now-lastClickAt<300)return;lastClick=el;lastClickAt=now;typedIn=null;
  const label=named(el);if(secret.test(label))return;
  // A link may take the page away before a timer runs, so it is noted at once. What switches is read after the page has switched it.
  if(setting(el)==='')send('click',label);
  else setTimeout(()=>{const now=setting(el);send('click',now?`${label}: ${now}`:label);},200);
 }
 function field(event,kinds){
  if(!event.isTrusted)return null;
  const path=elements(event),el=path[0];
  if(!el?.matches(kinds)||el.matches('input[type="password"]')||path.includes(banner)||path.some(n=>n.matches(guarded)))return null;
  return el;
 }
 // "input", not "change": a change inside a component never leaves it.
 function onInput(event){
  const el=field(event,'input,select,textarea');
  if(!el||el.matches('input[type="checkbox"],input[type="radio"]'))return;
  const label=named(el);if(secret.test(label))return;
  if(el.localName==='select'){const chosen=clean(el.selectedOptions[0]?.textContent,80);send('change',chosen?`${label}: ${chosen}`:label);return;}
  // A field is noted once when it is typed in, by its name and never by what was typed.
  if(typedIn===el)return;typedIn=el;send('change',label);
 }
 // Return in a field is how most searches are sent. No other key is noted.
 function onKey(event){
  moved=Date.now();
  if(event.key!=='Enter'||event.isComposing)return;
  const el=field(event,'input:not([type="checkbox"],[type="radio"],[type="button"],[type="submit"],[type="reset"],[type="file"])');if(!el)return;
  const label=named(el);if(secret.test(label))return;
  send('key',`${label}: pressed Return`);
 }
 function travelled(kind,from,to){
  if(kind==='reload')return 'Reloaded the page';
  if(kind!=='traverse')return '';
  return from==null||to==null||from===to?'Went back or forward':to<from?'Went back':'Went forward';
 }
 // Back and Forward within one page (a site that swaps its own content). A new page says how it was reached in start.
 function onNavigate(event){
  if(event.navigationType!=='traverse'||!event.userInitiated||!event.destination.sameDocument)return;
  const label=travelled('traverse',navigation.currentEntry?.index,event.destination.index);
  setTimeout(()=>send('history',label),200);
 }
 function onShow(event){
  if(!event.persisted)return;
  const reached=globalThis.navigation?.activation;
  send('history',travelled(reached?.navigationType||'traverse',reached?.from?.index,navigation.currentEntry?.index));
 }
 // Only scrolling the person did: a page also scrolls itself, and that isn't a step of their task.
 const onMove=()=>{moved=Date.now();};
 function onScroll(event){
  if(Date.now()-moved>1500)return;
  const el=event.target===document?document.scrollingElement:event.target;
  if(el?.nodeType!==1||el.closest(guarded))return;
  clearTimeout(scrollTimer);scrollTimer=setTimeout(()=>rested(el),1200);
 }
 // Noted where the scrolling comes to rest, and only when it went half a screen or more: with it, what was then in view.
 function rested(el){
  if(!id||paused||!el.isConnected)return;
  const room=el.scrollHeight-el.clientHeight,was=scrolledTo.get(el)??0,now=el.scrollTop;
  if(room<=0||Math.abs(now-was)<el.clientHeight*0.5)return;
  scrolledTo.set(el,now);
  const where=now<=2?'the top':now>=room-2?'the end':`about ${Math.max(10,Math.min(90,Math.round(now/room*10)*10))}% of the way down`;
  send('scroll',`Scrolled ${now>was?'down':'up'} ${el===document.scrollingElement?'the page':'a list'}, to ${where}`,true);
 }
 function modalNow(){
  let n=document.activeElement;for(let root;n&&(root=inside(n))&&root.activeElement;)n=root.activeElement;
  for(;n;n=n.parentNode||n.host)if(n.localName==='dialog'&&n.matches(':modal'))return n;
  return modalSeen?.isConnected&&modalSeen.matches(':modal')?modalSeen:null;
 }
 function anyModal(){
  let found=null,seen=0;
  (function look(root){for(const el of root.querySelectorAll('*')){if(++seen>20000)return;if(el.localName==='dialog'&&el.matches(':modal'))found=el;const within=inside(el);if(within)look(within);}})(document);
  return found;
 }
 function inFront(){
  const r=banner.getBoundingClientRect();
  return banner.isConnected?banner.getRootNode().elementFromPoint?.(r.left+r.width/2,r.top+r.height/2)??banner:null;
 }
 const onTop=()=>inFront()===banner;
 // Keeps the bar in front and usable. It is shown in the browser's top layer, above whatever a page stacks. A
 // modal dialog blurs and switches off everything outside itself, top layer included, so while one is open the
 // bar is put inside that dialog, which is the one place the browser leaves usable, and taken out when it closes.
 function place(){
  if(!banner)return;
  let home=modalNow();
  if(!home&&!onTop()&&Date.now()-scannedAt>1000){scannedAt=Date.now();home=anyModal();}
  modalSeen=home;home||=document.documentElement;
  try{
   if(banner.parentNode!==home){if(banner.matches(':popover-open'))banner.hidePopover();home.append(banner);}
   if(!banner.matches(':popover-open'))banner.showPopover();
   // Something shown since is in front of it: showing the bar again puts it back on top. Once for each thing
   // found there, so the bar never flickers under something it can't get in front of.
   else{const over=inFront();if(over===banner)coveredBy=null;else if(over!==coveredBy){coveredBy=over;banner.hidePopover();banner.showPopover();}}
  }catch{}
 }
 const listeners=[['click',onClick],['input',onInput],['keydown',onKey],['scroll',onScroll],['wheel',onMove],['touchmove',onMove],['pointerdown',onMove]];
 function listen(on){
  for(const [name,handler] of listeners)document[on?'addEventListener':'removeEventListener'](name,handler,{capture:true,passive:true});
  window[on?'addEventListener':'removeEventListener']('pageshow',onShow);
  globalThis.navigation?.[on?'addEventListener':'removeEventListener']('navigate',onNavigate);
 }
 function stop(){id=null;paused=false;clearInterval(ticking);clearInterval(placing);clearTimeout(scrollTimer);banner?.remove();banner=null;modalSeen=null;listen(false);}
 // At the limit the bar stays, to ask, and the page is no longer watched.
 function pause(){
  if(!id||paused)return;
  paused=true;clearInterval(ticking);clearTimeout(scrollTimer);listen(false);
  draw();
 }
 function draw(){
  bar.replaceChildren();bar.className=paused?'bar paused':'bar';
  const dot=document.createElement('span'),said=document.createElement('b');dot.className='dot';
  said.textContent=paused?'Lamp paused. Nothing has been sent.':'Lamp is recording';bar.append(dot,said);
  if(!paused){clock=document.createElement('span');clock.className='clock';bar.append(clock);}
  for(const [text,kind,op] of [[paused?'Show Lamp':'Stop and Show Lamp','stop','task-stop'],['Discard','discard','task-discard']]){const button=document.createElement('button');button.textContent=text;button.className=kind;button.onclick=e=>{if(!e.isTrusted)return;chrome.runtime.sendMessage({op}).catch(()=>{});};bar.append(button);}
 }
 function start(next,origin,started,held){
  if(id===next&&banner?.isConnected){if(held)pause();return;}
  stop();if(location.origin!==origin)return;id=next;site=origin;lastURL='';lastPage='';paused=held===true;
  // The bar floats over the page instead of sitting on its first lines, in a closed shadow root so the
  // page's own styles can't hide or restyle it. Nothing is recorded while it isn't on screen (see send).
  banner=document.createElement('div');banner.id='lamp-task-indicator';banner.popover='manual';
  banner.style.cssText='all:initial;display:block;position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;pointer-events:auto';
  const root=banner.attachShadow({mode:'closed'});
  root.innerHTML=`<style>
   .bar{display:flex;align-items:center;gap:10px;padding:7px 8px 7px 14px;border-radius:999px;background:#17182b;color:white;font:13px/1.2 -apple-system,system-ui,sans-serif;box-shadow:0 6px 24px rgb(0 0 0/.28),0 0 0 1px rgb(255 255 255/.14);white-space:nowrap}
   .dot{width:9px;height:9px;border-radius:50%;background:#ff4b33;animation:pulse 1.6s ease-in-out infinite}
   .paused .dot{background:#ffb02e;animation:none}
   @keyframes pulse{50%{opacity:.55}}
   @media (prefers-reduced-motion:reduce){.dot{animation:none}}
   b{font-weight:600}
   .clock{font-variant-numeric:tabular-nums;opacity:.7;margin-right:4px}
   button{font:inherit;font-weight:600;border:0;border-radius:999px;padding:6px 12px;cursor:pointer}
   .stop{background:white;color:#17182b}
   .discard{background:rgb(255 255 255/.14);color:white}
   button:hover{filter:brightness(.92)}
   button:focus-visible{outline:2px solid #ff8a24;outline-offset:2px}
  </style><div class="bar" role="status"></div>`;
  bar=root.querySelector('.bar');draw();
  document.documentElement.append(banner);place();placing=setInterval(place,400);
  if(paused)return;
  const tick=()=>{const t=Math.max(0,Math.floor((Date.now()-started)/1000));clock.textContent=`${Math.floor(t/60)}:${String(t%60).padStart(2,'0')}`;};
  tick();ticking=setInterval(tick,1000);
  if(document.scrollingElement)scrolledTo.set(document.scrollingElement,document.scrollingElement.scrollTop);
  listen(true);
  // A page opened during the recording by Back, Forward or Reload says so, once, before what it shows.
  const reached=globalThis.navigation?.activation;
  if(!arrived&&reached&&performance.timeOrigin>=started){const how=travelled(reached.navigationType,reached.from?.index,navigation.currentEntry?.index);if(how)send('history',how);}
  arrived=true;send('page');
 }
 window.__lampTaskCapture={start,stop,pause};
 setInterval(()=>{if(id&&!paused)send('page');},5000);
})();
