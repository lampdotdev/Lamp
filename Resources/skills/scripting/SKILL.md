---
name: scripting
description: LampScript, for behavior nobody can write in advance - what happens when two invented things meet, how a new kind of actor acts, a rule the person described in words - with the API it exposes and how scripts are written, cached and run. Read before using it.
---

# Behavior written while the app runs

When the app needs behavior nobody can write in advance (what happens when two invented things meet, how a new kind
of actor acts, a rule the person just described in words), use `LampScript` from LampSupport.swift:

1. Expose a small, well-described API of what scripts may do (spawn, move, remove, say, plus `isTrue`/`ask` for
   judgment).
2. Set `purpose` to a sentence about the app.
3. `write(...)` a script for a cache key, then `run(...)` it.

Scripts are plain JavaScript in a sealed context with a time limit, cached by key in LampStore. Keep rendering,
physics and movement in Swift; scripts decide what should happen, not how to draw it.
