//+------------------------------------------------------------------+
//|                                             EzyEA_V1_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V1 (REBUILT #2) - per explicit instruction, trigger is         |
//| EMA100 + SND levels, LOOSE zone confluence, paired PER TIMEFRAME:    |
//| the M15 SND level pairs only with the M15 EMA100, and so on through  |
//| H1/H4/D1 (M5, M30 removed) - four independent same-timeframe         |
//| pairings, not one EMA checked against every level.                   |
//| For each SND level, if its own timeframe's live EMA100 value sits    |
//| within InpDecisionRangeRatio of that level's own hi-lo range (a wide |
//| "decision range" tolerance, not a tight cluster check, and NOT a     |
//| fixed $ amount - it scales with each timeframe's own realized range  |
//| since a fixed points value cannot work across timeframes whose       |
//| ranges differ by an order of magnitude), the pairing becomes an      |
//| active trigger zone spanning EMA100->level. Price touching anywhere  |
//| in that zone fades in the level's own direction (supply ->           |
//| SELL, demand -> BUY) - reusing the level's intrinsic type rather     |
//| than inferring direction from which side price approached from,      |
//| since a wide zone makes "which side did price come from" ambiguous   |
//| far more often than a tight overlap did.                             |
//|                                                                      |
//| Everything else is the same proven infrastructure from this          |
//| session: risk-based lot sizing via OrderCalcProfit() with a          |
//| portfolio-aware margin check, ATR-based SL/trail-only exit with       |
//| the activation-floor rule and the trailing side-validation fix,       |
//| a hard max-holding-time exit, an overall peak-equity drawdown          |
//| breaker, TimeCurrent()-based modify backoff, the zero-stops-level      |
//| broker fallback, an auto-calibrating spread guard, and cent-account-   |
//| aware equity handling. The minimum-lot fallback defaults OFF (the       |
//| lesson confirmed live on V4).                                            |
//|                                                                             |
//| CHANGELOG                                                                   |
//| 1.000 (rebuild)   - EMA13/EMA47/Pivot confluence. Zero trades.               |
//| 1.001 (rebuild)   - Pivot dropped, EMA13/EMA47 overlap only.                 |
//|                     Drawdown confirmed not good.                             |
//| 1.002 (rebuild 2) - EMA200 + SNR levels, loose zone confluence.              |
//| 1.003              - SNR levels restricted to M5 only (was M5->W1).          |
//| 1.004              - Reverted to multi-TF, but each TF's SNR level must      |
//|                      pair with that SAME TF's own EMA100 (M5/M15/M30/H1/     |
//|                      H4/D1) rather than a single M5 EMA against a stack of   |
//|                      levels. Decision range/touch tolerance widened          |
//|                      (100/30 -> 400/50 pts) since the M5-only build's zero-  |
//|                      trades result was most likely a too-tight zone.        |
//| 1.005              - Still zero trades. Root cause: EMA100 averages a        |
//|                      100-bar window but levels used a much shorter          |
//|                      lookback (24/32/20/24/15/8 bars, 3-12x shorter) -       |
//|                      a slow EMA almost never sits near a fast extreme.       |
//|                      All 6 lookbacks now match the EMA period (100 bars)    |
//|                      so the level and its EMA describe the same window.     |
//| 1.006              - STILL zero trades - confirmed via live Journal log:    |
//|                      "in decision range=0" on EVERY line, all 6 TFs, even   |
//|                      with a 500-point cached tolerance. Root cause: a       |
//|                      FIXED points decision range/tolerance cannot work      |
//|                      across 6 timeframes whose realized ranges differ by    |
//|                      an order of magnitude (M5 100-bar window ~8h vs D1     |
//|                      100-bar window ~100 days). Replaced                    |
//|                      InpDecisionRangePoints/InpConfluenceTouchTolerance-    |
//|                      Points with InpDecisionRangeRatio (0.50) /             |
//|                      InpConfluenceTouchToleranceRatio (0.08), each level    |
//|                      now scales its own zone off its own hi-lo range over   |
//|                      its lookback window (new LevelTouchState.rangeWidth    |
//|                      field), so the zone naturally fits every timeframe.    |
//| 1.007              - Terminology only: "SNR" (support/resistance) renamed   |
//|                      to "SND" (supply/demand) throughout comments, logs,    |
//|                      and chart labels (SUPPORT/RESISTANCE -> DEMAND/        |
//|                      SUPPLY), matching the convention used by EzyEA         |
//|                      V2/V3/V4 for this same swing-high/low level system.    |
//|                      No functional change.                                 |
//| 1.008              - Fixed the early correlated-pile crash seen on the      |
//|                      equity graph (sharp drop right after the first burst   |
//|                      of entries, then flat/dead for the rest of the test):  |
//|                      added an H1 ADX trend filter (blocks a fade running    |
//|                      directly against a confirmed strong trend - the same   |
//|                      fix already proven on EzyEA V2 for this identical      |
//|                      symptom) and InpMaxConcurrentPerDirection (3) to cap   |
//|                      how many same-direction positions can pile up from     |
//|                      repeated touches within the re-entry cooldown.         |
//| 1.009              - Added a 3rd confluence: rejection candle (pin bar OR    |
//|                      engulfing) required on the SAME bar that touches the    |
//|                      EMA100/SND zone, in the fade direction. Requested       |
//|                      after inconsistent day-to-day results with only 2       |
//|                      confluences. Entries moved from tick-based touch        |
//|                      detection to bar-close evaluation per timeframe         |
//|                      (CheckRejectionEntry(), called from                     |
//|                      UpdateLevelsOnNewBars() BEFORE that slot's level is     |
//|                      rebuilt, so the zone being judged is the one price      |
//|                      actually returned to, not one the new bar just          |
//|                      redefined). ProcessConfluenceTriggers() now only        |
//|                      updates the "in decision range" chart/status display    |
//|                      per tick; it no longer opens positions.                 |
//| 1.010              - M5 removed from the SND+EMA100 timeframe stack -        |
//|                      M15 and above only (M15/M30/H1/H4/D1). EZY_TF_COUNT     |
//|                      6->5, g_levels 12->10, InpLevelLookbackM5 removed.      |
//| 1.011              - M30 also removed - stack is now M15/H1/H4/D1 only       |
//|                      (EZY_TF_COUNT 5->4, g_levels 10->8). InpEmaPeriod       |
//|                      default changed 100->47, and the matched SND lookback   |
//|                      defaults (M15/H1/H4/D1) changed 100->47 to keep them    |
//|                      in sync with the EMA's own window (the fix from        |
//|                      1.006 - level and EMA must describe the same window     |
//|                      or "in decision range" never engages).                 |
//| 1.012              - Added a fixed pip preset for SL/trail (InpUseFixedStops |
//|                      = true by default): 25-pip SL, 10-pip trail, using the  |
//|                      same cent-aware pip-size split already proven on this   |
//|                      session's other gold EAs (.sc symbol = 1 pip/0.01,      |
//|                      standard XAUUSD = 1 pip/0.10). The trail distance is    |
//|                      intentionally DECOUPLED from the SL distance in this    |
//|                      mode (ManageTrailing() normally trails at the same      |
//|                      distance as the initial SL - that still holds in ATR    |
//|                      mode, InpUseFixedStops=false, but the whole point of    |
//|                      this preset is a narrower trail than the SL width).     |
//| 1.013              - Fixed "no entry traded": the .sc=0.01/standard=0.10     |
//|                      pip split was wrong for this account. Confirmed via     |
//|                      Journal (attempts=6, accepted=0, spread/concurrency     |
//|                      gates clear) that the 25-pip SL at 0.01/pip (~$0.25)     |
//|                      was tighter than this EA's own zero-stops-level          |
//|                      fallback minimum, rejecting every attempt at the        |
//|                      distance gate. Both InpXAUUSDscPipPrice and             |
//|                      InpStandardXAUUSDPipPrice now default to 0.10.          |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "1.013"
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

