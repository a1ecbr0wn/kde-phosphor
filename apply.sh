#!/usr/bin/env bash
# Applies the installed Phosphor theme to the current session, backing up
# the settings it replaces first. Run install.sh before this.
#
#   ./apply.sh            apply the theme
#   ./apply.sh --restore  restore the settings from before Phosphor was
#                          ever applied
set -euo pipefail

LOOKANDFEEL_ID="com.a1ecbr0wn.phosphor"
COLOR_SCHEME="Phosphor"

# Both wallpapers are installed as part of the theme, not read from
# ~/Pictures/Backgrounds — that folder is specific to this machine and
# won't exist for anyone else who installs Phosphor.
LOCKSCREEN_IMAGE="$HOME/.local/share/plasma/look-and-feel/$LOOKANDFEEL_ID/contents/lockscreen/colossus.jpg"
DESKTOP_WALLPAPER_PKG_DIR="$HOME/.local/share/wallpapers/Phosphor/contents/images"

get_installed_desktop_wallpaper() {
    find "$DESKTOP_WALLPAPER_PKG_DIR" -maxdepth 1 -name '*.jpg' -print -quit 2>/dev/null
}

# A snapshot of "whatever was active immediately before Phosphor was last
# switched to" — refreshed every time apply() runs from a non-Phosphor
# theme, so --restore always undoes the most recent switch. It is only
# left alone when you're already on Phosphor (re-running apply.sh without
# having switched away), since at that point "current settings" *is*
# Phosphor and backing it up would just overwrite the real previous state
# with itself.
BACKUP_DIR="$HOME/.local/share/phosphor-kde/backup/pre-phosphor"

CONFIG_FILES=(kdeglobals kcminputrc kwinrc plasmarc ksplashrc kscreenlockerrc)
DESKTOP_WALLPAPER_FILE="$BACKUP_DIR/desktop-wallpaper-path"

# Plasma renumbers containment IDs across restarts (e.g. 710 -> 736), so a
# raw copy of plasma-org.kde.plasma.desktop-appletsrc can silently target
# containments that no longer exist. Track just the wallpaper *path*
# instead, and reapply it live with plasma-apply-wallpaperimage, which
# works on whatever containments currently exist.
get_desktop_wallpaper() {
    local f="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
    [ -f "$f" ] || return 1
    awk '/^\[Containments\]\[[0-9]+\]\[Wallpaper\]\[org\.kde\.image\]\[General\]$/{found=1; next} found && /^Image=/{print; exit}' "$f" \
        | sed 's/^Image=file:\/\///'
}

refresh_session() {
    qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    # Icon theme and Plasma desktop theme changes don't hot-reload from a
    # config file edit alone; plasmashell needs to restart to pick them up.
    if command -v kquitapp6 >/dev/null 2>&1 && command -v kstart6 >/dev/null 2>&1; then
        kquitapp6 plasmashell >/dev/null 2>&1 || true
        (kstart6 plasmashell >/dev/null 2>&1 &) || true
    fi
    kbuildsycoca6 >/dev/null 2>&1 || true
}

restore() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "No pre-Phosphor backup found at $BACKUP_DIR — apply.sh has never been run." >&2
        exit 1
    fi

    local prev_id
    prev_id="$(kreadconfig6 --file "$BACKUP_DIR/kdeglobals" --group KDE --key LookAndFeelPackage)"

    if [ -n "$prev_id" ] && [ "$prev_id" != "$LOOKANDFEEL_ID" ]; then
        echo "Reapplying previous global theme: $prev_id"
        lookandfeeltool -a "$prev_id" || true
    fi

    echo "Restoring exact settings from $BACKUP_DIR"
    for f in "${CONFIG_FILES[@]}"; do
        if [ -f "$BACKUP_DIR/$f" ]; then
            cp "$BACKUP_DIR/$f" "$HOME/.config/$f"
        fi
    done

    if [ -f "$DESKTOP_WALLPAPER_FILE" ]; then
        local wp
        wp="$(cat "$DESKTOP_WALLPAPER_FILE")"
        echo "Restoring desktop wallpaper: $wp"
        plasma-apply-wallpaperimage "$wp" || true
    fi

    refresh_session
    echo "Restored. Cursor theme may still need a full log out/in to update everywhere."
}

apply() {
    local current_id
    current_id="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)"

    if [ "$current_id" = "$LOOKANDFEEL_ID" ]; then
        echo "Already on Phosphor — leaving the existing backup at $BACKUP_DIR alone."
    else
        mkdir -p "$BACKUP_DIR"
        for f in "${CONFIG_FILES[@]}"; do
            if [ -f "$HOME/.config/$f" ]; then
                cp "$HOME/.config/$f" "$BACKUP_DIR/$f"
            fi
        done
        local wp
        wp="$(get_desktop_wallpaper || true)"
        if [ -n "${wp:-}" ]; then
            echo "$wp" > "$DESKTOP_WALLPAPER_FILE"
        fi
        echo "Backed up settings for '$current_id' to $BACKUP_DIR"
    fi

    echo "Applying colour scheme..."
    # Plasma 6's "Accent Color" (kdeglobals[General] AccentColor) is a
    # separate override layer that beats whatever Selection/Focus colours
    # are literally in the .colors file — clear it so our palette values
    # actually take effect instead of a derived/stuck accent shade.
    kwriteconfig6 --file kdeglobals --group General --key AccentColor --delete
    kwriteconfig6 --file kdeglobals --group General --key LastUsedCustomAccentColor --delete
    # plasma-apply-colorscheme also no-ops ("... is already set as the
    # theme") when the scheme *name* is already active, even if the
    # underlying .colors file content changed since (e.g. after a palette
    # edit + rebuild). Force a real reload by switching away and back.
    if [ "$(kreadconfig6 --file kdeglobals --group General --key ColorScheme)" = "$COLOR_SCHEME" ]; then
        plasma-apply-colorscheme BreezeDark >/dev/null 2>&1 || true
    fi
    plasma-apply-colorscheme "$COLOR_SCHEME"

    echo "Applying global theme..."
    lookandfeeltool -a "$LOOKANDFEEL_ID"

    if [ ! -f "$LOCKSCREEN_IMAGE" ]; then
        echo "Lock screen image not found at $LOCKSCREEN_IMAGE — run ./install.sh first." >&2
        exit 1
    fi
    echo "Setting lock screen wallpaper..."
    kwriteconfig6 --file kscreenlockerrc \
        --group Greeter --group Wallpaper --group org.kde.image --group General \
        --key Image "file://$LOCKSCREEN_IMAGE"

    echo "Setting desktop wallpaper..."
    # lookandfeeltool -a resets the desktop wallpaper to Plasma's fallback
    # default since our package declares no wallpaper default of its own;
    # set it explicitly afterwards, live, for every containment. Desktop
    # and lock screen intentionally use different photos.
    local desktop_wp
    desktop_wp="$(get_installed_desktop_wallpaper || true)"
    if [ -n "${desktop_wp:-}" ]; then
        plasma-apply-wallpaperimage "$desktop_wp" || true
    else
        echo "Desktop wallpaper image not found under $DESKTOP_WALLPAPER_PKG_DIR — run ./install.sh first." >&2
    fi

    refresh_session
    echo "Applied. Cursor theme may still need a full log out/in to update everywhere."
}

if [ "${1:-}" = "--restore" ]; then
    restore
else
    apply
fi
