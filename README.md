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

## Install

```bash
brew install --cask nlink-jp/tap/net-meter
```

Or grab the signed + notarized zip from
[GitHub Releases](https://github.com/nlink-jp/net-meter/releases), unzip it and
move `NetMeter.app` to Applications.

## Using it

The menu bar item shows the upstream rate on the upper line and the downstream
rate on the lower, with a graph of the last fourteen seconds beside them — one
bar per second, moving left as time passes: upstream above the centre line,
downstream below it. The graph's scale follows the traffic; when a peak scrolls
out it comes down over a few seconds rather than all at once. A dash means there is no value for this
second; a dimmed item means the selected interface is not connected. The numbers
never show another interface in its place.

Click the item to open the panel: the last three minutes as a chart, the
interface's addresses and link speed, the peaks of those three minutes, and the
totals since launch. The link speed is what the interface reports, not a limit on
what it carries. The panel does not take the keyboard away from the app you are
working in. Click anywhere else, click the item again, or press Esc to close it.
The settings are in the same panel:

| Setting | Choices |
|---|---|
| Interface | Automatic — the physical link macOS currently prefers, even while a VPN is up — or any interface by hand |
| Display | Numbers and graph, numbers only, or graph only. The width changes with this setting and with nothing else |
| Unit | Bytes per second (KB/s, MB/s) or bits per second (kbps, Mbps) |
| Colour | Off: the item takes the menu bar's own colour, like the system's items. On: upstream and downstream get their own colours |
| Launch at login | Off by default. macOS may ask you to approve it in System Settings › General › Login Items |

The version is at the bottom of the panel and can be selected and copied.

Rates below about 1 KB/s alternate between 0 and 1: macOS reports the byte
counters to an ordinary app in steps of 1 KiB.

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
- [ADR-0001](docs/en/adr/0001-counter-readings-to-rates.md) — how counter readings become rates, and when a sample is thrown away
- [ADR-0002](docs/en/adr/0002-menu-bar-drawing.md) — how the menu bar item is drawn
- [ADR-0003](docs/en/adr/0003-non-activating-panel.md) — why the panel is a non-activating panel, not a popover
- [Spikes](spikes/README.md) — the measurements the design rests on

## License

MIT
