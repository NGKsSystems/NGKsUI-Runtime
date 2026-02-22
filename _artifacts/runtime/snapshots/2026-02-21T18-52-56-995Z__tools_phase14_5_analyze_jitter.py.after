import argparse
import csv
import json
import math
import statistics
import sys
from pathlib import Path


def percentile(values: list[float], pct: float) -> float:
    if not values:
        raise ValueError("percentile with empty values")
    if len(values) == 1:
        return values[0]
    sorted_vals = sorted(values)
    rank = (len(sorted_vals) - 1) * (pct / 100.0)
    low = int(math.floor(rank))
    high = int(math.ceil(rank))
    if low == high:
        return sorted_vals[low]
    weight = rank - low
    return sorted_vals[low] * (1.0 - weight) + sorted_vals[high] * weight


def to_int(row: dict[str, str], key: str) -> int:
    raw = (row.get(key) or "").strip()
    if raw == "":
        return 0
    return int(float(raw))


def to_float(row: dict[str, str], key: str) -> float:
    raw = (row.get(key) or "").strip()
    if raw == "":
        return 0.0
    return float(raw)


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze Phase 14.5 jitter CSV")
    parser.add_argument("--csv", required=True, help="Input jitter CSV path")
    parser.add_argument("--json", help="Optional output JSON path")
    parser.add_argument("--include-presentfail", action="store_true")
    parser.add_argument("--include-stall", action="store_true")
    parser.add_argument("--include-resize", action="store_true")
    args = parser.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        print(f"ERROR: csv not found: {csv_path}")
        return 2

    dt_values: list[float] = []
    abs_drift_values: list[float] = []
    abs_error_values: list[float] = []
    present_block_values: list[float] = []
    pacing_active_rows = 0
    sleep_or_spin_rows = 0
    total_used_rows = 0
    skipped = 0
    excluded_presentfail = 0
    excluded_stall = 0
    excluded_resize = 0

    with csv_path.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            present_failed = to_int(row, "present_failed")
            stall_injected_ms = to_float(row, "stall_injected_ms")
            resize_event = to_int(row, "resize_event")

            if not args.include_presentfail and present_failed == 1:
                skipped += 1
                excluded_presentfail += 1
                continue
            if not args.include_stall and stall_injected_ms > 0.0:
                skipped += 1
                excluded_stall += 1
                continue
            if not args.include_resize and resize_event == 1:
                skipped += 1
                excluded_resize += 1
                continue

            dt_ms = to_float(row, "dt_ms")
            drift_ms = to_float(row, "drift_ms")
            abs_error_ms = to_float(row, "abs_error_ms") if "abs_error_ms" in row else abs(drift_ms)
            present_block_ms = to_float(row, "present_block_ms")
            pacing_active = to_int(row, "pacing_active")
            slept_us = to_float(row, "slept_us")
            spin_us_actual = to_float(row, "spin_us_actual")
            dt_values.append(dt_ms)
            abs_drift_values.append(abs(drift_ms))
            abs_error_values.append(abs_error_ms)
            present_block_values.append(present_block_ms)
            total_used_rows += 1
            if pacing_active == 1:
                pacing_active_rows += 1
            if slept_us > 0.0 or spin_us_actual > 0.0:
                sleep_or_spin_rows += 1

    if not dt_values:
        metrics = {
            "count": 0,
            "mean_dt_ms": 0.0,
            "p50_dt_ms": 0.0,
            "p95_dt_ms": 0.0,
            "p99_dt_ms": 0.0,
            "max_dt_ms": 0.0,
            "mean_abs_drift_ms": 0.0,
            "p95_abs_drift_ms": 0.0,
            "max_abs_drift_ms": 0.0,
            "p95_abs_error_ms": 0.0,
            "p99_abs_error_ms": 0.0,
            "max_abs_error_ms": 0.0,
            "p95_present_block_ms": 0.0,
            "p99_present_block_ms": 0.0,
            "max_present_block_ms": 0.0,
            "pacing_active_rate": 0.0,
            "sleep_or_spin_rate": 0.0,
            "rows_skipped": skipped,
            "excluded_presentfail": excluded_presentfail,
            "excluded_stall": excluded_stall,
            "excluded_resize": excluded_resize,
        }
        if args.json:
            out_json_path = Path(args.json)
            out_json_path.parent.mkdir(parents=True, exist_ok=True)
            out_json_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
        print("ERROR: no rows after filters")
        print(f"rows_used=0 rows_skipped={skipped}")
        print(f"excluded_presentfail={excluded_presentfail}")
        print(f"excluded_stall={excluded_stall}")
        print(f"excluded_resize={excluded_resize}")
        return 3

    metrics = {
        "count": len(dt_values),
        "mean_dt_ms": statistics.fmean(dt_values),
        "p50_dt_ms": percentile(dt_values, 50.0),
        "p95_dt_ms": percentile(dt_values, 95.0),
        "p99_dt_ms": percentile(dt_values, 99.0),
        "max_dt_ms": max(dt_values),
        "mean_abs_drift_ms": statistics.fmean(abs_drift_values),
        "p95_abs_drift_ms": percentile(abs_drift_values, 95.0),
        "max_abs_drift_ms": max(abs_drift_values),
        "p95_abs_error_ms": percentile(abs_error_values, 95.0),
        "p99_abs_error_ms": percentile(abs_error_values, 99.0),
        "max_abs_error_ms": max(abs_error_values),
        "p95_present_block_ms": percentile(present_block_values, 95.0),
        "p99_present_block_ms": percentile(present_block_values, 99.0),
        "max_present_block_ms": max(present_block_values),
        "pacing_active_rate": (pacing_active_rows / total_used_rows) if total_used_rows else 0.0,
        "sleep_or_spin_rate": (sleep_or_spin_rows / total_used_rows) if total_used_rows else 0.0,
        "rows_skipped": skipped,
        "excluded_presentfail": excluded_presentfail,
        "excluded_stall": excluded_stall,
        "excluded_resize": excluded_resize,
    }

    if args.json:
        out_json_path = Path(args.json)
        out_json_path.parent.mkdir(parents=True, exist_ok=True)
        out_json_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    print(f"csv={csv_path}")
    print(f"count={metrics['count']}")
    print(f"mean_dt_ms={metrics['mean_dt_ms']:.6f}")
    print(f"p50_dt_ms={metrics['p50_dt_ms']:.6f}")
    print(f"p95_dt_ms={metrics['p95_dt_ms']:.6f}")
    print(f"p99_dt_ms={metrics['p99_dt_ms']:.6f}")
    print(f"max_dt_ms={metrics['max_dt_ms']:.6f}")
    print(f"mean_abs_drift_ms={metrics['mean_abs_drift_ms']:.6f}")
    print(f"p95_abs_drift_ms={metrics['p95_abs_drift_ms']:.6f}")
    print(f"max_abs_drift_ms={metrics['max_abs_drift_ms']:.6f}")
    print(f"p95_abs_error_ms={metrics['p95_abs_error_ms']:.6f}")
    print(f"p99_abs_error_ms={metrics['p99_abs_error_ms']:.6f}")
    print(f"max_abs_error_ms={metrics['max_abs_error_ms']:.6f}")
    print(f"p95_present_block_ms={metrics['p95_present_block_ms']:.6f}")
    print(f"p99_present_block_ms={metrics['p99_present_block_ms']:.6f}")
    print(f"max_present_block_ms={metrics['max_present_block_ms']:.6f}")
    print(f"pacing_active_rate={metrics['pacing_active_rate']:.6f}")
    print(f"sleep_or_spin_rate={metrics['sleep_or_spin_rate']:.6f}")
    print(f"rows_skipped={metrics['rows_skipped']}")
    print(f"excluded_presentfail={metrics['excluded_presentfail']}")
    print(f"excluded_stall={metrics['excluded_stall']}")
    print(f"excluded_resize={metrics['excluded_resize']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
