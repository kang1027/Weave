**English** · [한국어](FEATURES.ko.md)

# Weave Feature Spec

A macOS menu bar portfolio tracker. It always shows pinned asset prices in the menu bar,
and clicking it opens a 360×720 popover where you manage the entire portfolio.

- Stack: SwiftUI (MenuBarExtra) + Swift Charts, macOS 14+
- Design: based on `design/mockups-v5.html` (Slate/Light themes, ring gauges, logo-marker charts)
- Data sources: 3 fixed sources — Binance / Naver / Yahoo Finance; the user only does symbol search

---

## 1. Menu Bar

- Display target: rotates through the selected assets at an N-second interval (default 10s). A specific asset can be pinned.
- Format: `BTC $60,000 ▲1.23%`, with ▲/▼ depending on the change direction.
  Options: full (name + price + change %) / compact (symbol + change %) / price only.
- If there is no asset to display, it shows the portfolio total.
- When privacy mode is on, amounts are masked and only the change % is shown.
- Click → opens the popover. Clicking outside the popover closes it.

## 2. Home (popover main)

### 2.0 Header
- Left: refresh · Center: title · Right: privacy toggle (eye) + settings (gear). See section 8 for the icon mapping.
- **Privacy mode**: when on, amounts (price, valuation, P&L amount) are masked across the whole app,
  while change % is kept. Also applies to the menu bar (section 1).

### 2.1 Three ring gauges
- **Day**: splits today's change contribution into asset-colored segments. If the portfolio is up,
  it includes only the gaining contributors; if it's down, only the losing contributors (opposite-sign assets are excluded).
  Segment length = that asset's contribution ratio.
- **Return** (center, large): total return. Same split rule as Day.
- **Assets**: a valuation-weight donut (asset colors for all assets), with the asset count in the center.
- Segments are continuous with no gaps (butt cap). On hover they thicken and show a contribution/weight tooltip.
- Fill scale: Day ring ±2% = full ring, Return ring ±25% = full ring; beyond that it stays fully filled.
- Asset colors: a fixed palette of 8 colors is auto-assigned in the order assets are added, and can be changed manually in asset management.
  The Assets donut groups the top 4 by weight + the rest into "Other" (gray).

### 2.2 Total area
- Portfolio total valuation (converted to base currency) + a solid change-% badge. Hovering the total shows
  invested cost and signed unrealized P&L.

### 2.3 Value History chart
- Filter: **Combined** (portfolio value line + gradient fill) / **By Asset** (per-asset
  normalized multi-line, based on a 0% starting point). Range: 1M / 3M / 6M / 1Y.
- Displayed span: from max(selected range start, first buy date). There is nothing before the first buy.
- Combined mode: **circular asset logo markers** (asset-colored ring) at buy-event positions.
  - hover → tooltip (quantity@price · date · % vs. current) + vertical guideline.
  - click → navigates to that asset's detail.
  - Markers are hidden in By Asset mode.
- Implementation: Swift Charts `LineMark`+`AreaMark`, markers via `PointMark`+`annotation`,
  hover via `chartOverlay`+`ChartProxy`.

### 2.4 Assets list
- Row: logo · name · holding quantity / buy count · current price · solid change badge.
  - An asset held in a linked account or wallet gets a small badge on its logo (the Toss logo, or a wallet
    icon) for the place that holds the most of it. Hovering lists every linked place.
- Sorting: fixed descending by valuation.
- Row click → asset detail. Context menu: pin / hide / delete.

### 2.5 Footer
- Left: `Weave 0.1.0 · Next refresh in 4m` (version + countdown to next price refresh).
  When an update is available, it switches to a `Weave 0.1.0 → 0.2.0 available` badge; click to install.
- Right: ✎ icon (navigates to the asset management screen). Icon only, no text button.
- Settings is entered via the ⚙ icon in the Home header (section 9).

## 3. Asset Management & Search (✎)

Entered via ✎ in the Home footer. Consists of a top search bar + a held-asset management list.

