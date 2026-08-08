# EzyMap V2.2 BTC — BTCUSD / BTCUSD.sc Portability and Bugfix Pass

**Base:** `EzyMap_V2_1b_TRIGGER_REFINED.mq5` · **Output:** `EzyMap_V2_2_BTCUSD_ADAPTATION.mq5`
Incremental build on V2.1b. `#property version` bumped `2.102` → `2.200`. Five stages, of
which **two are code fixes, one promotes four hardcoded literals to inputs, one changes
printed text, and one is a `.set` file with no code at all.** Four new inputs, one new
function, **zero changed function signatures.**

---

## ⚠️ Five things to know before testing

**1. This is a portability pass, not a strategy change.** Nothing in V2.1a's confluence
gate, V2.1b's trigger ladder, the V3.190 S01 exit-geometry phase machine, or the sizing
choke point was touched. The largest behavioural change on a **gold** chart is that four
numbers that used to be unreachable literals are now reachable inputs — at the same values.

**2. The default polarity is back to normal.** V2.1b was the exception in this lineage: both
of its inputs defaulted to the *new* behaviour, so its `STAGE0_BASELINE.set` was the
all-`true` rollback file. **V2.2 BTC returns to the original rule** — every new input
defaults to reproducing V2.1b exactly. `EzyMap_V2_2_BTCUSD_STAGE0_BASELINE.set` is
byte-identical to the compiled-in defaults and rolls nothing back; it exists so the control
arm is explicit in the tester.

**3. S01 and S02 have no rollback switch, deliberately.** They are unconditional fixes.
Both are provably no-ops on gold *by construction* rather than by configuration, so an input
to disable them would only be an input to re-enable a bug. The proofs are below and are the
main thing to check in review.

**4. `EzyMap_V2_2_BTCUSD_RECOMMENDED.set` is not validated.** There is no MQL5 toolchain and
no BTC price history in the environment that produced it. Not one number in it has been run
against a single bar of data. See **NOT VALIDATED — RETUNE BEFORE LIVE** at the end of this
document, which lists every numeric choice and how to check it.

**5. Not compiled.** Balance, hunk inventory, signature stability and grep counts were
verified mechanically (see the verification table). **Expect MetaEditor errors on the first
pass.**

---

## Why BTC broke: one root cause, three symptoms

`StrategyPipSize()` (new file line 2134) already had a BTC branch:

```
if(IsGold()) return MathMax(0.10,_Point);
if(IsBTC())  return MathMax(1.0,_Point);
```

**One strategy pip is $1 on BTC and $0.10 on gold.** That single line is what makes every
`...Pips` input a *dollar* amount on BTC and a *dime* amount on gold, and it is where all
three of the problems below come from — not from any one broken function.

| Symptom | Where | Class |
|---|---|---|
| Round-number grading test always true | `NearGoldRoundNumber()` | **Real bug** — silent, unconditional |
| Live cent protection parity never engages on `BTCUSD.sc` | `IsLiveXAUUSDscProtectionChart()` | **Real bug** — silent, live-account-only |
| H4/D1/W1/H1 level floors 10× too small in dollar terms | two function bodies | **Not tunable** — hardcoded literals |

A fourth, cosmetic issue — log lines that print `"XAU"` while running on BTC — is S04.

### Things I checked that turned out to be *already correct*

Worth recording so nobody re-investigates them:

- **`IsBTC()`** (line 2128) substring-matches `BTC`/`XBT` on the uppercased symbol, so
  **`BTCUSD` and `BTCUSD.sc` both match with no suffix stripping needed.** Untouched.
- **`ResolveAccountUnitDivisor()`** (line 2058 onward) does its `.SC` / `_SC` / `CENT`
  test **without any gold gate**, so a live `BTCUSD.sc` was *already* correctly detected as
  a cent account for lot sizing. This is exactly what made the S02 bug so easy to miss:
  half the cent handling worked and half silently did not.
- **`g_brnStep` / `g_microStep`** (lines 7705–7712) are already BTC-aware
  (`gold 100/50, BTC 1000/500, else price-relative`) and reasonable. **Untouched.**
  `ConfluenceCount()`'s `NearRound(mid,g_brnStep,tol)` consumes these — it is a completely
  different mechanism from `NearGoldRoundNumber()` and was never broken. Do not confuse the
  two.
- **The `$100 equity → lot` ladder** (`InpStandardSetupLotPer100`, `InpGoodSetupLotPer100`,
  `InpQualitySetupLotPer100`, `InpBaseEquity`, `InpBaseLayerLot`) are plain inputs — a BTC
  `.set` retunes them with no code change. Confirmed at lines 492–502.
- **The V3.190 S03 ATR geometry inputs** are all plain inputs (lines 920–934). Same.
- **`InpUseConfluenceScoring` / `InpScoreSession` / `InpScoreVolatilityRegime`** are plain
  inputs (lines 1141, 1149, 1199). Same.
- **`ProtectionPriceDistance()`** (line 2183) carries a redundant gold floor,
  `if(IsGold()) pipSize=MathMax(0.10,pipSize);`, which duplicates the `StrategyPipSize()`
  gold branch it just called. It is a no-op, not a bug, and it is *not* touched — but it is
  a live tripwire: **if the gold pip size is ever changed, it must be changed in both
  places.** Flagged rather than fixed, because fixing it is a behaviour-neutral edit to a
  function on every order-send path, which is not worth the risk in a portability pass.

---

## S01 — `NearGoldRoundNumber()` made symbol-aware
**Stage:** `V2.2 BTC S1` · **No input** · **New file lines 5225–5277** (declaration 1914,
call site in `ComputeZoneGrade()` 5318)

### What was wrong

V2.0 S04 upgrades a zone one grade (`C→B` or `B→A`) when its proximal edge sits within
`InpRoundNumberTolerancePips` of a `$5` or `$10` level. Those two levels were **hardcoded
constants with no symbol guard at all**:

```
double ten =MathRound(price/10.0)*10.0;   // V2.1b line 5092-ish
double five=MathRound(price/5.0)*5.0;
```

The tolerance is `InpRoundNumberTolerancePips * MathMax(StrategyPipSize(),_Point)`. On BTC
that is `5.0 × $1 = $5`.

**$5 is exactly the maximum possible distance from any price to the nearest multiple of
10.** The first test therefore returned `true` for *every price ever passed in*. So on BTC,
`ComputeZoneGrade()` upgraded **every single zone, unconditionally**, and the upgrade
carried zero information — it was a constant `+1 grade`, which then flowed straight into
`GradeSizeMultiplier()`, `GradeTrailMultiplier()` and `GradePartialTPPips()`.

This is the one change in V2.2 that would have altered live BTC results silently and
materially, and it was invisible in the log.

### What changed

The two checked levels are now scaled per symbol, using the **same ladder the map already
uses** for its big-round-number logic (`g_brnStep`/`g_microStep`, new file lines 7705–7712),
shifted one decade down because this test is about a zone edge resting on a round number,
not about the map's structural magnets:

```
double majorStep=IsGold()?10.0:
                 (IsBTC()?1000.0:MathMax(price*0.01,10.0));

double minorStep=IsGold()?5.0:
                 (IsBTC()?500.0:majorStep*0.5);
```

Everything else in the function — the `price<=0.0` guard, the tolerance expression, the
major-before-minor ordering, the `levelOut` semantics, the return contract — is byte-for-byte
unchanged.

### Proof it is behaviour-preserving for XAUUSD

`IsGold()` is `true` for any symbol containing `XAU` or `GOLD`, so `majorStep` resolves to
the literal `10.0` and `minorStep` to the literal `5.0` — **the exact constants the old code
had written in**. The two `MathRound` expressions then reduce character-for-character to the
originals:

| Old | New, with gold substituted |
|---|---|
| `MathRound(price/10.0)*10.0` | `MathRound(price/10.0)*10.0` |
| `MathRound(price/5.0)*5.0` | `MathRound(price/5.0)*5.0` |

Same arithmetic, same order, same tolerance, same early return. **Verified by inspection;
no floating-point difference is possible because the operands are identical.**

### Bonus: it is also behaviour-preserving for every symbol quoted under ~$1000

The fallback branch is `MathMax(price*0.01,10.0)`. For any price below `1000.0`,
`price*0.01 < 10.0`, so `majorStep` clamps to `10.0` and `minorStep` to `5.0` — again the
old constants. **So EURUSD, GBPUSD, silver, oil and every FX pair keep their previous
behaviour too.** Only instruments priced above ~$1000 — which are precisely the instruments
where the old code was broken — see a different result.

### Deliberate deviation from strict `g_brnStep` symmetry

The brief suggested keeping the fallback branch consistent with `g_brnStep`'s, which is
`MathMax(livePrice*0.01,_Point*100.0)`. **I used a floor of `10.0` instead of `_Point*100.0`,
on purpose.** On a 5-digit FX pair `_Point*100.0` is `0.001`, which would make `majorStep`
for EURUSD `MathMax(0.0108, 0.001) = 0.0108` — a completely different grid, and a
**behaviour change for every FX symbol**, in a stage whose whole premise is that nothing
except BTC changes. The `10.0` floor buys the much stronger safety property in the section
above. The `price*0.01` term and the `majorStep*0.5` minor step are kept identical to
`g_brnStep`/`g_microStep`, so the *shape* of the fallback still matches.

---

## S02 — live cent protection parity gate widened to BTC
**Stage:** `V2.2 BTC S2` · **No input** · **New file line 2164** (one condition)

### What was wrong

```
// V2.1b, line 2030
if((bool)MQLInfoInteger(MQL_TESTER) || !IsGold())
   return false;
```

The `IsGold()` test ran **before** the `.SC` / `_SC` / `CENT` suffix test, so
`IsLiveXAUUSDscProtectionChart()` returned `false` for `BTCUSD.sc` even though the suffix
matched. That silently disabled the whole V3.164 live-cent protection-parity feature —
all six inputs — on a live BTC cent account:

| Input | What was silently inert on `BTCUSD.sc` |
|---|---|
| `InpLiveXAUProtectionParity` | master switch — never engaged |
| `InpLiveXAUDisableHistoricalPeakRebuild` | trail rebuilt its peak from historical M1 immediately on attach |
| `InpLiveXAURequireFullTrailBeforeArm` | (clamps the arm input; unaffected by the gate) |
| `InpLiveXAUIncludeSpreadInTrailArm` | live spread never added to the arm distance |
| `InpLiveXAUTrailWarmupSeconds` | no warmup — trail could arm on the first tick after attach |
| `InpLiveXAUExtraProtectionCushionPoints` | cushion never added |

