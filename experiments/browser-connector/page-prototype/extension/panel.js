// The panel is the extension's page; the app's own page sits in it as an iframe from Lamp on this Mac. What the
// panel keeps for itself: the app's name and the consent line above the frame, the message when Lamp is away,
// and the one door to the person's tab (reading it), which opens only right after a click.
const tab = Number(new URLSearchParams(location.search).get('tab'));
// Each app gets its own origin (a name under .localhost, which Chrome sends to this Mac by itself), so one app's
// page can't read another's storage or cookies.
const origin = 'http://recipe-box.localhost:47123';
const frame = document.getElementById('app'), away = document.getElementById('away');
let ready = false;

frame.sandbox = 'allow-scripts allow-forms allow-same-origin';   // no popups, no navigating the panel itself
frame.src = origin + '/';
frame.hidden = false;
// A cross-origin frame that fails to load says nothing to its parent, so the page says hello; no hello, no app.
setTimeout(() => {
  if (ready) return;
  frame.hidden = true; away.hidden = false;
  away.textContent = 'Open Lamp on your Mac to use Recipe Box here.';
}, 3000);

window.addEventListener('message', async event => {
  if (event.source !== frame.contentWindow || event.origin !== origin) return;
  const message = event.data || {};
  const answer = value => frame.contentWindow.postMessage({lamp: 'answer', id: message.id, ...value}, origin);
  if (message.lamp === 'hello') {
    ready = true;
    document.getElementById('consent').textContent = message.readsPage ? 'Using this page shares its text with Recipe Box.' : '';
    return answer({tab, theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'});
  }
  if (message.lamp !== 'read') return;
  // A click inside the frame also activates the panel (Chrome passes a click's activation up to the frames above
  // it), so a page can read only when the person just clicked something, never by itself in the background.
  if (!navigator.userActivation.isActive) return answer({error: 'Reading the page needs a click.'});
  const result = await chrome.runtime.sendMessage({tab, scope: message.scope});
  answer(result?.error ? {error: result.error} : {page: result});
});
