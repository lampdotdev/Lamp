---
name: phone-controllers
description: A TV app's page for phones on the same Wi-Fi - phones as controllers (buttons, sticks, a wheel, a buzzer), or a second screen joined by a QR code. Read before writing Phone/ or using Lamp.controllers or Lamp.phonePage.
---

# Phones as controllers and second screens

The phone's page goes in `Phone/` at the app's root: `index.html` and the files beside it, loaded with relative paths. It runs in the phone's own modern browser, so it isn't held to the TV's 2019 syntax. Lamp serves it, and carries the phones' input to the TV page itself, over the home Wi-Fi, while the app runs (in the TV preview, or set to open on a TV). Never start a server, a login item or anything else that keeps running for it, and never publish the page another way. Nothing secret goes in `Phone/`: anyone on the Wi-Fi with its address can load it.

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
pad.send({ ready: true });                       // anything small to the TV app: at most 1,024 bytes (below)
```

Make each control big enough for a thumb, show the player's number and the state (say plainly when the TV app isn't there or the game has ended), and send a button's press and its release, so the TV can tell held from tapped.

On the TV, in `Web/`, `Lamp.controllers` (lamp.js's comment) runs the game: `Lamp.controllers.start()`, then `onLink(fn(url))` for the address phones open, to show as a QR code (it changes every few minutes, and `fn` is called again each time), `onJoin`/`onLeave(fn(player))`, `onButton(fn(player, name, down))`, `onAxis(fn(player, name, x, y))`, `onMessage(fn(player, data))`, `onError(fn(message))`, `send(player, data)` (player 0 for every phone), `isHeld(player, name)`, `players()` and `stop()`. A phone that leaves or drops has every button it held let go before `onLeave`, and movement that arrives late is dropped, so the game never acts on a stale stick.

## Messages, and sending a file

One message, as the JSON that goes out (Lamp's own few bytes of wrapping included), is at most 1,024 bytes (`LampController.messageLimit`, `Lamp.controllers.messageLimit`), either way. A bigger one isn't sent: `send` returns false, and the TV app's log (and its `onError`) says so with its size. `send` also returns false while the other side isn't there. Over about 120 messages a second from one phone, Lamp drops the rest.

Something big (a file, a picture, a long list) goes in pieces: base64 cut into pieces of at most 700 characters, each sent with its number and the count, and the next only once the other side has answered the last one. The receiver puts them together when it has them all.

```js
// Sender, on a phone's page (on the TV: Lamp.controllers.send(player, ...) and onMessage(fn(player, data)))
var outgoing = null;
function sendFile(base64) {
  outgoing = { id: String(Date.now()), b64: base64, next: 0, count: Math.ceil(base64.length / 700) };
  sendPiece();
}
function sendPiece() {
  var f = outgoing;
  if (f.next === f.count) { outgoing = null; return; }  // the TV has it all
  pad.send({ file: f.id, i: f.next, of: f.count, b64: f.b64.substr(f.next * 700, 700) });
}
// in the pad's onMessage: the TV's answer to a piece sends the next
function onMessage(data) {
  if (outgoing && data.got === outgoing.id && data.i === outgoing.next) { outgoing.next++; sendPiece(); }
}

// Receiver, on the TV: keep pieces by number, answer each, and put them together once all are in
var files = {};
Lamp.controllers.onMessage(function (player, data) {
  if (!data || !data.file) return;
  var f = files[data.file] || (files[data.file] = { parts: [], got: 0 });
  if (f.parts[data.i] === undefined) { f.parts[data.i] = data.b64; f.got++; }
  Lamp.controllers.send(player, { got: data.file, i: data.i });
  if (f.got === data.of) { delete files[data.file]; useFile(f.parts.join('')); }
});
```

From the wish's iPhone or Mac app it's the same with `LampController` (Swift): `data.base64EncodedString()`, then `pad.send(["file": id, "i": i, "of": count, "b64": piece])` for each piece once `pad.onMessage` has heard the answer to the one before. Show how far it's got, and send again a piece whose answer hasn't come after a few seconds.

## Tilt

The page is plain http, and phones give their motion sensors only to https pages. So make buttons and sticks the controls. Offer tilt only where `LampController.canTilt()` says so, from a tap (a Start button), since the browser asks the person first: `LampController.tilt(pad).then(...).catch(...)` then sends the phone's tilt as axis `'tilt'` (x: left -1 to right 1, y: away -1 to toward 1). Where it can't, the game must still be playable with the buttons.

## A second screen

For a page that shows something beside the TV rather than steering it (a hand of cards, a scoreboard, a buzzer that needs no game), the TV page draws a QR code of `Lamp.phonePage(hash)`, the page's address with `#hash` after it, inside `Lamp.onPhonePage(fn)`: it's called at once when there's an address and again whenever it moves, so redraw the code there. It's null when the app has no `Phone/index.html`. What the phone and the TV say to each other still goes through `Lamp.controllers` and `LampController` (`send` and `onMessage`); nothing else carries messages between them.
