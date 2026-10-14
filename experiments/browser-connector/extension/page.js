// What Lamp's page scripts share: reading a page the way a person sees it, through components and their slots,
// and the bar Lamp shows on a page while it records there or works there.
(()=>{
 if(window.__lampPage)return;
 const mark='lamp-task-indicator';
 const skipped='input,textarea,select,[contenteditable]:not([contenteditable="false"]),[data-private],[hidden],[aria-hidden="true"],script,style,noscript,iframe,template';
 // What a person works a page with. Sites build these from plain elements with a role as often as from the real thing.
 const controls='button,a[href],summary,select,option,input,label,[role="button"],[role="link"],[role="tab"],[role="checkbox"],[role="switch"],[role="radio"],[role="menuitem"],[role="menuitemcheckbox"],[role="menuitemradio"],[role="option"],[role="combobox"],[role="treeitem"],[aria-haspopup],[aria-expanded],[aria-pressed]';
 const clean=(s,n)=>String(s||'').replace(/\s+/g,' ').trim().slice(0,n);
 // A component keeps its insides in a shadow root, where the page's own queries and text walks don't reach.
 const inside=el=>{try{return el.shadowRoot||globalThis.chrome?.dom?.openOrClosedShadowRoot?.(el)||null;}catch{return null;}};
 // An element with no box of its own (a slot, a wrapper) counts as hidden to the browser though what it holds is shown.
 const shown=el=>el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})||getComputedStyle(el).display==='contents';
 // The words a person can see under root, through components and their slots; inView keeps to what is on screen.
 function words(root,max,inView){
  const parts=[];let length=0;
  (function walk(node){
   if(length>=max)return;
   if(node.nodeType===3){const s=clean(node.textContent,300);if(s){parts.push(s);length+=s.length+1;}return;}
   if(node.nodeType!==1&&node.nodeType!==11)return;
   if(node.nodeType===1){
    if(node.id===mark||node.matches(skipped)||!shown(node))return;
    if(inView){const r=node.getBoundingClientRect();if(r.width&&r.height&&(r.bottom<0||r.top>innerHeight||r.right<0||r.left>innerWidth))return;}
    if(node.localName==='slot'){const given=node.assignedNodes({flatten:true});if(given.length){given.forEach(walk);return;}}
   }
   // What a component is given to show comes through its slots, so its own children aren't walked a second time.
   for(const child of ((node.nodeType===1&&inside(node))||node).childNodes)walk(child);
  })(root);
  return parts.join('\n').slice(0,max);
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
 // The bar floats over the page instead of sitting on its first lines, in a closed shadow root so the page's own
 // styles can't hide or restyle it. `seen` is how a script that noticed a modal dialog says so. `alive` is asked
 // as often as the bar is placed: a bar whose owner has moved on takes itself away, wherever it was put.
 function makeBar(alive=()=>true){
  const banner=document.createElement('div');banner.id=mark;banner.popover='manual';
  banner.style.cssText='all:initial;display:block;position:fixed;top:12px;left:50%;transform:translateX(-50%);z-index:2147483647;pointer-events:auto';
  const root=banner.attachShadow({mode:'closed'});
  root.innerHTML=`<style>
   .bar{display:flex;align-items:center;gap:10px;padding:7px 8px 7px 14px;border-radius:999px;background:#17182b;color:white;font:13px/1.2 -apple-system,system-ui,sans-serif;box-shadow:0 6px 24px rgb(0 0 0/.28),0 0 0 1px rgb(255 255 255/.14);white-space:nowrap}
   .dot{width:9px;height:9px;border-radius:50%;background:#ff4b33;animation:pulse 1.6s ease-in-out infinite}
   .paused .dot{background:#ffb02e;animation:none}
   .working .dot{background:#ff8a24}
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
  const bar=root.querySelector('.bar');
  let modalSeen=null,coveredBy=null,scannedAt=0;
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
   if(!alive()){clearInterval(placing);banner.remove();return;}
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
  let placing=null;
  document.documentElement.append(banner);place();placing=setInterval(place,400);
  return {banner,bar,place,seen(dialog){modalSeen=dialog;},get modal(){return modalSeen?.isConnected&&modalSeen.matches(':modal')?modalSeen:null;},
          remove(){clearInterval(placing);banner.remove();}};
 }
 window.__lampPage={skipped,controls,clean,inside,shown,words,named,setting,makeBar};
})();
