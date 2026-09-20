#!/usr/bin/env python3
"""Tests for analyze_watch.py — conclusions in an ADR rest on what it reports."""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import analyze_watch as aw  # noqa: E402

PATH = [["en0", "wiredEthernet"], ["en1", "wifi"]]


def row(t, counters, path=PATH):
    return {"t": t, "wall": "", "path": path, "if": counters}


class AnalyzeWatchTests(unittest.TestCase):
    def test_delta_is_taken_modulo_2_to_the_32(self):
        self.assertEqual(aw.delta32(30_720, (1 << 32) - 51_200), 81_920)
        self.assertFalse(aw.backwards(30_720, (1 << 32) - 51_200))

    def test_a_counter_restarting_is_backwards(self):
        self.assertTrue(aw.backwards(12, 306_835_876))

    def test_ratio_and_rate_are_reported_per_interface(self):
        report = aw.analyze([
            row(0.0, {"en0": [0, 0, 0, 0, 1000]}),
            row(1.0, {"en0": [3_000, 60_000, 3, 2, 1000]}),
        ])
        stats = report["interfaces"]["en0"]
        self.assertEqual(stats["max_rx_per_pkt"], 1_000)
        self.assertEqual(stats["max_tx_per_pkt"], 30_000)
        self.assertEqual(stats["max_tx_rate"], 60_000)
        self.assertEqual(stats["bytes_without_packets"], 0)

    def test_bytes_without_packets_are_counted_beyond_one_floor_quantum(self):
        report = aw.analyze([
            row(0.0, {"en0": [0, 0, 0, 0, 0]}),
            row(1.0, {"en0": [1_024, 0, 0, 0, 0]}),   # one quantum of slack: not counted
            row(2.0, {"en0": [9_216, 0, 0, 0, 0]}),   # 8 KiB and no packets: counted
        ])
        self.assertEqual(report["interfaces"]["en0"]["bytes_without_packets"], 1)

    def test_stretched_interval_is_a_gap_and_does_not_feed_the_rate(self):
        report = aw.analyze([
            row(0.0, {"en0": [0, 0, 0, 0, 0]}),
            row(60.0, {"en0": [6_000_000, 0, 6_000, 0, 0]}),
        ])
        self.assertEqual(report["gaps"], [(0.0, 60.0, 60.0)])
        self.assertEqual(report["interfaces"]["en0"]["max_rx_rate"], 0.0)

    def test_backwards_sample_is_listed_and_kept_out_of_the_statistics(self):
        report = aw.analyze([
            row(0.0, {"en0": [5_000_000, 0, 5_000, 0, 0]}),
            row(1.0, {"en0": [2_048, 0, 2, 0, 0]}),
        ])
        self.assertEqual(report["backwards"], [(1.0, "en0", ["rx", "ipkts"], 1.0)])
        self.assertNotIn("en0", report["interfaces"])

    def test_interfaces_appearing_disappearing_and_path_changes(self):
        vpn = [["utun7", "other"]] + PATH
        report = aw.analyze([
            row(0.0, {"en0": [1, 1, 1, 1, 0]}),
            row(1.0, {"en0": [1, 1, 1, 1, 0], "utun7": [1, 1, 1, 1, 0]}, path=vpn),
            row(2.0, {"utun7": [1, 1, 1, 1, 0]}, path=vpn),
        ])
        self.assertEqual(report["appeared"], [(1.0, "utun7")])
        self.assertEqual(report["disappeared"], [(2.0, "en0")])
        self.assertEqual([t for t, _ in report["path_changes"]], [0.0, 1.0])


if __name__ == "__main__":
    unittest.main()
