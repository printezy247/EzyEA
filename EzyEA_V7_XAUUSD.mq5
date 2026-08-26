//+------------------------------------------------------------------+
//|                                             EzyEA_V7_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V7 - ports the LIVE SIGNAL TRIGGER LOGIC of the TradingView    |
//| Pine indicator "EzyMap Pro V1.7" (uploaded as EzyMap_Pro_V1_7.pine,   |
//| 2221 lines), run as FIVE INDEPENDENT PARALLEL ENGINES - one per        |
//| timeframe M5/M15/M30/H1/H4 - per explicit request ("entry on every       |
//| timeframe from m5 to h4 as per original live signal's logic"). Each       |
//| timeframe follows the Pine's own routing matrix for its direction/         |
//| support/entry timeframe trio, and each timeframe allows at most ONE          |
//| concurrent open position (matching the Pine's own single-ACTIVE-trade         |
//| constraint), so up to 5 positions total can be open system-wide, one           |
//| per timeframe tier.                                                              |
//|                                                                                     |
//| ROUTING MATRIX (verbatim from the Pine source's comment block):                     |
//|   M5  -> H1 direction  / M15 support / M5  entry  (mode: SCALP)                       |
//|   M15 -> H4 direction  / M30 support / M15 entry  (mode: INTRADAY)                     |
//|   M30 -> D1 direction  / H1 support  / M30 entry  (mode: INTRADAY)                      |
//|   H1  -> W1 direction  / H4 support  / H1  entry  (mode: SWING)                          |
//|   H4  -> MN1 direction / D1 support  / H4  entry  (mode: SWING)                           |
//|                                                                                              |
//| LIVE SIGNAL TRIGGER LOGIC PORTED WITH FULL FIDELITY (these all gate                          |
//| whether/when/which-direction a trade fires, or set the real entry price,                       |
//| straight from the Pine source, not from a summary):                                              |
//| 1. Direction-timeframe S1/S2/R1/R2: nearest historical CLOSE below/above                           |
//|    the entry-timeframe reference price within InpDirectionHistoryBars,                              |
//|    S2/R2 the next level at least InpMinLevelSeparationPips further out                                |
//|    (f_pick_direction_levels).                                                                           |
//| 2. Direction bias: direction-timeframe close vs its own EMA13                                            |
//|    (bullishBias/bearishBias); entry-timeframe close vs its own EMA13                                       |
//|    within a tolerance (entryBullishBias/entryBearishBias) determines                                        |
//|    trend-following vs counter-trend routing (trendBuyRoute/                                                   |
//|    counterTrendBuyRoute/allowBuy, mirrored for sell).                                                           |
//| 3. LOW-RISK zone (S2 for BUY, R2 for SELL) - Pro V1's change from V1.6:                                          |
//|    both trend-following and counter-trend routes arm on the LOW RISK                                              |
//|    zone, not the near HIGH RISK zone. Zone price = the nearest support-                                             |
//|    timeframe candle overlapping the level, sized as the REJECTION WICK                                               |
//|    only (low-to-close for a support/BUY zone, close-to-high for a                                                      |
//|    resistance/SELL zone), not the full candle range (f_support_zone).                                                    |
//| 4. Entry-timeframe confirmation (any ONE of five independent paths, all                                                    |
//|    computed on the confirmed entry-timeframe candle): plain structure-                                                       |
//|    break CHOCH, displacement-quality CHOCH (ATR-scaled range/body/close-                                                        |
//|    position + break distance), rejection wick, ordinary liquidity sweep +                                                          |
//|    reclaim, and session/previous-day liquidity sweep + reclaim (previous                                                              |
//|    day, completed Asian, completed London high/low). Each stays "recent"                                                                 |
//|    for InpArmedConfirmationWindowBars entry-timeframe candles and must                                                                      |
//|    spatially overlap the side's selected LOW-RISK zone.                                                                                        |
//| 5. READY arm/resync/invalidate/touch state machine, byte-for-byte the                                                                            |
//|    Pine's mechanics: a side arms when confirmation + correct-side-of-CMP +                                                                         |
//|    retest-count<=InpMaxZoneRetests are all true; resyncs its rectangle if                                                                             |
//|    the underlying zone moves while waiting; invalidates on expiry                                                                                       |
//|    (InpArmedExpiryEntryBars entry-timeframe candles), a broken trend route,                                                                               |
//|    a close beyond the zone by more than a small buffer, or price crossing                                                                                   |
//|    to the wrong side of CMP without ever touching; and commits the instant                                                                                     |
//|    a real tick touches the zone.                                                                                                                                  |
//| 6. Confluence count (round-number/EMA/trendline/fib/MTF-cluster/EMA-slope/                                                                                          |
//|    EMA-regime/VWAP) is DELIBERATELY NOT PORTED - in the source it is                                                                                                   |
//|    confluence-scoring only, feeding a display-only CONFIDENCE label, and                                                                                                 |
//|    is a NO-OP gate at the source's own default (minimumConfluenceForLive=0).                                                                                                |
//|    Dropping it changes nothing about default trading behavior. The support-                                                                                                    |
//|    timeframe swing-pivot/projected-trendline metrics (only otherwise used                                                                                                         |
//|    for confluence and as one of several SL front-run candidates) are                                                                                                                 |
//|    likewise not ported - a disclosed simplification, not an oversight.                                                                                                                  |
//|                                                                                                                                                                                            |
//| EXIT LOGIC - EXPLICITLY REPLACED per follow-up request ("set preset sl 29                                                                                                                    |
//| pips, trailing 13 pips, trail start after positive 5 pips p/l" + "only use                                                                                                                     |
//| the live signal entry trigger"): the Pine's own mode-based ATR/RR-clamped                                                                                                                         |
//| SL/TP + break-even-then-ATR-trail exit is NOT ported. Every position from                                                                                                                            |
//| any tier instead uses this codebase's established hybrid virtual-trail                                                                                                                                  |
//| pattern (verbatim in spirit from EzyEA V3/V4/V5): a flat 29-pip preset SL                                                                                                                                   |
//| from entry, no TP, tightening to a 13-pip trail the instant floating P&L                                                                                                                                       |
//| reaches +5 pips - a virtual stop tracked in EA memory and enforced by a                                                                                                                                            |
//| direct close, independent of whether the broker accepts a tight SL modify.                                                                                                                                            |
//|                                                                                                                                                                                                                              |
//| Reuses established EzyEA-family infrastructure: cent-account detection/                                                                                                                                                        |
//| scaling, risk-%-of-equity lot sizing via OrderCalcProfit() with a minimum-                                                                                                                                                        |
//| lot fallback, auto-calibrating spread guard, full retcode classification,                                                                                                                                                            |
//| an overall portfolio drawdown breaker. Market orders only, TimeCurrent()-                                                                                                                                                              |
//| based timing throughout.                                                                                                                                                                                                                    |
//|                                                                                                                                                                                                                                                  |
//| SCOPE NOTE: Asian/London session windows are evaluated in SERVER time                                                                                                                                                                            |
//| (TimeCurrent()), not the Pine source's explicit Etc/UTC - a disclosed                                                                                                                                                                              |
//| adaptation, since MQL5 has no built-in timezone conversion; adjust                                                                                                                                                                                    |
//| InpAsiaSessionStartHour/etc. to your broker's UTC offset if needed. Chart                                                                                                                                                                               |
//| drawing stays a compact per-tier status label and live trade lines - the                                                                                                                                                                                  |
//| Pine's dashboard/trade-card/historical-marker presentation is not ported.                                                                                                                                                                                    |
//|                                                                                                                                                                                                                                                                 |
//| CHANGELOG                                                                                                                                                                                                                                                        |
//| 1.000 - Initial build.                                                                                                                                                                                                                                              |
//| 1.100 - Per explicit request ("more aggressive" + "use v3.184 as                                                                                                                                                                                                      |
//|         reference trigger"): (a) InpEnableZeroConfluenceTouch (default                                                                                                                                                                                                |
//|         true) lets QualifyZone fire on a correctly-sided zone touch                                                                                                                                                                                                   |
//|         even with no recent reject/sweep/displacement/CHOCH confirmation,                                                                                                                                                                                             |
//|         matching V3.184's zero-confluence philosophy; (b) replaced the                                                                                                                                                                                                |
//|         one-trade-per-tier lock with InpMaxConcurrentPerTierDirection                                                                                                                                                                                                 |
//|         (default 5), allowing several concurrent layers per tier per                                                                                                                                                                                                  |
//|         direction - and both directions of the same tier simultaneously -                                                                                                                                                                                            |
//|         instead of one trade total per tier. Set                                                                                                                                                                                                                      |
//|         InpEnableZeroConfluenceTouch=false and                                                                                                                                                                                                                        |
//|         InpMaxConcurrentPerTierDirection=1 to restore 1.000's behavior.                                                                                                                                                                                               |
//| 1.200 - Added lot-traded / backtest reporting: a live running fill/lot                                                                                                                                                                                                 |
//|         counter (g_totalLotsTraded/g_totalFills) surfaced in the status                                                                                                                                                                                                |
//|         label and periodic log, plus WriteBacktestReport() on OnDeinit                                                                                                                                                                                                 |
//|         (HistoryDeals-based entry lots, fills, closed trades, win rate,                                                                                                                                                                                                |
//|         closed net P/L) with optional CSV export - the same reporting                                                                                                                                                                                                  |
//|         already added to EzyEA_V7.1_XAUUSD.mq5.                                                                                                                                                                                                                        |
//| 1.300 - Further "refine v7 to be more aggressive" pass: (a) added an     |
//|         optional HIGH-RISK zone (nearer S1/R1 level, same rejection-     |
//|         wick construction as LOW-RISK) as a fallback candidate zone -    |
//|         QualifyZone now tries LOW-RISK first, then HIGH-RISK if enabled  |
//|         (InpEnableHighRiskZone, default true), roughly doubling the      |
//|         number of candidate touch zones per tier/direction; (b) widened  |
//|         the entry-timeframe bias tolerance (InpEntryBiasToleranceMinPips |
//|         15->30, InpEntryBiasToleranceAtrMult 0.60->1.20) so more touches |
//|         pass the momentum-agreement gate; (c) raised InpMaxZoneRetests   |
//|         4->8 so zones survive more retests before invalidating; (d)      |
//|         raised InpMaxConcurrentPerTierDirection 5->8 for more layering   |
//|         headroom. Set InpEnableHighRiskZone=false and the four inputs    |
//|         above back to their prior values to restore 1.200's behavior.   |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "1.300"
#property strict

#include <Trade/Trade.mqh>

//======================================================================
// Enums
//======================================================================
enum ENUM_EZY_ACCOUNT_SCALE
{
   EZY_ACCOUNT_AUTO     = 0,
   EZY_ACCOUNT_STANDARD = 1,
   EZY_ACCOUNT_CENT     = 2
};

#define EZY_TIER_COUNT 5

//======================================================================
// Inputs
//======================================================================
input group "=== Direction / Level Construction ==="
input int    InpDirectionHistoryBars        = 48;
input double InpMinLevelSeparationPips      = 70.0;
input int    InpSupportHistoryBars          = 40;

