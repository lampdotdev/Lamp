---
name: phone-pages
description: How to build a page for phones on the same Wi-Fi - phones as controllers (buttons, sticks, a wheel, a buzzer, a game's own interaction, how views and moves go between game and phone), a second screen joined by a QR code, or sending the TV a file (a photo, a game, a song). Read before writing Phone/ or using Lamp.controllers or Lamp.phonePage.
---

# Phones as controllers and second screens

The phone's page goes in the app's own `Phone/` folder, beside its `Web/`: `index.html` and the files beside it, loaded with relative paths. In an app shared with the person, the phone's browser lets the page load only its own files, its link to the game and the sites its review named: keep everything such a page uses (scripts, styles, fonts, pictures, sounds) in `Phone/`. The app is a game on Lamp's runtime or a TV app, and its folder is the one `make_app_for` returned: an app at the wish's root has `Phone/index.html` beside `Web/index.html`, and one in a folder of its own (`TV/`, `Game/`) has `TV/Phone/index.html` beside `TV/Web/index.html`. Lamp serves only the app's own `Phone/`, so a page anywhere else (a `Phone/` at the wish's root beside `TV/`) is never served and its link answers "not found". Write the path from the wish's folder in every file tool call: a `cd` in a shell command doesn't change the folder later file tools write in. It runs in the phone's own modern browser, so it isn't held to the TV's 2019 syntax. The page is served, and the phones' input and files go to the screen over the home Wi-Fi, by the host the game chooses as it starts (below): the game itself or Lamp on the Mac. Nothing secret goes in `Phone/`: anyone on the Wi-Fi with its address can load it. Whatever carries the phones, keep what Lamp's hosts keep: a link a phone opens is an invitation for anyone who has it, so make it short-lived and never put the app's own keys or the person's data in it, the page or its messages; let in only the game's own page and the phones it invited; and send nothing past the home network unless the person asked for that.

## Controllers

On the phone, the page loads `lamp-controller.js`, which Lamp serves beside it (don't write one): `<script src="lamp-controller.js"></script>`.

```js
var pad = LampController.connect({
  onPlayer: function (n) { },      // this phone's player number (1, 2, ...)
  onMessage: function (data) { },  // what the TV app sent this phone, or every phone
  onState: function (state) { },   // 'connecting', 'connected', 'waiting' (the TV app isn't there), 'ended', 'full'
  busy: function () { return false; },  // true while opening again would lose something (a drawing, a form)
  onUpdate: function (apply) { }   // leave it out unless the page must choose: call apply() to open the newer page
});
pad.button('jump', true); pad.button('jump', false);  // a button held, then let go, named for what it does
pad.axis('steer', x, y);                         // a stick, wheel or slider, each from -1 to 1
pad.send({ ready: true });                       // JSON to the TV app, 16 KB at most
```

A page open on a phone takes what you save to Phone/ by itself where the host can, a few seconds later: it opens again as the same player once no button is held, no file is on its way, nothing is being typed and `busy` says false. So keep a form's or a drawing's work behind `busy`, or give `onUpdate` a button when only the person should choose. Phones and the TV don't switch at the same moment, so a change of what they send each other should still read the other side's old messages.

Make each control big enough for a thumb, show the player's number and the state (say plainly when the TV app isn't there or the game has ended), and send a button's press and its release, so the TV can tell held from tapped. The number comes from the TV app once it's there (`onPlayer`), so show the state until then. `onState` runs during `connect()` itself, before it returns, so set up everything it touches first: a first draw that throws there stops the page's script and leaves the phone on its loading text.

`pad.button`, `pad.axis` and `pad.send` return false when nothing was sent: show that state, never a press that went nowhere.

### How a game's controller is held

The game-ui skill ("With phones") settles what the controller is, and that settles how it's held. A two-thumb page is made for landscape: movement on the left, the main action on the right, and the player, the link and Back quiet in the middle or along the top. Compose those zones for the game and its verbs; a portrait layout stretched sideways isn't this. A page built around one big interaction (a lock, a dial, a hand of cards) and a page that isn't game controls (photos, files, a scoreboard) stay whichever way suits them, with the same safe areas and the same care when the phone turns.

- Lay it out with `viewport-fit=cover` in the viewport tag, `env(safe-area-inset-*)` around the edges and `100dvh` for the height, so a notch and the browser's bars don't sit on a control.
- Nothing forces a phone sideways. `screen.orientation.lock` works in few browsers and usually only full screen: try it after a tap if you like, handle its failure, and make the page right without it. Never rotate the page with CSS.
- Joining and typing a name may stay upright, and the keyboard changes the viewport's shape: decide what `@media (orientation: …)` shows from the game's phase too, so a keyboard never hides the name field behind "turn your phone".
- A two-thumb page held upright during play: keep the player and the link on screen, show a themed "Turn your phone sideways", take no play gestures, and offer "Use upright" with a compact layout for someone who can't rotate. Keep Back reachable, and never pause the party for one phone turning.
- If the phone turns during a press, end any gesture (below), send every held button's release and zero every active axis, drop the page's own pointer capture and gesture state, and ask for a fresh press. The page keeps track of what's held; never close the link to clear it. Turning back restores the phase as it was, with no new join and no reset.

```js
var held = {};
function press(name, down) { if (down) held[name] = true; else delete held[name]; pad.button(name, down); }
function letGo() {
  Object.keys(held).forEach(function (name) { press(name, false); });
  pad.axis('steer', 0, 0);                         // every axis this page moves
}
matchMedia('(orientation: landscape)').addEventListener('change', letGo);
```

### Views and moves

The game owns what's true; a phone draws what it's told and asks for moves. There's no second state machine on the phone.

- **Views.** Derive each player's view from the game's state in one function, and send it to that player alone (`send(player, view)`, never player 0 for anything private) whenever what it holds changes, not only when the phase does: a wrong attempt changes the view with no change of phase. Send it in `onJoin` too, which also runs for a phone coming back and for a page that opened again, and for phones already joined when the code runs again. The phone keeps nothing it can't get back from its next view. A player with no part in the current view, like one back from a dropped link, is shown that and when they're next in, never an empty screen.
- **Turns.** Each view carries the phase and a `turn` the game moves on whenever an old screen's move would no longer mean the same thing (a new round, a new turn). A move names the `turn` it was made on, and an `id`, since a `turn` can't tell two moves in one turn apart: one more than the `answer.id` in the view it was made on (below), so ids come from the game and survive the page opening again.
- **Moves.** Send the finished move as one bounded message: `pad.send({ move: 'try', id: id, turn: view.turn, path: path })`. `pad.axis` is for live movement only: an axis is dropped when the game is behind and late ones are thrown away, so never build a result from them. Collect a path on the phone and send it when it ends.
- **The game decides.** `f.phones` holds buttons only; axes and messages come by `onAxis` and `onMessage`, between frames, so the game keeps its own queue and empties it in `frame`, never a flag `frame` clears. It drops a move from another phase or `turn`, whose phone has already moved on, and takes one with an `id` no newer than the player's last answer as a repeat, which changes nothing and only sends the view again. For any other move it checks the player and the move's size and shape, accepts or rejects it, and keeps that for the player. Every view carries that as `answer: { id, ok }`, `{ id: 0 }` before the first.
- **One move at a time.** After sending, a phone takes no new move until a view's `answer.id` reaches it or a view has another phase or `turn`: views go out for other reasons too, and `send` returning true only means it went out. There's no timer that offers a fresh move, because a move that's late can still land, and two ids would count twice. A message can be dropped when the game is far behind, so a game whose turn can sit forever may send the same move again, same `id`, after a few seconds. A phone that loses its link forgets a waiting move and never sends it again after a reconnect; the view it comes back to says what happened.
- **Input needs a current view.** A view belongs to the link it came on: take input only once one has arrived, and stop when `onState` leaves `connected`, until `onJoin`'s view comes on the new link.
- **A gesture that's interrupted is no move.** Track the finger's `pointerId` and capture it. End the gesture, send nothing and clear what it drew on that finger's `pointercancel` or `lostpointercapture`, when the page is hidden (`visibilitychange`), when the phone turns, when `onState` leaves `connected`, and when a view arrives with another phase or `turn`. Only that finger's `pointerup` in the same `turn` submits, and it ends the gesture first, so the `lostpointercapture` that follows a normal release finds nothing to cancel. Keep `busy` true during a gesture so a newer page waits for it.

```js
var view = null, live = false, path = null, finger = null, waiting = null;
function cancel() { path = null; finger = null; draw(); }
var pad = LampController.connect({
  onMessage: function (next) {
    var moved = view && (next.turn !== view.turn || next.phase !== view.phase);
    if (moved) { path = null; finger = null; }
    if (moved || next.answer.id >= waiting) waiting = null;  // any other view isn't an answer
    view = next; live = true; draw();
  },
  onState: function (state) {
    if (state !== 'connected') { live = false; path = null; finger = null; waiting = null; }
    draw();
  },
  busy: function () { return !!path; }
});
lock.addEventListener('pointerdown', function (event) {
  if (!live || path || waiting !== null) return;
  finger = event.pointerId; lock.setPointerCapture(finger); path = []; draw();
});
lock.addEventListener('pointerup', function (event) { if (event.pointerId === finger) finish(); });
['pointercancel', 'lostpointercapture'].forEach(function (name) {
  lock.addEventListener(name, function (event) { if (event.pointerId === finger) cancel(); });
});
document.addEventListener('visibilitychange', function () { if (document.hidden) cancel(); });
matchMedia('(orientation: landscape)').addEventListener('change', cancel);
function finish() {                                     // the finger lifted, or Submit
  if (live && path) {
    var id = view.answer.id + 1;
    if (pad.send({ move: 'try', id: id, turn: view.turn, path: path })) waiting = id;
  }
  path = null; finger = null; draw();
}

// In the game: moves wait for the frame, and the state decides.
var moves = [];
Lamp.controllers.onMessage(function (player, data) { moves.push({ player: player, data: data }); });
Lamp.controllers.onJoin(function (player) { sendView(player); });
// in frame(f): for each of moves.splice(0): drop an old turn's; for a new id, check it, change the state and keep
// { id, ok } for that player's views; then sendView for whoever's view changed, and for a repeat
```

### Seeing the page

In a game on Lamp's web runtime, you can see and press this page yourself: `use_app` with `phone` true on an action opens the real `Phone/index.html` at 844x390, sideways (`rotate` with `up` for a page held upright), joined to the game as a player in the same play, with a picture of it beside the game's, what it sent the game, its words and controls, and what it logged. Tap with `click` by `target` (a selector or the words on it) or x and y; `press`, `release` and `drag` work a held button or a stick, and a `press`, several `drag`s with no place, then a `release` trace a path; `type` fills a field; `rotate` turns it (`up`, then `left` or `right` for each way round), and works with a finger left down; `link` with `item` `lost`, `away` or `back` drops and restores it. Before you finish, play the whole journey with it: joining, the menu, play, a move the game rejects, results, the link lost and back, and rotation with a control or a gesture held.

It's the real page and the real `Lamp.controllers`, but not a real phone: one phone at most and one finger, so it shows nothing about a second player's view or a two-finger gesture; in Mac WebKit, with synthetic touches that move in straight steps and no `pointercancel` of their own, so it shows a gesture works, not how it feels; on a link that stands in for the relay (no QR scan, no files, no network, so what it loads must be in `Phone/`). The page's timers and clocks go by the play, so a long press lasts what the script says; a CSS animation runs by real time. A notch, the browser's bars, the keyboard, tilt, the wake lock, vibration and `orientation.lock` aren't there to see, and speed isn't either. Say so when you report it, and ask the person to try it on their phone.

On the TV, in `Web/`, `Lamp.controllers` (lamp.js's comment) runs the game. It starts with a host:

- `Lamp.controllers.start({ host: 'game' })`: the game serves the page and runs the link itself, with no Lamp: on the Mac, an iPhone or iPad while it's in front, an LG TV whose package carries the game's service (webOS 5 on), and the Xbox. Lamp's TV preview has no game host.
- `Lamp.controllers.start({ host: 'lamp' })`: Lamp serves the page and runs the link, while Lamp is open and the Mac is reachable: in the TV preview, on a Samsung or LG TV and on the Xbox.
- `Lamp.controllers.start()`: where it ran before either existed (the game itself on the Mac, iPhone and iPad; Lamp elsewhere).

A host that isn't there, or fails, says so in `onError` and is tried again; the other one is never used instead. `stop()` ends the session the chosen host runs, and a later `start` may choose again. Then `onLink(fn(url))` for the address phones open, to show as a QR code (below; it changes every few minutes, and `fn` is called again each time), `onJoin`/`onLeave(fn(player))`, `onButton(fn(player, name, down))`, `onAxis(fn(player, name, x, y))`, `onMessage(fn(player, data))`, `onError(fn(message))`, `send(player, data)` (player 0 for every phone; 16 KB of JSON at most), `isHeld(player, name)`, `players()` and `stop()`. A phone that leaves or drops has every button it held let go before `onLeave`, and movement that arrives late is dropped, so the game never acts on a stale stick. A game on Lamp's runtime reads buttons each frame from `f.phones` rather than `onButton` (the game skill).

The session belongs to the page, not to one run of the game's code. When Lamp runs a game's code again in place for a change, phones stay joined with their numbers, so the code sets its `on…` callbacks as it starts and calls `start` as usual (with the same host it's already running, it changes nothing), and nothing stops or restarts the phones; a `stop()` in `dispose` is ignored. Before the new code's first frame, `onLeave` and `onJoin` hear who left and who is here, so `onJoin` is written to be called again for a player the game already has: the game skill's snapshot rule says how slots come back. The phone keeps its page and number throughout and sees no change.

### The join code

Draw the code with `LampQR`, which lamp.js has (its comment says how): never write a QR encoder or load one. A join link carries a signed credential, so it's long (about 170 characters, more with a long name or host); `LampQR` fits any length a link has.

```js
var code = document.getElementById('join-code');   // a <canvas> in the join card
Lamp.controllers.onLink(function (url) {             // before start(), so the first link is drawn too
  try { LampQR.draw(code, url, { size: 240 }); joinNote.textContent = 'Scan to play'; }
  catch (e) { joinNote.textContent = 'Couldn\'t draw the code: ' + e.message; }
});
Lamp.controllers.onError(function (message) { joinNote.textContent = message; });
Lamp.controllers.start();
```

In a game, the join card is a screen of its own, not part of a title (the game-ui skill has the flow, and what the shared display and each phone show in each phase): show it at once when the player goes to join, or from setup or pause to add players, and a game played only with phones may open on it. While it's up it says when the game is getting ready for phones (until the first link), when phones can't join and when it's trying again. Keep the session running behind it: hiding the card never calls `stop()`, drops a player or starts again. While it's hidden, keep the newest `onLink` address and the newest error rather than a picture of an old code, and draw the card from those when it opens, finding its elements again, since a change to the code may have made them anew. Register the handlers before `start()` in every case, and keep the links short-lived. A page that isn't a game (a second screen, a file sent to the TV) may show its code from the start. Draw into the same canvas each time `onLink` calls again. A code that couldn't be drawn and phones that can't join (`start()` rejects, `onError`) each say so in the card; neither hides it as if the game had no phones. In a game drawn on a canvas (three.js, Phaser), put the join card in HTML over it, or draw `LampQR.matrix(url)` (its `size` and `dark(x, y)`) into the scene yourself, with a light border four modules wide.

## Files

One message, as the JSON that goes out, is at most 16 KB (`LampController.messageLimit`, `Lamp.controllers.messageLimit`), either way. A bigger one isn't sent: `send` returns false, and the TV app's log (and its `onError`) says so with its size. `send` also returns false while the other side isn't there.

Anything bigger (a photo, a game for the TV to play, a song, a document) is a file, sent in pieces with its own progress, so buttons pressed meanwhile still arrive at once. Never cut it into messages yourself, as text or base64.

```js
// On the phone: a File from <input type="file">, a Blob, an ArrayBuffer, bytes or text, up to 64 MB.
var sending = pad.sendFile(input.files[0]);          // or pad.sendFile(bytes, { name: 'level.json', type: 'application/json' })
sending.onProgress(function (sent, size) { });     // show it
sending.done.then(function () { }, function (error) { /* error.message: say it */ });
sending.cancel();

// On the TV, in Web/:
Lamp.controllers.onFile(function (player, file) {  // file.name, file.type, file.size
  file.onProgress(function (received, size) { });
  file.done.then(function (arrayBuffer) { }, function (error) { });
});
```

The TV sends a phone a file the same way, with `Lamp.controllers.sendFile(player, data, { name, type })`, which the phone hears in `onFile` (passed to `LampController.connect`). A file whose player leaves, or whose link drops, ends with an error: say so and let the person send it again. Keep a TV's memory in mind: read what arrived and let it go rather than keeping many large files.

## Tilt

The page is plain http, and phones give their motion sensors only to https pages. So a game's controller is a touch interaction that's usable without tilt, whatever shape the game-ui skill's design gave it. Offer tilt only where `LampController.canTilt()` says so, from a tap (a Start button), since the browser asks the person first: `LampController.tilt(pad).then(...).catch(...)` then sends the phone's tilt as axis `'tilt'` (x: left -1 to right 1, y: away -1 to toward 1). Where it can't, the game must still be fully playable by touch. The wake lock and `navigator.vibrate` are extras in the same way: many phones won't give them to this page, so try them, handle their failure, and let nothing depend on them.

## The wish's own apps

A phone's page is not one of the wish's apps. When the wish has an iPhone, Mac or Android app beside the TV app, those apps and the TV page see each other and talk through `LampWish` (`Lamp.wish` in lamp.js, `LampWish` in LampSupport): who is open now, and messages between them. `Lamp.controllers` and `LampController` are for steering the TV (buttons, sticks, files to the TV); for anything else between the wish's apps, use `LampWish`, whose comment in lamp.js and LampSupport says how.

## A second screen

For a page that shows something beside the TV rather than steering it (a hand of cards, a scoreboard, a buzzer that needs no game), the TV page draws a QR code of `Lamp.phonePage(hash)` with `LampQR.draw`, the page's address with `#hash` after it, inside `Lamp.onPhonePage(fn)`: it's called at once when there's an address and again whenever it moves, so redraw the code there. It's null when the app has no `Phone/index.html`. `Lamp.phonePage` and `Lamp.onPhonePage` are a TV app's page's only: a game on Lamp's runtime draws its QR code of the address `Lamp.controllers.onLink` gives (the join code, above), so every phone that opens it joins as a player, and what each phone shows is what the game sends it (`send`). What the phone and the TV say to each other goes through `Lamp.controllers` and `LampController` (`send` and `onMessage`, `sendFile` and `onFile`).
