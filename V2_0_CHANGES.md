# EzyMap V2.0 — Zone Quality Engine & Routing Chain Rebuild

**Base:** `EzyMap_V3_190_REFINED.mq5` · **Output:** `EzyMap_V2_0_ZONE_QUALITY.mq5`
Incremental build on validated V3.190 code. The version number marks the routing-chain
change, not a rewrite.

## ⚠️ Two things to know before testing

**1. The M3 leg in the spec is dead code.** `M3ReversalConfirmation()` and
`SelectM5ReadyZone()` are *defined but never called* — I verified with a call-site grep.
The chain that actually runs is:

```
H1 levels  →  M15 high-risk zones  →  M5 rejection/CHOCH  →  CMP touch (M5)
```

So the "M3 and M5 don't nest, LCM is 15" defect **does not exist in the live path**. The
*real* defect is the one underneath it, and it is real: **confirmation and trigger were
both M5**, so a fill waited on the same bar that confirmed it. S01 fixes that by dropping
the trigger to M1. H4 is likewise not the zone-identification timeframe here — H1 picks
the levels; H4/D1/W1 only feed zero-confluence clustering.

**2. Same lineage caveat as V3.190.** This descends from V3.176, so the V3.180 P01–P13
parity fixes are absent, and `ApplyUniversalRiskCap()` / `SetupRiskDistance()` do not
exist. Their duties are carried by `CapSetupVolumeForCentSafety()` and
`CapVolumeForStandardRiskGuard()`, which is where the S05 "use the actual stop distance"
requirement was applied.

**Not compiled.** No MQL5 toolchain here. Balance and ordering were verified
mechanically; **expect MetaEditor errors on the first pass.**

## Cross-cutting design decisions

- **Sizing has one choke point.** `CapSetupVolumeForCentSafety()` is where quality is
  applied, because every entry path funnels through it. Quality is applied *before* the
  risk/margin caps, so it can only ever **reduce** size — the caps keep the final word.
- **Factors never compound.** S02/S03 combine by *least-favourable-wins*, not product.
  0.50 × 0.35 = 0.175 would be an unintended de-facto rejection. When S04 grading is on
  it becomes the **sole** consumer and ignores the individual factors entirely.
- **Quality never rejects.** If a multiplier would push volume under the broker minimum,
  the setup is taken **at the minimum**. Frequency is held constant by construction.
- **Anything driving exits is frozen at open**, for the same reason V3.190 S03 freezes ATR
  geometry: mid-trade drift would break the S01 monotonic ratchet.

---

## S01 — Routing chain correction + H1 bias
**Commit:** `V2.0 S01` · **Inputs:** `InpUseV2RoutingChain`, `InpUseH1BiasFilter`,
`InpH1BiasEMAPeriod`, `InpH1BiasMode`, `InpCounterTrendSizeMult`

Confirmation stays on M5; the **trigger drops to M1** (nests 5:1, so windows align on
every confirmation bar). H1 EMA bias requires price-vs-EMA *and* slope to agree —
disagreement yields NEUTRAL, so a chopping H1 doesn't tax setups in both directions.
Mode 1 size-weights counter-trend setups; mode 2 hard-filters and is opt-in.

**⚠️ Frequency trap caught here:** `InpReadyExpiryBars` counts bars of the *trigger*
timeframe. Switching to M1 unchanged would have cut READY lifetime from **~27.75 h to
~5.5 h** and silently dropped setups. `ReadyExpiryBarsEffective()` rescales it so
wall-clock lifetime is preserved.

**Functions:** `ConfigureRouting()` · new `RefreshH1Bias()`, `H1BiasDirection()`,
`IsCounterToH1Bias()`, `V2QualitySizeMultiplier()`, `ReadyExpiryBarsEffective()` ·
`CapSetupVolumeForCentSafety()` · `OnInit`/`OnDeinit` · `DrawDashboard()`

**Look for:** average adverse excursion between confirmation and fill should shrink —
that is the whole point. **Trade count must stay ≈ STAGE0; if it drops, the expiry
rescale isn't working.** Check the init line for `trigger=M1` and the rescaled bar count.

---

## S02 — Zone freshness
**Commit:** `V2.0 S02` · **Inputs:** `InpTrackZoneFreshness`, `InpFreshnessMaxTouches`,
`InpTouch1SizeMult`…`InpTouch4PlusSizeMult`, `InpZoneIdentityTolerancePips`

`InpMaxTouchDeployAttempts=7` + `InpReadyExpiryBars=333` meant the EA re-entered the same
zone repeatedly at full size — systematically loading the lowest-probability touches.
Now size decays 1.00 / 0.60 / 0.35 / 0.20 by touch number.

Touches count at the **latch, not at deploy** — a zone is worked by price arriving,
whether or not we filled. Identity is midpoint proximity (edges drift as the map
refreshes). Bounded 48-record ring with LRU eviction. **Persisted through
`SaveState()`/`LoadState()`** so a restart doesn't reset the decay curve.

**Functions:** new `ZoneTouchIndex/Count`, `RegisterZoneTouch()`,
`FreshnessSizeMultiplier()`, `SaveZoneTouchState()`/`LoadZoneTouchState()` ·
`SaveState()`/`LoadState()` · `PersistentReadySetup.zoneTouchNumber`

**Look for:** **the falsification test is win rate by `TouchNumber` in the CSV.** If
touch 1 doesn't materially outperform touch 3+, the whole freshness premise is wrong for
your zones and S02/S04 should be reconsidered rather than tuned.

---

## S03 — Departure strength
**Commit:** `V2.0 S03` · **Inputs:** `InpScoreDepartureStrength`,
`InpDepartureLookbackBars`, `InpStrongDepartureRatio`, `InpWeakDepartureRatio`,
`Inp{Strong,Moderate,Weak}DepartureSizeMult`

