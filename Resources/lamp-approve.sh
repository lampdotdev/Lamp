#!/bin/sh
# Hook command for Codex: sends the tool call (JSON on stdin) to Lamp, which waits for the user's decision if
# needed and prints the answer in the hook's format. If Lamp can't be reached, the call is denied outright:
# an empty answer would let it run.
curl -sf --max-time 3600 -X POST -H "Authorization: Bearer $LAMP_TOKEN" \
  -H 'Content-Type: application/json' --data-binary @- "$LAMP_APPROVE_URL" \
  || printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"Lamp could not be reached, so this was not allowed."}}'