This is worse on BTC than it would be on gold, because BTC's spread widens far harder, and
arming a trail off a rebuilt historical peak with no spread cushion is exactly the failure
V3.164 was written to stop.

### What changed

```
if((bool)MQLInfoInteger(MQL_TESTER) || !(IsGold() || IsBTC()))
   return false;
```

**The function name and all six input names are deliberately unchanged.** They are
referenced by name at four call sites, in the `.set` files, in the V3.176 log lines and
throughout the header comments. Renaming buys no behaviour and costs a large diff.

### Proof it is behaviour-preserving for XAUUSD.sc

Widening `!A` to `!(A || B)` can only make the guard *less* likely to return early. Formally:
if `IsGold()` was `true` before, `IsGold() || IsBTC()` is still `true`, so **no symbol that
previously reached the suffix test can now be rejected**, and no symbol that previously
returned `true` can now return `false`. The change is purely additive: it adds `BTCUSD`,
`BTCUSD.sc`, `XBTUSD.sc` and similar. `XAUUSD.sc` is untouched. The `MQL_TESTER` short-circuit
is unchanged, so **every backtest on every symbol still returns `false` exactly as before.**

### All four call sites audited

| New file line | Context | Assumes gold beyond the gate? |
|---|---|---|
| 2232 | `LiveTrailActivationDistance()` — adds spread + cushion to the arm distance | **No.** Reads only `tick.ask-tick.bid` and `_Point`. |
| 3874 | `ReconstructTrailPeak()` — suppresses the historical M1 peak rebuild | **No.** Returns `RoundPrice(peak)` from the live tick. |
| 5013 | `ManageHybridTrailingPositions()` — `liveProtectionChart` / warmup gate | **No.** Compares `TimeCurrent()` against `initializedClock`. |
| 15766, 15950 | OnInit log lines | **No** — they only *print* it, and S04 fixes the text. |

No call site contains gold-specific arithmetic, a gold price constant, or a `0.10` pip
assumption. The gate is the only thing that was gold-specific.

---

## S03 — H4 / D1 / W1 / H1 level minimum-distance floors promoted to inputs
**Stage:** `V2.2 BTC S3` · **Inputs:** four, all defaulting to the old literal

### What was wrong

Four numeric literals inside two function bodies, none reachable from a `.set` file:

| V2.1b line | Function | Literal | On gold | On BTC |
|---|---|---|---|---|
| 2641 | `RefreshZeroConfHigherTimeframeLevels()` — H4 | `70.0` | $7 | **$70** |
| 2655 | `RefreshZeroConfHigherTimeframeLevels()` — D1 | `120.0` | $12 | **$120** |
| 2663 | `RefreshZeroConfHigherTimeframeLevels()` — W1 | `200.0` | $20 | **$200** |
| 7573 | `CalculateMapAndMaybeReady()` — H1 | `70.0` | $7 | **$70** |

These are not tolerances. They are the `minimumDistance` argument to
`PickDirectionLevels()` — how far apart two chosen levels must be to count as two levels.
On BTC, $70–$200 is inside a single M5 candle, so **H4, D1 and W1 collapse onto
near-identical levels** and the zero-conf ladder's whole `W1 > D1 > H4` priority ordering
stops meaning anything.

### What changed

| New file line | Input | Default |
|---|---|---|
| 565 | `InpH4LevelMinDistancePips` | `70.0` |
| 566 | `InpD1LevelMinDistancePips` | `120.0` |
| 567 | `InpW1LevelMinDistancePips` | `200.0` |
| 572 | `InpH1LevelMinDistancePips` | `70.0` |

Declared in the zero-conf tolerance input block, immediately after
`InpZeroConfMaxDeployAttempts`, well before both use sites. Substituted at:

| New file line | Site |
|---|---|
| 2776 | H4 `baseDistance` |
| 2791 | D1 |
| 2800 | W1 |
| 7749 | H1 `minimumLevelDistance` |

Each substitution is wrapped as `MathMax(0.0,Inp...)`, matching the codebase's existing
defensive style, so a negative input degrades to `0.0` rather than inverting the `MathMax`.
The outer `MathMax(..., _Point*5.0)` / `MathMax(..., baseDistance)` floors are unchanged, so
**a zero input still cannot produce a zero minimum distance and there is no division by any
of these values anywhere.**

Defaults reproduce the literals exactly, so **XAUUSD behaviour is byte-identical.**

### ⚠️ Deviation from the brief: four inputs, not three

The brief specified three inputs and said to use `InpH4LevelMinDistancePips` at *both*
`70.0` sites, on the premise that the second one was "another copy of the H4 literal."
**It is not.** Line 7573 is inside `CalculateMapAndMaybeReady()` and sets the separation
floor for the **H1 map** (`g_S1`/`g_S2`/`g_R1`/`g_R2`) consumed by the **STANDARD** entry
path — a different timeframe feeding a different consumer from the zero-conf H4 levels. It
coincidentally shared the value `70.0`.

Aliasing it onto an input named `...H4...` would have been a permanent maintenance trap: a
user retuning H4 for the zero-conf ladder would silently move the H1 standard-path map too.
I added `InpH1LevelMinDistancePips` (default `70.0`) instead. **The default preserves
behaviour identically, so this deviation costs nothing and is reversible** — set both to the
same value and you have the brief's version.

---

## S04 — misleading `"XAU"` text in runtime strings
**Stage:** `V2.2 BTC S4` · **New helper:** `InstrumentLabel()` (declaration 1899, definition
2145)

```
string InstrumentLabel()
{
   if(IsGold()) return "XAU";
   if(IsBTC())  return "BTC";
   return _Symbol;
}
```

Used in printed strings only. It is never compared, never a threshold, never a branch
condition that affects trading.

### Complete inventory of every `XAU` / `gold` occurrence and its disposition

Produced by `grep -in "xau"` and `grep -in "gold"` over the whole V2.1b file (41 and 35 hits
respectively). Grouped by what they actually are:

**A. Runtime string literals that made a FALSE claim on a non-gold chart — all four FIXED:**

| V2.1b line | Old text | New file line | New text | Gold output |
|---|---|---|---|---|
| 15407 | `"V3.176 REAL XAUUSD.sc ACCOUNT PROFILE"` | 15685 | `"V3.176 REAL "+_Symbol+" ACCOUNT PROFILE"` | **byte-identical** on a real `XAUUSD.sc` chart |
| 15441 | `"V3.176 XAU PROTECTION SCALE"` | 15722 | `"V3.176 "+InstrumentLabel()+" PROTECTION SCALE"` | **byte-identical** (`InstrumentLabel()`→`"XAU"`) |
| 15476 | `"V3.176 LIVE XAUUSD.sc PROTECTION PARITY"` | 15763 | `"V3.176 LIVE "+_Symbol+" PROTECTION PARITY"` | **byte-identical** on a real `XAUUSD.sc` chart |
| 15478 | `" \| live XAUUSD.sc chart="` | 15765 | `" \| live cent-suffix chart="` | **changed text** — see note |
| 15670 | `" \| XAU pip size="` | 15959 | `" \| "+InstrumentLabel()+" pip size="` | **byte-identical** |

`_Symbol` is used rather than `InstrumentLabel()` on the two lines that are specifically
*about the broker symbol including its suffix*, which is what makes them byte-identical on
gold. **The one line whose gold text genuinely changes is `live XAUUSD.sc chart=` →
`live cent-suffix chart=`**, and it changes because after S02 the flag can be true on a BTC
chart, so the old wording would be a false statement in the exact log line an operator uses
to confirm the feature engaged. Anyone grepping logs for the old string needs to know.

**B. Comments — all LEFT ALONE (historical record, per the brief).** V2.1b lines 16, 21,
327, 330, 554, 559, 733, 744, 1170, 1173, 2083, and the header block. Also line 6827, which
is a comment *showing an example* of the dashboard line — the dashboard itself already
builds from `_Symbol` (`string compact=_Symbol+" • "+...`, new file line 7002) and needed no
change.

**C. Identifiers — all LEFT ALONE:**

| Identifier | Why untouched |
|---|---|
| `IsGold()` | correct name for what it does |
| `InpLiveXAU*` (six inputs) | referenced by name across the file, in `.set` files and in logs; renaming is pure diff noise |
| `IsLiveXAUUSDscProtectionChart()` | same; four call sites plus a forward declaration |
| `NearGoldRoundNumber()` | same; declaration + one call site. A `// V2.2 BTC S1` note above it records that the name is now legacy |
| `DrawActualTradeLevelsGold()` | **read in full and confirmed already symbol-generic** — it filters on `_Symbol` and `InpMagicNumber` and reads nothing instrument-specific. The `Gold` is the **drawing colour**, not the instrument. Six call sites. A comment at new file line 6811 records this so nobody re-investigates |
| `InpTradeLevelGold` | a **display colour** `C'255,215,0'`, unrelated to the symbol. Users may reference it in existing configs. **Completely untouched**, per the brief |

**D. `"GOLD"` inside `IsGold()`'s own `StringFind`** — that is the detector, not a claim.
Untouched.

### Also observed but deliberately NOT changed — stale hardcoded numbers in log text

Found while doing S04. These are **pre-existing and out of scope** (they contain no
`XAU`/`gold` substring), but they are wrong *today, on gold*, so they are recorded here
rather than left to be rediscovered:

| New file line | Text | Problem |
|---|---|---|
| 15746 | `" \| expected SL=2.30"` / `" \| expected trail=0.90"` | `InpPresetStopLossPips` is `21.0` and the gold pip is `0.10`, so the expected values are **2.10 and 0.70**. The literals are stale from an earlier default |
| 15722, 15763 | `"SL21="`, `"trail7="` | labels hardcode the pip counts; misleading once ATR geometry or a `.set` changes them |
| 15948 | `"a preset 21-pip SL"` | same |
| 15949 | `"7-PIP TRAIL: enabled="` | same |
| 15961 | `"FIXED 21-PIP LIVE-PARITY SL"` | same |

Fixing these means editing log lines that a gold operator greps for, for zero behavioural
gain, in a stage that is supposed to be narrowly scoped. **Left as-is on purpose.**

