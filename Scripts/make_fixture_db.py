#!/usr/bin/env python3
"""Regenerate the committed schema-v1 fixture database.

The fixture proves that `AquaristStoreSchema.migrator` can upgrade a real v1-era
database file to the current schema. Run this only when a later migration is
added; v1 is frozen and must not be edited in place.

Usage (from repo root, inside a Swift environment after building fixture-seed):
    Scripts/make_fixture_db.py Packages/AquaristStore/.build
"""
from __future__ import annotations

import argparse
import shutil
import sqlite3
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
FIXTURE = REPO_ROOT / "Packages/AquaristStore/Tests/AquaristStoreTests/Fixtures/v1.sqlite"


def logical_dump(path: Path) -> str:
    connection = sqlite3.connect(path)
    try:
        return "\n".join(connection.iterdump())
    finally:
        connection.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("scratch_dir", type=Path, help="Directory containing the built fixture-seed binary")
    parser.add_argument("--out", type=Path, default=FIXTURE)
    args = parser.parse_args()

    seed = next(args.scratch_dir.rglob("fixture-seed"), None)
    if seed is None:
        print("fixture-seed binary not found under", args.scratch_dir, file=sys.stderr)
        return 1

    staging = Path(__file__).resolve().parent / f".fixture-{FIXTURE.name}"
    staging.unlink(missing_ok=True)
    subprocess.run([str(seed), str(staging)], check=True)

    if args.out.exists() and logical_dump(args.out) != logical_dump(staging):
        print("Generated fixture differs logically from committed fixture — v1 must be frozen.", file=sys.stderr)
        staging.unlink(missing_ok=True)
        return 1

    args.out.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(staging), str(args.out))
    print(f"Wrote {args.out} ({args.out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
