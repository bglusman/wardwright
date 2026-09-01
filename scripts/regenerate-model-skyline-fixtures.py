#!/usr/bin/env python3
"""Validate or normalize Wardwright's golden SelectionSnapshot fixtures."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from model_skyline.models import SelectionSnapshot
from model_skyline.selection import selection_hash

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "app" / "test" / "fixtures" / "model_skyline"


def normalized_fixture(path: Path) -> str:
    payload = json.loads(path.read_text(encoding="utf-8"))
    snapshot = SelectionSnapshot.model_validate(payload)
    snapshot = snapshot.model_copy(update={"snapshot_id": selection_hash(snapshot)})
    return json.dumps(snapshot.model_dump(mode="json"), ensure_ascii=False, indent=2) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--write",
        action="store_true",
        help="rewrite fixtures; the default only checks that they are normalized",
    )
    args = parser.parse_args()
    changed: list[Path] = []

    for path in sorted(FIXTURES.glob("selection-*.json")):
        normalized = normalized_fixture(path)
        if path.read_text(encoding="utf-8") != normalized:
            changed.append(path)
            if args.write:
                path.write_text(normalized, encoding="utf-8")

    if changed and not args.write:
        for path in changed:
            print(path.relative_to(ROOT))
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
