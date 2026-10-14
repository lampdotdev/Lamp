#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/../.."
SIGN_IDENTITY=- ./build.sh