input group "=== Direction / Entry Bias (EMA13) ==="
input int    InpDirectionEmaPeriod          = 13;
input double InpEntryBiasToleranceMinPips   = 30.0; // was 15.0 - widened per explicit "more aggressive" request
input double InpEntryBiasToleranceAtrMult   = 1.20; // was 0.60 - widened per explicit "more aggressive" request

input group "=== Entry-Timeframe Confirmation ==="
input int    InpEntryPivotBars              = 1;
input bool   InpRequireDirectionalBody      = false;
input double InpRejectionWickRatio          = 0.25;
input int    InpSweepLookbackBars           = 5;
input bool   InpUseSweepReclaim             = true;
input bool   InpUseDisplacementChoch        = true;
input double InpDisplacementMinRangeATR     = 0.70;
input double InpDisplacementMinBodyPct      = 0.55;
input double InpDisplacementMinBreakATR     = 0.10;
input int    InpArmedConfirmationWindowBars = 4;

input group "=== Session / Previous-Day Liquidity (server time) ==="
input bool   InpUseSessionDayLiquidity      = true;
input int    InpAsiaSessionStartHour        = 0;
input int    InpAsiaSessionEndHour          = 8;
input int    InpLondonSessionStartHour      = 8;
input int    InpLondonSessionEndHour        = 16;
input int    InpSessionLevelMaxAgeHours     = 36;

input group "=== READY State Machine ==="
input int    InpMaxZoneRetests              = 8; // was 4 - raised per explicit "more aggressive" request
input int    InpArmedExpiryEntryBars        = 60;

input group "=== Zero-Confluence Touch (V3.184-style aggressive trigger) ==="
// V3.184's dominant frequency philosophy: a touch of a valid, correctly-
// sided zone fires immediately, with no requirement for a fresh reject/
// sweep/displacement/CHOCH confirmation. Set false to restore the strict
// original Pine behaviour (a recent confirmation is mandatory).
input bool   InpEnableZeroConfluenceTouch   = true;

// The Pine source always arms on the LOW-RISK (S2/R2) zone only. Enabling
// this lets a tier/direction also arm on the nearer HIGH-RISK (S1/R1)
// zone whenever LOW-RISK doesn't currently qualify, roughly doubling the
// number of candidate touch zones per tier/direction.
input bool   InpEnableHighRiskZone          = true;

input group "=== Concurrency: Multiple Trades Per Tier/Direction (V3.184-style layering) ==="
// The original Pine strategy is single-instance (one trade total). This
// EA already runs 5 independent tiers; V3.184's own frequency comes from
// also allowing several concurrent layers in the same direction rather
// than locking to one trade at a time. Raise/lower to trade off frequency
// against exposure. Set to 1 to restore the original one-trade-per-tier
// lock (both directions combined).
input int    InpMaxConcurrentPerTierDirection = 8; // was 5 - raised per explicit "more aggressive" request

input group "=== Exit: Hybrid Virtual Trail (shared by every tier) ==="
input double InpPresetStopLossPips          = 29.0;
input double InpTrailingActivationPips      = 5.0;
input double InpTrailingDistancePips        = 13.0;
input double InpTrailMinStepPoints          = 20.0;
input bool   InpUseVirtualTrailFallback     = true;
input int    InpVirtualTrailCloseDeviationPts = 30;
input bool   InpReconstructPeakFromM1       = true;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) ==="
input bool   InpEnableDrawdownBreaker       = true;
input double InpMaxEquityDrawdownPct        = 10.0;
input double InpDrawdownResumeFactor        = 0.5;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade         = 0.25;
input double InpMaxLotsAbsolute             = 5.0;
input double InpMaxMarginUsePct             = 40.0;
input bool   InpAllowMinimumLotFallback     = true;
input double InpMinimumLotFallbackMaxRiskPct = 1.0;

input group "=== Spread Guard (auto-calibrating) ==="
input bool   InpAutoCalibrateSpreadCap      = true;
input int    InpSpreadCalibrationTicks      = 200;
input double InpSpreadCalibrationMultiplier = 2.5;
input int    InpMaxSpreadPoints             = 400;

input group "=== Cent-Account Handling ==="
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor      = 100.0;
input bool   InpTesterAutoModeIsStandard    = true;
input bool   InpTreatSCSuffixAsCentOnLive   = true;

input group "=== Execution ==="
input ulong  InpMagicNumber                 = 190070;
input int    InpDeviationPoints             = 20;

input group "=== Reporting: Status Log ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Reporting: Lot-Traded / Backtest Report ==="
input bool   InpWriteCSVReport              = true;
input string InpCSVReportPrefix             = "EzyEA_V7_XAUUSD_Report";

input group "=== Chart Drawing ==="
input bool   InpApplyPremiumTheme           = true;
input color  InpChartBackground             = C'8,11,15';
input color  InpChartForeground             = C'176,185,195';
input color  InpBullCandleColor             = C'0,208,142';
input color  InpBearCandleColor             = C'235,72,96';
input bool   InpHideNativeTickerOHLC        = true;
input bool   InpDrawStatusLabel             = true;
input bool   InpShowLiveTradeLevels         = true;
input color  InpBuyColor                    = C'0,208,142';
input color  InpSellColor                   = C'235,72,96';
input color  InpTradeLevelGold              = C'255,215,0';

//======================================================================
// Types
//======================================================================
struct TierConfig
{
   string          label;
   string          modeLabel;
   ENUM_TIMEFRAMES entryTF;
   ENUM_TIMEFRAMES directionTF;
   ENUM_TIMEFRAMES supportTF;
};

struct TierSideState
{
   bool     armed;
   string   risk;
   string   confirmation;
   bool     counterTrend;
   double   supportLo,supportHi;
   int      retests;
   bool     zoneExited;
   double   entryLo,entryHi;
   datetime entryTime;
   datetime armedAtClock;
   bool     touchLatched;
};

struct TierConfirmState
{
   int      structureDirection;      // 1/-1/0 ratchet
   datetime lastProcessedEntryTime;
   int      rejectAge,chochAge,sweepAge,premiumAge,displaceAge;
   double   lastSweepLo,lastSweepHi;       datetime lastSweepTime;
   double   lastPremiumLo,lastPremiumHi;   datetime lastPremiumTime; string lastPremiumType;
   double   lastDisplaceLo,lastDisplaceHi; datetime lastDisplaceTime;
};

struct TierState
{
   // Direction levels
   double   S1,S2,R1,R2;
   bool     bullishBias,bearishBias;
   double   directionATR;
   double   supportATR;
   // LOW-RISK zones (armed-eligible zones)
   double   buyZoneLo,buyZoneHi;   datetime buyZoneTime;
   double   sellZoneLo,sellZoneHi; datetime sellZoneTime;
   // Confirmation state, bullish and bearish tracked separately
   TierConfirmState bull;
   TierConfirmState bear;
   // READY slots
   TierSideState buySide;
   TierSideState sellSide;
   // Active trade lock (one per tier)
   bool     tradeActive;
   int      tradeDirection;
   ulong    ticket;
};

struct ManagedPositionState
{
   ulong    ticket;
   int      consecutiveFailures;
   datetime cooldownUntil;
   double   peakPrice;
   double   virtualStop;
   bool     peakReconstructed;
};

struct BacktestTradeRow
{
   long   positionId;
   double entryLots;
   double netPnl;
   bool   hasExit;
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

TierConfig g_cfg[EZY_TIER_COUNT];
TierState  g_tier[EZY_TIER_COUNT];

ManagedPositionState g_managed[];

double g_accountUnitDivisor = 1.0;

double g_spreadCalSamples[];
int    g_spreadCalCount        = 0;
double g_spreadCalEffectiveCap = -1.0;

double g_peakEquity    = 0.0;
bool   g_tradingHalted = false;

// Session / previous-day liquidity (shared across all tiers - wall-clock,
// not tier-specific)
double   g_asiaRunningHigh=0.0, g_asiaRunningLow=0.0;
bool     g_asiaWasActive=false;
double   g_completedAsiaHigh=0.0, g_completedAsiaLow=0.0;
datetime g_completedAsiaAt=0;

double   g_londonRunningHigh=0.0, g_londonRunningLow=0.0;
bool     g_londonWasActive=false;
double   g_completedLondonHigh=0.0, g_completedLondonLow=0.0;
datetime g_completedLondonAt=0;

datetime g_lastM1BarTime=0;

datetime g_lastStatusLogTime = 0;

int g_gateAttempts           = 0;
int g_gateAccepted           = 0;
int g_gateRejected           = 0;
int g_gateSpreadRejects      = 0;
int g_gateDistanceRejects    = 0;
int g_gateSizingRejects      = 0;
int g_gateDrawdownRejects    = 0;

double g_totalLotsTraded = 0.0;
int    g_totalFills      = 0;

//======================================================================
// Forward declarations
//======================================================================
int    OnInit();
void   OnDeinit(const int reason);
void   OnTick();

string Upper(string s);
bool   IsGold();
bool   IsCentSuffixSymbol();
double StrategyPipSize();
double RoundPrice(double v);
string PriceText(double v);
void   Log(string msg);

double ResolveAccountUnitDivisor();
double EffectiveAccountEquity();
int    VolumeDigits();
double NormalizeVolumeDown(double vol);
double OneLotLoss(int direction,double entry,double sl);
double ComputeLotsForRisk(int direction,double entry,double sl);

bool   TradeRetcodeAccepted(uint code);
bool   TemporaryTradeRetcode(uint code);

double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel);
double MinimumStopDistance(double referencePrice);

int    SpreadCalibrationTicksEffective();
double MedianOfSpreadSamples(double &values[],int count);
bool   SpreadAllowed();

void   CloseAllPositions(string reason);
void   UpdateDrawdownBreaker();

void   UpdateSessionLiquidity();

void   PickDirectionLevels(int t);
void   SupportZone(int t,double level,bool isSupport,double &zoneLo,double &zoneHi,datetime &zoneTime);
void   BuildLowRiskZones(int t);
bool   RangesOverlap(double lo1,double hi1,double lo2,double hi2);
void   UpdateConfirmations(int t);
void   ProcessArmAndResync(int t,int direction);
void   ProcessTouch(int t,int direction);
bool   TryQualifyZoneCandidate(int t,int direction,double zoneLo,double zoneHi,datetime zoneTime,TierConfirmState &side,double cmp,int &outRetests,string &outConfirmation);
bool   QualifyZone(int t,int direction,double &outLo,double &outHi,datetime &outTime,int &outRetests,string &outConfirmation,bool &outCounterTrend,string &outRisk);
int    ZoneRetestCount(int t,double zoneLo,double zoneHi,datetime zoneTime,datetime currentEntryTime);
int    CountOpenPositionsForTierDirection(int t,int direction);
bool   SubmitEntryOrder(int t,int direction);

int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
double ReconstructPeakFromM1(int direction,double entry,double current,datetime positionTime);
bool   CloseAtVirtualStop(ulong ticket,string context,double current,double stop,double peak);
void   ManageTrailing();

void   DrawStatusLabel();
void   DrawLiveTradeLevels();
void   ApplyPremiumChartTheme();
void   RemoveAllDrawings();

void   WriteFinalReport();
void   PeriodicStatusLog();
int    EnsureBacktestRow(BacktestTradeRow &rows[],long positionId);
void   WriteBacktestReport();

