#!/usr/bin/env python3
"""v52 usage audit. Reads the JSON pulled from the iPhone into audit/ and prints a report.
   python3 tools/usage_audit.py            (reads audit/*.json, never committed)"""
import json, datetime as dt, collections, sys, os
A = sys.argv[1] if len(sys.argv) > 1 else 'audit'
REF = dt.datetime(2001, 1, 1, tzinfo=dt.timezone.utc)
def t(x): return (REF + dt.timedelta(seconds=x)).astimezone()
def load(n):
    p = os.path.join(A, n)
    return json.load(open(p)) if os.path.exists(p) else None

hist = load('daylive-history.json') or []
store = load('daylive-store.json') or {}
reality = load('daylive-reality.json') or {}

def is_test(e):
    i, ti = e.get('id', ''), e.get('title', '')
    return 'demo' in i or ti.startswith('Test ·') or i.startswith('test-')

rows = []
for d in sorted(hist, key=lambda d: d['day']):
    E = [e for e in d['entries'] if not d.get('isDemo')]
    real = [e for e in E if not is_test(e)]
    plan = [e for e in real if e['source'] == 'plan']
    cal = [e for e in real if e['source'] != 'plan']
    hrs = lambda es: sum(max(0, e['actualEnd'] - e['start']) for e in es) / 3600
    planned_h = sum(max(0, e['plannedEnd'] - e['start']) for e in plan) / 3600
    done = [e for e in plan if e['done']]
    early = [e for e in done if e['actualEnd'] < e['plannedEnd'] - 60]
    over = [e for e in plan if e['actualEnd'] > e['plannedEnd'] + 60]
    missed = [e for e in plan if not e['done']]
    steps = sum(e['stepsTotal'] for e in plan)
    rows.append(dict(day=d['day'], test=len(E) - len(real), plan=len(plan), cal=len(cal), done=len(done),
                     missed=len(missed), early=len(early), over=len(over), planned_h=planned_h,
                     plan_h=hrs(plan), cal_h=hrs(cal), steps=steps,
                     wd=dt.date.fromisoformat(d['day']).strftime('%a')))

print(f"{'day':<11}{'':4}{'plan':>5}{'done':>5}{'miss':>5}{'over':>5}{'plan h':>8}{'cal':>5}{'cal h':>7}{'test':>5}")
for r in rows:
    print(f"{r['day']:<11}{r['wd']:<4}{r['plan']:>5}{r['done']:>5}{r['missed']:>5}{r['over']:>5}{r['planned_h']:>8.1f}{r['cal']:>5}{r['cal_h']:>7.1f}{r['test']:>5}")

active = [r for r in rows if r['plan'] > 0]
P = sum(r['plan'] for r in rows); D = sum(r['done'] for r in rows)
print()
print(f"Days recorded: {len(rows)}  |  days with any planned block: {len(active)}  |  days with nothing planned: {len(rows)-len(active)}")
print(f"Planned blocks: {P}, done: {D}  ->  completion {100*D/max(P,1):.0f}%")
for label, part in (('First half', rows[:len(rows)//2]), ('Second half', rows[len(rows)//2:])):
    p = sum(r['plan'] for r in part); d = sum(r['done'] for r in part)
    print(f"  {label}: {sum(1 for r in part if r['plan'])}/{len(part)} days planned, {d}/{p} done ({100*d/max(p,1):.0f}%), {sum(r['plan'] for r in part)/max(len(part),1):.1f} blocks/day")
print(f"Ended early: {sum(r['early'] for r in rows)}  |  ran over: {sum(r['over'] for r in rows)}  |  missed: {sum(r['missed'] for r in rows)}")
print(f"Test/demo entries mixed into history: {sum(r['test'] for r in rows)}")

print("\nFeature use (from saved data):")
print(f"  plan blocks saved now: {len(store.get('planBlocks', []))}")
print(f"  blocks with steps: {len(store.get('steps', {}))}")
print(f"  category overrides: {len(store.get('categoryOverrides', {}))}, multi-category: {len(store.get('extraCategories', {}))}")
print(f"  timer overrides (Start/Pause/Done/Extend): {len(store.get('overrides', {}))}")
print(f"  Reality: places {len(reality.get('places', []))}, arrive/leave events {len(reality.get('events', []))}, commute samples {len(reality.get('commuteSamples', []))}")
print(f"  steps used on any recorded block: {sum(1 for d in hist for e in d['entries'] if e['stepsTotal'] and not is_test(e))}")
titles = collections.Counter(e['title'] for d in hist for e in d['entries'] if e['source']=='plan' and not is_test(e))
print("  most-planned titles:", ', '.join(f'{k} ×{v}' for k, v in titles.most_common(8)))
