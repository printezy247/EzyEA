# EzyMap V2.1a — Session Timing & Volatility Regime Confluence

**Base:** `EzyMap_V2_0_ZONE_QUALITY.mq5` · **Output:** `EzyMap_V2_1a_SESSION_VOL.mq5`
Incremental build on V2.0. Adds two **scored** confluence sources that gate **both** entry
paths through one shared aggregator. `#property version` bumped `2.000` → `2.101`.

## ⚠️ Three things to know before testing

**1. There is no shared choke point between the two entry paths.** The brief asked whether
`TradingEnvironmentReady()` or `SpreadAllowed()` could host the gate once. I checked both
with a call-site grep. Neither works, for different reasons:

| Candidate | Reachable from STANDARD? | Reachable from ZERO-CONF? | Verdict |
|---|---|---|---|
| `TradingEnvironmentReady()` | yes (`DeployAggressiveArmSetup`, `DeployPersistentSetup`) | yes (`SubmitDirectZeroConfMarket`) | **Rejected.** Its first statement is `if((bool)MQLInfoInteger(MQL_TESTER)) return true;`. A gate hosted there would be **silently inert in every backtest** — the one place the stage has to be measured. It is also called from the dashboard and the diagnostics block, which are not deployment attempts, so the frequency counters would be garbage. |
| `SpreadAllowed()` | **no** — neither standard deployment function calls it | yes | **Rejected.** Not on the standard path at all. |

So the gate is called **explicitly, three times**, which between them cover both paths
**exactly once each per deployment attempt**. This is a documented finding, not an
oversight. See the *Call sites* table below.

**2. Same lineage caveat as V2.0 and V3.190.** The task brief carried a line reading
"V3.180 P01–P13: tester/live parity fixes. DO NOT UNDO". **They are not in this file and
never were.** This lineage descends from V3.176, not from the separate V3.180
`PARITY_HARDENED` branch — the file's own header has said so since V3.190 (see BASE NOTE,
now extended to say so explicitly). `NowMs()` and `TradeRetcodePartial()` here are V3.190
implementations. Nothing was undone; there was nothing to undo. No P01–P13 code has been
invented to satisfy the brief.

**3. Not compiled.** There is no MQL5 toolchain in this environment. Balance, ordering,
declaration-before-use and call-site arity were verified mechanically (see the table at
the end); **expect MetaEditor errors on the first pass.**

## Cross-cutting design decisions

- **Scored, not ANDed.** Both sources return `0.0–1.0` and are combined into a weighted
  average compared against one threshold. Boolean AND would make frequency loss
  all-or-nothing; a single threshold makes it a dial.
- **A disabled source is excluded from the average, not counted as 0.5.** Counting it
  would drag every aggregate toward the middle and make `InpMinConfluenceScore` mean
  something different depending on which stages happen to be on.
- **One function per source, shared by both paths.** `SessionConfluenceScore()` and
  `VolatilityRegimeScore()` each have exactly **one** call site in the whole file — inside
  `ConfluenceScore()`. The paths share the aggregator, so the hour logic and the ATR logic
  are physically impossible to fork per path.
- **An unmeasurable source never rejects.** A missing ATR handle or cold history scores the
  *normal* value and never sets the extreme flag — same principle as V2.0 S03's unmeasured
  departure score. Otherwise the first N bars of every run and every restart would silently
  stop trading.
- **The hard veto is not folded into the score.** "This tape is untradeable" is a different
  claim from "slightly below the confluence bar", and must not be outvotable by a strong
  session score.
- **This feature touches entries only.** It has no path to stop-loss computation; see the
  verification table.

---

## S01 — Session timing score
**Stage:** `V2.1a S01` · **Inputs:** `InpUseConfluenceScoring`, `InpMinConfluenceScore`,
`InpScoreSession`, `InpLondonOpenHour`, `InpNYOpenHour`, `InpNYCloseHour`,
`InpSessionWeight`, `InpOverlapSessionScore`, `InpSingleSessionScore`,
`InpAsiaSessionScore`, `InpDeadZoneScore`

V2.0 deployed at 03:00 and at 14:00 with identical conviction. Nothing in it measured the
clock, even though gold's London/NY overlap and its post-NY-close liquidity hole are not
the same instrument.

**Boundary logic** (documented in code because hour arithmetic is easy to get subtly wrong).
`londonClose := InpLondonOpenHour + 8`. Tests run in this order, every interval half-open
`[start,end)`, ASIA the total fallback:

