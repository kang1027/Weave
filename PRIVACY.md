# Privacy

Weave is a local-first app. Your portfolio never leaves your Mac unless you explicitly export it.

## What Weave stores, and where

Everything is kept on your Mac only:

- `~/Library/Application Support/Weave/portfolio.json` — your assets, trades, and settings.
- `~/Library/Application Support/Weave/logos/` — any custom asset icons you upload.
- A local candle/quote/logo cache to avoid re-fetching market data and asset logos.

There is **no account, no sign-in, no cloud sync, and no server owned by this project.** Nothing you enter is
transmitted anywhere, except the keys of a broker account you choose to link, which go only to that broker.

## Network requests

Weave only makes requests to fetch **public market data** and asset logos:

- **Upbit** — public KRW crypto prices for the kimchi premium card (only when your base currency is KRW). No Upbit account or API key is used.
- **Binance** — crypto quotes and candles.
- **Naver Finance** — Korean stock quotes and candles, plus Korea/US/Japan stock logos.
- **Yahoo Finance** — US/Japan stock quotes, candles, and FX rates.
- **jsDelivr** — crypto icons from the open-source `cryptocurrency-icons` set.

Each logo is downloaded once and cached locally.

These requests contain only the symbol/endpoint being queried. Weave sends **no account identifiers, no API keys, and no personal data**. There is **no analytics, telemetry, tracking, or crash reporting** of any kind.

## Linked accounts (optional)

Nothing below happens unless you link an account or wallet in **Settings › Linked accounts**. The keys and
wallet addresses you enter are stored in the **macOS Keychain** for this Mac only — never in `portfolio.json`
or in backups.

- **Toss Securities Open API** (`openapi.tossinvest.com`) — Weave sends the client ID and secret you entered to
  Toss to get an access token, then reads your account list, holdings, and order history about every 5 minutes
  while the app runs. It never calls order APIs. Toss only answers IPs you allowed in its WTS settings.
- **ipify** (`api.ipify.org`) — only when you tap **Check this network's IP**, to show which IP to allow in Toss.
  It returns your public IP; nothing else is sent.
- **mempool.space** — for a linked Bitcoin wallet, the addresses you entered, to read their confirmed balance.
- **Public chain RPCs** (`ethereum-rpc.publicnode.com`, `arb1.arbitrum.io`, `mainnet.base.org`,
  `mainnet.optimism.io`, `polygon-bor-rpc.publicnode.com`) — for a linked EVM wallet, the address, to read the
  balances of a fixed list of known tokens on the chains you picked.
- **Binance** — current prices of the coins found in a wallet.

Wallet balances are public on-chain data, but these services can see which addresses are looked up from your
IP. Weave never asks for a seed phrase or private key and can't move coins.

Disconnecting deletes the keys or addresses from the Keychain together with the trades imported from that link.
**Delete all my data** does the same for every linked account.

## Updates

The packaged app checks for updates via [Sparkle](https://sparkle-project.org). It fetches an appcast and update archive over HTTPS from GitHub, and every update is verified with an EdDSA signature. Weave does **not** send a system profile with update checks.

## Data leaving your Mac

Apart from the broker keys described under Linked accounts, the only time your data leaves the device is when **you** choose **Export** and pick a destination — Weave writes a self-contained `.weave` backup to the location you select. Importing reads a file you choose. Neither step contacts any server.

## Market data & disclaimer

Market data comes from **unofficial public endpoints** and may be delayed, incomplete, or inaccurate. Weave is a personal tracking tool for your own bookkeeping — it is **not** financial or investment advice. Use it at your own risk.

## Questions

Open an issue or email **kang3171611@naver.com**.
