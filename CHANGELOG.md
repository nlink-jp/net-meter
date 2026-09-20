# Changelog

All notable changes to net-meter are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
Semantic Versioning.

## [0.1.0] - Unreleased

### Added

- Project scaffold: a menu bar item with a placeholder symbol, and a menu that
  shows the version and quits.
- A single-instance guard, so a second copy exits instead of stacking a second
  menu bar item.
- `make test` checks the documents as well as the code: relative links resolve,
  every English document has its Japanese mirror, and each pair names the same
  flags, make targets and snake_case identifiers.
- The rule that turns two counter readings into a rate, or into the reason there
  is none (ADR-0001): deltas modulo 2^32, samples after a stretched interval
  discarded, and counter resets told apart from wraps by the packet counters
  rather than the reported link speed. Not wired to the display yet.
- The rest of the pure core: a meter that keeps a baseline, a history, running
  totals and peaks for every interface at once; automatic selection that takes
  the first physical interface and never replaces an absent manual choice; rates
  formatted into a number that is never wider than three characters, in bytes or
  bits; and a graph scale shared by both directions with a floor.
- Interface labels ("Ethernet (en0)") and the manual selection list: hardware
  ports first in the OS preference order, the rest by name, loopback left out,
  and a manual choice that is currently absent kept in the list.
- The counter reader: one unprivileged `sysctl` per reading, for every interface
  at once. Its tests are live — on the Mac running them, an ordinary second on
  every interface must come out as a rate, never as a reset.
- Every SF Symbol name the app uses is listed in one place and resolved by a
  test, so a name that does not exist fails the build instead of leaving an
  invisible menu bar item.
