"""Builds Hyperday's line icons (24pt grid, 1.75pt stroke, round caps) into the asset catalogs as
vector PDFs with template rendering, so SwiftUI tints them like SF Symbols.

    pip install cairosvg && python3 tools/make_icons.py
"""
import json
import shutil
from pathlib import Path

import cairosvg

ICONS = {
    # categories
    "work": '<rect x="3" y="7" width="18" height="13" rx="2"/><path d="M9 7V5.5A1.5 1.5 0 0 1 10.5 4h3A1.5 1.5 0 0 1 15 5.5V7M3 12.5h18"/>',
    "meetings": '<circle cx="9" cy="8.5" r="3"/><path d="M3 19.5c0-3.2 2.7-5.5 6-5.5s6 2.3 6 5.5"/><circle cx="17" cy="9.5" r="2.4"/><path d="M16.5 14.1c2.6.2 4.5 2.1 4.5 5"/>',
    "deepwork": '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/><path d="M12 2.5v2.5M12 19v2.5M2.5 12H5M19 12h2.5"/>',
    "fitness": '<path d="M6.5 7.5v9M17.5 7.5v9M3.5 10v4M20.5 10v4M6.5 12h11"/>',
    "family": '<path d="M3.5 11 12 4.5l8.5 6.5"/><path d="M6 9.5V20h12V9.5M10 20v-5h4v5"/>',
    "personal": '<circle cx="12" cy="8" r="3.5"/><path d="M5 20.5c0-3.9 3.1-6.5 7-6.5s7 2.6 7 6.5"/>',
    "learning": '<path d="M12 6.5c-2-1.5-5-2-8-1.5v13c3-.5 6 0 8 1.5 2-1.5 5-2 8-1.5V5c-3-.5-6 0-8 1.5zM12 6.5v13"/>',
    "health": '<path d="M12 19.5s-7.5-4.4-7.5-9.7A4.3 4.3 0 0 1 12 7.4a4.3 4.3 0 0 1 7.5 2.4c0 5.3-7.5 9.7-7.5 9.7z"/>',
    "travel": '<rect x="5" y="8" width="14" height="11" rx="2"/><path d="M9 8V5.5h6V8M9 19v1.5M15 19v1.5M9 11.5v4M15 11.5v4"/>',
    "errands": '<path d="M5.5 8h13l-1 12h-11z"/><path d="M9 10V7a3 3 0 0 1 6 0v3"/>',
    "social": '<path d="M4 5.5h16v11H10.5L6 20v-3.5H4z"/>',
    "code": '<path d="M8.5 7.5 4 12l4.5 4.5M15.5 7.5 20 12l-4.5 4.5M13.5 5l-3 14"/>',
    "star": '<path d="M12 4l2.4 5 5.4.6-4 3.7 1.1 5.4L12 16l-4.9 2.7 1.1-5.4-4-3.7 5.4-.6z"/>',
    # tabs
    "today": '<path d="M3 18.5h18M7 18.5a5 5 0 0 1 10 0M12 7.5v2.5M5.8 11.3l1.6 1.2M18.2 11.3l-1.6 1.2"/>',
    "calendar": '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
    "stats": '<path d="M5.5 20v-8M12 20V5M18.5 20v-11M3.5 20.5h17"/>',
    "settings": '<path d="M4 7h9M17 7h3M4 17h3M11 17h9"/><circle cx="15" cy="7" r="2"/><circle cx="9" cy="17" r="2"/>',
    # actions
    "add": '<path d="M12 5v14M5 12h14"/>',
    "edit": '<path d="M4 20h4L19 9l-4-4L4 16v4zM13.5 6.5l4 4"/>',
    "delete": '<path d="M4 7h16M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13M10 11v5M14 11v5"/>',
    "move": '<rect x="3.5" y="5" width="13" height="15" rx="2"/><path d="M3.5 10h13M7.5 3v4M12.5 3v4M13 15h8M18 12l3 3-3 3"/>',
    "start": '<path d="M8 5.5v13l10-6.5z"/>',
    "done": '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
    "timer": '<circle cx="12" cy="13.5" r="7.5"/><path d="M12 9.5v4l2.5 1.5M10 2.5h4M18.5 6l1.5-1.5"/>',
    "steps": '<path d="M10 6.5h10M10 12h10M10 17.5h10M3.5 6.5l1.3 1.3L7 5.5M3.5 12l1.3 1.3L7 11"/><circle cx="5.2" cy="17.5" r="1.2"/>',
    "next": '<path d="M5 12h14M14 7l5 5-5 5"/>',
    "back": '<path d="M19 12H5M10 7l-5 5 5 5"/>',
    "share": '<path d="M12 3.5v11M8 7.5l4-4 4 4M5 12v7.5h14V12"/>',
    "close": '<path d="M6 6l12 12M18 6L6 18"/>',
    "sun": '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/>',
    "auto": '<circle cx="12" cy="12" r="8.5"/><path d="M12 3.5v17a8.5 8.5 0 0 0 0-17z" fill="#000"/>',
    "siri": '<path d="M12 4v16M8 8v8M16 8v8M4 11v2M20 11v2"/>',
    "calendar-scan": '<path d="M4 8V5.5A1.5 1.5 0 0 1 5.5 4H8M16 4h2.5A1.5 1.5 0 0 1 20 5.5V8M20 16v2.5a1.5 1.5 0 0 1-1.5 1.5H16M8 20H5.5A1.5 1.5 0 0 1 4 18.5V16M8 10h8M8 14h5"/>',
    "moon": '<path d="M19.5 14.5A8 8 0 0 1 9.5 4.5a8 8 0 1 0 10 10z"/>',
    "recap": '<rect x="4" y="3.5" width="16" height="17" rx="2"/><path d="M8 16v-3M12 16V9M16 16v-5"/>',
    "event": '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/><circle cx="12" cy="15" r="1.4" fill="#000"/>',
    "step-open": '<circle cx="12" cy="12" r="8.5"/>',
    "step-done": '<circle cx="12" cy="12" r="8.5"/><path d="M8 12.3l2.8 2.8L16.2 9.5"/>',
    "step-add": '<circle cx="12" cy="12" r="8.5"/><path d="M12 8.5v7M8.5 12h7"/>',
    "up": '<path d="M7 14l5-5 5 5"/>',
    "down": '<path d="M7 10l5 5 5-5"/>',
    "chevron": '<path d="M10 7l5 5-5 5"/>',
    "free": '<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>',
}

