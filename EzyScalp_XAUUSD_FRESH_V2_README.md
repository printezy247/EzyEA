# EzyScalp XAUUSD FRESH V2

Built from your uploaded `EzyMap_V3_140_V3_138_BASE_XAUUSD.sc_SL20_TRAIL10.mq5`
— not ported wholesale, but re-implemented as its **essential mechanism**,
on top of the exact same proven risk/sizing/safety scaffold as FRESH V1
(nothing there was criticized, so nothing there changed).

## What's the same as V1

- Flat, proportional sizing: 100 equity = 0.01 lot, floored below and
  scaled linearly above. No confidence tiers, no per-signal multipliers.
- Auto-calibrating spread guard (measures the symbol's own real spread,
  never a hand-guessed cap).
- Tester-safe cent-account handling.
- Daily circuit breaker (default 75%, deliberately loose).
- ATR-relative stop/target, and a trailing stop that only arms once a
  position's **real** floating profit is positive.
- `PERFORMANCE REPORT` at the end of every run (closed trades, win rate,
  lots traded, net profit).

## What's new — the entry signal

V1 was a pure momentum-breakout scalper. V2 replaces that with the core
mean-reversion-at-structure logic from your V3.140 file's H4 SNR → M15 zone
→ M3 reversal → M5 READY lineage, simplified to its essential mechanism:

1. **H1 bias**: EMA(13) vs H1 close — bullish, bearish, or neutral.
2. **Levels**: the nearest H1 *close* below current price (support) and
   the nearest H1 close above it (resistance), scanned over the last 48
   H1 bars — your original file's own approach (proximate recent closes
   acting as levels), not a full swing-pivot reconstruction.
3. **Zone**: a price band around each level, sized from **live M15 ATR**
   (never a fixed pip guess — the zone self-scales with current
   volatility instead of using a static width).
4. **Entry**: an M5 candle that touched the zone, with price having since
   moved back *out* of it in the trade's favour, and that candle's own
   close confirming the same direction — a retest-and-reject pattern.

**Both trend-following and counter-trend retests are valid setups**
(`InpAllowCounterTrend`, default `true`) — this matches your original
file's dual-route design (`trendBuyRoute`/`counterBuyRoute`) and keeps
signal frequency high, consistent with the volume objective from V1 (V1's
trend filter cut roughly half of all candidates and was switched off for
exactly this reason).

## Also fixed — the likely v1.04 regression

You reported v1.04 (which added the order-rate throttle) traded worse than
v1.03. Reviewing it: v1.04 gated **both** new entries and trailing-stop
updates behind the *same* shared throttle timestamp. With up to 15
concurrent positions, each eligible for a trail update on any tick their
profit improved, frequent modify calls could consume that shared budget
and silently block the bar's one entry attempt — a plausible, quiet cause
of lower trade count.

**V2's throttle applies only to new position opens.** Trailing-stop
updates are not rate-limited — they only ever make an existing position's
protection *tighter*, never open new risk, so delaying one to respect a
shared budget isn't a trade-off worth making for the exact problem the
throttle exists to prevent (uncontrolled *new*-position spam, per the
EzyMap V3.184 incident).

## Verification done so far

- Brace/paren/bracket balance: `{}` 62/62, `()` 415/415, `[]` 31/31,
  residual 0.
- Every MQL5 pattern used (`iMA`, `iATR`, `CopyRates`, `CopyBuffer`,
  `trade.Buy`/`Sell`/`PositionModify`, the `PositionGetTicket` loop) is
  copied verbatim from patterns already proven to compile in V1 or the
  legacy EzyMap files.
- **Not verified**: no MQL5 toolchain in this environment. This is a new
  ~600-line entry-logic section on top of V1's proven scaffold — please
  compile (F7) and send me any errors before running it.

## How to test

Same as V1: drop into `MQL5\Experts\Advisors`, compile, run on XAUUSD or
XAUUSD.sc, no `.set` file needed. Compare its `PERFORMANCE REPORT` against
V1.03's on the same test period — different entry philosophy (mean-reversion
at structure vs. pure momentum breakout), so a genuinely different trade
profile is expected, not a bug if the numbers look different in shape.