### 3.1 Search & add
- A single search box. Live search on 2+ characters with a 300ms debounce.
- Queries the 3 sources in parallel and merges into one list. Each row has a market badge: crypto / KR market / US market / JP market / other.
  - **Binance**: caches the `exchangeInfo` symbol list locally → local filtering (crypto, USDT pairs by default)
  - **Naver**: `ac.stock.naver.com` autocomplete (KR market, Korean search)
  - **Yahoo**: `/v1/finance/search` (US/JP market and global other, fallback)
- If the same instrument appears from multiple sources, only one is shown: KR market = Naver, crypto = Binance takes priority.
  Yahoo handles US/JP market exclusively.
- On selection, the asset is created with provider · symbol · currency · logo auto-set. Duplicate adds are prevented.
- **Manual Asset**: for assets that can't be searched (real estate, unlisted, etc.). Name/currency/valuation entered manually,
  no price refresh. Option to exclude from the Combined chart (or show as a fixed average-cost line).
- Logo: crypto uses the `cryptocurrency-icons` set; Korea/US/Japan stocks use Naver stock logos. Logos are downloaded once and cached under `cache/logos/`. Assets without a logo (ETFs, etc.) fall back to an initial badge. Every logo, including custom uploads and initial badges, is shown as a circle.

### 3.2 Held-asset management
- Asset row: logo · name · menu bar display toggle · color change · hide · delete.
- Delete removes the trade history along with it, with a confirmation dialog ("N trades will be deleted along with it").
- Asset count soft limit of 30 (to protect against API rate limits).
- Empty state (0 assets): an onboarding screen instead of Home — search bar + "Try searching for a
  symbol like BTC, Samsung Electronics, or AAPL" guidance.

## 4. Asset Detail

- Header: back · asset name · add trade (＋).
- Current price + change badge + vs. average-cost badge. Hovering the holding value shows
  invested cost and the signed unrealized P&L amount.
- Header `LIVE` toggle: while enabled, samples only this asset's quote every second and
  renders a rolling 1-second chart; it stops automatically when leaving the detail screen.
- **Kimchi premium card** (crypto, base currency KRW only): the Upbit KRW price, the Binance price
  converted to KRW (`$price × USD/KRW`), and the premium %, plus a 30-day daily premium sparkline with
  its min~max range. Refreshed on each quote refresh, not by `LIVE`, with a USD/KRW rate at most 5 minutes old. Hidden for coins without an
  Upbit KRW market.
- **Chart** (Swift Charts):
  - Actual candle close line + gradient fill (asset color), price on the right y-axis, dates on the bottom x-axis.
  - Average-cost dashed line (`RuleMark` + dash) + label.
  - Buy (B, green) / sell (S, red) circular markers — hover tooltip, positioned at actual fill-price coordinates.
  - hover crosshair + date/price tooltip.
  - Intervals: 15m / 1H / 4H / 1D / 1W / 1M (monthly candle).
  - Navigation: horizontal drag/scroll = pan, pinch = zoom, double-click = reset to the latest span.
    The y-axis auto-fits to the visible span.
- **Trades list**: a round icon (buy ↓ · sell ↑ · move ⇄ · opening balance ⚑) · title ("Buy 3 ETH",
  "Manual → Main wallet") · date and price · on the right, the amount with "% vs. current" for buys and
  "realized P&L" for sells; moves and opening balances show the quantity. Dates read "Oct 29" this year and
  "Sep 15, 2024" before. Edit/delete via the row context menu.
- The realized P&L running total is shown at the top of the Trades section. Realized P&L is exposed only on this screen
  (the Home rings/total stay on an unrealized basis).

## 5. Trade Entry (buy/sell)

- Fields: type (buy/sell) · quantity · unit price · total · date · memo.
- Entering 2 of quantity/unit price/total auto-calculates the remaining one.
- Selecting a past date auto-prefills the unit price with that day's close (using the candle cache, editable).
- Sell validation: cannot exceed the held quantity.
- Realized P&L = (sell unit price − average cost at time of sale) × quantity. Average cost uses the moving-average method.