# The widget extension only needs what the Live Activity, Island and widgets draw.
WIDGET = ["edit", "work", "meetings", "deepwork", "fitness", "family", "personal", "learning", "health", "travel",
          "errands", "social", "code", "star", "done", "start", "step-done", "free", "event"]


def svg(body: str) -> str:
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" '
            'stroke="#000" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>')


TABS = ["today", "calendar", "stats", "settings"]


def tab_svg(body: str) -> str:
    # Tab bar (icons only): 36pt canvas, glyph cropped tighter so it fills it; everything (stroke too)
    # scales together, so the icon just gets bigger without changing its look.
    # v22: labels are back (small), so the icon steps down to 31pt to leave room under it.
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="31" height="31" viewBox="2.5 2.5 19 19" fill="none" '
            'stroke="#000" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round">' + body + '</svg>')


def write(catalog: Path, names, tabs=False):
    folder = catalog / "Icons"
    if folder.exists():
        shutil.rmtree(folder)
    folder.mkdir(parents=True)
    (folder / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2))
    items = [(n, f"hd-{n}", svg(ICONS[n])) for n in names]
    if tabs:
        items += [(n, f"hd-tab-{n}", tab_svg(ICONS[n])) for n in TABS]
    if tabs:
        # v27: Calendar tab with today's date, Outlook-style: a rounded page with a header band and no ring tabs,
        # the date big and bold in the body, condensed for two digits so it never looks squeezed.
        for day in range(1, 32):
            two = day >= 10
            body = ('<rect x="3.6" y="4" width="16.8" height="16.6" rx="3"/><path d="M3.6 8.6h16.8"/>'
                    f'<text x="12" y="17.65" text-anchor="middle" font-family="DejaVu Sans Condensed, DejaVu Sans, Arial, sans-serif" '
                    f'font-weight="bold" font-size="{7.6 if two else 8.0}" letter-spacing="{-0.35 if two else 0}" '
                    f'fill="#000" stroke="none">{day}</text>')
            items.append((f"cal-{day}", f"hd-tab-cal-{day}", tab_svg(body)))
    for name, asset, source in items:
        d = folder / f"{asset}.imageset"
        d.mkdir()
        cairosvg.svg2pdf(bytestring=source.encode(), write_to=str(d / f"{asset}.pdf"))
        (d / "Contents.json").write_text(json.dumps({
            "images": [{"filename": f"{asset}.pdf", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
        }, indent=2))


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    write(root / "App/Assets.xcassets", list(ICONS), tabs=True)
    write(root / "Widget/Assets.xcassets", WIDGET)
    print(f"{len(ICONS)} app icons, {len(WIDGET)} widget icons")
