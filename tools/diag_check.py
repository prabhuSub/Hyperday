#!/usr/bin/env python3
"""v52: check a 7-day run. Pull the log from the iPhone, then run this.
   xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
     --domain-identifier com.prabhu.daylive --source Documents/diagnostics.jsonl --destination audit/diagnostics.jsonl
   python3 tools/diag_check.py audit/diagnostics.jsonl
A "missed update" = a refresh promised a next boundary while the card was running, and no refresh
happened within GRACE minutes after it (iOS wake-ups can be late; the card still self-updates its timer)."""
import json, sys, datetime as dt
GRACE = 15
path = sys.argv[1] if len(sys.argv) > 1 else 'audit/diagnostics.jsonl'
ev = [json.loads(l) for l in open(path) if l.strip()]
ev.sort(key=lambda e: e['t'])
fmt = lambda t: dt.datetime.fromtimestamp(t).strftime('%a %m-%d %H:%M')
refresh = [e for e in ev if e['ev'] == 'refresh']
missed = []
for i, e in enumerate(refresh):
    if not e.get('running') or 'next' not in e: continue
    later = [r['t'] for r in refresh[i+1:]]
    nxt = later[0] if later else None
    if e['next'] < ev[-1]['t'] and (nxt is None or nxt > e['next'] + GRACE * 60):
        missed.append((e['next'], nxt))
span = (ev[-1]['t'] - ev[0]['t']) / 86400 if ev else 0
count = lambda n: sum(1 for e in ev if e['ev'] == n)
print(f"Span: {span:.1f} days, {len(ev)} events")
print(f"Refreshes: {len(refresh)} (fg {sum(1 for r in refresh if r.get('app')=='fg')}, bg {sum(1 for r in refresh if r.get('app')!='fg')})")
print(f"Background wake-ups: {count('bg-fired')}  |  BG submit failures: {count('bg-submit-failed')}  |  foregrounds: {count('foreground')}")
errs = [r for r in refresh if r.get('err')]
print(f"Refreshes with a Live Activity error: {len(errs)}" + (f"  e.g. {errs[0]['err']}" if errs else ''))
print(f"Missed boundary updates (> {GRACE} min late): {len(missed)}")
for b, n in missed[:20]:
    print(f"  due {fmt(b)}  ->  next refresh {fmt(n) if n else 'never'}")
print("PASS" if span >= 7 and not missed and not errs else "NOT YET: need >= 7 days, 0 missed, 0 errors")