## 6. Price Data Pipeline

- **Quote (current price)**: Binance ticker / Naver quote / Yahoo chart meta.
  Periodic polling (default 300s, configurable 60–900s). On failure, keeps the last value + shows stale.
  The detail-screen `LIVE` toggle temporarily overrides this for the selected asset with 1-second sampling
  and a rolling live chart.
- **Candle (history)**: Binance klines / Naver fchart / Yahoo chart.
  Intervals 15m/1H/4H/1D/1W/1M. Local cache (`Application Support/Weave/cache/`) —
  daily and above refresh once a day, intraday uses a 5–30 min TTL.
  KR-market intraday isn't supported by fchart, so it bridges via Yahoo `.KS`/`.KQ` symbols.
  Yahoo doesn't provide 4H → 1H is synthesized on the client. The Home Combined chart is fixed to daily candles.
- **FX**: Yahoo `KRW=X`, `JPY=X`, etc. Cached for 1 hour. Aggregate calculations are converted to the base currency.
- An asset's currency is determined by its **listing market**, not the provider (even on Yahoo, 005930.KS is
  KRW). Asset rows display in the source currency by default; conversion applies only to aggregation (section 9).
- Providers are abstracted behind a protocol (Naver/Yahoo are unofficial APIs — if the spec changes, only the adapter is swapped).

## 7. Portfolio Calculation

- Per instrument: average cost (moving average) · holding quantity · valuation = quantity × current price · unrealized P&L · return ·
  daily change · weight.
- The daily-change basis uses the source-provided value as-is: crypto = 24h rolling (Binance), stocks = vs. previous
  close. It is not forcibly unified.
- Portfolio: sum of instruments (after conversion) · total return · daily change · ring contribution
  (the P&L ratio of instruments with the same sign as the portfolio P&L) · realized P&L running total.
