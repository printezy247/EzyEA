# EzyMap V3.190 — Exit Geometry & Entry Timing Refinement

**Base:** `EzyMap_V3_176_V3_175_BASE_SYNCHRONIZED_LIVE_EXIT_SL21_TRAIL7.mq5`
(the V3.176 line in this repo, including the risk-tightening and
reporting-reconciliation commits).
**Output:** `EzyMap_V3_190_REFINED.mq5`

## ⚠️ Read this before testing

**This is NOT built on `EzyMap_V3_180_PARITY_HARDENED.mq5`.** That file was never
available in this workspace — only the V3.176 line was. Consequences:

- The **V3.180 P01–P13 parity fixes are absent.** They were not removed; they were
  never present in this ancestor.
- `NowMs()` and `TradeRetcodePartial()` here are **V3.190 implementations**, not the
  V3.180 originals. Semantics may differ from what P08/P12 defined.
- `ApplyUniversalRiskCap()` and `SetupRiskDistance()` do not exist in this line. The
  equivalent duties are carried by `CapSetupVolumeForCentSafety()` and
  `CapVolumeForStandardRiskGuard()`, which is where the S03 "use the actual stop
  distance" requirement was applied.

If V3.180 is the branch you actually run, treat this as a **reference implementation
to port**, not a drop-in replacement.

**This has not been compiled.** No MQL5 toolchain exists in this environment. Brace,
paren and bracket balance were verified with a tokenizer that ignores strings and
comments (all balanced), every new function is forward-declared, and all changed
signatures were arity-checked at every call site — but **expect MetaEditor errors on
the first pass** and treat the first successful compile as the real gate.

## Design rules applied throughout

- Every new input **defaults to the V3.176 behaviour**. Flip one input to A/B a stage;
  no binary swapping.
- Every new input carries a `// V3.190 Sx:` comment stating what it does, what the old
  behaviour was, and the recommended value.
- Logging follows the existing style (`Log("V3.190 S1 ..." + ...)`).
- **No new `MQL_TESTER` branches.** Count is unchanged from the base file at 11, all
  pre-existing.
- **`GetTickCount64()` appears exactly once**, inside `NowMs()`. All 8 former direct
  call sites route through it.

## Test order

Run `STAGE0_BASELINE` first and keep its report. Each subsequent `.set` is cumulative
(STAGE3 = S1+S2+S3). Load them **on top of your working set** — they only list the
V3.190 inputs, so every other setting keeps its current value.

---

## S00 — Scaffold
**Commit:** `8630899`

Version → `3.190`; header gains the S01–S05 summary block. `PREFIX` and
`InpCSVReportPrefix` re-versioned so V3.190 does not collide with V3.176 chart objects
or report files.

**Added:** `NowMs()` (sole reader of the OS tick counter), `TradeRetcodePartial()`
(detects `TRADE_RETCODE_DONE_PARTIAL`).

---

## S01 — Decouple trail arming from trail distance ⭐ highest priority
**Commit:** `e67d98f` · **Inputs:** `InpTrailArmPips`, `InpTrailInitialDistancePips`,
`InpTrailTightenAtPips`, `InpTrailTightDistancePips`, `InpUseBreakevenLock`,
`InpBreakevenLockAtPips`, `InpBreakevenLockOffsetPips`

### What was wrong
`LiveTrailActivationDistance()` raised the arm threshold to the **full trail distance**
whenever `InpLiveXAURequireFullTrailBeforeArm` was true. With trail = 7 that forced
arm = 7, so a position had to run +7 — roughly **+9–10 net** of spread and commission —
before the trail could arm at all. Anything peaking between +1 and +9 and turning over
took the entire −21 preset stop.

### What changed
Arm threshold is now its own input, and the two-branch trail became one monotonic
phase machine:

| Phase | Condition | Stop source |
|---|---|---|
| 0 | from fill | preset stop |
| 1 | peak ≥ `InpTrailArmPips` | trail at initial distance |
| 2 | peak ≥ `InpBreakevenLockAtPips` | breakeven + offset **floor** |
| 3 | peak ≥ `InpTrailTightenAtPips` | trail at tight distance |

Each phase contributes a *candidate*; candidates combine through `TrailBetterStop()`
and pass through **one ratchet** into `HybridTrailState.virtualStop`, which can only
ever improve. That single ratchet is what makes the stop monotonic across every
transition — widening the trail can never drag an advanced stop backwards. The
breakeven lock is a floor folded into the same ratchet, not a replacement for the trail.

`InpLiveXAURequireFullTrailBeforeArm` now clamps the **arm** only. The arm distance is
applied identically in tester and live; only the pre-existing live-chart spread/cushion
padding stays conditional.

### Functions touched
`LiveTrailActivationDistance()` (2nd param is now the *arm* distance) ·
`ManageHybridTrailingPositions()` (phase machine) · **new:** `TrailStopImproves()`,
`TrailBetterStop()`, `FreezeTrailGeometry()` · `HybridTrailState` (frozen geometry
fields) · `EnsureHybridTrailState()`

### Verification done
Simulated the machine at default inputs against V3.176 semantics across excursions
0→60 pips: **stop placement identical at every point.** At recommended values the
ratchet stays monotonic through the 12→7 tighten flip.

### What to look for
Loss distribution should shift, not just shrink. Compare the count of full −21 losses
against STAGE0. Expect more small wins and small scratches, and a lower average loss.
Watch `V3.190 S1 TRAIL ARMED` for how early arming now happens, and
`V3.190 S1 BREAKEVEN FLOOR ENGAGED` for how often the floor saves a trade. **If average
win drops more than average loss improves, the initial trail (12) is too tight.**

---

## S02 — Partial take profit
**Commit:** `47613b7` · **Inputs:** `InpUsePartialTakeProfit`, `InpPartialTPPips`,
`InpPartialTPPercent`, `InpBreakevenAfterPartial`

### What was wrong
No TP of any kind. Every position ran purely on the trail, so any trade that spiked and
reversed handed the whole excursion back.

### What changed
Banks `InpPartialTPPercent` of volume at `InpPartialTPPips`, remainder rides on the S01
trail from breakeven + offset.

- Evaluated **before** the phase machine so a touched target banks on the same pass, and
  measured against **current** price, not the peak — we only bank what is actually
  available.
- **Never strands an unclosable stub:** if the slice or the remainder would fall below
  `SYMBOL_VOLUME_MIN`, the **full** position closes instead, with the reason logged.
- `partialTaken` is latched **before** the request is sent — the close is asynchronous,
  and an unlatched flag would let the next tick fire a second partial. A rejection
  clears it so a later pass can retry.
- `TradeRetcodePartial()` is checked on the close itself; a short fill is accepted but
  called out in the journal rather than read as a clean close.

### Functions touched
`RequestSynchronizedPositionClose()` — gained a trailing `closeVolume` parameter
defaulting to `0.0` (= full close, exact V3.176 behaviour), so **all four pre-existing
call sites are unchanged** and the partial inherits the existing close-lock, rejection
and deviation handling instead of calling `PositionClosePartial` directly ·
`ManageHybridTrailingPositions()` · `ExitExecutionState.partialCloseVolume` ·
`HybridTrailState.partialTaken` / `.partialRequestedVolume`

State reuses the existing per-position structs — no parallel tracking was added.

### What to look for
Win rate should rise noticeably; average win should fall. That trade-off is the point —
check **expectancy**, not win rate alone. Grep `V3.190 S2 PARTIAL TP` for how often
`FULL CLOSE (remainder would be below broker minimum)` fires: if that dominates, your
lot sizes are too small for a 55% split and you should raise size or lower the
percentage.

---

## S03 — ATR-normalized geometry
**Commit:** `1cd4f68` · **Inputs:** `InpUseATRGeometry`, `InpATRPeriod`,
`InpATRTimeframe`, `InpATRStopMultiplier`, `InpATRTrailMultiplier`,
`InpATRArmMultiplier`, `InpATRStopFloorPips`, `InpATRStopCeilingPips`,
`InpATRTrailFloorPips`

### What was wrong
Fixed 21/7 ignored that Asia-session gold ATR can be a third of the New York figure:
the same arm is unreachable in quiet hours, the same stop sits inside the noise during
news.

### What changed
```
stop  = clamp(ATR × InpATRStopMultiplier, floor, ceiling)
trail = max(ATR × InpATRTrailMultiplier, InpATRTrailFloorPips)
arm   = ATR × InpATRArmMultiplier
```
Tight distance and tighten-at threshold scale by the **same ratio** the initial trail
moved, preserving the shape configured in S01 rather than inventing separate
multipliers.

- Handle created once in `OnInit`, released in `OnDeinit`. **`iATR()` is never called
  per tick.**
- Buffer read at most once per bar of `InpATRTimeframe`, from **shift 1** (last *closed*
  bar) so geometry does not depend on where in the forming bar a position opened.
- **Geometry is frozen** into `HybridTrailState` at open and never re-derived, so a
  falling ATR cannot shrink a trail distance and drag an advanced stop backwards — S01
  monotonicity is preserved.
- Values land in the same fields and drive the **same phase machine**; the logic is not
  forked. With the switch off the resolver is a no-op and behaviour is identical to S01.

### Sizing correctness
All three order-send paths now derive their stop from `ResolvedPresetStopPips()` rather
than `InpPresetStopLossPips`, so an ATR-derived stop is the one actually submitted *and*
the one sizing is computed against.

Separately, a **pre-existing bug** was fixed: the live-cent parity check measured risk
against the **trailing** distance (7 pips) instead of the real 21-pip stop, understating
entry→stop risk by two thirds. It now uses the caller's actual `sl`, falling back to the
resolved preset distance only when no usable stop was supplied. Stale `"50-pip risk"`
log labels corrected to `"entry->stop risk"`.

### Functions touched
**New:** `RefreshGeometryATR()`, `CurrentGeometryATR()`, `ResolveATRGeometryPips()`,
`ResolvedPresetStopPips()` · `FreezeTrailGeometry()` · `OnInit` / `OnDeinit` ·
`ManageHybridTrailingPositions()` · `CapSetupVolumeForCentSafety()` ·
`SubmitDirectZeroConfMarket()`, `PlacePersistentLayer()`,
`BuildForcedZeroConfluenceMarketPlan()`

### What to look for
Check `V3.190 S1 GEOMETRY FROZEN` lines for the spread of frozen ATR values across
sessions — if they cluster at the floor or ceiling, the multipliers need retuning.
Compare Asia-hours vs New York performance separately; **this stage should show most of
its benefit in one session and little in the other.** If overall results barely move,
the floors/ceilings are binding too often and the geometry is effectively still fixed.

---

## S04 — Touch confirmation before fill
**Commit:** `2fa85ca` · **Inputs:** `InpRequireTouchConfirmation`,
`InpTouchConfirmMode`, `InpTouchStallSeconds`, `InpTouchStallMaxExtendPips`,
`InpTouchConfirmTimeoutSec`

### What was wrong
Deployed on the **first** touch of the zone. On a 21-pip stop, entering 2–5 pips better
is a material change in distance-to-stop.

### What changed
Records the touch and gates the deploy on either:
- **(a)** an M1 bar **closes** back inside the zone, or
- **(b)** price stops extending beyond the running touch extreme for
  `InpTouchStallSeconds` — a move further than `InpTouchStallMaxExtendPips` past the
  extreme restarts that clock.

`InpTouchConfirmMode` selects either / M1-only / stall-only.

**Frequency is explicitly preserved.** The touch latch is left standing while waiting so
the existing retry and expiry machinery keeps the setup alive, and
`TouchConfirmationSatisfied()` self-releases on `InpTouchConfirmTimeoutSec` by deploying
at market — the V3.176 behaviour — rather than dropping the setup.

Confirmation state lives in `PersistentReadySetup` alongside the other touch fields, not
in a parallel structure, so it is cleared by the same `ClearPersistentTouchLatch()` path
and cannot leak across a re-touch or expiry. All timing goes through `NowMs()`.

### Functions touched
**New:** `TouchConfirmationSatisfied()` · `PersistentReadySetup` (7 confirm fields) ·
`ClearPersistentTouchLatch()` · `ProcessPersistentSetups()` (gate before
`PersistentQualityPass`)

### What to look for
**Count `V3.190 S4 TIMEOUT FALLBACK` against `V3.190 S4 CONFIRMED` — this is the headline
metric for the stage.** A high fallback rate means confirmation rarely arrives and the
stage is mostly inert; a low rate with worse results means you are confirming into
already-moved prices. Total trade count must stay ≈ STAGE3; **if it drops, frequency
was lost and something is wrong.** Compare average entry price relative to zone edge.

---

## S05 — Scale into strength
**Commit:** `574892f` · **Inputs:** `InpScaleInOnConfirmation`, `InpInitialLayerCount`,
`InpScaleInTriggerATRMult`, `InpMaxScaleInLayers`

### What was wrong
Up to `InpMaxActiveLayersPerDirection` layers could deploy within a few pips of each
other. That is effectively one position at N× size, but it books N separate entries — so
a failed zone records N losses and the win rate reads as a rout.

### What changed
- `DesiredLayersForSetup()` returns only `InpInitialLayerCount` on the trigger.
- Everything beyond that must be earned: `ScaleInAllowed()` requires the existing
  directional exposure to be green by `InpScaleInTriggerATRMult × ATR`, measured as
  favourable excursion from the **volume-weighted average entry** for that direction.
  Falls back to the resolved preset stop as the reference when ATR is unavailable. Caps
  total additions at `InpMaxScaleInLayers`.

The gate sits at the top of `DirectionalLayerSlotAvailable()` because every entry path —
aggressive arm, persistent layer, direct zero-conf — already funnels through it. One
gate covers them all, and scale-in layers still travel the normal path to the broker, so
they keep existing volume/risk capping and derive their stop from the same resolved
geometry **relative to their own fill price**.

**Setup frequency is unchanged** — this gates *fills within an already-taken direction*,
never the arming or triggering of setups.

### Functions touched
**New:** `DirectionalFavourableExcursion()`, `ScaleInAllowed()` ·
`DirectionalLayerSlotAvailable()` · `DesiredLayersForSetup()`

### What to look for
Total **entry fills** should fall sharply while **setup count stays flat** — verify both
in the reconciliation line, since a drop in setups means the stage overreached. Win rate
should rise substantially because losing zones no longer book N entries. **Net profit
may fall** if the layering was genuinely additive on winners; that trade-off is the
decision this stage puts in front of you. Watch the ratio of
`V3.190 S5 SCALE-IN ALLOWED` to `V3.190 S5 SCALE-IN WAIT`.

---

## Verification performed

| Check | Result |
|---|---|
| Brace / paren / bracket balance (strings + comments excluded) | ✅ 832/832 · 5509/5509 · 1010/1010 |
| New functions forward-declared before first use | ✅ added to the block near line ~1190 |
| Arity at every call site of changed signatures | ✅ `RequestSynchronizedPositionClose` (4 legacy sites, default param), `LiveTrailActivationDistance` (2 sites) |
| No new `MQL_TESTER` branches | ✅ 11, unchanged from base |
| `GetTickCount64` confined to `NowMs()` | ✅ 1 occurrence |
| No order-send path can produce `SL = 0.0` | ✅ `InpRetryEntryWithoutSLOnReject` defaults **false**; the naked-retry branch is disabled, and all three send paths compute a non-zero stop via `ResolvedPresetStopPips()` |
| S01 defaults reproduce V3.176 | ✅ simulated across 0→60 pip excursions, identical |
| S01 monotonic at recommended values | ✅ verified through the 12→7 tighten flip |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain available** |
