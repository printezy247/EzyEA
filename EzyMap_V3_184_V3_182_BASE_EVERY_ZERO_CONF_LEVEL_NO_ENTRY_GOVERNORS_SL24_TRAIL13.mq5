//+------------------------------------------------------------------+
//| EzyMap Scalp Mastery V3.184                                      |
//| V3.182 base; every zero-confluence level triggers independently. |
//| Zero-confluence only; HIGH/LOW risk + HTF direct touch engine.       |
//+------------------------------------------------------------------+
#property copyright "EzyMap"
#property version   "3.184"

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
input double InpMaximumZoneRangeATR     = 1.80;


input bool   InpShowDirectionLevels    = true;
input bool   InpShowSupportingZones    = true;
input bool   InpShowDashboard          = true;
input bool   InpShowTradeCard          = true;

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

// SL distance modifies the confidence allocation, clamped to 25%-47%.

// Layering across the frozen READY rectangle.

// Automatic account-scaled layering.
// $100 equity is the minimum trading account and corresponds to a 0.01-lot
// BASE layer. Larger accounts scale that base layer proportionally.
// Final layer count is still constrained by the setup's monetary risk budget.
input double InpMinimumAccountEquity      = 5.0; // keep $100 base sizing alive after small drawdown
input double InpBaseEquity                = 100.0;

// V2.002 confidence-based SETUP volume.
// These are TOTAL lots for the complete setup at $100 equity.
// Standard = 1 layer, Good = 2 layers, Quality = 3 layers.
// Larger accounts scale linearly from the $100 rule.
input double InpStandardSetupLotPer100     = 0.01;
input double InpGoodSetupLotPer100         = 0.02;
input double InpQualitySetupLotPer100      = 0.03;
input int    InpGoodConfidenceMin          = 3;
input int    InpQualityConfidenceMin       = 5;

// Hard monetary-risk guard. Confidence lots are reduced if the frozen
// Entry->SL distance would otherwise exceed this percentage of equity.

// Soft daily-volume objective for reporting only.
// The EA never invents a setup merely to reach these numbers.

// V2.008 PARALLEL M5 FREQUENCY.
// Several valid M5 READY setups may wait simultaneously.
// Frequency increases by creating more independent setups,
// NOT by increasing the volume of any one setup.
// V3.081 frequency governor: arm BUY and SELL independently when both are
// valid, but freeze at most one new setup per direction for each completed M5.
// This raises opportunity count without duplicating the same zone every tick.

// Normal confluence-qualified entry tolerance.
// Zero-confluence fallbacks use their separate, wider profile below.
input double InpEntryTouchTolerancePips     = 5.0;

// V3.170 quality zero-confluence profile.
// The 9-pip tolerance applies only to zero-confluence trigger proximity and
// multi-timeframe level clustering. Entry requires a liquidity sweep followed
// by a reclaim on the latest completed M5 candle.
input double InpZeroConfTouchTolerancePips       = 9.0;
input double InpZeroConfClusterTolerancePips     = 9.0;
input bool   InpZeroConfRequireM5SweepReclaim    = false; // V3.184 raw touch: every mapped level
input int    InpZeroConfSweepLookbackM5          = 2;
input bool   InpZeroConfUseBidAskEnvelope        = true;
input bool   InpZeroConfUseTickPathCrossing      = true;

// V3.171: use the same quality concepts in normal confluence-qualified routes.
// These bonuses affect entry qualification only. They do not increase the
// confidence value used by V3.168 balance/confidence lot sizing.

// V2.009 PRECISE CMP EXECUTION.
// READY touch is detected from the symbol's CHART price (Bid or Last),
// matching what is visibly touching the rectangle. Actual BUY/SELL execution
// still uses the broker's executable Ask/Bid prices.
input bool   InpUseChartPriceForReadyTouch  = true;

// Once a legitimate chart CMP touch occurs, keep a short execution latch so
// a transient broker rejection / spread jump does not lose the signal.

// V3.104 prevents OnTick/OnTimer from submitting the same touched setup
// repeatedly during the same tester/server moment. Forced zero-confluence
// entries retry indefinitely at this interval until MARKET is accepted.
input int    InpDeploymentRetryIntervalMs   = 100;

// The user's confidence lot is the target volume. Percentage risk may still
// be reported, but it does not silently shrink a valid 0.01/0.02/0.03 setup.

// If LIMIT/STOP geometry cannot be constructed at a real CMP touch,
// fall back to MARKET layers using the same total setup volume.

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
// V3.026 duplicate protection: a READY rectangle may contain at most one
// EA LIMIT order for its direction. This check includes orders adjusted just
// outside the visual edge by the live broker-distance extension.

// V3.081 directional exposure governor. Positions and pending entry orders
// reserve a layer slot so a later pending fill cannot push the direction
// above the cap. BUY and SELL capacity are independent. A slot is released
// automatically when its position closes or its pending order is cancelled.
input bool   InpEnforceDirectionalLayerCap       = false; // V3.184 unrestricted test
input int    InpMaxActiveLayersPerDirection      = 13;
input bool   InpCountPendingAsReservedLayer      = true;
input bool   InpTrimExcessPendingToLayerCap      = true;

// V3.160 current floating-loss governor.
// BUY and SELL are independent. Once three EA positions in one direction
// have floating net P/L below zero, no new MARKET/LIMIT/STOP exposure is
// allowed in that direction. Existing positions remain managed normally.
input bool   InpEnforceDirectionalLosingCap      = false; // V3.184 unrestricted test
input int    InpMaxLosingPositionsPerDirection   = 3;
input bool   InpCancelPendingAtLosingCap         = true;

// V3.160 current-M5 realised-loss governor.
// Count EA closing deals completed during the current M5 whose realised
// net P/L (profit + commission + swap + fee) is negative. BUY and SELL are
// combined. At two losing closes, all new entries are blocked until next M5.
input bool   InpEnforceM5ClosedLossCap             = false; // V3.184 unrestricted test
input int    InpMaxClosedNegativeEntriesPerM5      = 2;
input bool   InpCancelPendingAtM5ClosedLossCap      = true;

// Real brokers may enforce a larger pending-order distance than Strategy Tester.
// Permit a live LIMIT route to sit just beyond the READY edge when that is the
// nearest broker-valid price. On XAU, 20 strategy pips = 2.00 price.

// Execution controls.
input int    InpDeviationPoints          = 20;

// V3.178 latency-resilient execution. This changes request tolerance and
// delayed-order handling only; zero-confluence signal logic is intact.
input bool   InpLatencySpreadAwareDeviation       = true;
input bool   InpSpreadAwareDeviationInTester      = true;
input int    InpEntrySpreadDeviationCushionPoints = 4;
input int    InpEntryDeviationCapPoints            = 45;
input int    InpExitSpreadDeviationCushionPoints  = 10;
input int    InpExitDeviationCapPoints             = 60;
input double InpMaxMarketAdverseDriftPips          = 3.0;
input bool   InpStageLimitAfterTemporaryMarketFailure = true;

input bool   InpPrintExecutionLog        = true;

// Safety.

// Persistent READY execution.

// v1.014 QUALITY-FREQUENCY.
// READY stays stored for 333 closed M5 candles.
// Orders are deployed only when price returns near the zone and quality re-confirms.

// Compatibility inputs retained for older SET files. The normal V3.081
// policy remains exactly 2 trend-following and 3 counter-trend confluences.

// V3.094 low-exposure exception.
// A valid mapped READY zone may arm with zero required confluences only while
// Direct zero-confluence exposure is limited by current open-position capacity.
const int    V3104_ZERO_CONF_MAX_OPEN_POSITIONS = 1;

// V3.170 zero-confluence zone trigger.
// HIGH-RISK is enabled as a direct zero-confluence execution zone.
// LOW-RISK is eligible only after a completed M5 sweep and reclaim.
const bool   V3170_ZERO_CONF_LOW_RISK_TOUCH_RULE = true;

// Additional V3.102 zero-confluence level trigger.
// BUY fallback stores the current S1 level; SELL fallback stores current R1.
// CMP touch of stored S1 -> BUY routing. Stored R1 -> SELL routing.

// V3.100 adds the outer support/resistance level trigger.
// BUY fallback stores S2; SELL fallback stores R2.
// CMP touch of stored S2 -> BUY routing. Stored R2 -> SELL routing.

// V3.104 has no zero-confluence fill limit per M5 candle.
// Once a zero-confluence trigger touches, execution remains latched until its
// MARKET route is accepted. Quality rechecks, retry expiry, attempt limits
// and current-M5 permanent-failure pauses no longer cancel that entry.

// The direct zero-confluence scanner
// evaluates HIGH-RISK, LOW-RISK, current-map H1, H4, D1 and W1 levels.
// Every direct zero-confluence trigger requires M5 sweep and reclaim.
const bool   V3104_ZERO_CONF_DIRECT_MAP_FALLBACK = true;


// Daily cap on successfully deployed layer orders.


