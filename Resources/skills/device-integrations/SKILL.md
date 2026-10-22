---
name: device-integrations
description: A device Lamp has no kit for (a streaming stick, a photo frame, a TV, an appliance), described as data for device_integration - how Lamp finds it, reads who it is, sets it up step by step, and puts software on it. Read before writing or fixing an integration.
---

# Device integrations

An integration is a JSON object handed to Lamp with `device_integration`. It is data, never code: Lamp acts on it with
its own primitives, fills every value itself, draws every card the person sees, and checks each step on the device.
Write it from the device's own documentation (its developer docs, its local API's reference). Lamp answers with what's
wrong; fix exactly that and send it again.

You never reach the device: no command, request or scan of yours. Lamp does that. You never walk the person through
steps in the chat: the steps are cards Lamp draws from what you write here.

## Shape

```json
{
  "id": "roku",                        // lowercase letters, digits, dashes
  "name": "Roku", "maker": "Roku", "kind": "streaming stick",
  "sources": ["https://developer.roku.com/docs/developer-program/debugging/external-control-api.md"],
  "find": [{ "ssdp": "roku:ecp" }],
  "identity": { ... },
  "steps": [ ... ],
  "bridge": { ... },                   // how an app goes on it, opens, is seen and is used
  "app": { ... }                       // what's built for it; needs bridge.install
}
```

### find

How the device announces itself; any one that matches finds it. Each entry has exactly one of:

- `"ssdp": "<search target>"`, optionally `"contains"` for what the answer's SERVER line holds.
- `"bonjour": "_service._tcp"`, optionally `"contains"` for the name.
- `"http": {"port": 8060, "path": "/query/device-info", "contains": "<device-info>"}`: asked of every address that
  answered Lamp's own SSDP scan.

### identity

Where each field of the device's record is read from its own answers. `os` is said once; the rest are reads. `id`
(unique to this one device: a serial, a UDN) and `model` are required.

```json
"identity": {
  "os": "Roku OS",
  "id":        { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "serial-number" },
  "model":     { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "model-name" },
  "name":      { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "user-device-name" },
  "modelID":   { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "model-number" },
  "osVersion": { "http": { "port": 8060, "path": "/query/device-info" }, "xml": "software-version" }
}
```

A read has `json` (a dotted path: `device.modelName`, `items.0.id`) or `xml` (an element, or `parent/child`). Reads are
GETs. In place of `http`, `"description": true` reads the device's UPnP description wherever its SSDP answer points now
(with `xml`), for a device whose description moves with its mode, as an Xbox's does. `contains` on a read says what the
value must hold for the device to be this kind (`"contains": "Xbox"` on the model), when other devices answer the same
search.

### Requests

Every request goes to the address the device was found at; you give only the port and path.

```json
{ "method": "POST", "port": 80, "path": "/plugin_install",
  "auth": { "digest": true, "user": "rokudev", "password": "{field:password}" },
  "form": { "mysubmit": "Install", "archive": "@{package}" } }
```