//======================================================================
// Event handlers
//======================================================================
int OnInit()
{
   if(!IsGold())
   {
      Log("EzyEA V7 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   // Routing matrix, verbatim from the Pine source's comment block.
   g_cfg[0].label="M5";  g_cfg[0].modeLabel="SCALP";    g_cfg[0].entryTF=PERIOD_M5;  g_cfg[0].directionTF=PERIOD_H1;  g_cfg[0].supportTF=PERIOD_M15;
   g_cfg[1].label="M15"; g_cfg[1].modeLabel="INTRADAY"; g_cfg[1].entryTF=PERIOD_M15; g_cfg[1].directionTF=PERIOD_H4;  g_cfg[1].supportTF=PERIOD_M30;
   g_cfg[2].label="M30"; g_cfg[2].modeLabel="INTRADAY"; g_cfg[2].entryTF=PERIOD_M30; g_cfg[2].directionTF=PERIOD_D1;  g_cfg[2].supportTF=PERIOD_H1;
   g_cfg[3].label="H1";  g_cfg[3].modeLabel="SWING";    g_cfg[3].entryTF=PERIOD_H1;  g_cfg[3].directionTF=PERIOD_W1;  g_cfg[3].supportTF=PERIOD_H4;
   g_cfg[4].label="H4";  g_cfg[4].modeLabel="SWING";    g_cfg[4].entryTF=PERIOD_H4;  g_cfg[4].directionTF=PERIOD_MN1; g_cfg[4].supportTF=PERIOD_D1;

   for(int t=0;t<EZY_TIER_COUNT;t++)
   {
      TierState blank;
      blank.S1=0; blank.S2=0; blank.R1=0; blank.R2=0;
      blank.bullishBias=false; blank.bearishBias=false;
      blank.directionATR=0; blank.supportATR=0;
      blank.buyZoneLo=0; blank.buyZoneHi=0; blank.buyZoneTime=0;
      blank.sellZoneLo=0; blank.sellZoneHi=0; blank.sellZoneTime=0;
      blank.bull.structureDirection=0; blank.bull.lastProcessedEntryTime=0;
      blank.bull.rejectAge=999999; blank.bull.chochAge=999999; blank.bull.sweepAge=999999; blank.bull.premiumAge=999999; blank.bull.displaceAge=999999;
      blank.bull.lastSweepLo=0; blank.bull.lastSweepHi=0; blank.bull.lastSweepTime=0;
      blank.bull.lastPremiumLo=0; blank.bull.lastPremiumHi=0; blank.bull.lastPremiumTime=0; blank.bull.lastPremiumType="";
      blank.bull.lastDisplaceLo=0; blank.bull.lastDisplaceHi=0; blank.bull.lastDisplaceTime=0;
      blank.bear=blank.bull;
      blank.buySide.armed=false; blank.buySide.risk=""; blank.buySide.confirmation=""; blank.buySide.counterTrend=false;
      blank.buySide.supportLo=0; blank.buySide.supportHi=0; blank.buySide.retests=0; blank.buySide.zoneExited=false;
      blank.buySide.entryLo=0; blank.buySide.entryHi=0; blank.buySide.entryTime=0; blank.buySide.armedAtClock=0; blank.buySide.touchLatched=false;
      blank.sellSide=blank.buySide;
      blank.tradeActive=false; blank.tradeDirection=0; blank.ticket=0;
      g_tier[t]=blank;
   }

   g_accountUnitDivisor = ResolveAccountUnitDivisor();

   int capacity = SpreadCalibrationTicksEffective();
   ArrayResize(g_spreadCalSamples,capacity);
   g_spreadCalCount        = 0;
   g_spreadCalEffectiveCap = -1.0;

   g_peakEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted = false;

   g_asiaRunningHigh=0.0; g_asiaRunningLow=0.0; g_asiaWasActive=false;
   g_completedAsiaHigh=0.0; g_completedAsiaLow=0.0; g_completedAsiaAt=0;
   g_londonRunningHigh=0.0; g_londonRunningLow=0.0; g_londonWasActive=false;
   g_completedLondonHigh=0.0; g_completedLondonLow=0.0; g_completedLondonAt=0;
   g_lastM1BarTime=0;

   ArrayResize(g_managed,0);

   g_lastStatusLogTime = 0;

   g_totalLotsTraded = 0.0;
   g_totalFills = 0;

   ApplyPremiumChartTheme();

   Log("EzyEA V7 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | tiers=M5/M15/M30/H1/H4, max "+IntegerToString(InpMaxConcurrentPerTierDirection)+" concurrent per tier/direction"+
       " | zero-confluence touch="+(InpEnableZeroConfluenceTouch?"ON":"OFF")+
       " | high-risk zone="+(InpEnableHighRiskZone?"ON":"OFF")+
       " | exit: preset="+DoubleToString(InpPresetStopLossPips,1)+"p trail="+DoubleToString(InpTrailingDistancePips,1)+
       "p @+"+DoubleToString(InpTrailingActivationPips,1)+"p"+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF"));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();
   WriteBacktestReport();
   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();
   UpdateSessionLiquidity();
   PruneManagedSlots();
   ManageTrailing();

   if(!g_tradingHalted)
   {
      for(int t=0;t<EZY_TIER_COUNT;t++)
      {
         // Refresh the tier's live-trade status (cosmetic only - entry
         // gating below reads live position counts directly, since
         // multiple concurrent trades per tier/direction are now allowed).
         int buyCount =CountOpenPositionsForTierDirection(t,1);
         int sellCount=CountOpenPositionsForTierDirection(t,-1);
         g_tier[t].tradeActive=(buyCount>0 || sellCount>0);
         g_tier[t].tradeDirection=(buyCount>0)?1:((sellCount>0)?-1:0);
         if(!g_tier[t].tradeActive) g_tier[t].ticket=0;

         datetime entryBarTime=iTime(_Symbol,g_cfg[t].entryTF,0);
         if(entryBarTime!=0 && entryBarTime!=g_tier[t].bull.lastProcessedEntryTime)
         {
            PickDirectionLevels(t);
            BuildLowRiskZones(t);
            UpdateConfirmations(t);
            ProcessArmAndResync(t,1);
            ProcessArmAndResync(t,-1);
         }

         ProcessTouch(t,1);
         ProcessTouch(t,-1);
      }
   }

   if(InpDrawStatusLabel)     DrawStatusLabel();
   if(InpShowLiveTradeLevels) DrawLiveTradeLevels();

   PeriodicStatusLog();
}

//======================================================================
// Small helpers
//======================================================================
string Upper(string s)
{
   StringToUpper(s);
   return s;
}

bool IsGold()
{
   string s=Upper(_Symbol);
   return (StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0);
}

bool IsCentSuffixSymbol()
{
   string s=Upper(_Symbol);
   return (StringFind(s,".SC")>=0 || StringFind(s,"_SC")>=0 || StringFind(s,"CENT")>=0);
}

double StrategyPipSize()
{
   return MathMax(0.10,_Point);
}

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

void Log(string msg)
{
   Print("EzyEA V7 | ",msg);
}

//======================================================================
// Cent-account / equity / sizing
//======================================================================
double ResolveAccountUnitDivisor()
{
   if(InpAccountScaleMode==EZY_ACCOUNT_STANDARD)
      return 1.0;

   double configured=MathMax(1.0,InpCentAccountUnitDivisor);

   if(InpAccountScaleMode==EZY_ACCOUNT_CENT)
      return configured;

   if((bool)MQLInfoInteger(MQL_TESTER) && InpTesterAutoModeIsStandard)
      return 1.0;

   string currency=Upper(AccountInfoString(ACCOUNT_CURRENCY));
   string server  =Upper(AccountInfoString(ACCOUNT_SERVER));
   string company =Upper(AccountInfoString(ACCOUNT_COMPANY));

   bool centCurrency=(currency=="USC" || currency=="USCENT" || StringFind(currency,"CENT")>=0);
   bool centBrand   =(StringFind(server,"CENT")>=0 || StringFind(company,"CENT")>=0);
   bool centSuffix  =InpTreatSCSuffixAsCentOnLive && IsCentSuffixSymbol();

   return (centCurrency || centBrand || centSuffix) ? configured : 1.0;
}

double EffectiveAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY)/MathMax(1.0,g_accountUnitDivisor);
}

int VolumeDigits()
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0.0) return 2;

   int digits=0;
   while(step<0.999999 && digits<8)
   {
      step*=10.0;
      digits++;
   }
   return digits;
}

double NormalizeVolumeDown(double vol)
{
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step  =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   if(step<=0) step=minVol;
   if(step<=0) return 0.0;
   if(vol<minVol) return 0.0;

   vol=MathMin(vol,maxVol);
   double v=MathFloor((vol+1e-12)/step)*step;
   if(v<minVol) return 0.0;

   return NormalizeDouble(v,VolumeDigits());
}

double OneLotLoss(int direction,double entry,double sl)
{
   if(entry<=0 || sl<=0) return 0.0;
   if(direction==1  && sl>=entry) return 0.0;
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

double ComputeLotsForRisk(int direction,double entry,double sl)
{
   double equity=EffectiveAccountEquity();
   double riskBudget=equity*InpRiskPercentPerTrade/100.0;
   if(riskBudget<=0.0) return 0.0;

   double perLotLoss=OneLotLoss(direction,entry,sl);
   if(perLotLoss<=0.0) return 0.0;

   double lots=NormalizeVolumeDown(riskBudget/perLotLoss);

   if(lots<=0.0)
   {
      if(!InpAllowMinimumLotFallback) return 0.0;

      double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      if(minVol<=0.0) return 0.0;

      double minVolRiskPct=(equity>0.0)?(minVol*perLotLoss/equity)*100.0:1.0e9;
      if(minVolRiskPct>InpMinimumLotFallbackMaxRiskPct)
      {
         Log("SIZING: minimum-lot fallback blocked - would risk "+
             DoubleToString(minVolRiskPct,2)+"% of equity, over the "+
             DoubleToString(InpMinimumLotFallbackMaxRiskPct,2)+"% cap");
         return 0.0;
      }

      Log("SIZING: risk budget rounded below broker minimum lot - using minimum lot "+
          DoubleToString(minVol,2));
      lots=minVol;
   }

   lots=MathMin(lots,InpMaxLotsAbsolute);

   double marginRequired=0.0;
   ENUM_ORDER_TYPE type=(direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(OrderCalcMargin(type,_Symbol,lots,entry,marginRequired))
   {
      double rawEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      double usedMargin=AccountInfoDouble(ACCOUNT_MARGIN);
      double projectedMarginPct=(rawEquity>0.0)
                                ?((usedMargin+marginRequired)/rawEquity)*100.0
                                :DBL_MAX;

      if(projectedMarginPct>InpMaxMarginUsePct)
      {
         double remainingBudget=MathMax(0.0,InpMaxMarginUsePct/100.0*rawEquity-usedMargin);
         lots=(remainingBudget<=0.0 || marginRequired<=0.0)
              ?0.0
              :NormalizeVolumeDown(lots*(remainingBudget/marginRequired));
      }

      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired>freeMargin)
         lots=0.0;
   }

   return NormalizeVolumeDown(lots);
}

//======================================================================
// Retcode classification (includes TRADE_RETCODE_MARKET_CLOSED)
//======================================================================
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
           code==TRADE_RETCODE_CONNECTION ||
           code==TRADE_RETCODE_MARKET_CLOSED);
}

