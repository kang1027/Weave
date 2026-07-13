**English** · [한국어](FLOWS.ko.md)

# Weave Behavior Flows (QA/Review Reference)

An exhaustive list that unpacks the specification in `docs/FEATURES.md` into individual user-action units.
Each flow follows the "action → expected behavior" format, and reviews/QA validate against this document.

## F1. App Startup

- **F1.1 First launch**: No `portfolio.json` → start with an empty document. Menu bar shows `Weave`,
  and the popover shows onboarding (search bar + guidance + Manual Asset link).
- **F1.2 Relaunch**: Load document → start price polling and menu bar rotation; on the popover's first open,
  start a background refresh only once (subsequent opens refresh immediately only if more than 60 seconds have elapsed).
- **F1.3 Corrupted/future-version document**: On load failure, fall back to an empty document (logged).
  If the schema version is higher than the app's, refuse to load.
- **F1.4 No Dock icon**: LSUIElement/accessory policy. Quit only via ⌘Q (settings screen) or
  the quit button in settings.

## F2. Asset Search, Add, and Management

- **F2.1 Live search**: 2+ characters in the search field + 300ms debounce → Binance (local catalog
  filter), Naver (autocomplete), and Yahoo (search API) in parallel → merged list.
  Each row: logo (crypto = CDN, otherwise initials) · name · symbol · market badge (crypto / KR market / US market / JP market / other).
- **F2.2 Deduplication**: For the KR market, Naver takes priority (if there is a Naver response, remove Yahoo KR-market results);
  for crypto, Binance takes priority (remove Yahoo crypto entries with the same base symbol). Sort by exact match → prefix → contains.
- **F2.3 Add**: Click a result row → create the asset with provider/symbol/currency auto-set →
  save → navigate to that asset's detail. For Yahoo, currency is finalized from the first quote.
- **F2.4 Duplicate-add prevention**: If an asset with the same provider+symbol exists, don't create a new one; navigate to the existing detail.
- **F2.5 30-asset limit**: When exceeded, disable the add UI + show a notice.
- **F2.6 Manual Asset**: Enter name/currency/valuation/whether to include a chart → create (no price refresh,
  excluded from menu bar rotation). Return to the management screen.
- **F2.7 Asset management row**: Toggle menu bar display · change color (8 colors) · hide/unhide · delete.
  Delete goes through a confirmation dialog ("name + delete N trades together") and then deletes the asset along with its trades.
- **F2.8 Asset color**: On add, automatically assign the least-used color among the 8 palette colors.
- **F2.9 Hidden assets**: Excluded from the home list, rings, chart, menu bar, and aggregation. Visible only on the management screen.

## F3. Home

- **F3.1 Ring gauges**: Day (±2% = full ring) · Return (±25% = full ring, larger in the center) · Assets (donut).
  Day/Return split only holdings with the same sign as the portfolio P&L by contribution ratio (largest contribution first),
  Assets shows the top 4 by weight + "Other" (gray). Segments use a gap-less butt cap, starting at 12 o'clock and going clockwise.
  On hover, the segment thickens and a contribution amount/weight tooltip appears.
- **F3.2 Total**: Total valuation converted to the base currency + a solid daily-change badge (▲/▼).
  Hovering the total shows invested cost and signed unrealized P&L.
- **F3.3 Combined chart**: A per-day Σ(holdings quantity × close × FX rate) line + gradient, with the right y-axis =
  abbreviated amount in the base currency (masked in privacy mode). If the FX time series fails, fall back to the spot FX rate.
  Buy marker tooltips also show the converted price when the asset currency ≠ base currency.
  Displayed range = max(period start, first buy date). At buy-event positions, a circular asset-logo marker —
  on hover a tooltip (quantity@price · date · % vs. current) + a vertical guide, and on click, navigate to that asset's detail.
