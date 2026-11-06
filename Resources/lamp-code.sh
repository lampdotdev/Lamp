#!/bin/zsh
# Runs Claude Code on one of Lamp's projects in this terminal ("Work in Claude Code"). Lamp opens it with a ticket that
# is good once; claimed, it gives back everything the session needs (the project's folder, Lamp's rules, tools, hooks
# and the session's token, which lives only in this process and the ones it starts) and the command to run. Claude
# Code runs in the foreground, so it has the terminal; when it ends, for whatever reason, Lamp is told.
emulate -L zsh
base=$1 ticket=$LAMP_TICKET
unset LAMP_TICKET
fail() { print -u2 -- "$1"; print -u2 -- "Close this window and choose Work in Claude Code in Lamp again."; exit 1 }
answer=$(/usr/bin/curl -sf --max-time 30 -X POST -H "Authorization: Bearer $ticket" -H 'Content-Type: application/json' \
  --data "{\"pid\":$$}" "$base/outside/claim") || fail "Lamp didn't start this session."
setup=$(print -r -- "$answer" | /usr/bin/plutil -extract script raw -o - -) || fail "Lamp's answer couldn't be read."
unset answer ticket
eval "$setup" || fail "Lamp's setup couldn't be run."
unset setup
eval "$LAMP_RUN"
/usr/bin/curl -sf --max-time 5 -X POST -H "Authorization: Bearer $LAMP_TOKEN" -H 'Content-Type: application/json' \
  --data '{}' "$LAMP_OUTSIDE_URL/ended" >/dev/null 2>&1
print -- "\nClaude Code has stopped working on $LAMP_WISH_NAME. You can close this window."