//======================================================================
// Broker minimum distance (zero-stops-level fallback)
//======================================================================
double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel)
{
   if(stopsLevel>0 || freezeLevel>0 || referencePrice<=0.0)
      return 0.0;
   return referencePrice*0.05/100.0;
}

double MinimumStopDistance(double referencePrice)
{
   long stopsLevel =SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double base=MathMax(_Point,((double)MathMax(stopsLevel,freezeLevel)+10.0)*_Point);

   return base+ZeroStopsLevelFallbackPrice(referencePrice,stopsLevel,freezeLevel);
}

//======================================================================
// Spread guard (auto-calibrating: median * multiplier, optional ceiling)
//======================================================================
int SpreadCalibrationTicksEffective()
{
   return (int)MathMax(20,MathMin(2000,InpSpreadCalibrationTicks));
}

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

   if(!InpAutoCalibrateSpreadCap)
   {
      if(InpMaxSpreadPoints<=0) return true;
      return (spread<=InpMaxSpreadPoints);
   }

   if(g_spreadCalEffectiveCap>=0.0)
      return (spread<=g_spreadCalEffectiveCap);

   int required=SpreadCalibrationTicksEffective();

   if(g_spreadCalCount<ArraySize(g_spreadCalSamples))
   {
      g_spreadCalSamples[g_spreadCalCount]=spread;
      g_spreadCalCount++;
   }

   if(g_spreadCalCount>=required)
   {
      double median=MedianOfSpreadSamples(g_spreadCalSamples,g_spreadCalCount);
      double mult  =MathMax(1.0,InpSpreadCalibrationMultiplier);
      double effective=median*mult;

      if(InpMaxSpreadPoints>0)
         effective=MathMin(effective,(double)InpMaxSpreadPoints);

      g_spreadCalEffectiveCap=MathMax(1.0,effective);

      Log("SPREAD AUTO-CALIBRATION COMPLETE"+
          " | samples="+IntegerToString(g_spreadCalCount)+
          " | median="+DoubleToString(median,1)+" pts"+
          " | multiplier="+DoubleToString(mult,2)+
          " | effective cap="+DoubleToString(g_spreadCalEffectiveCap,1)+" pts");
   }

   return true; // fail open while calibrating
}

//======================================================================
// Emergency stop / drawdown breaker
//======================================================================
void CloseAllPositions(string reason)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      bool ok=trade.PositionClose(ticket);
      uint retcode=trade.ResultRetcode();
      if(!ok || !TradeRetcodeAccepted(retcode))
         Log("EMERGENCY CLOSE FAILED ticket="+IntegerToString((int)ticket)+
             " retcode="+IntegerToString(retcode)+" reason="+reason);
   }

   for(int t=0;t<EZY_TIER_COUNT;t++)
   {
      g_tier[t].tradeActive=false;
      g_tier[t].tradeDirection=0;
      g_tier[t].ticket=0;
   }
}

void UpdateDrawdownBreaker()
{
   if(!InpEnableDrawdownBreaker)
   {
      g_tradingHalted=false;
      return;
   }

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0) return;

   g_peakEquity=MathMax(g_peakEquity,equity);
   if(g_peakEquity<=0.0) return;

   double drawdownPct=(g_peakEquity-equity)/g_peakEquity*100.0;
   double resumeThreshold=InpMaxEquityDrawdownPct*MathMax(0.0,MathMin(1.0,InpDrawdownResumeFactor));

   if(!g_tradingHalted && drawdownPct>=InpMaxEquityDrawdownPct)
   {
      g_tradingHalted=true;
      Log("DRAWDOWN BREAKER TRIPPED - closing all positions and halting new entries"+
          " | drawdown="+DoubleToString(drawdownPct,2)+"%");
      CloseAllPositions("drawdown breaker");
   }
   else if(g_tradingHalted && drawdownPct<=resumeThreshold)
   {
      g_tradingHalted=false;
      Log("DRAWDOWN BREAKER RESET - new entries resumed");
   }
}

//======================================================================
// Session / previous-day liquidity (shared globally, wall-clock driven,
// updated once per new M1 bar - server time, a disclosed adaptation of
// the Pine source's explicit Etc/UTC session inputs).
//======================================================================
void UpdateSessionLiquidity()
{
   datetime m1=iTime(_Symbol,PERIOD_M1,0);
   if(m1==0 || m1==g_lastM1BarTime) return;
   g_lastM1BarTime=m1;

   double h=iHigh(_Symbol,PERIOD_M1,1);
   double l=iLow(_Symbol,PERIOD_M1,1);
   if(h<=0.0 || l<=0.0) return;

   MqlDateTime dtStruct;
   TimeToStruct(iTime(_Symbol,PERIOD_M1,1),dtStruct);
   int hour=dtStruct.hour;

   bool asiaActive=(InpAsiaSessionStartHour<InpAsiaSessionEndHour)
                   ?(hour>=InpAsiaSessionStartHour && hour<InpAsiaSessionEndHour)
                   :(hour>=InpAsiaSessionStartHour || hour<InpAsiaSessionEndHour);
   bool londonActive=(InpLondonSessionStartHour<InpLondonSessionEndHour)
                     ?(hour>=InpLondonSessionStartHour && hour<InpLondonSessionEndHour)
                     :(hour>=InpLondonSessionStartHour || hour<InpLondonSessionEndHour);

   if(asiaActive && !g_asiaWasActive)
   {
      g_asiaRunningHigh=h;
      g_asiaRunningLow=l;
   }
   else if(asiaActive)
   {
      g_asiaRunningHigh=MathMax(g_asiaRunningHigh,h);
      g_asiaRunningLow=MathMin(g_asiaRunningLow,l);
   }
   if(!asiaActive && g_asiaWasActive)
   {
      g_completedAsiaHigh=g_asiaRunningHigh;
      g_completedAsiaLow=g_asiaRunningLow;
      g_completedAsiaAt=iTime(_Symbol,PERIOD_M1,1);
   }
   g_asiaWasActive=asiaActive;

   if(londonActive && !g_londonWasActive)
   {
      g_londonRunningHigh=h;
      g_londonRunningLow=l;
   }
   else if(londonActive)
   {
      g_londonRunningHigh=MathMax(g_londonRunningHigh,h);
      g_londonRunningLow=MathMin(g_londonRunningLow,l);
   }
   if(!londonActive && g_londonWasActive)
   {
      g_completedLondonHigh=g_londonRunningHigh;
      g_completedLondonLow=g_londonRunningLow;
      g_completedLondonAt=iTime(_Symbol,PERIOD_M1,1);
   }
   g_londonWasActive=londonActive;
}

//======================================================================
// Direction levels: nearest historical CLOSE below/above the entry-
// timeframe reference price (f_pick_direction_levels, verbatim formula).
//======================================================================
void PickDirectionLevels(int t)
{
   ENUM_TIMEFRAMES dtf=g_cfg[t].directionTF;
   double reference=iClose(_Symbol,g_cfg[t].entryTF,1);
   if(reference<=0.0) return;

   double minDist=MathMax(InpMinLevelSeparationPips,1.0)*StrategyPipSize();

   double s1=0,s2=0,r1=0,r2=0;
   double s1Dist=DBL_MAX,r1Dist=DBL_MAX,s2Dist=DBL_MAX,r2Dist=DBL_MAX;
   int maxN=MathMax(2,InpDirectionHistoryBars);

   for(int i=1;i<=maxN;i++)
   {
      double level=iClose(_Symbol,dtf,i);
      if(level<=0.0) continue;
      if(level<reference)
      {
         double d=reference-level;
         if(d<s1Dist) { s1=level; s1Dist=d; }
      }
      if(level>reference)
      {
         double d=level-reference;
         if(d<r1Dist) { r1=level; r1Dist=d; }
      }
   }
   for(int i=1;i<=maxN;i++)
   {
      double level=iClose(_Symbol,dtf,i);
      if(level<=0.0) continue;
      if(s1>0.0 && level<=s1-minDist)
      {
         double d=s1-level;
         if(d<s2Dist) { s2=level; s2Dist=d; }
      }
      if(r1>0.0 && level>=r1+minDist)
      {
         double d=level-r1;
         if(d<r2Dist) { r2=level; r2Dist=d; }
      }
   }

   double fallbackLow=iLow(_Symbol,dtf,iLowest(_Symbol,dtf,MODE_LOW,100,1));
   double fallbackHigh=iHigh(_Symbol,dtf,iHighest(_Symbol,dtf,MODE_HIGH,100,1));
   double atrHandleValue=0.0;
   int atrHandle=iATR(_Symbol,dtf,14);
   if(atrHandle!=INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(atrHandle,0,0,2,buf)>=2) atrHandleValue=buf[1];
      IndicatorRelease(atrHandle);
   }
   double safeATR=MathMax(atrHandleValue,minDist*5.0);

   if(s1<=0.0) s1=MathMin(fallbackLow>0?fallbackLow:reference-safeATR,reference-minDist);
   if(r1<=0.0) r1=MathMax(fallbackHigh>0?fallbackHigh:reference+safeATR,reference+minDist);
   if(s2<=0.0) s2=MathMin(fallbackLow>0?fallbackLow:s1-safeATR,s1-minDist);
   if(r2<=0.0) r2=MathMax(fallbackHigh>0?fallbackHigh:r1+safeATR,r1+minDist);

   g_tier[t].S1=RoundPrice(s1);
   g_tier[t].S2=RoundPrice(s2);
   g_tier[t].R1=RoundPrice(r1);
   g_tier[t].R2=RoundPrice(r2);
   g_tier[t].directionATR=safeATR;

   // Direction bias: direction-timeframe close vs its own EMA13.
   int emaHandle=iMA(_Symbol,dtf,InpDirectionEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   double directionClose=iClose(_Symbol,dtf,1);
   double directionEMA=0.0;
   if(emaHandle!=INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(emaHandle,0,1,2,buf)>=2) directionEMA=buf[0];
      IndicatorRelease(emaHandle);
   }
   g_tier[t].bullishBias=(directionClose>directionEMA && directionEMA>0.0);
   g_tier[t].bearishBias=(directionClose<directionEMA && directionEMA>0.0);

   // Support-timeframe ATR14, used only for the entry-bias tolerance below.
   int supportAtrHandle=iATR(_Symbol,g_cfg[t].supportTF,14);
   if(supportAtrHandle!=INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(supportAtrHandle,0,0,2,buf)>=2) g_tier[t].supportATR=buf[1];
      IndicatorRelease(supportAtrHandle);
   }
}

