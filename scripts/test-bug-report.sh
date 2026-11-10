#!/bin/zsh
# Exercise report generation without opening Lamp or reading anyone's settings or apps.
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
swiftc Sources/Lamp/ErrorMessages.swift Sources/Lamp/BugReport.swift tests/BugReportTests.swift -o "$test_dir/bug-report-tests"
"$test_dir/bug-report-tests"
# Edition names its folders by LampOutsideKit's rule (shared with Lamp's MCP helper), so that module is built first.
swiftc -parse-as-library -emit-library -static -module-name LampOutsideKit Sources/LampOutsideKit/OutsideKit.swift \
  -emit-module -emit-module-path "$test_dir/LampOutsideKit.swiftmodule" -o "$test_dir/libLampOutsideKit.a"
swiftc -I "$test_dir" -L "$test_dir" -lLampOutsideKit Sources/Lamp/Edition.swift Sources/Lamp/BugReportDelivery.swift tests/BugReportDeliveryTests.swift -o "$test_dir/bug-report-delivery-tests"
"$test_dir/bug-report-delivery-tests"
