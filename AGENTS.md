# Working on Forge

Forge is a Mac app that builds other Mac apps with an LLM agent. Read `README.md` for what it is and
`RELEASING.md` for how it ships. This file is for whoever (or whatever) edits the code.

## Keep the agent harnesses in step

Forge drives three coding agents, chosen in Settings → Building: **pi** (bundled), **Claude Code** and
**Codex**. They are set up in `Sources/Forge/Engines.swift` (`Agent.run`), one `case` per engine, and
the output of each is read by its own parser there (`parseClaude`, `parseCodex`, and pi's in
`Agent.parseLine`).

A capability given to one engine must be given to all of them that can take it, in the same change:

- **Tools the agent calls** (`look_at_app`, `use_app`, …): pi gets them from `Resources/forge-tools.ts`;
  Claude Code and Codex get them from Forge's MCP endpoint, `Store.mcp` (`/mcp` on the gateway). Both
  define the same tools with the same descriptions and schemas, so a change to one is a change to the other.
- **Rules in the system prompt** (`Agent.systemPrompt`, `Agent.tryRules`, `Agent.toolRules`): `tryRules`
  are for the tools every engine has; `toolRules` adds pi-only ones. When you add a tool to
  the MCP endpoint, its rule belongs in `tryRules`, not `toolRules`.
- **Approvals and privacy**: shell commands go through `/agent/approve` for every engine (pi's extension,
  Claude Code's hooks, Codex's hooks); file access outside the app's folder is checked the same way.
- **What Forge shows the user** (`BuildCard.activity`, `ToolCall`): tool names must be recognised in every
  engine's spelling. Claude Code calls MCP tools `mcp__forge__<name>`; `Engines.plainName` strips that.
  Codex reports them as `mcp_tool_call` items.
- **Models**: each engine has its own model list and picker (`Builder.engineModel`); never default to Haiku.

Before opening a PR that touches any of this, check each engine's `case` in `Agent.run` and its parser,
and say in the PR description which engines you tried.

## Generated apps

`Sources/Forge/Template.swift` holds `ForgeSupport.swift`, the support code copied into every generated
app (`ForgeAI`, `ForgeStore`, `ForgeScript`, the connectors, `ForgeDriver` for `use_app`). It is a Swift
string: after editing it, extract and type-check it (`swiftc -typecheck`), and bump anything that detects
an outdated app (`Store.open` rebuilds apps built by an older Forge).

## Conventions

- Comments explain why, in plain prose; user-facing text never names files, types or frameworks.
- Verify in an isolated harness app rather than in the user's apps.
- No attribution lines in commits or PR descriptions.