//======================================================================
// LOW-RISK zone construction (f_support_zone, verbatim formula): the
// nearest support-timeframe candle overlapping the level, sized as the
// rejection wick only - low-to-close for a support/BUY zone, close-to-
// high for a resistance/SELL zone - with a minimum-height guard and a
// symmetric-range fallback if no candle overlaps.
//======================================================================
void SupportZone(int t,double level,bool isSupport,double &zoneLo,double &zoneHi,datetime &zoneTime)
{
   ENUM_TIMEFRAMES stf=g_cfg[t].supportTF;
   int maxN=MathMax(2,InpSupportHistoryBars);

   double nearestLo=0,nearestHi=0,nearestClose=0; datetime nearestTime=0; bool found=false;
   double fallbackRange=0,fallbackDistance=DBL_MAX; datetime fallbackTime=0;

   for(int i=1;i<=maxN;i++)
   {
      double h=iHigh(_Symbol,stf,i);
      double l=iLow(_Symbol,stf,i);
      double c=iClose(_Symbol,stf,i);
      datetime tm=iTime(_Symbol,stf,i);
      if(h<=0.0 || l<=0.0 || h<=l) continue;

      if(!found && l<=level && h>=level)
      {
         nearestLo=l; nearestHi=h; nearestClose=c; nearestTime=tm; found=true;
      }

      double mid=(h+l)/2.0;
      double dist=MathAbs(mid-level);
      if(dist<fallbackDistance)
      {
         fallbackDistance=dist;
         fallbackRange=h-l;
         fallbackTime=tm;
      }
   }

   double minHeight=_Point*10.0;

   if(found)
   {
      if(isSupport)
      {
         zoneLo=nearestLo;
         zoneHi=nearestClose;
         if(zoneHi-zoneLo<minHeight) zoneLo=zoneHi-minHeight;
      }
      else
      {
         zoneLo=nearestClose;
         zoneHi=nearestHi;
         if(zoneHi-zoneLo<minHeight) zoneHi=zoneLo+minHeight;
      }
      zoneTime=nearestTime;
   }
   else
   {
      double preservedRange=MathMax(fallbackRange,_Point*10.0);
      zoneLo=level-preservedRange*0.5;
      zoneHi=level+preservedRange*0.5;
      zoneTime=fallbackTime;
   }

   zoneLo=RoundPrice(zoneLo);
   zoneHi=RoundPrice(zoneHi);
}

void BuildLowRiskZones(int t)
{
   double lo,hi; datetime tm;
   SupportZone(t,g_tier[t].S2,true,lo,hi,tm);
   g_tier[t].buyZoneLo=lo; g_tier[t].buyZoneHi=hi; g_tier[t].buyZoneTime=tm;

   SupportZone(t,g_tier[t].R2,false,lo,hi,tm);
   g_tier[t].sellZoneLo=lo; g_tier[t].sellZoneHi=hi; g_tier[t].sellZoneTime=tm;
}

//======================================================================
// Entry-timeframe confirmation: plain CHOCH, displacement CHOCH,
// rejection, ordinary sweep-reclaim, session/previous-day liquidity
// sweep-reclaim - all computed on the confirmed entry-timeframe candle,
// verbatim formulas from the Pine source.
//======================================================================
bool RangesOverlap(double lo1,double hi1,double lo2,double hi2)
{
   return (hi1>=lo2 && lo1<=hi2);
}

void UpdateConfirmations(int t)
{
   ENUM_TIMEFRAMES etf=g_cfg[t].entryTF;

   datetime entryTime=iTime(_Symbol,etf,1);
   if(entryTime==0 || entryTime==g_tier[t].bull.lastProcessedEntryTime)
      return;

   double o=iOpen(_Symbol,etf,1);
   double h=iHigh(_Symbol,etf,1);
   double l=iLow(_Symbol,etf,1);
   double c=iClose(_Symbol,etf,1);
   double prevClose=iClose(_Symbol,etf,2);

   double range=h-l;
   double body=MathAbs(c-o);
   double safeBody=MathMax(body,_Point);
   double lowerWick=MathMin(o,c)-l;
   double upperWick=h-MathMax(o,c);
   bool bullishBody=(c>o);
   bool bearishBody=(c<o);
   double bodyPct=(range>0)?body/range:0.0;
   double bullClosePos=(range>0)?(c-l)/range:0.0;
   double bearClosePos=(range>0)?(h-c)/range:0.0;

   int atrHandle=iATR(_Symbol,etf,14);
   double confirmedATR=0.0;
   if(atrHandle!=INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(atrHandle,0,0,3,buf)>=2) confirmedATR=buf[1];
      IndicatorRelease(atrHandle);
   }
   double displacementATR=MathMax(confirmedATR,_Point);

   int structureLookback=MathMax(InpEntryPivotBars*2+2,InpSweepLookbackBars);
   double recentHigh=0,recentLow=DBL_MAX; bool haveExtreme=false;
   for(int i=1;i<=structureLookback;i++)
   {
      double hh=iHigh(_Symbol,etf,i+1);
      double ll=iLow(_Symbol,etf,i+1);
      if(hh<=0.0 || ll<=0.0) continue;
      recentHigh=haveExtreme?MathMax(recentHigh,hh):hh;
      recentLow =haveExtreme?MathMin(recentLow,ll):ll;
      haveExtreme=true;
   }

   bool bullishBreak=haveExtreme && h>recentHigh && c>prevClose;
   bool bearishBreak=haveExtreme && l<recentLow  && c<prevClose;

   bool bullishChoch=bullishBreak && g_tier[t].bull.structureDirection<=0 && (!InpRequireDirectionalBody || bullishBody);
   bool bearishChoch=bearishBreak && g_tier[t].bear.structureDirection>=0 && (!InpRequireDirectionalBody || bearishBody);

   bool bullishDisplaceBreak=haveExtreme && c>=recentHigh+displacementATR*InpDisplacementMinBreakATR;
   bool bearishDisplaceBreak=haveExtreme && c<=recentLow -displacementATR*InpDisplacementMinBreakATR;
   bool bullishDisplacement=InpUseDisplacementChoch && g_tier[t].bull.structureDirection<=0 && bullishBody &&
                             range>=displacementATR*InpDisplacementMinRangeATR && bodyPct>=InpDisplacementMinBodyPct &&
                             bullClosePos>=0.70 && bullishDisplaceBreak;
   bool bearishDisplacement=InpUseDisplacementChoch && g_tier[t].bear.structureDirection>=0 && bearishBody &&
                             range>=displacementATR*InpDisplacementMinRangeATR && bodyPct>=InpDisplacementMinBodyPct &&
                             bearClosePos>=0.70 && bearishDisplaceBreak;

   bool bullishRejection=bullishBody && lowerWick>=safeBody*InpRejectionWickRatio && c>=l+range*0.45;
   bool bearishRejection=bearishBody && upperWick>=safeBody*InpRejectionWickRatio && c<=h-range*0.45;

   bool bullishSweep=InpUseSweepReclaim && haveExtreme && l<recentLow  && c>recentLow  && (!InpRequireDirectionalBody || bullishBody);
   bool bearishSweep=InpUseSweepReclaim && haveExtreme && h>recentHigh && c<recentHigh && (!InpRequireDirectionalBody || bearishBody);

   bool bullishPrevDay=false,bearishPrevDay=false,bullishAsia=false,bearishAsia=false,bullishLondon=false,bearishLondon=false;
   if(InpUseSessionDayLiquidity)
   {
      double prevDayLow =iLow(_Symbol,PERIOD_D1,1);
      double prevDayHigh=iHigh(_Symbol,PERIOD_D1,1);
      bullishPrevDay=(prevDayLow>0.0)  && l<prevDayLow  && c>prevDayLow  && (!InpRequireDirectionalBody || bullishBody);
      bearishPrevDay=(prevDayHigh>0.0) && h>prevDayHigh && c<prevDayHigh && (!InpRequireDirectionalBody || bearishBody);

      long maxAgeSec=(long)InpSessionLevelMaxAgeHours*3600;
      bool asiaFresh=(g_completedAsiaAt>0 && (TimeCurrent()-g_completedAsiaAt)<=maxAgeSec);
      bool londonFresh=(g_completedLondonAt>0 && (TimeCurrent()-g_completedLondonAt)<=maxAgeSec);

      bullishAsia=asiaFresh && g_completedAsiaLow>0.0 && entryTime>=g_completedAsiaAt && l<g_completedAsiaLow && c>g_completedAsiaLow && (!InpRequireDirectionalBody || bullishBody);
      bearishAsia=asiaFresh && g_completedAsiaHigh>0.0 && entryTime>=g_completedAsiaAt && h>g_completedAsiaHigh && c<g_completedAsiaHigh && (!InpRequireDirectionalBody || bearishBody);
      bullishLondon=londonFresh && g_completedLondonLow>0.0 && entryTime>=g_completedLondonAt && l<g_completedLondonLow && c>g_completedLondonLow && (!InpRequireDirectionalBody || bullishBody);
      bearishLondon=londonFresh && g_completedLondonHigh>0.0 && entryTime>=g_completedLondonAt && h>g_completedLondonHigh && c<g_completedLondonHigh && (!InpRequireDirectionalBody || bearishBody);
   }
   bool bullishPremium=bullishPrevDay || bullishAsia || bullishLondon;
   bool bearishPremium=bearishPrevDay || bearishAsia || bearishLondon;

   // Age reset (barssince equivalent: 0 = just happened, else increment
   // every entry-timeframe bar close until the event happens again).
   g_tier[t].bull.rejectAge  =bullishRejection ?0:g_tier[t].bull.rejectAge+1;
   g_tier[t].bear.rejectAge  =bearishRejection ?0:g_tier[t].bear.rejectAge+1;
   g_tier[t].bull.chochAge   =bullishChoch     ?0:g_tier[t].bull.chochAge+1;
   g_tier[t].bear.chochAge   =bearishChoch     ?0:g_tier[t].bear.chochAge+1;
   g_tier[t].bull.sweepAge   =bullishSweep     ?0:g_tier[t].bull.sweepAge+1;
   g_tier[t].bear.sweepAge   =bearishSweep     ?0:g_tier[t].bear.sweepAge+1;
   g_tier[t].bull.premiumAge =bullishPremium   ?0:g_tier[t].bull.premiumAge+1;
   g_tier[t].bear.premiumAge =bearishPremium   ?0:g_tier[t].bear.premiumAge+1;
   g_tier[t].bull.displaceAge=bullishDisplacement?0:g_tier[t].bull.displaceAge+1;
   g_tier[t].bear.displaceAge=bearishDisplacement?0:g_tier[t].bear.displaceAge+1;

   if(bullishSweep)     { g_tier[t].bull.lastSweepLo=l; g_tier[t].bull.lastSweepHi=h; g_tier[t].bull.lastSweepTime=entryTime; }
   if(bearishSweep)     { g_tier[t].bear.lastSweepLo=l; g_tier[t].bear.lastSweepHi=h; g_tier[t].bear.lastSweepTime=entryTime; }
   if(bullishPremium)   { g_tier[t].bull.lastPremiumLo=l; g_tier[t].bull.lastPremiumHi=h; g_tier[t].bull.lastPremiumTime=entryTime;
                          g_tier[t].bull.lastPremiumType=bullishPrevDay?"PREVIOUS-DAY LOW":bullishAsia?"ASIAN LOW":"LONDON LOW"; }
   if(bearishPremium)   { g_tier[t].bear.lastPremiumLo=l; g_tier[t].bear.lastPremiumHi=h; g_tier[t].bear.lastPremiumTime=entryTime;
                          g_tier[t].bear.lastPremiumType=bearishPrevDay?"PREVIOUS-DAY HIGH":bearishAsia?"ASIAN HIGH":"LONDON HIGH"; }
   if(bullishDisplacement) { g_tier[t].bull.lastDisplaceLo=l; g_tier[t].bull.lastDisplaceHi=h; g_tier[t].bull.lastDisplaceTime=entryTime; }
   if(bearishDisplacement) { g_tier[t].bear.lastDisplaceLo=l; g_tier[t].bear.lastDisplaceHi=h; g_tier[t].bear.lastDisplaceTime=entryTime; }

   if(bullishBreak) g_tier[t].bull.structureDirection=1;
   if(bearishBreak) g_tier[t].bear.structureDirection=-1;
   // The structure ratchet is one shared value in the source (entryStructureDirection);
   // mirror that by keeping bull/bear in sync to the same ratchet.
   if(bullishBreak) g_tier[t].bear.structureDirection=1;
   if(bearishBreak) g_tier[t].bull.structureDirection=-1;

   g_tier[t].bull.lastProcessedEntryTime=entryTime;
   g_tier[t].bear.lastProcessedEntryTime=entryTime;
}

