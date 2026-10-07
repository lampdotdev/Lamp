#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
phone_replay_bin="$(mktemp -d)/phone-replay"
trap 'rm -rf "${phone_replay_bin:h}"' EXIT
swiftc -parse-as-library Sources/Lamp/PhoneFailure.swift Sources/Lamp/PhoneLaunch.swift Tests/PhoneInstall/Replay.swift -o "$phone_replay_bin"
"$phone_replay_bin" Tests/PhoneInstall/Fixtures "$@"
