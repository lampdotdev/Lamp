#!/bin/zsh
# Writes the files lamp's command line (cli/) takes from Lamp's own code: the list of controllers a game's runtime
# reads (cli/lamps/lamp-controllers.js, committed, and checked by CLIFilesTests), and a new Mac app's starting files
# (cli/lamps/mac-starter, for `lamp new --mac`), a new web app's (cli/lamps/web-starter, for `lamp new --web`) and Lamp's
# building blocks for a page and for a game's (cli/lamps/lamp.js, lamp-for-games.js), made here and not committed; and the example of an Xbox's package
# the command line's own package maker is held to (cli/tests/fixtures/msix, committed). Run it after any of them changes.
set -euo pipefail
cd "${0:A:h}/.."
LAMP_WRITE_CLI_FILES=1 swift test --filter CLIFilesTests
echo "Written: cli/lamps/lamp-controllers.js, lamp.js, mac-starter and web-starter, and cli/tests/fixtures/msix"