//======================================================================
// READY arm / resync / invalidate / touch / commit - one lock per tier
//======================================================================
bool TryQualifyZoneCandidate(int t,int direction,double zoneLo,double zoneHi,datetime zoneTime,
                              TierConfirmState &side,double cmp,int &outRetests,string &outConfirmation)
{
   bool recentReject   =side.rejectAge<=InpArmedConfirmationWindowBars;
   bool recentChoch    =side.chochAge<=InpArmedConfirmationWindowBars;
   bool recentSweep    =side.sweepAge<=InpArmedConfirmationWindowBars    && RangesOverlap(side.lastSweepLo,side.lastSweepHi,zoneLo,zoneHi);
   bool recentPremium  =side.premiumAge<=InpArmedConfirmationWindowBars  && RangesOverlap(side.lastPremiumLo,side.lastPremiumHi,zoneLo,zoneHi);
   bool recentDisplace =side.displaceAge<=InpArmedConfirmationWindowBars && RangesOverlap(side.lastDisplaceLo,side.lastDisplaceHi,zoneLo,zoneHi);

   bool confirmed=recentReject || recentSweep || recentPremium || recentDisplace || recentChoch;
   if(!confirmed && !InpEnableZeroConfluenceTouch) return false;

   bool correctSide=(direction==1)?(zoneHi>0.0 && zoneHi<cmp-_Point):(zoneLo>0.0 && zoneLo>cmp+_Point);
   if(!correctSide) return false;
   if(zoneHi<=zoneLo) return false;

   int retests=ZoneRetestCount(t,zoneLo,zoneHi,zoneTime,iTime(_Symbol,g_cfg[t].entryTF,1));
   if(retests>InpMaxZoneRetests) return false;

   outRetests=retests;
   outConfirmation=recentPremium?((direction==1)?g_tier[t].bull.lastPremiumType:g_tier[t].bear.lastPremiumType)+" SWEEP + RECLAIM":
                    recentSweep?"LIQUIDITY SWEEP + RECLAIM":
                    recentDisplace?"DISPLACEMENT CHOCH":
                    recentReject?"ENTRY ZONE REJECTION":
                    recentChoch?"STRUCTURE BREAK (CHOCH)":
                    "ZERO-CONFLUENCE TOUCH";
   return true;
}

bool QualifyZone(int t,int direction,double &outLo,double &outHi,datetime &outTime,int &outRetests,string &outConfirmation,bool &outCounterTrend,string &outRisk)
{
   bool bullishBias=g_tier[t].bullishBias;
   bool bearishBias=g_tier[t].bearishBias;

   double entryClose=iClose(_Symbol,g_cfg[t].entryTF,1);
   int emaHandle=iMA(_Symbol,g_cfg[t].entryTF,InpDirectionEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   double entryEMA=0.0;
   if(emaHandle!=INVALID_HANDLE)
   {
      double buf[];
      ArraySetAsSeries(buf,true);
      if(CopyBuffer(emaHandle,0,1,2,buf)>=1) entryEMA=buf[0];
      IndicatorRelease(emaHandle);
   }
   double tolerance=MathMax(g_tier[t].supportATR*InpEntryBiasToleranceAtrMult,InpEntryBiasToleranceMinPips*StrategyPipSize());
   bool entryBullish=(entryClose>=entryEMA-tolerance);
   bool entryBearish=(entryClose<=entryEMA+tolerance);

   bool trendRoute        =(direction==1)?(bullishBias && entryBullish):(bearishBias && entryBearish);
   bool counterTrendRoute =(direction==1)?(bearishBias && entryBullish):(bullishBias && entryBearish);
   bool isCounterTrend=counterTrendRoute && !trendRoute;
   bool allow=trendRoute || isCounterTrend;
   if(!allow) return false;

   TierConfirmState side;
   if(direction==1) side=g_tier[t].bull; else side=g_tier[t].bear;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   double cmp=tick.bid;

   double zoneLo=(direction==1)?g_tier[t].buyZoneLo:g_tier[t].sellZoneLo;
   double zoneHi=(direction==1)?g_tier[t].buyZoneHi:g_tier[t].sellZoneHi;
   datetime zoneTime=(direction==1)?g_tier[t].buyZoneTime:g_tier[t].sellZoneTime;

   if(TryQualifyZoneCandidate(t,direction,zoneLo,zoneHi,zoneTime,side,cmp,outRetests,outConfirmation))
   {
      outLo=zoneLo; outHi=zoneHi; outTime=zoneTime; outCounterTrend=isCounterTrend; outRisk="LOW RISK";
      return true;
   }

   // HIGH-RISK zone: the nearer S1/R1 level, same rejection-wick zone
   // construction as LOW-RISK. Off by default in the Pine source (which
   // always arms on LOW-RISK only) - enabling it roughly doubles the
   // number of candidate touch zones per tier/direction, per explicit
   // request to make the EA more aggressive.
   if(InpEnableHighRiskZone)
   {
      double hrLo=0,hrHi=0; datetime hrTime=0;
      double hrLevel=(direction==1)?g_tier[t].S1:g_tier[t].R1;
      SupportZone(t,hrLevel,direction==1,hrLo,hrHi,hrTime);

      if(TryQualifyZoneCandidate(t,direction,hrLo,hrHi,hrTime,side,cmp,outRetests,outConfirmation))
      {
         outLo=hrLo; outHi=hrHi; outTime=hrTime; outCounterTrend=isCounterTrend; outRisk="HIGH RISK";
         return true;
      }
   }

   return false;
}

int ZoneRetestCount(int t,double zoneLo,double zoneHi,datetime zoneTime,datetime currentEntryTime)
{
   if(zoneLo<=0.0 || zoneHi<=0.0 || zoneTime<=0 || currentEntryTime<=0) return 0;

   long supportSeconds=(long)PeriodSeconds(g_cfg[t].supportTF);
   datetime zoneReadyTime=zoneTime+(datetime)supportSeconds;

   int retests=0;
   bool previousInside=false;
   int cap=MathMax(3,InpArmedExpiryEntryBars+5);

   for(int offset=cap;offset>=1;offset--)
   {
      datetime candleTime=iTime(_Symbol,g_cfg[t].entryTF,offset);
      if(candleTime==0) continue;
      if(candleTime<zoneReadyTime || candleTime>currentEntryTime) continue;

      double hh=iHigh(_Symbol,g_cfg[t].entryTF,offset);
      double ll=iLow(_Symbol,g_cfg[t].entryTF,offset);
      bool inside=RangesOverlap(ll,hh,zoneLo,zoneHi);

      if(inside && !previousInside) retests++;
      previousInside=inside;
   }
   return retests;
}

int CountOpenPositionsForTierDirection(int t,int direction)
{
   string wantComment="V7"+g_cfg[t].label;
   ENUM_POSITION_TYPE wantType=(direction==1)?POSITION_TYPE_BUY:POSITION_TYPE_SELL;
   int count=0;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)!=wantType) continue;
      if(PositionGetString(POSITION_COMMENT)!=wantComment) continue;
      count++;
   }
   return count;
}

void ProcessArmAndResync(int t,int direction)
{
   TierSideState side;
   if(direction==1) side=g_tier[t].buySide; else side=g_tier[t].sellSide;
   bool tradeLockedThisDirection=CountOpenPositionsForTierDirection(t,direction)>=InpMaxConcurrentPerTierDirection;

   double lo=0,hi=0; datetime tm=0; int retests=0; string confirmation=""; bool counterTrend=false; string risk="";
   bool qualifies=QualifyZone(t,direction,lo,hi,tm,retests,confirmation,counterTrend,risk);

   if(!side.armed)
   {
      if(!tradeLockedThisDirection && qualifies)
      {
         side.armed=true;
         side.risk=risk;
         side.confirmation=confirmation;
         side.counterTrend=counterTrend;
         side.supportLo=lo; side.supportHi=hi;
         side.retests=retests;
         side.zoneExited=false;
         side.entryLo=lo; side.entryHi=hi; side.entryTime=tm;
         side.armedAtClock=TimeCurrent();
         side.touchLatched=false;
      }
   }
   else
   {
      // Zone resync: if the underlying zone moved since arming (or the side
      // no longer qualifies at all), re-qualify or drop the stale arm.
      bool zoneMoved=(!qualifies) || (MathAbs(lo-side.supportLo)>_Point || MathAbs(hi-side.supportHi)>_Point);
      if(zoneMoved)
      {
         if(qualifies)
         {
            side.supportLo=lo; side.supportHi=hi;
            side.entryLo=lo; side.entryHi=hi; side.entryTime=tm;
            side.retests=retests;
            side.zoneExited=false;
            side.risk=risk;
            side.confirmation=confirmation;
            side.counterTrend=counterTrend;
            side.armedAtClock=TimeCurrent();
            side.touchLatched=false;
         }
         else
         {
            side.armed=false;
            side.touchLatched=false;
         }
      }

      if(side.armed && !side.touchLatched)
      {
         long expirySeconds=(long)InpArmedExpiryEntryBars*(long)PeriodSeconds(g_cfg[t].entryTF);
         bool expired=(TimeCurrent()-side.armedAtClock)>expirySeconds;

         MqlTick tick;
         SymbolInfoTick(_Symbol,tick);
         double cmp=tick.bid;
         double invalidationBuffer=MathMax(StrategyPipSize()*5.0,_Point*2.0);
         bool zoneInvalid=(direction==1)?(cmp<side.supportLo-invalidationBuffer):(cmp>side.supportHi+invalidationBuffer);

         bool touchedNow=RangesOverlap(cmp,cmp,side.entryLo,side.entryHi);
         if(!touchedNow) side.zoneExited=true;
         bool retestLimitInvalid=side.zoneExited && touchedNow && side.retests>=InpMaxZoneRetests;

         bool sideInvalid=(direction==1)?(!touchedNow && side.entryHi>=cmp-_Point):(!touchedNow && side.entryLo<=cmp+_Point);

         if(expired || zoneInvalid || retestLimitInvalid || sideInvalid)
         {
            side.armed=false;
         }
      }
   }

   if(direction==1) g_tier[t].buySide=side; else g_tier[t].sellSide=side;
}

