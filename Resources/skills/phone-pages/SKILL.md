---
name: phone-pages
description: How to build a page for phones on the same Wi-Fi - phones as controllers (buttons, sticks, a wheel, a buzzer), a second screen joined by a QR code, or sending the TV a file (a photo, a game, a song). Read before writing Phone/ or using Lamp.controllers or Lamp.phonePage.
---

# Phones as controllers and second screens

The phone's page goes in the app's own `Phone/` folder, beside its `Web/`: `index.html` and the files beside it, loaded with relative paths. The app is a game on Lamp's runtime or a TV app, and its folder is the one `make_app_for` returned: an app at the wish's root has `Phone/index.html` beside `Web/index.html`, and one in a folder of its own (`TV/`, `Game/`) has `TV/Phone/index.html` beside `TV/Web/index.html`. Lamp serves only the app's own `Phone/`, so a page anywhere else (a `Phone/` at the wish's root beside `TV/`) is never served and its link answers "not found". Write the path from the wish's folder in every file tool call: a `cd` in a shell command doesn't change the folder later file tools write in. It runs in the phone's own modern browser, so it isn't held to the TV's 2019 syntax. Lamp serves it while the app runs (in the TV preview, or set to open on a TV), and the phones' input and files go to the TV page over the home Wi-Fi, through a relay Lamp runs on the Mac; a game on the Mac serves its page and runs that relay itself, from Lamp's code built into it, so its phones play with Lamp closed too. Never start a server, a login item or anything else that keeps running for it, and never publish the page another way. Nothing secret goes in `Phone/`: anyone on the Wi-Fi with its address can load it.

## Controllers

On the phone, the page loads `lamp-controller.js`, which Lamp serves beside it (don't write one): `<script src="lamp-controller.js"></script>`.

```js
var pad = LampController.connect({
  onPlayer: function (n) { },      // this phone's player number (1, 2, ...)
  onMessage: function (data) { },  // what the TV app sent this phone, or every phone
  onState: function (state) { }    // 'connecting', 'connected', 'waiting' (the TV app isn't there), 'ended', 'full'
});
pad.button('a', true); pad.button('a', false);  // a button held, then let go
pad.axis('stick', x, y);                         // a stick or slider, each from -1 to 1
pad.send({ ready: true });                       // JSON to the TV app, 16 KB at most
```

Make each control big enough for a thumb, show the player's number and the state (say plainly when the TV app isn't there or the game has ended), and send a button's press and its release, so the TV can tell held from tapped. The number comes from the TV app once it's there (`onPlayer`), so show the state until then.

On the TV, in `Web/`, `Lamp.controllers` (lamp.js's comment) runs the game: `Lamp.controllers.start()`, then `onLink(fn(url))` for the address phones open, to show as a QR code (below; it changes every few minutes, and `fn` is called again each time), `onJoin`/`onLeave(fn(player))`, `onButton(fn(player, name, down))`, `onAxis(fn(player, name, x, y))`, `onMessage(fn(player, data))`, `onError(fn(message))`, `send(player, data)` (player 0 for every phone; 16 KB of JSON at most), `isHeld(player, name)`, `players()` and `stop()`. A phone that leaves or drops has every button it held let go before `onLeave`, and movement that arrives late is dropped, so the game never acts on a stale stick.

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

Show the join card from the start (say the game is getting ready for phones until the first link), and draw into the same canvas each time `onLink` calls again. A code that couldn't be drawn and phones that can't join (`start()` rejects, `onError`) each say so in the card; neither hides it as if the game had no phones. In a game drawn on a canvas (three.js, Phaser), put the join card in HTML over it, or draw `LampQR.matrix(url)` (its `size` and `dark(x, y)`) into the scene yourself, with a light border four modules wide.

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

The page is plain http, and phones give their motion sensors only to https pages. So make buttons and sticks the controls. Offer tilt only where `LampController.canTilt()` says so, from a tap (a Start button), since the browser asks the person first: `LampController.tilt(pad).then(...).catch(...)` then sends the phone's tilt as axis `'tilt'` (x: left -1 to right 1, y: away -1 to toward 1). Where it can't, the game must still be playable with the buttons.

## The wish's own apps

A phone's page is not one of the wish's apps. When the wish has an iPhone, Mac or Android app beside the TV app, those apps and the TV page see each other and talk through `LampWish` (`Lamp.wish` in lamp.js, `LampWish` in LampSupport): who is open now, and messages between them. `Lamp.controllers` and `LampController` are for steering the TV (buttons, sticks, files to the TV); for anything else between the wish's apps, use `LampWish`, whose comment in lamp.js and LampSupport says how.

## A second screen

For a page that shows something beside the TV rather than steering it (a hand of cards, a scoreboard, a buzzer that needs no game), the TV page draws a QR code of `Lamp.phonePage(hash)` with `LampQR.draw`, the page's address with `#hash` after it, inside `Lamp.onPhonePage(fn)`: it's called at once when there's an address and again whenever it moves, so redraw the code there. It's null when the app has no `Phone/index.html`. `Lamp.phonePage` and `Lamp.onPhonePage` are a TV app's page's only: a game on Lamp's runtime draws its QR code of the address `Lamp.controllers.onLink` gives (the join code, above), so every phone that opens it joins as a player, and what each phone shows is what the game sends it (`send`). What the phone and the TV say to each other still goes through `Lamp.controllers` and `LampController` (`send` and `onMessage`, `sendFile` and `onFile`); nothing else carries messages between them.