// Zero-confluence direct-map routing only.

// Stop the campaign for the broker day after target/loss threshold.
input double InpDailyEquityTargetPct           = 0.0; // disabled; exits are trade-structure based

// V3.168 broker-day equity risk guard.
// A value of 75 means new entries stop when current account equity reaches
// 25% of the broker-day starting equity. Percentage math is identical for
// standard USD and cent USC accounts; the cent divisor is never applied.
input double InpDailyLossStopPct               = 0.0; // V3.184 disabled for unrestricted trigger test
input bool   InpCloseAllAtDailyTarget          = true;
input bool   InpCloseAllAtDailyLossStop        = false;
input bool   InpCancelPendingAtDailyLossStop   = true;

// Take profit is disabled in V3.081. These inputs remain only for
// backward-compatible SET files and inactive legacy paths.
input bool   InpUseTakeProfit                  = false; // no take profit; exit by preset/trailing SL
input double InpFixedTakeProfitPips            = 0.0;  // retained for compatibility; disabled

// Legacy R target inputs retained for compatibility with inactive routes.
// The active aggressive Market/LIMIT route does not use them for TP.

// Preset protection. Every MARKET/LIMIT/STOP route first attempts to carry
// a visible broker SL exactly 24 strategy pips from its entry. If the broker
// rejects that SL with the opening request, the route is retried without SL
// and the exact virtual stop protects it immediately after fill. No TP is used.
input double InpPresetStopLossPips          = 24.0;
input bool   InpRetryEntryWithoutSLOnReject = true;

// V3.178 broker/virtual protection with no TP, a 24-pip preset SL and a 13-pip trailing stop.
// A preset 24-pip SL is requested with every entry. No TP is submitted. The exact virtual
// SL remains active when broker stop-distance rules require adjustment.
// The initial exact virtual stop is InpPresetStopLossPips from entry, and the EA
// immediately attempts to install the closest broker-compatible SL.
// BUY  stop = best Bid - InpTrailingDistancePips * strategy pip
// SELL stop = best Ask + InpTrailingDistancePips * strategy pip
// On XAU, one strategy pip is 0.10 price; therefore SL24 is 2.40 price and trail13 is 1.30 price.
input bool   InpUseFixedPipTrail               = true;
input bool   InpEnableTrailingAfterEntry        = true;
input double InpTrailingActivationPips         = 0.0;
input double InpTrailingDistancePips           = 13.0;
input double InpTrailingStepPips               = 1.0;

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
input int    InpExitInvalidStopsCooldownMs       = 1200;
input int    InpExitExtraStopCushionPoints       = 3;
input bool   InpExitLogFillSlippage              = true;

// Legacy compatibility inputs retained but hard-disabled in V2.009F.

// Automatic post-test report.
input bool   InpWriteCSVReport                 = true;
input string InpCSVReportPrefix                = "EzyMap_Scalp_Mastery_V3_182_Zero_Conf_Actual_Deal_Report";

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

//
// Phase 2 HYBRID execution model.
// M5 = setup/quality map. M1 = precise execution confirmation.
//

// M1 execution confirmation.

//----------------------------- Constants ----------------------------
#define PRODUCT_NAME "EzyMap Scalp Mastery"
#define PRODUCT_VERSION "V3.184 • EVERY ZERO-CONF LEVEL • UNRESTRICTED ENTRY TEST • SL24/TRAIL13"
#define EMA_LEN 13
#define TREND_MIN_CONFLUENCES 2
#define COUNTER_MIN_CONFLUENCES 3
#define MAX_ZONE_RETESTS 8
#define CONFIRM_WINDOW 12
#define MIN_RR 0.60
#define MAX_RR 2.50
#define BE_ARM_PROGRESS 0.40

string PREFIX="EZYSMV3178SL24TR13_";


struct ZoneInfo
{
   double lo;
   double hi;
   datetime time;
   bool valid;
};


enum EZY_ZERO_CONF_TRIGGER_CODE
{
   EZY_ZC_TRIGGER_NONE=0,
   EZY_ZC_TRIGGER_W1_CLUSTER=1,
   EZY_ZC_TRIGGER_W1_SINGLE=2,
   EZY_ZC_TRIGGER_D1_H4_CLUSTER=3,
   EZY_ZC_TRIGGER_D1_SINGLE=4,
   EZY_ZC_TRIGGER_LOW_RISK=5,
   EZY_ZC_TRIGGER_HIGH_RISK=6,
   EZY_ZC_TRIGGER_H4_SINGLE=7,
   EZY_ZC_TRIGGER_CURRENT_MAP=8,
   EZY_ZC_TRIGGER_CURRENT_OUTER=9
};


struct ZeroConfTriggerMap
{
   bool highRiskValid;
   double highRiskLo;
   double highRiskHi;
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
   double initialExecutablePrice;
   datetime latchedClock;
   datetime lastAttemptClock;
   ulong lastAttemptTickMs;
   int attempts;
};


struct EveryZeroConfLevelState
{
   bool inUse;
   bool inZone;
   bool consumed;
   int direction;
   int code;
   double lo;
   double hi;
   double initialExecutablePrice;
   datetime lastAttemptClock;
   ulong lastAttemptTickMs;
   int attempts;
   ulong lastSeenGeneration;
};

#define V3184_MAX_LEVEL_STATES 64



struct HybridTrailState
{
   ulong    ticket;
   bool     active;
   bool     reconstructed;
   double   peakPrice;
   double   virtualStop;
   datetime positionTime;
   datetime initializedClock;
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
int g_liveSignalCount=0;
int g_executedBasketCount=0;

long g_lastCapturedBuyId=0;
long g_lastCapturedSellId=0;
int g_qualityHoldCount=0;
int g_dailyLayerOrders=0;
int g_dailyDateKey=0;
HybridTrailState g_hybridTrailStates[];
ExitExecutionState g_exitExecutionStates[];

DirectZeroConfState g_directZeroConf;
bool   g_directZeroConfHasPreviousCMP=false;
double g_directZeroConfPreviousCMP=0.0;
EveryZeroConfLevelState g_everyZeroConfStates[V3184_MAX_LEVEL_STATES];
ulong g_everyZeroConfGeneration=0;

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
datetime g_reportFromTime=0;
bool g_reportWritten=false;
ulong g_lastAnalyticsDeal=0;
datetime g_lastStatsReportClock=0;
string g_lastStatsSignature="";

double ReadyTouchCMP(MqlTick &tick);
bool TradeRetcodeAccepted(uint code);
bool TemporaryTradeRetcode(uint code);
bool RetryWithoutSLRetcode(uint code);
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
int CountOurLosingPositionsByDirection(int direction);
bool DirectionalLosingPositionCapacityAvailable(int direction,string context);
void CancelPendingOrdersAtDirectionalLosingCap(int direction);
void EnforceDirectionalLosingPositionCaps();
int CountOurClosedNegativeEntriesCurrentM5();
bool M5ClosedLossCapacityAvailable(string context);
void CancelAllPendingAtM5ClosedLossCap();
void EnforceM5ClosedLossCap();
bool SubmitDirectZeroConfMarket();
ulong LatencyAwareEntryDeviationPoints(ulong baseDeviation);
ulong LatencyAwareExitDeviationPoints(ulong baseDeviation);
bool MarketAdverseDriftExceeded(int direction,double referencePrice,MqlTick &tick,double &driftPips);
bool SubmitDirectZeroConfLimitFallback(int direction,double volume,MqlTick &tick,string reason);
void CollectEveryZeroConfCandidates(ZeroConfTriggerMap &map,int direction,double observedLo,double observedHi,double tolerance,ZeroConfTriggerCandidate &candidates[]);
int FindOrCreateEveryZeroConfState(ZeroConfTriggerCandidate &candidate);
bool SubmitEveryZeroConfCandidate(ZeroConfTriggerCandidate &candidate,EveryZeroConfLevelState &state,MqlTick &tick);
void ProcessEveryZeroConfluenceTriggers();
bool IsLiveXAUUSDscProtectionChart();
double ProtectionTickSize();
double ProtectionPriceDistance(double strategyPips);
double RoundProtectionStop(int direction,double price);
double LiveTrailActivationDistance(MqlTick &tick,double trailDistance);
double BrokerSafeExecutionSL(int direction,double marketPrice,double requestedSL);
double BrokerSafeExecutionTP(int direction,
                             double entryPrice,
                             double requestedTP);
void ManageHybridTrailingPositions(string context);
int HybridTrailStateIndex(ulong ticket);
int EnsureHybridTrailState(ulong ticket,int direction,double entry,double current,datetime positionTime,MqlTick &tick);
double ReconstructTrailPeak(int direction,double entry,datetime positionTime,MqlTick &tick);
double BrokerTrailMinimumDistance();
double BrokerCompatibleTrailSL(int direction,double current,double virtualStop);
int ExitExecutionStateIndexByTicket(ulong ticket);
int ExitExecutionStateIndexByIdentifier(long positionIdentifier);
int EnsureExitExecutionState(ulong ticket);
bool ExitCloseInProgress(ulong ticket);
double LatestBrokerValidExitSL(int direction,double virtualStop,MqlTick &tick);
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
                                      ulong deviation);
