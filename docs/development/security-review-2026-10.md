# Security review, October 2026

A review of what becomes readable when Lamp's code is published: the HTTP endpoints Lamp runs on the Mac, the
socket its chat uses, the key a wish's apps share, the functions behind lamp.dev and updates.lamp.dev, and the usage
counts. For each: how a caller is told apart, what someone who isn't the person could do with it, a rating (low,
medium or high) and the fix. Fixes small enough went into the same change as this review and are marked **fixed**;
the rest are recommendations. The rules the design follows are in [approvals and privacy](approvals-and-privacy.md);
what's in scope for a report is in `SECURITY.md`.

**The short version.** No route on the Mac answers without something only its caller should hold: an app's token,
the agent's token for the turn, a one-time ticket, a claim from a device's own address, or a process check by code
signature. Websites can't reach any of it: a browser can't add the `Authorization` header without a preflight, the
preflight is refused on the loopback listener, and a page that rebinds its name to this Mac is turned away by the Host
check. What the design does not try to stop is a program running as the same person, which can read the same files
Lamp reads; that is the Mac's own model and is said where it matters. The medium findings are about what crosses the
local network in clear while an app is on a phone or TV, and about what an anonymous caller can cost the hosted
functions at volume. There is no high finding.

## Who a caller can be

Lamp draws four lines, and each endpoint is read against them:

- **Websites.** A page in any browser, on this Mac or on a device on the same network, must get nothing from Lamp.
- **The agent's commands.** They run confined (`Sandbox`): the app's folder, the system, developer tools, caches and
  the network are open; the rest of the home folder and every Lamp's own folders are closed. So a command can read
  its own app's token (`.lamp/token`, in the app's folder) and the agent's token for the turn (in its environment),
  and nothing of any other app's.
- **The local network.** While an app of the person's is on their phone, tablet, TV or another device, Lamp answers
  on every interface, and what those apps send is plain HTTP.
- **Other programs on this Mac**, running as the person. Lamp keeps them out where it can (a process check by code
  signature where the token alone would not do) and otherwise treats them as the person, as macOS does.

## On this Mac

Each Lamp has four ports of its own (`Edition`): the release's are 47811 (the gateway), 47812 and 47813 (models on this
Mac) and 47814 (the sidebar); Lamp Dev's are 47821 to 47824; a worktree instance's are hashed into 48000 and up. A TV
app's phone page takes one of sixteen more (47840 to 47855 for the release), and the relay between a wish's apps takes a
port the system picks.

### The gateway: 127.0.0.1:47811 (`Gateway.swift`, `Store.handleAI`)

One HTTP server, `Connection: close`, bodies up to 40 MB, JSON in and out. Every request must be a `POST` to one of a
fixed list of paths, with a `Host` header that names this Mac and nothing else (`Store.isLocalHost`: exactly
`127.0.0.1`, `localhost` or `[::1]`, with an optional numeric port; `localhost.evil.example` is not), and a bearer
token. Which token decides which routes answer:

| Routes | Who holds the token | What else is checked |
| --- | --- | --- |
| `/ai`, `/ai/image`, `/ai/decide`, `/ai/status`, `/ai/keys`, `/ai/computer`, `/app/share`, `/app/secrets`, `/app/controller`, `/app/phone-page`, `/app/wish*` | The app: `.lamp/token`, two UUIDs made on first use, in the app's folder (`Template.token`) | `/app/secrets` and `/app/share` also require the calling process to be the installed app, valid by its code signature's designated requirement (`PeerProcess.isApp`), since the agent can read the token |
| `/agent/*`, `/mcp` | The agent, for one turn: two UUIDs made when the turn starts, handed to the engine in its environment, forgotten when the turn ends (`Store.agentTokens`) | Setup finished and the turn still running; loopback only |
| `/pi/key` | pi, once: a ticket good for ten minutes and one redemption (`KeyTicket`) | Loopback only |
| `/agent/computer`, `/mcp` with a task's token | The coding agent driving one computer-use task, for that task's life (`Store.computerTasks`) | Only the task's own tools |
| `/app/claim`, `/app/wish/claim` | Nobody: a device Lamp has just put an app on, asking for its token or its wish's key | Network only, from the address Lamp put the app on, within a window (below) |
| `/browser/*` | Lamp Dev only, behind Settings → Experimental: Chrome's helper signs each message with a secret file (0600) and a nonce; apps use their token | Refused with any `Origin` header |

