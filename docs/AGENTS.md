# Public docs site (`docs/`)

This folder is Lamp's public documentation, a self-contained [Mintlify](https://mintlify.com) workspace meant
for [docs.lamp.dev](https://docs.lamp.dev).

## What belongs here

What someone using Lamp needs: installing it, choosing an AI, building and changing apps, versions, sharing,
privacy and troubleshooting.

## What does not belong here

Building Lamp from source, releasing it, how it works inside, and anything else for people who work on Lamp.
That stays in the repo's `README.md`, `RELEASING.md` and `CLAUDE.md`.

## Voice

- Write for someone who has never built software. Plain words, short sentences, one idea at a time.
- No Terminal, no commands to type, no file paths, and no names of files, types or frameworks. If the only
  fix for a problem is a command, leave the problem out and say so in the pull request.
- Call things what the app calls them, and put the exact name of a button or menu in bold: **New App**,
  **Undo Last Change**, **Settings → Building**. Check the name in the app's source before writing it.
- Say "Apple's app-building tools", as the app does.
- The app is **Lamp**. The three ways to build are **Claude Code**, **ChatGPT** and **Lamp Agent** in the
  welcome; Settings calls ChatGPT's builder **Codex**.
- Explain a term the first time it appears ("a key, which is a long password that…").

## Keeping docs in step

`Sources/Lamp/Help.swift` is the guide inside the app, and these pages cover the same ground. When a change
alters what the user sees or does, update Help and the matching page here in the same change.

When adding a page, add it to `docs.json`, and run `npm run check` in this folder before committing.
