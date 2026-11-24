# Changelog

## Unreleased

### v60: Add block screen, tappable graphs, scroll to top, battery colours, two modes
- **Add block** rebuilt as a JobTrail screen: glowing title card, sliding Today/Tomorrow/Other switcher, Starts/Ends readouts, quick lengths, live preview row + day bar, pinned amber Add button with a ✓ on success.
- **Tap a pulse graph** → a JobTrail detail popover: big live graph, elapsed/left clocks, moving bar, key facts.
- **Tap a tab** → that page scrolls back to the top (Calendar agenda jumps to today).
- **Car battery:** Tesla green, orange below 20%, red below 10% (app, widgets, dock).
- **Appearance:** Dark and Light only (no System); an old "System" setting reads as Dark.

### v59: pulse graphs, JobTrail switcher, more motion
- **Pulse graph** (`JTPulseLine`): JobTrail's live sparkline, heartbeat while running, amber drift while waiting. On the Now card, the running row, the Today and Stats meter cards, Settings › Live Activity, and (still) on the widgets.
- **Traveling pulses:** glowing dots run along every connector line.
- **Navigation:** the system tab bar is replaced by a JobTrail switcher: dark track, the selection slides between tabs, amber icon, mono labels, live dot on Today. Appearance button is a JobTrail square.
- **More motion:** wandering status light + breathing accent edge in the Now card, the live "left" pill shimmers, pull to refresh on Today.
- Debug: `-hdDemo YES` also skips the Health sheet.

### v58: JobTrail rebuild of every screen and widget
- **JTKit** (`Shared/JTKit.swift`): JobTrail's components in SwiftUI: status dots with halos, section heads, pills, LIVE/IDLE badge, meters with growing bars, cards with glow states, dashed empty boxes, film grain, staggered entry, chart reveal, press style.
- **Today:** map-dot Now card with shimmering running lane, meters card, Schedule head with run/wait/done legend, staggered entry.
- **Calendar:** amber today tile with breathing glow, glowing today card with flowing connectors, amber now-line with pulse + ripple in Week, running cells sweep green.
- **Stats:** meters card, columns grow in, line draws in with a rippling today point, category and meeting bars grow.
- **Settings:** rebuilt as JobTrail cards (same pages behind every row).
- **Topbar:** LIVE badge pulses while the Live Activity runs; + button breathes amber.
- **Widgets:** status dots, mono caps, live countdowns and timer-driven bars that move on their own, amber frame when a block is running; Heat and Calendar widgets on the JobTrail dark card, today amber.
- **Live Activity:** JobTrail pills, mono NOW/NEXT, amber heads-up.

