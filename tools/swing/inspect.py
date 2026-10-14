#!/usr/bin/env python3
"""Summarises a motion recording from the watch (watch/StrokeCounterWatch/SwingRecorder.swift).

Usage: tools/swing/inspect.py <recording folder with motion.bin and events.jsonl>

Prints the header, how long and how evenly it recorded, and for every stroke logged on the watch the strongest
rotation and acceleration in the 30 s before it (a shot should show up there as a clear peak), how it was logged
and the swing the watch found before it. Ends with what the watch did with the swings it found.
"""
import json
import math
import struct
import sys
from pathlib import Path

RECORD = struct.Struct('<10f')   # t, user acceleration xyz (g), rotation rate xyz (rad/s), gravity xyz (g)


def load(folder):
    folder = Path(folder)
    events = [json.loads(line) for line in (folder / 'events.jsonl').read_text().splitlines() if line.strip()]
    motion = folder / 'motion.bin'   # only in recordings made to tune the detector
    data = motion.read_bytes() if motion.exists() else b''
    samples = [RECORD.unpack_from(data, i) for i in range(0, len(data) - RECORD.size + 1, RECORD.size)]
    return events, samples


def main(folder):
    events, samples = load(folder)
    start = next((e for e in events if e['type'] == 'start'), None)
    if not start:
        sys.exit('no header')
    print('header:', {k: v for k, v in start.items() if k != 'type'})
    if samples:
        duration = samples[-1][0] - samples[0][0]
        gaps = [b[0] - a[0] for a, b in zip(samples, samples[1:])]
        print(f'{len(samples)} samples over {duration / 60:.1f} min, {len(samples) / max(duration, 1e-9):.1f} Hz, '
              f'longest gap {max(gaps, default=0):.2f} s')
    else:
        print('no motion samples (events only)')
    t0 = start['t0'] / 1000
    removed = {e['id'] for e in events if e['type'] == 'remove'}
    strokes = [e for e in events if e['type'] == 'stroke' and e['id'] not in removed]
    print(f"{len(strokes)} strokes, {sum(e['type'] == 'fix' for e in events)} GPS fixes")
    swings = [e for e in events if e['type'] == 'swing']
    for s in strokes:
        at = s['t'] / 1000 - t0
        how = 'swing list' if s.get('fromSwingList') else '+1'
        found = [w for w in swings if 0 <= (s['t'] - w['t']) / 1000 <= 60]
        swing_text = f"swing {(s['t'] - found[-1]['t']) / 1000:4.1f} s before" if found else 'no swing found'
        position = ', swing position' if s.get('swingPosition') else ''
        window = [x for x in samples if at - 30 <= x[0] <= at]
        if not window:
            print(f"  {at:8.1f} s  hole {s['hole']:>2} {s['club']:<8} [{how}, {swing_text}{position}]")
            continue
        rot = max(window, key=lambda x: math.hypot(x[4], x[5], x[6]))
        acc = max(math.hypot(x[1], x[2], x[3]) for x in window)
        print(f"  {at:8.1f} s  hole {s['hole']:>2} {s['club']:<8} peak rotation {math.hypot(rot[4], rot[5], rot[6]):5.1f} rad/s "
              f"{at - rot[0]:5.1f} s before, peak acceleration {acc:4.1f} g  [{how}, {swing_text}{position}]")
    battery = [e for e in events if e['type'] == 'battery' and e.get('level', -1) >= 0]
    if len(battery) > 1:
        hours = (battery[-1]['t'] - battery[0]['t']) / 3_600_000
        used = (battery[0]['level'] - battery[-1]['level']) * 100
        print(f"battery {battery[0]['level']:.0%} -> {battery[-1]['level']:.0%} over {hours * 60:.0f} min: "
              f"{used / hours:.0f} % per hour" if hours > 0 else '')
    if swings:
        count = lambda kind: sum(e['type'] == kind for e in events)
        print(f"{len(swings)} swings found; club list shown {count('swing-list')} times, "
              f"{sum(1 for s in strokes if s.get('fromSwingList'))} strokes logged from it, {count('swing-cancel') + count('not-a-shot')} cancelled")


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
