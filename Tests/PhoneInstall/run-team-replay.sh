#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
phone_team_replay="$(mktemp -d)"
trap 'rm -rf "$phone_team_replay"' EXIT
python3 Tests/PhoneInstall/team-replay.py "$phone_team_replay"
swiftc -parse-as-library Sources/Lamp/Subprocess.swift "$phone_team_replay/TeamReplay.swift" -o "$phone_team_replay/replay"
"$phone_team_replay/replay" "$phone_team_replay" "$@"
