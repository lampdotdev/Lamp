# Lamp's controller relay

Phones become controllers for a TV app made with Lamp. The relay:

- hands out each session's phone page at an address of the session's own (`https://<session>.<pages host>/`), so no two
  apps' pages share an origin, and over https, which phones' browsers want before they give a page their motion
  sensors;
- passes each phone's buttons, sticks and tilt to the session's host (the TV app, or Lamp for the preview on the Mac)
  and small messages back, with a beat every five seconds both ways;
- keeps nothing: no message is written down, a session lives in memory and goes ten minutes after its host leaves,
  or after twelve hours.

Its credentials are its own (`credentials.js`): a host's for the session's life, a join link's for fifteen minutes, a
phone's for two minutes and renewed over its socket. None is Lamp's token for an app's AI.

## Running it

```sh
node relay/server.js            # http://localhost:8787, phone pages at http://<session>.localhost:8787
node --test relay/test/*.test.js
```

Lamp finds it through the `controllerRelay` setting or `LAMP_CONTROLLER_RELAY`
(`open -n "Lamp Dev.app" --args -controllerRelay http://localhost:8787`). Locally a phone page is plain http on this
Mac, which a browser on this Mac treats as secure (`*.localhost`); a real phone needs the hosted relay's https.

Settings, all optional:

| | |
|---|---|
| `PORT`, `BIND` | where it listens (8787, 127.0.0.1) |
| `RELAY_SECRET` | the key credentials are signed with, as hex; a new one at each start when unset |
| `RELAY_API` | its public address, which Lamp is given (`https://ctl.example.dev`) |
| `RELAY_PAGES` | the phone pages' addresses, with `{session}` (`https://{session}.ctl.example.dev`) |

## Hosting it

It's one Node process with no dependencies and no storage, so it runs as it is on any machine that keeps a process up
and passes WebSockets: one small always-on machine (Fly.io's smallest, or a small VPS), behind TLS for the API's name
and a wildcard certificate for the pages' names, with wildcard DNS pointing at it. Sessions live in that one process,
so a second machine needs sessions kept to one machine each (by session id) before it helps.
