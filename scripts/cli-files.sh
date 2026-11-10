#!/bin/zsh
# Writes the files lamp's command line (cli/) takes from Lamp's own code: the list of controllers a game's runtime
# reads (cli/lamps/lamp-controllers.js, committed, and checked by CLIFilesTests), and a new Mac app's starting files
# (cli/lamps/mac-starter, made here and not committed, for `lamp new --mac`). Run it after either changes.
set -euo pipefail
cd "${0:A:h}/.."
LAMP_WRITE_CLI_FILES=1 swift test --filter CLIFilesTests
echo "Written: cli/lamps/lamp-controllers.js and cli/lamps/mac-starter"
