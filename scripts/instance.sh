#!/bin/zsh
# Which development build this checkout makes (see Sources/Lamp/Edition.swift): a name that keeps one worktree's
# Lamp Dev apart from another's, so two can run at once. LAMP_INSTANCE names it outright (empty for the plain
# "Lamp Dev"); without it, a checkout under a .claude/worktrees folder is named after its folder, and any other
# checkout makes the plain Lamp Dev. Printed with nothing else, for build.sh and the scripts to read.
if [ -n "${LAMP_INSTANCE+set}" ]; then name="$LAMP_INSTANCE"
else
  here="${0:A:h}/.."
  case "${here:A}" in */.claude/worktrees/*) name="${${here:A}:t}" ;; *) name="" ;; esac
fi
# Part of a bundle id and a URL scheme: letters, digits and hyphens only.
print -r -- "${${(L)name}//[^a-z0-9-]/-}"
