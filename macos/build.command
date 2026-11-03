#!/bin/zsh
set -euo pipefail
task_source_dir="$(cd "$(dirname "$0")" && pwd)"
task_output_dir="$(dirname "$task_source_dir")"
task_app="${1:-$task_output_dir/敲敲.app}"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
task_arch="${TASK_ARCH:-$(uname -m)}"
xcrun swiftc -swift-version 5 -O -target "${task_arch}-apple-macos13.0" \
    -framework AppKit -framework CoreGraphics -framework Carbon \
    "$task_source_dir/ActivityModel.swift" "$task_source_dir/PressInputModel.swift" "$task_source_dir/CounterModel.swift" "$task_source_dir/ScreenSizing.swift" "$task_source_dir/FeedbackModel.swift" \
    "$task_source_dir/OutfitPaint.swift" "$task_source_dir/OutfitRig.swift" "$task_source_dir/OutfitReview.swift" \
    "$task_source_dir/CelAnimation.swift" "$task_source_dir/CelRenderer.swift" "$task_source_dir/CelPreviews.swift" \
    "$task_source_dir/WardrobeModel.swift" "$task_source_dir/OutfitRenderer.swift" "$task_source_dir/PetView.swift" "$task_source_dir/WardrobeView.swift" \
    "$task_source_dir/ReminderModel.swift" "$task_source_dir/ReminderView.swift" \
    "$task_source_dir/TimerModel.swift" "$task_source_dir/TimerView.swift" "$task_source_dir/TimerIntegration.swift" "$task_source_dir/TimerTests.swift" \
    "$task_source_dir/AppController.swift" "$task_source_dir/ResponseProbe.swift" "$task_source_dir/main.swift" \
    -o "$task_app/Contents/MacOS/QiaoQiao"
cp "$task_source_dir/Info.plist" "$task_app/Contents/Info.plist"
if [ -f "$task_source_dir/AppIcon.icns" ]; then cp "$task_source_dir/AppIcon.icns" "$task_app/Contents/Resources/"; fi
mkdir -p "$task_app/Contents/Resources/StarCels"
cp "$task_source_dir/Assets/Frames/"*.png "$task_source_dir/Assets/Frames/manifest.json" "$task_app/Contents/Resources/StarCels/"
cp "$task_source_dir/MG-STYLES-15-LICENSE.txt" "$task_app/Contents/Resources/"
codesign --force --deep --sign - "$task_app"
if [[ "$task_arch" == "$(uname -m)" ]]; then
    "$task_app/Contents/MacOS/QiaoQiao" --self-test
fi
echo "构建完成：$task_app"