### v57: JobTrail look and motion
- **Palette:** JobTrail tokens (bg #000, surface #181818, lines #313131, amber accent #e9a23b). Status colours everywhere: green running, amber waiting, blue done, red failed. Starts in Dark once.
- **Type:** Geist for UI, Geist Mono for labels, times and stats (bundled in app + widget, `Shared/Fonts`, OFL).
- **Surfaces:** chamfers are now rounded cards with 1px borders; the Now card gets an amber border + glow.
- **Motion** (`Shared/HDMotion.swift`): pulsing live dots, blur-in for new items, breathing amber glow, sweeping green ring on running rows, ripples, shimmer + typing cursor while planning, flowing connector dashes, row flash, tilting hourglass, progress bar. Reduce Motion gets still frames; widgets/Live Activities get the static look.
- Debug: `-hdDemo YES` loads sample data for screenshots.

### v56: canvas dots + empty-day Island
- **Dot grid** (`DotGrid` in `Shared/HDTheme.swift`) replaces the hairlines: Now card, Lock Screen card, every widget plate, Car stage floor, and faint dots on the Today, Stats and Calendar page backgrounds.
- **Island on an empty day:** just a solid green check (compact and minimal). No more calendar icon + empty ring.

### v55: instrument look, whole app (approved v54/v55 mockups)
- **Shared theme** (`Shared/HDTheme.swift`): chamfered panels, brushed hairline plates, SF Mono readouts and caps, AA-checked tokens. Used by the app, every widget and every Live Activity.
- **App:** cards, buttons, stat tiles and the + button are chamfered (the + is drawn, so it's exactly centred); section caps are mono; the Now card is a dark hairline instrument panel in both modes; deeper darks.
- **Live Activities:** instrument plate with hairlines, SF Mono countdowns and "ENDS" caps, chamfered Pause/Done.
- **Widgets:** hairline plates (Hyperday, Dock, Car, Calendar, Heatmap), mono numbers, chamfered tiles.
- **Car tab:** stainless stage (no mountains, brushed floor) with cut corners, mono status line, alert strips (battery low, unlocked, window open, tires), solid status icons coloured only when they need attention, zero-padded readouts with a 20-segment bar and limit mark. v46 gloss values unchanged. Small car widget: mono, 10 segments, amber mark for an open window.

### v52: deeper, not bigger
- **Usage audit:** `tools/usage_audit.py` reads the data pulled from the iPhone into `audit/` (git-ignored). North-star: days per week with at least one planned block done.
- **Fix: skipped days vanished from history.** If the app didn't run on a day (e.g. Fri Oct 16), that day was never recorded. Now every missed day (up to 14) is filled when the app next runs.
- **Fix: overtime was never recorded.** Done after the planned end was saved as on time, so "ran over" was always 0. History now keeps the real Done time.
- **Reliability logging:** Logger + signposts around every Live Activity refresh and background wake-up, plus a local `Documents/diagnostics.jsonl` (no titles; never uploaded). `tools/diag_check.py` checks a 7-day run for missed updates.
- **Tests:** 14 new (ahead/behind, overtime, midnight, skipped days, save/restore); 27 total pass.
- **Dynamic Type:** all 152 fixed font sizes now follow Settings › Text Size (up to XXX Large).
- **VoiceOver:** the three new charts read their numbers; theme button is a 44 pt target; "1 dot = 15 min" no longer clipped.
- **Empty day:** with nothing planned (or nothing left), the Lock Screen card and Island show a green check mark instead of an empty timeline.
- **deploy.sh:** a failed launch now fails the deploy and prints the Trust steps instead of "✓".

### v50–v51
- **Onboarding (v50):** 3 pages on first run only: Welcome (sample Live Activity), Permissions (Calendar read-only, Notifications, Live Activities), Shape your day (picked categories are added; nothing is removed). Existing installs skip it. Test: Settings › Developer › Show onboarding, or `hyperday://onboarding`.
- **Stats charts (v51):** Focus this week (square-dot columns, today in blue), Ahead / behind plan (dots above = done as planned, orange below = missed or over, 30 days; 14 on narrow screens), Focus hours month to date (this month solid vs last month dashed). Existing Stats cards stay.

### v48
- **Every Live Activity state in the test kit:** Settings › Developer now previews 11 states: Running, Last 5 min, Free (Next + Later), Day closed, Paused, Overtime, Steps, Calendar event, Free (Next only), Day closed with tasks left, Driving. "Preview all styles" plays all 11, 5 s each.
- **Richer test day:** a done block, a running block with steps, a free gap, a photo task with a test picture, Standup and Gym. Remove deletes the test blocks and their photo.
- **Simulator:** `zsh tools/sim.sh` builds and runs on the iPhone 17 Pro Max simulator (Xcode 27 Device Hub).

### v45–v47
- **Thicker day bars** on the Today card; **glossy car back** (10 % less than v40).
- **Solid icons everywhere:** filled, rounded icons for categories and status (tools/filled_icons.json); controls (arrows, +, ×) stay as 2 pt lines. No circles or squares behind icons: Today rows, Live Activity, Island, Settings, widgets.
- **Dock-style widgets (CoolDock look):** Now strip and Day strip (medium), Now with Pause / Done buttons and 4 tiles (small): black tray, darker tiles, big numbers, ring gauges.

### v42–v44
- **Tesla data fix:** endpoints are sent encoded, so lock, Sentry, inside temperature and place come back.
- **Plan vs real:** 56 pt per hour, bigger text, header no longer overlaps.
- **Matte car:** no metal or clear coat, very rough surfaces; paint set to a darker Quicksilver so it doesn't read white; softer spotlight.
- **Car tab in Tesla's style:** centred name with battery · range · status, full-width 3D stage (badges kept), text row of views, a 3×2 grid of thin outline icons (lock, Sentry, port, inside, windows, tires), big thin battery % and range with a thin bar.

### v41
- **Lock Screen car card, more detail:** battery · range, lock icon + inside temperature, Leave-by (or place · last read), with a smaller front picture.
- **Car tab icon:** a front view of the car.
- **Car tab status chips:** Locked · Sentry · Charge port · Inside · Windows · Tires under the 3D car, always visible. Windows and tire warnings are now read from Tesla (same read, no extra cost). The 3D stage background follows light/dark.

### v39–v40
- **Car section back** (tab with your car's outline, Settings › Car, all car widgets).
- **Front view in every car widget:** a new matte (no gloss) straight-on render of your Quicksilver Model Y replaces the side/3⁄4 picture, including the Lock Screen gauges.
- **Lock icon instead of "Locked"** (red open lock when unlocked).
- **New widgets:** Lock Screen rectangular (78% · lock + range · the car), Home Screen medium "Car" (name, big %, lock + range, car on the right), and G "Big car" (small, the car fills it).
- **3D Car tab:** reflections halved, dark or light surroundings following the phone, and a soft diffused spotlight from above.

### v37–v38
- **Island:** compact long-press layout (title · timer · ends, strip, Next + Pause/Done); nothing cut off.
- **Day closed:** thick focus bars (up to 10–12 pt) in the Island and on the Lock Screen.
- **Stat tiles:** labels stay on one line.
- **Small car widgets:** Lock Screen battery gauge with your car's filled silhouette (bolt + full ring while charging), the same with a lock badge, a line above the clock ("76% · 205 mi", or "full at" while charging), and a Home Screen small list (battery/range, lock, inside temp). Car reads are back on for these only (app open + background refresh, never waking the car); the Car tab stays off.

### v36
- **Photo task** (replaces Scan to blocks): hold + → Photo task, or the camera button on Today. The camera opens, then you set a title and time. The exact picture is attached to a normal block and nothing is read from it.
- **Photos on blocks:** Edit shows a Photos section (add with the camera or library, tap for full screen with zoom/Share/Delete, touch and hold for Share/Delete). Today rows show a thumbnail and "1 photo".
- **Privacy:** photos are kept in the app's private storage, are locked while the phone is locked, are left out of iCloud device backup and Hyperday's weekly backup, and are deleted with their block.

### v35
- **Car is off for now:** Car tab, Settings › Car, background reads and car widgets are hidden (`Features.car`). The code is kept.
- **Apple tab bar:** iOS's own Liquid Glass bar, SF Symbols (Calendar keeps today's date), blue when selected.
- **+ button:** floating blue glass button again (not a tab). Tap = Add block; touch and hold = Apple's menu (Add block · Plan with words · Scan to blocks).
- **Long-press = Apple menus:** hold a block in Today for Edit · Extend 15 min · Extend… · Mark done · Delete.
- **Settings like iOS Settings:** one list with coloured icon squares; Appearance, Categories, Calendars, Auto rules, Live Activity, Focus & Siri and Developer are native pages. Close the day, Reality line and Backup still show their old cards for now.

### v34
- **Add / Edit block, Apple style:** round glass ✕ and blue ✓ buttons (iOS 26), Today · Tomorrow · Other segmented control with the system date pill, a plain "Ends" row.
- **Thick ruler:** bold length readout (40 pt), ticks 4.5–6 pt wide and taller, bold labels.
- **Chips:** tinted capsules everywhere (category colour when picked, system grey otherwise).

### v33
- **Taller Live Activity:** the Lock Screen card is now about as tall as other apps' cards. It has a big countdown and one full-width tick strip with 4 pt ticks, so there's no empty space on the right. The same layout is used for free time and for a running block, with Pause/Done next to the countdown.
- **Thicker ruler ticks** in Add block, Edit and Extend.

### v32
- **Time strips:** the Free card's thick bars (Lock Screen + Island) are now strips of fine ticks in flat colour; time already gone is dimmed, a white marker shows now.
- **Apple-style duration ruler:** drag a tick ruler (snaps to 5 min, haptic) to set a block's length in Add block and Edit.
- **Extend:** long-press the running Hyperday block in Today to add time with the same ruler. Calendar events stay untouched.
- **No gradients:** hero card, weekly recap, initials avatar, the + menu gloss and the Car sky are flat colours now.

### Added
- **Widgets:** Home Screen small / medium / large and StandBy (small).
- **Lock Screen widgets:** Now (rectangular), Day strip (rectangular), and a configurable Circle (time left / steps / next start / blocks left).
- **Apple Watch:** a Smart Stack card for the Live Activity with the time left, next, the bar and the Step / Done button.
- **Siri & Shortcuts:** "What's next", "Start my day", "I'm done" and "Start Deep Work" (90 min).
- **Focus filter:** show everything, only work, only personal, or nothing while a Focus is on.
- **Week view drag:** long-press to move a planned block (15-minute snap, across days), pull the bottom handle to resize.
- **Weekly recap:** a Sunday 7 PM notification that opens a full-screen card you can share or save to Photos.

- **Start timer:** tap Start (swipe right on a block, the editor, or "Start now" on the Lock Screen in free time) and the countdown runs from that moment for the block's length, then shows **+overtime** until Done.
- **Free time:** one bar that fills up until your next block, with "1:40:05 until Standup".
- **Date before time** when adding or editing (Today / Tomorrow / Pick date), and **Move to tomorrow** (editor or swipe left).
- **Multiple categories per block.** The first one sets the color; Stats split the time evenly.

- **Blocks-done heatmap** (GitHub-style): first card on Stats (12 months, tap a day for its blocks, Open in Calendar), plus widgets: Small (7 weeks), Medium (5 months), Large (12 months), Lock Screen (16 weeks).
- **App icon: Now Line**, and Hyperday's own line icons across the app. Categories can pick an icon.

- **Day Close** (v9): at your close time the Lock Screen card becomes "Day closed" with what you finished and a Review link; a 30-second review moves unfinished blocks to tomorrow or drops them.
- **Tomorrow pre-flight**: tomorrow's first block, leave-by (office days) and bed-by from your sleep target (Health average optional).

- **Reality line** (#3): Plan vs real on Today, from Location (Home/Office/Gym arrivals), your car (Shortcuts automation: I'm driving / Arrived) and Health workouts, which also tick Fitness blocks. Learns your commute for pre-flight.
- **Good-Day formula** (#4) on Stats: what your 6+-done days have in common (sleep, first block, meetings, workouts, commute).
- **Plan with words** (#5) and **Evening story** (#6) with Apple Intelligence on iOS 26 (on-device).
- **Scan to blocks** (#8): photo or camera → dates and times become blocks.
- **3-week calendar widget** (Lock Screen + StandBy/Home small): last, this and next week, Monday first, this week in a rounded band, today a rounded square, a bar under each date for how busy it is.
- **Drive card** (#9): while driving, arrival time from Apple Maps and minutes to spare before your next block.

### Changed
- Done is green, Step is yellow, Start now grey.
- Calendar tab always opens on today; the agenda is one continuous list (90 days back and ahead). Tasks are kept for 2 years.
- Appearance follows the system by default; the header button cycles System, Light, Dark.
- Only one Hyperday Live Activity at a time; older cards are cleared.
- Minimum iOS is now **18**.
- `deploy.sh` signs with an App Group and falls back without it on a free Apple ID.

## 0.1.0 — 2026-09-28 (pre-release)

### Added
- **Live Activity** for the day on the Lock Screen and in the Dynamic Island. It shows:
  - the current block, a live countdown and what's next
  - an "also:" line for overlaps
  - a segmented bar
  - Step / Done / Start next buttons
- **Checklist steps** per block. They drive the bar, and a yellow **Step n/N** button checks the next one.
- **Today** tab: heading, Focused / Steps / Meetings left, Add block, Go Live, timeline, and a LIVE NOW pill that opens the live block.
- **Calendar** tab: every calendar on the device plus your tasks, in Agenda / Week / Month views. Tap a date to jump to it; tap it again to go back to today.
- **Stats** tab: Week / Month / Year, focused hours, steps, streak, hours by category, meeting load, and blocks done / ended early / missed.
- **Categories**: auto rules (first match wins), manual override, editable colors. **Calendar colors**, with Tesla calendars defaulting to red.
- **Sample data** for previewing (8 weeks + a planned day).
- **Light / Dark / System** appearance and a native Liquid Glass tab bar (iOS 26+).
- **Siri / Shortcuts**: "Add a block in Hyperday".
- App icon (default, dark, tinted).
- `deploy.sh`: one command to build and install. It auto-detects the signing team.
