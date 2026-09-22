#!/usr/bin/env bash
# Builds the KDE Store release archives (one per category) plus a
# SHA-256 checksum file, into dist/. Meant to be run by CI (see
# .github/workflows/release.yml) but works identically run locally.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO/dist"

VERSION="$(python3 -c "
import json
print(json.load(open('$REPO/src/look-and-feel/com.a1ecbr0wn.phosphor/metadata.json'))['KPlugin']['Version'])
")"

echo "Building version $VERSION"
python3 "$REPO/tools/build.py"

rm -rf "$DIST"
mkdir -p "$DIST"

archive() {
    local name="$1" srcdir="$2"
    local out="$DIST/phosphor-${name}-${VERSION}.tar.gz"
    # Archive root is the package contents (metadata.json etc. at top
    # level), not an extra wrapping directory — that's what kpackagetool6
    # and the KDE Store both expect to unpack.
    tar -czf "$out" -C "$srcdir" .
    echo "  $out"
}

echo "Building archives..."
archive "globaltheme" "$REPO/src/look-and-feel/com.a1ecbr0wn.phosphor"
archive "wallpaper" "$REPO/src/wallpaper/Phosphor"

# The colour scheme is a single file, not a KPackage directory.
COLORS_STAGE="$(mktemp -d)"
cp "$REPO/src/look-and-feel/com.a1ecbr0wn.phosphor/contents/colors" "$COLORS_STAGE/Phosphor.colors"
archive "colors" "$COLORS_STAGE"
rm -rf "$COLORS_STAGE"

echo "Writing checksums..."
(cd "$DIST" && sha256sum ./*.tar.gz > SHA256SUMS)
cat "$DIST/SHA256SUMS"

echo
echo "Release archives in $DIST"