```
OVERLAP  h >= NYOpen  AND h < londonClose AND h < NYClose
LONDON   h >= LondonOpen AND h < NYOpen
NY       h >= londonClose AND h < NYClose
DEAD     ((h - NYClose) mod 24) < 2        ← first 2h after the NY close
ASIA     everything else
```

With the default 8/13/21 that yields **OVERLAP 13–15, LONDON 8–12, NY 16–20, DEAD 21–22,
ASIA 23 and 0–7** — no hour lands in two buckets and no hour falls through. The dead-zone
width is the constant `V21A_DEAD_ZONE_HOURS = 2` rather than a fourth input, deliberately:
the operator only has three hours to verify against their broker clock.

**Time source:** `TimeCurrent()` only. In the Strategy Tester that is the modelled server
time, so tester and live classify the same bar identically. `TimeLocal()` would follow the
box running the terminal and `TimeGMT()` would ignore the broker offset — either makes a
backtest un-reproducible elsewhere. Grep confirms **zero** new `TimeLocal`/`TimeGMT` in
code (5 matches, all inside comments explaining why they are not used).

**⚠️ Broker-offset trap.** These three inputs are **broker server hours**. Most European
brokers run GMT+2/+3, which puts the London open at 09:00 or 10:00 server, not 08:00. The
stage is worthless if they are set for the wrong clock, so the detected tag and hour are
logged on **every** deployment attempt on **both** paths, plus once at `OnInit` with an
explicit `VERIFY THIS AGAINST YOUR BROKER'S SERVER CLOCK` warning.

**No second daily reset.** I checked `CheckCampaignDay()` / `ResetCampaignDay()` first, as
instructed. They key on year/month/day from `TimeTradeServer()` — a **broker-day boundary**
concept driving the daily risk lock. The session classifier is an **intraday hour**
classifier and does not touch it. There is only one daily-reset mechanism in the file. A
comment at the `DeployPersistentSetup` gate records this so nobody merges the two later.

**Functions:** new `NormalizeHour24()`, `SessionCodeForHour()`, `SessionCodeText()`,
`EntryPathCodeText()`, `SessionScoreForCode()`, `SessionConfluenceScore()`,
`ConfluenceScore()`, `ConfluenceGateAllows()`, `CaptureConfluenceSnapshot()`,
`LogConfluenceFilterRate()` · `SubmitDirectZeroConfMarket()` ·
`DeployAggressiveArmSetup()` · `DeployPersistentSetup()` · `RegisterSetupAnalytics()` ·
`EnsureReportSetupRow()` · `WriteEzyMapBacktestReport()` · `OnInit`/`OnDeinit`

**Look for:** run STAGE0 and STAGE1 and compare **trade count first, expectancy second**.
Then bucket CSV `SessionScore` against net profit. The falsification test is whether
OVERLAP actually outperforms ASIA *on your broker's clock* — if it doesn't, check the
logged hour before tuning the scores, because a wrong offset produces exactly the same
null result as a wrong premise.

---

## S02 — Volatility regime score
**Stage:** `V2.1a S02` · **Inputs:** `InpScoreVolatilityRegime`, `InpVolATRPeriod`,
`InpVolTimeframe`, `InpVolPercentileLookback`, `InpVolLowPercentile`,
`InpVolHighPercentile`, `InpVolatilityWeight`, `InpVolNormalScore`, `InpVolExtremeScore`,
`InpHardBlockExtremeVol`

V3.190 S03 already *sizes* geometry off ATR, but nothing ever asked whether the regime is
worth trading. A dead tape never reaches the trail arm; a news spike blows through a
structural stop before the zone can work. V2.0 takes both at full conviction.

**Percentile, not an absolute threshold.** An absolute ATR level needs re-tuning per symbol
and per era. The current **closed-bar** ATR is ranked against its own trailing
`InpVolPercentileLookback` closed values (`CopyBuffer` from shift 1 — the forming bar's ATR
moves intrabar and would make the regime depend on *when* in the bar the trigger fired).
Ties contribute a half each, so a flat run of identical ATR ranks at the middle of its own
run rather than at 0 or 100. Below `InpVolLowPercentile` or above `InpVolHighPercentile` →
`InpVolExtremeScore`; between → `InpVolNormalScore`. A transposed low/high pair is swapped
rather than marking everything extreme and silently halting the EA.

**Handle reuse.** When `InpUseATRGeometry` is on **and** `InpVolTimeframe == InpATRTimeframe`
**and** `InpVolATRPeriod == InpATRPeriod`, `g_volATRHandle` is an **alias** of the existing
`g_geometryATRHandle` — no duplicate indicator. `g_volATRShared` records that, and
`OnDeinit` releases the handle only when it is our own, so it is never released twice.
Otherwise a second handle is created in `OnInit` and released in `OnDeinit`, mirroring the
V3.190 S03 pattern exactly.