### New log lines added (S01–S04 announcement block)
**New file lines 15446–15540**, in `OnInit()`, immediately after the V2.1b announcement
block. Log-only; wrapped in its own `{ }` scope so its locals cannot collide with the rest
of `OnInit`.

Five lines, printed unconditionally on every symbol (the last only on BTC):

- `V2.2 BTC INSTRUMENT PROFILE` — symbol, label, `IsGold`/`IsBTC`, strategy pip, `_Point`,
  digits, **contract size, tick value, min lot, lot step**
- `V2.2 BTC SPREAD CHECK` — **observed spread in points and in price**, next to
  `InpMaxSpreadPoints` and `InpDeviationPoints`
- `V2.2 BTC S1 ROUND-NUMBER GRADING LADDER` — the resolved major/minor steps and tolerance
- `V2.2 BTC S2 LIVE CENT PROTECTION PARITY GATE` — whether the widened gate resolved true
- `V2.2 BTC S3 LEVEL MIN-DISTANCE FLOORS` — all four, in pips *and* in price
- `V2.2 BTC CALIBRATION WARNING` — BTC charts only

This follows V2.1a S01's precedent that **a stage which cannot be verified from the log is
not really verifiable**. There is no V2.2 master switch to report; what has to be visible is
*which symbol branch resolved*, because that is exactly what silently differed before.

---

## Stage 5 — the ATR-geometry supersession trace

The brief asked which flat pip inputs are overridden at runtime when
`InpUseATRGeometry=true`, so that retuning them for BTC is moot, versus which stay live.
**Traced through the actual code path, not guessed.**

### The path

`FreezeTrailGeometry()` (new file line 4081) seeds seven locals from inputs, then calls
`ResolveATRGeometryPips()` (line 3950), which returns immediately with no effect if
`CurrentGeometryATR()` is `0.0` — i.e. if `InpUseATRGeometry` is false *or* the cached ATR
is not yet populated. That early return is what makes S03 behaviour-identical when off.

When it does run:

```
double atrPips = atr / MathMax(StrategyPipSize(),_Point);
double atrInitial = MathMax(MathMax(0.1,InpATRTrailFloorPips),
                            atrPips*MathMax(0.01,InpATRTrailMultiplier));
double ratio = atrInitial / MathMax(0.1, initPips);      // initPips = InpTrailInitialDistancePips

presetPips    = Clamp(atrPips*InpATRStopMultiplier, floorPips, ceilingPips);
armPips       = atrPips * InpATRArmMultiplier;
tightPips     = MathMax(InpATRTrailFloorPips, tightPips*ratio);
tightenAtPips = tightenAtPips * ratio;
initPips      = atrInitial;
```

### The answer

| Input | With ATR geometry ON | Needs BTC retuning? |
|---|---|---|
| `InpPresetStopLossPips` | **Fully superseded** — overwritten by `atrPips × InpATRStopMultiplier`, clamped | Only as the **no-ATR fallback** (first bars after attach, failed `CopyBuffer`). Still set it |
| `InpTrailArmPips` | **Fully superseded** — overwritten by `atrPips × InpATRArmMultiplier` | Fallback only |
| `InpTrailInitialDistancePips` | **Value fully superseded** — overwritten by `atrInitial` — **but it is also the `shapeReference` denominator of `ratio`**, so it still controls how `tightPips` and `tightenAtPips` are scaled. **Not inert.** | **Yes** — indirectly, via `ratio` |
| `InpTrailTightDistancePips` | **Partially live** — multiplied by `ratio`, floored at `InpATRTrailFloorPips`. Its *ratio* to `InpTrailInitialDistancePips` is what survives | Yes |
| `InpTrailTightenAtPips` | **Partially live** — multiplied by `ratio` (the `999.0` sentinel stays unreachable, which is the documented intent) | Yes |
| `InpATRStopFloorPips` / `CeilingPips` / `InpATRTrailFloorPips` | **These ARE the ATR geometry** — the only pip-denominated inputs in S03 | **Yes — the primary BTC retune** |
| `InpBreakevenLockAtPips` / `InpBreakevenLockOffsetPips` | **Never touched by `ResolveATRGeometryPips()`** — they are read in `FreezeTrailGeometry()` *after* the call and only scaled by the separate V2.0 S05 distal `stopRatio` | **Yes — fully live** |
| `InpTrailingActivationPips` | **Never touched.** Read in `LiveTrailActivationDistance()` as `MathMax(activation, armDistance)` — a **floor on the arm distance that outranks the ATR-derived arm** | **Yes — fully live, and easy to miss** |
| `InpTrailingDistancePips` | **Never touched — and effectively DEAD.** Its only non-log consumer is `FixedTrailCandidateSL()` (line 3842), which **has no callers** in this lineage. It appears in four log lines and nowhere else | No (set for log consistency only) |
| `InpPartialTPPips`, `InpGradeA/B/CPartialTPPips` | **Never touched** — resolved in `GradePartialTPPips()`, a separate path | **Yes — fully live** |
| `InpDistalStopBufferPips` / `MinPips` / `MaxPips` | **Never touched** — and `ResolveDistalStopPips()` **outranks ATR entirely** in `ResolvedPresetStopPips()`: a valid distal stop is returned *before* ATR is consulted | Yes, when `InpUseZoneDistalStops` is on |
| `InpZeroConfTouchTolerancePips`, `InpZeroConfClusterTolerancePips`, `InpConfluenceTolerancePips`, `InpEntryTouchTolerancePips`, `InpZoneIdentityTolerancePips`, `InpRoundNumberTolerancePips`, `InpSnrFrontRunPips`, `InpM1ZoneTolerancePips`, `InpLiveLimitGeometryExtensionPips`, `InpTouchStallMaxExtendPips` | **Never touched** — different subsystem entirely | **Yes — all fully live** |
| `InpScalpStopPips` / `InpIntradayStopPips` / `InpSwingStopPips` | **Never touched.** They do **not** set the submitted SL — that comes from `ResolvedPresetStopPips()`. They feed the READY snapshot's `volatilityStopDistance` (line 8225), the RR fallback (line 8572) and `PersistentFallbackSL()` (line 11725) | **Yes — fully live** |
| `InpH4/D1/W1/H1LevelMinDistancePips` | **Never touched** — map construction, upstream of geometry | **Yes** |

**Headline:** turning ATR geometry on supersedes **three** inputs' values and partially
rescales **two**. Every other pip input in the EA — including breakeven lock, partial TP,
the trailing-activation floor, all the tolerances and all three mode stops — **remains fully
live and must be retuned for BTC independently.** ATR geometry is not a blanket solution to
BTC's scale problem; it solves the *stop and trail* part of it and nothing else.

---

## Verification table

No MQL5 toolchain in this environment. Everything below is mechanical.

| Check | Result |
|---|---|
| Brace balance (comments and string literals stripped) | `929` / `929` — was `927`/`927`; **+2 = new `InstrumentLabel()` body and the scoped log block in `OnInit`** |
| Paren balance | `6308` / `6308` — was `6219`/`6219` |
| Bracket balance | `1178` / `1178` — **unchanged** |
| New functions forward-declared before first use | `InstrumentLabel()` declared line **1899**, defined **2145**, first *use* **15465** ✓ |
| Changed function signatures | **zero** — S01/S02 are body edits, S03 substitutes expressions, S04 edits string concatenation |
| New inputs declared before use | four inputs at **565–572**; earliest use **2776** ✓ |
| `grep -c MQL_TESTER` | `13` → `13` — **unchanged** |
| `grep -n GetTickCount64` | one hit, line **2518**, inside `NowMs()` — **still the only call site** |
| Order-send path can produce `SL=0.0`? | **No.** `ResolvedPresetStopPips()` always returns ≥`0.1` (distal path is floored at `InpDistalStopMinPips`≥0.1; ATR path is `Clamp`ed to `floorPips=MathMax(0.1,...)`; fallback is `MathMax(0.1,InpPresetStopLossPips)`). `ProtectionPriceDistance()` returns ≥ one tick. `BrokerSafeExecutionSL()` reassigns to `marketPrice ∓ minDist` whenever `safeSL<=0`. **No V2.2 edit touches any of these four functions.** |
| New S03 inputs can cause division by zero? | **No** — none of the four is ever a divisor; each is only a `MathMax` operand |
| S01 can cause division by zero? | **No** — `majorStep ≥ 10.0` and `minorStep ≥ 5.0` on every branch |
| `.set` convention: load-on-top, only the stage's own inputs | `STAGE0_BASELINE` lists exactly the four S03 inputs ✓. `RECOMMENDED` is a **symbol profile**, not a stage file, so it necessarily spans inputs from several stages — stated in its header, grouped by section, with `§11` listing what is deliberately excluded |
| Every input name in both `.set` files exists in the `.mq5` | verified by script against `^input ...` declarations — **zero mismatches** |
| Comment tag convention `// V2.2 BTC Sx:` | 19 occurrences |
| Log tag convention `Log("V2.2 BTC ...")` | 6 occurrences |
| Header block style matches prior stages | `V2.2 BTC STAGE SUMMARY (S01-S05)` at line **226**, same box-drawing and column width |
| `#property version` | `"2.102"` → `"2.200"` at line **312** |
| File size | 16,073 → 16,363 lines |

---

## ⚠️ NOT VALIDATED — RETUNE BEFORE LIVE

**Everything in this section applies only to `EzyMap_V2_2_BTCUSD_RECOMMENDED.set`.** The
code changes (S01–S04) are structural and reviewable by inspection. The `.set` numbers are
not: **there is no MQL5 toolchain and no BTC price history in this environment, so not one
of them has been tested against a single bar of data.** This ships as a structurally sound
starting point, not as a tuned strategy.

### The single assumption everything rests on

Every BTC number is gold's value **× 10**, justified as: gold M5 ATR(14) ≈ 8–15 strategy
pips; BTC M5 ATR(14) ≈ 50–150 strategy pips, because the BTC pip is $1 and the gold pip is
$0.10. **If your broker's BTC M5 ATR is 30 pips rather than 100, every distance in the file
is roughly 3× too wide.** BTC's volatility regime moves by a factor of 3–5 over a year in a
way gold's does not, so this needs rechecking periodically, not once.

### Per-number checklist

