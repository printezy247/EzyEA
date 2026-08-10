//+------------------------------------------------------------------+
//| EzyMap Scalp Mastery V3.126 - Directional 1-M5 Post-Loss Pause   |
//| High-frequency dual READY + live-cent parity + no TP / 30-pip preset SL / 10-pip trailing stop. |
//| H4 SNR -> M15 HIGH RISK -> M3 reversal -> M5 READY -> CMP layers. |
//+------------------------------------------------------------------+
//                                                                    |
//  FRESH V4 BTCUSD (built on top of FRESH V4, see that block below   |
//  for FRESH V4's own history) - explicit request: "do you still     |
//  remember v2.2 btcusd adaptation settings? implement to v3 and v4  |
//  too, i want to see the performance on btcusd, only v3 and v4,     |
//  we'll get to v3.1 and v4.1 later." Identical scope and reasoning  |
//  to sibling FRESH V3 BTCUSD, ported to this file's line numbers    |
//  and its DirectionalPostLossPauseActive() feature, which is        |
//  untouched.                                                        |
//                                                                    |
//  1. PIP SIZE / CENT-ACCOUNT HANDLING - already correct, no change  |
//     needed. StrategyPipSize()'s IsBTC() branch already resolves    |
//     $1.00/point for BTC (independent of the XAUUSD.sc-only         |
//     InpUseXAUUSDscBrokerPointPips toggle, which stays dormant on   |
//     this symbol since it's gated by IsGold()). ResolveAccountUnit  |
//     Divisor()/InpTesterAutoModeIsStandard are already symbol-      |
//     generic.                                                       |
//                                                                    |
//  2. SPREAD-CALIBRATION CEILING DECOUPLED (V2.2 BTCUSD adaptation,  |
//     ported) - added InpSpreadCalibrationCeilingPoints, a dedicated |
//     ceiling for the auto-calibrated cap, independent of the legacy |
//     InpMaxSpreadPoints input that caused a real BTC spread-        |
//     rejection bug on the EzyMap V2.2 BTC line. Default 0 =         |
//     uncapped.                                                      |
//                                                                    |
//  3. InpAutoCalibrateSpreadCap DEFAULTS TRUE HERE, UNLIKE FRESH V4  |
//     (which defaults FALSE to preserve V3.126's real XAUUSD.sc      |
//     trading history of 41.27 lots). This file has never traded     |
//     BTCUSD before, so there is no such benchmark to preserve, and  |
//     BTCUSD.sc's real spread is known to run far wider than         |
//     XAUUSD's, so the guard defaults ON here as protection.         |
//                                                                    |
//  NOT DONE (out of scope per "only v3 and v4" / this exact request):|
//  the stop-loss/trailing/confluence-tolerance inputs were tuned for |
//  XAUUSD's price scale and are UNCHANGED here. With BTC's pip size  |
//  resolving to $1.00, "30 pips" means a $30 stop and "10 pips" a    |
//  $10 trail - almost certainly far too tight for BTCUSD's typical   |
//  intraday range. Watch the first test run closely for the same     |
//  near-instant-stop-out pattern found on the XAUUSD.sc pip-         |
//  tightening regression earlier in this project.                   |
//                                                                    |
//  Distinct magic number (2475142) and order-comment prefix from     |
//  FRESH V4 so both can run side by side.                            |
//                                                                    |
//  Verified: brace/paren/bracket balance, and a full diff against    |
//  FRESH V4 showing only the additions described above. NOT          |
//  verified: compiles in MetaEditor, or real BTCUSD performance -    |
//  that is exactly what this run is for.                             |
//                                                                    |
//  CORRECTION (v4.3, real bug found live): a full-day BTCUSD.sc run   |
//  showed the same "Invalid stops" trailing-SL rejection repeating    |
//  roughly every tick (~45ms, ~20/second) with NO cooldown at all -   |
//  ManageHybridTrailingPositions() had no throttle between modify     |
//  attempts to begin with, unlike the analogous (and already-fixed)   |
//  bug on the EzyMap V2.2 BTC line's exit code. Same risk category as |
//  the confirmed entry-spam incident that cost real capital, applied  |
//  to modifies instead of entries. Identical fix to sibling FRESH V3  |
//  BTCUSD: added a per-ticket consecutiveInvalidStops counter         |
//  (HybridTrailState) that widens the required broker clearance by    |
//  InpTrailBackoffCushionStepPct% of the CURRENT PRICE per            |
//  consecutive failure and exponentially backs off the retry cooldown |
//  (both capped), resetting on success. Threaded through              |
//  FixedTrailSLBrokerValid(), BrokerTrailMinimumDistance() and        |
//  BrokerCompatibleTrailSL(), and a minimum retry interval            |
//  (InpTrailModifyMinimumIntervalMs, 300ms) added where there was     |
//  none before. Inputs: InpTrailModifyMinimumIntervalMs,              |
//  InpTrailBackoffCushionStepPct, InpTrailBackoffMaxSteps,            |
//  InpTrailBackoffCooldownCapMs. Not yet known whether the widened    |
//  cushion actually clears the broker's real minimum, or only slows   |
//  the retry rate - watch the new "(backoff)" log lines on the next   |
//  run.                                                               |
//+------------------------------------------------------------------+
//                                                                    |
//  FRESH V4 - recreated verbatim from the user's own V3.126 file per |
//  explicit instruction: "no alteration needed" to the trading       |
//  logic. Diffed against the original upload to confirm this -       |
//  every entry/exit/scoring/sizing/post-loss-pause rule is           |
//  byte-identical. Same three surgical additions as FRESH V3         |
//  (identical code, same reasoning, ported to this file's line       |
//  numbers):                                                         |
//                                                                    |
//  1. XAUUSD.sc BROKER-POINT PIP CORRECTION - StrategyPipSize() now  |
//     resolves 0.01 (one broker point) instead of a flat 0.10 for    |
//     this symbol on the small set of call sites that use it         |
//     directly: preset SL, trailing distance/activation, live-limit  |
//     geometry extension, zone-duplicate tolerance, H1 EMA neutral   |
//     band. Inputs: InpUseXAUUSDscBrokerPointPips (default TRUE),    |
//     InpXAUUSDscStrategyPipPrice, InpStandardXAUUSDStrategyPipPrice,|
//     InpPreserveLegacyPipDistances (default TRUE - see correction   |
//     #2 below).                                                     |
//                                                                    |
//  2. AUTO-CALIBRATING SPREAD GUARD - SpreadAllowed() now measures   |
//     this symbol's own real spread instead of relying on a static,  |
//     disabled-by-default cap. Inputs: InpAutoCalibrateSpreadCap     |
//     (default TRUE), InpSpreadCalibrationTicks,                     |
//     InpSpreadCalibrationMultiplier.                                |
//                                                                    |
//  3. GLOBAL ORDER-RATE THROTTLE - a single shared floor across this |
//     file's three order-send paths (SubmitDirectZeroConfMarket,     |
//     SubmitPersistentLayerOrder, PlaceOneLayer), each of which      |
//     previously retried independently with no aggregate rate cap.   |
//     Input: InpMinMsBetweenOrderRequests (default 250ms).           |
//                                                                    |
//  Verified: brace/paren/bracket balance, and a full diff against    |
//  the original upload showing only the additions above plus the    |
//  two function-body swaps (StrategyPipSize, SpreadAllowed) - no     |
//  other line touched. NOT verified: compiles in MetaEditor - no     |
//  MQL5 toolchain in this environment.                                |
//                                                                    |
//  CORRECTIONS (same bugs found and fixed on the sibling FRESH V3    |
//  file from a same-day test: original V3.116 = 94.50 lots real,     |
//  first FRESH V3 = 6.18 lots - a 15x gap):                          |
//   - InpAutoCalibrateSpreadCap default TRUE -> FALSE. The original   |
//     ran with NO spread gate at all (InpMaxSpreadPoints=0 is a       |
//     genuine off switch); defaulting the new gate ON was an active  |
//     behaviour change, not just a calculation fix. Mechanism stays  |
//     correct and available, just off by default now.                |
//   - InpMinMsBetweenOrderRequests 250ms -> 50ms. Three order-send    |
//     paths, one active state each, worst case ~6 requests/second -  |
//     250ms was tighter than needed.                                 |
//   - TOTAL ENTRY LOTS report fix: entries whose comment isn't the   |
//     persistent-setup path's "EZR..." format (direct zero-conf,     |
//     legacy/aggressive-arm layers) were silently excluded from this |
//     report's totals. They now fall back to being grouped by their  |
//     own position ID instead of being dropped.                      |
//   - "ZERO-CONFLUENCE FORCE PASS ... BYPASSED" is ORIGINAL,          |
//     UNALTERED behaviour: V3126_FORCE_ZERO_CONF_MARKET_EXECUTION=    |
//     true is a hardcoded const in the file the user uploaded, not   |
//     introduced by this port. Left exactly as-is per "no alteration".|
//                                                                      |
//  CORRECTION #2 (found from a same-day test after the above fixes:   |
//  original V3.126 = 41.27 lots real/1013.24 final balance, refined   |
//  FRESH V4 = 5.84 lots/1000.36 final balance - gap narrowed but      |
//  still large, worse than sibling FRESH V3's remaining gap):         |
//   - Traced every consumer of pip size. CalculateMapAndMaybeReady()  |
//     resets the CACHED g_pipSize global to a hardcoded flat 0.10 on  |
//     every tick (ORIGINAL code, present in the user's own upload,    |
//     not touched by this port) - so confluence tolerance and         |
//     everything else that reads g_pipSize was NEVER actually         |
//     affected by fix #1. The earlier version of this header claimed  |
//     confluence tolerance shrank 10x; that was wrong and is          |
//     corrected here.                                                 |
//   - Fix #1 only ever reached the handful of sites calling            |
//     StrategyPipSize() directly: preset stop-loss, trailing          |
//     distance/activation, live-limit-geometry extension, zone-       |
//     duplicate tolerance, H1 EMA neutral band. Tightening SL/        |
//     trailing 10x (e.g. a 20-pip stop: $2.00 -> $0.20) made most     |
//     positions stop out almost immediately on ordinary gold          |
//     noise/spread - and THIS file's DirectionalPostLossPauseActive() |
//     re-arms a per-direction entry pause on every one of those       |
//     losses, very plausibly compounding into a harsher volume        |
//     cutoff than the sibling FRESH V3 file (no such pause mechanic   |
//     there), matching the larger 7x gap observed here.               |
//   - Added InpPreserveLegacyPipDistances (default TRUE, per explicit |
//     instruction to match the original's real-dollar volume while    |
//     keeping the .sc broker-point detection inputs available/        |
//     documented for later use). StrategyPipSize() now returns the    |
//     same numeric value on XAUUSD.sc as the standard branch when     |
//     this is true, so every SL/trailing/tolerance distance is        |
//     byte-identical to the original file's real-world behaviour      |
//     again. Set to FALSE later if genuine broker-point-tight         |
//     distances are ever wanted instead.                              |
//+------------------------------------------------------------------+
#property copyright "EzyMap"
#property version   "4.4"

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
input ulong  InpMagicNumber              = 2475142; // distinct from FRESH V4's 2475126 so both can run side by side

// FRESH V4 stability/correctness pass: XAUUSD.sc broker-point pip
// correction, ported from the later EzyMap V3.140 file's own fix for this.
// StrategyPipSize() below returned a flat 0.10 for every gold symbol,
// cent-suffixed or not. On the user's .sc broker, one displayed gold pip is
// actually ONE BROKER POINT (0.01 price), not ten (0.10) - the standard XAU
// convention only holds on a non-cent-suffixed symbol. This is a
// calculation correction, not a strategy change - the number of pips each
// input asks for is unchanged, only what one pip is worth in price on THIS
// symbol is fixed.
//
// CORRECTION (found tracing the same-day 41.27 -> 5.84 lot regression):
// this file's own CalculateMapAndMaybeReady() resets the CACHED g_pipSize
// variable to a hardcoded flat 0.10 on every tick (line ~3830s, original,
// unaltered code) - so confluence tolerance and every other distance that
// reads g_pipSize was NEVER actually affected by this fix; the earlier
// FRESH V4 header's claim that confluence tolerance shrank 10x was wrong.
// The fix only ever reached the handful of call sites that call
// StrategyPipSize() DIRECTLY: preset stop-loss, trailing distance/
// activation, live-limit-geometry extension, zone-duplicate tolerance, and
// the H1 EMA neutral band. Tightening the STOP/TRAIL distances 10x (e.g. a
// 20-pip stop: $2.00 -> $0.20) made most positions stop out almost
// immediately on ordinary gold noise/spread - and this file's
// DirectionalPostLossPauseActive() re-arms a per-direction entry pause on
// every one of those losses, which very plausibly compounded into a much
// harsher, more direct volume cutoff here than on the sibling FRESH V3
// file (no such pause mechanic there), matching the larger 7x gap.
//
// InpPreserveLegacyPipDistances (new, default TRUE per explicit
// instruction to match the original's real-dollar SL/trailing/tolerance
// distances) makes StrategyPipSize() return the same numeric value for
// XAUUSD.sc as the standard branch, so every one of those distances is
// byte-identical to the original file's real-world behaviour again. The
// broker-point/.sc detection inputs above stay in place, documented and
// available, in case genuine broker-point-tight distances are ever wanted
// later - just set this to false.
input bool   InpUseXAUUSDscBrokerPointPips      = true;
input double InpXAUUSDscStrategyPipPrice        = 0.01;
input double InpStandardXAUUSDStrategyPipPrice  = 0.10;
input bool   InpPreserveLegacyPipDistances      = true;

