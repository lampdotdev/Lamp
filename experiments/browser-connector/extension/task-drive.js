// Works a page for an app the person built from a task they showed Lamp: reads the page as a list of what can be
// used, and uses one thing at a time when Lamp says so. What may be done, and what waits for the person's OK, is
// decided in Lamp; nothing here decides it.
(()=>{
 if(window.__lampDrive)return;
 const {controls,clean,inside,shown,words,named,setting,makeBar}=window.__lampPage;
 const secret=/password|secret|token|one.time.code/i;
 const check=/human verification|verify (that )?you('| a)re (a )?human|are you a (robot|human)|captcha|unusual traffic|checking your browser/i;
 const ids=new WeakMap(),known=new Map();let held=null,count=0;
 // Everything a person could use under root, through components and their slots, in the order it is laid out.
 function gather(root){
  const found=[];
  (function look(node){
   if(found.length>=400)return;
   if(node.nodeType===1){
    if(node.id==='lamp-task-indicator'||node.matches('[hidden],[aria-hidden="true"],[inert],script,style,template,noscript')||!shown(node))return;
    const label=node.localName==='label';
    if(node.matches(controls+',textarea')&&!(label&&node.control)&&!node.disabled&&node.getAttribute('aria-disabled')!=='true'){
     found.push(node);if(!label)return;
    }
    if(node.localName==='slot'){const given=node.assignedNodes({flatten:true});if(given.length){given.forEach(look);return;}}
   }else if(node.nodeType!==11)return;
   for(const child of ((node.nodeType===1&&inside(node))||node).childNodes)look(child);
  })(root);
  return found;
 }
 function kind(el){
  if(el.localName==='textarea')return 'field';
  if(el.localName==='select')return 'menu';
  if(el.localName==='a')return 'link';
  if(el.localName==='input')return {checkbox:'box',radio:'radio',submit:'button',button:'button',image:'button',reset:'button'}[el.type]||'field';
  return {switch:'switch',checkbox:'box',menuitemcheckbox:'box',radio:'radio',menuitemradio:'radio',tab:'tab',option:'option',menuitem:'option',
          treeitem:'option',combobox:'menu',link:'link'}[el.getAttribute('role')]||'button';
 }
 // What Lamp needs to know about a control to decide whether using it only looks around or does something.
 function facts(el){
  let id=ids.get(el);if(!id){id='c'+(++count);ids.set(el,id);}
  known.set(id,new WeakRef(el));
  const form=el.form||el.closest('form'),name=named(el),r=el.getBoundingClientRect();
  return {id,kind:kind(el),name,state:setting(el),href:el.localName==='a'?el.href:'',
   submit:!!form&&el.matches('button:not([type="button"],[type="reset"]),input[type="submit"],input[type="image"]'),
   method:form?(form.getAttribute('method')||'get').toLowerCase():'',
   search:el.matches('input[type="search"],[role="searchbox"]')||!!el.closest('[role="search"],search')||(!!form&&/search/i.test(form.getAttribute('action')||'')),
   opener:['aria-haspopup','aria-expanded','aria-controls','popovertarget'].some(a=>el.hasAttribute(a)),
   password:el.matches('input[type="password"]')||secret.test(name),
   off:r.bottom<0||r.top>innerHeight};
 }
 function look(){
  const dialog=held?.modal||null,main=document.querySelector('main,article,[role="main"]')||document.body;
  // While a modal dialog is open the rest of the page can't be used, so it isn't offered.
  // What is on screen comes first, then the rest, so a page with many controls still offers the ones in view
  // and its page links further down.
  const all=gather(dialog||document.body).map(facts),list=[...all.filter(c=>!c.off),...all.filter(c=>c.off)].slice(0,220);
  // The text is what is in view, so scrolling brings the next part of a long list.
  const text=dialog?(words(dialog,2500,true)+'\n'+words(main,1500,true)).slice(0,4000):words(main,4000,true);
  const top=document.scrollingElement,room=top?top.scrollHeight-top.clientHeight:0;
  const frames='iframe[src*="recaptcha"],iframe[src*="hcaptcha"],iframe[src*="challenges.cloudflare"]';
  // A password field alone isn't a sign-in page (a sign-in box in a corner, a settings page): the page's own title
  // or address has to say it is one.
  const signIn=list.some(c=>c.kind==='field'&&c.password&&!c.off)&&/sign.?in|log.?in|login|signin/i.test(document.title+' '+location.pathname);
  const needs=check.test(document.title+' '+text.slice(0,600))||/verify|captcha|challenge/i.test(location.pathname)||[...document.querySelectorAll(frames)].some(shown)
   ?'check':signIn?'sign-in':'';
  return {url:location.origin+location.pathname+location.search,title:clean(document.title,160),dialog:!!dialog,needs,controls:list,text,
          scrolled:room>0?Math.round(top.scrollTop/room*100):100};
 }
 const wait=ms=>new Promise(done=>setTimeout(done,ms));
 async function act(step){
  if(step.op==='scroll'){
   const list=held?.modal&&[...held.modal.querySelectorAll('*')].find(el=>el.scrollHeight>el.clientHeight+40&&/auto|scroll/.test(getComputedStyle(el).overflowY));
   (list||window).scrollBy({top:(step.up?-1:1)*0.85*innerHeight,behavior:'instant'});return {done:true};
  }
  const el=known.get(step.id)?.deref();
  if(!el?.isConnected)return {gone:true};
  if(el.matches('input[type="password"]')||secret.test(named(el)))return {refused:'password'};
  // Shown before it happens, so the person watching can follow what the app is doing.
  el.scrollIntoView({block:'center',inline:'nearest',behavior:'instant'});
  const outline=el.style.outline,offset=el.style.outlineOffset;
  el.style.outline='3px solid #ff8a24';el.style.outlineOffset='2px';
  await wait(450);el.style.outline=outline;el.style.outlineOffset=offset;
  if(step.op==='click')el.click();
  else if(step.op==='type'){
   if(!el.matches('input,textarea'))return {refused:'not a field'};
   el.focus();
   // Through the element's own setter: a page that keeps its own copy of a field only hears a real change.
   Object.getOwnPropertyDescriptor(el.localName==='textarea'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype,'value').set.call(el,String(step.text||'').slice(0,2000));
   el.dispatchEvent(new InputEvent('input',{bubbles:true,composed:true,inputType:'insertText',data:step.text}));
   el.dispatchEvent(new Event('change',{bubbles:true}));
  }else if(step.op==='return'){
   const form=el.form||el.closest('form');
   if(form)form.requestSubmit();
   else for(const name of ['keydown','keypress','keyup'])el.dispatchEvent(new KeyboardEvent(name,{key:'Enter',code:'Enter',keyCode:13,which:13,bubbles:true,composed:true,cancelable:true}));
  }
  return {done:true};
 }
 // The bar says whose work this is and stops it in one click. When a page needs the person themselves (a human
 // check, a sign-in) it says so and waits for them.
 function bar(app,state,note){
  if(state==='off'){held?.remove();held=null;return;}
  held||=makeBar();const el=held.bar;
  el.replaceChildren();el.className=state==='person'?'bar paused':'bar working';
  const dot=document.createElement('span'),said=document.createElement('b');dot.className='dot';
  said.textContent=state==='person'?(note||'This page needs you.')+' Then press Continue.':`${app} is working here`;el.append(dot,said);
  if(state!=='person'&&note){const step=document.createElement('span');step.className='clock';step.textContent=note;el.append(step);}
  const buttons=state==='person'?[['Continue','stop','run-continue'],['Stop','discard','run-stop']]:[['Stop','stop','run-stop']];
  for(const [text,look,op] of buttons){const button=document.createElement('button');button.textContent=text;button.className=look;button.onclick=e=>{if(!e.isTrusted)return;chrome.runtime.sendMessage({op}).catch(()=>{});};el.append(button);}
  held.place();
 }
 window.__lampDrive={look,act,bar};
})();