void ProcessTouch(int t,int direction)
{
   TierSideState side;
   if(direction==1) side=g_tier[t].buySide; else side=g_tier[t].sellSide;
   if(!side.armed || side.touchLatched) return;
   if(CountOpenPositionsForTierDirection(t,direction)>=InpMaxConcurrentPerTierDirection) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;
   double cmp=(direction==1)?tick.bid:tick.ask;

   bool touched=(cmp>=side.entryLo && cmp<=side.entryHi);
   if(!touched) return;

   side.touchLatched=true;
   if(direction==1) g_tier[t].buySide=side; else g_tier[t].sellSide=side;

   if(SubmitEntryOrder(t,direction))
   {
      side.armed=false;
      if(direction==1) g_tier[t].buySide=side; else g_tier[t].sellSide=side;
   }
   // If the order failed (spread/margin/etc.), touchLatched stays true so we
   // don't keep re-attempting on every tick - the zone invalidation rules
   // above will eventually clear a stuck armed slot.
}

bool SubmitEntryOrder(int t,int direction)
{
   g_gateAttempts++;

   if(g_tradingHalted) { g_gateDrawdownRejects++; return false; }
   if(!SpreadAllowed()) { g_gateSpreadRejects++; return false; }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;

   double entry=(direction==1)?tick.ask:tick.bid;
   double slDistance=MathMax(0.1,InpPresetStopLossPips)*StrategyPipSize();
   double sl=RoundPrice((direction==1)?entry-slDistance:entry+slDistance);

   double minDist=MinimumStopDistance(entry);
   if(MathAbs(entry-sl)<minDist)
   {
      g_gateDistanceRejects++;
      Log("ENTRY REJECTED ["+g_cfg[t].label+"] reason=SL_DISTANCE_TOO_TIGHT");
      return false;
   }

   double lots=ComputeLotsForRisk(direction,entry,sl);
   if(lots<=0.0)
   {
      g_gateSizingRejects++;
      Log("ENTRY REJECTED ["+g_cfg[t].label+"] reason=ZERO_LOTS");
      return false;
   }

   string comment="V7"+g_cfg[t].label;
   bool sent=(direction==1)
             ? trade.Buy(lots,_Symbol,0.0,sl,0.0,comment)
             : trade.Sell(lots,_Symbol,0.0,sl,0.0,comment);

   uint retcode=trade.ResultRetcode();

   if(sent && TradeRetcodeAccepted(retcode))
   {
      g_gateAccepted++;
      g_totalLotsTraded+=lots;
      g_totalFills++;

      ulong ticketOut=trade.ResultOrder();
      if(!PositionSelectByTicket(ticketOut))
      {
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong candidate=PositionGetTicket(i);
            if(candidate==0) continue;
            if(!PositionSelectByTicket(candidate)) continue;
            if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
            if(PositionGetString(POSITION_COMMENT)!=comment) continue;
            ticketOut=candidate;
            break;
         }
      }

      g_tier[t].tradeActive=true;
      g_tier[t].tradeDirection=direction;
      g_tier[t].ticket=ticketOut;

      Log("LIVE ["+g_cfg[t].label+"/"+g_cfg[t].modeLabel+"] dir="+(direction==1?"BUY":"SELL")+
          " lots="+DoubleToString(lots,2)+" entry="+PriceText(entry)+" sl="+PriceText(sl)+
          " | total lots traded="+DoubleToString(g_totalLotsTraded,2));
      return true;
   }

   g_gateRejected++;
   Log("ENTRY REJECTED ["+g_cfg[t].label+"] retcode="+IntegerToString(retcode)+
       " desc="+trade.ResultRetcodeDescription());
   return false;
}

//======================================================================
// Hybrid virtual trail - shared across every tier's positions, same
// pattern as the rest of the EzyEA family: wide preset floor from entry,
// tightens to a tighter trail distance once floating P&L clears the
// activation threshold. The virtual stop is the source of truth and is
// enforced by a direct close, independent of whether the broker accepts
// a tight SL modify; the broker-side SL is still pushed as a best-effort
// backup at a broker-legal distance.
//======================================================================
int EnsureManagedSlot(ulong ticket)
{
   int n=ArraySize(g_managed);
   for(int i=0;i<n;i++)
      if(g_managed[i].ticket==ticket) return i;

   if(!PositionSelectByTicket(ticket)) return -1;

   int direction=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
   double openPrice   =PositionGetDouble(POSITION_PRICE_OPEN);
   double openSl       =PositionGetDouble(POSITION_SL);
   double currentPrice =PositionGetDouble(POSITION_PRICE_CURRENT);
   datetime positionTime=(datetime)PositionGetInteger(POSITION_TIME);

   int idx=n;
   ArrayResize(g_managed,n+1);
   g_managed[idx].ticket=ticket;
   g_managed[idx].consecutiveFailures=0;
   g_managed[idx].cooldownUntil=0;
   g_managed[idx].peakPrice=ReconstructPeakFromM1(direction,openPrice,currentPrice,positionTime);
   g_managed[idx].peakReconstructed=true;
   g_managed[idx].virtualStop=openSl;
   return idx;
}

void PruneManagedSlots()
{
   for(int i=ArraySize(g_managed)-1;i>=0;i--)
   {
      if(PositionSelectByTicket(g_managed[i].ticket)) continue;

      int last=ArraySize(g_managed)-1;
      g_managed[i]=g_managed[last];
      ArrayResize(g_managed,last);
   }
}

double ReconstructPeakFromM1(int direction,double entry,double current,datetime positionTime)
{
   double peak=current;
   if(!InpReconstructPeakFromM1 || positionTime<=0) return peak;

   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,PERIOD_M1,positionTime,TimeCurrent(),rates);
   if(copied<=0) return peak;

   for(int i=0;i<copied;i++)
   {
      if(direction==1) peak=MathMax(peak,rates[i].high);
      else             peak=MathMin(peak,rates[i].low);
   }
   if(direction==1) peak=MathMax(peak,entry); else peak=MathMin(peak,entry);
   return RoundPrice(peak);
}

void ModifyPositionSafely(ulong ticket,double sl,double tp)
{
   int slot=EnsureManagedSlot(ticket);
   if(slot<0) return;
   if(g_managed[slot].cooldownUntil>0 && TimeCurrent()<g_managed[slot].cooldownUntil) return;
   if(!PositionSelectByTicket(ticket)) return;

   bool ok=trade.PositionModify(ticket,sl,tp);
   uint retcode=trade.ResultRetcode();

   if(ok && TradeRetcodeAccepted(retcode))
   {
      g_managed[slot].consecutiveFailures=0;
      g_managed[slot].cooldownUntil=0;
      return;
   }

   g_managed[slot].consecutiveFailures++;
   int steps=(int)MathMin((double)g_managed[slot].consecutiveFailures,6.0);
   int backoffSeconds=(int)MathMin(300.0,2.0*MathPow(2.0,steps-1));
   g_managed[slot].cooldownUntil=TimeCurrent()+backoffSeconds;

   if(!TemporaryTradeRetcode(retcode))
      Log("MODIFY REJECTED ticket="+IntegerToString((int)ticket)+" retcode="+IntegerToString(retcode)+
          " backoff="+IntegerToString(backoffSeconds)+"s");
}

bool CloseAtVirtualStop(ulong ticket,string context,double current,double stop,double peak)
{
   ulong deviation=(ulong)MathMax(0,InpVirtualTrailCloseDeviationPts);
   trade.SetDeviationInPoints(deviation);
   bool sent=trade.PositionClose(ticket,deviation);
   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);
   trade.SetDeviationInPoints((ulong)MathMax(0,InpDeviationPoints));

   if(accepted)
   {
      Log("VIRTUAL TRAIL CLOSE | "+context+" | ticket="+IntegerToString((int)ticket)+
          " | current="+PriceText(current)+" | virtualSL="+PriceText(stop)+" | peak="+PriceText(peak));
      return true;
   }

   Log("VIRTUAL TRAIL CLOSE FAILED | "+context+" | ticket="+IntegerToString((int)ticket)+
       " | retcode="+IntegerToString((int)code)+" | "+trade.ResultRetcodeDescription());
   return false;
}

void ManageTrailing()
{
   double slDistance=MathMax(0.1,InpPresetStopLossPips)*StrategyPipSize();
   double trailDistance=MathMax(0.1,InpTrailingDistancePips)*StrategyPipSize();
   double activationDistance=MathMax(0.0,InpTrailingActivationPips)*StrategyPipSize();

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      int slot=EnsureManagedSlot(ticket);
      if(slot<0) continue;

      int direction=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      double openPrice   =PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl   =PositionGetDouble(POSITION_SL);
      double currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      if(direction==1) g_managed[slot].peakPrice=MathMax(g_managed[slot].peakPrice,currentPrice);
      else             g_managed[slot].peakPrice=MathMin(g_managed[slot].peakPrice,currentPrice);

      double peak=g_managed[slot].peakPrice;
      double favorable=(direction==1)?(peak-openPrice):(openPrice-peak);

      if(g_managed[slot].virtualStop<=0.0)
         g_managed[slot].virtualStop=RoundPrice((direction==1)?openPrice-slDistance:openPrice+slDistance);

      if(favorable>=activationDistance)
      {
         double trailedStop=RoundPrice((direction==1)?peak-trailDistance:peak+trailDistance);
         bool improves=(direction==1)?(trailedStop>g_managed[slot].virtualStop):(trailedStop<g_managed[slot].virtualStop);
         if(improves) g_managed[slot].virtualStop=trailedStop;
      }

      double virtualStop=g_managed[slot].virtualStop;
      bool virtualHit=(direction==1)?currentPrice<=virtualStop+_Point*0.25:currentPrice>=virtualStop-_Point*0.25;

      if(InpUseVirtualTrailFallback && virtualHit)
      {
         CloseAtVirtualStop(ticket,"ManageTrailing",currentPrice,virtualStop,peak);
         continue;
      }

      double minDist=MinimumStopDistance(currentPrice);
      double brokerAllowed=(direction==1)?currentPrice-minDist:currentPrice+minDist;
      double desiredSl=(direction==1)?MathMin(virtualStop,brokerAllowed):MathMax(virtualStop,brokerAllowed);
      desiredSl=RoundPrice(desiredSl);

      bool improvesBroker=(currentSl<=0.0) || ((direction==1)?(desiredSl>currentSl):(desiredSl<currentSl));
      if(!improvesBroker) continue;

      double minStep=InpTrailMinStepPoints*_Point;
      if(currentSl>0.0 && MathAbs(desiredSl-currentSl)<minStep) continue;

      bool validSide=(direction==1)?(desiredSl<currentPrice):(desiredSl>currentPrice);
      if(!validSide) continue;

      ModifyPositionSafely(ticket,desiredSl,PositionGetDouble(POSITION_TP));
   }
}

//======================================================================
// Lot-traded / backtest report - reconstructed from broker deal history
// at OnDeinit, same pattern used across the EzyEA family.
//======================================================================
int EnsureBacktestRow(BacktestTradeRow &rows[],long positionId)
{
   for(int i=0;i<ArraySize(rows);i++)
      if(rows[i].positionId==positionId) return i;

   int n=ArraySize(rows);
   ArrayResize(rows,n+1);
   rows[n].positionId=positionId;
   rows[n].entryLots=0.0;
   rows[n].netPnl=0.0;
   rows[n].hasExit=false;
   return n;
}