| Input(s) | Value | How to check it |
|---|---|---|
| `InpATRStopFloorPips` `120` / `InpATRStopCeilingPips` `350` / `InpATRTrailFloorPips` `50` | ×10 | Read the actual M5 ATR from `RefreshGeometryATR()`'s cached value. With ATR≈100 the resolved stop is 160, well inside the clamp. **If the floor or ceiling is doing the work on most trades, they are wrong** — the clamp should be a guard rail, not the operative value |
| `InpATRStopMultiplier` `1.60` / `InpATRTrailMultiplier` `0.55` / `InpATRArmMultiplier` `0.35` | **unchanged from gold** | These are dimensionless ratios relative to ATR, so they should transfer. **Least likely of all Stage-5 numbers to be wrong**, but still untested on BTC |
| `InpMaxSpreadPoints` `1200` / `InpDeviationPoints` `200` | **pure placeholder** | **The weakest numbers in the file.** BTC is variously quoted with 1, 2 or 3 digits, so "one point" may be $1, $0.01 or $0.001 and the same integer means wildly different things. Attach the EA, read `V2.2 BTC SPREAD CHECK` for several minutes and across a session boundary, then set the cap to ~2–3× the calm reading |
| `InpStandardSetupLotPer100` `0.005` / `Good` `0.010` / `Quality` `0.015` | gold ÷ 2 | **Not the obvious reasoning.** A typical BTCUSD contract is 1 BTC (~$100k/lot) versus gold's 100 oz (~$330k/lot), so BTC notional is *smaller*, and with the ×10 stop the risk per 0.01 lot works out at ~$2.10 for both. The halving is for **margin**, not risk — crypto leverage is often 1:5–1:20 against gold's 1:100–1:500. **Verify your broker's actual contract size and margin rate.** Downside is capped regardless by the broker-native `OrderCalcProfit`/`OrderCalcMargin` caps; the symptom of getting this wrong is the EA constantly pinned to the minimum lot, which collapses the whole grade/confidence size ladder into one flat size. Watch for `STANDARD RISK GUARD CAP` and `LIVE CENT MINIMUM-LOT CANDIDATE` in the log |
| `InpH4/D1/W1/H1LevelMinDistancePips` `700/1200/2000/700` | ×10 | **The group I am least confident about**, because the right answer depends on BTC's swing structure rather than its ATR, and it interacts with V2.1b S02's outer-level-only rule. Too wide → almost no W1/D1 zero-conf triggers. Too narrow → W1/D1/H4 keep resolving to the same price |
| `InpRoundNumberTolerancePips` `50` | ×10 | Preserves the *fraction of prices that qualify*: gold ±$0.50 in a $5 grid = 20%; BTC ±$50 in a $500 grid = 20%. Only consumed when `InpUseZoneGrading=true`, which is **off** by default and not enabled by the file |
| All tolerance inputs (§4 of the `.set`) | ×10 | Fully live regardless of ATR geometry — see the supersession table |
| `InpScalpStopPips` `200` / `Intraday` `350` / `Swing` `700` and the six target inputs | ×10 | Do **not** set the submitted SL; they drive RR planning and `PersistentFallbackSL()` |
| `InpBreakevenLockAtPips` `90` / `Offset` `10`, `InpPartialTPPips` `110`, `InpGradeA/B/C` `160/110/70` | ×10 | **Never superseded by ATR geometry.** These are the ones most likely to be forgotten |
| `InpDistalStop*` `30/100/300` | ×10 | Inert unless `InpUseZoneDistalStops` is turned on; set so enabling it later is not a trap |
| `InpScoreSession=false` | **judgment call** | Not a finding. BTC has real hour-of-day structure (CME open, US cash session, futures settlement) — the claim is only that *gold's* session map is the wrong map, and its DEAD bucket would penalise perfectly ordinary crypto hours. The correct follow-up is to **re-tune the same mechanism** against BTC's own hourly distribution (all eight session inputs are exposed, no code change needed), not to conclude it does not apply |
| `InpScoreVolatilityRegime=true` | transfers unchanged | Percentile-ranks ATR against the instrument's **own** trailing distribution, so it is fully self-relative. Arguably worth more on BTC than on gold |
| `InpMagicNumber=2475222` | hygiene | Journal readability only. Every position and order loop already double-filters on `_Symbol` **and** `InpMagicNumber`, so gold and BTC would not interfere even at the same magic |

### Suggested order of work

1. Attach on BTCUSD **with the default binary** (not the `RECOMMENDED.set`) and read the
   `V2.2 BTC INSTRUMENT PROFILE` and `V2.2 BTC SPREAD CHECK` lines. Record the real pip size,
   digits, contract size, min lot and spread.
2. Fix `InpMaxSpreadPoints` and `InpDeviationPoints` from that reading before anything else.
3. Get the real M5 ATR figure, then rescale §1 and §2 of the `.set` from it rather than from
   the ×10 assumption.
4. Only then load the rest of `RECOMMENDED.set`, and A/B the strategy switches
   (`InpUseZoneGrading`, `InpUseZoneDistalStops`, the V2.1b ladder inputs) on BTC **one at a
   time**, using the existing per-stage `.set` files — exactly as they were A/B'd on gold.

### And on XAUUSD

Run `EzyMap_V2_2_BTCUSD_STAGE0_BASELINE.set` against a V2.1b binary on gold. The two should
be indistinguishable. **If they are not, the regression is in S03's four substitutions or in
S01's gold branch** — those are the only two places a gold-visible difference could come
from, and both are argued above to be arithmetically identical.

---

# S06 — sizing floor + deployment-gate instrumentation (diagnostic pass)

**Added after S01–S05.** `#property version` bumped `2.200` → `2.201` (line **364**). File
16,363 → **16,572 lines**. One new input, eleven new counter globals, one new function,
fifteen counter increments at existing call sites, **zero changed function signatures**,
28 diff hunks.

The identical patch is applied to `EzyMap_V2_1b_TRIGGER_REFINED.mq5` as **V2.1b S03** — the
added code is byte-identical apart from the stage tag in comments and log strings. See
`V2_1b_CHANGES.md`.

### ⚠️ This stage breaks the V2.2 "four inputs, all default to base" rule

`InpForceMinimumBaseSizing` is a **fifth** V2.2 input and it is the one that **defaults to
`true`**, i.e. to the new behaviour, at explicit request. That is the V2.1b polarity, not
the V2.2 polarity. `EzyMap_V2_2_BTCUSD_STAGE0_BASELINE.set` now pins it `false` so the
control arm remains a true V2.1b reproduction. Point 2 of *Five things to know* above is
still correct for S01–S05 and is now wrong for S06; this paragraph is the correction.

---

## The problem this stage exists to solve

Three BTCUSD.sc Strategy Tester runs, at deposits of **100, 1000 and 3000**, all ended:

```
READY=511, stored=54, deployed=0, LIVE=0
```

511 signals reached READY, 54 became stored persistent setups, **and not one of the 54 ever
reached the broker.** The working hypothesis was that lot sizing collapsed at or below 100
equity.

---

## Finding 1 — the sizing formula was NOT undersizing at 100/1000/3000

Verified by direct reading, not by test. The arithmetic:

**Step 1 — `LotSizingCapitalUnits()`** (pre-S06, lines 2096–2106 of the old file):

```
double raw = InpUseBalanceForLotSizing ? ACCOUNT_BALANCE : ACCOUNT_EQUITY;   // default: BALANCE
if(InpUseBrokerNativeDepositUnitsForLots) return MathMax(0.0, raw);          // default: true
return MathMax(0.0, raw / MathMax(1.0, g_accountUnitDivisor));
```

With `InpUseBrokerNativeDepositUnitsForLots=true` (the default, line 510) it returns the
**raw** balance. **No cent-currency division happens in that branch at all**, so a 100 USC
balance and a 100 USD balance both resolve to a numeric `sizingCapital` of exactly `100`.

The other branch reaches the same answer in the tester anyway:
`InpAccountScaleMode=EZY_ACCOUNT_AUTO` (line 466) and `InpTesterAutoModeIsStandard=true`
(line 470) make `ResolveAccountUnitDivisor()` return `1.0` under `MQL_TESTER` before any
`.sc` suffix test runs, so `raw/1.0 = raw`. **Both branches give 100.**

**Step 2 — the scale factor.** `AutoBaseLayerLot()` and `ConfidenceSetupLot()` both compute:

```
scale = sizingCapital / MathMax(1.0, InpBaseEquity)     // InpBaseEquity = 100.0
```

| Deposit | `sizingCapital` | `scale` |
|---|---|---|
| 100 | 100 | **1.0** |
| 1000 | 1000 | **10.0** |
| 3000 | 3000 | **30.0** |

**Step 3 — the target.** `targetLot = lotPer100 * scale`. At a deposit of 100 the scale is
exactly `1.0`, so **the target is exactly `lotPer100`** — the configured per-100 rate, not
some fraction of it. At 1000 and 3000 it scales up tenfold and thirtyfold.

**Conclusion: all three tested deposits sat at or above the point where the pre-S06 formula
already behaved exactly as requested.** A "sizing collapses below 100" bug cannot explain
zero deployments at 100, and certainly not at 1000 or 3000. The blocker was upstream of
sizing.

---

## Finding 2 — but the RECOMMENDED lot ladder *does* zero out at a 100 deposit

Separate from the formula, and **real**. This is a genuine bug in
`EzyMap_V2_2_BTCUSD_RECOMMENDED.set`, found while proving Finding 1, and it fully explains
the **100-deposit run on its own**.

`RECOMMENDED.set` halves the gold ladder for BTC margin headroom:
`InpStandardSetupLotPer100=0.005`. Following that number through `ConfidenceSetupLot()`:

| Deposit | `targetLot` = `0.005 × scale` | `NormalizeVolumeDown()` with min 0.01 / step 0.01 | Result |
|---|---|---|---|
| **100** | `0.005 × 1` = **0.005** | `if(vol < minVol) return 0.0;` → **0.0** | ❌ **zero volume** |
| 1000 | `0.005 × 10` = 0.05 | 0.05 | ✅ |
| 3000 | `0.005 × 30` = 0.15 | 0.15 | ✅ |

At 100 the target is below the broker minimum, so `normalized` is `0.0`, and the
`liveCentCandidate` rescue does not fire because it requires `IsLiveCentAccount()`, which is
`!MQLInfoInteger(MQL_TESTER) && divisor>1` — **false in the Strategy Tester by definition**.
`ConfidenceSetupLot()` logs `REAL CENT SIZE BLOCK` and returns `0.0`. Downstream,
`CapSetupVolumeForCentSafety(…, requested=0.0)` returns `0.0` immediately and the deployment
fails on `volume < minVolume`.

