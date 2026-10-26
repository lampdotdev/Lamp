---
name: device-control
description: How an app controls, plays to or reads the person's own devices on their home network (a TV, speakers, a console, lights) when Lamp has no block for them - finding each one, working out its local API, writing it into the app, and asking the person before changing anything on a real device. Read before writing code that reaches one of their devices.
---

# Controlling the person's devices

A remote for the TV and speakers, buttons that open the family's apps, what's playing in the menu bar: the app talks
to devices that are really in the person's home. Work out each one from what it says about itself, and never change
anything on a real one until the person has said you may.

## What's there

- Call `network_devices` first: what Lamp's own look found, with what it already has for each device. Start from
  that, not from a question about what the person owns, and ask only about what it can't tell you.
- In the app, find devices with `LampNetwork` (the building-blocks skill): `requestAccess()` after the app has said
  why, then `find()`. Give capabilities.json a `localNetwork` reason in the app's own words, and the Bonjour types
  of the devices it's for in `bonjourServices` (an iPhone app can look for no others).
- A Roku is `LampRoku`'s. Use it rather than writing ECP yourself.
- A device's maker and model say what it is. Its services say only what it can do: a console and a TV both answer as
  media renderers, and a Mac offers AirPlay, so none of them is a speaker for that.

## Working out a device

For a device Lamp has no block for, find how its maker's own phone app talks to it on the home network, from what it
says about itself: its SSDP answer and UPnP description (`location`), its Bonjour services and TXT record, its model.
Most have a local API: an HTTP or SOAP service (Sonos on port 1400, UPnP's AVTransport and RenderingControl), a
WebSocket (Samsung's remote channel, LG's second-screen socket), or a documented REST API. Read it from the device
(its description, a status endpoint) before relying on it. Some can't be reached this way: pairing that needs
cryptography of the maker's own (Apple TV, a Google TV's remote), or control only through the maker's cloud account.
Say so plainly in a sentence instead of half-building it.

## Writing it

- One file per kind of device, behind one small protocol the rest of the app uses, so a new kind is one more file:
  what it can do (keys, apps, text, volume, power, what's playing) and how. The screen asks a device what it can do,
  never which kind it is: a TV without volume over the network shows no volume buttons.
- Reach only addresses that discovery found, or one the person typed.
- A device that signs its own secure socket (an LG's 3001, a Samsung's 8002) is trusted for that address alone,
  never every certificate the app meets.
- A token a device hands back after the person allows the app on its screen is kept with the device in LampStore:
  it only lets an app on this network reach that one device, and the remote must work with Lamp closed, which
  `LampSecrets` on a Mac doesn't. A sign-in to the maker's account is the person's: `LampSecrets`, never LampStore.
- When the device asks the person on its own screen (Allow on a TV), the app says so while it waits, and what to do
  if they missed it.
- Example devices for exploring with nothing found, clearly marked, sending nothing.

## Asking before changing a device

Reading a device is always fine: what it is, its apps, what's playing, its volume. Changing one is the person's to
allow: a key press, opening an app, the volume, the input, power, a setting. Before the first change on a device, by
a command or by using the app (`use_app`), call `device_permission` with the device as the person knows it, its address,
and what you'd do, and end your turn. Lamp shows the card and keeps the answer: "Allow once" covers this request, "Always for"
the device covers the wish. Lamp refuses `use_app` on an app that reaches devices unless its `device` names one the person allowed,
and every engine's check refuses a command that changes a device without it. When the answer is "Not now", leave the
device alone and say how the person can try it themselves.