**Another process on this Mac.** With an app's token (readable by any program running as the person, and by the
agent's commands for the app they're building) it can: use the person's AI through the app's routes, which spends
their key or sign-in; ask `/ai/keys`, which answers only for iPhone apps and only sealed with a secret kept in Lamp's
own folder, so the key doesn't come out; and start computer-use tasks (`/ai/computer`), each step of which the person
approves on Lamp's card in the app's name unless they chose Allow All, and only when they turned the feature on in
Settings → Apps. It cannot read the app's secrets or make its shared file, which need the app's own process. With the
agent's token (in the engine's environment, so the agent's own commands and any program that reads another's
environment have it) it can call the agent's tools, which the agent has anyway, and speak to `/agent/approve` as if
it were the engine's hook: raise an approval card for a command that isn't going to run, or write a "didn't run" line
into the chat (`format=claude-refused`), which could mislead the person about what happened. Low: the lines and cards
are cosmetic, and a command that didn't go through the hook still can't run outside the sandbox.

**A page in a browser.** No. A `POST` with `Authorization` is never a simple request, so the browser asks first with
`OPTIONS`; on the loopback listener `OPTIONS` falls to the method check and gets a 404 with no CORS headers, so the
browser never sends the request. A simple request (`text/plain`, no custom headers) does reach the handler and is
answered 401 or 403 with no `Access-Control-Allow-Origin`, so the page can't read even that. DNS rebinding sends the
page's own name as `Host`, which fails the Host check. No `Host` at all fails it too.

**The network listener** (`Gateway.setLocalNetwork`): on while any app of the person's is set to open on their own
phone or tablet, on a TV, or on a device that takes Lamp's building blocks; off otherwise. Only the app routes answer
there, never the agent's or `/pi/key`, and `Host` must be this Mac's network name or one of its addresses
(`Store.isMacHost`). Responses and `OPTIONS` carry `Access-Control-Allow-Origin: *`, because a web app on a TV has a
package origin and the token is what's checked. Findings:

- **The app's token crosses the Wi-Fi in clear** (medium). Phones and TVs reach the gateway over plain HTTP, so
  anyone who can read the network's traffic has the token from the first request and keeps it: tokens don't change.
  What it buys is above: the person's AI spend, and computer-use tasks that show up as the app's. The OpenRouter key a
  phone keeps is sealed with a secret that went inside the phone's build, never on the air, so the key itself does
  not leak (`Store.keysForPhone`). Fix, in order of size: refuse `/ai/computer` from the network unless the person
  has allowed it for that app, so a sniffed token can't put a request to drive their Mac on their screen; rotate the
  token when an app is put on a device again; and the real one, TLS between device apps and the gateway with a
  certificate Lamp makes and gives each device at install. Each of these changes how device apps behave, so none is in
  this change.
- **A TV gets its token and its wish's key by address** (medium). An app Lamp has just put on a TV has no token in
  its package; it asks `/app/claim` from the TV's address, which Lamp answers for half an hour, any number of times
  (`DeviceSupport.Claims`). Its wish's key comes the same way but sealed to a key pair the TV's page just made, for
  two minutes and only once (`WishClaims`); the code says plainly that someone on the network could put their own
  public key in that one exchange. Addresses on a Wi-Fi network can be taken over. Fix: answer the token claim once
  too, as the key claim is, and show a short code on the TV that the claim must repeat, which a bystander on the
  network wouldn't have. A larger change to the TV flow, so a recommendation.
- **Memory from the network** (low). A connection may hold up to 40 MB of body while it arrives and nothing caps how
  many are open at once. Fix: a small cap on connections in flight from the network, dropping the oldest.
