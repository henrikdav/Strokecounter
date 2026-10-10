#!/usr/bin/env python3
"""Swing detection step 1: summarises a motion recording from the watch (watch/StrokeCounterWatch/SwingRecorder.swift).

Usage: tools/swing/inspect.py <recording folder with motion.bin and events.jsonl>

Prints the header, how long and how evenly it recorded, and for every stroke logged on the watch the strongest
rotation and acceleration in the 30 s before it (a shot should show up there as a clear peak).
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
    data = (folder / 'motion.bin').read_bytes()
    samples = [RECORD.unpack_from(data, i) for i in range(0, len(data) - RECORD.size + 1, RECORD.size)]
    return events, samples


def main(folder):
    events, samples = load(folder)
    start = next((e for e in events if e['type'] == 'start'), None)
    if not start or not samples:
        sys.exit('no header or no motion samples')
    print('header:', {k: v for k, v in start.items() if k != 'type'})
    duration = samples[-1][0] - samples[0][0]
    gaps = [b[0] - a[0] for a, b in zip(samples, samples[1:])]
    print(f'{len(samples)} samples over {duration / 60:.1f} min, {len(samples) / max(duration, 1e-9):.1f} Hz, '
          f'longest gap {max(gaps, default=0):.2f} s')
    t0 = start['t0'] / 1000
    removed = {e['id'] for e in events if e['type'] == 'remove'}
    strokes = [e for e in events if e['type'] == 'stroke' and e['id'] not in removed]
    print(f"{len(strokes)} strokes, {sum(e['type'] == 'fix' for e in events)} GPS fixes")
    for s in strokes:
        at = s['t'] / 1000 - t0
        window = [x for x in samples if at - 30 <= x[0] <= at]
        if not window:
            print(f"  {at:8.1f} s  hole {s['hole']:>2} {s['club']:<8} no samples before it")
            continue
        rot = max(window, key=lambda x: math.hypot(x[4], x[5], x[6]))
        acc = max(math.hypot(x[1], x[2], x[3]) for x in window)
        print(f"  {at:8.1f} s  hole {s['hole']:>2} {s['club']:<8} peak rotation {math.hypot(rot[4], rot[5], rot[6]):5.1f} rad/s "
              f"{at - rot[0]:5.1f} s before, peak acceleration {acc:4.1f} g")


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