//======================================================================
// Inputs
//======================================================================
input group "=== EMA(period) + SND Confluence Entries: per-timeframe pairing, fade the touch ==="
// Each timeframe's SND (supply/demand) level must pair with THAT SAME
// timeframe's EMA100 to trigger - not a single EMA against a stack of
// levels. M15 SND pairs only with M15 EMA100, and so on through
// H1/H4/D1 (M5 and M30 have been removed from the stack). "Loose zone
// confluence": if the live EMA100 (same TF) value sits within
// InpDecisionRangeRatio of its matching SND level's OWN window range
// (not a fixed $ amount - a fixed points value cannot work across
// timeframes whose realized ranges differ by an order of magnitude: an
// M15 100-bar window spans ~1 day, a D1 100-bar window spans ~100 days.
// Confirmed live: even a loose 500-point fixed tolerance produced "in
// decision range=0" on
// every single timeframe throughout a full test - the fixed-point
// design cannot work at any single value). Decision range and touch
// tolerance are now both expressed as a RATIO of that level's own hi-lo
// range over its lookback window, so the zone naturally scales to each
// timeframe's own volatility. A touch of that zone is FADED in the
// LEVEL's own direction (supply -> SELL, demand -> BUY) - not by which
// side price approached from, since a wide zone makes that ambiguous
// far more often than a tight overlap would. As of the 3rd confluence
// (rejection candle, below), this is now evaluated on each timeframe's
// OWN bar close, not on every tick - a rejection pattern only exists
// once its bar has finished forming.
input bool   InpEnableConfluenceEntries          = true;
input int    InpEmaPeriod                        = 47;
input double InpDecisionRangeRatio               = 0.50;
input double InpConfluenceTouchToleranceRatio    = 0.08;
input int    InpConfluenceReentrySeconds         = 60;

input group "=== Rejection Candle Confirmation (3rd confluence) ==="
// A touch of the EMA100/SND zone is no longer enough by itself - the
// closed bar that touches the zone must ALSO show a visible rejection:
// either a pin bar (long wick opposite the fade direction, small body,
// close on the favourable side) or an engulfing candle (this bar's body
// fully engulfs the prior bar's body, in the fade direction). Requested
// after a same-TF EMA+SND-only system produced inconsistent, sometimes
// worse-than-V3 day-to-day results - this adds real price-action
// confirmation instead of firing on proximity alone. Entries are
// necessarily rarer and later (bar-close, not tick) as a result.
input bool   InpRequireRejectionCandle           = true;
input double InpRejectionMaxBodyRatio            = 0.35;
input double InpRejectionMinWickRatio            = 0.50;
input double InpRejectionMaxOppositeWickRatio    = 0.25;

input group "=== Trend Filter (H1 ADX) - blocks fades against a strong trend ==="
// The equity graph showed a sharp early crash: a burst of same-direction
// entries piled up while price was in one confluence zone, all
// correlated, and lost together when the move continued. This is the
// exact mechanism diagnosed on EzyEA V2 earlier this session and fixed
// the same way there: block a fade that runs directly against a
// confirmed strong H1 trend. Does not change which mechanism generates
// entries (SND+EMA100 confluence is still the only trigger) - it only
// blocks the ones fighting a real trend.
input bool   InpEnableTrendFilter                = true;
input int    InpAdxPeriod                        = 14;
input double InpAdxTrendThreshold                = 25.0;

input group "=== SND Levels: M15/H1/H4/Daily swing high/low, one EMA(period) per TF (M5, M30 removed) ==="
// Lookback matched to InpEmaPeriod (47 bars) on purpose. A slow-ish EMA
// average over an N-bar window paired against a level built from a much
// shorter window (the original 24/32/20/24/15/8 defaults, several times
// shorter than the EMA) almost never sits near that EMA - it's a rare
// coincidence rather than a real pairing, which is why zero trades fired
// the first time this was tried. Building each level from the SAME
// N-bar window the EMA itself averages makes "EMA near its own level" a
// normal, frequent occurrence instead of a structural near-impossibility.
// If InpEmaPeriod is changed, change these to match.
input int    InpLevelLookbackM15                 = 47;
input int    InpLevelLookbackH1                  = 47;
input int    InpLevelLookbackH4                  = 47;
input int    InpLevelLookbackD1                  = 47;

input group "=== Stops / Trail (ATR-based, M5) - used only when InpUseFixedStops is OFF ==="
input int    InpAtrPeriod                        = 14;
input double InpAtrSlMultiplier                  = 1.5;
input double InpTrailMinStepPoints               = 20.0;

