---
name: lg-developer-mode
description: How Lamp walks the person through turning on Developer Mode on their LG TV (webOS) the way LG supports - opening the Developer Mode app's page in the LG Content Store and then the app itself on the TV, while the person installs it, signs in and turns its switches on with their own remote. Lamp's TV setup follows the steps below when the person clicks Do It for Me.
---

# Turning on Developer Mode on an LG TV

LG lets a TV take the person's own apps once its Developer Mode app is installed, signed in to a free LG developer
account and switched on. Lamp can't do that for them and mustn't try: installing an app, signing in and turning the
switches on are the person's, on the TV, with its remote. What Lamp does is put the right screen in front of them at
each step and say in one short line what to press.

Lamp reaches the TV over its second-screen socket, the protocol LG's Connect SDK publishes: `wss://<address>:3001`
(the TV's own certificate, trusted for that address alone), or `ws://<address>:3000` on older TVs. The TV asks the
person to allow Lamp once; the key it hands back is kept with the TV, so later connections don't ask again. Requests
that open or list apps need that key, and fail with 401 without it.

## What Lamp never does

- Press the remote's buttons for the person, install the app silently, or sign in for them.
- See the LG account's password or the passphrase in any conversation: the passphrase is typed into the setup window
  and goes only to the TV's key server (port 9991), exactly as typed (it's case-sensitive).
- Say a step happened that it can't see. Lamp sees that the TV let it in and that the app is installed; that the
  person signed in, turned a switch on or that the TV restarted is theirs to confirm.
- Open anything but the LG Content Store's page for Developer Mode and the Developer Mode app.

## Not yet checked on a real TV

- `com.palmdts.devmode` as the Developer Mode app's id, and the store query below (the Connect SDK's form) as the
  way to open its page on webOS 10. Lamp can't tell from the TV's answer whether the page opened, so the line said
  then always says what to do if the store opened on its front page instead.
- That opening the app by its id brings Developer Mode up.

## The steps

Lamp's setup reads this block and follows it in order. `{name}` is the TV's name. A step is one of: `connect` (let
Lamp in; asks on the TV the first time), `request` (send one request; `failed` is said and the setup goes on when
`continueOnFailure`), `wait` (ask the TV every `every` seconds until `until.path` holds `until.contains`), `confirm`
(the person says they've done it, with `button`), and `passphrase` (the setup window's own passphrase step).

```lamp-setup
{
  "connection": "webos-second-screen",
  "steps": [
    {
      "do": "connect",
      "doing": "Asking {name} to let Lamp in…",
      "ask": "On the TV, choose Accept.",
      "done": "{name} let Lamp in",
      "refused": "{name} didn't let Lamp in. Click Try Again, then choose Accept on the TV."
    },
    {
      "do": "request",
      "uri": "ssap://system.launcher/launch",
      "payload": { "id": "com.webos.app.discovery", "params": { "query": "category/GAME_APPS/com.palmdts.devmode" } },
      "doing": "Opening the LG Content Store on {name}…",
      "done": "Asked {name} to show Developer Mode in the LG Content Store",
      "failed": "{name} couldn't open the LG Content Store. On the TV, open it and search for Developer Mode.",
      "continueOnFailure": true
    },
    {
      "do": "wait",
      "uri": "ssap://com.webos.applicationManager/listApps",
      "until": { "path": "apps.id", "contains": "com.palmdts.devmode" },
      "every": 3,
      "doing": "Waiting for Developer Mode to be installed…",
      "ask": "On the TV, choose Install. If the store shows its front page, search for Developer Mode first.",
      "done": "Developer Mode is installed on {name}"
    },
    {
      "do": "request",
      "uri": "ssap://system.launcher/launch",
      "payload": { "id": "com.palmdts.devmode" },
      "doing": "Opening Developer Mode on {name}…",
      "done": "Asked {name} to open Developer Mode",
      "failed": "{name} couldn't open Developer Mode. On the TV, open it from your apps.",
      "continueOnFailure": true
    },
    {
      "do": "confirm",
      "ask": "On the TV, sign in with your LG developer account, then turn Dev Mode Status on. The TV restarts. Click Continue once it's back on.",
      "button": "Continue",
      "link": { "title": "Get an LG Developer Account", "url": "https://webostv.developer.lge.com/" },
      "done": "You turned Dev Mode Status on"
    },
    {
      "do": "connect",
      "doing": "Connecting to {name} again…",
      "ask": "If the TV asks, choose Accept.",
      "done": "Connected to {name} again",
      "refused": "{name} didn't let Lamp in. Click Try Again, then choose Accept on the TV."
    },
    {
      "do": "request",
      "uri": "ssap://system.launcher/launch",
      "payload": { "id": "com.palmdts.devmode" },
      "doing": "Opening Developer Mode on {name} again…",
      "done": "Asked {name} to open Developer Mode again",
      "failed": "{name} couldn't open Developer Mode. On the TV, open it from your apps.",
      "continueOnFailure": true
    },
    {
      "do": "passphrase",
      "ask": "On the TV, turn Key Server on. Type the passphrase it shows below exactly as shown, then click Connect."
    }
  ]
}
```
