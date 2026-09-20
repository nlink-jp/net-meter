# ADR-0001: Turning counter readings into rates — delta, discard and reset rules

| Field | Value |
|-------|-------|
| Status | **Accepted** |
| Date | 2026-09-20 |
| Binds | net-meter |
| Decision makers | nlink-jp maintainers |
| Triggered by | The wrap-versus-reset distinction the RFP left to "decide from Phase 1 measurements"; Amendments A2–A4 |

## Context

net-meter reads the per-interface cumulative counters once a second and derives a rate from
the difference to the previous reading. Showing a difference that cannot be trusted as a
rate produces a spike of several GB/s. Which differences to trust and which to throw away
has to be decided from measurements.

What has been measured (code and how to repeat it: `spikes/README.md`):

| Fact | Where and how many times |
|------|--------------------------|
| Byte counters arrive as the true value modulo 2^32, floored to 1 KiB | macOS 27.0 machine, wired: 3 times; macOS 26.6.2 VM: once. Each bracketed by `netstat` readings, with the true counter already past 2^32 |
| Packet counters arrive unaltered (not floored, equal to `netstat`) | macOS 27.0 on 2 interfaces, macOS 26.6.2 on 1, once or twice each. Whether they are truncated to 32 bits is unknown — no interface had reached 2^32 packets |
| The value readable as link speed is not a ceiling | A virtual NIC on the host reported 100 Mbps while carrying 2.3 Gbps; the VM's virtual NIC reported 0. Wired reported 2.5 Gbps (matching `ifconfig`), Wi-Fi about 239 Mbps |
| "Bytes ÷ packets" within one sample has a physical ceiling | Largest seen: 31,477, over 50 samples and 17 interfaces including a 286 MB/s load. TSO makes a packet larger than the MTU, but none exceeded 64 KiB |
| Samples where bytes grew by more than 1 KiB with zero packets | None in the same 50 samples |

Not measured yet: what a wake from sleep does to the counters; a VPN tunnel interface being
re-created; an adapter being unplugged. The rest of Phase 1's checks on real systems measure
these. The rules below are built to fail safe whatever those results are.

## Decision

Per interface, from the previous reading P, the current reading C and the elapsed time dt
between them, exactly one outcome is chosen, in this order. Elapsed time is measured with a
clock that keeps running during sleep (`ContinuousClock`).

1. **No P** → `baseline`. Remember C; show no rate. When an interface disappears from a
   reading its baseline is dropped, so when it comes back it always starts here. A tunnel
   interface being re-created and an adapter being replugged are handled by this path first.
2. **dt < 0.5 s** → `tooSoon`. Show nothing and keep P as the baseline. A timer that fires
   twice in quick succession after a stall would otherwise divide by a tiny interval.
3. **dt > 3 s** → `discarded(intervalTooLong)`. C becomes the baseline. The values are not
   looked at.
4. Take the byte and the packet deltas, both **modulo 2^32**.
5. **A packet delta above 2^26 × dt in either direction** → `discarded(reset)`. C becomes
   the baseline. A counter that went backwards shows up, modulo 2^32, as a huge step forwards.
6. **In either direction, byte delta > (packet delta + 16) × 131,072 + 1,024** →
   `discarded(reset)`. C becomes the baseline.
7. Otherwise → `rate`. The rate is the delta divided by dt, and only these deltas are added
   to the cumulative transfer.

Where the constants come from:

- **3 s**: allows one missed tick plus jitter. Even at this interval a saturated 10GbE link
  (3.75 GB) fits within 2^32 bytes. A 1-second interval is unambiguous up to about 34 Gbps;
  an interval stretched to 3 seconds, up to about 11 Gbps.
- **2^26 packets per second** (about 67 million): over four times the 10GbE ceiling at
  minimum frame size (about 14.9 million).
- **131,072 bytes per packet**: twice the largest measured (31,477) and twice the largest IP
  packet (65,535).
- **+16 packets, +1,024 bytes**: slack for the byte and packet counters not being updated
  together, and for the 1 KiB flooring.

A discarded sample, `baseline` and `tooSoon` reach the display layer as "no value", not as a
rate of zero.

## Consequences

- A wake from sleep is re-baselined by rule 3 whatever the counters actually do.
- A reset can still be missed. If the packet count just before the reset, modulo 2^32, lies
  within 2^26 × dt of the top, rule 5 lets it through. Even assuming that value is evenly
  spread, at a 1-second interval that is about 1.6% per direction and about 0.02% for both
  at once, and rule 6 has to pass as well. Real packet counts are usually far below 2^32, so
  the probability is lower still. The symptom of a miss is a spike lasting one sample.
- Real traffic above 34 Gbps cannot be measured correctly at a 1-second interval. Samples
  are not discarded on the strength of the reported link speed: that figure is unreliable,
  and as long as real traffic stays below that range the value is right, so discarding would
  be the greater loss.
- Because of the 1 KiB flooring, traffic below 1 KB/s alternates between 0 and one unit.
  Whether the display smooths that is outside this ADR.
- The rules are implemented as pure functions in `NetMeterCore`, and sequences of values
  taken from the measurements are used directly as test input.

## Alternatives considered

- **Cap at link speed × elapsed time** (the RFP's original candidate). Rejected. The
  measurements include a reported speed that was not the ceiling (100 Mbps reported, 2.3 Gbps
  carried) and one that was 0. It would discard good samples, and on 10GbE it would still let
  through roughly three in ten deltas after a reset.
- **Treat a counter smaller than last time as a reset.** Rejected. Byte counters wrap every
  4 GiB in normal operation, so going backwards and wrapping cannot be told apart from the
  values alone.
- **Trust the 64-bit field and handle no wrap.** Rejected. Truncation to 32 bits was measured
  on both macOS 26 and 27.
- **Measure elapsed time with a clock that stops during sleep.** Rejected. A sleep would hide
  inside an interval of ordinary length and rule 3 would never fire.
- **Use a state-change timestamp such as `ifi_lastchange`.** Deferred. It marks link state
  changes, with no guarantee that it marks a counter reset, and it has not been measured.
- **Use the private NetworkStatistics framework.** Rejected. Out of the RFP's scope (private API).

## References

- RFP §3 "How the data is read", §7 "Counter precision", Amendments A2–A4
- `spikes/README.md` — measurement code, how to repeat it, observation counts

## Amendments

### 2026-09-20 — What `tooSoon` shows (correcting the last sentence of the Decision)

The Decision ends with "a discarded sample, `baseline` and `tooSoon` reach the display layer
as 'no value'". For `tooSoon` that is wrong. `tooSoon` means nothing happened as far as this
reading is concerned: the baseline, the history and the previous outcome all stay where they
were, so the previous rate stays on display. A second reading arriving within half a second
is no reason to turn the display into a dash, and the implementation and its test
(`testTooSoonLeavesBaselineHistoryAndLatestAlone`) pin that behaviour. What reaches the
display as "no value" is `baseline` and `discarded`.

### 2026-09-20 — When reads keep failing (addition to the Decision)

An empty reading is ignored as a single failure; it is outside the rules. But once reads
have been failing for more than 3 seconds — the longest interval one sample may span — the
previous outcome of every interface is dropped and there is "no value". To go on showing the
last rate would no longer be showing what is happening. The first reading after recovery is
discarded by rule 3, and rates resume with the one after it.
