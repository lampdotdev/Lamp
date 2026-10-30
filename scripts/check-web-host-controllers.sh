#!/bin/zsh
# Runs the Xbox host's phones protocol (Resources/WebHost/lamp_controllers.h) on this Mac: the same C++ the host is built
# with, over POSIX sockets (Tests/WebHost/posix_host.cpp) in place of the console's, with a game's page and phones
# driven by Tests/WebHost/controllers.mjs over real HTTP and WebSockets. A check of the protocol, not of the console:
# the host itself (lamp_web_host.cpp) only runs on an Xbox.
set -euo pipefail
cd "${0:A:h}/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
clang++ -std=c++20 -Wall -Wextra -Werror -O1 -o "$work/posix_host" Tests/WebHost/posix_host.cpp
mkdir -p "$work/Phone"
print '<!doctype html><title>test phone page</title>' > "$work/Phone/index.html"
print '{"only":["api.example.com","x.test; script-src *"]}' > "$work/Phone/lamp-reach.json"
print 'outside the page' > "$work/secret.txt"
print 'hidden' > "$work/Phone/.hidden"
node Tests/WebHost/controllers.mjs "$work/posix_host" "$work/Phone"
