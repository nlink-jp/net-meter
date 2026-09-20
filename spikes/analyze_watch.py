#!/usr/bin/env python3
"""Reads a log written by spikes/watch.swift and reports what the design needs.

Per interface: how many samples, the largest bytes-per-packet ratio seen in one
sample (the reset rule leans on this having a physical ceiling), every sample
whose interval was stretched, every sample where a counter went backwards, and
every change in the interface preference order.

    python3 spikes/analyze_watch.py <log> [--gap SECONDS]
"""

import json
import sys

M32 = 1 << 32


def delta32(new: int, old: int) -> int:
    """Forward distance from old to new, modulo 2^32."""
    return (new - old) % M32


def backwards(new: int, old: int) -> bool:
    """True when the shorter way from old to new is backwards."""
    return delta32(new, old) >= M32 // 2


def load(path: str) -> list[dict]:
    with open(path, encoding="utf-8") as handle:
        return [json.loads(line) for line in handle if line.strip().startswith("{")]


def analyze(rows: list[dict], gap: float = 3.0) -> dict:
    report = {"samples": len(rows), "gaps": [], "backwards": [], "path_changes": [],
              "appeared": [], "disappeared": [], "interfaces": {}}
    previous = None
    for row in rows:
        if previous is None:
            previous = row
            report["path_changes"].append((row["t"], row["path"]))
            continue
        dt = row["t"] - previous["t"]
        if dt > gap:
            report["gaps"].append((previous["t"], row["t"], round(dt, 3)))
        if row["path"] != previous["path"]:
            report["path_changes"].append((row["t"], row["path"]))
        now, before = row["if"], previous["if"]
        for name in sorted(set(now) - set(before)):
            report["appeared"].append((row["t"], name))
        for name in sorted(set(before) - set(now)):
            report["disappeared"].append((row["t"], name))
        for name in sorted(set(now) & set(before)):
            rx, tx, ip, op = (delta32(now[name][i], before[name][i]) for i in range(4))
            went_back = [label for label, i in (("rx", 0), ("tx", 1), ("ipkts", 2), ("opkts", 3))
                         if backwards(now[name][i], before[name][i])]
            if went_back:
                report["backwards"].append((row["t"], name, went_back, round(dt, 3)))
                continue
            stats = report["interfaces"].setdefault(
                name, {"samples": 0, "max_rx_per_pkt": 0.0, "max_tx_per_pkt": 0.0,
                       "bytes_without_packets": 0, "max_rx_rate": 0.0, "max_tx_rate": 0.0,
                       "baud": now[name][4]})
            stats["samples"] += 1
            stats["baud"] = now[name][4]
            if dt > 0 and dt <= gap:
                stats["max_rx_rate"] = max(stats["max_rx_rate"], rx / dt)
                stats["max_tx_rate"] = max(stats["max_tx_rate"], tx / dt)
            for nbytes, npkts, key in ((rx, ip, "max_rx_per_pkt"), (tx, op, "max_tx_per_pkt")):
                if npkts > 0:
                    stats[key] = max(stats[key], nbytes / npkts)
                elif nbytes > 1024:  # one floor quantum of slack
                    stats["bytes_without_packets"] += 1
        previous = row
    return report


def main(argv: list[str]) -> int:
    gap = float(argv[argv.index("--gap") + 1]) if "--gap" in argv else 3.0
    report = analyze(load(argv[1]), gap)
    print(f"samples: {report['samples']}")
    for name, s in sorted(report["interfaces"].items()):
        print(f"  {name}: {s['samples']} samples, baud={s['baud']}, "
              f"max rate rx={s['max_rx_rate'] / 1e6:.1f} MB/s tx={s['max_tx_rate'] / 1e6:.1f} MB/s, "
              f"max bytes/packet rx={s['max_rx_per_pkt']:.0f} tx={s['max_tx_per_pkt']:.0f}, "
              f"samples with >1 KiB and no packets: {s['bytes_without_packets']}")
    for key in ("gaps", "backwards", "appeared", "disappeared"):
        print(f"{key}: {len(report[key])}")
        for item in report[key]:
            print(f"  {item}")
    print(f"path changes: {len(report['path_changes'])}")
    for t, path in report["path_changes"]:
        print(f"  t={t}: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