`https: true` for a device that only speaks HTTPS with a certificate of its own (Xbox's Device Portal): Lamp
trusts that certificate the first time and holds the device to it after. `method` (GET, POST, PUT, DELETE), `headers`, `body` or `form` (a value `"@{package}"` sends the package file), `auth`
(`digest` true or false for basic; the password is always one `{field:…}`), and `keep`: `"picture"` in `bridge.look`
for the answer that is the screen's picture, `"key"` in a step's `run` for an SSH key the device gives this Mac.
`poll` (seconds) asks again every two seconds while the device answers 204 (still working on an install), and `expect`
(`json` or `xml`, with `equals` or `contains`) is what the answer must say for the step to count, else it fails with the
device's words. A form value `"@{certificate}"` sends Lamp's certificate for a wrapped package (below).

### Values Lamp fills

Write `{name}`; Lamp fills it, checked to a safe alphabet. You never write a value yourself.

- `{address}` the device's address, `{mac}` this Mac's address on that network, `{deviceID}` the device's id
- `{package}` the built package's file, `{appID}` the app's id, `{key}` a remote key from `bridge.keys`, `{text}` text to type
- `{callback}` the sign-in's address back (only in `vendorSignIn.page`), `{signIn}` what that sign-in returned
- `{sshKey}` Lamp's public SSH key, for a device that must be told it
- `{field:<key>}` what the person typed in a step's field: only in a sign-in, a form, a header or a body, never in a path
  or command
- `{read:<step>}` the value a step's check read
- `{cookie:<name>}` a cookie the device set earlier in the same sequence, only in a header (a CSRF token: a GET first,
  then `"X-CSRF-Token": "{cookie:CSRF-Token}"` on the POST)
- `{packageFullName}` and `{appUserModelID}` a wrapped Windows package's names, and `{base64:<one of Lamp's values>}`
  any of Lamp's values in base64, as some devices take an id in a query

### steps

The setup, in order. Each step is done when its `check` passes, never because anyone said so.

```json
{
  "id": "developer-mode",
  "title": "Turn on developer mode",                 // at most 8 words
  "lines": ["Press Home three times on the remote", "Then Up, Up, Right, Left, Right, Left, Right",
            "Choose Enable installer and restart", "Set a developer password when it asks"],   // at most 8 lines, 16 words each
  "wait": true,                                      // hands on the device: Lamp checks again until it passes
  "accepts": ["softwareRisk"],
  "check": [{ "http": { "port": 8060, "path": "/query/device-info" }, "xml": "developer-enabled", "equals": "true" },
            { "tcp": 80 }],
  "known": { "how": "read", "source": "https://developer.roku.com/docs/developer-program/getting-started/developer-setup.md" }
}
```

- `show`: `[{"label": "This Mac", "value": "{mac}"}]`, Lamp's values shown large. `qr`: a value shown as a QR code.
- `field`: `{"key": "password", "label": "Developer password", "secret": true}`, what the person types; kept for that
  device only and sent only to it.
- `link`: an https page to read. A step that roots, jailbreaks or unlocks a device is only ever a link the person
  follows themselves.
- `run`: what Lamp does when the person presses the step's button, in order (primitives below).
- `check`: every condition must hold. Each is one of `http` (answers 2xx; with `json` or `xml`, the value `equals` or
  `contains` something), `tcp` (a port that accepts a connection), `field` (the person typed it), `signedIn` (a
  `vendorSignIn` came back).
- Every setting of the device's that the bridge needs is a step of its own, checked on the device, so it's found in
  setup rather than when a builder first uses it: a Roku answers key presses only with Settings → System → Advanced
  system settings → Control by mobile apps set to Enabled, which its device-info says
  (`{"http": {"port": 8060, "path": "/query/device-info"}, "xml": "ecp-setting-mode", "equals": "enabled"}`).
- `accepts`: what doing it may cost, from Lamp's list; Lamp writes the sentences. `account` (an account with the
  maker), `softwareRisk` (it may stop working until reset), `warranty`, `dataWiped`, `updatesStop`, `protectionsOff`,
  `commandRuns` (required by any step that runs `ssh` or a downloaded `tool`).
- `known`: only `{"how": "read", "source": "<https page>"}`. Lamp marks a step checked or done once it passes on a
  device; the person sees "Not tried yet" until then.

### Primitives

A step's `run` and each bridge sequence are lists of these, one key each:

- `http`: a request (above).
- `probe`: `"tcp:8060"`, `"ssdp:<target>"` or `"bonjour:<type>"`; fails the sequence when the device doesn't answer.
- `stream`: `{"port": 8085}`, the device's log read line by line into the app's log (bridge.logs only).
- `ssh`: `{"user": "prisoner", "port": 9922, "command": "luna-send-pub -n 1 luna://… '{…}'", "explanation": "…"}`.
  The person approves the exact command for that device first, with your explanation (plain words, at most 30). One
  line; values are quoted by Lamp. Lamp pins the device's host key and forwards nothing.
- `tool`: `{"name": "<Lamp's tool>"}`, from Lamp's list (`unlock-device-key`: unlocks a key kept with `keep: "key"`
  with the field `passphrase`), or `{"download": "https://…", "sha256": "<64 hex>", "arguments": […], "explanation": "…"}`
  for another program, which runs confined to its own folder and the network after the person approves it.
- `vendorSignIn`: `{"page": "https://account.vendor.com/…?redirect_uri={callback}"}`, the vendor's page in the
  browser; what comes back is `{signIn}`. Setup steps only.
- `wait`: seconds to wait, 1 to 30.

### bridge

How software goes on the device once it's set up. Each is a sequence of primitives. With `app`, this is all Lamp has
to make apps for the device with, and the builder of each app gets it as Lamp's own: `install` then `launch` when
the person presses Play and at every look, `look` for the picture the builder sees, `use` once for each of the
remote's keys the builder presses (`{key}` is the device's name for it, from `keys`), `logs` read into the app's log
while it's open. What the device answers to `install` is shown to the builder, so a device that says there what it
made of the package (a compile error) needs nothing more. Lamp presses `home` when the app is stopped.

```json
"bridge": {
  "install": [{ "http": { "method": "POST", "port": 80, "path": "/plugin_install",
                          "auth": { "digest": true, "user": "rokudev", "password": "{field:password}" },
                          "form": { "mysubmit": "Install", "archive": "@{package}" } } }],
  "launch":  [{ "http": { "method": "POST", "port": 8060, "path": "/launch/dev" } }, { "wait": 3 }],
  "look":    [{ "http": { "method": "POST", "port": 80, "path": "/plugin_inspect",
                          "auth": { "digest": true, "user": "rokudev", "password": "{field:password}" },
                          "form": { "mysubmit": "Screenshot" } } },
              { "http": { "port": 80, "path": "/pkgs/dev.jpg", "keep": "picture",
                          "auth": { "digest": true, "user": "rokudev", "password": "{field:password}" } } }],
  "use":     [{ "http": { "method": "POST", "port": 8060, "path": "/keypress/{key}" } }],
  "logs":    [{ "stream": { "port": 8085 } }],
  "keys": { "home": "Home", "up": "Up", "down": "Down", "left": "Left", "right": "Right", "select": "Select", "back": "Back" }
}
```

### app

What's built for it: `{"lamp": "tv-web"}` for Lamp's own TV web app, or a kind you declare. A declared kind becomes
a kind of app people can wish for ("a Roku app that…"): `files` is each new app's scaffold, where `{{NAME}}` is the
app's name; `rules` is what its builder is told about writing for the device (the language, the layout, the screen,
how input arrives, where its output is printed), as the only guide they get; `package` is the shell command that
makes the package from the app's folder, run there in the app's sandbox with the system's own tools (`zip`, `tar`),
never anything to download; `output` is where it leaves it, which `"@{package}"` sends.

```json
"app": { "declared": {
  "files": { "manifest": "title={{NAME}}\nmajor_version=1\nmm_icon_focus_hd=pkg:/images/icon_focus_hd.png\n…", "source/main.brs": "sub Main()\n…\nend sub\n" },
  "rules": "What a builder needs to know to write apps for it, in a few sentences.",
  "package": "rm -f build/app.zip && mkdir -p build && zip -r build/app.zip manifest source components images",
  "output": "build/app.zip",
  "icons": { "images/icon_focus_hd.png": "336x210" }
} }
```

The package step runs in the app's sandbox like every build.

`"support"` gives the app Lamp's building blocks (AI through the person's Mac, saved data, the package's own files),
by library to where they go in the app's folder: `"web": "Web/lamp.js"` for an app that's a web page (a script its
`index.html` loads before the app's own), `"brightscript": "components/Lamp"` for a Roku channel (a folder its
components include). Lamp writes them before every build, so keep them out of `files`, and make sure the package step
takes them into the package. Lamp tells the app where it is and gives it its token on the device itself.

`"icons"` gives the app its icon on the device, wherever the device shows one (a channel's poster on a Roku's home
screen, a tile, a launcher): by path in the app's folder to its size in pixels, `"images/icon_focus_hd.png": "336x210"`,
one for each picture the device's manifest names, at the sizes its maker documents. Lamp draws the icon it made for the
app at each path before every build, so name those paths in the scaffold's manifest, keep them out of `files`, and make
sure the package step takes them in. Never draw an icon in the scaffold or the package step. A device that shows no icon
for an app needs none.

`"wrap": "msix"` is for a device that takes Windows app packages (an Xbox in Developer Mode, through its Device
Portal): the package step leaves a `.zip` of the app's files, and Lamp makes the package itself, writing its manifest
(started at `start`, `index.html` unless said), its logos from the app's icon, and its signature with a certificate of
Lamp's. Install it with the package and `"@{certificate}"` in one form, and launch it by `{base64:appUserModelID}` and
`{base64:packageFullName}`. Never write a manifest or sign anything in the package step.

## Checking it before you send

- Every step has a check that asks the device (or a field the step itself asks for).
- Every `{…}` is one of Lamp's values above, and a field is only in a sign-in, form, header or body.
- Titles and lines are short and in plain words, for someone who has never done this.
- A step written from documentation says where (`known.source`).