- **F3.4 By-asset chart**: Multi-line normalized % per holding (period start = 0%) in asset colors, with the right y-axis = %.
  Markers hidden.
- **F3.5 Period**: 1M/3M/6M/1Y — recompute on change (candles reuse the daily-candle cache).
- **F3.6 Asset list**: Fixed descending by valuation. Row: logo · name · quantity/buy count · current price · change badge.
  The current price follows the display-currency setting (source / base-converted). Click → detail.
  Context menu: pin/unpin · hide · delete. Assets whose quote failed show a stale icon.
- **F3.7 Footer**: `Weave {version} · Next refresh in {remaining time}` real-time countdown.
  When an update is found, it switches to a "{current} → {new} available" link. The ✎ on the right → asset management.
- **F3.8 Privacy mode**: eye toggle → amounts (total · current price · P&L amount) are heavily blurred,
  while tooltip amounts and the menu bar are masked with `•••••` (string limitation). Change rates (%) are preserved.
  Reflected immediately in the menu bar as well. Persists across app restarts (saved in settings).
- **F3.9 Manual refresh**: Click ↻ → refresh prices + FX immediately, and reset the countdown.

## F4. Menu Bar

- **F4.1 Rotation**: Display targets = not hidden + menu bar display on + not manual.
  Cycle at the configured interval (5/10/30s, off). If there is a pinned asset, show only the pin without rotation.
- **F4.2 Format**: Full (`BTC $60,000 ▲1.23%`) / Compact (`BTC ▲1.23%`) / Price only (`$60,000`).
- **F4.3 No target**: Portfolio total (`₩12,345,678 ▲1.23%`); if there is no total either, `Weave`.
- **F4.4 Privacy**: Mask amounts with `•••••`, preserve change rate. The price-only format is replaced with symbol + change rate.
- **F4.5 Quote failure**: Keep the last successful value (snapshot), and mark the row as stale.

## F5. Asset Detail

- **F5.1 Header**: ‹ back · asset name · ＋ (add trade). Current price + change badge + badge vs. average cost (when holding).
  Hovering the holding value shows invested cost and signed unrealized P&L.
- **F5.2 Chart**: Actual candle close line + asset-color gradient, right y-axis (abbreviated price), bottom x-axis.
  Average-cost dashed line (RuleMark + label, only when holding). Buy (B, green) / sell (S, red) markers —
  at actual fill-price coordinates, with hover tooltips. On hovering an empty area, a crosshair (vertical + horizontal guide) + a date · close tooltip.
- **F5.3 Interval and navigation**: Interval selection of 15m/1H/4H/1D/1W/1M. Drag / horizontal scroll = pan,
  vertical scroll over the chart · pinch · −/+ buttons = zoom (anchored at the cursor position, minimum 15 candles),
  ↺ button = reset to the latest range (90 candles). Controls are at the right of the interval pills row.
  The y-axis auto-fits the visible range. The x-axis is tied to the interval (intraday: midnight = date, otherwise HH:mm;
  daily and above: day/month/year depending on window length). Rendering covers only the visible range + buffer (down-sampled to at most 500 points)
  — even at a 1000-candle interval, hover/pan does not trigger a mark rebuild.
  Intraday cache TTL is 5–30 minutes, and KR-market intraday uses the Yahoo `.KS`/`.KQ` bridge.
- **F5.8 Chart double-click → add trade**: Double-clicking a point on the chart navigates to a trade form
  prefilled with that candle's date · close — you can save by entering just the quantity.
- **F5.4 Trades**: Newest first. On buy rows, the right = % vs. current; on sell rows, the right = realized P&L.
  A running realized-P&L total at the top (shown only on this screen). Row context menu: edit/delete (confirmation dialog).
- **F5.5 Footer**: `N buys · M sells` + `+ Add Trade`.
- **F5.6 Right after asset deletion**: Return to home/management without any residue of the detail screen.
- **F5.7 Manual asset detail**: No chart/trades — guidance + a link to the management screen.