input group "=== Fixed Pip Preset (overrides ATR sizing when enabled) ==="
// Trailing is intentionally a SEPARATE, narrower distance from the SL
// (10 pips vs 25) - ManageTrailing() normally trails at the same
// distance as the position's initial SL (the proven "activation floor =
// trail distance" rule), but a fixed preset with a different trail
// width needs that decoupled, so InpFixedTrailPips is read directly
// instead of being derived from the open SL distance.
input bool   InpUseFixedStops                    = true;
input double InpFixedSlPips                      = 25.0;
input double InpFixedTrailPips                   = 10.0;
// Confirmed live: the V5-borrowed assumption that a .sc (cent) suffixed
// symbol quotes 1 pip = 1 point (0.01) was wrong for this account/broker
// - it made the 25-pip SL (~$0.25) far tighter than even this EA's own
// zero-stops-level fallback minimum (0.05% of a ~$4000+ gold price is
// ~$2+), so every entry attempt was rejected at the distance gate before
// opening (confirmed via attempts=6/accepted=0 in the Journal, spread
// and concurrency gates both clear). Both symbol types now default to
// the standard gold convention, 1 pip = 10 points (0.10) = $0.10, giving
// a 25-pip SL of ~$2.50 - still tighter than the old ATR sizing (~$8-9)
// but a plausible, tradeable distance rather than a structural block.
input double InpXAUUSDscPipPrice                 = 0.10;
input double InpStandardXAUUSDPipPrice           = 0.10;

input group "=== Exit Management ==="
input int    InpMaxHoldingMinutes                = 60;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade              = 0.25;
input int    InpMaxConcurrentPositions           = 10;
// Caps how many same-direction positions can pile up from repeated
// touches of the same (or different) confluence zones within the
// re-entry cooldown window - the other half of the fix for the
// correlated-pile crash seen on the equity graph.
input int    InpMaxConcurrentPerDirection        = 3;
input double InpMaxLotsAbsolute                  = 5.0;
input double InpMaxMarginUsePct                  = 40.0;
// Confirmed live on V4: leaving this on let a risk% input become
// dishonest once the real calculated lot rounded below the broker
// minimum. Off by default.
input bool   InpAllowMinimumLotFallback          = false;
input double InpMinimumLotFallbackMaxRiskPct     = 1.0;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) ==="
input bool   InpEnableDrawdownBreaker            = true;
input double InpMaxEquityDrawdownPct             = 10.0;
input double InpDrawdownResumeFactor             = 0.5;

input group "=== Modify Backoff (TimeCurrent()-based, never GetTickCount64) ==="
input int    InpModifyBackoffBaseSeconds         = 5;
input int    InpModifyBackoffMaxSeconds          = 300;
input int    InpModifyMaxConsecutiveFail         = 6;

input group "=== Broker Minimum Distance ==="
input int    InpExecutionStopCushionPoints       = 10;
input double InpZeroStopsLevelFallbackPct        = 0.05;

input group "=== Spread Guard (auto-calibrating) ==="
input bool   InpAutoCalibrateSpreadCap           = true;
input int    InpSpreadCalibrationTicks           = 200;
input double InpSpreadCalibrationMultiplier      = 2.5;
input int    InpMaxSpreadPoints                  = 350;

input group "=== Cent-Account Handling ==="
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor           = 100.0;
input bool   InpTesterAutoModeIsStandard         = true;
input bool   InpTreatSCSuffixAsCentOnLive        = true;

input group "=== Execution ==="
input ulong  InpMagicNumber                      = 190001;
input int    InpDeviationPoints                  = 30;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds         = 60;

input group "=== Chart Drawing ==="
input bool   InpDrawReferences                    = true;
input bool   InpDrawStatusLabel                   = true;

//======================================================================
// Types
//======================================================================
struct ManagedPositionState
{
   ulong    ticket;
   int      consecutiveFailures;
   datetime cooldownUntil;
   double   peakPrice;
};