- **Value time series** (for the Combined chart): daily Σ(that day's holding quantity × that day's close × that day's FX rate).
  Holding quantity is a step function keyed to trade dates. Computed locally from the candle cache.

## 8. Themes & Icons

- **Slate**: bluish charcoal (#2B2D35 base) + vivid system colors.
- **Light**: light gray (#F4F4F6) + light system colors.
- The default is **follow system appearance** (dark → Slate, light → Light); can be manually fixed in settings.
- All colors are managed as semantic tokens (ported directly from the mockup variables).

### Icon policy
- All icons in the app use **SF Symbols**. Emoji and color glyphs are forbidden.
- Monochrome; colors follow semantic tokens (usually `--text2`, and `--link`/`--green` when active).
- The glyphs in the HTML mockup (↻, ⚙, ✎, etc.) are only approximations; the mapping below is the implementation reference.

| Location | Function | SF Symbol |
|------|------|-----------|
| Home header left | Manual refresh | `arrow.clockwise` |
| Home header right | Privacy toggle | `eye` / `eye.slash` (when on) |
| Home header right | Enter settings | `gearshape` |
| Home footer right | Enter asset management | `square.and.pencil` |
| Common header left | Go back | `chevron.left` |
| Detail header right | Add trade | `plus` |
| Asset management row | Menu bar display | `menubar.rectangle` |
| Asset management row | Hide / delete | `eye.slash` / `trash` |
| Settings | Register shortcut | `keyboard` |
| Settings | Quit app | `power` |
| Search | Search field | `magnifyingglass` |

## 9. Settings Screen & Localization

- Entry: the ⚙ icon in the Home header → the settings screen inside the popover (return with ‹, vertical scroll).
- UI: section labels + **group cards** (rounded), with controls on the right of each row — toggle / select
  dropdown / button. (OpenUsage settings-screen style)
- **General**
  - Launch at login (toggle, `SMAppService`)
  - Global shortcut (record button) — open the popover
  - Menu bar rotation interval (select: 5s / 10s / 30s / off)
- **Appearance**
  - Theme (select: System / Slate / Light, default System)
- **Data**
  - Price refresh interval (select: 1/5/10/15 min)
  - Base currency (select: KRW/USD/JPY; new installs default to KRW for Korean systems, JPY for Japanese systems, USD otherwise)
    — used **only for aggregate calculations** like total and the Combined chart
  - Asset display currency (select: **source currency as-is** (default) / convert to base currency)
    — with source currency, BTC shows in $ and Samsung Electronics in ₩, each in its own currency
  - Data backup/restore (button) · clear candle cache · permanently delete all data after a successful backup export
- **Updates**
  - Auto update check (toggle) · check now (button) · release notes link
- At the very bottom: a **Quit Weave** button (+ ⌘Q) — as a menu bar app there's no Dock quit path.
- Footer: version + countdown to next refresh.
- **Language**: English only. Strings go through `en.lproj/Localizable.strings` (keys = English source text; lproj
  instead of xcstrings because the SwiftPM CLI build can't compile xcstrings). Dates and numbers use the `en_US`
  locale so they match the English UI on any system language. Base currency still defaults from the system
  language.

## 10. App Updates & Version Management

- **Sparkle 2** adopted (the menu bar app standard, same approach as OpenUsage).
  - Upload a notarized zip to GitHub Releases + publish `appcast.xml` (GitHub Pages).
  - The repo is **public** — simplifies Releases distribution / appcast hosting.
  - EdDSA signing, 5-min auto-check interval, one-click download→restart.
- Versioning: semver (`0.x.y`), with release notes per release on GitHub Releases. The current version is always shown in the footer.
- Requirements: Developer ID signing + notarization (without them, Gatekeeper blocks updates).

## 11. Data Storage

- `Application Support/Weave/portfolio.json` — assets · trades (buy/sell) · settings.
- The schema has a `version` field, with a migration chain on load.
- Quote/candle/FX caches are separate files (separated from the portfolio data, harmless to delete).
- `sources` lists linked accounts and wallets (kind · display name · masked account/address label · last sync).
  Keys and full addresses are not stored in the document. A trade imported from a source keeps its
  `sourceID` and the source's execution ID (`externalID`); manual trades have neither.
- The file is saved as `version` 3 only once a source or an imported trade exists. Otherwise it stays at
  version 2 so v0.1.x builds can still open it. A v0.1.x build refuses a version 3 file instead of
  silently dropping the linked data.

### Linked accounts

Settings › Linked accounts. Toss Securities and crypto wallets work today; Korea Investment comes later. Upbit
is left out because its API keys require an allowlisted static IP.

- **Toss Securities**: the user pastes the Open API client ID and secret from WTS › Settings › Open API.
  Weave checks them, picks the brokerage account, and stores the keys plus `accountSeq` in the macOS Keychain
  (this Mac only). The document keeps only the masked account number (`••••8901`).
- **Allowed IPs**: Toss only answers IPs registered in WTS. The setup screen shows this network's IP with a
  copy button in step 2, so it can be allowed before connecting. On another network a sync pauses, the row
  shows the IP to add, and the last synced data stays. The IP comes from `api.ipify.org`, asked only on the
  setup screen and when a sync fails for this reason.
- **What is read**: holdings (quantity · average cost · current price, which only feeds the review screen's values) and orders. The first sync reads every closed order
  since the account opened; later syncs read from 7 days before the last sync. An order is one row with its
  total filled quantity and average fill price, so one order becomes one imported trade (`externalID` =
  order ID). Partly filled then canceled or replaced orders keep their filled part; `CANCEL_REJECTED` and
  `REPLACE_REJECTED` records are skipped. Holdings and open orders are read before and after the order
  history; an instrument that moved in between, or has an order still filling, is not reconciled this time.
  Order APIs are never called.
- **Access token**: Toss allows one valid token per client, so Weave reuses it until a minute before it
  expires and reissues once on a 401.
- **First sync** goes to a review screen: the total on top, then one row per asset with what happens to it
  (New · Moved · Orders · Merged · Opening · Adjusted · Check) and a "New asset" tag, then the skipped balances
  folded into one line. Later syncs run with the quote refresh, at most every 5 minutes, and apply without
  review.
- **Accounts & wallets**: the linked total with **Sync all** on top, then brokers and wallets. Each row shows
  the value, a few holding logos, and its state (synced · syncing · review · paused). Anything to do, like a
  review, an IP to allow, or the keychain prompt, sits inside that row instead of a banner.
- **New assets**: Korean stocks are created on Naver, US stocks on Yahoo (`BRK.B` → `BRK-B`). Positions that
  were sold out and have no asset in Weave are left out. When the 30-asset limit blocks a new asset, its
  trades wait and `lastSyncedAt` does not move, so they come in once there is room.
- **Last sync** is the time the snapshot was taken, even if the review was applied later.
- **Disconnect** deletes the keys, the imported trades, and assets whose every trade came from that account.

#### Wallets

- **Bitcoin**: one or more addresses per wallet; confirmed balances from `mempool.space`. xpub discovery is
  not supported yet.
- **EVM**: one address on Ethereum, Arbitrum, Base, Optimism, and Polygon (pick any). Each chain's public RPC
  is called once through Multicall3 for the gas coin plus a fixed token list
  (`EVMTokenList.swift`, generated by `scripts/update-evm-tokens.py` from the Uniswap default list ∩ Binance
  USDT markets; the script swaps legacy contracts the list still carries, such as KNC v1, for the ones Binance
  trades). Unknown contracts are never read, so spam tokens with look-alike symbols don't come in. WETH
  counts as ETH. A failed balance call stops the sync instead of reading as zero.
- **Yield and staking tokens** (`EVMYieldTokens.swift`, hand-kept, each address checked on-chain): Aave v3
  aTokens, static aTokens (waEth…), and Umbrella stake tokens (stkwaEth….v1) become their own assets, e.g.
  "Aave Umbrella USDC · stkwaEthUSDC.v1". They use the `onchain` provider: price = the vault's
  `convertToAssets` rate for one token (Umbrella: stk → waEth → underlying, aTokens 1:1, cached 60s) × the
  underlying coin's Binance price. Charts are the underlying's candles times today's rate, and the logo is the
  underlying's. A holder of a vault token sees interest as price growth. USDT and GHO have no Binance price, so
  those tokens only show under "Not imported". A wallet change worth under $5
  waits until it adds up, so accruing interest doesn't log a trade every sync.
- **Connection detail**: tapping a link shows its value and state on top, the holdings it brought in with each
  one's share, the balances it left out (under $10 or no Binance price) folded into one line, then the address
  (with copy), chains, and last sync. **Sync now** and **Disconnect…** sit at the bottom.
- **Coins**: only coins with a Binance USDT market. New coins become Binance assets (`BTCUSDT`). A balance
  under $10 doesn't bring in a new coin, but a coin the wallet already holds keeps being reconciled, so it
  doesn't flip in and out around $10. A coin with a balance but no price (delisted, halted) is skipped for that
  sync instead of reading as zero.
- **No trade history**: a wallet only has balances, so changes are recorded as moves against the manual
  holdings, at average cost:
  - More in the wallet → the same amount moves over from the manual holdings at their average cost. What the
    manual holdings can't cover starts at the market price (an opening balance on the first link, a balance
    adjustment later).
  - Less in the wallet → the difference goes back to the manual holdings at the wallet's average cost, so a sale
    on an exchange can be entered there as a manual sell.
  - Both sides of a move are locked. The trade list shows one move row (wallet side), and moves are left out
    of buy/sell counts, chart markers, and the asset's average cost and realized P&L (only each location's own
    ledger uses them).
  - All wallets sync together: decreases are applied first, then increases, so coins sent from one linked wallet
    to another aren't counted twice whichever wallet is synced.
  - A manual buy whose coins moved to a wallet can't be deleted or lowered below what moved.
  - Disconnecting deletes the moves, so the manual holdings come back. If coins that came back were sold by hand
    afterwards, that asset's manual-side moves stay as plain trades (with a note) so the manual holdings never go
    negative.

- **Already imported**: executions whose `externalID` is already in the document are skipped, as are repeats in the same sync.
- **Same trade entered manually**: same asset · side · quantity, same day, price within 1% → suggested as a
  duplicate. By default the imported record replaces the manual one.
- **Opening balance**: when the holding is larger than the fetched history explains, an opening-balance buy
  is added just before the history starts. Its price is solved so that replaying the history gives the
  source's average cost. One opening balance per source and asset.
- **Balance adjustment**: the account is the original, so a gap the history can't explain is closed with a
  locked adjustment trade dated at the sync. Holding less than the history (transfer out, after-hours sale)
  → a sell at the average cost, so no realized P&L (a reverse split keeps the old average). Holding more once
  the source already has trades for the asset (transfer in, split) → a buy priced so the average matches the
  account, which is 0 for a split. Only the first import uses an opening balance.
- **Needs review**: a history that dips below zero; a missing average cost; or manual trades on the same
  asset that could double count with an opening balance (deleting them lets the next sync match the
  account). These are not filled in automatically.
- **Dust**: holdings under a threshold (₩10,000 planned) are skipped unless the asset already exists.
- **Locked**: imported trades can't be edited or deleted in the app (the source is the original). A manual
  sell can only sell what was entered manually, so it never reduces a linked account's holding.
- **Deleting an asset** also deletes its imported trades. If a linked account still holds it, the next sync
  brings it back.
- **Where it's held**: the detail screen shows how much of the asset sits in each source and in manual
  trades, with each one's value and share, once the asset has an imported trade.

---

## 12. Implementation Order (milestones)

| # | Scope | Done criteria |
|---|------|-----------|
| M0 | Project setup | Weave package/target, theme tokens, empty popover runs |
| M1 | Data layer | Models · store · quote/candle/FX providers + cache, unit tests pass |
| M2 | Search / asset add | Creating an asset via 3-source live search works E2E |
| M3 | Home + menu bar | Rings / charts (Combined · By Asset) / list / menu bar title render with real data |
| M4 | Detail + trades | Real chart + markers + trade CRUD, realized P&L calculation |
| M5 | Release prep | Sparkle updates, settings screen, signing/notarization, 0.1.0 release |

## 13. Confirmed Decisions

1. **Repo**: start from scratch in a new repo. No porting of MarketBar code; this spec is the sole reference.
2. **Signing**: Developer ID in hand — proceed with Sparkle full auto-updates.
3. **SwiftBar import**: not supported. No legacy migration.
4. **Menu bar**: multi-asset rotation supported by default (see section 1).
5. **Settings UI**: group card + select dropdown style (OpenUsage reference).
6. **Currency**: base currency (KRW/USD/JPY) is for aggregation; asset display defaults to the source currency as-is.
7. **Privacy mode**: included in v0.1 — an eye toggle in the Home header (left of the settings icon), masks amounts / keeps change %.
8. **repo**: public.
9. **Detailed policies**: daily change on a source basis / ring scale Day ±2% · Return ±25% /
   8-color palette auto-assignment / list ordered by valuation / Combined chart from the first buy date /
   realized P&L on detail only / buy unit-price prefill supported / search dedup merged by source priority /
   asset soft limit of 30.

## 14. Backlog (v0.2+)

- Price alerts: macOS notification when the target price is reached, with an alert line on the chart
- Trade fee field (reflected in average cost / realized P&L)
- Volume bars on the detail chart
- Manual asset sorting · buy-marker clustering (grouping N trades in the same period)
- Update beta channel (separate Sparkle appcast)
- iCloud Drive backup / multi-Mac sync
- macOS widget (portfolio summary)