// Cent-account interpretation and hard exposure guards. AUTO detects
// common cent currency/server labels; live .sc suffix detection is optional.
// AUTO tester mode defaults to STANDARD to prevent false division by 100.
// V2.009W uses BROKER-NATIVE deposit units for lot scaling by default:
// 603.94 USC at 0.01 lot per 100 units requests 0.06 cent-account lots.
// Monetary risk and margin remain broker-native via OrderCalcProfit/Margin.
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
// Requested aggressive campaign risk band: 25%-47% per setup.
input double InpMaxRiskPct               = 47.0;
input double InpRiskPct_1Conf            = 25.00;
input double InpRiskPct_2Conf            = 25.00;
input double InpRiskPct_3Conf            = 25.00;
input double InpRiskPct_4Conf            = 33.00;
input double InpRiskPct_5Plus            = 42.00;

// SL distance modifies the confidence allocation, clamped to 25%-47%.
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

// Hard monetary-risk guard. Confidence lots are reduced if the frozen
// Entry->SL distance would otherwise exceed this percentage of equity.
input double InpConfidenceLotRiskGuardPct  = 47.0;

// Soft daily-volume objective for reporting only.
// The EA never invents a setup merely to reach these numbers.
input double InpDailyVolumeTargetMinLots   = 0.50;
input double InpDailyVolumeTargetMaxLots   = 1.50;

// V2.008 PARALLEL M5 FREQUENCY.
// Several valid M5 READY setups may wait simultaneously.
// Frequency increases by creating more independent setups,
// NOT by increasing the volume of any one setup.
input bool   InpAllowParallelWaitingReady   = true;
input int    InpMaxWaitingReadyPerDirection = 8;
input int    InpMaxTotalWaitingReady        = 16;
// V3.081 frequency governor: arm BUY and SELL independently when both are
// valid, but freeze at most one new setup per direction for each completed M5.
// This raises opportunity count without duplicating the same zone every tick.
input bool   InpArmBothDirectionsWhenValid  = true;
input bool   InpOneSetupPerDirectionPerM5   = true;

// Normal confluence-qualified entry tolerance.
// Zero-confluence fallbacks use their separate, wider profile below.
input double InpEntryTouchTolerancePips     = 5.0;

// V3.099 sensitive zero-confluence touch profile.
// The detector checks CMP, Bid, Ask, Last and the tick path from the previous
// observation, preventing fast movement or spread geometry from skipping a
// READY, HIGH-RISK, S1 or R1 trigger.
input double InpZeroConfTouchTolerancePips  = 12.0;
input bool   InpZeroConfUseBidAskEnvelope   = true;
input bool   InpZeroConfUseTickPathCrossing = true;
input int    InpZeroConfTouchRetrySeconds   = 30;
input int    InpZeroConfMaxDeployAttempts   = 15;

// V2.009 PRECISE CMP EXECUTION.
// READY touch is detected from the symbol's CHART price (Bid or Last),
// matching what is visibly touching the rectangle. Actual BUY/SELL execution
// still uses the broker's executable Ask/Bid prices.
input bool   InpUseChartPriceForReadyTouch  = true;

// Once a legitimate chart CMP touch occurs, keep a short execution latch so
// a transient broker rejection / spread jump does not lose the signal.
input int    InpTouchRetrySeconds           = 15;
input int    InpMaxTouchDeployAttempts      = 7;

// V3.126 prevents OnTick/OnTimer from submitting the same touched setup
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
input int    InpMaxActiveLayersPerDirection      = 13;
input bool   InpCountPendingAsReservedLayer      = true;
input bool   InpTrimExcessPendingToLayerCap      = true;

// V3.124 current floating-loss governor.
// BUY and SELL are counted independently. At two currently losing EA
// positions in one direction, new entries and pending exposure for that
// direction are blocked. Existing open positions remain managed normally.
input bool   InpEnforceDirectionalLosingCap      = true;
input int    InpMaxLosingPositionsPerDirection   = 2;
input bool   InpCancelPendingAtLosingCap         = true;

// V3.124 current-M5 closed-loss governor.
// Count EA closing deals completed during the current M5 whose realised
// net P/L (profit + commission + swap + fee) is negative. BUY and SELL are
// combined. At one losing close, all new entries are blocked until next M5.
input bool   InpEnforceM5ClosedLossCap             = true;
input int    InpMaxClosedNegativeEntriesPerM5      = 1;
input bool   InpCancelPendingAtM5ClosedLossCap      = true;

// V3.126 direction-specific post-loss pause.
// When a BUY position closes with negative net P/L, BUY is paused for the next
// complete M5 candle while SELL remains eligible. A losing SELL close does the
// symmetric action. The existing current-M5 closed-loss cap still controls the
// candle in which the loss closes.
input bool   InpEnableDirectionalPostLossPause       = true;
input int    InpDirectionalPostLossPauseM5Candles    = 1;
input bool   InpCancelPendingDuringDirectionalPause  = true;
input double InpAggressiveLimitDepthPct       = 25.0;
// Real brokers may enforce a larger pending-order distance than Strategy Tester.
// Permit a live LIMIT route to sit just beyond the READY edge when that is the
// nearest broker-valid price. On XAU, 20 strategy pips = 2.00 price.
input double InpLiveLimitGeometryExtensionPips = 20.0;

// Execution controls.
input int    InpMaxSpreadPoints          = 0;     // 0 = filter disabled
// FRESH V4 stability pass: SpreadAllowed() below used to be a plain
// static cap (disabled by default, InpMaxSpreadPoints=0) - no protection
// at all against a spread blowout unless someone hand-guesses a point
// value for this specific broker/symbol first. Ported the auto-
// calibrating spread guard proven on the EzyMap V2.2 BTC line: measures
// THIS symbol's own real spread for InpSpreadCalibrationTicks ticks after
// attach (filter INACTIVE / fail-open while collecting), then enforces
// median(observed) * InpSpreadCalibrationMultiplier.
//
// CORRECTION (on the sibling XAUUSD.sc file, not this one): this defaulted
// TRUE in the first delivery, and a same-day test came back trading 6.18
// lots against the original V3.116's real 94.50 lots on that date - a 15x
// gap, because that original ran with NO spread gate active at all. THIS
// file has no such "original real-money benchmark" to preserve on
// BTCUSD - it has never traded this symbol before - so the same reasoning
// does not apply here. BTCUSD.sc spreads are known to run far wider than
// XAUUSD's (Vantage Markets reference: roughly $15-17 per unit, ~1500-1700
// points on a 2-digit-quoted symbol) and can blow out further during
// volatility, so this BTCUSD variant defaults the guard ON - unlike its
// XAUUSD.sc sibling - specifically to protect against that.
input bool   InpAutoCalibrateSpreadCap      = true;
input int    InpSpreadCalibrationTicks      = 100;
input double InpSpreadCalibrationMultiplier = 3.0;

// V2.2 BTCUSD ADAPTATION (ported): a stale/legacy InpMaxSpreadPoints value
// used to double as the calibration ceiling, which could silently clamp
// the calibrated median*multiplier straight back down to a number far
// below BTCUSD's real spread - confirmed on the EzyMap V2.2 BTC line,
// where a leftover InpMaxSpreadPoints=120 (a XAUUSD-scale default) capped
// a genuinely-measured ~1500-1700 point BTC spread down to 120, making
// SpreadAllowed() reject almost everything. Decoupled here from the start:
// this dedicated ceiling is the ONLY thing that can clamp the calibrated
// cap. 0 = uncapped (trust median*multiplier). InpMaxSpreadPoints keeps
// its original meaning in the static (non-calibrating) branch only.
input int    InpSpreadCalibrationCeilingPoints = 0;

// FRESH V4 stability pass: this file's three order-send paths retry
// independently on their own InpDeploymentRetryIntervalMs (default 500ms)
// timer with no shared cap on aggregate REQUEST RATE across all three. A
// different EzyMap build with a much more aggressive version of this same
// pattern (a 100ms retry across up to 64 parallel signal states) triggered
// a real broker "server problem" alert from entry spamming, confirmed by
// the user, and cost real capital.
//
// CORRECTION: this file has only ONE active state per path (not 64), so
// three independent 500ms timers can produce at most ~6 requests/second
// in the worst case - nowhere near the volume that caused the actual
// incident. 250ms was tighter than necessary and could itself delay a
// legitimate send from one path because a different, unrelated path just
// sent moments earlier. Loosened to 50ms - low enough to never bind under
// this file's real worst-case cadence, while still capping any future
// pathological case well below spam levels.
input int    InpMinMsBetweenOrderRequests = 50;

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
const bool   V3126_ZERO_CONFLUENCE_TOUCH_RULE = true;
const int    V3126_ZERO_CONF_MAX_OPEN_POSITIONS = 1;

// Additional V3.102 zero-confluence trigger.
// CMP touching the stored directional HIGH-RISK zone may deploy immediately,
// even when CMP has not yet reached the narrower READY entry rectangle.
const bool   V3126_ZERO_CONF_HIGH_RISK_TOUCH_RULE = true;

// Additional V3.102 zero-confluence level trigger.
// BUY fallback stores the current S1 level; SELL fallback stores current R1.
// CMP touch of stored S1 -> BUY routing. Stored R1 -> SELL routing.
const bool   V3126_ZERO_CONF_S1_R1_TOUCH_RULE = true;

// V3.100 adds the outer support/resistance level trigger.
// BUY fallback stores S2; SELL fallback stores R2.
// CMP touch of stored S2 -> BUY routing. Stored R2 -> SELL routing.
const bool   V3126_ZERO_CONF_S2_R2_TOUCH_RULE = true;

// V3.126 has no zero-confluence fill limit per M5 candle.
// Once a zero-confluence trigger touches, execution remains latched until its
// MARKET route is accepted. Quality rechecks, retry expiry, attempt limits
// and current-M5 permanent-failure pauses no longer cancel that entry.
const bool   V3126_FORCE_ZERO_CONF_MARKET_EXECUTION = true;
const bool   V3126_ZERO_CONF_RETRY_UNTIL_FILLED = true;

// When no stored zero-confluence READY exists for a direction, the current
// map itself may create a direct STANDARD MARKET entry:
// READY / HIGH-RISK / S1 / S2 -> BUY.
// READY / HIGH-RISK / R1 / R2 -> SELL.
const bool   V3126_ZERO_CONF_DIRECT_MAP_FALLBACK = true;

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
input double InpDailyLossStopPct               = 47.0;
input bool   InpCloseAllAtDailyTarget          = true;

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
// rejects that SL with the opening request, the route is retried without SL
// and the exact virtual stop protects it immediately after fill. No TP is used.
input double InpPresetStopLossPips          = 30.0;
input bool   InpRetryEntryWithoutSLOnReject = true;

// V3.126 broker/virtual protection with no TP, a 30-pip preset SL and a 10-pip trailing stop.
// A preset 30-pip SL is requested with every entry. No TP is submitted. The exact virtual
// SL remains active when broker stop-distance rules require adjustment.
// The initial exact virtual stop is InpPresetStopLossPips from entry, and the EA
// immediately attempts to install the closest broker-compatible SL.
// BUY  stop = best Bid - InpTrailingDistancePips * strategy pip
// SELL stop = best Ask + InpTrailingDistancePips * strategy pip
// On XAU, one strategy pip is 0.10 price; therefore SL30 is 3.00 price and trail10 is 1.00 price.
input bool   InpUseFixedPipTrail               = true;
input bool   InpEnableTrailingAfterEntry        = true;  // trail after first favourable broker point
input double InpTrailingActivationPips         = 0.0;
input double InpTrailingDistancePips           = 10.0;
input double InpTrailingStepPips               = 1.0;
input bool   InpUseVirtualTrailFallback        = true;
input bool   InpReconstructTrailFromM1         = true;
input int    InpVirtualTrailCloseDeviationPts  = 30;
input int    InpTrailBrokerCushionPoints       = 2;

// TRAIL MODIFY BACKOFF - added after a live BTCUSD.sc run showed the broker
// rejecting the same trailing-SL modify with "Invalid stops" on repeat,
// roughly every tick (~45ms in a fast BTC feed), continuously, because
// ManageHybridTrailingPositions() has NO cooldown between modify attempts at
// all - unlike the V2.2 BTC line's exit code, which at least had a fixed
// interval before this same class of bug was found there too. Same risk
// category as the confirmed entry-spam incident that cost real capital,
// just applied to modifies and even less throttled than that incident's
// 100ms retry. InpTrailModifyMinimumIntervalMs adds the missing floor;
// InpTrailBackoffCushionStepPct/MaxSteps/CooldownCapMs escalate on repeated
// rejection exactly like the V2.2 BTC fix - percentage of current price,
// not a fixed point count, so it scales correctly on BTC's $65,000 print.
input int    InpTrailModifyMinimumIntervalMs   = 300;
input double InpTrailBackoffCushionStepPct     = 0.02;
input int    InpTrailBackoffMaxSteps           = 8;
input int    InpTrailBackoffCooldownCapMs      = 15000;

