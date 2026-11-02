#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p artifacts
xcrun swiftc -swift-version 5 -O -framework AppKit \
  macos/ActivityModel.swift macos/CounterModel.swift macos/FeedbackModel.swift \
  macos/WardrobeModel.swift macos/OutfitRenderer.swift macos/OutfitPaint.swift \
  macos/OutfitRig.swift macos/CelAnimation.swift macos/CelRenderer.swift \
  scripts/export-assets/main.swift -o artifacts/export-assets
artifacts/export-assets "$PWD/assets"