Two things sharpen this:

- **It hits the direct zero-conf path unconditionally.** `SubmitDirectZeroConfMarket()`
  calls `ConfidenceSetupLot(0)`, and confidence 0 is always the STANDARD tier.
- **GOOD and QUALITY survive.** `0.010 × 1` = 0.010 clears the minimum exactly, and
  `0.015 × 1` floors down to 0.010. Only STANDARD dies. So at a 100 deposit the EA loses the
  entire zero-conf path plus every sub-3-confluence setup, silently.

**`InpForceMinimumBaseSizing` does not fix this**, and it is worth being explicit about that
because it is exactly the case the floor was requested for. The floor raises the sizing
**capital** to `InpBaseEquity`; at a 100-unit deposit the capital already *was* 100. The
shortfall is in the per-100 lot **rate**, not in the capital. The fix is to un-halve the
ladder (or use a deposit of at least 200 units), which is what
`EzyMap_V2_2_BTCUSD_DIAGNOSTIC_FIRSTPASS.set` does and what the new note in section 9 of
`RECOMMENDED.set` says.

This does **not** explain the 1000 and 3000 runs.

---

## Finding 3 — the two candidates that can zero out all three runs

Both found by direct reading, neither previously instrumented, neither confirmed by a test.

### Candidate A — `InpMaxSpreadPoints`, the strongest suspect

`SpreadAllowed()` (lines 9509–9519 of the old file) is:

```
if(InpMaxSpreadPoints<=0) return true;
...
spread = (tick.ask - tick.bid) / _Point;
return (spread <= InpMaxSpreadPoints);
```

`RECOMMENDED.set` ships `InpMaxSpreadPoints=1200`, and **that file's own section 7 already
flags it** as an unverified placeholder widened 10× from gold, because "the broker's point
convention for BTCUSD is unknown at authoring time."

The failure mode is arithmetic, not strategic. On a BTCUSD symbol quoted with **2 digits**,
`_Point` is `0.01`, so an entirely ordinary **$30** spread is **3000 points** — two and a
half times the cap, on **every tick, forever**. That is a total, permanent, deposit-independent
block, which is exactly the shape of the observed result: identical zero at three different
balances. **This is the single most likely cause.**

It is called from three sites (now lines **3470**, **11966**, **15211**), covering the
zero-conf, persistent and legacy paths — so it gates everything.

### Candidate B — `InpHardBlockExtremeVol`, a real drag, probably not a total block

`ConfluenceGateAllows()` hard-vetoes before the soft score is consulted:

```
if(InpScoreVolatilityRegime && InpHardBlockExtremeVol && g_volRegimeExtreme)   // ~line 9879
```

`g_volRegimeExtreme` is set in `VolatilityRegimeScore()` as
`percentile < InpVolLowPercentile || percentile > InpVolHighPercentile`, with
`RECOMMENDED.set` at `20` / `90`.

**The honest version of this concern, which is narrower than it first appears:** the test is
a percentile **rank** of the current ATR against the same 500-bar trailing window it is
drawn from. By construction that marks roughly **30% of bars extreme even in a perfectly
calm market** — the tails of a rank distribution are always populated. As a *hard veto* that
is a permanent ~30% frequency tax that no price action can avoid, which is a real design
problem. On a single strongly-trending day the window (500 M5 bars ≈ 42 hours) is
non-stationary and trending the same way, so readings cluster in the tails for long
stretches and the rate goes well above 30%.

**But ~30–60% is not 100%.** Unlike the spread gate, this cannot on its own produce 0 of 54
unless the ATR sat persistently in one tail for the entire run. It is best read as a
plausible **compounding** factor, and — more importantly — as something that was firing
completely invisibly, because the hard block returns before any counter is touched.

One thing it cannot be: `RefreshVolatilityATR()` returns early when fewer than 20 bars are
usable, leaving `g_volATRPercentile` at `-1.0`, and `VolatilityRegimeScore()` then scores
**NORMAL** and never sets the extreme flag. A cold start does not manufacture rejections.

### Why the instrumentation matters more than either guess

Neither gate had any counter. Guessing at better numbers without knowing which gate fired
produces a fourth zero-trade run carrying no more information than the first three. **That
is why the instrumentation, not the retuning, is the primary deliverable of S06.**

---

## S06(a) — `InpForceMinimumBaseSizing`

New input at line **577**, immediately after `InpBaseLayerLot`. `LotSizingCapitalUnits()`
(lines **2181–2198**) refactored from two bare returns into a local `capital` that both
branches assign, floored identically before return:

```
   double capital=InpUseBrokerNativeDepositUnitsForLots
                  ? MathMax(0.0,raw)
                  : MathMax(0.0,raw/MathMax(1.0,g_accountUnitDivisor));

   if(InpForceMinimumBaseSizing)
      capital=MathMax(capital,MathMax(1.0,InpBaseEquity));

   return capital;
```

Given Findings 1 and 2, this input's practical effect is **narrower than the request
implied**: it only changes anything below `InpBaseEquity` deposit units, and none of the
three failing runs was in that range. It is shipped because it was asked for, it is correct,
and it removes a real edge case — not because it fixes the reported symptom.

### Proof it cannot weaken a real risk cap

Verified by grep rather than assumed. **`LotSizingCapitalUnits()` has exactly four call
sites** (declaration 2105, definition 2181), unchanged in count by this edit:

| Line | Call site | What it does with the value | Risk-bearing? |
|---|---|---|---|
| **9240** | `AutoBaseLayerLot()` | `rawLot = InpBaseLayerLot * (sizingCapital/baseEquity)` — nominal base-layer target | no |
| **12356** | `ConfidenceSetupLot()` | `targetLot = lotPer100 * (sizingCapital/baseEquity)` — nominal confidence target | no |
| **15814** | `OnInit`, `BROKER-NATIVE LOT SIZING` log line | printed; feeds a display-only `standardRawTarget` | no |
| **16382** | `OnTimer`, `LIVE PARITY STATUS` log line | printed as `lot targets S/G/Q=` | no |

**All four are nominal-lot-target calculations or log lines. None is a `$`-risk or
margin-percentage calculation.** Further:

- `CapSetupVolumeForCentSafety()` and `CapVolumeForStandardRiskGuard()` — the two real caps —
  **appear nowhere in that list**. `CapVolumeForStandardRiskGuard()` reads
  `AccountInfoDouble(ACCOUNT_EQUITY)` and `OrderCalcProfit` directly (lines 9179–9181 area);
  the cent path uses `OrderCalcProfit`/`OrderCalcMargin` against the real symbol. Both still
  have final authority over every submitted volume.
- The `effectiveEquity < MinimumTradingEquity()` refusal at the top of **both** sizing
  functions tests `EffectiveAccountEquity()`, **not** the floored value — an under-funded
  account is still refused before the floor is consulted.

A maintenance note naming all four call sites lives in the input's comment block (lines
**547–576**) so this audit does not need redoing from scratch.

---

## S06(b) — deployment-gate breakdown instrumentation

Eleven counters at lines **2620–2630**, beneath the existing V2.1a counters, reset in
`OnInit` at **15583–15593**:

```
g_spreadRejectStd    g_spreadRejectZc    g_spreadRejectOther
g_envRejectStd       g_envRejectZc
g_capacityRejectStd  g_capacityRejectZc  g_capacityRejectOther
g_orderSendStd       g_orderSendZc       g_orderSendOther
```

`STANDARD` / `ZERO-CONF` are the same two scored paths the confluence line uses, so the two
summaries read side by side. `OTHER` is the legacy bridge-signal path
(`ArmReadySignal()` → `PlaceOneLayer()`), which belongs to neither scored path and so is not
forced into an artificial split. `TradingEnvironmentReady()` is never called from that path,
hence no `OTHER` column on the environment field.

**No gate function was modified.** `SpreadAllowed()`, `TradingEnvironmentReady()`,
`DailyRiskCapacityAvailable()` and `LotSizingCapitalUnits()` keep their exact signatures and
bodies. Increments sit at the **call sites**, on the false branch only, beside whatever
logging and `return` already existed:

| Line | Enclosing function | Gate | Counter |
|---|---|---|---|
| **3463** | `SubmitDirectZeroConfMarket()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectZc` |
| **3470** | `SubmitDirectZeroConfMarket()` | `SpreadAllowed()` | `g_spreadRejectZc` |
| **3520** | `SubmitDirectZeroConfMarket()` | `TradingEnvironmentReady()` | `g_envRejectZc` |
| **3579** | `SubmitDirectZeroConfMarket()` | *(order send)* | `g_orderSendZc` |
| **3682** | `ProcessDirectZeroConfluenceTriggers()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectZc` |
| **11966** | `PlacePersistentLayer()` | `SpreadAllowed()` | `g_spreadRejectStd` |
| **12000** | `PlacePersistentLayer()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectStd` |
| **12083** | `PlacePersistentLayer()` | *(order send)* | `g_orderSendStd` |
| **12993** | `PersistentQualityPass()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectStd` |
| **13679** | `DeployAggressiveArmSetup()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectStd` |
| **13715** | `DeployAggressiveArmSetup()` | `TradingEnvironmentReady()` | `g_envRejectStd` |
| **13984** | `DeployPersistentSetup()` | `TradingEnvironmentReady()` | `g_envRejectStd` |
| **14922** | `PlaceOneLayer()` *(legacy)* | `DailyRiskCapacityAvailable()` | `g_capacityRejectOther` |
| **14942** | `PlaceOneLayer()` *(legacy)* | *(order send)* | `g_orderSendOther` |
| **15211** | `ArmReadySignal()` *(legacy)* | `SpreadAllowed()` | `g_spreadRejectOther` |

Braces were added around two previously brace-less single-statement returns (**3682**,
**14922**); that is the whole `{}` +2 delta outside the new function and changes no behaviour.

**Order-send counting.** No pre-existing global counted send attempts — `g_directZeroConf.attempts`
is a per-setup struct field, not a run total — so a new counter was added rather than
duplicating something existing. It increments **once** per submission, immediately before the
first `trade.Buy`/`trade.Sell`, so the "retry without SL on reject" second send is
deliberately not double-counted: the number means *deployments that reached the broker*.