// ZERO STOPS-LEVEL FALLBACK - added after a live BTCUSD.sc run's log showed
// "stopLevel=0 | freezeLevel=0" logged alongside every single INVALID_STOPS
// rejection. Both SYMBOL_TRADE_STOPS_LEVEL and SYMBOL_TRADE_FREEZE_LEVEL
// reporting 0 does NOT reliably mean "no minimum distance" on every broker -
// some crypto CFD brokers enforce a real, larger minimum server-side while
// reporting 0 via these two API fields, which is exactly what the repeated
// first-attempt failures (before InpTrailBackoffCushionStepPct's escalation
// had a chance to widen anything) point to. When both report zero, this
// adds a percentage-of-price floor to the required clearance from the
// FIRST attempt, instead of only widening after failures accumulate.
input double InpZeroStopsLevelFallbackPct = 0.05;

// VIRTUAL TRAIL CLOSE BACKOFF - added after a live BTCUSD.sc run's log
// showed 547 combined FROZEN(10029)/POSITION_CLOSED(10036) failures on
// "HYBRID VIRTUAL TRAIL CLOSE FAILED", the single largest failure category
// in the log, with the same tickets failing repeatedly back-to-back.
// ClosePositionAtVirtualTrail() had NO cooldown or retry-state at all -
// unlike the SL-install/trailing-update paths above, it retried on every
// single tick with no throttle, hammering the broker with close requests
// for a position that was either temporarily FROZEN (server-side
// processing/freeze-level lock) or had ALREADY closed by other means
// (broker-side stop-out, or a previous request's fill racing ahead of this
// one) - the same request-spam risk category as the confirmed entry-spam
// incident that cost real capital, just on the exit side. Reuses
// InpTrailModifyMinimumIntervalMs/InpTrailBackoffCooldownCapMs above for
// its retry cadence rather than adding yet more inputs for the same
// underlying policy.

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
input string InpCSVReportPrefix                = "EzyMap_Scalp_Mastery_V3_126_Directional_Next_M5_Loss_Pause_Report";

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
#define PRODUCT_VERSION "V4.2 FRESH BTCUSD (V2.2 spread-guard adaptation) • V3.126 • V3.125 BASE • DIRECTIONAL NEXT-M5 LOSS PAUSE • M5 EQUAL-SCORE"
#define EMA_LEN 13
#define TREND_MIN_CONFLUENCES 2
#define COUNTER_MIN_CONFLUENCES 3
#define MAX_ZONE_RETESTS 8
#define CONFIRM_WINDOW 12
#define MIN_RR 0.60
#define MAX_RR 2.50
#define BE_ARM_PROGRESS 0.40

string PREFIX="EZYSMV3126BTCV42_"; // distinct from FRESH V4's prefix so order comments/history never collide

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

   // Frozen directional levels captured when the setup is stored:
   // BUY uses S1 and S2; SELL uses R1 and R2.
   double zeroConfluenceLevelPrice;
   double zeroConfluenceOuterLevelPrice;

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
};

struct DirectZeroConfState
{
   bool active;
   bool buyTouchConsumed;
   bool sellTouchConsumed;
   int direction;
   string triggerText;
   double triggerLo;
   double triggerHi;
   datetime latchedClock;
   datetime lastAttemptClock;
   ulong lastAttemptTickMs;
   int attempts;
};

struct SetupAnalytics
{
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

   // TRAIL MODIFY BACKOFF: consecutive rejected SL modifies for this
   // ticket (initial preset install or trailing update, either counts -
   // both write the same broker SL). Widens the required broker clearance
   // and the retry cooldown on every failure; reset to 0 the instant a
   // modify is accepted. See InpTrailBackoffCushionStepPct.
   int      consecutiveInvalidStops;
   ulong    modifyCooldownUntilMs;

   // VIRTUAL TRAIL CLOSE BACKOFF: separate from the modify counters above -
   // a close attempt and a modify attempt are different operations on the
   // same ticket, and coupling their retry state would let a recent modify
   // failure delay a legitimate close (or vice versa). Consecutive
   // rejected PositionClose() attempts at the virtual trail; reset to 0 on
   // acceptance OR when the broker reports the position is already closed
   // (POSITION_CLOSED means the goal is already achieved, not a failure).
   int      closeConsecutiveFailures;
   ulong    closeCooldownUntilMs;
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

DirectZeroConfState g_directZeroConf;
bool   g_directZeroConfHasPreviousCMP=false;
double g_directZeroConfPreviousCMP=0.0;

// FRESH V4: spread auto-calibration state (see SpreadAllowed()).
// g_spreadCalEffectiveCap<0.0 means "still collecting samples, filter
// inactive (fail open)". Array sized once in OnInit.
double g_spreadCalSamples[];
int    g_spreadCalCount=0;
double g_spreadCalEffectiveCap=-1.0;

// FRESH V4: single global order-rate throttle covering every order-send
// call site in this file. See OrderRequestThrottleOK() for the full
// reasoning - added after a different EzyMap build's unthrottled 100ms
// retry-until-filled loop triggered a real broker "server problem" alert
// from entry spamming, confirmed by the user, and cost real capital.
double g_lastOrderRequestMs=0;

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

// Direction-specific next-M5 pause windows after a realised losing close.
datetime g_buyPostLossPauseStart=0;
datetime g_buyPostLossPauseEnd=0;
datetime g_sellPostLossPauseStart=0;
datetime g_sellPostLossPauseEnd=0;

bool HasUntriggeredPersistentReady(int direction);
int CountWaitingReadyDirection(int direction);
int CountTotalWaitingReady();
double ReadyTouchCMP(MqlTick &tick);
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
bool ResolveDirectZeroConfTrigger(int direction,double observedLo,double observedHi,
                                  double tolerance,string &triggerText,
                                  double &triggerLo,double &triggerHi);
bool DirectZeroConfRetryElapsed();
int CountOurLosingPositionsByDirection(int direction);
bool DirectionalLosingPositionCapacityAvailable(int direction,string context);
void CancelPendingOrdersAtDirectionalLosingCap(int direction);
void EnforceDirectionalLosingPositionCaps();
int CountOurClosedNegativeEntriesCurrentM5();
bool M5ClosedLossCapacityAvailable(string context);
void CancelAllPendingAtM5ClosedLossCap();
void EnforceM5ClosedLossCap();
bool RegisterDirectionalPostLossPauseFromDeal(ulong dealTicket,bool logEvent);
void RebuildDirectionalPostLossPauseFromHistory();
bool DirectionalPostLossPauseActive(int direction,string context);
void CancelPendingForDirectionalPostLossPause(int direction);
void EnforceDirectionalPostLossPause();
bool SubmitDirectZeroConfMarket();
void ProcessDirectZeroConfluenceTriggers();
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
double TrailBackoffCushionPrice(double referencePrice,int backoffSteps);
double BrokerTrailMinimumDistance(double current,int backoffSteps);
double BrokerCompatibleTrailSL(int direction,double current,double virtualStop,int backoffSteps);
double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel);
bool ClosePositionAtVirtualTrail(int stateIndex,ulong ticket,string context,double current,double stop,double peak);
void PruneHybridTrailStates();
void ResetDailyFrequencyCounter();
bool PersistentQualityPass(PersistentReadySetup &setup,string &reason);
bool DeployPersistentSetup(int index);
bool DeployAggressiveArmSetup(int index);
void DeletePersistentObjects(long id);
void ResetCampaignDay(bool forceReset);
void CheckCampaignDay();
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

   if(InpUseBrokerNativeDepositUnitsForLots)
      return MathMax(0.0,raw);

   return MathMax(0.0,raw/MathMax(1.0,g_accountUnitDivisor));
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

// FRESH V4: the same cent-suffix check ResolveAccountUnitDivisor() already
// uses elsewhere in this file to decide the account is denominated in
// cents - reused here for the pip-price correction, not duplicated logic.
bool IsCentSuffixSymbol()
{
   string s=Upper(_Symbol);
   return (StringFind(s,".SC")>=0 || StringFind(s,"_SC")>=0 ||
           StringFind(s,"CENT")>=0);
}

// FRESH V4: XAUUSD.sc broker-point pip correction (see the input block
// above for the full reasoning). Every other symbol/branch is unchanged.
// InpPreserveLegacyPipDistances (default true) keeps the resolved value
// identical to the original file's flat 0.10 so every SL/trailing/
// tolerance distance that multiplies by this function matches the
// original's real-dollar behaviour exactly.
double StrategyPipSize()
{
   if(IsGold())
   {
      if(InpUseXAUUSDscBrokerPointPips && IsCentSuffixSymbol() &&
         !InpPreserveLegacyPipDistances)
         return MathMax(InpXAUUSDscStrategyPipPrice,_Point);
      return MathMax(InpStandardXAUUSDStrategyPipPrice,_Point);
   }
   if(IsBTC())  return MathMax(1.0,_Point);
   return _Point;
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
   if(setup.s1r1TouchLatched)
      return setup.direction==1
             ? "ZERO-CONF S1"
             : "ZERO-CONF R1";

   if(setup.s2r2TouchLatched)
      return setup.direction==1
             ? "ZERO-CONF S2"
             : "ZERO-CONF R2";

   if(setup.highRiskTouchLatched)
      return "ZERO-CONF HIGH RISK";

   return "READY";
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

   ulong nowMs=GetTickCount64();

   if(nowMs<setup.lastDeployAttemptTickMs)
      return true;

   return (nowMs-setup.lastDeployAttemptTickMs >=
           (ulong)MathMax(0,InpDeploymentRetryIntervalMs));
}

void MarkDeploymentAttempt(PersistentReadySetup &setup)
{
   setup.lastDeployAttemptClock=TimeCurrent();
   setup.lastDeployAttemptTickMs=GetTickCount64();
}

