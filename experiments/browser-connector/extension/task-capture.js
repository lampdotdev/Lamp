(()=>{
 if(window.__lampTaskCapture)return;
 const {controls,clean,shown,words,named,setting,makeBar}=window.__lampPage;
 let id=null,site=null,held=null,banner=null,bar=null,clock=null,ticking=null,paused=false,lastURL='',lastPage='';
 let lastClick=null,lastClickAt=0,typedIn=null,moved=0,scrollTimer=null,arrived=false;
 const scrolledTo=new WeakMap();
 const guarded='[data-private],[contenteditable]:not([contenteditable="false"])';
 const secret=/password|secret|token|one.time.code/i;
 const address=()=>location.origin+location.pathname;
 const elements=event=>event.composedPath().filter(n=>n.nodeType===1);
 function openDialog(){
  if(held?.modal)return held.modal;
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
  const dialog=path.find(n=>n.localName==='dialog'&&n.matches(':modal'));if(dialog)held?.seen(dialog);
  setTimeout(()=>held?.place(),60);
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
 const listeners=[['click',onClick],['input',onInput],['keydown',onKey],['scroll',onScroll],['wheel',onMove],['touchmove',onMove],['pointerdown',onMove]];
 function listen(on){
  for(const [name,handler] of listeners)document[on?'addEventListener':'removeEventListener'](name,handler,{capture:true,passive:true});
  window[on?'addEventListener':'removeEventListener']('pageshow',onShow);
  globalThis.navigation?.[on?'addEventListener':'removeEventListener']('navigate',onNavigate);
 }
 function stop(){id=null;paused=false;clearInterval(ticking);clearTimeout(scrollTimer);held?.remove();held=null;banner=null;listen(false);}
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
  // Nothing is recorded while the bar isn't on screen (see send).
  // While it is being made the bar has no owner to ask yet.
  let made=null;made=makeBar(()=>made===null||(id!==null&&held===made));held=made;banner=held.banner;bar=held.bar;draw();
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
 // A bar must never outlive its recording: one that missed being told (a stop that crossed a page loading) asks.
 setInterval(()=>{if(id)chrome.runtime.sendMessage({op:'task-alive',id}).then(r=>{if(r&&!r.alive)stop();}).catch(()=>{});},1000);
})();
