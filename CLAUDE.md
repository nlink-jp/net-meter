# CLAUDE.md — net-meter

**Organization rules (mandatory): https://github.com/nlink-jp/.github/blob/main/CONVENTIONS.md**

Project summary, structure, non-negotiable rules and the known gotchas live in
[AGENTS.md](AGENTS.md). Read it before changing anything here. Scope and the
decisions already made — including the alternatives that were rejected — are in
the [RFP](docs/ja/net-meter-rfp.ja.md); do not reopen them without a reason the
RFP did not consider.

The two rules worth repeating: this app requests **no permission of any kind and
makes no network connections of its own**, and a byte counter's delta is
**always taken modulo 2^32** — the field is 64 bits wide, the value is not.