- **A wrong token reloads the app list** (low). Any request with an unknown app token makes Lamp reread every app from
  disk, at most once every five seconds, so a stale app finds its new token. From the network that's a free way to keep
  Lamp rereading. Fix: none needed at that rate; keep the five seconds.
- **Every interface, not just the Wi-Fi** (low). The network listener and the relay bind every interface, so a VPN or
  tunnel the Mac is on is "the local network" too. Fix: bind only interfaces of the Wi-Fi and wired kinds
  (`NWParameters.requiredInterfaceType` won't take two, so a listener per kind), when someone reports it.

### A TV app's phone page: 47840 to 47855 (`PhoneSites`, `Gateway.startSite`)

`GET` and `HEAD` only, on every interface, no token: a phone opening the QR code's link has none. It serves the staged
copy of the app's `Phone/` folder and nothing else (no step up, nothing hidden, only plain files), with `nosniff`,
`no-store` and no referrer, while the app runs in the preview or on a TV. Anyone on the network can read the page while
it's served, and the agent is told so. Low; nothing to fix.

### The relay between devices (`LampRelay`, a port the system picks, WebSocket)

Phones joining a TV app's game hold a credential Lamp or the relay signed (`ControllerToken`: HMAC under a key that
lives only in memory, for one app, one session generation, with a lifetime). A wish's apps join their wish's room by
proving they hold the wish's key (below). Without either, a socket gets a challenge and nothing more, and the relay
rate-limits what each peer sends. Low.

### The sidebar's socket: 127.0.0.1:47814 (`Sidebar.swift`, `SidebarServer.Listener`)

The chat beside a Mac app is drawn by an extension Lamp signs into every app, in a sandboxed process that reaches Lamp
on this port. There is no token. Lamp finds which process is on the other end by matching the connection's port
against the sockets of every process running a sidebar's program (`PeerProcess.find`, libproc), then checks that
process's code against the hashes of the extensions Lamp itself signed for that app (`SecCodeCheckValidity` with a
`cdhash` requirement; the hashes are in Lamp's folder, never the app's, which the agent writes). Anything else is
closed before a byte of the chat goes out.

- **Another process on this Mac** connects and is closed. Each attempt costs one scan of every process's file
  descriptors on the main actor, so a program connecting in a loop would make Lamp's window stutter (low; the same
  scan serves `/app/secrets`). Fix: accept on a background queue and check there.
- **Before Lamp runs**, a program could bind the port and play Lamp to the extension, which doesn't check who it
  talks to: the person would see a chat that isn't Lamp's and what they typed would go to the impostor. Low, since the
  program already runs as the person. Fix: have the extension check Lamp's code signature on the other end the same
  way, when the chat moves to a Unix socket in Lamp's folder.
- **A page in a browser** can't speak the protocol and isn't an extension Lamp signed: nothing.

### Computer use and the page reader

A coding agent driving another app's task gets a token for that task only, and each step the person approves on
Lamp's card (`ComputerUse`). Codex's own computer-use server is a local process over standard input, not a port. The
sidebar's page reader reaches the internet only through `PublicOnlyProxy`, a `CONNECT` proxy on a loopback port the
system picks, which looks each name up and refuses any that leads to this Mac, the local network or another range
that isn't the internet. It has no token: another program on this Mac could tunnel to public addresses through it
while a page is being read, which gives it nothing it didn't have. Low.

## The wish hub's shared key (`WishHub.swift`, `WishChannel`)

**How it's made.** 32 random bytes (`WishChannel.random`), the first time an app of a wish needs it.

**Where it's kept.** `~/Library/Application Support/Lamp/Wish Keys/<wish instance>`, mode 0600 in a 0700 folder, in
Lamp's own folder: never in the wish's, which the agent's commands read and shared files and versions carry. A rename
keeps it (by instance); deleting the wish deletes it.

**How it reaches each app**, by ways nothing on the network can read: a Mac app's installed copy and a phone's build
inside Lamp's folder (`Template.wishKeyPlistLines`), the simulator's app folder after the install, an Android app's own
storage through adb, the TV preview through its bridge on this Mac, and a TV over the network only sealed to a key
pair the TV's page just made (`WishRooms.claim`, X25519 and AES-GCM), inside the two-minute, one-answer claim above.