void WriteBacktestReport()
{
   if(!HistorySelect(0,TimeCurrent()))
   {
      Log("REPORT: HistorySelect failed.");
      return;
   }

   BacktestTradeRow rows[];
   int deals=HistoryDealsTotal();
   int actualFills=0;

   for(int i=0;i<deals;i++)
   {
      ulong deal=HistoryDealGetTicket(i);
      if(deal==0) continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=InpMagicNumber) continue;

      ENUM_DEAL_TYPE type=(ENUM_DEAL_TYPE)HistoryDealGetInteger(deal,DEAL_TYPE);
      if(type!=DEAL_TYPE_BUY && type!=DEAL_TYPE_SELL) continue;

      long positionId=(long)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(positionId<=0) continue;

      int row=EnsureBacktestRow(rows,positionId);
      double profit=HistoryDealGetDouble(deal,DEAL_PROFIT)+HistoryDealGetDouble(deal,DEAL_SWAP)+HistoryDealGetDouble(deal,DEAL_COMMISSION);
      rows[row].netPnl+=profit;

      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal,DEAL_ENTRY);
      double volume=HistoryDealGetDouble(deal,DEAL_VOLUME);
      if((entry==DEAL_ENTRY_IN || entry==DEAL_ENTRY_INOUT) && volume>0.0)
      {
         rows[row].entryLots+=volume;
         actualFills++;
      }
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY || entry==DEAL_ENTRY_INOUT)
         rows[row].hasExit=true;
   }

   double totalEntryLots=0.0; int closedTrades=0,wins=0,losses=0,breakeven=0,openTrades=0;
   double closedNet=0.0; double pnlEpsilon=0.005;

   for(int i=0;i<ArraySize(rows);i++)
   {
      if(rows[i].entryLots<=0.0) continue;
      totalEntryLots+=rows[i].entryLots;

      if(PositionSelectByTicket((ulong)rows[i].positionId)) { openTrades++; continue; }
      if(!rows[i].hasExit) continue;

      closedTrades++;
      closedNet+=rows[i].netPnl;
      if(rows[i].netPnl>pnlEpsilon) wins++;
      else if(rows[i].netPnl<-pnlEpsilon) losses++;
      else breakeven++;
   }

   double winRate=(wins+losses>0)?100.0*(double)wins/(double)(wins+losses):0.0;

   Log("================ EZYEA V7 LOT-TRADED / BACKTEST SUMMARY ================");
   Log("TOTAL ENTRY LOTS: "+DoubleToString(totalEntryLots,VolumeDigits())+" | ACTUAL ENTRY FILLS: "+IntegerToString(actualFills));
   Log("CLOSED TRADES: "+IntegerToString(closedTrades)+" | wins="+IntegerToString(wins)+" | losses="+IntegerToString(losses)+
       " | breakeven="+IntegerToString(breakeven)+" | open="+IntegerToString(openTrades));
   Log("WINRATE: "+DoubleToString(winRate,2)+"% | CLOSED NET: "+DoubleToString(closedNet,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
   Log("===========================================================================");

   if(!InpWriteCSVReport) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   string filename=StringFormat("%s_%s_%04d%02d%02d_%02d%02d.csv",InpCSVReportPrefix,_Symbol,dt.year,dt.mon,dt.day,dt.hour,dt.min);
   int handle=FileOpen(filename,FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON,',');
   if(handle==INVALID_HANDLE)
   {
      Log("REPORT: could not create CSV. Error="+IntegerToString(GetLastError()));
      return;
   }

   FileWrite(handle,"PositionID","EntryLots","NetPnL","Status");
   for(int i=0;i<ArraySize(rows);i++)
   {
      if(rows[i].entryLots<=0.0) continue;
      string status="INCOMPLETE";
      if(PositionSelectByTicket((ulong)rows[i].positionId)) status="OPEN";
      else if(rows[i].hasExit)
      {
         if(rows[i].netPnl>pnlEpsilon) status="WIN";
         else if(rows[i].netPnl<-pnlEpsilon) status="LOSS";
         else status="BREAKEVEN";
      }
      FileWrite(handle,(string)rows[i].positionId,DoubleToString(rows[i].entryLots,VolumeDigits()),DoubleToString(rows[i].netPnl,2),status);
   }
   FileWrite(handle,"");
   FileWrite(handle,"SUMMARY","Value");
   FileWrite(handle,"TotalEntryLots",DoubleToString(totalEntryLots,VolumeDigits()));
   FileWrite(handle,"ActualEntryFills",actualFills);
   FileWrite(handle,"ClosedTrades",closedTrades);
   FileWrite(handle,"WinningTrades",wins);
   FileWrite(handle,"LosingTrades",losses);
   FileWrite(handle,"BreakevenTrades",breakeven);
   FileWrite(handle,"OpenTrades",openTrades);
   FileWrite(handle,"WinRatePct",DoubleToString(winRate,2));
   FileWrite(handle,"ClosedNet",DoubleToString(closedNet,2));
   FileClose(handle);
   Log("REPORT: CSV written to "+filename);
}

//======================================================================
// Chart drawing
//======================================================================
void DrawStatusLabel()
{
   string name="V7_StatusLabel";
   string text="EzyEA V7 | ";
   for(int t=0;t<EZY_TIER_COUNT;t++)
   {
      text+=g_cfg[t].label+"=";
      if(g_tier[t].tradeActive) text+=(g_tier[t].tradeDirection==1?"LIVE-BUY":"LIVE-SELL");
      else if(g_tier[t].buySide.armed && g_tier[t].sellSide.armed) text+="RDY-B/S";
      else if(g_tier[t].buySide.armed) text+="RDY-BUY";
      else if(g_tier[t].sellSide.armed) text+="RDY-SELL";
      else text+="-";
      text+="  ";
   }
   text+="| lots traded="+DoubleToString(g_totalLotsTraded,2)+
         " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" | "+(g_tradingHalted?"HALTED":"ACTIVE");

   if(ObjectFind(0,name)<0)
   {
      ObjectCreate(0,name,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_XDISTANCE,10);
      ObjectSetInteger(0,name,OBJPROP_YDISTANCE,20);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   }
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clrWhite);
}

void DrawLiveTradeLevels()
{
   ObjectsDeleteAll(0,"V7_LIVE_");

   for(int t=0;t<EZY_TIER_COUNT;t++)
   {
      if(!g_tier[t].tradeActive) continue;
      if(!PositionSelectByTicket(g_tier[t].ticket)) continue;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   =PositionGetDouble(POSITION_SL);
      color  directionColor=(g_tier[t].tradeDirection==1)?InpBuyColor:InpSellColor;

      string nameE="V7_LIVE_ENTRY_"+g_cfg[t].label;
      if(ObjectFind(0,nameE)<0) ObjectCreate(0,nameE,OBJ_HLINE,0,0,entry);
      ObjectSetDouble(0,nameE,OBJPROP_PRICE,entry);
      ObjectSetInteger(0,nameE,OBJPROP_COLOR,directionColor);
      ObjectSetInteger(0,nameE,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,nameE,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameE,OBJPROP_SELECTABLE,false);

      if(sl>0.0)
      {
         string nameS="V7_LIVE_SL_"+g_cfg[t].label;
         if(ObjectFind(0,nameS)<0) ObjectCreate(0,nameS,OBJ_HLINE,0,0,sl);
         ObjectSetDouble(0,nameS,OBJPROP_PRICE,sl);
         ObjectSetInteger(0,nameS,OBJPROP_COLOR,InpTradeLevelGold);
         ObjectSetInteger(0,nameS,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,nameS,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nameS,OBJPROP_SELECTABLE,false);
      }
   }
}

void ApplyPremiumChartTheme()
{
   if(!InpApplyPremiumTheme) return;

   ChartSetInteger(0,CHART_MODE,CHART_CANDLES);
   ChartSetInteger(0,CHART_SHOW_GRID,false);
   ChartSetInteger(0,CHART_SHOW_VOLUMES,CHART_VOLUME_HIDE);
   ChartSetInteger(0,CHART_SHOW_PERIOD_SEP,false);
   ChartSetInteger(0,CHART_SHOW_OBJECT_DESCR,false);

   if(InpHideNativeTickerOHLC)
   {
      ChartSetInteger(0,CHART_SHOW_TICKER,false);
      ChartSetInteger(0,CHART_SHOW_OHLC,false);
   }

   ChartSetInteger(0,CHART_COLOR_BACKGROUND,InpChartBackground);
   ChartSetInteger(0,CHART_COLOR_FOREGROUND,InpChartForeground);
   ChartSetInteger(0,CHART_COLOR_GRID,InpChartBackground);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BULL,InpBullCandleColor);
   ChartSetInteger(0,CHART_COLOR_CANDLE_BEAR,InpBearCandleColor);
   ChartSetInteger(0,CHART_COLOR_CHART_UP,InpBullCandleColor);
   ChartSetInteger(0,CHART_COLOR_CHART_DOWN,InpBearCandleColor);
   ChartSetInteger(0,CHART_COLOR_CHART_LINE,InpChartForeground);
}

void RemoveAllDrawings()
{
   ObjectsDeleteAll(0,"V7_");
}

//======================================================================
// Reporting
//======================================================================
void WriteFinalReport()
{
   Log("FINAL REPORT | attempts="+IntegerToString(g_gateAttempts)+
       " accepted="+IntegerToString(g_gateAccepted)+
       " rejected="+IntegerToString(g_gateRejected)+
       " | spreadRejects="+IntegerToString(g_gateSpreadRejects)+
       " distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " sizingRejects="+IntegerToString(g_gateSizingRejects)+
       " drawdownRejects="+IntegerToString(g_gateDrawdownRejects)+
       " | totalLotsTraded="+DoubleToString(g_totalLotsTraded,2)+
       " totalFills="+IntegerToString(g_totalFills));
}

void PeriodicStatusLog()
{
   if(InpStatusLogIntervalSeconds<=0) return;
   if(TimeCurrent()-g_lastStatusLogTime<InpStatusLogIntervalSeconds) return;
   g_lastStatusLogTime=TimeCurrent();

   string tiers="";
   for(int t=0;t<EZY_TIER_COUNT;t++)
   {
      tiers+=g_cfg[t].label+"["+(g_tier[t].tradeActive?"LIVE":(g_tier[t].buySide.armed||g_tier[t].sellSide.armed?"RDY":"-"))+"] ";
   }

   Log("STATUS | equity="+DoubleToString(EffectiveAccountEquity(),2)+" | "+tiers+
       " | lots traded="+DoubleToString(g_totalLotsTraded,2)+" fills="+IntegerToString(g_totalFills)+
       " | halted="+(g_tradingHalted?"YES":"NO"));

   Log("DEPLOYMENT GATE BREAKDOWN | attempts="+IntegerToString(g_gateAttempts)+
       " accepted="+IntegerToString(g_gateAccepted)+
       " rejected="+IntegerToString(g_gateRejected)+
       " | spread="+IntegerToString(g_gateSpreadRejects)+
       " distance="+IntegerToString(g_gateDistanceRejects)+
       " sizing="+IntegerToString(g_gateSizingRejects)+
       " drawdown="+IntegerToString(g_gateDrawdownRejects));
}
