#!/usr/bin/env python3
"""Build the compact airport index bundled by Flight Footprint.

The source is the public-domain CSV published by OurAirports:
https://ourairports.com/data/

Usage:
    python3 tool/generate_airport_index.py airports.csv \
        assets/data/airport-coordinates.json

The generated value for each IATA code is:
    [longitude, latitude, name, municipality, iso_country,
     icao_code, type, scheduled_service, iso_region, keywords]

The legacy index is optional. When supplied, entries that disappeared from a
new OurAirports snapshot remain as aliases so historical flight records can
still resolve their coordinates.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path
from typing import Any


def _text(value: str | None) -> str:
    return (value or "").strip()


def _number(value: str | None) -> float | None:
    try:
        number = float(_text(value))
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _keywords(value: str | None) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in _text(value).split(","):
        item = " ".join(item.split())
        if item and item.casefold() not in seen:
            seen.add(item.casefold())
            result.append(item)
    return result


def _source_row(row: dict[str, str]) -> list[Any] | None:
    iata = _text(row.get("iata_code")).upper()
    if len(iata) != 3 or not iata.isascii() or not iata.isalnum():
        return None
    longitude = _number(row.get("longitude_deg"))
    latitude = _number(row.get("latitude_deg"))
    if longitude is None or latitude is None:
        return None
    if not -180 <= longitude <= 180 or not -90 <= latitude <= 90:
        return None
    return [
        longitude,
        latitude,
        _text(row.get("name")),
        _text(row.get("municipality")),
        _text(row.get("iso_country")).upper(),
        _text(row.get("icao_code")).upper(),
        _text(row.get("type")),
        _text(row.get("scheduled_service")).lower() == "yes",
        _text(row.get("iso_region")).upper(),
        _keywords(row.get("keywords")),
    ]


def _read_source(path: Path) -> dict[str, list[Any]]:
    airports: dict[str, list[Any]] = {}
    with path.open("r", newline="", encoding="utf-8-sig") as handle:
        for row in csv.DictReader(handle):
            iata = _text(row.get("iata_code")).upper()
            value = _source_row(row)
            if value is not None:
                airports[iata] = value
    return airports


def _read_legacy(path: Path) -> dict[str, list[Any]]:
    decoded = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(decoded, dict):
        return {}
    legacy: dict[str, list[Any]] = {}
    for raw_code, raw_value in decoded.items():
        code = str(raw_code).strip().upper()
        if len(code) != 3 or not isinstance(raw_value, list) or len(raw_value) < 5:
            continue
        longitude = raw_value[0]
        latitude = raw_value[1]
        if not isinstance(longitude, (int, float)) or not isinstance(
            latitude, (int, float)
        ):
            continue
        value = list(raw_value[:5])
        # Keep old rows resolvable without pretending they are current source
        # records. The search layer can still use the historical IATA code.
        value.extend(["", "", False, "", ["legacy IATA alias"]])
        legacy[code] = value
    return legacy


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="OurAirports airports.csv")
    parser.add_argument("output", type=Path, help="generated JSON asset")
    parser.add_argument(
        "--legacy",
        type=Path,
        help="previous airport-coordinates.json to preserve removed IATA aliases",
    )
    args = parser.parse_args()

    airports = _read_source(args.source)
    if args.legacy and args.legacy.exists():
        for code, value in _read_legacy(args.legacy).items():
            airports.setdefault(code, value)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(airports, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n",
        encoding="utf-8",
    )
    print(f"wrote {len(airports)} IATA airports to {args.output}")


if __name__ == "__main__":
    main()