void HandleExitExecutionTransaction(const MqlTradeTransaction &trans);
void PruneExitExecutionStates();
bool ClosePositionAtVirtualTrail(ulong ticket,string context,double current,double stop,double peak);
void PruneHybridTrailStates();


void ResetCampaignDay(bool forceReset);
void CheckCampaignDay();
bool DailyRiskCapacityAvailable(string context);
void CancelAllPendingAtDailyRiskLock();
void CloseAllEzyExposure();
double ConfidenceSetupLot(int conf);
double ResolveAccountUnitDivisor();
double EffectiveAccountEquity();
double LotSizingCapitalUnits();
double MinimumTradingEquity();
double CapSetupVolumeForCentSafety(int direction,double entry,double sl,double requested);

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

double StrategyPipSize()
{
   if(IsGold()) return MathMax(0.10,_Point);
   if(IsBTC())  return MathMax(1.0,_Point);
   return _Point;
}

bool IsLiveXAUUSDscProtectionChart()
{
   if((bool)MQLInfoInteger(MQL_TESTER) || !IsGold())
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


double LiveTrailActivationDistance(MqlTick &tick,double trailDistance)
{
   double strategyPip=StrategyPipSize();
   double activation=MathMax(_Point,
                             MathMax(0.0,InpTrailingActivationPips)*strategyPip);

   if(!InpLiveXAUProtectionParity || !IsLiveXAUUSDscProtectionChart())
      return activation;

   if(InpLiveXAURequireFullTrailBeforeArm)
      activation=MathMax(activation,trailDistance);

   if(InpLiveXAUIncludeSpreadInTrailArm)
      activation+=MathMax(0.0,tick.ask-tick.bid);

   activation+=MathMax(0,InpLiveXAUExtraProtectionCushionPoints)*_Point;
   return activation;
}


int TfSeconds(ENUM_TIMEFRAMES tf)
{
   return PeriodSeconds(tf);
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
      case EZY_ZC_TRIGGER_HIGH_RISK:
         return "ZERO-CONF HIGH RISK";
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

   double baseDistance=
      MathMax(70.0*g_pipSize,_Point*5.0);

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
         MathMax(120.0*g_pipSize,baseDistance),
         g_zcD1S1,g_zcD1S2,
         g_zcD1R1,g_zcD1R2);

   bool w1OK=
      BuildZeroConfLevelsForTimeframe(
         PERIOD_W1,
         reference,
         MathMax(200.0*g_pipSize,baseDistance),
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
      map.highRiskValid=g_buyHigh.valid;
      map.highRiskLo=g_buyHigh.lo;
      map.highRiskHi=g_buyHigh.hi;

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
      map.highRiskValid=g_sellHigh.valid;
      map.highRiskLo=g_sellHigh.lo;
      map.highRiskHi=g_sellHigh.hi;

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

   for(int i=0;i<2;i++)
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

   for(int i=0;i<2;i++)
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         2,EZY_ZC_TRIGGER_W1_SINGLE,
         w1[i],w1[i],
         observedLo,observedHi,tolerance);
   }

   for(int i=0;i<2;i++)
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

   for(int i=0;i<2;i++)
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
   if(map.highRiskValid)
   {
      ConsiderZeroConfCandidate(
         candidate,direction,
         6,EZY_ZC_TRIGGER_HIGH_RISK,
         map.highRiskLo,map.highRiskHi,
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

   return candidate.valid;
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

   if(!DailyRiskCapacityAvailable(
         "DIRECT ZERO-CONF "+g_directZeroConf.triggerText))
   {
      g_directZeroConf.active=false;
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
          " | reason=maximum 3 currently losing positions reached");
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
   double exactDistance=ProtectionPriceDistance(InpPresetStopLossPips);
   double exactSL=RoundProtectionStop(
      direction,
      direction==1 ? entry-exactDistance : entry+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(direction,entry,exactSL);

   double requested=ConfidenceSetupLot(0);
   double volume=CapSetupVolumeForCentSafety(direction,entry,brokerSL,requested);
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   if(volume<minVolume-1e-12)
   {
      Log("DIRECT ZERO-CONF MARKET RETRY | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | attempt="+IntegerToString(g_directZeroConf.attempts)+
          " | reason=BASE volume below broker/safety minimum"+
          " | requested="+DoubleToString(requested,VolumeDigits())+
          " | safe="+DoubleToString(volume,VolumeDigits())+
          " | minimum="+DoubleToString(minVolume,VolumeDigits()));
      return false;
   }

   double driftPips=0.0;
   if(MarketAdverseDriftExceeded(direction,
                                 g_directZeroConf.initialExecutablePrice,
                                 tick,
                                 driftPips))
   {
      if(SubmitDirectZeroConfLimitFallback(
            direction,
            volume,
            tick,
            "adverse MARKET drift "+DoubleToString(driftPips,1)+" pips"))
      {
         g_directZeroConf.active=false;
         if(direction==1) g_directZeroConf.buyTouchConsumed=true;
         else g_directZeroConf.sellTouchConsumed=true;
         return true;
      }

      Log("DIRECT ZERO-CONF MARKET CHASE BLOCKED | trigger="+
          g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | adverse drift="+DoubleToString(driftPips,1)+" pips"+
          " | maximum="+DoubleToString(InpMaxMarketAdverseDriftPips,1));
      return false;
   }

   string comment=PREFIX+"DIRECT_ZC_"+string(direction==1?"BUY_":"SELL_")+
                  IntegerToString(g_directZeroConf.attempts);

   ulong baseDeviation=(ulong)MathMax(0,InpDeviationPoints);
   trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
   bool sent=(direction==1)
             ? trade.Buy(volume,_Symbol,0.0,brokerSL,0.0,comment)
             : trade.Sell(volume,_Symbol,0.0,brokerSL,0.0,comment);
   trade.SetDeviationInPoints(baseDeviation);

   uint retcode=trade.ResultRetcode();
   bool accepted=(sent && TradeRetcodeAccepted(retcode));
   bool openedWithoutSL=false;

   if(!accepted && InpRetryEntryWithoutSLOnReject && RetryWithoutSLRetcode(retcode))
   {
      trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
      sent=(direction==1)
           ? trade.Buy(volume,_Symbol,0.0,0.0,0.0,comment)
           : trade.Sell(volume,_Symbol,0.0,0.0,0.0,comment);
      trade.SetDeviationInPoints(baseDeviation);
      retcode=trade.ResultRetcode();
      accepted=(sent && TradeRetcodeAccepted(retcode));
      openedWithoutSL=accepted;
   }

   if(!accepted)
   {
      bool temporary=TemporaryTradeRetcode(retcode);
      if(temporary &&
         SubmitDirectZeroConfLimitFallback(
            direction,
            volume,
            tick,
            "temporary MARKET retcode "+IntegerToString((int)retcode)))
      {
         g_directZeroConf.active=false;
         if(direction==1) g_directZeroConf.buyTouchConsumed=true;
         else g_directZeroConf.sellTouchConsumed=true;
         return true;
      }

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
       " | priority="+IntegerToString(g_directZeroConf.triggerPriority)+
       " | reclaim="+
       TimeToString(g_directZeroConf.reclaimTime,TIME_DATE|TIME_MINUTES)+
       " | SL24="+string(openedWithoutSL?"virtual/broker install pending":
                         DoubleToString(brokerSL,_Digits))+
       " | TP=NONE | trail13=ACTIVE");

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
            g_directZeroConf.initialExecutablePrice=(chosenDirection==1)?tick.ask:tick.bid;
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


//---------------- V3.184 every zero-confluence level engine ----------------
void AppendEveryZeroConfCandidate(ZeroConfTriggerCandidate &candidates[],
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

   if(!SensitiveEnvelopeTouchesZone(observedLo,observedHi,lo,hi,tolerance))
      return;

   // Every distinct mapped level is eligible on raw live touch. No M5
   // sweep/reclaim, confidence, position-count, candle-loss or layer-cap gate.
   int count=ArraySize(candidates);
   for(int i=0;i<count;i++)
   {
      if(candidates[i].direction==direction &&
         candidates[i].code==code &&
         MathAbs(candidates[i].lo-lo)<=_Point*0.25 &&
         MathAbs(candidates[i].hi-hi)<=_Point*0.25)
         return;
   }

   ArrayResize(candidates,count+1);
   ZeroConfTriggerCandidate item;
   ResetZeroConfCandidate(item);
   item.valid=true;
   item.direction=direction;
   item.priority=priority;
   item.code=code;
   item.lo=lo;
   item.hi=hi;
   item.distance=MathAbs((observedLo+observedHi)*0.5-(lo+hi)*0.5);
   item.reclaimTime=TimeCurrent();
   candidates[count]=item;
}

void CollectEveryZeroConfCandidates(ZeroConfTriggerMap &map,
                                    int direction,
                                    double observedLo,
                                    double observedHi,
                                    double tolerance,
                                    ZeroConfTriggerCandidate &candidates[])
{
   ArrayResize(candidates,0);

   double clusterTolerance=MathMax(0.0,InpZeroConfClusterTolerancePips)*g_pipSize;
   double w1[2],d1[2],h4[2],current[2];
   w1[0]=map.w1Level1; w1[1]=map.w1Level2;
   d1[0]=map.d1Level1; d1[1]=map.d1Level2;
   h4[0]=map.h4Level1; h4[1]=map.h4Level2;
   current[0]=map.currentLevel1; current[1]=map.currentLevel2;

   for(int i=0;i<2;i++)
   {
      if(w1[i]>0.0)
      {
         double partner=NearestClusterPartner(w1[i],d1[0],d1[1],h4[0],h4[1],clusterTolerance);
         if(partner>0.0)
            AppendEveryZeroConfCandidate(candidates,direction,1,EZY_ZC_TRIGGER_W1_CLUSTER,
                                         MathMin(w1[i],partner),MathMax(w1[i],partner),
                                         observedLo,observedHi,tolerance);
      }
      AppendEveryZeroConfCandidate(candidates,direction,2,EZY_ZC_TRIGGER_W1_SINGLE,
                                   w1[i],w1[i],observedLo,observedHi,tolerance);
   }

   for(int i=0;i<2;i++)
   {
      if(d1[i]>0.0)
      {
         double partner=NearestClusterPartner(d1[i],h4[0],h4[1],0.0,0.0,clusterTolerance);
         if(partner>0.0)
            AppendEveryZeroConfCandidate(candidates,direction,3,EZY_ZC_TRIGGER_D1_H4_CLUSTER,
                                         MathMin(d1[i],partner),MathMax(d1[i],partner),
                                         observedLo,observedHi,tolerance);
      }
      AppendEveryZeroConfCandidate(candidates,direction,4,EZY_ZC_TRIGGER_D1_SINGLE,
                                   d1[i],d1[i],observedLo,observedHi,tolerance);
   }

   if(map.lowRiskValid)
      AppendEveryZeroConfCandidate(candidates,direction,5,EZY_ZC_TRIGGER_LOW_RISK,
                                   map.lowRiskLo,map.lowRiskHi,observedLo,observedHi,tolerance);
   if(map.highRiskValid)
      AppendEveryZeroConfCandidate(candidates,direction,6,EZY_ZC_TRIGGER_HIGH_RISK,
                                   map.highRiskLo,map.highRiskHi,observedLo,observedHi,tolerance);

   for(int i=0;i<2;i++)
      AppendEveryZeroConfCandidate(candidates,direction,7,EZY_ZC_TRIGGER_H4_SINGLE,
                                   h4[i],h4[i],observedLo,observedHi,tolerance);

   AppendEveryZeroConfCandidate(candidates,direction,8,EZY_ZC_TRIGGER_CURRENT_MAP,
                                current[0],current[0],observedLo,observedHi,tolerance);
   AppendEveryZeroConfCandidate(candidates,direction,8,EZY_ZC_TRIGGER_CURRENT_OUTER,
                                current[1],current[1],observedLo,observedHi,tolerance);
}

int FindOrCreateEveryZeroConfState(ZeroConfTriggerCandidate &candidate)
{
   int reusable=-1;
   for(int i=0;i<V3184_MAX_LEVEL_STATES;i++)
   {
      if(g_everyZeroConfStates[i].inUse)
      {
         if(g_everyZeroConfStates[i].direction==candidate.direction &&
            g_everyZeroConfStates[i].code==candidate.code &&
            MathAbs(g_everyZeroConfStates[i].lo-candidate.lo)<=_Point*0.5 &&
            MathAbs(g_everyZeroConfStates[i].hi-candidate.hi)<=_Point*0.5)
            return i;

         if(reusable<0 && g_everyZeroConfStates[i].lastSeenGeneration+2<g_everyZeroConfGeneration)
            reusable=i;
      }
      else if(reusable<0)
         reusable=i;
   }

   if(reusable<0)
      reusable=0;

   g_everyZeroConfStates[reusable].inUse=true;
   g_everyZeroConfStates[reusable].inZone=false;
   g_everyZeroConfStates[reusable].consumed=false;
   g_everyZeroConfStates[reusable].direction=candidate.direction;
   g_everyZeroConfStates[reusable].code=candidate.code;
   g_everyZeroConfStates[reusable].lo=candidate.lo;
   g_everyZeroConfStates[reusable].hi=candidate.hi;
   g_everyZeroConfStates[reusable].initialExecutablePrice=0.0;
   g_everyZeroConfStates[reusable].lastAttemptClock=0;
   g_everyZeroConfStates[reusable].lastAttemptTickMs=0;
   g_everyZeroConfStates[reusable].attempts=0;
   g_everyZeroConfStates[reusable].lastSeenGeneration=0;
   return reusable;
}

bool EveryZeroConfRetryElapsed(EveryZeroConfLevelState &state)
{
   if(state.lastAttemptClock<=0)
      return true;
   if(TimeCurrent()>state.lastAttemptClock)
      return true;
   ulong nowMs=GetTickCount64();
   if(nowMs<state.lastAttemptTickMs)
      return true;
   return (nowMs-state.lastAttemptTickMs >= (ulong)MathMax(0,InpDeploymentRetryIntervalMs));
}

bool SubmitEveryZeroConfLimitFallback(ZeroConfTriggerCandidate &candidate,
                                      EveryZeroConfLevelState &state,
                                      double volume,
                                      MqlTick &tick,
                                      string reason)
{
   if(!InpStageLimitAfterTemporaryMarketFailure)
      return false;

   int direction=candidate.direction;
   double reference=state.initialExecutablePrice;
   if(reference<=0.0)
      reference=(candidate.lo+candidate.hi)*0.5;
   if(reference<=0.0)
      return false;

   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax(_Point,
                         ((double)MathMax(stopsLevel,freezeLevel)+
                          MathMax(0,InpExecutionStopCushionPoints))*_Point);

   double pending=(direction==1)
                  ? MathMin(reference,tick.ask-minDist)
                  : MathMax(reference,tick.bid+minDist);
   pending=RoundPrice(pending);

   if((direction==1 && pending>=tick.ask-minDist+_Point*0.25) ||
      (direction==-1 && pending<=tick.bid+minDist-_Point*0.25))
      return false;

   double exactDistance=ProtectionPriceDistance(InpPresetStopLossPips);
   double exactSL=RoundProtectionStop(direction,
                    direction==1 ? pending-exactDistance : pending+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(direction,pending,exactSL);
   string text=ZeroConfTriggerCodeText(candidate.code,direction);
   string comment=PREFIX+"EVERY_ZC_LIMIT_"+
                  string(direction==1?"BUY_":"SELL_")+IntegerToString(state.attempts);

   ulong baseDeviation=(ulong)MathMax(0,InpDeviationPoints);
   trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
   bool sent=(direction==1)
             ? trade.BuyLimit(volume,pending,_Symbol,brokerSL,0.0,ORDER_TIME_GTC,0,comment)
             : trade.SellLimit(volume,pending,_Symbol,brokerSL,0.0,ORDER_TIME_GTC,0,comment);
   trade.SetDeviationInPoints(baseDeviation);

   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);
   if(!accepted && InpRetryEntryWithoutSLOnReject && RetryWithoutSLRetcode(code))
   {
      trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
      sent=(direction==1)
           ? trade.BuyLimit(volume,pending,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment)
           : trade.SellLimit(volume,pending,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
      trade.SetDeviationInPoints(baseDeviation);
      code=trade.ResultRetcode();
      accepted=sent && TradeRetcodeAccepted(code);
   }

   if(accepted)
   {
      g_dailyLayerOrders++;
      Log("EVERY ZERO-CONF LIMIT PLACED | trigger="+text+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | zone="+DoubleToString(candidate.lo,_Digits)+".."+
          DoubleToString(candidate.hi,_Digits)+
          " | price="+DoubleToString(pending,_Digits)+
          " | volume="+DoubleToString(volume,VolumeDigits())+
          " | reason="+reason);
      return true;
   }

   Log("EVERY ZERO-CONF LIMIT FAILED | trigger="+text+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());
   return false;
}

bool SubmitEveryZeroConfCandidate(ZeroConfTriggerCandidate &candidate,
                                  EveryZeroConfLevelState &state,
                                  MqlTick &tick)
{
   if(state.consumed || !EveryZeroConfRetryElapsed(state))
      return false;

   state.lastAttemptClock=TimeCurrent();
   state.lastAttemptTickMs=GetTickCount64();
   state.attempts++;

   string envReason="";
   if(!TradingEnvironmentReady(envReason))
      return false;

   int direction=candidate.direction;
   double entry=(direction==1)?tick.ask:tick.bid;
   if(state.initialExecutablePrice<=0.0)
      state.initialExecutablePrice=entry;

   double exactDistance=ProtectionPriceDistance(InpPresetStopLossPips);
   double exactSL=RoundProtectionStop(direction,
                    direction==1 ? entry-exactDistance : entry+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(direction,entry,exactSL);

   double requested=ConfidenceSetupLot(0);
   double volume=CapSetupVolumeForCentSafety(direction,entry,brokerSL,requested);
   double minVolume=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(volume<minVolume-1e-12)
      return false;

   double driftPips=0.0;
   if(MarketAdverseDriftExceeded(direction,state.initialExecutablePrice,tick,driftPips))
   {
      if(SubmitEveryZeroConfLimitFallback(candidate,state,volume,tick,
            "adverse MARKET drift "+DoubleToString(driftPips,1)+" pips"))
      {
         state.consumed=true;
         return true;
      }
      return false;
   }

   string text=ZeroConfTriggerCodeText(candidate.code,direction);
   string comment=PREFIX+"EVERY_ZC_"+
                  string(direction==1?"BUY_":"SELL_")+IntegerToString(state.attempts);
   ulong baseDeviation=(ulong)MathMax(0,InpDeviationPoints);
   trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
   bool sent=(direction==1)
             ? trade.Buy(volume,_Symbol,0.0,brokerSL,0.0,comment)
             : trade.Sell(volume,_Symbol,0.0,brokerSL,0.0,comment);
   trade.SetDeviationInPoints(baseDeviation);

   uint retcode=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(retcode);
   bool openedWithoutSL=false;
   if(!accepted && InpRetryEntryWithoutSLOnReject && RetryWithoutSLRetcode(retcode))
   {
      trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
      sent=(direction==1)
           ? trade.Buy(volume,_Symbol,0.0,0.0,0.0,comment)
           : trade.Sell(volume,_Symbol,0.0,0.0,0.0,comment);
      trade.SetDeviationInPoints(baseDeviation);
      retcode=trade.ResultRetcode();
      accepted=sent && TradeRetcodeAccepted(retcode);
      openedWithoutSL=accepted;
   }

   if(!accepted)
   {
      if(TemporaryTradeRetcode(retcode) &&
         SubmitEveryZeroConfLimitFallback(candidate,state,volume,tick,
            "temporary MARKET retcode "+IntegerToString((int)retcode)))
      {
         state.consumed=true;
         return true;
      }
      return false;
   }

   g_dailyLayerOrders++;
   state.consumed=true;
   Log("EVERY ZERO-CONF LEVEL EXECUTED | trigger="+text+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | zone="+DoubleToString(candidate.lo,_Digits)+".."+
       DoubleToString(candidate.hi,_Digits)+
       " | volume="+DoubleToString(volume,VolumeDigits())+
       " | attempt="+IntegerToString(state.attempts)+
       " | SL24="+string(openedWithoutSL?"virtual/broker install pending":DoubleToString(brokerSL,_Digits))+
       " | TP=NONE | trail13=ACTIVE");
   return true;
}

void ProcessEveryZeroConfluenceTriggers()
{
   if(!V3104_ZERO_CONF_DIRECT_MAP_FALLBACK)
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

   g_everyZeroConfGeneration++;
   if(g_everyZeroConfGeneration==0)
      g_everyZeroConfGeneration=1;

   ZeroConfTriggerMap buyMap,sellMap;
   BuildCurrentZeroConfTriggerMap(1,buyMap);
   BuildCurrentZeroConfTriggerMap(-1,sellMap);
   ZeroConfTriggerCandidate buyCandidates[],sellCandidates[];
   CollectEveryZeroConfCandidates(buyMap,1,observedLo,observedHi,tolerance,buyCandidates);
   CollectEveryZeroConfCandidates(sellMap,-1,observedLo,observedHi,tolerance,sellCandidates);

   int buyCount=ArraySize(buyCandidates);
   for(int i=0;i<buyCount;i++)
   {
      int stateIndex=FindOrCreateEveryZeroConfState(buyCandidates[i]);
      g_everyZeroConfStates[stateIndex].lastSeenGeneration=g_everyZeroConfGeneration;
      if(!g_everyZeroConfStates[stateIndex].inZone)
      {
         g_everyZeroConfStates[stateIndex].inZone=true;
         g_everyZeroConfStates[stateIndex].consumed=false;
         g_everyZeroConfStates[stateIndex].initialExecutablePrice=tick.ask;
         g_everyZeroConfStates[stateIndex].attempts=0;
         g_everyZeroConfStates[stateIndex].lastAttemptClock=0;
         g_everyZeroConfStates[stateIndex].lastAttemptTickMs=0;
      }
      SubmitEveryZeroConfCandidate(buyCandidates[i],g_everyZeroConfStates[stateIndex],tick);
   }

   int sellCount=ArraySize(sellCandidates);
   for(int i=0;i<sellCount;i++)
   {
      int stateIndex=FindOrCreateEveryZeroConfState(sellCandidates[i]);
      g_everyZeroConfStates[stateIndex].lastSeenGeneration=g_everyZeroConfGeneration;
      if(!g_everyZeroConfStates[stateIndex].inZone)
      {
         g_everyZeroConfStates[stateIndex].inZone=true;
         g_everyZeroConfStates[stateIndex].consumed=false;
         g_everyZeroConfStates[stateIndex].initialExecutablePrice=tick.bid;
         g_everyZeroConfStates[stateIndex].attempts=0;
         g_everyZeroConfStates[stateIndex].lastAttemptClock=0;
         g_everyZeroConfStates[stateIndex].lastAttemptTickMs=0;
      }
      SubmitEveryZeroConfCandidate(sellCandidates[i],g_everyZeroConfStates[stateIndex],tick);
   }

   // A level becomes eligible again only after price leaves its touch envelope.
   // There is no global latch, open-position cap, per-candle fill cap, losing-
   // position cap, directional layer ceiling or daily-loss entry lock.
   for(int i=0;i<V3184_MAX_LEVEL_STATES;i++)
   {
      if(!g_everyZeroConfStates[i].inUse)
         continue;
      if(g_everyZeroConfStates[i].lastSeenGeneration!=g_everyZeroConfGeneration)
      {
         g_everyZeroConfStates[i].inZone=false;
         g_everyZeroConfStates[i].consumed=false;
         g_everyZeroConfStates[i].initialExecutablePrice=0.0;
         g_everyZeroConfStates[i].attempts=0;
         g_everyZeroConfStates[i].lastAttemptClock=0;
         g_everyZeroConfStates[i].lastAttemptTickMs=0;
      }
   }
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
                             double requestedSL)
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
               MathMax(0,InpExecutionStopCushionPoints))*_Point);

   if(direction==1)
      return requestedSL<=currentPrice-minimumDistance+_Point*0.25;

   return requestedSL>=currentPrice+minimumDistance-_Point*0.25;
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
   g_hybridTrailStates[index].initializedClock=TimeCurrent();

   g_hybridTrailStates[index].peakPrice=
      ReconstructTrailPeak(direction,entry,positionTime,tick);
   g_hybridTrailStates[index].reconstructed=true;
   return index;
}

double BrokerTrailMinimumDistance()
{
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   int cushion=MathMax(MathMax(0,InpExecutionStopCushionPoints),
                       MathMax(0,InpTrailBrokerCushionPoints));

   return MathMax(_Point,
                  ((double)MathMax(stopsLevel,freezeLevel)+cushion)*_Point);
}

double BrokerCompatibleTrailSL(int direction,
                               double current,
                               double virtualStop)
{
   double minDistance=BrokerTrailMinimumDistance();
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

   ulong now=GetTickCount64();

   if(now<g_exitExecutionStates[index].closeLockUntilMs)
      return true;

   if(PositionSelectByTicket(ticket))
   {
      Log("V3.178 EXIT CLOSE LOCK TIMEOUT"+
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
                               MqlTick &tick)
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
          cushion)*_Point);

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

   ulong now=GetTickCount64();

   if(InpSynchronizeExitRequests &&
      now<g_exitExecutionStates[stateIndex].modifyCooldownUntilMs)
      return false;

   if(InpSynchronizeExitRequests &&
      g_exitExecutionStates[stateIndex].lastModifyAttemptMs>0 &&
      now-g_exitExecutionStates[stateIndex].lastModifyAttemptMs<
      (ulong)MathMax(0,InpExitModifyMinimumIntervalMs))
      return false;

   MqlTick latestTick;
   double brokerSL=
      LatestBrokerValidExitSL(
         direction,
         virtualStop,
         latestTick);

   if(brokerSL<=0.0)
      return false;

   double current=
      direction==1 ? latestTick.bid : latestTick.ask;

   if(!FixedTrailSLBrokerValid(direction,current,brokerSL))
   {
      g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
         now+
         (ulong)MathMax(
            0,
            InpExitInvalidStopsCooldownMs);
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
      g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
         now+
         (ulong)MathMax(
            0,
            InpExitModifyMinimumIntervalMs);

      submittedSL=brokerSL;

      Log("V3.178 SYNCHRONIZED SL ACCEPTED | "+context+
          " | purpose="+purpose+
          " | ticket="+(string)ticket+
          " | Bid="+DoubleToString(latestTick.bid,_Digits)+
          " | Ask="+DoubleToString(latestTick.ask,_Digits)+
          " | virtualSL="+DoubleToString(virtualStop,_Digits)+
          " | submittedSL="+DoubleToString(brokerSL,_Digits));
      return true;
   }

   int cooldown=
      code==TRADE_RETCODE_INVALID_STOPS
      ? MathMax(0,InpExitInvalidStopsCooldownMs)
      : MathMax(0,InpExitModifyMinimumIntervalMs);

   g_exitExecutionStates[stateIndex].modifyCooldownUntilMs=
      now+(ulong)cooldown;

   Log("V3.178 SYNCHRONIZED SL REJECTED | "+context+
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
       " | cooldown="+IntegerToString(cooldown)+"ms"+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());

   return false;
}


bool RequestSynchronizedPositionClose(ulong ticket,
                                      string context,
                                      double stop,
                                      double peak,
                                      ulong deviation)
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

   ulong now=GetTickCount64();

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

   deviation=LatencyAwareExitDeviationPoints(deviation);
   trade.SetDeviationInPoints(deviation);
   bool sent=trade.PositionClose(ticket,deviation);
   uint code=trade.ResultRetcode();
   trade.SetDeviationInPoints(
      (ulong)MathMax(0,InpDeviationPoints));

   bool accepted=
      sent && TradeRetcodeAccepted(code);

   bool alreadyClosing=
      code==TRADE_RETCODE_CLOSE_ORDER_EXIST;

   if(accepted || alreadyClosing)
   {
      Log("V3.178 SYNCHRONIZED CLOSE REQUEST | "+context+
          " | ticket="+(string)ticket+
          " | position id="+
          (string)g_exitExecutionStates[stateIndex].positionIdentifier+
          " | requested price="+
          DoubleToString(requestedClosePrice,_Digits)+
          " | stop="+DoubleToString(stop,_Digits)+
          " | peak="+DoubleToString(peak,_Digits)+
          " | deviation="+(string)deviation+
          " | close lock="+
          IntegerToString(
             MathMax(250,InpExitCloseLockTimeoutMs))+
          "ms"+
          " | retcode="+IntegerToString((int)code));
      return true;
   }

   g_exitExecutionStates[stateIndex].closeInProgress=false;

   Log("V3.178 SYNCHRONIZED CLOSE REJECTED | "+context+
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

   ulong now=GetTickCount64();
   ulong elapsed=
      now>=g_exitExecutionStates[stateIndex].closeRequestMs
      ? now-g_exitExecutionStates[stateIndex].closeRequestMs
      : 0;

   if(InpExitLogFillSlippage)
   {
      Log("V3.178 LIVE EXIT FILL"+
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

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double strategyPip=StrategyPipSize();
   double trailDistance=ProtectionPriceDistance(InpTrailingDistancePips);
   double presetDistance=ProtectionPriceDistance(InpPresetStopLossPips);
   double activationDistance=LiveTrailActivationDistance(tick,trailDistance);
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

      // Exact preset protection is active from fill, before favourable movement.
      double initialVirtualStop=RoundProtectionStop(
         direction,
         direction==1 ? entry-presetDistance : entry+presetDistance);
      if(g_hybridTrailStates[stateIndex].virtualStop<=0.0)
         g_hybridTrailStates[stateIndex].virtualStop=initialVirtualStop;

      bool initialVirtualHit=(direction==1)
                             ? current<=initialVirtualStop+_Point*0.25
                             : current>=initialVirtualStop-_Point*0.25;
      if(InpUseVirtualTrailFallback && initialVirtualHit)
      {
         ClosePositionAtVirtualTrail(ticket,context,current,initialVirtualStop,peak);
         continue;
      }

      double initialBrokerSL=BrokerCompatibleTrailSL(direction,current,initialVirtualStop);
      bool initialImproves=currentSL<=0.0 ||
         (direction==1 ? initialBrokerSL>currentSL+_Point*0.25
                       : initialBrokerSL<currentSL-_Point*0.25);
      if(initialImproves && initialBrokerSL>0.0 &&
         FixedTrailSLBrokerValid(direction,current,initialBrokerSL))
      {
         double submittedSL=0.0;
         bool initialSent=
            RequestSynchronizedPositionModify(
               ticket,
               direction,
               initialVirtualStop,
               currentTP,
               context,
               "PRESET SL",
               submittedSL);

         if(initialSent)
            currentSL=submittedSL;
      }

      bool liveProtectionChart=
         InpLiveXAUProtectionParity && IsLiveXAUUSDscProtectionChart();

      bool liveWarmupComplete=
         !liveProtectionChart ||
         InpLiveXAUTrailWarmupSeconds<=0 ||
         TimeCurrent()>=g_hybridTrailStates[stateIndex].initializedClock+
                        InpLiveXAUTrailWarmupSeconds;

      if(InpEnableTrailingAfterEntry &&
         !g_hybridTrailStates[stateIndex].active &&
         liveWarmupComplete &&
         peakFavourable>=activationDistance-_Point*0.25)
      {
         g_hybridTrailStates[stateIndex].active=true;
         Log("HYBRID 7-PIP TRAIL ARMED | "+context+
             " | ticket="+(string)ticket+
             " | entry="+DoubleToString(entry,_Digits)+
             " | peak="+DoubleToString(peak,_Digits)+
             " | favourable="+DoubleToString(peakFavourable/strategyPip,1)+" pips"+
             " | required="+DoubleToString(activationDistance/strategyPip,1)+" pips"+
             " | live parity="+string(liveProtectionChart?"YES":"NO"));
      }

      if(InpEnableTrailingAfterEntry && g_hybridTrailStates[stateIndex].active)
      {
         double virtualStop=RoundProtectionStop(
            direction,
            direction==1 ? peak-trailDistance : peak+trailDistance);
         if(direction==1) virtualStop=MathMax(virtualStop,initialVirtualStop);
         else             virtualStop=MathMin(virtualStop,initialVirtualStop);
         g_hybridTrailStates[stateIndex].virtualStop=virtualStop;

         bool virtualHit=(direction==1)
                         ? current<=virtualStop+_Point*0.25
                         : current>=virtualStop-_Point*0.25;

         if(InpUseVirtualTrailFallback && virtualHit)
         {
            ClosePositionAtVirtualTrail(ticket,context,current,virtualStop,peak);
            continue;
         }

         double desiredSL=BrokerCompatibleTrailSL(direction,current,virtualStop);
         bool improves=currentSL<=0.0 ||
            (direction==1
             ? desiredSL>currentSL+minimumStep-_Point*0.25
             : desiredSL<currentSL-minimumStep+_Point*0.25);

         if(improves && desiredSL>0.0 && FixedTrailSLBrokerValid(direction,current,desiredSL))
         {
            double submittedSL=0.0;
            bool accepted=
               RequestSynchronizedPositionModify(
                  ticket,
                  direction,
                  virtualStop,
                  currentTP,
                  context,
                  "TRAILING SL",
                  submittedSL);

            if(accepted)
            {
               currentSL=submittedSL;

               Log("HYBRID BROKER SL MOVED | "+context+
                   " | ticket="+(string)ticket+
                   " | peak="+DoubleToString(peak,_Digits)+
                   " | virtualSL="+DoubleToString(virtualStop,_Digits)+
                   " | brokerSL="+DoubleToString(submittedSL,_Digits));
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

   DeleteObject("CARD");
   int rows=4;
   Panel("CARD_PANEL",14,38,315,34+rows*17,
         InpPanelColor,InpPanelBorderColor);

   CardRow(0,"ZERO-CONFLUENCE ONLY",InpPanelHeaderColor,true);
   CardRow(1,_Symbol+" • "+g_mode+" • "+g_tfLabel,
           InpNeutralColor,false);
   CardRow(2,"POSITIONS  "+IntegerToString(CountOurPositions())+
             "  |  PENDING  "+IntegerToString(CountOurPendingOrders()),
           InpNeutralColor,false);
   CardRow(3,"EVERY ZERO-CONF LEVEL ACTIVE",InpBuyColor,true);

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
}


void ClearHistoricalMarkers()
{
   int n=ArraySize(g_historicalMarkerNames);
   for(int i=0;i<n;i++)
      ObjectDelete(0,g_historicalMarkerNames[i]);

   ArrayResize(g_historicalMarkerNames,0);
}

//-------------------------- Signal engine ---------------------------


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

   double reference=m5[1].close;
   double directionATR=ATRFromRates(h1,ArraySize(h1),14,1);
   double directionEMA=EMAFromRates(h1,ArraySize(h1),EMA_LEN,1);

   if(directionATR==EMPTY_VALUE || directionEMA==EMPTY_VALUE)
      return false;

   double directionLow=DBL_MAX;
   double directionHigh=-DBL_MAX;
   int dirN=MathMin(100,ArraySize(h1)-1);

   for(int i=1;i<=dirN;i++)
   {
      directionLow=MathMin(directionLow,h1[i].low);
      directionHigh=MathMax(directionHigh,h1[i].high);
   }

   double minimumLevelDistance=MathMax(70.0*g_pipSize,_Point*5.0);

   PickDirectionLevels(h1,ArraySize(h1),reference,
                       minimumLevelDistance,
                       directionLow,directionHigh,directionATR,
                       g_S1,g_S2,g_R1,g_R2);

   RefreshZeroConfHigherTimeframeLevels(reference);

   double directionClose=h1[1].close;
   g_biasText=directionClose>directionEMA
              ? "BULLISH"
              : (directionClose<directionEMA ? "BEARISH" : "NEUTRAL");

   g_trendBuyRoute=(g_biasText=="BULLISH");
   g_trendSellRoute=(g_biasText=="BEARISH");

   double supportATR=ATRFromRates(m15,ArraySize(m15),14,1);
   if(supportATR==EMPTY_VALUE)
      return false;

   g_buyHigh=V120SignalZoneFromLevel(g_S1,g_S2,true,
                                     m15,ArraySize(m15),supportATR);
   g_buyLow=V120SignalZoneFromLevel(g_S2,g_S1,true,
                                    m15,ArraySize(m15),supportATR);
   g_sellHigh=V120SignalZoneFromLevel(g_R1,g_R2,false,
                                      m15,ArraySize(m15),supportATR);
   g_sellLow=V120SignalZoneFromLevel(g_R2,g_R1,false,
                                     m15,ArraySize(m15),supportATR);

   g_buyHighConf=0;
   g_sellHighConf=0;
   g_lastEntryClosedTime=m5[1].time;
   return true;
}


//---------------------------- Constants -----------------------------
#define LAYER_MARKET 0
#define LAYER_LIMIT  1
#define LAYER_STOP   2


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

      double protectionDistance=ProtectionPriceDistance(InpTrailingDistancePips);
      double protectionSL=RoundProtectionStop(
         direction,
         direction==1 ? entry-protectionDistance : entry+protectionDistance);
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


//---------------- V3.178 latency-resilient execution ----------------
ulong LatencyAwareDeviationCore(ulong baseDeviation,
                                int cushionPoints,
                                int capPoints)
{
   if(!InpLatencySpreadAwareDeviation)
      return baseDeviation;

   bool tester=(bool)MQLInfoInteger(MQL_TESTER) ||
               (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   if(tester && !InpSpreadAwareDeviationInTester)
      return baseDeviation;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || _Point<=0.0)
      return baseDeviation;

   double spreadPoints=MathMax(0.0,(tick.ask-tick.bid)/_Point);
   ulong spreadFloor=(ulong)MathCeil(spreadPoints)+
                     (ulong)MathMax(0,cushionPoints);
   ulong result=MathMax(baseDeviation,spreadFloor);

   if(capPoints>0)
      result=MathMin(result,(ulong)capPoints);

   return result;
}

ulong LatencyAwareEntryDeviationPoints(ulong baseDeviation)
{
   return LatencyAwareDeviationCore(baseDeviation,
                                    InpEntrySpreadDeviationCushionPoints,
                                    InpEntryDeviationCapPoints);
}

ulong LatencyAwareExitDeviationPoints(ulong baseDeviation)
{
   return LatencyAwareDeviationCore(baseDeviation,
                                    InpExitSpreadDeviationCushionPoints,
                                    InpExitDeviationCapPoints);
}

bool MarketAdverseDriftExceeded(int direction,
                                double referencePrice,
                                MqlTick &tick,
                                double &driftPips)
{
   driftPips=0.0;
   double pip=StrategyPipSize();
   if(referencePrice<=0.0 || pip<=0.0 || InpMaxMarketAdverseDriftPips<=0.0)
      return false;

   double current=(direction==1)?tick.ask:tick.bid;
   double adverse=(direction==1)?current-referencePrice:referencePrice-current;
   adverse=MathMax(0.0,adverse);
   driftPips=adverse/pip;
   return driftPips>InpMaxMarketAdverseDriftPips+1e-9;
}

bool SubmitDirectZeroConfLimitFallback(int direction,
                                       double volume,
                                       MqlTick &tick,
                                       string reason)
{
   if(!InpStageLimitAfterTemporaryMarketFailure)
      return false;

   double reference=g_directZeroConf.initialExecutablePrice;
   if(reference<=0.0)
      reference=(g_directZeroConf.triggerLo+g_directZeroConf.triggerHi)*0.5;
   if(reference<=0.0)
      return false;

   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   double minDist=MathMax(_Point,
                         ((double)MathMax(stopsLevel,freezeLevel)+
                          MathMax(0,InpExecutionStopCushionPoints))*_Point);

   double pending=(direction==1)
                  ? MathMin(reference,tick.ask-minDist)
                  : MathMax(reference,tick.bid+minDist);
   pending=RoundPrice(pending);

   if((direction==1 && pending>=tick.ask-minDist+_Point*0.25) ||
      (direction==-1 && pending<=tick.bid+minDist-_Point*0.25))
      return false;

   double exactDistance=ProtectionPriceDistance(InpPresetStopLossPips);
   double exactSL=RoundProtectionStop(
      direction,
      direction==1 ? pending-exactDistance : pending+exactDistance);
   double brokerSL=BrokerSafeExecutionSL(direction,pending,exactSL);
   string comment=PREFIX+"DIRECT_ZC_LIMIT_"+
                  string(direction==1?"BUY_":"SELL_")+
                  IntegerToString(g_directZeroConf.attempts);

   ulong baseDeviation=(ulong)MathMax(0,InpDeviationPoints);
   trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
   bool sent=(direction==1)
             ? trade.BuyLimit(volume,pending,_Symbol,brokerSL,0.0,ORDER_TIME_GTC,0,comment)
             : trade.SellLimit(volume,pending,_Symbol,brokerSL,0.0,ORDER_TIME_GTC,0,comment);
   trade.SetDeviationInPoints(baseDeviation);

   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);
   if(!accepted && InpRetryEntryWithoutSLOnReject && RetryWithoutSLRetcode(code))
   {
      trade.SetDeviationInPoints(LatencyAwareEntryDeviationPoints(baseDeviation));
      sent=(direction==1)
           ? trade.BuyLimit(volume,pending,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment)
           : trade.SellLimit(volume,pending,_Symbol,0.0,0.0,ORDER_TIME_GTC,0,comment);
      trade.SetDeviationInPoints(baseDeviation);
      code=trade.ResultRetcode();
      accepted=sent && TradeRetcodeAccepted(code);
   }

   if(accepted)
   {
      g_dailyLayerOrders++;
      Log("LATENCY LIMIT FALLBACK PLACED | trigger="+g_directZeroConf.triggerText+
          " | direction="+string(direction==1?"BUY":"SELL")+
          " | price="+DoubleToString(pending,_Digits)+
          " | volume="+DoubleToString(volume,VolumeDigits())+
          " | reason="+reason);
      return true;
   }

   Log("LATENCY LIMIT FALLBACK FAILED | trigger="+g_directZeroConf.triggerText+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | price="+DoubleToString(pending,_Digits)+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());
   return false;
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


//------------------------ Layer construction ------------------------


//-------------------- Persistent READY execution --------------------



//---------------- Zero-confluence actual-deal reporting ----------------

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

   JournalTradeRow rows[];
   ulong entryOrders[];
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

   double totalEntryLots=0.0;
   double closedNet=0.0;
   int closedTrades=0;
   int wins=0;
   int losses=0;
   int breakeven=0;
   int openTrades=0;
   double pnlEpsilon=0.005;

   for(int i=0;i<ArraySize(rows);i++)
   {
      if(rows[i].entryLots<=0.0)
         continue;

      totalEntryLots+=rows[i].entryLots;

      if(JournalPositionIdentifierIsOpen(rows[i].positionId))
      {
         openTrades++;
         continue;
      }

      if(!rows[i].hasExit)
         continue;

      closedTrades++;
      closedNet+=rows[i].netPnl;

      if(rows[i].netPnl>pnlEpsilon)
         wins++;
      else if(rows[i].netPnl<-pnlEpsilon)
         losses++;
      else
         breakeven++;
   }

   double winRate=(wins+losses)>0
                  ? 100.0*(double)wins/(double)(wins+losses)
                  : 0.0;

   Log("================ EZYMAP ZERO-CONF ACTUAL-DEAL SUMMARY ================");
   Log("TOTAL ENTRY LOTS: "+DoubleToString(totalEntryLots,VolumeDigits())+
       " | ACTUAL ENTRY FILLS: "+IntegerToString(ArraySize(entryOrders)));
   Log("CLOSED TRADES: "+IntegerToString(closedTrades)+
       " | wins="+IntegerToString(wins)+
       " | losses="+IntegerToString(losses)+
       " | breakeven="+IntegerToString(breakeven)+
       " | open="+IntegerToString(openTrades));
   Log("WINRATE: "+DoubleToString(winRate,2)+"%"+
       " | CLOSED NET: "+DoubleToString(closedNet,2)+" "+
       AccountInfoString(ACCOUNT_CURRENCY));
   Log("=====================================================================");

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
             "PositionID",
             "EntryLots",
             "NetPnL",
             "Status");

   for(int i=0;i<ArraySize(rows);i++)
   {
      if(rows[i].entryLots<=0.0)
         continue;

      string status="INCOMPLETE";
      if(JournalPositionIdentifierIsOpen(rows[i].positionId))
         status="OPEN";
      else if(rows[i].hasExit)
      {
         if(rows[i].netPnl>pnlEpsilon)
            status="WIN";
         else if(rows[i].netPnl<-pnlEpsilon)
            status="LOSS";
         else
            status="BREAKEVEN";
      }

      FileWrite(handle,
                (string)rows[i].positionId,
                DoubleToString(rows[i].entryLots,VolumeDigits()),
                DoubleToString(rows[i].netPnl,2),
                status);
   }

   FileWrite(handle,"");
   FileWrite(handle,"SUMMARY","Value");
   FileWrite(handle,"TotalEntryLots",DoubleToString(totalEntryLots,VolumeDigits()));
   FileWrite(handle,"ActualEntryFills",ArraySize(entryOrders));
   FileWrite(handle,"ClosedTrades",closedTrades);
   FileWrite(handle,"WinningTrades",wins);
   FileWrite(handle,"LosingTrades",losses);
   FileWrite(handle,"BreakevenTrades",breakeven);
   FileWrite(handle,"OpenTrades",openTrades);
   FileWrite(handle,"WinRatePct",DoubleToString(winRate,2));
   FileWrite(handle,"ClosedNet",DoubleToString(closedNet,2));

   FileFlush(handle);
   FileClose(handle);

   string reportPath=
      TerminalInfoString(TERMINAL_COMMONDATA_PATH)+
      "\\Files\\"+filename;

   Log("CSV REPORT SAVED: "+reportPath);
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
         Log("DAILY RISK 75% PENDING CANCEL"+
             " | ticket="+(string)ticket+
             " | direction="+
             string(direction==1?"BUY":"SELL")+
             " | price="+DoubleToString(price,_Digits));
      }
      else
      {
         Log("DAILY RISK 75% PENDING CANCEL FAILED"+
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

   Log("ENTRY BLOCKED BY DAILY RISK 75%"+
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

   Log("V3.178 BROKER-DAY RISK RESET"+
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

      Log("V3.178 DAILY RISK LOCK"+
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


//--------------------------- Order placement ------------------------


//-------------------------- Basket management -----------------------


//--------------------------- MT5 EA events ---------------------------
int OnInit()
{
   g_accountUnitDivisor=ResolveAccountUnitDivisor();
   g_pipSize=StrategyPipSize();
   g_reportFromTime=TimeCurrent();
   g_reportWritten=false;
   g_lastAnalyticsDeal=0;

   if(!ConfigureRouting())
   {
      Alert(PRODUCT_NAME+" "+PRODUCT_VERSION+
            ": routing initialization failed.");
      return INIT_FAILED;
   }

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
   g_directZeroConf.initialExecutablePrice=0.0;
   g_directZeroConf.latchedClock=0;
   g_directZeroConf.lastAttemptClock=0;
   g_directZeroConf.lastAttemptTickMs=0;
   g_directZeroConf.attempts=0;
   g_directZeroConfHasPreviousCMP=false;
   g_directZeroConfPreviousCMP=0.0;
   g_everyZeroConfGeneration=0;
   for(int z=0;z<V3184_MAX_LEVEL_STATES;z++)
   {
      g_everyZeroConfStates[z].inUse=false;
      g_everyZeroConfStates[z].inZone=false;
      g_everyZeroConfStates[z].consumed=false;
      g_everyZeroConfStates[z].direction=0;
      g_everyZeroConfStates[z].code=EZY_ZC_TRIGGER_NONE;
      g_everyZeroConfStates[z].lo=0.0;
      g_everyZeroConfStates[z].hi=0.0;
      g_everyZeroConfStates[z].initialExecutablePrice=0.0;
      g_everyZeroConfStates[z].lastAttemptClock=0;
      g_everyZeroConfStates[z].lastAttemptTickMs=0;
      g_everyZeroConfStates[z].attempts=0;
      g_everyZeroConfStates[z].lastSeenGeneration=0;
   }
   g_zcM5ReclaimCacheBar=0;
   ArrayResize(g_zcM5ReclaimRates,0);
   ArrayResize(g_exitExecutionStates,0);

   ApplyPremiumChartTheme();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.SetAsyncMode(false);

   LoadState();
   ResetCampaignDay(false);

   g_biasText="NEUTRAL";
   DrawDashboard();
   DrawTradeCard();
   ChartRedraw(0);
   EventSetTimer(1);

   Log("EzyMap Scalp Mastery V3.184 | EVERY ZERO-CONFLUENCE LEVEL"+
       " | HIGH-RISK=ON | LOW-RISK=ON"+
       " | M5 SWEEP/RECLAIM=FORCED OFF"+
       " | every mapped level=INDEPENDENT"+
       " | tolerance="+
       DoubleToString(InpZeroConfTouchTolerancePips,1)+" pips"+
       " | no standard route | no entry governors | one fill per continuous level touch");

   Log("EXECUTION | entry deviation=spread+"+
       IntegerToString(InpEntrySpreadDeviationCushionPoints)+
       " capped "+IntegerToString(InpEntryDeviationCapPoints)+
       " | exit deviation=spread+"+
       IntegerToString(InpExitSpreadDeviationCushionPoints)+
       " capped "+IntegerToString(InpExitDeviationCapPoints)+
       " | retry="+IntegerToString(InpDeploymentRetryIntervalMs)+"ms"+
       " | max adverse drift="+
       DoubleToString(InpMaxMarketAdverseDriftPips,1)+" pips");

   Log("PROTECTION | TP=NONE | SL="+
       DoubleToString(InpPresetStopLossPips,0)+" pips"+
       " | trailing="+
       DoubleToString(InpTrailingDistancePips,0)+" pips"+
       " | synchronized exit=ON");

   Log("ACCOUNT | profile="+
       string(g_accountUnitDivisor>1.0?"CENT":"STANDARD")+
       " | raw equity="+
       DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
       " | effective equity="+
       DoubleToString(EffectiveAccountEquity(),2)+
       " | symbol="+_Symbol);

   ReportJournalPerformance(true,"INIT");
   return INIT_SUCCEEDED;
}


void OnDeinit(const int reason)
{
   ReportJournalPerformance(true,"FINAL");
   WriteEzyMapBacktestReport();
   EventKillTimer();
   SaveState();
   ClearHistoricalMarkers();
   ObjectsDeleteAll(0,PREFIX);
   ChartRedraw(0);
}


void OnTimer()
{
   ManageHybridTrailingPositions("TIMER");
   ReportJournalPerformance(false,"UPDATE");

   ResetCampaignDay(false);

   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
      {
         double price=(tick.bid>0.0)?tick.bid:tick.last;
         if(price>0.0)
         {
            CalculateMapAndMaybeReady(price);
            ProcessEveryZeroConfluenceTriggers();
         }
      }
   }

   DrawMap(TimeCurrent());
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

   double livePrice=(tick.bid>0.0)?tick.bid:tick.last;
   if(livePrice<=0.0)
      return;

   ManageHybridTrailingPositions("TICK");
   ResetCampaignDay(false);

   CalculateMapAndMaybeReady(livePrice);
   ProcessEveryZeroConfluenceTriggers();

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

   if(trans.type==TRADE_TRANSACTION_DEAL_ADD &&
      trans.deal>0 &&
      HistoryDealSelect(trans.deal) &&
      HistoryDealGetString(trans.deal,DEAL_SYMBOL)==_Symbol &&
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC)==InpMagicNumber)
   {
      ENUM_DEAL_ENTRY entry=
         (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal,DEAL_ENTRY);

      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
         performanceReason="CLOSE";
      else if(entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT)
         performanceReason="ENTRY";
   }

   ManageHybridTrailingPositions("TRADE");
   SaveState();
   DrawActualTradeLevelsGold();
   ChartRedraw(0);

   if(performanceReason!="")
      ReportJournalPerformance(true,performanceReason);
}


//+------------------------------------------------------------------+
