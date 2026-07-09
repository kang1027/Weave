<div align="center">

<img src="assets/logo.svg" width="112" height="112" alt="Weave">

# Weave

**Korea, US & Japan stocks + crypto — right in your macOS menu bar. Local-only, no account, real P&L from your own trades.**

[![Release](https://img.shields.io/github/v/release/kang1027/Weave?label=release&color=6366F1)](https://github.com/kang1027/Weave/releases)
[![License](https://img.shields.io/github/license/kang1027/Weave?color=6366F1)](LICENSE)
[![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)

**English** · [한국어](README.ko.md)

<br>

<img src="assets/screenshot-menubar.png" width="300" alt="Weave in the macOS menu bar"><br>
<sub>Lives in your menu bar</sub>

<br><br>

<table align="center">
  <tr>
    <td align="center"><img src="assets/screenshot.png" width="230" alt="Portfolio overview"><br><sub><b>Portfolio</b></sub></td>
    <td align="center"><img src="assets/screenshot-detail.png" width="230" alt="Asset detail"><br><sub><b>Asset detail</b></sub></td>
    <td align="center"><img src="assets/screenshot-byasset.png" width="230" alt="By-asset chart"><br><sub><b>By asset</b></sub></td>
  </tr>
</table>

</div>

## Features

- **Lives in your menu bar.** A rotating ticker of your holdings — click for the full popover.
- **Korea, US & Japan stocks + crypto.** One symbol search across Binance, Naver, and Yahoo Finance.
- **Real cost basis & P&L.** Average cost, unrealized and realized returns computed from your own buy/sell history.
- **Value-history charts.** Combined and per-asset (1D / 1W / 1M / 1Y), ring gauges, and buy markers.
- **Manual assets.** Track anything without a ticker — real estate, cash, whatever you want counted.
- **Privacy mode.** Mask amounts while keeping percentages, in both the popover and the menu bar.
- **Yours, locally.** No account, no telemetry — your data never leaves the Mac. The `.weave` backup is self-contained, custom logos included.
- **Native & polished.** Slate / Light themes, English / 한국어, signed & notarized, and it updates itself via Sparkle.

## Install

### Homebrew (recommended)

```sh
brew install --cask kang1027/weave/weave-pt
```

One command — it taps and installs in one go. Signed with a Developer ID and notarized by Apple, so it launches without Gatekeeper warnings and keeps itself up to date through Sparkle. Update anytime with `brew upgrade --cask weave-pt`.

### Direct download

Prefer not to use Homebrew? Grab the latest `.dmg` from the [releases page](https://github.com/kang1027/Weave/releases/latest), open it, and drag **Weave** to your Applications folder. It's signed and notarized, so no Gatekeeper warning.

### Build from source

Requires macOS 14+ and a Swift toolchain.

```sh
git clone https://github.com/kang1027/Weave.git
cd Weave
scripts/fetch-sparkle.sh   # one-time — vendors Sparkle
swift run Weave            # run
swift test                 # unit tests
scripts/bundle.sh          # build dist/Weave.app
```

## Data & privacy

Your portfolio is stored only on this Mac (`Application Support/Weave`) and is never sent anywhere. Weave reads public quotes and candles from Binance, Naver, and Yahoo Finance — no accounts, no API keys, no telemetry. Details in [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md).

Market data comes from unofficial public endpoints and may be delayed or inaccurate. Weave is a personal tracking tool, not investment advice.

## Support

Weave is free and open source. If you'd like to support development, you can also get it from the Mac App Store as a paid build — the same app, just a way to chip in.

## Documentation

[Features](docs/FEATURES.md) · [Flows](docs/FLOWS.md) · [Privacy](PRIVACY.md) · [Security](SECURITY.md) · [Contributing](CONTRIBUTING.md)

## License

[MIT](LICENSE) © 2026 kang1027