New function `LogDeploymentGateBreakdown()` at lines **10083–10118**, immediately after
`LogConfluenceFilterRate()`, forward-declared at **2038** beside it, called from `OnDeinit`
at **16293** directly after the `LogConfluenceFilterRate()` call:

```
V2.2 BTC S06 DEPLOYMENT GATE BREAKDOWN | SPREAD REJECTED: n | ENVIRONMENT REJECTED: n | DAILY CAPACITY REJECTED: n | ORDER-SEND ATTEMPTS: n
V2.2 BTC S06 DEPLOYMENT GATE BREAKDOWN BY PATH | SPREAD std/zc/other: n/n/n | ENVIRONMENT std/zc: n/n | DAILY CAPACITY std/zc/other: n/n/n | ORDER-SEND std/zc/other: n/n/n
```

**Deviation:** the brief specified one line. The per-path split went on a second line rather
than widening the mandated line's fields, so the mandated string stays greppable verbatim.

**Deliberately not gated by any input**, unlike `LogConfluenceFilterRate()`. The reasoning
inverts here: a breakdown of all zeros is the *most* informative outcome, because it proves
nothing ever reached these gates and the blocker is upstream. Suppressing that would hide
exactly the case this was built for.

Note `TradingEnvironmentReady()` returns `true` immediately under `MQL_TESTER`, so
`ENVIRONMENT REJECTED` is **always 0 in a backtest** by design. It is in the line for live
runs. A non-zero value there in a tester run would itself be a bug report.

---

## `.set` file changes

### `EzyMap_V2_2_BTCUSD_STAGE0_BASELINE.set`

`InpForceMinimumBaseSizing=false` added, with a note that this file now pins **five** inputs
and that this fifth one is the polarity exception. At ≥100 deposit units the two arms are
arithmetically identical, so seeing no difference is expected.

### `EzyMap_V2_2_BTCUSD_RECOMMENDED.set`

| Change | Section | Detail |
|---|---|---|
| `InpForceMinimumBaseSizing=true` **added** | 9 (sizing) | The compiled default, listed explicitly. Carries the Finding-1 arithmetic and, importantly, the **Finding-2 warning** that the halved ladder produces zero volume for the STANDARD tier at exactly 100 units |
| `InpHardBlockExtremeVol` **`true` → `false`** | 10 (confluence) | See below |

**Why the hard block was turned off.** Because a single trending test day with a trailing
percentile window can classify a large fraction of bars as extreme, hard-vetoing nearly
every deployment **with no visibility into how often it fired**. Soft-score first: an
extreme reading still scores `InpVolExtremeScore=0.15`, still drags the aggregate down, and
with session scoring off it still fails `InpMinConfluenceScore=0.45` — so this is **not** a
permissiveness change, it is a **visibility** change. The same bars are still rejected; they
are now rejected *through* `ConfluenceGateAllows()`, where they get counted and show up in
the `V2.1a CONFLUENCE FILTER RATE` line, instead of being vetoed silently before the score
is consulted. Re-enable once you have seen real percentile behaviour in your own log. If you
want the soft gate to genuinely *admit* extreme bars while measuring, `InpMinConfluenceScore`
has to come below `0.15` too — the hard block is not the only thing rejecting them.

**This is a judgment call made from static reading, not from a test run.**

### New: `EzyMap_V2_2_BTCUSD_DIAGNOSTIC_FIRSTPASS.set`

A deliberately over-permissive **measuring instrument, not a trading profile**, whose only
purpose is to produce one run in which nothing should be able to zero out the trade count.
It is `RECOMMENDED.set` reproduced in full with four marked changes:

| # | Change | Why |
|---|---|---|
| 1 | `InpMaxSpreadPoints=0` | Disables the spread gate via `SpreadAllowed()`'s existing, documented `if(InpMaxSpreadPoints<=0) return true;` no-op path — **confirmed by reading the function**, not assumed. Removes Candidate A |
| 2 | `InpUseConfluenceScoring=false` | `ConfluenceGateAllows()` returns `true` before touching its counters and before the hard block is consulted, so this one switch neutralises the **entire** V2.1a gate — session, volatility, `InpMinConfluenceScore` and `InpHardBlockExtremeVol` together. Removes Candidate B. The remaining V2.1a inputs are left at RECOMMENDED values so step 3 restores that profile exactly |
| 3 | Lot ladder un-halved to `0.01/0.02/0.03` | Removes Finding 2, so a 100-unit deposit can actually produce a non-zero STANDARD lot |
| 4 | `InpConfidenceLotRiskGuardPct=25.0` | `CapVolumeForStandardRiskGuard()` blocks outright when even the minimum lot exceeds the cap (`STANDARD RISK GUARD BLOCK`). RECOMMENDED does not set this input, so it runs at the compiled 5.0%. Widened so it cannot be the thing that zeroes the run. **This is the one change that genuinely increases risk — remove it before any real test** |

**Deviation from the brief:** changes 3 and 4 were not specified; the brief said "sizing as
in RECOMMENDED". They were added because sizing as in RECOMMENDED is precisely what zeroes
the 100-unit case (Finding 2), which would defeat the profile's entire purpose. Both are
marked in the file and both are called out as things to revert.

**Expected absence in this run:** the `V2.1a CONFLUENCE FILTER RATE` line will **not**
appear, because `LogConfluenceFilterRate()` returns early when `InpUseConfluenceScoring` is
false — by design since V2.1a S01, so a 0/0 rate cannot imply a filter that never ran had
rejected everything. That is correct behaviour, not a missing log; the line becomes readable
at step 3. The file says so, and offers the alternative
(`InpUseConfluenceScoring=true` + `InpMinConfluenceScore=0.0`) if you want the gate counted
and passing in the first pass instead.

---

## Retest procedure

1. **Run `EzyMap_V2_2_BTCUSD_DIAGNOSTIC_FIRSTPASS.set`** over the same period as the
   zero-trade runs, at a deposit of at least 100.
   **If this still produces zero trades, stop tuning.** With the spread gate disabled, the
   confluence engine off and a ladder that clears the broker minimum at 100 units, no input
   in this EA can be responsible. The cause is environmental — no M5 history downloaded for
   BTCUSD.sc in the tester (by far the most common), symbol not selected in Market Watch,
   algo trading disabled, tester date range outside the available data, or an unexpected
   `SYMBOL_VOLUME_MIN`/`SYMBOL_VOLUME_STEP` (both printed by the OnInit
   `BROKER-NATIVE LOT SIZING` line). **Report that back rather than tuning blind.**
2. **Read the two new lines** from that run:
   `V2.2 BTC S06 DEPLOYMENT GATE BREAKDOWN` and `… BY PATH`. Check `ORDER-SEND ATTEMPTS`
   first. Expect `SPREAD REJECTED: 0` (gate disabled) and `ENVIRONMENT REJECTED: 0` (always
   0 in the tester). `V2.1a CONFLUENCE FILTER RATE` will be absent — see above.
3. **Re-enable `InpMaxSpreadPoints` alone**, at a *real observed value*. Read it off the
   OnInit line the EA already ships:
   `V2.2 BTC SPREAD CHECK | observed spread=… points (… price) | …`
   Watch it for a few minutes and across a session boundary, then set roughly 2–3× the calm
   reading. Re-run. If the trade count collapses again and `SPREAD REJECTED` is large, the
   spread gate was the original blocker and the observed reading was still too tight.
4. **Re-enable `InpUseConfluenceScoring=true` alone** (spread still at the value from step
   3), leaving `InpHardBlockExtremeVol=false`. Re-run and read `V2.1a CONFLUENCE FILTER RATE`
   — it now reports the pass rate of the soft gate, split by path.
5. **Re-enable `InpHardBlockExtremeVol=true` last.** Re-run and compare the confluence pass
   rate against step 4. The difference is the hard block's exact contribution — the number
   that was unmeasurable before S06. If it costs more than the ~30% the percentile bands
   imply structurally, widen `InpVolLowPercentile`/`InpVolHighPercentile` or leave the hard
   block off and rely on the soft score.
6. **Restore `InpConfidenceLotRiskGuardPct` to 5.0** and decide the lot ladder from the
   observed margin usage before treating any result as real.

Change one thing per run and re-read the same two lines each time. That is the whole point
of the instrumentation.

---

## S06 verification performed

| Check | Result |
|---|---|
| Brace / paren / bracket balance (tokenizer excluding strings, char literals, line and block comments) | ✅ `{}` 932/932 · `()` 6345/6345 · `[]` 1178/1178; residual stack 0, no mismatched pairs |
| Balance delta accounted for | ✅ `{}` **+3** = new function body (1) + braces round the two brace-less returns at 3682 and 14922 (2). `()` **+37** = two `Log(` calls and their 15 `IntegerToString((int)…)` pairs (32) + definition, forward declaration and `OnDeinit` call (3) + net +2 from the `LotSizingCapitalUnits()` rewrite. `[]` **+0**. **Identical deltas in both files** |
| No existing function signature changed | ✅ machine-diffed the set of top-level signature lines old vs new: the **only** difference in either direction is the addition of `void LogDeploymentGateBreakdown()` and its forward declaration. `SpreadAllowed()`, `TradingEnvironmentReady()`, `DailyRiskCapacityAvailable()` and `LotSizingCapitalUnits()` unchanged in arity and return type |
| `LotSizingCapitalUnits()` call sites re-counted after the edit | ✅ still exactly 4, at 9240 / 12356 / 15814 / 16382. All audited in the table above |
| No risk or margin cap consumes `LotSizingCapitalUnits()` | ✅ `CapSetupVolumeForCentSafety()` and `CapVolumeForStandardRiskGuard()` appear at no line in the call-site list; both read `ACCOUNT_EQUITY` / `OrderCalcProfit` / `OrderCalcMargin` directly |
| No new `MQL_TESTER` branches | ✅ 13 raw grep hits, **unchanged** (pre-S06: 13, post-S06: 13) |
| `GetTickCount64` still confined to `NowMs()` | ✅ 1 occurrence |
| New identifiers do not collide | ✅ none of the eleven counter names, nor `InpForceMinimumBaseSizing`, nor `LogDeploymentGateBreakdown`, existed anywhere pre-S06 |
| Declared before first use | ✅ input at 577, first use 2194; counters at 2620–2630, first use 3463; forward declaration at 2038, first call 16293 |
| New function declared consistently with file convention | ✅ forward declaration immediately beside `LogConfluenceFilterRate();`, definition immediately after that function's body, `OnDeinit` call immediately after that function's call |
| MQL5 string handling | ✅ no reliance on implicit adjacent string-literal concatenation; every join uses explicit `+` |
| Diff hunk count matches intent | ✅ 28 hunks (27 + the `STAGE SUMMARY (S01-S05)` → `(S01-S06)` title line), no unintended edit |
| Every `.set` input name matches a real declaration | ✅ script-checked, not eyeballed. `STAGE0_BASELINE` 5 entries, `RECOMMENDED` 72, `DIAGNOSTIC_FIRSTPASS` 73 — every `Inp…` name resolves to an `input` declaration in the `.mq5`; no missing names, no duplicates, no unparsed lines |
| Patch identical to the V2.1b S03 patch | ✅ added lines from both diffs extracted and compared with the stage tag normalised: **byte-identical apart from the tag string, the header block and the version number** |
| Header block style matches prior stages | ✅ `V2.2 BTC STAGE SUMMARY (S01-S06)` at line 226, S06 block at 305–356, same box-drawing and 72-column width |
| Not committed to git | ✅ files written only |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |
| **`InpHardBlockExtremeVol=false` validated by a test run** | ❌ **no — judgment call from static reading** |
| **`DIAGNOSTIC_FIRSTPASS.set` validated by a test run** | ❌ **no — judgment call from static reading** |

