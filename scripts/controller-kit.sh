#!/bin/zsh
# Writes Lamp's controller kit, the one file a game on the Mac runs its own phones with (GameKit.controllerKit): every
# Swift file of Sources/LampRelayKit, in name order, for the Mac only. build.sh puts it in Lamp's bundle, where the
# player and every compiled game take it from; scripts/check-starters.sh type-checks games against it.
#
#   scripts/controller-kit.sh OUT.swift
set -euo pipefail
here="${0:A:h}/.."
{
  print "// Lamp's controller kit (Sources/LampRelayKit in Lamp's source, as one file). Written by Lamp before every build; don't edit."
  print "#if os(macOS)"
  for f in "$here"/Sources/LampRelayKit/*.swift(on); do cat "$f"; print; done
  print "#endif"
} > "$1"
