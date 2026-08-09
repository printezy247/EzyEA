//+------------------------------------------------------------------+
//| EzyMap Scalp Mastery V3.190                                      |
//| V3.176 base + exit geometry and entry timing refinement.         |
//| H4 SNR -> M15 HIGH RISK -> M3 reversal -> M5 READY -> CMP layers. |
//+------------------------------------------------------------------+
//                                                                    |
//  V3.190 STAGE SUMMARY (S01-S05)                                    |
//                                                                    |
//  Every stage is gated by its own input and every new input DEFAULTS |
//  to the V3.176 behaviour. Enabling one input at a time gives a      |
//  clean A/B without swapping binaries. Recommended values are stated |
//  in each input's comment.                                          |
//                                                                    |
//  S01 TRAIL ARM DECOUPLED FROM TRAIL DISTANCE                        |
//      V3.176 forced arm == trail distance (both 7 pips) whenever     |
//      InpLiveXAURequireFullTrailBeforeArm was true, so a trade had   |
//      to run ~+9-10 net before it could exit green and everything    |
//      peaking between +1 and +9 took the full -21. S01 adds an       |
//      independent arm threshold and a monotonic three-phase trail:   |
//      preset-only -> initial trail -> breakeven floor -> tight trail.|
//      InpLiveXAURequireFullTrailBeforeArm now clamps the ARM input   |
//      only; it no longer forces arm == trail.                        |
//      Inputs: InpTrailArmPips, InpTrailInitialDistancePips,          |
//              InpTrailTightenAtPips, InpTrailTightDistancePips,      |
//              InpUseBreakevenLock, InpBreakevenLockAtPips,           |
//              InpBreakevenLockOffsetPips                             |
//                                                                    |
//  S02 PARTIAL TAKE PROFIT                                            |
//      V3.176 submitted no TP at all, so any position that peaked and |
//      reversed gave back the whole excursion. S02 closes a share of  |
//      the volume at a fixed pip target and rides the remainder from  |
//      breakeven+offset. Closes route through the synchronized exit   |
//      path so they inherit its lock/retry handling, and a position   |
//      is only ever partialled once.                                  |
//      Inputs: InpUsePartialTakeProfit, InpPartialTPPips,             |
//              InpPartialTPPercent, InpBreakevenAfterPartial          |
//                                                                    |
//  S03 ATR-NORMALIZED GEOMETRY                                        |
//      Fixed 21/7 ignored that Asia-session gold ATR can be a third   |
//      of the New York figure. S03 derives stop/trail/arm from a      |
//      cached ATR handle refreshed once per M5 bar. Geometry is       |
//      FROZEN into the position's trail state at open so it cannot    |
//      drift mid-trade and break S01 monotonicity. Feeds the same     |
//      phase machine as S01 - the logic is not forked. Risk sizing    |
//      uses the ACTUAL stop distance for the setup rather than        |
//      InpPresetStopLossPips.                                         |
//      Inputs: InpUseATRGeometry, InpATRPeriod, InpATRTimeframe,      |
//              InpATRStopMultiplier, InpATRTrailMultiplier,           |
//              InpATRArmMultiplier, InpATRStopFloorPips,              |
//              InpATRStopCeilingPips, InpATRTrailFloorPips            |
//                                                                    |
//  S04 TOUCH CONFIRMATION BEFORE FILL                                 |
//      V3.176 filled on first touch of the zone. S04 records the      |
//      touch and waits for an M1 close back inside the zone, or for   |
//      price to stall beyond the touch extreme. Frequency is          |
//      preserved: if confirmation does not arrive inside the timeout  |
//      the setup deploys at market anyway and logs the fallback so    |
//      the confirmation miss rate is measurable.                      |
//      Inputs: InpRequireTouchConfirmation, InpTouchConfirmMode,      |
//              InpTouchStallSeconds, InpTouchStallMaxExtendPips,      |
//              InpTouchConfirmTimeoutSec                              |
//                                                                    |
//  S05 SCALE INTO STRENGTH                                            |
//      V3.176 could deploy many layers within a few pips of each      |
//      other, so a failed zone booked every one of them as a separate |
//      loss. S05 deploys a smaller initial layer count and only adds  |
//      further layers once the directional exposure is green by a     |
//      multiple of ATR. Setup frequency is unchanged; only the fill   |
//      count on losing zones drops. Added layers still pass through   |
//      normal volume/risk capping.                                    |
//      Inputs: InpScaleInOnConfirmation, InpInitialLayerCount,        |
//              InpScaleInTriggerATRMult, InpMaxScaleInLayers          |
//                                                                    |
//  V2.0 STAGE SUMMARY (S01-S05)                                       |
//                                                                    |
//  Incremental build on V3.190, not a rewrite. The version number     |
//  marks the routing-chain change. Every stage is gated by its own    |
//  input defaulting to V3.190 behaviour.                              |
//                                                                    |
//  S01 ROUTING CHAIN CORRECTION + H1 BIAS                             |
//      V3.190 ran confirmation AND trigger both on M5, so a fill      |
//      waited on the same bar that confirmed it - up to 5 minutes of  |
//      drift against a 21-pip stop. S01 keeps confirmation on M5 and  |
//      drops the TRIGGER to M1, which nests 5:1 inside M5. Adds an H1 |
//      EMA bias that SIZE-WEIGHTS counter-trend setups (mode 1)       |
//      rather than rejecting them, so frequency is unchanged.         |
//      READY lifetime is rescaled to the new trigger timeframe so the |
//      wall-clock expiry window does not shrink.                      |
//      Inputs: InpUseV2RoutingChain, InpUseH1BiasFilter,              |
//              InpH1BiasEMAPeriod, InpH1BiasMode,                     |
//              InpCounterTrendSizeMult                                |
//                                                                    |
//  S02 ZONE FRESHNESS  - touch count per zone drives size only.       |
//  S03 DEPARTURE SCORE - impulsiveness of the zone's origin leg.      |
//  S04 UNIFIED GRADE   - A/B/C from freshness+departure+bias, single  |
//                        consumer for both size and exit geometry.    |
//  S05 DISTAL STOPS    - stop at the zone's invalidation edge.        |
//                                                                    |
//  ROUTING NOTE: the M3 confirmation leg described in earlier specs   |
//  is DEAD CODE in this lineage. M3ReversalConfirmation() and         |
//  SelectM5ReadyZone() are defined but never called; the live signal  |
//  path runs H1 levels -> M15 zones -> M5 rejection/CHOCH -> CMP      |
//  touch. S01 is written against the code as it actually runs.        |
//                                                                    |
//  V2.1a STAGE SUMMARY (S01-S02)                                      |
//                                                                    |
//  Incremental build on V2.0. Adds two SCORED confluence sources that |
//  gate BOTH entry paths (the STANDARD structural path and the direct |
//  ZERO-CONF path) through one shared aggregator. Scores are 0.0-1.0  |
//  and are averaged, NOT ANDed, so the frequency cost is dial-able    |
//  with a single threshold instead of being all-or-nothing.           |
//  Every new input defaults to reproducing V2.0 exactly: the master   |
//  switch InpUseConfluenceScoring is false, so ConfluenceScore()      |
//  returns a neutral 1.0 and the gate never rejects anything.         |
//                                                                    |
//  S01 SESSION TIMING SCORE                                           |
//      V2.0 traded every hour of the broker day at the same           |
//      conviction. Gold's London/NY overlap and its Asia session are  |
//      not the same instrument. S01 classifies the broker server hour |
//      from TimeCurrent() (so the Strategy Tester's modelled clock is |
//      respected - TimeLocal()/TimeGMT() are deliberately NOT used)   |
//      into OVERLAP / LONDON / NY / ASIA / DEAD and scores it. The    |
//      detected tag is logged on every deployment attempt on both     |
//      paths so the broker server-time offset can be VERIFIED from    |
//      the log before any result is trusted.                          |
//      Inputs: InpUseConfluenceScoring, InpMinConfluenceScore,        |
//              InpScoreSession, InpLondonOpenHour, InpNYOpenHour,     |
//              InpNYCloseHour, InpSessionWeight,                      |
//              InpOverlapSessionScore, InpSingleSessionScore,         |
//              InpAsiaSessionScore, InpDeadZoneScore                  |
//                                                                    |
//  S02 VOLATILITY REGIME SCORE                                        |
//      A 21-pip stop is a different trade in a dead tape than it is   |
//      in a news spike, yet V2.0 measured neither. S02 percentile-    |
//      ranks the current closed-bar ATR against its own trailing      |
//      distribution and scores the regime. Too quiet or too wild both |
//      score low. InpHardBlockExtremeVol additionally blocks an       |
//      extreme reading outright on BOTH paths, as a gate DISTINCT     |
//      from the weighted score. The ATR handle is REUSED from the     |
//      V3.190 S03 geometry cache when the timeframe and period match; |
//      otherwise a second cached handle is created in OnInit and      |
//      refreshed once per bar, never per tick.                        |
//      Inputs: InpScoreVolatilityRegime, InpVolATRPeriod,             |
//              InpVolTimeframe, InpVolPercentileLookback,             |
//              InpVolLowPercentile, InpVolHighPercentile,             |
//              InpVolatilityWeight, InpVolNormalScore,                |
//              InpVolExtremeScore, InpHardBlockExtremeVol             |
//                                                                    |
//  GATE NOTE: there is NO single shared choke point between the two   |
//  entry paths. TradingEnvironmentReady() is reached by both but      |
//  returns true immediately under MQL_TESTER, so a gate hosted there  |
//  would be silently inert in every backtest; SpreadAllowed() is not  |
//  reached by the standard deployment path at all. The gate is        |
//  therefore called explicitly from three deployment entry points -   |
//  SubmitDirectZeroConfMarket(), DeployAggressiveArmSetup() and       |
//  DeployPersistentSetup() - which between them cover both paths      |
//  exactly once each. See V2_1a_CHANGES.md.                           |
//                                                                    |
//  V2.1b STAGE SUMMARY (S01-S02)                                      |
//                                                                    |
//  Incremental build on V2.1a. Scoped EXCLUSIVELY to the zero-        |
//  confluence TRIGGER SOURCE LADDER in ResolveZeroConfTriggerMap()    |
//  and to the directional exclusivity rule inside                     |
//  ProcessDirectZeroConfluenceTriggers(). No confluence-gate,         |
//  sweep/reclaim, exit-geometry or sizing code is touched.            |
//                                                                    |
//  POLARITY WARNING - READ THIS FIRST. Every earlier stage in this    |
//  file (V3.190 S01-S05, V2.0 S01-S05, V2.1a S01-S02) added inputs    |
//  that DEFAULT TO THE OLD BEHAVIOUR, so a freshly compiled binary    |
//  reproduced its base exactly. V2.1b REVERSES THAT CONVENTION.       |
//  BOTH new inputs default to the NEW, CHANGED behaviour:             |
//                                                                    |
//      InpZeroConfAllowCurrentMapTier = false -> tier REMOVED         |
//      InpZeroConfIncludeLevel1       = false -> Level1 EXCLUDED      |
//                                                                    |
//  Setting BOTH to true restores the V2.1a ladder in full. That is    |
//  what EzyMap_V2_1b_STAGE0_BASELINE.set does and it is the A/B       |
//  CONTROL. A default-valued V2.1b binary is NOT V2.1a-equivalent.    |
//                                                                    |
//  S01 CURRENT_MAP / CURRENT_OUTER TIER REMOVED                       |
//      V2.1a's ladder ended with two priority-8 candidates fed        |
//      from map.currentLevel1 / map.currentLevel2 - the LIVE          |
//      g_S1/g_S2 (g_R1/g_R2) pair, which re-derives as price          |
//      moves, rather than the frozen W1/D1/H4 levels the rest of      |
//      the ladder is built from. Because they re-derive they sit      |
//      near price by construction and win the nearest-distance        |
//      tie-break far more often than a priority-8 rank implies.       |
//      CURRENT_OUTER additionally carried a unique privilege: it      |
//      was the ONLY code allowed to fire while a zero-conf setup      |
//      for the same direction was already waiting, and on fill it     |
//      RETIRED every other waiting zero-conf setup in that            |
//      direction.                                                     |
//      S01 removes the tier from the ladder and removes that          |
//      override right with it - ONE switch, not two - leaving         |
//      W1_CLUSTER, W1_SINGLE, D1_H4_CLUSTER, D1_SINGLE, LOW_RISK      |
//      and READY as the scored sources, with H4_SINGLE still          |
//      present at priority 7 and completely unchanged.                |
//      The enum values and the ZeroConfTriggerCodeText() cases are    |
//      KEPT so the rollback input can restore the old ladder in       |
//      full and so any already-persisted setup still renders.         |
//      Inputs: InpZeroConfAllowCurrentMapTier                         |
//                                                                    |
//  S02 WEEKLY / DAILY TRIGGERS RESTRICTED TO LEVEL2 (S2 / D2)         |
//      map.w1Level1 / map.d1Level1 hold S1/D1 and map.w1Level2 /      |
//      map.d1Level2 hold S2/D2 - assigned in                          |
//      BuildCurrentZeroConfTriggerMap(). V2.1a made both eligible     |
//      in all four W1/D1 ladder loops, so the inner level, being      |
//      nearer price and touched far more often, took most of the      |
//      fills on the distance tie-break. S02 starts those four         |
//      loops at index 1, leaving only the OUTER level eligible.       |
//      H4 is deliberately NOT gated: the H4_SINGLE loop still runs    |
//      both levels, and h4[0]/h4[1] remain available as CLUSTER       |
//      PARTNERS for a W1 or D1 anchor. LOW_RISK and READY are not     |
//      level-indexed and are untouched.                               |
//      Inputs: InpZeroConfIncludeLevel1                               |
//                                                                    |
//  LADDER NOTE: ResolveZeroConfTriggerMap() is shared by BOTH         |
//  zero-conf routes - the DIRECT route (via                           |
//  ResolveDirectZeroConfTrigger(), live map) and the PERSISTENT-      |
//  SETUP fallback route (the CMP touch scan, frozen map). Both        |
//  stages therefore apply to both routes. Only S01's exclusivity      |
//  and retire-on-fill change is direct-route-only, because that       |
//  rule lives in ProcessDirectZeroConfluenceTriggers(). See           |
//  V2_1b_CHANGES.md.                                                  |
//                                                                    |
//  V2.2 BTC STAGE SUMMARY (S01-S11)                                   |
//                                                                    |
//  Incremental build on V2.1b. This is a PORTABILITY AND BUGFIX pass, |
//  not a strategy change. Scope: make the EA behave correctly on      |
//  BTCUSD and on the broker cent variant BTCUSD.sc, alongside its     |
//  existing XAUUSD tuning. No confluence gate, trigger ladder, exit   |
//  geometry phase machine or sizing choke point is touched.           |
//                                                                    |
//  POLARITY: this stage RETURNS to the pre-V2.1b convention. Every    |
//  new input DEFAULTS to reproducing V2.1b behaviour exactly, and     |
//  both code fixes (S01, S02) are no-ops on a gold chart by           |
//  construction, not by an input. A default-valued V2.2 binary on     |
//  XAUUSD is byte-identical in behaviour to V2.1b. See                |
//  V2_2_BTCUSD_CHANGES.md for the proof of that claim.                |
//                                                                    |
//  S01 NearGoldRoundNumber() MADE SYMBOL-AWARE  (real bug)            |
//      V2.0 S04 upgrades a zone's grade by one letter when the        |
//      proximal edge sits within InpRoundNumberTolerancePips of a $5  |
//      or $10 level. Those two levels were HARDCODED, with no symbol  |
//      guard at all. On BTC the tolerance evaluates to               |
//      5.0 * StrategyPipSize() = 5.0 * $1 = $5, which is exactly the  |
//      maximum possible distance from any price to the nearest        |
//      multiple of 10 - so the test was ALWAYS TRUE and every single  |
//      zone was silently promoted C->B or B->A. S01 scales the two    |
//      checked levels with the SAME per-symbol ladder that            |
//      g_brnStep / g_microStep already use (gold 100/50, BTC          |
//      1000/500, else price-relative), reduced one decade for the     |
//      grading test: gold 10/5, BTC 1000/500, else price-relative.    |
//      Gold resolves to the same 10.0/5.0 constants the old code had  |
//      literally written in, so XAUUSD grading is unchanged.          |
//      No new input. No signature change.                             |
//                                                                    |
//  S02 LIVE CENT PROTECTION PARITY EXTENDED TO BTC  (real bug)        |
//      IsLiveXAUUSDscProtectionChart() tested IsGold() BEFORE the     |
//      .SC / _SC / CENT suffix test, so the whole V3.164 live-cent    |
//      protection-parity feature (InpLiveXAUProtectionParity and its  |
//      five companions) silently never engaged on BTCUSD.sc, even     |
//      though ResolveAccountUnitDivisor() already treated that exact  |
//      symbol as a cent symbol. The gate is widened to               |
//      IsGold()||IsBTC(). The function name and all six input names   |
//      are DELIBERATELY UNCHANGED - they are referenced by name       |
//      across the file, in the .set files and in the V3.176 log       |
//      lines, and renaming buys no behaviour.                         |
//      Adds BTCUSD.sc; removes nothing from XAUUSD.sc.                |
//                                                                    |
//  S03 HIGHER-TIMEFRAME LEVEL DISTANCE FLOORS PROMOTED TO INPUTS      |
//      The minimum level-separation distances used when picking the   |
//      zero-confluence H4/D1/W1 levels, and the H1 map levels, were   |
//      hardcoded numeric literals inside two function bodies          |
//      (70.0 / 120.0 / 200.0 / 70.0 pips). On gold those are          |
//      $7 / $12 / $20 - sane. On BTC they are $70 / $120 / $200,      |
//      which is noise inside a single M5 candle, so every timeframe   |
//      collapses onto near-identical levels. They are now inputs so a |
//      BTC .set can retune them without a recompile.                  |
//      DEFAULTS EXACTLY REPRODUCE THE OLD LITERALS.                   |
//      Inputs: InpH4LevelMinDistancePips, InpD1LevelMinDistancePips,  |
//              InpW1LevelMinDistancePips, InpH1LevelMinDistancePips   |
//                                                                    |
//  S04 RUNTIME LOG / LABEL TEXT MADE INSTRUMENT-ACCURATE              |
//      Several OnInit log lines asserted "XAU" in text while printing |
//      a value that was already computed dynamically from             |
//      StrategyPipSize(). On a BTC chart those lines made a FALSE     |
//      claim about which instrument was being scaled, which defeats   |
//      the log-verification discipline V2.1a S01 depends on. A new    |
//      helper InstrumentLabel() renders XAU / BTC / _Symbol and is    |
//      substituted into the printed strings. COMMENTS ARE UNTOUCHED - |
//      they are historical record. InpTradeLevelGold is a DISPLAY     |
//      COLOUR named after the colour gold, not the instrument, and is |
//      deliberately left alone. DrawActualTradeLevelsGold() keeps its |
//      legacy name; its body was already symbol-generic.              |
//                                                                    |
//  S05 BTC SYMBOL PROFILE - NO CODE. See                              |
//      EzyMap_V2_2_BTCUSD_RECOMMENDED.set. Every number in that file  |
//      is an UNVALIDATED starting point: there is no MQL5 toolchain   |
//      and no BTC price history in the build environment, so nothing  |
//      in it has been backtested. It must be checked against the      |
//      live symbol's actual ATR, spread and contract size before use. |
//      The .set file and V2_2_BTCUSD_CHANGES.md both say so.          |
//                                                                    |
//  S06 SIZING FLOOR + DEPLOYMENT-GATE INSTRUMENTATION                 |
//      Diagnostic response to three BTCUSD.sc tester runs (at         |
//      100 / 1000 / 3000 deposit) that all ended                      |
//      READY=511, stored=54, deployed=0, LIVE=0.                      |
//                                                                    |
//      (a) SIZING FLOOR. InpForceMinimumBaseSizing (DEFAULT TRUE -    |
//          a deliberate polarity exception, same precedent as the     |
//          two V2.1b inputs above) floors LotSizingCapitalUnits()     |
//          at InpBaseEquity, so an account below 100 units still      |
//          sizes as if it had 100 instead of targeting a lot below    |
//          the broker minimum. This is a NOMINAL target floor only:   |
//          LotSizingCapitalUnits() has exactly four call sites -      |
//          AutoBaseLayerLot(), ConfidenceSetupLot() and two log       |
//          lines - and reaches NO risk or margin calculation. The     |
//          real caps (CapSetupVolumeForCentSafety() /                 |
//          CapVolumeForStandardRiskGuard()) read ACCOUNT_EQUITY and   |
//          OrderCalcProfit/OrderCalcMargin directly and still have    |
//          the final word, and the MinimumTradingEquity() refusal     |
//          still tests EffectiveAccountEquity(), unfloored.           |
//                                                                    |
//          NOTE: the floor did NOT cause the zero-trade runs. With    |
//          InpUseBrokerNativeDepositUnitsForLots=true a 100 deposit   |
//          already resolves to sizingCapital=100, so the base rule    |
//          lotPerHundred*(100/InpBaseEquity) already returned         |
//          exactly lotPerHundred. All three tested balances were at   |
//          or above the point this floor engages. See                 |
//          V2_2_BTCUSD_CHANGES.md for the arithmetic.                 |
//                                                                    |
//      (b) DEPLOYMENT-GATE BREAKDOWN. ConfluenceGateAllows() has      |
//          had pass/fail counters since V2.1a S01, but the three      |
//          gates beside it on every deployment path had none, so      |
//          there was no way to read from the journal whether the      |
//          spread filter, the trading-environment check or the        |
//          daily-risk lock was what zeroed a run. Counters are now    |
//          incremented AT THE CALL SITES of SpreadAllowed(),          |
//          TradingEnvironmentReady() and DailyRiskCapacityAvailable() |
//          on their false branches, plus one order-send attempt       |
//          counter, split STANDARD / ZERO-CONF / OTHER. The three     |
//          gate functions themselves are UNCHANGED - no signature,    |
//          no control flow, no existing log text.                     |
//          LogDeploymentGateBreakdown() prints the totals and the     |
//          per-path split at OnDeinit, beside the existing V2.1a      |
//          CONFLUENCE FILTER RATE line.                               |
//          No input gates this log: an all-zero breakdown is itself   |
//          the finding (nothing ever reached these gates).            |
//                                                                    |
//      Inputs: InpForceMinimumBaseSizing                              |
//                                                                    |
//      See also EzyMap_V2_2_BTCUSD_DIAGNOSTIC_FIRSTPASS.set, the      |
//      over-permissive profile for proving the EA can deploy at       |
//      all before re-enabling filters one at a time.                  |
//                                                                    |
//  S07 AUTO-CALIBRATING SPREAD CAP                                    |
//      InpMaxSpreadPoints is a flat "points" guess and three           |
//      straight zero-trade BTCUSD.sc runs survived ruling out          |
//      sizing, the environment gate (tester-safe) and daily risk       |
//      capacity - a mis-scaled static spread cap is the strongest      |
//      remaining suspect, since BTC's broker point convention          |
//      cannot be known ahead of time. SpreadAllowed() now measures     |
//      the symbol's own real spread for InpSpreadCalibrationTicks      |
//      ticks (filter INACTIVE / fail-open while collecting), then      |
//      sets the enforced cap to median(observed) *                     |
//      InpSpreadCalibrationMultiplier, clamped to InpMaxSpreadPoints   |
//      as an optional ceiling. Logs "SPREAD AUTO-CALIBRATION           |
//      COMPLETE" once locked in.                                       |
//      Inputs: InpAutoCalibrateSpreadCap (default TRUE here, FALSE     |
//              in the XAUUSD lineage), InpSpreadCalibrationTicks,      |
//              InpSpreadCalibrationMultiplier                          |
//                                                                    |
//      CORRECTION (found from the very next test run, same stage):    |
//      the ceiling was originally InpMaxSpreadPoints itself, which     |
//      silently clamped the calibrated cap straight back down to      |
//      the stale 120 default whenever no .set was loaded - the        |
//      user's own journal showed "calibrated cap=120.0" verbatim.     |
//      A broker reference (Vantage Markets) puts typical BTCUSD       |
//      spread at ~$15-17/unit, ~1500-1700 points on a 2-digit         |
//      symbol - 12-14x what that ceiling let through. The ceiling     |
//      is now its own input, InpSpreadCalibrationCeilingPoints        |
//      (default 0 = uncapped), fully decoupled from                   |
//      InpMaxSpreadPoints, which keeps its old meaning only in the    |
//      static (non-calibrating) branch.                               |
//      Inputs: InpSpreadCalibrationCeilingPoints                      |
//                                                                    |
//  S08 ATR-ADAPTIVE STOP/TRAIL GEOMETRY TURNED ON BY DEFAULT           |
//      A real test run at compiled defaults (spread gate now fixed,   |
//      312 deployed / 305 completed) came back with a 12% win rate    |
//      (56/403/69). InpUseATRGeometry was still false, so every       |
//      stop was a flat InpPresetStopLossPips=21 "strategy pip" -      |
//      and StrategyPipSize() is $1 for BTC (the file's own comment    |
//      only ever worked this out for XAU: "one strategy pip is 0.10   |
//      price"), so that is a flat $21 stop on a ~$65,000 symbol       |
//      with $10-40 of noise per single M5 candle. No code was        |
//      needed - V3.190's existing ATR geometry (built for gold's      |
//      Asia-vs-NY ATR swing) already derives stop/trail/arm from      |
//      live ATR instead of a frozen constant. Turned on by default    |
//      in THIS file only; V3.190/V2.1b keep it off (gold-proven       |
//      fixed-pip behaviour, not touched).                             |
//      InpATRStopCeilingPips raised 35 -> 500: the ceiling clamps     |
//      atrPips*multiplier, so a gold-sized ceiling left in place      |
//      would have silently re-imposed the same "too tight for BTC"    |
//      bug this stage exists to fix - the identical shape of bug      |
//      S07's spread ceiling had. 500 is a safety backstop (needs a    |
//      BTC M5 ATR above ~$312 to ever bind), not an everyday clamp.   |
//      Inputs: InpUseATRGeometry (default TRUE here, FALSE            |
//              elsewhere), InpATRStopCeilingPips (500.0, was 35.0)    |
//                                                                    |
//  S09 ZERO-CONFLUENCE FALLBACK NO LONGER MEANS ZERO CONFLUENCES       |
//      S08's ATR-adaptive stops did not move a second real test run's |
//      win rate (~12-14% on two different days) and the equity curve  |
//      was a smooth, steady grind - many small losses, not occasional |
//      big ones - which points at trade SELECTIVITY, not stop width.  |
//      ResolveMarketReadySignal() has a documented "V3.094 exception":|
//      required confluences drop to ZERO whenever this EA has 0 or 1  |
//      open positions, and a setup admitted that way also has its     |
//      touch-quality and position-count rechecks explicitly BYPASSED  |
//      at deployment (V3104_FORCE_ZERO_CONF_MARKET_EXECUTION). On     |
//      gold this fires rarely. On BTC, positions turn over fast (301  |
//      completed trades in 24h in the test that exposed this, one     |
//      every ~5 minutes), so exposure sits at 0-1 almost continuously |
//      and this "rare exception" is plausibly the DOMINANT path -     |
//      most entries getting no real quality bar at all.               |
//      FIX: the required-confluence value that low-exposure setups    |
//      get assigned is no longer hardcoded 0. Raising it above 0 is   |
//      sufficient on its own to route them through the NORMAL         |
//      deployment path instead of the bypass, because                 |
//      zeroConfluenceFallback=(requiredConfluences==0) downstream -   |
//      no other call site needed editing. WHICH setups can arm at     |
//      all is unchanged (buyCandidate/sellCandidate's admission test  |
//      does not read this value); only whether an admitted setup      |
//      still has to clear the normal quality gate changed.            |
//      Inputs: InpZeroConfFallbackMinConfluences (default 2)          |
//                                                                    |
//  S10 LOT MULTIPLICATION REMOVED - CONFIDENCE NOW MEANS LAYER COUNT   |
//      The user watched the live BTC chart double a lot on a single    |
//      order and asked for the tier system to express confidence as   |
//      NUMBER OF LAYERS, not per-layer SIZE: Standard = one instant    |
//      (MARKET), Good = one instant plus one limit, Quality = one     |
//      instant plus two limits - every layer the SAME flat lot.       |
//      ROOT CAUSE: ConfidenceSetupLot() picked a bigger lotPer100 for  |
//      Good/Quality (2x/3x Standard), producing a bigger TOTAL, and    |
//      DesiredLayersForSetup() ALSO gave that setup more layers to     |
//      split the bigger total across - two systems compounding. Worse,|
//      BuildAggressiveArmPlans's route-shrink logic could drop a      |
//      LIMIT route that failed to attach WITHOUT shrinking the total, |
//      dumping the whole un-split total onto the surviving route(s) - |
//      exactly the single doubled MARKET order observed live.         |
//      FIX: ConfidenceSetupLot() always returns the flat Standard lot |
//      now, regardless of confluence count (InpGoodSetupLotPer100/    |
//      InpQualitySetupLotPer100 are no longer read - kept as inputs   |
//      only so old .set files still load). Confidence is expressed    |
//      SOLELY through DesiredLayersForSetup()'s layer count, which     |
//      was already correct (1/2/3) and untouched. Every layer-builder |
//      (BuildConfidenceLayerPlans, BuildAggressiveArmPlans's route     |
//      loop, CreateMarketFallbackLayerSet) now assigns this SAME flat  |
//      lot to every layer instead of dividing one total across        |
//      however many layers/routes end up valid - a route that cannot  |
//      open now simply does not open, at no cost to the routes that   |
//      do, which also removes the doubling bug at its source.         |
//      Ported identically to EzyMap_V2_1b_TRIGGER_REFINED.mq5 (same   |
//      three functions, same reasoning) since the user asked for both.|
//      Inputs: none new. InpGoodSetupLotPer100/InpQualitySetupLotPer100|
//      remain declared but are no longer read by ConfidenceSetupLot().|
//                                                                    |
//  S11 EXIT MODIFY BACKOFF (real bug, found live)                     |
//      A full-day live run on BTCUSD.sc showed the broker rejecting   |
//      the same trailing-SL modify, on two tickets, roughly once per  |
//      second, continuously for the whole session ("Invalid stops"    |
//      every single time - see the "modify"/"failed modify" pairs in |
//      the Trades journal). ROOT CAUSE: FixedTrailSLBrokerValid(),    |
//      LatestBrokerValidExitSL() and BrokerTrailMinimumDistance()     |
//      each require only SYMBOL_TRADE_STOPS_LEVEL/FREEZE_LEVEL plus a |
//      small fixed 2-5 POINT cushion (InpExecutionStopCushionPoints/  |
//      InpTrailBrokerCushionPoints/InpExitExtraStopCushionPoints).    |
//      On XAUUSD that is a sane few-dollar buffer; on BTCUSD.sc it is |
//      a few CENTS - negligible - so if the broker's real enforced    |
//      minimum distance for this symbol is wider than what those two  |
//      symbol properties report (common for crypto CFDs), every       |
//      retry keeps failing forever with no correction. This is the    |
//      same risk category as the confirmed entry-spam incident that   |
//      cost real capital on a different EA - just applied to modifies |
//      instead of new orders, and throttled to ~1/sec instead of      |
//      100+/sec, but still a sustained, forever-failing, broker-      |
//      facing request pattern with no self-correction.                |
//      FIX: added a per-ticket consecutiveInvalidStops counter        |
//      (ExitExecutionState). Every rejection (broker OR the pre-send  |
//      validity check) widens the required clearance by               |
//      InpExitBackoffCushionStepPct% of the CURRENT PRICE (percentage,|
//      not a fixed point count, so it scales correctly on BTC's       |
//      $65,000 print and XAU's $2,000 print alike) and multiplies the |
//      retry cooldown, both capped (InpExitBackoffMaxSteps,           |
//      InpExitBackoffCooldownCapMs). Resets to zero the instant a     |
//      modify is accepted. Threaded through all three distance        |
//      functions plus the pre-filter gate in                          |
//      ManageHybridTrailingPositions() so every layer of the check     |
//      agrees. Defaults (0.02% per step, 8 step cap, 15s cooldown     |
//      cap) are a first attempt, not backtested - watch the new       |
//      "(backoff)" log lines on the next live run to see whether they |
//      actually clear the rejection or just slow it down.             |
//      Inputs: InpExitBackoffCushionStepPct, InpExitBackoffMaxSteps,  |
//      InpExitBackoffCooldownCapMs.                                   |
//                                                                    |
//  BASE NOTE: this file descends from the V3.176 line, NOT from the   |
//  separate V3.180 PARITY_HARDENED branch. It does not contain the    |
//  V3.180 P01-P13 parity fixes. NowMs() and TradeRetcodePartial()     |
//  here are V3.190 implementations, not the V3.180 originals. They    |
//  were never present in this lineage; they were not removed.         |
//+------------------------------------------------------------------+
#property copyright "EzyMap"
#property version   "2.206"

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_EZY_ACCOUNT_SCALE
{
   EZY_ACCOUNT_AUTO     = 0,
   EZY_ACCOUNT_STANDARD = 1,
   EZY_ACCOUNT_CENT     = 2
};

//------------------------------ Inputs ------------------------------
input int    InpDirectionHistory       = 48;
input int    InpSupportHistory         = 40;
input int    InpEntryHistory           = 24;
input int    InpSupportPivotBars       = 3;
input int    InpEntryPivotBars         = 2;
input bool   InpRequireDirectionalBody = false;
input double InpRejectionWickRatio     = 0.25;
input int    InpReadyExpiryBars        = 333;
input double InpConfluenceTolerancePips= 70.0;
input double InpMaximumZoneRangeATR     = 1.80;

input double InpScalpStopPips          = 20.0;
input double InpIntradayStopPips       = 35.0;
input double InpSwingStopPips          = 70.0;
input double InpScalpTargetMinPoints   = 15.0;
input double InpScalpTargetMaxPoints   = 80.0;
input double InpIntradayTargetMinPoints= 60.0;
input double InpIntradayTargetMaxPoints= 250.0;
input double InpSwingTargetMinPoints   = 180.0;
input double InpSwingTargetMaxPoints   = 800.0;
input double InpSnrFrontRunPips        = 10.0;

input bool   InpShowDirectionLevels    = true;
input bool   InpShowSupportingZones    = true;
input bool   InpShowEntryZone          = true;
input bool   InpShowDashboard          = true;
input bool   InpShowTradeCard          = true;
input bool   InpShowMonitoringCard     = true;
input bool   InpShowHistoricalMarkers  = true;
input int    InpMaxHistoricalMarkers   = 250;
input bool   InpEnableAlerts           = true;
input bool   InpAlertReady             = true;
input bool   InpAlertLive              = true;
input bool   InpAlertResult            = true;
input bool   InpPushNotifications      = false;

input color  InpBuyColor               = C'0,208,142';
input color  InpSellColor              = C'235,72,96';
input color  InpSupportColor           = C'52,211,176';
input color  InpResistanceColor        = C'237,185,58';
input color  InpPanelColor             = C'7,10,14';
input color  InpNeutralColor           = C'204,211,218';

//
// Premium MT5 presentation
//
input bool   InpApplyPremiumTheme       = true;
input bool   InpShowDrawingLabels       = true;
input bool   InpShowLowRiskSourceMarker = false;
input bool   InpShowLowRiskZones        = false;
input bool   InpLowRiskPreferNoOverlap  = true;
input bool   InpLowRiskUseChartCandles  = true;
input bool   InpShowBELevel             = true;
input bool   InpHideNativeTickerOHLC    = true;
input int    InpChartScale              = 3;
input double InpRightShiftPercent       = 22.0;

input color  InpChartBackground         = C'8,11,15';
input color  InpChartForeground         = C'176,185,195';
input color  InpBullCandleColor         = C'0,208,142';
input color  InpBearCandleColor         = C'235,72,96';
input color  InpBullWickColor           = C'70,220,172';
input color  InpBearWickColor           = C'245,105,125';
input color  InpPanelBorderColor        = C'56,65,76';
input color  InpPanelHeaderColor        = C'237,185,58';

input color  InpBuyHighRiskZoneColor    = C'18,74,61';
input color  InpBuyLowRiskZoneColor     = C'11,45,38';
input color  InpSellHighRiskZoneColor   = C'82,28,39';
input color  InpSellLowRiskZoneColor    = C'58,42,19';
input color  InpBEColor                 = C'126,137,150';
input color  InpTradeLevelGold         = C'255,215,0';


//
// Phase 2 automated execution — M5 chart.
// H4 SNR lines -> M15 overlap zone -> M3 reversal -> M5 READY.
//
input ulong  InpMagicNumber              = 2475176;

// REAL STANDARD + CENT ACCOUNT PROFILE FOR XAUUSD.sc.
// AUTO detects cent currency/server metadata and may use the live .sc suffix.
// Set EZY_ACCOUNT_STANDARD to force a real standard account even when the
// broker symbol is XAUUSD.sc. Set EZY_ACCOUNT_CENT to force a real cent account.
// AUTO tester mode defaults to STANDARD to prevent false division by 100.
// Broker-native displayed deposit units drive the per-100 lot rule:
// USD 600 -> 0.06 lot; USC 600 -> 0.06 cent-symbol lot.
// Risk and margin remain broker-native via OrderCalcProfit/OrderCalcMargin.
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor            = 100.0;
// Strategy Tester deposits are normally entered in standard account currency,
// even when the tested symbol carries a broker suffix such as .sc.
input bool   InpTesterAutoModeIsStandard          = true;
// On a live chart, .sc may identify the broker's cent symbol. Disable this
// only when the live account is definitely standard despite the suffix.
input bool   InpTreatSCSuffixAsCentOnLive         = true;
input bool   InpEnableCentSafetyCaps              = true;
input double InpCentMaxRiskPerSetupPct            = 5.00;
input double InpCentMaxMarginUsePct               = 25.0;
input double InpCentAbsoluteMaxLots               = 0.20;
// Live-cent execution may evaluate the broker minimum lot when proportional
// sizing falls below the symbol minimum. The minimum is never accepted blindly:
// OrderCalcProfit and OrderCalcMargin must satisfy the limits below.
input bool   InpAllowCentMinimumLotFallback       = true;
input double InpCentMinimumLotMaxRiskPct          = 5.00;
input double InpCentMinimumLotMaxMarginPct        = 25.0;
input double InpCentMinimumEffectiveEquity        = 1.0;
// LIVE-CENT EXECUTION PROFILE. When proportional volume is below
// the broker minimum, 0.01 is treated only as a candidate. It is
// accepted solely when broker-native risk and margin calculations
// remain inside the cent safety thresholds below. Tester sizing is
// unchanged because Strategy Tester AUTO mode remains STANDARD.
input bool   InpLiveCentBrokerMinimumExecution    = true;
input double InpLiveCentRawBalanceFloor           = 100.0;

// LIVE-CENT PARITY PROFILE. Broker-native lot volume is approved from the
// immediate 30-pip protection risk plus broker-calculated margin. This keeps
// cent-symbol lot scaling aligned with the displayed USC balance without
// allowing margin-only approval to bypass the real stop-distance risk.
input bool   InpLiveCentParityMode                 = true;
input bool   InpLiveCentMarginOnlyMinimumApproval  = true; // compatibility switch; validates 30-pip risk + margin
input double InpLiveCentMaximumMarginUsePct        = 25.0;
input int    InpLiveCentMaximumOpenPositions       = 26;
input bool   InpLiveCentMarketOnly                 = false;
input bool   InpResetExecutionStateOnAttach        = true;

// BROKER-NATIVE LOT SCALING.
// true: use the account's displayed deposit units for the per-100 rule.
//       USD 600 -> 0.06 lot; USC 600 -> 0.06 cent-symbol lot.
// false: legacy effective-USD conversion (USC divided by cent divisor).
// Balance is used by default so an open floating P/L does not unexpectedly
// reduce the next setup's intended account-tier lot.
input bool   InpUseBrokerNativeDepositUnitsForLots = true;
input bool   InpUseBalanceForLotSizing              = true;

// Percentage of CURRENT EQUITY allocated to the complete setup.
// Tightened risk band (was 25%-47% per setup): 1.5%-5% per setup.
// NOTE: these feed the legacy (InpAggressiveArmExecution=false) sizing path
// and RiskPctForSetup(). The default aggressive-arm path is capped instead by
// InpConfidenceLotRiskGuardPct via CapSetupVolumeForCentSafety(), which now
// applies to STANDARD accounts too (see CapVolumeForStandardRiskGuard()).
input double InpMaxRiskPct               = 5.0;
input double InpRiskPct_1Conf            = 1.50;
input double InpRiskPct_2Conf            = 1.50;
input double InpRiskPct_3Conf            = 2.00;
input double InpRiskPct_4Conf            = 3.00;
input double InpRiskPct_5Plus            = 4.00;

// SL distance modifies the confidence allocation, clamped to 1%-InpMaxRiskPct.
input double InpRiskTightSLBonusPct       = 5.00;
input double InpRiskWideSLPenaltyPct      = 7.00;
input double InpTightSLRatio              = 0.80;
input double InpWideSLRatio               = 1.35;

// Layering across the frozen READY rectangle.
input int    InpMinLayers                = 1;
input int    InpMaxLayers                = 3;
input int    InpMaxImmediateLayers       = 2;
input int    InpLayeringExpiryMinutes    = 30;

// Automatic account-scaled layering.
// $100 equity is the minimum trading account and corresponds to a 0.01-lot
// BASE layer. Larger accounts scale that base layer proportionally.
// Final layer count is still constrained by the setup's monetary risk budget.
input bool   InpAutoScaleLayerLot         = true;
input double InpMinimumAccountEquity      = 5.0; // keep $100 base sizing alive after small drawdown
input double InpBaseEquity                = 100.0;
input double InpBaseLayerLot              = 0.01;

// V2.1b S03 / V2.2 BTC S06: floor the lot-sizing TARGET at InpBaseEquity so an
// account below $100 (or 100 cent-units) still sizes as if it had $100, rather
// than the base-layer target shrinking below 0.01 and potentially rounding to
// a lot the broker rejects. This does NOT weaken real risk protection: the
// downstream broker-native caps (CapSetupVolumeForCentSafety() /
// CapVolumeForStandardRiskGuard(), both driven by OrderCalcProfit/
// OrderCalcMargin against the ACTUAL account equity/margin, not this floored
// number) still clamp the final size to what the real account can actually
// afford -- this floor only affects the NOMINAL starting target, never the
// final risk-checked size.
//
// VERIFIED at V2.1b S03 / V2.2 BTC S06 by full-file grep: LotSizingCapitalUnits()
// has exactly four call sites, none of them a $-risk or margin-percentage
// calculation --
//   1. AutoBaseLayerLot()       - nominal base-layer lot target
//   2. ConfidenceSetupLot()     - nominal confidence lot target
//   3. OnInit "BROKER-NATIVE LOT SIZING" log line   - display only
//   4. OnTimer "LIVE PARITY STATUS" log line        - display only
// Neither CapSetupVolumeForCentSafety() nor CapVolumeForStandardRiskGuard()
// calls it; both read AccountInfoDouble(ACCOUNT_EQUITY) and
// OrderCalcProfit/OrderCalcMargin directly. Also note the separate
// MinimumTradingEquity() gate inside AutoBaseLayerLot()/ConfidenceSetupLot()
// tests EffectiveAccountEquity(), NOT this floored value, so a genuinely
// under-funded account is still refused. If a future change makes any risk or
// margin cap consume LotSizingCapitalUnits(), STOP and re-audit this floor.
//
// Default TRUE per explicit user request -- this is a deliberate exception to
// the usual "new inputs default to old behaviour" rule, same precedent as
// V2.1b's two reversed-polarity rollback inputs. Set false to restore the old
// unfloored scaling for A/B comparison.
input bool   InpForceMinimumBaseSizing    = true;

// V2.002 confidence-based SETUP volume.
// These are TOTAL lots for the complete setup at $100 equity.
// Standard = 1 layer, Good = 2 layers, Quality = 3 layers.
// Larger accounts scale linearly from the $100 rule.
input bool   InpUseConfidenceLotSizing     = true;
input double InpStandardSetupLotPer100     = 0.01;
input double InpGoodSetupLotPer100         = 0.02;
input double InpQualitySetupLotPer100      = 0.03;
input int    InpGoodConfidenceMin          = 3;
input int    InpQualityConfidenceMin       = 5;

// V2.2 BTC S09: the "V3.094 exception" (see ResolveMarketReadySignal()) drops
// the required confluence count to ZERO whenever this EA has 0 or 1 open
// positions on the symbol - meant as a rare low-exposure fallback on gold.
// On BTC, positions turn over fast (a real test run completed 301 trades in
// 24 hours, roughly one every 5 minutes), so exposure sits at 0-1 almost
// continuously and this "exception" ends up being the DOMINANT path, not a
// rare one - every setup admitted through it also gets its touch-quality and
// position-count rechecks explicitly bypassed (see V3104_FORCE_ZERO_CONF_
// MARKET_EXECUTION), so effectively no quality bar applied to most entries.
// That, not stop width, is the leading explanation for a ~12-14% win rate
// that did not improve after S08's ATR-adaptive stops. This does not remove
// the low-exposure fallback (BTC still needs to be able to re-enter while
// flat) - it just requires a real confluence count instead of none. Default
// 2 matches the existing trend-following bar, so a counter-trend setup can
// still use the fallback with partial (but non-zero) confirmation, while a
// trend-following setup below its own 2-confluence bar can no longer use the
// fallback to skip that bar entirely.
input int    InpZeroConfFallbackMinConfluences = 2;

// Hard monetary-risk guard. Confidence lots are reduced if the frozen
// Entry->SL distance would otherwise exceed this percentage of equity.
// Tightened from 47.0. This now applies on STANDARD accounts too, via
// CapVolumeForStandardRiskGuard() inside CapSetupVolumeForCentSafety() -
// previously standard accounts had no percentage-of-equity cap at all.
input double InpConfidenceLotRiskGuardPct  = 5.0;

// Soft daily-volume objective for reporting only.
// The EA never invents a setup merely to reach these numbers.
input double InpDailyVolumeTargetMinLots   = 0.50;
input double InpDailyVolumeTargetMaxLots   = 1.50;

// V2.008 PARALLEL M5 FREQUENCY.
// Several valid M5 READY setups may wait simultaneously.
// Frequency increases by creating more independent setups,
// NOT by increasing the volume of any one setup.
input bool   InpAllowParallelWaitingReady   = true;
input int    InpMaxWaitingReadyPerDirection = 3;
input int    InpMaxTotalWaitingReady        = 5;
// V3.081 frequency governor: arm BUY and SELL independently when both are
// valid, but freeze at most one new setup per direction for each completed M5.
// This raises opportunity count without duplicating the same zone every tick.
input bool   InpArmBothDirectionsWhenValid  = true;
input bool   InpOneSetupPerDirectionPerM5   = true;

// Normal confluence-qualified entry tolerance.
// Zero-confluence fallbacks use their separate, wider profile below.
input double InpEntryTouchTolerancePips     = 5.0;

// V3.170 quality zero-confluence profile.
// The 9-pip tolerance applies only to zero-confluence trigger proximity and
// multi-timeframe level clustering. Entry requires a liquidity sweep followed
// by a reclaim on the latest completed M5 candle.
input double InpZeroConfTouchTolerancePips       = 9.0;
input double InpZeroConfClusterTolerancePips     = 9.0;
input bool   InpZeroConfRequireM5SweepReclaim    = true;
input int    InpZeroConfSweepLookbackM5          = 2;
input bool   InpZeroConfUseBidAskEnvelope        = true;
input bool   InpZeroConfUseTickPathCrossing      = true;
input int    InpZeroConfTouchRetrySeconds        = 30;
input int    InpZeroConfMaxDeployAttempts        = 15;

//========================= V2.2 BTC STAGE 3 =========================
// V2.2 BTC S3: minimum level-SEPARATION distance, in strategy pips, used
// when picking support/resistance levels for each timeframe. These four
// numbers were HARDCODED NUMERIC LITERALS inside two function bodies:
//
//   RefreshZeroConfHigherTimeframeLevels()  H4 70.0 / D1 120.0 / W1 200.0
//   CalculateMapAndMaybeReady()             H1 70.0
//
// They are not tolerances - they are the floor passed to
// PickDirectionLevels() as minimumDistance, i.e. how far apart two chosen
// levels must be before they count as two levels rather than one.
//
// The defaults below ARE the old literals, so a default-valued binary
// reproduces V2.1b exactly. They are inputs purely so a non-gold .set can
// retune them: on gold 70 pips is $7, on BTC (pip = $1 per
// StrategyPipSize()) the same 70 is $70, which is inside a single M5
// candle, so H4/D1/W1 would all collapse onto near-identical levels.
input double InpH4LevelMinDistancePips           = 70.0;
input double InpD1LevelMinDistancePips           = 120.0;
input double InpW1LevelMinDistancePips           = 200.0;
// V2.2 BTC S3: the H1 map separation literal was also 70.0, but it feeds a
// DIFFERENT consumer (the STANDARD-path g_S1/g_S2/g_R1/g_R2 map, not the
// zero-conf ladder), so it gets its own input rather than being aliased
// onto the H4 one. Default is the same 70.0 it always was.
input double InpH1LevelMinDistancePips           = 70.0;

// V3.171: use the same quality concepts in normal confluence-qualified routes.
// These bonuses affect entry qualification only. They do not increase the
// confidence value used by V3.168 balance/confidence lot sizing.
input bool   InpStandardUseMTFClusterQualification      = true;
input bool   InpStandardUseM5SweepReclaimQualification  = true;

// V2.009 PRECISE CMP EXECUTION.
// READY touch is detected from the symbol's CHART price (Bid or Last),
// matching what is visibly touching the rectangle. Actual BUY/SELL execution
// still uses the broker's executable Ask/Bid prices.
input bool   InpUseChartPriceForReadyTouch  = true;

// Once a legitimate chart CMP touch occurs, keep a short execution latch so
// a transient broker rejection / spread jump does not lose the signal.
input int    InpTouchRetrySeconds           = 15;
input int    InpMaxTouchDeployAttempts      = 7;

// V3.104 prevents OnTick/OnTimer from submitting the same touched setup
// repeatedly during the same tester/server moment. Forced zero-confluence
// entries retry indefinitely at this interval until MARKET is accepted.
input int    InpDeploymentRetryIntervalMs   = 500;

// The user's confidence lot is the target volume. Percentage risk may still
// be reported, but it does not silently shrink a valid 0.01/0.02/0.03 setup.
input bool   InpHonorConfidenceLotAtTouch   = true;

// If LIMIT/STOP geometry cannot be constructed at a real CMP touch,
// fall back to MARKET layers using the same total setup volume.
input bool   InpMarketFallbackOnTouch       = true;

// Small broker stop-distance cushion.
input int    InpExecutionStopCushionPoints  = 2;

// V2.009D AGGRESSIVE MARKET + LIMIT.
// The moment BUY/SELL READY is stored:
// 1) one MARKET route executes immediately,
// 2) retracement LIMIT route(s) are staged when broker-valid.
//
// Momentum STOP orders are removed from this aggressive branch.
//
// Total setup volume follows the original confidence sizing:
// $100 STANDARD = 0.01 total
// $100 GOOD     = 0.02 total
// $100 QUALITY  = 0.03 total
//
// The total confidence volume is divided across the valid Market/LIMIT
// routes. Standard normally uses Market only; Good uses Market + one
// LIMIT; Quality can use Market + two LIMIT levels.
input bool   InpAggressiveArmExecution        = true;
input bool   InpAggressiveRequireMarketFill   = false;
input bool   InpAggressivePlaceLimitRoute     = true;
// V3.026 duplicate protection: a READY rectangle may contain at most one
// EA LIMIT order for its direction. This check includes orders adjusted just
// outside the visual edge by the live broker-distance extension.
input bool   InpOneLimitPerReadyZone          = true;
input double InpLimitZoneDuplicateTolerancePips = 1.0;

// V3.081 directional exposure governor. Positions and pending entry orders
// reserve a layer slot so a later pending fill cannot push the direction
// above the cap. BUY and SELL capacity are independent. A slot is released
// automatically when its position closes or its pending order is cancelled.
input bool   InpEnforceDirectionalLayerCap       = true;
input int    InpMaxActiveLayersPerDirection      = 3; // tightened from 13
input bool   InpCountPendingAsReservedLayer      = true;
input bool   InpTrimExcessPendingToLayerCap      = true;

// V3.160 current floating-loss governor.
// BUY and SELL are independent. Once two EA positions in one direction
// have floating net P/L below zero, no new MARKET/LIMIT/STOP exposure is
// allowed in that direction. Existing positions remain managed normally.
input bool   InpEnforceDirectionalLosingCap      = true;
input int    InpMaxLosingPositionsPerDirection   = 2; // tightened from 3
input bool   InpCancelPendingAtLosingCap         = true;

// V3.160 current-M5 realised-loss governor.
// Count EA closing deals completed during the current M5 whose realised
// net P/L (profit + commission + swap + fee) is negative. BUY and SELL are
// combined. At two losing closes, all new entries are blocked until next M5.
input bool   InpEnforceM5ClosedLossCap             = true;
input int    InpMaxClosedNegativeEntriesPerM5      = 2;
input bool   InpCancelPendingAtM5ClosedLossCap      = true;

input double InpAggressiveLimitDepthPct       = 25.0;
// Real brokers may enforce a larger pending-order distance than Strategy Tester.
// Permit a live LIMIT route to sit just beyond the READY edge when that is the
// nearest broker-valid price. On XAU, 20 strategy pips = 2.00 price.
input double InpLiveLimitGeometryExtensionPips = 20.0;

// Execution controls.
// Spread filter enabled by default (was 0/disabled). 120 points is a starting
// guard for XAUUSD (~12 pips) meant to block news-driven spread blowouts while
// still allowing normal quoted spread through. Tune to your broker's typical
// spread plus headroom; set back to 0 to disable.
input int    InpMaxSpreadPoints          = 120;
// V2.2 BTC S07: three straight zero-trade test runs on BTCUSD.sc survived
// ruling out sizing, the environment gate (tester-safe: TradingEnvironmentReady()
// returns true unconditionally under MQL_TESTER) and daily risk capacity, which
// leaves a mis-scaled InpMaxSpreadPoints as the strongest remaining suspect -
// BTC's broker point convention (1, 2 or 3 digits) cannot be known when this
// file is written, so 120 (or even the BTC .set's widened 1200) is a guess that
// keeps turning out wrong. Rather than guess a fifth number, measure the
// symbol's OWN real spread for InpSpreadCalibrationTicks ticks after attach and
// derive the enforced cap from what is actually observed:
//   effective cap = median(observed spread) * InpSpreadCalibrationMultiplier
// clamped to InpMaxSpreadPoints as an optional ceiling when that input is > 0.
// WHILE CALIBRATING the filter is INACTIVE (fails open) so a slow calibration
// cannot itself reproduce the zero-trade bug - see SpreadAllowed(). Once
// calibration completes it is logged and locked for the rest of the run.
// Default TRUE here (three static guesses have failed); default FALSE in the
// XAUUSD lineage this was ported from, where the static value already has a
// working track record and must not be silently overridden.
//
// CORRECTION (same stage, found from the very next test run): the ceiling
// below used to be InpMaxSpreadPoints itself, which defeated the entire
// point of calibrating - a user running with no .set loaded still has
// InpMaxSpreadPoints=120, so "median * multiplier" got clamped straight back
// down to the same 120 the feature exists to get past. The journal from that
// run showed it happening verbatim: "current spread exceeds calibrated
// cap=120.0" - not a coincidence, the ceiling clamp landed exactly on the
// legacy default. A broker reference for BTCUSD CFDs (Vantage Markets) puts
// typical spread around $15-17/unit, which on a 2-digit-quoted symbol is on
// the order of 1500-1700 points - roughly 12-14x what that ceiling allowed
// through. The ceiling is now its OWN input, decoupled from
// InpMaxSpreadPoints (which keeps its old meaning, but only in the static/
// non-calibrating branch below).
input bool   InpAutoCalibrateSpreadCap      = true;
input int    InpSpreadCalibrationTicks      = 100;
input double InpSpreadCalibrationMultiplier = 3.0;
input int    InpSpreadCalibrationCeilingPoints = 0; // 0 = uncapped
input int    InpDeviationPoints          = 20;
input bool   InpUseAsyncMode             = false;
input bool   InpUseLimitStopLayers       = true;
input bool   InpPrintExecutionLog        = true;

// Safety.
input bool   InpOneBasketAtATime         = false; // V2.002 can manage multiple deployed M5 setups

// Persistent READY execution.
input bool   InpPersistentReadyMode        = true;
input int    InpMaxPersistentSetups        = 32;
input bool   InpKeepZoneVisibleWhileLive   = true;
input double InpLiveRR                     = 0.80; // final quick-win target

// v1.014 QUALITY-FREQUENCY.
// READY stays stored for 333 closed M5 candles.
// Orders are deployed only when price returns near the zone and quality re-confirms.
input bool   InpDelayedOrderDeployment        = true;
input double InpDeploymentApproachPips        = 0.0;

// Compatibility inputs retained for older SET files. The normal V3.081
// policy remains exactly 2 trend-following and 3 counter-trend confluences.
input int    InpTrendMinConfluences           = 2; // compatibility only
input int    InpCounterMinConfluences         = 3; // compatibility only

// V3.094 low-exposure exception.
// A valid mapped READY zone may arm with zero required confluences only while
// this EA has zero or one open position on the current symbol. Pending orders
// do not count as a running entry. The same position-count condition is
// checked again at CMP touch before deployment.
const bool   V3104_ZERO_CONFLUENCE_TOUCH_RULE = true;
const int    V3104_ZERO_CONF_MAX_OPEN_POSITIONS = 1;

// V3.170 zero-confluence zone trigger.
// HIGH-RISK is removed from direct zero-confluence execution.
// LOW-RISK is eligible only after a completed M5 sweep and reclaim.
const bool   V3170_ZERO_CONF_LOW_RISK_TOUCH_RULE = true;

// Additional V3.102 zero-confluence level trigger.
// BUY fallback stores the current S1 level; SELL fallback stores current R1.
// CMP touch of stored S1 -> BUY routing. Stored R1 -> SELL routing.
const bool   V3104_ZERO_CONF_S1_R1_TOUCH_RULE = true;

// V3.100 adds the outer support/resistance level trigger.
// BUY fallback stores S2; SELL fallback stores R2.
// CMP touch of stored S2 -> BUY routing. Stored R2 -> SELL routing.
const bool   V3104_ZERO_CONF_S2_R2_TOUCH_RULE = true;

// V3.104 has no zero-confluence fill limit per M5 candle.
// Once a zero-confluence trigger touches, execution remains latched until its
// MARKET route is accepted. Quality rechecks, retry expiry, attempt limits
// and current-M5 permanent-failure pauses no longer cancel that entry.
const bool   V3104_FORCE_ZERO_CONF_MARKET_EXECUTION = true;
const bool   V3104_ZERO_CONF_RETRY_UNTIL_FILLED = true;

// When no stored zero-confluence READY exists for a direction, V3.170
// evaluates READY, LOW-RISK, current-map H1, H4, D1 and W1 levels.
// Every direct zero-confluence trigger requires M5 sweep and reclaim.
const bool   V3104_ZERO_CONF_DIRECT_MAP_FALLBACK = true;

input bool   InpRequireCurrentM30Alignment    = true;
input bool   InpRequireM5ZoneStillValid       = true;

input int    InpM1QualityLookback             = 3;
input double InpTrendRejectionWickRatio       = 0.20;
input double InpCounterRejectionWickRatio     = 0.45;
input double InpQualityCloseStrength          = 0.55;
input double InpMomentumBodyFactor            = 1.05;

input bool   InpTrendRequireMomentumOrBreak   = true;
input bool   InpCounterRequireCHOCH           = true;

// Daily cap on successfully deployed layer orders.
input int    InpMaxLayerOrdersPerDay           = 0; // disabled; source signal controls frequency


//
// v1.015 REFINED M5 ROUTING
// H4  = support/resistance lines only.
// M15 = HIGH RISK candle zone physically overlapping an H4 S/R line.
// M3  = reversal confirmation inside that M15 HIGH RISK zone.
// M5  = READY signal candle rectangle.
// CMP touch of the frozen M5 rectangle releases layered entries.
//
input int    InpH4LevelHistory                 = 72;
input int    InpM15ZoneHistory                 = 48;
input int    InpM5ReadyHistory                 = 24;

// M3 confirmation controls. Default is rejection only.
// Users may enable CHOCH, engulfing and/or momentum and choose how many must agree.
input bool   InpM3UseRejection                 = true;
input bool   InpM3UseCHOCH                     = false;
input bool   InpM3UseEngulfing                 = false;
input bool   InpM3UseMomentum                  = false;
input int    InpM3MinConfirmations             = 1;
input int    InpM3Lookback                     = 8;
input int    InpM3StructureBars                = 3;
input double InpM3RejectionWickRatio           = 0.15;
input double InpM3CloseStrength                = 0.50;
input double InpM3MomentumBodyFactor           = 1.10;

// ACTIVE SIGNAL RECOVERY. These defaults prevent valid H1/M15 maps from
// producing zero READY signals because one strict M5 condition is missing.
input bool   InpActiveSignalMode                 = true;  // high-frequency signal recovery
input bool   InpAllowDirectionalM5Fallback       = true;
input bool   InpRequireZoneCorrectSide           = false;
input int    InpActiveMaxZoneRetests             = 8;
input int    InpActiveMinimumConfluences          = 0; // compatibility only; locked 2/3 policy overrides
input double InpDirectionalM5CloseStrength       = 0.50;
input bool   InpSignalDiagnostics                = true;

// Last-zone continuation campaign.
input bool   InpLatestZoneOnly                 = false; // source READY is frozen until touch/invalidation
input bool   InpLockDirectionAfterFirstSetup   = false; // do not override source BUY/SELL selection
input int    InpMaxCampaignSetupsPerDay        = 300; // effectively non-blocking
input int    InpMaxCampaignZoneRetests         = 8;

// Stop the campaign for the broker day after target/loss threshold.
input double InpDailyEquityTargetPct           = 0.0; // disabled; exits are trade-structure based

// V3.168 broker-day equity risk guard.
// A value of X means new entries stop when current account equity has dropped
// by X% from the broker-day starting equity (was 75 = a 75% drawdown allowed
// before the EA's own governor even reacts, effectively no real limit).
// Tightened to 10%. Set this BELOW whatever external daily-loss rule you are
// held to (broker/prop-firm), with margin, so this fires first.
// Percentage math is identical for standard USD and cent USC accounts; the
// cent divisor is never applied.
input double InpDailyLossStopPct               = 10.0;
input bool   InpCloseAllAtDailyTarget          = true;
// Was false: existing positions used to keep running (only pending orders were
// cancelled) once the daily-loss floor was hit. Now flattens everything at the
// floor so the internal governor actually stops the bleeding.
input bool   InpCloseAllAtDailyLossStop        = true;
input bool   InpCancelPendingAtDailyLossStop   = true;

// Take profit is disabled in V3.081. These inputs remain only for
// backward-compatible SET files and inactive legacy paths.
input bool   InpUseTakeProfit                  = false; // no take profit; exit by preset/trailing SL
input double InpStandardTakeProfitPips         = 0.0;
input double InpGoodTakeProfitPips             = 0.0;
input double InpQualityTakeProfitPips          = 0.0;
input double InpFixedTakeProfitPips            = 0.0;  // retained for compatibility; disabled

// Legacy R target inputs retained for compatibility with inactive routes.
// The active aggressive Market/LIMIT route does not use them for TP.
input double InpContinuationMinRR              = 0.60;
input double InpContinuationMaxRR              = 1.00;
input bool   InpUseStagedProfitTaking          = false;
input double InpLayer1TakeProfitR              = 0.35;
input double InpLayer2TakeProfitR              = 0.55;

// Preset protection. Every MARKET/LIMIT/STOP route first attempts to carry
// a visible broker SL exactly 30 strategy pips from its entry. If the broker
// rejects that SL with the opening request, the route used to be retried
// without any SL at all, leaving the position protected only by the
// tick-driven virtual trail (ManageHybridTrailingPositions) until it could
// install one - a real gap if a tick is missed, the terminal stalls, or the
// connection drops right after such a fill. Tightened to false: a rejected
// SL now skips that layer instead of opening it naked. No TP is used either way.
input double InpPresetStopLossPips          = 21.0;
input bool   InpRetryEntryWithoutSLOnReject = false;

// V3.176 broker/virtual protection with no TP, a 21-pip preset SL and a 7-pip trailing stop.
// A preset 21-pip SL is requested with every entry. No TP is submitted. The exact virtual
// SL remains active when broker stop-distance rules require adjustment.
// The initial exact virtual stop is InpPresetStopLossPips from entry, and the EA
// immediately attempts to install the closest broker-compatible SL.
// BUY  stop = best Bid - InpTrailingDistancePips * strategy pip
// SELL stop = best Ask + InpTrailingDistancePips * strategy pip
// On XAU, one strategy pip is 0.10 price; therefore SL21 is 2.10 price and trail7 is 0.70 price.
input bool   InpUseFixedPipTrail               = true;
input bool   InpEnableTrailingAfterEntry        = true;
input double InpTrailingActivationPips         = 0.0;
input double InpTrailingDistancePips           = 7.0;
input double InpTrailingStepPips               = 1.0;

//------------------------- V3.190 STAGE 1 ---------------------------
// V3.190 S1: arm threshold decoupled from trail distance.
// OLD BEHAVIOUR: the arm threshold was InpTrailingActivationPips (0), but
// LiveTrailActivationDistance() then forced it up to the FULL trail distance
// whenever InpLiveXAURequireFullTrailBeforeArm was true. With trail=7 that
// made arm=7, so a position had to run +7 (plus spread and commission, call
// it +9-10 net) before the trail could arm at all. Anything that peaked
// between +1 and +9 and turned over took the whole -21 preset stop. That
// bucket is the single largest population of losing trades.
// NEW: the arm threshold is its own input, and the trail runs a three-phase
// monotonic ratchet (initial -> breakeven floor -> tight).
// Defaults below reproduce V3.176 exactly (arm 7 = trail 7, no tighten
// because 999 is unreachable, no breakeven lock).

// V3.190 S1: favourable excursion required before the trail arms at all.
// Default 7.0 = V3.176. RECOMMENDED 4.0 - arms early enough that a modest
// runner can still be salvaged green.
input double InpTrailArmPips                   = 7.0;
// V3.190 S1: trail distance used from arming until InpTrailTightenAtPips.
// Default 7.0 = V3.176. RECOMMENDED 12.0 - a wider initial trail lets the
// trade breathe through normal retracement instead of scratching out.
input double InpTrailInitialDistancePips       = 7.0;
// V3.190 S1: favourable excursion at which the trail switches to the tight
// distance. Default 999.0 = unreachable, so V3.176 never tightens.
// RECOMMENDED 16.0.
input double InpTrailTightenAtPips             = 999.0;
// V3.190 S1: trail distance once InpTrailTightenAtPips is reached.
// Default 7.0 = V3.176. RECOMMENDED 7.0 - lock in the move once it is real.
input double InpTrailTightDistancePips         = 7.0;
// V3.190 S1: once the peak reaches InpBreakevenLockAtPips the stop may never
// again sit worse than entry +/- InpBreakevenLockOffsetPips. This is a FLOOR
// under the trail, not a replacement for it - the trail still ratchets past
// it. Default false = V3.176 (no breakeven concept at all).
// RECOMMENDED true.
input bool   InpUseBreakevenLock               = false;
// V3.190 S1: favourable excursion that triggers the breakeven floor.
input double InpBreakevenLockAtPips            = 9.0;
// V3.190 S1: how far beyond entry the breakeven floor sits, so a "breakeven"
// exit still covers spread and commission rather than closing at a small net
// loss.
input double InpBreakevenLockOffsetPips        = 1.0;

//------------------------- V3.190 STAGE 2 ---------------------------
// V3.190 S2: partial take profit.
// OLD BEHAVIOUR: no TP of any kind was submitted (InpUseTakeProfit was off
// and the fixed-TP inputs were all zero), so a position ran purely on the
// trail. Any trade that spiked and reversed handed the whole excursion back.
// NEW: bank a share of the volume at a fixed pip target and let the rest ride
// from breakeven+offset. Default false = V3.176 behaviour.

// V3.190 S2: master switch. Default false = V3.176 (no TP at all).
// RECOMMENDED true.
input bool   InpUsePartialTakeProfit           = false;
// V3.190 S2: favourable excursion at which the partial is taken.
input double InpPartialTPPips                  = 11.0;
// V3.190 S2: percentage of the position closed at the target. The remainder
// keeps running on the S01 trail. If the remainder would land below the
// broker volume minimum the FULL position is closed instead, so no
// unclosable stub is ever left behind.
input double InpPartialTPPercent               = 55.0;
// V3.190 S2: move the surviving remainder's stop to breakeven +
// InpBreakevenLockOffsetPips as soon as the partial fills, so the runner
// cannot turn a booked win into a loss.
input bool   InpBreakevenAfterPartial          = true;

//------------------------- V3.190 STAGE 3 ---------------------------
// V3.190 S3: ATR-normalized geometry.
// OLD BEHAVIOUR: stop and trail were fixed pip counts (21/7) regardless of
// conditions. Asia-session gold ATR can be a third of the New York figure, so
// the same 7-pip arm is unreachable in quiet hours while the same 21-pip stop
// sits inside the noise during news. NEW: derive the distances from ATR.
// Default false = fixed pips, byte-identical to S01.

// V3.190 S3: master switch. Default false = S01 fixed-pip geometry.
// RECOMMENDED true.
//
// V2.2 BTC S08: turned ON by default in this file only (V3.190/V2.1b keep
// false, the gold-proven fixed-pip behaviour). WHY: a real test run at the
// compiled defaults (InpUseATRGeometry=false, so a flat InpPresetStopLossPips
// = 21 "strategy pips") produced a 12% win rate (56 wins / 403 losses / 69
// flat out of 528 setups). StrategyPipSize() returns $1 for BTC (comment
// above literally documents "on XAU, one strategy pip is 0.10 price" - it
// was never re-derived for BTC's completely different absolute scale), so
// that 21-pip preset is a flat $21 stop on a symbol trading around $65,000
// with $10-40 of noise per single M5 candle - tight enough that ordinary
// noise, not a wrong signal, is the most likely explanation for the low win
// rate. ATR geometry already existed in this file for exactly this problem
// (built to handle gold's Asia-vs-NY ATR swing) and needed no new code, only
// turning on and rescaling its ceiling - see InpATRStopCeilingPips below.
input bool   InpUseATRGeometry                 = true;
input int    InpATRPeriod                      = 14;
input ENUM_TIMEFRAMES InpATRTimeframe          = PERIOD_M5;
// V3.190 S3: stop distance = ATR * this, clamped to the floor/ceiling below.
input double InpATRStopMultiplier              = 1.60;
// V3.190 S3: initial trail distance = ATR * this, floored by
// InpATRTrailFloorPips. The tight distance and the tighten-at threshold are
// scaled by the SAME ratio, which preserves the shape configured in S01
// rather than inventing separate ATR multipliers for them.
input double InpATRTrailMultiplier             = 0.55;
// V3.190 S3: arm threshold = ATR * this.
input double InpATRArmMultiplier               = 0.35;
input double InpATRStopFloorPips               = 12.0;
// V2.2 BTC S08: was 35.0 (gold-scaled). This is a CEILING, not the enforced
// value - ResolveATRGeometryPips() computes Clamp(atrPips*multiplier, floor,
// ceiling), so a gold-sized ceiling here would silently re-impose the exact
// same "stop too tight for BTC" bug this stage exists to fix, the same shape
// of bug S07's spread ceiling had. Raised generously so it acts as a genuine
// safety backstop against a runaway ATR reading, not an everyday clamp - a
// BTC M5 ATR would need to exceed roughly $312 (500/1.60) before this ever
// binds.
input double InpATRStopCeilingPips             = 500.0;
input double InpATRTrailFloorPips              = 5.0;

//------------------------- V3.190 STAGE 4 ---------------------------
// V3.190 S4: touch confirmation before fill.
// OLD BEHAVIOUR: the CMP logic deployed on the FIRST touch of the zone. On a
// 21-pip stop, entering 2-5 pips better is a material change in
// distance-to-stop. NEW: record the touch, then wait for either an M1 close
// back inside the zone or for price to stall beyond the touch extreme.
// Frequency is deliberately preserved - on timeout the setup deploys at
// market anyway rather than being skipped, and every fallback is logged so
// the confirmation miss rate is measurable.
// Default false = V3.176 fill-on-first-touch.

// V3.190 S4: master switch. RECOMMENDED true.
input bool   InpRequireTouchConfirmation       = false;
// V3.190 S4: 0 = either signal confirms, 1 = M1 close inside only,
// 2 = stall only.
input int    InpTouchConfirmMode               = 0;
// V3.190 S4: how long price must fail to extend before the stall path
// confirms.
input int    InpTouchStallSeconds              = 3;
// V3.190 S4: a move further than this beyond the running touch extreme counts
// as still extending, and restarts the stall clock.
input double InpTouchStallMaxExtendPips        = 2.0;
// V3.190 S4: give up waiting after this long and deploy at market anyway,
// which is exactly the V3.176 behaviour. Logged as a fallback.
input int    InpTouchConfirmTimeoutSec         = 45;

//------------------------- V3.190 STAGE 5 ---------------------------
// V3.190 S5: scale into strength instead of stacking on trigger.
// OLD BEHAVIOUR: up to InpMaxActiveLayersPerDirection layers could deploy in
// one direction within a few pips of each other. That is effectively one
// position at N x size, but it books N separate entries - so a zone that
// fails records N losses and the win rate reads as a rout.
// NEW: deploy a small initial layer count, and only add further layers once
// the directional exposure is actually green by a multiple of ATR.
// Setup FREQUENCY is unchanged - this only reduces the fill count on losing
// zones. Default false = V3.176 layering.

// V3.190 S5: master switch. RECOMMENDED true.
input bool   InpScaleInOnConfirmation          = false;
// V3.190 S5: layers deployed on the initial trigger.
input int    InpInitialLayerCount              = 1;
// V3.190 S5: the directional exposure must be green by this multiple of ATR
// before any additional layer is allowed. Falls back to the frozen preset
// stop distance when ATR geometry is unavailable.
input double InpScaleInTriggerATRMult          = 0.50;
// V3.190 S5: hard ceiling on how many layers may be ADDED beyond the initial
// count for one direction.
input int    InpMaxScaleInLayers               = 2;

//========================= V2.0 STAGE 1 =============================
// V2.0 S1: routing chain correction + H1 directional bias.
//
// OLD BEHAVIOUR (as actually wired in V3.190, see V2_0_CHANGES.md): the live
// chain is H1 levels -> M15 high-risk zones -> M5 for BOTH confirmation and
// trigger. Confirmation and trigger sharing one timeframe means the fill waits
// for the same M5 structure that confirmed it, so up to 5 minutes of drift can
// open up between confirmation and fill - on gold routinely 8-15 pips against
// a 21-pip stop.
//
// NEW: confirmation stays on M5, the TRIGGER moves down to M1. M1 nests
// cleanly inside M5 (5:1), so trigger and confirmation windows align on every
// confirmation bar instead of drifting.
//
// Both chains coexist. With InpUseV2RoutingChain=false the V3.190 chain runs
// completely unchanged.

// V2.0 S1: master switch for the corrected chain. RECOMMENDED true.
input bool   InpUseV2RoutingChain              = false;
// V2.0 S1: H1 directional bias filter. RECOMMENDED true.
input bool   InpUseH1BiasFilter                = false;
input int    InpH1BiasEMAPeriod                = 50;
// V2.0 S1: 0 = bias ignored, 1 = SIZE-WEIGHT counter-trend setups (they are
// still taken, at InpCounterTrendSizeMult), 2 = HARD FILTER counter-trend
// setups away. Mode 1 is the recommendation: mode 2 costs frequency, which is
// out of scope. Default 1 is inert while InpUseH1BiasFilter is false.
input int    InpH1BiasMode                     = 1;
// V2.0 S1: size multiplier applied to setups fighting the H1 bias in mode 1.
input double InpCounterTrendSizeMult           = 0.50;

//========================= V2.0 STAGE 2 =============================
// V2.0 S2: zone freshness tracking.
// OLD BEHAVIOUR: supply/demand probability decays sharply per touch - the
// resting orders that formed the zone get filled - yet V3.190 was configured
// to do the opposite. InpMaxTouchDeployAttempts=7 and InpReadyExpiryBars=333
// mean the EA re-enters the same zone repeatedly, systematically loading the
// LOWEST-probability touches at full size.
// NEW: count touches per zone and scale size down as the zone is worked.
// Freshness NEVER rejects a setup - frequency is unchanged, only size moves.
// Default false = V3.190 (every touch at full size).

// V2.0 S2: master switch. RECOMMENDED true.
input bool   InpTrackZoneFreshness             = false;
// V2.0 S2: touches beyond this all get the minimum multiplier.
input int    InpFreshnessMaxTouches            = 4;
input double InpTouch1SizeMult                 = 1.00;
input double InpTouch2SizeMult                 = 0.60;
input double InpTouch3SizeMult                 = 0.35;
input double InpTouch4PlusSizeMult             = 0.20;
// V2.0 S2: two zones are the same zone when their midpoints sit within this
// distance. Gold zones drift a little between refreshes of the H1/M15 map.
input double InpZoneIdentityTolerancePips      = 8.0;

//========================= V2.0 STAGE 3 =============================
// V2.0 S3: departure strength scoring.
// OLD BEHAVIOUR: zone quality was never measured against how price LEFT the
// zone when it formed. A zone that price crawled away from and one it was
// launched out of were sized identically, even though the impulsive
// departure is the one that signals real resting interest.
// NEW: score the origin leg once, at zone formation, and freeze it.
// Default false = V3.190 (no departure measurement).

// V2.0 S3: master switch. RECOMMENDED true.
input bool   InpScoreDepartureStrength         = false;
// V2.0 S3: how many bars of the departure leg to measure.
input int    InpDepartureLookbackBars          = 6;
// V2.0 S3: departure range / base range at or above this scores 1.0 on the
// range component; at or below InpWeakDepartureRatio it scores 0.0.
input double InpStrongDepartureRatio           = 3.0;
input double InpWeakDepartureRatio             = 1.5;
input double InpStrongDepartureSizeMult        = 1.00;
input double InpModerateDepartureSizeMult      = 0.70;
input double InpWeakDepartureSizeMult          = 0.40;

//========================= V2.0 STAGE 4 =============================
// V2.0 S4: unified A/B/C zone grade.
// OLD BEHAVIOUR: S02 and S03 each produced their own size multiplier. Even
// taking the least-favourable rather than the product, two independent knobs
// are hard to reason about and cannot express "this zone deserves a different
// EXIT", only a different size.
// NEW: fold freshness, departure and H1 alignment into ONE grade that is the
// SINGLE consumer - it replaces the individual multipliers rather than
// stacking on them - and let that grade drive size AND exit geometry.
// Default false = the S02/S03 multipliers stay in charge.

// V2.0 S4: master switch. RECOMMENDED true.
input bool   InpUseZoneGrading                 = false;
input double InpGradeASizeMult                 = 1.00;
input double InpGradeBSizeMult                 = 0.60;
input double InpGradeCSizeMult                 = 0.30;
// V2.0 S4: grade-differentiated partial TP, overriding InpPartialTPPips from
// V3.190 S02. A-grades are given room; C-grades book fast.
input double InpGradeAPartialTPPips            = 16.0;
input double InpGradeBPartialTPPips            = 11.0;
input double InpGradeCPartialTPPips            = 7.0;
// V2.0 S4: grade-differentiated trail, as a multiple of the V3.190 S01/S03
// base trail distance.
input double InpGradeATrailMult                = 1.40;
input double InpGradeBTrailMult                = 1.00;
input double InpGradeCTrailMult                = 0.70;
// V2.0 S4: gold respects round numbers. A zone whose proximal edge sits
// within this distance of a $5 or $10 level is upgraded one step (C->B or
// B->A). Upgrade only - it can never downgrade a zone.
// V2.2 BTC S1: the $5/$10 pair is the GOLD case only. NearGoldRoundNumber()
// now scales the checked levels per symbol (BTC $500/$1000, other symbols
// price-relative), so this tolerance is no longer wide enough to match
// every possible price on a five-figure instrument.
input double InpRoundNumberTolerancePips       = 5.0;

//========================= V2.0 STAGE 5 =============================
// V2.0 S5: supply/demand distal-edge stops.
// OLD BEHAVIOUR: the stop was a fixed 21 pips, or an ATR multiple under
// V3.190 S03. Neither is tied to where the zone is actually INVALIDATED - a
// stop can sit inside the zone it is trading, so ordinary rotation inside the
// zone stops the trade out on a thesis that has not failed.
// NEW: place the stop just beyond the zone's distal edge, which is the price
// at which the zone premise is genuinely wrong.
// Default false = V3.190 stop selection.

// V2.0 S5: master switch. RECOMMENDED true.
input bool   InpUseZoneDistalStops             = false;
input double InpDistalStopBufferPips           = 3.0;
input double InpDistalStopMinPips              = 10.0;
input double InpDistalStopMaxPips              = 30.0;
// V2.0 S5: when the zone is so wide that its distal stop would exceed
// InpDistalStopMaxPips, fall back to the V3.190 ATR/fixed stop rather than
// clamping. A zone that wide is a different setup and must be SIZED as one -
// clamping would silently under-stop it while sizing as if the stop held.
input bool   InpFallbackToATRStop              = true;

//========================= V2.1a STAGE 1 ============================
// V2.1a S1: session timing confluence score.
//
// OLD BEHAVIOUR: V2.0 deployed with identical conviction at 03:00 and at
// 14:00 server time. On gold those are not the same instrument - the
// London/NY overlap carries the participation that makes a 21-pip stop
// meaningful, while the post-NY-close gap is a spread-widening liquidity
// hole. Nothing in V2.0 measured the clock.
//
// NEW: classify the broker server hour into OVERLAP / LONDON / NY / ASIA /
// DEAD and turn that into a 0.0-1.0 SCORE. The score is fed into a shared
// weighted aggregator (ConfluenceScore()) together with the V2.1a S2
// volatility score; a setup deploys only when the aggregate clears
// InpMinConfluenceScore. Scoring rather than boolean filtering is what
// keeps the frequency cost dial-able from one input.
//
// The classification is computed from TimeCurrent(), NEVER TimeLocal() or
// TimeGMT(), so the Strategy Tester's modelled clock is honoured and the
// tester and the live account classify identically.
//
// Default false = V2.0 behaviour exactly: ConfluenceScore() returns a
// neutral 1.0, the gate cannot reject, and nothing is logged.

// V2.1a S1: MASTER SWITCH for the whole confluence engine - shared with
// V2.1a S2. While false neither scored source is consulted, the gate is a
// pass-through, and behaviour is byte-identical to V2.0. RECOMMENDED true.
input bool   InpUseConfluenceScoring           = false;
// V2.1a S1: shared deployment threshold. The weighted average of the ACTIVE
// scored sources must be >= this to deploy on either path. Tune in
// backtest: 0.45 is a starting point, not a validated value. RECOMMENDED
// tune - raise it to trade less and better, lower it to keep frequency.
input double InpMinConfluenceScore             = 0.45;
// V2.1a S1: enable the session score as one source of the aggregate.
// RECOMMENDED true.
input bool   InpScoreSession                   = false;
// V2.1a S1: BROKER SERVER TIME, not your wall clock. Most European brokers
// run GMT+2/+3, which puts the London open at 09:00/10:00 server rather
// than 08:00. VERIFY the offset on your live account from the session tag
// printed on every deployment attempt before trusting any result.
// RECOMMENDED verify then set.
input int    InpLondonOpenHour                 = 8;
// V2.1a S1: broker server hour of the New York open. RECOMMENDED verify.
input int    InpNYOpenHour                     = 13;
// V2.1a S1: broker server hour of the New York close. RECOMMENDED verify.
input int    InpNYCloseHour                    = 21;
// V2.1a S1: weight of the session score inside the aggregate. Set 0 to keep
// the source computed and logged but excluded from the average.
// RECOMMENDED 1.0.
input double InpSessionWeight                  = 1.0;
// V2.1a S1: score for the London/NY overlap - the highest-participation
// window for gold. RECOMMENDED 1.00.
input double InpOverlapSessionScore            = 1.00;
// V2.1a S1: score for London-only or NY-only hours. RECOMMENDED 0.65.
input double InpSingleSessionScore             = 0.65;
// V2.1a S1: score for the Asia session. RECOMMENDED 0.35.
input double InpAsiaSessionScore               = 0.35;
// V2.1a S1: score for the dead zone - the first V21A_DEAD_ZONE_HOURS after
// the New York close, before Asia liquidity arrives. RECOMMENDED 0.15.
input double InpDeadZoneScore                  = 0.15;

//========================= V2.1a STAGE 2 ============================
// V2.1a S2: volatility regime confluence score.
//
// OLD BEHAVIOUR: V3.190 S03 already SIZES geometry off ATR, but nothing
// ever asked whether the current regime is one worth trading at all. A dead
// tape never reaches the trail arm, and a news spike blows through a
// structural stop before the zone has a chance to work. Both are taken at
// full conviction in V2.0.
//
// NEW: percentile-rank the current CLOSED-bar ATR against its own trailing
// distribution and score the regime. An absolute ATR threshold would need
// re-tuning for every symbol and every era; a percentile is self-normalising
// and stays meaningful as gold's baseline volatility drifts.
//
// Two independent mechanisms:
//   - the SCORE feeds the shared weighted aggregate (dial-able), and
//   - InpHardBlockExtremeVol is a separate HARD veto that blocks the entry
//     outright on both paths regardless of the aggregate. It is deliberately
//     NOT folded into the score: "too wild to trade" is a different claim
//     from "slightly below the confluence bar".
//
// Default false = V2.0: no ATR is read, no handle is created, no gate.

// V2.1a S2: master switch for the volatility source. RECOMMENDED true.
input bool   InpScoreVolatilityRegime          = false;
// V2.1a S2: ATR period for the regime measurement. When this AND
// InpVolTimeframe both match the V3.190 S03 geometry ATR inputs, the
// EXISTING cached handle is reused rather than opening a duplicate.
input int    InpVolATRPeriod                   = 14;
input ENUM_TIMEFRAMES InpVolTimeframe          = PERIOD_M5;
// V2.1a S2: how many closed bars of ATR history the percentile is ranked
// against. Long enough to span more than one session cycle, short enough to
// still track a regime change.
input int    InpVolPercentileLookback          = 500;
// V2.1a S2: at or below this percentile the tape is too quiet to reach the
// trail arm. RECOMMENDED 20.0.
input double InpVolLowPercentile               = 20.0;
// V2.1a S2: at or above this percentile the tape is too wild for a
// structural stop. RECOMMENDED 90.0.
input double InpVolHighPercentile              = 90.0;
// V2.1a S2: weight of the volatility score inside the aggregate. Set 0 to
// keep the source computed and logged but excluded from the average.
// RECOMMENDED 1.0.
input double InpVolatilityWeight               = 1.0;
// V2.1a S2: score for a percentile between the two bounds. RECOMMENDED 1.00.
input double InpVolNormalScore                 = 1.00;
// V2.1a S2: score for a reading outside either bound. RECOMMENDED 0.15.
input double InpVolExtremeScore                = 0.15;
// V2.1a S2: when true an extreme reading BLOCKS the entry outright on both
// paths, independently of the weighted score. RECOMMENDED true - the score
// alone can be outvoted by a strong session, which is not the intent for a
// tape that is genuinely untradeable.
input bool   InpHardBlockExtremeVol            = false;

//========================= V2.1b STAGE 1 ============================
// V2.1b S1: the zero-confluence CURRENT_MAP / CURRENT_OUTER trigger tier.
//
// OLD BEHAVIOUR: ResolveZeroConfTriggerMap() ended with two priority-8
// candidates built from map.currentLevel1 / map.currentLevel2 - the LIVE
// g_S1/g_S2 (g_R1/g_R2) pair, which re-derives as price moves. That is a
// different kind of level from the frozen W1/D1/H4 map the rest of the
// ladder is built from: because it re-derives it sits near price by
// construction, so it wins the nearest-distance tie-break inside
// ConsiderZeroConfCandidate() far more often than a priority-8 rank implies.
// CURRENT_OUTER also held a unique privilege in
// ProcessDirectZeroConfluenceTriggers(): it was the ONLY code permitted to
// fire while a zero-conf setup for the same direction was already waiting,
// and on fill it retired every other waiting zero-conf setup in that
// direction.
//
// NEW: the tier is not populated, so it can never be chosen, and the
// override right does not exist. The already-waiting rule becomes
// unconditional and H4_SINGLE (priority 7) is the last scored source.
//
// NOTE THE REVERSED POLARITY. Unlike every earlier stage in this file,
// FALSE is the NEW behaviour and TRUE is the old one.
//
// true  = restore the V2.1a CURRENT_MAP/CURRENT_OUTER tier AND its
//         directional override and retire-on-fill right. A/B CONTROL ONLY.
// false = V2.1b behaviour: the tier is fully excluded from the ladder.
input bool   InpZeroConfAllowCurrentMapTier    = false;

//========================= V2.1b STAGE 2 ============================
// V2.1b S2: restrict the W1 and D1 trigger sources to the OUTER level.
//
// OLD BEHAVIOUR: all four W1/D1 ladder loops ran i = 0..1, so both
// w1Level1/d1Level1 (S1/D1) and w1Level2/d1Level2 (S2/D2) were eligible.
// The inner level is nearer price and is touched far more often, so it took
// most of the fills on the distance tie-break - a strictly worse location
// for a zero-CONFLUENCE entry, which has no structural confirmation behind
// it and needs the level itself to carry the trade.
//
// NEW: those four loops start at index 1, so only the OUTER level (S2/D2)
// can trigger. H4_SINGLE is NOT affected - both H4 levels stay eligible -
// and h4[0]/h4[1] remain usable as cluster PARTNERS for a W1 or D1 anchor.
// LOW_RISK and READY are not level-indexed and are untouched.
//
// NOTE THE REVERSED POLARITY. Unlike every earlier stage in this file,
// FALSE is the NEW behaviour and TRUE is the old one.
//
// true  = restore V2.1a Level1 (S1/D1) eligibility. A/B CONTROL ONLY.
// false = V2.1b behaviour: only Level2 (S2/D2) is eligible on W1 and D1.
input bool   InpZeroConfIncludeLevel1          = false;

// V3.164 live XAUUSD.sc protection parity.
// Account denomination affects money and lot sizing, never price distance.
// Historical M1 highs/lows cannot arm a trail immediately after attaching
// the EA to a real XAUUSD.sc chart. The live trail first requires one full
// trailing distance plus spread/cushion and a short warmup.
input bool   InpLiveXAUProtectionParity              = true;
input bool   InpLiveXAUDisableHistoricalPeakRebuild  = true;
input bool   InpLiveXAURequireFullTrailBeforeArm     = true;
input bool   InpLiveXAUIncludeSpreadInTrailArm       = true;
input int    InpLiveXAUTrailWarmupSeconds            = 15;
input int    InpLiveXAUExtraProtectionCushionPoints  = 2;

input bool   InpUseVirtualTrailFallback        = true;
input bool   InpReconstructTrailFromM1         = true;
input int    InpVirtualTrailCloseDeviationPts  = 30;
input int    InpTrailBrokerCushionPoints       = 2;

// V3.175 synchronized live exit execution.
// One accepted close request owns the ticket until its closing deal arrives
// or the lock times out. Broker-SL retries are throttled after Invalid stops.
input bool   InpSynchronizeExitRequests          = true;
input int    InpExitCloseLockTimeoutMs           = 5000;
input int    InpExitModifyMinimumIntervalMs      = 300;
// Shortened from 1200ms: a shorter cooldown means a broker SL install that was
// rejected (e.g. a naked/unprotected fill) gets retried sooner, shrinking the
// window where the position has no broker-side stop at all.
input int    InpExitInvalidStopsCooldownMs       = 500;
// Widened from 2/default cushion by +2 points beyond stops/freeze level so the
// SL install is more likely to be accepted on the first attempt instead of
// being rejected and falling back to the (now disabled) no-SL retry.
input int    InpExitExtraStopCushionPoints       = 5;
input bool   InpExitLogFillSlippage              = true;

// EXIT MODIFY BACKOFF - added after a real live run on BTCUSD.sc showed the
// broker rejecting the SAME trailing-SL modify, on TWO tickets, roughly once
// per second, continuously for the whole session ("Invalid stops" every
// time). None of the cushion inputs above ever escalate on repeated
// rejection - they are small, fixed POINT counts (2-5 points), which is
// negligible in dollar terms for BTCUSD (a few cents) even though it may be
// enough headroom for a forex/metals symbol where 1 point is a meaningful
// fraction of typical price moves. If the broker's real enforced minimum
// distance for this symbol is wider than what SYMBOL_TRADE_STOPS_LEVEL/
// SYMBOL_TRADE_FREEZE_LEVEL report (common for crypto CFDs), every retry
// keeps failing forever with no correction - exactly the kind of sustained,
// broker-facing request pattern that previously triggered a real "server
// problem" alert on a different EA (unthrottled entry retries; this is the
// same risk category applied to modifies instead of entries).
//
// After each consecutive failure (broker reject OR the pre-send validity
// check itself failing) for a given ticket, this widens the required
// clearance by InpExitBackoffCushionStepPct% of the CURRENT price - scales
// correctly with price level, so the same setting is meaningful on both a
// $65,000 BTC print and a $2,000 XAU print - and multiplies the retry
// cooldown, both capped. Resets to zero the moment a modify is accepted.
input double InpExitBackoffCushionStepPct  = 0.02;   // % of current price added per consecutive failure
input int    InpExitBackoffMaxSteps        = 8;       // cap on how many failures keep widening the cushion
input int    InpExitBackoffCooldownCapMs   = 15000;   // cap on the exponential retry backoff

// Legacy compatibility inputs retained but hard-disabled in V2.009F.
input bool   InpUseContinuationTrail           = false;
input double InpTrailStartR                    = 1.50;
input double InpTrailInitialLockR              = 0.25;
input double InpTrailStepR                     = 0.50;
input bool   InpUsePeakProfitProtection        = false;
input double InpPeakLockActivateR              = 1.00;
input double InpPeakProfitGivebackPct          = 30.0;

// Automatic post-test report.
input bool   InpWriteCSVReport                 = true;
input string InpCSVReportPrefix                = "EzyMap_Scalp_Mastery_V2_0_ZoneQuality_Report";

// Live/tester Journal performance reporting. Reconstructed from broker history
// for this symbol and magic number, so the figures survive EA/chart restarts.
// "total trades" means fully closed position campaigns; breakeven trades are
// reported separately and excluded from the win-rate denominator.
input bool   InpReportPerformanceToJournal      = true;
input int    InpStatsHistoryDays                 = 0;   // 0 = all available history
input int    InpStatsReportIntervalSeconds       = 300; // periodic report while attached


// Signal parity mode:
// true  = execute only after the V1.2 LIVE first-touch event.
// false = permits the older READY pre-staging behaviour.
input bool   InpV120SignalParityMode      = true; // retained for legacy mode only

//
// Phase 2 HYBRID execution model.
// M5 = setup/quality map. M1 = precise execution confirmation.
//
input bool   InpQualityMode                    = true;
input int    InpMinTrendExecutionConfluences   = 2; // compatibility only
input int    InpMinCounterExecutionConfluences = 3; // compatibility only
input bool   InpAllowCounterTrendTrades        = true;
input int    InpMaxExecutionZoneRetests        = 2;

// M1 execution confirmation.
input bool   InpUseM1ExecutionConfirmation     = false; // keep OFF: M1 is already the signal timeframe
input int    InpM1ConfirmationLookback         = 3;
input double InpM1RejectionWickRatio           = 0.25;
input double InpM1CloseStrength                = 0.55;
input double InpM1MomentumBodyFactor           = 0.90;
input double InpM1ZoneTolerancePips            = 8.0;
input bool   InpCounterRequireM1Break          = true;

//----------------------------- Constants ----------------------------
#define PRODUCT_NAME "EzyMap Scalp Mastery"
#define PRODUCT_VERSION "V2.0 • V3.190 BASE • ZONE QUALITY + ROUTING CHAIN • S01-S05"
#define EMA_LEN 13
#define TREND_MIN_CONFLUENCES 2
#define COUNTER_MIN_CONFLUENCES 3
#define MAX_ZONE_RETESTS 8
#define CONFIRM_WINDOW 12
#define MIN_RR 0.60
#define MAX_RR 2.50
#define BE_ARM_PROGRESS 0.40

string PREFIX="EZYSMV20ZONEQUAL_";

enum EzyState { ST_MONITORING=0, ST_READY=1, ST_ACTIVE=2, ST_TP=3, ST_SL=4, ST_BE=5 };

struct ZoneInfo
{
   double lo;
   double hi;
   datetime time;
   bool valid;
};

struct TradePlan
{
   double sl;
   double tp;
   double rr;
   bool valid;
};

struct ReadySnapshot
{
   string direction;
   bool counterTrend;
   int confluences;
   int requiredConfluences;
   int zoneRetests;
   double supportLo;
   double supportHi;
   double entryLo;
   double entryHi;
   datetime entryTime;
   double planSL;
   double planTP;
   double planRR;
   datetime armedClock;
   datetime armedBarTime;
   bool zoneExited;
   bool armed;
};

struct ActiveSnapshot
{
   string direction;
   bool counterTrend;
   int confluences;
   int zoneRetests;
   long signalId;
   double entry;
   double sl;
   double tp;
   double rr;
   double entryLo;
   double entryHi;
   datetime entryTime;
   datetime startClock;
   datetime startBarTime;
   double beTrigger;
   bool beArmed;
};



enum EZY_ZERO_CONF_TRIGGER_CODE
{
   EZY_ZC_TRIGGER_NONE=0,
   EZY_ZC_TRIGGER_W1_CLUSTER=1,
   EZY_ZC_TRIGGER_W1_SINGLE=2,
   EZY_ZC_TRIGGER_D1_H4_CLUSTER=3,
   EZY_ZC_TRIGGER_D1_SINGLE=4,
   EZY_ZC_TRIGGER_LOW_RISK=5,
   EZY_ZC_TRIGGER_READY=6,
   EZY_ZC_TRIGGER_H4_SINGLE=7,
   EZY_ZC_TRIGGER_CURRENT_MAP=8,
   EZY_ZC_TRIGGER_CURRENT_OUTER=9
};


struct ZeroConfTriggerMap
{
   bool readyValid;
   double readyLo;
   double readyHi;
   bool lowRiskValid;
   double lowRiskLo;
   double lowRiskHi;
   double currentLevel1;
   double currentLevel2;
   double h4Level1;
   double h4Level2;
   double d1Level1;
   double d1Level2;
   double w1Level1;
   double w1Level2;
};


struct ZeroConfTriggerCandidate
{
   bool valid;
   int direction;
   int priority;
   int code;
   double lo;
   double hi;
   double distance;
   datetime reclaimTime;
};

struct PersistentReadySetup
{
   bool active;
   bool deployed;
   bool triggered;
   bool expiryHandled;
   long id;
   int direction;            // +1 BUY, -1 SELL
   bool counterTrend;
   int confluences;

   // V3.102 zero-confluence READY-touch state.
   int requiredConfluences;
   bool zeroConfluenceFallback;

   // Frozen directional trigger map for V3.170.
   double zeroConfluenceLevelPrice;
   double zeroConfluenceOuterLevelPrice;
   ZeroConfTriggerMap zeroConfTriggerMap;
   int zeroConfTriggerCode;
   int zeroConfTriggerPriority;
   double zeroConfTriggerLo;
   double zeroConfTriggerHi;
   datetime zeroConfReclaimTime;

   int zoneRetests;
   double supportLo;
   double supportHi;
   double entryLo;
   double entryHi;
   double structuralSL;
   datetime entryTime;
   datetime armedClock;
   datetime armedBarTime;
   datetime deployedClock;
   bool zoneExited;
   int layersPlanned;
   int layersPlaced;
   double riskPct;
   double targetRR;

   // V2.009 touch latch / retry state.
   bool touchLatched;
   bool highRiskTouchLatched;
   bool s1r1TouchLatched;
   bool s2r2TouchLatched;

   // V3.100 sensitive touch path state.
   bool hasPreviousTouchCMP;
   double previousTouchCMP;

   datetime touchClock;
   double touchPrice;
   int deployAttempts;

   // V3.102 execution retry control.
   datetime lastDeployAttemptClock;
   ulong lastDeployAttemptTickMs;
   datetime deploymentBlockedM5;

   // V2.0 S2/S3/S4: zone quality, frozen when the touch latches so the
   // number reported in logs and the CSV is the one that actually sized the
   // trade.
   int      zoneTouchNumber;
   double   departureScore;
   int      zoneGrade;          // 0 unset, 1=A, 2=B, 3=C

   // V3.190 S4: touch-confirmation state. Lives here rather than in a
   // parallel structure so it is cleared by the same latch-reset and
   // setup-expiry paths as every other touch field, and cannot leak.
   bool     confirmPending;
   bool     confirmSatisfied;
   ulong    confirmStartMs;
   ulong    confirmStallSinceMs;
   double   confirmExtreme;
   double   confirmTouchPrice;
   datetime confirmTouchM1Bar;
};

struct DirectZeroConfState
{
   bool active;
   bool buyTouchConsumed;
   bool sellTouchConsumed;
   int direction;
   string triggerText;
   int triggerCode;
   int triggerPriority;
   double triggerLo;
   double triggerHi;
   datetime reclaimTime;
   datetime latchedClock;
   datetime lastAttemptClock;
   ulong lastAttemptTickMs;
   int attempts;
};

struct SetupAnalytics
{
   // V2.0 quality attribution captured at deployment.
   int v2ZoneGrade;
   int v2TouchNumber;
   double v2DepartureScore;
   int v2H1BiasAligned;
   double v2ActualStopPips;

   // V2.1a S1/S2: the confluence snapshot the trade was deployed on, frozen
   // at the gate. Re-deriving these at report time would read the session
   // and ATR of whenever the report happened to be written.
   // Session and path are stored as integer CODES, not strings: these rows
   // are zeroed with ZeroMemory(), and keeping the struct free of string
   // members keeps that safe. The codes are rendered to text only at CSV
   // write time via SessionCodeText()/EntryPathCodeText().
   int v21aSessionCode;
   double v21aSessionScore;
   double v21aVolPercentile;
   double v21aVolScore;
   double v21aTotalScore;
   int v21aEntryPathCode;

   bool used;
   bool peakRunnerArmed;
   long id;
   int direction;
   int confidence;
   double riskPct;
   double targetRR;
   int plannedLayers;
   double plannedLots;
   double actualEntryLots;
   double realisedProfit;
   double peakCampaignProfit;
   double peakRunnerProfit;
   int peakLockCloses;
   datetime armedTime;
   datetime deployedTime;
};

struct ReportPositionMap
{
   long positionId;
   long setupId;
   int layerIndex;
   int totalLayers;
};

struct ReportSetupRow
{
   long id;
   int direction;
   // V2.0: quality attribution, so win rate and expectancy can be measured
   // PER GRADE / PER TOUCH from the CSV. Without these the grading table is
   // unfalsifiable.
   int zoneGrade;
   int zoneTouchNumber;
   double departureScore;
   int h1BiasAligned;      // 1 aligned, -1 counter, 0 neutral/unknown
   double actualStopPips;
   // V2.1a: the confluence snapshot at deployment, so pass/fail rate and
   // expectancy can be sliced by session and by volatility regime. Codes
   // rather than strings for the same ZeroMemory reason as SetupAnalytics.
   int v21aSessionCode;
   double v21aSessionScore;
   double v21aVolPercentile;
   double v21aVolScore;
   double v21aTotalScore;
   int v21aEntryPathCode;
   int confidence;
   double riskPct;
   double targetRR;
   int plannedLayers;
   double entryLots;
   double maxEntryDealLot;
   double netProfit;
   double peakCampaignProfit;
   double peakRunnerProfit;
   int layer1TPHits;
   int layer2TPHits;
   int runnerTPHits;
   int peakLockCloses;
};


struct HybridTrailState
{
   ulong    ticket;
   bool     active;
   bool     reconstructed;
   double   peakPrice;
   double   virtualStop;
   datetime positionTime;
   datetime initializedClock;

   // V3.190 S1/S3: geometry is resolved ONCE when the position is first seen
   // and then frozen here, in PRICE distance. Freezing matters because S03
   // can source these from ATR: if they were recomputed live, a falling ATR
   // would shrink the trail distance and drag an already-advanced stop
   // backwards, breaking the monotonic ratchet S01 depends on.
   bool     geometryFrozen;
   double   presetDistance;
   double   armDistance;
   double   trailInitialDistance;
   double   tightenAtDistance;
   double   trailTightDistance;
   double   breakevenAtDistance;
   double   breakevenOffset;
   double   frozenATR;          // 0.0 when S03 geometry is disabled
   bool     breakevenLocked;    // latched once the BE floor has engaged

   // V3.190 S2: a position may only be partial-closed once.
   bool     partialTaken;
   double   partialRequestedVolume;

   // V2.0 S4: grade frozen with the position, so exit geometry cannot shift
   // mid-trade (same constraint as V3.190 S03 geometry freezing).
   int      zoneGrade;
   double   partialTargetDistance;
};

struct ExitExecutionState
{
   ulong  ticket;
   long   positionIdentifier;
   int    direction;

   bool   closeInProgress;
   ulong  closeRequestMs;
   ulong  closeLockUntilMs;
   double requestedClosePrice;
   double requestedStop;
   double peakPrice;
   string closeReason;

   ulong  lastModifyAttemptMs;
   ulong  modifyCooldownUntilMs;
   double lastRequestedSL;
   uint   lastModifyRetcode;

   // EXIT MODIFY BACKOFF: consecutive rejections (broker or pre-send
   // validity check) for this ticket's SL modify. Widens the required
   // broker clearance and the retry cooldown on every failure; reset to 0
   // the instant a modify is accepted. See InpExitBackoffCushionStepPct.
   int    consecutiveInvalidStops;

   // V3.190 S2: volume requested on the in-flight close. 0.0 means the
   // request was a full close; a positive value marks it as a partial so the
   // deal handler can tell the two apart when the fill arrives.
   double partialCloseVolume;
};


// Journal statistics aggregate one completed trade per broker position id,
// preventing partial-fill deals from inflating the win/loss trade count.
struct JournalTradeRow
{
   long   positionId;
   double entryLots;
   double netPnl;
   bool   hasExit;
};

struct JournalPerformanceSnapshot
{
   double lotsTraded;
   int    actualEntryFills;
   int    totalTrades;
   int    wins;
   int    losses;
   int    breakeven;
   int    openTrades;
   double closedNetPnl;
};

//--------------------------- Global state ---------------------------
EzyState g_state=ST_MONITORING;
ReadySnapshot g_ready;       // UI compatibility snapshot
ReadySnapshot g_buyReady;    // V1.2 independent BUY READY
ReadySnapshot g_sellReady;   // V1.2 independent SELL READY
ActiveSnapshot g_active;
datetime g_lastEntryClosedTime=0;
int g_structureDirection=0;
int g_bullChochAge=9999, g_bearChochAge=9999;
int g_bullRejectAge=9999, g_bearRejectAge=9999;
string g_lastResult="";
datetime g_resultTime=0;

string g_historicalMarkerNames[];
int g_historicalMarkerSerial=0;

ENUM_TIMEFRAMES g_directionTF=PERIOD_H1;
ENUM_TIMEFRAMES g_supportTF=PERIOD_M15;
ENUM_TIMEFRAMES g_confirmTF=PERIOD_M5;
ENUM_TIMEFRAMES g_entryTF=PERIOD_M5;
string g_mode="SCALP";
string g_tfLabel="M5";
string g_dirLabel="H1";
string g_supLabel="M15";
string g_confirmLabel="M5";

// Current map snapshot
double g_S1=0,g_S2=0,g_R1=0,g_R2=0;

// V3.170 higher-timeframe levels used only by zero-confluence execution.
double g_zcH4S1=0,g_zcH4S2=0,g_zcH4R1=0,g_zcH4R2=0;
double g_zcD1S1=0,g_zcD1S2=0,g_zcD1R1=0,g_zcD1R2=0;
double g_zcW1S1=0,g_zcW1S2=0,g_zcW1R1=0,g_zcW1R2=0;
MqlRates g_zcM5ReclaimRates[];
datetime g_zcM5ReclaimCacheBar=0;

ZoneInfo g_buyHigh,g_buyLow,g_sellHigh,g_sellLow;
int g_buyHighConf=0,g_sellHighConf=0;
double g_pipSize=0,g_brnStep=0,g_microStep=0;
double g_accountUnitDivisor=1.0;
string g_biasText="NEUTRAL";
double g_livePrice=0.0;
bool g_trendBuyRoute=false;
bool g_trendSellRoute=false;
int g_readySignalCount=0;
int g_liveSignalCount=0;
int g_executedBasketCount=0;

PersistentReadySetup g_persistentSetups[];
long g_lastCapturedBuyId=0;
long g_lastCapturedSellId=0;
int g_persistentQueuedCount=0;
int g_persistentTriggeredCount=0;
int g_persistentCompletedCount=0;
int g_qualityHoldCount=0;
int g_qualityDeployCount=0;
int g_dailyLayerOrders=0;
int g_dailyDateKey=0;
HybridTrailState g_hybridTrailStates[];
ExitExecutionState g_exitExecutionStates[];

DirectZeroConfState g_directZeroConf;
bool   g_directZeroConfHasPreviousCMP=false;
double g_directZeroConfPreviousCMP=0.0;
// Distinct id space so direct zero-conf trades cannot collide with the
// TimeCurrent()*10+direction ids QueuePersistentSetup() assigns.
long   g_directZeroConfSerial=0;

bool   g_deployFailureSet=false;
bool   g_deployFailureTemporary=false;
uint   g_deployFailureRetcode=0;
string g_deployFailureReason="";
string g_deployFailureDescription="";
string g_deployFailureBrokerComment="";

int g_buyM3Score=0;
int g_sellM3Score=0;
datetime g_buyM3ConfirmTime=0;
datetime g_sellM3ConfirmTime=0;
double g_buyHighLine=0.0;
double g_sellHighLine=0.0;
datetime g_lastBuyReadyEntryTime=0;
datetime g_lastSellReadyEntryTime=0;

double g_dayStartEquity=0.0;
double g_dayTargetEquity=0.0;
double g_dayLossFloor=0.0;
bool g_dayTradingLocked=false;
string g_dayLockReason="";
int g_campaignDirection=0;
int g_campaignSetups=0;

// v1.016 reporting and profit-capture analytics.
SetupAnalytics g_setupAnalytics[];
datetime g_reportFromTime=0;
bool g_reportWritten=false;
ulong g_lastAnalyticsDeal=0;
datetime g_lastStatsReportClock=0;
string g_lastStatsSignature="";

bool HasUntriggeredPersistentReady(int direction);
int CountWaitingReadyDirection(int direction);
int CountTotalWaitingReady();
double ReadyTouchCMP(MqlTick &tick);
ulong NowMs();
bool TradeRetcodePartial(uint code);
bool TradeRetcodeAccepted(uint code);
bool TemporaryTradeRetcode(uint code);
bool RetryWithoutSLRetcode(uint code);
void ResetDeploymentFailure();
void SetDeploymentFailure(string reason,
                          uint retcode,
                          string description,
                          string brokerComment,
                          bool temporary);
string DeploymentFailureSummary();
bool DeploymentRetryIntervalElapsed(PersistentReadySetup &setup);
void MarkDeploymentAttempt(PersistentReadySetup &setup);
void ClearPersistentTouchLatch(PersistentReadySetup &setup);
bool HasWaitingZeroConfluenceSetup(int direction);
void ResetZeroConfTriggerMap(ZeroConfTriggerMap &map);
void ResetZeroConfCandidate(ZeroConfTriggerCandidate &candidate);
string ZeroConfTriggerCodeText(int code,int direction);
bool RefreshZeroConfHigherTimeframeLevels(double reference);
void BuildCurrentZeroConfTriggerMap(int direction,ZeroConfTriggerMap &map);
bool ResolveZeroConfTriggerMap(ZeroConfTriggerMap &map,
                               int direction,
                               double observedLo,
                               double observedHi,
                               double tolerance,
                               ZeroConfTriggerCandidate &candidate);
bool ResolveDirectZeroConfTrigger(int direction,double observedLo,double observedHi,
                                  double tolerance,string &triggerText,
                                  double &triggerLo,double &triggerHi,
                                  int &triggerCode,int &triggerPriority,
                                  datetime &reclaimTime);
bool DirectZeroConfRetryElapsed();
string PersistentTag(long id);
int CountOurLosingPositionsByDirection(int direction);
bool DirectionalLosingPositionCapacityAvailable(int direction,string context);
void CancelPendingOrdersAtDirectionalLosingCap(int direction);
void EnforceDirectionalLosingPositionCaps();
int CountOurClosedNegativeEntriesCurrentM5();
bool M5ClosedLossCapacityAvailable(string context);
void CancelAllPendingAtM5ClosedLossCap();
void EnforceM5ClosedLossCap();
bool SpreadAllowed();
string EffectiveSpreadCapText();
bool SubmitDirectZeroConfMarket();
void ProcessDirectZeroConfluenceTriggers();
bool IsLiveXAUUSDscProtectionChart();
// V2.2 BTC S4: short instrument tag for RUNTIME log/label text, so a line
// that scales itself from StrategyPipSize() does not also hardcode a claim
// about WHICH instrument it scaled. Defined beside IsGold()/IsBTC().
string InstrumentLabel();
double ProtectionTickSize();
double ProtectionPriceDistance(double strategyPips);
double RoundProtectionStop(int direction,double price);
double ExactProtectionStop(int direction,double anchor,double strategyPips);
double LiveTrailActivationDistance(MqlTick &tick,double armDistance);
bool TrailStopImproves(int direction,double candidate,double existing,double minimumGain);
double TrailBetterStop(int direction,double a,double b);
void FreezeTrailGeometry(int index,int direction,double entry);
// V3.190 S2/S3: these are defined further down the file but are now called
// from earlier functions (the ATR geometry resolver and the synchronized
// close), so they need declaring up here.
double Clamp(double v,double lo,double hi);
double NormalizeVolumeDown(double vol);
int VolumeDigits();
bool NearGoldRoundNumber(double price,double &levelOut);
int ComputeZoneGrade(int direction,int touchNumber,double departureScore,
                     double proximalEdge,string &detail);
string ZoneGradeText(int grade);
double GradeSizeMultiplier(int grade);
double GradeTrailMultiplier(int grade);
double GradePartialTPPips(int grade);
int ResolvePositionZoneGrade(ulong ticket);
double ComputeDepartureScore(double zoneLo,double zoneHi,datetime zoneTime,int direction);
double DepartureSizeMultiplier(double score);
int ZoneTouchIndex(double lo,double hi);
int ZoneTouchCount(double lo,double hi);
int RegisterZoneTouch(double lo,double hi);
double FreshnessSizeMultiplier(int touchNumber);
void SaveZoneTouchState();
void LoadZoneTouchState();
void SetQualityContext(int direction,int touches,double departure,int grade);
void ClearQualityContext();
string StatePrefix();
void RefreshH1Bias();
int H1BiasDirection();
bool IsCounterToH1Bias(int direction);
double V2QualitySizeMultiplier(int direction,string &reason);
int ReadyExpiryBarsEffective();
// V2.1a S1/S2: the shared confluence engine. Declared here because the gate
// is called from SubmitDirectZeroConfMarket() (~line 2900) long before the
// implementations, which sit next to SpreadAllowed().
int NormalizeHour24(int hour);
int SessionCodeForHour(int hour);
string SessionCodeText(int code);
string EntryPathCodeText(int code);
double SessionScoreForCode(int code);
double SessionConfluenceScore();
bool VolatilityInputsMatchGeometryATR();
void RefreshVolatilityATR();
double VolatilityRegimeScore();
double ConfluenceScore();
bool ConfluenceGateAllows(string path,string context);
void CaptureConfluenceSnapshot(int analyticsIndex);
void LogConfluenceFilterRate();
void LogDeploymentGateBreakdown();
void RefreshGeometryATR();
double CurrentGeometryATR();
void ResolveATRGeometryPips(double &presetPips,double &armPips,double &initPips,
                            double &tightPips,double &tightenAtPips,double &atrPrice);
double ResolveDistalStopPips();
void SetDistalContext(int direction,double entry,double zoneLo,double zoneHi);
void ClearDistalContext();
double ResolvedPresetStopPips();
bool TouchConfirmationSatisfied(PersistentReadySetup &setup,int direction,
                                double zoneLo,double zoneHi,double cmp,
                                string &outcome);
double DirectionalFavourableExcursion(int direction);
bool ScaleInAllowed(int direction,string context);
double BrokerSafeExecutionSL(int direction,double marketPrice,double requestedSL);
double BrokerSafeExecutionTP(int direction,
                             double entryPrice,
                             double requestedTP);
void CapturePersistentReadySignals();
void ProcessPersistentSetups();
void DrawPersistentReadyZones();
void RefreshPersistentPositionProtection();
void ManageHybridTrailingPositions(string context);
int HybridTrailStateIndex(ulong ticket);
int EnsureHybridTrailState(ulong ticket,int direction,double entry,double current,datetime positionTime,MqlTick &tick);
double ReconstructTrailPeak(int direction,double entry,datetime positionTime,MqlTick &tick);
double ExitBackoffCushionPrice(double referencePrice,int backoffSteps);
double BrokerTrailMinimumDistance(double current,int backoffSteps);
double BrokerCompatibleTrailSL(int direction,double current,double virtualStop,int backoffSteps);
int ExitExecutionStateIndexByTicket(ulong ticket);
int ExitExecutionStateIndexByIdentifier(long positionIdentifier);
int EnsureExitExecutionState(ulong ticket);
bool ExitCloseInProgress(ulong ticket);
double LatestBrokerValidExitSL(int direction,double virtualStop,MqlTick &tick,int backoffSteps);
bool RequestSynchronizedPositionModify(ulong ticket,
                                       int direction,
                                       double virtualStop,
                                       double tp,
                                       string context,
                                       string purpose,
                                       double &submittedSL);
bool RequestSynchronizedPositionClose(ulong ticket,
                                      string context,
                                      double stop,
                                      double peak,
                                      ulong deviation,
                                      double closeVolume=0.0);
void HandleExitExecutionTransaction(const MqlTradeTransaction &trans);
void PruneExitExecutionStates();
bool ClosePositionAtVirtualTrail(ulong ticket,string context,double current,double stop,double peak);
void PruneHybridTrailStates();
void ResetDailyFrequencyCounter();
bool PersistentQualityPass(PersistentReadySetup &setup,string &reason);
bool DeployPersistentSetup(int index);
bool DeployAggressiveArmSetup(int index);
void DeletePersistentObjects(long id);
void ResetCampaignDay(bool forceReset);
void CheckCampaignDay();
bool DailyRiskCapacityAvailable(string context);
void CancelAllPendingAtDailyRiskLock();
void CloseAllEzyExposure();
void SupersedeWaitingZones(int direction,long incomingId);
double RiskPctForSetup(int conf,double entryLo,double entryHi,double sl);
int DesiredLayersForSetup(int conf,double entryLo,double entryHi,double sl);
double TargetRRForSetup(double riskPct);
double ConfidenceSetupLot(int conf);
double ResolveAccountUnitDivisor();
double EffectiveAccountEquity();
double LotSizingCapitalUnits();
double MinimumTradingEquity();
double CapSetupVolumeForCentSafety(int direction,double entry,double sl,double requested);
string ConfidenceClassText(int conf);
double ConfidenceTakeProfitPips(int conf);
double FixedPipTPForSetup(int direction,double entry,int conf);

double LayerRRForSetup(int layerIndex,int totalLayers,double runnerRR);
bool ParsePersistentComment(string comment,long &setupId,int &layerIndex,int &totalLayers);
datetime CurrentM5OpenTime();
int AnalyticsIndex(long id);
int EnsureAnalytics(long id);
void RegisterSetupAnalytics(PersistentReadySetup &setup);
void RegisterDealAnalytics(ulong dealTicket);
void UpdateSetupPeakAnalytics(long setupId);
bool BuildJournalPerformanceSnapshot(JournalPerformanceSnapshot &snapshot);
void ReportJournalPerformance(bool force,string reason);
void WriteEzyMapBacktestReport();

//----------------------------- Helpers ------------------------------
double RoundPrice(double v)
{
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(v,digits);
}

string PriceText(double v)
{
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return DoubleToString(v,digits);
}

string Upper(string s)
{
   StringToUpper(s);
   return s;
}

double ResolveAccountUnitDivisor()
{
   if(InpAccountScaleMode==EZY_ACCOUNT_STANDARD)
      return 1.0;

   double configured=MathMax(1.0,InpCentAccountUnitDivisor);

   if(InpAccountScaleMode==EZY_ACCOUNT_CENT)
      return configured;

   // AUTO mode: a normal Strategy Tester deposit must not be divided merely
   // because the historical symbol name ends in .sc. This was the main cause
   // of V2.009N producing zero lots and therefore no tester entries.
   if((bool)MQLInfoInteger(MQL_TESTER) && InpTesterAutoModeIsStandard)
      return 1.0;

   string currency=Upper(AccountInfoString(ACCOUNT_CURRENCY));
   string server=Upper(AccountInfoString(ACCOUNT_SERVER));
   string company=Upper(AccountInfoString(ACCOUNT_COMPANY));
   string symbol=Upper(_Symbol);

   bool centCurrency=(currency=="USC" || currency=="USCENT" ||
                      StringFind(currency,"CENT")>=0);
   bool centBrand=(StringFind(server,"CENT")>=0 ||
                   StringFind(company,"CENT")>=0);
   bool centSuffix=InpTreatSCSuffixAsCentOnLive &&
                   (StringFind(symbol,".SC")>=0 ||
                    StringFind(symbol,"_SC")>=0 ||
                    StringFind(symbol,"CENT")>=0);

   return (centCurrency || centBrand || centSuffix)?configured:1.0;
}

double EffectiveAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY)/MathMax(1.0,g_accountUnitDivisor);
}

double LotSizingCapitalUnits()
{
   double raw=InpUseBalanceForLotSizing
              ? AccountInfoDouble(ACCOUNT_BALANCE)
              : AccountInfoDouble(ACCOUNT_EQUITY);

   double capital=InpUseBrokerNativeDepositUnitsForLots
                  ? MathMax(0.0,raw)
                  : MathMax(0.0,raw/MathMax(1.0,g_accountUnitDivisor));

   // V2.1b S03 / V2.2 BTC S06: nominal sizing floor, applied identically to
   // both branches above. See InpForceMinimumBaseSizing for the full rationale
   // and the call-site audit proving this cannot reach a risk/margin cap.
   if(InpForceMinimumBaseSizing)
      capital=MathMax(capital,MathMax(1.0,InpBaseEquity));

   return capital;
}

bool IsLiveCentAccount()
{
   return (!(bool)MQLInfoInteger(MQL_TESTER) &&
           g_accountUnitDivisor>1.0);
}

double MinimumTradingEquity()
{
   if(g_accountUnitDivisor>1.0)
      return MathMax(0.0,InpCentMinimumEffectiveEquity);

   return MathMax(0.0,InpMinimumAccountEquity);
}

bool IsGold()
{
   string s=Upper(_Symbol);
   return (StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0);
}

bool IsBTC()
{
   string s=Upper(_Symbol);
   return (StringFind(s,"BTC")>=0 || StringFind(s,"XBT")>=0);
}

double StrategyPipSize()
{
   if(IsGold()) return MathMax(0.10,_Point);
   if(IsBTC())  return MathMax(1.0,_Point);
   return _Point;
}

// V2.2 BTC S4: instrument tag for printed strings ONLY. Never used in a
// comparison, a threshold or a branch that affects trading - it exists so a
// log line cannot claim "XAU" while running on BTC. Falls back to the raw
// broker symbol for anything that is neither gold nor crypto.
string InstrumentLabel()
{
   if(IsGold()) return "XAU";
   if(IsBTC())  return "BTC";
   return _Symbol;
}

bool IsLiveXAUUSDscProtectionChart()
{
   // V2.2 BTC S2: the suffix test below is already generic - it is the same
   // .SC / _SC / CENT check ResolveAccountUnitDivisor() uses to decide the
   // account is denominated in cents, and that function is NOT gold-gated.
   // Only this guard was, so a live BTCUSD.sc cent chart was recognised as a
   // cent account for LOT SIZING but not for PROTECTION PARITY: the trail
   // armed off rebuilt historical M1 peaks with no warmup and no spread
   // cushion, which is precisely the failure V3.164 added the feature to
   // stop. Widened from IsGold() to IsGold()||IsBTC().
   // XAUUSD.sc is unaffected: IsGold() still short-circuits true for it, and
   // no symbol that previously returned true can now return false.
   if((bool)MQLInfoInteger(MQL_TESTER) || !(IsGold() || IsBTC()))
      return false;

   string symbol=Upper(_Symbol);

   return (StringFind(symbol,".SC")>=0 ||
           StringFind(symbol,"_SC")>=0 ||
           StringFind(symbol,"CENT")>=0);
}


double ProtectionTickSize()
{
   double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tickSize<=0.0) tickSize=_Point;
   return MathMax(_Point,tickSize);
}


double ProtectionPriceDistance(double strategyPips)
{
   // Account cent divisor affects money/lot scaling only, never price distance.
   double pipSize=StrategyPipSize();
   if(IsGold()) pipSize=MathMax(0.10,pipSize);

   double distance=MathMax(0.1,strategyPips)*pipSize;
   double tickSize=ProtectionTickSize();
   double ticks=MathCeil((distance/tickSize)-1e-10);
   return MathMax(tickSize,ticks*tickSize);
}


double RoundProtectionStop(int direction,double price)
{
   double tickSize=ProtectionTickSize();
   double ticks=price/tickSize;
   double aligned=(direction==1)
                  ? MathFloor(ticks+1e-10)*tickSize
                  : MathCeil(ticks-1e-10)*tickSize;
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(aligned,digits);
}


double ExactProtectionStop(int direction,double anchor,double strategyPips)
{
   double distance=ProtectionPriceDistance(strategyPips);
   return RoundProtectionStop(direction,
                              direction==1 ? anchor-distance : anchor+distance);
}


// V3.190 S1: the second parameter is now the ARM distance, not the trail
// distance. OLD BEHAVIOUR: InpLiveXAURequireFullTrailBeforeArm raised the
// activation threshold to the full TRAIL distance, which is what welded
// arm == trail together. It now clamps against the arm distance only, so the
// two are independent and the caller's InpTrailArmPips is honoured.
double LiveTrailActivationDistance(MqlTick &tick,double armDistance)
{
   double strategyPip=StrategyPipSize();
   double activation=MathMax(_Point,
                             MathMax(0.0,InpTrailingActivationPips)*strategyPip);

   // The configured arm distance is the floor everywhere - tester and live
   // alike. Only the broker-parity padding below is live-chart specific, and
   // that behaviour is inherited unchanged from V3.176.
   activation=MathMax(activation,armDistance);

   if(!InpLiveXAUProtectionParity || !IsLiveXAUUSDscProtectionChart())
      return activation;

   if(InpLiveXAUIncludeSpreadInTrailArm)
      activation+=MathMax(0.0,tick.ask-tick.bid);

   activation+=MathMax(0,InpLiveXAUExtraProtectionCushionPoints)*_Point;
   return activation;
}


// V3.190 S1: "is candidate a strictly better (more protective) stop than
// existing?" Buy stops improve upward, sell stops improve downward. Every
// stop movement in the phase machine goes through this, which is what makes
// the ratchet monotonic regardless of which phase produced the candidate.
bool TrailStopImproves(int direction,double candidate,double existing,double minimumGain)
{
   if(candidate<=0.0)
      return false;

   if(existing<=0.0)
      return true;

   if(direction==1)
      return candidate>existing+minimumGain;

   return candidate<existing-minimumGain;
}


double TrailBetterStop(int direction,double a,double b)
{
   if(a<=0.0) return b;
   if(b<=0.0) return a;
   return (direction==1) ? MathMax(a,b) : MathMin(a,b);
}


int TfSeconds(ENUM_TIMEFRAMES tf)
{
   return PeriodSeconds(tf);
}


bool HasActivePersistentSignal()
{
   // V2.008 parallel mode:
   // a waiting READY no longer freezes the entire M5 signal scanner.
   // New confirmed M5 setups may continue to arm until queue caps are reached.
   if(InpAllowParallelWaitingReady)
      return false;

   // Exact V2.003 behaviour when parallel mode is disabled.
   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active)
         continue;

      if(!g_persistentSetups[i].deployed)
         return true;
   }

   return false;
}


double ReadyTouchCMP(MqlTick &tick)
{
   if(!InpUseChartPriceForReadyTouch)
      return tick.bid;

   long chartMode=SymbolInfoInteger(_Symbol,SYMBOL_CHART_MODE);

   if(chartMode==SYMBOL_CHART_MODE_LAST && tick.last>0.0)
      return tick.last;

   // Most OTC/CFD charts use Bid mode.
   return tick.bid;
}

void BuildZeroConfluenceTouchEnvelope(MqlTick &tick,
                                      double cmp,
                                      bool hasPreviousCMP,
                                      double previousCMP,
                                      double &observedLo,
                                      double &observedHi)
{
   observedLo=cmp;
   observedHi=cmp;

   if(InpZeroConfUseBidAskEnvelope)
   {
      if(tick.bid>0.0)
      {
         observedLo=MathMin(observedLo,tick.bid);
         observedHi=MathMax(observedHi,tick.bid);
      }

      if(tick.ask>0.0)
      {
         observedLo=MathMin(observedLo,tick.ask);
         observedHi=MathMax(observedHi,tick.ask);
      }

      if(tick.last>0.0)
      {
         observedLo=MathMin(observedLo,tick.last);
         observedHi=MathMax(observedHi,tick.last);
      }
   }

   if(InpZeroConfUseTickPathCrossing &&
      hasPreviousCMP &&
      previousCMP>0.0)
   {
      observedLo=MathMin(observedLo,previousCMP);
      observedHi=MathMax(observedHi,previousCMP);
   }
}

bool SensitiveEnvelopeTouchesZone(double observedLo,
                                  double observedHi,
                                  double zoneLo,
                                  double zoneHi,
                                  double tolerance)
{
   double lo=MathMin(zoneLo,zoneHi);
   double hi=MathMax(zoneLo,zoneHi);

   if(lo<=0.0 || hi<=0.0 || hi<lo)
      return false;

   return observedHi>=lo-tolerance &&
          observedLo<=hi+tolerance;
}

bool SensitiveEnvelopeTouchesLevel(double observedLo,
                                   double observedHi,
                                   double level,
                                   double tolerance)
{
   if(level<=0.0)
      return false;

   return observedHi>=level-tolerance &&
          observedLo<=level+tolerance;
}

string PersistentTouchTriggerText(PersistentReadySetup &setup)
{
   if(setup.zeroConfluenceFallback &&
      setup.zeroConfTriggerCode!=EZY_ZC_TRIGGER_NONE)
   {
      return ZeroConfTriggerCodeText(
         setup.zeroConfTriggerCode,
         setup.direction);
   }

   return "READY";
}

// V2.0 S2: one record per distinct price zone the EA has touched. Kept as a
// bounded ring so a long run cannot grow it without limit, and persisted
// through the existing SaveState()/LoadState() path so touch history survives
// a restart or a terminal bounce.
#define V2_MAX_ZONE_TOUCH_RECORDS 48

struct ZoneTouchRecord
{
   bool     used;
   double   lo;
   double   hi;
   int      touches;
   datetime firstTouch;
   datetime lastTouch;
};

ZoneTouchRecord g_zoneTouches[];

// V2.0 S2/S3/S4: quality context for the entry currently being sized.
// CapSetupVolumeForCentSafety() is the single sizing choke point but it has no
// setup handle, so the deploying path publishes the setup's quality here just
// before sizing and clears it afterwards.
// V2.0 S5: the zone the entry currently being sized belongs to, so
// ResolvedPresetStopPips() can derive a distal stop. Published and cleared
// alongside the quality context.
bool   g_distalContextValid=false;
double g_distalContextLo=0.0;
double g_distalContextHi=0.0;
int    g_distalContextDirection=0;
double g_distalContextEntry=0.0;

bool   g_qualityContextValid=false;
int    g_qualityContextTouches=0;
double g_qualityContextDeparture=-1.0;
int    g_qualityContextDirection=0;
int    g_qualityContextGrade=0;      // 0 unset, 1=A, 2=B, 3=C


// V2.0 S1: cached H1 bias. iMA() must not be called per tick, so the handle is
// created once in OnInit and the buffer is read at most once per H1 bar.
int      g_h1BiasHandle=INVALID_HANDLE;
double   g_h1BiasEMA=0.0;
double   g_h1BiasEMAPrev=0.0;
double   g_h1BiasClose=0.0;
datetime g_h1BiasBar=0;
int      g_h1BiasDir=0;      // +1 bullish, -1 bearish, 0 undecided/unavailable


// V3.190 S3: cached ATR. iATR() must not be called per tick, so the handle is
// created once in OnInit, the buffer is read at most once per bar of
// InpATRTimeframe, and every consumer reads the cached price value.
int      g_geometryATRHandle=INVALID_HANDLE;
double   g_geometryATRValue=0.0;
datetime g_geometryATRBar=0;


// V2.1a S1: the dead zone is the first N hours AFTER the New York close,
// before Asia liquidity arrives. It is derived from InpNYCloseHour rather
// than exposed as a fourth hour input, so the classifier is driven by
// exactly the three session hours the operator has to verify against their
// broker's server clock.
#define V21A_DEAD_ZONE_HOURS 2

// V2.1a S1: path tags. Used for the per-path counters, the deployment logs
// and the CSV EntryPath column. Kept as constants so the STANDARD and
// ZERO-CONF strings cannot drift apart between the call sites.
#define V21A_PATH_STANDARD "STANDARD"
#define V21A_PATH_ZEROCONF "ZERO-CONF"

// V2.1a S1: session classification codes. Integers rather than strings so
// the analytics struct stays ZeroMemory-safe; 0 means "never evaluated".
#define V21A_SESSION_UNSET   0
#define V21A_SESSION_OVERLAP 1
#define V21A_SESSION_LONDON  2
#define V21A_SESSION_NY      3
#define V21A_SESSION_ASIA    4
#define V21A_SESSION_DEAD    5

// V2.1a S1: entry-path codes, same reasoning.
#define V21A_PATHCODE_UNSET    0
#define V21A_PATHCODE_STANDARD 1
#define V21A_PATHCODE_ZEROCONF 2

// V2.1a S1: the last evaluated confluence snapshot. Written by the gate,
// read at deployment time by the analytics capture so the CSV records the
// scores the trade was ACTUALLY taken on rather than a re-evaluation at
// report time (the session would have moved on by then).
int      g_v21aSessionCode=V21A_SESSION_UNSET;
int      g_v21aSessionHour=-1;
double   g_v21aSessionScore=-1.0;
double   g_v21aVolPercentile=-1.0;
double   g_v21aVolScore=-1.0;
double   g_v21aTotalScore=-1.0;
int      g_v21aEntryPathCode=V21A_PATHCODE_UNSET;

// V2.1a S2: cached volatility ATR. Same discipline as V3.190 S03 and V2.0
// S01: the handle is created once in OnInit and the buffer is read at most
// once per bar of InpVolTimeframe, never per tick. g_volATRShared is true
// when the handle is an ALIAS of g_geometryATRHandle (same timeframe and
// period) - in that case OnDeinit must NOT release it twice.
int      g_volATRHandle=INVALID_HANDLE;
bool     g_volATRShared=false;
double   g_volATRValue=0.0;
double   g_volATRPercentile=-1.0;   // -1.0 = not yet measurable
datetime g_volATRBar=0;
bool     g_volRegimeExtreme=false;

// V2.1a S1: rolling gate frequency instrumentation, split by entry path so
// a frequency collapse can be attributed to the path that caused it.
// Incremented at the gate ONLY while InpUseConfluenceScoring is true, which
// is why the OnDeinit summary line is also suppressed while it is false.
long     g_stdAttempts=0;
long     g_stdPassed=0;
long     g_zcAttempts=0;
long     g_zcPassed=0;

// V2.2 BTC S06: deployment-gate rejection instrumentation.
//
// WHY: a run that ends "READY=511, stored=54, deployed=0" gives no way to tell
// WHICH gate zeroed it out. ConfluenceGateAllows() has had pass/fail counters
// since V2.1a S1, but the three gates that sit alongside it on every
// deployment path - SpreadAllowed(), TradingEnvironmentReady() and
// DailyRiskCapacityAvailable() - had none, so a spread filter set to a wrong
// point convention (or a hard volatility veto firing on every bar) looked
// exactly like "no signals". These counters make each of those visible.
//
// HOW: the three gate FUNCTIONS are deliberately unchanged. Every counter is
// incremented at the CALL SITE, on the false branch only, alongside whatever
// logging/return that site already did - no control flow and no existing log
// text is altered.
//
// SPLIT: STANDARD = persistent-setup deployment path (V21A_PATH_STANDARD),
// ZERO-CONF = direct zero-confluence market path (V21A_PATH_ZEROCONF), OTHER =
// the legacy bridge-signal arm/PlaceOneLayer path, which belongs to neither of
// the two scored entry paths and so cannot be attributed to either.
long     g_spreadRejectStd=0;
long     g_spreadRejectZc=0;
long     g_spreadRejectOther=0;
long     g_envRejectStd=0;
long     g_envRejectZc=0;
long     g_capacityRejectStd=0;
long     g_capacityRejectZc=0;
long     g_capacityRejectOther=0;
long     g_orderSendStd=0;
long     g_orderSendZc=0;
long     g_orderSendOther=0;

// V2.2 BTC S07: spread auto-calibration state. g_spreadCalEffectiveCap<0.0
// means "still collecting samples, filter inactive (fail open)". Array is
// sized once in OnInit to MathMax(20,InpSpreadCalibrationTicks).
double   g_spreadCalSamples[];
int      g_spreadCalCount=0;
double   g_spreadCalEffectiveCap=-1.0;

double MedianOfSpreadSamples(double &values[],int count)
{
   if(count<=0) return 0.0;

   double copy[];
   ArrayResize(copy,count);
   for(int i=0;i<count;i++) copy[i]=values[i];
   ArraySort(copy);

   if(count%2==1) return copy[count/2];
   return 0.5*(copy[count/2-1]+copy[count/2]);
}


// V3.190 S00: single monotonic millisecond clock for every timing decision in
// the EA. V3.176 called the raw OS tick counter directly from eight separate
// sites; funnelling them through one accessor means timing behaves
// identically in the tester and live, and there is exactly one place to
// change if the clock source ever needs to. This is the ONLY function in the
// file permitted to read the OS tick counter directly.
ulong NowMs()
{
   return GetTickCount64();
}

// V3.190 S00: a partially-filled order is neither a clean success nor a
// failure - the requested volume did not all execute, so the caller must
// re-read the position rather than assume its request completed. Used by the
// S02 partial-take-profit path.
bool TradeRetcodePartial(uint code)
{
   return (code==TRADE_RETCODE_DONE_PARTIAL);
}

bool TradeRetcodeAccepted(uint code)
{
   return (code==TRADE_RETCODE_DONE ||
           code==TRADE_RETCODE_PLACED ||
           code==TRADE_RETCODE_DONE_PARTIAL);
}

bool TemporaryTradeRetcode(uint code)
{
   return (code==TRADE_RETCODE_REQUOTE ||
           code==TRADE_RETCODE_REJECT ||
           code==TRADE_RETCODE_ERROR ||
           code==TRADE_RETCODE_TIMEOUT ||
           code==TRADE_RETCODE_INVALID_PRICE ||
           code==TRADE_RETCODE_PRICE_CHANGED ||
           code==TRADE_RETCODE_PRICE_OFF ||
           code==TRADE_RETCODE_TOO_MANY_REQUESTS ||
           code==TRADE_RETCODE_LOCKED ||
           code==TRADE_RETCODE_FROZEN ||
           code==TRADE_RETCODE_CONNECTION);
}

bool RetryWithoutSLRetcode(uint code)
{
   return (code==TRADE_RETCODE_INVALID_STOPS ||
           code==TRADE_RETCODE_REJECT);
}

void ResetDeploymentFailure()
{
   g_deployFailureSet=false;
   g_deployFailureTemporary=false;
   g_deployFailureRetcode=0;
   g_deployFailureReason="";
   g_deployFailureDescription="";
   g_deployFailureBrokerComment="";
}

void SetDeploymentFailure(string reason,
                          uint retcode,
                          string description,
                          string brokerComment,
                          bool temporary)
{
   g_deployFailureSet=true;
   g_deployFailureTemporary=temporary;
   g_deployFailureRetcode=retcode;
   g_deployFailureReason=reason;
   g_deployFailureDescription=description;
   g_deployFailureBrokerComment=brokerComment;
}

string DeploymentFailureSummary()
{
   string summary="reason="+
                  (g_deployFailureReason==""
                   ? "unspecified deployment failure"
                   : g_deployFailureReason);

   if(g_deployFailureRetcode>0)
   {
      summary+=" | retcode="+
               IntegerToString((int)g_deployFailureRetcode);

      if(g_deployFailureDescription!="")
         summary+=" | description="+g_deployFailureDescription;

      if(g_deployFailureBrokerComment!="")
         summary+=" | broker comment="+
                  g_deployFailureBrokerComment;
   }

   return summary;
}

bool DeploymentRetryIntervalElapsed(PersistentReadySetup &setup)
{
   if(setup.lastDeployAttemptClock<=0)
      return true;

   datetime nowClock=TimeCurrent();

   if(nowClock>setup.lastDeployAttemptClock)
      return true;

   ulong nowMs=NowMs();

   if(nowMs<setup.lastDeployAttemptTickMs)
      return true;

   return (nowMs-setup.lastDeployAttemptTickMs >=
           (ulong)MathMax(0,InpDeploymentRetryIntervalMs));
}

void MarkDeploymentAttempt(PersistentReadySetup &setup)
{
   setup.lastDeployAttemptClock=TimeCurrent();
   setup.lastDeployAttemptTickMs=NowMs();
}

void ClearPersistentTouchLatch(PersistentReadySetup &setup)
{
   setup.touchLatched=false;
   setup.highRiskTouchLatched=false;
   setup.s1r1TouchLatched=false;
   setup.s2r2TouchLatched=false;
   setup.zeroConfTriggerCode=EZY_ZC_TRIGGER_NONE;
   setup.zeroConfTriggerPriority=999;
   setup.zeroConfTriggerLo=0.0;
   setup.zeroConfTriggerHi=0.0;
   setup.zeroConfReclaimTime=0;
   setup.touchClock=0;

   // V3.190 S4: confirmation state is part of the touch latch and must die
   // with it, otherwise a stale pending confirmation survives into the next
   // touch of the same setup.
   setup.confirmPending=false;
   setup.confirmSatisfied=false;
   setup.confirmStartMs=0;
   setup.confirmStallSinceMs=0;
   setup.confirmExtreme=0.0;
   setup.confirmTouchPrice=0.0;
   setup.confirmTouchM1Bar=0;
}


void ResetZeroConfTriggerMap(ZeroConfTriggerMap &map)
{
   ZeroMemory(map);
}


void ResetZeroConfCandidate(ZeroConfTriggerCandidate &candidate)
{
   ZeroMemory(candidate);
   candidate.priority=999;
   candidate.distance=DBL_MAX;
}


string ZeroConfTriggerCodeText(int code,int direction)
{
   string side=(direction==1)?"SUPPORT":"RESISTANCE";

   switch(code)
   {
      case EZY_ZC_TRIGGER_W1_CLUSTER:
         return "ZERO-CONF W1 + D1/H4 "+side+" CLUSTER";
      case EZY_ZC_TRIGGER_W1_SINGLE:
         return "ZERO-CONF W1 "+side;
      case EZY_ZC_TRIGGER_D1_H4_CLUSTER:
         return "ZERO-CONF D1 + H4 "+side+" CLUSTER";
      case EZY_ZC_TRIGGER_D1_SINGLE:
         return "ZERO-CONF D1 "+side;
      case EZY_ZC_TRIGGER_LOW_RISK:
         return "ZERO-CONF LOW RISK";
      case EZY_ZC_TRIGGER_READY:
         return "ZERO-CONF READY";
      case EZY_ZC_TRIGGER_H4_SINGLE:
         return "ZERO-CONF H4 "+side;
      case EZY_ZC_TRIGGER_CURRENT_MAP:
         return direction==1
                ? "ZERO-CONF CURRENT S1"
                : "ZERO-CONF CURRENT R1";

      case EZY_ZC_TRIGGER_CURRENT_OUTER:
         return direction==1
                ? "ZERO-CONF LIVE S2"
                : "ZERO-CONF LIVE R2";
   }

   return "ZERO-CONF";
}


bool BuildZeroConfLevelsForTimeframe(ENUM_TIMEFRAMES timeframe,
                                     double reference,
                                     double minimumDistance,
                                     double &s1,
                                     double &s2,
                                     double &r1,
                                     double &r2)
{
   s1=0.0;
   s2=0.0;
   r1=0.0;
   r2=0.0;

   MqlRates rates[];

   int requested=
      timeframe==PERIOD_W1
      ? 90
      : (timeframe==PERIOD_D1 ? 140 : 180);

   int minimum=
      timeframe==PERIOD_W1
      ? 24
      : (timeframe==PERIOD_D1 ? 40 : 55);

   if(!LoadRatesFlexible(timeframe,requested,minimum,rates))
      return false;

   double rangeLow=DBL_MAX;
   double rangeHigh=-DBL_MAX;

   int count=
      MathMin(
         ArraySize(rates)-1,
         MathMax(20,InpDirectionHistory));

   for(int i=1;i<=count;i++)
   {
      rangeLow=MathMin(rangeLow,rates[i].low);
      rangeHigh=MathMax(rangeHigh,rates[i].high);
   }

   double atr=
      ATRFromRates(rates,ArraySize(rates),14,1);

   if(rangeLow==DBL_MAX ||
      rangeHigh==-DBL_MAX ||
      atr==EMPTY_VALUE)
      return false;

   PickDirectionLevels(
      rates,
      ArraySize(rates),
      reference,
      MathMax(minimumDistance,_Point*5.0),
      rangeLow,
      rangeHigh,
      atr,
      s1,s2,r1,r2);

   return s1>0.0 && s2>0.0 && r1>0.0 && r2>0.0;
}


bool RefreshZeroConfHigherTimeframeLevels(double reference)
{
   if(reference<=0.0)
      return false;

   // V2.2 BTC S3: was a hardcoded 70.0. Input default is 70.0, so unchanged.
   double baseDistance=
      MathMax(MathMax(0.0,InpH4LevelMinDistancePips)*g_pipSize,_Point*5.0);

   bool h4OK=
      BuildZeroConfLevelsForTimeframe(
         PERIOD_H4,
         reference,
         baseDistance,
         g_zcH4S1,g_zcH4S2,
         g_zcH4R1,g_zcH4R2);

   bool d1OK=
      BuildZeroConfLevelsForTimeframe(
         PERIOD_D1,
         reference,
         // V2.2 BTC S3: was a hardcoded 120.0. Input default is 120.0.
         MathMax(MathMax(0.0,InpD1LevelMinDistancePips)*g_pipSize,baseDistance),
         g_zcD1S1,g_zcD1S2,
         g_zcD1R1,g_zcD1R2);

   bool w1OK=
      BuildZeroConfLevelsForTimeframe(
         PERIOD_W1,
         reference,
         // V2.2 BTC S3: was a hardcoded 200.0. Input default is 200.0.
         MathMax(MathMax(0.0,InpW1LevelMinDistancePips)*g_pipSize,baseDistance),
         g_zcW1S1,g_zcW1S2,
         g_zcW1R1,g_zcW1R2);

   if(!h4OK)
   {
      g_zcH4S1=0.0;
      g_zcH4S2=0.0;
      g_zcH4R1=0.0;
      g_zcH4R2=0.0;
   }

   if(!d1OK)
   {
      g_zcD1S1=0.0;
      g_zcD1S2=0.0;
      g_zcD1R1=0.0;
      g_zcD1R2=0.0;
   }

   if(!w1OK)
   {
      g_zcW1S1=0.0;
      g_zcW1S2=0.0;
      g_zcW1R1=0.0;
      g_zcW1R2=0.0;
   }

   return h4OK || d1OK || w1OK;
}


void BuildCurrentZeroConfTriggerMap(int direction,
                                    ZeroConfTriggerMap &map)
{
   ResetZeroConfTriggerMap(map);

   if(direction==1)
   {
      map.readyValid=
         g_buyReady.armed &&
         g_buyReady.entryHi>g_buyReady.entryLo;
      map.readyLo=g_buyReady.entryLo;
      map.readyHi=g_buyReady.entryHi;

      map.lowRiskValid=
         V3170_ZERO_CONF_LOW_RISK_TOUCH_RULE &&
         g_buyLow.valid;
      map.lowRiskLo=g_buyLow.lo;
      map.lowRiskHi=g_buyLow.hi;

      map.currentLevel1=g_S1;
      map.currentLevel2=g_S2;
      map.h4Level1=g_zcH4S1;
      map.h4Level2=g_zcH4S2;
      map.d1Level1=g_zcD1S1;
      map.d1Level2=g_zcD1S2;
      map.w1Level1=g_zcW1S1;
      map.w1Level2=g_zcW1S2;
   }
   else
   {
      map.readyValid=
         g_sellReady.armed &&
         g_sellReady.entryHi>g_sellReady.entryLo;
      map.readyLo=g_sellReady.entryLo;
      map.readyHi=g_sellReady.entryHi;

      map.lowRiskValid=
         V3170_ZERO_CONF_LOW_RISK_TOUCH_RULE &&
         g_sellLow.valid;
      map.lowRiskLo=g_sellLow.lo;
      map.lowRiskHi=g_sellLow.hi;

      map.currentLevel1=g_R1;
      map.currentLevel2=g_R2;
      map.h4Level1=g_zcH4R1;
      map.h4Level2=g_zcH4R2;
      map.d1Level1=g_zcD1R1;
      map.d1Level2=g_zcD1R2;
      map.w1Level1=g_zcW1R1;
      map.w1Level2=g_zcW1R2;
   }
}


bool RefreshZeroConfM5ReclaimCache()
{
   datetime currentBar=iTime(_Symbol,PERIOD_M5,0);

   if(currentBar<=0)
      return false;

   if(g_zcM5ReclaimCacheBar==currentBar &&
      ArraySize(g_zcM5ReclaimRates)>=4)
      return true;

   ArraySetAsSeries(g_zcM5ReclaimRates,true);

   int requested=
      MathMax(
         6,
         MathMax(1,InpZeroConfSweepLookbackM5)+4);

   int copied=
      CopyRates(
         _Symbol,
         PERIOD_M5,
         0,
         requested,
         g_zcM5ReclaimRates);

   if(copied<4)
      return false;

   g_zcM5ReclaimCacheBar=currentBar;
   return true;
}


bool ZeroConfM5SweepReclaim(int direction,
                            double triggerLo,
                            double triggerHi,
                            datetime &reclaimTime)
{
   reclaimTime=0;

   if(!InpZeroConfRequireM5SweepReclaim)
   {
      reclaimTime=TimeCurrent();
      return true;
   }

   if(!RefreshZeroConfM5ReclaimCache())
      return false;

   double lo=MathMin(triggerLo,triggerHi);
   double hi=MathMax(triggerLo,triggerHi);

   if(lo<=0.0 || hi<=0.0)
      return false;

   MqlRates reclaim=g_zcM5ReclaimRates[1];

   bool reclaimed=
      direction==1
      ? reclaim.close>hi
      : reclaim.close<lo;

   if(!reclaimed)
      return false;

   int maximumSweepIndex=
      MathMin(
         ArraySize(g_zcM5ReclaimRates)-1,
         1+MathMax(1,InpZeroConfSweepLookbackM5));

   bool swept=false;

   for(int i=1;i<=maximumSweepIndex;i++)
   {
      if(direction==1 &&
         g_zcM5ReclaimRates[i].low<lo)
      {
         swept=true;
         break;
      }

      if(direction==-1 &&
         g_zcM5ReclaimRates[i].high>hi)
      {
         swept=true;
         break;
      }
   }

   if(!swept)
      return false;

   reclaimTime=reclaim.time;
   return true;
}


void ConsiderZeroConfCandidate(
   ZeroConfTriggerCandidate &best,
   int direction,
   int priority,
   int code,
   double triggerLo,
   double triggerHi,
   double observedLo,
   double observedHi,
   double tolerance)
{
   double lo=MathMin(triggerLo,triggerHi);
   double hi=MathMax(triggerLo,triggerHi);

   if(lo<=0.0 || hi<=0.0 || hi<lo)
      return;

   bool envelopeNear=
      SensitiveEnvelopeTouchesZone(
         observedLo,
         observedHi,
         lo,
         hi,
         tolerance);

   // V3.173: an actual live touch within the configured tolerance is required.
   if(!envelopeNear)
      return;

   datetime reclaimTime=0;

   if(!ZeroConfM5SweepReclaim(
         direction,
         lo,
         hi,
         reclaimTime))
      return;

   double centre=(lo+hi)*0.5;
   double observedCentre=(observedLo+observedHi)*0.5;
   double distance=MathAbs(observedCentre-centre);

   if(!best.valid ||
      priority<best.priority ||
      (priority==best.priority &&
       distance<best.distance))
   {
      best.valid=true;
      best.direction=direction;
      best.priority=priority;
      best.code=code;
      best.lo=lo;
      best.hi=hi;
      best.distance=distance;
      best.reclaimTime=reclaimTime;
   }
}


double NearestClusterPartner(double anchor,
                             double candidate1,
                             double candidate2,
                             double candidate3,
                             double candidate4,
                             double clusterTolerance)
{
   double best=0.0;
   double bestDistance=DBL_MAX;
   double candidates[4];

   candidates[0]=candidate1;
   candidates[1]=candidate2;
   candidates[2]=candidate3;
   candidates[3]=candidate4;

   for(int i=0;i<4;i++)
   {
      if(candidates[i]<=0.0)
         continue;

      double distance=MathAbs(anchor-candidates[i]);

      if(distance<=clusterTolerance &&
         distance<bestDistance)
      {
         best=candidates[i];
         bestDistance=distance;
      }
   }

   return best;
}


bool ResolveZeroConfTriggerMap(
   ZeroConfTriggerMap &map,
   int direction,
   double observedLo,
   double observedHi,
   double tolerance,
   ZeroConfTriggerCandidate &candidate)
{
   ResetZeroConfCandidate(candidate);

   double clusterTolerance=
      MathMax(
         0.0,
         InpZeroConfClusterTolerancePips)*
      g_pipSize;

   double w1[2];
   double d1[2];
   double h4[2];
   double current[2];

   w1[0]=map.w1Level1;
   w1[1]=map.w1Level2;
   d1[0]=map.d1Level1;
   d1[1]=map.d1Level2;
   h4[0]=map.h4Level1;
   h4[1]=map.h4Level2;
   current[0]=map.currentLevel1;
   current[1]=map.currentLevel2;

   // V2.1b S2: index 0 is the INNER level (S1/D1) and index 1 the OUTER level
   // (S2/D2) - see the assignments in BuildCurrentZeroConfTriggerMap().
   // Starting the four W1/D1 loops here leaves only the outer level eligible.
   // H4 is deliberately NOT gated by this: the H4_SINGLE loop further down
   // still runs 0..1, and h4[0]/h4[1] stay available as cluster partners for
   // a W1 or D1 anchor in the two cluster loops below.
   int startIdx=InpZeroConfIncludeLevel1 ? 0 : 1;   // V2.1b S2

   for(int i=startIdx;i<2;i++)   // V2.1b S2: W1_CLUSTER anchor, was i=0
   {
      if(w1[i]<=0.0)
         continue;

      double partner=
         NearestClusterPartner(
            w1[i],
            d1[0],d1[1],
            h4[0],h4[1],
            clusterTolerance);

      if(partner>0.0)
      {
         ConsiderZeroConfCandidate(
            candidate,direction,
            1,EZY_ZC_TRIGGER_W1_CLUSTER,
            MathMin(w1[i],partner),
            MathMax(w1[i],partner),
            observedLo,observedHi,tolerance);
      }
   }

   for(int i=startIdx;i<2;i++)   // V2.1b S2: W1_SINGLE, was i=0
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         2,EZY_ZC_TRIGGER_W1_SINGLE,
         w1[i],w1[i],
         observedLo,observedHi,tolerance);
   }

   for(int i=startIdx;i<2;i++)   // V2.1b S2: D1_H4_CLUSTER anchor, was i=0
   {
      if(d1[i]<=0.0)
         continue;

      double partner=
         NearestClusterPartner(
            d1[i],
            h4[0],h4[1],
            0.0,0.0,
            clusterTolerance);

      if(partner>0.0)
      {
         ConsiderZeroConfCandidate(
            candidate,direction,
            3,EZY_ZC_TRIGGER_D1_H4_CLUSTER,
            MathMin(d1[i],partner),
            MathMax(d1[i],partner),
            observedLo,observedHi,tolerance);
      }
   }

   for(int i=startIdx;i<2;i++)   // V2.1b S2: D1_SINGLE, was i=0
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         4,EZY_ZC_TRIGGER_D1_SINGLE,
         d1[i],d1[i],
         observedLo,observedHi,tolerance);
   }

   if(map.lowRiskValid)
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         5,EZY_ZC_TRIGGER_LOW_RISK,
         map.lowRiskLo,map.lowRiskHi,
         observedLo,observedHi,tolerance);
   }

   if(map.readyValid)
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         6,EZY_ZC_TRIGGER_READY,
         map.readyLo,map.readyHi,
         observedLo,observedHi,tolerance);
   }

   for(int i=0;i<2;i++)
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         7,EZY_ZC_TRIGGER_H4_SINGLE,
         h4[i],h4[i],
         observedLo,observedHi,tolerance);
   }

   // V2.1b S1: the CURRENT_MAP / CURRENT_OUTER tier is no longer part of the
   // ladder. The two calls are retained behind the rollback input rather than
   // deleted so EzyMap_V2_1b_STAGE0_BASELINE.set reproduces the V2.1a
   // nine-source ladder EXACTLY for the A/B; with the input false they never
   // execute, no priority-8 candidate can ever be produced, and the ladder
   // ends at H4_SINGLE (priority 7). The matching gate on CURRENT_OUTER's
   // directional override lives in ProcessDirectZeroConfluenceTriggers() and
   // is driven by the SAME input, so the tier and its privilege are one
   // switch and cannot be half-restored.
   if(InpZeroConfAllowCurrentMapTier)   // V2.1b S1
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         8,EZY_ZC_TRIGGER_CURRENT_MAP,
         current[0],current[0],
         observedLo,observedHi,tolerance);

      ConsiderZeroConfCandidate(
         candidate,direction,
         8,EZY_ZC_TRIGGER_CURRENT_OUTER,
         current[1],current[1],
         observedLo,observedHi,tolerance);
   }

   return candidate.valid;
}


bool HasWaitingZeroConfluenceSetup(int direction)
{
   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active ||
         g_persistentSetups[i].deployed ||
         g_persistentSetups[i].triggered)
         continue;

      if(g_persistentSetups[i].direction==direction &&
         g_persistentSetups[i].zeroConfluenceFallback)
         return true;
   }
   return false;
}

bool ResolveDirectZeroConfTrigger(
   int direction,
   double observedLo,
   double observedHi,
   double tolerance,
   string &triggerText,
   double &triggerLo,
   double &triggerHi,
   int &triggerCode,
   int &triggerPriority,
   datetime &reclaimTime)
{
   triggerText="";
   triggerLo=0.0;
   triggerHi=0.0;
   triggerCode=EZY_ZC_TRIGGER_NONE;
   triggerPriority=999;
   reclaimTime=0;

   ZeroConfTriggerMap map;
   BuildCurrentZeroConfTriggerMap(direction,map);

   ZeroConfTriggerCandidate candidate;

   if(!ResolveZeroConfTriggerMap(
         map,
         direction,
         observedLo,
         observedHi,
         tolerance,
         candidate))
      return false;

   triggerText=
      ZeroConfTriggerCodeText(
         candidate.code,
         direction);

   triggerLo=candidate.lo;
   triggerHi=candidate.hi;
   triggerCode=candidate.code;
   triggerPriority=candidate.priority;
   reclaimTime=candidate.reclaimTime;
   return true;
}

bool DirectZeroConfRetryElapsed()
{
   if(g_directZeroConf.lastAttemptClock<=0)
      return true;

   if(TimeCurrent()>g_directZeroConf.lastAttemptClock)
      return true;

   ulong nowMs=NowMs();
   if(nowMs<g_directZeroConf.lastAttemptTickMs)
      return true;

   return (nowMs-g_directZeroConf.lastAttemptTickMs >=
           (ulong)MathMax(0,InpDeploymentRetryIntervalMs));
}

bool SubmitDirectZeroConfMarket()
{
   if(!g_directZeroConf.active || !DirectZeroConfRetryElapsed())
      return false;

   g_directZeroConf.lastAttemptClock=TimeCurrent();
   g_directZeroConf.lastAttemptTickMs=NowMs();
   g_directZeroConf.attempts++;

   int direction=g_directZeroConf.direction;

   // V2.1a S1/S2: ZERO-CONF confluence gate. This is one of the two entry
   // paths and it shares SessionConfluenceScore()/VolatilityRegimeScore()
   // with the standard path - the scoring logic is never duplicated here.
   // Placed after the retry-interval check so it is evaluated exactly once
   // per genuine deployment attempt, and before every capacity check so a
   // rejected attempt costs nothing.
   if(!ConfluenceGateAllows(
         V21A_PATH_ZEROCONF,
         "trigger="+g_directZeroConf.triggerText+
         " direction="+string(direction==1?"BUY":"SELL")+
         " attempt="+IntegerToString(g_directZeroConf.attempts)))
      return false;

   if(!DailyRiskCapacityAvailable(
         "DIRECT ZERO-CONF "+g_directZeroConf.triggerText))
   {
      g_capacityRejectZc++;   // V2.2 BTC S06 instrumentation
      g_directZeroConf.active=false;
      return false;
   }

   if(!SpreadAllowed())
   {
      g_spreadRejectZc++;     // V2.2 BTC S06 instrumentation
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+
          g_directZeroConf.triggerText+
          " | direction="+
          string(direction==1?"BUY":"SELL")+
          " | attempt="+
          IntegerToString(g_directZeroConf.attempts)+
          " | reason=spread filter: current spread exceeds "+
          EffectiveSpreadCapText());
      return false;
   }

   if(!M5ClosedLossCapacityAvailable(
         "DIRECT ZERO-CONF "+g_directZeroConf.triggerText))
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+
          g_directZeroConf.triggerText+
          " | direction="+
          string(direction==1?"BUY":"SELL")+
          " | attempt="+
          IntegerToString(g_directZeroConf.attempts)+
          " | reason=maximum 2 losing closes reached in current M5");
      return false;
   }

   if(!DirectionalLosingPositionCapacityAvailable(
         direction,
         "DIRECT ZERO-CONF "+g_directZeroConf.triggerText))
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+
          g_directZeroConf.triggerText+
          " | direction="+
          string(direction==1?"BUY":"SELL")+
          " | attempt="+
          IntegerToString(g_directZeroConf.attempts)+
          " | reason=maximum currently losing positions reached");
      return false;
   }

   if(!DirectionalLayerSlotAvailable(direction,g_directZeroConf.triggerText))
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | attempt="+IntegerToString(g_directZeroConf.attempts)+
          " | reason=directional layer ceiling reached");
      return false;
   }

   string envReason="";
   if(!TradingEnvironmentReady(envReason))
   {
      g_envRejectZc++;        // V2.2 BTC S06 instrumentation
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | attempt="+IntegerToString(g_directZeroConf.attempts)+
          " | reason="+envReason);
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double entry=(direction==1)?tick.ask:tick.bid;
   // V3.190 S3: resolved stop distance, so an ATR-derived stop is the one
   // actually submitted (and the one sizing is computed against).
   double exactDistance=ProtectionPriceDistance(ResolvedPresetStopPips());
   double exactSL=RoundProtectionStop(
      direction,
      direction==1 ? entry-exactDistance : entry+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(direction,entry,exactSL);

   double requested=ConfidenceSetupLot(0);

   // V2.0 S2: the direct zero-conf path has no PersistentReadySetup, so its
   // quality context is derived from the resolved trigger band.
   int directTouchNumber=
      RegisterZoneTouch(g_directZeroConf.triggerLo,
                        g_directZeroConf.triggerHi);

   SetQualityContext(direction,directTouchNumber,-1.0,0);
   SetDistalContext(direction,entry,
                    g_directZeroConf.triggerLo,g_directZeroConf.triggerHi);

   double volume=CapSetupVolumeForCentSafety(direction,entry,brokerSL,requested);

   ClearQualityContext();

   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(volume<minVolume-1e-12)
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | attempt="+IntegerToString(g_directZeroConf.attempts)+
          " | reason=STANDARD volume below broker/safety minimum"+
          " | requested="+DoubleToString(requested,VolumeDigits())+
          " | safe="+DoubleToString(volume,VolumeDigits())+
          " | minimum="+DoubleToString(minVolume,VolumeDigits()));
      return false;
   }

   // Tagged as an "EZR..." setup (single layer) instead of the old
   // PREFIX+"DIRECT_ZC_..." comment. The old tag never matched
   // ParsePersistentComment()'s required "EZR" prefix, so every direct
   // zero-conf trade was silently excluded from WriteEzyMapBacktestReport()'s
   // CSV/summary and from RegisterDealAnalytics() - it still traded and still
   // affected the account, it just never showed up in that report, which is
   // why its totals (trade count and net P/L) never reconciled with the
   // account's real balance change or with ReportJournalPerformance().
   g_orderSendZc++;           // V2.2 BTC S06 instrumentation
   g_directZeroConfSerial++;
   long directZcId=5000000000000+g_directZeroConfSerial;
   string comment=PersistentTag(directZcId)+" L1/1 DZC-"+
                  string(direction==1?"BUY":"SELL");

   bool sent=(direction==1)
             ? trade.Buy(volume,_Symbol,0.0,brokerSL,0.0,comment)
             : trade.Sell(volume,_Symbol,0.0,brokerSL,0.0,comment);

   uint retcode=trade.ResultRetcode();
   bool accepted=(sent && TradeRetcodeAccepted(retcode));
   bool openedWithoutSL=false;

   if(!accepted && InpRetryEntryWithoutSLOnReject && RetryWithoutSLRetcode(retcode))
   {
      sent=(direction==1)
           ? trade.Buy(volume,_Symbol,0.0,0.0,0.0,comment)
           : trade.Sell(volume,_Symbol,0.0,0.0,0.0,comment);
      retcode=trade.ResultRetcode();
      accepted=(sent && TradeRetcodeAccepted(retcode));
      openedWithoutSL=accepted;
   }

   if(!accepted)
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | attempt="+IntegerToString(g_directZeroConf.attempts)+
          " | retcode="+IntegerToString((int)retcode)+
          " | description="+trade.ResultRetcodeDescription()+
          " | broker comment="+trade.ResultComment()+
          " | retry remains latched=YES");
      return false;
   }

   g_dailyLayerOrders++;

   // V2.1a S1/S2: the direct zero-conf path has no PersistentReadySetup, so
   // RegisterSetupAnalytics() never runs for it. Its analytics row is created
   // anyway by RegisterDealAnalytics() (the order comment is EZR-tagged), so
   // this only fills in the six V2.1a columns and leaves every V2.0 column at
   // the zeroed value the CSV already reported for zero-conf rows.
   CaptureConfluenceSnapshot(EnsureAnalytics(directZcId));

   Log("DIRECT ZERO-CONF MARKET EXECUTED | signal="+(string)directZcId+
       " | trigger="+g_directZeroConf.triggerText+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | volume="+DoubleToString(volume,VolumeDigits())+
       " | attempts="+IntegerToString(g_directZeroConf.attempts)+
       " | priority="+IntegerToString(g_directZeroConf.triggerPriority)+
       " | reclaim="+
       TimeToString(g_directZeroConf.reclaimTime,TIME_DATE|TIME_MINUTES)+
       " | SL21="+string(openedWithoutSL?"virtual/broker install pending":
                         DoubleToString(brokerSL,_Digits))+
       " | TP=NONE | trail9=ACTIVE");

   // V2.1b S1: CURRENT_OUTER's right to retire every other waiting zero-conf
   // setup in this direction is part of the same tier and is withdrawn with
   // it. The block is unreachable while InpZeroConfAllowCurrentMapTier is
   // false - triggerCode can never hold CURRENT_OUTER then - but the input is
   // named in the condition anyway so the privilege reads as belonging to the
   // rollback switch rather than as surviving behaviour.
   if(InpZeroConfAllowCurrentMapTier &&   // V2.1b S1
      g_directZeroConf.triggerCode==
      EZY_ZC_TRIGGER_CURRENT_OUTER)
   {
      int retired=0;

      for(int i=0;i<ArraySize(g_persistentSetups);i++)
      {
         if(!g_persistentSetups[i].active ||
            g_persistentSetups[i].deployed ||
            g_persistentSetups[i].triggered ||
            !g_persistentSetups[i].zeroConfluenceFallback ||
            g_persistentSetups[i].direction!=direction)
            continue;

         g_persistentSetups[i].active=false;
         retired++;
      }

      Log("V3.176 LIVE S2/R2 OVERRIDE COMPLETE"+
          " | direction="+
          string(direction==1?"BUY":"SELL")+
          " | retired stale waiting zero-conf setups="+
          IntegerToString(retired)+
          " | duplicate frozen-map fill prevented=YES");
   }

   g_directZeroConf.active=false;
   if(direction==1) g_directZeroConf.buyTouchConsumed=true;
   else g_directZeroConf.sellTouchConsumed=true;
   return true;
}

void ProcessDirectZeroConfluenceTriggers()
{
   if(!V3104_ZERO_CONF_DIRECT_MAP_FALLBACK)
      return;

   if(!DailyRiskCapacityAvailable("DIRECT ZERO-CONF TRIGGER SCAN"))
   {
      g_capacityRejectZc++;   // V2.2 BTC S06 instrumentation
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double cmp=ReadyTouchCMP(tick);
   if(cmp<=0.0)
      return;

   double observedLo=cmp,observedHi=cmp;
   BuildZeroConfluenceTouchEnvelope(tick,cmp,
                                    g_directZeroConfHasPreviousCMP,
                                    g_directZeroConfPreviousCMP,
                                    observedLo,observedHi);
   g_directZeroConfPreviousCMP=cmp;
   g_directZeroConfHasPreviousCMP=true;

   double tolerance=MathMax(MathMax(0.0,InpEntryTouchTolerancePips),
                            MathMax(0.0,InpZeroConfTouchTolerancePips))*g_pipSize;

   string buyTrigger="",sellTrigger="";
   double buyLo=0.0,buyHi=0.0,sellLo=0.0,sellHi=0.0;
   int buyCode=EZY_ZC_TRIGGER_NONE;
   int sellCode=EZY_ZC_TRIGGER_NONE;
   int buyPriority=999;
   int sellPriority=999;
   datetime buyReclaimTime=0;
   datetime sellReclaimTime=0;

   bool buyTouched=
      ResolveDirectZeroConfTrigger(
         1,
         observedLo,observedHi,
         tolerance,
         buyTrigger,buyLo,buyHi,
         buyCode,buyPriority,
         buyReclaimTime);

   bool sellTouched=
      ResolveDirectZeroConfTrigger(
         -1,
         observedLo,observedHi,
         tolerance,
         sellTrigger,sellLo,sellHi,
         sellCode,sellPriority,
         sellReclaimTime);

   if(!buyTouched && !g_directZeroConf.active)
      g_directZeroConf.buyTouchConsumed=false;
   if(!sellTouched && !g_directZeroConf.active)
      g_directZeroConf.sellTouchConsumed=false;

   bool buyWaitingZeroConf=
      HasWaitingZeroConfluenceSetup(1);

   bool sellWaitingZeroConf=
      HasWaitingZeroConfluenceSetup(-1);

   // V2.1b S1: V2.1a carved CURRENT_OUTER out of the "an already-waiting
   // zero-conf setup blocks a new direct fill" rule. That carve-out is part of
   // the CURRENT tier and is withdrawn with it, so it is gated on the SAME
   // rollback input. With the input false the tier cannot be chosen at all and
   // the carve-out would be unreachable regardless; gating it explicitly is
   // what makes STAGE0_BASELINE a FAITHFUL A/B control - restoring the tier
   // without its override right would reproduce neither ladder.
   bool buyOuterOverride=
      InpZeroConfAllowCurrentMapTier &&
      (buyCode==EZY_ZC_TRIGGER_CURRENT_OUTER);      // V2.1b S1

   bool sellOuterOverride=
      InpZeroConfAllowCurrentMapTier &&
      (sellCode==EZY_ZC_TRIGGER_CURRENT_OUTER);     // V2.1b S1

   if(buyWaitingZeroConf &&
      !buyOuterOverride)      // V2.1b S1: was buyCode!=EZY_ZC_TRIGGER_CURRENT_OUTER
      buyTouched=false;

   if(sellWaitingZeroConf &&
      !sellOuterOverride)     // V2.1b S1: was sellCode!=EZY_ZC_TRIGGER_CURRENT_OUTER
      sellTouched=false;

   if(!g_directZeroConf.active)
   {
      int runningPositions=CountOurPositions();

      if(runningPositions<=V3104_ZERO_CONF_MAX_OPEN_POSITIONS)
      {
         bool chooseBuy=buyTouched && !g_directZeroConf.buyTouchConsumed;
         bool chooseSell=sellTouched && !g_directZeroConf.sellTouchConsumed;
         int chosenDirection=0;
         string chosenTrigger="";
         int chosenCode=EZY_ZC_TRIGGER_NONE;
         int chosenPriority=999;
         double chosenLo=0.0,chosenHi=0.0;
         datetime chosenReclaimTime=0;

         if(chooseBuy && chooseSell)
         {
            bool buyWins=false;

            if(buyPriority<sellPriority)
               buyWins=true;
            else if(buyPriority==sellPriority)
            {
               double buyCentre=(buyLo+buyHi)*0.5;
               double sellCentre=(sellLo+sellHi)*0.5;
               buyWins=
                  MathAbs(cmp-buyCentre)<=
                  MathAbs(cmp-sellCentre);
            }

            if(buyWins)
            {
               chosenDirection=1;
               chosenTrigger=buyTrigger;
               chosenCode=buyCode;
               chosenPriority=buyPriority;
               chosenLo=buyLo;
               chosenHi=buyHi;
               chosenReclaimTime=buyReclaimTime;
            }
            else
            {
               chosenDirection=-1;
               chosenTrigger=sellTrigger;
               chosenCode=sellCode;
               chosenPriority=sellPriority;
               chosenLo=sellLo;
               chosenHi=sellHi;
               chosenReclaimTime=sellReclaimTime;
            }
         }
         else if(chooseBuy)
         {
            chosenDirection=1;
            chosenTrigger=buyTrigger;
            chosenCode=buyCode;
            chosenPriority=buyPriority;
            chosenLo=buyLo;
            chosenHi=buyHi;
            chosenReclaimTime=buyReclaimTime;
         }
         else if(chooseSell)
         {
            chosenDirection=-1;
            chosenTrigger=sellTrigger;
            chosenCode=sellCode;
            chosenPriority=sellPriority;
            chosenLo=sellLo;
            chosenHi=sellHi;
            chosenReclaimTime=sellReclaimTime;
         }

         if(chosenDirection!=0)
         {
            g_directZeroConf.active=true;
            g_directZeroConf.direction=chosenDirection;
            g_directZeroConf.triggerText=chosenTrigger;
            g_directZeroConf.triggerCode=chosenCode;
            g_directZeroConf.triggerPriority=chosenPriority;
            g_directZeroConf.triggerLo=chosenLo;
            g_directZeroConf.triggerHi=chosenHi;
            g_directZeroConf.reclaimTime=chosenReclaimTime;
            g_directZeroConf.latchedClock=TimeCurrent();
            g_directZeroConf.lastAttemptClock=0;
            g_directZeroConf.lastAttemptTickMs=0;
            g_directZeroConf.attempts=0;

            Log("DIRECT ZERO-CONF TOUCH LATCHED | trigger="+chosenTrigger+
                " | direction="+string(chosenDirection==1?"BUY":"SELL")+
                " | CMP="+DoubleToString(cmp,_Digits)+
                " | observed path="+DoubleToString(observedLo,_Digits)+".."+
                DoubleToString(observedHi,_Digits)+
                " | zone="+DoubleToString(chosenLo,_Digits)+".."+
                DoubleToString(chosenHi,_Digits)+
                " | priority="+IntegerToString(chosenPriority)+
                " | live outer override="+
                string(chosenCode==EZY_ZC_TRIGGER_CURRENT_OUTER
                       ?"YES"
                       :"NO")+
                " | M5 reclaim="+
                TimeToString(chosenReclaimTime,TIME_DATE|TIME_MINUTES)+
                " | running positions at latch="+IntegerToString(runningPositions)+
                " | retry until MARKET accepted=YES");
         }
      }
   }

   if(g_directZeroConf.active)
      SubmitDirectZeroConfMarket();
}



double BrokerSafeExecutionSL(int direction,
                             double marketPrice,
                             double requestedSL)
{
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   double minDist=
      MathMax(_Point,
              ((double)stopsLevel+
               MathMax(0,InpExecutionStopCushionPoints))*_Point);

   double safeSL=requestedSL;

   if(direction==1)
   {
      double maxSL=marketPrice-minDist;

      if(safeSL<=0 || safeSL>maxSL)
         safeSL=maxSL;
   }
   else
   {
      double minSL=marketPrice+minDist;

      if(safeSL<=0 || safeSL<minSL)
         safeSL=minSL;
   }

   return RoundProtectionStop(direction,safeSL);
}


double BrokerSafeExecutionTP(int direction,
                             double entryPrice,
                             double requestedTP)
{
   if(entryPrice<=0 || requestedTP<=0)
      return requestedTP;

   long stopsLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   double minDist=
      MathMax(_Point,
              ((double)stopsLevel+
               MathMax(0,InpExecutionStopCushionPoints))*_Point);

   double safeTP=requestedTP;

   if(direction==1)
   {
      double minTP=entryPrice+minDist;

      if(safeTP<minTP)
         safeTP=minTP;
   }
   else
   {
      double maxTP=entryPrice-minDist;

      if(safeTP>maxTP)
         safeTP=maxTP;
   }

   return RoundPrice(safeTP);
}



bool FixedTrailSLBrokerValid(int direction,
                             double currentPrice,
                             double requestedSL,
                             int backoffSteps)
{
   if(currentPrice<=0 || requestedSL<=0)
      return false;

   long stopsLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   long freezeLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double minimumDistance=
      MathMax(_Point,
              ((double)MathMax(stopsLevel,freezeLevel)+
               MathMax(0,InpExecutionStopCushionPoints))*_Point)+
      ExitBackoffCushionPrice(currentPrice,backoffSteps);

   if(direction==1)
      return requestedSL<=currentPrice-minimumDistance+_Point*0.25;

   return requestedSL>=currentPrice+minimumDistance-_Point*0.25;
}

double FixedTrailCandidateSL(int direction,
                             double currentPrice)
{
   double distance=
      ProtectionPriceDistance(InpTrailingDistancePips);

   return RoundProtectionStop(direction,
                              direction==1
                              ? currentPrice-distance
                              : currentPrice+distance);
}

int HybridTrailStateIndex(ulong ticket)
{
   for(int i=0;i<ArraySize(g_hybridTrailStates);i++)
      if(g_hybridTrailStates[i].ticket==ticket)
         return i;
   return -1;
}

double ReconstructTrailPeak(int direction,
                            double entry,
                            datetime positionTime,
                            MqlTick &tick)
{
   double peak=(direction==1)?tick.bid:tick.ask;

   if(!InpReconstructTrailFromM1 || positionTime<=0)
      return peak;

   if(InpLiveXAUProtectionParity &&
      InpLiveXAUDisableHistoricalPeakRebuild &&
      IsLiveXAUUSDscProtectionChart())
      return RoundPrice(peak);

   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,PERIOD_M1,positionTime,TimeCurrent(),rates);
   if(copied<=0)
      return peak;

   double spread=MathMax(0.0,tick.ask-tick.bid);

   for(int i=0;i<copied;i++)
   {
      if(direction==1)
         peak=MathMax(peak,rates[i].high);
      else
         peak=MathMin(peak,rates[i].low+spread);
   }

   if(direction==1)
      peak=MathMax(peak,entry);
   else
      peak=MathMin(peak,entry);

   return RoundPrice(peak);
}

// V3.190 S1: resolve the phase geometry for one position and freeze it.
// Called exactly once per ticket, from EnsureHybridTrailState(). All values
// are PRICE distances. When S03 is enabled the pip figures come from ATR
// instead of the fixed inputs, but they land in the same fields and drive the
// same phase machine - the logic is never forked.
// V3.190 S3: refresh the cached ATR at most once per bar of the configured
// timeframe. Called from the protection pass; the per-bar guard is what keeps
// this off the per-tick cost path.
void RefreshGeometryATR()
{
   if(!InpUseATRGeometry || g_geometryATRHandle==INVALID_HANDLE)
      return;

   datetime bar=iTime(_Symbol,InpATRTimeframe,0);

   if(bar<=0 || bar==g_geometryATRBar)
      return;

   double buffer[];
   ArraySetAsSeries(buffer,true);

   // Shift 1: the last CLOSED bar. The forming bar's ATR moves intrabar and
   // would make geometry depend on when in the bar a position happened to
   // open.
   if(CopyBuffer(g_geometryATRHandle,0,1,1,buffer)<1)
      return;

   if(buffer[0]<=0.0)
      return;

   g_geometryATRValue=buffer[0];
   g_geometryATRBar=bar;
}


// V3.190 S3: cached ATR in PRICE units, 0.0 when unavailable or disabled.
double CurrentGeometryATR()
{
   if(!InpUseATRGeometry)
      return 0.0;

   return g_geometryATRValue;
}


// V3.190 S3: overwrite the fixed pip geometry with ATR-derived figures.
// A no-op when S03 is off or the ATR is not yet available, which is what
// makes S01 behaviour byte-identical in that case. The results feed the SAME
// phase machine as S01 - the logic is never forked.
void ResolveATRGeometryPips(double &presetPips,
                            double &armPips,
                            double &initPips,
                            double &tightPips,
                            double &tightenAtPips,
                            double &atrPrice)
{
   atrPrice=0.0;

   double atr=CurrentGeometryATR();
   if(atr<=0.0)
      return;

   double pip=MathMax(StrategyPipSize(),_Point);
   double atrPips=atr/pip;

   if(atrPips<=0.0)
      return;

   atrPrice=atr;

   // Preserve the tight:initial shape the user configured in S01 instead of
   // inventing separate ATR multipliers for the tighten phase.
   double shapeReference=MathMax(0.1,initPips);
   double atrInitial=MathMax(MathMax(0.1,InpATRTrailFloorPips),
                             atrPips*MathMax(0.01,InpATRTrailMultiplier));
   double ratio=atrInitial/shapeReference;

   double floorPips  =MathMax(0.1,InpATRStopFloorPips);
   double ceilingPips=MathMax(floorPips,InpATRStopCeilingPips);

   presetPips=Clamp(atrPips*MathMax(0.01,InpATRStopMultiplier),
                    floorPips,ceilingPips);

   armPips  =MathMax(0.0,atrPips*MathMax(0.0,InpATRArmMultiplier));
   tightPips=MathMax(MathMax(0.1,InpATRTrailFloorPips),tightPips*ratio);

   // An unreachable tighten threshold (the S01 default of 999) must stay
   // unreachable after scaling.
   tightenAtPips=tightenAtPips*ratio;

   initPips=atrInitial;
}


// V3.190 S3: the stop distance in pips that a NEW order should carry. Order
// submission happens before any HybridTrailState exists, so it cannot read
// the frozen geometry and has to resolve the same figure independently.
// Every order-send path and every risk calculation uses this rather than
// InpPresetStopLossPips directly, so a variable stop cannot desync sizing
// from the stop actually placed.
// V2.0 S5: stop distance in pips from the zone's distal edge, or -1.0 when
// the zone cannot produce a usable one (no zone, degenerate geometry, or the
// zone is wider than InpDistalStopMaxPips allows).
double ResolveDistalStopPips()
{
   if(!InpUseZoneDistalStops || !g_distalContextValid)
      return -1.0;

   double lo=g_distalContextLo;
   double hi=g_distalContextHi;
   double entry=g_distalContextEntry;
   int direction=g_distalContextDirection;

   if(lo<=0.0 || hi<=lo || entry<=0.0 || direction==0)
      return -1.0;

   double pip=MathMax(StrategyPipSize(),_Point);
   double buffer=MathMax(0.0,InpDistalStopBufferPips)*pip;

   // Distal edge = the far side of the zone, the price at which the zone
   // premise is actually wrong. BUY at demand -> below the zone low.
   double distal=(direction==1) ? lo-buffer : hi+buffer;

   double distance=(direction==1) ? entry-distal : distal-entry;

   if(distance<=0.0)
      return -1.0;

   double pips=distance/pip;
   double minPips=MathMax(0.1,InpDistalStopMinPips);
   double maxPips=MathMax(minPips,InpDistalStopMaxPips);

   if(pips>maxPips)
   {
      // Too wide to be this setup. Fall back rather than clamp: clamping
      // would place a stop the zone does not justify while sizing as though
      // it did.
      if(InpFallbackToATRStop)
      {
         Log("V2.0 S5 DISTAL STOP FALLBACK | "+
             string(direction==1?"BUY":"SELL")+
             " | zone="+DoubleToString(lo,_Digits)+".."+DoubleToString(hi,_Digits)+
             " | distal would need "+DoubleToString(pips,1)+" pips"+
             " > max "+DoubleToString(maxPips,1)+
             " | using ATR/fixed stop instead");
         return -1.0;
      }

      pips=maxPips;
   }

   return MathMax(minPips,pips);
}


double ResolvedPresetStopPips()
{
   // V2.0 S5: a zone-derived stop takes precedence over ATR/fixed. Because
   // every order-send path AND the risk cap read this one function, sizing is
   // automatically computed against the stop actually placed - the variable
   // stop can never desync from the risk calculation.
   double distalPips=ResolveDistalStopPips();

   if(distalPips>0.0)
      return distalPips;

   double presetPips = MathMax(0.1,InpPresetStopLossPips);
   double armPips    = MathMax(0.0,InpTrailArmPips);
   double initPips   = MathMax(0.1,InpTrailInitialDistancePips);
   double tightPips  = MathMax(0.1,InpTrailTightDistancePips);
   double tightenAt  = MathMax(0.0,InpTrailTightenAtPips);
   double atrValue   = 0.0;

   ResolveATRGeometryPips(presetPips,armPips,initPips,tightPips,
                          tightenAt,atrValue);

   return presetPips;
}


void FreezeTrailGeometry(int index,int direction,double entry)
{
   double presetPips = MathMax(0.1,InpPresetStopLossPips);
   double armPips    = MathMax(0.0,InpTrailArmPips);
   double initPips   = MathMax(0.1,InpTrailInitialDistancePips);
   double tightPips  = MathMax(0.1,InpTrailTightDistancePips);
   double tightenAt  = MathMax(0.0,InpTrailTightenAtPips);
   double bePips     = MathMax(0.0,InpBreakevenLockAtPips);
   double beOffset   = MathMax(0.0,InpBreakevenLockOffsetPips);
   double atrValue   = 0.0;

   // V3.190 S3: ATR-sourced geometry replaces the fixed pip figures here,
   // before anything is converted to price distance. Frozen from this point.
   ResolveATRGeometryPips(presetPips,armPips,initPips,tightPips,
                          tightenAt,atrValue);

   // V2.0 S5: if this position's stop came from the zone's distal edge, the
   // trail and arm distances must scale with it or the S01 phase ratios drift
   // - a 30-pip stop with a 7-pip arm is a completely different trade shape
   // from a 12-pip stop with a 7-pip arm. Scaling keeps the shape constant.
   double actualPresetPips=ResolvedPresetStopPips();

   if(InpUseZoneDistalStops &&
      actualPresetPips>0.0 &&
      presetPips>0.0 &&
      MathAbs(actualPresetPips-presetPips)>0.01)
   {
      double stopRatio=actualPresetPips/presetPips;

      presetPips=actualPresetPips;
      armPips   *=stopRatio;
      initPips  *=stopRatio;
      tightPips *=stopRatio;
      tightenAt *=stopRatio;
      bePips    *=stopRatio;
      beOffset  *=stopRatio;
   }

   g_hybridTrailStates[index].presetDistance      =ProtectionPriceDistance(presetPips);
   g_hybridTrailStates[index].armDistance         =(armPips<=0.0)
                                                   ? 0.0
                                                   : ProtectionPriceDistance(armPips);
   g_hybridTrailStates[index].trailInitialDistance=ProtectionPriceDistance(initPips);
   g_hybridTrailStates[index].trailTightDistance  =ProtectionPriceDistance(tightPips);
   g_hybridTrailStates[index].tightenAtDistance   =ProtectionPriceDistance(MathMax(0.1,tightenAt));
   g_hybridTrailStates[index].breakevenAtDistance =ProtectionPriceDistance(MathMax(0.1,bePips));
   g_hybridTrailStates[index].breakevenOffset     =(beOffset<=0.0)
                                                   ? 0.0
                                                   : ProtectionPriceDistance(beOffset);
   // V2.0 S4: apply the grade's trail multiplier and partial target to the
   // frozen geometry. Resolved once here and never re-read.
   int grade=ResolvePositionZoneGrade(g_hybridTrailStates[index].ticket);
   double gradeTrail=GradeTrailMultiplier(grade);

   g_hybridTrailStates[index].zoneGrade=grade;
   g_hybridTrailStates[index].trailInitialDistance*=gradeTrail;
   g_hybridTrailStates[index].trailTightDistance  *=gradeTrail;
   g_hybridTrailStates[index].partialTargetDistance=
      ProtectionPriceDistance(GradePartialTPPips(grade));

   g_hybridTrailStates[index].frozenATR           =atrValue;
   g_hybridTrailStates[index].breakevenLocked     =false;
   g_hybridTrailStates[index].partialTaken        =false;
   g_hybridTrailStates[index].partialRequestedVolume=0.0;
   g_hybridTrailStates[index].geometryFrozen      =true;

   double pip=MathMax(StrategyPipSize(),_Point);

   Log("V3.190 S1 GEOMETRY FROZEN"+
       " | ticket="+(string)g_hybridTrailStates[index].ticket+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | entry="+DoubleToString(entry,_Digits)+
       " | preset="+DoubleToString(presetPips,1)+"p"+
       " | arm="+DoubleToString(armPips,1)+"p"+
       " | trail(initial)="+DoubleToString(initPips,1)+"p"+
       " | tighten@="+DoubleToString(tightenAt,1)+"p"+
       " -> trail(tight)="+DoubleToString(tightPips,1)+"p"+
       " | BE lock="+string(InpUseBreakevenLock?"ON":"OFF")+
       " @"+DoubleToString(bePips,1)+"p"+
       " +"+DoubleToString(beOffset,1)+"p"+
       " | grade="+
       (grade>0?ZoneGradeText(grade)+" (trail x"+DoubleToString(gradeTrail,2)+
                ", partial "+DoubleToString(GradePartialTPPips(grade),1)+"p)"
              :"ungraded")+
       " | ATR geometry="+string(InpUseATRGeometry?"ON":"OFF")+
       (atrValue>0.0
        ?" | frozen ATR="+DoubleToString(atrValue/pip,1)+"p"
        :""));
}

int EnsureHybridTrailState(ulong ticket,
                           int direction,
                           double entry,
                           double current,
                           datetime positionTime,
                           MqlTick &tick)
{
   int index=HybridTrailStateIndex(ticket);
   if(index>=0)
      return index;

   index=ArraySize(g_hybridTrailStates);
   ArrayResize(g_hybridTrailStates,index+1);
   ZeroMemory(g_hybridTrailStates[index]);

   g_hybridTrailStates[index].ticket=ticket;
   g_hybridTrailStates[index].active=false;
   g_hybridTrailStates[index].reconstructed=false;
   g_hybridTrailStates[index].peakPrice=current;
   g_hybridTrailStates[index].virtualStop=0.0;
   g_hybridTrailStates[index].positionTime=positionTime;
   g_hybridTrailStates[index].initializedClock=TimeCurrent();

   FreezeTrailGeometry(index,direction,entry);

   g_hybridTrailStates[index].peakPrice=
      ReconstructTrailPeak(direction,entry,positionTime,tick);
   g_hybridTrailStates[index].reconstructed=true;
   return index;
}

// EXIT MODIFY BACKOFF: shared formula for the extra clearance added per
// consecutive rejected modify on a ticket. Scales with the symbol's own
// current price (percentage, not a fixed point count), so the same
// InpExitBackoffCushionStepPct is meaningful on BTCUSD's $65,000 scale and
// on XAUUSD's $2,000 scale alike - unlike the point-based cushions above,
// which are negligible in dollar terms on a high-priced symbol like BTC.
double ExitBackoffCushionPrice(double referencePrice,int backoffSteps)
{
   int steps=MathMin(MathMax(0,backoffSteps),MathMax(0,InpExitBackoffMaxSteps));
   if(steps<=0 || referencePrice<=0.0)
      return 0.0;
   return referencePrice*MathMax(0.0,InpExitBackoffCushionStepPct)/100.0*steps;
}

double BrokerTrailMinimumDistance(double current,int backoffSteps)
{
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   int cushion=MathMax(MathMax(0,InpExecutionStopCushionPoints),
                       MathMax(0,InpTrailBrokerCushionPoints));

   double base=MathMax(_Point,
                       ((double)MathMax(stopsLevel,freezeLevel)+cushion)*_Point);

   return base+ExitBackoffCushionPrice(current,backoffSteps);
}

double BrokerCompatibleTrailSL(int direction,
                               double current,
                               double virtualStop,
                               int backoffSteps)
{
   double minDistance=BrokerTrailMinimumDistance(current,backoffSteps);
   double allowed=(direction==1)?current-minDistance:current+minDistance;
   double candidate=(direction==1)
                    ? MathMin(virtualStop,allowed)
                    : MathMax(virtualStop,allowed);
   return RoundProtectionStop(direction,candidate);
}


int ExitExecutionStateIndexByTicket(ulong ticket)
{
   for(int i=0;i<ArraySize(g_exitExecutionStates);i++)
   {
      if(g_exitExecutionStates[i].ticket==ticket)
         return i;
   }

   return -1;
}


int ExitExecutionStateIndexByIdentifier(long positionIdentifier)
{
   if(positionIdentifier<=0)
      return -1;

   for(int i=0;i<ArraySize(g_exitExecutionStates);i++)
   {
      if(g_exitExecutionStates[i].positionIdentifier==
         positionIdentifier)
         return i;
   }

   return -1;
}


int EnsureExitExecutionState(ulong ticket)
{
   int index=ExitExecutionStateIndexByTicket(ticket);

   if(index>=0)
      return index;

   if(!PositionSelectByTicket(ticket))
      return -1;

   index=ArraySize(g_exitExecutionStates);
   ArrayResize(g_exitExecutionStates,index+1);
   ZeroMemory(g_exitExecutionStates[index]);

   g_exitExecutionStates[index].ticket=ticket;
   g_exitExecutionStates[index].positionIdentifier=
      (long)PositionGetInteger(POSITION_IDENTIFIER);

   ENUM_POSITION_TYPE type=
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   g_exitExecutionStates[index].direction=
      type==POSITION_TYPE_BUY ? 1 : -1;

   return index;
}


bool ExitCloseInProgress(ulong ticket)
{
   if(!InpSynchronizeExitRequests)
      return false;

   int index=ExitExecutionStateIndexByTicket(ticket);

   if(index<0 ||
      !g_exitExecutionStates[index].closeInProgress)
      return false;

   ulong now=NowMs();

   if(now<g_exitExecutionStates[index].closeLockUntilMs)
      return true;

   if(PositionSelectByTicket(ticket))
   {
      Log("V3.176 EXIT CLOSE LOCK TIMEOUT"+
          " | ticket="+(string)ticket+
          " | reason="+
          g_exitExecutionStates[index].closeReason+
          " | retry permitted=YES");
   }

   g_exitExecutionStates[index].closeInProgress=false;
   return false;
}


double LatestBrokerValidExitSL(int direction,
                               double virtualStop,
                               MqlTick &tick,
                               int backoffSteps)
{
   if(!SymbolInfoTick(_Symbol,tick))
      return 0.0;

   double current=
      direction==1 ? tick.bid : tick.ask;

   if(current<=0.0 || virtualStop<=0.0)
      return 0.0;

   long stopsLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   long freezeLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   int cushion=
      MathMax(
         MathMax(
            MathMax(0,InpExecutionStopCushionPoints),
            MathMax(0,InpTrailBrokerCushionPoints)),
         MathMax(0,InpExitExtraStopCushionPoints));

   double minimumDistance=
      MathMax(
         ProtectionTickSize(),
         ((double)MathMax(stopsLevel,freezeLevel)+
          cushion)*_Point)+
      ExitBackoffCushionPrice(current,backoffSteps);

   double allowed=
      direction==1
      ? current-minimumDistance
      : current+minimumDistance;

   double candidate=
      direction==1
      ? MathMin(virtualStop,allowed)
      : MathMax(virtualStop,allowed);

   candidate=RoundProtectionStop(direction,candidate);

   // One extra tradable tick prevents a borderline level from becoming
   // invalid while the request is traveling to the trade server.
   if(direction==1 &&
      candidate>current-minimumDistance)
      candidate=RoundProtectionStop(
         direction,
         current-minimumDistance-
         ProtectionTickSize());

   if(direction==-1 &&
      candidate<current+minimumDistance)
      candidate=RoundProtectionStop(
         direction,
         current+minimumDistance+
         ProtectionTickSize());

   return candidate;
}


bool RequestSynchronizedPositionModify(ulong ticket,
                                       int direction,
                                       double virtualStop,
                                       double tp,
                                       string context,
                                       string purpose,
                                       double &submittedSL)
{
   submittedSL=0.0;

   if(!PositionSelectByTicket(ticket))
      return false;

   int stateIndex=EnsureExitExecutionState(ticket);
   if(stateIndex<0)
      return false;

   if(ExitCloseInProgress(ticket))
      return false;

   ulong now=NowMs();

   if(InpSynchronizeExitRequests &&
      now<g_exitExecutionStates[stateIndex].modifyCooldownUntilMs)
      return false;

   if(InpSynchronizeExitRequests &&
      g_exitExecutionStates[stateIndex].lastModifyAttemptMs>0 &&
      now-g_exitExecutionStates[stateIndex].lastModifyAttemptMs<
      (ulong)MathMax(0,InpExitModifyMinimumIntervalMs))
      return false;

   // EXIT MODIFY BACKOFF: how many times IN A ROW has this ticket's modify
   // been rejected (broker or pre-send check)? Feeds a widening clearance
   // into both checks below, and an exponential retry cooldown further
   // down, so a systematically-invalid modify backs off instead of
   // hammering the server at a fixed rate forever. See
   // InpExitBackoffCushionStepPct.
   int backoffSteps=g_exitExecutionStates[stateIndex].consecutiveInvalidStops;

   MqlTick latestTick;
   double brokerSL=
      LatestBrokerValidExitSL(
         direction,
         virtualStop,
         latestTick,
         backoffSteps);

   if(brokerSL<=0.0)
      return false;

   double current=
      direction==1 ? latestTick.bid : latestTick.ask;

   if(!FixedTrailSLBrokerValid(direction,current,brokerSL,backoffSteps))
   {
      int failCount=++g_exitExecutionStates[stateIndex].consecutiveInvalidStops;
      int backoffCooldown=
         (int)MathMin(
            (double)MathMax(0,InpExitBackoffCooldownCapMs),
            (double)MathMax(0,InpExitInvalidStopsCooldownMs)*
            (double)(1<<MathMin(failCount,10)));

      g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
         now+(ulong)backoffCooldown;

      Log("V3.176 SYNCHRONIZED SL PRE-SEND REJECTED (backoff) | "+context+
          " | purpose="+purpose+
          " | ticket="+(string)ticket+
          " | consecutive failures="+IntegerToString(failCount)+
          " | widened clearance="+
          DoubleToString(ExitBackoffCushionPrice(current,backoffSteps),_Digits)+
          " | next retry in="+IntegerToString(backoffCooldown)+"ms");
      return false;
   }

   g_exitExecutionStates[stateIndex].lastModifyAttemptMs=now;
   g_exitExecutionStates[stateIndex].lastRequestedSL=brokerSL;

   bool sent=trade.PositionModify(ticket,brokerSL,tp);
   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);

   g_exitExecutionStates[stateIndex].lastModifyRetcode=code;

   if(accepted)
   {
      g_exitExecutionStates[stateIndex].consecutiveInvalidStops=0;

      g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
         now+
         (ulong)MathMax(
            0,
            InpExitModifyMinimumIntervalMs);

      submittedSL=brokerSL;

      Log("V3.176 SYNCHRONIZED SL ACCEPTED | "+context+
          " | purpose="+purpose+
          " | ticket="+(string)ticket+
          " | Bid="+DoubleToString(latestTick.bid,_Digits)+
          " | Ask="+DoubleToString(latestTick.ask,_Digits)+
          " | virtualSL="+DoubleToString(virtualStop,_Digits)+
          " | submittedSL="+DoubleToString(brokerSL,_Digits));
      return true;
   }

   int failCount=++g_exitExecutionStates[stateIndex].consecutiveInvalidStops;

   int cooldown=
      code==TRADE_RETCODE_INVALID_STOPS
      ? (int)MathMin(
           (double)MathMax(0,InpExitBackoffCooldownCapMs),
           (double)MathMax(0,InpExitInvalidStopsCooldownMs)*
           (double)(1<<MathMin(failCount,10)))
      : MathMax(0,InpExitModifyMinimumIntervalMs);

   g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
      now+(ulong)cooldown;

   Log("V3.176 SYNCHRONIZED SL REJECTED | "+context+
       " | purpose="+purpose+
       " | ticket="+(string)ticket+
       " | Bid="+DoubleToString(latestTick.bid,_Digits)+
       " | Ask="+DoubleToString(latestTick.ask,_Digits)+
       " | virtualSL="+DoubleToString(virtualStop,_Digits)+
       " | submittedSL="+DoubleToString(brokerSL,_Digits)+
       " | stopLevel="+
       IntegerToString(
          (int)SymbolInfoInteger(
             _Symbol,
             SYMBOL_TRADE_STOPS_LEVEL))+
       " | freezeLevel="+
       IntegerToString(
          (int)SymbolInfoInteger(
             _Symbol,
             SYMBOL_TRADE_FREEZE_LEVEL))+
       " | consecutive failures="+IntegerToString(failCount)+
       " | cooldown="+IntegerToString(cooldown)+"ms"+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());

   return false;
}


// V3.190 S2: gained a trailing closeVolume parameter. It defaults to 0.0,
// which means "close the whole position" - the exact V3.176 behaviour - so
// every pre-existing call site is unchanged. A positive value below the
// position's volume routes through PositionClosePartial instead, which lets
// the S02 partial take profit inherit this function's close-lock and
// rejection handling rather than bypassing it.
bool RequestSynchronizedPositionClose(ulong ticket,
                                      string context,
                                      double stop,
                                      double peak,
                                      ulong deviation,
                                      double closeVolume=0.0)
{
   if(!PositionSelectByTicket(ticket))
      return false;

   int stateIndex=EnsureExitExecutionState(ticket);
   if(stateIndex<0)
      return false;

   if(ExitCloseInProgress(ticket))
      return true;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   ENUM_POSITION_TYPE type=
      (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

   int direction=
      type==POSITION_TYPE_BUY ? 1 : -1;

   double requestedClosePrice=
      direction==1 ? tick.bid : tick.ask;

   ulong now=NowMs();

   g_exitExecutionStates[stateIndex].positionIdentifier=
      (long)PositionGetInteger(POSITION_IDENTIFIER);
   g_exitExecutionStates[stateIndex].direction=direction;
   g_exitExecutionStates[stateIndex].closeInProgress=true;
   g_exitExecutionStates[stateIndex].closeRequestMs=now;
   g_exitExecutionStates[stateIndex].closeLockUntilMs=
      now+
      (ulong)MathMax(
         250,
         InpExitCloseLockTimeoutMs);
   g_exitExecutionStates[stateIndex].requestedClosePrice=
      requestedClosePrice;
   g_exitExecutionStates[stateIndex].requestedStop=stop;
   g_exitExecutionStates[stateIndex].peakPrice=peak;
   g_exitExecutionStates[stateIndex].closeReason=context;

   // V3.190 S2: decide full vs partial. A requested volume that meets or
   // exceeds the live position volume degrades to a full close, and so does a
   // request that would strand a remainder under the broker minimum - never
   // leave an unclosable stub behind.
   double positionVolume=PositionGetDouble(POSITION_VOLUME);
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double partialVolume=0.0;

   if(closeVolume>0.0 && positionVolume>0.0)
   {
      double requestVolume=NormalizeVolumeDown(MathMin(closeVolume,positionVolume));
      double remainder=positionVolume-requestVolume;

      if(requestVolume>=minVolume-1e-12 &&
         requestVolume<positionVolume-1e-12 &&
         remainder>=minVolume-1e-12)
         partialVolume=requestVolume;
   }

   g_exitExecutionStates[stateIndex].partialCloseVolume=partialVolume;

   trade.SetDeviationInPoints(deviation);
   bool sent=(partialVolume>0.0)
             ? trade.PositionClosePartial(ticket,partialVolume,deviation)
             : trade.PositionClose(ticket,deviation);
   uint code=trade.ResultRetcode();
   trade.SetDeviationInPoints(
      (ulong)MathMax(0,InpDeviationPoints));

   bool accepted=
      sent && TradeRetcodeAccepted(code);

   // V3.190 S2: the close request itself can come back partially filled. That
   // is an accepted outcome, but the caller must not assume the volume it
   // asked for actually left the book - surface it so a short fill is visible
   // in the journal instead of being read as a clean close.
   bool partiallyFilled=TradeRetcodePartial(code);

   bool alreadyClosing=
      code==TRADE_RETCODE_CLOSE_ORDER_EXIST;

   if(accepted || alreadyClosing)
   {
      Log("V3.176 SYNCHRONIZED CLOSE REQUEST | "+context+
          " | ticket="+(string)ticket+
          " | position id="+
          (string)g_exitExecutionStates[stateIndex].positionIdentifier+
          " | requested price="+
          DoubleToString(requestedClosePrice,_Digits)+
          " | stop="+DoubleToString(stop,_Digits)+
          " | peak="+DoubleToString(peak,_Digits)+
          " | deviation="+(string)deviation+
          " | volume="+
          (partialVolume>0.0
           ? DoubleToString(partialVolume,VolumeDigits())+" of "+
             DoubleToString(positionVolume,VolumeDigits())+" (PARTIAL)"
           : DoubleToString(positionVolume,VolumeDigits())+" (FULL)")+
          " | close lock="+
          IntegerToString(
             MathMax(250,InpExitCloseLockTimeoutMs))+
          "ms"+
          " | retcode="+IntegerToString((int)code)+
          (partiallyFilled
           ? " | WARNING partial fill on the close request itself"
             " - requested volume did not fully execute"
           : ""));
      return true;
   }

   g_exitExecutionStates[stateIndex].closeInProgress=false;

   Log("V3.176 SYNCHRONIZED CLOSE REJECTED | "+context+
       " | ticket="+(string)ticket+
       " | requested price="+
       DoubleToString(requestedClosePrice,_Digits)+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());

   return false;
}


void HandleExitExecutionTransaction(
   const MqlTradeTransaction &trans)
{
   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD ||
      trans.deal==0 ||
      !HistoryDealSelect(trans.deal))
      return;

   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL)!=_Symbol ||
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)!=
      InpMagicNumber)
      return;

   ENUM_DEAL_ENTRY entry=
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(
         trans.deal,
         DEAL_ENTRY);

   if(entry!=DEAL_ENTRY_OUT &&
      entry!=DEAL_ENTRY_OUT_BY)
      return;

   long positionIdentifier=
      (long)HistoryDealGetInteger(
         trans.deal,
         DEAL_POSITION_ID);

   int stateIndex=
      ExitExecutionStateIndexByIdentifier(
         positionIdentifier);

   if(stateIndex<0 ||
      !g_exitExecutionStates[stateIndex].closeInProgress)
      return;

   double fillPrice=
      HistoryDealGetDouble(trans.deal,DEAL_PRICE);

   double fillVolume=
      HistoryDealGetDouble(trans.deal,DEAL_VOLUME);

   double requested=
      g_exitExecutionStates[stateIndex].requestedClosePrice;

   int direction=
      g_exitExecutionStates[stateIndex].direction;

   double adversePrice=
      direction==1
      ? requested-fillPrice
      : fillPrice-requested;

   double strategyPip=
      MathMax(
         StrategyPipSize(),
         _Point);

   double adversePips=
      adversePrice/strategyPip;

   ulong now=NowMs();
   ulong elapsed=
      now>=g_exitExecutionStates[stateIndex].closeRequestMs
      ? now-g_exitExecutionStates[stateIndex].closeRequestMs
      : 0;

   if(InpExitLogFillSlippage)
   {
      Log("V3.176 LIVE EXIT FILL"+
          " | reason="+
          g_exitExecutionStates[stateIndex].closeReason+
          " | ticket="+
          (string)g_exitExecutionStates[stateIndex].ticket+
          " | position id="+
          (string)positionIdentifier+
          " | requested="+
          DoubleToString(requested,_Digits)+
          " | fill="+
          DoubleToString(fillPrice,_Digits)+
          " | adverse slippage="+
          DoubleToString(adversePips,1)+" pips"+
          " | volume="+
          DoubleToString(fillVolume,VolumeDigits())+
          " | elapsed="+(string)elapsed+"ms"+
          " | stop="+
          DoubleToString(
             g_exitExecutionStates[stateIndex].requestedStop,
             _Digits)+
          " | peak="+
          DoubleToString(
             g_exitExecutionStates[stateIndex].peakPrice,
             _Digits));
   }

   g_exitExecutionStates[stateIndex].closeInProgress=false;
   g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
      now+
      (ulong)MathMax(
         0,
         InpExitModifyMinimumIntervalMs);
}


void PruneExitExecutionStates()
{
   for(int i=ArraySize(g_exitExecutionStates)-1;i>=0;i--)
   {
      ulong ticket=g_exitExecutionStates[i].ticket;

      if(ticket>0 && PositionSelectByTicket(ticket))
         continue;

      if(g_exitExecutionStates[i].closeInProgress)
         continue;

      int last=ArraySize(g_exitExecutionStates)-1;

      if(i<last)
         g_exitExecutionStates[i]=
            g_exitExecutionStates[last];

      ArrayResize(g_exitExecutionStates,last);
   }
}


bool ClosePositionAtVirtualTrail(ulong ticket,
                                 string context,
                                 double current,
                                 double stop,
                                 double peak)
{
   ulong deviation=
      (ulong)MathMax(
         0,
         InpVirtualTrailCloseDeviationPts);

   bool accepted=
      RequestSynchronizedPositionClose(
         ticket,
         "HYBRID VIRTUAL TRAIL "+context,
         stop,
         peak,
         deviation);

   if(!accepted)
   {
      Log("HYBRID VIRTUAL TRAIL CLOSE FAILED | "+context+
          " | ticket="+(string)ticket+
          " | observed="+DoubleToString(current,_Digits)+
          " | virtualSL="+DoubleToString(stop,_Digits));
   }

   return accepted;
}

void PruneHybridTrailStates()
{
   for(int i=ArraySize(g_hybridTrailStates)-1;i>=0;i--)
   {
      ulong ticket=g_hybridTrailStates[i].ticket;
      if(ticket>0 && PositionSelectByTicket(ticket))
         continue;

      int last=ArraySize(g_hybridTrailStates)-1;
      if(i<last)
         g_hybridTrailStates[i]=g_hybridTrailStates[last];
      ArrayResize(g_hybridTrailStates,last);
   }
}

void ManageHybridTrailingPositions(string context)
{
   if(!InpUseFixedPipTrail)
      return;

   // V3.190 S3: no-op unless a new bar of InpATRTimeframe has formed.
   RefreshGeometryATR();

   // V2.0 S1: no-op unless a new H1 bar has formed.
   RefreshH1Bias();

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double strategyPip=StrategyPipSize();
   // V3.190 S1: trail/preset/arm distances are no longer function-level
   // constants. They are frozen per position in HybridTrailState and read
   // back inside the loop, so a position keeps the geometry it opened with.
   double minimumStep=MathMax(ProtectionTickSize(),
                              ProtectionPriceDistance(InpTrailingStepPips));

   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int direction=(type==POSITION_TYPE_BUY)?1:-1;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double current=(direction==1)?tick.bid:tick.ask;
      double currentSL=PositionGetDouble(POSITION_SL);
      double currentTP=PositionGetDouble(POSITION_TP);
      datetime positionTime=(datetime)PositionGetInteger(POSITION_TIME);

      // Do not modify or close the same ticket again while the first
      // accepted close request is waiting for its closing deal.
      if(ExitCloseInProgress(ticket))
         continue;

      // V3.081 has no take profit. Remove a TP left by an older EA build
      // while preserving the currently installed broker SL.
      if(!InpUseTakeProfit && currentTP>0.0)
      {
         bool tpRemoved=trade.PositionModify(ticket,currentSL,0.0);
         uint tpRemoveCode=trade.ResultRetcode();
         if(tpRemoved && TradeRetcodeAccepted(tpRemoveCode))
         {
            currentTP=0.0;
            Log("NO-TP CLEANUP | removed inherited TP | "+context+
                " | ticket="+(string)ticket);
         }
         else
         {
            Log("NO-TP CLEANUP FAILED | "+context+
                " | ticket="+(string)ticket+
                " | retcode="+IntegerToString((int)tpRemoveCode)+
                " | "+trade.ResultRetcodeDescription());
         }
      }

      int stateIndex=EnsureHybridTrailState(ticket,direction,entry,current,positionTime,tick);
      if(stateIndex<0) continue;

      if(direction==1)
         g_hybridTrailStates[stateIndex].peakPrice=MathMax(g_hybridTrailStates[stateIndex].peakPrice,current);
      else
         g_hybridTrailStates[stateIndex].peakPrice=MathMin(g_hybridTrailStates[stateIndex].peakPrice,current);

      double peak=g_hybridTrailStates[stateIndex].peakPrice;
      double peakFavourable=(direction==1)?peak-entry:entry-peak;

      // ---------------- V3.190 S2 partial take profit ----------------
      // Evaluated BEFORE the trail so a touched target banks volume on this
      // pass rather than waiting for the next one. Uses the CURRENT price,
      // not the peak: we only bank what is actually available right now.
      if(InpUsePartialTakeProfit &&
         !g_hybridTrailStates[stateIndex].partialTaken)
      {
         double currentFavourable=(direction==1)?current-entry:entry-current;
         // V2.0 S4: grade-differentiated partial target, frozen at open.
         double partialTarget=
            (g_hybridTrailStates[stateIndex].partialTargetDistance>0.0)
            ? g_hybridTrailStates[stateIndex].partialTargetDistance
            : ProtectionPriceDistance(MathMax(0.1,InpPartialTPPips));

         if(currentFavourable>=partialTarget-_Point*0.25)
         {
            double positionVolume=PositionGetDouble(POSITION_VOLUME);
            double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
            double pct=MathMax(0.0,MathMin(100.0,InpPartialTPPercent));
            double wanted=NormalizeVolumeDown(positionVolume*pct/100.0);
            double remainder=positionVolume-wanted;

            // Degrade to a full close when a partial is not cleanly possible.
            bool fullInstead=(wanted<minVolume-1e-12) ||
                             (remainder<minVolume-1e-12) ||
                             (wanted>=positionVolume-1e-12);

            double requestVolume=fullInstead?0.0:wanted;

            // Mark BEFORE sending. The close is asynchronous - leaving the
            // flag until the fill arrives would let the next tick fire a
            // second partial on the same position.
            g_hybridTrailStates[stateIndex].partialTaken=true;
            g_hybridTrailStates[stateIndex].partialRequestedVolume=requestVolume;

            bool partialSent=
               RequestSynchronizedPositionClose(
                  ticket,
                  "V3.190 S2 PARTIAL TP",
                  g_hybridTrailStates[stateIndex].virtualStop,
                  peak,
                  (ulong)MathMax(0,InpVirtualTrailCloseDeviationPts),
                  requestVolume);

            Log("V3.190 S2 PARTIAL TP "+
                string(partialSent?"REQUESTED":"REJECTED")+" | "+context+
                " | ticket="+(string)ticket+
                " | target="+DoubleToString(InpPartialTPPips,1)+" pips"+
                " | favourable="+DoubleToString(currentFavourable/strategyPip,1)+" pips"+
                " | position volume="+DoubleToString(positionVolume,VolumeDigits())+
                " | requested="+
                (fullInstead
                 ? "FULL CLOSE (remainder would be below broker minimum "+
                   DoubleToString(minVolume,VolumeDigits())+")"
                 : DoubleToString(requestVolume,VolumeDigits())+" ("+
                   DoubleToString(pct,1)+"%)")+
                " | BE after partial="+
                string(InpBreakevenAfterPartial?"YES":"NO"));

            if(!partialSent)
            {
               // Allow a retry on a later pass rather than silently
               // abandoning the target after one rejection.
               g_hybridTrailStates[stateIndex].partialTaken=false;
               g_hybridTrailStates[stateIndex].partialRequestedVolume=0.0;
            }
            else if(fullInstead)
            {
               continue;
            }
         }
      }

      // V3.190 S2: once a partial has actually reduced the position, put a
      // breakeven+offset floor under the remainder. Folded into the same
      // ratchet as every other stop movement, so it can only improve.
      if(InpUsePartialTakeProfit &&
         InpBreakevenAfterPartial &&
         g_hybridTrailStates[stateIndex].partialTaken &&
         g_hybridTrailStates[stateIndex].partialRequestedVolume>0.0 &&
         !g_hybridTrailStates[stateIndex].breakevenLocked)
      {
         double beOffsetAfterPartial=
            (MathMax(0.0,InpBreakevenLockOffsetPips)<=0.0)
            ? 0.0
            : ProtectionPriceDistance(InpBreakevenLockOffsetPips);

         double beStop=RoundProtectionStop(
            direction,
            direction==1 ? entry+beOffsetAfterPartial
                         : entry-beOffsetAfterPartial);

         if(TrailStopImproves(direction,
                              beStop,
                              g_hybridTrailStates[stateIndex].virtualStop,
                              0.0))
         {
            g_hybridTrailStates[stateIndex].virtualStop=beStop;
         }

         g_hybridTrailStates[stateIndex].breakevenLocked=true;

         Log("V3.190 S2 BREAKEVEN AFTER PARTIAL | "+context+
             " | ticket="+(string)ticket+
             " | entry="+DoubleToString(entry,_Digits)+
             " | floor="+DoubleToString(beStop,_Digits)+
             " | remainder rides on the S01 trail from here");
      }

      // ---------------- V3.190 S1 phase machine ----------------
      // Geometry was frozen at EnsureHybridTrailState() time and never
      // changes for the life of the position. Every phase contributes a
      // CANDIDATE stop; the candidates are combined with TrailBetterStop()
      // and then ratcheted into state.virtualStop, which can only ever
      // improve. That single ratchet is what guarantees monotonicity across
      // phase transitions - widening the trail distance, or an ATR change
      // under S03, can never drag an advanced stop backwards.
      double gPreset  =g_hybridTrailStates[stateIndex].presetDistance;
      double gArm     =g_hybridTrailStates[stateIndex].armDistance;
      double gInitial =g_hybridTrailStates[stateIndex].trailInitialDistance;
      double gTighten =g_hybridTrailStates[stateIndex].tightenAtDistance;
      double gTight   =g_hybridTrailStates[stateIndex].trailTightDistance;
      double gBeAt    =g_hybridTrailStates[stateIndex].breakevenAtDistance;
      double gBeOffset=g_hybridTrailStates[stateIndex].breakevenOffset;

      // PHASE 0 - preset stop. Active from fill, before any favourable move.
      double initialVirtualStop=RoundProtectionStop(
         direction,
         direction==1 ? entry-gPreset : entry+gPreset);

      if(g_hybridTrailStates[stateIndex].virtualStop<=0.0)
         g_hybridTrailStates[stateIndex].virtualStop=initialVirtualStop;

      double candidateStop=initialVirtualStop;

      double activationDistance=
         LiveTrailActivationDistance(tick,gArm);

      bool liveProtectionChart=
         InpLiveXAUProtectionParity && IsLiveXAUUSDscProtectionChart();

      bool liveWarmupComplete=
         !liveProtectionChart ||
         InpLiveXAUTrailWarmupSeconds<=0 ||
         TimeCurrent()>=g_hybridTrailStates[stateIndex].initializedClock+
                        InpLiveXAUTrailWarmupSeconds;

      // PHASE 1 - arm the trail once the peak clears the ARM distance, which
      // is now independent of the trail distance itself.
      if(InpEnableTrailingAfterEntry &&
         !g_hybridTrailStates[stateIndex].active &&
         liveWarmupComplete &&
         peakFavourable>=activationDistance-_Point*0.25)
      {
         g_hybridTrailStates[stateIndex].active=true;
         Log("V3.190 S1 TRAIL ARMED | "+context+
             " | ticket="+(string)ticket+
             " | entry="+DoubleToString(entry,_Digits)+
             " | peak="+DoubleToString(peak,_Digits)+
             " | favourable="+DoubleToString(peakFavourable/strategyPip,1)+" pips"+
             " | arm required="+DoubleToString(activationDistance/strategyPip,1)+" pips"+
             " | initial trail="+DoubleToString(gInitial/strategyPip,1)+" pips"+
             " | live parity="+string(liveProtectionChart?"YES":"NO"));
      }

      if(InpEnableTrailingAfterEntry && g_hybridTrailStates[stateIndex].active)
      {
         // PHASE 3 selection - tight distance once the peak clears the
         // tighten threshold, otherwise the initial (wider) distance.
         bool tightened=(peakFavourable>=gTighten-_Point*0.25);
         double activeTrail=tightened?gTight:gInitial;

         double trailStop=RoundProtectionStop(
            direction,
            direction==1 ? peak-activeTrail : peak+activeTrail);

         candidateStop=TrailBetterStop(direction,candidateStop,trailStop);
      }

      // PHASE 2 - breakeven floor. A FLOOR under the trail, not a
      // replacement: it is folded in with TrailBetterStop() so whichever of
      // the two is more protective wins, and the trail keeps ratcheting past
      // it afterwards.
      if(InpUseBreakevenLock &&
         peakFavourable>=gBeAt-_Point*0.25)
      {
         double beStop=RoundProtectionStop(
            direction,
            direction==1 ? entry+gBeOffset : entry-gBeOffset);

         candidateStop=TrailBetterStop(direction,candidateStop,beStop);

         if(!g_hybridTrailStates[stateIndex].breakevenLocked)
         {
            g_hybridTrailStates[stateIndex].breakevenLocked=true;
            Log("V3.190 S1 BREAKEVEN FLOOR ENGAGED | "+context+
                " | ticket="+(string)ticket+
                " | entry="+DoubleToString(entry,_Digits)+
                " | favourable="+DoubleToString(peakFavourable/strategyPip,1)+" pips"+
                " | floor="+DoubleToString(beStop,_Digits)+
                " (entry "+string(direction==1?"+":"-")+
                DoubleToString(gBeOffset/strategyPip,1)+" pips)");
         }
      }

      // RATCHET - the only place virtualStop is allowed to move.
      if(TrailStopImproves(direction,
                           candidateStop,
                           g_hybridTrailStates[stateIndex].virtualStop,
                           0.0))
      {
         g_hybridTrailStates[stateIndex].virtualStop=candidateStop;
      }

      double virtualStop=g_hybridTrailStates[stateIndex].virtualStop;

      bool virtualHit=(direction==1)
                      ? current<=virtualStop+_Point*0.25
                      : current>=virtualStop-_Point*0.25;

      if(InpUseVirtualTrailFallback && virtualHit)
      {
         ClosePositionAtVirtualTrail(ticket,context,current,virtualStop,peak);
         continue;
      }

      // Push the ratcheted virtual stop out to the broker. The step filter
      // only throttles how often we talk to the server; it never permits a
      // backwards move because virtualStop itself is already monotonic.
      // EXIT MODIFY BACKOFF: mirror the same widening clearance used inside
      // RequestSynchronizedPositionModify() here, so this pre-filter agrees
      // with the authoritative check instead of optimistically offering a
      // desiredSL that the deeper check (correctly) rejects every time.
      int exitStateIndex=ExitExecutionStateIndexByTicket(ticket);
      int trailBackoffSteps=
         exitStateIndex>=0
         ? g_exitExecutionStates[exitStateIndex].consecutiveInvalidStops
         : 0;

      double desiredSL=BrokerCompatibleTrailSL(direction,current,virtualStop,trailBackoffSteps);

      bool improves=
         TrailStopImproves(direction,
                           desiredSL,
                           currentSL,
                           g_hybridTrailStates[stateIndex].active
                           ? minimumStep-_Point*0.25
                           : _Point*0.25);

      if(improves && desiredSL>0.0 &&
         FixedTrailSLBrokerValid(direction,current,desiredSL,trailBackoffSteps))
      {
         double submittedSL=0.0;
         bool accepted=
            RequestSynchronizedPositionModify(
               ticket,
               direction,
               virtualStop,
               currentTP,
               context,
               g_hybridTrailStates[stateIndex].active?"TRAILING SL":"PRESET SL",
               submittedSL);

         if(accepted)
         {
            currentSL=submittedSL;

            Log("V3.190 S1 BROKER SL MOVED | "+context+
                " | ticket="+(string)ticket+
                " | peak="+DoubleToString(peak,_Digits)+
                " | favourable="+DoubleToString(peakFavourable/strategyPip,1)+" pips"+
                " | virtualSL="+DoubleToString(virtualStop,_Digits)+
                " | brokerSL="+DoubleToString(submittedSL,_Digits)+
                " | phase="+
                string(!g_hybridTrailStates[stateIndex].active
                       ?"PRESET"
                       :(peakFavourable>=gTighten-_Point*0.25
                         ?"TIGHT TRAIL"
                         :"INITIAL TRAIL"))+
                (g_hybridTrailStates[stateIndex].breakevenLocked?" +BE FLOOR":""));
         }
      }

      // Optional fixed take-profit compatibility path. Disabled by default in V3.081.
      // When disabled, any TP inherited from a previous build is removed.

      if(InpUseTakeProfit)
      {
         double requestedTP=RoundPrice(direction==1
                                       ? entry+MathMax(0.1,InpFixedTakeProfitPips)*strategyPip
                                       : entry-MathMax(0.1,InpFixedTakeProfitPips)*strategyPip);
         bool exactTPHit=(direction==1)
                         ? current>=requestedTP-_Point*0.25
                         : current<=requestedTP+_Point*0.25;
         if(exactTPHit)
         {
         ulong deviation=
            (ulong)MathMax(
               0,
               InpVirtualTrailCloseDeviationPts);

         bool tpClosed=
            RequestSynchronizedPositionClose(
               ticket,
               "FIXED VIRTUAL TP "+context,
               requestedTP,
               current,
               deviation);

         if(tpClosed)
         {
            Log("FIXED VIRTUAL TP CLOSE REQUESTED | "+context+
                " | ticket="+(string)ticket+
                " | entry="+DoubleToString(entry,_Digits)+
                " | target="+DoubleToString(requestedTP,_Digits)+
                " | current="+DoubleToString(current,_Digits));
            continue;
         }

         Log("FIXED VIRTUAL TP CLOSE FAILED | "+context+
             " | ticket="+(string)ticket+
             " | target="+DoubleToString(requestedTP,_Digits));
      }

      double brokerTP=BrokerSafeExecutionTP(direction,entry,requestedTP);
      bool tpNeedsInstall=InpUseTakeProfit &&
                          (currentTP<=0.0 || MathAbs(currentTP-brokerTP)>_Point*0.5);
      if(tpNeedsInstall && PositionSelectByTicket(ticket))
      {
         double retainedSL=PositionGetDouble(POSITION_SL);
         bool sent=trade.PositionModify(ticket,retainedSL,brokerTP);
         uint code=trade.ResultRetcode();
         if(!sent || !TradeRetcodeAccepted(code))
            Log("FIXED TP INSTALL FAILED | "+context+
                " | ticket="+(string)ticket+
                " | requestedTP="+DoubleToString(requestedTP,_Digits)+
                " | brokerTP="+DoubleToString(brokerTP,_Digits)+
                " | retcode="+IntegerToString((int)code)+
                " | "+trade.ResultRetcodeDescription());
         else
            currentTP=brokerTP;
         }
      }
   }

   PruneHybridTrailStates();
   PruneExitExecutionStates();
}




//------------------------- V2.0 S4 zone grading ----------------------

// V2.0 S4: is this price within tolerance of a $5 or $10 round level?
// Gold pivots around those levels, so a zone edge sitting on one carries
// extra resting interest.
// V2.2 BTC S1: the $5/$10 pair is now the GOLD BRANCH of a per-symbol
// ladder rather than a universal constant. The name is kept because the
// forward declaration, the call in ComputeZoneGrade() and the V2.0 S04
// documentation all use it; only the level scale became symbol-aware.
bool NearGoldRoundNumber(double price,double &levelOut)
{
   // V2.2 BTC S1: the two checked levels were the hardcoded constants 10.0
   // and 5.0, with NO symbol guard. That is correct for gold and broken for
   // anything priced in five figures. On BTC, StrategyPipSize() is $1, so
   // the tolerance below evaluates to InpRoundNumberTolerancePips * $1 =
   // $5 by default - which is exactly the LARGEST distance any price can be
   // from the nearest multiple of 10. The first test therefore returned
   // true for every price ever passed in, and ComputeZoneGrade() upgraded
   // EVERY zone one letter, unconditionally. The upgrade stopped carrying
   // information and just became a constant +1 grade.
   //
   // Fix: scale the checked levels per symbol using the SAME ladder the map
   // already uses for its big-round-number logic in
   // CalculateMapAndMaybeReady() - g_brnStep / g_microStep, gold 100/50,
   // BTC 1000/500, else MathMax(price*0.01,...) with a half-step minor -
   // shifted one decade down, because this test is about a zone edge
   // resting on a round number, not about the map's structural magnets.
   //
   // NO XAUUSD CHANGE: for gold majorStep/minorStep resolve to 10.0/5.0,
   // the literals the old code had written in, and every other line of the
   // function is untouched. The gold path is arithmetically identical.
   levelOut=0.0;

   if(price<=0.0)
      return false;

   double majorStep=IsGold()?10.0:
                    (IsBTC()?1000.0:MathMax(price*0.01,10.0));

   double minorStep=IsGold()?5.0:
                    (IsBTC()?500.0:majorStep*0.5);

   double tolerance=
      MathMax(0.0,InpRoundNumberTolerancePips)*MathMax(StrategyPipSize(),_Point);

   // Major step first so the stronger level is the one reported.
   double major=MathRound(price/majorStep)*majorStep;
   if(MathAbs(price-major)<=tolerance)
   {
      levelOut=major;
      return true;
   }

   double minor=MathRound(price/minorStep)*minorStep;
   if(MathAbs(price-minor)<=tolerance)
   {
      levelOut=minor;
      return true;
   }

   return false;
}


// V2.0 S4: grade a zone. 1=A, 2=B, 3=C.
//   A : 1st touch AND departure >= 0.70 AND aligned with H1 bias
//   C : 3rd+ touch OR departure < 0.35 OR counter-trend to H1 bias
//   B : everything else
// A round-number proximal edge then upgrades one step.
int ComputeZoneGrade(int direction,int touchNumber,double departureScore,
                     double proximalEdge,string &detail)
{
   detail="";

   // Unknown inputs must not manufacture a good grade OR a bad one. An
   // unmeasured departure is treated as neutral, not as weak.
   bool departureKnown=(departureScore>=0.0);
   bool counterTrend  =IsCounterToH1Bias(direction);
   bool firstTouch    =(touchNumber<=1);
   bool staleTouch    =(touchNumber>=3);

   int grade=2;

   bool gradeA=firstTouch &&
               departureKnown && departureScore>=0.70 &&
               !counterTrend;

   bool gradeC=staleTouch ||
               (departureKnown && departureScore<0.35) ||
               counterTrend;

   // C wins ties: a stale or counter-trend zone is not an A even if the
   // departure was explosive.
   if(gradeC)      grade=3;
   else if(gradeA) grade=1;
   else            grade=2;

   detail="touch#"+IntegerToString(touchNumber)+
          " departure="+(departureKnown?DoubleToString(departureScore,2):"n/a")+
          " H1="+(counterTrend?"counter":"aligned");

   double roundLevel=0.0;
   if(grade>1 && NearGoldRoundNumber(proximalEdge,roundLevel))
   {
      grade--;
      detail+=" +round("+DoubleToString(roundLevel,2)+")";
   }

   detail+=" -> "+string(grade==1?"A":(grade==2?"B":"C"));
   return grade;
}


string ZoneGradeText(int grade)
{
   if(grade==1) return "A";
   if(grade==2) return "B";
   if(grade==3) return "C";
   return "?";
}


double GradeSizeMultiplier(int grade)
{
   if(grade==1) return MathMax(0.0,InpGradeASizeMult);
   if(grade==2) return MathMax(0.0,InpGradeBSizeMult);
   if(grade==3) return MathMax(0.0,InpGradeCSizeMult);
   return 1.0;
}


double GradeTrailMultiplier(int grade)
{
   if(!InpUseZoneGrading) return 1.0;
   if(grade==1) return MathMax(0.05,InpGradeATrailMult);
   if(grade==2) return MathMax(0.05,InpGradeBTrailMult);
   if(grade==3) return MathMax(0.05,InpGradeCTrailMult);
   return 1.0;
}


double GradePartialTPPips(int grade)
{
   if(!InpUseZoneGrading) return MathMax(0.1,InpPartialTPPips);
   if(grade==1) return MathMax(0.1,InpGradeAPartialTPPips);
   if(grade==2) return MathMax(0.1,InpGradeBPartialTPPips);
   if(grade==3) return MathMax(0.1,InpGradeCPartialTPPips);
   return MathMax(0.1,InpPartialTPPips);
}


// V2.0 S4: recover the grade a position was deployed under, by mapping its
// order comment back to the originating setup. Returns 0 when unknown, which
// leaves geometry at the ungraded defaults.
int ResolvePositionZoneGrade(ulong ticket)
{
   if(!InpUseZoneGrading)
      return 0;

   if(!PositionSelectByTicket(ticket))
      return 0;

   long setupId=0;
   int layerIndex=0,totalLayers=0;

   if(!ParsePersistentComment(PositionGetString(POSITION_COMMENT),
                              setupId,layerIndex,totalLayers))
      return 0;

   if(setupId<=0)
      return 0;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(g_persistentSetups[i].id==setupId)
         return g_persistentSetups[i].zoneGrade;
   }

   return 0;
}



//---------------------- V2.0 S3 departure strength -------------------

// V2.0 S3: score how impulsively price left this zone when it formed.
// Returns 0.0-1.0, or -1.0 when it cannot be measured.
//
// Two components, deliberately continuous rather than bucketed:
//   range  - the departure leg's travel divided by the zone's own base range.
//            A zone price exploded away from has a high ratio.
//   bodies - the run of strong-bodied candles (body > 60% of range) heading
//            away from the zone. Measures conviction rather than distance.
// Combined 60/40 in favour of range, because distance travelled is the harder
// signal to fake with a single outsized bar.
double ComputeDepartureScore(double zoneLo,double zoneHi,
                             datetime zoneTime,int direction)
{
   if(!InpScoreDepartureStrength)
      return -1.0;

   double lo=MathMin(zoneLo,zoneHi);
   double hi=MathMax(zoneLo,zoneHi);

   if(lo<=0.0 || hi<=lo || zoneTime<=0)
      return -1.0;

   int lookback=(int)MathMax(2,MathMin(50,InpDepartureLookbackBars));

   int shift=iBarShift(_Symbol,g_supportTF,zoneTime,false);
   if(shift<0)
      return -1.0;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);

   // The zone bar itself plus the leg that left it.
   int need=shift+2;
   if(need<lookback+2)
      need=lookback+2;

   if(CopyRates(_Symbol,g_supportTF,0,need+2,rates)<need)
      return -1.0;

   if(shift>=ArraySize(rates))
      return -1.0;

   double baseRange=hi-lo;
   if(baseRange<=_Point)
      return -1.0;

   // Walk FORWARD in time from the zone bar, i.e. DOWN the series index.
   double departureExtreme=(direction==1)?hi:lo;
   int    strongBodies=0;
   bool   runIntact=true;
   int    measured=0;

   for(int k=1;k<=lookback;k++)
   {
      int idx=shift-k;
      if(idx<0) break;
      if(idx>=ArraySize(rates)) continue;

      measured++;

      if(direction==1)
         departureExtreme=MathMax(departureExtreme,rates[idx].high);
      else
         departureExtreme=MathMin(departureExtreme,rates[idx].low);

      double range=rates[idx].high-rates[idx].low;
      if(range<=_Point)
      {
         runIntact=false;
         continue;
      }

      double body=MathAbs(rates[idx].close-rates[idx].open);
      bool directional=(direction==1)
                       ? (rates[idx].close>rates[idx].open)
                       : (rates[idx].close<rates[idx].open);

      // Consecutive run only - a counter bar ends it.
      if(runIntact && directional && body>=range*0.60)
         strongBodies++;
      else
         runIntact=false;
   }

   if(measured<=0)
      return -1.0;

   double departureRange=(direction==1)
                         ? departureExtreme-hi
                         : lo-departureExtreme;

   if(departureRange<0.0)
      departureRange=0.0;

   double ratio=departureRange/baseRange;

   double weak  =MathMax(0.01,InpWeakDepartureRatio);
   double strong=MathMax(weak+0.01,InpStrongDepartureRatio);

   double rangeScore=Clamp((ratio-weak)/(strong-weak),0.0,1.0);
   double bodyScore =Clamp((double)strongBodies/(double)MathMax(1,measured),0.0,1.0);

   return Clamp(rangeScore*0.60+bodyScore*0.40,0.0,1.0);
}


// V2.0 S3: departure score -> size multiplier. Score < 0 means unmeasured,
// which must never penalise the setup.
double DepartureSizeMultiplier(double score)
{
   if(!InpScoreDepartureStrength || score<0.0)
      return 1.0;

   if(score>=0.70) return MathMax(0.0,InpStrongDepartureSizeMult);
   if(score>=0.35) return MathMax(0.0,InpModerateDepartureSizeMult);

   return MathMax(0.0,InpWeakDepartureSizeMult);
}



//------------------------ V2.0 S2 zone freshness ---------------------

// V2.0 S2: locate an existing record for this zone, or -1.
int ZoneTouchIndex(double lo,double hi)
{
   double zlo=MathMin(lo,hi);
   double zhi=MathMax(lo,hi);

   if(zlo<=0.0 || zhi<=0.0)
      return -1;

   double mid=(zlo+zhi)*0.5;
   double tolerance=
      MathMax(0.0,InpZoneIdentityTolerancePips)*MathMax(StrategyPipSize(),_Point);

   int best=-1;
   double bestDistance=DBL_MAX;

   for(int i=0;i<ArraySize(g_zoneTouches);i++)
   {
      if(!g_zoneTouches[i].used)
         continue;

      double recordMid=
         (g_zoneTouches[i].lo+g_zoneTouches[i].hi)*0.5;

      double distance=MathAbs(recordMid-mid);

      if(distance<=tolerance && distance<bestDistance)
      {
         best=i;
         bestDistance=distance;
      }
   }

   return best;
}


// V2.0 S2: read-only touch count. 0 means "never touched" - the next touch
// will be touch number 1.
int ZoneTouchCount(double lo,double hi)
{
   if(!InpTrackZoneFreshness)
      return 0;

   int index=ZoneTouchIndex(lo,hi);

   if(index<0)
      return 0;

   return g_zoneTouches[index].touches;
}


// V2.0 S2: record a touch and return the touch NUMBER (1 for a virgin zone).
// Called on every CMP touch whether or not the setup went on to deploy - a
// zone is worked by price arriving at it, not by us filling there.
int RegisterZoneTouch(double lo,double hi)
{
   if(!InpTrackZoneFreshness)
      return 1;

   double zlo=MathMin(lo,hi);
   double zhi=MathMax(lo,hi);

   if(zlo<=0.0 || zhi<=0.0)
      return 1;

   int index=ZoneTouchIndex(zlo,zhi);

   if(index<0)
   {
      // Find a free slot, else evict the least recently touched record.
      for(int i=0;i<ArraySize(g_zoneTouches);i++)
      {
         if(!g_zoneTouches[i].used)
         {
            index=i;
            break;
         }
      }

      if(index<0 && ArraySize(g_zoneTouches)<V2_MAX_ZONE_TOUCH_RECORDS)
      {
         index=ArraySize(g_zoneTouches);
         ArrayResize(g_zoneTouches,index+1);
         ZeroMemory(g_zoneTouches[index]);
      }

      if(index<0)
      {
         datetime oldest=0;
         for(int i=0;i<ArraySize(g_zoneTouches);i++)
         {
            if(index<0 || g_zoneTouches[i].lastTouch<oldest)
            {
               oldest=g_zoneTouches[i].lastTouch;
               index=i;
            }
         }

         if(index<0)
            return 1;

         ZeroMemory(g_zoneTouches[index]);
      }

      g_zoneTouches[index].used=true;
      g_zoneTouches[index].lo=zlo;
      g_zoneTouches[index].hi=zhi;
      g_zoneTouches[index].touches=0;
      g_zoneTouches[index].firstTouch=TimeCurrent();
   }

   // Keep the stored band tracking the current zone geometry, which drifts
   // slightly as the H1/M15 map refreshes.
   g_zoneTouches[index].lo=zlo;
   g_zoneTouches[index].hi=zhi;
   g_zoneTouches[index].touches++;
   g_zoneTouches[index].lastTouch=TimeCurrent();

   return g_zoneTouches[index].touches;
}


// V2.0 S2: size multiplier for a given touch NUMBER (1-based).
double FreshnessSizeMultiplier(int touchNumber)
{
   if(!InpTrackZoneFreshness || touchNumber<=0)
      return 1.0;

   if(touchNumber>=MathMax(1,InpFreshnessMaxTouches))
      return MathMax(0.0,InpTouch4PlusSizeMult);

   if(touchNumber==1) return MathMax(0.0,InpTouch1SizeMult);
   if(touchNumber==2) return MathMax(0.0,InpTouch2SizeMult);
   if(touchNumber==3) return MathMax(0.0,InpTouch3SizeMult);

   return MathMax(0.0,InpTouch4PlusSizeMult);
}


// V2.0 S2: persist touch history through the existing state path.
void SaveZoneTouchState()
{
   if(!InpTrackZoneFreshness)
      return;

   string prefix=StatePrefix()+"ZT_";
   int count=ArraySize(g_zoneTouches);

   GlobalVariableSet(prefix+"COUNT",(double)count);

   for(int i=0;i<count;i++)
   {
      string k=prefix+IntegerToString(i)+"_";
      GlobalVariableSet(k+"USED",g_zoneTouches[i].used?1.0:0.0);
      GlobalVariableSet(k+"LO",g_zoneTouches[i].lo);
      GlobalVariableSet(k+"HI",g_zoneTouches[i].hi);
      GlobalVariableSet(k+"N",(double)g_zoneTouches[i].touches);
      GlobalVariableSet(k+"FIRST",(double)g_zoneTouches[i].firstTouch);
      GlobalVariableSet(k+"LAST",(double)g_zoneTouches[i].lastTouch);
   }
}


void LoadZoneTouchState()
{
   if(!InpTrackZoneFreshness)
      return;

   string prefix=StatePrefix()+"ZT_";

   if(!GlobalVariableCheck(prefix+"COUNT"))
      return;

   int count=(int)GlobalVariableGet(prefix+"COUNT");
   count=(int)MathMax(0,MathMin(V2_MAX_ZONE_TOUCH_RECORDS,count));

   ArrayResize(g_zoneTouches,count);

   int restored=0;

   for(int i=0;i<count;i++)
   {
      string k=prefix+IntegerToString(i)+"_";
      ZeroMemory(g_zoneTouches[i]);

      if(!GlobalVariableCheck(k+"LO"))
         continue;

      g_zoneTouches[i].used      =(GlobalVariableGet(k+"USED")>0.5);
      g_zoneTouches[i].lo        =GlobalVariableGet(k+"LO");
      g_zoneTouches[i].hi        =GlobalVariableGet(k+"HI");
      g_zoneTouches[i].touches   =(int)GlobalVariableGet(k+"N");
      g_zoneTouches[i].firstTouch=(datetime)GlobalVariableGet(k+"FIRST");
      g_zoneTouches[i].lastTouch =(datetime)GlobalVariableGet(k+"LAST");

      if(g_zoneTouches[i].used)
         restored++;
   }

   Log("V2.0 S2 ZONE FRESHNESS RESTORED"+
       " | records="+IntegerToString(restored)+
       " | touch history survives restart");
}


// V2.0 S2/S4: publish the quality of the entry about to be sized, so the
// sizing choke point can see it.
void SetDistalContext(int direction,double entry,double zoneLo,double zoneHi)
{
   g_distalContextValid    =true;
   g_distalContextDirection=direction;
   g_distalContextEntry    =entry;
   g_distalContextLo       =MathMin(zoneLo,zoneHi);
   g_distalContextHi       =MathMax(zoneLo,zoneHi);
}


void ClearDistalContext()
{
   g_distalContextValid    =false;
   g_distalContextDirection=0;
   g_distalContextEntry    =0.0;
   g_distalContextLo       =0.0;
   g_distalContextHi       =0.0;
}


void SetQualityContext(int direction,int touches,double departure,int grade)
{
   g_qualityContextValid    =true;
   g_qualityContextDirection=direction;
   g_qualityContextTouches  =touches;
   g_qualityContextDeparture=departure;
   g_qualityContextGrade    =grade;
}


void ClearQualityContext()
{
   ClearDistalContext();
   g_qualityContextValid    =false;
   g_qualityContextDirection=0;
   g_qualityContextTouches  =0;
   g_qualityContextDeparture=-1.0;
   g_qualityContextGrade    =0;
}



// V2.0 S1: refresh the cached H1 bias at most once per H1 bar.
void RefreshH1Bias()
{
   if(!InpUseH1BiasFilter || g_h1BiasHandle==INVALID_HANDLE)
      return;

   datetime bar=iTime(_Symbol,PERIOD_H1,0);

   if(bar<=0 || bar==g_h1BiasBar)
      return;

   double buffer[];
   ArraySetAsSeries(buffer,true);

   // Shifts 1 and 2: the last two CLOSED H1 bars. Using the forming bar would
   // let the bias flip back and forth inside the hour.
   if(CopyBuffer(g_h1BiasHandle,0,1,2,buffer)<2)
      return;

   if(buffer[0]<=0.0 || buffer[1]<=0.0)
      return;

   double close1=iClose(_Symbol,PERIOD_H1,1);
   if(close1<=0.0)
      return;

   g_h1BiasEMA    =buffer[0];
   g_h1BiasEMAPrev=buffer[1];
   g_h1BiasClose  =close1;
   g_h1BiasBar    =bar;

   // Bias requires price and slope to agree. When they disagree the bias is
   // undecided (0) and nothing is treated as counter-trend - that keeps a
   // chopping H1 from taxing every setup in both directions.
   bool priceAbove=(close1>buffer[0]);
   bool slopeUp   =(buffer[0]>buffer[1]);

   int previous=g_h1BiasDir;

   if(priceAbove && slopeUp)       g_h1BiasDir=1;
   else if(!priceAbove && !slopeUp) g_h1BiasDir=-1;
   else                             g_h1BiasDir=0;

   if(g_h1BiasDir!=previous)
   {
      Log("V2.0 S1 H1 BIAS CHANGED"+
          " | "+string(previous==1?"BULLISH":(previous==-1?"BEARISH":"NEUTRAL"))+
          " -> "+string(g_h1BiasDir==1?"BULLISH":(g_h1BiasDir==-1?"BEARISH":"NEUTRAL"))+
          " | H1 close="+DoubleToString(close1,_Digits)+
          " | EMA"+IntegerToString(MathMax(1,InpH1BiasEMAPeriod))+"="+
          DoubleToString(buffer[0],_Digits)+
          " | slope="+string(slopeUp?"UP":"DOWN"));
   }
}


// V2.0 S1: +1 bullish, -1 bearish, 0 undecided or filter disabled.
int H1BiasDirection()
{
   if(!InpUseH1BiasFilter)
      return 0;

   return g_h1BiasDir;
}


// V2.0 S1: true when this setup direction fights a DECIDED H1 bias. An
// undecided bias is never counter-trend.
bool IsCounterToH1Bias(int direction)
{
   int bias=H1BiasDirection();

   if(bias==0 || direction==0)
      return false;

   return (bias!=direction);
}


// V2.0 S1: the quality size multiplier for a prospective entry. Returns 0.0
// only in hard-filter mode. Stage 4 replaces the body of this with the unified
// grade, so every sizing path keeps calling this one function.
double V2QualitySizeMultiplier(int direction,string &reason)
{
   reason="";

   double multiplier=1.0;

   // ---- unified grade (S4) ----
   // When grading is on it REPLACES the individual S01/S02/S03 multipliers
   // rather than stacking with them. Exactly one factor decides size.
   if(InpUseZoneGrading && g_qualityContextValid && g_qualityContextGrade>0)
   {
      double gradeMult=GradeSizeMultiplier(g_qualityContextGrade);

      reason="grade "+ZoneGradeText(g_qualityContextGrade)+
             " x"+DoubleToString(gradeMult,2);

      return MathMax(0.0,gradeMult);
   }

   // ---- H1 bias (S1) ----
   if(InpUseH1BiasFilter && InpH1BiasMode!=0 && IsCounterToH1Bias(direction))
   {
      if(InpH1BiasMode==2)
      {
         reason="counter-trend to H1 bias (HARD FILTER)";
         return 0.0;
      }

      multiplier=MathMin(multiplier,MathMax(0.0,InpCounterTrendSizeMult));
      reason="counter-trend H1 x"+
             DoubleToString(MathMax(0.0,InpCounterTrendSizeMult),2);
   }

   // ---- zone freshness (S2) ----
   if(InpTrackZoneFreshness &&
      g_qualityContextValid &&
      g_qualityContextTouches>0)
   {
      double freshness=FreshnessSizeMultiplier(g_qualityContextTouches);

      // The LEAST favourable factor wins - the factors are never multiplied
      // together. Compounding 0.50 bias x 0.35 freshness would give 0.175,
      // which is an unintended de-facto rejection.
      if(freshness<multiplier)
      {
         multiplier=freshness;
         reason="touch #"+IntegerToString(g_qualityContextTouches)+
                " freshness x"+DoubleToString(freshness,2);
      }
      else if(reason=="")
      {
         reason="touch #"+IntegerToString(g_qualityContextTouches)+" (full size)";
      }
   }

   // ---- departure strength (S3) ----
   if(InpScoreDepartureStrength &&
      g_qualityContextValid &&
      g_qualityContextDeparture>=0.0)
   {
      double departure=DepartureSizeMultiplier(g_qualityContextDeparture);

      if(departure<multiplier)
      {
         multiplier=departure;
         reason="departure "+
                DoubleToString(g_qualityContextDeparture,2)+
                " x"+DoubleToString(departure,2);
      }
   }

   if(reason=="")
      reason="no quality reduction";

   return MathMax(0.0,multiplier);
}


// V2.0 S1: READY lifetime in bars of the ACTIVE trigger timeframe.
// InpReadyExpiryBars is expressed in M5 bars (333 ~ 27.75 hours). Moving the
// trigger to M1 without rescaling would silently cut that lifetime to ~5.5
// hours and lose setups - frequency must stay constant, so the bar count is
// converted to preserve the same wall-clock lifetime.
int ReadyExpiryBarsEffective()
{
   int configured=MathMax(1,InpReadyExpiryBars);

   if(!InpUseV2RoutingChain)
      return configured;

   int baseSeconds  =PeriodSeconds(PERIOD_M5);
   int activeSeconds=PeriodSeconds(g_entryTF);

   if(activeSeconds<=0 || baseSeconds<=0 || activeSeconds>=baseSeconds)
      return configured;

   double scaled=(double)configured*((double)baseSeconds/(double)activeSeconds);

   return (int)MathMin(2147483000.0,MathMax(1.0,MathRound(scaled)));
}


bool ConfigureRouting()
{
   // V3.190 chain (InpUseV2RoutingChain=false): H1 direction -> M15 supporting
   // zone -> M5 for BOTH confirmation and entry.
   g_directionTF=PERIOD_H1;
   g_supportTF=PERIOD_M15;
   g_confirmTF=PERIOD_M5;
   g_entryTF=PERIOD_M5;

   g_mode="SCALP";
   g_tfLabel="M5";
   g_dirLabel="H1";
   g_supLabel="M15";
   g_confirmLabel="M5";

   // V2.0 S1: corrected chain. Confirmation stays on M5; the TRIGGER drops to
   // M1 so the fill no longer waits on the same bar that confirmed it. M1
   // nests 5:1 inside M5, so the two windows align on every confirmation bar.
   if(InpUseV2RoutingChain)
   {
      g_entryTF=PERIOD_M1;
      g_tfLabel="M1";
      g_confirmLabel="M5";
   }

   Log("V2.0 S1 ROUTING CHAIN="+
       string(InpUseV2RoutingChain?"V2.0":"V3.190")+
       " | zones="+g_dirLabel+
       " | H1 bias="+
       string(InpUseH1BiasFilter
              ?("ON mode "+IntegerToString(InpH1BiasMode)+
                (InpH1BiasMode==1
                 ?" (counter-trend x"+DoubleToString(InpCounterTrendSizeMult,2)+")"
                 :(InpH1BiasMode==2?" (hard filter)":" (inert)")))
              :"OFF")+
       " | setup="+g_supLabel+
       " | confirmation="+g_confirmLabel+
       " | trigger="+g_tfLabel+
       " | READY lifetime="+IntegerToString(InpReadyExpiryBars)+
       " M5-equivalent bars -> "+IntegerToString(ReadyExpiryBarsEffective())+
       " "+g_tfLabel+" bars (wall-clock preserved)");

   return true;
}

bool LoadRatesFlexible(ENUM_TIMEFRAMES tf,int requested,int minimum,MqlRates &rates[])
{
   ArraySetAsSeries(rates,true);
   ResetLastError();
   int got=CopyRates(_Symbol,tf,0,requested,rates);

   if(got<minimum)
   {
      // Trigger/allow MT5 history synchronization and report only when genuinely insufficient.
      Print("EzyMap: insufficient ",EnumToString(tf),
            " history. Loaded=",got,
            " Minimum=",minimum,
            " Error=",GetLastError());
      return false;
   }

   return true;
}

double EMAFromRates(MqlRates &r[],int total,int period,int shift)
{
   if(total<=period+shift+5) return EMPTY_VALUE;
   int oldest=total-1;
   double alpha=2.0/(period+1.0);
   double ema=r[oldest].close;
   for(int i=oldest-1;i>=shift;i--)
      ema=alpha*r[i].close+(1.0-alpha)*ema;
   return ema;
}

double ATRFromRates(MqlRates &r[],int total,int period,int shift)
{
   if(total<=period+shift+5) return EMPTY_VALUE;
   int oldest=total-2;
   double atr=0.0;
   int seedCount=0;
   for(int i=oldest;i>=MathMax(shift,oldest-period+1);i--)
   {
      double prev=r[i+1].close;
      double tr=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-prev),MathAbs(r[i].low-prev)));
      atr+=tr; seedCount++;
   }
   if(seedCount==0) return EMPTY_VALUE;
   atr/=seedCount;
   for(int i=oldest-period;i>=shift;i--)
   {
      if(i+1>=total) continue;
      double prev=r[i+1].close;
      double tr=MathMax(r[i].high-r[i].low,MathMax(MathAbs(r[i].high-prev),MathAbs(r[i].low-prev)));
      atr=(atr*(period-1)+tr)/period;
   }
   return atr;
}

bool Near(double a,double b,double tol) { return MathAbs(a-b)<=tol; }

bool NearRound(double v,double step,double tol)
{
   if(step<=0) return false;
   double nearest=MathRound(v/step)*step;
   return MathAbs(v-nearest)<=tol;
}

double Clamp(double v,double lo,double hi) { return MathMax(lo,MathMin(hi,v)); }

bool Overlap(double lo,double hi,double zlo,double zhi)
{
   return (hi>=zlo && lo<=zhi);
}

void PickDirectionLevels(MqlRates &d[],int total,double reference,double minDist,double fallbackLow,double fallbackHigh,double fallbackATR,
                         double &s1,double &s2,double &r1,double &r2)
{
   s1=s2=r1=r2=EMPTY_VALUE;
   double s1d=DBL_MAX,s2d=DBL_MAX,r1d=DBL_MAX,r2d=DBL_MAX;
   int maxN=MathMin(InpDirectionHistory,total-1);
   for(int i=1;i<=maxN;i++)
   {
      double level=d[i].close;
      if(level<reference && reference-level<s1d) { s1=level; s1d=reference-level; }
      if(level>reference && level-reference<r1d) { r1=level; r1d=level-reference; }
   }
   for(int i=1;i<=maxN;i++)
   {
      double level=d[i].close;
      if(s1!=EMPTY_VALUE && level<=s1-minDist && s1-level<s2d) { s2=level; s2d=s1-level; }
      if(r1!=EMPTY_VALUE && level>=r1+minDist && level-r1<r2d) { r2=level; r2d=level-r1; }
   }
   double safeATR=MathMax(fallbackATR,minDist*5.0);
   if(s1==EMPTY_VALUE) s1=MathMin(fallbackLow,reference-minDist);
   if(r1==EMPTY_VALUE) r1=MathMax(fallbackHigh,reference+minDist);
   if(s2==EMPTY_VALUE) s2=MathMin(fallbackLow,s1-minDist);
   if(r2==EMPTY_VALUE) r2=MathMax(fallbackHigh,r1+minDist);
   s1=RoundPrice(s1); s2=RoundPrice(s2); r1=RoundPrice(r1); r2=RoundPrice(r2);
}

ZoneInfo SupportZone(double level,MqlRates &s[],int total)
{
   ZoneInfo z; z.valid=false; z.lo=0; z.hi=0; z.time=0;
   double nearestDistance=DBL_MAX, nearestRange=0; datetime nearestTime=0;
   int maxN=MathMin(InpSupportHistory,total-1);
   for(int i=1;i<=maxN;i++)
   {
      if(s[i].high<=s[i].low) continue;
      if(s[i].low<=level && s[i].high>=level && !z.valid)
      {
         z.lo=RoundPrice(s[i].low); z.hi=RoundPrice(s[i].high); z.time=s[i].time; z.valid=true;
      }
      double mid=(s[i].high+s[i].low)/2.0;
      double dist=MathAbs(mid-level);
      if(dist<nearestDistance) { nearestDistance=dist; nearestRange=s[i].high-s[i].low; nearestTime=s[i].time; }
   }
   if(!z.valid && nearestTime>0)
   {
      double range=MathMax(nearestRange,_Point*10.0);
      z.lo=RoundPrice(level-range*0.5); z.hi=RoundPrice(level+range*0.5); z.time=nearestTime; z.valid=true;
   }
   return z;
}

// Refined LOW RISK zone selector.
//
// LOW RISK zones remain drawing-only and do not participate in READY/LIVE.
//
// BUY LOW RISK at S2:
//   1) Candle must overlap S2: low <= S2 <= high.
//   2) Prefer candles where the resulting zone [S2, candle high]
//      stays below the BUY HIGH RISK zone.
//   3) From the preferred set, choose the candle with the LOWEST LOW.
//   4) Zone is S2 -> selected candle HIGH.
//
// SELL LOW RISK at R2:
//   1) Candle must overlap R2: low <= R2 <= high.
//   2) Prefer candles where the resulting zone [candle low, R2]
//      stays above the SELL HIGH RISK zone.
//   3) From the preferred set, choose the candle with the HIGHEST HIGH.
//   4) Zone is selected candle LOW -> R2.
//
// If no non-overlapping candle exists, the same extreme rule is used
// without the separation requirement.

ZoneInfo V120SignalZoneFromLevel(double level,
                                 double neighborLevel,
                                 bool isDemand,
                                 MqlRates &s[],
                                 int total,
                                 double supportATR)
{
   ZoneInfo z;
   z.valid=false; z.lo=0; z.hi=0; z.time=0;

   if(level<=0 || level==EMPTY_VALUE || total<3)
      return z;

   int maxN=MathMin(InpSupportHistory,total-1);

   double averageRange=0.0;
   int validCount=0;

   for(int i=1;i<=maxN;i++)
   {
      if(s[i].high>s[i].low)
      {
         averageRange += s[i].high-s[i].low;
         validCount++;
      }
   }

   if(validCount>0)
      averageRange/=validCount;
   else
      averageRange=MathMax(supportATR,g_pipSize*20.0);

   double preferredMaximum=MathMax(averageRange*InpMaximumZoneRangeATR,
                                   g_pipSize*10.0);
   double atrWidth=MathMax(supportATR*0.75,averageRange*0.80);

   double neighborDistance=(neighborLevel>0 && neighborLevel!=EMPTY_VALUE)
                           ? MathAbs(level-neighborLevel)
                           : atrWidth;
   double neighborWidthCap=neighborDistance*0.75;
   double maximumWidth=MathMax(g_pipSize*10.0,
                               MathMin(atrWidth,neighborWidthCap));
   double minimumWidth=MathMax(g_pipSize*5.0,_Point*10.0);

   int preferred=-1;
   int overlap=-1;

   // Series arrays are newest first; therefore first match is the newest.
   for(int i=1;i<=maxN;i++)
   {
      if(s[i].high<=s[i].low)
         continue;

      bool intersects=(s[i].low<=level && s[i].high>=level);
      if(!intersects)
         continue;

      if(overlap<0)
         overlap=i;

      if(preferred<0 && (s[i].high-s[i].low)<=preferredMaximum)
         preferred=i;
   }

   int source=(preferred>=0)?preferred:overlap;

   double lowerAllowance=isDemand?maximumWidth*0.80:maximumWidth*0.20;
   double upperAllowance=isDemand?maximumWidth*0.20:maximumWidth*0.80;
   double allowedLo=level-lowerAllowance;
   double allowedHi=level+upperAllowance;

   double zoneLo=allowedLo;
   double zoneHi=allowedHi;
   datetime zoneTime=TimeCurrent();

   if(source>=0)
   {
      zoneLo=MathMax(s[source].low,allowedLo);
      zoneHi=MathMin(s[source].high,allowedHi);
      zoneTime=s[source].time;

      if(zoneHi<=zoneLo || zoneLo>level || zoneHi<level)
      {
         zoneLo=allowedLo;
         zoneHi=allowedHi;
      }
   }

   if(zoneHi-zoneLo<minimumWidth)
   {
      if(isDemand)
      {
         zoneLo=level-minimumWidth*0.80;
         zoneHi=level+minimumWidth*0.20;
      }
      else
      {
         zoneLo=level-minimumWidth*0.20;
         zoneHi=level+minimumWidth*0.80;
      }
   }

   zoneLo=MathMin(zoneLo,level);
   zoneHi=MathMax(zoneHi,level);

   z.lo=RoundPrice(zoneLo);
   z.hi=RoundPrice(zoneHi);
   z.time=zoneTime;
   z.valid=(z.hi>z.lo);

   return z;
}

ZoneInfo LowRiskExtremeOverlapZone(double level,
                                   ZoneInfo &highRisk,
                                   MqlRates &candles[],
                                   int total,
                                   bool buy)
{
   ZoneInfo z;
   z.valid=false;
   z.lo=0.0;
   z.hi=0.0;
   z.time=0;

   if(level<=0 || level==EMPTY_VALUE || total<2)
      return z;

   int maxN=MathMin(InpEntryHistory,total-1);
   if(maxN<1)
      return z;

   int bestSeparated=-1;
   int bestFallback=-1;

   double bestSeparatedExtreme = buy ? DBL_MAX : -DBL_MAX;
   double bestFallbackExtreme  = buy ? DBL_MAX : -DBL_MAX;

   for(int i=1;i<=maxN;i++)
   {
      if(candles[i].high<=candles[i].low)
         continue;

      // Candle must physically overlap S2/R2.
      bool crosses=(candles[i].low<=level && candles[i].high>=level);
      if(!crosses)
         continue;

      double zoneLo = buy ? level : candles[i].low;
      double zoneHi = buy ? candles[i].high : level;

      if(zoneHi<=zoneLo+_Point)
         continue;

      // Avoid same-side HIGH RISK overlap whenever possible.
      bool separated=true;

      if(InpLowRiskPreferNoOverlap && highRisk.valid)
      {
         if(buy)
         {
            // BUY LOW RISK must remain underneath BUY HIGH RISK.
            separated=(zoneHi < highRisk.lo-_Point);
         }
         else
         {
            // SELL LOW RISK must remain above SELL HIGH RISK.
            separated=(zoneLo > highRisk.hi+_Point);
         }
      }

      // Extreme selection requested by user:
      // BUY = lowest LOW; SELL = highest HIGH.
      double extreme = buy ? candles[i].low : candles[i].high;

      if(buy)
      {
         if(extreme<bestFallbackExtreme ||
            (MathAbs(extreme-bestFallbackExtreme)<=_Point && (bestFallback<0 || i<bestFallback)))
         {
            bestFallbackExtreme=extreme;
            bestFallback=i;
         }

         if(separated &&
            (extreme<bestSeparatedExtreme ||
             (MathAbs(extreme-bestSeparatedExtreme)<=_Point && (bestSeparated<0 || i<bestSeparated))))
         {
            bestSeparatedExtreme=extreme;
            bestSeparated=i;
         }
      }
      else
      {
         if(extreme>bestFallbackExtreme ||
            (MathAbs(extreme-bestFallbackExtreme)<=_Point && (bestFallback<0 || i<bestFallback)))
         {
            bestFallbackExtreme=extreme;
            bestFallback=i;
         }

         if(separated &&
            (extreme>bestSeparatedExtreme ||
             (MathAbs(extreme-bestSeparatedExtreme)<=_Point && (bestSeparated<0 || i<bestSeparated))))
         {
            bestSeparatedExtreme=extreme;
            bestSeparated=i;
         }
      }
   }

   int selected=(bestSeparated>=0)?bestSeparated:bestFallback;

   if(selected<0)
      return z;

   if(buy)
   {
      z.lo=RoundPrice(level);
      z.hi=RoundPrice(candles[selected].high);
   }
   else
   {
      z.lo=RoundPrice(candles[selected].low);
      z.hi=RoundPrice(level);
   }

   z.time=candles[selected].time;
   z.valid=(z.hi>z.lo+_Point);
   return z;
}

bool IsPivotHigh(MqlRates &s[],int total,int idx,int bars)
{
   if(idx-bars<0 || idx+bars>=total) return false;
   double v=s[idx].high;
   for(int k=1;k<=bars;k++) if(s[idx-k].high>=v || s[idx+k].high>v) return false;
   return true;
}

bool IsPivotLow(MqlRates &s[],int total,int idx,int bars)
{
   if(idx-bars<0 || idx+bars>=total) return false;
   double v=s[idx].low;
   for(int k=1;k<=bars;k++) if(s[idx-k].low<=v || s[idx+k].low<v) return false;
   return true;
}

void SupportMetrics(MqlRates &s[],int total,int piv,double &swingHigh,double &swingLow,double &trendSupport,double &trendResistance)
{
   swingHigh=swingLow=trendSupport=trendResistance=EMPTY_VALUE;
   int ph1=-1,ph2=-1,pl1=-1,pl2=-1;
   for(int i=piv+1;i<MathMin(total-piv,120);i++)
   {
      if(ph1<0 && IsPivotHigh(s,total,i,piv)) ph1=i;
      else if(ph1>=0 && ph2<0 && IsPivotHigh(s,total,i,piv)) ph2=i;
      if(pl1<0 && IsPivotLow(s,total,i,piv)) pl1=i;
      else if(pl1>=0 && pl2<0 && IsPivotLow(s,total,i,piv)) pl2=i;
      if(ph2>=0 && pl2>=0) break;
   }
   if(ph1>=0) swingHigh=s[ph1].high;
   if(pl1>=0) swingLow=s[pl1].low;
   if(ph1>=0 && ph2>=0)
   {
      double dx=(double)(ph2-ph1);
      trendResistance=s[ph1].high+(s[ph1].high-s[ph2].high)/dx*(double)ph1;
   }
   if(pl1>=0 && pl2>=0)
   {
      double dx=(double)(pl2-pl1);
      trendSupport=s[pl1].low+(s[pl1].low-s[pl2].low)/dx*(double)pl1;
   }
}

int ZoneRetests(ZoneInfo &z,MqlRates &e[],int total,datetime currentEntryTime)
{
   if(!z.valid) return 999;
   datetime readyTime=z.time+TfSeconds(g_supportTF);
   int maxN=MathMin(InpEntryHistory,total-1);
   int retests=0; bool prevInside=false;
   for(int i=maxN;i>=1;i--)
   {
      bool eligible=(e[i].time>=readyTime && e[i].time<=currentEntryTime);
      if(!eligible) continue;
      bool inside=Overlap(e[i].low,e[i].high,z.lo,z.hi);
      if(inside && !prevInside) retests++;
      prevInside=inside;
   }
   return retests;
}

bool SelectEntryCandle(ZoneInfo &z,double cmp,bool buy,MqlRates &e[],int total,double &lo,double &hi,datetime &tm)
{
   lo=hi=0; tm=0; double best=DBL_MAX; bool found=false;
   int maxN=MathMin(InpEntryHistory,total-1);
   for(int i=1;i<=maxN;i++)
   {
      bool inside=(e[i].low>=z.lo && e[i].high<=z.hi && e[i].high>e[i].low);
      bool side=buy ? (e[i].high<cmp-_Point) : (e[i].low>cmp+_Point);
      if(!inside || !side) continue;
      double dist=buy ? cmp-e[i].high : e[i].low-cmp;
      if(dist<best) { best=dist; lo=RoundPrice(e[i].low); hi=RoundPrice(e[i].high); tm=e[i].time; found=true; }
   }
   return found;
}

int ConfluenceCount(ZoneInfo &z,double ema,double trend,double fib50,double fib618,double tol)
{
   if(!z.valid) return 0;
   double mid=(z.lo+z.hi)/2.0;
   int c=1;
   bool brn=NearRound(mid,g_brnStep,tol);
   bool micro=(!brn && NearRound(mid,g_microStep,tol));
   bool em=Near(mid,ema,tol);
   bool tr=(trend!=EMPTY_VALUE && Near(mid,trend,tol));
   bool fib=((fib50!=EMPTY_VALUE && Near(mid,fib50,tol)) || (fib618!=EMPTY_VALUE && Near(mid,fib618,tol)));
   if(brn) c++; if(micro)c++; if(em)c++; if(tr)c++; if(fib)c++;
   return c;
}


bool StandardZoneNearCluster(ZoneInfo &zone,
                             double level1,
                             double level2,
                             double tolerance)
{
   if(!zone.valid || level1<=0.0 || level2<=0.0)
      return false;

   double clusterLo=MathMin(level1,level2);
   double clusterHi=MathMax(level1,level2);

   return SensitiveEnvelopeTouchesZone(
      zone.lo,
      zone.hi,
      clusterLo,
      clusterHi,
      tolerance);
}


bool StandardMTFClusterQualification(ZoneInfo &zone,
                                     int direction,
                                     string &detail)
{
   detail="";

   if(!InpStandardUseMTFClusterQualification ||
      !zone.valid)
      return false;

   double tolerance=
      MathMax(
         0.0,
         InpZeroConfClusterTolerancePips)*
      g_pipSize;

   double w1[2];
   double d1[2];
   double h4[2];

   if(direction==1)
   {
      w1[0]=g_zcW1S1;
      w1[1]=g_zcW1S2;
      d1[0]=g_zcD1S1;
      d1[1]=g_zcD1S2;
      h4[0]=g_zcH4S1;
      h4[1]=g_zcH4S2;
   }
   else
   {
      w1[0]=g_zcW1R1;
      w1[1]=g_zcW1R2;
      d1[0]=g_zcD1R1;
      d1[1]=g_zcD1R2;
      h4[0]=g_zcH4R1;
      h4[1]=g_zcH4R2;
   }

   // Strongest cluster: W1 with D1 or H4.
   for(int i=0;i<2;i++)
   {
      if(w1[i]<=0.0)
         continue;

      for(int j=0;j<2;j++)
      {
         if(d1[j]>0.0 &&
            MathAbs(w1[i]-d1[j])<=tolerance &&
            StandardZoneNearCluster(
               zone,w1[i],d1[j],tolerance))
         {
            detail="W1+D1";
            return true;
         }

         if(h4[j]>0.0 &&
            MathAbs(w1[i]-h4[j])<=tolerance &&
            StandardZoneNearCluster(
               zone,w1[i],h4[j],tolerance))
         {
            detail="W1+H4";
            return true;
         }
      }
   }

   // Secondary cluster: D1 with H4.
   for(int i=0;i<2;i++)
   {
      if(d1[i]<=0.0)
         continue;

      for(int j=0;j<2;j++)
      {
         if(h4[j]>0.0 &&
            MathAbs(d1[i]-h4[j])<=tolerance &&
            StandardZoneNearCluster(
               zone,d1[i],h4[j],tolerance))
         {
            detail="D1+H4";
            return true;
         }
      }
   }

   return false;
}


bool StandardM5SweepReclaimQualification(
   ZoneInfo &zone,
   int direction,
   MqlRates &m5[],
   int total,
   datetime &reclaimTime)
{
   reclaimTime=0;

   if(!InpStandardUseM5SweepReclaimQualification ||
      !zone.valid ||
      total<4)
      return false;

   MqlRates reclaim=m5[1];

   bool reclaimed=
      direction==1
      ? reclaim.close>zone.hi
      : reclaim.close<zone.lo;

   if(!reclaimed)
      return false;

   int maximumSweepIndex=
      MathMin(
         total-1,
         1+MathMax(1,InpZeroConfSweepLookbackM5));

   bool swept=false;

   for(int i=1;i<=maximumSweepIndex;i++)
   {
      if(direction==1 && m5[i].low<zone.lo)
      {
         swept=true;
         break;
      }

      if(direction==-1 && m5[i].high>zone.hi)
      {
         swept=true;
         break;
      }
   }

   if(!swept)
      return false;

   reclaimTime=reclaim.time;
   return true;
}


double NearestBelow4(double ref,double a,double b,double c,double d)
{
   double result=EMPTY_VALUE; double v[4]={a,b,c,d};
   for(int i=0;i<4;i++) if(v[i]!=EMPTY_VALUE && v[i]<ref && (result==EMPTY_VALUE || v[i]>result)) result=v[i];
   return result;
}

double NearestAbove4(double ref,double a,double b,double c,double d)
{
   double result=EMPTY_VALUE; double v[4]={a,b,c,d};
   for(int i=0;i<4;i++) if(v[i]!=EMPTY_VALUE && v[i]>ref && (result==EMPTY_VALUE || v[i]<result)) result=v[i];
   return result;
}

TradePlan BuildTradePlan(string dir,double entry,double entryLo,double entryHi,double volStop,double volTarget,double snr,
                         double targetMin,double targetMax,double s1,double s2,double r1,double r2,
                         double swingLow,double swingHigh,double trendSupport,double trendResistance)
{
   TradePlan p; p.valid=false; p.sl=p.tp=p.rr=0;

   if(dir=="BUY")
   {
      double baseSL=RoundPrice(entryLo-volStop);
      double fs=NearestBelow4(entryLo-snr,s1,s2,swingLow,trendSupport);
      double protectedSL=(fs!=EMPTY_VALUE)?RoundPrice(fs+snr):baseSL;
      p.sl=MathMax(baseSL,protectedSL);

      if(p.sl<entry)
      {
         double risk=entry-p.sl;
         double desired=Clamp(MathMax(volTarget,risk*1.5),targetMin,targetMax);
         desired=MathMin(desired,risk*MAX_RR);
         double fr=NearestAbove4(entry,r1,r2,swingHigh,trendResistance);
         double available=(fr!=EMPTY_VALUE)?fr-snr-entry:desired;
         double reward=MathMin(desired,available);

         if(reward>=risk*MIN_RR)
         {
            p.tp=RoundPrice(entry+reward);
            p.rr=(p.tp-entry)/risk;
            p.valid=(p.rr>=MIN_RR-0.0001 && p.rr<=MAX_RR+0.0001);
         }
      }
   }
   else
   {
      double baseSL=RoundPrice(entryHi+volStop);
      double fr=NearestAbove4(entryHi+snr,r1,r2,swingHigh,trendResistance);
      double protectedSL=(fr!=EMPTY_VALUE)?RoundPrice(fr-snr):baseSL;
      p.sl=MathMin(baseSL,protectedSL);

      if(p.sl>entry)
      {
         double risk=p.sl-entry;
         double desired=Clamp(MathMax(volTarget,risk*1.5),targetMin,targetMax);
         desired=MathMin(desired,risk*MAX_RR);
         double fs=NearestBelow4(entry,s1,s2,swingLow,trendSupport);
         double available=(fs!=EMPTY_VALUE)?entry-(fs+snr):desired;
         double reward=MathMin(desired,available);

         if(reward>=risk*MIN_RR)
         {
            p.tp=RoundPrice(entry-reward);
            p.rr=(entry-p.tp)/risk;
            p.valid=(p.rr>=MIN_RR-0.0001 && p.rr<=MAX_RR+0.0001);
         }
      }
   }

   // V1.2 bounded fallback: valid touch should not vanish simply because
   // the nearest structural target is too close.
   if(!p.valid)
   {
      double fallbackRisk=MathMax(volStop,targetMin/MAX_RR);
      double rewardFloor=fallbackRisk*MIN_RR;
      double rewardCeiling=MathMax(rewardFloor,
                                   MathMin(targetMax,fallbackRisk*MAX_RR));
      double fallbackReward=Clamp(MathMax(volTarget,targetMin),
                                  rewardFloor,rewardCeiling);

      if(dir=="BUY")
      {
         p.sl=RoundPrice(entry-fallbackRisk);
         p.tp=RoundPrice(entry+fallbackReward);
      }
      else
      {
         p.sl=RoundPrice(entry+fallbackRisk);
         p.tp=RoundPrice(entry-fallbackReward);
      }

      p.rr=fallbackReward/fallbackRisk;
      p.valid=(p.rr>=MIN_RR-0.0001 && p.rr<=MAX_RR+0.0001);
   }

   return p;
}

//----------------------------- Drawing ------------------------------
void DeleteObject(string suffix)
{
   ObjectDelete(0,PREFIX+suffix);
}

void SetObjectCommon(string n,bool back=false)
{
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,n,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,n,OBJPROP_BACK,back);
   ObjectSetInteger(0,n,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetInteger(0,n,OBJPROP_ZORDER,100);
}

void ApplyPremiumChartTheme()
{
   if(!InpApplyPremiumTheme) return;

   int scale=(int)MathMax(0,MathMin(5,InpChartScale));
   double shift=MathMax(10.0,MathMin(50.0,InpRightShiftPercent));

   ChartSetInteger(0,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(0,CHART_AUTOSCROLL,true);
   ChartSetInteger(0,CHART_SHIFT,true);
   ChartSetDouble(0,CHART_SHIFT_SIZE,shift);
   ChartSetInteger(0,CHART_SCALE,scale);
   ChartSetInteger(0,CHART_FOREGROUND,false);

   ChartSetInteger(0,CHART_SHOW_GRID,false);
   ChartSetInteger(0,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);
   ChartSetInteger(0,CHART_SHOW_PERIOD_SEP,false);
   ChartSetInteger(0,CHART_SHOW_ASK_LINE,false);
   ChartSetInteger(0,CHART_SHOW_LAST_LINE,false);
   ChartSetInteger(0,CHART_SHOW_BID_LINE,true);
   ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,false);
   ChartSetInteger(0,CHART_SHOW_ONE_CLICK,false);

   if(InpHideNativeTickerOHLC)
   {
      ChartSetInteger(0,CHART_SHOW_TICKER,false);
      ChartSetInteger(0,CHART_SHOW_OHLC,false);
   }

   ChartSetInteger(0,CHART_COLOR_BACKGROUND,InpChartBackground);
   ChartSetInteger(0,CHART_COLOR_FOREGROUND,InpChartForeground);
   ChartSetInteger(0,CHART_COLOR_GRID,InpChartBackground);
   ChartSetInteger(0,CHART_COLOR_VOLUME,C'48,56,66');

   // Candle bodies
   ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,InpBullCandleColor);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,InpBearCandleColor);

   // Wick / outline colors
   ChartSetInteger(0,CHART_COLOR_CHART_UP,InpBullWickColor);
   ChartSetInteger(0,CHART_COLOR_CHART_DOWN,InpBearWickColor);
   ChartSetInteger(0,CHART_COLOR_CHART_LINE,InpChartForeground);

   ChartSetInteger(0,CHART_COLOR_BID,C'78,88,100');
   ChartSetInteger(0,CHART_COLOR_ASK,C'78,88,100');
   ChartSetInteger(0,CHART_COLOR_LAST,C'78,88,100');
   ChartSetInteger(0,CHART_COLOR_STOP_LEVEL,InpPanelHeaderColor);
}

void HLine(string suffix,double price,color clr,ENUM_LINE_STYLE style=STYLE_DOT,int width=1)
{
   if(price<=0 || price==EMPTY_VALUE) return;

   string n=PREFIX+suffix;
   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_HLINE,0,0,price);

   ObjectSetDouble(0,n,OBJPROP_PRICE,price);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,width);
   SetObjectCommon(n,true);
}


// Draw the broker's actual pending/filled entry and active SL in gold.
// V3.081 submits no TP. The exact virtual 10-pip stop and any broker-compatible SL are shown.
// V2.2 BTC S4: the "Gold" in this function's name refers to the DRAWING
// COLOUR (InpTradeLevelGold, C'255,215,0'), not to XAUUSD. The body below is
// already fully symbol-generic - it filters on _Symbol and InpMagicNumber and
// reads nothing instrument-specific - so it is correct on BTC as written.
// Deliberately NOT renamed: six call sites, zero behaviour change, pure diff
// noise. Documented here so the next reader does not re-investigate it.
void DrawActualTradeLevelsGold()
{
   ObjectsDeleteAll(0,PREFIX+"LIVE_");

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string key=(string)ticket;
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=PositionGetDouble(POSITION_SL);
      double tp=PositionGetDouble(POSITION_TP);

      HLine("LIVE_ENTRY_"+key,entry,InpTradeLevelGold,STYLE_SOLID,2);
      if(sl>0.0)
         HLine("LIVE_SL_"+key,sl,InpTradeLevelGold,STYLE_DASH,2);
      if(tp>0.0)
         HLine("LIVE_TP_"+key,tp,InpTradeLevelGold,STYLE_DOT,2);

      int trailIndex=HybridTrailStateIndex(ticket);
      if(trailIndex>=0 &&
         g_hybridTrailStates[trailIndex].active &&
         g_hybridTrailStates[trailIndex].virtualStop>0.0)
      {
         HLine("LIVE_VIRTUAL_SL_"+key,
               g_hybridTrailStates[trailIndex].virtualStop,
               InpTradeLevelGold,STYLE_DOT,1);
      }
   }

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      double price=OrderGetDouble(ORDER_PRICE_OPEN);
      if(price>0.0)
         HLine("LIVE_PENDING_"+(string)ticket,
               price,InpTradeLevelGold,STYLE_DASHDOT,2);
   }
}

void Rect(string suffix,datetime t1,double p1,datetime t2,double p2,color clr,bool back=true,int width=1,ENUM_LINE_STYLE style=STYLE_SOLID)
{
   if(t1<=0 || t2<=0 || p1<=0 || p2<=0) return;

   string n=PREFIX+suffix;
   double lo=MathMin(p1,p2), hi=MathMax(p1,p2);

   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_RECTANGLE,0,t1,lo,t2,hi);
   else
   {
      ObjectMove(0,n,0,t1,lo);
      ObjectMove(0,n,1,t2,hi);
   }

   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FILL,true);
   ObjectSetInteger(0,n,OBJPROP_STYLE,style);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,width);
   SetObjectCommon(n,back);
}

void Panel(string suffix,int x,int y,int width,int height,color bg,color border)
{
   string n=PREFIX+suffix;
   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);

   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,width);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,height);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,border);
   ObjectSetInteger(0,n,OBJPROP_COLOR,border);
   ObjectSetInteger(0,n,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,n,OBJPROP_WIDTH,1);
   SetObjectCommon(n,false);
}

void CornerLabel(string suffix,string value,int x,int y,color clr,int size=9,string font="Arial")
{
   string n=PREFIX+suffix;
   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);

   // Correct right-side anchoring: the text expands LEFT into the chart.
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
   ObjectSetString(0,n,OBJPROP_FONT,font);
   ObjectSetString(0,n,OBJPROP_TEXT,value);
   SetObjectCommon(n,false);
}

void ChartText(string suffix,datetime tm,double price,string value,color clr,int size=8,ENUM_ANCHOR_POINT anchor=ANCHOR_LEFT)
{
   if(tm<=0 || price<=0 || price==EMPTY_VALUE) return;

   string n=PREFIX+suffix;
   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_TEXT,0,tm,price);
   else
      ObjectMove(0,n,0,tm,price);

   ObjectSetString(0,n,OBJPROP_TEXT,value);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,size);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,anchor);
   ObjectSetString(0,n,OBJPROP_FONT,"Arial Bold");
   SetObjectCommon(n,false);
}

void PriceMarker(string suffix,datetime tm,double price,string value,color clr)
{
   ChartText(suffix,tm,price,value,clr,10,ANCHOR_LEFT);
}

void AlertUser(string msg)
{
   if(!InpEnableAlerts) return;
   Alert(msg);
   if(InpPushNotifications) SendNotification(msg);
}

string StateText()
{
   if(g_state==ST_READY) return "READY";
   if(g_state==ST_ACTIVE) return "LIVE";
   if(g_state==ST_TP) return "TP HIT";
   if(g_state==ST_SL) return "SL HIT";
   if(g_state==ST_BE) return "BE HIT";
   return "MONITORING";
}

color StateColor()
{
   if(g_state==ST_READY)
      return (g_ready.direction=="BUY")?InpBuyColor:InpSellColor;
   if(g_state==ST_ACTIVE)
      return (g_active.direction=="BUY")?InpBuyColor:InpSellColor;
   if(g_state==ST_TP) return InpBuyColor;
   if(g_state==ST_SL) return InpSellColor;
   if(g_state==ST_BE) return InpNeutralColor;
   return InpPanelHeaderColor;
}

void DrawDashboard()
{
   if(!InpShowDashboard)
   {
      DeleteObject("DASH_PANEL");
      DeleteObject("DASH_TITLE");
      DeleteObject("DASH_BODY");
      DeleteObject("DASH_STATE");
      DeleteObject("DASH_COMPACT");
      DeleteObject("DASH_COMPACT_LEFT");
      DeleteObject("DASH_COMPACT_BIAS");
      DeleteObject("DASH_RIGHT");
      return;
   }

   // Remove legacy dashboard objects from prior builds.
   DeleteObject("DASH_PANEL");
   DeleteObject("DASH_TITLE");
   DeleteObject("DASH_BODY");
   DeleteObject("DASH_STATE");
   DeleteObject("DASH_COMPACT");
   DeleteObject("DASH_COMPACT_LEFT");
   DeleteObject("DASH_COMPACT_BIAS");

   // Privacy-safe single line:
   // XAUUSD • SCALP • M1 | BIAS BULLISH
   string biasText=(g_biasText=="")?"NEUTRAL":g_biasText;
   string compact=_Symbol+" • "+g_mode+" • "+g_tfLabel+" | BIAS "+biasText;

   // V2.0 S1: surface the active routing chain and H1 bias on the chart.
   if(InpUseV2RoutingChain || InpUseH1BiasFilter)
   {
      int h1bias=H1BiasDirection();

      compact+=" | "+string(InpUseV2RoutingChain?"V2":"V3.190")+
               " "+g_confirmLabel+">"+g_tfLabel;

      if(InpUseH1BiasFilter)
         compact+=" | H1 "+
                  string(h1bias==1?"BULL":(h1bias==-1?"BEAR":"FLAT"));
   }

   color clr=InpNeutralColor;
   if(biasText=="BULLISH")
      clr=InpBuyColor;
   else if(biasText=="BEARISH")
      clr=InpSellColor;

   string n=PREFIX+"DASH_RIGHT";
   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);

   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,18);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,8);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
   ObjectSetString(0,n,OBJPROP_FONT,"Arial Bold");
   ObjectSetString(0,n,OBJPROP_TEXT,compact);
   SetObjectCommon(n,false);
}

void ClearTradeCardRows()
{
   DeleteObject("CARD_PANEL");
   for(int i=0;i<10;i++)
      DeleteObject("CARD_ROW_"+IntegerToString(i));
   DeleteObject("CARD");
}

void CardRow(int row,string value,color clr,bool bold=false)
{
   string suffix="CARD_ROW_"+IntegerToString(row);
   string n=PREFIX+suffix;

   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);

   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,30);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,50+row*17);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,8);
   ObjectSetString(0,n,OBJPROP_FONT,bold?"Arial Bold":"Arial");
   ObjectSetString(0,n,OBJPROP_TEXT,value);
   SetObjectCommon(n,false);
}

void DrawTradeCard()
{
   if(!InpShowTradeCard)
   {
      ClearTradeCardRows();
      return;
   }

   // Always delete legacy single-label card.
   DeleteObject("CARD");

   int rows=0;
   color accent=InpNeutralColor;

   if(g_state==ST_READY)
   {
      accent=(g_ready.direction=="BUY")?InpBuyColor:InpSellColor;
      rows=g_ready.counterTrend?6:5;
      Panel("CARD_PANEL",14,38,300,34+rows*17,InpPanelColor,InpPanelBorderColor);

      CardRow(0,"SETUP READY • "+g_ready.direction,accent,true);
      CardRow(1,_Symbol+" • "+g_mode+" • "+g_tfLabel,InpNeutralColor,false);
      CardRow(2,"ENTRY  "+PriceText(g_ready.entryLo)+" - "+PriceText(g_ready.entryHi),InpNeutralColor,false);
      CardRow(3,"CONFIRMATION  ENTRY ZONE REJECTION",InpNeutralColor,false);
      CardRow(4,"CONFLUENCES  "+IntegerToString(g_ready.confluences),InpNeutralColor,false);
      if(g_ready.counterTrend)
         CardRow(5,"⚠ COUNTER-TREND",InpPanelHeaderColor,true);
   }
   else if(g_state==ST_ACTIVE)
   {
      accent=(g_active.direction=="BUY")?InpBuyColor:InpSellColor;
      rows=7+(g_active.beArmed?1:0)+(g_active.counterTrend?1:0);
      Panel("CARD_PANEL",14,38,300,34+rows*17,InpPanelColor,InpPanelBorderColor);

      int r=0;
      CardRow(r++,"TRADE ACTIVE • "+g_active.direction,accent,true);
      CardRow(r++,_Symbol+" • "+g_mode+" • "+g_tfLabel,InpNeutralColor,false);
      CardRow(r++,"ENTRY  "+PriceText(g_active.entry),InpNeutralColor,false);
      CardRow(r++,"TP     "+PriceText(g_active.tp),InpBuyColor,false);
      CardRow(r++,"SL     "+PriceText(g_active.sl),InpSellColor,false);
      CardRow(r++,"R:R    1:"+DoubleToString(g_active.rr,2),InpNeutralColor,false);
      CardRow(r++,"CONFLUENCES  "+IntegerToString(g_active.confluences),InpNeutralColor,false);

      if(g_active.beArmed)
         CardRow(r++,"BE ARMED @ +1R",InpBEColor,true);
      if(g_active.counterTrend)
         CardRow(r++,"⚠ COUNTER-TREND",InpPanelHeaderColor,true);
   }
   else if(g_state==ST_TP || g_state==ST_SL || g_state==ST_BE)
   {
      accent=(g_state==ST_TP)?InpBuyColor:(g_state==ST_SL?InpSellColor:InpNeutralColor);
      rows=2;
      Panel("CARD_PANEL",14,38,300,70,InpPanelColor,InpPanelBorderColor);
      CardRow(0,g_lastResult,accent,true);
      CardRow(1,_Symbol+" • "+g_tfLabel,InpNeutralColor,false);
   }
   else
   {
      if(!InpShowMonitoringCard)
      {
         ClearTradeCardRows();
         return;
      }

      rows=3;
      Panel("CARD_PANEL",14,38,300,86,InpPanelColor,InpPanelBorderColor);
      CardRow(0,"MONITORING",InpNeutralColor,true);
      CardRow(1,_Symbol+" • "+g_mode+" • "+g_tfLabel,InpNeutralColor,false);
      CardRow(2,"WAITING FOR VALID SETUP",InpNeutralColor,false);
   }

   // Remove unused rows from a previous larger state.
   for(int i=rows;i<10;i++)
      DeleteObject("CARD_ROW_"+IntegerToString(i));
}

void DrawLevelLabel(string suffix,string tag,double price,color clr,datetime labelTime)
{
   if(!InpShowDrawingLabels)
   {
      DeleteObject(suffix);
      return;
   }
   ChartText(suffix,labelTime,price,tag+"  "+PriceText(price),clr,8,ANCHOR_LEFT);
}

void DrawZoneLabel(string suffix,string tag,const ZoneInfo &z,color clr,datetime labelTime)
{
   if(!InpShowDrawingLabels || !z.valid)
   {
      DeleteObject(suffix);
      return;
   }
   ChartText(suffix,labelTime,(z.lo+z.hi)/2.0,tag,clr,8,ANCHOR_LEFT);
}

void DrawMap(datetime now)
{
   datetime mapFuture=now+TfSeconds(g_entryTF)*22;
   datetime labelTime=now+TfSeconds(g_entryTF)*3;

   // Direction S/R levels + labels
   if(InpShowDirectionLevels)
   {
      HLine("S1",g_S1,InpSupportColor,STYLE_DOT,1);
      HLine("S2",g_S2,InpSupportColor,STYLE_DASH,1);
      HLine("R1",g_R1,InpResistanceColor,STYLE_DOT,1);
      HLine("R2",g_R2,InpResistanceColor,STYLE_DASH,1);

      DrawLevelLabel("LBL_S1","S1",g_S1,InpSupportColor,labelTime);
      DrawLevelLabel("LBL_S2","S2",g_S2,InpSupportColor,labelTime);
      DrawLevelLabel("LBL_R1","R1",g_R1,InpResistanceColor,labelTime);
      DrawLevelLabel("LBL_R2","R2",g_R2,InpResistanceColor,labelTime);
   }
   else
   {
      DeleteObject("S1"); DeleteObject("S2"); DeleteObject("R1"); DeleteObject("R2");
      DeleteObject("LBL_S1"); DeleteObject("LBL_S2"); DeleteObject("LBL_R1"); DeleteObject("LBL_R2");
   }

   // FOUR support/resistance zones:
   // S1 = BUY HIGH RISK, S2 = BUY LOW RISK
   // R1 = SELL HIGH RISK, R2 = SELL LOW RISK
   if(InpShowSupportingZones)
   {
      if(g_buyHigh.valid)
         Rect("BUY_HIGH_ZONE",g_buyHigh.time,g_buyHigh.lo,mapFuture,g_buyHigh.hi,InpBuyHighRiskZoneColor,true,1,STYLE_SOLID);

      if(g_sellHigh.valid)
         Rect("SELL_HIGH_ZONE",g_sellHigh.time,g_sellHigh.lo,mapFuture,g_sellHigh.hi,InpSellHighRiskZoneColor,true,1,STYLE_SOLID);

      if(InpShowLowRiskZones && g_buyLow.valid)
         Rect("BUY_LOW_ZONE",g_buyLow.time,g_buyLow.lo,mapFuture,g_buyLow.hi,InpBuyLowRiskZoneColor,true,1,STYLE_DASH);

      if(InpShowLowRiskZones && g_sellLow.valid)
         Rect("SELL_LOW_ZONE",g_sellLow.time,g_sellLow.lo,mapFuture,g_sellLow.hi,InpSellLowRiskZoneColor,true,1,STYLE_DASH);

      DrawZoneLabel("LBL_BUY_HIGH","BUY • HIGH RISK",g_buyHigh,InpBuyColor,labelTime);
      DrawZoneLabel("LBL_SELL_HIGH","SELL • HIGH RISK",g_sellHigh,InpSellColor,labelTime);

      if(InpShowLowRiskZones)
      {
         DrawZoneLabel("LBL_BUY_LOW","BUY • LOW RISK",g_buyLow,InpSupportColor,labelTime);
         DrawZoneLabel("LBL_SELL_LOW","SELL • LOW RISK",g_sellLow,InpResistanceColor,labelTime);

         // Optional temporary validation marker for the exact candle chosen.
         if(InpShowLowRiskSourceMarker)
         {
            if(g_buyLow.valid)
               ChartText("SRC_BUY_LOW",g_buyLow.time,g_buyLow.hi,
                         "BUY LOW SOURCE",InpBuyColor,7,ANCHOR_LOWER);
            if(g_sellLow.valid)
               ChartText("SRC_SELL_LOW",g_sellLow.time,g_sellLow.lo,
                         "SELL LOW SOURCE",InpSellColor,7,ANCHOR_UPPER);
         }
         else
         {
            DeleteObject("SRC_BUY_LOW");
            DeleteObject("SRC_SELL_LOW");
         }
      }
      else
      {
         DeleteObject("BUY_LOW_ZONE"); DeleteObject("SELL_LOW_ZONE");
         DeleteObject("LBL_BUY_LOW"); DeleteObject("LBL_SELL_LOW");
         DeleteObject("SRC_BUY_LOW"); DeleteObject("SRC_SELL_LOW");
      }
   }
   else
   {
      DeleteObject("BUY_HIGH_ZONE"); DeleteObject("BUY_LOW_ZONE");
      DeleteObject("SELL_HIGH_ZONE"); DeleteObject("SELL_LOW_ZONE");
      DeleteObject("LBL_BUY_HIGH"); DeleteObject("LBL_BUY_LOW");
      DeleteObject("LBL_SELL_HIGH"); DeleteObject("LBL_SELL_LOW");
      DeleteObject("SRC_BUY_LOW"); DeleteObject("SRC_SELL_LOW");
   }

   // V1.2 dual READY rectangles + immutable LIVE rectangle.
   if(InpShowEntryZone && g_state==ST_READY)
   {
      if(g_buyReady.armed)
      {
         Rect("ENTRY_BUY_READY",g_buyReady.entryTime,g_buyReady.entryLo,
              mapFuture,g_buyReady.entryHi,InpBuyColor,false,2,STYLE_SOLID);

         if(InpShowDrawingLabels)
            ChartText("LBL_ENTRY_BUY",labelTime,
                      (g_buyReady.entryLo+g_buyReady.entryHi)/2.0,
                      "READY BUY • ENTRY ZONE",InpBuyColor,9,ANCHOR_LEFT);
      }
      else
      {
         DeleteObject("ENTRY_BUY_READY");
         DeleteObject("LBL_ENTRY_BUY");
      }

      if(g_sellReady.armed)
      {
         Rect("ENTRY_SELL_READY",g_sellReady.entryTime,g_sellReady.entryLo,
              mapFuture,g_sellReady.entryHi,InpSellColor,false,2,STYLE_SOLID);

         if(InpShowDrawingLabels)
            ChartText("LBL_ENTRY_SELL",labelTime,
                      (g_sellReady.entryLo+g_sellReady.entryHi)/2.0,
                      "READY SELL • ENTRY ZONE",InpSellColor,9,ANCHOR_LEFT);
      }
      else
      {
         DeleteObject("ENTRY_SELL_READY");
         DeleteObject("LBL_ENTRY_SELL");
      }

      DeleteObject("ENTRY");
      DeleteObject("LBL_ENTRY");
      DeleteObject("ACTIVE_ENTRY");
      DeleteObject("ACTIVE_TP");
      DeleteObject("ACTIVE_SL");
      DeleteObject("ACTIVE_BE");
      DeleteObject("LBL_ACTIVE_ENTRY");
      DeleteObject("LBL_ACTIVE_TP");
      DeleteObject("LBL_ACTIVE_SL");
      DeleteObject("LBL_ACTIVE_BE");
   }
   else if(InpShowEntryZone && g_state==ST_ACTIVE)
   {
      DeleteObject("ENTRY_BUY_READY");
      DeleteObject("ENTRY_SELL_READY");
      DeleteObject("LBL_ENTRY_BUY");
      DeleteObject("LBL_ENTRY_SELL");

      color c=(g_active.direction=="BUY")?InpBuyColor:InpSellColor;

      Rect("ENTRY",g_active.entryTime,g_active.entryLo,
           mapFuture,g_active.entryHi,c,false,2,STYLE_SOLID);

      if(InpShowDrawingLabels)
         ChartText("LBL_ENTRY",labelTime,
                   (g_active.entryLo+g_active.entryHi)/2.0,
                   "LIVE "+g_active.direction+" • ENTRY ZONE",c,9,ANCHOR_LEFT);

      HLine("ACTIVE_ENTRY",g_active.entry,c,STYLE_SOLID,2);
      HLine("ACTIVE_TP",g_active.tp,InpBuyColor,STYLE_DASH,1);
      HLine("ACTIVE_SL",g_active.sl,InpSellColor,STYLE_DASH,1);

      if(InpShowBELevel)
         HLine("ACTIVE_BE",g_active.beTrigger,InpBEColor,STYLE_DOT,1);
      else
         DeleteObject("ACTIVE_BE");

      if(InpShowDrawingLabels)
      {
         ChartText("LBL_ACTIVE_ENTRY",labelTime,g_active.entry,
                   "ENTRY  "+PriceText(g_active.entry),c,8,ANCHOR_LEFT);
         ChartText("LBL_ACTIVE_TP",labelTime,g_active.tp,
                   "TP  "+PriceText(g_active.tp),InpBuyColor,8,ANCHOR_LEFT);
         ChartText("LBL_ACTIVE_SL",labelTime,g_active.sl,
                   "SL  "+PriceText(g_active.sl),InpSellColor,8,ANCHOR_LEFT);

         if(InpShowBELevel)
            ChartText("LBL_ACTIVE_BE",labelTime,g_active.beTrigger,
                      "BE 40%  "+PriceText(g_active.beTrigger),
                      InpBEColor,8,ANCHOR_LEFT);
      }
   }
   else
   {
      DeleteObject("ENTRY_BUY_READY");
      DeleteObject("ENTRY_SELL_READY");
      DeleteObject("LBL_ENTRY_BUY");
      DeleteObject("LBL_ENTRY_SELL");
      DeleteObject("ENTRY");
      DeleteObject("LBL_ENTRY");
      DeleteObject("ACTIVE_ENTRY");
      DeleteObject("ACTIVE_TP");
      DeleteObject("ACTIVE_SL");
      DeleteObject("ACTIVE_BE");
      DeleteObject("LBL_ACTIVE_ENTRY");
      DeleteObject("LBL_ACTIVE_TP");
      DeleteObject("LBL_ACTIVE_SL");
      DeleteObject("LBL_ACTIVE_BE");
   }

}


void RemoveOldestHistoricalMarker()
{
   int n=ArraySize(g_historicalMarkerNames);
   if(n<=0) return;

   ObjectDelete(0,g_historicalMarkerNames[0]);

   for(int i=1;i<n;i++)
      g_historicalMarkerNames[i-1]=g_historicalMarkerNames[i];

   ArrayResize(g_historicalMarkerNames,n-1);
}

void AddHistoricalMarker(string direction,datetime tm,double price)
{
   if(!InpShowHistoricalMarkers) return;
   if(direction!="BUY" && direction!="SELL") return;
   if(tm<=0 || price<=0) return;

   g_historicalMarkerSerial++;
   string name=PREFIX+"HIST_"+IntegerToString((int)tm)+"_"+IntegerToString(g_historicalMarkerSerial);

   // Place BUY marker slightly under entry and SELL slightly above it.
   double offset=MathMax(g_pipSize*8.0,_Point*8.0);
   double markerPrice=(direction=="BUY")?price-offset:price+offset;

   if(!ObjectCreate(0,name,OBJ_TEXT,0,tm,markerPrice))
      return;

   ObjectSetString(0,name,OBJPROP_TEXT,direction);
   ObjectSetString(0,name,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,name,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,name,OBJPROP_COLOR,(direction=="BUY")?InpBuyColor:InpSellColor);
   ObjectSetInteger(0,name,OBJPROP_ANCHOR,(direction=="BUY")?ANCHOR_UPPER:ANCHOR_LOWER);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_SELECTED,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,false);
   ObjectSetInteger(0,name,OBJPROP_BACK,false);
   ObjectSetInteger(0,name,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);
   ObjectSetInteger(0,name,OBJPROP_ZORDER,110);

   int n=ArraySize(g_historicalMarkerNames);
   ArrayResize(g_historicalMarkerNames,n+1);
   g_historicalMarkerNames[n]=name;

   int maxMarkers=MathMax(1,InpMaxHistoricalMarkers);
   while(ArraySize(g_historicalMarkerNames)>maxMarkers)
      RemoveOldestHistoricalMarker();
}

void ClearHistoricalMarkers()
{
   int n=ArraySize(g_historicalMarkerNames);
   for(int i=0;i<n;i++)
      ObjectDelete(0,g_historicalMarkerNames[i]);

   ArrayResize(g_historicalMarkerNames,0);
}

//-------------------------- Signal engine ---------------------------
void UpdateEventAges(bool bullChoch,bool bearChoch,bool bullReject,bool bearReject)
{
   g_bullChochAge=bullChoch?0:MathMin(9999,g_bullChochAge+1);
   g_bearChochAge=bearChoch?0:MathMin(9999,g_bearChochAge+1);
   g_bullRejectAge=bullReject?0:MathMin(9999,g_bullRejectAge+1);
   g_bearRejectAge=bearReject?0:MathMin(9999,g_bearRejectAge+1);
}

void ClearReadySnapshot(ReadySnapshot &r)
{
   ZeroMemory(r);
   r.direction="NONE";
   r.armed=false;
}

void SyncReadyDisplay(double livePrice)
{
   ClearReadySnapshot(g_ready);

   if(g_buyReady.armed && !g_sellReady.armed)
      g_ready=g_buyReady;
   else if(g_sellReady.armed && !g_buyReady.armed)
      g_ready=g_sellReady;
   else if(g_buyReady.armed && g_sellReady.armed)
   {
      double bd=(livePrice<g_buyReady.entryLo)?g_buyReady.entryLo-livePrice:
                (livePrice>g_buyReady.entryHi)?livePrice-g_buyReady.entryHi:0.0;
      double sd=(livePrice<g_sellReady.entryLo)?g_sellReady.entryLo-livePrice:
                (livePrice>g_sellReady.entryHi)?livePrice-g_sellReady.entryHi:0.0;
      g_ready=(bd<=sd)?g_buyReady:g_sellReady;
   }

   if(g_buyReady.armed || g_sellReady.armed)
      g_state=ST_READY;
   else if(g_state==ST_READY)
      g_state=ST_MONITORING;
}

void ResetReady()
{
   ClearReadySnapshot(g_buyReady);
   ClearReadySnapshot(g_sellReady);
   ClearReadySnapshot(g_ready);

   if(g_state==ST_READY)
      g_state=ST_MONITORING;
}

void FinishTrade(EzyState result,double resultPips)
{
   // Preserve the completed LIVE signal as a historical BUY/SELL marker.
   // The marker is anchored to the original LIVE start time and entry.
   AddHistoricalMarker(g_active.direction,g_active.startClock,g_active.entry);

   if(result==ST_TP) g_lastResult="✅ COLLECT PROFIT";
   else if(result==ST_SL) g_lastResult="❌ HIT RISK";
   else g_lastResult="⚪ HIT BE";
   g_state=result; g_resultTime=TimeCurrent();
   string msg=g_lastResult+"\n\n"+_Symbol+" • "+g_active.direction+" • "+g_tfLabel+"\n\nRESULT\n"+(resultPips>0?"+":"")+DoubleToString(resultPips,0)+" PIPS\n\nEZYMAP • SCALP MASTERY";
   if(InpAlertResult) AlertUser(msg);
}

ZoneInfo StrictM15ZoneAtH4Line(double level,MqlRates &m15[],int total)
{
   ZoneInfo z;
   z.valid=false; z.lo=0.0; z.hi=0.0; z.time=0;

   if(level<=0 || level==EMPTY_VALUE || total<3)
      return z;

   int maxN=MathMin(InpM15ZoneHistory,total-1);
   double avgRange=0.0;
   int n=0;

   for(int i=1;i<=maxN;i++)
   {
      if(m15[i].high<=m15[i].low) continue;
      avgRange+=m15[i].high-m15[i].low;
      n++;
   }

   if(n>0) avgRange/=n;
   double preferredMax=MathMax(avgRange*InpMaximumZoneRangeATR,g_pipSize*10.0);

   int newestOverlap=-1;
   int newestPreferred=-1;

   for(int i=1;i<=maxN;i++)
   {
      if(m15[i].high<=m15[i].low) continue;
      if(!(m15[i].low<=level && m15[i].high>=level)) continue;

      if(newestOverlap<0) newestOverlap=i;
      if(newestPreferred<0 && (m15[i].high-m15[i].low)<=preferredMax)
         newestPreferred=i;
   }

   int source=(newestPreferred>=0)?newestPreferred:newestOverlap;
   if(source<0)
      return z;

   z.lo=RoundPrice(m15[source].low);
   z.hi=RoundPrice(m15[source].high);
   z.time=m15[source].time;
   z.valid=(z.hi>z.lo && z.lo<=level && z.hi>=level);
   return z;
}

ZoneInfo LatestH4OverlapZone(double level1,double level2,
                             MqlRates &m15[],int total,
                             double &selectedLine)
{
   ZoneInfo a=StrictM15ZoneAtH4Line(level1,m15,total);
   ZoneInfo b=StrictM15ZoneAtH4Line(level2,m15,total);
   selectedLine=0.0;

   if(a.valid && !b.valid) { selectedLine=level1; return a; }
   if(b.valid && !a.valid) { selectedLine=level2; return b; }
   if(!a.valid && !b.valid) return a;

   if(a.time>=b.time) { selectedLine=level1; return a; }
   selectedLine=level2;
   return b;
}

bool M3ReversalConfirmation(ZoneInfo &zone,
                            bool buy,
                            MqlRates &m3[],
                            int total,
                            int &bestScore,
                            datetime &confirmTime)
{
   bestScore=0;
   confirmTime=0;
   if(!zone.valid || total<8) return false;

   int lookback=MathMax(1,MathMin(InpM3Lookback,total-4));
   int structureBars=MathMax(2,MathMin(InpM3StructureBars,6));
   double closeStrength=MathMax(0.50,MathMin(0.90,InpM3CloseStrength));

   for(int i=1;i<=lookback;i++)
   {
      if(i+structureBars>=total) break;
      if(!Overlap(m3[i].low,m3[i].high,zone.lo,zone.hi)) continue;

      double range=m3[i].high-m3[i].low;
      if(range<=_Point) continue;

      double body=MathAbs(m3[i].close-m3[i].open);
      double safeBody=MathMax(body,_Point);
      bool directional=buy ? (m3[i].close>m3[i].open) : (m3[i].close<m3[i].open);
      bool strongClose=buy
                       ? (m3[i].close>=m3[i].low+range*closeStrength)
                       : (m3[i].close<=m3[i].high-range*closeStrength);
      int score=0;

      if(InpM3UseRejection)
      {
         double wick=buy
                     ? MathMin(m3[i].open,m3[i].close)-m3[i].low
                     : m3[i].high-MathMax(m3[i].open,m3[i].close);
         if(directional && strongClose &&
            wick>=safeBody*MathMax(0.0,InpM3RejectionWickRatio))
            score++;
      }

      if(InpM3UseCHOCH)
      {
         double priorHigh=-DBL_MAX;
         double priorLow=DBL_MAX;
         for(int k=1;k<=structureBars;k++)
         {
            priorHigh=MathMax(priorHigh,m3[i+k].high);
            priorLow=MathMin(priorLow,m3[i+k].low);
         }
         bool choch=buy
                    ? (m3[i].close>priorHigh && directional)
                    : (m3[i].close<priorLow && directional);
         if(choch) score++;
      }

      if(InpM3UseEngulfing && i+1<total)
      {
         bool engulf=buy
                     ? (m3[i].close>m3[i].open && m3[i+1].close<m3[i+1].open &&
                        m3[i].open<=m3[i+1].close && m3[i].close>=m3[i+1].open)
                     : (m3[i].close<m3[i].open && m3[i+1].close>m3[i+1].open &&
                        m3[i].open>=m3[i+1].close && m3[i].close<=m3[i+1].open);
         if(engulf) score++;
      }

      if(InpM3UseMomentum)
      {
         double avgBody=0.0;
         int cnt=0;
         for(int k=1;k<=4 && i+k<total;k++)
         {
            avgBody+=MathAbs(m3[i+k].close-m3[i+k].open);
            cnt++;
         }
         if(cnt>0) avgBody/=cnt;
         bool momentum=(directional && strongClose && avgBody>0 &&
                        body>=avgBody*MathMax(0.50,InpM3MomentumBodyFactor));
         if(momentum) score++;
      }

      if(score>bestScore)
      {
         bestScore=score;
         confirmTime=m3[i].time;
      }
   }

   int enabled=0;
   if(InpM3UseRejection) enabled++;
   if(InpM3UseCHOCH) enabled++;
   if(InpM3UseEngulfing) enabled++;
   if(InpM3UseMomentum) enabled++;
   if(enabled<=0) return false;

   int required=MathMax(1,MathMin(InpM3MinConfirmations,enabled));
   return (bestScore>=required && confirmTime>0);
}

bool SelectM5ReadyZone(ZoneInfo &highRisk,
                       bool buy,
                       MqlRates &m5[],
                       int total,
                       datetime confirmTime,
                       double cmp,
                       double &lo,
                       double &hi,
                       datetime &tm,
                       bool &directional)
{
   lo=hi=0.0;
   tm=0;
   directional=false;
   if(!highRisk.valid || total<3 || confirmTime<=0) return false;

   int maxN=MathMin(InpM5ReadyHistory,total-1);
   int fallback=-1;

   for(int i=1;i<=maxN;i++)
   {
      if(m5[i].time+TfSeconds(PERIOD_M5)<confirmTime) continue;
      if(!Overlap(m5[i].low,m5[i].high,highRisk.lo,highRisk.hi)) continue;

      bool side=buy ? (m5[i].high<cmp-_Point) : (m5[i].low>cmp+_Point);
      if(!side) continue;

      bool fullyInside=(m5[i].low>=highRisk.lo && m5[i].high<=highRisk.hi);
      if(fullyInside)
      {
         lo=RoundPrice(m5[i].low);
         hi=RoundPrice(m5[i].high);
         tm=m5[i].time;
         directional=buy ? (m5[i].close>m5[i].open) : (m5[i].close<m5[i].open);
         return (hi>lo);
      }

      if(fallback<0) fallback=i;
   }

   if(fallback>=0)
   {
      lo=RoundPrice(MathMax(m5[fallback].low,highRisk.lo));
      hi=RoundPrice(MathMin(m5[fallback].high,highRisk.hi));
      tm=m5[fallback].time;
      directional=buy ? (m5[fallback].close>m5[fallback].open)
                      : (m5[fallback].close<m5[fallback].open);
      return (hi>lo+_Point);
   }

   return false;
}

int RefinedConfidence(int m3Score,bool m5Directional,int retests)
{
   // H4 line + M15 overlap = 2 base confirmations.
   int conf=2+m3Score;
   if(m5Directional) conf++;
   if(retests==0) conf++;
   return MathMax(1,MathMin(7,conf));
}

bool CalculateMapAndMaybeReady(double livePrice)
{
   MqlRates m5[],h1[],m15[];

   if(!LoadRatesFlexible(PERIOD_M5,140,40,m5) ||
      !LoadRatesFlexible(PERIOD_H1,140,55,h1) ||
      !LoadRatesFlexible(PERIOD_M15,180,60,m15))
      return false;

   g_pipSize=IsGold()?MathMax(0.10,_Point):
             (IsBTC()?MathMax(1.0,_Point):_Point);

   g_brnStep=IsGold()?100.0:
             (IsBTC()?1000.0:MathMax(livePrice*0.01,_Point*100.0));

   g_microStep=IsGold()?50.0:
               (IsBTC()?500.0:g_brnStep*0.5);

   g_livePrice=livePrice;

   // --------------------------------------------------------
   // M5 entry reference: confirmed previous M5 candle.
   // --------------------------------------------------------
   double entryReference=m5[1].close;
   double entryBiasEMA=EMAFromRates(m5,ArraySize(m5),EMA_LEN,1);

   // --------------------------------------------------------
   // H1 direction engine.
   // --------------------------------------------------------
   double directionATR=ATRFromRates(h1,ArraySize(h1),14,1);
   double directionEMA=EMAFromRates(h1,ArraySize(h1),EMA_LEN,1);
   double directionClose=h1[1].close;

   if(directionATR==EMPTY_VALUE ||
      directionEMA==EMPTY_VALUE ||
      entryBiasEMA==EMPTY_VALUE)
      return false;

   double directionLow=DBL_MAX;
   double directionHigh=-DBL_MAX;

   int dirN=MathMin(100,ArraySize(h1)-1);

   for(int i=1;i<=dirN;i++)
   {
      directionLow=MathMin(directionLow,h1[i].low);
      directionHigh=MathMax(directionHigh,h1[i].high);
   }

   // V2.2 BTC S3: was a hardcoded 70.0. Separate input from the H4 one -
   // this floor governs the STANDARD-path H1 map (g_S1/g_S2/g_R1/g_R2),
   // not the zero-conf ladder. Default is 70.0, so unchanged.
   double minimumLevelDistance=
      MathMax(MathMax(0.0,InpH1LevelMinDistancePips)*g_pipSize,_Point*5.0);

   PickDirectionLevels(h1,
                       ArraySize(h1),
                       entryReference,
                       minimumLevelDistance,
                       directionLow,
                       directionHigh,
                       directionATR,
                       g_S1,g_S2,g_R1,g_R2);

   // Extra levels affect zero-confluence execution only.
   RefreshZeroConfHigherTimeframeLevels(entryReference);

   bool bullishBias=(directionClose>directionEMA);
   bool bearishBias=(directionClose<directionEMA);

   g_biasText=bullishBias?"BULLISH":
              (bearishBias?"BEARISH":"NEUTRAL");

   // --------------------------------------------------------
   // M15 supporting map.
   // --------------------------------------------------------
   double supportATR=ATRFromRates(m15,ArraySize(m15),14,1);
   double supportEMA=EMAFromRates(m15,ArraySize(m15),EMA_LEN,1);

   if(supportATR==EMPTY_VALUE || supportEMA==EMPTY_VALUE)
      return false;

   double swingHigh=EMPTY_VALUE;
   double swingLow=EMPTY_VALUE;
   double trendSupport=EMPTY_VALUE;
   double trendResistance=EMPTY_VALUE;

   SupportMetrics(m15,
                  ArraySize(m15),
                  InpSupportPivotBars,
                  swingHigh,
                  swingLow,
                  trendSupport,
                  trendResistance);

   double entryBiasTolerance=
      MathMax(supportATR*0.60,g_pipSize*15.0);

   bool entryBullishBias=
      (entryReference>=entryBiasEMA-entryBiasTolerance);

   bool entryBearishBias=
      (entryReference<=entryBiasEMA+entryBiasTolerance);

   // Exact V1.1.0 route rules: no EMA-slope gate.
   bool trendBuyRoute=bullishBias && entryBullishBias;
   bool trendSellRoute=bearishBias && entryBearishBias;
   bool counterBuyRoute=bearishBias && entryBullishBias;
   bool counterSellRoute=bullishBias && entryBearishBias;

   g_trendBuyRoute=trendBuyRoute;
   g_trendSellRoute=trendSellRoute;

   // --------------------------------------------------------
   // Level-anchored M15 zones.
   // S1/R1 = HIGH RISK trade zones.
   // S2/R2 = drawing-only LOW RISK zones.
   // --------------------------------------------------------
   g_buyHigh=V120SignalZoneFromLevel(g_S1,g_S2,true,
                                     m15,ArraySize(m15),supportATR);

   g_buyLow=V120SignalZoneFromLevel(g_S2,g_S1,true,
                                    m15,ArraySize(m15),supportATR);

   g_sellHigh=V120SignalZoneFromLevel(g_R1,g_R2,false,
                                      m15,ArraySize(m15),supportATR);

   g_sellLow=V120SignalZoneFromLevel(g_R2,g_R1,false,
                                     m15,ArraySize(m15),supportATR);

   double supportRange=
      (swingHigh!=EMPTY_VALUE && swingLow!=EMPTY_VALUE)
      ? MathAbs(swingHigh-swingLow)
      : EMPTY_VALUE;

   double buyFib50=(supportRange!=EMPTY_VALUE)
                   ? swingHigh-supportRange*0.50
                   : EMPTY_VALUE;

   double buyFib618=(supportRange!=EMPTY_VALUE)
                    ? swingHigh-supportRange*0.618
                    : EMPTY_VALUE;

   double sellFib50=(supportRange!=EMPTY_VALUE)
                    ? swingLow+supportRange*0.50
                    : EMPTY_VALUE;

   double sellFib618=(supportRange!=EMPTY_VALUE)
                     ? swingLow+supportRange*0.618
                     : EMPTY_VALUE;

   double tolerance=InpConfluenceTolerancePips*g_pipSize;

   // Base confidence remains the original V3.168 confidence used for
   // STANDARD/GOOD/QUALITY lot sizing.
   int buyHighConfluences=
      ConfluenceCount(g_buyHigh,
                      supportEMA,
                      trendSupport,
                      buyFib50,
                      buyFib618,
                      tolerance);

   int sellHighConfluences=
      ConfluenceCount(g_sellHigh,
                      supportEMA,
                      trendResistance,
                      sellFib50,
                      sellFib618,
                      tolerance);

   string buyMTFClusterDetail="";
   string sellMTFClusterDetail="";

   bool buyMTFClusterQualification=
      StandardMTFClusterQualification(
         g_buyHigh,
         1,
         buyMTFClusterDetail);

   bool sellMTFClusterQualification=
      StandardMTFClusterQualification(
         g_sellHigh,
         -1,
         sellMTFClusterDetail);

   datetime buySweepReclaimTime=0;
   datetime sellSweepReclaimTime=0;

   bool buySweepReclaimQualification=
      StandardM5SweepReclaimQualification(
         g_buyHigh,
         1,
         m5,
         ArraySize(m5),
         buySweepReclaimTime);

   bool sellSweepReclaimQualification=
      StandardM5SweepReclaimQualification(
         g_sellHigh,
         -1,
         m5,
         ArraySize(m5),
         sellSweepReclaimTime);

   int buyQualificationConfluences=
      buyHighConfluences+
      (buyMTFClusterQualification?1:0)+
      (buySweepReclaimQualification?1:0);

   int sellQualificationConfluences=
      sellHighConfluences+
      (sellMTFClusterQualification?1:0)+
      (sellSweepReclaimQualification?1:0);

   // Preserve the original confidence/lot ladder.
   g_buyHighConf=buyHighConfluences;
   g_sellHighConf=sellHighConfluences;

   // Signal state is evaluated once per confirmed M5 close.
   if(m5[1].time==g_lastEntryClosedTime)
      return true;

   g_lastEntryClosedTime=m5[1].time;

   // --------------------------------------------------------
   // Confirmed M5 rejection / CHOCH window.
   // --------------------------------------------------------
   if(g_bullRejectAge<9999) g_bullRejectAge++;
   if(g_bearRejectAge<9999) g_bearRejectAge++;
   if(g_bullChochAge<9999) g_bullChochAge++;
   if(g_bearChochAge<9999) g_bearChochAge++;

   double candleRange=m5[1].high-m5[1].low;
   double candleBody=MathAbs(m5[1].close-m5[1].open);
   double safeBody=MathMax(candleBody,_Point);
   double lowerWick=MathMin(m5[1].open,m5[1].close)-m5[1].low;
   double upperWick=m5[1].high-MathMax(m5[1].open,m5[1].close);

   bool bullishBody=(m5[1].close>m5[1].open);
   bool bearishBody=(m5[1].close<m5[1].open);

   int structureLookback=
      MathMin(ArraySize(m5)-3,InpEntryPivotBars*2+2);

   double recentHigh=-DBL_MAX;
   double recentLow=DBL_MAX;

   for(int i=2;i<=structureLookback+1 && i<ArraySize(m5);i++)
   {
      recentHigh=MathMax(recentHigh,m5[i].high);
      recentLow=MathMin(recentLow,m5[i].low);
   }

   bool bullishBreak=
      recentHigh>-DBL_MAX &&
      m5[1].high>recentHigh &&
      m5[1].close>m5[2].close;

   bool bearishBreak=
      recentLow<DBL_MAX &&
      m5[1].low<recentLow &&
      m5[1].close<m5[2].close;

   bool bullishChochEvent=
      bullishBreak &&
      g_structureDirection<=0 &&
      (!InpRequireDirectionalBody || bullishBody);

   bool bearishChochEvent=
      bearishBreak &&
      g_structureDirection>=0 &&
      (!InpRequireDirectionalBody || bearishBody);

   bool bullishRejectionEvent=
      bullishBody &&
      candleRange>_Point &&
      lowerWick>=safeBody*InpRejectionWickRatio &&
      m5[1].close>=m5[1].low+candleRange*0.45;

   bool bearishRejectionEvent=
      bearishBody &&
      candleRange>_Point &&
      upperWick>=safeBody*InpRejectionWickRatio &&
      m5[1].close<=m5[1].high-candleRange*0.45;

   if(bullishRejectionEvent) g_bullRejectAge=0;
   if(bearishRejectionEvent) g_bearRejectAge=0;
   if(bullishChochEvent) g_bullChochAge=0;
   if(bearishChochEvent) g_bearChochAge=0;

   if(bullishBreak) g_structureDirection=1;
   if(bearishBreak) g_structureDirection=-1;

   bool bullishRecentRejection=
      (g_bullRejectAge<=CONFIRM_WINDOW);

   bool bearishRecentRejection=
      (g_bearRejectAge<=CONFIRM_WINDOW);

   bool bullishRecentChoch=
      (g_bullChochAge<=CONFIRM_WINDOW);

   bool bearishRecentChoch=
      (g_bearChochAge<=CONFIRM_WINDOW);

   // Source V1.1.0 is one READY/LIVE setup at a time.
   if(HasActivePersistentSignal() ||
      g_buyReady.armed ||
      g_sellReady.armed)
      return true;

   // --------------------------------------------------------
   // Candidate construction.
   // --------------------------------------------------------
   int buyRetests=
      ZoneRetests(g_buyHigh,m5,ArraySize(m5),m5[1].time);

   int sellRetests=
      ZoneRetests(g_sellHigh,m5,ArraySize(m5),m5[1].time);

   bool buyCounter=counterBuyRoute && !trendBuyRoute;
   bool sellCounter=counterSellRoute && !trendSellRoute;

   double directionalCloseBuy=(candleRange>_Point)
                              ? (m5[1].close-m5[1].low)/candleRange
                              : 0.0;
   double directionalCloseSell=(candleRange>_Point)
                               ? (m5[1].high-m5[1].close)/candleRange
                               : 0.0;
   bool bullishDirectionalFallback=InpActiveSignalMode &&
                                    InpAllowDirectionalM5Fallback &&
                                    bullishBody &&
                                    directionalCloseBuy>=MathMax(0.50,InpDirectionalM5CloseStrength);
   bool bearishDirectionalFallback=InpActiveSignalMode &&
                                    InpAllowDirectionalM5Fallback &&
                                    bearishBody &&
                                    directionalCloseSell>=MathMax(0.50,InpDirectionalM5CloseStrength);

   bool allowBuy=trendBuyRoute || buyCounter || bullishDirectionalFallback;
   bool allowSell=trendSellRoute || sellCounter || bearishDirectionalFallback;

   // Normal V3.081 confluence policy remains locked:
   // Trend-following READY = exactly 2 required confluences.
   // Counter-trend READY   = exactly 3 required confluences.
   // V3.102 retains the V3.094 exception: zero required confluences while this
   // EA has no open position or only one open position on the symbol.
   const int trendRequired=TREND_MIN_CONFLUENCES;
   const int counterRequired=COUNTER_MIN_CONFLUENCES;

   int buyRequired=buyCounter?counterRequired:trendRequired;
   int sellRequired=sellCounter?counterRequired:trendRequired;

   int runningEAEntries=CountOurPositions();

   bool zeroConfluenceLowExposure=
      V3104_ZERO_CONFLUENCE_TOUCH_RULE &&
      runningEAEntries<=V3104_ZERO_CONF_MAX_OPEN_POSITIONS;

   // Pine's live `close` is the current chart price. In MT5, the current
   // M5 bar close is the closest chart-equivalent reference.
   double cmp=m5[0].close;
   if(cmp<=0)
      cmp=livePrice;

   double buyEntryLo=0.0,buyEntryHi=0.0;
   double sellEntryLo=0.0,sellEntryHi=0.0;
   datetime buyEntryTime=0,sellEntryTime=0;

   bool buyEntryFound=
      SelectEntryCandle(g_buyHigh,
                        cmp,
                        true,
                        m5,
                        ArraySize(m5),
                        buyEntryLo,
                        buyEntryHi,
                        buyEntryTime);

   bool sellEntryFound=
      SelectEntryCandle(g_sellHigh,
                        cmp,
                        false,
                        m5,
                        ArraySize(m5),
                        sellEntryLo,
                        sellEntryHi,
                        sellEntryTime);

   // Active fallback: when the legacy M5 entry-candle search misses, freeze
   // the latest closed M5 candle clipped to the valid H1/M15 zone. If there is
   // no physical clip, keep the complete mapped zone so READY can still arm.
   if(InpActiveSignalMode && !buyEntryFound && g_buyHigh.valid)
   {
      buyEntryLo=RoundPrice(MathMax(m5[1].low,g_buyHigh.lo));
      buyEntryHi=RoundPrice(MathMin(m5[1].high,g_buyHigh.hi));
      if(buyEntryHi<=buyEntryLo)
      {
         buyEntryLo=g_buyHigh.lo;
         buyEntryHi=g_buyHigh.hi;
      }
      buyEntryTime=m5[1].time;
      buyEntryFound=(buyEntryHi>buyEntryLo);
   }

   if(InpActiveSignalMode && !sellEntryFound && g_sellHigh.valid)
   {
      sellEntryLo=RoundPrice(MathMax(m5[1].low,g_sellHigh.lo));
      sellEntryHi=RoundPrice(MathMin(m5[1].high,g_sellHigh.hi));
      if(sellEntryHi<=sellEntryLo)
      {
         sellEntryLo=g_sellHigh.lo;
         sellEntryHi=g_sellHigh.hi;
      }
      sellEntryTime=m5[1].time;
      sellEntryFound=(sellEntryHi>sellEntryLo);
   }

   bool buyZoneCorrectSide=
      !InpRequireZoneCorrectSide || (g_buyHigh.valid && g_buyHigh.hi<cmp);

   bool sellZoneCorrectSide=
      !InpRequireZoneCorrectSide || (g_sellHigh.valid && g_sellHigh.lo>cmp);

   bool buyConfirmation=bullishRecentRejection || bullishRecentChoch ||
                        bullishDirectionalFallback;
   bool sellConfirmation=bearishRecentRejection || bearishRecentChoch ||
                         bearishDirectionalFallback;
   int maximumRetests=InpActiveSignalMode
                      ? MathMax(0,InpActiveMaxZoneRetests)
                      : MAX_ZONE_RETESTS;

   bool buyNormalConfluence=
      buyQualificationConfluences>=buyRequired;

   bool sellNormalConfluence=
      sellQualificationConfluences>=sellRequired;

   bool buyZeroConfluenceFallback=
      zeroConfluenceLowExposure &&
      !buyNormalConfluence;

   bool sellZeroConfluenceFallback=
      zeroConfluenceLowExposure &&
      !sellNormalConfluence;

   // V2.2 BTC S09: was a hardcoded 0 (see InpZeroConfFallbackMinConfluences
   // for why). g_buyReady.requiredConfluences/g_sellReady.requiredConfluences
   // carry this value through to zeroConfluenceFallback=(requiredConfluences
   // ==0) at persistence time, so raising it above 0 here is sufficient on
   // its own to route these setups through the NORMAL deployment path
   // instead of the FORCE-PASS bypass - no other call site needs editing.
   int buyEffectiveRequired=
      buyZeroConfluenceFallback
      ? MathMax(0,InpZeroConfFallbackMinConfluences)
      : buyRequired;

   int sellEffectiveRequired=
      sellZeroConfluenceFallback
      ? MathMax(0,InpZeroConfFallbackMinConfluences)
      : sellRequired;

   bool buyCandidate=
      allowBuy &&
      buyConfirmation &&
      buyZoneCorrectSide &&
      buyEntryFound &&
      buyRetests<=maximumRetests &&
      (buyNormalConfluence || buyZeroConfluenceFallback);

   bool sellCandidate=
      allowSell &&
      sellConfirmation &&
      sellZoneCorrectSide &&
      sellEntryFound &&
      sellRetests<=maximumRetests &&
      (sellNormalConfluence || sellZeroConfluenceFallback);

   if(!buyCandidate && !sellCandidate)
   {
      if(InpSignalDiagnostics)
         Log("SIGNAL DIAGNOSTIC | M5="+TimeToString(m5[1].time,TIME_DATE|TIME_MINUTES)+
             " | BUY route="+string(allowBuy?"Y":"N")+
             " conf="+string(buyConfirmation?"Y":"N")+
             " zone="+string(g_buyHigh.valid?"Y":"N")+
             " entry="+string(buyEntryFound?"Y":"N")+
             " retests="+IntegerToString(buyRetests)+"/"+IntegerToString(maximumRetests)+
             " base conf="+IntegerToString(buyHighConfluences)+
             " qualification="+
             IntegerToString(buyQualificationConfluences)+"/"+
             IntegerToString(buyEffectiveRequired)+
             " MTF cluster="+
             string(buyMTFClusterQualification?"Y":"N")+
             " sweep/reclaim="+
             string(buySweepReclaimQualification?"Y":"N")+
             " zero-fallback="+string(buyZeroConfluenceFallback?"Y":"N")+
             " | SELL route="+string(allowSell?"Y":"N")+
             " conf="+string(sellConfirmation?"Y":"N")+
             " zone="+string(g_sellHigh.valid?"Y":"N")+
             " entry="+string(sellEntryFound?"Y":"N")+
             " retests="+IntegerToString(sellRetests)+"/"+IntegerToString(maximumRetests)+
             " base conf="+IntegerToString(sellHighConfluences)+
             " qualification="+
             IntegerToString(sellQualificationConfluences)+"/"+
             IntegerToString(sellEffectiveRequired)+
             " MTF cluster="+
             string(sellMTFClusterQualification?"Y":"N")+
             " sweep/reclaim="+
             string(sellSweepReclaimQualification?"Y":"N")+
             " zero-fallback="+string(sellZeroConfluenceFallback?"Y":"N")+
             " running entries="+IntegerToString(runningEAEntries));
      return true;
   }

   // V3.095 V3.081 selection with zero-confluence low-exposure fallback.
   // BUY and SELL candidates can be armed independently on the same completed
   // M5 candle. When dual-ready is disabled, preserve the original winner rule:
   // highest confluence, then the mapped zone nearest CMP.
   bool armBuy=buyCandidate;
   bool armSell=sellCandidate;

   if(!InpArmBothDirectionsWhenValid && buyCandidate && sellCandidate)
   {
      double buyDistance=MathAbs((g_buyHigh.lo+g_buyHigh.hi)/2.0-cmp);
      double sellDistance=MathAbs((g_sellHigh.lo+g_sellHigh.hi)/2.0-cmp);
      bool sellWins=
         (sellQualificationConfluences>
          buyQualificationConfluences ||
          (sellQualificationConfluences==
           buyQualificationConfluences &&
           sellDistance<buyDistance));
      armBuy=!sellWins;
      armSell=sellWins;
   }

   double chartATR=ATRFromRates(m5,ArraySize(m5),14,1);
   double targetMinimumDistance=InpScalpTargetMinPoints*g_pipSize;
   double targetMaximumDistance=InpScalpTargetMaxPoints*g_pipSize;
   double volatilityStopDistance=
      MathMax(InpScalpStopPips*g_pipSize,
              MathMax(chartATR,targetMinimumDistance)*0.40);
   double volatilityTargetDistance=
      MathMax(chartATR,targetMinimumDistance)*0.60;
   double snrBuffer=InpSnrFrontRunPips*g_pipSize;
   double fallbackRisk=
      MathMax(volatilityStopDistance,
              targetMinimumDistance/MAX_RR);

   ClearReadySnapshot(g_buyReady);
   ClearReadySnapshot(g_sellReady);

   int armedCount=0;
   datetime frequencyKey=InpOneSetupPerDirectionPerM5
                         ? m5[1].time
                         : TimeCurrent();

   if(armBuy)
   {
      double previewEntry=buyEntryHi;
      TradePlan plan=BuildTradePlan("BUY",
                                    previewEntry,
                                    buyEntryLo,
                                    buyEntryHi,
                                    volatilityStopDistance,
                                    volatilityTargetDistance,
                                    snrBuffer,
                                    targetMinimumDistance,
                                    targetMaximumDistance,
                                    g_S1,g_S2,g_R1,g_R2,
                                    swingLow,swingHigh,
                                    trendSupport,trendResistance);

      double frozenSL=0.0;
      double previewTP=0.0;
      double previewRR=InpLiveRR;

      if(plan.valid)
      {
         frozenSL=plan.sl;
         previewTP=plan.tp;
         previewRR=plan.rr;
      }
      else
      {
         frozenSL=RoundPrice(previewEntry-fallbackRisk);
         previewTP=RoundPrice(previewEntry+
                              MathMax(targetMinimumDistance,
                                      fallbackRisk*MIN_RR));
         previewRR=MathAbs(previewTP-previewEntry)/
                   MathMax(_Point,MathAbs(previewEntry-frozenSL));
      }

      g_buyReady.direction="BUY";
      g_buyReady.armed=true;
      g_buyReady.counterTrend=buyCounter;
      g_buyReady.confluences=buyHighConfluences;
      g_buyReady.requiredConfluences=buyEffectiveRequired;
      g_buyReady.zoneRetests=buyRetests;
      g_buyReady.supportLo=g_buyHigh.lo;
      g_buyReady.supportHi=g_buyHigh.hi;
      g_buyReady.entryLo=buyEntryLo;
      g_buyReady.entryHi=buyEntryHi;
      g_buyReady.entryTime=buyEntryTime;
      g_buyReady.planSL=frozenSL;
      g_buyReady.planTP=previewTP;
      g_buyReady.planRR=previewRR;
      g_buyReady.armedClock=frequencyKey;
      g_buyReady.armedBarTime=m5[0].time;
      g_buyReady.zoneExited=false;
      armedCount++;

      Log("SOURCE READY BUY | H1/M15/M5 | base conf="+
          IntegerToString(buyHighConfluences)+
          " | qualification="+
          IntegerToString(buyQualificationConfluences)+
          " | required="+IntegerToString(buyEffectiveRequired)+
          " | MTF cluster="+
          string(buyMTFClusterQualification?"YES":"NO")+
          (buyMTFClusterDetail==""?"":" ("+buyMTFClusterDetail+")")+
          " | M5 sweep/reclaim="+
          string(buySweepReclaimQualification?"YES":"NO")+
          (buySweepReclaimTime>0
           ?" ("+
             TimeToString(
                buySweepReclaimTime,
                TIME_DATE|TIME_MINUTES)+
             ")"
           :"")+
          " | zero-conf fallback="+
          string(buyZeroConfluenceFallback?"YES":"NO")+
          " | running entries="+IntegerToString(runningEAEntries)+
          " | counter="+string(buyCounter?"YES":"NO")+
          " | rejection="+string(bullishRecentRejection?"YES":"NO")+
          " | CHOCH="+string(bullishRecentChoch?"YES":"NO")+
          " | directional fallback="+
          string(bullishDirectionalFallback?"YES":"NO")+
          " | retests="+IntegerToString(buyRetests)+
          " | frequency key="+
          TimeToString(frequencyKey,TIME_DATE|TIME_MINUTES));
   }

   if(armSell)
   {
      double previewEntry=sellEntryLo;
      TradePlan plan=BuildTradePlan("SELL",
                                    previewEntry,
                                    sellEntryLo,
                                    sellEntryHi,
                                    volatilityStopDistance,
                                    volatilityTargetDistance,
                                    snrBuffer,
                                    targetMinimumDistance,
                                    targetMaximumDistance,
                                    g_S1,g_S2,g_R1,g_R2,
                                    swingLow,swingHigh,
                                    trendSupport,trendResistance);

      double frozenSL=0.0;
      double previewTP=0.0;
      double previewRR=InpLiveRR;

      if(plan.valid)
      {
         frozenSL=plan.sl;
         previewTP=plan.tp;
         previewRR=plan.rr;
      }
      else
      {
         frozenSL=RoundPrice(previewEntry+fallbackRisk);
         previewTP=RoundPrice(previewEntry-
                              MathMax(targetMinimumDistance,
                                      fallbackRisk*MIN_RR));
         previewRR=MathAbs(previewTP-previewEntry)/
                   MathMax(_Point,MathAbs(previewEntry-frozenSL));
      }

      g_sellReady.direction="SELL";
      g_sellReady.armed=true;
      g_sellReady.counterTrend=sellCounter;
      g_sellReady.confluences=sellHighConfluences;
      g_sellReady.requiredConfluences=sellEffectiveRequired;
      g_sellReady.zoneRetests=sellRetests;
      g_sellReady.supportLo=g_sellHigh.lo;
      g_sellReady.supportHi=g_sellHigh.hi;
      g_sellReady.entryLo=sellEntryLo;
      g_sellReady.entryHi=sellEntryHi;
      g_sellReady.entryTime=sellEntryTime;
      g_sellReady.planSL=frozenSL;
      g_sellReady.planTP=previewTP;
      g_sellReady.planRR=previewRR;
      g_sellReady.armedClock=frequencyKey;
      g_sellReady.armedBarTime=m5[0].time;
      g_sellReady.zoneExited=false;
      armedCount++;

      Log("SOURCE READY SELL | H1/M15/M5 | base conf="+
          IntegerToString(sellHighConfluences)+
          " | qualification="+
          IntegerToString(sellQualificationConfluences)+
          " | required="+IntegerToString(sellEffectiveRequired)+
          " | MTF cluster="+
          string(sellMTFClusterQualification?"YES":"NO")+
          (sellMTFClusterDetail==""?"":" ("+sellMTFClusterDetail+")")+
          " | M5 sweep/reclaim="+
          string(sellSweepReclaimQualification?"YES":"NO")+
          (sellSweepReclaimTime>0
           ?" ("+
             TimeToString(
                sellSweepReclaimTime,
                TIME_DATE|TIME_MINUTES)+
             ")"
           :"")+
          " | zero-conf fallback="+
          string(sellZeroConfluenceFallback?"YES":"NO")+
          " | running entries="+IntegerToString(runningEAEntries)+
          " | counter="+string(sellCounter?"YES":"NO")+
          " | rejection="+string(bearishRecentRejection?"YES":"NO")+
          " | CHOCH="+string(bearishRecentChoch?"YES":"NO")+
          " | directional fallback="+
          string(bearishDirectionalFallback?"YES":"NO")+
          " | retests="+IntegerToString(sellRetests)+
          " | frequency key="+
          TimeToString(frequencyKey,TIME_DATE|TIME_MINUTES));
   }

   g_readySignalCount+=armedCount;
   SyncReadyDisplay(cmp);
   return true;
}

void ManageReady(double livePrice)
{
   if(g_state!=ST_READY)
      return;

   MqlRates e[];
   if(!LoadRatesFlexible(g_entryTF,12,4,e))
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   datetime currentBarTime=e[0].time;
   double currentOpen=e[0].open;
   double currentHigh=e[0].high;
   double currentLow=e[0].low;
   double buffer=MathMax(g_pipSize*5.0,_Point*2.0);
   double sideBuffer=_Point;

   // Independent expiry / invalidation.
   if(g_buyReady.armed)
   {
      int closedBars=(g_buyReady.armedBarTime>0)
                     ? (int)((currentBarTime-g_buyReady.armedBarTime)/TfSeconds(g_entryTF))
                     : 0;

      bool expired=(closedBars>=ReadyExpiryBarsEffective());
      bool routeInvalid=(!g_buyReady.counterTrend && !g_trendBuyRoute);
      bool zoneInvalid=(livePrice<g_buyReady.supportLo-buffer);

      bool supportTouched=Overlap(currentLow,currentHigh,
                                  g_buyReady.supportLo,g_buyReady.supportHi);

      if(!supportTouched)
         g_buyReady.zoneExited=true;

      bool retestInvalid=(g_buyReady.zoneExited &&
                          supportTouched &&
                          g_buyReady.zoneRetests>=MAX_ZONE_RETESTS);

      bool entryTouched=(tick.ask>=g_buyReady.entryLo &&
                         tick.ask<=g_buyReady.entryHi);

      bool entrySideInvalid=(!entryTouched &&
                             g_buyReady.entryHi>=tick.ask-sideBuffer);

      if(expired || routeInvalid || zoneInvalid || retestInvalid || entrySideInvalid)
         ClearReadySnapshot(g_buyReady);
   }

   if(g_sellReady.armed)
   {
      int closedBars=(g_sellReady.armedBarTime>0)
                     ? (int)((currentBarTime-g_sellReady.armedBarTime)/TfSeconds(g_entryTF))
                     : 0;

      bool expired=(closedBars>=ReadyExpiryBarsEffective());
      bool routeInvalid=(!g_sellReady.counterTrend && !g_trendSellRoute);
      bool zoneInvalid=(livePrice>g_sellReady.supportHi+buffer);

      bool supportTouched=Overlap(currentLow,currentHigh,
                                  g_sellReady.supportLo,g_sellReady.supportHi);

      if(!supportTouched)
         g_sellReady.zoneExited=true;

      bool retestInvalid=(g_sellReady.zoneExited &&
                          supportTouched &&
                          g_sellReady.zoneRetests>=MAX_ZONE_RETESTS);

      bool entryTouched=(tick.bid>=g_sellReady.entryLo &&
                         tick.bid<=g_sellReady.entryHi);

      bool entrySideInvalid=(!entryTouched &&
                             g_sellReady.entryLo<=tick.bid+sideBuffer);

      if(expired || routeInvalid || zoneInvalid || retestInvalid || entrySideInvalid)
         ClearReadySnapshot(g_sellReady);
   }

   // V1.2 requires a completely later M5 chart candle.
   bool buyLater=g_buyReady.armed &&
                 g_buyReady.armedBarTime>0 &&
                 currentBarTime>g_buyReady.armedBarTime;

   bool sellLater=g_sellReady.armed &&
                  g_sellReady.armedBarTime>0 &&
                  currentBarTime>g_sellReady.armedBarTime;

   bool buyTouch=buyLater &&
                 tick.ask>=g_buyReady.entryLo &&
                 tick.ask<=g_buyReady.entryHi;

   bool sellTouch=sellLater &&
                  tick.bid>=g_sellReady.entryLo &&
                  tick.bid<=g_sellReady.entryHi;

   string trigger="NONE";

   if(buyTouch && !sellTouch)
      trigger="BUY";
   else if(sellTouch && !buyTouch)
      trigger="SELL";
   else if(buyTouch && sellTouch)
   {
      // Same-tick ambiguity: approximate the Pine historical first-touch rule
      // using distance from the current M5 bar open.
      double bd=(currentOpen<g_buyReady.entryLo)?g_buyReady.entryLo-currentOpen:
                (currentOpen>g_buyReady.entryHi)?currentOpen-g_buyReady.entryHi:0.0;

      double sd=(currentOpen<g_sellReady.entryLo)?g_sellReady.entryLo-currentOpen:
                (currentOpen>g_sellReady.entryHi)?currentOpen-g_sellReady.entryHi:0.0;

      if(MathAbs(bd-sd)<=_Point)
         trigger=(e[0].close>=currentOpen)?"BUY":"SELL";
      else
         trigger=(bd<sd)?"BUY":"SELL";
   }

   if(trigger=="NONE")
   {
      SyncReadyDisplay(livePrice);
      return;
   }

   ReadySnapshot chosen=(trigger=="BUY")?g_buyReady:g_sellReady;
   double entry=RoundPrice((trigger=="BUY")?tick.ask:tick.bid);
   double sl=chosen.planSL;
   double tp=chosen.planTP;
   double rr=0.0;

   // The V1.2 plan has a bounded fallback. Re-anchor TP around the actual
   // first-touch entry while keeping the frozen structural SL.
   if(trigger=="BUY" && sl<entry)
   {
      double risk=entry-sl;
      double minTp=entry+risk*MIN_RR;
      double maxTp=entry+risk*MAX_RR;
      tp=RoundPrice(MathMax(minTp,MathMin(maxTp,tp)));
      rr=(tp-entry)/risk;
   }
   else if(trigger=="SELL" && sl>entry)
   {
      double risk=sl-entry;
      double highestTarget=entry-risk*MIN_RR;
      double lowestTarget=entry-risk*MAX_RR;
      tp=RoundPrice(MathMax(lowestTarget,MathMin(highestTarget,tp)));
      rr=(entry-tp)/risk;
   }

   if(rr<MIN_RR-0.0001 || rr>MAX_RR+0.0001)
   {
      // Final bounded fallback directly from the V1.2 plan philosophy.
      double fallbackRisk=MathMax(
         (g_mode=="SCALP"?InpScalpStopPips:
          (g_mode=="INTRADAY"?InpIntradayStopPips:InpSwingStopPips))*g_pipSize,
         g_pipSize*10.0);

      double fallbackReward=Clamp(fallbackRisk*1.0,
                                  fallbackRisk*MIN_RR,
                                  fallbackRisk*MAX_RR);

      if(trigger=="BUY")
      {
         sl=RoundPrice(entry-fallbackRisk);
         tp=RoundPrice(entry+fallbackReward);
      }
      else
      {
         sl=RoundPrice(entry+fallbackRisk);
         tp=RoundPrice(entry-fallbackReward);
      }

      rr=fallbackReward/fallbackRisk;
   }

   ZeroMemory(g_active);
   g_active.direction=trigger;
   g_active.counterTrend=chosen.counterTrend;
   g_active.confluences=chosen.confluences;
   g_active.zoneRetests=chosen.zoneRetests;
   g_active.signalId=(long)chosen.armedClock;
   g_active.entry=entry;
   g_active.sl=sl;
   g_active.tp=tp;
   g_active.rr=rr;
   g_active.entryLo=chosen.entryLo;
   g_active.entryHi=chosen.entryHi;
   g_active.entryTime=chosen.entryTime;
   g_active.startClock=TimeCurrent();
   g_active.startBarTime=currentBarTime;

   double fullReward=MathAbs(tp-entry);
   g_active.beTrigger=RoundPrice(
      trigger=="BUY"
      ? entry+fullReward*BE_ARM_PROGRESS
      : entry-fullReward*BE_ARM_PROGRESS);

   g_active.beArmed=false;
   g_state=ST_ACTIVE;
   g_liveSignalCount++;

   PriceMarker("LIVE_MARK",TimeCurrent(),entry,
               (trigger=="BUY"?"▲ LIVE BUY":"▼ LIVE SELL"),
               (trigger=="BUY"?InpBuyColor:InpSellColor));

   if(InpAlertLive)
   {
      string msg=(trigger=="BUY"?"🟢 BUY • TRADE ACTIVE":"🔴 SELL • TRADE ACTIVE")+
                 StringFormat("\n\n%s • %s • %s\n\nENTRY: %s\nTAKE PROFIT: %s\nSTOP LOSS: %s\n\nCONFLUENCES: %d\n━━━━━━━━━━━━━━━\n⚡️ POSITION ACTIVE",
                              _Symbol,g_mode,g_tfLabel,
                              PriceText(entry),PriceText(tp),PriceText(sl),
                              g_active.confluences);

      if(g_active.counterTrend)
         msg+="\n⚠️ COUNTER-TREND TRADE";

      msg+="\n\nEZYMAP • SCALP MASTERY";
      AlertUser(msg);
   }

   // First touch wins; cancel both READY snapshots.
   ClearReadySnapshot(g_buyReady);
   ClearReadySnapshot(g_sellReady);
   ClearReadySnapshot(g_ready);
}

void ManageActive(double livePrice)
{
   if(g_state!=ST_ACTIVE)
      return;

   MqlRates e[];
   if(!LoadRatesFlexible(g_entryTF,4,2,e))
      return;

   // TradingView V1.2 starts result monitoring only from a later chart candle.
   if(g_active.startBarTime>0 && e[0].time<=g_active.startBarTime)
      return;

   bool target=(g_active.direction=="BUY")
               ? (livePrice>=g_active.tp)
               : (livePrice<=g_active.tp);

   bool stop=(g_active.direction=="BUY")
             ? (livePrice<=g_active.sl)
             : (livePrice>=g_active.sl);

   bool reachedBE=(g_active.direction=="BUY")
                  ? (livePrice>=g_active.beTrigger)
                  : (livePrice<=g_active.beTrigger);

   bool beWasArmed=g_active.beArmed;

   if(reachedBE)
      g_active.beArmed=true;

   // V1.2 BE returns into ANY part of the frozen entry rectangle.
   bool insideEntry=(livePrice>=g_active.entryLo &&
                     livePrice<=g_active.entryHi);

   bool be=(beWasArmed && insideEntry);

   // Gap/original SL remains first priority.
   if(stop)
   {
      double p=(g_active.direction=="BUY")
               ? (g_active.sl-g_active.entry)/g_pipSize
               : (g_active.entry-g_active.sl)/g_pipSize;
      FinishTrade(ST_SL,p);
      return;
   }

   if(be)
   {
      FinishTrade(ST_BE,0.0);
      return;
   }

   if(target)
   {
      double p=(g_active.direction=="BUY")
               ? (g_active.tp-g_active.entry)/g_pipSize
               : (g_active.entry-g_active.tp)/g_pipSize;
      FinishTrade(ST_TP,p);
      return;
   }
}

void ResetResultAfterTTL()
{
   if((g_state==ST_TP || g_state==ST_SL || g_state==ST_BE) &&
      TimeCurrent()-g_resultTime>=60)
   {
      ZeroMemory(g_active);
      g_active.direction="NONE";
      ResetReady();
      g_state=ST_MONITORING;
      DeleteObject("LIVE_MARK");
   }
}



//---------------------------- Constants -----------------------------
#define LAYER_MARKET 0
#define LAYER_LIMIT  1
#define LAYER_STOP   2

struct BridgeSignal
{
   bool     valid;
   int      state;
   int      direction;       // +1 BUY, -1 SELL
   double   entryLo;
   double   entryHi;
   double   sl;
   int      confluences;
   int      zoneRetests;
   bool     counterTrend;
   long     signalId;
   datetime armedTime;
   datetime heartbeat;
};

struct LayerPlan
{
   double rawPrice;
   double execPrice;
   double volume;
   double lossPerLot;
   int    kind;
};

//---------------------------- EA state ------------------------------
long     g_signalId=0;
long     g_lastDoneSignalId=0;
int      g_direction=0;
double   g_commonSL=0.0;
double   g_riskBudget=0.0;
datetime g_signalStarted=0;
bool     g_hadFill=false;

//---------------------------- Utilities -----------------------------
void Log(string msg)
{
   if(InpPrintExecutionLog)
      Print("EzyMap P2: ",msg);
}

string SafeSymbolKey()
{
   string s=_Symbol;
   string out="";
   for(int i=0;i<StringLen(s);i++)
   {
      ushort c=StringGetCharacter(s,i);
      bool ok=((c>='A' && c<='Z') || (c>='a' && c<='z') || (c>='0' && c<='9'));
      out += ok ? ShortToString(c) : "_";
   }
   return out;
}

string StatePrefix()
{
   return "EZP2EA_"+IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN))+"_"+SafeSymbolKey()+"_";
}

void SaveState()
{
   string p=StatePrefix();
   GlobalVariableSet(p+"SIGNAL",(double)g_signalId);
   GlobalVariableSet(p+"LAST_DONE",(double)g_lastDoneSignalId);
   GlobalVariableSet(p+"DIR",(double)g_direction);
   GlobalVariableSet(p+"SL",g_commonSL);
   GlobalVariableSet(p+"RISK",g_riskBudget);
   GlobalVariableSet(p+"START",(double)g_signalStarted);
   GlobalVariableSet(p+"HAD_FILL",g_hadFill?1.0:0.0);

   // V2.0 S2: zone touch history rides the existing state path.
   SaveZoneTouchState();
}

void LoadState()
{
   string p=StatePrefix();
   if(GlobalVariableCheck(p+"SIGNAL"))    g_signalId=(long)GlobalVariableGet(p+"SIGNAL");
   if(GlobalVariableCheck(p+"LAST_DONE")) g_lastDoneSignalId=(long)GlobalVariableGet(p+"LAST_DONE");
   if(GlobalVariableCheck(p+"DIR"))       g_direction=(int)GlobalVariableGet(p+"DIR");
   if(GlobalVariableCheck(p+"SL"))        g_commonSL=GlobalVariableGet(p+"SL");
   if(GlobalVariableCheck(p+"RISK"))      g_riskBudget=GlobalVariableGet(p+"RISK");
   if(GlobalVariableCheck(p+"START"))     g_signalStarted=(datetime)GlobalVariableGet(p+"START");
   if(GlobalVariableCheck(p+"HAD_FILL"))  g_hadFill=(GlobalVariableGet(p+"HAD_FILL")>0.5);

   // V2.0 S2: restore zone touch history.
   LoadZoneTouchState();
}

void ClearCurrentState(bool markDone)
{
   if(markDone && g_signalId>0)
      g_lastDoneSignalId=g_signalId;

   g_signalId=0;
   g_direction=0;
   g_commonSL=0.0;
   g_riskBudget=0.0;
   g_signalStarted=0;
   g_hadFill=false;
   SaveState();
}

bool ReadDirectEzySignal(BridgeSignal &s)
{
   ZeroMemory(s);
   s.valid=false;
   s.state=(int)g_state;
   s.heartbeat=TimeCurrent();

   if(g_state==ST_ACTIVE || g_state==ST_TP || g_state==ST_SL || g_state==ST_BE)
   {
      s.direction=(g_active.direction=="BUY")?1:-1;
      s.entryLo=MathMin(g_active.entryLo,g_active.entryHi);
      s.entryHi=MathMax(g_active.entryLo,g_active.entryHi);
      s.sl=g_active.sl;
      s.confluences=g_active.confluences;
      s.zoneRetests=g_active.zoneRetests;
      s.counterTrend=g_active.counterTrend;
      s.signalId=g_active.signalId;
      s.armedTime=(datetime)g_active.signalId;
   }
   else if(!InpV120SignalParityMode && g_state==ST_READY)
   {
      // Optional legacy pre-staging mode.
      s.direction=(g_ready.direction=="BUY")?1:-1;
      s.entryLo=MathMin(g_ready.entryLo,g_ready.entryHi);
      s.entryHi=MathMax(g_ready.entryLo,g_ready.entryHi);
      s.sl=g_ready.planSL;
      s.confluences=g_ready.confluences;
      s.zoneRetests=g_ready.zoneRetests;
      s.counterTrend=g_ready.counterTrend;
      s.signalId=(long)g_ready.armedClock;
      s.armedTime=g_ready.armedClock;
   }

   s.valid=(s.signalId>0 &&
            (s.direction==1 || s.direction==-1) &&
            s.entryHi>s.entryLo &&
            s.sl>0);

   return s.valid;
}

double RiskPctForConfidence(int conf)
{
   double pct=InpRiskPct_1Conf;

   if(conf>=5)
      pct=InpRiskPct_5Plus;
   else if(conf==4)
      pct=InpRiskPct_4Conf;
   else if(conf==3)
      pct=InpRiskPct_3Conf;
   else if(conf==2)
      pct=InpRiskPct_2Conf;
   else
      pct=InpRiskPct_1Conf;

   pct=MathMin(pct,InpMaxRiskPct);
   return MathMax(0.0,pct);
}

int VolumeDigits()
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   int d=0;
   while(d<8 && MathAbs(step-NormalizeDouble(step,d))>1e-10)
      d++;
   return d;
}

int FindJournalTradeRow(JournalTradeRow &rows[],long positionId)
{
   for(int i=0;i<ArraySize(rows);i++)
      if(rows[i].positionId==positionId)
         return i;
   return -1;
}

int EnsureJournalTradeRow(JournalTradeRow &rows[],long positionId)
{
   int index=FindJournalTradeRow(rows,positionId);
   if(index>=0)
      return index;

   index=ArraySize(rows);
   ArrayResize(rows,index+1);
   rows[index].positionId=positionId;
   rows[index].entryLots=0.0;
   rows[index].netPnl=0.0;
   rows[index].hasExit=false;
   return index;
}

bool JournalPositionIdentifierIsOpen(long positionId)
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;
      if((long)PositionGetInteger(POSITION_IDENTIFIER)==positionId)
         return true;
   }
   return false;
}

bool JournalUlongExists(ulong value,ulong &values[])
{
   for(int i=0;i<ArraySize(values);i++)
      if(values[i]==value)
         return true;
   return false;
}

double JournalDealNetPnl(ulong deal)
{
   return HistoryDealGetDouble(deal,DEAL_PROFIT)+
          HistoryDealGetDouble(deal,DEAL_COMMISSION)+
          HistoryDealGetDouble(deal,DEAL_SWAP)+
          HistoryDealGetDouble(deal,DEAL_FEE);
}

bool BuildJournalPerformanceSnapshot(JournalPerformanceSnapshot &snapshot)
{
   ZeroMemory(snapshot);

   int days=MathMax(0,InpStatsHistoryDays);
   datetime now=TimeCurrent();
   datetime from=(days==0)?0:now-days*24*60*60;
   if(!HistorySelect(from,now+60))
      return false;

   JournalTradeRow rows[];
   ulong entryOrders[];
   ArrayResize(rows,0);
   ArrayResize(entryOrders,0);

   int deals=HistoryDealsTotal();
   for(int i=0;i<deals;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber)
         continue;

      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL)
         continue;

      long positionId=(long)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(positionId<=0)
         continue;

      int row=EnsureJournalTradeRow(rows,positionId);
      rows[row].netPnl+=JournalDealNetPnl(deal);

      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);

      if((entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT) && volume>0.0)
      {
         rows[row].entryLots+=volume;
         snapshot.lotsTraded+=volume;

         ulong order=(ulong)HistoryDealGetInteger(deal,DEAL_ORDER);
         if(order>0 && !JournalUlongExists(order,entryOrders))
         {
            int n=ArraySize(entryOrders);
            ArrayResize(entryOrders,n+1);
            entryOrders[n]=order;
         }
      }

      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
         rows[row].hasExit=true;
   }

   snapshot.actualEntryFills=ArraySize(entryOrders);
   double pnlEpsilon=0.005;

   for(int i=0;i<ArraySize(rows);i++)
   {
      if(rows[i].entryLots<=0.0)
         continue;

      if(JournalPositionIdentifierIsOpen(rows[i].positionId))
      {
         snapshot.openTrades++;
         continue;
      }

      if(!rows[i].hasExit)
         continue;

      snapshot.totalTrades++;
      snapshot.closedNetPnl+=rows[i].netPnl;

      if(rows[i].netPnl>pnlEpsilon)
         snapshot.wins++;
      else if(rows[i].netPnl<-pnlEpsilon)
         snapshot.losses++;
      else
         snapshot.breakeven++;
   }

   return true;
}

void ReportJournalPerformance(bool force,string reason)
{
   if(!InpReportPerformanceToJournal)
      return;

   datetime now=TimeCurrent();
   int interval=MathMax(10,InpStatsReportIntervalSeconds);
   if(!force && g_lastStatsReportClock>0 && now-g_lastStatsReportClock<interval)
      return;

   JournalPerformanceSnapshot stats;
   if(!BuildJournalPerformanceSnapshot(stats))
      return;

   double winRate=(stats.wins+stats.losses)>0
                  ? 100.0*(double)stats.wins/(double)(stats.wins+stats.losses)
                  : 0.0;

   string signature=
      DoubleToString(stats.lotsTraded,VolumeDigits())+"|"+
      IntegerToString(stats.actualEntryFills)+"|"+
      IntegerToString(stats.totalTrades)+"|"+
      IntegerToString(stats.wins)+"|"+
      IntegerToString(stats.losses)+"|"+
      IntegerToString(stats.breakeven)+"|"+
      IntegerToString(stats.openTrades)+"|"+
      DoubleToString(stats.closedNetPnl,2);

   g_lastStatsReportClock=now;
   if(!force && signature==g_lastStatsSignature)
      return;
   g_lastStatsSignature=signature;

   Print("EzyMap P2: PERFORMANCE ",reason,
         " | lot traded=",DoubleToString(stats.lotsTraded,VolumeDigits()),
         " | actual entry fills=",IntegerToString(stats.actualEntryFills),
         " | total trades=",IntegerToString(stats.totalTrades),
         " | wins=",IntegerToString(stats.wins),
         " | losses=",IntegerToString(stats.losses),
         " | breakeven=",IntegerToString(stats.breakeven),
         " | open trades=",IntegerToString(stats.openTrades),
         " | winrate=",DoubleToString(winRate,2),"%",
         " | closed net=",DoubleToString(stats.closedNetPnl,2)," ",
         AccountInfoString(ACCOUNT_CURRENCY));
}

double NormalizeVolumeDown(double vol)
{
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(step<=0) step=minVol;
   if(step<=0) return 0.0;
   if(vol<minVol) return 0.0;

   vol=MathMin(vol,maxVol);
   double v=MathFloor((vol+1e-12)/step)*step;
   if(v<minVol) return 0.0;

   return NormalizeDouble(v,VolumeDigits());
}

double AutoBaseLayerLot()
{
   double effectiveEquity=EffectiveAccountEquity();
   double sizingCapital=LotSizingCapitalUnits();

   if(effectiveEquity<MinimumTradingEquity())
      return 0.0;

   double baseEquity=MathMax(1.0,InpBaseEquity);
   double rawLot=InpBaseLayerLot*(sizingCapital/baseEquity);

   // Always round DOWN to broker volume step so automatic scaling never
   // increases exposure beyond the proportional account-size target.
   double lot=NormalizeVolumeDown(rawLot);

   // Broker minimum may be above the calculated value.
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(lot<minVol)
      return 0.0;

   return lot;
}


double OneLotLoss(int direction,double entry,double sl)
{
   if(entry<=0 || sl<=0) return 0.0;
   if(direction==1 && sl>=entry) return 0.0;
   if(direction==-1 && sl<=entry) return 0.0;

   double profit=0.0;
   ENUM_ORDER_TYPE type=(direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,profit))
   {
      Log("OrderCalcProfit failed. Error "+IntegerToString(GetLastError()));
      return 0.0;
   }

   return MathAbs(profit);
}

// Previously, on a STANDARD (non-cent) account, CapSetupVolumeForCentSafety()
// applied NO percentage-of-equity risk cap at all - it just rounded the
// confidence lot-per-$100-equity request down to the broker's volume step
// and returned it. InpConfidenceLotRiskGuardPct existed as an input but was
// never actually enforced for standard accounts. This closes that gap: cap
// the requested volume so the entry->SL loss (computed the same way the
// cent-safety path already does, via OrderCalcProfit) cannot exceed
// InpConfidenceLotRiskGuardPct percent of current equity.
double CapVolumeForStandardRiskGuard(int direction,
                                     double entry,
                                     double sl,
                                     double requested)
{
   double normalized=NormalizeVolumeDown(requested);

   if(normalized<=0.0 || InpConfidenceLotRiskGuardPct<=0.0)
      return normalized;

   if(entry<=0.0 || sl<=0.0)
      return normalized;

   ENUM_ORDER_TYPE orderType=(direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;

   double probeProfit=0.0;
   if(!OrderCalcProfit(orderType,_Symbol,normalized,entry,sl,probeProfit))
      return normalized;

   double lossPerLot=MathAbs(probeProfit)/normalized;
   if(lossPerLot<=0.0)
      return normalized;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskBudget=equity*InpConfidenceLotRiskGuardPct/100.0;
   double maxByRisk=NormalizeVolumeDown(riskBudget/lossPerLot);
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(maxByRisk<minVol-1e-12)
   {
      Log("STANDARD RISK GUARD BLOCK | requested="+
          DoubleToString(normalized,VolumeDigits())+
          " | entry->SL loss/lot="+DoubleToString(lossPerLot,2)+
          " | equity="+DoubleToString(equity,2)+
          " | cap="+DoubleToString(InpConfidenceLotRiskGuardPct,2)+"%"+
          " | even the broker minimum lot exceeds the risk cap");
      return 0.0;
   }

   double capped=MathMin(normalized,maxByRisk);

   if(capped<normalized-1e-12)
      Log("STANDARD RISK GUARD CAP | requested="+
          DoubleToString(normalized,VolumeDigits())+
          " -> allowed="+DoubleToString(capped,VolumeDigits())+
          " | entry->SL loss/lot="+DoubleToString(lossPerLot,2)+
          " | equity="+DoubleToString(equity,2)+
          " | cap="+DoubleToString(InpConfidenceLotRiskGuardPct,2)+"%");

   return capped;
}

double CapSetupVolumeForCentSafety(int direction,
                                    double entry,
                                    double sl,
                                    double requested)
{
   if(requested<=0.0)
      return 0.0;

   // V2.0 S1: quality sizing is applied HERE because every entry path -
   // aggressive arm, persistent layer, forced/direct zero-conf - funnels
   // through this function on its way to the broker. Applying it before the
   // caps (rather than after) guarantees quality can only ever REDUCE size:
   // the risk and margin caps below still have the final word, so a
   // multiplier can never push volume above what the cap permits.
   string qualityReason="";
   double qualityMultiplier=V2QualitySizeMultiplier(direction,qualityReason);

   if(qualityMultiplier<=0.0)
   {
      Log("V2.0 QUALITY BLOCK | "+string(direction==1?"BUY":"SELL")+
          " | reason="+qualityReason+
          " | requested="+DoubleToString(requested,VolumeDigits()));
      return 0.0;
   }

   if(qualityMultiplier<1.0-1e-9)
   {
      double scaled=NormalizeVolumeDown(requested*qualityMultiplier);
      double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

      // Never scale a setup out of existence: if the multiplier would drop it
      // under the broker minimum, take it at the minimum instead. Quality
      // adjusts SIZE, it does not reject setups - frequency stays constant.
      if(scaled<minVolume-1e-12)
         scaled=NormalizeVolumeDown(minVolume);

      Log("V2.0 QUALITY SIZING | "+string(direction==1?"BUY":"SELL")+
          " | reason="+qualityReason+
          " | requested="+DoubleToString(requested,VolumeDigits())+
          " -> "+DoubleToString(scaled,VolumeDigits())+
          " (x"+DoubleToString(qualityMultiplier,2)+")");

      requested=scaled;

      if(requested<=0.0)
         return 0.0;
   }

   if(g_accountUnitDivisor<=1.0 || !InpEnableCentSafetyCaps)
      return CapVolumeForStandardRiskGuard(direction,entry,sl,requested);

   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double probe=MathMax(minVol,MathMin(1.0,maxVol));

   if(minVol<=0.0 || probe<=0.0)
      return 0.0;

   double safe=requested;

   if(InpCentAbsoluteMaxLots>0.0)
      safe=MathMin(safe,InpCentAbsoluteMaxLots);

   ENUM_ORDER_TYPE orderType=(direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;

   // LIVE-CENT PARITY: validate the requested cent-symbol lot against the
   // exact 50-strategy-pip protection distance and broker-calculated margin.
   if(IsLiveCentAccount() &&
      InpLiveCentParityMode &&
      InpLiveCentMarginOnlyMinimumApproval &&
      InpLiveCentBrokerMinimumExecution)
   {
      double candidate=MathMax(minVol,MathMin(safe,maxVol));
      candidate=NormalizeVolumeDown(candidate);

      if(candidate<minVol-1e-12)
         return 0.0;

      if(InpCentAbsoluteMaxLots>0.0 &&
         candidate>InpCentAbsoluteMaxLots+1e-12)
      {
         Log("LIVE CENT PARITY BLOCK | candidate exceeds absolute lot cap");
         return 0.0;
      }

      // V3.190 S3: risk must be measured against the ACTUAL stop for this
      // setup. This previously used the TRAILING distance, which understated
      // the real entry->stop risk by two thirds (7 pips vs a 21-pip stop) and
      // would be wrong again in a different way once S03 makes the stop
      // variable. Prefer the caller's real sl; fall back to the resolved
      // preset distance only if no usable stop was supplied.
      double protectionSL=sl;

      if(protectionSL<=0.0 ||
         (direction==1 && protectionSL>=entry) ||
         (direction==-1 && protectionSL<=entry))
      {
         double protectionDistance=
            ProtectionPriceDistance(ResolvedPresetStopPips());
         protectionSL=RoundProtectionStop(
            direction,
            direction==1 ? entry-protectionDistance : entry+protectionDistance);
      }
      double candidatePnL=0.0;
      if(!OrderCalcProfit(orderType,_Symbol,candidate,entry,protectionSL,candidatePnL))
      {
         Log("LIVE CENT PARITY BLOCK | OrderCalcProfit failed | error="+
             IntegerToString(GetLastError()));
         return 0.0;
      }

      double rawEquity=MathMax(0.0,AccountInfoDouble(ACCOUNT_EQUITY));
      double candidateRisk=MathAbs(candidatePnL);
      double riskPct=(rawEquity>0.0)?candidateRisk/rawEquity*100.0:DBL_MAX;

      if(InpCentMaxRiskPerSetupPct>0.0 &&
         riskPct>InpCentMaxRiskPerSetupPct+1e-9)
      {
         double permitted=candidate*(InpCentMaxRiskPerSetupPct/riskPct);
         candidate=NormalizeVolumeDown(permitted);
         if(candidate<minVol-1e-12)
         {
            Log("LIVE CENT PARITY BLOCK | entry->stop risk="+
                DoubleToString(riskPct,2)+"% exceeds max "+
                DoubleToString(InpCentMaxRiskPerSetupPct,2)+"% and normalized lot is below minimum");
            return 0.0;
         }

         if(!OrderCalcProfit(orderType,_Symbol,candidate,entry,protectionSL,candidatePnL))
            return 0.0;
         candidateRisk=MathAbs(candidatePnL);
         riskPct=(rawEquity>0.0)?candidateRisk/rawEquity*100.0:DBL_MAX;
      }

      double candidateMargin=0.0;
      if(!OrderCalcMargin(orderType,_Symbol,candidate,entry,candidateMargin))
      {
         Log("LIVE CENT PARITY BLOCK | OrderCalcMargin failed | error="+
             IntegerToString(GetLastError()));
         return 0.0;
      }

      double freeMargin=MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      double marginUsePct=(freeMargin>0.0)
                          ? candidateMargin/freeMargin*100.0
                          : DBL_MAX;

      if(InpLiveCentMaximumMarginUsePct>0.0 &&
         marginUsePct>InpLiveCentMaximumMarginUsePct+1e-9)
      {
         Log("LIVE CENT PARITY BLOCK | candidate="+
             DoubleToString(candidate,VolumeDigits())+
             " | margin="+DoubleToString(candidateMargin,2)+
             " | free margin="+DoubleToString(freeMargin,2)+
             " | use="+DoubleToString(marginUsePct,2)+
             "% / max "+DoubleToString(InpLiveCentMaximumMarginUsePct,2)+"%");
         return 0.0;
      }

      Log("LIVE CENT PARITY APPROVED | candidate="+
          DoubleToString(candidate,VolumeDigits())+
          " | entry->stop risk="+DoubleToString(candidateRisk,2)+" "+
          AccountInfoString(ACCOUNT_CURRENCY)+
          " ("+DoubleToString(riskPct,2)+"%)"+
          " | margin="+DoubleToString(candidateMargin,2)+
          " | margin use="+DoubleToString(marginUsePct,2)+"%");
      return candidate;
   }

   double probeProfit=0.0;
   double lossPerLot=0.0;
   if(OrderCalcProfit(orderType,_Symbol,probe,entry,sl,probeProfit))
      lossPerLot=MathAbs(probeProfit)/probe;

   if(InpCentMaxRiskPerSetupPct>0.0 && lossPerLot>0.0)
   {
      double riskBudget=AccountInfoDouble(ACCOUNT_EQUITY)*
                        InpCentMaxRiskPerSetupPct/100.0;
      safe=MathMin(safe,riskBudget/lossPerLot);
   }

   double probeMargin=0.0;
   double marginPerLot=0.0;
   if(OrderCalcMargin(orderType,_Symbol,probe,entry,probeMargin))
      marginPerLot=probeMargin/probe;

   if(InpCentMaxMarginUsePct>0.0 && marginPerLot>0.0)
   {
      double marginBudget=AccountInfoDouble(ACCOUNT_MARGIN_FREE)*
                          InpCentMaxMarginUsePct/100.0;
      safe=MathMin(safe,marginBudget/marginPerLot);
   }

   double normalized=NormalizeVolumeDown(safe);

   if(normalized<minVol-1e-12 && InpAllowCentMinimumLotFallback)
   {
      double rawEquity=MathMax(0.0,AccountInfoDouble(ACCOUNT_EQUITY));
      double freeMargin=MathMax(0.0,AccountInfoDouble(ACCOUNT_MARGIN_FREE));
      double minLotLoss=(lossPerLot>0.0)?lossPerLot*minVol:DBL_MAX;
      double minLotMargin=(marginPerLot>0.0)?marginPerLot*minVol:DBL_MAX;
      double minLotRiskPct=(rawEquity>0.0)?minLotLoss/rawEquity*100.0:DBL_MAX;
      double minLotMarginPct=(freeMargin>0.0)?minLotMargin/freeMargin*100.0:DBL_MAX;

      bool riskOK=(InpCentMinimumLotMaxRiskPct<=0.0 ||
                   minLotRiskPct<=InpCentMinimumLotMaxRiskPct+1e-9);
      bool marginOK=(InpCentMinimumLotMaxMarginPct<=0.0 ||
                     minLotMarginPct<=InpCentMinimumLotMaxMarginPct+1e-9);
      bool absoluteOK=(InpCentAbsoluteMaxLots<=0.0 ||
                       minVol<=InpCentAbsoluteMaxLots+1e-12);

      if(riskOK && marginOK && absoluteOK)
      {
         Log("CENT MINIMUM LOT FALLBACK | allowed="+
             DoubleToString(minVol,VolumeDigits())+
             " | calculated risk="+DoubleToString(minLotRiskPct,2)+"%"+
             " | calculated margin="+DoubleToString(minLotMarginPct,2)+"%");
         return NormalizeDouble(minVol,VolumeDigits());
      }

      Log("CENT MINIMUM LOT REJECTED | broker minimum="+
          DoubleToString(minVol,VolumeDigits())+
          " | risk="+DoubleToString(minLotRiskPct,2)+"% / max "+
          DoubleToString(InpCentMinimumLotMaxRiskPct,2)+"%"+
          " | margin="+DoubleToString(minLotMarginPct,2)+"% / max "+
          DoubleToString(InpCentMinimumLotMaxMarginPct,2)+"%");
   }

   if(normalized<minVol-1e-12)
   {
      Log("CENT SAFETY BLOCK | requested="+
          DoubleToString(requested,VolumeDigits())+
          " | computed safe="+DoubleToString(safe,VolumeDigits())+
          " | broker minimum="+DoubleToString(minVol,VolumeDigits())+
          " | effective equity="+DoubleToString(EffectiveAccountEquity(),2)+
          " | raw equity="+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
      return 0.0;
   }

   if(normalized<requested-1e-12)
   {
      Log("CENT SAFETY CAP | requested="+
          DoubleToString(requested,VolumeDigits())+
          " -> allowed="+DoubleToString(normalized,VolumeDigits())+
          " | effective equity="+DoubleToString(EffectiveAccountEquity(),2)+
          " | raw equity="+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2));
   }

   return normalized;
}

bool TradingEnvironmentReady(string &reason)
{
   reason="";

   if((bool)MQLInfoInteger(MQL_TESTER))
      return true;

   if(!(bool)TerminalInfoInteger(TERMINAL_CONNECTED))
   {
      reason="terminal disconnected";
      return false;
   }

   if(!(bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      reason="terminal Algo Trading disabled";
      return false;
   }

   if(!(bool)MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      reason="EA live trading permission disabled";
      return false;
   }

   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
   {
      reason="account trading disabled";
      return false;
   }

   if(!(bool)AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
   {
      reason="account expert trading disabled";
      return false;
   }

   ENUM_SYMBOL_TRADE_MODE mode=
      (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);

   if(mode==SYMBOL_TRADE_MODE_DISABLED ||
      mode==SYMBOL_TRADE_MODE_CLOSEONLY)
   {
      reason="symbol trade mode does not permit new entries";
      return false;
   }

   return true;
}

bool SpreadAllowed()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double spread=(tick.ask-tick.bid)/_Point;

   // V2.2 BTC S07: legacy static-cap path, unchanged behaviour when
   // auto-calibration is off (this is the ONLY branch the XAUUSD lineage uses).
   if(!InpAutoCalibrateSpreadCap)
   {
      if(InpMaxSpreadPoints<=0) return true;
      return (spread<=InpMaxSpreadPoints);
   }

   // Already calibrated: enforce the measured cap.
   if(g_spreadCalEffectiveCap>=0.0)
      return (spread<=g_spreadCalEffectiveCap);

   // Still calibrating: collect this sample, fail OPEN regardless of its
   // value. A slow/incomplete calibration must never itself zero out a run.
   int required=MathMax(20,InpSpreadCalibrationTicks);

   if(g_spreadCalCount<ArraySize(g_spreadCalSamples))
   {
      g_spreadCalSamples[g_spreadCalCount]=spread;
      g_spreadCalCount++;
   }

   if(g_spreadCalCount>=required)
   {
      double median=MedianOfSpreadSamples(g_spreadCalSamples,g_spreadCalCount);
      double mult=MathMax(1.0,InpSpreadCalibrationMultiplier);
      double effective=median*mult;

      if(InpSpreadCalibrationCeilingPoints>0)
         effective=MathMin(effective,(double)InpSpreadCalibrationCeilingPoints);

      g_spreadCalEffectiveCap=MathMax(1.0,effective);

      Log("V2.2 BTC SPREAD AUTO-CALIBRATION COMPLETE"+
          " | samples="+IntegerToString(g_spreadCalCount)+
          " | median observed="+DoubleToString(median,1)+" points"+
          " | multiplier="+DoubleToString(mult,2)+
          " | ceiling(InpSpreadCalibrationCeilingPoints)="+
          IntegerToString(InpSpreadCalibrationCeilingPoints)+
          (InpSpreadCalibrationCeilingPoints<=0?" (uncapped)":"")+
          " | EFFECTIVE CAP NOW ENFORCED="+
          DoubleToString(g_spreadCalEffectiveCap,1)+" points");
   }

   return true;
}

// V2.2 BTC S07 follow-up: the three SpreadAllowed() call sites below each log
// a rejection with the literal text "InpMaxSpreadPoints=<raw input>" - which
// is now misleading when InpAutoCalibrateSpreadCap is on, because a rejection
// in that mode is compared against g_spreadCalEffectiveCap, not the raw
// input. That ambiguity is exactly what made a real test run's journal
// impossible to read: "current spread exceeds InpMaxSpreadPoints=120" looks
// identical whether auto-calibration never ran (old .ex5) or ran and simply
// arrived at a calibrated cap that still rejected this tick. This helper
// reports what is ACTUALLY being enforced right now, so the rejection log
// itself proves which code path produced it.
string EffectiveSpreadCapText()
{
   if(!InpAutoCalibrateSpreadCap)
      return "static cap="+IntegerToString(InpMaxSpreadPoints)+
             (InpMaxSpreadPoints<=0?" (DISABLED, should not reject)":"");

   if(g_spreadCalEffectiveCap<0.0)
      return "STILL CALIBRATING ("+IntegerToString(g_spreadCalCount)+"/"+
             IntegerToString(MathMax(20,InpSpreadCalibrationTicks))+
             " samples, filter inactive, should not reject)";

   return "calibrated cap="+DoubleToString(g_spreadCalEffectiveCap,1);
}

//====================== V2.1a CONFLUENCE ENGINE =====================
// V2.1a S1/S2: one scoring engine, called from BOTH entry paths.
//
// Placed immediately after the two existing environment gates because it is
// the same kind of thing - a pre-deployment veto - even though, unlike them,
// it is scored rather than boolean. It is deliberately NOT folded into
// TradingEnvironmentReady(): that function returns true immediately under
// MQL_TESTER, so a gate hosted there would be inert in every backtest.

// V2.1a S1: fold any integer into [0,23]. MQL5's % keeps the sign of the
// dividend, so a negative input hour would otherwise produce a negative
// bucket and silently mis-classify every bar.
int NormalizeHour24(int hour)
{
   int h=hour%24;
   if(h<0) h+=24;
   return h;
}

// V2.1a S1: broker-server-hour -> session tag.
//
// BOUNDARY LOGIC, stated explicitly because hour arithmetic is easy to get
// subtly wrong and the whole stage is worthless if the classification drifts:
//
//   londonClose  := InpLondonOpenHour + 8      (London runs ~8 hours)
//   OVERLAP  = h >= InpNYOpenHour AND h < londonClose AND h < InpNYCloseHour
//              i.e. NY has opened and London has not yet closed.
//   LONDON   = h >= InpLondonOpenHour AND h < InpNYOpenHour
//              London is open and NY has not opened yet.
//   NY       = h >= londonClose AND h < InpNYCloseHour
//              London has closed, NY still running.
//   DEAD     = the first V21A_DEAD_ZONE_HOURS after InpNYCloseHour, measured
//              with wraparound, so a late NY close still carves its dead zone
//              out of the following morning.
//   ASIA     = everything else, i.e. the remainder of the overnight gap.
//
// Every comparison is on the half-open interval [start,end), so no hour can
// land in two buckets and no hour can fall through: the tests are evaluated
// in the order above and ASIA is the total fallback. With the default
// 8/13/21 inputs this gives OVERLAP 13-15, LONDON 8-12, NY 16-20,
// DEAD 21-22, ASIA 23 and 0-7.
int SessionCodeForHour(int hour)
{
   int h=NormalizeHour24(hour);

   int londonOpen =NormalizeHour24(InpLondonOpenHour);
   int nyOpen     =NormalizeHour24(InpNYOpenHour);
   int nyClose    =NormalizeHour24(InpNYCloseHour);
   int londonClose=NormalizeHour24(londonOpen+8);

   if(h>=nyOpen && h<londonClose && h<nyClose)
      return V21A_SESSION_OVERLAP;

   if(h>=londonOpen && h<nyOpen)
      return V21A_SESSION_LONDON;

   if(h>=londonClose && h<nyClose)
      return V21A_SESSION_NY;

   // Wraparound-safe distance from the NY close.
   int sinceNYClose=NormalizeHour24(h-nyClose);

   if(sinceNYClose<V21A_DEAD_ZONE_HOURS)
      return V21A_SESSION_DEAD;

   return V21A_SESSION_ASIA;
}

// V2.1a S1: code -> log/CSV text.
string SessionCodeText(int code)
{
   if(code==V21A_SESSION_OVERLAP) return "OVERLAP";
   if(code==V21A_SESSION_LONDON)  return "LONDON";
   if(code==V21A_SESSION_NY)      return "NY";
   if(code==V21A_SESSION_ASIA)    return "ASIA";
   if(code==V21A_SESSION_DEAD)    return "DEAD";
   return "UNSET";
}

// V2.1a S1: entry-path code -> log/CSV text.
string EntryPathCodeText(int code)
{
   if(code==V21A_PATHCODE_STANDARD) return V21A_PATH_STANDARD;
   if(code==V21A_PATHCODE_ZEROCONF) return V21A_PATH_ZEROCONF;
   return "UNSET";
}

// V2.1a S1: code -> configured score, clamped into [0,1] so a mistyped input
// cannot push the weighted average outside the range the threshold assumes.
double SessionScoreForCode(int code)
{
   if(code==V21A_SESSION_OVERLAP) return Clamp(InpOverlapSessionScore,0.0,1.0);
   if(code==V21A_SESSION_LONDON)  return Clamp(InpSingleSessionScore,0.0,1.0);
   if(code==V21A_SESSION_NY)      return Clamp(InpSingleSessionScore,0.0,1.0);
   if(code==V21A_SESSION_DEAD)    return Clamp(InpDeadZoneScore,0.0,1.0);
   return Clamp(InpAsiaSessionScore,0.0,1.0);
}

// V2.1a S1: the session component of the aggregate. ONE function, shared by
// both entry paths - the hour logic is never inlined per path.
//
// TimeCurrent() ONLY. In the Strategy Tester TimeCurrent() is the modelled
// server time, so the tester and the live account classify the same bar the
// same way. TimeLocal() would follow the machine running the terminal and
// TimeGMT() would ignore the broker's offset entirely; either would make the
// backtest un-reproducible on a different box or a different broker.
double SessionConfluenceScore()
{
   datetime now=TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(now,dt);

   g_v21aSessionHour =NormalizeHour24(dt.hour);
   g_v21aSessionCode =SessionCodeForHour(g_v21aSessionHour);
   g_v21aSessionScore=SessionScoreForCode(g_v21aSessionCode);

   return g_v21aSessionScore;
}

// V2.1a S2: true when the volatility inputs are identical to the V3.190 S03
// geometry ATR inputs AND that handle actually exists, in which case the
// regime measurement reuses it instead of opening a second identical
// indicator.
bool VolatilityInputsMatchGeometryATR()
{
   return (InpUseATRGeometry &&
           g_geometryATRHandle!=INVALID_HANDLE &&
           InpVolTimeframe==InpATRTimeframe &&
           MathMax(1,InpVolATRPeriod)==MathMax(1,InpATRPeriod));
}

// V2.1a S2: recompute the ATR percentile at most once per bar of
// InpVolTimeframe.
//
// The per-bar guard is what keeps this off the per-tick cost path - the same
// reasoning that governs RefreshGeometryATR() and RefreshH1Bias(), and the
// reason iATR()/iMA() handles are created in OnInit rather than inline. This
// is called from VolatilityRegimeScore(), which itself only runs at a
// deployment attempt, so the CopyBuffer happens at most once per bar and
// only on bars where the EA actually tried to deploy.
//
// Shift 1 is the last CLOSED bar. The forming bar's ATR moves intrabar and
// would make the regime depend on WHEN in the bar the trigger fired.
void RefreshVolatilityATR()
{
   if(!InpScoreVolatilityRegime || g_volATRHandle==INVALID_HANDLE)
      return;

   datetime bar=iTime(_Symbol,InpVolTimeframe,0);

   if(bar<=0 || bar==g_volATRBar)
      return;

   // A percentile over a handful of samples is noise dressed as a statistic,
   // so refuse to produce one below a floor of 20 usable bars.
   int lookback=(int)MathMax(20.0,MathMin(5000.0,(double)InpVolPercentileLookback));

   double buffer[];
   ArraySetAsSeries(buffer,true);

   int copied=CopyBuffer(g_volATRHandle,0,1,lookback,buffer);

   if(copied<20)
      return;   // history not warm yet - keep the previous cache, if any

   double current=buffer[0];

   if(current<=0.0)
      return;

   int valid=0,below=0,equal=0;

   for(int i=0;i<copied;i++)
   {
      if(buffer[i]<=0.0)
         continue;

      valid++;

      if(buffer[i]<current-1e-12)
         below++;
      else if(MathAbs(buffer[i]-current)<=1e-12)
         equal++;
   }

   if(valid<20)
      return;

   // Ties contribute a half each, so a flat stretch of identical ATR values
   // ranks at the middle of its own run rather than at 0 or 100.
   double pct=100.0*(((double)below)+0.5*((double)equal))/((double)valid);

   g_volATRValue=current;
   g_volATRPercentile=Clamp(pct,0.0,100.0);
   g_volATRBar=bar;
}

// V2.1a S2: the volatility component of the aggregate. ONE function, shared
// by both entry paths.
//
// An UNMEASURABLE regime (handle missing, history not warm) scores the
// NORMAL value and never sets the extreme flag. This mirrors V2.0 S03's
// unmeasured departure score: a missing measurement must not manufacture a
// rejection, otherwise the first N bars of every run and every restart would
// silently stop trading.
double VolatilityRegimeScore()
{
   g_volRegimeExtreme=false;

   RefreshVolatilityATR();

   if(g_volATRPercentile<0.0)
   {
      g_v21aVolPercentile=-1.0;
      g_v21aVolScore=Clamp(InpVolNormalScore,0.0,1.0);
      return g_v21aVolScore;
   }

   double low =Clamp(InpVolLowPercentile,0.0,100.0);
   double high=Clamp(InpVolHighPercentile,0.0,100.0);

   // Guard a transposed pair: without this, low=90/high=20 would mark every
   // reading extreme and silently halt the EA.
   if(low>high)
   {
      double swap=low;
      low=high;
      high=swap;
   }

   g_v21aVolPercentile=g_volATRPercentile;

   bool extreme=(g_volATRPercentile<low || g_volATRPercentile>high);

   g_volRegimeExtreme=extreme;

   g_v21aVolScore=
      extreme
      ? Clamp(InpVolExtremeScore,0.0,1.0)
      : Clamp(InpVolNormalScore,0.0,1.0);

   return g_v21aVolScore;
}

// V2.1a S1: shared weighted aggregator.
//
// A source whose master switch is OFF is EXCLUDED from the average, not
// counted as a neutral 0.5 - counting it would drag every aggregate toward
// the middle and make the single threshold mean something different
// depending on which stages happen to be enabled.
//
// Returns a neutral 1.0 when the engine is off or when no source is both
// enabled and weighted, so the gate is a guaranteed pass-through and V2.0
// behaviour is reproduced exactly.
double ConfluenceScore()
{
   g_v21aSessionCode=V21A_SESSION_UNSET;
   g_v21aSessionScore=-1.0;
   g_v21aVolPercentile=-1.0;
   g_v21aVolScore=-1.0;
   g_v21aTotalScore=-1.0;
   g_volRegimeExtreme=false;

   if(!InpUseConfluenceScoring)
      return 1.0;

   double weighted=0.0;
   double weightSum=0.0;

   if(InpScoreSession)
   {
      // Always evaluated when enabled, even at zero weight, so the session
      // tag is still recorded and logged for offset verification.
      double s=SessionConfluenceScore();
      double w=MathMax(0.0,InpSessionWeight);

      if(w>0.0)
      {
         weighted+=s*w;
         weightSum+=w;
      }
   }

   if(InpScoreVolatilityRegime)
   {
      // Always evaluated when enabled, even at zero weight: the hard-block
      // veto and the CSV percentile column both depend on it having run.
      double v=VolatilityRegimeScore();
      double w=MathMax(0.0,InpVolatilityWeight);

      if(w>0.0)
      {
         weighted+=v*w;
         weightSum+=w;
      }
   }

   if(weightSum<=0.0)
   {
      g_v21aTotalScore=1.0;
      return 1.0;
   }

   g_v21aTotalScore=Clamp(weighted/weightSum,0.0,1.0);
   return g_v21aTotalScore;
}

// V2.1a S1: THE GATE. Called once per deployment attempt from each entry
// path. Returns true when the setup may deploy.
//
// While InpUseConfluenceScoring is false this returns true before touching
// the counters and before logging anything, so V2.0 behaviour - including
// V2.0's log output - is reproduced byte for byte.
bool ConfluenceGateAllows(string path,string context)
{
   bool standard=(path==V21A_PATH_STANDARD);

   g_v21aEntryPathCode=
      standard ? V21A_PATHCODE_STANDARD : V21A_PATHCODE_ZEROCONF;

   if(!InpUseConfluenceScoring)
      return true;

   if(standard) g_stdAttempts++;
   else         g_zcAttempts++;

   double total=ConfluenceScore();

   string detail=
      "V2.1a CONFLUENCE | path="+path+
      " | "+context+
      " | session="+
      (InpScoreSession
       ? (SessionCodeText(g_v21aSessionCode)+
          "@"+IntegerToString(g_v21aSessionHour)+"h srv"+
          " score="+DoubleToString(g_v21aSessionScore,3)+
          " weight="+DoubleToString(MathMax(0.0,InpSessionWeight),2))
       : "off")+
      " | volatility="+
      (InpScoreVolatilityRegime
       ? ("pct="+
          (g_v21aVolPercentile>=0.0
           ? DoubleToString(g_v21aVolPercentile,1)
           : "n/a (history not warm - treated as NORMAL)")+
          " bounds="+DoubleToString(InpVolLowPercentile,1)+
          "/"+DoubleToString(InpVolHighPercentile,1)+
          " score="+DoubleToString(g_v21aVolScore,3)+
          " weight="+DoubleToString(MathMax(0.0,InpVolatilityWeight),2)+
          " extreme="+string(g_volRegimeExtreme?"YES":"NO"))
       : "off")+
      " | total="+DoubleToString(total,3)+
      " | threshold="+DoubleToString(InpMinConfluenceScore,3);

   // V2.1a S2: the hard extreme-volatility veto is checked SEPARATELY from
   // and BEFORE the weighted threshold. It is not folded into the score,
   // because "the tape is untradeable" must not be outvotable by a strong
   // session score.
   if(InpScoreVolatilityRegime && InpHardBlockExtremeVol && g_volRegimeExtreme)
   {
      Log(detail+" | RESULT=REJECTED (InpHardBlockExtremeVol:"+
          " ATR percentile outside bounds)");
      return false;
   }

   if(total<InpMinConfluenceScore-1e-12)
   {
      Log(detail+" | RESULT=REJECTED (score below threshold)");
      return false;
   }

   if(standard) g_stdPassed++;
   else         g_zcPassed++;

   Log(detail+" | RESULT=PASSED");
   return true;
}

// V2.1a S1: freeze the snapshot the trade was actually taken on into the
// analytics row, so the CSV reports the scores at DEPLOYMENT time. Safe to
// call with an out-of-range index - it simply does nothing.
void CaptureConfluenceSnapshot(int analyticsIndex)
{
   if(analyticsIndex<0 || analyticsIndex>=ArraySize(g_setupAnalytics))
      return;

   g_setupAnalytics[analyticsIndex].v21aSessionCode   =g_v21aSessionCode;
   g_setupAnalytics[analyticsIndex].v21aSessionScore  =g_v21aSessionScore;
   g_setupAnalytics[analyticsIndex].v21aVolPercentile =g_v21aVolPercentile;
   g_setupAnalytics[analyticsIndex].v21aVolScore      =g_v21aVolScore;
   g_setupAnalytics[analyticsIndex].v21aTotalScore    =g_v21aTotalScore;
   g_setupAnalytics[analyticsIndex].v21aEntryPathCode =g_v21aEntryPathCode;
}

// V2.1a S1: end-of-run frequency instrumentation. Suppressed entirely while
// the engine is off, because with no gate evaluations the rates would read
// 0/0 and imply a filter that never ran had rejected everything.
void LogConfluenceFilterRate()
{
   if(!InpUseConfluenceScoring)
      return;

   double stdPct=
      (g_stdAttempts>0)
      ? (100.0*(double)g_stdPassed/(double)g_stdAttempts)
      : 0.0;

   double zcPct=
      (g_zcAttempts>0)
      ? (100.0*(double)g_zcPassed/(double)g_zcAttempts)
      : 0.0;

   Log("V2.1a CONFLUENCE FILTER RATE | STANDARD: "+
       DoubleToString(stdPct,1)+"% passed ("+
       IntegerToString((int)g_stdPassed)+"/"+
       IntegerToString((int)g_stdAttempts)+") | ZERO-CONF: "+
       DoubleToString(zcPct,1)+"% passed ("+
       IntegerToString((int)g_zcPassed)+"/"+
       IntegerToString((int)g_zcAttempts)+")");
}

// V2.2 BTC S06: end-of-run deployment-gate breakdown. Companion to
// LogConfluenceFilterRate() above - that line answers "did the confluence
// score reject everything?", this one answers "did spread, environment or
// daily capacity reject everything?". Together they cover every gate that
// stands between a stored READY setup and an order-send attempt.
//
// Deliberately NOT suppressed by any input: unlike the confluence rate, a run
// where all four numbers are zero is itself the most important possible
// finding - it means nothing ever even reached these gates, so the blocker is
// further upstream (no setups armed, no touches registered, or an environment
// problem outside the EA such as missing tester history).
void LogDeploymentGateBreakdown()
{
   long spreadTotal  =g_spreadRejectStd+g_spreadRejectZc+g_spreadRejectOther;
   long envTotal     =g_envRejectStd+g_envRejectZc;
   long capacityTotal=g_capacityRejectStd+g_capacityRejectZc+
                      g_capacityRejectOther;
   long sendTotal    =g_orderSendStd+g_orderSendZc+g_orderSendOther;

   Log("V2.2 BTC S06 DEPLOYMENT GATE BREAKDOWN | SPREAD REJECTED: "+
       IntegerToString((int)spreadTotal)+
       " | ENVIRONMENT REJECTED: "+IntegerToString((int)envTotal)+
       " | DAILY CAPACITY REJECTED: "+IntegerToString((int)capacityTotal)+
       " | ORDER-SEND ATTEMPTS: "+IntegerToString((int)sendTotal));

   // Second line carries the per-path split. STANDARD and ZERO-CONF match the
   // two scored entry paths in the CONFLUENCE FILTER RATE line above, so the
   // two lines can be read side by side. OTHER is the legacy bridge-signal
   // arm/PlaceOneLayer path, which belongs to neither scored path.
   // TradingEnvironmentReady() is never called from the OTHER path, which is
   // why the environment field has no OTHER column.
   Log("V2.2 BTC S06 DEPLOYMENT GATE BREAKDOWN BY PATH | SPREAD std/zc/other: "+
       IntegerToString((int)g_spreadRejectStd)+"/"+
       IntegerToString((int)g_spreadRejectZc)+"/"+
       IntegerToString((int)g_spreadRejectOther)+
       " | ENVIRONMENT std/zc: "+
       IntegerToString((int)g_envRejectStd)+"/"+
       IntegerToString((int)g_envRejectZc)+
       " | DAILY CAPACITY std/zc/other: "+
       IntegerToString((int)g_capacityRejectStd)+"/"+
       IntegerToString((int)g_capacityRejectZc)+"/"+
       IntegerToString((int)g_capacityRejectOther)+
       " | ORDER-SEND std/zc/other: "+
       IntegerToString((int)g_orderSendStd)+"/"+
       IntegerToString((int)g_orderSendZc)+"/"+
       IntegerToString((int)g_orderSendOther));
}

//---------------------- Existing trade detection --------------------
int CountOurPendingOrders()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      count++;
   }
   return count;
}

bool PendingOrderDirection(ENUM_ORDER_TYPE type,int &direction)
{
   direction=0;

   if(type==ORDER_TYPE_BUY_LIMIT ||
      type==ORDER_TYPE_BUY_STOP ||
      type==ORDER_TYPE_BUY_STOP_LIMIT)
   {
      direction=1;
      return true;
   }

   if(type==ORDER_TYPE_SELL_LIMIT ||
      type==ORDER_TYPE_SELL_STOP ||
      type==ORDER_TYPE_SELL_STOP_LIMIT)
   {
      direction=-1;
      return true;
   }

   return false;
}

int CountOurPositionsByDirection(int direction)
{
   if(direction!=1 && direction!=-1)
      return 0;

   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      ENUM_POSITION_TYPE type=
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if((direction==1 && type==POSITION_TYPE_BUY) ||
         (direction==-1 && type==POSITION_TYPE_SELL))
         count++;
   }
   return count;
}

int CountOurLosingPositionsByDirection(int direction)
{
   if(direction!=1 && direction!=-1)
      return 0;

   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);

      if(ticket==0)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol)
         continue;

      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
         continue;

      ENUM_POSITION_TYPE type=
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      bool directionMatches=
         (direction==1 && type==POSITION_TYPE_BUY) ||
         (direction==-1 && type==POSITION_TYPE_SELL);

      if(!directionMatches)
         continue;

      double floatingNet=
         PositionGetDouble(POSITION_PROFIT)+
         PositionGetDouble(POSITION_SWAP);

      if(floatingNet<0.0)
         count++;
   }

   return count;
}

bool DirectionalLosingPositionCapacityAvailable(int direction,string context)
{
   if(!InpEnforceDirectionalLosingCap ||
      InpMaxLosingPositionsPerDirection<=0)
      return true;

   int losing=
      CountOurLosingPositionsByDirection(direction);

   if(losing<InpMaxLosingPositionsPerDirection)
      return true;

   Log("DIRECTION LOSING CAP BLOCK | "+
       string(direction==1?"BUY":"SELL")+
       " | losing positions="+
       IntegerToString(losing)+
       "/"+
       IntegerToString(InpMaxLosingPositionsPerDirection)+
       " | new same-direction entry blocked"+
       " | opposite direction remains independent"+
       " | context="+context);

   return false;
}

void CancelPendingOrdersAtDirectionalLosingCap(int direction)
{
   if(!InpEnforceDirectionalLosingCap ||
      !InpCancelPendingAtLosingCap ||
      InpMaxLosingPositionsPerDirection<=0)
      return;

   int losing=
      CountOurLosingPositionsByDirection(direction);

   if(losing<InpMaxLosingPositionsPerDirection)
      return;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)
         continue;

      int orderDirection=0;

      ENUM_ORDER_TYPE type=
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(!PendingOrderDirection(type,orderDirection))
         continue;

      if(orderDirection!=direction)
         continue;

      double price=
         OrderGetDouble(ORDER_PRICE_OPEN);

      if(trade.OrderDelete(ticket))
      {
         Log("DIRECTION LOSING CAP CANCEL | "+
             string(direction==1?"BUY":"SELL")+
             " pending ticket="+
             (string)ticket+
             " @ "+
             DoubleToString(price,_Digits)+
             " | losing positions="+
             IntegerToString(losing)+
             "/"+
             IntegerToString(InpMaxLosingPositionsPerDirection));
      }
      else
      {
         Log("DIRECTION LOSING CAP CANCEL FAILED | "+
             string(direction==1?"BUY":"SELL")+
             " | ticket="+
             (string)ticket+
             " | "+
             trade.ResultRetcodeDescription());
      }
   }
}

void EnforceDirectionalLosingPositionCaps()
{
   CancelPendingOrdersAtDirectionalLosingCap(1);
   CancelPendingOrdersAtDirectionalLosingCap(-1);
}

int CountOurClosedNegativeEntriesCurrentM5()
{
   datetime m5Open=
      iTime(_Symbol,PERIOD_M5,0);

   if(m5Open<=0)
      return 0;

   if(!HistorySelect(m5Open,TimeCurrent()))
      return 0;

   int count=0;
   int total=HistoryDealsTotal();

   for(int i=0;i<total;i++)
   {
      ulong ticket=
         HistoryDealGetTicket(i);

      if(ticket==0)
         continue;

      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol)
         continue;

      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber)
         continue;

      ENUM_DEAL_ENTRY entry=
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);

      if(entry!=DEAL_ENTRY_OUT &&
         entry!=DEAL_ENTRY_OUT_BY)
         continue;

      datetime closeTime=
         (datetime)HistoryDealGetInteger(ticket,DEAL_TIME);

      if(closeTime<m5Open)
         continue;

      double realisedNet=
         HistoryDealGetDouble(ticket,DEAL_PROFIT)+
         HistoryDealGetDouble(ticket,DEAL_COMMISSION)+
         HistoryDealGetDouble(ticket,DEAL_SWAP)+
         HistoryDealGetDouble(ticket,DEAL_FEE);

      if(realisedNet<0.0)
         count++;
   }

   return count;
}

bool M5ClosedLossCapacityAvailable(string context)
{
   if(!InpEnforceM5ClosedLossCap ||
      InpMaxClosedNegativeEntriesPerM5<=0)
      return true;

   int closedLosses=
      CountOurClosedNegativeEntriesCurrentM5();

   if(closedLosses<InpMaxClosedNegativeEntriesPerM5)
      return true;

   Log("M5 CLOSED LOSS CAP BLOCK"+
       " | current M5="+
       TimeToString(
          iTime(_Symbol,PERIOD_M5,0),
          TIME_DATE|TIME_MINUTES)+
       " | closed negative-P/L deals="+
       IntegerToString(closedLosses)+
       "/"+
       IntegerToString(InpMaxClosedNegativeEntriesPerM5)+
       " | BUY and SELL combined=YES"+
       " | new entry blocked until next M5"+
       " | context="+context);

   return false;
}

void CancelAllPendingAtM5ClosedLossCap()
{
   if(!InpEnforceM5ClosedLossCap ||
      !InpCancelPendingAtM5ClosedLossCap ||
      InpMaxClosedNegativeEntriesPerM5<=0)
      return;

   int closedLosses=
      CountOurClosedNegativeEntriesCurrentM5();

   if(closedLosses<InpMaxClosedNegativeEntriesPerM5)
      return;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=
         OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)
         continue;

      int direction=0;

      ENUM_ORDER_TYPE type=
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      if(!PendingOrderDirection(type,direction))
         continue;

      double price=
         OrderGetDouble(ORDER_PRICE_OPEN);

      if(trade.OrderDelete(ticket))
      {
         Log("M5 CLOSED LOSS CAP CANCEL"+
             " | ticket="+
             (string)ticket+
             " | direction="+
             string(direction==1?"BUY":"SELL")+
             " | price="+
             DoubleToString(price,_Digits)+
             " | closed negative-P/L deals="+
             IntegerToString(closedLosses)+
             "/"+
             IntegerToString(InpMaxClosedNegativeEntriesPerM5));
      }
      else
      {
         Log("M5 CLOSED LOSS CAP CANCEL FAILED"+
             " | ticket="+
             (string)ticket+
             " | "+
             trade.ResultRetcodeDescription());
      }
   }
}

void EnforceM5ClosedLossCap()
{
   CancelAllPendingAtM5ClosedLossCap();
}

int CountOurPendingOrdersByDirection(int direction)
{
   if(direction!=1 && direction!=-1)
      return 0;

   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      int orderDirection=0;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!PendingOrderDirection(type,orderDirection)) continue;
      if(orderDirection==direction) count++;
   }
   return count;
}

int DirectionalLayerUsage(int direction)
{
   int used=CountOurPositionsByDirection(direction);
   if(InpCountPendingAsReservedLayer)
      used+=CountOurPendingOrdersByDirection(direction);
   return used;
}

int DirectionalLayerCapacityRemaining(int direction)
{
   if(!InpEnforceDirectionalLayerCap || InpMaxActiveLayersPerDirection<=0)
      return 1000000;

   return MathMax(0,InpMaxActiveLayersPerDirection-DirectionalLayerUsage(direction));
}

// V3.190 S5: favourable excursion of the existing directional exposure, in
// PRICE, measured from the volume-weighted average entry. Zero when the
// direction has no open position.
double DirectionalFavourableExcursion(int direction)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return 0.0;

   double volume=0.0;
   double weighted=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      ENUM_POSITION_TYPE type=
         (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      bool matches=(direction==1 && type==POSITION_TYPE_BUY) ||
                   (direction==-1 && type==POSITION_TYPE_SELL);

      if(!matches) continue;

      double v=PositionGetDouble(POSITION_VOLUME);
      if(v<=0.0) continue;

      volume  += v;
      weighted+= v*PositionGetDouble(POSITION_PRICE_OPEN);
   }

   if(volume<=0.0)
      return 0.0;

   double averageEntry=weighted/volume;
   double current=(direction==1)?tick.bid:tick.ask;

   return (direction==1)?current-averageEntry:averageEntry-current;
}


// V3.190 S5: may this direction take ANOTHER layer on top of what it already
// holds? Only reached once the direction has open exposure - the initial
// layer is never gated by this.
bool ScaleInAllowed(int direction,string context)
{
   if(!InpScaleInOnConfirmation)
      return true;

   int positions=CountOurPositionsByDirection(direction);
   int pending  =CountOurPendingOrdersByDirection(direction);
   int used     =positions+pending;
   int initial  =MathMax(1,InpInitialLayerCount);

   // Still filling the initial allocation - not a scale-in yet.
   if(used<initial)
      return true;

   int added=used-initial;

   if(added>=MathMax(0,InpMaxScaleInLayers))
   {
      Log("V3.190 S5 SCALE-IN CAP | "+string(direction==1?"BUY":"SELL")+
          " | initial="+IntegerToString(initial)+
          " | added="+IntegerToString(added)+
          "/"+IntegerToString(MathMax(0,InpMaxScaleInLayers))+
          " | context="+context);
      return false;
   }

   // Require the existing exposure to be genuinely green before adding.
   double favourable=DirectionalFavourableExcursion(direction);

   double atr=CurrentGeometryATR();
   double reference=(atr>0.0)
                    ? atr
                    : ProtectionPriceDistance(ResolvedPresetStopPips());

   double required=reference*MathMax(0.0,InpScaleInTriggerATRMult);
   double pip=MathMax(StrategyPipSize(),_Point);

   if(favourable<required-_Point*0.25)
   {
      Log("V3.190 S5 SCALE-IN WAIT | "+string(direction==1?"BUY":"SELL")+
          " | favourable="+DoubleToString(favourable/pip,1)+" pips"+
          " | required="+DoubleToString(required/pip,1)+" pips"+
          " ("+DoubleToString(InpScaleInTriggerATRMult,2)+" x "+
          string(atr>0.0?"ATR":"preset stop")+")"+
          " | open="+IntegerToString(positions)+
          " pending="+IntegerToString(pending)+
          " | context="+context);
      return false;
   }

   Log("V3.190 S5 SCALE-IN ALLOWED | "+string(direction==1?"BUY":"SELL")+
       " | favourable="+DoubleToString(favourable/pip,1)+" pips"+
       " >= required "+DoubleToString(required/pip,1)+" pips"+
       " | adding layer "+IntegerToString(added+1)+
       "/"+IntegerToString(MathMax(0,InpMaxScaleInLayers))+
       " | context="+context);

   return true;
}


bool DirectionalLayerSlotAvailable(int direction,string context)
{
   // V3.190 S5: evaluated before the flat layer cap. Sits here because every
   // entry path (aggressive arm, persistent layer, direct zero-conf) already
   // funnels through this function, so one gate covers them all and the
   // scale-in layers still pass through the normal volume/risk capping on
   // their way to the broker.
   if(!ScaleInAllowed(direction,context))
      return false;

   if(!InpEnforceDirectionalLayerCap || InpMaxActiveLayersPerDirection<=0)
      return true;

   int positions=CountOurPositionsByDirection(direction);
   int pending=CountOurPendingOrdersByDirection(direction);
   int used=positions+(InpCountPendingAsReservedLayer?pending:0);

   if(used<InpMaxActiveLayersPerDirection)
      return true;

   Log("DIRECTION LAYER CAP BLOCK | "+
       string(direction==1?"BUY":"SELL")+
       " | open="+IntegerToString(positions)+
       " | pending reserved="+IntegerToString(pending)+
       " | used="+IntegerToString(used)+
       "/"+IntegerToString(InpMaxActiveLayersPerDirection)+
       " | context="+context);
   return false;
}

void TrimExcessPendingForDirection(int direction)
{
   if(!InpEnforceDirectionalLayerCap ||
      !InpTrimExcessPendingToLayerCap ||
      InpMaxActiveLayersPerDirection<=0)
      return;

   int openPositions=CountOurPositionsByDirection(direction);
   int pending=CountOurPendingOrdersByDirection(direction);
   int allowedPending=MathMax(0,InpMaxActiveLayersPerDirection-openPositions);
   int excess=pending-allowedPending;

   if(excess<=0)
      return;

   for(int i=OrdersTotal()-1;i>=0 && excess>0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      int orderDirection=0;
      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(!PendingOrderDirection(type,orderDirection)) continue;
      if(orderDirection!=direction) continue;

      double price=OrderGetDouble(ORDER_PRICE_OPEN);
      if(trade.OrderDelete(ticket))
      {
         excess--;
         Log("DIRECTION CAP TRIM | cancelled "+
             string(direction==1?"BUY":"SELL")+
             " pending ticket="+(string)ticket+
             " @ "+DoubleToString(price,_Digits)+
             " | open positions="+IntegerToString(openPositions)+
             " | max layers="+IntegerToString(InpMaxActiveLayersPerDirection));
      }
      else
      {
         Log("DIRECTION CAP TRIM FAILED | ticket="+(string)ticket+
             " | "+trade.ResultRetcodeDescription());
      }
   }

   if(openPositions>InpMaxActiveLayersPerDirection)
   {
      Log("DIRECTION CAP WARNING | existing "+
          string(direction==1?"BUY":"SELL")+
          " positions="+IntegerToString(openPositions)+
          " already exceed cap="+
          IntegerToString(InpMaxActiveLayersPerDirection)+
          ". Existing positions are not force-closed.");
   }
}

void EnforceDirectionalLayerCaps()
{
   TrimExcessPendingForDirection(1);
   TrimExcessPendingForDirection(-1);
}

bool ExistingEALimitInReadyZone(int direction,
                                  double zoneLo,
                                  double zoneHi,
                                  ulong &existingTicket,
                                  double &existingPrice)
{
   existingTicket=0;
   existingPrice=0.0;

   double lo=MathMin(zoneLo,zoneHi);
   double hi=MathMax(zoneLo,zoneHi);

   double tolerance=
      MathMax(_Point,
              MathMax(0.0,InpLimitZoneDuplicateTolerancePips)*StrategyPipSize());

   // Live LIMIT geometry may be moved just beyond the drawn READY edge to
   // satisfy the broker's stop/freeze distance. Treat that order as belonging
   // to the same READY zone so it cannot be duplicated on the next heartbeat.
   double liveExtension=0.0;
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      liveExtension=
         MathMax(0.0,InpLiveLimitGeometryExtensionPips)*StrategyPipSize();

   double acceptedLo=lo-liveExtension-tolerance;
   double acceptedHi=hi+liveExtension+tolerance;

   ENUM_ORDER_TYPE requiredType=
      direction==1 ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      ENUM_ORDER_TYPE type=(ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      if(type!=requiredType) continue;

      double price=OrderGetDouble(ORDER_PRICE_OPEN);
      if(price<acceptedLo || price>acceptedHi) continue;

      existingTicket=ticket;
      existingPrice=price;
      return true;
   }

   return false;
}

int CountOurPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      count++;
   }
   return count;
}

bool HasForeignPositionOnSymbol()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      ulong magic=(ulong)PositionGetInteger(POSITION_MAGIC);
      if(magic!=InpMagicNumber)
         return true;
   }
   return false;
}

void CancelOurPendingOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      if(!trade.OrderDelete(ticket))
         Log("Could not delete pending order "+(string)ticket+" : "+trade.ResultRetcodeDescription());
   }
}

void CloseOurPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      if(!RequestSynchronizedPositionClose(
            ticket,
            "CLOSE OUR POSITIONS",
            0.0,
            0.0,
            (ulong)MathMax(0,InpDeviationPoints)))
      {
         Log("Position close request failed "+(string)ticket);
      }
   }
}

//------------------------ Layer construction ------------------------
bool PrepareExecutionPrice(int direction,
                           double rawPrice,
                           double zoneLo,
                           double zoneHi,
                           int &immediateUsed,
                           int &kind,
                           double &execPrice)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double minDist=MathMax((double)stopsLevel*_Point,_Point);

   kind=-1;
   execPrice=0.0;

   if(!InpUseLimitStopLayers)
   {
      kind=LAYER_MARKET;
      execPrice=(direction==1)?tick.ask:tick.bid;
      execPrice=NormalizeDouble(execPrice,digits);
      immediateUsed++;
      return true;
   }

   if(direction==1)
   {
      if(rawPrice<=tick.ask-minDist)
      {
         kind=LAYER_LIMIT;
         execPrice=rawPrice;
      }
      else if(rawPrice>=tick.ask+minDist)
      {
         kind=LAYER_STOP;
         execPrice=rawPrice;
      }
      else if(immediateUsed<MathMax(0,InpMaxImmediateLayers))
      {
         kind=LAYER_MARKET;
         execPrice=tick.ask;
         immediateUsed++;
      }
      else
      {
         double lower=tick.ask-minDist;
         double upper=tick.ask+minDist;
         bool lowerOK=(lower>=zoneLo && lower<=zoneHi);
         bool upperOK=(upper>=zoneLo && upper<=zoneHi);

         if(lowerOK && upperOK)
         {
            if(MathAbs(rawPrice-lower)<=MathAbs(rawPrice-upper))
            {
               kind=LAYER_LIMIT; execPrice=lower;
            }
            else
            {
               kind=LAYER_STOP; execPrice=upper;
            }
         }
         else if(lowerOK)
         {
            kind=LAYER_LIMIT; execPrice=lower;
         }
         else if(upperOK)
         {
            kind=LAYER_STOP; execPrice=upper;
         }
         else
            return false;
      }
   }
   else
   {
      if(rawPrice>=tick.bid+minDist)
      {
         kind=LAYER_LIMIT;
         execPrice=rawPrice;
      }
      else if(rawPrice<=tick.bid-minDist)
      {
         kind=LAYER_STOP;
         execPrice=rawPrice;
      }
      else if(immediateUsed<MathMax(0,InpMaxImmediateLayers))
      {
         kind=LAYER_MARKET;
         execPrice=tick.bid;
         immediateUsed++;
      }
      else
      {
         double upper=tick.bid+minDist;
         double lower=tick.bid-minDist;
         bool upperOK=(upper>=zoneLo && upper<=zoneHi);
         bool lowerOK=(lower>=zoneLo && lower<=zoneHi);

         if(upperOK && lowerOK)
         {
            if(MathAbs(rawPrice-upper)<=MathAbs(rawPrice-lower))
            {
               kind=LAYER_LIMIT; execPrice=upper;
            }
            else
            {
               kind=LAYER_STOP; execPrice=lower;
            }
         }
         else if(upperOK)
         {
            kind=LAYER_LIMIT; execPrice=upper;
         }
         else if(lowerOK)
         {
            kind=LAYER_STOP; execPrice=lower;
         }
         else
            return false;
      }
   }

   execPrice=NormalizeDouble(execPrice,digits);
   return true;
}

bool DuplicatePendingPrice(LayerPlan &plans[],int upto,int kind,double price)
{
   if(kind==LAYER_MARKET) return false;

   for(int i=0;i<upto;i++)
   {
      if(plans[i].kind==LAYER_MARKET) continue;
      if(MathAbs(plans[i].execPrice-price)<=_Point)
         return true;
   }
   return false;
}

bool BuildLayerPlans(int direction,
                     double zoneLo,
                     double zoneHi,
                     double sl,
                     double riskBudget,
                     int requestedLayers,
                     LayerPlan &plans[])
{
   if(requestedLayers<1 || riskBudget<=0)
      return false;

   ArrayResize(plans,requestedLayers);

   int immediateUsed=0;
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double accountLayerCap=InpAutoScaleLayerLot ? AutoBaseLayerLot() : maxVol;

   if(accountLayerCap<=0)
      return false;

   double plannedRisk=0.0;

   for(int i=0;i<requestedLayers;i++)
   {
      double frac=(requestedLayers==1)?0.5:(double)i/(double)(requestedLayers-1);

      double raw=(direction==1)
                 ? zoneHi-(zoneHi-zoneLo)*frac
                 : zoneLo+(zoneHi-zoneLo)*frac;

      int kind=-1;
      double execPrice=0.0;

      if(!PrepareExecutionPrice(direction,raw,zoneLo,zoneHi,
                                immediateUsed,kind,execPrice))
         return false;

      if(DuplicatePendingPrice(plans,i,kind,execPrice))
         return false;

      if(direction==1 && sl>=execPrice) return false;
      if(direction==-1 && sl<=execPrice) return false;

      double loss=OneLotLoss(direction,execPrice,sl);
      if(loss<=0)
         return false;

      // Risk decides the actual volume. Account scaling is only the maximum
      // allowed per individual layer.
      double equalRisk=riskBudget/(double)requestedLayers;
      double riskSizedVolume=NormalizeVolumeDown(equalRisk/loss);
      double vol=NormalizeVolumeDown(MathMin(accountLayerCap,riskSizedVolume));

      if(vol<minVol-1e-12)
         return false;

      plans[i].rawPrice=raw;
      plans[i].execPrice=execPrice;
      plans[i].lossPerLot=loss;
      plans[i].kind=kind;
      plans[i].volume=vol;

      plannedRisk += vol*loss;

      if(plannedRisk>riskBudget+0.01)
         return false;
   }

   return true;
}

bool CreateBestLayerSet(int direction,
                        double zoneLo,
                        double zoneHi,
                        double sl,
                        double riskBudget,
                        LayerPlan &plans[])
{
   int minLayers=MathMax(1,InpMinLayers);
   int maxLayers=MathMax(minLayers,InpMaxLayers);

   for(int n=maxLayers;n>=minLayers;n--)
   {
      LayerPlan temp[];
      if(BuildLayerPlans(direction,zoneLo,zoneHi,sl,riskBudget,n,temp))
      {
         ArrayResize(plans,n);
         for(int i=0;i<n;i++) plans[i]=temp[i];
         return true;
      }
   }

   return false;
}


//-------------------- Persistent READY execution --------------------


double ConfidenceTakeProfitPips(int conf)
{
   // V3.081: take profit is disabled for every confidence class.
   return InpUseTakeProfit ? MathMax(0.1,InpFixedTakeProfitPips) : 0.0;
}

double FixedPipTPForSetup(int direction,
                          double entry,
                          int conf)
{
   if(!InpUseTakeProfit || entry<=0 || g_pipSize<=0)
      return 0.0;

   double distance=
      ConfidenceTakeProfitPips(conf)*g_pipSize;

   return RoundPrice(
      direction==1
      ? entry+distance
      : entry-distance);
}


double LayerRRForSetup(int layerIndex,int totalLayers,double runnerRR)
{
   runnerRR=MathMax(0.10,runnerRR);

   if(!InpUseStagedProfitTaking || totalLayers<=1)
      return runnerRR;

   if(layerIndex==1)
      return MathMax(0.10,InpLayer1TakeProfitR);

   if(totalLayers>=3 && layerIndex==2)
      return MathMax(0.10,InpLayer2TakeProfitR);

   return runnerRR;
}

bool ParsePersistentComment(string comment,long &setupId,int &layerIndex,int &totalLayers)
{
   setupId=0;
   layerIndex=0;
   totalLayers=0;

   if(StringFind(comment,"EZR")!=0)
      return false;

   int spacePos=StringFind(comment," ");
   if(spacePos<4)
      return false;

   setupId=(long)StringToInteger(StringSubstr(comment,3,spacePos-3));

   int lPos=StringFind(comment,"L",spacePos);
   int slashPos=(lPos>=0)?StringFind(comment,"/",lPos):-1;

   if(lPos>=0 && slashPos>lPos)
   {
      layerIndex=(int)StringToInteger(
         StringSubstr(comment,lPos+1,slashPos-lPos-1));

      totalLayers=(int)StringToInteger(
         StringSubstr(comment,slashPos+1));
   }

   return (setupId>0);
}

datetime CurrentM5OpenTime()
{
   return iTime(_Symbol,PERIOD_M5,0);
}

int AnalyticsIndex(long id)
{
   for(int i=0;i<ArraySize(g_setupAnalytics);i++)
      if(g_setupAnalytics[i].used && g_setupAnalytics[i].id==id)
         return i;

   return -1;
}

int EnsureAnalytics(long id)
{
   int idx=AnalyticsIndex(id);

   if(idx>=0)
      return idx;

   int n=ArraySize(g_setupAnalytics);
   ArrayResize(g_setupAnalytics,n+1);
   ZeroMemory(g_setupAnalytics[n]);

   g_setupAnalytics[n].used=true;
   g_setupAnalytics[n].id=id;

   return n;
}

void RegisterSetupAnalytics(PersistentReadySetup &setup)
{
   int idx=EnsureAnalytics(setup.id);

   g_setupAnalytics[idx].direction=setup.direction;
   g_setupAnalytics[idx].confidence=setup.confluences;
   g_setupAnalytics[idx].riskPct=setup.riskPct;
   g_setupAnalytics[idx].targetRR=setup.targetRR;
   g_setupAnalytics[idx].plannedLayers=setup.layersPlaced;
   g_setupAnalytics[idx].armedTime=setup.armedClock;
   g_setupAnalytics[idx].deployedTime=setup.deployedClock;

   // V2.0: freeze the quality attributes this setup was actually deployed on.
   g_setupAnalytics[idx].v2ZoneGrade      =setup.zoneGrade;
   g_setupAnalytics[idx].v2TouchNumber    =setup.zoneTouchNumber;
   g_setupAnalytics[idx].v2DepartureScore =setup.departureScore;
   g_setupAnalytics[idx].v2H1BiasAligned  =
      (H1BiasDirection()==0)
      ? 0
      : (IsCounterToH1Bias(setup.direction)?-1:1);
   g_setupAnalytics[idx].v2ActualStopPips =
      (g_pipSize>0.0 && setup.structuralSL>0.0)
      ? MathAbs(((setup.entryLo+setup.entryHi)*0.5)-setup.structuralSL)/g_pipSize
      : 0.0;

   // V2.1a S1/S2: freeze the confluence snapshot the gate produced for THIS
   // deployment. Both standard-path deployment functions call the gate and
   // then this, in the same call, so the snapshot is still the one the trade
   // was taken on.
   CaptureConfluenceSnapshot(idx);
}

long ResolveSetupIdFromSelectedHistory(long positionId,
                                       int &layerIndex,
                                       int &totalLayers)
{
   layerIndex=0;
   totalLayers=0;

   int total=HistoryDealsTotal();

   for(int i=0;i<total;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;

      if((long)HistoryDealGetInteger(ticket,DEAL_POSITION_ID)!=positionId)
         continue;

      long setupId=0;
      int li=0,tl=0;

      if(ParsePersistentComment(
            HistoryDealGetString(ticket,DEAL_COMMENT),
            setupId,li,tl))
      {
         layerIndex=li;
         totalLayers=tl;
         return setupId;
      }
   }

   return 0;
}

void RegisterDealAnalytics(ulong dealTicket)
{
   if(dealTicket==0 || dealTicket==g_lastAnalyticsDeal)
      return;

   g_lastAnalyticsDeal=dealTicket;

   if(!HistoryDealSelect(dealTicket))
      return;

   string symbol=HistoryDealGetString(dealTicket,DEAL_SYMBOL);
   ulong magic=(ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC);

   if(symbol!=_Symbol || magic!=InpMagicNumber)
      return;

   string comment=HistoryDealGetString(dealTicket,DEAL_COMMENT);
   long positionId=(long)HistoryDealGetInteger(dealTicket,DEAL_POSITION_ID);

   long setupId=0;
   int layerIndex=0,totalLayers=0;

   ParsePersistentComment(comment,setupId,layerIndex,totalLayers);

   double dealProfit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT);
   double dealCommission=HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
   double dealSwap=HistoryDealGetDouble(dealTicket,DEAL_SWAP);
   double dealFee=HistoryDealGetDouble(dealTicket,DEAL_FEE);
   double dealVolume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);

   ENUM_DEAL_ENTRY entry=
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);

   if(setupId<=0)
   {
      HistorySelect(g_reportFromTime>0?g_reportFromTime:0,TimeCurrent());
      setupId=ResolveSetupIdFromSelectedHistory(positionId,layerIndex,totalLayers);
   }

   if(setupId<=0)
      return;

   int idx=EnsureAnalytics(setupId);

   g_setupAnalytics[idx].realisedProfit+=
      dealProfit+dealCommission+dealSwap+dealFee;

   if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
      g_setupAnalytics[idx].actualEntryLots+=dealVolume;
}

void UpdateSetupPeakAnalytics(long setupId)
{
   int idx=AnalyticsIndex(setupId);
   if(idx<0)
      return;

   double floating=0.0;

   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      long id=0;
      int layerIndex=0,totalLayers=0;

      if(!ParsePersistentComment(
            PositionGetString(POSITION_COMMENT),
            id,layerIndex,totalLayers))
         continue;

      if(id!=setupId)
         continue;

      floating+=PositionGetDouble(POSITION_PROFIT)
               +PositionGetDouble(POSITION_SWAP);
   }

   double campaignProfit=
      g_setupAnalytics[idx].realisedProfit+floating;

   if(campaignProfit>g_setupAnalytics[idx].peakCampaignProfit)
      g_setupAnalytics[idx].peakCampaignProfit=campaignProfit;
}

int FindReportPositionMap(ReportPositionMap &maps[],long positionId)
{
   for(int i=0;i<ArraySize(maps);i++)
      if(maps[i].positionId==positionId)
         return i;

   return -1;
}

int FindReportSetupRow(ReportSetupRow &rows[],long id)
{
   for(int i=0;i<ArraySize(rows);i++)
      if(rows[i].id==id)
         return i;

   return -1;
}

int EnsureReportSetupRow(ReportSetupRow &rows[],long id)
{
   int idx=FindReportSetupRow(rows,id);

   if(idx>=0)
      return idx;

   int n=ArraySize(rows);
   ArrayResize(rows,n+1);
   ZeroMemory(rows[n]);
   rows[n].id=id;

   int a=AnalyticsIndex(id);

   if(a>=0)
   {
      rows[n].direction=g_setupAnalytics[a].direction;
      rows[n].confidence=g_setupAnalytics[a].confidence;
      rows[n].riskPct=g_setupAnalytics[a].riskPct;
      rows[n].targetRR=g_setupAnalytics[a].targetRR;
      rows[n].plannedLayers=g_setupAnalytics[a].plannedLayers;
      rows[n].peakCampaignProfit=g_setupAnalytics[a].peakCampaignProfit;
      rows[n].peakRunnerProfit=g_setupAnalytics[a].peakRunnerProfit;
      rows[n].peakLockCloses=g_setupAnalytics[a].peakLockCloses;
      rows[n].zoneGrade=g_setupAnalytics[a].v2ZoneGrade;
      rows[n].zoneTouchNumber=g_setupAnalytics[a].v2TouchNumber;
      rows[n].departureScore=g_setupAnalytics[a].v2DepartureScore;
      rows[n].h1BiasAligned=g_setupAnalytics[a].v2H1BiasAligned;
      rows[n].actualStopPips=g_setupAnalytics[a].v2ActualStopPips;
      rows[n].v21aSessionCode=g_setupAnalytics[a].v21aSessionCode;
      rows[n].v21aSessionScore=g_setupAnalytics[a].v21aSessionScore;
      rows[n].v21aVolPercentile=g_setupAnalytics[a].v21aVolPercentile;
      rows[n].v21aVolScore=g_setupAnalytics[a].v21aVolScore;
      rows[n].v21aTotalScore=g_setupAnalytics[a].v21aTotalScore;
      rows[n].v21aEntryPathCode=g_setupAnalytics[a].v21aEntryPathCode;
   }

   return n;
}

string DirectionText(int direction)
{
   if(direction==1) return "BUY";
   if(direction==-1) return "SELL";
   return "UNKNOWN";
}

void WriteEzyMapBacktestReport()
{
   if(g_reportWritten)
      return;

   g_reportWritten=true;

   datetime from=(g_reportFromTime>0)?g_reportFromTime:0;
   datetime to=TimeCurrent();

   if(!HistorySelect(from,to))
   {
      Log("REPORT: HistorySelect failed.");
      return;
   }

   ReportPositionMap maps[];
   ReportSetupRow rows[];

   int deals=HistoryDealsTotal();

   // Pass 1: exact entry volumes and map each position to setup/layer.
   for(int i=0;i<deals;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;

      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;

      ENUM_DEAL_ENTRY entry=
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);

      if(entry!=DEAL_ENTRY_IN && entry!=DEAL_ENTRY_INOUT)
         continue;

      long setupId=0;
      int layerIndex=0,totalLayers=0;

      // Attribution is by MAGIC NUMBER, not by comment. Previously any entry
      // deal whose comment did not parse as "EZR<id>..." was skipped outright,
      // so its volume AND its profit/loss vanished from this report while
      // still affecting the real account - which is why TOTAL ENTRY LOTS and
      // NET PROFIT never matched "lot traded"/the final balance. Order
      // comments are not a reliable key: brokers truncate and overwrite them,
      // and not every entry path tags them identically. Deals that cannot be
      // grouped into a setup now fall into the UNATTRIBUTED row (id 0) instead
      // of being dropped, so the totals always reconcile with the account.
      if(!ParsePersistentComment(
            HistoryDealGetString(ticket,DEAL_COMMENT),
            setupId,layerIndex,totalLayers))
      {
         setupId=0;
         layerIndex=0;
         totalLayers=0;
      }

      long positionId=(long)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);

      if(FindReportPositionMap(maps,positionId)<0)
      {
         int n=ArraySize(maps);
         ArrayResize(maps,n+1);
         maps[n].positionId=positionId;
         maps[n].setupId=setupId;
         maps[n].layerIndex=layerIndex;
         maps[n].totalLayers=totalLayers;
      }

      int r=EnsureReportSetupRow(rows,setupId);
      double vol=HistoryDealGetDouble(ticket,DEAL_VOLUME);

      rows[r].entryLots+=vol;
      rows[r].maxEntryDealLot=MathMax(rows[r].maxEntryDealLot,vol);
      rows[r].plannedLayers=MathMax(rows[r].plannedLayers,totalLayers);

      ENUM_DEAL_TYPE type=
         (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket,DEAL_TYPE);

      if(type==DEAL_TYPE_BUY) rows[r].direction=1;
      if(type==DEAL_TYPE_SELL) rows[r].direction=-1;
   }

   // Pass 2: full net P/L and TP statistics.
   for(int i=0;i<deals;i++)
   {
      ulong ticket=HistoryDealGetTicket(i);
      if(ticket==0) continue;

      if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=InpMagicNumber) continue;

      long positionId=(long)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);
      int m=FindReportPositionMap(maps,positionId);

      if(m<0)
         continue;

      int r=EnsureReportSetupRow(rows,maps[m].setupId);

      rows[r].netProfit+=
         HistoryDealGetDouble(ticket,DEAL_PROFIT)
        +HistoryDealGetDouble(ticket,DEAL_COMMISSION)
        +HistoryDealGetDouble(ticket,DEAL_SWAP)
        +HistoryDealGetDouble(ticket,DEAL_FEE);

      ENUM_DEAL_ENTRY entry=
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);

      ENUM_DEAL_REASON reason=
         (ENUM_DEAL_REASON)HistoryDealGetInteger(ticket,DEAL_REASON);

      bool closing=
         (entry==DEAL_ENTRY_OUT ||
          entry==DEAL_ENTRY_OUT_BY ||
          entry==DEAL_ENTRY_INOUT);

      if(closing && reason==DEAL_REASON_TP)
      {
         if(maps[m].layerIndex==1 && maps[m].totalLayers>1)
            rows[r].layer1TPHits++;
         else if(maps[m].layerIndex==2 && maps[m].totalLayers>=3)
            rows[r].layer2TPHits++;
         else
            rows[r].runnerTPHits++;
      }
   }

   double totalEntryLots=0.0;
   double maxSetupLots=0.0;
   double maxEntryDealLot=0.0;
   double totalNet=0.0;
   double captureSum=0.0;

   int captureCount=0;
   int wins=0,losses=0,flat=0;
   int l1Hits=0,l2Hits=0,runnerHits=0,peakLockCloses=0;

   for(int i=0;i<ArraySize(rows);i++)
   {
      int a=AnalyticsIndex(rows[i].id);

      if(a>=0)
      {
         rows[i].confidence=g_setupAnalytics[a].confidence;
         rows[i].riskPct=g_setupAnalytics[a].riskPct;
         rows[i].targetRR=g_setupAnalytics[a].targetRR;
         rows[i].peakCampaignProfit=g_setupAnalytics[a].peakCampaignProfit;
         rows[i].peakRunnerProfit=g_setupAnalytics[a].peakRunnerProfit;
         rows[i].peakLockCloses=g_setupAnalytics[a].peakLockCloses;
         rows[i].zoneGrade=g_setupAnalytics[a].v2ZoneGrade;
         rows[i].zoneTouchNumber=g_setupAnalytics[a].v2TouchNumber;
         rows[i].departureScore=g_setupAnalytics[a].v2DepartureScore;
         rows[i].h1BiasAligned=g_setupAnalytics[a].v2H1BiasAligned;
         rows[i].actualStopPips=g_setupAnalytics[a].v2ActualStopPips;
         rows[i].v21aSessionCode=g_setupAnalytics[a].v21aSessionCode;
         rows[i].v21aSessionScore=g_setupAnalytics[a].v21aSessionScore;
         rows[i].v21aVolPercentile=g_setupAnalytics[a].v21aVolPercentile;
         rows[i].v21aVolScore=g_setupAnalytics[a].v21aVolScore;
         rows[i].v21aTotalScore=g_setupAnalytics[a].v21aTotalScore;
         rows[i].v21aEntryPathCode=g_setupAnalytics[a].v21aEntryPathCode;
      }

      totalEntryLots+=rows[i].entryLots;
      maxSetupLots=MathMax(maxSetupLots,rows[i].entryLots);
      maxEntryDealLot=MathMax(maxEntryDealLot,rows[i].maxEntryDealLot);
      totalNet+=rows[i].netProfit;

      if(rows[i].netProfit>0.01) wins++;
      else if(rows[i].netProfit<-0.01) losses++;
      else flat++;

      if(rows[i].peakCampaignProfit>0.01)
      {
         captureSum+=
            (rows[i].netProfit/rows[i].peakCampaignProfit)*100.0;
         captureCount++;
      }

      l1Hits+=rows[i].layer1TPHits;
      l2Hits+=rows[i].layer2TPHits;
      runnerHits+=rows[i].runnerTPHits;
      peakLockCloses+=rows[i].peakLockCloses;
   }

   double avgLots=
      (ArraySize(rows)>0)?totalEntryLots/ArraySize(rows):0.0;

   double avgCapture=
      (captureCount>0)?captureSum/captureCount:0.0;

   Log("================ EZYMAP SCALP MASTERY V2.009 SUMMARY ================");
   Log("TOTAL SETUPS: "+IntegerToString(ArraySize(rows))+
       " | wins="+IntegerToString(wins)+
       " | losses="+IntegerToString(losses)+
       " | flat="+IntegerToString(flat));

   Log("TOTAL ENTRY LOTS: "+DoubleToString(totalEntryLots,VolumeDigits())+
       " | AVG LOT/SETUP: "+DoubleToString(avgLots,VolumeDigits()));

   Log("MAX SETUP LOTS: "+DoubleToString(maxSetupLots,VolumeDigits())+
       " | MAX ENTRY DEAL LOT: "+DoubleToString(maxEntryDealLot,VolumeDigits()));

   Log("NET PROFIT FROM REPORTED SETUPS: "+DoubleToString(totalNet,2)+
       " | AVG PROFIT CAPTURE: "+DoubleToString(avgCapture,1)+"%");

   int unattributed=FindReportSetupRow(rows,0);

   if(unattributed>=0)
      Log("UNATTRIBUTED (no parseable setup tag, counted in the totals above): "+
          "entry lots="+
          DoubleToString(rows[unattributed].entryLots,VolumeDigits())+
          " | net="+DoubleToString(rows[unattributed].netProfit,2)+
          " | these are magic-matched trades that could not be grouped into a"+
          " setup id; they are included so the totals reconcile.");

   Log("L1 TP HITS: "+IntegerToString(l1Hits)+
       " | L2 TP HITS: "+IntegerToString(l2Hits)+
       " | RUNNER TP HITS: "+IntegerToString(runnerHits)+
       " | PEAK-LOCK CLOSES: "+IntegerToString(peakLockCloses));

   // Self-check: this report groups by setup, ReportJournalPerformance()
   // reconstructs straight from broker history. They cover the same deals, so
   // any difference means attribution is losing trades again - surface it here
   // instead of letting the two figures silently disagree.
   JournalPerformanceSnapshot reconcile;

   if(BuildJournalPerformanceSnapshot(reconcile))
   {
      double lotsDelta=totalEntryLots-reconcile.lotsTraded;
      double netDelta=totalNet-reconcile.closedNetPnl;
      bool matches=(MathAbs(lotsDelta)<=0.005 &&
                    MathAbs(netDelta)<=0.01);

      Log("RECONCILIATION vs BROKER HISTORY: "+
          string(matches?"OK":"MISMATCH")+
          " | report lots="+DoubleToString(totalEntryLots,VolumeDigits())+
          " vs history lots="+DoubleToString(reconcile.lotsTraded,VolumeDigits())+
          " (delta "+DoubleToString(lotsDelta,VolumeDigits())+")"+
          " | report net="+DoubleToString(totalNet,2)+
          " vs history closed net="+DoubleToString(reconcile.closedNetPnl,2)+
          " (delta "+DoubleToString(netDelta,2)+")"+
          " | history total trades="+IntegerToString(reconcile.totalTrades)+
          " | still-open trades at report time="+
          IntegerToString(reconcile.openTrades));

      if(reconcile.openTrades>0)
         Log("RECONCILIATION NOTE: "+IntegerToString(reconcile.openTrades)+
             " position(s) were still open when this report was written."+
             " Their floating P/L is not part of either net figure, so the"+
             " account balance change will differ by that amount.");
   }

   Log("============================================================");

   if(!InpWriteCSVReport)
      return;

   MqlDateTime dt;
   TimeToStruct(to,dt);

   string filename=
      StringFormat("%s_%s_%04d%02d%02d_%02d%02d.csv",
                   InpCSVReportPrefix,
                   _Symbol,
                   dt.year,dt.mon,dt.day,dt.hour,dt.min);

   int handle=
      FileOpen(filename,
               FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,
               ',');

   if(handle==INVALID_HANDLE)
   {
      Log("REPORT: could not create CSV. Error="+
          IntegerToString(GetLastError()));
      return;
   }

   FileWrite(handle,
             "SetupID",
             "Direction",
             "Confidence",
             "RiskPct",
             "TargetRR",
             "Layers",
             "EntryLots",
             "MaxEntryDealLot",
             "NetProfit",
             "PeakCampaignProfit",
             "ProfitCapturePct",
             "PeakRunnerProfit",
             "Layer1TPHits",
             "Layer2TPHits",
             "RunnerTPHits",
             "PeakLockCloses",
             "ZoneGrade",
             "TouchNumber",
             "DepartureScore",
             "H1BiasAligned",
             "ActualStopPips",
             "SessionTag",
             "SessionScore",
             "VolPercentile",
             "VolScore",
             "ConfluenceScore",
             "EntryPath");

   for(int i=0;i<ArraySize(rows);i++)
   {
      double capture=
         (rows[i].peakCampaignProfit>0.01)
         ? rows[i].netProfit/rows[i].peakCampaignProfit*100.0
         : 0.0;

      FileWrite(handle,
                rows[i].id==0?"UNATTRIBUTED":(string)rows[i].id,
                DirectionText(rows[i].direction),
                rows[i].confidence,
                DoubleToString(rows[i].riskPct,2),
                DoubleToString(rows[i].targetRR,2),
                rows[i].plannedLayers,
                DoubleToString(rows[i].entryLots,VolumeDigits()),
                DoubleToString(rows[i].maxEntryDealLot,VolumeDigits()),
                DoubleToString(rows[i].netProfit,2),
                DoubleToString(rows[i].peakCampaignProfit,2),
                DoubleToString(capture,1),
                DoubleToString(rows[i].peakRunnerProfit,2),
                rows[i].layer1TPHits,
                rows[i].layer2TPHits,
                rows[i].runnerTPHits,
                rows[i].peakLockCloses,
                ZoneGradeText(rows[i].zoneGrade),
                rows[i].zoneTouchNumber,
                (rows[i].departureScore>=0.0
                 ? DoubleToString(rows[i].departureScore,3)
                 : "n/a"),
                (rows[i].h1BiasAligned==1?"ALIGNED":
                 (rows[i].h1BiasAligned==-1?"COUNTER":"NEUTRAL")),
                DoubleToString(rows[i].actualStopPips,1),
                // V2.1a: "n/a" wherever the source was not scored for this
                // setup, so a legitimately-unscored row can never be read as
                // a zero score.
                SessionCodeText(rows[i].v21aSessionCode),
                (rows[i].v21aSessionScore>=0.0
                 ? DoubleToString(rows[i].v21aSessionScore,3)
                 : "n/a"),
                (rows[i].v21aVolPercentile>=0.0
                 ? DoubleToString(rows[i].v21aVolPercentile,1)
                 : "n/a"),
                (rows[i].v21aVolScore>=0.0
                 ? DoubleToString(rows[i].v21aVolScore,3)
                 : "n/a"),
                (rows[i].v21aTotalScore>=0.0
                 ? DoubleToString(rows[i].v21aTotalScore,3)
                 : "n/a"),
                EntryPathCodeText(rows[i].v21aEntryPathCode));
   }

   FileWrite(handle,"");
   FileWrite(handle,"SUMMARY","Value");
   FileWrite(handle,"TotalSetups",ArraySize(rows));
   FileWrite(handle,"WinningSetups",wins);
   FileWrite(handle,"LosingSetups",losses);
   FileWrite(handle,"TotalEntryLots",DoubleToString(totalEntryLots,VolumeDigits()));
   FileWrite(handle,"AverageLotsPerSetup",DoubleToString(avgLots,VolumeDigits()));
   FileWrite(handle,"MaxSetupLots",DoubleToString(maxSetupLots,VolumeDigits()));
   FileWrite(handle,"MaxEntryDealLot",DoubleToString(maxEntryDealLot,VolumeDigits()));
   FileWrite(handle,"NetProfit",DoubleToString(totalNet,2));
   FileWrite(handle,"AverageProfitCapturePct",DoubleToString(avgCapture,1));
   FileWrite(handle,"Layer1TPHits",l1Hits);
   FileWrite(handle,"Layer2TPHits",l2Hits);
   FileWrite(handle,"RunnerTPHits",runnerHits);
   FileWrite(handle,"PeakLockCloses",peakLockCloses);

   FileFlush(handle);
   FileClose(handle);

   string reportPath=
      TerminalInfoString(TERMINAL_COMMONDATA_PATH)+
      "\\Files\\"+filename;

   Log("CSV REPORT SAVED: "+reportPath);
}

string PersistentTag(long id)
{
   return "EZR"+(string)id;
}

int FindPersistentSetup(long id)
{
   for(int i=0;i<ArraySize(g_persistentSetups);i++)
      if(g_persistentSetups[i].active && g_persistentSetups[i].id==id)
         return i;
   return -1;
}

bool HasUntriggeredPersistentReady(int direction)
{
   return (CountWaitingReadyDirection(direction)>0);
}

int CountWaitingReadyDirection(int direction)
{
   int count=0;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active)
         continue;

      if(g_persistentSetups[i].direction!=direction)
         continue;

      if(g_persistentSetups[i].deployed ||
         g_persistentSetups[i].triggered)
         continue;

      count++;
   }

   return count;
}

int CountTotalWaitingReady()
{
   int count=0;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active)
         continue;

      if(g_persistentSetups[i].deployed ||
         g_persistentSetups[i].triggered)
         continue;

      count++;
   }

   return count;
}

bool PersistentCommentMatches(string comment,long id)
{
   string tag=PersistentTag(id);
   return (StringFind(comment,tag)==0);
}

int CountPersistentOrders(long id)
{
   int count=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      string comment=OrderGetString(ORDER_COMMENT);
      if(PersistentCommentMatches(comment,id))
         count++;
   }

   return count;
}

int CountPersistentPositions(long id)
{
   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      if(PersistentCommentMatches(comment,id))
         count++;
   }

   return count;
}

void CancelPersistentOrders(long id)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      string comment=OrderGetString(ORDER_COMMENT);
      if(!PersistentCommentMatches(comment,id))
         continue;

      if(!trade.OrderDelete(ticket))
         Log("Could not cancel persistent order "+(string)ticket+
             " : "+trade.ResultRetcodeDescription());
   }
}

int PersistentClosedBars(datetime armedBarTime)
{
   if(armedBarTime<=0)
      return 0;

   int shift=iBarShift(_Symbol,g_entryTF,armedBarTime,false);
   if(shift<0)
      return 0;

   return shift;
}

double PersistentFallbackSL(ReadySnapshot &r,int direction)
{
   double stopPips=(g_mode=="SCALP")
                   ? InpScalpStopPips
                   : ((g_mode=="INTRADAY")?InpIntradayStopPips:InpSwingStopPips);

   double fallback=MathMax(stopPips*g_pipSize,g_pipSize*10.0);

   if(direction==1)
      return RoundPrice(r.entryLo-fallback);

   return RoundPrice(r.entryHi+fallback);
}

double LayerTPForSetup(int direction,double entry,double sl,double rr)
{
   rr=MathMax(0.10,rr);
   if(direction==1)
   {
      double risk=entry-sl;
      if(risk<=0) return 0.0;
      return RoundPrice(entry+risk*rr);
   }

   double risk=sl-entry;
   if(risk<=0) return 0.0;
   return RoundPrice(entry-risk*rr);
}

bool SubmitPersistentLayerOrder(PersistentReadySetup &setup,
                                LayerPlan &p,
                                string comment,
                                double brokerSL,
                                double tp)
{
   if(setup.direction==1)
   {
      if(p.kind==LAYER_MARKET)
         return trade.Buy(p.volume,_Symbol,0.0,brokerSL,tp,comment);
      if(p.kind==LAYER_LIMIT)
         return trade.BuyLimit(p.volume,p.execPrice,_Symbol,brokerSL,tp,ORDER_TIME_GTC,0,comment);
      if(p.kind==LAYER_STOP)
         return trade.BuyStop(p.volume,p.execPrice,_Symbol,brokerSL,tp,ORDER_TIME_GTC,0,comment);
   }
   else
   {
      if(p.kind==LAYER_MARKET)
         return trade.Sell(p.volume,_Symbol,0.0,brokerSL,tp,comment);
      if(p.kind==LAYER_LIMIT)
         return trade.SellLimit(p.volume,p.execPrice,_Symbol,brokerSL,tp,ORDER_TIME_GTC,0,comment);
      if(p.kind==LAYER_STOP)
         return trade.SellStop(p.volume,p.execPrice,_Symbol,brokerSL,tp,ORDER_TIME_GTC,0,comment);
   }
   return false;
}

bool PlacePersistentLayer(PersistentReadySetup &setup,
                          LayerPlan &p,
                          int layerIndex,
                          int totalLayers)
{
   // Spread filter (previously only wired into the unused legacy execution
   // path). Blocks new submissions during spread spikes/news on the symbol's
   // real current quote, independent of order kind.
   if(!SpreadAllowed())
   {
      g_spreadRejectStd++;    // V2.2 BTC S06 instrumentation
      Log("SPREAD FILTER BLOCK | signal="+(string)setup.id+
          " | current spread exceeds "+EffectiveSpreadCapText());
      SetDeploymentFailure("spread filter: current spread exceeds "+EffectiveSpreadCapText(),
                           0,"","",true);
      return false;
   }

   // Recheck immediately before submission. Another READY setup or timer pass
   // may have staged a LIMIT after this layer plan was built.
   if(p.kind==LAYER_LIMIT && InpOneLimitPerReadyZone)
   {
      ulong existingTicket=0;
      double existingPrice=0.0;
      if(ExistingEALimitInReadyZone(setup.direction,
                                    setup.entryLo,
                                    setup.entryHi,
                                    existingTicket,
                                    existingPrice))
      {
         Log("LIMIT SUBMISSION SKIPPED | signal="+(string)setup.id+
             " | READY zone already covered by ticket="+
             (string)existingTicket+
             " @ "+DoubleToString(existingPrice,_Digits));
         return false;
      }
   }

   string plannedKindText=(p.kind==LAYER_MARKET)?"MARKET":(p.kind==LAYER_LIMIT?"LIMIT":"STOP");

   if(!DailyRiskCapacityAvailable(
         plannedKindText+" signal="+(string)setup.id))
   {
      g_capacityRejectStd++;  // V2.2 BTC S06 instrumentation
      SetDeploymentFailure(
         "daily risk lock: "+g_dayLockReason,
         0,"","",false);
      return false;
   }

   if(!M5ClosedLossCapacityAvailable(
         plannedKindText+" signal="+(string)setup.id))
   {
      SetDeploymentFailure(
         "maximum losing closing deals reached for current M5",
         0,
         "",
         "",
         false);
      return false;
   }

   if(!DirectionalLosingPositionCapacityAvailable(
         setup.direction,
         plannedKindText+" signal="+(string)setup.id))
   {
      SetDeploymentFailure(
         "maximum currently losing positions reached for direction",
         0,
         "",
         "",
         false);
      return false;
   }

   if(!DirectionalLayerSlotAvailable(
         setup.direction,
         plannedKindText+" signal="+(string)setup.id))
   {
      SetDeploymentFailure(
         "directional position/pending layer cap reached",
         0,
         "",
         "",
         false);
      return false;
   }

   string comment=PersistentTag(setup.id)+
                  " L"+IntegerToString(layerIndex+1)+
                  "/"+IntegerToString(totalLayers);

   if(setup.zeroConfluenceFallback)
      comment+=" ZC";

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      SetDeploymentFailure(
         "current symbol tick unavailable",
         0,
         "",
         "",
         true);
      return false;
   }

   double estimatedEntry=p.execPrice;
   if(p.kind==LAYER_MARKET || estimatedEntry<=0.0)
      estimatedEntry=(setup.direction==1)?tick.ask:tick.bid;

   double requestedTP=InpUseTakeProfit
                      ? FixedPipTPForSetup(setup.direction,estimatedEntry,setup.confluences)
                      : 0.0;
   double tp=InpUseTakeProfit
             ? BrokerSafeExecutionTP(setup.direction,estimatedEntry,requestedTP)
             : 0.0;
   // V3.190 S3: resolved stop distance, so an ATR-derived stop is the one
   // actually submitted (and the one sizing is computed against).
   double exactDistance=ProtectionPriceDistance(ResolvedPresetStopPips());
   double exactSL=RoundProtectionStop(
      setup.direction,
      setup.direction==1 ? estimatedEntry-exactDistance
                         : estimatedEntry+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(setup.direction,estimatedEntry,exactSL);

   g_orderSendStd++;          // V2.2 BTC S06 instrumentation
   bool ok=SubmitPersistentLayerOrder(setup,p,comment,brokerSL,tp);
   uint retcode=trade.ResultRetcode();
   bool accepted=(ok && TradeRetcodeAccepted(retcode));
   bool openedWithoutSL=false;

   if(!accepted &&
      InpRetryEntryWithoutSLOnReject &&
      RetryWithoutSLRetcode(retcode))
   {
      Log("PRESET SL OPEN RETRY | signal="+(string)setup.id+
          " | requestedSL="+DoubleToString(brokerSL,_Digits)+
          " | first retcode="+IntegerToString((int)retcode)+
          " | description="+trade.ResultRetcodeDescription()+
          " | broker comment="+trade.ResultComment());

      ok=SubmitPersistentLayerOrder(setup,p,comment,0.0,tp);
      retcode=trade.ResultRetcode();
      accepted=(ok && TradeRetcodeAccepted(retcode));
      openedWithoutSL=accepted;
   }

   string kindText=plannedKindText;
   if(accepted)
   {
      Log("PERSISTENT "+kindText+
          " | signal="+(string)setup.id+
          " | layer "+IntegerToString(layerIndex+1)+"/"+IntegerToString(totalLayers)+
          " | requested price="+DoubleToString(estimatedEntry,_Digits)+
          " | brokerPrice="+DoubleToString(trade.ResultPrice(),_Digits)+
          " | exact virtual SL="+DoubleToString(exactSL,_Digits)+
          " | broker SL="+string(openedWithoutSL?"POST-FILL INSTALL":DoubleToString(brokerSL,_Digits))+
          " | TP="+string(InpUseTakeProfit?DoubleToString(tp,_Digits):"NONE")+
          " | confidence="+ConfidenceClassText(setup.confluences)+
          " | volume="+DoubleToString(p.volume,VolumeDigits())+
          " | retcode="+IntegerToString((int)retcode));
   }
   else
   {
      string rejectDescription=trade.ResultRetcodeDescription();
      string rejectComment=trade.ResultComment();
      bool temporary=TemporaryTradeRetcode(retcode);

      SetDeploymentFailure(
         kindText+" order rejected by broker/tester",
         retcode,
         rejectDescription,
         rejectComment,
         temporary);

      Log("Persistent "+kindText+" layer rejected | signal="+
          (string)setup.id+
          " | temporary="+string(temporary?"YES":"NO")+
          " | retcode="+IntegerToString((int)retcode)+
          " | description="+rejectDescription+
          " | bid="+DoubleToString(trade.ResultBid(),_Digits)+
          " | ask="+DoubleToString(trade.ResultAsk(),_Digits)+
          " | broker comment="+rejectComment);
   }

   return accepted;
}

void SupersedeWaitingZones(int direction,long incomingId)
{
   if(!InpLatestZoneOnly) return;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active) continue;
      if(g_persistentSetups[i].id==incomingId) continue;
      if(g_persistentSetups[i].direction!=direction) continue;

      if(CountPersistentPositions(g_persistentSetups[i].id)>0)
         continue;

      CancelPersistentOrders(g_persistentSetups[i].id);
      DeletePersistentObjects(g_persistentSetups[i].id);
      g_persistentSetups[i].active=false;
   }
}

void CloseAllEzyExposure()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      trade.OrderDelete(ticket);
   }

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      RequestSynchronizedPositionClose(
         ticket,
         "CLOSE ALL EZY EXPOSURE",
         0.0,
         0.0,
         (ulong)MathMax(0,InpDeviationPoints));
   }

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(g_persistentSetups[i].active)
      {
         DeletePersistentObjects(g_persistentSetups[i].id);
         g_persistentSetups[i].active=false;
      }
   }
}

void CancelAllPendingAtDailyRiskLock()
{
   if(!InpCancelPendingAtDailyLossStop)
      return;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);

      if(ticket==0)
         continue;

      if(OrderGetString(ORDER_SYMBOL)!=_Symbol)
         continue;

      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber)
         continue;

      ENUM_ORDER_TYPE type=
         (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

      int direction=0;
      if(!PendingOrderDirection(type,direction))
         continue;

      double price=OrderGetDouble(ORDER_PRICE_OPEN);

      if(trade.OrderDelete(ticket))
      {
         Log("DAILY RISK LIMIT PENDING CANCEL"+
             " | ticket="+(string)ticket+
             " | direction="+
             string(direction==1?"BUY":"SELL")+
             " | price="+DoubleToString(price,_Digits));
      }
      else
      {
         Log("DAILY RISK LIMIT PENDING CANCEL FAILED"+
             " | ticket="+(string)ticket+
             " | "+trade.ResultRetcodeDescription());
      }
   }
}


bool DailyRiskCapacityAvailable(string context)
{
   CheckCampaignDay();

   if(!g_dayTradingLocked)
      return true;

   Log("ENTRY BLOCKED BY DAILY RISK LIMIT"+
       " | context="+context+
       " | reason="+g_dayLockReason+
       " | start equity="+DoubleToString(g_dayStartEquity,2)+
       " | current equity="+
       DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
       " | floor="+DoubleToString(g_dayLossFloor,2));

   return false;
}


void ResetCampaignDay(bool forceReset)
{
   datetime brokerNow=TimeTradeServer();
   if(brokerNow<=0)
      brokerNow=TimeCurrent();

   MqlDateTime dt;
   TimeToStruct(brokerNow,dt);
   int key=dt.year*10000+dt.mon*100+dt.day;

   if(!forceReset && key==g_dailyDateKey) return;

   g_dailyDateKey=key;
   g_dailyLayerOrders=0;
   g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_dayTargetEquity=g_dayStartEquity*(1.0+MathMax(0.0,InpDailyEquityTargetPct)/100.0);
   double lossPct=MathMax(0.0,MathMin(95.0,InpDailyLossStopPct));
   g_dayLossFloor=g_dayStartEquity*(1.0-lossPct/100.0);
   g_dayTradingLocked=false;
   g_dayLockReason="";
   g_campaignDirection=0;
   g_campaignSetups=0;

   Log("V3.176 BROKER-DAY RISK RESET"+
       " | date="+IntegerToString(g_dailyDateKey)+
       " | start equity="+DoubleToString(g_dayStartEquity,2)+
       " | daily risk="+DoubleToString(InpDailyLossStopPct,1)+"%"+
       " | lock floor="+DoubleToString(g_dayLossFloor,2)+
       " | account profile="+
       string(g_accountUnitDivisor>1.0?"CENT":"STANDARD"));
}

void CheckCampaignDay()
{
   ResetCampaignDay(false);
   if(g_dayTradingLocked) return;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpDailyEquityTargetPct>0 && equity>=g_dayTargetEquity)
   {
      g_dayTradingLocked=true;
      g_dayLockReason="DAILY TARGET REACHED";
      if(InpCloseAllAtDailyTarget) CloseAllEzyExposure();
      Log("CAMPAIGN REST: DAILY TARGET REACHED | equity="+DoubleToString(equity,2));
      return;
   }

   if(InpDailyLossStopPct>0 && equity<=g_dayLossFloor)
   {
      g_dayTradingLocked=true;
      g_dayLockReason=
         "DAILY RISK "+
         DoubleToString(InpDailyLossStopPct,1)+
         "% REACHED";

      // Prevent a latched forced zero-confluence retry from carrying through
      // the daily lock. A fresh touch may arm again after the next broker day.
      g_directZeroConf.active=false;

      if(InpCloseAllAtDailyLossStop)
         CloseAllEzyExposure();
      else
         CancelAllPendingAtDailyRiskLock();

      Log("V3.176 DAILY RISK LOCK"+
          " | risk="+DoubleToString(InpDailyLossStopPct,1)+"%"+
          " | start equity="+DoubleToString(g_dayStartEquity,2)+
          " | current equity="+DoubleToString(equity,2)+
          " | floor="+DoubleToString(g_dayLossFloor,2)+
          " | close positions="+
          string(InpCloseAllAtDailyLossStop?"YES":"NO")+
          " | cancel pending="+
          string(InpCancelPendingAtDailyLossStop?"YES":"NO")+
          " | reset=next broker day");
   }
}

string ConfidenceClassText(int conf)
{
   if(conf>=InpQualityConfidenceMin)
      return "QUALITY";

   if(conf>=InpGoodConfidenceMin)
      return "GOOD";

   return "STANDARD";
}

// S10: conf is intentionally unused now - see the comment below on why lot
// size no longer scales by confidence tier. Signature kept unchanged so
// every existing call site (which all pass a real confluence count) needs
// no edits.
double ConfidenceSetupLot(int conf)
{
   double effectiveEquity=EffectiveAccountEquity();
   double sizingCapital=LotSizingCapitalUnits();

   if(effectiveEquity<MinimumTradingEquity())
      return 0.0;

   // S10 (both files): per-tier LOT scaling removed at the user's explicit
   // request - this used to select InpGoodSetupLotPer100/InpQualitySetupLot-
   // Per100 (2x/3x InpStandardSetupLotPer100) here, making a "Good" or
   // "Quality" setup's TOTAL lot bigger while DesiredLayersForSetup() ALSO
   // gave it more layers to split that bigger total across - the two systems
   // were stacking (more layers of a bigger pie), and if a limit layer
   // failed to place, BuildAggressiveArmPlans's route-shrink logic dumped
   // the entire un-split total onto whatever routes remained, which is what
   // produced an observed live BTC trade at 2x the normal single-layer lot.
   // Every layer now requests this SAME flat, untiered lot - confidence is
   // expressed ONLY through DesiredLayersForSetup()'s layer COUNT (1 for
   // Standard, 2 for Good, 3 for Quality), never through a bigger per-layer
   // size. InpGoodSetupLotPer100/InpQualitySetupLotPer100 are kept as inputs
   // only for .set-file compatibility; neither is read here anymore.
   double lotPer100=InpStandardSetupLotPer100;

   // REAL-CENT BROKER-NATIVE RULE:
   // Calculate the proportional target first. On a live cent account only,
   // a target below the symbol minimum may nominate the broker minimum as a
   // candidate; the cent risk/margin validator still has final authority.
   double baseEquity=MathMax(1.0,InpBaseEquity);
   double scale=sizingCapital/baseEquity;
   double targetLot=lotPer100*scale;
   double normalized=NormalizeVolumeDown(targetLot);
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(normalized<minVol-1e-12)
   {
      bool liveCentCandidate=
         IsLiveCentAccount() &&
         InpLiveCentBrokerMinimumExecution &&
         InpAllowCentMinimumLotFallback &&
         AccountInfoDouble(ACCOUNT_BALANCE)>=
            MathMax(0.0,InpLiveCentRawBalanceFloor);

      if(liveCentCandidate)
      {
         Log("LIVE CENT MINIMUM-LOT CANDIDATE | raw balance="+
             DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),2)+" "+
             AccountInfoString(ACCOUNT_CURRENCY)+
             " | economic USD-equivalent="+DoubleToString(effectiveEquity,2)+
             " | broker-native sizing capital="+DoubleToString(sizingCapital,2)+
             " | proportional target="+DoubleToString(targetLot,4)+
             " | broker candidate="+DoubleToString(minVol,VolumeDigits())+
             " | awaiting broker-native risk/margin validation");

         // Return the broker minimum as a CANDIDATE only.
         // CapSetupVolumeForCentSafety() still decides whether it is safe.
         return NormalizeDouble(minVol,VolumeDigits());
      }

      Log("REAL CENT SIZE BLOCK | raw equity="+
          DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+" "+
          AccountInfoString(ACCOUNT_CURRENCY)+
          " | economic USD-equivalent="+DoubleToString(effectiveEquity,2)+
          " | broker-native sizing capital="+DoubleToString(sizingCapital,2)+
          " | proportional target="+DoubleToString(targetLot,4)+
          " | broker minimum="+DoubleToString(minVol,VolumeDigits())+
          " | live minimum-lot profile="+
          string(InpLiveCentBrokerMinimumExecution?"ON":"OFF"));
      return 0.0;
   }

   return normalized;
}


double RiskPctForSetup(int conf,double entryLo,double entryHi,double sl)
{
   double pct=(conf>=5)?InpRiskPct_5Plus:((conf==4)?InpRiskPct_4Conf:InpRiskPct_3Conf);
   double mid=(entryLo+entryHi)/2.0;
   double slPips=(g_pipSize>0)?MathAbs(mid-sl)/g_pipSize:0.0;
   double ratio=slPips/MathMax(1.0,InpScalpStopPips);

   if(ratio<=InpTightSLRatio) pct+=InpRiskTightSLBonusPct;
   else if(ratio>=InpWideSLRatio) pct-=InpRiskWideSLPenaltyPct;

   return Clamp(pct,1.0,InpMaxRiskPct);
}

int DesiredLayersForSetup(int conf,double entryLo,double entryHi,double sl)
{
   // V3.190 S5: the trigger deploys only the initial allocation. Everything
   // beyond it has to be earned by a green move, gated in ScaleInAllowed().
   if(InpScaleInOnConfirmation)
      return MathMax(1,MathMin(InpInitialLayerCount,InpMaxLayers));

   // Predictable confidence ladder:
   // STANDARD -> 1 layer
   // GOOD     -> 2 layers
   // QUALITY  -> 3 layers
   //
   // The total setup lot is split across these layers.
   if(conf>=InpQualityConfidenceMin)
      return MathMin(3,InpMaxLayers);

   if(conf>=InpGoodConfidenceMin)
      return MathMin(2,InpMaxLayers);

   return 1;
}

double TargetRRForSetup(double riskPct)
{
   // V2.009G quick-win final target.
   // Sub-1R continuation targets are deliberately permitted.
   return Clamp(InpLiveRR,
                MathMax(0.20,InpContinuationMinRR),
                MathMax(InpContinuationMinRR,
                        InpContinuationMaxRR));
}

bool QueuePersistentSetup(ReadySnapshot &r,int direction)
{
   if(!r.armed)
      return false;

   if(InpAllowParallelWaitingReady)
   {
      int dirWaiting=CountWaitingReadyDirection(direction);
      int allWaiting=CountTotalWaitingReady();

      if(dirWaiting>=MathMax(1,InpMaxWaitingReadyPerDirection))
      {
         Log("PARALLEL READY CAP | "+
             string(direction==1?"BUY":"SELL")+
             " waiting="+IntegerToString(dirWaiting));
         return false;
      }

      if(allWaiting>=MathMax(1,InpMaxTotalWaitingReady))
      {
         Log("TOTAL WAITING READY CAP | waiting="+
             IntegerToString(allWaiting));
         return false;
      }
   }

   if(ArraySize(g_persistentSetups)>=MathMax(1,InpMaxPersistentSetups))
   {
      bool reusable=false;

      for(int k=0;k<ArraySize(g_persistentSetups);k++)
      {
         if(!g_persistentSetups[k].active)
         {
            reusable=true;
            break;
         }
      }

      if(!reusable)
      {
         Log("Persistent setup queue full. READY not stored.");
         return false;
      }
   }

   long id=(long)r.armedClock*10+(direction==1?1:2);

   if(FindPersistentSetup(id)>=0)
      return false;

   SupersedeWaitingZones(direction,id);

   int slot=-1;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active)
      {
         slot=i;
         break;
      }
   }

   if(slot<0)
   {
      slot=ArraySize(g_persistentSetups);
      ArrayResize(g_persistentSetups,slot+1);
   }

   ZeroMemory(g_persistentSetups[slot]);

   g_persistentSetups[slot].active=true;
   g_persistentSetups[slot].deployed=false;
   g_persistentSetups[slot].triggered=false;
   g_persistentSetups[slot].expiryHandled=false;

   g_persistentSetups[slot].id=id;
   g_persistentSetups[slot].direction=direction;
   g_persistentSetups[slot].counterTrend=r.counterTrend;
   g_persistentSetups[slot].confluences=r.confluences;
   g_persistentSetups[slot].requiredConfluences=r.requiredConfluences;
   g_persistentSetups[slot].zeroConfluenceFallback=
      (r.requiredConfluences==0);

   g_persistentSetups[slot].zeroConfluenceLevelPrice=
      direction==1 ? g_S1 : g_R1;

   g_persistentSetups[slot].zeroConfluenceOuterLevelPrice=
      direction==1 ? g_S2 : g_R2;

   BuildCurrentZeroConfTriggerMap(
      direction,
      g_persistentSetups[slot].zeroConfTriggerMap);

   g_persistentSetups[slot].zeroConfTriggerMap.readyValid=
      r.entryHi>r.entryLo;
   g_persistentSetups[slot].zeroConfTriggerMap.readyLo=r.entryLo;
   g_persistentSetups[slot].zeroConfTriggerMap.readyHi=r.entryHi;

   g_persistentSetups[slot].zeroConfTriggerCode=
      EZY_ZC_TRIGGER_NONE;
   g_persistentSetups[slot].zeroConfTriggerPriority=999;
   g_persistentSetups[slot].zeroConfTriggerLo=0.0;
   g_persistentSetups[slot].zeroConfTriggerHi=0.0;
   g_persistentSetups[slot].zeroConfReclaimTime=0;

   g_persistentSetups[slot].zoneRetests=r.zoneRetests;

   g_persistentSetups[slot].supportLo=r.supportLo;
   g_persistentSetups[slot].supportHi=r.supportHi;
   g_persistentSetups[slot].entryLo=r.entryLo;
   g_persistentSetups[slot].entryHi=r.entryHi;

   g_persistentSetups[slot].entryTime=r.entryTime;
   g_persistentSetups[slot].armedClock=r.armedClock;
   g_persistentSetups[slot].armedBarTime=r.armedBarTime;
   g_persistentSetups[slot].deployedClock=0;
   g_persistentSetups[slot].zoneExited=false;
   g_persistentSetups[slot].riskPct=0.0;
   g_persistentSetups[slot].targetRR=InpLiveRR;
   g_persistentSetups[slot].touchLatched=false;
   g_persistentSetups[slot].highRiskTouchLatched=false;
   g_persistentSetups[slot].s1r1TouchLatched=false;
   g_persistentSetups[slot].s2r2TouchLatched=false;
   g_persistentSetups[slot].hasPreviousTouchCMP=false;
   g_persistentSetups[slot].previousTouchCMP=0.0;
   g_persistentSetups[slot].touchClock=0;
   g_persistentSetups[slot].touchPrice=0.0;
   g_persistentSetups[slot].deployAttempts=0;
   g_persistentSetups[slot].zoneTouchNumber=0;
   // V2.0 S3: scored ONCE here, at zone formation, and frozen with the setup
   // so it cannot drift as the M15 map refreshes underneath it.
   g_persistentSetups[slot].departureScore=
      ComputeDepartureScore(r.supportLo,r.supportHi,r.entryTime,direction);
   g_persistentSetups[slot].zoneGrade=0;
   g_persistentSetups[slot].lastDeployAttemptClock=0;
   g_persistentSetups[slot].lastDeployAttemptTickMs=0;
   g_persistentSetups[slot].deploymentBlockedM5=0;

   double sl=r.planSL;

   if(direction==1 && (sl<=0 || sl>=r.entryLo))
      sl=PersistentFallbackSL(r,direction);

   if(direction==-1 && (sl<=r.entryHi))
      sl=PersistentFallbackSL(r,direction);

   g_persistentSetups[slot].structuralSL=NormalizeDouble(sl,_Digits);

   g_persistentQueuedCount++;

   Log("SOURCE READY STORED | signal="+(string)id+
       " | V2.0 departure score="+
       (g_persistentSetups[slot].departureScore>=0.0
        ? DoubleToString(g_persistentSetups[slot].departureScore,2)
        : "n/a")+
       " | "+string(direction==1?"BUY":"SELL")+
       " | conf="+IntegerToString(r.confluences)+
       " | required="+IntegerToString(r.requiredConfluences)+
       " | zero-conf fallback="+
       string(g_persistentSetups[slot].zeroConfluenceFallback?"YES":"NO")+
       " | frozen "+string(direction==1?"S1":"R1")+"="+
       DoubleToString(
          g_persistentSetups[slot].zeroConfluenceLevelPrice,
          _Digits)+
       " | frozen "+string(direction==1?"S2":"R2")+"="+
       DoubleToString(
          g_persistentSetups[slot].zeroConfluenceOuterLevelPrice,
          _Digits)+
       " | open EA positions="+IntegerToString(CountOurPositions())+
       " | counter="+string(r.counterTrend?"YES":"NO")+
       " | lifetime="+IntegerToString(InpReadyExpiryBars)+
       " closed "+g_tfLabel+" bars");

   // Normal confluence-qualified V3.081 setups keep immediate-on-arm routing.
   // Zero-confluence fallback setups are touch-only by explicit V3.102 rule.
   if(InpAggressiveArmExecution &&
      !g_persistentSetups[slot].zeroConfluenceFallback)
   {
      Log("READY ARMED -> INSTANT MARKET + CONFIDENCE LIMITS | signal="+
          (string)id);

      bool deployedNow=
         DeployAggressiveArmSetup(slot);

      if(!deployedNow)
      {
         // Keep a short retry latch for a transient market/server rejection.
         g_persistentSetups[slot].touchLatched=true;
         g_persistentSetups[slot].touchClock=TimeCurrent();
         g_persistentSetups[slot].touchPrice=
            (direction==1)
            ? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
            : SymbolInfoDouble(_Symbol,SYMBOL_BID);
         g_persistentSetups[slot].deployAttempts=0;

         Log("AGGRESSIVE ARM RETRY LATCHED | signal="+
             (string)id);
      }
   }
   else if(g_persistentSetups[slot].zeroConfluenceFallback)
   {
      Log("V3.170 ZERO-CONFLUENCE WAITING | signal="+
          (string)id+
          " | priority=W1 cluster/W1/D1-H4 cluster/D1/LOW-RISK/READY/H4/current"+
          " | low-risk trigger="+
          string(V3170_ZERO_CONF_LOW_RISK_TOUCH_RULE?"ON":"OFF")+
          " | M5 sweep+reclaim="+
          string(InpZeroConfRequireM5SweepReclaim?"REQUIRED":"OFF")+
          " | tolerance="+
          DoubleToString(InpZeroConfTouchTolerancePips,1)+" pips"+
          " | cluster tolerance="+
          DoubleToString(InpZeroConfClusterTolerancePips,1)+" pips"+
          " | open EA positions="+
          IntegerToString(CountOurPositions())+
          " | trigger allowed only while positions <= "+
          IntegerToString(V3104_ZERO_CONF_MAX_OPEN_POSITIONS));
   }

   return true;
}


void ResetDailyFrequencyCounter()
{
   ResetCampaignDay(false);
}

bool PersistentPriceNearZone(PersistentReadySetup &setup)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;

   double px=(setup.direction==1)?tick.ask:tick.bid;
   double tol=MathMax(0.0,InpDeploymentApproachPips)*g_pipSize;
   return (px>=setup.entryLo-tol && px<=setup.entryHi+tol);
}

bool PersistentM5ZoneValid(PersistentReadySetup &setup)
{
   if(!InpRequireM5ZoneStillValid)
      return true;

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double buffer=MathMax(g_pipSize*5.0,_Point*2.0);

   if(setup.direction==1)
      return (tick.bid>=setup.supportLo-buffer);

   return (tick.ask<=setup.supportHi+buffer);
}

bool M1QualitySignals(int direction,
                      double zoneLo,
                      double zoneHi,
                      double wickRatio,
                      bool &rejection,
                      bool &microBreak,
                      bool &momentum)
{
   rejection=false;
   microBreak=false;
   momentum=false;

   MqlRates r[];
   ArraySetAsSeries(r,true);

   int lookback=MathMax(2,MathMin(6,InpM1QualityLookback));
   int need=MathMax(8,lookback+5);

   if(CopyRates(_Symbol,PERIOD_M1,0,need,r)<need)
      return false;

   double strength=MathMax(0.50,MathMin(0.90,InpQualityCloseStrength));

   if(direction==1)
      microBreak=(r[1].close>r[2].high && r[1].close>r[1].open);
   else
      microBreak=(r[1].close<r[2].low && r[1].close<r[1].open);

   double avgBody=0.0;
   int count=0;

   for(int i=2;i<=MathMin(7,need-1);i++)
   {
      avgBody+=MathAbs(r[i].close-r[i].open);
      count++;
   }

   if(count>0)
      avgBody/=count;

   double body1=MathAbs(r[1].close-r[1].open);
   double range1=r[1].high-r[1].low;

   bool directional=(direction==1)
                    ? (r[1].close>r[1].open)
                    : (r[1].close<r[1].open);

   bool strongMomentumClose=false;

   if(range1>_Point)
   {
      if(direction==1)
         strongMomentumClose=(r[1].close>=r[1].low+range1*strength);
      else
         strongMomentumClose=(r[1].close<=r[1].high-range1*strength);
   }

   momentum=(directional &&
             strongMomentumClose &&
             avgBody>0 &&
             body1>=avgBody*MathMax(0.80,InpMomentumBodyFactor));

   for(int i=1;i<=lookback;i++)
   {
      double range=r[i].high-r[i].low;

      if(range<=_Point)
         continue;

      bool touches=(r[i].low<=zoneHi && r[i].high>=zoneLo);

      if(!touches)
         continue;

      double body=MathAbs(r[i].close-r[i].open);
      double safeBody=MathMax(body,_Point);

      if(direction==1)
      {
         double lowerWick=MathMin(r[i].open,r[i].close)-r[i].low;
         bool bullish=(r[i].close>r[i].open);
         bool strongClose=(r[i].close>=r[i].low+range*strength);

         if(bullish &&
            lowerWick>=safeBody*wickRatio &&
            strongClose)
         {
            rejection=true;
            break;
         }
      }
      else
      {
         double upperWick=r[i].high-MathMax(r[i].open,r[i].close);
         bool bearish=(r[i].close<r[i].open);
         bool strongClose=(r[i].close<=r[i].high-range*strength);

         if(bearish &&
            upperWick>=safeBody*wickRatio &&
            strongClose)
         {
            rejection=true;
            break;
         }
      }
   }

   return true;
}


// V3.190 S4: evaluate touch confirmation for one latched setup.
// Returns true when the setup may deploy. Sets outcome to a short reason so
// the caller can log why, and in particular so timeout fallbacks are
// countable in the journal.
//
// zoneLo/zoneHi are the zone the touch happened against (the READY rectangle,
// or the resolved zero-confluence trigger band).
bool TouchConfirmationSatisfied(PersistentReadySetup &setup,
                                int direction,
                                double zoneLo,
                                double zoneHi,
                                double cmp,
                                string &outcome)
{
   outcome="";

   if(!InpRequireTouchConfirmation)
   {
      outcome="confirmation disabled";
      return true;
   }

   if(setup.confirmSatisfied)
   {
      outcome="already confirmed";
      return true;
   }

   ulong now=NowMs();
   double pip=MathMax(StrategyPipSize(),_Point);

   // First pass after the touch latched: seed the state.
   if(!setup.confirmPending)
   {
      setup.confirmPending=true;
      setup.confirmStartMs=now;
      setup.confirmStallSinceMs=now;
      setup.confirmExtreme=cmp;
      setup.confirmTouchPrice=cmp;
      setup.confirmTouchM1Bar=iTime(_Symbol,PERIOD_M1,0);

      Log("V3.190 S4 CONFIRMATION PENDING | signal="+(string)setup.id+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | touch="+DoubleToString(cmp,_Digits)+
          " | zone="+DoubleToString(zoneLo,_Digits)+".."+
          DoubleToString(zoneHi,_Digits)+
          " | mode="+IntegerToString(InpTouchConfirmMode)+
          " | timeout="+IntegerToString(InpTouchConfirmTimeoutSec)+"s");
   }

   // Track the adverse extreme since the touch. For a BUY at support the
   // adverse direction is down, for a SELL at resistance it is up.
   bool extended=false;
   double extendTolerance=MathMax(0.0,InpTouchStallMaxExtendPips)*pip;

   if(direction==1)
   {
      if(cmp<setup.confirmExtreme-extendTolerance)
      {
         setup.confirmExtreme=cmp;
         extended=true;
      }
      else if(cmp<setup.confirmExtreme)
         setup.confirmExtreme=cmp;
   }
   else
   {
      if(cmp>setup.confirmExtreme+extendTolerance)
      {
         setup.confirmExtreme=cmp;
         extended=true;
      }
      else if(cmp>setup.confirmExtreme)
         setup.confirmExtreme=cmp;
   }

   if(extended)
      setup.confirmStallSinceMs=now;

   bool allowM1   =(InpTouchConfirmMode==0 || InpTouchConfirmMode==1);
   bool allowStall=(InpTouchConfirmMode==0 || InpTouchConfirmMode==2);

   // (a) an M1 bar has CLOSED back inside the zone since the touch.
   if(allowM1)
   {
      datetime currentM1=iTime(_Symbol,PERIOD_M1,0);

      if(currentM1>0 && currentM1>setup.confirmTouchM1Bar)
      {
         double closedM1=iClose(_Symbol,PERIOD_M1,1);
         double lo=MathMin(zoneLo,zoneHi);
         double hi=MathMax(zoneLo,zoneHi);

         if(closedM1>0.0 && closedM1>=lo && closedM1<=hi)
         {
            setup.confirmSatisfied=true;
            outcome="M1 close back inside zone @"+DoubleToString(closedM1,_Digits);

            Log("V3.190 S4 CONFIRMED | signal="+(string)setup.id+
                " | via=M1 CLOSE INSIDE"+
                " | close="+DoubleToString(closedM1,_Digits)+
                " | waited="+IntegerToString((int)((now-setup.confirmStartMs)/1000))+"s");
            return true;
         }
      }
   }

   // (b) price has stopped extending beyond the touch extreme.
   if(allowStall)
   {
      ulong stallMs=(ulong)MathMax(0,InpTouchStallSeconds)*1000;

      if(now>=setup.confirmStallSinceMs &&
         now-setup.confirmStallSinceMs>=stallMs)
      {
         setup.confirmSatisfied=true;
         outcome="stalled "+IntegerToString((int)(stallMs/1000))+"s beyond extreme";

         Log("V3.190 S4 CONFIRMED | signal="+(string)setup.id+
             " | via=STALL"+
             " | extreme="+DoubleToString(setup.confirmExtreme,_Digits)+
             " | extension from touch="+
             DoubleToString(MathAbs(setup.confirmExtreme-setup.confirmTouchPrice)/pip,1)+" pips"+
             " | waited="+IntegerToString((int)((now-setup.confirmStartMs)/1000))+"s");
         return true;
      }
   }

   // Timeout: deploy anyway. Frequency must not drop, so a confirmation that
   // never arrives falls back to V3.176 fill-at-market rather than skipping
   // the setup. Logged so the miss rate can be measured.
   ulong timeoutMs=(ulong)MathMax(0,InpTouchConfirmTimeoutSec)*1000;

   if(timeoutMs>0 && now>=setup.confirmStartMs &&
      now-setup.confirmStartMs>=timeoutMs)
   {
      setup.confirmSatisfied=true;
      outcome="TIMEOUT FALLBACK";

      Log("V3.190 S4 TIMEOUT FALLBACK | signal="+(string)setup.id+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | no confirmation in "+IntegerToString(InpTouchConfirmTimeoutSec)+"s"+
          " | deploying at market (V3.176 behaviour)"+
          " | touch="+DoubleToString(setup.confirmTouchPrice,_Digits)+
          " | extreme="+DoubleToString(setup.confirmExtreme,_Digits)+
          " | adverse excursion="+
          DoubleToString(MathAbs(setup.confirmExtreme-setup.confirmTouchPrice)/pip,1)+" pips");
      return true;
   }

   outcome="waiting";
   return false;
}


bool PersistentQualityPass(PersistentReadySetup &setup,string &reason)
{
   reason="";

   if(!DailyRiskCapacityAvailable(
         "PERSISTENT QUALITY signal="+(string)setup.id))
   {
      g_capacityRejectStd++;  // V2.2 BTC S06 instrumentation
      reason=g_dayLockReason;
      return false;
   }

   if(V3104_FORCE_ZERO_CONF_MARKET_EXECUTION &&
      setup.zeroConfluenceFallback &&
      setup.requiredConfluences==0)
   {
      Log("ZERO-CONFLUENCE FORCE PASS | signal="+(string)setup.id+
          " | touch quality recheck=BYPASSED"+
          " | current position-count recheck=BYPASSED"+
          " | retry until MARKET accepted=YES");
      return true;
   }

   int normalRequired=setup.counterTrend
                      ? COUNTER_MIN_CONFLUENCES
                      : TREND_MIN_CONFLUENCES;
   if(setup.confluences>=normalRequired)
      return true;

   reason="stored setup does not meet normal confluence requirement";
   return false;
}

bool BuildConfidenceLayerPlans(int direction,
                               double zoneLo,
                               double zoneHi,
                               double sl,
                               double targetSetupLot,
                               double riskBudget,
                               int requestedLayers,
                               LayerPlan &plans[])
{
   if(requestedLayers<1 ||
      targetSetupLot<=0 ||
      riskBudget<=0)
      return false;

   ArrayResize(plans,requestedLayers);

   int immediateUsed=0;
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(minVol<=0)
      return false;

   double plannedRisk=0.0;

   for(int i=0;i<requestedLayers;i++)
   {
      double frac=(requestedLayers==1)
                  ? 0.5
                  : (double)i/(double)(requestedLayers-1);

      double raw=(direction==1)
                 ? zoneHi-(zoneHi-zoneLo)*frac
                 : zoneLo+(zoneHi-zoneLo)*frac;

      int kind=-1;
      double execPrice=0.0;

      if(!PrepareExecutionPrice(direction,
                                raw,
                                zoneLo,
                                zoneHi,
                                immediateUsed,
                                kind,
                                execPrice))
         return false;

      if(DuplicatePendingPrice(plans,i,kind,execPrice))
         return false;

      if(direction==1 && sl>=execPrice)
         return false;

      if(direction==-1 && sl<=execPrice)
         return false;

      double lossPerLot=OneLotLoss(direction,execPrice,sl);

      if(lossPerLot<=0)
         return false;

      // S10: every layer requests the SAME flat targetSetupLot - no more
      // dividing one total across requestedLayers, which is what let a
      // "Good"/"Quality" setup's already-larger tiered total get sliced
      // into layers instead of adding real, separate, standard-sized
      // layers. riskBudget remains a genuine AGGREGATE ceiling across all
      // layers placed so far (not divided up-front either), so a layer is
      // still shrunk or refused once the setup's cumulative risk would
      // exceed it - it just no longer pre-shrinks every layer to fit a
      // fixed total that no longer exists.
      double riskRemaining=MathMax(0.0,riskBudget-plannedRisk);
      double maxByRisk=NormalizeVolumeDown(riskRemaining/lossPerLot);

      double vol=
         NormalizeVolumeDown(MathMin(targetSetupLot,maxByRisk));

      if(vol<minVol-1e-12)
         return false;

      plans[i].rawPrice=raw;
      plans[i].execPrice=execPrice;
      plans[i].lossPerLot=lossPerLot;
      plans[i].kind=kind;
      plans[i].volume=vol;

      plannedRisk+=vol*lossPerLot;

      if(plannedRisk>riskBudget+0.01)
         return false;
   }

   return true;
}

bool CreateConfidenceLayerSet(int direction,
                              double zoneLo,
                              double zoneHi,
                              double sl,
                              double targetSetupLot,
                              double riskBudget,
                              int desiredLayers,
                              LayerPlan &plans[])
{
   int maxLayers=MathMax(1,MathMin(desiredLayers,InpMaxLayers));

   // If broker volume step or risk makes the preferred layer count impossible,
   // reduce layer count rather than discard an otherwise valid M5 setup.
   for(int n=maxLayers;n>=1;n--)
   {
      LayerPlan temp[];

      if(BuildConfidenceLayerPlans(direction,
                                   zoneLo,
                                   zoneHi,
                                   sl,
                                   targetSetupLot,
                                   riskBudget,
                                   n,
                                   temp))
      {
         ArrayResize(plans,n);

         for(int i=0;i<n;i++)
            plans[i]=temp[i];

         return true;
      }
   }

   return false;
}


bool CreateBestLayerSetDynamic(int direction,
                               double zoneLo,
                               double zoneHi,
                               double sl,
                               double riskBudget,
                               int desiredMax,
                               LayerPlan &plans[])
{
   int maxLayers=MathMax(1,MathMin(desiredMax,InpMaxLayers));

   for(int n=maxLayers;n>=1;n--)
   {
      LayerPlan temp[];
      if(BuildLayerPlans(direction,zoneLo,zoneHi,sl,riskBudget,n,temp))
      {
         ArrayResize(plans,n);
         for(int i=0;i<n;i++) plans[i]=temp[i];
         return true;
      }
   }
   return false;
}




bool AddAggressiveLimitCandidate(PersistentReadySetup &setup,
                                 MqlTick &tick,
                                 double minDist,
                                 double depthPct,
                                 LayerPlan &plans[])
{
   int direction=setup.direction;
   double zoneLo=MathMin(setup.entryLo,setup.entryHi);
   double zoneHi=MathMax(setup.entryLo,setup.entryHi);
   double width=MathMax(0.0,zoneHi-zoneLo);

   if(width<=_Point)
      return false;

   if(InpOneLimitPerReadyZone)
   {
      // A LIMIT already planned in this build means this READY zone is
      // already covered, even before the order reaches the trade server.
      for(int i=0;i<ArraySize(plans);i++)
      {
         if(plans[i].kind==LAYER_LIMIT)
         {
            Log("LIMIT DUPLICATE SKIP | signal="+(string)setup.id+
                " | READY zone already has a planned LIMIT route");
            return false;
         }
      }

      ulong existingTicket=0;
      double existingPrice=0.0;
      if(ExistingEALimitInReadyZone(direction,
                                    zoneLo,
                                    zoneHi,
                                    existingTicket,
                                    existingPrice))
      {
         Log("LIMIT DUPLICATE SKIP | signal="+(string)setup.id+
             " | existing ticket="+(string)existingTicket+
             " | price="+DoubleToString(existingPrice,_Digits)+
             " | READY="+DoubleToString(zoneLo,_Digits)+
             ".."+DoubleToString(zoneHi,_Digits));
         return false;
      }
   }

   double depth=
      MathMax(0.0,MathMin(100.0,depthPct))/100.0;

   double limitPrice=0.0;

   if(direction==1)
   {
      // BUY LIMIT: deeper toward the lower READY edge.
      limitPrice=zoneLo+width*depth;
      limitPrice=MathMin(limitPrice,tick.ask-minDist);
      limitPrice=MathMax(limitPrice,setup.structuralSL+minDist);
   }
   else
   {
      // SELL LIMIT: deeper toward the upper READY edge.
      limitPrice=zoneHi-width*depth;
      limitPrice=MathMax(limitPrice,tick.bid+minDist);
      limitPrice=MathMin(limitPrice,setup.structuralSL-minDist);
   }

   limitPrice=RoundPrice(limitPrice);

   double liveExtension=0.0;
   if(!(bool)MQLInfoInteger(MQL_TESTER))
      liveExtension=MathMax(minDist,
                            MathMax(0.0,InpLiveLimitGeometryExtensionPips)*StrategyPipSize());

   bool insideZone=
      (limitPrice>=zoneLo-liveExtension-_Point &&
       limitPrice<=zoneHi+liveExtension+_Point);

   bool correctSide=
      direction==1
      ? (limitPrice<=tick.ask-minDist &&
         limitPrice>setup.structuralSL)
      : (limitPrice>=tick.bid+minDist &&
         limitPrice<setup.structuralSL);

   if(!insideZone || !correctSide)
   {
      Log("LIMIT GEOMETRY REJECT | signal="+(string)setup.id+
          " | side="+string(direction==1?"BUY":"SELL")+
          " | candidate="+DoubleToString(limitPrice,_Digits)+
          " | zone="+DoubleToString(zoneLo,_Digits)+".."+DoubleToString(zoneHi,_Digits)+
          " | live extension="+DoubleToString(liveExtension/_Point,0)+" points"+
          " | broker minimum distance="+DoubleToString(minDist/_Point,0)+" points");
      return false;
   }

   // Avoid duplicate LIMIT prices when the broker-valid zone is narrow.
   for(int i=0;i<ArraySize(plans);i++)
      if(MathAbs(plans[i].execPrice-limitPrice)<=_Point)
         return false;

   double lossPerLot=
      OneLotLoss(direction,limitPrice,setup.structuralSL);

   if(lossPerLot<=0)
      return false;

   int n=ArraySize(plans);
   ArrayResize(plans,n+1);

   plans[n].rawPrice=limitPrice;
   plans[n].execPrice=limitPrice;
   plans[n].volume=0.0; // assigned after valid route count is known
   plans[n].kind=LAYER_LIMIT;
   plans[n].lossPerLot=lossPerLot;

   return true;
}

bool BuildAggressiveArmPlans(PersistentReadySetup &setup,
                             LayerPlan &plans[])
{
   ArrayResize(plans,0);

   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
   {
      SetDeploymentFailure(
         "aggressive plan cannot read current symbol tick",
         0,"","",true);
      return false;
   }

   double targetSetupLot=
      ConfidenceSetupLot(setup.confluences);

   double minVol=
      SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(targetSetupLot<=0 ||
      minVol<=0 ||
      targetSetupLot<minVol-1e-12)
   {
      string reason=
         "confidence setup lot below broker minimum: calculated="+
         DoubleToString(targetSetupLot,VolumeDigits())+
         " minimum="+DoubleToString(minVol,VolumeDigits())+
         " confidence="+IntegerToString(setup.confluences);

      Log("AGGRESSIVE ARM LOT BLOCK | effective USD-equivalent="+
          DoubleToString(EffectiveAccountEquity(),2)+
          " | "+reason);

      SetDeploymentFailure(reason,0,"","",false);
      return false;
   }

   int desiredLayers=
      DesiredLayersForSetup(setup.confluences,
                            setup.entryLo,
                            setup.entryHi,
                            setup.structuralSL);

   desiredLayers=
      MathMax(1,MathMin(3,desiredLayers));

   long stopsLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);

   long freezeLevel=
      SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double minDist=
      MathMax(_Point,
              ((double)MathMax(stopsLevel,freezeLevel)+
               MathMax(0,InpExecutionStopCushionPoints))*_Point);

   int direction=setup.direction;
   double marketPrice=(direction==1)?tick.ask:tick.bid;

   setup.structuralSL=
      BrokerSafeExecutionSL(direction,
                            marketPrice,
                            setup.structuralSL);

   if(direction==1 && setup.structuralSL>=marketPrice)
   {
      SetDeploymentFailure(
         "BUY structural SL is not below MARKET entry price",
         0,"","",false);
      return false;
   }

   if(direction==-1 && setup.structuralSL<=marketPrice)
   {
      SetDeploymentFailure(
         "SELL structural SL is not above MARKET entry price",
         0,"","",false);
      return false;
   }

   // V2.0 S2/S4: publish this setup's quality so the sizing choke point can
   // see it, then clear so no later unrelated call inherits it.
   SetQualityContext(direction,
                     setup.zoneTouchNumber,
                     setup.departureScore,
                     setup.zoneGrade);
   SetDistalContext(direction,marketPrice,setup.entryLo,setup.entryHi);

   targetSetupLot=
      CapSetupVolumeForCentSafety(direction,
                                  marketPrice,
                                  setup.structuralSL,
                                  targetSetupLot);

   ClearQualityContext();

   if(targetSetupLot<minVol-1e-12)
   {
      SetDeploymentFailure(
         "cent-safety normalization reduced setup lot below broker minimum",
         0,"","",false);
      return false;
   }

   // Route 1 is always immediate MARKET.
   ArrayResize(plans,1);
   plans[0].rawPrice=marketPrice;
   plans[0].execPrice=marketPrice;
   plans[0].volume=0.0;
   plans[0].kind=LAYER_MARKET;
   plans[0].lossPerLot=
      OneLotLoss(direction,marketPrice,setup.structuralSL);

   if(plans[0].lossPerLot<=0)
   {
      SetDeploymentFailure(
         "MARKET layer loss-per-lot calculation is invalid",
         0,"","",false);
      return false;
   }

   // Good may add one LIMIT. Quality may add two distinct LIMIT levels.
   if(InpAggressivePlaceLimitRoute && desiredLayers>=2)
   {
      double firstDepth=
         MathMax(5.0,
                 MathMin(45.0,InpAggressiveLimitDepthPct));

      AddAggressiveLimitCandidate(
         setup,tick,minDist,firstDepth,plans);
   }

   if(InpAggressivePlaceLimitRoute && desiredLayers>=3)
   {
      double secondDepth=
         MathMax(55.0,
                 MathMin(95.0,
                         100.0-InpAggressiveLimitDepthPct));

      AddAggressiveLimitCandidate(
         setup,tick,minDist,secondDepth,plans);
   }

   // S10: every route - the MARKET route and each LIMIT route - now
   // requests the SAME flat targetSetupLot instead of splitting one total
   // across however many routes ended up valid. This is precisely the fix
   // for the bug this stage exists to remove: previously, if a LIMIT route
   // failed to attach (a common outcome - price too close, a duplicate zone,
   // a broker distance rule), the shrink-loop below reduced "available"
   // WITHOUT reducing targetSetupLot, so the entire un-split total (already
   // 2x/3x the standard lot from the old confidence-tiered ConfidenceSetupLot())
   // fell onto whatever routes remained - observed live as a single MARKET
   // order at double the normal size. targetSetupLot is already the flat,
   // untiered per-layer lot (see ConfidenceSetupLot()) and was already
   // verified above to be >= the broker minimum, so no shrink-loop or
   // remainder split is needed at all: a route that cannot open still just
   // does not open, at no cost to the routes that do.
   int available=ArraySize(plans);

   if(available<=0)
      return false;

   for(int i=0;i<available;i++)
      plans[i].volume=targetSetupLot;

   double assigned=0.0;

   for(int i=0;i<available;i++)
      assigned+=plans[i].volume;

   Log("CONFIDENCE ARM PLAN | signal="+
       (string)setup.id+
       " | "+ConfidenceClassText(setup.confluences)+
       " | target lots="+
       DoubleToString(targetSetupLot,VolumeDigits())+
       " | valid routes="+
       IntegerToString(available)+
       " | assigned="+
       DoubleToString(assigned,VolumeDigits()));

   return true;
}

bool BuildForcedZeroConfluenceMarketPlan(PersistentReadySetup &setup,LayerPlan &plan)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      SetDeploymentFailure("forced zero-confluence MARKET cannot read current tick",
                           0,"","",true);
      return false;
   }

   int direction=setup.direction;
   double marketPrice=(direction==1)?tick.ask:tick.bid;
   // V3.190 S3: resolved stop distance, so an ATR-derived stop is the one
   // actually submitted (and the one sizing is computed against).
   double exactDistance=ProtectionPriceDistance(ResolvedPresetStopPips());

   setup.structuralSL=RoundProtectionStop(
      direction,
      direction==1 ? marketPrice-exactDistance : marketPrice+exactDistance);
   setup.structuralSL=BrokerSafeExecutionSL(direction,marketPrice,setup.structuralSL);

   double requested=ConfidenceSetupLot(0);

   SetQualityContext(direction,
                     setup.zoneTouchNumber,
                     setup.departureScore,
                     setup.zoneGrade);
   SetDistalContext(direction,marketPrice,setup.entryLo,setup.entryHi);

   double volume=CapSetupVolumeForCentSafety(direction,marketPrice,
                                             setup.structuralSL,requested);

   ClearQualityContext();
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(volume<minVolume-1e-12)
   {
      SetDeploymentFailure("forced zero-confluence STANDARD lot below broker/safety minimum",
                           0,"","",false);
      return false;
   }

   plan.rawPrice=marketPrice;
   plan.execPrice=marketPrice;
   plan.volume=volume;
   plan.kind=LAYER_MARKET;
   plan.lossPerLot=OneLotLoss(direction,marketPrice,setup.structuralSL);

   if(plan.lossPerLot<=0.0)
   {
      SetDeploymentFailure("forced zero-confluence MARKET loss-per-lot calculation failed",
                           0,"","",false);
      return false;
   }
   return true;
}



bool CreateMarketFallbackLayerSet(int direction,
                                  double targetSetupLot,
                                  int requestedLayers,
                                  double sl,
                                  LayerPlan &plans[])
{
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(minVol<=0 || targetSetupLot<minVol-1e-12)
      return false;

   int layers=MathMax(1,MathMin(requestedLayers,InpMaxLayers));

   // S10: every fallback layer requests the SAME flat targetSetupLot, same
   // reasoning as BuildAggressiveArmPlans - targetSetupLot is already the
   // flat, untiered per-layer lot and already verified >= broker minimum
   // above, so no split-to-fit-a-total logic is needed here at all.
   ArrayResize(plans,layers);

   double marketPrice=(direction==1)?tick.ask:tick.bid;

   for(int i=0;i<layers;i++)
   {
      plans[i].rawPrice=marketPrice;
      plans[i].execPrice=marketPrice;
      plans[i].volume=targetSetupLot;
      plans[i].kind=LAYER_MARKET;
      plans[i].lossPerLot=OneLotLoss(direction,marketPrice,sl);

      if(plans[i].lossPerLot<=0)
         return false;
   }

   return true;
}



bool DeployAggressiveArmSetup(int index)
{
   if(index<0 || index>=ArraySize(g_persistentSetups))
   {
      SetDeploymentFailure(
         "persistent setup index is invalid",
         0,"","",false);
      return false;
   }

   if(!g_persistentSetups[index].active ||
      g_persistentSetups[index].deployed)
   {
      SetDeploymentFailure(
         "persistent setup is inactive or already deployed",
         0,"","",false);
      return false;
   }

   // V2.1a S1/S2: STANDARD-path confluence gate.
   //
   // This function is entered BOTH directly (from the READY-armed instant
   // route) and by delegation from DeployPersistentSetup(). The gate lives
   // here rather than in the caller so the direct route is covered too, and
   // DeployPersistentSetup() only evaluates the gate on the branch that does
   // NOT delegate here - so exactly one gate evaluation happens per standard
   // deployment attempt and the counters cannot double-count.
   if(!ConfluenceGateAllows(
         V21A_PATH_STANDARD,
         "route=AGGRESSIVE-ARM signal="+
         (string)g_persistentSetups[index].id+
         " direction="+
         string(g_persistentSetups[index].direction==1?"BUY":"SELL")))
   {
      SetDeploymentFailure(
         "V2.1a confluence score below InpMinConfluenceScore",
         0,"","",true);
      return false;
   }

   bool zeroConf=g_persistentSetups[index].zeroConfluenceFallback;
   bool forceZeroConf=zeroConf && V3104_FORCE_ZERO_CONF_MARKET_EXECUTION;

   if(!DailyRiskCapacityAvailable(
         "AGGRESSIVE ARM signal="+
         (string)g_persistentSetups[index].id+
         " zero-conf="+string(forceZeroConf?"YES":"NO")))
   {
      g_capacityRejectStd++;  // V2.2 BTC S06 instrumentation
      SetDeploymentFailure(
         "daily risk lock: "+g_dayLockReason,
         0,"","",false);
      return false;
   }

   if(!forceZeroConf && g_campaignSetups>=InpMaxCampaignSetupsPerDay)
   {
      SetDeploymentFailure("maximum campaign setups per day reached",
                           0,"","",false);
      return false;
   }

   if(!forceZeroConf &&
      IsLiveCentAccount() &&
      InpLiveCentParityMode &&
      InpLiveCentMaximumOpenPositions>0 &&
      CountOurPositions()>=InpLiveCentMaximumOpenPositions)
   {
      string reason=
         "live-cent open-position cap reached: "+
         IntegerToString(InpLiveCentMaximumOpenPositions);

      Log("LIVE CENT PARITY WAIT | open position cap="+
          IntegerToString(InpLiveCentMaximumOpenPositions)+
          " | signal="+
          (string)g_persistentSetups[index].id);

      SetDeploymentFailure(reason,0,"","",false);
      return false;
   }

   string tradeEnvironmentReason="";
   if(!TradingEnvironmentReady(tradeEnvironmentReason))
   {
      g_envRejectStd++;       // V2.2 BTC S06 instrumentation
      bool temporary=
         (StringFind(tradeEnvironmentReason,
                     "disconnected")>=0);

      Log("LIVE ENTRY BLOCKED | "+tradeEnvironmentReason+
          " | signal="+
          (string)g_persistentSetups[index].id);

      SetDeploymentFailure(
         "trading environment unavailable: "+
         tradeEnvironmentReason,
         0,
         "",
         "",
         temporary);
      return false;
   }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double effectiveEquity=EffectiveAccountEquity();

   if(effectiveEquity<MinimumTradingEquity())
   {
      string reason=
         "effective equity below minimum: effective="+
         DoubleToString(effectiveEquity,2)+
         " raw="+DoubleToString(equity,2)+
         " minimum="+
         DoubleToString(MinimumTradingEquity(),2);

      Log("AGGRESSIVE ARM BLOCKED | "+reason);
      SetDeploymentFailure(reason,0,"","",false);
      return false;
   }

   LayerPlan plans[];
   bool planBuilt=BuildAggressiveArmPlans(g_persistentSetups[index],plans);

   if(!planBuilt && forceZeroConf)
   {
      Log("ZERO-CONF PLAN FALLBACK | signal="+
          (string)g_persistentSetups[index].id+
          " | forcing one direct STANDARD MARKET plan");
      ResetDeploymentFailure();

      LayerPlan forcedMarket;
      if(BuildForcedZeroConfluenceMarketPlan(g_persistentSetups[index],forcedMarket))
      {
         ArrayResize(plans,1);
         plans[0]=forcedMarket;
         planBuilt=true;
      }
   }

   if(!planBuilt)
   {
      if(!g_deployFailureSet)
         SetDeploymentFailure(
            "aggressive layer plan unavailable: check lot size, broker minimum, SL geometry and margin limits",
            0,"","",false);

      Log("AGGRESSIVE ARM plan unavailable | signal="+
          (string)g_persistentSetups[index].id+
          " | "+DeploymentFailureSummary());
      return false;
   }

   int available=ArraySize(plans);
   int totalLayers=available;

   if(available<1 || plans[0].kind!=LAYER_MARKET)
   {
      SetDeploymentFailure(
         "layer plan did not provide MARKET as route 1",
         0,"","",false);
      return false;
   }

   double plannedRiskMoney=0.0;

   for(int i=0;i<available;i++)
      plannedRiskMoney+=plans[i].volume*
                        plans[i].lossPerLot;

   g_persistentSetups[index].riskPct=
      (equity>0)
      ? plannedRiskMoney/equity*100.0
      : 0.0;

   g_persistentSetups[index].targetRR=
      TargetRRForSetup(
         g_persistentSetups[index].riskPct);

   bool marketFilled=
      PlacePersistentLayer(
         g_persistentSetups[index],
         plans[0],
         0,
         totalLayers);

   if(!marketFilled)
   {
      if(!g_deployFailureSet)
      {
         SetDeploymentFailure(
            "first MARKET layer was not accepted",
            trade.ResultRetcode(),
            trade.ResultRetcodeDescription(),
            trade.ResultComment(),
            TemporaryTradeRetcode(
               trade.ResultRetcode()));
      }

      Log("AGGRESSIVE ARM MARKET FAILED | signal="+
          (string)g_persistentSetups[index].id+
          " | zero-conf="+string(zeroConf?"YES":"NO")+
          " | "+DeploymentFailureSummary()+
          " | no pending exposure staged="+
          string((zeroConf ||
                  InpAggressiveRequireMarketFill)
                 ?"YES":"NO"));

      if(zeroConf ||
         InpAggressiveRequireMarketFill)
         return false;
   }

   int placed=marketFilled?1:0;
   int pendingPlaced=0;
   double acceptedLots=
      marketFilled ? plans[0].volume : 0.0;

   if(marketFilled)
      g_dailyLayerOrders++;

   if(zeroConf)
   {
      Log("ZERO-CONF MARKET-FIRST CONTINUE | signal="+
          (string)g_persistentSetups[index].id+
          " | no per-M5 fill cap"+
          " | optional confidence layers may follow MARKET"+
          " | directional ceiling="+
          IntegerToString(InpMaxActiveLayersPerDirection));
   }

   if(marketFilled ||
      (!zeroConf &&
       !InpAggressiveRequireMarketFill))
   {
      for(int i=1;i<available;i++)
      {
         if(PlacePersistentLayer(
               g_persistentSetups[index],
               plans[i],
               i,
               totalLayers))
         {
            placed++;
            pendingPlaced++;
            acceptedLots+=plans[i].volume;
            g_dailyLayerOrders++;
         }
      }
   }

   if(placed<=0)
   {
      if(!g_deployFailureSet)
      {
         SetDeploymentFailure(
            "no MARKET or pending layer was accepted",
            0,"","",false);
      }
      return false;
   }

   g_persistentSetups[index].deployed=true;
   g_persistentSetups[index].deployedClock=
      TimeCurrent();
   g_persistentSetups[index].layersPlanned=
      totalLayers;
   g_persistentSetups[index].layersPlaced=
      placed;

   g_qualityDeployCount++;
   g_campaignSetups++;

   RegisterSetupAnalytics(
      g_persistentSetups[index]);

   int analyticsIndex=
      EnsureAnalytics(
         g_persistentSetups[index].id);

   g_setupAnalytics[analyticsIndex].plannedLots=
      acceptedLots;

   Log("AGGRESSIVE ARM DEPLOYED | signal="+
       (string)g_persistentSetups[index].id+
       " | "+
       string(g_persistentSetups[index].direction==1
              ?"BUY":"SELL")+
       " | MARKET="+
       string(marketFilled?"FILLED":"FAILED")+
       " | LIMIT placed="+
       IntegerToString(pendingPlaced)+
       " | total routes="+
       IntegerToString(placed)+
       "/"+IntegerToString(totalLayers)+
       " | zero-conf MARKET-first="+
       string(zeroConf?"YES":"NO")+
       " | confidence="+
       ConfidenceClassText(
          g_persistentSetups[index].confluences)+
       " | lots="+
       DoubleToString(
          acceptedLots,
          VolumeDigits())+
       " | SL="+
       DoubleToString(
          g_persistentSetups[index].structuralSL,
          _Digits));

   return true;
}


bool DeployPersistentSetup(int index)
{
   if(InpAggressiveArmExecution)
      return DeployAggressiveArmSetup(index);

   if(index<0 || index>=ArraySize(g_persistentSetups))
      return false;

   if(!g_persistentSetups[index].active ||
      g_persistentSetups[index].deployed)
      return false;

   // V2.1a S1/S2: STANDARD-path confluence gate, non-delegating branch only.
   // When InpAggressiveArmExecution is true this function has already
   // returned above via DeployAggressiveArmSetup(), which carries its own
   // gate - so exactly one evaluation happens per standard attempt.
   //
   // NOTE ON THE DAILY RESET: CheckCampaignDay() below is a BROKER-DAY
   // boundary concept (ResetCampaignDay() keys on year/month/day from
   // TimeTradeServer()). The V2.1a session classifier is an INTRADAY hour
   // classifier and deliberately does not touch it - there is no second
   // daily-reset mechanism being introduced here.
   if(!ConfluenceGateAllows(
         V21A_PATH_STANDARD,
         "route=PERSISTENT-TOUCH signal="+
         (string)g_persistentSetups[index].id+
         " direction="+
         string(g_persistentSetups[index].direction==1?"BUY":"SELL")))
      return false;

   CheckCampaignDay();

   if(g_dayTradingLocked)
      return false;

   if(g_campaignSetups>=InpMaxCampaignSetupsPerDay)
      return false;

   string tradeEnvironmentReason="";
   if(!TradingEnvironmentReady(tradeEnvironmentReason))
   {
      g_envRejectStd++;       // V2.2 BTC S06 instrumentation
      Log("LIVE ENTRY BLOCKED | "+tradeEnvironmentReason+
          " | signal="+(string)g_persistentSetups[index].id);
      return false;
   }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double effectiveEquity=EffectiveAccountEquity();

   if(effectiveEquity<MinimumTradingEquity())
   {
      Log("TOUCH BLOCKED: effective equity below minimum | signal="+
          (string)g_persistentSetups[index].id+
          " | effective="+DoubleToString(effectiveEquity,2)+
          " | raw="+DoubleToString(equity,2)+
          " | minimum="+DoubleToString(MinimumTradingEquity(),2));
      return false;
   }

   MqlTick execTick;

   if(!SymbolInfoTick(_Symbol,execTick))
      return false;

   int conf=g_persistentSetups[index].confluences;

   double marketPrice=
      (g_persistentSetups[index].direction==1)
      ? execTick.ask
      : execTick.bid;

   double safeSL=
      BrokerSafeExecutionSL(
         g_persistentSetups[index].direction,
         marketPrice,
         g_persistentSetups[index].structuralSL);

   if(MathAbs(safeSL-g_persistentSetups[index].structuralSL)>_Point)
   {
      Log("BROKER-SAFE SL ADJUST | signal="+
          (string)g_persistentSetups[index].id+
          " | old="+
          DoubleToString(g_persistentSetups[index].structuralSL,_Digits)+
          " | new="+DoubleToString(safeSL,_Digits));
   }

   g_persistentSetups[index].structuralSL=safeSL;

   double targetSetupLot=
      InpUseConfidenceLotSizing
      ? ConfidenceSetupLot(conf)
      : AutoBaseLayerLot();

   SetQualityContext(g_persistentSetups[index].direction,
                     g_persistentSetups[index].zoneTouchNumber,
                     g_persistentSetups[index].departureScore,
                     g_persistentSetups[index].zoneGrade);
   SetDistalContext(g_persistentSetups[index].direction,
                    marketPrice,
                    g_persistentSetups[index].entryLo,
                    g_persistentSetups[index].entryHi);

   targetSetupLot=
      CapSetupVolumeForCentSafety(
         g_persistentSetups[index].direction,
         marketPrice,
         g_persistentSetups[index].structuralSL,
         targetSetupLot);

   ClearQualityContext();

   if(targetSetupLot<=0)
   {
      Log("CMP TOUCH but confidence setup lot is below broker minimum | signal="+
          (string)g_persistentSetups[index].id);
      return false;
   }

   // In precise-touch mode the confidence lot is the requested setup size.
   // Risk is still calculated and reported, but it does not silently convert
   // a valid 0.01/0.02/0.03 setup into no trade.
   double guardPct=
      MathMax(0.0,
              MathMin(InpMaxRiskPct,
                      InpConfidenceLotRiskGuardPct));

   double riskBudget=
      InpHonorConfidenceLotAtTouch
      ? 1.0e12
      : equity*guardPct/100.0;

   int desiredLayers=
      DesiredLayersForSetup(conf,
                            g_persistentSetups[index].entryLo,
                            g_persistentSetups[index].entryHi,
                            g_persistentSetups[index].structuralSL);

   LayerPlan plans[];

   bool planOK=false;

   if(InpUseConfidenceLotSizing)
   {
      planOK=
         CreateConfidenceLayerSet(
            g_persistentSetups[index].direction,
            g_persistentSetups[index].entryLo,
            g_persistentSetups[index].entryHi,
            g_persistentSetups[index].structuralSL,
            targetSetupLot,
            riskBudget,
            desiredLayers,
            plans);
   }
   else
   {
      planOK=
         CreateBestLayerSetDynamic(
            g_persistentSetups[index].direction,
            g_persistentSetups[index].entryLo,
            g_persistentSetups[index].entryHi,
            g_persistentSetups[index].structuralSL,
            riskBudget,
            desiredLayers,
            plans);
   }

   if(!planOK && InpMarketFallbackOnTouch)
   {
      Log("SMART LAYER PLAN unavailable -> MARKET FALLBACK | signal="+
          (string)g_persistentSetups[index].id+
          " | target lot="+
          DoubleToString(targetSetupLot,VolumeDigits()));

      planOK=
         CreateMarketFallbackLayerSet(
            g_persistentSetups[index].direction,
            targetSetupLot,
            desiredLayers,
            g_persistentSetups[index].structuralSL,
            plans);
   }

   if(!planOK)
   {
      Log("CMP TOUCH but execution plan still unavailable | signal="+
          (string)g_persistentSetups[index].id+
          " | class="+ConfidenceClassText(conf)+
          " | target lot="+
          DoubleToString(targetSetupLot,VolumeDigits()));
      return false;
   }

   int available=ArraySize(plans);

   if(available<=0)
      return false;

   double plannedRiskMoney=0.0;
   double plannedLots=0.0;

   for(int i=0;i<available;i++)
   {
      plannedRiskMoney+=plans[i].volume*plans[i].lossPerLot;
      plannedLots+=plans[i].volume;
   }

   double actualRiskPct=
      (equity>0)
      ? plannedRiskMoney/equity*100.0
      : 0.0;

   g_persistentSetups[index].riskPct=actualRiskPct;
   g_persistentSetups[index].targetRR=
      TargetRRForSetup(actualRiskPct);

   int placed=0;
   double acceptedLots=0.0;

   for(int i=0;i<available;i++)
   {
      bool layerOK=
         PlacePersistentLayer(g_persistentSetups[index],
                              plans[i],
                              i,
                              available);

      // A real CMP touch should not be lost only because a pending-price
      // placement becomes invalid as Bid/Ask moves by a few points.
      if(!layerOK &&
         InpMarketFallbackOnTouch &&
         plans[i].kind!=LAYER_MARKET)
      {
         MqlTick retryTick;

         if(SymbolInfoTick(_Symbol,retryTick))
         {
            LayerPlan marketPlan=plans[i];
            marketPlan.kind=LAYER_MARKET;
            marketPlan.execPrice=
               (g_persistentSetups[index].direction==1)
               ? retryTick.ask
               : retryTick.bid;
            marketPlan.rawPrice=marketPlan.execPrice;
            marketPlan.lossPerLot=
               OneLotLoss(
                  g_persistentSetups[index].direction,
                  marketPlan.execPrice,
                  g_persistentSetups[index].structuralSL);

            if(marketPlan.lossPerLot>0)
            {
               Log("PENDING REJECTED -> MARKET RETRY | signal="+
                   (string)g_persistentSetups[index].id+
                   " | layer="+IntegerToString(i+1));

               layerOK=
                  PlacePersistentLayer(
                     g_persistentSetups[index],
                     marketPlan,
                     i,
                     available);
            }
         }
      }

      if(layerOK)
      {
         placed++;
         acceptedLots+=plans[i].volume;
         g_dailyLayerOrders++;
      }
   }

   if(placed<=0)
      return false;

   g_persistentSetups[index].deployed=true;
   g_persistentSetups[index].deployedClock=TimeCurrent();
   g_persistentSetups[index].layersPlanned=available;
   g_persistentSetups[index].layersPlaced=placed;

   g_qualityDeployCount++;

   RegisterSetupAnalytics(g_persistentSetups[index]);

   int analyticsIndex=
      EnsureAnalytics(g_persistentSetups[index].id);

   g_setupAnalytics[analyticsIndex].plannedLots=acceptedLots;

   g_campaignSetups++;

   Log("FAST M5 DEPLOYED | signal="+
       (string)g_persistentSetups[index].id+
       " | "+
       string(g_persistentSetups[index].direction==1?"BUY":"SELL")+
       " | class="+ConfidenceClassText(conf)+
       " | conf="+IntegerToString(conf)+
       " | setup lots="+
       DoubleToString(acceptedLots,VolumeDigits())+
       " | actual risk="+
       DoubleToString(actualRiskPct,2)+"%"+
       " | layers="+IntegerToString(placed)+
       " | execution=MARKET/LIMIT/STOP");

   return true;
}
void CapturePersistentReadySignals()
{
   if(!InpPersistentReadyMode)
      return;

   if(g_buyReady.armed)
   {
      long id=(long)g_buyReady.armedClock*10+1;

      if(id!=g_lastCapturedBuyId)
      {
         if(QueuePersistentSetup(g_buyReady,1))
            g_lastCapturedBuyId=id;
      }

      // The READY state is now owned by the persistent queue.
      ClearReadySnapshot(g_buyReady);
   }

   if(g_sellReady.armed)
   {
      long id=(long)g_sellReady.armedClock*10+2;

      if(id!=g_lastCapturedSellId)
      {
         if(QueuePersistentSetup(g_sellReady,-1))
            g_lastCapturedSellId=id;
      }

      ClearReadySnapshot(g_sellReady);
   }

   ClearReadySnapshot(g_ready);

   // Do NOT freeze scanning just because another real trade is LIVE.
   g_state=ST_MONITORING;
}

void DeletePersistentObjects(long id)
{
   string key=(string)id;

   DeleteObject("PZ_"+key);
   DeleteObject("PZLBL_"+key);
   DeleteObject("PSL_"+key);
   DeleteObject("PSLLBL_"+key);
}

void DrawPersistentReadyZones()
{
   if(!InpPersistentReadyMode)
      return;

   datetime labelTime=TimeCurrent()+TfSeconds(g_entryTF)*3;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active)
         continue;

      PersistentReadySetup s=g_persistentSetups[i];
      datetime future=s.armedBarTime+TfSeconds(g_entryTF)*ReadyExpiryBarsEffective();
      if(future<=TimeCurrent()) future=TimeCurrent()+TfSeconds(g_entryTF);

      int positions=CountPersistentPositions(s.id);
      bool live=(positions>0);

      color c=(s.direction==1)?InpBuyColor:InpSellColor;
      string key=(string)s.id;

      Rect("PZ_"+key,
           s.entryTime,
           s.entryLo,
           future,
           s.entryHi,
           c,
           true,
           live?2:1,
           STYLE_SOLID);

      string state=live
                   ?"LIVE"
                   :(s.deployed?"READY ORDERS SET":"READY WATCHING");
      string label=state+" "+string(s.direction==1?"BUY":"SELL")+
                   " • "+IntegerToString(s.confluences)+" CONF";

      ChartText("PZLBL_"+key,
                labelTime,
                (s.entryLo+s.entryHi)/2.0,
                label,
                c,
                8,
                ANCHOR_LEFT);

      if(live && InpKeepZoneVisibleWhileLive)
      {
         HLine("PSL_"+key,s.structuralSL,InpSellColor,STYLE_DASH,1);

         ChartText("PSLLBL_"+key,
                   labelTime,
                   s.structuralSL,
                   "SL  "+PriceText(s.structuralSL),
                   InpSellColor,
                   8,
                   ANCHOR_LEFT);
      }
      else
      {
         DeleteObject("PSL_"+key);
         DeleteObject("PSLLBL_"+key);
      }
   }
}



void RefreshPersistentPositionProtection()
{
   if(!InpPersistentReadyMode)
      return;

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
      if(g_persistentSetups[i].active)
         UpdateSetupPeakAnalytics(g_persistentSetups[i].id);

   ManageHybridTrailingPositions("PERSISTENT");
}

void ProcessPersistentSetups()
{
   if(!InpPersistentReadyMode)
      return;

   CheckCampaignDay();

   // Normal setups still observe the day lock in quality/deployment checks.
   // Touched zero-confluence setups continue forced MARKET retry.

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   MqlRates m5[];
   if(!LoadRatesFlexible(PERIOD_M5,20,6,m5))
      return;

   double invalidationBuffer=
      MathMax(g_pipSize*5.0,_Point*2.0);

   for(int i=0;i<ArraySize(g_persistentSetups);i++)
   {
      if(!g_persistentSetups[i].active)
         continue;

      long id=g_persistentSetups[i].id;

      int closedBars=
         PersistentClosedBars(
            g_persistentSetups[i].armedBarTime);

      bool expired=
         (closedBars>=ReadyExpiryBarsEffective());

      // -----------------------------------------------------
      // FROZEN V1.1.0 READY.
      // -----------------------------------------------------
      if(!g_persistentSetups[i].deployed &&
         !g_persistentSetups[i].triggered)
      {
         int direction=
            g_persistentSetups[i].direction;

         // Signal touch follows the chart's own price mode (Bid or Last).
         // Actual order execution remains Ask for BUY / Bid for SELL.
         double cmp=ReadyTouchCMP(tick);

         double normalTouchTol=
            MathMax(0.0,InpEntryTouchTolerancePips)*
            g_pipSize;

         double zeroConfTouchTol=
            MathMax(
               MathMax(0.0,InpEntryTouchTolerancePips),
               MathMax(0.0,InpZeroConfTouchTolerancePips))*
            g_pipSize;

         bool zeroConf=
            g_persistentSetups[i].zeroConfluenceFallback;

         double observedLo=cmp;
         double observedHi=cmp;

         if(zeroConf)
         {
            BuildZeroConfluenceTouchEnvelope(
               tick,
               cmp,
               g_persistentSetups[i].hasPreviousTouchCMP,
               g_persistentSetups[i].previousTouchCMP,
               observedLo,
               observedHi);
         }

         // Save this observation only after the previous value has been used
         // to construct the tick path.
         g_persistentSetups[i].previousTouchCMP=cmp;
         g_persistentSetups[i].hasPreviousTouchCMP=true;

         bool entryTouched=
            zeroConf
            ? false
            : (cmp>=g_persistentSetups[i].entryLo-normalTouchTol &&
               cmp<=g_persistentSetups[i].entryHi+normalTouchTol);

         ZeroConfTriggerCandidate zeroCandidate;
         ResetZeroConfCandidate(zeroCandidate);

         bool zeroConfQualified=
            zeroConf &&
            ResolveZeroConfTriggerMap(
               g_persistentSetups[i].zeroConfTriggerMap,
               direction,
               observedLo,
               observedHi,
               zeroConfTouchTol,
               zeroCandidate);

         bool laterM5=
            InpAggressiveArmExecution
            ? true
            : (closedBars>=1);

         bool touchEligible=
            zeroConf
            ? zeroConfQualified
            : (laterM5 && entryTouched);

         // Precise touch latch:
         // once a normal READY touch or a qualified zero-confluence M5 reclaim
         // is found, remember it so transient movement cannot lose it.
         if(touchEligible &&
            !g_persistentSetups[i].touchLatched)
         {
            g_persistentSetups[i].touchLatched=true;
            g_persistentSetups[i].highRiskTouchLatched=false;
            g_persistentSetups[i].s1r1TouchLatched=false;
            g_persistentSetups[i].s2r2TouchLatched=false;
            g_persistentSetups[i].touchClock=TimeCurrent();
            g_persistentSetups[i].touchPrice=cmp;
            g_persistentSetups[i].deployAttempts=0;

            // V2.0 S2: a zone is worked by price ARRIVING at it, so the touch
            // is counted here - at the latch - regardless of whether this
            // setup goes on to deploy.
            g_persistentSetups[i].zoneTouchNumber=
               RegisterZoneTouch(g_persistentSetups[i].entryLo,
                                 g_persistentSetups[i].entryHi);

            // V2.0 S4: grade is fixed at the moment of the touch that will
            // deploy it, then frozen - so the size it was graded for and the
            // exit geometry it runs on can never disagree.
            if(InpUseZoneGrading)
            {
               string gradeDetail="";

               double proximalEdge=
                  (direction==1)
                  ? g_persistentSetups[i].entryHi
                  : g_persistentSetups[i].entryLo;

               g_persistentSetups[i].zoneGrade=
                  ComputeZoneGrade(direction,
                                   g_persistentSetups[i].zoneTouchNumber,
                                   g_persistentSetups[i].departureScore,
                                   proximalEdge,
                                   gradeDetail);

               Log("V2.0 S4 ZONE GRADED | signal="+(string)id+
                   " | "+gradeDetail+
                   " | size x"+
                   DoubleToString(GradeSizeMultiplier(
                      g_persistentSetups[i].zoneGrade),2)+
                   " | trail x"+
                   DoubleToString(GradeTrailMultiplier(
                      g_persistentSetups[i].zoneGrade),2)+
                   " | partial TP="+
                   DoubleToString(GradePartialTPPips(
                      g_persistentSetups[i].zoneGrade),1)+" pips");
            }

            double triggerLo=
               zeroConf
               ? zeroCandidate.lo
               : g_persistentSetups[i].entryLo;

            double triggerHi=
               zeroConf
               ? zeroCandidate.hi
               : g_persistentSetups[i].entryHi;

            if(zeroConf)
            {
               g_persistentSetups[i].zeroConfTriggerCode=
                  zeroCandidate.code;
               g_persistentSetups[i].zeroConfTriggerPriority=
                  zeroCandidate.priority;
               g_persistentSetups[i].zeroConfTriggerLo=
                  zeroCandidate.lo;
               g_persistentSetups[i].zeroConfTriggerHi=
                  zeroCandidate.hi;
               g_persistentSetups[i].zeroConfReclaimTime=
                  zeroCandidate.reclaimTime;
            }

            string triggerText=
               zeroConf
               ? ZeroConfTriggerCodeText(
                    zeroCandidate.code,
                    direction)
               : "READY";

            Log("CMP TOUCH LATCHED | signal="+
                (string)id+
                " | V2.0 touch #"+
                IntegerToString(g_persistentSetups[i].zoneTouchNumber)+
                " | trigger="+triggerText+
                " | direction="+
                string(direction==1?"BUY":"SELL")+
                " | chartCMP="+DoubleToString(cmp,_Digits)+
                " | observed path="+
                DoubleToString(observedLo,_Digits)+".."+
                DoubleToString(observedHi,_Digits)+
                " | tolerance="+
                DoubleToString(
                   zeroConf
                   ? InpZeroConfTouchTolerancePips
                   : InpEntryTouchTolerancePips,
                   1)+" pips"+
                " | bid="+DoubleToString(tick.bid,_Digits)+
                " | ask="+DoubleToString(tick.ask,_Digits)+
                " | zone="+
                DoubleToString(triggerLo,_Digits)+
                "-"+
                DoubleToString(triggerHi,_Digits)+
                " | priority="+
                IntegerToString(
                   zeroConf
                   ? zeroCandidate.priority
                   : 6)+
                " | M5 reclaim="+
                string(zeroConf
                       ? TimeToString(
                            zeroCandidate.reclaimTime,
                            TIME_DATE|TIME_MINUTES)
                       : "NOT REQUIRED"));
         }

         int activeRetrySeconds=
            zeroConf
            ? MathMax(InpTouchRetrySeconds,
                      InpZeroConfTouchRetrySeconds)
            : InpTouchRetrySeconds;

         int activeMaxAttempts=
            zeroConf
            ? MathMax(InpMaxTouchDeployAttempts,
                      InpZeroConfMaxDeployAttempts)
            : InpMaxTouchDeployAttempts;

         bool forceZeroConfExecution=
            zeroConf &&
            V3104_FORCE_ZERO_CONF_MARKET_EXECUTION &&
            V3104_ZERO_CONF_RETRY_UNTIL_FILLED;

         bool latchFresh=
            g_persistentSetups[i].touchLatched &&
            (forceZeroConfExecution ||
             ((TimeCurrent()-g_persistentSetups[i].touchClock <=
               MathMax(0,activeRetrySeconds)) &&
              g_persistentSetups[i].deployAttempts<
               MathMax(1,activeMaxAttempts)));

         if(latchFresh)
         {
            datetime currentM5=
               CurrentM5OpenTime();

            if(!forceZeroConfExecution &&
               currentM5>0 &&
               g_persistentSetups[i].deploymentBlockedM5==currentM5)
               continue;

            // V3.190 S4: gate the deploy on touch confirmation. The latch is
            // deliberately left standing while we wait, so the existing
            // retry/expiry machinery keeps the setup alive and frequency is
            // unchanged - TouchConfirmationSatisfied() self-releases on
            // timeout rather than letting the setup be dropped.
            string confirmOutcome="";

            double confirmZoneLo=
               zeroConf && g_persistentSetups[i].zeroConfTriggerLo>0.0
               ? g_persistentSetups[i].zeroConfTriggerLo
               : g_persistentSetups[i].entryLo;

            double confirmZoneHi=
               zeroConf && g_persistentSetups[i].zeroConfTriggerHi>0.0
               ? g_persistentSetups[i].zeroConfTriggerHi
               : g_persistentSetups[i].entryHi;

            if(!TouchConfirmationSatisfied(
                  g_persistentSetups[i],
                  direction,
                  confirmZoneLo,
                  confirmZoneHi,
                  cmp,
                  confirmOutcome))
            {
               continue;
            }

            string reason="";

            if(PersistentQualityPass(
                  g_persistentSetups[i],reason))
            {
               if(!DeploymentRetryIntervalElapsed(
                     g_persistentSetups[i]))
               {
                  continue;
               }

               MarkDeploymentAttempt(
                  g_persistentSetups[i]);

               g_persistentSetups[i].deployAttempts++;

               ResetDeploymentFailure();

               bool deployed=
                  DeployPersistentSetup(i);

               if(deployed)
               {
                  Log("CMP TOUCH EXECUTED | signal="+
                      (string)id+
                      " | trigger="+
                      PersistentTouchTriggerText(
                         g_persistentSetups[i])+
                      " | zero-conf fallback="+
                      string(g_persistentSetups[i].zeroConfluenceFallback
                             ?"YES":"NO")+
                      " | direction="+
                      string(direction==1?"BUY":"SELL")+
                      " | attempts="+
                      IntegerToString(
                         g_persistentSetups[i].deployAttempts));
                  continue;
               }

               if(!g_deployFailureSet)
               {
                  SetDeploymentFailure(
                     "deployment returned false without a detailed broker result",
                     0,"","",false);
               }

               string failure=
                  DeploymentFailureSummary();

               if(forceZeroConfExecution)
               {
                  Log("ZERO-CONF FORCED MARKET RETRY | signal="+(string)id+
                      " | trigger="+PersistentTouchTriggerText(g_persistentSetups[i])+
                      " | direction="+string(direction==1?"BUY":"SELL")+
                      " | attempt="+IntegerToString(g_persistentSetups[i].deployAttempts)+
                      " | broker classification="+
                      string(g_deployFailureTemporary?"TEMPORARY":"PERMANENT/LOCAL")+
                      " | "+failure+
                      " | latch remains active=YES"+
                      " | retry interval="+
                      IntegerToString((int)MathMax(0,InpDeploymentRetryIntervalMs))+"ms");
               }
               else if(g_deployFailureTemporary)
               {
                  Log("CMP TOUCH EXECUTION RETRY | signal="+
                      (string)id+
                      " | trigger="+PersistentTouchTriggerText(g_persistentSetups[i])+
                      " | attempt="+IntegerToString(g_persistentSetups[i].deployAttempts)+
                      " | temporary=YES | "+failure+
                      " | minimum retry interval="+
                      IntegerToString((int)MathMax(0,InpDeploymentRetryIntervalMs))+"ms");
               }
               else
               {
                  string triggerBeforeBlock=PersistentTouchTriggerText(g_persistentSetups[i]);
                  g_persistentSetups[i].deploymentBlockedM5=currentM5;
                  ClearPersistentTouchLatch(g_persistentSetups[i]);

                  Log("CMP TOUCH EXECUTION STOPPED THIS M5 | signal="+(string)id+
                      " | trigger="+triggerBeforeBlock+
                      " | attempt="+IntegerToString(g_persistentSetups[i].deployAttempts)+
                      " | temporary=NO | "+failure+
                      " | next eligible M5="+
                      TimeToString(currentM5+PeriodSeconds(PERIOD_M5),
                                   TIME_DATE|TIME_MINUTES));
               }
            }
            else
            {
               Log("CMP TOUCH QUALITY WAIT | signal="+
                   (string)id+
                   " | trigger="+
                   PersistentTouchTriggerText(
                      g_persistentSetups[i])+
                   " | "+reason);
            }
         }

         if(g_persistentSetups[i].touchLatched &&
            !latchFresh)
         {
            ClearPersistentTouchLatch(
               g_persistentSetups[i]);
         }

         bool routeInvalid=
            !g_persistentSetups[i].counterTrend &&
            ((direction==1 && !g_trendBuyRoute) ||
             (direction==-1 && !g_trendSellRoute));

         bool zoneInvalid=
            (direction==1)
            ? (tick.bid<
               g_persistentSetups[i].supportLo-
               invalidationBuffer)
            : (tick.ask>
               g_persistentSetups[i].supportHi+
               invalidationBuffer);

         bool supportTouched=
            Overlap(m5[0].low,
                    m5[0].high,
                    g_persistentSetups[i].supportLo,
                    g_persistentSetups[i].supportHi);

         if(!supportTouched)
            g_persistentSetups[i].zoneExited=true;

         bool retestInvalid=
            g_persistentSetups[i].zoneExited &&
            supportTouched &&
            g_persistentSetups[i].zoneRetests>=MAX_ZONE_RETESTS;

         bool entrySideInvalid=
            InpAggressiveArmExecution
            ? false
            : (!zeroConf &&
               !entryTouched &&
               ((direction==1 &&
                 g_persistentSetups[i].entryHi>=cmp-_Point) ||
                (direction==-1 &&
                 g_persistentSetups[i].entryLo<=cmp+_Point)));

         bool activeTouchRetry=
            g_persistentSetups[i].touchLatched &&
            (forceZeroConfExecution ||
             (TimeCurrent()-g_persistentSetups[i].touchClock <=
              MathMax(0,activeRetrySeconds)));

         if(!activeTouchRetry &&
            (expired ||
             routeInvalid ||
             zoneInvalid ||
             retestInvalid ||
             entrySideInvalid))
         {
            DeletePersistentObjects(id);
            g_persistentSetups[i].expiryHandled=true;
            g_persistentSetups[i].active=false;

            Log("SOURCE READY INVALIDATED | signal="+
                (string)id+
                " | expired="+string(expired?"YES":"NO")+
                " | route="+string(routeInvalid?"YES":"NO")+
                " | zone="+string(zoneInvalid?"YES":"NO")+
                " | retest="+string(retestInvalid?"YES":"NO")+
                " | side="+string(entrySideInvalid?"YES":"NO"));
         }

         continue;
      }

      // -----------------------------------------------------
      // DEPLOYED / LIVE: signal snapshot is immutable.
      // Profit Harvest owns exits.
      // -----------------------------------------------------
      int positions=CountPersistentPositions(id);
      int orders=CountPersistentOrders(id);

      if(positions>0 &&
         !g_persistentSetups[i].triggered)
      {
         g_persistentSetups[i].triggered=true;
         g_persistentTriggeredCount++;
         g_liveSignalCount++;

         Log("SOURCE LIVE | signal="+
             (string)id+
             " | "+
             string(g_persistentSetups[i].direction==1
                    ?"BUY":"SELL")+
             " | risk="+
             DoubleToString(
                g_persistentSetups[i].riskPct,2)+"%"+
             " | runnerRR="+
             DoubleToString(
                g_persistentSetups[i].targetRR,2));
      }

      // 333 bars governs READY/pending validity only.
      // Existing LIVE positions continue to staged TP / trail / SL.
      if(expired &&
         !g_persistentSetups[i].expiryHandled)
      {
         if(orders>0)
            CancelPersistentOrders(id);

         g_persistentSetups[i].expiryHandled=true;
      }

      positions=CountPersistentPositions(id);
      orders=CountPersistentOrders(id);

      if(!g_persistentSetups[i].triggered &&
         g_persistentSetups[i].expiryHandled &&
         positions==0 &&
         orders==0)
      {
         DeletePersistentObjects(id);
         g_persistentSetups[i].active=false;
         continue;
      }

      if(g_persistentSetups[i].triggered &&
         positions==0 &&
         orders==0)
      {
         DeletePersistentObjects(id);
         g_persistentSetups[i].active=false;
         g_persistentCompletedCount++;
         g_executedBasketCount++;

         Log("SOURCE SETUP COMPLETED | signal="+
             (string)id);
      }
   }

   RefreshPersistentPositionProtection();
   CheckCampaignDay();
}

//--------------------------- Order placement ------------------------
bool PlaceOneLayer(int direction,LayerPlan &p,int layerIndex,int totalLayers,long signalId)
{
   if(!DailyRiskCapacityAvailable(
         "LEGACY layer "+
         IntegerToString(layerIndex+1)+
         "/"+
         IntegerToString(totalLayers)))
   {
      g_capacityRejectOther++;   // V2.2 BTC S06 instrumentation
      return false;
   }

   if(!M5ClosedLossCapacityAvailable(
         "LEGACY layer "+
         IntegerToString(layerIndex+1)+
         "/"+
         IntegerToString(totalLayers)))
      return false;

   if(!DirectionalLosingPositionCapacityAvailable(
         direction,
         "LEGACY layer "+
         IntegerToString(layerIndex+1)+
         "/"+
         IntegerToString(totalLayers)))
      return false;

   string comment="EZP2 "+IntegerToString((int)signalId)+" L"+IntegerToString(layerIndex+1)+"/"+IntegerToString(totalLayers);
   g_orderSendOther++;           // V2.2 BTC S06 instrumentation
   bool ok=false;

   if(direction==1)
   {
      if(p.kind==LAYER_MARKET)
         ok=trade.Buy(p.volume,_Symbol,0.0,0.0,0.0,comment);
      else if(p.kind==LAYER_LIMIT)
         ok=trade.BuyLimit(p.volume,p.execPrice,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
      else if(p.kind==LAYER_STOP)
         ok=trade.BuyStop(p.volume,p.execPrice,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
   }
   else
   {
      if(p.kind==LAYER_MARKET)
         ok=trade.Sell(p.volume,_Symbol,0.0,0.0,0.0,comment);
      else if(p.kind==LAYER_LIMIT)
         ok=trade.SellLimit(p.volume,p.execPrice,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
      else if(p.kind==LAYER_STOP)
         ok=trade.SellStop(p.volume,p.execPrice,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
   }

   string kindText=(p.kind==LAYER_MARKET)?"MARKET":(p.kind==LAYER_LIMIT?"LIMIT":"STOP");

   if(ok)
      Log(kindText+" layer "+IntegerToString(layerIndex+1)+"/"+IntegerToString(totalLayers)+
          " placed. Price="+DoubleToString(p.execPrice,_Digits)+
          " Volume="+DoubleToString(p.volume,VolumeDigits()));
   else
      Log(kindText+" layer failed: "+trade.ResultRetcodeDescription());

   return ok;
}


bool M1ExecutionConfirmation(BridgeSignal &s,string &detail)
{
   detail="";

   if(!InpUseM1ExecutionConfirmation)
   {
      detail="M1 filter disabled";
      return true;
   }

   MqlRates r[];
   ArraySetAsSeries(r,true);

   int lookback=MathMax(2,MathMin(5,InpM1ConfirmationLookback));
   int need=MathMax(8,lookback+5);

   int got=CopyRates(_Symbol,PERIOD_M1,0,need,r);
   if(got<need)
   {
      detail="M1 history not ready";
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
   {
      detail="no live tick";
      return false;
   }

   double live=(s.direction==1)?tick.ask:tick.bid;
   double tol=MathMax(0.0,InpM1ZoneTolerancePips)*g_pipSize;

   // Price must still be at/near the frozen M5 READY rectangle.
   // This avoids chasing a move after the M1 confirmation has already run away.
   if(live<s.entryLo-tol || live>s.entryHi+tol)
   {
      detail="price moved away from READY zone";
      return false;
   }

   double wickRatio=MathMax(0.0,InpM1RejectionWickRatio);
   double closeStrength=MathMax(0.50,MathMin(0.90,InpM1CloseStrength));

   bool rejection=false;
   datetime rejectionTime=0;

   // Recent M1 rejection must touch the frozen M5 READY rectangle.
   for(int i=1;i<=lookback;i++)
   {
      // Only use M1 candles that belong to/after the READY activation window.
      if(s.armedTime>0 && (r[i].time+60)<s.armedTime)
         continue;

      double range=r[i].high-r[i].low;
      if(range<=_Point)
         continue;

      bool touches=(r[i].low<=s.entryHi && r[i].high>=s.entryLo);
      if(!touches)
         continue;

      double body=MathAbs(r[i].close-r[i].open);
      double safeBody=MathMax(body,_Point);

      if(s.direction==1)
      {
         double lowerWick=MathMin(r[i].open,r[i].close)-r[i].low;
         bool bullish=(r[i].close>r[i].open);
         bool strongClose=(r[i].close>=r[i].low+range*closeStrength);

         if(bullish && lowerWick>=safeBody*wickRatio && strongClose)
         {
            rejection=true;
            rejectionTime=r[i].time;
            break;
         }
      }
      else
      {
         double upperWick=r[i].high-MathMax(r[i].open,r[i].close);
         bool bearish=(r[i].close<r[i].open);
         bool strongClose=(r[i].close<=r[i].high-range*closeStrength);

         if(bearish && upperWick>=safeBody*wickRatio && strongClose)
         {
            rejection=true;
            rejectionTime=r[i].time;
            break;
         }
      }
   }

   // Micro structure break from the latest closed M1 candle.
   bool microBreak=false;
   if(s.direction==1)
      microBreak=(r[1].close>r[2].high && r[1].close>r[1].open);
   else
      microBreak=(r[1].close<r[2].low && r[1].close<r[1].open);

   // Momentum alternative: latest M1 body meaningfully larger than recent average.
   double avgBody=0.0;
   int bodyCount=0;
   for(int i=2;i<=MathMin(6,got-1);i++)
   {
      avgBody+=MathAbs(r[i].close-r[i].open);
      bodyCount++;
   }
   if(bodyCount>0) avgBody/=bodyCount;

   double body1=MathAbs(r[1].close-r[1].open);
   double range1=r[1].high-r[1].low;
   bool directional=(s.direction==1)?(r[1].close>r[1].open):(r[1].close<r[1].open);
   bool strongMomentumClose=false;

   if(range1>_Point)
   {
      if(s.direction==1)
         strongMomentumClose=(r[1].close>=r[1].low+range1*closeStrength);
      else
         strongMomentumClose=(r[1].close<=r[1].high-range1*closeStrength);
   }

   bool momentum=(directional &&
                  strongMomentumClose &&
                  avgBody>0 &&
                  body1>=avgBody*MathMax(0.80,InpM1MomentumBodyFactor));

   bool confirmed=false;

   if(s.counterTrend)
   {
      // Counter-trend signals already require at least 3 confluences on M5.
      // M1 still needs a genuine structure break plus either rejection or momentum.
      confirmed=microBreak && (rejection||momentum);
   }
   else
   {
      // M5 V1.2 READY already contains the compulsory rejection.
      // On M1, one additional execution clue is enough to avoid choking frequency.
      confirmed=(rejection||microBreak||momentum);
   }

   if(!confirmed)
   {
      detail=s.counterTrend
             ? "counter M1 confirmation missing"
             : "no M1 execution confirmation";
      return false;
   }

   detail="M1 confirmed";
   return true;
}

bool PassExecutionQualityFilter(BridgeSignal &s,string &reason)
{
   reason="";

   // The locked 2/3 confluence gate is mandatory and independent of the
   // optional QualityMode switch. This protects stored READY setups and all
   // compatibility execution paths from bypassing the source rule.
   const int required=s.counterTrend
                      ? COUNTER_MIN_CONFLUENCES
                      : TREND_MIN_CONFLUENCES;

   if(s.confluences<required)
   {
      reason="confluences "+IntegerToString(s.confluences)+
             " < required "+IntegerToString(required);
      return false;
   }

   if(!InpQualityMode)
      return true;

   if(s.counterTrend && !InpAllowCounterTrendTrades)
   {
      reason="counter-trend blocked";
      return false;
   }

   if(s.zoneRetests>MathMax(0,InpMaxExecutionZoneRetests))
   {
      reason="zone retests "+IntegerToString(s.zoneRetests)+
             " > allowed "+IntegerToString(InpMaxExecutionZoneRetests);
      return false;
   }

   if(InpUseM1ExecutionConfirmation)
   {
      string m1Reason="";
      if(!M1ExecutionConfirmation(s,m1Reason))
      {
         reason=m1Reason;
         return false;
      }
   }

   return true;
}

bool ArmReadySignal(BridgeSignal &s)
{
   if((s.state!=ST_READY && s.state!=ST_ACTIVE) || !s.valid)
      return false;

   double currentEquity=EffectiveAccountEquity();

   if(InpAutoScaleLayerLot && currentEquity<MinimumTradingEquity())
   {
      Log("READY ignored: effective account equity "+
          DoubleToString(currentEquity,2)+
          " is below minimum "+
          DoubleToString(MinimumTradingEquity(),2)+
          " | raw equity="+
          DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+".");
      return false;
   }

   if(s.signalId==g_lastDoneSignalId)
      return false;

   if(InpOneBasketAtATime && (CountOurPositions()>0 || CountOurPendingOrders()>0))
      return false;

   if(HasForeignPositionOnSymbol())
   {
      Log("Foreign/manual position already exists on "+_Symbol+". New setup skipped.");
      return false;
   }

   if(!SpreadAllowed())
   {
      g_spreadRejectOther++;     // V2.2 BTC S06 instrumentation
      Log("Spread filter blocked READY setup. | current spread exceeds "+
          EffectiveSpreadCapText());
      return false;
   }

   string qualityReason="";
   if(!PassExecutionQualityFilter(s,qualityReason))
   {
      Log("READY skipped by quality filter: "+qualityReason);
      return false;
   }

   double riskPct=RiskPctForConfidence(s.confluences);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double riskBudget=equity*riskPct/100.0;

   if(riskBudget<=0)
      return false;

   g_signalId=s.signalId;
   g_direction=s.direction;
   g_commonSL=NormalizeDouble(s.sl,_Digits);
   g_riskBudget=riskBudget;
   g_signalStarted=(s.armedTime>0)?s.armedTime:TimeCurrent();
   g_hadFill=false;

   LayerPlan plans[];
   if(!CreateBestLayerSet(g_direction,s.entryLo,s.entryHi,g_commonSL,g_riskBudget,plans))
   {
      Log("Could not create the minimum safe layer set within broker lot constraints.");
      ClearCurrentState(true);
      return false;
   }

   int n=ArraySize(plans);
   double plannedRisk=0.0,totalVolume=0.0;
   for(int i=0;i<n;i++)
   {
      plannedRisk += plans[i].volume*plans[i].lossPerLot;
      totalVolume += plans[i].volume;
   }

   Log("READY "+string(g_direction==1?"BUY":"SELL")+
       " | conf="+IntegerToString(s.confluences)+
       " | risk="+DoubleToString(riskPct,2)+"%"+
       " | budget="+DoubleToString(g_riskBudget,2)+
       " | layers="+IntegerToString(n)+
       " | total lots="+DoubleToString(totalVolume,VolumeDigits())+
       " | theoretical SL loss="+DoubleToString(plannedRisk,2)+
       " | quality=PASS"+
       " | retests="+IntegerToString(s.zoneRetests)+
       (InpAutoScaleLayerLot
        ? " | auto layer="+DoubleToString(AutoBaseLayerLot(),VolumeDigits())
        : ""));

   SaveState();

   int placed=0;
   for(int i=0;i<n;i++)
      if(PlaceOneLayer(g_direction,plans[i],i,n,g_signalId))
         placed++;

   if(placed<InpMinLayers)
   {
      Log("Fewer than minimum layers were accepted. Canceling setup.");
      CancelOurPendingOrders();

      if(CountOurPositions()>0)
      {
         // A market layer may already have filled. Keep it protected rather than
         // force-closing purely because another pending layer was rejected.
         g_hadFill=true;
         SaveState();
      }
      else
      {
         ClearCurrentState(true);
         return false;
      }
   }

   g_executedBasketCount++;

   return true;
}

//-------------------------- Basket management -----------------------
bool GetBasketStats(double &totalVolume,double &avgEntry,int &direction)
{
   totalVolume=0.0;
   avgEntry=0.0;
   direction=0;
   double weighted=0.0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      double vol=PositionGetDouble(POSITION_VOLUME);
      double price=PositionGetDouble(POSITION_PRICE_OPEN);
      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int d=(type==POSITION_TYPE_BUY)?1:-1;

      if(direction==0) direction=d;
      if(direction!=d)
      {
         Log("Mixed-direction basket detected. Protection update skipped.");
         return false;
      }

      totalVolume += vol;
      weighted += vol*price;
   }

   if(totalVolume<=0)
      return false;

   avgEntry=weighted/totalVolume;
   return true;
}

void ApplyBasketProtection()
{
   ManageHybridTrailingPositions("LEGACY");

   if(CountOurPositions()>0)
   {
      g_hadFill=true;
      SaveState();
   }
}

void ReconcileExecutionState(BridgeSignal &s,bool bridgeAvailable)
{
   int positions=CountOurPositions();
   int pending=CountOurPendingOrders();

   if(positions>0)
   {
      g_hadFill=true;
      ApplyBasketProtection();

      // Do not let stale unfilled layers survive forever.
      if(g_signalStarted>0 &&
         TimeCurrent()-g_signalStarted>=InpLayeringExpiryMinutes*60)
      {
         if(pending>0)
         {
            Log("Layering window expired. Canceling remaining pending layers.");
            CancelOurPendingOrders();
         }
      }

      SaveState();
      return;
   }

   // No live positions.
   if(g_hadFill)
   {
      // Basket has finished. Remove any orphan pending layers and prevent re-entry
      // on the same EzyMap signal.
      if(pending>0) CancelOurPendingOrders();
      Log("Basket completed. Signal locked from re-entry.");
      ClearCurrentState(true);
      return;
   }

   if(pending>0)
   {
      bool sameSignal=bridgeAvailable && s.valid && s.signalId==g_signalId;
      bool signalStillUsable=sameSignal &&
                             (s.state==ST_READY || s.state==ST_ACTIVE);

      bool expired=(g_signalStarted>0 &&
                    TimeCurrent()-g_signalStarted>=InpLayeringExpiryMinutes*60);

      if(!signalStillUsable || expired)
      {
         Log(expired?"READY layering expired before fill.":"EzyMap READY invalidated before fill.");
         CancelOurPendingOrders();
         ClearCurrentState(true);
      }
      return;
   }

   // Nothing is open and nothing is pending.
   if(g_signalId>0)
      ClearCurrentState(true);
}



//--------------------------- MT5 EA events ---------------------------
int OnInit()
{
   g_accountUnitDivisor=ResolveAccountUnitDivisor();
   g_pipSize=StrategyPipSize();

   g_reportFromTime=TimeCurrent();
   g_reportWritten=false;
   g_lastAnalyticsDeal=0;
   ArrayResize(g_setupAnalytics,0);
   if(!ConfigureRouting())
   {
      Alert(PRODUCT_NAME+" "+PRODUCT_VERSION+": routing initialization failed.");
      return INIT_FAILED;
   }

   ClearReadySnapshot(g_ready);
   ClearReadySnapshot(g_buyReady);
   ClearReadySnapshot(g_sellReady);
   ZeroMemory(g_active);
   g_active.direction="NONE";

   g_directZeroConf.active=false;
   g_directZeroConf.buyTouchConsumed=false;
   g_directZeroConf.sellTouchConsumed=false;
   g_directZeroConf.direction=0;
   g_directZeroConf.triggerText="";
   g_directZeroConf.triggerCode=EZY_ZC_TRIGGER_NONE;
   g_directZeroConf.triggerPriority=999;
   g_directZeroConf.triggerLo=0.0;
   g_directZeroConf.triggerHi=0.0;
   g_directZeroConf.reclaimTime=0;
   g_directZeroConf.latchedClock=0;
   g_directZeroConf.lastAttemptClock=0;
   g_directZeroConf.lastAttemptTickMs=0;
   g_directZeroConf.attempts=0;
   g_directZeroConfHasPreviousCMP=false;
   g_directZeroConfPreviousCMP=0.0;
   g_zcM5ReclaimCacheBar=0;
   ArrayResize(g_zcM5ReclaimRates,0);
   ArrayResize(g_exitExecutionStates,0);

   // V2.0 S1: create the H1 bias EMA handle once. iMA() per tick is exactly
   // the kind of cost the tick handler must not carry.
   g_h1BiasHandle=INVALID_HANDLE;
   g_h1BiasEMA=0.0;
   g_h1BiasEMAPrev=0.0;
   g_h1BiasClose=0.0;
   g_h1BiasBar=0;
   g_h1BiasDir=0;

   if(InpUseH1BiasFilter)
   {
      g_h1BiasHandle=iMA(_Symbol,PERIOD_H1,MathMax(1,InpH1BiasEMAPeriod),
                         0,MODE_EMA,PRICE_CLOSE);

      if(g_h1BiasHandle==INVALID_HANDLE)
      {
         Log("V2.0 S1 H1 BIAS HANDLE FAILED"+
             " | period="+IntegerToString(MathMax(1,InpH1BiasEMAPeriod))+
             " | error="+IntegerToString(GetLastError())+
             " | bias treated as NEUTRAL (no setups are lost)");
      }
      else
      {
         RefreshH1Bias();
      }
   }

   // V3.190 S3: create the ATR handle once. iATR() per tick is exactly the
   // kind of cost the tick handler must not carry.
   g_geometryATRHandle=INVALID_HANDLE;
   g_geometryATRValue=0.0;
   g_geometryATRBar=0;

   if(InpUseATRGeometry)
   {
      g_geometryATRHandle=iATR(_Symbol,InpATRTimeframe,MathMax(1,InpATRPeriod));

      if(g_geometryATRHandle==INVALID_HANDLE)
      {
         Log("V3.190 S3 ATR HANDLE FAILED"+
             " | timeframe="+EnumToString(InpATRTimeframe)+
             " | period="+IntegerToString(MathMax(1,InpATRPeriod))+
             " | error="+IntegerToString(GetLastError())+
             " | falling back to fixed-pip geometry");
      }
      else
      {
         RefreshGeometryATR();
         Log("V3.190 S3 ATR GEOMETRY ENABLED"+
             " | timeframe="+EnumToString(InpATRTimeframe)+
             " | period="+IntegerToString(MathMax(1,InpATRPeriod))+
             " | stop x"+DoubleToString(InpATRStopMultiplier,2)+
             " (floor "+DoubleToString(InpATRStopFloorPips,1)+
             "p / ceiling "+DoubleToString(InpATRStopCeilingPips,1)+"p)"+
             " | trail x"+DoubleToString(InpATRTrailMultiplier,2)+
             " (floor "+DoubleToString(InpATRTrailFloorPips,1)+"p)"+
             " | arm x"+DoubleToString(InpATRArmMultiplier,2)+
             " | geometry frozen per position at open");
      }
   }

   // V2.1a S2: create the volatility ATR handle once, AFTER the V3.190 S03
   // block above so g_geometryATRHandle is already resolved and can be
   // aliased when the inputs match. iATR() per tick is exactly the kind of
   // cost the tick handler must not carry.
   g_volATRHandle=INVALID_HANDLE;
   g_volATRShared=false;
   g_volATRValue=0.0;
   g_volATRPercentile=-1.0;
   g_volATRBar=0;
   g_volRegimeExtreme=false;

   if(InpUseConfluenceScoring && InpScoreVolatilityRegime)
   {
      if(VolatilityInputsMatchGeometryATR())
      {
         g_volATRHandle=g_geometryATRHandle;
         g_volATRShared=true;

         Log("V2.1a S2 VOLATILITY REGIME ENABLED"+
             " | REUSING the V3.190 S03 geometry ATR handle"+
             " (timeframe and period match)"+
             " | timeframe="+EnumToString(InpVolTimeframe)+
             " | period="+IntegerToString(MathMax(1,InpVolATRPeriod))+
             " | lookback="+IntegerToString(
                (int)MathMax(20.0,MathMin(5000.0,(double)InpVolPercentileLookback)))+
             " bars | bounds="+DoubleToString(InpVolLowPercentile,1)+
             "/"+DoubleToString(InpVolHighPercentile,1)+
             " | hard block="+string(InpHardBlockExtremeVol?"YES":"NO"));
      }
      else
      {
         g_volATRHandle=
            iATR(_Symbol,InpVolTimeframe,MathMax(1,InpVolATRPeriod));

         if(g_volATRHandle==INVALID_HANDLE)
         {
            Log("V2.1a S2 VOLATILITY ATR HANDLE FAILED"+
                " | timeframe="+EnumToString(InpVolTimeframe)+
                " | period="+IntegerToString(MathMax(1,InpVolATRPeriod))+
                " | error="+IntegerToString(GetLastError())+
                " | regime treated as NORMAL and never hard-blocked"+
                " (no setups are lost)");
         }
         else
         {
            Log("V2.1a S2 VOLATILITY REGIME ENABLED"+
                " | OWN ATR handle (inputs differ from the V3.190 S03"+
                " geometry ATR)"+
                " | timeframe="+EnumToString(InpVolTimeframe)+
                " | period="+IntegerToString(MathMax(1,InpVolATRPeriod))+
                " | lookback="+IntegerToString(
                   (int)MathMax(20.0,MathMin(5000.0,(double)InpVolPercentileLookback)))+
                " bars | bounds="+DoubleToString(InpVolLowPercentile,1)+
                "/"+DoubleToString(InpVolHighPercentile,1)+
                " | hard block="+string(InpHardBlockExtremeVol?"YES":"NO"));

            RefreshVolatilityATR();
         }
      }
   }

   // V2.1a S1: reset the gate instrumentation and announce the session map.
   // The announcement exists so the BROKER SERVER-TIME OFFSET can be checked
   // against the operator's own clock before any result is trusted - the
   // three hour inputs are meaningless if the server runs GMT+3 and they
   // were set for GMT.
   g_stdAttempts=0;
   g_stdPassed=0;
   g_zcAttempts=0;
   g_zcPassed=0;

   // V2.2 BTC S06: reset the deployment-gate breakdown counters alongside the
   // confluence counters, so both summaries describe the same run.
   g_spreadRejectStd=0;
   g_spreadRejectZc=0;
   g_spreadRejectOther=0;
   g_envRejectStd=0;
   g_envRejectZc=0;
   g_capacityRejectStd=0;
   g_capacityRejectZc=0;
   g_capacityRejectOther=0;
   g_orderSendStd=0;
   g_orderSendZc=0;
   g_orderSendOther=0;

   // V2.2 BTC S07: (re)arm spread auto-calibration for this run. Sized once
   // here rather than per-tick in SpreadAllowed(). -1.0 means "not yet
   // calibrated" so the very first ticks of every run/optimization pass
   // recalibrate from scratch rather than inheriting a prior pass's cap.
   g_spreadCalCount=0;
   g_spreadCalEffectiveCap=-1.0;
   ArrayResize(g_spreadCalSamples,MathMax(20,InpSpreadCalibrationTicks));

   Log("V2.2 BTC SPREAD GUARD MODE"+
       " | InpAutoCalibrateSpreadCap="+string(InpAutoCalibrateSpreadCap?"ON":"OFF")+
       (InpAutoCalibrateSpreadCap
        ? (" | calibrating over first "+IntegerToString(MathMax(20,InpSpreadCalibrationTicks))+
           " ticks, multiplier="+DoubleToString(MathMax(1.0,InpSpreadCalibrationMultiplier),2)+
           " | ceiling="+(InpSpreadCalibrationCeilingPoints>0
                          ?IntegerToString(InpSpreadCalibrationCeilingPoints)
                          :"uncapped")+
           " | filter INACTIVE (fail-open) until calibration completes - watch for"+
           " V2.2 BTC SPREAD AUTO-CALIBRATION COMPLETE")
        : (" | static InpMaxSpreadPoints="+IntegerToString(InpMaxSpreadPoints)+
           (InpMaxSpreadPoints<=0?" (filter DISABLED)":""))));

   g_v21aSessionCode=V21A_SESSION_UNSET;
   g_v21aSessionHour=-1;
   g_v21aSessionScore=-1.0;
   g_v21aVolPercentile=-1.0;
   g_v21aVolScore=-1.0;
   g_v21aTotalScore=-1.0;
   g_v21aEntryPathCode=V21A_PATHCODE_UNSET;

   if(InpUseConfluenceScoring)
   {
      MqlDateTime initDT;
      TimeToStruct(TimeCurrent(),initDT);
      int initHour=NormalizeHour24(initDT.hour);

      Log("V2.1a CONFLUENCE ENGINE ENABLED"+
          " | threshold="+DoubleToString(InpMinConfluenceScore,3)+
          " | session scoring="+string(InpScoreSession?"ON":"OFF")+
          " | London open="+IntegerToString(NormalizeHour24(InpLondonOpenHour))+
          "h srv | London close="+
          IntegerToString(NormalizeHour24(InpLondonOpenHour+8))+
          "h srv | NY open="+IntegerToString(NormalizeHour24(InpNYOpenHour))+
          "h srv | NY close="+IntegerToString(NormalizeHour24(InpNYCloseHour))+
          "h srv | dead zone="+IntegerToString(V21A_DEAD_ZONE_HOURS)+"h"+
          " | TimeCurrent() now="+
          TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES)+
          " (hour "+IntegerToString(initHour)+
          ", classified "+SessionCodeText(SessionCodeForHour(initHour))+")"+
          " | VERIFY THIS AGAINST YOUR BROKER'S SERVER CLOCK");
   }

   // V2.1b S1/S2: announce the zero-confluence trigger ladder actually in
   // force. Printed UNCONDITIONALLY, in both polarities, because both V2.1b
   // inputs default to the NEW behaviour - the inverse of every earlier
   // stage's convention - so here it is the DEFAULT run that changed the EA
   // and the default run that must not be silent.
   if(!InpZeroConfAllowCurrentMapTier)
      Log("V2.1b: CURRENT_MAP/CURRENT_OUTER tier disabled"+
          " | zero-conf ladder now W1_CLUSTER, W1_SINGLE, D1_H4_CLUSTER,"+
          " D1_SINGLE, LOW_RISK, READY"+
          " | H4_SINGLE (priority 7) still eligible, unchanged by V2.1b"+
          " | CURRENT_OUTER directional override and retire-on-fill"+
          " withdrawn with the tier");
   else
      Log("V2.1b: CURRENT_MAP/CURRENT_OUTER tier RESTORED (A/B control only)"+
          " | V2.1a nine-source ladder in force"+
          " | CURRENT_OUTER keeps its directional override and"+
          " retire-on-fill right");

   if(!InpZeroConfIncludeLevel1)
      Log("V2.1b: W1/D1 triggers restricted to S2/D2 (Level2) only"+
          " | S1/D1 (Level1) excluded from zero-conf ladder"+
          " | H4, LOW_RISK, READY unaffected");
   else
      Log("V2.1b: W1/D1 Level1 (S1/D1) inclusion RESTORED (A/B control only)"+
          " | V2.1a two-level W1/D1 ladder in force");

   // V2.2 BTC S1-S4: announce the resolved instrument profile. Printed
   // UNCONDITIONALLY on every symbol. There is no V2.2 master switch to
   // report - S01 and S02 are unconditional fixes whose gold behaviour is
   // unchanged by construction - so what has to be verifiable from the log
   // is WHICH symbol branch resolved, because that is what silently differed
   // before. Read this line before trusting any BTC result.
   {
      double v22Major=IsGold()?10.0:(IsBTC()?1000.0:0.0);
      double v22Minor=IsGold()?5.0 :(IsBTC()?500.0 :0.0);

      MqlTick v22Tick;
      bool v22TickOK=SymbolInfoTick(_Symbol,v22Tick);
      double v22SpreadPoints=
         (v22TickOK && _Point>0.0)
         ? (v22Tick.ask-v22Tick.bid)/_Point
         : -1.0;

      Log("V2.2 BTC INSTRUMENT PROFILE"+
          " | symbol="+_Symbol+
          " | label="+InstrumentLabel()+
          " | IsGold="+string(IsGold()?"YES":"NO")+
          " | IsBTC="+string(IsBTC()?"YES":"NO")+
          " | strategy pip="+DoubleToString(StrategyPipSize(),_Digits)+
          " price"+
          " | _Point="+DoubleToString(_Point,_Digits)+
          " | digits="+IntegerToString(_Digits)+
          " | contract size="+
          DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_CONTRACT_SIZE),2)+
          " | tick value="+
          DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE),5)+
          " | min lot="+
          DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),2)+
          " | lot step="+
          DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),2));

      // V2.2 BTC S5 support: InpMaxSpreadPoints cannot be chosen blind for a
      // symbol whose point convention is unknown, so the CURRENT spread is
      // printed next to the configured cap at attach time. One reading is a
      // sample, not a distribution - watch it for a few minutes before
      // trusting the cap, exactly as V2.1a S01 asks for the session hour.
      Log("V2.2 BTC SPREAD CHECK"+
          " | observed spread="+
          ((v22SpreadPoints>=0.0)
           ? DoubleToString(v22SpreadPoints,1)+" points ("+
             DoubleToString(v22Tick.ask-v22Tick.bid,_Digits)+" price)"
           : "unavailable at init")+
          " | InpMaxSpreadPoints="+IntegerToString(InpMaxSpreadPoints)+
          ((InpMaxSpreadPoints<=0)?" (filter DISABLED)":"")+
          " | InpDeviationPoints="+IntegerToString(InpDeviationPoints)+
          " | VERIFY THE CAP AGAINST A FEW MINUTES OF LIVE SPREAD");

      Log("V2.2 BTC S1 ROUND-NUMBER GRADING LADDER"+
          " | major="+
          ((v22Major>0.0)?DoubleToString(v22Major,2):"price*0.01 (min 10)")+
          " | minor="+
          ((v22Minor>0.0)?DoubleToString(v22Minor,2):"half of major")+
          " | tolerance="+
          DoubleToString(MathMax(0.0,InpRoundNumberTolerancePips)*
                         MathMax(StrategyPipSize(),_Point),_Digits)+
          " price"+
          " | grading upgrade active="+
          string(InpUseZoneGrading?"YES":"NO")+
          " | pre-V2.2 this test was ALWAYS TRUE on a five-figure symbol");

      Log("V2.2 BTC S2 LIVE CENT PROTECTION PARITY GATE"+
          " | gate now IsGold()||IsBTC() + .SC/_SC/CENT suffix"+
          " | resolved for this chart="+
          string(IsLiveXAUUSDscProtectionChart()?"YES":"NO")+
          " | InpLiveXAUProtectionParity="+
          string(InpLiveXAUProtectionParity?"ON":"OFF")+
          " | input names deliberately unchanged");

      Log("V2.2 BTC S3 LEVEL MIN-DISTANCE FLOORS"+
          " | H4="+DoubleToString(InpH4LevelMinDistancePips,1)+" pips / "+
          DoubleToString(InpH4LevelMinDistancePips*StrategyPipSize(),_Digits)+
          " price"+
          " | D1="+DoubleToString(InpD1LevelMinDistancePips,1)+" pips / "+
          DoubleToString(InpD1LevelMinDistancePips*StrategyPipSize(),_Digits)+
          " price"+
          " | W1="+DoubleToString(InpW1LevelMinDistancePips,1)+" pips / "+
          DoubleToString(InpW1LevelMinDistancePips*StrategyPipSize(),_Digits)+
          " price"+
          " | H1="+DoubleToString(InpH1LevelMinDistancePips,1)+" pips / "+
          DoubleToString(InpH1LevelMinDistancePips*StrategyPipSize(),_Digits)+
          " price"+
          " | defaults 70/120/200/70 reproduce V2.1b exactly");

      if(IsBTC())
         Log("V2.2 BTC CALIBRATION WARNING"+
             " | this binary is STRUCTURALLY portable to BTC, NOT tuned for it"+
             " | no BTC value in EzyMap_V2_2_BTCUSD_RECOMMENDED.set has been"+
             " backtested"+
             " | verify ATR, spread points and contract size from THIS log"+
             " and from the symbol specification before trading live");
   }

   ApplyPremiumChartTheme();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.SetAsyncMode(InpEnforceDirectionalLayerCap ? false : InpUseAsyncMode);

   LoadState();
   EnforceDirectionalLayerCaps();
   EnforceDirectionalLosingPositionCaps();
   EnforceM5ClosedLossCap();

   if(!(bool)MQLInfoInteger(MQL_TESTER) &&
      IsLiveCentAccount() &&
      InpLiveCentParityMode)
   {
      Log("LIVE CENT PARITY ATTACH | MARKET and confidence LIMIT routes are enabled; existing valid EA pending routes are preserved");
   }

   if(!(bool)MQLInfoInteger(MQL_TESTER) &&
      InpResetExecutionStateOnAttach &&
      CountOurPositions()==0 &&
      CountOurPendingOrders()==0)
   {
      ClearCurrentState(false);
      g_lastEntryClosedTime=0;
      ResetCampaignDay(true);
      Log("LIVE ATTACH RESET | stale execution/day state cleared; latest closed M5 is forced through a fresh READY scan");
   }

   // Backtests should start as a clean execution session.
   if((bool)MQLInfoInteger(MQL_TESTER))
   {
      g_signalId=0;
      g_lastDoneSignalId=0;
      g_direction=0;
      g_commonSL=0.0;
      g_riskBudget=0.0;
      g_signalStarted=0;
      g_hadFill=false;
      SaveState();
   }

   g_biasText="NEUTRAL";
   DrawDashboard();
   DrawTradeCard();
   ChartRedraw(0);

   EventSetTimer(1);

   Log("EzyMap Scalp Mastery V3.176 | V3.175 BASE | SYNCHRONIZED LIVE EXIT | STANDARD + ZERO-CONF QUALITY | SL21/TRAIL7 | DAILY RISK LIMIT | ORIGINAL V3.168 LOT SIZING initialized.");
   Log("Engine is integrated: no bridge, resource or iCustom dependency.");
   Log("ACCOUNT SCALE="+
       string(g_accountUnitDivisor>1.0?"CENT":"STANDARD")+
       " | divisor="+DoubleToString(g_accountUnitDivisor,0)+
       " | raw equity="+
       DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
       " | effective equity="+
       DoubleToString(EffectiveAccountEquity(),2)+
       " | minimum effective equity="+DoubleToString(MinimumTradingEquity(),2)+
       " | tester="+string((bool)MQLInfoInteger(MQL_TESTER)?"YES":"NO")+
       " | symbol="+_Symbol+".");

   double rawBalance=AccountInfoDouble(ACCOUNT_BALANCE);
   double effectiveBalance=rawBalance/MathMax(1.0,g_accountUnitDivisor);
   double sizingCapital=LotSizingCapitalUnits();
   double standardRawTarget=InpStandardSetupLotPer100*
                            (sizingCapital/MathMax(1.0,InpBaseEquity));
   Log("BROKER-NATIVE LOT SIZING | balance="+DoubleToString(rawBalance,2)+" "+
       AccountInfoString(ACCOUNT_CURRENCY)+
       " | economic USD-equivalent="+DoubleToString(effectiveBalance,2)+
       " | lot-sizing capital="+DoubleToString(sizingCapital,2)+
       " | source="+string(InpUseBalanceForLotSizing?"BALANCE":"EQUITY")+
       " | mode="+string(InpUseBrokerNativeDepositUnitsForLots?"RAW DEPOSIT UNITS":"EFFECTIVE USD")+
       " | base rule="+DoubleToString(InpStandardSetupLotPer100,2)+
       " lot per "+DoubleToString(InpBaseEquity,0)+" sizing units"+
       " | current STANDARD target="+DoubleToString(standardRawTarget,4)+
       " | broker minimum="+
       DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),VolumeDigits())+".");

   if(IsLiveCentAccount())
      Log("CENT CONTRACT NOTE | V3.081 uses broker-native deposit-unit blocks for lot requests and broker-native OrderCalcProfit/OrderCalcMargin for validation. Example: 603.94 USC requests 0.06 STANDARD cent-symbol lots before safety caps.");
   if(IsLiveCentAccount())
   {
      Log("LIVE CENT EXECUTION PROFILE="+
          string(InpLiveCentBrokerMinimumExecution?"ON":"OFF")+
          " | minimum-lot fallback="+
          string(InpAllowCentMinimumLotFallback?"ON":"OFF")+
          " | raw balance floor="+
          DoubleToString(InpLiveCentRawBalanceFloor,2)+" "+
          AccountInfoString(ACCOUNT_CURRENCY)+
          " | broker candidate lot="+
          DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),VolumeDigits())+
          ". Candidate execution still requires broker-native risk and margin approval.");

      Log("LIVE CENT PARITY="+
          string(InpLiveCentParityMode?"ON":"OFF")+
          " | approval="+
          string(InpLiveCentMarginOnlyMinimumApproval?"30-PIP RISK+MARGIN":"LEGACY RISK+MARGIN")+
          " | max margin use="+DoubleToString(InpLiveCentMaximumMarginUsePct,1)+"%"+
          " | max open positions="+IntegerToString(InpLiveCentMaximumOpenPositions)+
          " | market-only compatibility input="+string(InpLiveCentMarketOnly?"YES (ignored by V3.024)":"NO")+
          " | TP=NONE"+
          " | preset SL="+DoubleToString(InpPresetStopLossPips,0)+" pips"+
          " | trailing="+string(InpEnableTrailingAfterEntry?"ON":"OFF"));

      string environmentReason="";
      Log("LIVE TRADE ENVIRONMENT="+
          string(TradingEnvironmentReady(environmentReason)?"READY":"BLOCKED")+
          (environmentReason==""?"":" | "+environmentReason));
   }

   if(g_accountUnitDivisor>1.0)
      Log("CENT SAFETY: total setup volume is capped by "+
          DoubleToString(InpCentMaxRiskPerSetupPct,2)+
          "% risk, "+DoubleToString(InpCentMaxMarginUsePct,1)+
          "% free-margin use and "+
          DoubleToString(InpCentAbsoluteMaxLots,VolumeDigits())+
          " absolute lots.");
   string selectedAccountProfile=
      (InpAccountScaleMode==EZY_ACCOUNT_STANDARD)
      ? "FORCED STANDARD"
      : (InpAccountScaleMode==EZY_ACCOUNT_CENT
         ? "FORCED CENT"
         : "AUTO");

   string resolvedAccountProfile=
      (g_accountUnitDivisor>1.0)
      ? "CENT"
      : "STANDARD";

   string upperSymbol=Upper(_Symbol);
   bool scSymbol=
      (StringFind(upperSymbol,".SC")>=0 ||
       StringFind(upperSymbol,"_SC")>=0);

   // V2.2 BTC S4: was the literal "REAL XAUUSD.sc ACCOUNT PROFILE". Nothing
   // in this line is gold-specific - it reports the resolved cent/standard
   // divisor for whatever symbol is attached. _Symbol is used here rather
   // than InstrumentLabel() because this line is specifically about the
   // BROKER SYMBOL including its suffix, which means the text is BYTE-
   // IDENTICAL on a real XAUUSD.sc chart: "REAL XAUUSD.sc ACCOUNT PROFILE".
   Log("V3.176 REAL "+_Symbol+" ACCOUNT PROFILE"+
       " | selected="+selectedAccountProfile+
       " | resolved="+resolvedAccountProfile+
       " | symbol="+_Symbol+
       " | .sc suffix="+string(scSymbol?"YES":"NO")+
       " | account currency="+AccountInfoString(ACCOUNT_CURRENCY)+
       " | divisor="+DoubleToString(g_accountUnitDivisor,0)+
       " | broker-native lot blocks="+
       string(InpUseBrokerNativeDepositUnitsForLots?"ON":"OFF")+
       " | force STANDARD with EZY_ACCOUNT_STANDARD"+
       " | force CENT with EZY_ACCOUNT_CENT");

   Log("V3.176 DIRECTIONAL LOSING GOVERNOR"+
       " | maximum losing BUY="+
       IntegerToString(InpMaxLosingPositionsPerDirection)+
       " | maximum losing SELL="+
       IntegerToString(InpMaxLosingPositionsPerDirection)+
       " | BUY/SELL independent=YES"+
       " | floating net=profit+swap"+
       " | block same-direction MARKET/LIMIT/STOP=YES"+
       " | cancel same-direction pending="+
       string(InpCancelPendingAtLosingCap?"YES":"NO")+
       " | force-close existing positions=NO");

   Log("V3.176 CURRENT-M5 CLOSED LOSS GOVERNOR"+
       " | maximum losing closing deals="+
       IntegerToString(InpMaxClosedNegativeEntriesPerM5)+
       " | BUY and SELL combined=YES"+
       " | net=profit+commission+swap+fee"+
       " | block all new entries until next M5=YES"+
       " | cancel all EA pending="+
       string(InpCancelPendingAtM5ClosedLossCap?"YES":"NO")+
       " | force-close existing positions=NO");

   // V2.2 BTC S4: was the literal "V3.176 XAU PROTECTION SCALE" while every
   // value on the line already came from StrategyPipSize(). Prints
   // "V3.176 XAU PROTECTION SCALE" unchanged on any gold symbol.
   Log("V3.176 "+InstrumentLabel()+" PROTECTION SCALE"+
       " | strategy pip="+DoubleToString(StrategyPipSize(),_Digits)+
       " price"+
       " | SL21="+
       DoubleToString(ProtectionPriceDistance(InpPresetStopLossPips),_Digits)+
       " price"+
       " | trail7="+
       DoubleToString(ProtectionPriceDistance(InpTrailingDistancePips),_Digits)+
       " price");

   Log("V3.176 PROTECTION PROFILE VERIFIED"+
       " | strategy pip="+
       DoubleToString(StrategyPipSize(),_Digits)+
       " price"+
       " | preset SL="+
       DoubleToString(InpPresetStopLossPips,0)+
       " pips / "+
       DoubleToString(ProtectionPriceDistance(InpPresetStopLossPips),_Digits)+
       " price"+
       " | trailing="+
       DoubleToString(InpTrailingDistancePips,0)+
       " pips / "+
       DoubleToString(ProtectionPriceDistance(InpTrailingDistancePips),_Digits)+
       " price"+
       " | expected SL=2.30"+
       " | expected trail=0.90");

   MqlTick protectionTick;
   bool protectionTickAvailable=SymbolInfoTick(_Symbol,protectionTick);
   double liveTrailArmDistance=
      protectionTickAvailable
      ? LiveTrailActivationDistance(protectionTick,
           ProtectionPriceDistance(MathMax(0.1,InpTrailArmPips)))
      : ProtectionPriceDistance(MathMax(0.1,InpTrailArmPips));

   // V2.2 BTC S4: was "V3.176 LIVE XAUUSD.sc PROTECTION PARITY" / "live
   // XAUUSD.sc chart=". Since V2.2 BTC S2 widened the gate, this feature can
   // now be active on BTCUSD.sc, and a line that says XAUUSD.sc while
   // reporting YES on a BTC chart is a false statement in the one log line
   // an operator uses to confirm the feature engaged. _Symbol is used so the
   // text is BYTE-IDENTICAL on a real XAUUSD.sc chart.
   Log("V3.176 LIVE "+_Symbol+" PROTECTION PARITY"+
       " | enabled="+string(InpLiveXAUProtectionParity?"YES":"NO")+
       " | live cent-suffix chart="+
       string(IsLiveXAUUSDscProtectionChart()?"YES":"NO")+
       " | account divisor affects lots only=YES"+
       " | strategy pip="+DoubleToString(StrategyPipSize(),_Digits)+" price"+
       " | SL21="+DoubleToString(ProtectionPriceDistance(InpPresetStopLossPips),_Digits)+" price"+
       " | trail7="+DoubleToString(ProtectionPriceDistance(InpTrailingDistancePips),_Digits)+" price"+
       " | live trail arm="+DoubleToString(liveTrailArmDistance,_Digits)+" price"+
       " | warmup="+IntegerToString(InpLiveXAUTrailWarmupSeconds)+" sec"+
       " | historical M1 peak rebuild="+
       string(InpLiveXAUDisableHistoricalPeakRebuild?"DISABLED":"ENABLED")+
       " | spread included="+
       string(InpLiveXAUIncludeSpreadInTrailArm?"YES":"NO"));

   Log("Host/tester period="+EnumToString((ENUM_TIMEFRAMES)_Period)+
       "; internal signal period="+EnumToString(g_entryTF)+".");
   Log("LIVE signal source: V1.1.0 parity = H1 direction -> M15 support -> M5 READY/LIVE.");
   Log("Confidence setup lots per $100: STANDARD="+
       DoubleToString(InpStandardSetupLotPer100,2)+
       " | GOOD="+DoubleToString(InpGoodSetupLotPer100,2)+
       " | QUALITY="+DoubleToString(InpQualitySetupLotPer100,2)+".");
   Log("M5 parallel frequency: "+
       string(InpAllowParallelWaitingReady?"ON":"OFF")+
       " | waiting/direction="+
       IntegerToString(InpMaxWaitingReadyPerDirection)+
       " | total waiting="+
       IntegerToString(InpMaxTotalWaitingReady)+
       " | active slots="+
       IntegerToString(InpMaxPersistentSetups)+".");
   Log("Execution: MARKET/LIMIT/STOP="+
       string(InpUseLimitStopLayers?"ON":"OFF")+
       " | immediate layers="+
       IntegerToString(InpMaxImmediateLayers)+
       " | touch tolerance="+
       DoubleToString(InpEntryTouchTolerancePips,1)+" pips.");
   Log("Precise CMP: chart-price touch="+
       string(InpUseChartPriceForReadyTouch?"ON":"OFF")+
       " | retry="+IntegerToString(InpTouchRetrySeconds)+
       " sec / "+IntegerToString(InpMaxTouchDeployAttempts)+
       " attempts | market fallback="+
       string(InpMarketFallbackOnTouch?"ON":"OFF")+".");
   Log("Confidence lot at touch="+
       string(InpHonorConfidenceLotAtTouch?"EXACT":"RISK-CAPPED")+
       " | $100 base lot continuity enabled down to minimum equity "+
       DoubleToString(MinimumTradingEquity(),0)+".");
   Log("Soft daily volume objective="+
       DoubleToString(InpDailyVolumeTargetMinLots,2)+"-"+
       DoubleToString(InpDailyVolumeTargetMaxLots,2)+
       " lots; signals are never fabricated to hit the target.");
   Log("EXIT PROFILE: TP=NONE | preset SL="+
       DoubleToString(InpPresetStopLossPips,0)+
       " pips | trailing distance="+
       DoubleToString(InpTrailingDistancePips,0)+" pips.");
   Log("PRESET PROTECTION: every route requests "+
       DoubleToString(InpPresetStopLossPips,0)+
       " strategy-pip SL; virtual fallback remains active.");
   Log("ENTRY LOGIC: original V2.009M H4 SNR > M15 overlap > M3 reversal > M5 READY retained; active fallback="+
       string(InpActiveSignalMode?"ON":"OFF")+".");
   Log("Smart execution: MARKET/LIMIT/STOP selection="+
       string(InpUseLimitStopLayers?"ON":"OFF")+".");
   Log("Persistent READY="+string(InpPersistentReadyMode?"ON":"OFF")+
       " | READY lifetime="+IntegerToString(InpReadyExpiryBars)+
       " closed "+g_tfLabel+" candles.");
   Log("Source rules: active signal recovery="+string(InpActiveSignalMode?"ON":"OFF")+
       " | directional M5 fallback="+string(InpAllowDirectionalM5Fallback?"ON":"OFF")+
       " | zone-side gate="+string(InpRequireZoneCorrectSide?"ON":"OFF")+
       " | max retests="+IntegerToString(InpActiveMaxZoneRetests)+
       " | LOCKED confluences: trend="+IntegerToString(TREND_MIN_CONFLUENCES)+
       ", counter="+IntegerToString(COUNTER_MIN_CONFLUENCES)+".");
   Log("V3.081 FREQUENCY PROFILE | dual BUY/SELL READY="+
       string(InpArmBothDirectionsWhenValid?"ON":"OFF")+
       " | one setup/direction/completed M5="+
       string(InpOneSetupPerDirectionPerM5?"ON":"OFF")+
       " | waiting caps BUY/SELL="+
       IntegerToString(InpMaxWaitingReadyPerDirection)+
       " | total="+IntegerToString(InpMaxTotalWaitingReady)+
       " | touch tolerance="+
       DoubleToString(InpEntryTouchTolerancePips,1)+" pips.");
   Log("READY lifetime override="+IntegerToString(InpReadyExpiryBars)+
       " CLOSED M5 candles.");
   Log("Maximum setup risk ceiling: "+DoubleToString(InpMaxRiskPct,2)+"% of equity.");
   if(InpAutoScaleLayerLot)
   {
      Log("AUTO layer sizing ON: "+
          DoubleToString(InpBaseLayerLot,2)+" lot per "+
          DoubleToString(InpBaseEquity,0)+
          " equity, minimum account "+
          DoubleToString(MinimumTradingEquity(),0)+".");
      Log("Current calculated base layer = "+
          DoubleToString(AutoBaseLayerLot(),VolumeDigits())+" lot.");
   }

   if(InpQualityMode)
   {
      Log("Execution quality gate (locked source policy): M5 trend minimum="+
          IntegerToString(TREND_MIN_CONFLUENCES)+
          " conf, counter minimum="+
          IntegerToString(COUNTER_MIN_CONFLUENCES)+
          " conf, max retests="+
          IntegerToString(InpMaxExecutionZoneRetests)+
          ", READY expiry="+IntegerToString(InpReadyExpiryBars)+" M5 bars.");
      Log("V1.2 signal parity="+
          string(InpV120SignalParityMode?"ON":"OFF")+
          ", optional M1 filter="+
          string(InpUseM1ExecutionConfirmation?"ON":"OFF")+
          ", layer range="+
          IntegerToString(InpMinLayers)+"-"+IntegerToString(InpMaxLayers)+".");
   }

   Log("V3.104 STRUCTURE CHECK"+
       " | PersistentReadySetup.requiredConfluences=ACTIVE"+
       " | PersistentReadySetup.zeroConfluenceFallback=ACTIVE"+
       " | ActiveSnapshot restored to V3.081 layout");
   Log("V3.104 ZERO-CONF M5 CAP REMOVED"+
       " | no zero-confluence fill quantity limit per M5"+
       " | pending orders are not cancelled by an M5 fill counter"+
       " | directional and broker safeguards remain active");
   Log("V3.104 EXECUTION RETRY FIX"+
       " | exact broker reason in Journal"+
       " | temporary retcodes only are retried"+
       " | permanent failures stop the affected setup for current M5"+
       " | same-moment throttle="+
       IntegerToString(InpDeploymentRetryIntervalMs)+"ms"+
       " | zero-conf route 1 MARKET required"+
       " | optional pending has no per-M5 fill cap");
   Log("V3.104 FORCE ZERO-CONF EXECUTION"+
       " | stored touch retries until MARKET accepted"+
       " | quality/position recheck bypassed after valid storage"+
       " | retry expiry/attempt limit/current-M5 permanent pause bypassed"+
       " | direct current-map fallback="+
       string(V3104_ZERO_CONF_DIRECT_MAP_FALLBACK?"ON":"OFF")+
       " | hard controls=broker permission/valid volume/margin/market"+
       " + directional layer ceiling");
   Log("V3.176 ZERO-CONFLUENCE QUALITY PROFILE"+
       " | tolerance="+
       DoubleToString(InpZeroConfTouchTolerancePips,1)+" pips"+
       " | cluster tolerance="+
       DoubleToString(InpZeroConfClusterTolerancePips,1)+" pips"+
       " | Bid/Ask/Last envelope="+
       string(InpZeroConfUseBidAskEnvelope?"ON":"OFF")+
       " | tick-path crossing="+
       string(InpZeroConfUseTickPathCrossing?"ON":"OFF")+
       " | liquidity sweep + latest completed M5 reclaim="+
       string(InpZeroConfRequireM5SweepReclaim?"REQUIRED":"OFF")+
       " | sweep may occur in reclaim candle or prior "+
       IntegerToString(InpZeroConfSweepLookbackM5)+" completed M5 bars"+
       " | HIGH-RISK direct trigger=REMOVED"+
       " | LOW-RISK direct trigger="+
       string(V3170_ZERO_CONF_LOW_RISK_TOUCH_RULE?"ON":"OFF")+
       " | USD news block=NOT ADDED");

   Log("V3.176 ZERO-CONF TRIGGER PRIORITY"+
       " | 1 W1+D1/H4 cluster"+
       " | 2 W1 single"+
       " | 3 D1+H4 cluster"+
       " | 4 D1 single"+
       " | 5 LOW-RISK"+
       " | 6 READY"+
       " | 7 H4 single"+
       " | 8 current S1/S2/R1/R2");

   Log("AGGRESSIVE ARM="+
       string(InpAggressiveArmExecution?"ON":"OFF")+
       " | original confidence totals per $100: STANDARD="+
       DoubleToString(InpStandardSetupLotPer100,2)+
       " | GOOD="+DoubleToString(InpGoodSetupLotPer100,2)+
       " | QUALITY="+DoubleToString(InpQualitySetupLotPer100,2)+".");
   Log("Entry routes: STANDARD=Market | GOOD=Market+1 LIMIT | QUALITY=Market+up to 2 LIMITs.");
   Log("LIVE ROUTE PARITY: confidence LIMIT orders are enabled on real cent charts; MARKET failure does not automatically suppress broker-valid LIMIT staging.");
   Log("V3.081 LIMIT GUARD: maximum one EA LIMIT per direction per READY zone; duplicate staging is skipped at planning and submission.");
   Log("DIRECTIONAL LAYER GOVERNOR="+
       string(InpEnforceDirectionalLayerCap?"ON":"OFF")+
       " | max BUY="+IntegerToString(InpMaxActiveLayersPerDirection)+
       " | max SELL="+IntegerToString(InpMaxActiveLayersPerDirection)+
       " | pending reserves slot="+string(InpCountPendingAsReservedLayer?"YES":"NO")+
       " | current BUY open/pending="+
       IntegerToString(CountOurPositionsByDirection(1))+"/"+
       IntegerToString(CountOurPendingOrdersByDirection(1))+
       " | SELL open/pending="+
       IntegerToString(CountOurPositionsByDirection(-1))+"/"+
       IntegerToString(CountOurPendingOrdersByDirection(-1))+".");
   Log("LIVE LIMIT GEOMETRY: broker stop/freeze distance may extend a pending route up to "+
       DoubleToString(InpLiveLimitGeometryExtensionPips,1)+
       " strategy pips beyond the READY edge instead of silently dropping the LIMIT.");
   Log("All MARKET/LIMIT/STOP routes request no TP and a preset 21-pip SL; exact virtual protection remains active when broker geometry differs.");
   Log("7-PIP TRAIL: enabled="+string(InpEnableTrailingAfterEntry?"YES":"NO")+" | activation="+
       string((InpLiveXAUProtectionParity && IsLiveXAUUSDscProtectionChart())
              ?"full trail distance + live spread/cushion after warmup"
              :"configured activation")+
       " | trail distance="+
       DoubleToString(MathMax(0.1,InpTrailingDistancePips),1)+
       " pips | step="+
       DoubleToString(MathMax(0.1,InpTrailingStepPips),1)+" pip(s)"+
       // V2.2 BTC S4: was the literal " | XAU pip size=" in front of a value
       // StrategyPipSize() already resolves per symbol.
       " | "+InstrumentLabel()+" pip size="+
       DoubleToString(StrategyPipSize(),_Digits)+".");
   Log("FIXED 21-PIP LIVE-PARITY SL: broker SL + virtual exact stop | virtual fallback="+
       string(InpUseVirtualTrailFallback?"ON":"OFF")+
       " | reconstruct M1="+
       string(InpReconstructTrailFromM1?"ON":"OFF")+
       " | broker stops="+
       IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL))+
       " points | freeze="+
       IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))+
       " points.");

   Log("V3.176 DAILY RISK LIMIT VERIFIED"+
       " | broker-day start equity="+
       DoubleToString(g_dayStartEquity,2)+
       " | loss percentage="+
       DoubleToString(InpDailyLossStopPct,1)+"%"+
       " | equity floor="+
       DoubleToString(g_dayLossFloor,2)+
       " | forced zero-conf bypass=DISABLED"+
       " | MARKET/LIMIT/STOP bypass=DISABLED"+
       " | close existing positions="+
       string(InpCloseAllAtDailyLossStop?"YES":"NO")+
       " | cancel pending="+
       string(InpCancelPendingAtDailyLossStop?"YES":"NO")+
       " | reset clock=BROKER SERVER DAY");

   Log("V3.176 BASELINE PRESERVATION VERIFIED"+
       " | source=V3.168"+
       " | balance/confidence lot sizing="+
       string(InpUseBalanceForLotSizing?"PRESERVED":"CHANGED")+
       " | preset SL="+
       DoubleToString(InpPresetStopLossPips,0)+" pips"+
       " | trailing="+
       DoubleToString(InpTrailingDistancePips,0)+" pips"+
       " | daily risk="+
       DoubleToString(InpDailyLossStopPct,0)+"%"+
       " | V3.169 equity/previous-lot refinements=NOT INCLUDED");

   Log("V3.176 STANDARD TRIGGER QUALITY VERIFIED"+
       " | original base confidence still controls lot tier=YES"+
       " | MTF cluster qualification bonus="+
       string(InpStandardUseMTFClusterQualification?"+1":"OFF")+
       " | M5 sweep/reclaim qualification bonus="+
       string(InpStandardUseM5SweepReclaimQualification?"+1":"OFF")+
       " | trend requirement="+
       IntegerToString(TREND_MIN_CONFLUENCES)+
       " | countertrend requirement="+
       IntegerToString(COUNTER_MIN_CONFLUENCES)+
       " | cluster tolerance="+
       DoubleToString(InpZeroConfClusterTolerancePips,1)+" pips"+
       " | sweep lookback="+
       IntegerToString(InpZeroConfSweepLookbackM5)+" completed M5"+
       " | V3.168 balance/confidence sizing=PRESERVED");

   Log("V3.176 COMPILE CORRECTION VERIFIED"+
       " | removed obsolete legacy touch-flag references"+
       " | normal entry-side invalidation applies only to non-zero-conf READY"+
       " | zero-conf invalidation uses MTF trigger map + M5 reclaim state"+
       " | trading logic otherwise unchanged from V3.171");

   Log("V3.176 LIVE S2/R2 ZERO-CONF TRIGGER VERIFIED"+
       " | actual live 9-pip proximity required=YES"+
       " | S2/R2 classified separately from S1/R1=YES"+
       " | current S2/R2 allowed despite stale waiting zero-conf READY=YES"+
       " | maximum running positions="+
       IntegerToString(V3104_ZERO_CONF_MAX_OPEN_POSITIONS)+
       " | M5 sweep/reclaim still required="+
       string(InpZeroConfRequireM5SweepReclaim?"YES":"NO")+
       " | accepted outer entry retires stale same-direction waiting setups=YES");

   Log("V3.176 SYNCHRONIZED LIVE EXIT VERIFIED"+
       " | direct base=V3.173"+
       " | one close request per ticket="+
       string(InpSynchronizeExitRequests?"ON":"OFF")+
       " | close lock timeout="+
       IntegerToString(InpExitCloseLockTimeoutMs)+"ms"+
       " | modify minimum interval="+
       IntegerToString(InpExitModifyMinimumIntervalMs)+"ms"+
       " | Invalid stops cooldown="+
       IntegerToString(InpExitInvalidStopsCooldownMs)+"ms"+
       " | extra stop cushion="+
       IntegerToString(InpExitExtraStopCushionPoints)+" points"+
       " | live fill slippage log="+
       string(InpExitLogFillSlippage?"ON":"OFF")+
       " | V3.174 max3-active rule=NOT INCLUDED");

   Log("V3.176 PROTECTION PROFILE VERIFIED"+
       " | direct base=V3.175"+
       " | preset SL="+
       DoubleToString(InpPresetStopLossPips,0)+" pips"+
       " | preset SL price distance="+
       DoubleToString(
          ProtectionPriceDistance(InpPresetStopLossPips),
          _Digits)+
       " | trailing="+
       DoubleToString(InpTrailingDistancePips,0)+" pips"+
       " | trailing price distance="+
       DoubleToString(
          ProtectionPriceDistance(InpTrailingDistancePips),
          _Digits)+
       " | synchronized live exit=PRESERVED"+
       " | zero-conf tolerance remains="+
       DoubleToString(InpZeroConfTouchTolerancePips,0)+" pips");

   ReportJournalPerformance(true,"INIT");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ReportJournalPerformance(true,"FINAL");
   WriteEzyMapBacktestReport();

   Log("EZYMAP SCALP MASTERY V3.081 SUMMARY: READY="+IntegerToString(g_readySignalCount)+
       ", stored="+IntegerToString(g_persistentQueuedCount)+
       ", deployed="+IntegerToString(g_qualityDeployCount)+
       ", LIVE="+IntegerToString(g_persistentTriggeredCount)+
       ", completed="+IntegerToString(g_persistentCompletedCount)+
       ", campaign setups="+IntegerToString(g_campaignSetups)+
       ", day lock="+g_dayLockReason+".");

   // V2.1a S1/S2: rolling gate frequency, split by entry path. Suppressed
   // while the engine is off so a run with no gate evaluations does not
   // print a 0/0 rate.
   LogConfluenceFilterRate();

   // V2.2 BTC S06: which of the non-confluence gates rejected deployments,
   // and how many attempts actually reached the broker.
   LogDeploymentGateBreakdown();

   EventKillTimer();

   // V2.1a S2: release the volatility ATR handle FIRST, and only when it is
   // our own. When g_volATRShared is true the handle is an alias of
   // g_geometryATRHandle and releasing it here would release it twice.
   if(g_volATRHandle!=INVALID_HANDLE && !g_volATRShared)
      IndicatorRelease(g_volATRHandle);

   g_volATRHandle=INVALID_HANDLE;
   g_volATRShared=false;

   // V3.190 S3: release the cached ATR handle.
   if(g_geometryATRHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_geometryATRHandle);
      g_geometryATRHandle=INVALID_HANDLE;
   }

   // V2.0 S1: release the cached H1 bias handle.
   if(g_h1BiasHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_h1BiasHandle);
      g_h1BiasHandle=INVALID_HANDLE;
   }

   SaveState();
   ClearHistoricalMarkers();
   ObjectsDeleteAll(0,PREFIX);
   ChartRedraw(0);
}

void OnTimer()
{
   // Protection must continue even when signal scanning is locked or quiet.
   ManageHybridTrailingPositions("TIMER");
   EnforceDirectionalLayerCaps();
   EnforceDirectionalLosingPositionCaps();
   EnforceM5ClosedLossCap();
   ReportJournalPerformance(false,"UPDATE");

   // LIVE PARITY HEARTBEAT: do not rely exclusively on the chart's OnTick
   // event to capture READY and stage confidence LIMIT routes. This is
   // especially important on suffixed cent symbols and around sparse ticks.
   if(InpPersistentReadyMode)
   {
      CheckCampaignDay();
      if(!g_dayTradingLocked)
      {
         MqlTick liveTick;
         if(SymbolInfoTick(_Symbol,liveTick))
         {
            double heartbeatPrice=(liveTick.bid>0.0)?liveTick.bid:liveTick.last;
            if(heartbeatPrice>0.0)
            {
               g_state=ST_MONITORING;
               CalculateMapAndMaybeReady(heartbeatPrice);
               CapturePersistentReadySignals();
               ProcessDirectZeroConfluenceTriggers();
               ProcessPersistentSetups();
            }
         }
      }
      else
      {
         ProcessPersistentSetups();
         ProcessDirectZeroConfluenceTriggers();
      }

      // Periodic live diagnostics make a missing entry explain itself instead
      // of failing silently. This does not change tester or signal behavior.
      static datetime lastParityStatus=0;
      if(!(bool)MQLInfoInteger(MQL_TESTER) &&
         (lastParityStatus==0 || TimeCurrent()-lastParityStatus>=30))
      {
         lastParityStatus=TimeCurrent();
         int activeReady=0;
         int deployedReady=0;
         for(int i=0;i<ArraySize(g_persistentSetups);i++)
         {
            if(!g_persistentSetups[i].active) continue;
            activeReady++;
            if(g_persistentSetups[i].deployed) deployedReady++;
         }

         string envReason="";
         bool envOK=TradingEnvironmentReady(envReason);
         double capital=LotSizingCapitalUnits();
         double blocks=capital/MathMax(1.0,InpBaseEquity);
         Log("LIVE PARITY STATUS | environment="+string(envOK?"READY":"BLOCKED")+
             (envReason==""?"":" ("+envReason+")")+
             " | READY active="+IntegerToString(activeReady)+
             " deployed="+IntegerToString(deployedReady)+
             " | positions="+IntegerToString(CountOurPositions())+
             " pending="+IntegerToString(CountOurPendingOrders())+
             " | BUY open/pending="+
             IntegerToString(CountOurPositionsByDirection(1))+"/"+
             IntegerToString(CountOurPendingOrdersByDirection(1))+
             " | SELL open/pending="+
             IntegerToString(CountOurPositionsByDirection(-1))+"/"+
             IntegerToString(CountOurPendingOrdersByDirection(-1))+
             " | direction cap="+IntegerToString(InpMaxActiveLayersPerDirection)+
             " | day lock="+string(g_dayTradingLocked?"YES":"NO")+
             (g_dayLockReason==""?"":" ("+g_dayLockReason+")")+
             " | lot targets S/G/Q="+
             DoubleToString(InpStandardSetupLotPer100*blocks,4)+"/"+
             DoubleToString(InpGoodSetupLotPer100*blocks,4)+"/"+
             DoubleToString(InpQualitySetupLotPer100*blocks,4)+
             " | min/step="+
             DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN),VolumeDigits())+"/"+
             DoubleToString(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP),VolumeDigits()));
      }
   }

   // Keep visual layer alive while markets are quiet or history is synchronizing.
   DrawMap(TimeCurrent());
   DrawPersistentReadyZones();
   DrawDashboard();
   DrawTradeCard();
   DrawActualTradeLevelsGold();
   ChartRedraw(0);
}

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double livePrice=tick.bid;
   if(livePrice<=0)
      return;

   // Never let a signal/day lock suspend protection of an existing position.
   ManageHybridTrailingPositions("TICK");
   EnforceDirectionalLosingPositionCaps();
   EnforceM5ClosedLossCap();

   if(InpPersistentReadyMode)
   {
      CheckCampaignDay();

      if(g_dayTradingLocked)
      {
         ProcessPersistentSetups();
         ProcessDirectZeroConfluenceTriggers();

         DrawMap(TimeCurrent());
         DrawPersistentReadyZones();
         DrawDashboard();
         DrawTradeCard();
         DrawActualTradeLevelsGold();
         ChartRedraw(0);
         return;
      }

      // Keep H1/M15/M5 map current; a new READY may form after the prior READY has deployed.
      g_state=ST_MONITORING;
      CalculateMapAndMaybeReady(livePrice);

      // 2) Transfer each newly frozen source READY into execution storage.
      // execution slot. Clearing the engine slot does NOT delete the zone;
      // the persistent queue now owns it.
      CapturePersistentReadySignals();

      // Direct fallback runs after READY capture so it yields to a stored
      // zero-confluence setup and cannot create a duplicate entry.
      ProcessDirectZeroConfluenceTriggers();

      // 3) V2.009A deploys MARKET immediately at arm and stages STOP/LIMIT routes.
      // remains alive for 333 CLOSED M5 candles.
      ProcessPersistentSetups();

      DrawMap(TimeCurrent());
      DrawPersistentReadyZones();
      DrawDashboard();
      DrawTradeCard();
      DrawActualTradeLevelsGold();
      ChartRedraw(0);
      return;
   }

   // ---------------- Legacy single-signal execution ----------------
   ResetResultAfterTTL();

   CalculateMapAndMaybeReady(livePrice);
   ManageReady(livePrice);
   ManageActive(livePrice);

   BridgeSignal signal;
   bool signalAvailable=ReadDirectEzySignal(signal);

   ReconcileExecutionState(signal,signalAvailable);

   bool executionStateOK=InpV120SignalParityMode
                         ? (signalAvailable && signal.state==ST_ACTIVE)
                         : (signalAvailable &&
                            (signal.state==ST_READY || signal.state==ST_ACTIVE));

   if(g_signalId==0 &&
      CountOurPositions()==0 &&
      CountOurPendingOrders()==0 &&
      executionStateOK &&
      signal.signalId!=g_lastDoneSignalId)
   {
      ArmReadySignal(signal);
   }

   ReadDirectEzySignal(signal);
   ReconcileExecutionState(signal,signal.valid);

   DrawMap(TimeCurrent());
   DrawDashboard();
   DrawTradeCard();
   DrawActualTradeLevelsGold();
   ChartRedraw(0);
}

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   HandleExitExecutionTransaction(trans);

   string performanceReason="";
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD && trans.deal>0 &&
      HistoryDealSelect(trans.deal) &&
      HistoryDealGetString(trans.deal,DEAL_SYMBOL)==_Symbol &&
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==InpMagicNumber)
   {
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);

      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
      {
         performanceReason="CLOSE";
      }
      else if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
      {
         performanceReason="ENTRY";
      }
   }

   if(InpPersistentReadyMode)
   {
      if(trans.deal>0)
         RegisterDealAnalytics(trans.deal);

      ManageHybridTrailingPositions("TRADE");
      EnforceDirectionalLayerCaps();
      EnforceDirectionalLosingPositionCaps();
      EnforceM5ClosedLossCap();
      ProcessPersistentSetups();
      DrawActualTradeLevelsGold();
      ChartRedraw(0);

      if(performanceReason!="")
         ReportJournalPerformance(true,performanceReason);
      return;
   }

   if(CountOurPositions()>0)
   {
      g_hadFill=true;
      ManageHybridTrailingPositions("TRADE");
      ApplyBasketProtection();
   }

   EnforceDirectionalLosingPositionCaps();
   EnforceM5ClosedLossCap();

   SaveState();
   DrawActualTradeLevelsGold();
   ChartRedraw(0);

   if(performanceReason!="")
      ReportJournalPerformance(true,performanceReason);
}

//+------------------------------------------------------------------+
