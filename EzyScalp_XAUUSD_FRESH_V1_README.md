# EzyScalp XAUUSD FRESH V1 — Phase 1

## v1.02 update

v1.01's report came back: 12 closed trades, 1.14 lots traded on a $1000
test day, against the old V2.1b EA's 80 lots on the **same date** — a
~70x gap. That gap is not about per-trade size (both EAs size roughly
0.10 lot at $1000 equity) — it's about **signal count**. The old EA has
several parallel signal-generation paths (zone touches across H4/D1/W1
levels, a zero-confluence low-exposure fallback, persistent setups, direct
market triggers) all feeding the same position stream; a single N-bar
channel breakout is inherently a "sometimes" event next to that.

Changes:

- **New second entry trigger, `InpUseMomentumCandleTrigger` (default ON)**:
  fires on any single M1 candle whose body alone is a large-enough fraction
  of ATR (`InpMomentumCandleATRFraction`, default 0.25) — no requirement to
  clear any N-bar extreme at all. This runs *alongside* the channel
  breakout, not instead of it; either one can produce a signal. This is the
  main volume lever in v1.02.
- `InpChannelLookbackBars`: 10 → **5**.
- `InpBreakoutATRFraction`: 0.05 → **0.0** (any close beyond the channel
  now counts, no minimum clearance).
- `InpMaxConcurrentPositions`: 5 → **15**.
- `InpUseTrendFilter`: **OFF by default now** (was ON) — it was refusing
  roughly half of every candidate signal, a direct tax on the volume
  objective. Still there as a one-input toggle if the wider trade count
  trades away more win rate than you want.

**Worth knowing**: at $1000 equity and ~0.10 lot/position, 15 concurrent
positions would need roughly $1,300 of margin at 1:500 leverage — more
than the account has. In practice you likely won't see all 15 filled at
once; orders will start failing on insufficient margin before that, logged
as `ENTRY FAILED`. That's expected, not a bug — margin becomes the real
ceiling on concurrent exposure at this equity level, not the input.


## v1.01 update

First test run (compiled clean, ran on the tester) came back with two issues:

1. **No reporting.** Fixed — `OnDeinit()` now prints a `PERFORMANCE REPORT` line
   (closed trades, wins/losses/flat, win rate, lots traded, net profit),
   built from the EA's own deal history (`HistorySelect` scoped to when the
   EA attached, so it never mixes in unrelated trades and stays fast even on
   a long-running account).
2. **Trade frequency too low.** Three entry-frequency levers were tightened
   toward "quality over quantity" in v1.00; loosened toward "quantity" now,
   per the stated objective (maximum daily lot volume):
   - `InpSignalTimeframe`: M5 → **M1** (5x more bars/day)
   - `InpChannelLookbackBars`: 20 → **10** (a shorter channel clears far more often — the single biggest lever on signal count)
   - `InpBreakoutATRFraction`: 0.15 → **0.05** (more marginal breaks now qualify)
   - `InpMaxConcurrentPositions`: 3 → **5** (so more concurrent signals can actually be acted on)

   **Understood tradeoff:** more signals from a shorter, looser channel means
   more of them will be noise rather than a genuine sustained move — expect
   win rate per trade to come down some in exchange for materially higher
   trade count and lot volume. That's the explicit priority you set, not an
   oversight.


A clean-slate rebuild for XAUUSD, started after two weeks of patching
`EzyMap_V2_1b`/`V2_2` revealed the old file's accumulated complexity
(confidence-tier lot scaling, three separate layer-builders, a
zero-confluence bypass path, ATR geometry bolted onto a fixed-pip base) was
harder to reason about than the strategy itself. **Nothing is carried over
from that file** — this is a fresh design, built directly from the design
discussion and your three explicit answers:

1. **Style**: scalping — frequent, small, fast trades.
2. **Objective**: minimum daily drawdown, maximum daily lot volume traded —
   not a per-trade risk-percentage target.
3. **Risk**: no specific risk-per-trade; a single daily circuit breaker at
   75% (deliberately loose, a backstop against a catastrophic day, not a
   tight governor).
4. **News**: trade it deliberately (breakout mode) — **not yet built**, see
   "What's not in this file" below.

## Sizing — exactly as you specified

