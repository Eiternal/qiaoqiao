#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p dist artifacts
TASK_ARCH=arm64 macos/build.command "$PWD/artifacts/arm64/敲敲.app"
TASK_ARCH=x86_64 macos/build.command "$PWD/artifacts/x86_64/敲敲.app"
ditto "artifacts/arm64/敲敲.app" "dist/敲敲.app"
lipo -create "artifacts/arm64/敲敲.app/Contents/MacOS/QiaoQiao" "artifacts/x86_64/敲敲.app/Contents/MacOS/QiaoQiao" -output "dist/敲敲.app/Contents/MacOS/QiaoQiao"
codesign --force --deep --sign - "dist/敲敲.app"
codesign --verify --deep --strict "dist/敲敲.app"
"dist/敲敲.app/Contents/MacOS/QiaoQiao" --self-test
"dist/敲敲.app/Contents/MacOS/QiaoQiao" --presentation-test
python3 scripts/package.py macos