struct LevelTouchState
{
   double   price;
   int      fadeDirection;   // 1 = demand, fade BUY; -1 = supply, fade SELL
   bool     inZone;          // true when this level is currently within InpDecisionRangeRatio of its own-TF EMA100
   double   rangeWidth;      // this level's own hi-lo range over its lookback window - scales the decision/touch zone
   datetime cooldownUntil;
   string   tfLabel;
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

int g_handleAtrM5 = INVALID_HANDLE;
int g_handleAdxH1 = INVALID_HANDLE;

datetime g_lastAdxH1BarTime = 0;
int      g_trendDirection   = 0;   // 1 up, -1 down, 0 no strong trend
double   g_lastAdxValue     = 0.0;

// 4 timeframes (M5, M30 removed - M15/H1/H4/D1 only), one EMA100 handle
// each, fixed slot order matched 1:1 with g_levels' slot order
// (slot i -> g_levels[i*2]/[i*2+1]).
#define EZY_TF_COUNT 4
int              g_handleEma[EZY_TF_COUNT];
double           g_emaValue[EZY_TF_COUNT];
ENUM_TIMEFRAMES  g_emaTf[EZY_TF_COUNT]    = {PERIOD_M15,PERIOD_H1,PERIOD_H4,PERIOD_D1};
string           g_emaTfLabel[EZY_TF_COUNT] = {"M15","H1","H4","D1"};

double g_accountUnitDivisor = 1.0;

double g_spreadCalSamples[];
int    g_spreadCalCount        = 0;
double g_spreadCalEffectiveCap = -1.0;

ManagedPositionState g_managed[];

datetime g_lastStatusLogTime = 0;

int g_gateAttempts           = 0;
int g_gateAccepted           = 0;
int g_gateRejected           = 0;
int g_gateSpreadRejects      = 0;
int g_gateConcurrencyRejects = 0;
int g_gateDistanceRejects    = 0;
int g_gateSizingRejects      = 0;
int g_gateDrawdownRejects    = 0;
int g_gateTrendRejects       = 0;

// 4 timeframes (M15/H1/H4/D1) x 2 levels (swing high=supply,
// swing low=demand) each. Slot i's pair lives at g_levels[i*2]/[i*2+1]
// and is checked against g_emaValue[i] - the SAME timeframe's EMA100.
LevelTouchState g_levels[8];

datetime g_lastM15LevelBarTime = 0;
datetime g_lastH1LevelBarTime  = 0;
datetime g_lastH4LevelBarTime  = 0;
datetime g_lastD1LevelBarTime  = 0;

double g_peakEquity    = 0.0;
bool   g_tradingHalted = false;

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

int    CountOpenPositions();
int    CountOpenPositionsByDirection(int direction);

int    CopyBufferSeries(int handle,int bufferIndex,int count,double &out[]);

void   CloseAllPositions(string reason);
void   UpdateDrawdownBreaker();

void   UpdateTrendFilterOnNewH1Bar();
bool   TrendFilterAllows(int direction);

void   TryOpenPosition(int direction,string tag,double slDistance);

int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
void   ManageTrailing();
void   EnforceMaxHoldingTime();

void   RebuildLevelForTimeframe(int slotIndex,ENUM_TIMEFRAMES tf,int lookback,string tfLabel);
void   UpdateLevelsOnNewBars();
void   UpdateEmaValues();
bool   IsRejectionPinBar(double o,double h,double l,double c,int direction);
bool   IsEngulfingPattern(double prevOpen,double prevClose,double o,double c,int direction);
bool   IsRejectionCandle(double prevOpen,double prevClose,double o,double h,double l,double c,int direction);
void   CheckRejectionEntry(int slotIndex,ENUM_TIMEFRAMES tf);
void   TryConfluenceEntry(int direction,double levelPrice);
void   ProcessConfluenceTriggers();

int    CountActiveLevels();
void   DrawReferences();
void   DrawStatusLabel();
void   RemoveAllDrawings();

void   WriteFinalReport();
void   PeriodicStatusLog();

//======================================================================
// Event handlers
//======================================================================
int OnInit()
{
   if(!IsGold())
   {
      Log("EzyEA V1 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   g_handleAtrM5 = iATR(_Symbol,PERIOD_M5,InpAtrPeriod);
   if(g_handleAtrM5==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed (ATR).");
      return INIT_FAILED;
   }

   for(int i=0;i<EZY_TF_COUNT;i++)
   {
      g_handleEma[i]=iMA(_Symbol,g_emaTf[i],InpEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
      g_emaValue[i]=0.0;
      if(g_handleEma[i]==INVALID_HANDLE)
      {
         Log("Indicator handle creation failed (EMA"+IntegerToString(InpEmaPeriod)+" "+g_emaTfLabel[i]+").");
         return INIT_FAILED;
      }
   }

   g_handleAdxH1 = iADX(_Symbol,PERIOD_H1,InpAdxPeriod);
   if(g_handleAdxH1==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed (ADX H1).");
      return INIT_FAILED;
   }
   g_lastAdxH1BarTime=0;
   g_trendDirection=0;
   g_lastAdxValue=0.0;

   g_accountUnitDivisor = ResolveAccountUnitDivisor();

   int capacity = SpreadCalibrationTicksEffective();
   ArrayResize(g_spreadCalSamples,capacity);
   g_spreadCalCount        = 0;
   g_spreadCalEffectiveCap = -1.0;

   g_lastStatusLogTime = 0;

   ArrayResize(g_managed,0);

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      g_levels[i].price=0.0;
      g_levels[i].fadeDirection=0;
      g_levels[i].inZone=false;
      g_levels[i].rangeWidth=0.0;
      g_levels[i].cooldownUntil=0;
      g_levels[i].tfLabel="";
   }
   g_lastM15LevelBarTime = 0;
   g_lastH1LevelBarTime  = 0;
   g_lastH4LevelBarTime  = 0;
   g_lastD1LevelBarTime  = 0;

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted=false;

   Log("EzyEA V1 (EMA"+IntegerToString(InpEmaPeriod)+" x"+IntegerToString(EZY_TF_COUNT)+"TF + SND confluence) initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions)+
       " (per-direction="+IntegerToString(InpMaxConcurrentPerDirection)+")"+
       " | decision range ratio="+DoubleToString(InpDecisionRangeRatio,2)+
       " | trend filter="+(InpEnableTrendFilter?"ON (ADX>="+DoubleToString(InpAdxTrendThreshold,0)+")":"OFF")+
       " | stops="+(InpUseFixedStops
                    ?"FIXED "+DoubleToString(InpFixedSlPips,1)+"pip SL/"+DoubleToString(InpFixedTrailPips,1)+"pip trail (pipSize="+DoubleToString(StrategyPipSize(),_Digits)+")"
                    :"ATR x"+DoubleToString(InpAtrSlMultiplier,2))+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF"));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAtrM5!=INVALID_HANDLE) IndicatorRelease(g_handleAtrM5);
   if(g_handleAdxH1!=INVALID_HANDLE) IndicatorRelease(g_handleAdxH1);
   for(int i=0;i<EZY_TF_COUNT;i++)
      if(g_handleEma[i]!=INVALID_HANDLE) IndicatorRelease(g_handleEma[i]);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();
   UpdateTrendFilterOnNewH1Bar();

   if(InpEnableConfluenceEntries)
   {
      UpdateLevelsOnNewBars();
      ProcessConfluenceTriggers();
      DrawReferences();
   }

   ManageTrailing();
   EnforceMaxHoldingTime();
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
   if(IsCentSuffixSymbol())
      return MathMax(InpXAUUSDscPipPrice,_Point);
   return MathMax(InpStandardXAUUSDPipPrice,_Point);
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
   Print("EzyEA V1 | ",msg);
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
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
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
      if(minVolRiskPct>InpMinimumLotFallbackMaxRiskPct) return 0.0;

      lots=minVol;
   }

   lots=MathMin(lots,InpMaxLotsAbsolute);

   double marginRequired=0.0;
   ENUM_ORDER_TYPE type=(direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(OrderCalcMargin(type,_Symbol,lots,entry,marginRequired))
   {
      double usedMargin=AccountInfoDouble(ACCOUNT_MARGIN);
      double projectedMarginPct=(equity>0.0)
                                ?((usedMargin+marginRequired)/equity)*100.0
                                :DBL_MAX;

      if(projectedMarginPct>InpMaxMarginUsePct)
      {
         double remainingBudget=MathMax(0.0,InpMaxMarginUsePct/100.0*equity-usedMargin);
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
   return referencePrice*MathMax(0.0,InpZeroStopsLevelFallbackPct)/100.0;
}

double MinimumStopDistance(double referencePrice)
{
   long stopsLevel =SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double base=MathMax(_Point,
               ((double)MathMax(stopsLevel,freezeLevel)+InpExecutionStopCushionPoints)*_Point);

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
// Position accounting
//======================================================================
int CountOpenPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      count++;
   }
   return count;
}

int CountOpenPositionsByDirection(int direction)
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      int posDirection=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      if(posDirection==direction) count++;
   }
   return count;
}

//======================================================================
// Indicator buffer helper (as-series: out[0]=forming/live bar, out[1]=
// last closed bar, out[2]=the bar before it)
//======================================================================
int CopyBufferSeries(int handle,int bufferIndex,int count,double &out[])
{
   ArraySetAsSeries(out,true);
   int copied=CopyBuffer(handle,bufferIndex,0,count,out);
   if(copied<=0) return 0;
   return copied;
}

//======================================================================
// Emergency stop: closes every position this EA opened. Used by the
// overall drawdown breaker.
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
}

//======================================================================
// Overall drawdown circuit breaker: peak equity seen since attach.
// Closes everything and halts new entries the moment it trips; resumes
// with hysteresis.
//======================================================================
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
          " | drawdown="+DoubleToString(drawdownPct,2)+"%"+
          " | peakEquity="+DoubleToString(g_peakEquity,2)+
          " | equity="+DoubleToString(equity,2));
      CloseAllPositions("drawdown breaker");
   }
   else if(g_tradingHalted && drawdownPct<=resumeThreshold)
   {
      g_tradingHalted=false;
      Log("DRAWDOWN BREAKER RESET - new entries resumed"+
          " | drawdown="+DoubleToString(drawdownPct,2)+"%"+
          " | resumeThreshold="+DoubleToString(resumeThreshold,2)+"%");
   }
}

