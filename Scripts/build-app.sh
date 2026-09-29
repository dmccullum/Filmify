#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/dist/Granular.app"
CONTENTS="$APP/Contents"
ICON_SOURCE_PACKAGE="$ROOT/AppIcon.icon"

cd "$ROOT"

if [[ ! -d "$ICON_SOURCE_PACKAGE" ]]; then
    echo "Missing canonical icon source: $ICON_SOURCE_PACKAGE" >&2
    exit 66
fi

swift build -c release

rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$ROOT/.build/release/Granular" "$CONTENTS/MacOS/Granular"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp -R "$ROOT/Sources/GranularCore/FilmStocks" "$CONTENTS/Resources/FilmStocks"
cp -R "$ROOT/Resources/Fonts" "$CONTENTS/Resources/Fonts"
cp "$ROOT/Resources/THIRD_PARTY_NOTICES.txt" "$CONTENTS/Resources/THIRD_PARTY_NOTICES.txt"
xcrun actool \
    "$ROOT/Resources/Assets.xcassets" \
    "$ICON_SOURCE_PACKAGE" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/.build/Granular-asset-info.plist"

# Icon Composer's macOS fallback can omit several legacy ICNS sizes. Finder
# still relies on those flattened renditions in ordinary folders, even though
# Assets.car contains the dynamic Default, Dark, and tintable icon stacks.
# Export the current Default appearance and build a complete ICNS alongside it.
ICON_TOOL="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"
ICON_SOURCE="$ROOT/.build/AppIcon-default.png"
ICONSET="$ROOT/.build/AppIcon-fallback.iconset"

"$ICON_TOOL" \
    "$ICON_SOURCE_PACKAGE" \
    --export-image \
    --output-file "$ICON_SOURCE" \
    --platform macOS \
    --rendition Default \
    --width 1024 \
    --height 1024 \
    --scale 1

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
iconutil --convert icns --output "$CONTENTS/Resources/AppIcon.icns" "$ICONSET"

# Copied resources and generated icons can carry Finder metadata or resource
# forks that codesign rejects. Clean the assembled bundle before signing it.
/usr/bin/xattr -cr "$APP"

codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$ROOT/Resources/Granular.entitlements" \
    "$APP"

codesign --verify --deep --strict "$APP"
echo "$APP"
