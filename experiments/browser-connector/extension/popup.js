const $ = id => document.getElementById(id);
let port, outstanding, requests, tab, documentID, url, chosen, challenge;
function native(body) {
  return new Promise((resolve, reject) => {
    if (outstanding) return reject(new Error("Please wait for the current step."));
    outstanding = {resolve, reject};
    port.postMessage(body);
  });
}
function showError(error) {
  $("status").textContent = error.message;
  $("share").hidden = true;
  $("cancel").hidden = true;
}
async function choose() {
  chosen = requests.find(r => r.id === $("destination").value);
  challenge = null;
  $("share").hidden = true;
  const result = await native({op:"prepare", id:chosen.id, tab:String(tab.id), document:documentID, url});
  challenge = result.challenge;
  $("consent").textContent = `Send visible page text, title and URL to ${result.name}? It stays in that app on this Mac.`;
  $("status").textContent = "";
  $("share").textContent = `Share with ${result.name}`;
  $("share").hidden = false;
  $("cancel").hidden = false;
}
// A fresh native port binds approval to this popup/browser profile. No content-script messages or external listeners.
async function start() {
  port = chrome.runtime.connectNative("dev.lamp.prototype");
  port.onMessage.addListener(value => {
    const waiting = outstanding; outstanding = null;
    if (value.error) waiting?.reject(new Error(value.error)); else waiting?.resolve(value);
  });
  port.onDisconnect.addListener(() => {
    const error = new Error(chrome.runtime.lastError?.message || "Lamp disconnected. Reopen this popup.");
    outstanding?.reject(error); outstanding = null; showError(error);
  });
  ({requests} = await native({op:"list"}));
  if (!requests.length) { $("status").textContent = "Click Get current page in a Lamp-made app first."; return; }
  [tab] = await chrome.tabs.query({active:true,currentWindow:true});
  if (!/^https?:/.test(tab.url || "")) throw new Error("Chrome does not let extensions read this page. Open a website first.");
  const [metadata] = await chrome.scripting.executeScript({target:{tabId:tab.id},func:() => ({url:location.href})});
  documentID = metadata.documentId; url = metadata.result.url;
  $("site").textContent = new URL(url).origin;
  for (const r of requests) { const option = document.createElement("option"); option.value=r.id; option.textContent=r.name; $("destination").append(option); }
  $("destination").hidden = requests.length < 2;
  await choose();
}
$("destination").onchange = () => choose().catch(showError);
$("share").onclick = async () => {
  $("share").disabled = true;
  $("destination").disabled = true;
  try {
    const [capture] = await chrome.scripting.executeScript({target:{tabId:tab.id,documentIds:[documentID]},func:() => {
      // Local's main/article-first approach, bounded and narrowed to rendered text nodes.
      // Never read field values, editable drafts, cookie/storage APIs or other frames.
      const read = root => {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
        const parts=[]; let count=0, n;
        while ((n=walker.nextNode()) && count<24000) {
          const el=n.parentElement;
          if (!el || el.closest('input,textarea,select,script,style,noscript,iframe,[contenteditable]:not([contenteditable="false"]),[hidden],[aria-hidden="true"]')) continue;
          if (!el.checkVisibility({checkOpacity:true,checkVisibilityCSS:true})) continue;
          const text=n.textContent.replace(/\s+/g," ").trim();
          if (text) { parts.push(text); count+=text.length+1; }
        }
        return parts.join("\n").slice(0,24000);
      };
      const main=document.querySelector('main,article,[role="main"]');
      let text=read(main || document.body);
      if (main && text.length<500) text=read(document.body);
      return {url:location.href,title:document.title.slice(0,1000),text};
    }});
    if (capture.documentId !== documentID || capture.result.url !== url) throw new Error("The page changed. Open the extension again.");
    const result = await native({op:"deliver", id:chosen.id, challenge, tab:String(tab.id), document:documentID, page:capture.result});
    $("status").textContent = `Shared with ${result.name}.`;
    $("share").hidden = true; $("cancel").hidden = true;
  } catch (error) { showError(error); }
};
$("cancel").onclick = async () => {
  try { await native({op:"cancel",id:chosen.id,challenge}); $("status").textContent="Nothing shared."; $("share").hidden=true; $("cancel").hidden=true; }
  catch (error) { showError(error); }
};
start().catch(showError);
