---
name: lg-developer-mode
description: How Lamp walks the person through turning on Developer Mode on their LG TV (webOS) the way LG supports - opening the Developer Mode app's page in the LG Content Store and then the app itself on the TV, while the person installs it, restarts the TV when asked, signs in and turns its switches on with their own remote. Lamp's TV setup follows the steps below when the person clicks Do It for Me.
---

# Turning on Developer Mode on an LG TV

LG lets a TV take the person's own apps once its Developer Mode app is installed, signed in to a free LG developer
account and switched on. Lamp can't do that for them and mustn't try: installing an app, restarting the TV, signing in
and turning the switches on are the person's, on the TV, with its remote. What Lamp does is put the right screen in
front of them at each step and say in one short line what to do.

What happens on the TV, in order:

1. The person installs Developer Mode from the LG Content Store.
2. On some TVs the app shows no Sign In until the TV has been fully restarted (unplugged, not just turned off with
   the remote, which only puts it to sleep). Until then its switches can be turned on but nothing works.
3. The person signs in with their LG developer account and turns Dev Mode Status on; the TV restarts.
4. In Developer Mode again, the person turns Key Server on and types the passphrase it shows into Lamp. The key
   server answers only while Developer Mode is open on the screen, so it stays open until Lamp has connected.

A TV that was set up before may show Developer Mode already signed in, with Dev Mode Status on: then only Key Server
and the passphrase are left.

Lamp reaches the TV over its second-screen socket, the protocol LG's Connect SDK publishes: `wss://<address>:3001`,
the TV's own certificate kept with the key the TV hands back once the person lets Lamp in. Later connections offer
that key, to a TV showing the same certificate only, and the TV doesn't ask again. Requests that open or list apps
need the key, and fail with 401 without it.

## What Lamp never does

- Press the remote's buttons for the person, install the app silently, or sign in for them.
- See the LG account's password or the passphrase in any conversation: the passphrase is typed into the setup window
  and goes only to the TV's key server (port 9991), exactly as typed (it's case-sensitive).
- Say a step happened that it can't see. Lamp sees that the TV let it in, that the app is installed, and that the TV
  went away and came back; a sign-in or a switch is the person's to do, and Lamp says nothing of it as done.
- Open anything but the LG Content Store's page for Developer Mode and the Developer Mode app.

## Not yet checked on a real TV

- That the store query below (the Connect SDK's form) opens Developer Mode's own page rather than the store's front
  page. The TV only says it opened the store, so the line said then always says what to do on the front page.

## The steps

Lamp's setup reads this block and follows it in order. `{name}` is the TV's name. A step is one of: `connect` (let
Lamp in; asks on the TV the first time), `request` (send one request; `failed` is said and the setup goes on when
`continueOnFailure`), `wait` (ask the TV every `every` seconds until `until.path` holds `until.contains`), `confirm`
(the person clicks `button` once they've done it; a confirm has no `done`, since Lamp didn't see it happen), `rejoin`
(the device restarts: Lamp carries on by itself once it has seen it stop answering and answer again, and only then
says `done`; `button` skips a restart that isn't needed and claims nothing), and `passphrase` (the setup window's own
passphrase step).

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
      "payload": {
        "id": "com.webos.app.discovery",
        "params": {
          "query": "category/GAME_APPS/com.palmdts.devmode"
        }
      },
      "doing": "Opening the LG Content Store on {name}…",
      "done": "Asked {name} to show Developer Mode in the LG Content Store",
      "failed": "{name} couldn't open the LG Content Store. On the TV, open it and search for Developer Mode.",
      "continueOnFailure": true
    },
    {
      "do": "wait",
      "uri": "ssap://com.webos.applicationManager/listApps",
      "until": {
        "path": "apps.id",
        "contains": "com.palmdts.devmode"
      },
      "every": 3,
      "doing": "Waiting for Developer Mode to be installed…",
      "ask": "On the TV, choose Install. If the store shows its front page, search for Developer Mode first.",
      "done": "Developer Mode is installed on {name}"
    },
    {
      "do": "request",
      "uri": "ssap://system.launcher/launch",
      "payload": {
        "id": "com.palmdts.devmode"
      },
      "doing": "Opening Developer Mode on {name}…",
      "done": "Asked {name} to open Developer Mode",
      "failed": "{name} couldn't open Developer Mode. On the TV, open it from your apps.",
      "continueOnFailure": true
    },
    {
      "do": "rejoin",
      "ask": "If Developer Mode shows no Sign In, unplug the TV for 30 seconds, then plug it back in and turn it on. Lamp carries on once the TV answers again.",
      "button": "Sign In Is Showing",
      "done": "{name} is back on"
    },
    {
      "do": "request",
      "uri": "ssap://system.launcher/launch",
      "payload": {
        "id": "com.palmdts.devmode"
      },
      "doing": "Opening Developer Mode on {name}…",
      "done": "Asked {name} to open Developer Mode",
      "failed": "{name} couldn't open Developer Mode. On the TV, open it from your apps.",
      "continueOnFailure": true
    },
    {
      "do": "rejoin",
      "ask": "In Developer Mode, sign in with your LG developer account, then turn Dev Mode Status on. The TV restarts, and Lamp carries on once it's back on.",
      "button": "Dev Mode Status Is Already On",
      "link": {
        "title": "Get an LG Developer Account",
        "url": "https://webostv.developer.lge.com/"
      },
      "done": "{name} is back on"
    },
    {
      "do": "request",
      "uri": "ssap://system.launcher/launch",
      "payload": {
        "id": "com.palmdts.devmode"
      },
      "doing": "Opening Developer Mode on {name} again…",
      "done": "Asked {name} to open Developer Mode again",
      "failed": "{name} couldn't open Developer Mode. On the TV, open it from your apps.",
      "continueOnFailure": true
    },
    {
      "do": "passphrase",
      "ask": "In Developer Mode, turn Key Server on and keep Developer Mode open on the TV. Type the passphrase it shows below exactly as shown, then click Connect."
    }
  ]
}
```
