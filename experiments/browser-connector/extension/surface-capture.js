// This function runs in Chrome's isolated extension world. It never reads a whole page for a selection action.
globalThis.__lampCaptureSurface = scope => {
  const selection = scope === 'selection' ? window.getSelection() : null;
  const range = selection?.rangeCount === 1 && !selection.isCollapsed ? selection.getRangeAt(0) : null;
  if (scope === 'selection' && !range) throw new Error('Select a passage on the page first.');
  if (range && (range.startContainer.getRootNode() !== document || range.endContainer.getRootNode() !== document)) throw new Error('Select text in the main page, outside embedded content.');
  const root = range ? range.commonAncestorContainer : document.querySelector('main,article,[role="main"]') || document.body;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  let node = root.nodeType === Node.TEXT_NODE ? root : walker.nextNode();
  let size = 0; const parts = [];
  while (node && size < 24000) {
    const el = node.parentElement;
    if (el && (!range || range.intersectsNode(node)) &&
        !el.closest('input,textarea,select,script,style,noscript,iframe,[data-private],[contenteditable]:not([contenteditable="false"]),[hidden],[aria-hidden="true"]') &&
        el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})) {
      const start = range && node === range.startContainer ? range.startOffset : 0;
      const end = range && node === range.endContainer ? range.endOffset : node.textContent.length;
      const text = node.textContent.slice(start,end).replace(/\s+/g,' ').trim();
      if (text) {parts.push(text);size += text.length + 1;}
    }
    node = walker.nextNode();
  }
  const text = parts.join('\n').slice(0,24000);
  if (scope === 'selection' && !text) throw new Error('Select readable page text, outside private areas or fields.');
  return {url:location.href,title:document.title.slice(0,1000),text,scope};
};
