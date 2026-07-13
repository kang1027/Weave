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
- Portfolio total valuation (converted to base currency) + a solid change-% badge.

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
- Logo: crypto uses a bundled icon set; for stocks, falls back to an initial badge if the logo cache fails.

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
- **Chart** (Swift Charts):
  - Actual candle close line + gradient fill (asset color), price on the right y-axis, dates on the bottom x-axis.
  - Average-cost dashed line (`RuleMark` + dash) + label.
  - Buy (B, green) / sell (S, red) circular markers — hover tooltip, positioned at actual fill-price coordinates.
  - hover crosshair + date/price tooltip.
  - Intervals: 15m / 1H / 4H / 1D / 1W / 1M (monthly candle).
  - Navigation: horizontal drag/scroll = pan, pinch = zoom, double-click = reset to the latest span.
    The y-axis auto-fits to the visible span.
- **Trades list**: buy/sell chip · quantity@price · date/memo · on the right,
  "% vs. current" for buys and "realized P&L" for sells. Edit/delete via the row context menu.
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
  - Language (select: System / 한국어 / English, default System)
- **Data**
  - Price refresh interval (select: 1/5/10/15 min)
  - Base currency (select: KRW/USD/JPY) — used **only for aggregate calculations** like total and the Combined chart
  - Asset display currency (select: **source currency as-is** (default) / convert to base currency)
    — with source currency, BTC shows in $ and Samsung Electronics in ₩, each in its own currency
  - Data backup/restore (button) · clear candle cache
- **Updates**
  - Auto update check (toggle) · check now (button) · release notes link
- At the very bottom: a **Quit Weave** button (+ ⌘Q) — as a menu bar app there's no Dock quit path.
- Footer: version + countdown to next refresh.
- **Localization**: 2 languages, Korean/English, based on `{ko,en}.lproj/Localizable.strings` (keys = English
  source text; xcstrings is used because the SwiftPM CLI build can't compile it, so lproj was adopted). The default is the system
  locale, with a per-app override in settings. Number/currency/date formats follow locale rules
  (`FormatStyle`).

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