//======================================================================
// H1 ADX trend filter: does not change which mechanism generates
// entries (SND+EMA100 confluence is still the only trigger) - it only
// blocks a fade that runs directly against a confirmed strong trend.
// Same fix proven on EzyEA V2 for the identical correlated-pile symptom.
//======================================================================
void UpdateTrendFilterOnNewH1Bar()
{
   if(!InpEnableTrendFilter) return;

   datetime h1=iTime(_Symbol,PERIOD_H1,0);
   if(h1==0 || h1==g_lastAdxH1BarTime) return;
   g_lastAdxH1BarTime=h1;

   double adxBuf[],plusBuf[],minusBuf[];
   if(CopyBufferSeries(g_handleAdxH1,0,3,adxBuf)<3)   return;
   if(CopyBufferSeries(g_handleAdxH1,1,3,plusBuf)<3)  return;
   if(CopyBufferSeries(g_handleAdxH1,2,3,minusBuf)<3) return;

   double adx    =adxBuf[1];
   double plusDI =plusBuf[1];
   double minusDI=minusBuf[1];

   g_lastAdxValue=adx;

   if(adx>=InpAdxTrendThreshold)
      g_trendDirection=(plusDI>minusDI)?1:((minusDI>plusDI)?-1:0);
   else
      g_trendDirection=0;
}

bool TrendFilterAllows(int direction)
{
   if(!InpEnableTrendFilter) return true;
   if(g_trendDirection==0) return true;
   return direction==g_trendDirection;
}

//======================================================================
// Entry execution
//======================================================================
void TryOpenPosition(int direction,string tag,double slDistance)
{
   g_gateAttempts++;

   if(g_tradingHalted)
   {
      g_gateDrawdownRejects++;
      return;
   }

   if(CountOpenPositions()>=InpMaxConcurrentPositions)
   {
      g_gateConcurrencyRejects++;
      return;
   }

   if(CountOpenPositionsByDirection(direction)>=InpMaxConcurrentPerDirection)
   {
      g_gateConcurrencyRejects++;
      return;
   }

   if(!SpreadAllowed())
   {
      g_gateSpreadRejects++;
      return;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double entry=(direction==1)?tick.ask:tick.bid;
   double sl=RoundPrice((direction==1)?entry-slDistance:entry+slDistance);

   double minDist=MinimumStopDistance(entry);
   if(MathAbs(entry-sl)<minDist)
   {
      g_gateDistanceRejects++;
      Log("ENTRY REJECTED "+tag+" reason=SL_DISTANCE_TOO_TIGHT"+
          " slDistance="+PriceText(slDistance)+
          " minDist="+PriceText(minDist));
      return;
   }

   double lots=ComputeLotsForRisk(direction,entry,sl);
   if(lots<=0.0)
   {
      g_gateSizingRejects++;
      Log("ENTRY REJECTED "+tag+" reason=ZERO_LOTS"+
          " riskEquity="+DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),2)+
          " entry="+PriceText(entry)+" sl="+PriceText(sl)+
          " perLotLoss="+DoubleToString(OneLotLoss(direction,entry,sl),2));
      return;
   }

   bool sent=(direction==1)
             ? trade.Buy(lots,_Symbol,0.0,sl,0.0,tag)
             : trade.Sell(lots,_Symbol,0.0,sl,0.0,tag);

   uint retcode=trade.ResultRetcode();

   if(sent && TradeRetcodeAccepted(retcode))
   {
      g_gateAccepted++;
      Log("ENTRY "+tag+" dir="+IntegerToString(direction)+
          " lots="+DoubleToString(lots,2)+
          " entry="+PriceText(entry)+
          " sl="+PriceText(sl));
   }
   else
   {
      g_gateRejected++;
      Log("ENTRY REJECTED "+tag+" retcode="+IntegerToString(retcode)+
          " desc="+trade.ResultRetcodeDescription());
   }
}

//======================================================================
// EMA100 + SND loose zone confluence, paired per timeframe. SND levels
// only rebuild on their OWN timeframe's new bar close, never intra-bar.
// EMA100 read LIVE (shift=0) - an EMA is a smoothed lagging price, not a
// bar pattern, so reading it live carries no repaint risk.
//======================================================================
void RebuildLevelForTimeframe(int slotIndex,ENUM_TIMEFRAMES tf,int lookback,string tfLabel)
{
   double hi=-DBL_MAX, lo=DBL_MAX;

   for(int shift=1;shift<=lookback;shift++)
   {
      double h=iHigh(_Symbol,tf,shift);
      double l=iLow(_Symbol,tf,shift);
      if(h<=0.0 || l<=0.0) continue;
      hi=MathMax(hi,h);
      lo=MathMin(lo,l);
   }

   if(hi<=-DBL_MAX || lo>=DBL_MAX) return;

   double width=hi-lo;

   int supplyIdx=slotIndex*2;
   int demandIdx=slotIndex*2+1;

   // cooldownUntil deliberately NOT reset here - CheckRejectionEntry()
   // runs immediately before this call (same new-bar event) and may have
   // just set it; resetting it here would silently defeat the re-entry
   // cooldown on every single bar close.
   g_levels[supplyIdx].price=RoundPrice(hi);
   g_levels[supplyIdx].fadeDirection=-1;
   g_levels[supplyIdx].inZone=false;
   g_levels[supplyIdx].rangeWidth=width;
   g_levels[supplyIdx].tfLabel=tfLabel;

   g_levels[demandIdx].price=RoundPrice(lo);
   g_levels[demandIdx].fadeDirection=1;
   g_levels[demandIdx].inZone=false;
   g_levels[demandIdx].rangeWidth=width;
   g_levels[demandIdx].tfLabel=tfLabel;
}

