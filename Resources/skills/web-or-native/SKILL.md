---
name: web-or-native
description: Choosing how an app or game is made - native first, in the device's own code, or as a web page Lamp's host shows on each device when one app is shared across devices or native is out of reach - and on which devices, when to ask the person and what to tell them. Read before the first make_app_for of a wish, and before changing how an app is made or adding a device.
---

# Web or native

Every app and game Lamp makes is made one of two ways:

- **Web**: one page (HTML and JavaScript) that Lamp's host shows on each device, the same page everywhere it goes.
- **Native**: the device's own code. Swift for Apple's devices (one code for all of them), Kotlin for Android, and
  what an integration declares for its device.

`make_app_for`'s description has the table of devices: what each one runs, and how a build gets onto it. It refuses
a make Lamp can't build on a device, with the reason, and the request's device line says what Lamp knows of the
person's own devices. Those are the facts, and the only place they're kept; this skill doesn't repeat them.

## Native first

Make an app native wherever the table gives the device a native app: it has the device's own look, feel and
controls. Choose web only when:

- **one app is meant to be shared across several devices or brands**: several people's phones as controllers for a
  TV app, one app on TVs of different makers; or
- **native is out of reach there**: the table has no native app for the device, or what the person wants can't be
  built that way.

This is how you choose a make for a new app, or when the person asks for a change; it's no reason to rewrite an app
the wish has unasked.

- **A make the person names is theirs.** When they ask for a web app, or a native one, make it that way wherever Lamp
  can build it, even where you'd have chosen the other; say in a sentence what that costs only when it matters.
- **Devices found on the network can suggest web, never choose it.** A Samsung TV and an iPhone in the house aren't a
  request for one app shared between them: when sharing one app across them seems to be what the person wants, say
  so or ask, and never switch to web silently.
- **Separate apps that talk don't need web.** The wish's apps reach each other through `LampWish` on whichever
  devices they're on, however each is made (the wish-links skill): an iPhone app and its Android TV app can both be
  native.
- **Never choose web to get around a limit of Lamp's**: two apps of one code in one wish, say (the more-apps
  skill). Say what the limit is instead, and offer what can be done.
- **Never refuse a make that works only because it isn't the one you'd choose.** Only the table, and the refusal it
  gives, says what can't be built.

## What to weigh within that

- **What the app needs from the device.** Native code has the device's own APIs: widgets, the watch, Health, the
  camera and other hardware, work in the background. A page reaches some of the person's things only through Lamp's
  app around it, where there is one (`LampNative`, the web-app skill).
- **How it gets to the people who use it.** Read the table's way onto each device, for each make. On some devices a
  page still comes inside an app of Lamp's that is installed the same way a native app is, so web doesn't save
  installing there.
- **Whose devices, and how many.** One person's own Mac or phone, a family's TV, every phone at a party: who has to
  install or open what. Several people's phones joining one TV app by a link is the shared case above.
- **What it's played or used with.** A remote, a controller, touch, phones in the room: the game skill and the
  phone-controllers skill say what each takes.

When the app needs several devices, it can be one app on all of them where one native code covers them (Swift for
Apple's), or several of the wish's apps, each made natively for its device, that talk through `LampWish`. Adding one
more app to a wish that has one is the person's to choose: the more-apps skill says how to ask.

## When to ask

Only when the answer really changes what you'd make, and only in one line about people and devices, never in the
words "web" or "native": "Is this for your iPhone, or for everyone's phones at the party?" When the request already
says, or a wrong guess is cheap to change, choose, build, and say in a sentence what you chose and how it gets onto
their devices.

## Saying how it gets there

Tell the person how the build reaches each device, as `make_app_for` answers it ("each phone is paired with this Mac",
"each phone joins the TV's game by a link"), so a choice that doesn't suit them shows at once.

## Away from home

Each way of connecting has its own reach, said where it's described: phones joining a TV app's page do it on the same
Wi‑Fi with Lamp open on this Mac (the phone-controllers skill); the wish's own apps find each other on the home
network, and once Lamp has introduced them go on talking with Lamp closed (the wish-links skill, which also says what
reaching each other away from home takes). Lamp runs no relay of its own for players in other homes: when that's what
the person wants, say so plainly, and offer what works (playing on one Wi‑Fi, or another way of connecting, as the
wish-links skill says).

## Changing it later

`make_app_for` with an app's folder in `app` changes how that app is made: it keeps its folder and what it saved, but
the new code doesn't read what the old one saved unless you write it to, and Lamp moves nothing across, so say so when
it matters. One more app beside the others is `another`, only once the person chose that when you asked (the
`more-apps` skill). `remove_app` takes one away, which the person can undo.
