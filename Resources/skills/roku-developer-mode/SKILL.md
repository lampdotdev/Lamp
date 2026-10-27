---
name: roku-developer-mode
description: How Lamp walks the person through turning on developer mode on their Roku the way Roku documents it - pressing the remote's secret keys over the Roku's own control protocol, then waiting while the person enables the installer, accepts the license and sets a developer password, and the Roku restarts. Lamp's Roku setup follows the steps below when the person clicks Do It for Me.
setup-for: roku
setup-step: developer-mode
---

# Turning on developer mode on a Roku

A Roku takes the person's own channels once its developer mode is on. Roku documents how
(https://developer.roku.com/docs/developer-program/getting-started/developer-setup.md): press Home three times, Up
twice, then Right, Left, Right, Left, Right on the remote; the developer screen opens; enable the installer, accept the
Developer Tools License Agreement, enter a password, and the Roku reboots.

Lamp can press those keys for the person: Roku's External Control Protocol takes `POST /keypress/<key>` on port 8060
(https://developer.roku.com/docs/developer-program/debugging/external-control-api.md), once Settings > System >
Advanced system settings > Control by mobile apps is Enabled, which is the Roku setup's step before this one. The
license and the password are the person's, on the Roku: Lamp never presses them.

What Lamp sees: that the Roku answers on port 8060, that it went away and came back (the reboot), and
`developer-enabled` in `/query/device-info` reading `true`. Nothing else is said done.

## What Lamp never does

- Accept the license or choose the password for the person, or press anything on those screens.
- Press the keys again after a failure part way: it can't tell which reached the Roku, so the person finishes this
  step on the remote instead.
- Press the keys when `developer-enabled` already reads `true`.

## Not yet checked on a real Roku

- The whole guide. Every request and value comes from Roku's documents and Lamp's Roku integration, whose own
  developer-mode step presses the same keys the same way.
- Whether a Roku that already had developer mode on and was set up again goes straight to the password.

## The steps

Lamp's setup reads this block and follows it in order; the frontmatter says it does the Roku setup's
`developer-mode` step, on any Roku. `{name}` is the Roku's name. The connection is plain HTTP, as the Roku
integration's own steps are.

```lamp-setup
{
  "connection": "http",
  "offer": "Lamp presses the Roku's secret keys; you accept the license and set a password.",
  "reach": [
    { "http": { "port": 8060, "path": "/query/device-info" } }
  ],
  "steps": [
    {
      "do": "connect",
      "doing": "Checking {name} answers…",
      "done": "{name} answers"
    },
    {
      "do": "request",
      "run": [
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Home" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Home" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Home" } },
        { "wait": 3 },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Up" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Up" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Right" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Left" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Right" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Left" } },
        { "http": { "method": "POST", "port": 8060, "path": "/keypress/Right" } }
      ],
      "unless": [
        { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "developer-enabled", "equals": "true" }
      ],
      "doing": "Pressing the keys that open the developer screen on {name}…",
      "done": "Pressed the keys that open the developer screen on {name}",
      "failed": "Lamp couldn't finish pressing the keys. On the Roku's remote, press Home three times, then Up, Up, Right, Left, Right, Left, Right."
    },
    {
      "do": "rejoin",
      "ask": "On the Roku, choose Enable installer and restart, accept the license, then set a developer password. The Roku restarts; Lamp carries on once it's back.",
      "button": "It Didn't Restart",
      "unless": [
        { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "developer-enabled", "equals": "true" }
      ],
      "link": {
        "title": "Roku's Developer Setup",
        "url": "https://developer.roku.com/docs/developer-program/getting-started/developer-setup.md"
      },
      "done": "{name} is back on"
    },
    {
      "do": "wait",
      "until": [
        { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "developer-enabled", "equals": "true" },
        { "tcp": 80 }
      ],
      "every": 3,
      "doing": "Waiting for developer mode…",
      "done": "Developer mode is on"
    },
    {
      "do": "handoff",
      "ask": "Type the developer password you just set on the Roku."
    }
  ]
}
```
