(() => {
  const root = document.querySelector('main,article,[role="main"]') || document.body;
  const walk = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node, size = 0; const parts = [];
  while ((node = walk.nextNode()) && size < 24000) {
    const el = node.parentElement;
    if (!el || el.closest('input,textarea,select,script,style,noscript,iframe,[data-private],[contenteditable]:not([contenteditable="false"]),[hidden],[aria-hidden="true"]')) continue;
    if (!el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})) continue;
    const text = node.textContent.replace(/\s+/g, ' ').trim();
    if (text) { parts.push(text); size += text.length + 1; }
  }
  return {url:location.href, title:document.title.slice(0,1000), text:parts.join('\n').slice(0,24000)};
})()
