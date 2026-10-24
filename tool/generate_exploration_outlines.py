#!/usr/bin/env python3
"""Build offline exploration outlines; no clipping is performed by the app.

Build-only dependency: shapely==2.1.2 (not shipped in the application).
Run from any directory: python tool/generate_exploration_outlines.py [--check]
Uses the same Natural Earth land source, continent windows and 0.13-degree
closed-ring simplification as the original Flutter artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path

from shapely.affinity import translate
from shapely.geometry import Polygon
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/data/world-land-50m.geo.json"
OUTPUT = ROOT / "assets/data/exploration-outlines.json"
TOLERANCE_SQUARED = 0.13 ** 2
WINDOWS = {'europe': [[-25.0, 35.5], [-25.0, 66.0], [-12.0, 75.0], [-10.0, 90.0], [60.0, 90.0], [60.0, 55.0], [52.0, 45.0], [40.0, 42.0], [28.0, 41.0], [26.0, 38.0], [25.0, 34.0], [10.0, 38.0], [6.0, 38.0], [-6.0, 35.95]], 'asia': [[60.0, 90.0], [191.5, 90.0], [191.5, 60.0], [180.0, 56.0], [180.0, 5.0], [153.0, 5.0], [141.0, 0.0], [141.0, -10.0], [130.0, -10.0], [130.0, -12.0], [60.0, -12.0], [43.0, 12.0], [35.0, 29.0], [32.3, 31.2], [25.0, 34.0], [26.0, 38.0], [28.0, 41.0], [40.0, 42.0], [52.0, 45.0], [60.0, 55.0]], 'africa': [[-25.0, 35.5], [-6.0, 35.95], [6.0, 38.0], [10.0, 38.0], [25.0, 34.0], [32.3, 31.2], [35.0, 29.0], [43.0, 12.0], [60.0, -12.0], [60.0, -48.0], [-25.0, -48.0]], 'northAmerica': [[-168.5, 90.0], [-10.0, 90.0], [-10.0, 16.0], [-60.0, 16.0], [-77.2, 9.0], [-77.4, 7.2], [-83.0, 7.2], [-170.0, 7.2], [-195.0, 50.0], [-195.0, 56.0], [-180.0, 56.0], [-168.5, 60.0]], 'southAmerica': [[-83.0, 7.2], [-77.4, 7.2], [-77.2, 9.0], [-60.0, 16.0], [-25.0, 16.0], [-25.0, -60.0], [-83.0, -60.0]], 'oceania': [[110.0, -12.0], [130.0, -12.0], [130.0, -10.0], [141.0, -10.0], [141.0, 0.0], [153.0, 5.0], [220.0, 5.0], [220.0, -55.0], [110.0, -55.0]], 'antarctica': [[-180.0, -60.0], [180.0, -60.0], [180.0, -90.0], [-180.0, -90.0]]}


def simplify_line(points):
    if len(points) <= 2:
        return points
    kept = {0, len(points) - 1}
    pending = [(0, len(points) - 1)]
    while pending:
        start, end = pending.pop()
        a, b = points[start], points[end]
        dx, dy = b[0] - a[0], b[1] - a[1]
        length = dx * dx + dy * dy
        farthest, distance = -1, TOLERANCE_SQUARED
        for i in range(start + 1, end):
            x, y = points[i]
            t = 0 if length == 0 else max(0, min(1, ((x-a[0])*dx + (y-a[1])*dy) / length))
            d = (x-a[0]-dx*t)**2 + (y-a[1]-dy*t)**2
            if d > distance:
                farthest, distance = i, d
        if farthest != -1:
            kept.add(farthest)
            pending.extend([(start, farthest), (farthest, end)])
    return [points[i] for i in sorted(kept)]


def simplify_ring(points):
    middle = len(points) // 2
    result = simplify_line(points[:middle+1]) + simplify_line(points[middle:])[1:]
    return result if len(result) >= 4 else points


def rings_of(geometry):
    if geometry.is_empty:
        return []
    if geometry.geom_type == "Polygon":
        return [list(geometry.exterior.coords)] + [list(r.coords) for r in geometry.interiors]
    return [ring for part in geometry.geoms for ring in rings_of(part)]


def flattened(rings):
    return [[round(value, 6) for point in ring for value in point[:2]] for ring in rings]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    source_bytes = SOURCE.read_bytes()
    document = json.loads(source_bytes)
    world_rings, land = [], []
    for feature in document["features"]:
        geometry = feature["geometry"]
        polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
        for polygon in polygons:
            rings = [simplify_ring(r) for r in polygon if len(r) >= 4]
            if not rings:
                continue
            world_rings.extend(rings)
            shape = Polygon(rings[0], rings[1:])
            # Simplification can create self-crossings on tiny islands.
            # Resolve them during generation rather than at runtime.
            land.append(shape if shape.is_valid else shape.buffer(0))
    world = unary_union(land)
    repeated = unary_union([translate(world, xoff=shift) for shift in (-360, 0, 360)])
    outlines = {"world": flattened(world_rings)}
    for name, window in WINDOWS.items():
        outlines[name] = flattened(rings_of(repeated.intersection(Polygon(window))))
    payload = {
        "version": 1,
        "source": "world-land-50m.geo.json",
        "sourceSha256": hashlib.sha256(source_bytes).hexdigest(),
        "simplificationDegrees": 0.13,
        "outlines": outlines,
    }
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n"
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != encoded:
            raise SystemExit("Exploration outlines are stale; regenerate them.")
        print("Exploration outlines match the source and generator.")
    else:
        OUTPUT.write_text(encoded)
        print(f"Wrote {OUTPUT.name}: {len(encoded.encode())} bytes, "
              f"{sum(len(r)//2 for rings in outlines.values() for r in rings)} vertices")


if __name__ == "__main__":
    main()
