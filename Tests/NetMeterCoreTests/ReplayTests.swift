import Foundation
import XCTest
@testable import NetMeterCore

/// Replays a log recorded by `spikes/watch.swift` through the real `Meter`.
///
/// Opt-in, because the log is a recording of one particular Mac and is not kept
/// in the repository:
///
///     NET_METER_REPLAY_LOG=/path/to/watch.jsonl swift test --filter ReplayTests
///
/// It prints what each interface's samples came out as. A reset in a log of
/// ordinary use is a finding — either the counters really restarted, or
/// ADR-0001 misjudged a good sample — so it fails the test unless
/// `NET_METER_REPLAY_ALLOW_RESETS=1` says the log is known to contain one.
final class ReplayTests: XCTestCase {
    func testReplayRecordedLog() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["NET_METER_REPLAY_LOG"] else {
            throw XCTSkip("set NET_METER_REPLAY_LOG to a log written by spikes/watch.swift")
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)

        var meter = Meter()
        var counts: [String: [String: Int]] = [:]
        var resets: [String] = []
        var rows = 0

        for line in text.split(separator: "\n") where line.hasPrefix("{") {
            guard let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let time = object["t"] as? Double,
                  let interfaces = object["if"] as? [String: [NSNumber]] else { continue }
            rows += 1
            var reading: [String: InterfaceCounters] = [:]
            for (name, values) in interfaces where values.count >= 5 {
                reading[name] = InterfaceCounters(
                    rxBytes: values[0].uint64Value, txBytes: values[1].uint64Value,
                    rxPackets: values[2].uint64Value, txPackets: values[3].uint64Value,
                    linkSpeed: values[4].uint64Value
                )
            }
            for (name, outcome) in meter.ingest(reading, at: time) {
                let label: String
                switch outcome {
                case .baseline: label = "baseline"
                case .tooSoon: label = "tooSoon"
                case .discarded(.intervalTooLong): label = "intervalTooLong"
                case .discarded(.reset):
                    label = "reset"
                    resets.append("t=\(time) \(name)")
                case .rate: label = "rate"
                }
                counts[name, default: [:]][label, default: 0] += 1
            }
        }

        XCTAssertGreaterThan(rows, 1, "no samples parsed from \(path)")
        print("replayed \(rows) samples")
        for name in counts.keys.sorted() {
            let summary = counts[name]!.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            let totals = meter.totals(for: name)
            print("  \(name): \(summary)  totals down=\(totals.downBytes) up=\(totals.upBytes)")
        }
        if environment["NET_METER_REPLAY_ALLOW_RESETS"] != "1" {
            XCTAssertTrue(resets.isEmpty, "samples judged a reset: \(resets)")
        }
    }
}
