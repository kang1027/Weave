# Privacy

Weave is a local-first app. Your portfolio never leaves your Mac unless you explicitly export it.

## What Weave stores, and where

Everything is kept on your Mac only:

- `~/Library/Application Support/Weave/portfolio.json` — your assets, trades, and settings.
- `~/Library/Application Support/Weave/logos/` — any custom asset icons you upload.
- A local candle/quote cache to avoid re-fetching market data.

There is **no account, no sign-in, no cloud sync, and no server owned by this project.** Nothing you enter is transmitted anywhere.

## Network requests

Weave only makes requests to fetch **public market data**:

- **Binance** — crypto quotes and candles.
- **Naver Finance** — Korean stock quotes and candles.
- **Yahoo Finance** — US/Japan stock quotes, candles, and FX rates.

These requests contain only the symbol/endpoint being queried. Weave sends **no account identifiers, no API keys, and no personal data**. There is **no analytics, telemetry, tracking, or crash reporting** of any kind.

## Updates

The packaged app checks for updates via [Sparkle](https://sparkle-project.org). It fetches an appcast and update archive over HTTPS from GitHub, and every update is verified with an EdDSA signature. Weave does **not** send a system profile with update checks.

## Data leaving your Mac

The only time your data leaves the device is when **you** choose **Export** and pick a destination — Weave writes a self-contained `.weave` backup to the location you select. Importing reads a file you choose. Neither step contacts any server.

## Market data & disclaimer

Market data comes from **unofficial public endpoints** and may be delayed, incomplete, or inaccurate. Weave is a personal tracking tool for your own bookkeeping — it is **not** financial or investment advice. Use it at your own risk.

## Questions

Open an issue or email **kang3171611@naver.com**.
