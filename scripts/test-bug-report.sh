#!/bin/zsh
# Exercise report generation without opening Lamp or reading anyone's settings or apps.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc Sources/Lamp/BugReport.swift tests/BugReportTests.swift -o "$test_dir/bug-report-tests"
"$test_dir/bug-report-tests"
