# net-meter

A macOS menu bar meter for one network interface: the current upstream and
downstream rate, as numbers and a graph.

The apps that can already do this offer it as one feature of an all-in-one system
monitor. net-meter does only this.

[日本語](README.ja.md)

## Requirements

- macOS 26 or later, Apple Silicon.
- No permissions. The app needs no privacy grant, no administrator rights and no
  entitlement, and it makes no network connections of its own.

> macOS releases are **Developer ID signed and Apple-notarized** (stapled). They
> launch without Gatekeeper prompts and work offline.

## Build from source

```bash
make build-app
```

This produces `dist/NetMeter.app`. Signing uses a Developer ID Application
identity from your keychain. Without one the build still succeeds and the app
keeps its ad-hoc signature, which is enough to run it on the Mac that built it.

```bash
make test
```

```bash
make run
```

`make run` starts a debug build from the terminal. Quit a running net-meter
first. The single-instance guard covers the assembled `.app` only: a debug binary
has no bundle identifier to be recognised by, so it starts anyway and a second
menu bar item appears.

## Documentation

- [RFP](docs/en/net-meter-rfp.md) — scope, behaviour and the design decisions behind them
- [Spikes](spikes/README.md) — the measurements the design rests on

## License

MIT
