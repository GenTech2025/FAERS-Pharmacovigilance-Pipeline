#!/usr/bin/env python3
"""
backfill.py — Trigger the faers_quarterly_ingest Kestra flow for every quarter
between START_YEAR Q1 and END_YEAR Q4 (inclusive).

Usage:
    python kestra/scripts/backfill.py [--start 2019] [--end 2024] [--dry-run]

Requirements:
    pip install requests

Prerequisites:
    - Kestra must be running:  docker compose up -d
    - UI reachable at:         http://localhost:8080
"""

import argparse
import sys
import time

import requests

KESTRA_URL = "http://localhost:8080"
NAMESPACE  = "faers"
FLOW_ID    = "faers_quarterly_ingest"


def trigger_execution(year: int, quarter: str, dry_run: bool) -> str | None:
    label = f"{year} {quarter}"
    if dry_run:
        print(f"[DRY-RUN] Would trigger: {label}")
        return None

    url  = f"{KESTRA_URL}/api/v1/executions/{NAMESPACE}/{FLOW_ID}"
    resp = requests.post(url, json={"year": year, "quarter": quarter}, timeout=30)

    if resp.status_code not in (200, 201):
        print(f"  ERROR {resp.status_code} for {label}: {resp.text}", file=sys.stderr)
        return None

    exec_id = resp.json().get("id", "unknown")
    print(f"  Triggered {label} → execution ID: {exec_id}")
    return exec_id


def main() -> None:
    parser = argparse.ArgumentParser(description="Backfill FAERS quarterly data via Kestra")
    parser.add_argument("--start", type=int, default=2019, metavar="YEAR",
                        help="First year to ingest (default: 2019)")
    parser.add_argument("--end", type=int, default=2024, metavar="YEAR",
                        help="Last year to ingest (default: 2024)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print what would be triggered without actually calling the API")
    parser.add_argument("--delay", type=float, default=2.0, metavar="SECONDS",
                        help="Seconds to wait between triggers (default: 2)")
    args = parser.parse_args()

    if args.start > args.end:
        sys.exit("--start must be <= --end")

    quarters = [
        (year, f"Q{q}")
        for year in range(args.start, args.end + 1)
        for q in range(1, 5)
    ]

    total = len(quarters)
    print(f"Backfilling {total} quarters ({args.start} Q1 → {args.end} Q4)")
    if args.dry_run:
        print("(DRY-RUN mode — no executions will be created)\n")

    triggered, failed = 0, 0
    for i, (year, quarter) in enumerate(quarters, 1):
        print(f"[{i}/{total}]", end=" ")
        exec_id = trigger_execution(year, quarter, args.dry_run)
        if exec_id is not None:
            triggered += 1
        elif not args.dry_run:
            failed += 1
        if not args.dry_run and i < total:
            time.sleep(args.delay)   # avoid overwhelming Kestra

    print(f"\nDone. Triggered: {triggered}  Failed: {failed}  Total: {total}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
