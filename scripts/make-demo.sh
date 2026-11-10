#!/bin/zsh
# Renders docs/screenshot.png (the README image) from Snap's real overlay code.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build docs
swiftc -O -swift-version 5 -D DEMO \
  Sources/Capture.swift Sources/Overlay.swift Sources/Settings.swift scripts/demo/main.swift \
  -o build/snap-demo
build/snap-demo docs/screenshot.png
