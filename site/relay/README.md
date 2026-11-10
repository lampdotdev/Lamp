# Relay prototype: a game's page changed by the player's own agent

**A prototype, run locally only.** Nothing here is deployed, and lamp.dev's own page for a shared game
(`/w/<id>`, SHARED_WISHES.md) is untouched.

Someone playing a shared game asks for a change in the game's page. A helper on their own Mac (`lamp play <code>`)
runs their own coding agent on a copy of the game, and the rebuilt game comes back into the page.

```bash
node site/relay/relay.mjs --game path/to/a/static/game     # the relay, with a stand-in page at http://127.0.0.1:4700/w/demo
node cli/lamp.mjs play ABC234                                # on the player's Mac, with the code the page shows
```

## The parts

| Part | What it is | Stand-in? |
| --- | --- | --- |
| `relay.mjs` | Plain Node, no dependencies, outside the site's Vercel functions: rooms, codes and builds are kept in its memory, which a function doesn't keep. | The relay itself would need a home that keeps a process running. |
| `page.html`, `page.js`, `page.css` | The game's page: the pairing code, the game in a frame, a box to ask for a change, and each new version put into the frame. | **Yes**: a stand-in for `/w/<id>`, labeled as one on screen. |
| The game | The folder given with `--game`, served as version 1 of every room. | **Yes**: on lamp.dev it's the link's page in Blob. |
| `cli/play.mjs` | `lamp play <code>`, the helper. | No |
| `cli/play-guard.mjs` | The check Claude Code runs before each tool call: file tools only, inside the game's copy only. | No |

## How it holds together

- **Both sides dial in.** The page and the helper each keep an event stream open to the relay (SSE) and send with
  POST. Nothing connects to the player's Mac.
- **Secrets, not origins.** Opening a room gives the page a secret of its own. The code it shows is six characters,
  works once, runs out after five minutes, and an address gets five tries a minute. The helper trades the code for its
  own secret. Every later call carries one of the two, in a header, never in an address. The page reads its event
  stream with fetch for that reason, rather than EventSource.
- **Origins add to that.** The page's POSTs must come from the page's own origin, and anything a browser sends to the
  helper's side is refused. So a game in the frame can't send a request even with a secret it guessed.
- **The game plays on another site.** Each room's game is served from a host of its own (`<room>.localhost`, as
  lamp.dev uses `<id>.play.lamp.dev`). That host holds no secret and can only be framed by the page.
- **One request at a time, each once.** The page makes each request's id. A request sent again with the same id is
  the one already taken. The relay sends the helper what it hasn't finished whenever the helper connects again. The
  helper keeps a journal of what it took and how each ended, so a repeat is answered and never run again. One the
  helper was running when it stopped is reported as not done.
- **The agent is confined.** Claude Code runs with `--restricted` (no tools that run code, no user, project or local
  settings, file tools held to the working folder), `--strict-mcp-config` with no servers, `--tools
  Read,Edit,Write,Glob,Grep`, and a PreToolUse hook (`play-guard.mjs`, given with `--settings`) that refuses any other
  tool and any path outside the copy once links are resolved. An agent's own files (`.claude/`, `CLAUDE.md`,
  `AGENTS.md`, every hidden file) never go into the copy, so a game can't bring its own hooks, settings, MCP servers or
  instructions.
- **One whole version after a run that worked.** Only once the agent has finished does the helper pack the copy, as
  the site packs a page: nothing hidden, none of an agent's files, no links (a link refuses the build), nothing shaped
  like a key, at most 3,000 files and 64 MB, and 32 MB packed. It sends that as one new version. After a failed run, the
  copy goes back to the last version sent and the page keeps showing it. The relay unpacks a build with the site's own
  `readZip`: no traversal, no links, within the limits.
- **Static games only.** Nothing of the game's runs on the Mac: no build, no install, and the agent has no shell.

## Not done here

- Codex (`--agent codex`) is wired behind the same interface and **has not been run**. Its workspace-write sandbox
  confines writes and commands, but it still reads anywhere on the Mac, and its network setting doesn't cover every
  tool an MCP server could add.
- The helper's secret lives only in its process. A helper that stops can't rejoin its room. Reloading the page opens a
  new room with a new code.
- Rooms and builds live only in the relay's memory, with no limit on how many rooms it keeps.
