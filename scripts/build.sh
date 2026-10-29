#!/bin/bash
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
BUILD_DIR="$REPO_ROOT/build"
APP="$BUILD_DIR/周间.app"
ARCH="$(uname -m)"
case "$ARCH" in arm64|x86_64) ;; *) echo "Unsupported architecture: $ARCH" >&2; exit 1;; esac
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/AppIcon.iconset"
swift scripts/Icon.swift "$BUILD_DIR/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$BUILD_DIR/AppIcon.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$BUILD_DIR/AppIcon.png" --out "$BUILD_DIR/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
SOURCE=Sources/Weekspace
swiftc -parse-as-library -swift-version 5 -target "$ARCH-apple-macos14.0" -O \
  -framework SwiftUI -framework AppKit \
  "$SOURCE/Model.swift" "$SOURCE/Importer.swift" "$SOURCE/Store.swift" \
  "$SOURCE/Views.swift" "$SOURCE/CompanionViews.swift" "$SOURCE/Navigation.swift" \
  "$SOURCE/Assistant.swift" "$SOURCE/V2Tests.swift" "$SOURCE/App.swift" \
  -o "$APP/Contents/MacOS/Weekspace"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Weekspace</string>
<key>CFBundleIdentifier</key><string>io.github.gufanyuanying031.weekspace</string>
<key>CFBundleName</key><string>周间</string>
<key>CFBundleDisplayName</key><string>周间</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/Weekspace" --self-test
printf 'Built: %s\n' "$APP"