**What a device on the same network can do without it.** It can see each app's hello (an eight-byte tag derived from
the key, which names the wish without naming it, and a fresh nonce) and the relay's challenge; it can't answer the
challenge, so it never joins. What the apps say after joining is sealed with keys made from the wish's key and the
handshake, with a counting nonce, so a recording can't be read, replayed, reordered or trimmed without the link
noticing. The code names two limits honestly: every app of a wish holds the same key, so a device that has one of the
wish's apps can join as any of them; and there's no forward secrecy, so someone who records the traffic and later gets
the key reads it. The key leaves Lamp's folder only sealed, so "later gets the key" means getting into the Mac or a
device's app data. Low, apart from the TV claim window rated above.

## The website and the update service (Vercel)

Secrets (the Slack webhook, the Upstash token, the OpenRouter key, the GitHub token) are environment variables on
Vercel and never in the repository or the app; nothing a request holds is logged. Every function that writes refuses a
browser from another site by its `Origin` header and counts callers by the client address Vercel sets, in expiring
Upstash counters under a keyed hash of the address. A tool like `curl` sends no `Origin`, so "Lamp is the only caller"
is a description of the honest caller, not something the functions can check: the quotas are the real limit, and the
findings below are what an anonymous caller can do inside them. `vercel.json` adds `nosniff`, a referrer policy and
`X-Frame-Options: DENY` to every path.

| Function | Takes | Limits | Anonymous, at volume |
| --- | --- | --- | --- |
| `bug-report` | `POST`, `text/plain`, a report | 16,384 bytes, read while streaming; 3 an hour per address, 10 an hour, 30 a day | Fill the day's 30 with junk, so real reports are refused until it resets; put any name in the text |
| `first-idea` | `POST`, JSON: a situation or the visitor's words, up to three turns | 8 KB; 30 an hour per address, 1,500 an hour, 9,000 a day; the model's instructions stay on the server | Spend the site's OpenRouter credit up to the day's quota |
| `idea-event` | `POST`, a 200-byte event from fixed lists | 300 an hour per address; a day's tally of counts, nothing typed | Skew the counts |
| `wishes` | `POST` a wish (name 60, line 140, words 2,000 characters, a PNG or JPEG up to 1.5 MB, a square PNG icon up to 300 KB); `PUT`/`DELETE ?id=` with the link's secret | 2.6 MB a body; 10 shares or changes an hour per address, 200 an hour, 1,000 a day; 60 takedowns an hour per address; only the secret's hash is kept | Store up to about 1.8 GB of pictures a day, and 1,000 records a day that never expire |
| `wish-file` | `PUT` a part (raw bytes), `POST` to join them, `DELETE`, each with the link's secret | 3 MB a part, 6 parts, 16 MB a file; 40 parts an hour per address, 3,000 a day; joining counts as a share | Store up to 16 GB of files a day within the share quota, and 9 GB of parts |
| `wish-page` | `GET /w/<id>` | Cached a minute at the CDN; `noindex`; the words reach the page as JSON in a script that isn't run | Guess ids: 58 bits, so no |
| `wish-card` | `GET /w/<id>/card.png` | Cached an hour in browsers and a day at the CDN, by the full address | Draw the card again and again with a different `?v=`, each a 15-second function |
| `appcast` | `GET` | Cached five minutes at the CDN; reads ten releases from GitHub | Little: the cache absorbs it |
| `download` | `GET ?tag=` | Two GitHub calls per request against the token's hourly budget; **now cached a minute at the CDN** | Spend the GitHub token's hourly budget, so updates and downloads fail for everyone until it refills |
| `engines` | `GET` | Static JSON | Nothing |

Findings:

