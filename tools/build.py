#!/usr/bin/env python3
"""Render KDE colour/theme files from palette/phosphor.toml.

Usage: tools/build.py

Reads the single palette source, renders:
  - src/look-and-feel/com.a1ecbr0wn.phosphor/contents/colors             (KDE colour-scheme file)
  - src/look-and-feel/com.a1ecbr0wn.phosphor/contents/lockscreen/colossus.jpg (lock screen image)
  - src/desktoptheme/phosphor/colors                                    (Plasma desktop theme colours)
  - src/wallpaper/Phosphor/contents/images/<W>x<H>.jpg                  (desktop wallpaper)

Both wallpaper photos are packaged into the repository itself — never
referenced from ~/Pictures/Backgrounds — so an installed theme is portable
to any machine. The desktop wallpaper (shells.JPG) goes into its own
Plasma/Wallpaper KPackage; the lock screen photo (colossus.JPG) is bundled
inside the look-and-feel package since kscreenlockerrc just needs a fixed
file path, not a KPackage of its own.

Checks WCAG contrast ratios for body, muted and link text against the
ground colour, refusing to run if any drops below 4.5:1 or a colour is
malformed.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PALETTE_FILE = REPO / "palette" / "phosphor.toml"
# Committed into the repo (not read from ~/Pictures/Backgrounds) so the
# build is reproducible anywhere, including CI.
DESKTOP_WALLPAPER_SOURCE = REPO / "assets" / "photos" / "shells.JPG"
LOCKSCREEN_WALLPAPER_SOURCE = REPO / "assets" / "photos" / "colossus.JPG"

LOOKANDFEEL_DIR = REPO / "src" / "look-and-feel" / "com.a1ecbr0wn.phosphor"
LOOKANDFEEL_COLORS = LOOKANDFEEL_DIR / "contents" / "colors"
LOCKSCREEN_IMAGE_DEST = LOOKANDFEEL_DIR / "contents" / "lockscreen" / "colossus.jpg"
DESKTOPTHEME_COLORS = REPO / "src" / "desktoptheme" / "phosphor" / "colors"
WALLPAPER_IMAGES_DIR = REPO / "src" / "wallpaper" / "Phosphor" / "contents" / "images"

MIN_CONTRAST = 4.5


def hex_to_rgb(value: str) -> tuple[int, int, int]:
    value = value.strip()
    if not value.startswith("#") or len(value) != 7:
        raise ValueError(f"malformed colour value: {value!r}")
    try:
        r = int(value[1:3], 16)
        g = int(value[3:5], 16)
        b = int(value[5:7], 16)
    except ValueError as exc:
        raise ValueError(f"malformed colour value: {value!r}") from exc
    return r, g, b


def rgb_str(value: str) -> str:
    r, g, b = hex_to_rgb(value)
    return f"{r},{g},{b}"


def _channel_linear(c: int) -> float:
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


def relative_luminance(value: str) -> float:
    r, g, b = hex_to_rgb(value)
    rl, gl, bl = _channel_linear(r), _channel_linear(g), _channel_linear(b)
    return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl


def contrast_ratio(a: str, b: str) -> float:
    la, lb = relative_luminance(a), relative_luminance(b)
    lighter, darker = max(la, lb), min(la, lb)
    return (lighter + 0.05) / (darker + 0.05)


def load_palette() -> dict:
    with PALETTE_FILE.open("rb") as f:
        return tomllib.load(f)


def check_contrast(p: dict) -> None:
    ground = p["surface"]["ground"]
    checks = {
        "body text (text.normal on surface.ground)": (p["text"]["normal"], ground),
        "muted text (text.muted on surface.ground)": (p["text"]["muted"], ground),
        "link text (accent.link on surface.ground)": (p["accent"]["link"], ground),
    }
    failures = []
    for label, (fg, bg) in checks.items():
        ratio = contrast_ratio(fg, bg)
        status = "OK" if ratio >= MIN_CONTRAST else "FAIL"
        print(f"  contrast {label}: {ratio:.2f}:1 [{status}]")
        if ratio < MIN_CONTRAST:
            failures.append(label)
    if failures:
        print(f"\nContrast below {MIN_CONTRAST}:1 for: {', '.join(failures)}", file=sys.stderr)
        sys.exit(1)


def render_colors_file(p: dict) -> str:
    s, a, t, sem, sel, wm = (
        p["surface"], p["accent"], p["text"], p["semantic"], p["selection"], p["wm"]
    )

    def role(fg=None, bg_normal=None, bg_alt=None):
        lines = []
        if bg_normal is not None:
            lines.append(f"BackgroundNormal={rgb_str(bg_normal)}")
        if bg_alt is not None:
            lines.append(f"BackgroundAlternate={rgb_str(bg_alt)}")
        lines += [
            f"DecorationFocus={rgb_str(a['primary'])}",
            f"DecorationHover={rgb_str(a['hover'])}",
            f"ForegroundActive={rgb_str(a['primary'])}",
            f"ForegroundInactive={rgb_str(t['muted'])}",
            f"ForegroundLink={rgb_str(a['link'])}",
            f"ForegroundNegative={rgb_str(sem['negative'])}",
            f"ForegroundNeutral={rgb_str(sem['neutral'])}",
            f"ForegroundNormal={rgb_str(fg if fg else t['normal'])}",
            f"ForegroundPositive={rgb_str(sem['positive'])}",
            f"ForegroundVisited={rgb_str(a['link_visited'])}",
        ]
        return "\n".join(lines)

    out = []
    out.append("[ColorEffects:Disabled]")
    out.append(f"Color={rgb_str(t['faint'])}")
    out.append("ColorAmount=0")
    out.append("ColorEffect=0")
    out.append("ContrastAmount=0.65")
    out.append("ContrastEffect=0")
    out.append("IntensityAmount=0.1")
    out.append("IntensityEffect=2")
    out.append("")

    out.append("[ColorEffects:Inactive]")
    out.append("ChangeSelectionColor=true")
    out.append(f"Color={rgb_str(t['muted'])}")
    out.append("ColorAmount=0.025")
    out.append("ColorEffect=2")
    out.append("ContrastAmount=0.1")
    out.append("ContrastEffect=2")
    out.append("Enable=false")
    out.append("IntensityAmount=0")
    out.append("IntensityEffect=0")
    out.append("")

    out.append("[Colors:Button]")
    out.append(role(bg_normal=s["button"], bg_alt=s["button_alt"]))
    out.append("")

    out.append("[Colors:Selection]")
    out.append(f"BackgroundNormal={rgb_str(sel['background'])}")
    out.append(f"BackgroundAlternate={rgb_str(sel['background'])}")
    out.append(f"DecorationFocus={rgb_str(a['primary'])}")
    out.append(f"DecorationHover={rgb_str(a['hover'])}")
    out.append(f"ForegroundActive={rgb_str(sel['foreground'])}")
    out.append(f"ForegroundInactive={rgb_str(t['normal'])}")
    out.append(f"ForegroundLink={rgb_str(a['link'])}")
    out.append(f"ForegroundNegative={rgb_str(sem['negative'])}")
    out.append(f"ForegroundNeutral={rgb_str(sem['neutral'])}")
    out.append(f"ForegroundNormal={rgb_str(sel['foreground'])}")
    out.append(f"ForegroundPositive={rgb_str(sem['positive'])}")
    out.append(f"ForegroundVisited={rgb_str(a['link_visited'])}")
    out.append("")

    out.append("[Colors:Tooltip]")
    out.append(role(bg_normal=s["tooltip"], bg_alt=s["tooltip"]))
    out.append("")

    out.append("[Colors:View]")
    out.append(role(bg_normal=s["panel"], bg_alt=s["panel_alt"]))
    out.append("")

    out.append("[Colors:Window]")
    out.append(role(bg_normal=s["ground"], bg_alt=s["panel"]))
    out.append("")

    out.append("[Colors:Header]")
    out.append(role(bg_normal=s["ground"], bg_alt=s["ground"]))
    out.append("")

    out.append("[General]")
    out.append(f"ColorScheme={p['meta']['color_scheme_name']}")
    out.append(f"Name={p['meta']['name']}")
    out.append("shadeSortColumn=true")
    out.append("")

    out.append("[KDE]")
    out.append("contrast=4")
    out.append("")

    out.append("[WM]")
    out.append(f"activeBackground={rgb_str(wm['active_background'])}")
    out.append(f"activeBlend={rgb_str(wm['active_foreground'])}")
    out.append(f"activeForeground={rgb_str(wm['active_foreground'])}")
    out.append(f"inactiveBackground={rgb_str(wm['inactive_background'])}")
    out.append(f"inactiveBlend={rgb_str(wm['inactive_background'])}")
    out.append(f"inactiveForeground={rgb_str(wm['inactive_foreground'])}")
    out.append("")

    return "\n".join(out)


def render_desktoptheme_colors(p: dict) -> str:
    s, a, t = p["surface"], p["accent"], p["text"]
    out = []
    out.append("[Colors:Window]")
    out.append(f"BackgroundNormal={rgb_str(s['ground'])}")
    out.append(f"ForegroundNormal={rgb_str(t['normal'])}")
    out.append("")
    out.append("[Colors:View]")
    out.append(f"BackgroundNormal={rgb_str(s['panel'])}")
    out.append(f"ForegroundNormal={rgb_str(t['normal'])}")
    out.append("")
    out.append("[Colors:Selection]")
    out.append(f"BackgroundNormal={rgb_str(a['primary'])}")
    out.append(f"ForegroundNormal={rgb_str(s['ground'])}")
    out.append("")
    out.append("[Colors:Tooltip]")
    out.append(f"BackgroundNormal={rgb_str(s['tooltip'])}")
    out.append(f"ForegroundNormal={rgb_str(t['normal'])}")
    out.append("")
    return "\n".join(out)


def copy_desktop_wallpaper() -> None:
    if not DESKTOP_WALLPAPER_SOURCE.exists():
        print(f"desktop wallpaper source not found: {DESKTOP_WALLPAPER_SOURCE}", file=sys.stderr)
        sys.exit(1)
    dims = subprocess.run(
        ["identify", "-format", "%wx%h", str(DESKTOP_WALLPAPER_SOURCE)],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    WALLPAPER_IMAGES_DIR.mkdir(parents=True, exist_ok=True)
    # Clear any stale resolution-named file from a previous source image.
    for old in WALLPAPER_IMAGES_DIR.glob("*.jpg"):
        old.unlink()
    dest = WALLPAPER_IMAGES_DIR / f"{dims}.jpg"
    shutil.copyfile(DESKTOP_WALLPAPER_SOURCE, dest)
    print(f"  desktop wallpaper -> {dest.relative_to(REPO)} ({dims}, native resolution, no crop/colour changes)")


def copy_lockscreen_wallpaper() -> None:
    if not LOCKSCREEN_WALLPAPER_SOURCE.exists():
        print(f"lock screen wallpaper source not found: {LOCKSCREEN_WALLPAPER_SOURCE}", file=sys.stderr)
        sys.exit(1)
    LOCKSCREEN_IMAGE_DEST.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(LOCKSCREEN_WALLPAPER_SOURCE, LOCKSCREEN_IMAGE_DEST)
    print(f"  lock screen wallpaper -> {LOCKSCREEN_IMAGE_DEST.relative_to(REPO)} (native resolution, no crop/colour changes)")


def main() -> None:
    palette = load_palette()

    print("Checking contrast ratios:")
    check_contrast(palette)

    LOOKANDFEEL_COLORS.parent.mkdir(parents=True, exist_ok=True)
    LOOKANDFEEL_COLORS.write_text(render_colors_file(palette) + "\n")
    print(f"\n  wrote {LOOKANDFEEL_COLORS.relative_to(REPO)}")

    DESKTOPTHEME_COLORS.parent.mkdir(parents=True, exist_ok=True)
    DESKTOPTHEME_COLORS.write_text(render_desktoptheme_colors(palette) + "\n")
    print(f"  wrote {DESKTOPTHEME_COLORS.relative_to(REPO)}")

    copy_desktop_wallpaper()
    copy_lockscreen_wallpaper()

    print("\nBuild complete.")


if __name__ == "__main__":
    main()
