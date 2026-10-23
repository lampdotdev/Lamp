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
pad.send({ ready: true });                       // anything small to the TV app
```

Make each control big enough for a thumb, show the player's number and the state (say plainly when the TV app isn't there or the game has ended), and send a button's press and its release, so the TV can tell held from tapped.

On the TV, in `Web/`, `Lamp.controllers` (lamp.js's comment) runs the game: `Lamp.controllers.start()`, then `onLink(fn(url))` for the address phones open, to show as a QR code (it changes every few minutes, and `fn` is called again each time), `onJoin`/`onLeave(fn(player))`, `onButton(fn(player, name, down))`, `onAxis(fn(player, name, x, y))`, `onMessage(fn(player, data))`, `onError(fn(message))`, `send(player, data)` (player 0 for every phone), `isHeld(player, name)`, `players()` and `stop()`. A phone that leaves or drops has every button it held let go before `onLeave`, and movement that arrives late is dropped, so the game never acts on a stale stick.

## Tilt

The page is plain http, and phones give their motion sensors only to https pages. So make buttons and sticks the controls. Offer tilt only where `LampController.canTilt()` says so, from a tap (a Start button), since the browser asks the person first: `LampController.tilt(pad).then(...).catch(...)` then sends the phone's tilt as axis `'tilt'` (x: left -1 to right 1, y: away -1 to toward 1). Where it can't, the game must still be playable with the buttons.

## A second screen

For a page that shows something beside the TV rather than steering it (a hand of cards, a scoreboard, a buzzer that needs no game), the TV page draws a QR code of `Lamp.phonePage(hash)`, the page's address with `#hash` after it, inside `Lamp.onPhonePage(fn)`: it's called at once when there's an address and again whenever it moves, so redraw the code there. It's null when the app has no `Phone/index.html`. What the phone and the TV say to each other still goes through `Lamp.controllers` and `LampController` (`send` and `onMessage`); nothing else carries messages between them.