---

## ⚠️ What is still unknown after S06

**Nothing in this stage has been run.** There is still no MQL5 toolchain and no BTC price
history in this environment, so:

- The claim that the spread gate is the most likely blocker is **reasoned, not observed.**
- Turning `InpHardBlockExtremeVol` off is a **judgment call**, not a finding.
- `DIAGNOSTIC_FIRSTPASS.set` is a **hypothesis about what to disable**, not a validated
  profile.

Findings 1 and 2 are the exceptions — those are arithmetic derived from the source and hold
regardless of any test. Everything else needs the run described in *Retest procedure*.
**Please run `DIAGNOSTIC_FIRSTPASS.set` and report back what the `DEPLOYMENT GATE BREAKDOWN`
line actually says.** That single line will settle in one run what three previous runs could
not.

---

## S07 — Auto-calibrating spread cap

**A fourth run, on a real cent-account BTCUSD.sc chart, also produced zero trades.** At
that point re-guessing `InpMaxSpreadPoints` a fifth time stops being a reasonable strategy —
every static number offered so far (compiled default 120, `RECOMMENDED.set`'s 1200) has
turned out to be a guess about a broker point convention that cannot be known from this
environment. S07 removes the guess entirely.

### What changed

`SpreadAllowed()` gained an auto-calibration mode, opt-in via `InpAutoCalibrateSpreadCap`
(default **TRUE** in this file — a deliberate polarity exception, same precedent as S06's
`InpForceMinimumBaseSizing`, because three static guesses have now failed):

- **While calibrating** (the first `InpSpreadCalibrationTicks` real ticks after attach,
  default 100): the filter is **inactive** — every tick passes regardless of its spread.
  Each observed spread is recorded into a fixed-size buffer sized once in `OnInit`.
  A slow or incomplete calibration must never itself reproduce the zero-trade bug, so this
  branch fails **open**, not closed.
- **Once calibrated**: the enforced cap becomes `median(observed) *
  InpSpreadCalibrationMultiplier` (default multiplier 3.0), clamped down to
  `InpMaxSpreadPoints` as an optional safety ceiling when that input is `> 0`. Logged once,
  verbatim, as `V2.2 BTC SPREAD AUTO-CALIBRATION COMPLETE`.
- **When `InpAutoCalibrateSpreadCap` is false**: `SpreadAllowed()` is byte-identical to the
  pre-S07 function — same two lines, same `InpMaxSpreadPoints<=0` no-op path. This is the
  branch the XAUUSD lineage (`EzyMap_V2_1b_TRIGGER_REFINED.mq5`) uses by default; the same
  feature was ported there as S04, with the input defaulting **false** since gold's static
  cap has a working track record and this stage's whole premise (three failed guesses) does
  not apply to it.

An `OnInit` line (`V2.2 BTC SPREAD GUARD MODE`) states which branch is active and, if
calibrating, the sample count and multiplier — printed unconditionally so a run that never
reaches calibration completion (because it ends before 100 ticks arrive, unlikely but
possible on a very short backtest window) is still distinguishable from one where
calibration silently never started.

### Why median, not mean, and why a multiplier

A mean is dragged by the rare huge print (a news-driven spread blowout during the
calibration window would inflate every subsequent comparison); a median describes the
*typical* tick. The multiplier (default 3x) is the actual safety margin — it is what turns
"the typical spread right now" into "a cap wide enough to survive ordinary widening without
being wide enough to let every wild print through."

### Functions/inputs touched

New: `MedianOfSpreadSamples()`, inputs `InpAutoCalibrateSpreadCap`,
`InpSpreadCalibrationTicks`, `InpSpreadCalibrationMultiplier`, globals
`g_spreadCalSamples[]`, `g_spreadCalCount`, `g_spreadCalEffectiveCap`. Changed:
`SpreadAllowed()` body only (signature unchanged — still `bool SpreadAllowed()`, still called
identically from all three existing call sites, which needed **no edits at all** since the
function's external contract didn't change). `OnInit()` gained the array sizing, the state
reset, and the mode-announcement log line.

### `.set` file changes

- `RECOMMENDED.set` section 7 rewritten: `InpAutoCalibrateSpreadCap=true`,
  `InpSpreadCalibrationTicks=100`, `InpSpreadCalibrationMultiplier=3.0`,
  `InpMaxSpreadPoints=5000` (now a generous safety **ceiling**, not the enforced value).
- `STAGE0_BASELINE.set` gained `InpAutoCalibrateSpreadCap=false`, so the control arm still
  enforces the plain static cap exactly as V2.1b/gold always have.
- `DIAGNOSTIC_FIRSTPASS.set` now explicitly sets `InpAutoCalibrateSpreadCap=false` alongside
  its existing `InpMaxSpreadPoints=0` — for THIS profile the goal is to prove the EA can
  deploy with the spread gate fully out of the picture, not to exercise the new calibration
  logic, so it deliberately stays on the old, unambiguous "completely disabled" path.

### What to look for

Read `V2.2 BTC SPREAD GUARD MODE` at attach, then `V2.2 BTC SPREAD AUTO-CALIBRATION
COMPLETE` a few dozen ticks later. **The median it reports is now the number to
sanity-check** — if it looks absurd (e.g. thousands of points on a first read), that is a
broker/`_Digits` question to resolve with your broker, not something this EA can infer.
Compare the `DEPLOYMENT GATE BREAKDOWN` spread-reject count on a run with calibration ON
against the same run with it OFF at the old static value — the difference between those two
counts is the actual size of the bug this stage fixes.

### Verification

| Check | Result |
|---|---|
| Brace / paren / bracket balance | ✅ V2.2: `{}` 936/936 · `()` 6384/6384 · `[]` 1187/1187, residual 0. V2.1b: `{}` 934/934 · `()` 6295/6295 · `[]` 1187/1187, residual 0 |
| `SpreadAllowed()` signature unchanged | ✅ still `bool SpreadAllowed()`, zero call-site edits needed in either file |
| `MedianOfSpreadSamples()` declared before first use | ✅ defined well above `SpreadAllowed()` in both files (no separate forward declaration needed — MQL5 only requires the definition to precede use, and it does) |
| No new `MQL_TESTER` branches | ✅ unchanged in both files |
| `GetTickCount64` still confined to `NowMs()` | ✅ unchanged in both files |
| Does not touch stop-loss computation | ✅ this stage only gates whether an attempt proceeds, never the stop distance |
| V2.1b default preserves exact prior behaviour | ✅ `InpAutoCalibrateSpreadCap=false` by default → `SpreadAllowed()` takes the byte-identical legacy branch |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |
| **Calibration behavior validated by a real run** | ❌ **no — this is a mechanism, not a tuned number; the median/multiplier it lands on has not been observed against real BTCUSD.sc ticks** |

**This is a mechanism fix, not a guaranteed fix.** It removes the need to guess the spread
cap by hand, but it cannot conjure a trade out of a market/history problem (e.g. no tester
history downloaded for BTCUSD.sc, algo trading disabled, wrong symbol selected). If a run
with `InpAutoCalibrateSpreadCap=true` still shows `DEPLOYMENT GATE BREAKDOWN` at all zeros —
including zero order-send attempts — the spread gate was never the issue and the next place
to look is outside this EA's inputs entirely.

---

## S07 correction — the ceiling was quietly re-imposing the bug it was built to fix

**The very next test run proved the mechanism above.** It confirmed calibration is running
(`current spread exceeds calibrated cap=120.0` replaced the old static-cap message) and
produced 5 deployments instead of 0. But `120.0` is exactly `InpMaxSpreadPoints`'s compiled
default — not a coincidence. `SpreadAllowed()` clamped the calibrated cap
(`median * multiplier`) down to `InpMaxSpreadPoints` as a "safety ceiling," and a run with no
`.set` loaded still has `InpMaxSpreadPoints=120`. The calibration measured the real spread
correctly, multiplied it by 3, and the ceiling threw that measurement away and substituted
the exact static number the whole feature exists to replace.

A broker reference for BTCUSD CFDs (Vantage Markets) states typical spread runs
**~$15-17 per unit**, which on a 2-digit-quoted symbol is on the order of **1500-1700
points** — roughly 12-14x the ceiling that was silently capping it. That is consistent with
`SPREAD REJECTED` barely moving between the two runs (229027 → 224599) despite calibration
being active: almost every real tick's spread still exceeded the clamped-down 120.

### Fix

`InpMaxSpreadPoints` and the calibration ceiling are no longer the same input.
`InpSpreadCalibrationCeilingPoints` (default `0` = uncapped) is now the only thing that can
clamp `median * multiplier`. `InpMaxSpreadPoints` keeps its original meaning — the enforced
value — but only in the static (`InpAutoCalibrateSpreadCap=false`) branch, which never
touches the new input at all.

`RECOMMENDED.set` was rewritten to set `InpSpreadCalibrationCeilingPoints=0` (trust the
calibration) and leave `InpMaxSpreadPoints` at its plain compiled default (now inert while
calibration is on, so its value no longer matters).

### On "what is BTCUSD.sc's usual spread"

The Vantage Markets reference (~$15-17, ~1500-1700 points) is a general figure for their
BTCUSD CFD product — useful for sanity-checking, but not this exact tester feed. The
authoritative number is whatever the EA's own `V2.2 BTC SPREAD AUTO-CALIBRATION COMPLETE`
log line reports as `median observed=`, measured from the same broker/symbol/tick data the
backtest actually runs on. That line has not yet been read from a run with the ceiling fix
in place — the next test should report it.

### Verification

| Check | Result |
|---|---|
| Brace / paren / bracket balance | ✅ `{}` 937/937 · `()` 6400/6400 · `[]` 1187/1187, residual 0 |
| `InpMaxSpreadPoints` untouched in the static branch | ✅ still the only input read there; ceiling clamp in the calibration branch now reads `InpSpreadCalibrationCeilingPoints` exclusively |
| New input declared before first use | ✅ input at line ~817, first use in `SpreadAllowed()` at ~9763, well after |
| Every `.set` input name resolves to a real declaration | ✅ script-checked: `RECOMMENDED` 76, `STAGE0_BASELINE` 6, `DIAGNOSTIC_FIRSTPASS` 74 entries, zero missing |
| `STAGE0_BASELINE.set` / `DIAGNOSTIC_FIRSTPASS.set` need no new pin | ✅ both already set `InpAutoCalibrateSpreadCap=false`, so the calibration branch (and its ceiling) never executes in either control arm |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |
| **Fix validated by a real run** | ❌ **no — the ceiling-decoupling is reasoned from the exact number (`120.0`) observed in the user's own journal, not yet re-tested** |

---

## S08 — ATR-adaptive stop/trail geometry turned on by default

**The ceiling fix worked.** The next test run confirmed it: `SPREAD REJECTED` went from
229,027 to **0**, and the run went from 0 deployments to `deployed=312, LIVE=305,
completed=305`. The deployment-gate bug across S06/S07 is fully resolved — the EA now
places and manages real trades on `BTCUSD.sc`.

That same run surfaced the next problem: `TOTAL SETUPS: 528 | wins=56 | losses=403 |
flat=69` — a **~12% win rate**. The user confirmed this run used the plain compiled
defaults, no `.set` loaded (they don't write code and asked to receive a ready-to-run `.mq5`
going forward rather than instructions to hand-edit `.set` files — every fix from here on
should be a compiled-default change, not a `.set`-only one).

At compiled defaults, `InpUseATRGeometry=false`, so every stop was a flat
`InpPresetStopLossPips=21` "strategy pips." `StrategyPipSize()` returns `$1` for BTC — the
file's own long-standing comment only ever worked this out for gold ("on XAU, one strategy
pip is 0.10 price"), so a BTC "21-pip stop" is a flat **$21** stop on a symbol trading around
$65,000 with $10-40 of noise on a single M5 candle (visible directly in the user's own
chart screenshot). A stop that tight relative to ordinary noise, not a wrong directional
signal, is the most likely single explanation for a win rate this low.

### Fix

No new code was needed — V3.190 already built ATR-adaptive geometry (`InpUseATRGeometry`,
`ResolveATRGeometryPips()`) for the analogous gold problem (Asia-session ATR a third of New
York's). Two compiled-default changes in this file only (V3.190/V2.1b keep the gold-proven
fixed-pip defaults untouched):

- `InpUseATRGeometry`: `false` → **`true`**.
- `InpATRStopCeilingPips`: `35.0` → **`500.0`**.

The ceiling change matters as much as turning the switch on. `ResolveATRGeometryPips()`
computes `Clamp(atrPips * InpATRStopMultiplier, floor, ceiling)` — a gold-sized ceiling of 35
left in place would have silently clamped the ATR-derived BTC stop straight back down to
"too tight," the identical bug shape S07 already found and fixed once for the spread cap.
500 is deliberately generous (a BTC M5 ATR would need to exceed roughly $312 before it ever
binds) so it acts as a safety backstop against a runaway ATR reading, not an everyday clamp.
`InpATRStopFloorPips` (12.0) is left unchanged — BTC's ATR is expected to sit well above it,
so it was never the operative constraint.

`RECOMMENDED.set`'s existing section 1 already reasoned through this exact scaling problem
independently (pip = $1 on BTC vs $0.10 on gold, "multiply gold's flat pip counts by 10") and
sets its own more specific `InpATRStopCeilingPips=350`; that number stands when the `.set` is
loaded (`.set` values override compiled defaults) and is not disturbed by this stage — a
short cross-reference comment was added there instead so the two numbers don't look like an
unexplained conflict later.

### `.set` file changes

`STAGE0_BASELINE.set` gained the S08 polarity-exception pin (`InpUseATRGeometry=false`,
`InpATRStopCeilingPips=35.0`), same pattern as S06/S07, so the control arm still reproduces
plain fixed-pip gold/V2.1b behaviour exactly.

### Verification

| Check | Result |
|---|---|
| Brace / paren / bracket balance | ✅ `{}` 937/937 · `()` 6400/6400 · `[]` 1187/1187, residual 0 (comment + default-value only change, no structural edit) |
| No function signature or control-flow changed | ✅ only two `input` default values changed; `ResolveATRGeometryPips()`, `RefreshGeometryATR()`, `CurrentGeometryATR()` untouched |
| `STAGE0_BASELINE.set` reproduces pre-S08 behaviour | ✅ pins both changed defaults back to their old values |
| Every `.set` input name resolves to a real declaration | ✅ script-checked: `RECOMMENDED` 76, `STAGE0_BASELINE` 8, `DIAGNOSTIC_FIRSTPASS` 74 entries, zero missing |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |
| **Fix validated by a real run** | ❌ **no — reasoned from the file's own documented pip-to-dollar conversion and the observed noise scale in the user's chart, not yet re-tested** |

**Next test:** re-pull, recompile with no `.set` needed, and re-run. Read the `V2.2 BTC
SPREAD AUTO-CALIBRATION COMPLETE` line for the real measured spread (still open from S07),
and this time also check the win/loss split and net profit — if the win rate is still very
low with ATR-adaptive stops active, the geometry scale was not the (whole) story and the
next place to look is the entry/direction signal logic itself.

---

## S09 — the zero-confluence fallback stopped meaning zero confluences

**S08 did not move the win rate.** A second real test run, on a different day, came back at
~14.4% (53/315/65) — essentially the same as S07's 12.2% (56/403/69) despite stops now being
ATR-adaptive instead of a flat $21. The user's own equity-curve screenshot settled the
question: a smooth, steady grind downward with no drawdown spikes at all — many small
losses, not occasional big ones. That is a trade-*selectivity* signature, not a stop-width
one, so S08's fix (real, and kept) was not the whole story.

Reading `ResolveMarketReadySignal()` found a second, independent bug in the same family as
S07/S08 — a fixed value that made sense for gold's trading cadence but not BTC's. A
documented "V3.094 exception" drops the required confluence count to **zero** whenever the
EA has 0 or 1 open positions on the symbol, meant as a rare low-exposure fallback. A setup
admitted this way also has its touch-quality recheck and position-count recheck explicitly
**bypassed** at deployment time (`V3104_FORCE_ZERO_CONF_MARKET_EXECUTION`, logged as
`ZERO-CONFLUENCE FORCE PASS ... recheck=BYPASSED`). On gold this presumably fires rarely.
On BTC, the same test run that exposed the win-rate problem completed **301 trades in 24
hours** — about one every 5 minutes — so exposure sits at 0-1 almost continuously. The "rare
exception" is plausibly the *dominant* entry path on BTC: most trades getting no real
quality bar at all, which is consistent with a strategy that has some real edge but pays it
away in noise trades with none.

### Fix

The user was explicit that the fix should be "more confluences," not changes to the
exit/profit-locking logic (S08 stands untouched). `InpZeroConfFallbackMinConfluences`
(default `2`, matching the existing trend-following bar) replaces the hardcoded `0` that
low-exposure setups were assigned. This is sufficient on its own: `zeroConfluenceFallback=
(requiredConfluences==0)` downstream is what actually triggers the FORCE-PASS bypass at
deployment, so once the assigned value is non-zero, those setups fall through to the
**normal** deployment path (touch-quality recheck and position-count recheck both apply)
instead of skipping it.

**What did NOT change:** `buyCandidate`/`sellCandidate` — the test for whether a setup arms
at all — reads `(buyNormalConfluence || buyZeroConfluenceFallback)`, and
`buyZeroConfluenceFallback`'s own definition (exposure ≤ 1 and confluence count below the
normal bar) is untouched. So exactly the same set of setups can still arm while the EA is
flat or near-flat; the only change is that most of them now have to clear the standard
quality gate on the way to a real order, instead of being force-passed through it.

