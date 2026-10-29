Recorded 2026-10-29 from a game Lamp built for a plain wish, with phones as controllers:

- `join-link.txt`: the join link the game's relay gave its page (`Lamp.controllers.onLink`), 167 bytes. Its credential
  ran out 15 minutes after it was made; it's here only as text to encode.
- `generated-qr.js`: the QR encoder the agent wrote for that game's page, as it wrote it, cut after its `qr` function
  (the drawing after it isn't needed). It holds versions 1 to 6 only, at most 134 bytes, and returns null for anything
  longer, which the game's page took for "no phones", so it showed no code.

`LampQRTests` encodes the link with each.