`LotForEquity()`: 100 (USD or USC) equity uses 0.01 lot. An account **below**
100 still sizes as if it had 100 (a floor, never a below-minimum lot). An
account **above** 100 scales up linearly from that same 100/0.01 anchor.
Flat and proportional — no confidence tier, no per-signal multiplier, no
risk-percentage/stop-distance calculation. This is the exact mechanism that
caused the live lot-doubling bug on the old EA, and it is deliberately
absent here from day one rather than removed after the fact.

`InpBaseEquity` and `InpBaseLot` control the 100/0.01 anchor if you ever
want to change it.

## What Phase 1 actually does

- **Entry**: a Donchian-style breakout — price clears the highest high /
  lowest low of the last `InpChannelLookbackBars` CLOSED bars (default 20,
  on M5) by at least `InpBreakoutATRFraction` (default 0.15) of the live
  ATR. One decision per bar. An optional H1 EMA trend filter (default ON)
  refuses counter-trend breakouts outright — gold has been a choppy,
  news-driven correction through 2026 (Fed-leadership uncertainty,
  geopolitical spikes), and a pure two-directional breakout scalper would
  get chopped up trading against that structure.
- **Exit**: stop = live ATR × `InpATRStopMultiplier` (default 1.2), target =
  stop distance × `InpRewardRiskMultiple` (default 1.2R). Both are
  ATR-relative, never a fixed pip guess — that guess-the-instrument's-scale
  mistake is the single most expensive lesson from the old file.
- **Trail**: arms only once the position's *real* floating profit
  (`POSITION_PROFIT`, which already nets out the spread since a BUY closes
  at bid and a SELL at ask) is positive — not just a favourable price move,
  which can still be a net loss once spread is subtracted. This is the same
  principle you asked for on the old EA's FIXEDEXIT test, built in from day
  one this time.
- **Spread guard**: auto-calibrating from the symbol's own real spread
  (median observed × multiplier), the same mechanism that fixed the old
  EA's zero-trade bug — never a hand-guessed static cap.
- **Daily circuit breaker**: stops opening new trades once today's equity
  drawdown hits `InpDailyLossStopPct` (default 75%), resets on the next
  broker day.
- **Sizing/account handling**: tester-safe cent-account detection — a
  Strategy Tester deposit is never divided just because the symbol name or
  account currency looks like a cent account, the same fix the old EA
  needed.

## What's NOT in this file yet (Phase 2)

The **news-breakout module** — placing a straddle around scheduled
high-impact releases (NFP, FOMC, CPI, Fed speakers) using MT5's built-in
Economic Calendar (`CalendarValueHistory`) — is not built yet. Left out of
this first delivery so the sizing/risk/baseline-entry skeleton can be
tested and trusted on its own before adding it. Say the word once you've
run this and it's behaving sensibly, and Phase 2 gets added on top without
touching what's already here.

## Verification done so far

- Brace/paren/bracket balance checked with the same tokenizer script used
  throughout the old EA's work: `{}` 45/45, `()` 326/326, `[]` 20/20,
  residual 0.
- Every function-call pattern (`trade.Buy`/`trade.Sell`, `iATR`, `iMA`,
  `CopyBuffer`, `CopyRates`, `PositionGetTicket` loop, the `Upper()` helper)
  is copied verbatim from patterns already proven to compile and run live in
  the old EA — nothing here is untested syntax.
- **Not verified**: there is no MQL5 toolchain in this environment, so this
  has never actually been compiled. This is a fresh file with roughly 500
  lines of new logic — please compile with MetaEditor (F7) and send me any
  errors/warnings if it doesn't come back clean on the first try.

## How to test

1. Drop `EzyScalp_XAUUSD_FRESH_V1.mq5` into `MQL5\Experts\Advisors`,
   compile (F7).
2. Run it in the Strategy Tester on XAUUSD or XAUUSD.sc, M5, "Every tick
   based on real ticks."
3. Read the `EzyScalp XAUUSD FRESH V1: INIT` line at attach — confirms
   account profile, base equity/lot, daily risk stop, and trend filter
   state.
4. Watch for `SPREAD AUTO-CALIBRATION COMPLETE` a short way into the run,
   then `ENTRY SENT`/`ENTRY FAILED` lines as signals fire.
5. No `.set` file is needed — every default above is compiled in.