// Entry evaluation happens BEFORE the level is rebuilt for this new bar -
// using the level's PRIOR state (established from earlier bars) against
// the bar that JUST closed. This checks "did price return to an
// already-existing zone and reject it", not "does the zone trivially
// match wherever price just went" (which is what checking AFTER rebuild
// would risk, since a new extreme bar can redefine the level to sit
// exactly where price now is).
void UpdateLevelsOnNewBars()
{
   datetime m15=iTime(_Symbol,PERIOD_M15,0);
   if(m15!=0 && m15!=g_lastM15LevelBarTime)
   {
      g_lastM15LevelBarTime=m15;
      CheckRejectionEntry(0,PERIOD_M15);
      RebuildLevelForTimeframe(0,PERIOD_M15,InpLevelLookbackM15,"M15");
   }

   datetime h1=iTime(_Symbol,PERIOD_H1,0);
   if(h1!=0 && h1!=g_lastH1LevelBarTime)
   {
      g_lastH1LevelBarTime=h1;
      CheckRejectionEntry(1,PERIOD_H1);
      RebuildLevelForTimeframe(1,PERIOD_H1,InpLevelLookbackH1,"H1");
   }

   datetime h4=iTime(_Symbol,PERIOD_H4,0);
   if(h4!=0 && h4!=g_lastH4LevelBarTime)
   {
      g_lastH4LevelBarTime=h4;
      CheckRejectionEntry(2,PERIOD_H4);
      RebuildLevelForTimeframe(2,PERIOD_H4,InpLevelLookbackH4,"H4");
   }

   datetime d1=iTime(_Symbol,PERIOD_D1,0);
   if(d1!=0 && d1!=g_lastD1LevelBarTime)
   {
      g_lastD1LevelBarTime=d1;
      CheckRejectionEntry(3,PERIOD_D1);
      RebuildLevelForTimeframe(3,PERIOD_D1,InpLevelLookbackD1,"D1");
   }
}

// Live EMA100 read (shift=0) for each of the 6 timeframes - used for the
// chart lines and the per-tick "in decision range" status display only.
// Entry decisions use the bar-close EMA value read fresh inside
// CheckRejectionEntry(), not this live value (an EMA is a smoothed
// lagging price, not a bar pattern, so reading it live carries no
// repaint risk either way - this split is about consistency between the
// zone and the candle being judged, not about repaint safety).
void UpdateEmaValues()
{
   for(int i=0;i<EZY_TF_COUNT;i++)
   {
      double buf[];
      if(CopyBufferSeries(g_handleEma[i],0,1,buf)<1)
      {
         g_emaValue[i]=0.0;
         continue;
      }
      g_emaValue[i]=buf[0];
   }
}

// Pin bar: small body, a long wick opposite the fade direction (the
// side being rejected), and a small wick on the favourable side.
// direction=1 (BUY/demand): long LOWER wick, close in the upper part.
// direction=-1 (SELL/supply): long UPPER wick, close in the lower part.
bool IsRejectionPinBar(double o,double h,double l,double c,int direction)
{
   double range=h-l;
   if(range<=0.0) return false;

   double body=MathAbs(c-o);
   if(body>range*InpRejectionMaxBodyRatio) return false;

   double upperWick=h-MathMax(o,c);
   double lowerWick=MathMin(o,c)-l;

   if(direction==1)
      return lowerWick>=range*InpRejectionMinWickRatio &&
             upperWick<=range*InpRejectionMaxOppositeWickRatio;

   return upperWick>=range*InpRejectionMinWickRatio &&
          lowerWick<=range*InpRejectionMaxOppositeWickRatio;
}

// Engulfing: this bar's body fully engulfs the PRIOR bar's body, in the
// fade direction. direction=1: prior bar bearish, this bar bullish and
// engulfing. direction=-1: prior bar bullish, this bar bearish and
// engulfing.
bool IsEngulfingPattern(double prevOpen,double prevClose,double o,double c,int direction)
{
   if(direction==1)
   {
      bool priorBearish=(prevClose<prevOpen);
      bool thisBullish =(c>o);
      if(!priorBearish || !thisBullish) return false;
      return (o<=prevClose && c>=prevOpen);
   }

   bool priorBullish=(prevClose>prevOpen);
   bool thisBearish =(c<o);
   if(!priorBullish || !thisBearish) return false;
   return (o>=prevClose && c<=prevOpen);
}

bool IsRejectionCandle(double prevOpen,double prevClose,double o,double h,double l,double c,int direction)
{
   return IsRejectionPinBar(o,h,l,c,direction) ||
          IsEngulfingPattern(prevOpen,prevClose,o,c,direction);
}

// Evaluates BOTH levels of this timeframe slot (supply and demand)
// against the bar that just closed, using the level's PRE-rebuild state.
// Fires only when: the level is in decision range of its own-TF EMA100
// (bar-close value, not live), the closed bar's range touched the zone,
// and (if enabled) that same bar is a rejection candle in the level's
// fade direction.
void CheckRejectionEntry(int slotIndex,ENUM_TIMEFRAMES tf)
{
   double emaBuf[];
   if(CopyBufferSeries(g_handleEma[slotIndex],0,2,emaBuf)<2) return;
   double emaValue=emaBuf[1];
   if(emaValue<=0.0) return;

   double o=iOpen(_Symbol,tf,1);
   double h=iHigh(_Symbol,tf,1);
   double l=iLow(_Symbol,tf,1);
   double c=iClose(_Symbol,tf,1);
   double prevO=iOpen(_Symbol,tf,2);
   double prevC=iClose(_Symbol,tf,2);
   if(h<=0.0 || l<=0.0 || h<l) return;

   int supplyIdx=slotIndex*2;
   int demandIdx=slotIndex*2+1;

   for(int k=0;k<2;k++)
   {
      int i=(k==0)?supplyIdx:demandIdx;
      if(g_levels[i].price<=0.0 || g_levels[i].rangeWidth<=0.0) continue;
      if(TimeCurrent()<g_levels[i].cooldownUntil) continue;

      double decisionRange=InpDecisionRangeRatio*g_levels[i].rangeWidth;
      double spread=MathAbs(emaValue-g_levels[i].price);
      if(spread>decisionRange) continue;

      double touchTolerance=InpConfluenceTouchToleranceRatio*g_levels[i].rangeWidth;
      double zoneLo=MathMin(emaValue,g_levels[i].price)-touchTolerance;
      double zoneHi=MathMax(emaValue,g_levels[i].price)+touchTolerance;

      bool touching=(h>=zoneLo && l<=zoneHi);
      if(!touching) continue;

      int direction=g_levels[i].fadeDirection;

      if(InpRequireRejectionCandle && !IsRejectionCandle(prevO,prevC,o,h,l,c,direction))
         continue;

      TryConfluenceEntry(direction,g_levels[i].price);
      g_levels[i].cooldownUntil=TimeCurrent()+MathMax(0,InpConfluenceReentrySeconds);
   }
}

