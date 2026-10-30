#!/bin/zsh
# Writes Lamp's controller kit, the one file a game runs its own phones with (GameKit.controllerKit): every Swift file
# of Sources/LampRelayKit, in name order, for the Mac, the iPhone and the iPad (its only Mac-only call, the Mac's
# Bonjour name, is guarded in ControllerAddresses.swift). build.sh puts it in Lamp's bundle, where the player
# and every compiled game take it from; scripts/check-starters.sh and scripts/check-controller-kit.sh
# type-check it.
#
#   scripts/controller-kit.sh OUT.swift
set -euo pipefail
here="${0:A:h}/.."
{
  print "// Lamp's controller kit (Sources/LampRelayKit in Lamp's source, as one file). Written by Lamp before every build; don't edit."
  print "#if os(macOS) || os(iOS)"
  for f in "$here"/Sources/LampRelayKit/*.swift(on); do cat "$f"; print; done
  print "#endif"
} > "$1"
