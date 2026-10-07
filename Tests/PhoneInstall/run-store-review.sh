#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
phone_store_replay="$(mktemp -d)"
trap 'rm -rf "$phone_store_replay"' EXIT
python3 Tests/PhoneInstall/store-review-replay.py "$phone_store_replay/StoreReviewReplay.swift"
swiftc -parse-as-library Sources/Lamp/PhoneFailure.swift "$phone_store_replay/StoreReviewReplay.swift" -o "$phone_store_replay/replay"
"$phone_store_replay/replay" Tests/PhoneInstall/Fixtures/messages.json
