#!/bin/zsh
# Writes the files lamp's command line (cli/) takes from Lamp's own code: the list of controllers a game's runtime
# reads (cli/lamps/lamp-controllers.js, committed, and checked by CLIFilesTests), and a new Mac app's starting files
# (cli/lamps/mac-starter, for `lamp new --mac`), a new web app's (cli/lamps/web-starter, for `lamp new --web`) and Lamp's
# building blocks for a page and for a game's (cli/lamps/lamp.js, lamp-for-games.js) and Lamp's Android app around a page
# (cli/lamps/android-host, for `lamp open --on android`), made here and not committed. Run it after any of them changes.
# (Lamp's app writes the same into the copy of lamp it carries as it's built: `CLIFiles`, build.sh.)
set -euo pipefail
cd "${0:A:h}/.."
LAMP_WRITE_CLI_FILES=1 swift test --filter CLIFilesTests
echo "Written: cli/lamps/lamp-controllers.js, lamp.js, mac-starter, web-starter and android-host"
