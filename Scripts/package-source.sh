#!/bin/zsh

set -euo pipefail

ROOT="${0:A:h:h}"
VERSION="$(/usr/bin/plutil -extract CFBundleShortVersionString raw "$ROOT/Resources/Info.plist")"
PACKAGE_NAME="Granular-$VERSION-source"
STAGE_ROOT="$ROOT/.build/source-package"
STAGE="$STAGE_ROOT/$PACKAGE_NAME"
ARCHIVE="$ROOT/dist/$PACKAGE_NAME.zip"

rm -rf "$STAGE_ROOT"
mkdir -p "$STAGE" "$ROOT/dist"

/usr/bin/rsync -a --prune-empty-dirs \
    --exclude '/.build/' \
    --exclude '/.git/' \
    --exclude '/.pnpm-store/' \
    --exclude '/dist/' \
    --exclude '/.DS_Store' \
    --exclude '/Icon/' \
    --exclude '/Website/.next/' \
    --exclude '/Website/.openai/' \
    --exclude '/Website/.vinext/' \
    --exclude '/Website/.wrangler/' \
    --exclude '/Website/dist/' \
    --exclude '/Website/node_modules/' \
    --exclude '/Website/outputs/' \
    --exclude '/Website/work/' \
    --exclude '/Website/worker/' \
    "$ROOT/" "$STAGE/"

chmod +x \
    "$STAGE/Build Granular.command" \
    "$STAGE/Scripts/build-app.sh" \
    "$STAGE/Scripts/package-source.sh"

rm -f "$ARCHIVE"
pushd "$STAGE_ROOT" >/dev/null
COPYFILE_DISABLE=1 /usr/bin/zip -qry "$ARCHIVE" "$PACKAGE_NAME"
popd >/dev/null
/usr/bin/unzip -tq "$ARCHIVE"

echo "$ARCHIVE"
