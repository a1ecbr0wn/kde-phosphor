#!/usr/bin/env bash
# Removes every installed Phosphor component. Does not touch backups made
# by apply.sh, and does not revert the active theme — run
# `apply.sh --restore` first if you want your previous look back.
set -euo pipefail

kpackagetool6 --type Plasma/LookAndFeel --remove com.a1ecbr0wn.phosphor 2>/dev/null || true
kpackagetool6 --type Plasma/Theme --remove phosphor 2>/dev/null || true
rm -rf "$HOME/.local/share/wallpapers/Phosphor"
rm -f "$HOME/.local/share/color-schemes/Phosphor.colors"

kbuildsycoca6 >/dev/null 2>&1 || true

echo "Uninstalled."
