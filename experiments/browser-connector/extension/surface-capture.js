// This runs in Chrome's isolated extension world, and in Lamp's own preview of a sidebar (BrowserPreview), so an app's
// builder is given a page the way the person's click gives it. It never reads a whole page for a selection action.
globalThis.__lampCaptureSurface = scope => {
  const limit = 24000;
  const selection = scope === 'selection' ? window.getSelection() : null;
  const range = selection?.rangeCount === 1 && !selection.isCollapsed ? selection.getRangeAt(0) : null;
  if (scope === 'selection' && !range) throw new Error('Select a passage on the page first.');
  if (range && (range.startContainer.getRootNode() !== document || range.endContainer.getRootNode() !== document)) throw new Error('Select text in the main page, outside embedded content.');
  const read = root => {
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let node = root.nodeType === Node.TEXT_NODE ? root : walker.nextNode();
    let size = 0; const parts = [];
    while (node && size < limit) {
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
    const joined = parts.join('\n');
    // Said, so an app can tell the person the page was longer than what it was given.
    return {text: joined.slice(0,limit), truncated: joined.length > limit || node !== null};
  };
  const main = range ? null : document.querySelector('main,article,[role="main"]');
  let result = read(range ? range.commonAncestorContainer : main || document.body);
  // A page whose main region is a stub (a header, a teaser) is read whole instead.
  if (main && result.text.length < 500) result = read(document.body);
  if (scope === 'selection' && !result.text) throw new Error('Select readable page text, outside private areas or fields.');
  return {url:location.href,title:document.title.slice(0,1000),text:result.text,scope,truncated:result.truncated};
};
