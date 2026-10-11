#!/bin/bash
# Builds Folio.app (release) next to this script.
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=Folio.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Folio "$APP/Contents/MacOS/Folio"

ICONSET=$(mktemp -d)/Folio.iconset
mkdir -p "$ICONSET"
swift scripts/make_icon.swift "$ICONSET/base.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$ICONSET/base.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
rm "$ICONSET/base.png"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Folio</string>
  <key>CFBundleDisplayName</key><string>Folio</string>
  <key>CFBundleIdentifier</key><string>app.folio.reader</string>
  <key>CFBundleExecutable</key><string>Folio</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.books</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key><string>app.folio.reader.item</string>
      <key>UTTypeDescription</key><string>Folio Item</string>
      <key>UTTypeConformsTo</key><array><string>public.data</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
codesign --force --deep -s - "$APP"
echo "Built $(pwd)/$APP"
