# Services the person already uses

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

### Services the person already uses

An app reaches the person's account on a service they use (Notion, Linear, Airtable, GitHub, Readwise…) in one of two
ways, or open data that needs no account in a third, and every service an app can connect to is one entry in
`Connectors.all` (Sources/Lamp/Connectors.swift): its
name, what people keep there, how it connects, its API's documentation and a few lines on the calls that matter.
The builder finds them through the `connectors` tool, which lists them and, given one, says how to build on it
(`Connectors.answer`), so the system prompt has one line about connectors however many there are
(`Agent.connectorRules`, which keeps the Mac's own accounts first and `LampComputer` after, and names open data
too, since a wish for the weather or exchange rates isn't about an account). Each entry's
declaration in LampSupport.swift (`LampService.<id>`, `LampAPI.<id>`) is written from the same entry
(`Connectors.fill`, in place of `{{SIGN_IN_SERVICES}}` and `{{TOKEN_SERVICES}}`), so what the builder is told is what
the app has. A service is added only when the person can connect without anyone registering an app first; one that
needs a developer app, a secret key that can spend money, or whose terms forbid an app collecting its tokens (Jira
and Confluence's API tokens) doesn't belong.

**Signing in on the service's page** (`LampService`, `LampServiceButton`; Mac apps only): through the service's own
MCP server. Nobody registers anything beforehand: Connect finds the service's sign-in addresses the way MCP
describes them (the server's 401 names its resource description, which names the authorization server), registers
the app with the service under its own name (dynamic client registration, no secret), and opens the service's page
in the browser with PKCE. Each address is trusted only as far as the document before it vouches for it (`discover`):
the resource description must be on the service's own https origin and name that server, its authorization server
must be https and its description must name itself as `issuer`, and every sign-in address must be on that server's
origin; anything else stops the sign-in before the browser opens. No request of the sign-in follows a redirect, its
description fetches included, so each document comes from the address that was vouched for.
`ServiceSignInTests` runs this against the services' recorded answers and against changed copies of them.
The service sends the person back to this Mac's own address (`127.0.0.1`, a listener open
only while that sign-in waits, which ignores anything that isn't the answer to it), and the app trades the code for
its sign-in. Disconnect forgets the sign-in here and asks the service to end both its keys, writing each answer
(never a key) to the app's log. What a service says when it refuses is cut to one short line before the app shows it
(`brief`). Calls are the
service's own MCP tools (`call`, `tools`); after a sign-in the app writes the tool
list, with no account data, to `.lamp/runtime/services/` for the builder. Not on iPhone yet: a phone can't keep the
listener open while the browser is in front.

**A personal token** (`LampAPI`, `LampAPIButton`; every kind of app): for a service whose own site lets the person make
one. Connect opens a sheet with one sentence on what to do, a link to the service's page and a field for each thing
to paste (the token, and for Harvest the account number); the app asks the service's address for checking a token
before keeping it. Calls are the service's REST API (`get`, `post`, `patch`, …)
with paths relative to its `base`: a path that leads anywhere else (another site, a scheme, above the base) is
refused before anything is sent, and no request follows a redirect, so the token goes only to the service.
A 401 means the token is over and it's forgotten; a 403 is asked of the check address again, since Toggl Track says
403 for a token it doesn't take where others say it of one thing the token may not see. Disconnect forgets the
token here; it still works until the person deletes it on the service. `TokenServiceTests` runs this against each
service's recorded answer to a wrong token. A service that runs on the person's own server (Home Assistant) has
`{server}` in its base and its token page, and an address field on the sheet: what they type is cut to its scheme,
host and port (`LampAPI.server`; with no scheme, http for a home-network name or a number, as such servers come,
https otherwise), kept with the token, and the token goes only there.

**Open data** (`LampAPI` with no fields; Open-Meteo, Open Food Facts, Frankfurter): no account and no key, so no
Connect, no sheet and no button; it is always connected and the app calls it as it opens. It keeps `LampAPI`'s paths
relative to its base, plus a full address under one of its own other hosts (`also`: Open-Meteo answers air quality
and place names elsewhere). Only services free to read without signing up belong here, and their terms (credit,
limits) go in the entry's notes for the builder.

Both kinds are kept by Lamp for the app, not in the app's own Keychain (`LampSecrets` in LampSupport.swift,
`AppSecrets` and `/app/secrets` in Lamp): Lamp's certificate has no Apple team, so macOS ties an item an app makes to
the one build that made it and asks for the login password after every rebuild, while Lamp is the same program from
build to build. Lamp keeps them as it keeps its own keys (the Keychain when it is signed for a team, else a file only
this user can read), each app's under its instance (so an app made later under the same folder name doesn't inherit
them), and forgets them when the app is deleted. The app's token is in its folder, where the agent can read it, so
Lamp answers only the app itself (`PeerProcess.isApp`): the process on the other end of the connection must run from
where Lamp installed the app and pass that installed copy's designated requirement; `AppSecretsTests` runs real
processes against it. Two things keep that check from being passed by a process the builder's shell starts as the
app: every Mac app is built with a `__RESTRICT` segment (buildSh), so dyld ignores `DYLD_INSERT_LIBRARIES` and the like
for it — LiveReload's `dlopen` from inside the app is unaffected — and the agent's sandbox refuses `process-exec` under
the apps folder, since exec needs no read the profile closes. A connection therefore opens only while Lamp is open. On
iPhone `LampSecrets` stays the device's Keychain, which asks nothing, and an app that keeps its own secrets again is
one line (`LampSecrets.store`). Neither kind is ever in the app's folder, so a shared copy arrives disconnected and is
flagged in the review (`Sharing.checklist`). How to build on each is in its doc comment in LampSupport.swift, which the tool's answer
sends the builder to.

**A service that isn't listed** can still be called from the app's own code. When it needs a key, the app declares
it with `LampAPI.own` (its API's address, the page where the key is made, one sentence of steps, how the key is
sent: a header or a query parameter, and a path to check it) and uses `LampAPIButton`, so the person pastes the key
on the same Connect sheet as a listed service's, it is checked, kept in `LampSecrets` under a name of its own
(`own-…`, so it can't stand in for a listed service's token), and sent only to that address. No key field or dialog
of the app's own, and never UserDefaults, LampStore or a Keychain item of the app's own: the first two are the app's
settings and folder, and the last asks for the password after every rebuild. Both `Agent.connectorRules` and the
tool's list (`Connectors.list`, also its answer to a name it doesn't know) say so. Such a service's address must be
https (`httpsOnly`: nothing is sent otherwise), while a listed one's may be the person's own server on plain http.
The review counts `LampAPIButton`, `LampAPI.own` and `LampSecrets.` in the app's code as connecting an account, and
open data alone as going online.

