#!/usr/bin/env python3
"""Deterministic, original geometric application icon; standard-library PNG writer."""
import json
import math
from pathlib import Path
import struct
import zlib

ROOT = Path(__file__).resolve().parents[1]


def line_distance(x, y, start, end):
    dx, dy = end[0] - start[0], end[1] - start[1]
    t = min(1, max(0, ((x - start[0]) * dx + (y - start[1]) * dy) / (dx * dx + dy * dy)))
    return math.hypot(x - start[0] - t * dx, y - start[1] - t * dy)


def icon(size):
    edges = [((.24,.34),(.5,.20)), ((.5,.20),(.76,.34)), ((.76,.34),(.76,.64)),
             ((.76,.64),(.5,.80)), ((.5,.80),(.24,.64)), ((.24,.64),(.24,.34)),
             ((.24,.34),(.5,.49)), ((.5,.49),(.76,.34)), ((.5,.49),(.5,.80))]
    rows = bytearray()
    for py in range(size):
        rows.append(0)
        for px in range(size):
            x, y = (px + .5) / size, (py + .5) / size
            base = (10, int(38 + 15*(1-y)), int(58 + 22*(1-y)))
            edge = min(line_distance(x, y, a, b) for a, b in edges)
            if edge < .013:
                base = (143, 224, 235)
            # Three clear flow strokes through a room outline; qualitative brand motif only.
            for offset in (0, .07, .14):
                if .31 <= x <= .68 and abs(y - (.39 + offset + .022*math.sin((x-.31)*14))) < .012:
                    base = (248, 253, 255)
            rows.extend(base)
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows, 9)) + chunk(b'IEND', b'')


def main():
    root = ROOT / 'Apps/Shared/Assets.xcassets/AppIcon.appiconset'
    root.mkdir(exist_ok=True)
    for size in (16, 32, 64, 128, 256, 512, 1024):
        (root / f'icon-{size}.png').write_bytes(icon(size))
    images = [{'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024', 'filename': 'icon-1024.png'}]
    for size in (16, 32, 128, 256, 512):
        for scale in (1, 2):
            images.append({'idiom': 'mac', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': f'icon-{size*scale}.png'})
    (root / 'Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}, indent=2) + '\n')


if __name__ == '__main__':
    main()