- **The update service could be taken down for an hour at a time** (medium, **fixed** in part). A fine-grained
  GitHub token has an hourly budget of calls, and `download` made two per request with nothing cached, so a few
  thousand requests would leave `appcast` and every download failing until the hour turned. The redirect now carries
  `Cache-Control: public, s-maxage=60`, so the CDN answers repeats for a minute (GitHub's signed link lives five). A
  caller who varies the query string still reaches the function, so the full fix is to serve the DMG from somewhere
  that needs no token per download: a public release on a public repository once the code is open, or a copy in Blob
  written by the release workflow.
- **Storage can be filled** (medium). Shares are capped by count, not by bytes, and a record stays until the sharer
  takes it down, so a day of the quota is on the order of 18 GB of Blob and 1,000 records that never expire; the free
  tier of either would be gone in days. Fix: a byte budget a day beside the counts (the quota script with `INCRBY`),
  a usage alert on the Blob store, and expiry for records nobody has opened in a year. Larger than a few lines, so a
  recommendation. Within the same handler, two parts sent at once can each read the record before the other writes
  it, which loses one part's address and leaves its bytes in Blob (low): the next join notices a part is missing, and
  the takedown script removes what a record names, so the orphan is the only cost.
- **The first-idea conversation costs money per call** (medium). The quotas bound it to 9,000 calls a day, each a
  prompt of a few hundred words and up to 4,000 tokens back, which at the current model's prices is tens to a few
  hundred dollars a day if someone runs it flat out from many addresses. The real ceiling is the monthly credit limit
  on the OpenRouter key, which `FIRST_IDEA.md` asks for at setup: check it is set. Fix beyond that: a lower day quota,
  or a daily token budget in the same counters.
- **The bug-report channel can be jammed and spoken into** (low). Thirty reports a day is the most Slack ever sees,
  and a report has no sender: the text is whatever the caller wrote, name included, and the team reads it as such.
  Fix: none in code; the person who reads the channel knows reports are anonymous text.
- **The card can be redrawn at will** (low). Each `?v=` is a new cache key and a new run of `@vercel/og`. Fix: answer
  only the `v` that matches the wish's `updated` time and redirect the rest to it, so there is one cacheable address.
- **The shared file is served from Blob as it was sent** (low). Lamp checks the file before building anything from
  it, and the page says so. Nothing to fix.

## Usage counts (`Analytics.swift`)

Fixed-word events to PostHog under a random id made on this Mac, with no person profile; never text, names, paths or
keys; nothing from Lamp Dev. Until this change there was no way to turn them off, which the README and Help said. Now
**Send usage counts to the Lamp team** in Settings → Memory turns them off (default on), and with it off `capture`
returns before building a payload, so nothing is sent or logged. Help → AI & Privacy and the README say where the
switch is.

## Findings at a glance

| Finding | Rating | Status |
| --- | --- | --- |
| Device apps' tokens cross the Wi-Fi in clear; a sniffed one spends AI and can put computer-use requests on the screen | Medium | Recommended: refuse `/ai/computer` from the network unless allowed per app; rotate tokens; TLS to the gateway |
| A TV's token claim is answered by address, many times, for half an hour | Medium | Recommended: one answer, and a code shown on the TV |
| `download` spends the GitHub token's budget two calls at a time | Medium | Fixed in part (CDN cache); recommended: serve DMGs without a token |
| Shared wishes are capped by count, not bytes, and never expire | Medium | Recommended: byte budget, Blob alert, expiry |
| First-idea calls cost per call up to 9,000 a day | Medium | Check the key's credit limit; recommended: lower or budget the day |
| Agent can raise cards and write lines in its own chat through the approval route | Low | None |
| Network bodies up to 40 MB with no cap on open connections | Low | Recommended: cap |
| Unknown tokens reread the app list every five seconds | Low | None |
| Listeners bind every interface | Low | Recommended when reported |
| Sidebar connections cost a process scan on the main actor | Low | Recommended: background queue |
| A port squatter could play Lamp to the sidebar before Lamp runs | Low | Recommended with a Unix socket |
| Page-reader proxy has no token | Low | None |
| Bug reports are anonymous text, 30 a day | Low | None |
| Wish card redrawn per `?v=` | Low | Recommended: one address |
| Concurrent parts can orphan a blob | Low | Recommended with the byte budget |
| Usage counts had no switch | Low | Fixed |

No route on the Mac was found answering without the check it should have, and no function was found without a size
cap or a quota.