Scores the origin leg 0.0–1.0: **range 60%** (departure travel ÷ base range, linear
between weak and strong ratios) + **bodies 40%** (consecutive run of ≥60%-body candles
leaving the zone; a counter bar ends the run). Weighted toward range because distance is
harder to fake with one outsized bar.

Scored **once** at zone formation and frozen. Unmeasurable → −1.0, which never penalises.

**Functions:** new `ComputeDepartureScore()`, `DepartureSizeMultiplier()` ·
`QueuePersistentSetup()` · `PersistentReadySetup.departureScore`

**Look for:** bucket CSV `DepartureScore` into <0.35 / 0.35–0.70 / >0.70 and compare
expectancy. Needs a **monotonic** relationship to justify the stage — if the middle
bucket wins, the score is measuring noise.

---

## S04 — Unified A/B/C grade
**Commit:** `V2.0 S04` · **Inputs:** `InpUseZoneGrading`, `InpGrade{A,B,C}SizeMult`,
`InpGrade{A,B,C}PartialTPPips`, `InpGrade{A,B,C}TrailMult`,
`InpRoundNumberTolerancePips`

```
A : 1st touch AND departure ≥ 0.70 AND aligned with H1 bias
C : 3rd+ touch OR departure < 0.35 OR counter-trend to H1
B : everything else
```
**C wins ties** — a stale or counter-trend zone is not an A however explosive its
departure. An *unmeasured* departure is neutral, so a missing score can't manufacture
either grade. A proximal edge within tolerance of a $5/$10 level upgrades one step
($10 reported in preference); **upgrade only**.

Grade is the **single consumer** — when on, `V2QualitySizeMultiplier()` returns the grade
multiplier and never consults S01/S02/S03. It also drives **exits**: frozen onto
`HybridTrailState` at open (resolved by mapping the order comment back to its setup) and
scaling the initial/tight trail plus the S02 partial target.

**Functions:** new `NearGoldRoundNumber()`, `ComputeZoneGrade()`, `ZoneGradeText()`,
`Grade{Size,Trail}Multiplier()`, `GradePartialTPPips()`, `ResolvePositionZoneGrade()` ·
`FreezeTrailGeometry()` · `HybridTrailState.zoneGrade/.partialTargetDistance`

**Look for:** **this is the stage the CSV columns exist for.** Compute win rate *and*
expectancy per `ZoneGrade`. The table is validated only if **A > B > C on expectancy**.
If C outperforms B you have the grade definition backwards; if all three are equal the
grading inputs aren't separating anything and the added complexity isn't paying.

---

## S05 — Zone distal-edge stops
**Commit:** `V2.0 S05` · **Inputs:** `InpUseZoneDistalStops`, `InpDistalStopBufferPips`,
`InpDistalStopMinPips`, `InpDistalStopMaxPips`, `InpFallbackToATRStop`

Stop sits beyond the zone's **distal edge** (BUY at demand → below the zone low) plus
buffer, clamped to [min, max]. Previously a stop could sit *inside* the zone being
traded, so ordinary rotation stopped the trade out on a thesis that hadn't failed.

**Wide zones fall back to the ATR/fixed stop rather than clamping** — clamping would
place a stop the zone doesn't justify while sizing as though it did.

**Sizing correctness:** the distal stop is returned from `ResolvedPresetStopPips()`, which
every order-send path *and* the risk cap already call — so sizing is computed against the
stop actually placed and a variable stop cannot desync from the risk calc.

Trail / arm / tighten / breakeven all scale by the **same ratio** the stop moved,
preserving the S01 phase shape (a 30-pip stop with an unscaled 7-pip arm is a different
trade entirely).

**Functions:** new `ResolveDistalStopPips()`, `SetDistalContext()`/`ClearDistalContext()` ·
`ResolvedPresetStopPips()` · `FreezeTrailGeometry()`

**Look for:** distribution of `ActualStopPips` in the CSV. If most rows sit at
`InpDistalStopMaxPips` the fallback is firing constantly and zones are too wide for this
approach. Compare loss size distribution vs STAGE4 — the win is **fewer stop-outs that
later reversed**, which shows up as fewer losses, not smaller ones.

---

## CSV additions

`ZoneGrade` · `TouchNumber` · `DepartureScore` · `H1BiasAligned` · `ActualStopPips`
— captured into `SetupAnalytics` at deployment and written per setup row. Without these
the grading table is unfalsifiable, which is why they ship with the build rather than
after it.

## Verification performed

| Check | Result |
|---|---|
| Brace / paren balance (strings + comments excluded) | ✅ 896/896 · 5966/5966, depth returns to 0, never negative |
| New functions forward-declared before first use | ✅ added to the existing block |
| Arity at changed call sites | ✅ no existing signature changed; all new functions are additive |
| No new `MQL_TESTER` branches | ✅ 11, unchanged from V3.190 |
| `GetTickCount64` confined to `NowMs()` | ✅ 1 occurrence |
| No order-send path yields `SL = 0.0` | ✅ `InpRetryEntryWithoutSLOnReject` still defaults false; all send paths take a non-zero stop from `ResolvedPresetStopPips()` |
| Both routing chains produce valid setups | ⚠️ **structurally** verified (both branches wired, expiry rescaled, old path untouched when the switch is off) — **not** runtime-verified; this is what STAGE0 vs STAGE1 is for |
| Indicator handles created once / released | ✅ H1 EMA + ATR both in `OnInit`/`OnDeinit`, refreshed per-bar |
| **Compiles in MetaEditor** | ❌ **not verified — no toolchain** |
