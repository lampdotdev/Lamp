#!/bin/zsh
# Runs the Xbox host's network guard for shared apps (Resources/WebHost/lamp_web_guard.h) on this Mac: the same C++ the
# host is built with, asked each question the host asks (Tests/WebHost/guard_host.cpp), with a hostile page
# (Tests/WebHost/hostile) run in headless Chrome, whose DevTools stand in for WebView2's request event
# (Tests/WebHost/guard.mjs). Chromium is the engine WebView2 is, so the page's policy is held as it would be on a
# console; the host itself (lamp_web_host.cpp) only runs on an Xbox. CHROME names another Chrome or Chromium.
set -euo pipefail
cd "${0:A:h}/.."
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
[[ -x "$chrome" ]] || { print -u2 "No Chrome at $chrome: set CHROME to a Chrome or Chromium."; exit 1; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
clang++ -std=c++20 -Wall -Wextra -Werror -O1 -o "$work/guard_host" Tests/WebHost/guard_host.cpp
node Tests/WebHost/guard.mjs "$work/guard_host" Tests/WebHost/hostile "$work" "$chrome"