**Cost.** `RefreshVolatilityATR()` carries the same **per-bar guard** as
`RefreshGeometryATR()` (`iTime(_Symbol,InpVolTimeframe,0) == g_volATRBar → return`), for the
same reason the codebase creates `iATR()`/`iMA()` handles in `OnInit` — *"iATR() per tick is
exactly the kind of cost the tick handler must not carry"*. It is additionally called only
from `VolatilityRegimeScore()`, which only runs at a deployment attempt, so the `CopyBuffer`
happens at most once per bar **and** only on bars where the EA actually tried to deploy. It
is not on the tick path at all.

**`InpHardBlockExtremeVol`** is a distinct veto, evaluated *before* and *separately from*
the weighted threshold, on both paths, and logged with its own reject reason.

**Functions:** new `VolatilityInputsMatchGeometryATR()`, `RefreshVolatilityATR()`,
`VolatilityRegimeScore()` · `ConfluenceScore()` · `ConfluenceGateAllows()` ·
`OnInit`/`OnDeinit`

**Look for:** bucket CSV `VolPercentile` into <20 / 20–90 / >90 and compare expectancy. The
stage is justified only if the **middle bucket beats both tails**. If the >90 bucket wins,
gold's high-volatility tape is where your edge lives and `InpHardBlockExtremeVol` is
actively costing money — turn it off before tuning anything else. Also compare the
STANDARD vs ZERO-CONF pass rates in the `OnDeinit` line: a large divergence means one path
fires predominantly in one regime, which is itself a finding.

---

## Call sites

`SessionConfluenceScore()` and `VolatilityRegimeScore()` each have **exactly one** call
site, inside the shared aggregator. That is stronger than "one per path": both paths reach
the same single call through `ConfluenceScore()`, so the logic cannot fork.

| Symbol | Definition | Call site(s) | Path reached |
|---|---|---|---|
| `SessionConfluenceScore()` | 9292 | **9460** (inside `ConfluenceScore()`) | both, via the aggregator |
| `VolatilityRegimeScore()` | 9392 | **9474** (inside `ConfluenceScore()`) | both, via the aggregator |
| `ConfluenceScore()` | 9441 | 9513 (inside `ConfluenceGateAllows()`) | both |
| `ConfluenceGateAllows()` | 9500 | **3056** `SubmitDirectZeroConfMarket()` | ZERO-CONF |
| | | **13141** `DeployAggressiveArmSetup()` | STANDARD (armed-instant route) |
| | | **13446** `DeployPersistentSetup()` | STANDARD (persistent-touch route) |
| `RefreshVolatilityATR()` | 9330 | 9396 (`VolatilityRegimeScore()`), 15041 (`OnInit` warmup) | — |
| `CaptureConfluenceSnapshot()` | 9567 | 3221 (zero-conf), 10679 (`RegisterSetupAnalytics()`) | both |
| `LogConfluenceFilterRate()` | 9583 | 15609 (`OnDeinit`) | — |

**Why the standard path needs two gate call sites and still evaluates once.**
`DeployAggressiveArmSetup()` is entered *both* directly (line 11380-ish, the READY-armed
instant route) and by delegation from `DeployPersistentSetup()`. The gate therefore lives
inside `DeployAggressiveArmSetup()` so the direct route is covered, and
`DeployPersistentSetup()` only evaluates it on the branch that does **not** delegate —
after `if(InpAggressiveArmExecution) return DeployAggressiveArmSetup(index);`. Exactly one
evaluation per standard deployment attempt; the counters cannot double-count.

A standard-path rejection sets `SetDeploymentFailure(..., temporary=true)`, which keeps the
touch latch alive for a retry. That is correct: a confluence score is a function of the
clock and the ATR, both of which change. A permanent classification would discard the setup
for the rest of the M5.

---

## Frequency instrumentation

Module-level `g_stdAttempts` / `g_stdPassed` / `g_zcAttempts` / `g_zcPassed`, incremented at
the gate, reset in `OnInit`, logged in `OnDeinit`:

```
V2.1a CONFLUENCE FILTER RATE | STANDARD: X% passed (Y/Z) | ZERO-CONF: X% passed (Y/Z)
```

Counters are only touched — and the line is only printed — while `InpUseConfluenceScoring`
is true. With the engine off a `0/0` rate would read as a filter that rejected everything.

