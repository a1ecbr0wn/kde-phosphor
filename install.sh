#!/usr/bin/env bash
# Installs the Phosphor components into ~/.local/share.
# Does not apply the theme — run apply.sh afterwards for that.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Building from palette..."
python3 "$REPO/tools/build.py"

install_or_upgrade() {
    local type="$1" path="$2"
    if kpackagetool6 --type "$type" --install "$path" 2>/dev/null; then
        return
    fi
    kpackagetool6 --type "$type" --upgrade "$path"
}

echo "Installing look-and-feel package..."
install_or_upgrade "Plasma/LookAndFeel" "$REPO/src/look-and-feel/com.a1ecbr0wn.phosphor"

echo "Installing desktop theme..."
install_or_upgrade "Plasma/Theme" "$REPO/src/desktoptheme/phosphor"

echo "Installing wallpaper..."
# Static image wallpapers are not KPackage plugins (those need a QML
# ui/main.qml) — they're just files under ~/.local/share/wallpapers/<Name>/.
mkdir -p "$HOME/.local/share/wallpapers"
rm -rf "$HOME/.local/share/wallpapers/Phosphor"
cp -r "$REPO/src/wallpaper/Phosphor" "$HOME/.local/share/wallpapers/Phosphor"

echo "Installing colour scheme..."
mkdir -p "$HOME/.local/share/color-schemes"
cp "$REPO/src/look-and-feel/com.a1ecbr0wn.phosphor/contents/colors" \
   "$HOME/.local/share/color-schemes/Phosphor.colors"

echo "Rebuilding the system configuration cache..."
kbuildsycoca6 >/dev/null 2>&1 || true

if ! rpm -q kwin-decoration-oxygen >/dev/null 2>&1 && \
   ! dpkg -s kwin-decoration-oxygen >/dev/null 2>&1 && \
   ! [ -e /usr/lib/x86_64-linux-gnu/qt6/plugins/org.kde.kdecoration2/oxygendecoration.so ] && \
   ! find /usr/lib* -iname '*oxygendecoration*' -print -quit 2>/dev/null | grep -q .; then
    echo "Warning: the Oxygen window decoration does not appear to be installed." >&2
    echo "  Phosphor requests Oxygen; KWin will fall back to its own default decoration (Breeze) instead." >&2
fi


# Not `grep -q`: with pipefail, grep -q can close the pipe as soon as it
# finds the first match, which SIGPIPEs fc-list before it finishes
# writing — that failure (exit 141) then outranks grep's own success.
# Reading to completion (no -q, redirect instead) avoids it.
if ! fc-list | grep -i "DM Mono" >/dev/null; then
    echo "Warning: the 'DM Mono' font was not found (fc-list)." >&2
    echo "  The theme sets it as the fixed-width font; install it for the intended look." >&2
fi

echo "Done. Run ./apply.sh to apply the theme."