## F6. Trade Entry

- **F6.1 Auto-calculation**: When 2 of quantity/price/total are entered, the remaining one is auto-calculated.
  Fields the user has touched are not overwritten. Input other than digits and the decimal point is blocked.
- **F6.1b In-form chart selection**: Clicking the mini chart at the top of the trade form (the interval data seen in the detail)
  maps that point's date · price into the form. Layout: chart → form → save button.
- **F6.1c Date selection**: Custom pill button → calendar popover (graphical). Future dates not allowed.
- **F6.2 Close prefill**: When a past date is selected, prefill the price with that day's close (candle cache, editable).
  When entering trade "edit", do not prefill for the original fill date (preserve the fill price).
- **F6.3 Sell validation**: Cannot exceed the holdings as of that date (when editing, exclude the trade itself).
  Show the available quantity + an error when exceeded + disable save.
- **F6.4 No future dates**: The DatePicker is limited to today.
- **F6.5 Save/edit/delete reflection**: Average cost (moving average) · realized P&L · quantity · home chart are recomputed immediately.
  Realized P&L = (sell price − average cost at time of sell) × quantity; average cost is preserved even after selling.

## F7. Data Pipeline

- **F7.1 Price polling**: Refresh all assets in parallel at the configured cycle (1/5/10/15 min, clamped to 60–900s).
  Daily change uses the source-provided value (crypto 24h rolling, stocks vs. previous close). Failed assets keep the previous value + stale.
- **F7.2 Candle cache**: Files per provider · symbol · cycle in `Application Support/Weave/cache/`.
  Re-requests on the same day hit the cache (0 network calls), refresh the next day, and fall back to the stale cache on refresh failure.
  Concurrent requests join the in-flight request.
- **F7.3 FX rates**: Spot rates cached for 1 hour (aggregation · menu bar); the daily time series shares the candle cache (combined chart).
  For the same currency, conversion is skipped (rate=1).
- **F7.4 Save**: Atomic save of `portfolio.json` right after every mutation. version field + migration chain.
- **F7.5 Binance symbol catalog**: exchangeInfo (USDT pairs) cached for one day; on failure, use the expired cache.

## F8. Settings

- **F8.1 General**: Auto-start (SMAppService, only when running from a bundle) · global shortcut (recording,
  ⎋ to cancel, remove via context menu, toggles the popover when triggered) · rotation interval · menu bar format.
- **F8.2 Appearance**: Theme (System/Slate/Light — switches immediately) · language (System/Korean/English
  — switches immediately, with number/date formats tied to the locale).
- **F8.3 Data**: Refresh cycle (restarts the polling loop) · base currency (KRW/USD/JPY — total · rings · chart
  recompute immediately) · asset display currency (source as-is / base-converted) · backup (JSON export) ·
  restore (error on validation failure, on success replace everything + refresh) · clear candle cache.
- **F8.4 Updates**: Auto-update toggle · check now (enabled only when there is a bundle + feed).
- **F8.5 Quit**: Quit Weave button + ⌘Q.
- **F8.6 Settings persistence**: All settings changes are saved immediately and persist across restarts.

## F9. Updates and Distribution

- **F9.1 Dev run**: `swift run Weave` — Sparkle/auto-start disabled (silently), all other features work.
- **F9.2 Bundle**: `scripts/bundle.sh` → `dist/Weave.app` (Info.plist: LSUIElement,
  SUFeedURL, version injection + Sparkle.framework + resource bundle).
- **F9.3 Release**: `scripts/release.sh` → ED public-key guard → sign → notarize → zip →
  EdDSA signing, all automated. Uploading the GitHub Release and adding the `docs/appcast.xml` entry are
  manual steps the script guides you through (served via GitHub Pages).
- **F9.4 Receiving updates**: The bundled app checks the appcast every 5 minutes → shows a footer badge when found → click to install.