void ClearPersistentTouchLatch(PersistentReadySetup &setup)
{
   setup.touchLatched=false;
   setup.highRiskTouchLatched=false;
   setup.s1r1TouchLatched=false;
   setup.s2r2TouchLatched=false;
   setup.touchClock=0;
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

bool ResolveDirectZeroConfTrigger(int direction,double observedLo,double observedHi,
                                  double tolerance,string &triggerText,
                                  double &triggerLo,double &triggerHi)
{
   triggerText="";
   triggerLo=0.0;
   triggerHi=0.0;

   if(direction==1 && g_buyReady.armed &&
      SensitiveEnvelopeTouchesZone(observedLo,observedHi,
                                   g_buyReady.entryLo,g_buyReady.entryHi,tolerance))
   {
      triggerText="DIRECT ZERO-CONF READY";
      triggerLo=g_buyReady.entryLo;
      triggerHi=g_buyReady.entryHi;
      return true;
   }

   if(direction==-1 && g_sellReady.armed &&
      SensitiveEnvelopeTouchesZone(observedLo,observedHi,
                                   g_sellReady.entryLo,g_sellReady.entryHi,tolerance))
   {
      triggerText="DIRECT ZERO-CONF READY";
      triggerLo=g_sellReady.entryLo;
      triggerHi=g_sellReady.entryHi;
      return true;
   }

   double level1=(direction==1)?g_S1:g_R1;
   double level2=(direction==1)?g_S2:g_R2;

   if(SensitiveEnvelopeTouchesLevel(observedLo,observedHi,level1,tolerance))
   {
      triggerText=(direction==1)?"DIRECT ZERO-CONF S1":"DIRECT ZERO-CONF R1";
      triggerLo=level1;
      triggerHi=level1;
      return true;
   }

   if(SensitiveEnvelopeTouchesLevel(observedLo,observedHi,level2,tolerance))
   {
      triggerText=(direction==1)?"DIRECT ZERO-CONF S2":"DIRECT ZERO-CONF R2";
      triggerLo=level2;
      triggerHi=level2;
      return true;
   }

   if(direction==1 && g_buyHigh.valid &&
      SensitiveEnvelopeTouchesZone(observedLo,observedHi,
                                   g_buyHigh.lo,g_buyHigh.hi,tolerance))
   {
      triggerText="DIRECT ZERO-CONF HIGH RISK";
      triggerLo=g_buyHigh.lo;
      triggerHi=g_buyHigh.hi;
      return true;
   }

   if(direction==-1 && g_sellHigh.valid &&
      SensitiveEnvelopeTouchesZone(observedLo,observedHi,
                                   g_sellHigh.lo,g_sellHigh.hi,tolerance))
   {
      triggerText="DIRECT ZERO-CONF HIGH RISK";
      triggerLo=g_sellHigh.lo;
      triggerHi=g_sellHigh.hi;
      return true;
   }

   return false;
}

bool DirectZeroConfRetryElapsed()
{
   if(g_directZeroConf.lastAttemptClock<=0)
      return true;

   if(TimeCurrent()>g_directZeroConf.lastAttemptClock)
      return true;

   ulong nowMs=GetTickCount64();
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
   g_directZeroConf.lastAttemptTickMs=GetTickCount64();
   g_directZeroConf.attempts++;

   int direction=g_directZeroConf.direction;

   if(DirectionalPostLossPauseActive(
         direction,
         "DIRECT ZERO-CONF "+g_directZeroConf.triggerText))
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+
          g_directZeroConf.triggerText+
          " | direction="+
          string(direction==1?"BUY":"SELL")+
          " | attempt="+
          IntegerToString(g_directZeroConf.attempts)+
          " | reason=directional next-M5 post-loss pause");
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
          " | reason=maximum 1 losing close reached in current M5");
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
          " | reason=maximum 2 currently losing positions reached");
      return false;
   }

   if(!DirectionalLayerSlotAvailable(direction,g_directZeroConf.triggerText))
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | attempt="+IntegerToString(g_directZeroConf.attempts)+
          " | reason=directional 13-layer ceiling reached");
      return false;
   }

   string envReason="";
   if(!TradingEnvironmentReady(envReason))
   {
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
   double exactDistance=MathMax(0.1,InpPresetStopLossPips)*StrategyPipSize();
   double exactSL=RoundPrice(direction==1?entry-exactDistance:entry+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(direction,entry,exactSL);

   double requested=ConfidenceSetupLot(0);
   double volume=CapSetupVolumeForCentSafety(direction,entry,brokerSL,requested);
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

   // FRESH V4: global order-rate floor, see OrderRequestThrottleOK().
   if(!OrderRequestThrottleOK())
      return false;

   string comment=PREFIX+"DIRECT_ZC_"+string(direction==1?"BUY_":"SELL_")+
                  IntegerToString(g_directZeroConf.attempts);

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

   Log("DIRECT ZERO-CONF MARKET EXECUTED | trigger="+g_directZeroConf.triggerText+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | volume="+DoubleToString(volume,VolumeDigits())+
       " | attempts="+IntegerToString(g_directZeroConf.attempts)+
       " | SL30="+string(openedWithoutSL?"virtual/broker install pending":
                         DoubleToString(brokerSL,_Digits))+
       " | TP=NONE | trail10=ACTIVE");

   g_directZeroConf.active=false;
   if(direction==1) g_directZeroConf.buyTouchConsumed=true;
   else g_directZeroConf.sellTouchConsumed=true;
   return true;
}

void ProcessDirectZeroConfluenceTriggers()
{
   if(!V3126_ZERO_CONF_DIRECT_MAP_FALLBACK)
      return;

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

   bool buyTouched=ResolveDirectZeroConfTrigger(1,observedLo,observedHi,tolerance,
                                               buyTrigger,buyLo,buyHi);
   bool sellTouched=ResolveDirectZeroConfTrigger(-1,observedLo,observedHi,tolerance,
                                                sellTrigger,sellLo,sellHi);

   if(!buyTouched && !g_directZeroConf.active)
      g_directZeroConf.buyTouchConsumed=false;
   if(!sellTouched && !g_directZeroConf.active)
      g_directZeroConf.sellTouchConsumed=false;

   if(HasWaitingZeroConfluenceSetup(1)) buyTouched=false;
   if(HasWaitingZeroConfluenceSetup(-1)) sellTouched=false;

   if(!g_directZeroConf.active)
   {
      int runningPositions=CountOurPositions();

      if(runningPositions<=V3126_ZERO_CONF_MAX_OPEN_POSITIONS)
      {
         bool chooseBuy=buyTouched && !g_directZeroConf.buyTouchConsumed;
         bool chooseSell=sellTouched && !g_directZeroConf.sellTouchConsumed;
         int chosenDirection=0;
         string chosenTrigger="";
         double chosenLo=0.0,chosenHi=0.0;

         if(chooseBuy && chooseSell)
         {
            double buyCentre=(buyLo+buyHi)*0.5;
            double sellCentre=(sellLo+sellHi)*0.5;
            if(MathAbs(cmp-buyCentre)<=MathAbs(cmp-sellCentre))
            {
               chosenDirection=1; chosenTrigger=buyTrigger;
               chosenLo=buyLo; chosenHi=buyHi;
            }
            else
            {
               chosenDirection=-1; chosenTrigger=sellTrigger;
               chosenLo=sellLo; chosenHi=sellHi;
            }
         }
         else if(chooseBuy)
         {
            chosenDirection=1; chosenTrigger=buyTrigger;
            chosenLo=buyLo; chosenHi=buyHi;
         }
         else if(chooseSell)
         {
            chosenDirection=-1; chosenTrigger=sellTrigger;
            chosenLo=sellLo; chosenHi=sellHi;
         }

         if(chosenDirection!=0)
         {
            g_directZeroConf.active=true;
            g_directZeroConf.direction=chosenDirection;
            g_directZeroConf.triggerText=chosenTrigger;
            g_directZeroConf.triggerLo=chosenLo;
            g_directZeroConf.triggerHi=chosenHi;
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

   return RoundPrice(safeSL);
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
      TrailBackoffCushionPrice(currentPrice,backoffSteps)+
      ZeroStopsLevelFallbackPrice(currentPrice,stopsLevel,freezeLevel);

   if(direction==1)
      return requestedSL<=currentPrice-minimumDistance+_Point*0.25;

   return requestedSL>=currentPrice+minimumDistance-_Point*0.25;
}

double FixedTrailCandidateSL(int direction,
                             double currentPrice)
{
   double distance=
      MathMax(0.1,InpTrailingDistancePips)*StrategyPipSize();

   return RoundPrice(
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

   g_hybridTrailStates[index].ticket=ticket;
   g_hybridTrailStates[index].active=false;
   g_hybridTrailStates[index].reconstructed=false;
   g_hybridTrailStates[index].peakPrice=current;
   g_hybridTrailStates[index].virtualStop=0.0;
   g_hybridTrailStates[index].positionTime=positionTime;
   g_hybridTrailStates[index].consecutiveInvalidStops=0;
   g_hybridTrailStates[index].modifyCooldownUntilMs=0;
   g_hybridTrailStates[index].closeConsecutiveFailures=0;
   g_hybridTrailStates[index].closeCooldownUntilMs=0;

   g_hybridTrailStates[index].peakPrice=
      ReconstructTrailPeak(direction,entry,positionTime,tick);
   g_hybridTrailStates[index].reconstructed=true;
   return index;
}

// TRAIL MODIFY BACKOFF: shared formula for the extra clearance added per
// consecutive rejected modify on a ticket. Scales with the symbol's own
// current price (percentage, not a fixed point count), so the same
// InpTrailBackoffCushionStepPct is meaningful on BTCUSD's $65,000 scale
// and on XAUUSD's $2,000 scale alike.
double TrailBackoffCushionPrice(double referencePrice,int backoffSteps)
{
   int steps=MathMin(MathMax(0,backoffSteps),MathMax(0,InpTrailBackoffMaxSteps));
   if(steps<=0 || referencePrice<=0.0)
      return 0.0;
   return referencePrice*MathMax(0.0,InpTrailBackoffCushionStepPct)/100.0*steps;
}

double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel)
{
   if(stopsLevel>0 || freezeLevel>0 || referencePrice<=0.0)
      return 0.0;
   return referencePrice*MathMax(0.0,InpZeroStopsLevelFallbackPct)/100.0;
}

double BrokerTrailMinimumDistance(double current,int backoffSteps)
{
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   int cushion=MathMax(MathMax(0,InpExecutionStopCushionPoints),
                       MathMax(0,InpTrailBrokerCushionPoints));

   double base=MathMax(_Point,
                       ((double)MathMax(stopsLevel,freezeLevel)+cushion)*_Point);

   return base+TrailBackoffCushionPrice(current,backoffSteps)+
          ZeroStopsLevelFallbackPrice(current,stopsLevel,freezeLevel);
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
   return RoundPrice(candidate);
}

bool ClosePositionAtVirtualTrail(int stateIndex,
                                 ulong ticket,
                                 string context,
                                 double current,
                                 double stop,
                                 double peak)
{
   ulong nowMs=GetTickCount64();
   if(stateIndex>=0 &&
      nowMs<g_hybridTrailStates[stateIndex].closeCooldownUntilMs)
      return false;

   ulong deviation=(ulong)MathMax(0,InpVirtualTrailCloseDeviationPts);
   trade.SetDeviationInPoints(deviation);
   bool sent=trade.PositionClose(ticket,deviation);
   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);
   trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));

   if(accepted)
   {
      if(stateIndex>=0)
         g_hybridTrailStates[stateIndex].closeConsecutiveFailures=0;

      Log("HYBRID VIRTUAL TRAIL CLOSE | "+context+
          " | ticket="+(string)ticket+
          " | current="+DoubleToString(current,_Digits)+
          " | virtualSL="+DoubleToString(stop,_Digits)+
          " | peak="+DoubleToString(peak,_Digits));
      return true;
   }

   if(code==TRADE_RETCODE_POSITION_CLOSED)
   {
      if(stateIndex>=0)
         g_hybridTrailStates[stateIndex].closeConsecutiveFailures=0;

      Log("HYBRID VIRTUAL TRAIL CLOSE ALREADY DONE | "+context+
          " | ticket="+(string)ticket+
          " | position was already closed by the time this request reached the broker");
      return true;
   }

   int failCount=0;
   int cooldown=MathMax(0,InpTrailModifyMinimumIntervalMs);

   if(stateIndex>=0)
   {
      failCount=++g_hybridTrailStates[stateIndex].closeConsecutiveFailures;
      cooldown=(int)MathMin(
         (double)MathMax(0,InpTrailBackoffCooldownCapMs),
         (double)MathMax(0,InpTrailModifyMinimumIntervalMs)*
         (double)(1<<MathMin(failCount,10)));
      g_hybridTrailStates[stateIndex].closeCooldownUntilMs=nowMs+(ulong)cooldown;
   }

   Log("HYBRID VIRTUAL TRAIL CLOSE FAILED | "+context+
       " | ticket="+(string)ticket+
       " | current="+DoubleToString(current,_Digits)+
       " | virtualSL="+DoubleToString(stop,_Digits)+
       " | consecutive failures="+IntegerToString(failCount)+
       " | next retry in="+IntegerToString(cooldown)+"ms"+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());
   return false;
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

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double strategyPip=StrategyPipSize();
   double activationDistance=MathMax(_Point,MathMax(0.0,InpTrailingActivationPips)*strategyPip);
   double trailDistance=MathMax(0.1,InpTrailingDistancePips)*strategyPip;
   double presetDistance=MathMax(0.1,InpPresetStopLossPips)*strategyPip;
   double minimumStep=MathMax(_Point,MathMax(0.1,InpTrailingStepPips)*strategyPip);

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

      // Exact preset protection is active from fill, before favourable movement.
      double initialVirtualStop=RoundPrice(direction==1 ? entry-presetDistance
                                                        : entry+presetDistance);
      if(g_hybridTrailStates[stateIndex].virtualStop<=0.0)
         g_hybridTrailStates[stateIndex].virtualStop=initialVirtualStop;

      bool initialVirtualHit=(direction==1)
                             ? current<=initialVirtualStop+_Point*0.25
                             : current>=initialVirtualStop-_Point*0.25;
      if(InpUseVirtualTrailFallback && initialVirtualHit)
      {
         ClosePositionAtVirtualTrail(stateIndex,ticket,context,current,initialVirtualStop,peak);
         continue;
      }

      // TRAIL MODIFY BACKOFF: this block used to call trade.PositionModify()
      // on every tick with no cooldown at all whenever initialImproves was
      // true - if the broker kept rejecting the same value, that meant one
      // request per tick, forever (confirmed live on BTCUSD.sc: ~45ms
      // between attempts, i.e. roughly 20/second, sustained all day). The
      // cooldown gate and backoffSteps below mirror the fix already applied
      // to the trailing-update block further down, and to the analogous
      // bug found on the EzyMap V2.2 BTC line.
      ulong nowMsTrail=GetTickCount64();
      int backoffSteps=g_hybridTrailStates[stateIndex].consecutiveInvalidStops;
      double initialBrokerSL=BrokerCompatibleTrailSL(direction,current,initialVirtualStop,backoffSteps);
      bool initialImproves=currentSL<=0.0 ||
         (direction==1 ? initialBrokerSL>currentSL+_Point*0.25
                       : initialBrokerSL<currentSL-_Point*0.25);
      bool initialCooldownElapsed=
         nowMsTrail>=g_hybridTrailStates[stateIndex].modifyCooldownUntilMs;

      if(initialImproves && initialBrokerSL>0.0 && initialCooldownElapsed)
      {
         if(!FixedTrailSLBrokerValid(direction,current,initialBrokerSL,backoffSteps))
         {
            int preFailCount=++g_hybridTrailStates[stateIndex].consecutiveInvalidStops;
            int preCooldown=
               (int)MathMin(
                  (double)MathMax(0,InpTrailBackoffCooldownCapMs),
                  (double)MathMax(0,InpTrailModifyMinimumIntervalMs)*
                  (double)(1<<MathMin(preFailCount,10)));
            g_hybridTrailStates[stateIndex].modifyCooldownUntilMs=
               nowMsTrail+(ulong)preCooldown;

            Log("PRESET 30P BROKER SL PRE-SEND REJECTED (backoff) | "+context+
                " | ticket="+(string)ticket+
                " | consecutive failures="+IntegerToString(preFailCount)+
                " | next retry in="+IntegerToString(preCooldown)+"ms");
         }
         else
         {
            bool initialSent=trade.PositionModify(ticket,initialBrokerSL,currentTP);
            uint initialCode=trade.ResultRetcode();
            bool initialAccepted=initialSent && TradeRetcodeAccepted(initialCode);

            if(initialAccepted)
            {
               g_hybridTrailStates[stateIndex].consecutiveInvalidStops=0;
               g_hybridTrailStates[stateIndex].modifyCooldownUntilMs=
                  nowMsTrail+(ulong)MathMax(0,InpTrailModifyMinimumIntervalMs);
               currentSL=initialBrokerSL;
            }
            else
            {
               int initialFailCount=++g_hybridTrailStates[stateIndex].consecutiveInvalidStops;
               int initialCooldown=
                  (int)MathMin(
                     (double)MathMax(0,InpTrailBackoffCooldownCapMs),
                     (double)MathMax(0,InpTrailModifyMinimumIntervalMs)*
                     (double)(1<<MathMin(initialFailCount,10)));
               g_hybridTrailStates[stateIndex].modifyCooldownUntilMs=
                  nowMsTrail+(ulong)initialCooldown;

               Log("PRESET 30P BROKER SL INSTALL FAILED | "+context+
                   " | ticket="+(string)ticket+
                   " | virtualSL="+DoubleToString(initialVirtualStop,_Digits)+
                   " | brokerSL="+DoubleToString(initialBrokerSL,_Digits)+
                   " | consecutive failures="+IntegerToString(initialFailCount)+
                   " | next retry in="+IntegerToString(initialCooldown)+"ms"+
                   " | retcode="+IntegerToString((int)initialCode)+
                   " | "+trade.ResultRetcodeDescription());
            }
         }
      }

      if(InpEnableTrailingAfterEntry &&
         !g_hybridTrailStates[stateIndex].active &&
         peakFavourable>=activationDistance-_Point*0.25)
      {
         g_hybridTrailStates[stateIndex].active=true;
         Log("HYBRID 10-PIP TRAIL ARMED | "+context+
             " | ticket="+(string)ticket+
             " | entry="+DoubleToString(entry,_Digits)+
             " | peak="+DoubleToString(peak,_Digits)+
             " | favourable="+DoubleToString(peakFavourable/strategyPip,1)+" pips");
      }

      if(InpEnableTrailingAfterEntry && g_hybridTrailStates[stateIndex].active)
      {
         double virtualStop=RoundPrice(direction==1?peak-trailDistance:peak+trailDistance);
         if(direction==1) virtualStop=MathMax(virtualStop,initialVirtualStop);
         else             virtualStop=MathMin(virtualStop,initialVirtualStop);
         g_hybridTrailStates[stateIndex].virtualStop=virtualStop;

         bool virtualHit=(direction==1)
                         ? current<=virtualStop+_Point*0.25
                         : current>=virtualStop-_Point*0.25;

         if(InpUseVirtualTrailFallback && virtualHit)
         {
            ClosePositionAtVirtualTrail(stateIndex,ticket,context,current,virtualStop,peak);
            continue;
         }

         // TRAIL MODIFY BACKOFF: see the identical fix on the initial-preset
         // block above for the full reasoning (confirmed live: ~45ms
         // between repeated "Invalid stops" rejections on BTCUSD.sc,
         // sustained for a whole session with no cooldown at all).
         ulong nowMsTrailUpdate=GetTickCount64();
         int trailBackoffSteps=g_hybridTrailStates[stateIndex].consecutiveInvalidStops;
         double desiredSL=BrokerCompatibleTrailSL(direction,current,virtualStop,trailBackoffSteps);
         bool improves=currentSL<=0.0 ||
            (direction==1
             ? desiredSL>currentSL+minimumStep-_Point*0.25
             : desiredSL<currentSL-minimumStep+_Point*0.25);
         bool trailCooldownElapsed=
            nowMsTrailUpdate>=g_hybridTrailStates[stateIndex].modifyCooldownUntilMs;

         if(improves && desiredSL>0.0 && trailCooldownElapsed)
         {
            if(!FixedTrailSLBrokerValid(direction,current,desiredSL,trailBackoffSteps))
            {
               int preFailCount2=++g_hybridTrailStates[stateIndex].consecutiveInvalidStops;
               int preCooldown2=
                  (int)MathMin(
                     (double)MathMax(0,InpTrailBackoffCooldownCapMs),
                     (double)MathMax(0,InpTrailModifyMinimumIntervalMs)*
                     (double)(1<<MathMin(preFailCount2,10)));
               g_hybridTrailStates[stateIndex].modifyCooldownUntilMs=
                  nowMsTrailUpdate+(ulong)preCooldown2;

               Log("HYBRID BROKER SL PRE-SEND REJECTED (backoff) | "+context+
                   " | ticket="+(string)ticket+
                   " | consecutive failures="+IntegerToString(preFailCount2)+
                   " | next retry in="+IntegerToString(preCooldown2)+"ms");
            }
            else
            {
               bool sent=trade.PositionModify(ticket,desiredSL,currentTP);
               uint code=trade.ResultRetcode();
               bool accepted=sent && TradeRetcodeAccepted(code);

               if(!accepted)
               {
                  int failCount=++g_hybridTrailStates[stateIndex].consecutiveInvalidStops;
                  int cooldown=
                     (int)MathMin(
                        (double)MathMax(0,InpTrailBackoffCooldownCapMs),
                        (double)MathMax(0,InpTrailModifyMinimumIntervalMs)*
                        (double)(1<<MathMin(failCount,10)));
                  g_hybridTrailStates[stateIndex].modifyCooldownUntilMs=
                     nowMsTrailUpdate+(ulong)cooldown;

                  Log("HYBRID BROKER SL MODIFY FAILED | "+context+
                      " | ticket="+(string)ticket+
                      " | virtualSL="+DoubleToString(virtualStop,_Digits)+
                      " | brokerSL="+DoubleToString(desiredSL,_Digits)+
                      " | stopLevel="+IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL))+
                      " | freezeLevel="+IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))+
                      " | consecutive failures="+IntegerToString(failCount)+
                      " | next retry in="+IntegerToString(cooldown)+"ms"+
                      " | retcode="+IntegerToString((int)code)+
                      " | "+trade.ResultRetcodeDescription());
               }
               else
               {
                  g_hybridTrailStates[stateIndex].consecutiveInvalidStops=0;
                  g_hybridTrailStates[stateIndex].modifyCooldownUntilMs=
                     nowMsTrailUpdate+(ulong)MathMax(0,InpTrailModifyMinimumIntervalMs);

                  Log("HYBRID BROKER SL MOVED | "+context+
                      " | ticket="+(string)ticket+
                      " | peak="+DoubleToString(peak,_Digits)+
                      " | virtualSL="+DoubleToString(virtualStop,_Digits)+
                      " | brokerSL="+DoubleToString(desiredSL,_Digits));
               }
            }
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
         ulong deviation=(ulong)MathMax(0,InpVirtualTrailCloseDeviationPts);
         trade.SetDeviationInPoints(deviation);
         bool tpClosed=trade.PositionClose(ticket,deviation);
         uint tpCode=trade.ResultRetcode();
         trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));
         if(tpClosed && TradeRetcodeAccepted(tpCode))
         {
            Log("FIXED VIRTUAL TP CLOSE | "+context+
                " | ticket="+(string)ticket+
                " | entry="+DoubleToString(entry,_Digits)+
                " | target="+DoubleToString(requestedTP,_Digits)+
                " | current="+DoubleToString(current,_Digits));
            continue;
         }
         Log("FIXED VIRTUAL TP CLOSE FAILED | "+context+
             " | ticket="+(string)ticket+
             " | target="+DoubleToString(requestedTP,_Digits)+
             " | retcode="+IntegerToString((int)tpCode)+
             " | "+trade.ResultRetcodeDescription());
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
}



