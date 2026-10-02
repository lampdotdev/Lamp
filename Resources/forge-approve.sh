#!/bin/sh
# Hook command for Claude Code and Codex: sends the tool call (JSON on stdin) to Forge, which waits for the
# user's decision if needed and prints the answer in the hook's format. If Forge can't be reached, curl
# exits non-zero, so the call isn't approved by this hook.
exec curl -sf --max-time 3600 -X POST -H "Authorization: Bearer $FORGE_TOKEN" \
  -H 'Content-Type: application/json' --data-binary @- "$FORGE_APPROVE_URL"