void TryConfluenceEntry(int direction,double levelPrice)
{
   if(!TrendFilterAllows(direction))
   {
      g_gateTrendRejects++;
      return;
   }

   double slDistance;
   if(InpUseFixedStops)
   {
      slDistance=InpFixedSlPips*StrategyPipSize();
   }
   else
   {
      double atrBuf[];
      if(CopyBufferSeries(g_handleAtrM5,0,3,atrBuf)<3) return;
      slDistance=InpAtrSlMultiplier*atrBuf[1];
   }
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V1CONF",slDistance);
}

// Entry decisions now happen in CheckRejectionEntry() on each timeframe's
// own bar close (called from UpdateLevelsOnNewBars()). This function only
// updates the live "in decision range" status per tick, for the chart
// level coloring and the status label/log - it does not open positions.
void ProcessConfluenceTriggers()
{
   UpdateEmaValues();

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      if(g_levels[i].price<=0.0 || g_levels[i].rangeWidth<=0.0)
      {
         g_levels[i].inZone=false;
         continue;
      }

      // Each level pairs ONLY with its own timeframe's EMA100 - slot
      // i/2 in g_emaValue[], matching RebuildLevelForTimeframe()'s
      // slotIndex*2/slotIndex*2+1 layout.
      double emaValue=g_emaValue[i/2];
      if(emaValue<=0.0)
      {
         g_levels[i].inZone=false;
         continue;
      }

      double decisionRange=InpDecisionRangeRatio*g_levels[i].rangeWidth;
      double spread=MathAbs(emaValue-g_levels[i].price);
      g_levels[i].inZone=(spread<=decisionRange);
   }
}

//======================================================================
// Per-position management state (backoff + peak tracking)
//======================================================================
int EnsureManagedSlot(ulong ticket)
{
   int n=ArraySize(g_managed);
   for(int i=0;i<n;i++)
      if(g_managed[i].ticket==ticket) return i;

   if(!PositionSelectByTicket(ticket)) return -1;

   int idx=n;
   ArrayResize(g_managed,n+1);
   g_managed[idx].ticket=ticket;
   g_managed[idx].consecutiveFailures=0;
   g_managed[idx].cooldownUntil=0;
   g_managed[idx].peakPrice=PositionGetDouble(POSITION_PRICE_OPEN);
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

void ModifyPositionSafely(ulong ticket,double sl,double tp)
{
   int slot=EnsureManagedSlot(ticket);
   if(slot<0) return;

   if(g_managed[slot].cooldownUntil>0 && TimeCurrent()<g_managed[slot].cooldownUntil)
      return;

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
   int steps=(int)MathMin((double)g_managed[slot].consecutiveFailures,(double)InpModifyMaxConsecutiveFail);
   int backoffSeconds=(int)MathMin((double)InpModifyBackoffMaxSeconds,
                       (double)InpModifyBackoffBaseSeconds*MathPow(2.0,steps-1));
   g_managed[slot].cooldownUntil=TimeCurrent()+backoffSeconds;

   if(!TemporaryTradeRetcode(retcode))
      Log("MODIFY REJECTED ticket="+IntegerToString((int)ticket)+
          " retcode="+IntegerToString(retcode)+
          " backoff="+IntegerToString(backoffSeconds)+"s");
}

//======================================================================
// Exit 1: trail-only, no TP. Activates once favourable excursion has run
// the full SL distance. Every candidate stop must land on the CORRECT
// SIDE of current price, not just far enough from it.
//======================================================================
void ManageTrailing()
{
   PruneManagedSlots();

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      int direction=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      double openPrice   =PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl   =PositionGetDouble(POSITION_SL);
      double currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      double slDistance=MathAbs(openPrice-currentSl);
      if(slDistance<=0.0) continue;

      // Fixed-preset mode trails at a DIFFERENT (narrower) distance than
      // the initial SL - e.g. 25-pip SL, 10-pip trail - so the trail
      // distance is decoupled from the position's own SL distance here.
      // ATR mode keeps the original "activation floor = trail distance"
      // rule (trails at the same distance the SL was placed at).
      double trailDistance=(InpUseFixedStops && InpFixedTrailPips>0.0)
                           ?InpFixedTrailPips*StrategyPipSize()
                           :slDistance;

      int slot=EnsureManagedSlot(ticket);
      if(slot<0) continue;

      if(direction==1)
         g_managed[slot].peakPrice=MathMax(g_managed[slot].peakPrice,currentPrice);
      else
         g_managed[slot].peakPrice=MathMin(g_managed[slot].peakPrice,currentPrice);

      double favorable=(direction==1)
                       ?(g_managed[slot].peakPrice-openPrice)
                       :(openPrice-g_managed[slot].peakPrice);

      if(favorable<trailDistance) continue;

      double candidateSl=RoundPrice((direction==1)
                         ?g_managed[slot].peakPrice-trailDistance
                         :g_managed[slot].peakPrice+trailDistance);

      bool improves=(direction==1)?(candidateSl>currentSl):(candidateSl<currentSl);
      if(!improves) continue;

      double minStep=InpTrailMinStepPoints*_Point;
      if(MathAbs(candidateSl-currentSl)<minStep) continue;

      bool validSide=(direction==1)?(candidateSl<currentPrice):(candidateSl>currentPrice);
      if(!validSide) continue;

      double minDist=MinimumStopDistance(currentPrice);
      if(MathAbs(currentPrice-candidateSl)<minDist) continue;

      ModifyPositionSafely(ticket,candidateSl,PositionGetDouble(POSITION_TP));
   }
}

//======================================================================
// Exit 2: hard force-close once a position has been open
// InpMaxHoldingMinutes, regardless of P&L.
//======================================================================
void EnforceMaxHoldingTime()
{
   if(InpMaxHoldingMinutes<=0) return;

   long cutoffSeconds=(long)InpMaxHoldingMinutes*60;

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
      long heldSeconds=(long)(TimeCurrent()-openTime);
      if(heldSeconds<cutoffSeconds) continue;

      bool ok=trade.PositionClose(ticket);
      uint retcode=trade.ResultRetcode();

      if(ok && TradeRetcodeAccepted(retcode))
         Log("MAX HOLDING TIME EXIT ticket="+IntegerToString((int)ticket)+
             " heldMinutes="+DoubleToString(heldSeconds/60.0,1));
      else
         Log("MAX HOLDING TIME EXIT FAILED ticket="+IntegerToString((int)ticket)+
             " retcode="+IntegerToString(retcode)+
             " desc="+trade.ResultRetcodeDescription());
   }
}