bool ConfigureRouting()
{
   // EzyMap Scalp Mastery V2 uses the uploaded V1.1.0 M5 route:
   // H1 direction -> M15 supporting zone -> M5 signal/entry.
   g_directionTF=PERIOD_H1;
   g_supportTF=PERIOD_M15;
   g_confirmTF=PERIOD_M5;
   g_entryTF=PERIOD_M5;

   g_mode="SCALP";
   g_tfLabel="M5";
   g_dirLabel="H1";
   g_supLabel="M15";
   g_confirmLabel="M5";
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

int CurrentM5SelectionBias(string &biasText)
{
   biasText="NEUTRAL";

   MqlRates m5[];

   if(!LoadRatesFlexible(PERIOD_M5,80,30,m5))
      return 0;

   double ema=
      EMAFromRates(
         m5,
         ArraySize(m5),
         EMA_LEN,
         1);

   if(ema==EMPTY_VALUE)
      return 0;

   double closePrice=m5[1].close;
   double openPrice=m5[1].open;

   double neutralBand=
      MathMax(
         _Point*2.0,
         StrategyPipSize()*0.5);

   if(closePrice>ema+neutralBand)
   {
      biasText="BULLISH";
      return 1;
   }

   if(closePrice<ema-neutralBand)
   {
      biasText="BEARISH";
      return -1;
   }

   // Near EMA13, use the direction of the previous closed M5 candle.
   if(closePrice>openPrice)
   {
      biasText="BULLISH";
      return 1;
   }

   if(closePrice<openPrice)
   {
      biasText="BEARISH";
      return -1;
   }

   return 0;
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

   double minimumLevelDistance=
      MathMax(70.0*g_pipSize,_Point*5.0);

   PickDirectionLevels(h1,
                       ArraySize(h1),
                       entryReference,
                       minimumLevelDistance,
                       directionLow,
                       directionHigh,
                       directionATR,
                       g_S1,g_S2,g_R1,g_R2);

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
      V3126_ZERO_CONFLUENCE_TOUCH_RULE &&
      runningEAEntries<=V3126_ZERO_CONF_MAX_OPEN_POSITIONS;

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
      buyHighConfluences>=buyRequired;

   bool sellNormalConfluence=
      sellHighConfluences>=sellRequired;

   bool buyZeroConfluenceFallback=
      zeroConfluenceLowExposure &&
      !buyNormalConfluence;

   bool sellZeroConfluenceFallback=
      zeroConfluenceLowExposure &&
      !sellNormalConfluence;

   int buyEffectiveRequired=
      buyZeroConfluenceFallback ? 0 : buyRequired;

   int sellEffectiveRequired=
      sellZeroConfluenceFallback ? 0 : sellRequired;

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
             " confluence="+IntegerToString(buyHighConfluences)+"/"+
             IntegerToString(buyEffectiveRequired)+
             " zero-fallback="+string(buyZeroConfluenceFallback?"Y":"N")+
             " | SELL route="+string(allowSell?"Y":"N")+
             " conf="+string(sellConfirmation?"Y":"N")+
             " zone="+string(g_sellHigh.valid?"Y":"N")+
             " entry="+string(sellEntryFound?"Y":"N")+
             " retests="+IntegerToString(sellRetests)+"/"+IntegerToString(maximumRetests)+
             " confluence="+IntegerToString(sellHighConfluences)+"/"+
             IntegerToString(sellEffectiveRequired)+
             " zero-fallback="+string(sellZeroConfluenceFallback?"Y":"N")+
             " running entries="+IntegerToString(runningEAEntries));
      return true;
   }

   // V3.124 selection:
   // V3.104 BUY and SELL qualification stays unchanged. When both sides
   // qualify with the same exact numeric confidence score, M5 bias selects
   // one direction. Neutral M5 falls back to the nearest mapped zone.
   bool armBuy=buyCandidate;
   bool armSell=sellCandidate;

   bool exactEqualScoreDualCandidate=
      buyCandidate &&
      sellCandidate &&
      buyHighConfluences==
      sellHighConfluences;

   if(exactEqualScoreDualCandidate)
   {
      string m5BiasText="NEUTRAL";

      int m5Bias=
         CurrentM5SelectionBias(
            m5BiasText);

      double buyDistance=
         MathAbs(
            (g_buyHigh.lo+
             g_buyHigh.hi)/2.0-
            cmp);

      double sellDistance=
         MathAbs(
            (g_sellHigh.lo+
             g_sellHigh.hi)/2.0-
            cmp);

      string selectionReason="";

      if(m5Bias>0)
      {
         armBuy=true;
         armSell=false;
         selectionReason="M5 BULLISH";
      }
      else if(m5Bias<0)
      {
         armBuy=false;
         armSell=true;
         selectionReason="M5 BEARISH";
      }
      else
      {
         bool sellNearest=
            sellDistance<
            buyDistance;

         armBuy=!sellNearest;
         armSell=sellNearest;
         selectionReason="M5 NEUTRAL -> NEAREST ZONE";
      }

      Log("V3.124 EQUAL-SCORE M5 SELECTION"+
          " | BUY score="+
          IntegerToString(
             buyHighConfluences)+
          " | SELL score="+
          IntegerToString(
             sellHighConfluences)+
          " | M5 bias="+m5BiasText+
          " | reason="+selectionReason+
          " | selected="+
          string(armBuy?"BUY":"SELL")+
          " | BUY distance="+
          DoubleToString(
             buyDistance/
             MathMax(g_pipSize,_Point),
             1)+" pips"+
          " | SELL distance="+
          DoubleToString(
             sellDistance/
             MathMax(g_pipSize,_Point),
             1)+" pips");
   }
   else if(!InpArmBothDirectionsWhenValid &&
           buyCandidate &&
           sellCandidate)
   {
      double buyDistance=
         MathAbs(
            (g_buyHigh.lo+
             g_buyHigh.hi)/2.0-
            cmp);

      double sellDistance=
         MathAbs(
            (g_sellHigh.lo+
             g_sellHigh.hi)/2.0-
            cmp);

      bool sellWins=
         sellHighConfluences>
         buyHighConfluences ||
         (sellHighConfluences==
          buyHighConfluences &&
          sellDistance<
          buyDistance);

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

      Log("SOURCE READY BUY | H1/M15/M5 | conf="+
          IntegerToString(buyHighConfluences)+
          " | required="+IntegerToString(buyEffectiveRequired)+
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

      Log("SOURCE READY SELL | H1/M15/M5 | conf="+
          IntegerToString(sellHighConfluences)+
          " | required="+IntegerToString(sellEffectiveRequired)+
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

      bool expired=(closedBars>=InpReadyExpiryBars);
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

      bool expired=(closedBars>=InpReadyExpiryBars);
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

double CapSetupVolumeForCentSafety(int direction,
                                    double entry,
                                    double sl,
                                    double requested)
{
   if(requested<=0.0)
      return 0.0;

   if(g_accountUnitDivisor<=1.0 || !InpEnableCentSafetyCaps)
      return NormalizeVolumeDown(requested);

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

      double protectionDistance=MathMax(0.1,InpTrailingDistancePips)*StrategyPipSize();
      double protectionSL=RoundPrice(direction==1
                                     ? entry-protectionDistance
                                     : entry+protectionDistance);
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
            Log("LIVE CENT PARITY BLOCK | 50-pip risk="+
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
          " | 50-pip risk="+DoubleToString(candidateRisk,2)+" "+
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

// FRESH V4: median-of-samples helper for the auto-calibrating spread guard.
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

bool SpreadAllowed()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double spread=(tick.ask-tick.bid)/_Point;

   // Legacy static-cap path, unchanged behaviour when auto-calibration is
   // off - byte-identical to this file's original SpreadAllowed().
   if(!InpAutoCalibrateSpreadCap)
   {
      if(InpMaxSpreadPoints<=0) return true;
      return (spread<=InpMaxSpreadPoints);
   }

   if(g_spreadCalEffectiveCap>=0.0)
      return (spread<=g_spreadCalEffectiveCap);

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

      Log("FRESH V4 BTCUSD SPREAD AUTO-CALIBRATION COMPLETE"+
          " | samples="+IntegerToString(g_spreadCalCount)+
          " | median observed="+DoubleToString(median,1)+" points"+
          " | multiplier="+DoubleToString(mult,2)+
          " | ceiling(InpSpreadCalibrationCeilingPoints)="+IntegerToString(InpSpreadCalibrationCeilingPoints)+
          (InpSpreadCalibrationCeilingPoints<=0?" (uncapped)":"")+
          " | EFFECTIVE CAP NOW ENFORCED="+
          DoubleToString(g_spreadCalEffectiveCap,1)+" points");
   }

   return true; // fail open while calibrating
}

// FRESH V4: single global floor on time between any two order requests,
// regardless of which internal path triggered it. See the
// g_lastOrderRequestMs declaration for the full reasoning.
bool OrderRequestThrottleOK()
{
   double nowMs=(double)GetTickCount64();
   if(g_lastOrderRequestMs>0.0 &&
      nowMs-g_lastOrderRequestMs<(double)MathMax(0,InpMinMsBetweenOrderRequests))
      return false;

   g_lastOrderRequestMs=nowMs;
   return true;
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

bool RegisterDirectionalPostLossPauseFromDeal(ulong dealTicket,bool logEvent)
{
   if(!InpEnableDirectionalPostLossPause ||
      InpDirectionalPostLossPauseM5Candles<=0 ||
      dealTicket==0)
      return false;

   string symbol=
      HistoryDealGetString(dealTicket,DEAL_SYMBOL);

   if(symbol=="")
   {
      if(!HistoryDealSelect(dealTicket))
         return false;

      symbol=
         HistoryDealGetString(dealTicket,DEAL_SYMBOL);
   }

   if(symbol!=_Symbol)
      return false;

   if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=InpMagicNumber)
      return false;

   ENUM_DEAL_ENTRY entry=
      (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);

   if(entry!=DEAL_ENTRY_OUT &&
      entry!=DEAL_ENTRY_OUT_BY)
      return false;

   double realisedNet=
      HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+
      HistoryDealGetDouble(dealTicket,DEAL_COMMISSION)+
      HistoryDealGetDouble(dealTicket,DEAL_SWAP)+
      HistoryDealGetDouble(dealTicket,DEAL_FEE);

   if(realisedNet>=0.0)
      return false;

   ENUM_DEAL_TYPE dealType=
      (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket,DEAL_TYPE);

   // A SELL closing deal exits a BUY position; a BUY closing deal exits SELL.
   int closedDirection=0;

   if(dealType==DEAL_TYPE_SELL)
      closedDirection=1;
   else if(dealType==DEAL_TYPE_BUY)
      closedDirection=-1;
   else
      return false;

   datetime closeTime=
      (datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);

   int m5Seconds=
      PeriodSeconds(PERIOD_M5);

   if(m5Seconds<=0)
      m5Seconds=300;

   datetime lossBarOpen=
      closeTime-
      (closeTime%m5Seconds);

   datetime pauseStart=
      lossBarOpen+
      m5Seconds;

   datetime pauseEnd=
      pauseStart+
      MathMax(1,InpDirectionalPostLossPauseM5Candles)*
      m5Seconds;

   if(closedDirection==1)
   {
      if(pauseEnd>g_buyPostLossPauseEnd)
      {
         g_buyPostLossPauseStart=pauseStart;
         g_buyPostLossPauseEnd=pauseEnd;
      }
   }
   else
   {
      if(pauseEnd>g_sellPostLossPauseEnd)
      {
         g_sellPostLossPauseStart=pauseStart;
         g_sellPostLossPauseEnd=pauseEnd;
      }
   }

   if(logEvent)
   {
      Log("DIRECTIONAL POST-LOSS PAUSE ARMED"+
          " | closed direction="+
          string(closedDirection==1?"BUY":"SELL")+
          " | deal="+
          (string)dealTicket+
          " | realised net="+
          DoubleToString(realisedNet,2)+
          " | loss M5="+
          TimeToString(
             lossBarOpen,
             TIME_DATE|TIME_MINUTES)+
          " | pause starts="+
          TimeToString(
             pauseStart,
             TIME_DATE|TIME_MINUTES)+
          " | pause ends="+
          TimeToString(
             pauseEnd,
             TIME_DATE|TIME_MINUTES)+
          " | opposite direction remains allowed=YES");
   }

   return true;
}

void RebuildDirectionalPostLossPauseFromHistory()
{
   g_buyPostLossPauseStart=0;
   g_buyPostLossPauseEnd=0;
   g_sellPostLossPauseStart=0;
   g_sellPostLossPauseEnd=0;

   if(!InpEnableDirectionalPostLossPause ||
      InpDirectionalPostLossPauseM5Candles<=0)
      return;

   datetime now=TimeCurrent();

   if(!HistorySelect(now-86400,now))
      return;

   int total=
      HistoryDealsTotal();

   for(int i=0;i<total;i++)
   {
      ulong ticket=
         HistoryDealGetTicket(i);

      if(ticket==0)
         continue;

      RegisterDirectionalPostLossPauseFromDeal(
         ticket,
         false);
   }
}

bool DirectionalPostLossPauseActive(int direction,string context)
{
   if(!InpEnableDirectionalPostLossPause ||
      InpDirectionalPostLossPauseM5Candles<=0 ||
      (direction!=1 && direction!=-1))
      return false;

   datetime now=TimeCurrent();

   datetime pauseStart=
      direction==1
      ? g_buyPostLossPauseStart
      : g_sellPostLossPauseStart;

   datetime pauseEnd=
      direction==1
      ? g_buyPostLossPauseEnd
      : g_sellPostLossPauseEnd;

   if(pauseEnd<=0)
      return false;

   if(now>=pauseEnd)
   {
      if(direction==1)
      {
         g_buyPostLossPauseStart=0;
         g_buyPostLossPauseEnd=0;
      }
      else
      {
         g_sellPostLossPauseStart=0;
         g_sellPostLossPauseEnd=0;
      }

      return false;
   }

   // The loss candle itself is governed by the current-M5 closed-loss cap.
   // This directional pause begins only when the next M5 candle opens.
   if(now<pauseStart)
      return false;

   Log("DIRECTIONAL POST-LOSS PAUSE BLOCK"+
       " | direction="+
       string(direction==1?"BUY":"SELL")+
       " | pause="+
       TimeToString(
          pauseStart,
          TIME_DATE|TIME_MINUTES)+
       " to "+
       TimeToString(
          pauseEnd,
          TIME_DATE|TIME_MINUTES)+
       " | opposite direction allowed=YES"+
       " | context="+context);

   return true;
}

void CancelPendingForDirectionalPostLossPause(int direction)
{
   if(!InpEnableDirectionalPostLossPause ||
      !InpCancelPendingDuringDirectionalPause ||
      !DirectionalPostLossPauseActive(
         direction,
         "pending-order enforcement"))
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
         Log("DIRECTIONAL POST-LOSS PAUSE CANCEL"+
             " | direction="+
             string(direction==1?"BUY":"SELL")+
             " | ticket="+
             (string)ticket+
             " | price="+
             DoubleToString(price,_Digits));
      }
      else
      {
         Log("DIRECTIONAL POST-LOSS PAUSE CANCEL FAILED"+
             " | direction="+
             string(direction==1?"BUY":"SELL")+
             " | ticket="+
             (string)ticket+
             " | "+
             trade.ResultRetcodeDescription());
      }
   }
}

void EnforceDirectionalPostLossPause()
{
   CancelPendingForDirectionalPostLossPause(1);
   CancelPendingForDirectionalPostLossPause(-1);
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

bool DirectionalLayerSlotAvailable(int direction,string context)
{
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

      if(!trade.PositionClose(ticket,(ulong)InpDeviationPoints))
         Log("Position close failed "+(string)ticket+" : "+trade.ResultRetcodeDescription());
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
      long positionId=(long)HistoryDealGetInteger(ticket,DEAL_POSITION_ID);

      // FRESH V4 report fix: ParsePersistentComment() only recognises the
      // "EZR..." comment format used by the persistent-setup deployment
      // path. The direct zero-conf market path (PREFIX+"DIRECT_ZC_...") and
      // the legacy/aggressive-arm layer path ("EZP2 ...") use entirely
      // different comment formats, so every real entry placed through
      // either of those two paths used to fail this parse and hit the old
      // "continue" below - silently excluded from TOTAL ENTRY LOTS and
      // every other figure in this report, even though the trade genuinely
      // executed and shows up in the broker's own trade history. Falling
      // back to the deal's own position ID (negated, so it can never
      // collide with a real positive EZR setup ID) means every real entry
      // is still counted - it just cannot be grouped by persistent-setup
      // layer attribution the way an EZR-commented entry can, since that
      // information was never in a comment to parse in the first place.
      if(!ParsePersistentComment(
            HistoryDealGetString(ticket,DEAL_COMMENT),
            setupId,layerIndex,totalLayers))
      {
         setupId=-positionId;
         layerIndex=1;
         totalLayers=1;
      }

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

   Log("L1 TP HITS: "+IntegerToString(l1Hits)+
       " | L2 TP HITS: "+IntegerToString(l2Hits)+
       " | RUNNER TP HITS: "+IntegerToString(runnerHits)+
       " | PEAK-LOCK CLOSES: "+IntegerToString(peakLockCloses));

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
             "PeakLockCloses");

   for(int i=0;i<ArraySize(rows);i++)
   {
      double capture=
         (rows[i].peakCampaignProfit>0.01)
         ? rows[i].netProfit/rows[i].peakCampaignProfit*100.0
         : 0.0;

      FileWrite(handle,
                (string)rows[i].id,
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
                rows[i].peakLockCloses);
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
   // FRESH V4: global order-rate floor, see OrderRequestThrottleOK().
   if(!OrderRequestThrottleOK())
      return false;

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
   string plannedKindText=
      (p.kind==LAYER_MARKET)
      ? "MARKET"
      : (p.kind==LAYER_LIMIT
         ? "LIMIT"
         : "STOP");

   if(DirectionalPostLossPauseActive(
         setup.direction,
         plannedKindText+" signal="+(string)setup.id))
   {
      SetDeploymentFailure(
         "directional next-M5 post-loss pause active",
         0,
         "",
         "",
         false);
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
   double exactDistance=MathMax(0.1,InpPresetStopLossPips)*StrategyPipSize();
   double exactSL=RoundPrice(setup.direction==1 ? estimatedEntry-exactDistance
                                                : estimatedEntry+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(setup.direction,estimatedEntry,exactSL);

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
      trade.PositionClose(ticket,InpDeviationPoints);
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

void ResetCampaignDay(bool forceReset)
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(),dt);
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

   Log("CAMPAIGN DAY RESET | start="+DoubleToString(g_dayStartEquity,2)+
       " | target="+DoubleToString(g_dayTargetEquity,2)+
       " | loss floor="+DoubleToString(g_dayLossFloor,2));
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
      g_dayLockReason="DAILY LOSS STOP";
      CloseAllEzyExposure();
      Log("CAMPAIGN REST: DAILY LOSS STOP | equity="+DoubleToString(equity,2));
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

double ConfidenceSetupLot(int conf)
{
   double effectiveEquity=EffectiveAccountEquity();
   double sizingCapital=LotSizingCapitalUnits();

   if(effectiveEquity<MinimumTradingEquity())
      return 0.0;

   double lotPer100=InpStandardSetupLotPer100;

   if(conf>=InpQualityConfidenceMin)
      lotPer100=InpQualitySetupLotPer100;
   else if(conf>=InpGoodConfidenceMin)
      lotPer100=InpGoodSetupLotPer100;

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

   return Clamp(pct,25.0,InpMaxRiskPct);
}

int DesiredLayersForSetup(int conf,double entryLo,double entryHi,double sl)
{
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
      Log("ZERO-CONFLUENCE SETUP WAITING FOR CMP TOUCH | signal="+
          (string)id+
          " | triggers=READY, matching HIGH-RISK, frozen "+
          string(direction==1?"S1/S2":"R1/R2")+" levels"+
          " | high-risk trigger="+
          string(V3126_ZERO_CONF_HIGH_RISK_TOUCH_RULE?"ON":"OFF")+
          " | S1/R1 trigger="+
          string(V3126_ZERO_CONF_S1_R1_TOUCH_RULE?"ON":"OFF")+
          " | S2/R2 trigger="+
          string(V3126_ZERO_CONF_S2_R2_TOUCH_RULE?"ON":"OFF")+
          " | open EA positions="+
          IntegerToString(CountOurPositions())+
          " | trigger allowed only while positions <= "+
          IntegerToString(V3126_ZERO_CONF_MAX_OPEN_POSITIONS));
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

bool PersistentQualityPass(PersistentReadySetup &setup,string &reason)
{
   reason="";

   if(V3126_FORCE_ZERO_CONF_MARKET_EXECUTION &&
      setup.zeroConfluenceFallback &&
      setup.requiredConfluences==0)
   {
      Log("ZERO-CONFLUENCE FORCE PASS | signal="+(string)setup.id+
          " | touch quality recheck=BYPASSED"+
          " | current position-count recheck=BYPASSED"+
          " | retry until MARKET accepted=YES");
      return true;
   }

   CheckCampaignDay();
   if(g_dayTradingLocked)
   {
      reason=g_dayLockReason;
      return false;
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

   double remainingLot=targetSetupLot;
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

      int layersLeft=requestedLayers-i;

      // Split the requested TOTAL setup lot as evenly as possible.
      double desiredShare=
         NormalizeVolumeDown(remainingLot/(double)layersLeft);

      if(desiredShare<minVol-1e-12)
         return false;

      // Each layer receives an equal share of the remaining hard risk budget.
      double riskRemaining=MathMax(0.0,riskBudget-plannedRisk);
      double riskShare=riskRemaining/(double)layersLeft;
      double maxByRisk=NormalizeVolumeDown(riskShare/lossPerLot);

      double vol=
         NormalizeVolumeDown(MathMin(desiredShare,maxByRisk));

      if(vol<minVol-1e-12)
         return false;

      plans[i].rawPrice=raw;
      plans[i].execPrice=execPrice;
      plans[i].lossPerLot=lossPerLot;
      plans[i].kind=kind;
      plans[i].volume=vol;

      plannedRisk+=vol*lossPerLot;
      remainingLot=MathMax(0.0,remainingLot-vol);

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

   targetSetupLot=
      CapSetupVolumeForCentSafety(direction,
                                  marketPrice,
                                  setup.structuralSL,
                                  targetSetupLot);

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

   // Use only valid routes, but preserve the full original confidence lot.
   int available=ArraySize(plans);

   while(available>1)
   {
      double share=
         NormalizeVolumeDown(
            targetSetupLot/(double)available);

      if(share>=minVol-1e-12)
         break;

      ArrayResize(plans,available-1);
      available=ArraySize(plans);
   }

   if(available<=0)
      return false;

   double remaining=targetSetupLot;

   // LIMIT routes receive equal broker-valid shares.
   // MARKET receives the final rounding remainder, preserving total volume.
   for(int i=available-1;i>=0;i--)
   {
      int routesLeft=i+1;

      double volume=
         (i==0)
         ? NormalizeVolumeDown(remaining)
         : NormalizeVolumeDown(
              remaining/(double)routesLeft);

      if(volume<minVol-1e-12)
      {
         SetDeploymentFailure(
            "confidence volume split produced a layer below broker minimum",
            0,"","",false);
         return false;
      }

      plans[i].volume=volume;
      remaining=MathMax(0.0,remaining-volume);
   }

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
   double exactDistance=MathMax(0.1,InpPresetStopLossPips)*StrategyPipSize();

   setup.structuralSL=RoundPrice(direction==1
                                ? marketPrice-exactDistance
                                : marketPrice+exactDistance);
   setup.structuralSL=BrokerSafeExecutionSL(direction,marketPrice,setup.structuralSL);

   double requested=ConfidenceSetupLot(0);
   double volume=CapSetupVolumeForCentSafety(direction,marketPrice,
                                             setup.structuralSL,requested);
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

   // Reduce layer count only when broker minimum volume makes the preferred
   // split impossible. Total setup lot remains the same.
   while(layers>1)
   {
      double share=
         NormalizeVolumeDown(targetSetupLot/(double)layers);

      if(share>=minVol-1e-12)
         break;

      layers--;
   }

   ArrayResize(plans,layers);

   double remaining=targetSetupLot;
   double marketPrice=(direction==1)?tick.ask:tick.bid;

   for(int i=0;i<layers;i++)
   {
      int left=layers-i;

      double vol=
         (left==1)
         ? NormalizeVolumeDown(remaining)
         : NormalizeVolumeDown(remaining/(double)left);

      if(vol<minVol-1e-12)
         return false;

      plans[i].rawPrice=marketPrice;
      plans[i].execPrice=marketPrice;
      plans[i].volume=vol;
      plans[i].kind=LAYER_MARKET;
      plans[i].lossPerLot=OneLotLoss(direction,marketPrice,sl);

      if(plans[i].lossPerLot<=0)
         return false;

      remaining=MathMax(0.0,remaining-vol);
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

   bool zeroConf=g_persistentSetups[index].zeroConfluenceFallback;
   bool forceZeroConf=zeroConf && V3126_FORCE_ZERO_CONF_MARKET_EXECUTION;

   CheckCampaignDay();

   if(!forceZeroConf && g_dayTradingLocked)
   {
      SetDeploymentFailure("campaign/day trading lock: "+g_dayLockReason,
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

   CheckCampaignDay();

   if(g_dayTradingLocked)
      return false;

   if(g_campaignSetups>=InpMaxCampaignSetupsPerDay)
      return false;

   string tradeEnvironmentReason="";
   if(!TradingEnvironmentReady(tradeEnvironmentReason))
   {
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

   targetSetupLot=
      CapSetupVolumeForCentSafety(
         g_persistentSetups[index].direction,
         marketPrice,
         g_persistentSetups[index].structuralSL,
         targetSetupLot);

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
      datetime future=s.armedBarTime+TfSeconds(g_entryTF)*InpReadyExpiryBars;
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
         (closedBars>=InpReadyExpiryBars);

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
            ? SensitiveEnvelopeTouchesZone(
                 observedLo,
                 observedHi,
                 g_persistentSetups[i].entryLo,
                 g_persistentSetups[i].entryHi,
                 zeroConfTouchTol)
            : (cmp>=g_persistentSetups[i].entryLo-normalTouchTol &&
               cmp<=g_persistentSetups[i].entryHi+normalTouchTol);

         bool highRiskZoneValid=
            g_persistentSetups[i].supportLo>0.0 &&
            g_persistentSetups[i].supportHi>
            g_persistentSetups[i].supportLo;

         bool highRiskTouched=
            zeroConf &&
            V3126_ZERO_CONF_HIGH_RISK_TOUCH_RULE &&
            highRiskZoneValid &&
            SensitiveEnvelopeTouchesZone(
               observedLo,
               observedHi,
               g_persistentSetups[i].supportLo,
               g_persistentSetups[i].supportHi,
               zeroConfTouchTol);

         double frozenS1R1=
            g_persistentSetups[i].zeroConfluenceLevelPrice;

         double frozenS2R2=
            g_persistentSetups[i].zeroConfluenceOuterLevelPrice;

         bool s1r1LevelValid=
            frozenS1R1>0.0;

         bool s2r2LevelValid=
            frozenS2R2>0.0;

         bool s1r1Touched=
            zeroConf &&
            V3126_ZERO_CONF_S1_R1_TOUCH_RULE &&
            s1r1LevelValid &&
            SensitiveEnvelopeTouchesLevel(
               observedLo,
               observedHi,
               frozenS1R1,
               zeroConfTouchTol);

         bool s2r2Touched=
            zeroConf &&
            V3126_ZERO_CONF_S2_R2_TOUCH_RULE &&
            s2r2LevelValid &&
            SensitiveEnvelopeTouchesLevel(
               observedLo,
               observedHi,
               frozenS2R2,
               zeroConfTouchTol);

         // Trigger priority when areas overlap:
         // READY first, then S1/R1, then S2/R2, then HIGH-RISK.
         bool s1r1OnlyTouched=
            s1r1Touched &&
            !entryTouched;

         bool s2r2OnlyTouched=
            s2r2Touched &&
            !entryTouched &&
            !s1r1Touched;

         bool highRiskOnlyTouched=
            highRiskTouched &&
            !entryTouched &&
            !s1r1Touched &&
            !s2r2Touched;

         // The arming M5 candle is candle zero.
         // A completely later M5 candle is normally required for LIVE.
         bool laterM5=
            InpAggressiveArmExecution
            ? true
            : (closedBars>=1);

         // The new zero-confluence HIGH-RISK trigger is immediate and does
         // not wait for another completed M5 candle after the setup is stored.
         bool touchEligible=
            (laterM5 && entryTouched) ||
            s1r1Touched ||
            s2r2Touched ||
            highRiskTouched;

         // Precise touch latch:
         // once chart CMP touches READY or the matching zero-confluence
         // HIGH-RISK zone, remember it so transient movement cannot lose it.
         if(touchEligible &&
            !g_persistentSetups[i].touchLatched)
         {
            g_persistentSetups[i].touchLatched=true;
            g_persistentSetups[i].highRiskTouchLatched=
               highRiskOnlyTouched;
            g_persistentSetups[i].s1r1TouchLatched=
               s1r1OnlyTouched;
            g_persistentSetups[i].s2r2TouchLatched=
               s2r2OnlyTouched;
            g_persistentSetups[i].touchClock=TimeCurrent();
            g_persistentSetups[i].touchPrice=cmp;
            g_persistentSetups[i].deployAttempts=0;

            double triggerLo=
               s1r1OnlyTouched
               ? frozenS1R1
               : (s2r2OnlyTouched
                  ? frozenS2R2
                  : (highRiskOnlyTouched
                     ? g_persistentSetups[i].supportLo
                     : g_persistentSetups[i].entryLo));

            double triggerHi=
               s1r1OnlyTouched
               ? frozenS1R1
               : (s2r2OnlyTouched
                  ? frozenS2R2
                  : (highRiskOnlyTouched
                     ? g_persistentSetups[i].supportHi
                     : g_persistentSetups[i].entryHi));

            string triggerText=
               s1r1OnlyTouched
               ? (direction==1
                  ? "ZERO-CONF S1"
                  : "ZERO-CONF R1")
               : (s2r2OnlyTouched
                  ? (direction==1
                     ? "ZERO-CONF S2"
                     : "ZERO-CONF R2")
                  : (highRiskOnlyTouched
                     ? "ZERO-CONF HIGH RISK"
                     : "READY"));

            Log("CMP TOUCH LATCHED | signal="+
                (string)id+
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
                " | frozen "+string(direction==1?"S1":"R1")+"="+
                DoubleToString(frozenS1R1,_Digits)+
                " | frozen "+string(direction==1?"S2":"R2")+"="+
                DoubleToString(frozenS2R2,_Digits));
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
            V3126_FORCE_ZERO_CONF_MARKET_EXECUTION &&
            V3126_ZERO_CONF_RETRY_UNTIL_FILLED;

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
            : (!entryTouched &&
               !s1r1Touched &&
               !s2r2Touched &&
               !highRiskTouched &&
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
   // FRESH V4: global order-rate floor, see OrderRequestThrottleOK().
   if(!OrderRequestThrottleOK())
      return false;

   if(DirectionalPostLossPauseActive(
         direction,
         "LEGACY layer "+
         IntegerToString(layerIndex+1)+
         "/"+
         IntegerToString(totalLayers)))
      return false;

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
      Log("Spread filter blocked READY setup.");
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
   g_buyPostLossPauseStart=0;
   g_buyPostLossPauseEnd=0;
   g_sellPostLossPauseStart=0;
   g_sellPostLossPauseEnd=0;
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
   g_directZeroConf.triggerLo=0.0;
   g_directZeroConf.triggerHi=0.0;
   g_directZeroConf.latchedClock=0;
   g_directZeroConf.lastAttemptClock=0;
   g_directZeroConf.lastAttemptTickMs=0;
   g_directZeroConf.attempts=0;
   g_directZeroConfHasPreviousCMP=false;
   g_directZeroConfPreviousCMP=0.0;

   // FRESH V4: (re)arm spread auto-calibration and the order-rate throttle
   // for this run/attach.
   g_spreadCalCount=0;
   g_spreadCalEffectiveCap=-1.0;
   ArrayResize(g_spreadCalSamples,MathMax(20,InpSpreadCalibrationTicks));
   g_lastOrderRequestMs=0;

   Log("FRESH V4 BTCUSD SPREAD GUARD MODE"+
       " | InpAutoCalibrateSpreadCap="+string(InpAutoCalibrateSpreadCap?"ON":"OFF")+
       (InpAutoCalibrateSpreadCap
        ? (" | calibrating over first "+IntegerToString(MathMax(20,InpSpreadCalibrationTicks))+
           " ticks, multiplier="+DoubleToString(MathMax(1.0,InpSpreadCalibrationMultiplier),2)+
           " | ceiling="+IntegerToString(InpSpreadCalibrationCeilingPoints)+
           (InpSpreadCalibrationCeilingPoints<=0?" (uncapped)":"")+
           " | filter INACTIVE (fail-open) until calibration completes")
        : (" | static InpMaxSpreadPoints="+IntegerToString(InpMaxSpreadPoints)+
           (InpMaxSpreadPoints<=0?" (filter DISABLED)":""))));

   Log("FRESH V4 BTCUSD PIP-SIZE"+
       " | symbol="+_Symbol+
       " | IsGold="+string(IsGold()?"YES":"NO")+
       " | IsBTC="+string(IsBTC()?"YES":"NO")+
       " | cent-suffix="+string(IsCentSuffixSymbol()?"YES":"NO")+
       " | InpUseXAUUSDscBrokerPointPips="+string(InpUseXAUUSDscBrokerPointPips?"ON":"OFF")+" (dormant unless IsGold())"+
       " | InpPreserveLegacyPipDistances="+string(InpPreserveLegacyPipDistances?"ON":"OFF")+" (dormant unless IsGold())"+
       " | resolved strategy pip price="+DoubleToString(StrategyPipSize(),_Digits));

   ApplyPremiumChartTheme();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.SetAsyncMode(InpEnforceDirectionalLayerCap ? false : InpUseAsyncMode);

   LoadState();
   EnforceDirectionalLayerCaps();
   RebuildDirectionalPostLossPauseFromHistory();
   EnforceDirectionalPostLossPause();

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

   Log("EzyMap Scalp Mastery V3.124 V3.103 BASE + DIRECTIONAL 13-LAYER CAP + NO TP / 30P SL + 10P TRAIL initialized.");
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

   Log("V3.126 DIRECTIONAL POST-LOSS PAUSE"+
       " | losing BUY close pauses BUY only=YES"+
       " | losing SELL close pauses SELL only=YES"+
       " | pause duration="+
       IntegerToString(InpDirectionalPostLossPauseM5Candles)+
       " complete M5 candle"+
       " | pause begins at next M5 open=YES"+
       " | opposite direction remains allowed=YES"+
       " | same-direction pending cancelled during pause="+
       string(InpCancelPendingDuringDirectionalPause?"YES":"NO")+
       " | existing positions force-closed=NO");
   Log("V3.126 EQUAL-SCORE M5 POLICY"+
       " | V3.124 BUY/SELL confluence unchanged"+
       " | trend minimum="+
       IntegerToString(TREND_MIN_CONFLUENCES)+
       " | counter minimum="+
       IntegerToString(COUNTER_MIN_CONFLUENCES)+
       " | exact equal BUY/SELL score=M5 BIAS WINNER"+
       " | M5 source=previous closed candle versus EMA13"+
       " | bullish M5=BUY"+
       " | bearish M5=SELL"+
       " | neutral M5=nearest mapped zone");
   Log("V3.126 DIRECTIONAL LOSING GOVERNOR"+
       " | maximum losing BUY positions="+
       IntegerToString(InpMaxLosingPositionsPerDirection)+
       " | maximum losing SELL positions="+
       IntegerToString(InpMaxLosingPositionsPerDirection)+
       " | BUY/SELL independent=YES"+
       " | floating net=profit+swap"+
       " | block same-direction MARKET/LIMIT/STOP at cap=YES"+
       " | cancel same-direction pending="+
       string(InpCancelPendingAtLosingCap?"YES":"NO")+
       " | existing positions force-closed=NO");
   Log("V3.126 CURRENT-M5 CLOSED LOSS GOVERNOR"+
       " | maximum losing closing deals per M5="+
       IntegerToString(InpMaxClosedNegativeEntriesPerM5)+
       " | BUY and SELL combined=YES"+
       " | net=profit+commission+swap+fee"+
       " | block all new entries until next M5=YES"+
       " | cancel all EA pending="+
       string(InpCancelPendingAtM5ClosedLossCap?"YES":"NO")+
       " | existing positions force-closed=NO");
   Log("V3.126 STRUCTURE CHECK"+
       " | PersistentReadySetup.requiredConfluences=ACTIVE"+
       " | PersistentReadySetup.zeroConfluenceFallback=ACTIVE"+
       " | ActiveSnapshot restored to V3.081 layout");
   Log("V3.126 ZERO-CONF M5 CAP REMOVED"+
       " | no zero-confluence fill quantity limit per M5"+
       " | pending orders are not cancelled by an M5 fill counter"+
       " | directional and broker safeguards remain active");
   Log("V3.124 EXECUTION RETRY FIX"+
       " | exact broker reason in Journal"+
       " | temporary retcodes only are retried"+
       " | permanent failures stop the affected setup for current M5"+
       " | same-moment throttle="+
       IntegerToString(InpDeploymentRetryIntervalMs)+"ms"+
       " | zero-conf route 1 MARKET required"+
       " | optional pending has no per-M5 fill cap");
   Log("V3.124 FORCE ZERO-CONF EXECUTION"+
       " | stored touch retries until MARKET accepted"+
       " | quality/position recheck bypassed after valid storage"+
       " | retry expiry/attempt limit/current-M5 permanent pause bypassed"+
       " | direct current-map fallback="+
       string(V3126_ZERO_CONF_DIRECT_MAP_FALLBACK?"ON":"OFF")+
       " | hard controls=broker permission/valid volume/margin/market"+
       " + directional 13-layer ceiling");
   Log("V3.124 SENSITIVE ZERO-CONF TOUCH"+
       " | tolerance="+
       DoubleToString(InpZeroConfTouchTolerancePips,1)+" pips"+
       " | normal tolerance="+
       DoubleToString(InpEntryTouchTolerancePips,1)+" pips"+
       " | Bid/Ask/Last envelope="+
       string(InpZeroConfUseBidAskEnvelope?"ON":"OFF")+
       " | tick-path crossing="+
       string(InpZeroConfUseTickPathCrossing?"ON":"OFF")+
       " | retry="+
       IntegerToString(InpZeroConfTouchRetrySeconds)+" sec / "+
       IntegerToString(InpZeroConfMaxDeployAttempts)+" attempts"+
       " | applies only to zero-confluence READY/HIGH-RISK/S1/S2/R1/R2");
   Log("V3.124 ZERO-CONF LEVEL TRIGGERS"+
       " | S1/R1="+
       string(V3126_ZERO_CONF_S1_R1_TOUCH_RULE?"ON":"OFF")+
       " | S2/R2="+
       string(V3126_ZERO_CONF_S2_R2_TOUCH_RULE?"ON":"OFF")+
       " | BUY stores S1/S2; either touch -> instant BUY routing"+
       " | SELL stores R1/R2; either touch -> instant SELL routing"+
       " | levels frozen when READY is stored"+
       " | zero-conf touch tolerance="+
       DoubleToString(InpZeroConfTouchTolerancePips,1)+" pips"+
       " | zero-conf per-M5 fill cap=REMOVED");
   Log("V3.124 ZERO-CONF HIGH-RISK TRIGGER"+
       " | enabled="+
       string(V3126_ZERO_CONF_HIGH_RISK_TOUCH_RULE?"ON":"OFF")+
       " | BUY high-risk CMP touch -> instant BUY routing"+
       " | SELL high-risk CMP touch -> instant SELL routing"+
       " | first route=MARKET"+
       " | zero-conf per-M5 fill cap=REMOVED");
   Log("V3.124 ZERO-CONFLUENCE TOUCH RULE"+
       " | enabled="+
       string(V3126_ZERO_CONFLUENCE_TOUCH_RULE?"ON":"OFF")+
       " | zero required confluences only when open EA positions <= "+
       IntegerToString(V3126_ZERO_CONF_MAX_OPEN_POSITIONS)+
       " | pending orders excluded from running-entry count"+
       " | fallback triggers=READY, matching HIGH-RISK, or frozen S1/S2/R1/R2 CMP touch"+
       " | normal rules remain trend="+
       IntegerToString(TREND_MIN_CONFLUENCES)+
       " / counter="+
       IntegerToString(COUNTER_MIN_CONFLUENCES));
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
   Log("All MARKET/LIMIT/STOP routes request no TP and a preset 30-pip SL; exact virtual protection remains active when broker geometry differs.");
   Log("10-PIP TRAIL: enabled="+string(InpEnableTrailingAfterEntry?"YES":"NO")+" | activation="+
       "first favourable broker point"+
       " | trail distance="+
       DoubleToString(MathMax(0.1,InpTrailingDistancePips),1)+
       " pips | step="+
       DoubleToString(MathMax(0.1,InpTrailingStepPips),1)+" pip(s)"+
       " | XAU pip size="+DoubleToString(StrategyPipSize(),_Digits)+".");
   Log("FIXED 30-PIP SL: broker SL + virtual exact stop | virtual fallback="+
       string(InpUseVirtualTrailFallback?"ON":"OFF")+
       " | reconstruct M1="+
       string(InpReconstructTrailFromM1?"ON":"OFF")+
       " | broker stops="+
       IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL))+
       " points | freeze="+
       IntegerToString((int)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL))+
       " points.");

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
   EventKillTimer();
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
   EnforceDirectionalPostLossPause();
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
             " | BUY losing="+
             IntegerToString(CountOurLosingPositionsByDirection(1))+
             "/"+
             IntegerToString(InpMaxLosingPositionsPerDirection)+
             " | SELL losing="+
             IntegerToString(CountOurLosingPositionsByDirection(-1))+
             "/"+
             IntegerToString(InpMaxLosingPositionsPerDirection)+
             " | current-M5 closed losses="+
             IntegerToString(CountOurClosedNegativeEntriesCurrentM5())+
             "/"+
             IntegerToString(InpMaxClosedNegativeEntriesPerM5)+
             " | BUY post-loss pause="+
             string(DirectionalPostLossPauseActive(1,"status")?"ON":"OFF")+
             " | SELL post-loss pause="+
             string(DirectionalPostLossPauseActive(-1,"status")?"ON":"OFF")+
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
   EnforceDirectionalPostLossPause();

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

         RegisterDirectionalPostLossPauseFromDeal(
            trans.deal,
            true);
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
      EnforceDirectionalPostLossPause();
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
   EnforceDirectionalPostLossPause();

   SaveState();
   DrawActualTradeLevelsGold();
   ChartRedraw(0);

   if(performanceReason!="")
      ReportJournalPerformance(true,performanceReason);
}

//+------------------------------------------------------------------+