### `.set` file changes

`STAGE0_BASELINE.set` gained the S09 polarity-exception pin
(`InpZeroConfFallbackMinConfluences=0`), same pattern as S06-S08, reproducing the exact
pre-S09 "any touch while flat" behaviour that has existed since V3.094/V3.102.

### Verification

| Check | Result |
|---|---|
| Brace / paren / bracket balance | ✅ `{}` 937/937 · `()` 6402/6402 · `[]` 1187/1187, residual 0 |
| Admission test (`buyCandidate`/`sellCandidate`) unchanged | ✅ still reads `buyNormalConfluence \|\| buyZeroConfluenceFallback`; neither operand touched |
| Only the two `effectiveRequired` assignments changed | ✅ `buyEffectiveRequired`/`sellEffectiveRequired` now read the new input instead of a literal `0`; no other call site edited |
| New input declared before first use | ✅ input at line ~661, first use at ~8432, well after |
| Every `.set` input name resolves to a real declaration | ✅ script-checked: `RECOMMENDED` 76, `STAGE0_BASELINE` 9, `DIAGNOSTIC_FIRSTPASS` 74 entries, zero missing |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |
| **Fix validated by a real run** | ❌ **no — reasoned from the file's own documented "V3.094 exception" and the observed 301-trades/24h turnover rate, not yet re-tested** |

**Next test:** the user is running this build live today on a $1000 (USC) real chart rather
than the Strategy Tester. Watch for a lower trade count than the ~300-450/day seen in S07/S08
tester runs (most low-exposure setups should now be filtered by the normal quality gate
instead of force-passed) and check whether the win rate improves. If trade count drops but
win rate is still poor, the remaining problem is in the entry/direction signal quality
itself, not in how permissively it gets applied.
