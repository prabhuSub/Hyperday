"""Hyperday app icon, v63 "JobTrail Now Line": your day as three blocks in JobTrail's status colours
(blue = done, green = running, dashed amber = waiting) on a black card with the map's dot grid,
crossed by a glowing amber now-line.

    pip install cairosvg && python3 tools/make_app_icon_jt.py
Writes AppIcon (light / dark / tinted, 1024 px) and the small HyperdayMark.
"""
import sys
from pathlib import Path
import cairosvg

AMBER, GREEN, BLUE, PALE = "#E9A23B", "#7AA36A", "#6EA8D9", "#CFEEC2"

DEFS = ('<defs>'
        '<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#161616"/>'
        '<stop offset="1" stop-color="#000"/></linearGradient>'
        '<radialGradient id="halo" cx=".62" cy=".5" r=".55"><stop offset="0" stop-color="#E9A23B" stop-opacity=".22"/>'
        '<stop offset="1" stop-color="#E9A23B" stop-opacity="0"/></radialGradient>'
        '<filter id="glow" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2"/></filter>'
        '</defs>')


def dots() -> str:
    out = []
    for y in range(6, 100, 8):
        for x in range(6, 100, 8):
            out.append(f'<circle cx="{x}" cy="{y}" r=".55" fill="#232323"/>')
    return "".join(out)


def glyph(mono: bool = False) -> str:
    c = (lambda col: "#fff") if mono else (lambda col: col)
    done = f'<rect x="17" y="25" width="38" height="12" rx="6" fill="{c(BLUE)}" opacity="{.5 if mono else .6}"/>'
    run_glow = "" if mono else f'<rect x="29" y="44" width="54" height="12" rx="6" fill="{GREEN}" filter="url(#glow)" opacity=".7"/>'
    run = (f'<rect x="29" y="44" width="54" height="12" rx="6" fill="{c(GREEN)}"/>'
           + ("" if mono else f'<rect x="29.6" y="44.6" width="52.8" height="10.8" rx="5.4" fill="none" stroke="{PALE}" stroke-width=".8" opacity=".55"/>'))
    wait = (f'<rect x="18" y="64" width="34" height="11" rx="5.5" fill="none" stroke="{c(AMBER)}" '
            f'stroke-width="2" stroke-dasharray="3.2 2.6" opacity="{.6 if mono else 1}"/>')
    line_glow = "" if mono else (f'<rect x="60" y="15" width="5" height="70" rx="2.5" fill="{AMBER}" filter="url(#glow)"/>'
                                 f'<circle cx="62.5" cy="16" r="7" fill="{AMBER}" filter="url(#glow)"/>')
    line = (f'<rect x="61" y="16" width="3" height="68" rx="1.5" fill="{c(AMBER)}"/>'
            f'<circle cx="62.5" cy="16" r="4.6" fill="{c(AMBER)}"/>'
            + ("" if mono else '<circle cx="62.5" cy="16" r="1.8" fill="#fff" opacity=".85"/>'))
    return done + run_glow + run + wait + line_glow + line


def svg(variant: str, size: int) -> str:
    head = f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">{DEFS}'
    if variant == "light":
        body = '<rect width="100" height="100" fill="url(#bg)"/>' + dots() + '<rect width="100" height="100" fill="url(#halo)"/>' + glyph()
    elif variant == "dark":      # iOS draws its own dark background behind a transparent icon
        body = glyph()
    else:                        # tinted: white glyph, iOS applies the tint
        body = glyph(mono=True)
    return head + body + "</svg>"


def mark_svg(size: int) -> str:
    # Small rounded-square mark for widgets: JobTrail card with the same glyph.
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{size}" height="{size}" viewBox="0 0 100 100">{DEFS}'
            '<rect width="100" height="100" rx="24" fill="#181818"/>'
            '<rect x="1.5" y="1.5" width="97" height="97" rx="22.5" fill="none" stroke="#313131" stroke-width="3"/>'
            + glyph() + '</svg>')


if __name__ == "__main__":
    root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent
    icon = root / "App/Assets.xcassets/AppIcon.appiconset"
    icon.mkdir(parents=True, exist_ok=True)
    for variant in ("light", "dark", "tinted"):
        cairosvg.svg2png(bytestring=svg(variant, 1024).encode(), write_to=str(icon / f"AppIcon-{variant}.png"))
    for cat in ("App", "Widget"):
        d = root / f"{cat}/Assets.xcassets/HyperdayMark.imageset"
        d.mkdir(parents=True, exist_ok=True)
        cairosvg.svg2png(bytestring=mark_svg(96).encode(), write_to=str(d / "HyperdayMark.png"))
    print("app icon: JobTrail Now Line")