## CSV additions

`SessionTag` · `SessionScore` · `VolPercentile` · `VolScore` · `ConfluenceScore` ·
`EntryPath` — appended to the same `SetupAnalytics` → `ReportSetupRow` →
`WriteEzyMapBacktestReport()` chain V2.0 used for `ZoneGrade`/`TouchNumber`/etc.

Two implementation notes:

- **Codes, not strings, in the structs.** Both structs are zeroed with `ZeroMemory()`;
  keeping them free of `string` members keeps that unambiguous. `SessionCodeText()` /
  `EntryPathCodeText()` render at write time.
- **The zero-conf path gets its columns too.** It has no `PersistentReadySetup`, so
  `RegisterSetupAnalytics()` never runs for it — but its order comment *is* `EZR`-tagged
  (V2.0 fixed that), so `RegisterDealAnalytics()` already creates its analytics row and the
  setup already appears in the CSV. `SubmitDirectZeroConfMarket()` therefore calls
  `CaptureConfluenceSnapshot(EnsureAnalytics(directZcId))` after acceptance, filling in only
  the six V2.1a columns and leaving every V2.0 column at the zeroed value those rows already
  reported.

Unscored sources write `n/a`, never `0`, so a legitimately-unscored row can never be read as
a zero score. `EntryPath` is populated even at STAGE0 (the path code is set before the
master-switch early return), which is free extra attribution and affects no trading logic.

## Verification performed

| Check | Result |
|---|---|
| Brace / paren / bracket balance (strings + comments excluded, depth tracked) | ✅ `{}` 926/926 · `()` 6210/6210 · `[]` 1178/1178; depth returns to 0, never negative, no mismatched pairs (V2.0 baseline was 896/5966/1129) |
| New functions forward-declared before first use | ✅ all 13 added to the existing block at ~1712–1723, ahead of the earliest call site (3056) |
| Arity at changed call sites | ✅ **no existing signature was changed**; every new function is additive. Verified `SetDeploymentFailure(string,uint,string,string,bool)` — the one pre-existing function called from new code — matches its 5-arg use |
| Exactly one call site per scoring function | ✅ 1 each, both inside the shared aggregator — see the call-site table. Stronger than one-per-path |
| Both entry paths gated, once each | ✅ ZERO-CONF at 3056; STANDARD at 13141 **or** 13446, mutually exclusive by the `InpAggressiveArmExecution` delegation branch |
| No new `MQL_TESTER` branches | ✅ 11 code occurrences, unchanged from V2.0 (13 raw grep hits — 2 are new comments explaining why the gate is *not* hosted in `TradingEnvironmentReady()`) |
| `GetTickCount64` confined to `NowMs()` | ✅ 1 occurrence, line 2267 |
| No new `TimeLocal()` / `TimeGMT()` | ✅ 5 matches, **all inside comments**; session logic reads `TimeCurrent()` only |
| Session classifier is total and non-overlapping | ✅ all 24 hours enumerated against the implemented predicate order: OVERLAP 13–15, LONDON 8–12, NY 16–20, DEAD 21–22, ASIA 23+0–7. No hour unclassified, none double-classified |
| No order-send path yields `SL = 0.0` | ✅ this feature never touches SL computation — it only returns `false` earlier than V2.0 would. `ResolvedPresetStopPips()`, `BrokerSafeExecutionSL()` and `InpRetryEntryWithoutSLOnReject` are untouched. In `SubmitDirectZeroConfMarket()` the gate sits **above** the SL block; in the standard path it sits above `BrokerSafeExecutionSL()` |
| Indicator handles created once / released once | ✅ `g_volATRHandle` created in `OnInit` only when the engine **and** S02 are on; aliased to `g_geometryATRHandle` when the inputs match (`g_volATRShared`), and `OnDeinit` releases it only when it is not the alias |
| Refresh is per-bar, not per-tick | ✅ `RefreshVolatilityATR()` guards on `iTime(_Symbol,InpVolTimeframe,0)`; reached only from `VolatilityRegimeScore()`, i.e. only at deployment attempts. Nothing added to `OnTick` |
| Defaults reproduce V2.0 | ✅ `InpUseConfluenceScoring=false` → gate returns `true` before touching counters or logging; `ConfluenceScore()` returns neutral 1.0; no ATR handle is created. Only CSV *columns* differ (all `n/a`) |
| Two stages built and checked separately | ✅ S01 written and balance-verified before S02 was started. **Not committed to git** — the brief said not to commit or push, so the two stages are sequential edit passes on one working tree, not two git commits |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |
