# EzyMap V2.1b — Zero-Confluence Trigger Source Ladder Refinement

**Base:** `EzyMap_V2_1a_SESSION_VOL.mq5` · **Output:** `EzyMap_V2_1b_TRIGGER_REFINED.mq5`
Incremental build on V2.1a, scoped **exclusively** to the zero-confluence trigger source
ladder. `#property version` bumped `2.101` → `2.102`. Two stages, two inputs, eleven diff
hunks, no signature changes.

## ⚠️ Four things to know before testing

**1. The default polarity is REVERSED from every earlier stage.** V3.190 S01–S05, V2.0
S01–S05 and V2.1a S01–S02 all added inputs that **default to the old behaviour**, so a
freshly compiled binary reproduced its base exactly and the `STAGE0_BASELINE.set` was the
all-`false` one. **V2.1b inverts that.** Both new inputs default to the **new, changed**
behaviour:

| Input | Default | Meaning of the default |
|---|---|---|
| `InpZeroConfAllowCurrentMapTier` | `false` | **NEW** — CURRENT_MAP/CURRENT_OUTER tier removed |
| `InpZeroConfIncludeLevel1` | `false` | **NEW** — Level1 (S1/D1) excluded from the W1/D1 ladder |

So `EzyMap_V2_1b_STAGE0_BASELINE.set` is the **all-`true`** file, not the all-`false` one,
and **a default-valued V2.1b binary is not V2.1a-equivalent.** This is called out in the
file's own header block (`POLARITY WARNING`, lines 165–177), in both input comment blocks,
and in both `.set` file headers. It is the single most likely thing to be misread when
someone returns to this build in three months.

**2. The ladder change hits BOTH zero-conf routes, not just the direct one.** The brief
named `ResolveZeroConfTriggerMap()` and `ProcessDirectZeroConfluenceTriggers()`.
`ResolveZeroConfTriggerMap()` has **two** callers, and I did not restrict the edit to one:

| Caller | New file line | Map used | Affected by S01 population gate | Affected by S02 |
|---|---|---|---|---|
| `ResolveDirectZeroConfTrigger()` | 3138 (V2.1a: 3001) | live, built per touch | yes | yes |
| the CMP touch scan (persistent-setup zero-conf fallback) | 14110 (V2.1a: 13951) | **frozen** `g_persistentSetups[i].zeroConfTriggerMap` | yes | yes |

That is the correct reading of "refine the trigger source ladder" — the ladder is one
ladder — but it is a wider blast radius than the two function names imply and is stated
here rather than discovered in a backtest. **S01's exclusivity and retire-on-fill changes
are direct-route-only**, because that rule physically lives in
`ProcessDirectZeroConfluenceTriggers()`.

**3. One deliberate deviation from the brief's literal log text.** See *Deviations* below.
The mandated string lists six sources and omits `H4_SINGLE`, which is still live at
priority 7. I kept the mandated text verbatim as the prefix and appended a clause naming
H4_SINGLE, rather than shipping a ladder announcement that omits an active tier.

**4. Not compiled.** There is no MQL5 toolchain in this environment. Balance, hunk
inventory, signature stability and grep counts were verified mechanically (see the
verification table); **expect MetaEditor errors on the first pass.**

---

## Level1 / Level2 = S1/S2 and D1/D2 — confirmed structurally

Re-verified by direct read of `BuildCurrentZeroConfTriggerMap()` in the V2.1a source before
editing. The assignment is unambiguous and symmetric:

**Support / buy-anchor branch — `EzyMap_V2_1a_SESSION_VOL.mq5` lines 2597–2604:**

```
map.currentLevel1=g_S1;      // line 2597
map.currentLevel2=g_S2;      // line 2598
map.h4Level1=g_zcH4S1;       // line 2599
map.h4Level2=g_zcH4S2;       // line 2600
map.d1Level1=g_zcD1S1;       // line 2601
map.d1Level2=g_zcD1S2;       // line 2602
map.w1Level1=g_zcW1S1;       // line 2603
map.w1Level2=g_zcW1S2;       // line 2604
```

**Resistance / sell-anchor branch — lines 2620–2627:**

```
map.currentLevel1=g_R1;      // line 2620
map.currentLevel2=g_R2;      // line 2621
map.h4Level1=g_zcH4R1;       // line 2622
map.h4Level2=g_zcH4R2;       // line 2623
map.d1Level1=g_zcD1R1;       // line 2624
map.d1Level2=g_zcD1R2;       // line 2625
map.w1Level1=g_zcW1R1;       // line 2626
map.w1Level2=g_zcW1R2;       // line 2627
```

**Therefore `Level2` is unambiguously S2 on the buy side and R2 on the sell side**, and
`Level1` is S1/R1. Index `1` of the `w1[]`/`d1[]` arrays in `ResolveZeroConfTriggerMap()`
is the outer level. S02's premise holds. (Struct field order is at V2.1a lines 1222–1238;
the array loads are at V2.1a lines 2845–2852 / V2.1b lines 2962–2969.)

### Collateral-damage check: S01 and S02 do not overlap

`map.currentLevel1` / `map.currentLevel2` are a **separate, unrelated pair of fields**
(struct lines 1230–1231) fed from `g_S1`/`g_S2` and `g_R1`/`g_R2` — the live, continuously
re-derived pair — **not** from `g_zcD1S1`/`g_zcW1S1`/etc., which is where every other field
in the map comes from.

- **S01 touches only** `currentLevel1` / `currentLevel2`, via the `current[]` array.
- **S02 touches only** `w1Level1`/`w1Level2` and `d1Level1`/`d1Level2`, via `startIdx`.

The two field sets are disjoint, the two code sites are disjoint, and **there is zero
interaction between the stages.** Setting either input independently is meaningful; the
`.set` pair only ships the two extremes because those are the A/B endpoints.

---

## S01 — CURRENT_MAP / CURRENT_OUTER tier removed
**Stage:** `V2.1b S01` · **Input:** `InpZeroConfAllowCurrentMapTier` (default `false` = new)

V2.1a's ladder ended with two priority-8 candidates built from `current[0]`/`current[1]`.
Those are the **live** `g_S1`/`g_S2` (`g_R1`/`g_R2`) pair, which re-derives as price moves,
unlike the frozen W1/D1/H4 levels the rest of the ladder is built from. Because they
re-derive, they sit near price **by construction**, so they win the nearest-distance
tie-break inside `ConsiderZeroConfCandidate()` far more often than a priority-8 rank
implies — a bottom-of-ladder source taking top-of-ladder share.

`EZY_ZC_TRIGGER_CURRENT_OUTER` additionally carried a privilege no other code had:

- it was the **only** code allowed to fire while a zero-conf setup for the same direction
  was already waiting (the exclusivity carve-out), and
- on fill it **retired every other waiting zero-conf setup** in that direction.

### Design decision: gated, not deleted — and why the override goes with it

The brief asked for the tier to be *"removed entirely"* including its override right,
**and** for a rollback input so the old 9-source ladder could be reproduced for an A/B
backtest. Those two requirements only both hold if **the override right is restored too**
when the rollback flag is set. Restoring the population without the privilege would
reproduce *neither* ladder: not V2.1a (which had the privilege) and not V2.1b (which has
no tier), and the "control" arm of the A/B would be measuring a configuration that has
never existed. So:

1. **Population** (new lines 3079–3092) — the two `ConsiderZeroConfCandidate()` calls are
   wrapped in `if(InpZeroConfAllowCurrentMapTier)`.
2. **Exclusivity carve-out** (new lines 3483–3497) — rewritten so the carve-out only
   exists when the flag is on. With the flag off this is the unconditional strict rule
   *"an already-waiting zero-conf setup blocks a new direct fill"*, with **no exception** —
   exactly the "removed entirely" default the brief wants.
3. **Retire-stale-setups block** (new lines 3378–3380) — **I chose to add the explicit
   `InpZeroConfAllowCurrentMapTier &&` guard** rather than leave the condition bare. The
   block is unreachable either way once the tier cannot be populated
   (`g_directZeroConf.triggerCode` can never hold `CURRENT_OUTER`), so this is a
   readability decision, not a functional one. Naming the input in the condition makes the
   privilege visibly part of the same rollback switch; a bare `if` would read to a future
   maintainer as behaviour that survived S01.

The net effect is that the override logic **is not deleted from the source but is fully
inert by default**, and all three pieces move together under one input. That is why the
PR does not show the deletion the brief's wording might lead a reviewer to expect.

The enum values (`=8`, `=9`) and the `ZeroConfTriggerCodeText()` switch cases are
**deliberately kept**. Removing the enum would break the rollback and any persisted
`PersistentReadySetup.zeroConfTriggerCode` carrying an old value; removing the text cases
would make such a code render as the generic fallback in the CSV.

### Every `CURRENT_MAP` / `CURRENT_OUTER` reference and how it was handled

Complete inventory — 12 lines in the new file (9 pre-existing, 3 net-new from the rewritten
carve-out):

| New line | V2.1a line | Site | Disposition |
|---|---|---|---|
| 1334 | 1217 | `EZY_ZC_TRIGGER_CURRENT_MAP=8` enum decl | **kept unchanged** — required for rollback and for persisted codes |
| 1335 | 1218 | `EZY_ZC_TRIGGER_CURRENT_OUTER=9` enum decl | **kept unchanged** — same |
| 2556 | 2439 | `ZeroConfTriggerCodeText()` case → `"ZERO-CONF CURRENT S1"`/`R1` | **kept unchanged** — display only; must not break under rollback |
| 2561 | 2444 | `ZeroConfTriggerCodeText()` case → `"ZERO-CONF LIVE S2"`/`R2` | **kept unchanged** — same |
| 3083 | 2947 | `ConsiderZeroConfCandidate(..., CURRENT_MAP, ...)` | **population gated** behind `if(InpZeroConfAllowCurrentMapTier)` |
| 3089 | 2953 | `ConsiderZeroConfCandidate(..., CURRENT_OUTER, ...)` | **population gated** — same block |
| 3380 | 3236 | retire-stale-setups block condition | **explicitly guarded** by the input, in addition to being unreachable without it |
| 3485 | 3333 | buy exclusivity comparison | **rewritten** as `buyOuterOverride = Inp… && (buyCode==CURRENT_OUTER)` |
| 3489 | 3337 | sell exclusivity comparison | **rewritten** as `sellOuterOverride = Inp… && (sellCode==CURRENT_OUTER)` |
| 3492 | — | `if(buyWaitingZeroConf && !buyOuterOverride)` | new line replacing the inline comparison |
| 3496 | — | `if(sellWaitingZeroConf && !sellOuterOverride)` | new line replacing the inline comparison |
| 3595 | 3436 | cosmetic `"live outer override=YES/NO"` log flag | **left as-is** per brief — no functional effect; simply always reads `NO` at defaults |

There is **no other reference anywhere in the file**. There is no CSV struct field, no
`ReportSetupRow` column and no dashboard branch named after these codes; the CSV and the
logs carry the generic `triggerCode` / `triggerText` / `ZeroConfTriggerCodeText()` output,
which degrades cleanly once the tier stops being populated. The `V3.176 LIVE S2/R2 OVERRIDE
COMPLETE` log line inside the retire block was left with its original V3.176 tag — it can
now only print in rollback mode, where the tag is accurate.

---

## S02 — W1 / D1 triggers restricted to Level2 (S2 / D2)
**Stage:** `V2.1b S02` · **Input:** `InpZeroConfIncludeLevel1` (default `false` = new)

All four W1/D1 ladder loops iterated `i = 0..1`, making both the inner (S1/D1) and the
outer (S2/D2) level eligible. The inner level is nearer price and is touched far more
often, so on the distance tie-break it took most of the fills — the worse location for a
zero-**confluence** entry, which has no structural confirmation behind it and needs the
level itself to carry the trade.

One `startIdx` is declared once, before the four loops, and reused — the four loops share a
function scope, so per-loop declarations would be four copies of the same expression:

```
+   // V2.1b S2: index 0 is the INNER level (S1/D1) and index 1 the OUTER level
+   // (S2/D2) - see the assignments in BuildCurrentZeroConfTriggerMap().
+   // Starting the four W1/D1 loops here leaves only the outer level eligible.
+   // H4 is deliberately NOT gated by this: the H4_SINGLE loop further down
+   // still runs 0..1, and h4[0]/h4[1] stay available as cluster partners for
+   // a W1 or D1 anchor in the two cluster loops below.
+   int startIdx=InpZeroConfIncludeLevel1 ? 0 : 1;   // V2.1b S2
```

### Exact before/after of the four loop guards

Only the `for` line changes in each case; every loop **body** is byte-identical.

| # | Tier | New line | Before (V2.1a) | After (V2.1b) |
|---|---|---|---|---|
| 1 | `W1_CLUSTER` (priority 1) | 2979 | `   for(int i=0;i<2;i++)` | `   for(int i=startIdx;i<2;i++)   // V2.1b S2: W1_CLUSTER anchor, was i=0` |
| 2 | `W1_SINGLE` (priority 2) | 3002 | `   for(int i=0;i<2;i++)` | `   for(int i=startIdx;i<2;i++)   // V2.1b S2: W1_SINGLE, was i=0` |
| 3 | `D1_H4_CLUSTER` (priority 3) | 3011 | `   for(int i=0;i<2;i++)` | `   for(int i=startIdx;i<2;i++)   // V2.1b S2: D1_H4_CLUSTER anchor, was i=0` |
| 4 | `D1_SINGLE` (priority 4) | 3034 | `   for(int i=0;i<2;i++)` | `   for(int i=startIdx;i<2;i++)   // V2.1b S2: D1_SINGLE, was i=0` |

### What S02 deliberately does NOT touch

- **`H4_SINGLE` (priority 7, new line 3061).** Still `for(int i=0;i<2;i++)`. Both H4 levels
  remain eligible. Byte-identical to V2.1a lines 2936–2943.
- **Cluster-partner lookups.** `NearestClusterPartner(w1[i], d1[0],d1[1], h4[0],h4[1], …)`
  (new line 2985) and `NearestClusterPartner(d1[i], h4[0],h4[1], 0.0,0.0, …)` (new line
  3017) still pass **both** H4 indices, and the W1 cluster still passes **both** D1 indices.
  `startIdx` restricts the **anchor** only, never the partner set. A W1-outer anchor can
  therefore still cluster with a D1-**inner** or H4-inner partner — which is the intent: the
  partner is confirming evidence for the anchor's location, not itself a trigger source.
- **`LOW_RISK` (priority 5, new lines 3043–3050) and `READY` (priority 6, new lines
  3052–3059).** **Confirmed left untouched.** Both are gated on `map.lowRiskValid` /
  `map.readyValid` and address `map.lowRiskLo/Hi` / `map.readyLo/Hi` — zone bands, not
  level-indexed arrays. There is no `[i]` for `startIdx` to apply to. Byte-identical to
  V2.1a lines 2918–2934.

---

## CSV analytics: `triggerCode` capture is untouched

Confirmed by grep across the whole new file. The trigger type still reaches the CSV and the
logs through exactly the same three capture points as V2.1a and V2.0, none of which were
edited:

| Capture point | New line | V2.1a line | Route | Touched? |
|---|---|---|---|---|
| `g_persistentSetups[i].zeroConfTriggerCode = zeroCandidate.code;` | 14193 | 14034 | standard / persistent-setup fallback | **no** |
| `g_directZeroConf.triggerCode = chosenCode;` | 3576 | 3417 | direct zero-conf | **no** |
| `setup.zeroConfTriggerCode = EZY_ZC_TRIGGER_NONE;` (reset) · `g_persistentSetups[slot].zeroConfTriggerCode = EZY_ZC_TRIGGER_NONE;` (arm) | 2502 · 12206 | 2385 · 12047 | both | **no** |

Rendering to text is unchanged too: `PersistentTouchTriggerText()` (new line 2246) and the
`CMP TOUCH LATCHED` / `DIRECT ZERO-CONF …` log lines all call `ZeroConfTriggerCodeText()`,
whose switch is intact and whose fallback `return "ZERO-CONF";` still terminates the
function for any code not enumerated. **Win-rate-by-trigger-type therefore remains
measurable after the ladder shrinks from nine sources to six** — the same column carries
the same codes, there are simply fewer distinct values in it. `CaptureConfluenceSnapshot()`
call sites (3358, 10838) are likewise unchanged, so the V2.1a confluence columns keep
populating on both routes.

---

## Deviations from the brief

**1. The S01 init log line was extended.** The brief mandated verbatim:

```
Log("V2.1b: CURRENT_MAP/CURRENT_OUTER tier disabled | zero-conf ladder now W1_CLUSTER, W1_SINGLE, D1_H4_CLUSTER, D1_SINGLE, LOW_RISK, READY");
```

That string enumerates the ladder but **omits `H4_SINGLE`**, which the same brief
explicitly requires to stay unchanged and eligible at priority 7. Shipping it as written
would put a ladder announcement in every backtest log that contradicts the code. I kept the
mandated text **verbatim as the prefix** (so it stays greppable) and appended:

```
 | H4_SINGLE (priority 7) still eligible, unchanged by V2.1b
 | CURRENT_OUTER directional override and retire-on-fill withdrawn with the tier
```

The same reasoning applies to the phrase "6-source ladder": the **scored, changed** ladder
is six sources, but the **total** eligible tier count at defaults is seven including
H4_SINGLE. This document uses "six sources + H4_SINGLE" wherever precision matters.

**2. Both init log lines print unconditionally, in both polarities.** The brief asked for
the new-behaviour message only when the flag is `false`, with "the inverse … when true".
Implemented exactly that — but as `if/else`, so there is always exactly one line per stage
in the log. Given the reversed default polarity, a silent default run would be the *changed*
EA saying nothing, which is the wrong way round for reading a batch of tester logs.

**3. Explicit guard added to the retire-stale-setups block.** The brief offered this as a
choice. I took the explicit guard; rationale under S01 above.

Nothing else deviates. The V2.1a confluence gate (`ConfluenceGateAllows()`,
`SessionConfluenceScore()`, `VolatilityRegimeScore()`), the sweep/reclaim logic
(`ZeroConfM5SweepReclaim()`, `RefreshZeroConfM5ReclaimCache()`), exit geometry and sizing
are all byte-identical to V2.1a — see the hunk inventory.

---

## Diff hunk inventory

Eleven hunks, all accounted for. Nothing else in 16,073 lines changed.

| Hunk (V2.1a → V2.1b) | New lines | Stage | What |
|---|---|---|---|
| `@@ -156,6 +156,73 @@` | 159–225 | — | `V2.1b STAGE SUMMARY (S01-S02)` header block, inserted after the V2.1a `GATE NOTE` and before the `BASE NOTE`, padded to the existing 72-column comment box |
| `@@ -163,7 +230,7 @@` | 233 | — | `#property version "2.101"` → `"2.102"` |
| `@@ -1050,6 +1117,56 @@` | 1120–1168 | S01+S02 | two `//===== V2.1b STAGE n =====` input blocks with OLD/NEW/polarity commentary, after the V2.1a S02 block |
| `@@ -2851,7 +2968,15 @@` | 2971–2979 | S02 | `startIdx` declaration + W1_CLUSTER loop guard |
| `@@ -2874,7 +2999,7 @@` | 3002 | S02 | W1_SINGLE loop guard |
| `@@ -2883,7 +3008,7 @@` | 3011 | S02 | D1_H4_CLUSTER loop guard |
| `@@ -2906,7 +3031,7 @@` | 3034 | S02 | D1_SINGLE loop guard |
| `@@ -2942,17 +3067,29 @@` | 3070–3092 | S01 | CURRENT tier population wrapped in `if(InpZeroConfAllowCurrentMapTier)` |
| `@@ -3232,7 +3369,14 @@` | 3372–3380 | S01 | retire-stale-setups block guarded by the input |
| `@@ -3329,12 +3473,27 @@` | 3476–3497 | S01 | exclusivity carve-out rewritten via `buyOuterOverride`/`sellOuterOverride` |
| `@@ -15082,6 +15241,32 @@` | 15244–15268 | S01+S02 | `OnInit` ladder announcement, inserted after the V2.1a confluence-engine announcement and before `ApplyPremiumChartTheme()` |

---

## Verification performed

| Check | Result |
|---|---|
| Brace / paren / bracket balance (tokenizer excluding strings, char literals, line and block comments; depth tracked) | ✅ V2.1b `{}` 927/927 · `()` 6219/6219 · `[]` 1178/1178; depth never negative, residual stack 0, no mismatched pairs |
| Tokenizer sanity-checked against the documented V2.1a baseline | ✅ same tool reports V2.1a as `{}` 926/926 · `()` 6210/6210 · `[]` 1178/1178 — exactly the figures recorded in `V2_1a_CHANGES.md`, so the counts below are comparable |
| Delta accounted for | ✅ `{}` +1 = the `if(InpZeroConfAllowCurrentMapTier)` block. `()` +9 = that `if` (1) + two `(…Code==CURRENT_OUTER)` parenthesisations (2) + two `if(!Inp…)` (2) + four `Log(` (4). `[]` +0 |
| No existing function signature changed | ✅ machine-diffed the set of top-level signature lines in both files: **empty in both directions**. Pure body-edit inside `ResolveZeroConfTriggerMap()` / `ProcessDirectZeroConfluenceTriggers()` / `SubmitDirectZeroConfMarket()` / `OnInit`, plus two additive inputs. No arity change anywhere; the forward declaration of `ResolveZeroConfTriggerMap()` (new line 1762) is untouched |
| Every remaining `CURRENT_MAP` / `CURRENT_OUTER` reference enumerated and safe | ✅ 12 lines, all listed in the S01 table. None can crash: the enum values still exist so every comparison and `case` is well-formed; `ZeroConfTriggerCodeText()` has the safe terminal `return "ZERO-CONF";` (new line 2567) for any code that never occurs; the two `case` arms simply become unreachable at defaults, which MQL5 does not treat as an error |
| No new `MQL_TESTER` branches | ✅ 13 raw grep hits, **unchanged from the V2.1a source** (V2.1a: 13, V2.1b: 13). No tester-only code added |
| `GetTickCount64` confined to `NowMs()` | ✅ 1 occurrence, new line 2384 (`return GetTickCount64();`) |
| No order-send path can produce `SL = 0.0` | ✅ this change only selects **which price level a trigger fires from**; it never reaches stop-loss computation. `BrokerSafeExecutionSL()`, `ResolvedPresetStopPips()`, `InpRetryEntryWithoutSLOnReject` and the structural-stop path are byte-identical. A grep of the entire diff for `structuralSL` / `brokerSL` / `BrokerSafeExecutionSL` / `OrderSend` / `PositionModify` returns **zero** changed lines |
| `H4_SINGLE` loop byte-identical to V2.1a | ✅ V2.1b 3061–3068 vs V2.1a 2936–2943 — identical including the `for(int i=0;i<2;i++)` header. No comment was added above it precisely so this claim is exact |
| `LOW_RISK` block byte-identical to V2.1a | ✅ V2.1b 3043–3050 vs V2.1a 2918–2925 |
| `READY` block byte-identical to V2.1a | ✅ V2.1b 3052–3059 vs V2.1a 2927–2934 |
| Diff hunk count matches intent | ✅ exactly 11 hunks, each mapped in the inventory table above. No unintended edit anywhere in the file |
| New identifiers do not collide | ✅ `startIdx` (5 occurrences, all inside `ResolveZeroConfTriggerMap()`), `buyOuterOverride`/`sellOuterOverride` (4 occurrences, all inside `ProcessDirectZeroConfluenceTriggers()`), `InpZeroConfAllowCurrentMapTier` (9), `InpZeroConfIncludeLevel1` (5). No pre-existing symbol of any of those names |
| Inputs declared before first use | ✅ inputs at 1146 / 1168; earliest use at 2977 (`ResolveZeroConfTriggerMap()`) |
| `triggerCode` still captured into the CSV analytics row | ✅ all three capture points unchanged — see the CSV table above. Trigger-type attribution survives the 9→6 shrink |
| V2.1a confluence gate untouched | ✅ `ConfluenceGateAllows()`, `SessionConfluenceScore()`, `VolatilityRegimeScore()`, `ConfluenceScore()` and all their call sites appear in **no** diff hunk |
| Sweep/reclaim, exit geometry, sizing untouched | ✅ `ZeroConfM5SweepReclaim()`, `RefreshZeroConfM5ReclaimCache()`, `ConsiderZeroConfCandidate()`, `NearestClusterPartner()` and every trail/partial/ATR function appear in **no** diff hunk. `ConsiderZeroConfCandidate()`'s priority-then-distance selection is exactly as V2.1a left it |
| `.set` pair reproduces the two arms | ✅ `STAGE0_BASELINE` = both `true` (V2.1a nine-source ladder incl. the override right); `FULL` = both `false` (new six-source + H4_SINGLE, S2/D2-only). Both are load-on-top files listing only the V2.1b inputs, matching the V2.1a/V2.0 convention |
| Not committed to git | ✅ files written only; the brief said not to commit or push |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |

---

## What to look for in the A/B

Run `STAGE0_BASELINE` and `FULL` over the same period and compare **trade count first,
expectancy second**. The stage is a frequency-for-quality trade, so a lower trade count is
expected and is not by itself a failure.

Then slice the CSV by trigger type. Three specific falsification tests:

1. **Did CURRENT_MAP/CURRENT_OUTER actually take a disproportionate share in STAGE0?** If
   the priority-8 tier was only a few percent of fills, S01 changes almost nothing and any
   difference between the arms is noise from S02 or from run-to-run variance.
2. **Was the priority-8 tier's win rate actually worse?** The premise is that a live,
   re-deriving level near price is a weaker trigger than a frozen structural one. If the
   CURRENT rows in the STAGE0 CSV *outperform* the W1/D1 rows, S01 is removing the best
   source in the ladder and should be reverted before S02 is tuned.
3. **Was Level1 actually worse than Level2?** Bucket the STAGE0 zero-conf rows by trigger
   text into the inner and outer level. If S1/D1 rows carry a comparable win rate at
   materially higher frequency, S02 is pure frequency loss.

Also watch the **fill rate on the direct route specifically**. Removing CURRENT_OUTER's
carve-out means an already-waiting zero-conf setup now blocks the direct path
unconditionally, so some fills do not move to another trigger — they simply do not happen.
That interacts with S02, which already cuts the number of eligible W1/D1 levels in half.
Two independent frequency reductions stacking is the most likely way this build
under-trades; if it does, `InpZeroConfIncludeLevel1=true` alone is the natural intermediate
configuration and is a legitimate third arm even though no `.set` ships for it.

---

# S03 — sizing floor + deployment-gate instrumentation

**Added after S01–S02 as a separate patch.** `#property version` bumped `2.102` → `2.103`
(line **279**). File 16,073 → **16,276 lines**. One new input, eleven new counter globals,
one new function, twelve counter increments at existing call sites, **zero changed function
signatures**, 27 diff hunks.

This stage is not a strategy change and has no A/B hypothesis behind it. It exists because
the V2.2 BTC descendant of this file produced three consecutive Strategy Tester runs that
ended `READY=511, stored=54, deployed=0, LIVE=0` and **the journal could not say which gate
was responsible.** The same blind spot exists here, so the same fix is applied to both
files identically. The full diagnosis lives in `V2_2_BTCUSD_CHANGES.md` (S06); this section
documents what landed in V2.1b.

---

## S03(a) — `InpForceMinimumBaseSizing`

New input at line **492**, immediately after `InpBaseLayerLot`:

```
input bool   InpForceMinimumBaseSizing    = true;
```

`LotSizingCapitalUnits()` (lines **2062–2079**) previously had two bare returns. It now
assigns to a local and floors it before returning, so the floor applies to **both** branches
identically:

```
   double capital=InpUseBrokerNativeDepositUnitsForLots
                  ? MathMax(0.0,raw)
                  : MathMax(0.0,raw/MathMax(1.0,g_accountUnitDivisor));

   if(InpForceMinimumBaseSizing)
      capital=MathMax(capital,MathMax(1.0,InpBaseEquity));

   return capital;
```

An account below `InpBaseEquity` deposit units now sizes as if it had exactly
`InpBaseEquity`, instead of the base-layer target shrinking below `0.01` and rounding to a
volume the broker rejects.

### ⚠️ Polarity: defaults to `true`

**This is the third input in this file that defaults to the NEW behaviour**, joining
`InpZeroConfAllowCurrentMapTier` and `InpZeroConfIncludeLevel1`. It was requested that way
explicitly. `EzyMap_V2_1b_STAGE0_BASELINE.set` therefore pins it `false` to stay a true
control arm, and `EzyMap_V2_1b_FULL.set` lists it `true`.

At `InpBaseEquity` deposit units **or above, the two arms are arithmetically identical**, so
an A/B at any normal tester deposit will show no difference from this input alone. That is
the expected result, not a failed load.

### Proof it cannot weaken a real risk cap

This is the one way this change could be dangerous, so it was verified by grep rather than
assumed. **`LotSizingCapitalUnits()` has exactly four call sites in this file** (declaration
at 1986, definition at 2062):

| Line | Call site | What it does with the value | Risk-bearing? |
|---|---|---|---|
| **9058** | `AutoBaseLayerLot()` | `rawLot = InpBaseLayerLot * (sizingCapital/baseEquity)` — nominal base-layer target | no |
| **12174** | `ConfidenceSetupLot()` | `targetLot = lotPer100 * (sizingCapital/baseEquity)` — nominal confidence target | no |
| **15536** | `OnInit`, `BROKER-NATIVE LOT SIZING` log line | printed, and used to print a display-only `standardRawTarget` | no |
| **16086** | `OnTimer`, `LIVE PARITY STATUS` log line | printed as `lot targets S/G/Q=` | no |

**Every one is a nominal-lot-target calculation or a log line. None is a `$`-risk or
margin-percentage calculation.** Confirmed further:

- `CapSetupVolumeForCentSafety()` and `CapVolumeForStandardRiskGuard()` — the two real caps
  — **do not appear in that list**, i.e. they never call `LotSizingCapitalUnits()`. They read
  `AccountInfoDouble(ACCOUNT_EQUITY)` and call `OrderCalcProfit` / `OrderCalcMargin` against
  the actual account, and they still have final authority over every submitted volume.
- The `effectiveEquity < MinimumTradingEquity()` refusal at the top of **both**
  `AutoBaseLayerLot()` and `ConfidenceSetupLot()` tests `EffectiveAccountEquity()`, **not**
  the floored value. A genuinely under-funded account is still refused before the floor is
  ever consulted.
- `RiskPctForConfidence()`, `RiskPctForSetup()` and the `riskBudget = equity * pct/100`
  arithmetic all read `AccountInfoDouble(ACCOUNT_EQUITY)` directly.

The floor therefore moves the **nominal starting target only**. A maintenance note to this
effect, naming all four call sites, sits in the input's comment block (lines **462–491**) so
the audit does not have to be redone from scratch next time.

---

## S03(b) — deployment-gate breakdown instrumentation

### The blind spot being closed

`ConfluenceGateAllows()` has reported `g_stdAttempts`/`g_stdPassed`/`g_zcAttempts`/
`g_zcPassed` since V2.1a S01, and prints them at `OnDeinit` via `LogConfluenceFilterRate()`.
The three gates that sit **alongside** it on every deployment path had no counters at all:

| Gate | Why it can silently zero a run |
|---|---|
| `SpreadAllowed()` | compares `(ask-bid)/_Point` against `InpMaxSpreadPoints`. If the point convention is misjudged for the symbol, **every tick** fails before anything else runs |
| `TradingEnvironmentReady()` | returns `true` immediately under `MQL_TESTER`, so it cannot be the tester blocker — but it is a live-trading blocker and belongs in the same summary |
| `DailyRiskCapacityAvailable()` | a day lock latches and then rejects everything for the rest of the day |

There was no way to tell these apart in the journal. Guessing at better numbers without
that information just produces a fourth zero-trade run carrying no more information than
the first three, which is why this is the higher-priority half of S03.

### Eleven new counters (lines 2480–2490)

Declared directly beneath the existing V2.1a counters, same `long g_… = 0;` convention:

```
g_spreadRejectStd    g_spreadRejectZc    g_spreadRejectOther
g_envRejectStd       g_envRejectZc
g_capacityRejectStd  g_capacityRejectZc  g_capacityRejectOther
g_orderSendStd       g_orderSendZc       g_orderSendOther
```

All eleven are reset in `OnInit` at lines **15401–15411**, immediately after the existing
`g_stdAttempts=0;` block, so both summaries always describe the same run.

**Path split.** `STANDARD` and `ZERO-CONF` are the same two scored entry paths the
confluence line uses, so the two log lines can be read side by side. `OTHER` is the legacy
bridge-signal path (`ArmReadySignal()` → `PlaceOneLayer()`), which belongs to neither scored
path and so **cannot honestly be attributed to either** — it gets its own column rather than
an invented split. `TradingEnvironmentReady()` is never called from that path, which is why
the environment field has no `OTHER` column.

### Twelve increments, all at call sites

**No gate function was modified.** `SpreadAllowed()`, `TradingEnvironmentReady()`,
`DailyRiskCapacityAvailable()` and `LotSizingCapitalUnits()` keep their exact signatures and
bodies. Each counter is incremented at the **call site**, on the false branch only,
alongside whatever logging and `return` that site already performed. No control flow and no
existing log text was altered.

| Line | Enclosing function | Gate | Counter |
|---|---|---|---|
| **3320** | `SubmitDirectZeroConfMarket()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectZc` |
| **3327** | `SubmitDirectZeroConfMarket()` | `SpreadAllowed()` | `g_spreadRejectZc` |
| **3377** | `SubmitDirectZeroConfMarket()` | `TradingEnvironmentReady()` | `g_envRejectZc` |
| **3436** | `SubmitDirectZeroConfMarket()` | *(order send)* | `g_orderSendZc` |
| **3539** | `ProcessDirectZeroConfluenceTriggers()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectZc` |
| **11784** | `PlacePersistentLayer()` | `SpreadAllowed()` | `g_spreadRejectStd` |
| **11818** | `PlacePersistentLayer()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectStd` |
| **11901** | `PlacePersistentLayer()` | *(order send)* | `g_orderSendStd` |
| **12811** | `PersistentQualityPass()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectStd` |
| **13497** | `DeployAggressiveArmSetup()` | `DailyRiskCapacityAvailable()` | `g_capacityRejectStd` |
| **13533** | `DeployAggressiveArmSetup()` | `TradingEnvironmentReady()` | `g_envRejectStd` |
| **13802** | `DeployPersistentSetup()` | `TradingEnvironmentReady()` | `g_envRejectStd` |
| **14740** | `PlaceOneLayer()` *(legacy)* | `DailyRiskCapacityAvailable()` | `g_capacityRejectOther` |
| **14760** | `PlaceOneLayer()` *(legacy)* | *(order send)* | `g_orderSendOther` |
| **15029** | `ArmReadySignal()` *(legacy)* | `SpreadAllowed()` | `g_spreadRejectOther` |

Two of these needed braces added around a previously brace-less single-statement `return`
(lines **3539** and **14740**) — that is the whole of the `{}` +2 delta outside the new
function, and it changes no behaviour.

**Order-send counters.** No pre-existing global counted send attempts; `g_directZeroConf.attempts`
is a per-setup struct field, not a run total, so a new counter was added rather than a
duplicate of something existing. The increment sits **once** per submission, immediately
before the first `trade.Buy`/`trade.Sell`, so the "retry without SL on reject" second send
is deliberately **not** double-counted — the number means *deployments that reached the
broker*, not *packets sent*.

### Two new log lines at `OnDeinit`

New function `LogDeploymentGateBreakdown()` at lines **9901–9936**, placed immediately after
`LogConfluenceFilterRate()` and forward-declared at line **1919** beside it, matching the
existing convention. Called from `OnDeinit` at line **15997**, directly after the
`LogConfluenceFilterRate()` call:

```
V2.1b S03 DEPLOYMENT GATE BREAKDOWN | SPREAD REJECTED: n | ENVIRONMENT REJECTED: n | DAILY CAPACITY REJECTED: n | ORDER-SEND ATTEMPTS: n
V2.1b S03 DEPLOYMENT GATE BREAKDOWN BY PATH | SPREAD std/zc/other: n/n/n | ENVIRONMENT std/zc: n/n | DAILY CAPACITY std/zc/other: n/n/n | ORDER-SEND std/zc/other: n/n/n
```

**Deliberate deviation:** the brief specified one line. A second line carries the per-path
split, rather than widening the mandated line's fields, so the mandated string stays greppable
verbatim while the attribution is still available.

**Deliberately not suppressed by any input**, unlike `LogConfluenceFilterRate()`, which
returns early when `InpUseConfluenceScoring` is false. The reasoning is inverted here: a run
in which all four totals are zero is the single most informative outcome the line can
report — it means nothing ever *reached* these gates, so the blocker is upstream (no setups
armed, no touch registered, or an environment problem outside the EA). Suppressing that
would hide exactly the case the instrumentation was built for.

---

## `.set` file changes

| File | Change |
|---|---|
| `EzyMap_V2_1b_STAGE0_BASELINE.set` | `InpForceMinimumBaseSizing=false` added, with a note that this is the reversed-polarity control and that at ≥100 units it is arithmetically a no-op |
| `EzyMap_V2_1b_FULL.set` | `InpForceMinimumBaseSizing=true` added, plus the explanatory comment |

**Deviation:** the brief said `FULL.set` needed a comment but no new line, since `true` is
the compiled default. The line was added anyway because that file's own header states its
purpose is to make the intended values "explicit in the tester rather than implied", and
omitting the newest input would break exactly that. It sets the value it already has, so it
cannot change behaviour.

The gate-breakdown instrumentation has **no input and no rollback switch**. It prints in
both arms and changes no behaviour, so it does not compromise the control.

---

## S03 verification performed

| Check | Result |
|---|---|
| Brace / paren / bracket balance (tokenizer excluding strings, char literals, line and block comments) | ✅ `{}` 930/930 · `()` 6256/6256 · `[]` 1178/1178; residual stack 0, no mismatched pairs |
| Balance delta accounted for | ✅ `{}` **+3** = `LogDeploymentGateBreakdown()` body (1) + braces added around the two brace-less returns at 3539 and 14740 (2). `()` **+37** = the two `Log(` calls and their 15 `IntegerToString((int)…)` pairs (32) + new function definition, forward declaration and `OnDeinit` call (3) + net +2 from the `LotSizingCapitalUnits()` rewrite. `[]` **+0** |
| No existing function signature changed | ✅ machine-diffed the set of top-level signature lines old vs new: the **only** difference in either direction is the addition of `void LogDeploymentGateBreakdown()` and its forward declaration. `SpreadAllowed()`, `TradingEnvironmentReady()`, `DailyRiskCapacityAvailable()` and `LotSizingCapitalUnits()` are all unchanged in arity and in return type |
| `LotSizingCapitalUnits()` call sites re-counted after the edit | ✅ still exactly 4, at 9058 / 12174 / 15536 / 16086 — the change added no new call site. All four audited in the table above |
| No risk or margin cap consumes `LotSizingCapitalUnits()` | ✅ `CapSetupVolumeForCentSafety()` and `CapVolumeForStandardRiskGuard()` appear at no line in the call-site list. Both read `ACCOUNT_EQUITY` / `OrderCalcProfit` / `OrderCalcMargin` directly |
| No new `MQL_TESTER` branches | ✅ 13 raw grep hits, **unchanged** (pre-S03: 13, post-S03: 13). No tester-only code added |
| `GetTickCount64` still confined to `NowMs()` | ✅ 1 occurrence |
| New identifiers do not collide | ✅ none of the eleven `g_…Reject…`/`g_orderSend…` names, nor `InpForceMinimumBaseSizing`, nor `LogDeploymentGateBreakdown`, existed anywhere in the pre-S03 file |
| New globals declared before first use | ✅ declared at 2480–2490; earliest use at 3320 |
| Input declared before first use | ✅ input at 492; earliest use at 2075 |
| New function declared consistently with file convention | ✅ forward declaration at 1919 immediately beside `LogConfluenceFilterRate();`, definition at 9901 immediately after that function's body |
| Counters reset in `OnInit` | ✅ lines 15401–15411, in the same block as the V2.1a counters |
| MQL5 string handling | ✅ no reliance on implicit adjacent string-literal concatenation; every join uses explicit `+` |
| Diff hunk count matches intent | ✅ 27 hunks, no unintended edit |
| Every `.set` input name matches a real declaration | ✅ script-checked, not eyeballed: both V2.1b `.set` files parsed and every `Inp…` name resolved against an `input` declaration in the `.mq5`. No missing names, no duplicates, no unparsed lines |
| Identical patch applied to `EzyMap_V2_2_BTCUSD_ADAPTATION.mq5` | ✅ added lines from both diffs extracted and compared with the stage tag normalised: **byte-identical apart from the tag string, the header block and the version number** |
| Not committed to git | ✅ files written only |
| **Compiles in MetaEditor** | ❌ **not verified — no MQL5 toolchain in this environment** |

---

## What to do with the new line

Run whatever you were already running. At the end of the run, read the breakdown line
before anything else:

- **`ORDER-SEND ATTEMPTS` > 0** — the EA can deploy. Any shortfall in trade count is a
  filter, and the three rejection counts tell you which one to look at.
- **`ORDER-SEND ATTEMPTS` = 0 and one rejection count is large** — that gate is the blocker.
  Fix that input; do not touch the others yet.
- **All four are 0** — nothing ever reached these gates. The problem is upstream of them
  entirely: no setups armed, no touch registered, or an environment problem outside the EA
  (missing tester history, symbol not in Market Watch, algo trading off). Read the
  `SetDeploymentFailure` reasons in the journal rather than changing more inputs.

Read it alongside the existing `V2.1a CONFLUENCE FILTER RATE` line — between them the two
lines now cover every gate standing between a stored READY setup and an order send.

---

## S04 — Auto-calibrating spread cap (opt-in, off by default here)

Ported from the BTCUSD sibling (`EzyMap_V2_2_BTCUSD_ADAPTATION.mq5` S07), where three
static `InpMaxSpreadPoints` guesses in a row failed to produce a single trade on
BTCUSD.sc. `SpreadAllowed()` can now measure the symbol's own real spread for
`InpSpreadCalibrationTicks` ticks (filter inactive / fail-open while collecting) and lock in
`median(observed) * InpSpreadCalibrationMultiplier` as the enforced cap, clamped to
`InpMaxSpreadPoints` as an optional ceiling.

**On this (gold) lineage `InpAutoCalibrateSpreadCap` defaults `false`** — the ordinary
"new input reproduces old behaviour" rule, not the S03 polarity exception — because the
static value here has a working track record and this stage's whole premise doesn't apply
to it. With the input off, `SpreadAllowed()` takes the byte-identical pre-S04 branch. Turn
it on only if you ever see the same symptom (zero trades, spread suspected) on this file.

See the BTCUSD file's `V2_2_BTCUSD_CHANGES.md` S07 section for the full write-up, the
median-vs-mean reasoning, and the verification table — the code is byte-identical between
the two files apart from the log tag and this default.