//======================================================================
// Chart drawing (EMA(period) x4TF + SND levels + status label)
//======================================================================
int CountActiveLevels()
{
   int n=0;
   for(int i=0;i<ArraySize(g_levels);i++)
      if(g_levels[i].price>0.0) n++;
   return n;
}

int CountLevelsInDecisionRange()
{
   int n=0;
   for(int i=0;i<ArraySize(g_levels);i++)
      if(g_levels[i].inZone) n++;
   return n;
}

void DrawReferences()
{
   if(!InpDrawReferences) return;

   // One short EMA100 segment per timeframe (own TF bar times as
   // x-coordinates - valid even on an M5 chart, since object
   // coordinates are just absolute datetimes).
   color emaColors[EZY_TF_COUNT]={clrYellow,clrDeepSkyBlue,clrDodgerBlue,clrMediumPurple};
   for(int tfi=0;tfi<EZY_TF_COUNT;tfi++)
   {
      double buf[];
      if(CopyBufferSeries(g_handleEma[tfi],0,2,buf)<2) continue;

      string name="V1_EMA_"+g_emaTfLabel[tfi];
      datetime t1=iTime(_Symbol,g_emaTf[tfi],1);
      datetime t2=iTime(_Symbol,g_emaTf[tfi],0);
      if(t1==0 || t2==0) continue;

      if(ObjectFind(0,name)<0)
         ObjectCreate(0,name,OBJ_TREND,0,t1,buf[1],t2,buf[0]);
      else
      {
         ObjectMove(0,name,0,t1,buf[1]);
         ObjectMove(0,name,1,t2,buf[0]);
      }
      ObjectSetInteger(0,name,OBJPROP_COLOR,emaColors[tfi]);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_RAY,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_TEXT,g_emaTfLabel[tfi]+" EMA"+IntegerToString(InpEmaPeriod));
   }

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      string name="V1_LVL_"+IntegerToString(i);
      if(g_levels[i].price<=0.0)
      {
         ObjectDelete(0,name);
         continue;
      }

      color clr=g_levels[i].inZone
               ?(g_levels[i].fadeDirection==1?clrLime:clrRed)
               :clrGray;

      if(ObjectFind(0,name)<0)
         ObjectCreate(0,name,OBJ_HLINE,0,0,g_levels[i].price);

      ObjectSetDouble(0,name,OBJPROP_PRICE,g_levels[i].price);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_STYLE,g_levels[i].inZone?STYLE_SOLID:STYLE_DOT);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,g_levels[i].inZone?2:1);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_TEXT,
                      g_levels[i].tfLabel+" "+
                      (g_levels[i].fadeDirection==1?"DEMAND":"SUPPLY")+
                      (g_levels[i].inZone?" - IN DECISION RANGE":""));
   }

   if(InpDrawStatusLabel) DrawStatusLabel();
}

void DrawStatusLabel()
{
   string name="V1_StatusLabel";
   string text=StringFormat("EzyEA V1 | EMA%d + SND | in-range=%d/%d | Open=%d/%d | %s",
                InpEmaPeriod,
                CountLevelsInDecisionRange(),CountActiveLevels(),
                CountOpenPositions(),InpMaxConcurrentPositions,
                g_tradingHalted?"HALTED (drawdown breaker)":"ACTIVE");

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
   ObjectSetInteger(0,name,OBJPROP_COLOR,g_tradingHalted?clrOrange:clrWhite);
}

void RemoveAllDrawings()
{
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,"V1_")==0)
         ObjectDelete(0,name);
   }
}

//======================================================================
// Reporting
//======================================================================
void PeriodicStatusLog()
{
   if(InpStatusLogIntervalSeconds<=0) return;

   datetime now=TimeCurrent();
   if(g_lastStatusLogTime>0 && now-g_lastStatusLogTime<InpStatusLogIntervalSeconds) return;
   g_lastStatusLogTime=now;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct =(g_peakEquity>0.0)?(g_peakEquity-equity)/g_peakEquity*100.0:0.0;

   string trendText=(g_trendDirection==1?"UP":(g_trendDirection==-1?"DOWN":"NONE"));

   Log("V1 LIVE PARITY STATUS"+
       " | SND active="+IntegerToString(CountActiveLevels())+"/"+IntegerToString(ArraySize(g_levels))+
       " | in decision range="+IntegerToString(CountLevelsInDecisionRange())+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
       " | adx="+DoubleToString(g_lastAdxValue,1)+" trend="+trendText+
       " | drawdown="+DoubleToString(ddPct,2)+"%"+(g_tradingHalted?" (HALTED)":"")+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY));

   Log("V1 DEPLOYMENT GATE BREAKDOWN"+
       " | attempts="+IntegerToString(g_gateAttempts)+
       " | accepted="+IntegerToString(g_gateAccepted)+
       " | rejected="+IntegerToString(g_gateRejected)+
       " | spreadRejects="+IntegerToString(g_gateSpreadRejects)+
       " | concurrencyRejects="+IntegerToString(g_gateConcurrencyRejects)+
       " | distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " | sizingRejects="+IntegerToString(g_gateSizingRejects)+
       " | drawdownRejects="+IntegerToString(g_gateDrawdownRejects)+
       " | trendRejects="+IntegerToString(g_gateTrendRejects));
}

// Summarizes this EA's own deal history (by symbol+magic) at shutdown -
// covers both a Strategy Tester run ending and the EA being removed live.
void WriteFinalReport()
{
   if(!HistorySelect(0,TimeCurrent())) return;

   int total=HistoryDealsTotal();
   int trades=0;
   double lotsTraded=0.0;
   double netPnl=0.0;

   for(int i=0;i<total;i++)
   {
      ulong dealTicket=HistoryDealGetTicket(i);
      if(dealTicket==0) continue;
      if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=InpMagicNumber) continue;

      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY)==DEAL_ENTRY_IN)
      {
         trades++;
         lotsTraded+=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      }

      netPnl+=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+
              HistoryDealGetDouble(dealTicket,DEAL_SWAP)+
              HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
   }

   Log("V1 FINAL REPORT"+
       " | trades="+IntegerToString(trades)+
       " | total lots traded="+DoubleToString(lotsTraded,2)+
       " | net P/L="+DoubleToString(netPnl,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
}
//+------------------------------------------------------------------+
