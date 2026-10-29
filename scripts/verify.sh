#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
mkdir -p build/verification
bash scripts/build.sh > build/verification/build.log 2>&1
python3 Tests/make_fixtures.py
rm -f build/verification/mock-port.txt
python3 Tests/mock_api.py > build/verification/mock-api.log 2>&1 &
mock_pid=$!
trap 'kill "$mock_pid" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
  if [ -s build/verification/mock-port.txt ]; then break; fi
  sleep 0.1
done
swiftc -parse-as-library -swift-version 5 -target "$(uname -m)-apple-macos14.0" -O \
  -framework SwiftUI -framework AppKit \
  Sources/Weekspace/Model.swift Sources/Weekspace/Importer.swift Sources/Weekspace/Store.swift \
  Tests/IntegrationTests.swift -o build/verification/IntegrationTests
build/verification/IntegrationTests "$(cat build/verification/mock-port.txt)" "$REPO_ROOT/build/verification/fixtures" > build/verification/integration.log 2>&1
cat build/verification/build.log build/verification/integration.log
