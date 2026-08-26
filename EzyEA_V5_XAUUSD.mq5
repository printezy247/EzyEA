//+------------------------------------------------------------------+
//|                                             EzyEA_V5_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V5 - ground-up build, a genuinely new strategy shape rather   |
//| than a refinement of the V1-V4 SND/EMA touch-fade lineage, though     |
//| it now REUSES that lineage's level/EMA touch engines as additional     |
//| entry sources (see point 6 below). Target: high-frequency XAUUSD        |
//| scalping (with individual trades allowed to extend into a swing when     |
//| they're winning), designed for an ultra-low-latency VPS (~2.5ms or        |
//| below to the broker).                                                       |
//|                                                                                |
//| DESIGN CHOICES (resolved with the user before writing any code, each          |
//| a real fork with financial-safety implications):                               |
//| 1. LAYERING MODE = ANTI-MARTINGALE PYRAMID, not classic martingale.             |
//|    Additional layers are only added when price has already moved                |
//|    FAVOURABLY from the basket's anchor entry (scaling into a winner),             |
//|    each new layer SMALLER than the last (InpPyramidSizeRatio). This                |
//|    deliberately does NOT average down into a loser - true/capped                    |
//|    martingale was offered and explicitly declined because averaging                  |
//|    down at high frequency on a wide-spread broker has genuine account-                 |
//|    blowup tail risk on a real trending day. "Cover losses if any" is                    |
//|    handled by the basket-level equity stop, not by an averaging-down                     |
//|    mechanism.                                                                                |
//| 2. ENTRY = ZERO-CONFLUENCE TOUCH, no bar-close wait, no confirmation, no                      |
//|    "how many signals agree" requirement anywhere. v1.000 of this file                          |
//|    required a bar to close outside a Bollinger Band and the NEXT bar to                         |
//|    close back inside before firing; live/tester feedback showed this                              |
//|    fires almost never (a bar-close snapback is rare specifically on                                 |
//|    trending days). v2.000 switched to an immediate touch of the live                                  |
//|    Bollinger Band, edge-triggered with state-based re-arm (must fully                                   |
//|    leave the zone before that side can fire again) - the same "touch =                                    |
//|    immediate trade" philosophy already used throughout this codebase.                                        |
//| 3. NO VOLATILITY GATE (v2.100, was optional-and-off-by-default in                                              |
//|    v2.000, was a hard requirement in v1.000): per explicit follow-up                                             |
//|    request ("remove all filter and let the trades be taken at any                                                 |
//|    levels set"), the ATR-vs-baseline gate is removed entirely, not just                                             |
//|    defaulted off - there is no volatility precondition anywhere in the                                                |
//|    entry path now. ATR is still read and used for SIZING (structural SL,                                                |
//|    pyramid step, trail distances) - that is a sizing input, not an entry                                                  |
//|    filter, and stays.                                                                                                        |
//| 4. BASKET-LEVEL HARD STOP = fixed % of equity (InpBasketMaxLossEquityPct),                                                     |
//|    not ATR-scaled - predictable worst-case drawdown per basket, by                                                                |
//|    explicit choice. This is a RISK BACKSTOP, not an entry filter - it is                                                            |
//|    unaffected by point 3.                                                                                                              |
//| 5. CONCURRENT BASKETS, ONE PER DIRECTION: a long basket and a short basket                                                                |
//|    can be open at the same time, so a winning basket riding its trailing                                                                    |
//|    stop into a genuine swing move doesn't block fresh entries on either                                                                        |
//|    side - directly serves "scalping to swing mode" plus a high daily                                                                             |
//|    trade-count target. A fresh touch on the SAME side as an already-                                                                                |
//|    active basket is a no-op for opening purposes (that basket's own                                                                                    |
//|    pyramid-add logic, not a fresh touch, is what adds further layers to                                                                                   |
//|    it); a touch on the OPPOSITE side opens its own independent basket.                                                                                        |
//| 6. THREE INDEPENDENT ZERO-CONFLUENCE ENTRY SOURCES, all funnelled through                                                                                        |
//|    the same TryFireTouch()/basket-per-direction gate so they share                                                                                                  |
//|    identical risk, sizing and concurrency rules (added per explicit                                                                                                    |
//|    follow-up request "add SND levels and EMA too for more trades"):                                                                                                       |
//|      a) Live M1 Bollinger Band touch (see point 2).                                                                                                                          |
//|      b) SND swing-high/low levels across M5/M15/H1/H4/D1/W1 (12 levels                                                                                                          |
//|         total, verbatim reuse of this codebase's proven                                                                                                                            |
//|         IsSwingHigh/IsSwingLow/RebuildLevelForTimeframe pattern from                                                                                                                  |
//|         EzyEA V3) - a touch of any level fades toward it, zero confluence.                                                                                                              |
//|      c) Live M5 EMA13 touch (verbatim reuse of V3's CheckEmaTouch                                                                                                                            |
//|         pattern) - direction is which side price approached from.                                                                                                                              |
//|    All three sources are edge-triggered/state-based (must leave the zone                                                                                                                          |
//|    before re-firing), for internal consistency across the whole file.                                                                                                                                |
//|                                                                                                                                                                                                          |
//| MECHANICS                                                                                                                                                                                                    |
//| - Each layer carries its own WIDE, static, ATR-scaled structural SL                                                                                                                                            |
//|   (InpStructuralSlAtrMult, broker-enforced at order-send) purely as a                                                                                                                                            |
//|   catastrophic/gap backstop - it is not expected to be the normal exit                                                                                                                                            |
//|   path. The REAL exit logic is basket-level, checked every tick, per                                                                                                                                              |
//|   basket:                                                                                                                                                                                                            |
//|     (a) basket trailing stop - arms once the basket's combined favourable                                                                                                                                             |
//|         excursion from its anchor entry clears an ATR-scaled activation                                                                                                                                                 |
//|         distance, then trails behind the peak by an ATR-scaled distance                                                                                                                                                   |
//|         ("hold ... to ride on the wins" / the "swing" half of this build).                                                                                                                                                  |
//|     (b) basket equity stop - fixed % of equity, force-closes every open                                                                                                                                                       |
//|         layer in that basket immediately, independent of (a).                                                                                                                                                                     |
//| - What is KEPT despite "remove all filter" - broker-compliance / basic                                                                                                                                                              |
//|   execution safety, per the explicit follow-up "ensure it follows broker                                                                                                                                                              |
//|   guidance": the auto-calibrating spread guard, broker minimum stop-                                                                                                                                                                     |
//|   distance clamping (SYMBOL_TRADE_STOPS_LEVEL/FREEZE_LEVEL), margin-usage                                                                                                                                                                  |
//|   cap, and account-level risk backstops (overall drawdown breaker, basket                                                                                                                                                                    |
//|   equity stop). These are not "strategic filters" on which setups are                                                                                                                                                                          |
//|   good enough to take - they are correctness/safety constraints that                                                                                                                                                                             |
//|   apply after a signal has already fired, matching this codebase's                                                                                                                                                                                  |
//|   established distinction between the two.                                                                                                                                                                                                            |
//| - Reuses this codebase's proven infrastructure verbatim in spirit: cent-                                                                                                                                                                                  |
//|   account detection/scaling, risk-%-of-equity lot sizing via                                                                                                                                                                                              |
//|   OrderCalcProfit() with a minimum-lot-fallback safety valve, retcode                                                                                                                                                                                        |
//|   classification (including TRADE_RETCODE_MARKET_CLOSED).                                                                                                                                                                                                       |
//| - Assumes a hedging-mode account (multiple simultaneous same-symbol                                                                                                                                                                                              |
//|   positions), matching every other EzyEA variant's assumption.                                                                                                                                                                                                       |
//| - Market orders only, TimeCurrent()-based timing throughout (never                                                                                                                                                                                                     |
//|   GetTickCount64) - built assuming an ultra-low-latency VPS.                                                                                                                                                                                                             |
//|                                                                                                                                                                                                                                                                            |
//| SCOPE NOTE: chart drawing stays a compact status label, live basket entry/                                                                                                                                                                                                  |
//| trail/SL lines, the Bollinger Band plot, and the SND level/EMA lines - the                                                                                                                                                                                                    |
//| fuller trade-card/historical-marker presentation from V1-V4 remains                                                                                                                                                                                                              |
//| deferred.                                                                                                                                                                                                                                                                          |
//|                                                                                                                                                                                                                                                                                        |
//| CHANGELOG                                                                                                                                                                                                                                                                                |
//| 1.000 - Initial build (bar-close-confirmed BB fade, single basket).                                                                                                                                                                                                                        |
//| 2.000 - "refine trade frequency ... minimum 100 trades per day": replaced                                                                                                                                                                                                                    |
//|         the bar-close confirmation with an immediate zero-confluence                                                                                                                                                                                                                            |
//|         band-touch trigger (state-based re-arm); made the volatility gate                                                                                                                                                                                                                          |
//|         optional/off by default; lowered InpBBDeviation (2.0->1.2);                                                                                                                                                                                                                                    |
//|         lowered pyramid step distance/inter-layer delay; switched from                                                                                                                                                                                                                                    |
//|         one global basket to two concurrent basket slots (long + short).                                                                                                                                                                                                                                     |
//| 2.100 - "add SND levels and EMA too for more trades" + "remove all                                                                                                                                                                                                                                          |
//|         filter ... ensure it follows broker guidance": added SND multi-                                                                                                                                                                                                                                          |
//|         timeframe swing-level touches and a live EMA13 touch as two more                                                                                                                                                                                                                                            |
//|         zero-confluence entry sources feeding the same basket-per-                                                                                                                                                                                                                                                    |
//|         direction gate; removed the volatility gate entirely (ATR is now                                                                                                                                                                                                                                                  |
//|         sizing-only, never an entry precondition); kept every broker-                                                                                                                                                                                                                                                        |
//|         compliance/execution-safety check (spread guard, broker minimum                                                                                                                                                                                                                                                          |
//|         stop distance, margin cap, drawdown breaker, basket equity stop)                                                                                                                                                                                                                                                              |
//|         unchanged, per explicit instruction to keep those.                                                                                                                                                                                                                                                                                  |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "2.100"
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
input group "=== ATR (sizing only - SL/step/trail distances; NOT an entry filter) ==="
input int    InpAtrFastPeriod               = 14;

input group "=== Entry Source 1: M1 Bollinger Band zero-confluence touch ==="
// A touch of either band, from either side, is the entire signal - no
// bar-close wait, no confirmation bar. Re-arm is state-based: that side
// must fully return inside the band before it can fire again.
input int    InpBBPeriod                    = 20;
input double InpBBDeviation                 = 1.2;

input group "=== Entry Source 2: SND swing levels (M5/M15/H1/H4/D1/W1), zero confluence ==="
input bool   InpEnableLevelTouchEntries     = true;
input double InpLevelTouchTolerancePoints   = 30.0;
input int    InpLevelLookbackM5             = 24;
input int    InpLevelLookbackM15            = 32;
input int    InpLevelLookbackH1             = 24;
input int    InpLevelLookbackH4             = 15;
input int    InpLevelLookbackD1             = 8;
input int    InpLevelLookbackW1             = 5;
// A zone level is the most recent genuine swing pivot within the
// lookback (high/low exceeds InpZonePivotBars bars on BOTH sides), zone
// PRICE uses that pivot bar's CLOSE (close-to-high for supply/SELL,
// close-to-low for demand/BUY) - same convention as EzyEA V3.
input int    InpZonePivotBars               = 3;

input group "=== Entry Source 3: EMA13 touch (M5, live value), zero confluence ==="
input bool   InpEnableEmaTouchEntries       = true;
input int    InpEmaPeriod                   = 13;
input double InpEmaTouchTolerancePoints     = 30.0;

input group "=== Anti-Martingale Pyramid Layering ==="
input int    InpMaxPyramidLayers            = 3;
// Each added layer's volume = previous layer's volume * this ratio
// (<1.0 = decreasing size, the anti-martingale convention).
input double InpPyramidSizeRatio            = 0.6;
// Price must move this many ATR(fast) multiples further in favour of
// the basket, from the MOST RECENT layer's own entry, before the next
// layer is added.
input double InpPyramidStepAtrMult          = 0.5;
input int    InpPyramidMinSecondsBetweenLayers = 2;

input group "=== Structural SL (per layer, catastrophic backstop only) ==="
// Wide and static - not expected to be the normal exit path. The real
// exit logic is the basket-level trail/equity-stop below.
input double InpStructuralSlAtrMult         = 3.0;

input group "=== Basket Exit: Trailing (ride the wins / the 'swing' side) ==="
input double InpBasketTrailActivationAtrMult = 1.5;
input double InpBasketTrailDistanceAtrMult   = 0.8;

input group "=== Basket Exit: Hard Equity Stop (cover losses) - risk backstop, not a filter ==="
// Fixed % of equity, not ATR-scaled - predictable worst case per basket.
input double InpBasketMaxLossEquityPct      = 3.0;

input group "=== Backstop: Max Holding Time (safety net, not a strategy exit) ==="
input int    InpMaxHoldingMinutes           = 180;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) - risk backstop, not a filter ==="
input bool   InpEnableDrawdownBreaker       = true;
input double InpMaxEquityDrawdownPct        = 10.0;
input double InpDrawdownResumeFactor        = 0.5;

input group "=== Risk / Sizing (first layer; later layers decay by InpPyramidSizeRatio) ==="
input double InpRiskPercentPerTrade         = 0.25;
input double InpMaxLotsAbsolute             = 5.0;
input double InpMaxMarginUsePct             = 40.0;
// On a small account, InpRiskPercentPerTrade's risk budget can round
// down below the broker's minimum lot (0.01) once XAUUSD's per-lot
// dollar sensitivity and an ATR-wide structural SL are applied - the
// signal never gets a chance to trade at all, not because it was a bad
// signal but purely because the arithmetic underflowed. If that
// happens, place the broker's minimum lot instead, but only if doing
// so wouldn't risk more than InpMinimumLotFallbackMaxRiskPct of equity
// (a real, if larger-than-requested, risk cap - not a blank check).
input bool   InpAllowMinimumLotFallback     = true;
input double InpMinimumLotFallbackMaxRiskPct = 1.0;

input group "=== Spread Guard (auto-calibrating) - broker-guidance safety, kept per explicit request ==="
input bool   InpAutoCalibrateSpreadCap      = true;
input int    InpSpreadCalibrationTicks      = 200;
input double InpSpreadCalibrationMultiplier = 2.5;
input int    InpMaxSpreadPoints             = 400;

input group "=== Cent-Account Handling ==="
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor      = 100.0;
input bool   InpTesterAutoModeIsStandard    = true;
input bool   InpTreatSCSuffixAsCentOnLive   = true;

input group "=== Execution (tuned for ultra-low-latency VPS) ==="
input ulong  InpMagicNumber                 = 190050;
input int    InpDeviationPoints             = 10;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Chart Drawing ==="
input bool   InpApplyPremiumTheme           = true;
input color  InpChartBackground             = C'8,11,15';
input color  InpChartForeground             = C'176,185,195';
input color  InpBullCandleColor             = C'0,208,142';
input color  InpBearCandleColor             = C'235,72,96';
input bool   InpHideNativeTickerOHLC        = true;
input bool   InpDrawBands                   = true;
input bool   InpDrawLevels                  = true;
input bool   InpDrawEma                     = true;
input int    InpDrawBarsBack                = 60;
input bool   InpDrawStatusLabel             = true;
input bool   InpShowLiveTradeLevels         = true;
input color  InpBuyColor                    = C'0,208,142';
input color  InpSellColor                   = C'235,72,96';
input color  InpTradeLevelGold              = C'255,215,0';

//======================================================================
// Types
//======================================================================
struct PyramidBasket
{
   bool     active;
   int      direction;         // 1 buy, -1 sell
   int      layerCount;
   ulong    tickets[8];
   double   lastLayerEntryPrice;
   double   peakFavorablePrice; // best price reached since basket open
   bool     trailActive;
   double   trailStopPrice;
   datetime openTime;
   datetime lastLayerTime;
   double   atrAtOpen;          // ATR(fast) snapshot at basket open, used for this basket's trail/step math
};

struct LevelTouchState
{
   double price;
   int    fadeDirection; // 1 = demand (support), fade BUY; -1 = supply (resistance), fade SELL
   bool   inZone;
   string tfLabel;
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

int g_handleAtrFast = INVALID_HANDLE;
int g_handleBB      = INVALID_HANDLE;
int g_handleEmaM5   = INVALID_HANDLE;

double g_accountUnitDivisor = 1.0;

double g_spreadCalSamples[];
int    g_spreadCalCount        = 0;
double g_spreadCalEffectiveCap = -1.0;

double g_peakEquity    = 0.0;
bool   g_tradingHalted = false;

// Basket slots: 0 = long (direction 1), 1 = short (direction -1).
PyramidBasket g_baskets[2];

// Zero-confluence touch state, shared by all three entry sources -
// edge-triggered, state-based re-arm (must fully return inside/off the
// zone before that side/level can fire again).
bool   g_inUpperZone   = false;
bool   g_inLowerZone   = false;
bool   g_emaInZone     = false;
bool   g_hasPreviousCMP = false;
double g_previousCMP    = 0.0;

// 6 timeframes (M5/M15/H1/H4/D1/W1) x 2 levels (swing high=supply,
// swing low=demand) each.
LevelTouchState g_levels[12];

datetime g_lastM5LevelBarTime  = 0;
datetime g_lastM15LevelBarTime = 0;
datetime g_lastH1LevelBarTime  = 0;
datetime g_lastH4LevelBarTime  = 0;
datetime g_lastD1LevelBarTime  = 0;
datetime g_lastW1LevelBarTime  = 0;

datetime g_lastStatusLogTime = 0;

int g_gateAttempts           = 0;
int g_gateAccepted           = 0;
int g_gateRejected           = 0;
int g_gateSpreadRejects      = 0;
int g_gateVolatilityRejects  = 0; // now means "ATR not ready yet", not a strategic filter
int g_gateDistanceRejects    = 0;
int g_gateSizingRejects      = 0;
int g_gateDrawdownRejects    = 0;

//======================================================================
// Forward declarations
//======================================================================
int    OnInit();
void   OnDeinit(const int reason);
void   OnTick();

string Upper(string s);
bool   IsGold();
bool   IsCentSuffixSymbol();
double RoundPrice(double v);
string PriceText(double v);
void   Log(string msg);

double ResolveAccountUnitDivisor();
double EffectiveAccountEquity();
int    VolumeDigits();
double NormalizeVolumeDown(double vol);
double OneLotLoss(int direction,double entry,double sl);
double ComputeFirstLayerLots(int direction,double entry,double sl);

bool   TradeRetcodeAccepted(uint code);
bool   TemporaryTradeRetcode(uint code);

double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel);
double MinimumStopDistance(double referencePrice);

int    SpreadCalibrationTicksEffective();
double MedianOfSpreadSamples(double &values[],int count);
bool   SpreadAllowed();

int    CopyBufferSeries(int handle,int bufferIndex,int count,double &out[]);

void   CloseAllPositions(string reason);
void   UpdateDrawdownBreaker();

double CurrentAtrFast();

bool   IsSwingHigh(ENUM_TIMEFRAMES tf,int shift,int pivotBars);
bool   IsSwingLow(ENUM_TIMEFRAMES tf,int shift,int pivotBars);
void   RebuildLevelForTimeframe(int slotIndex,ENUM_TIMEFRAMES tf,int lookback,string tfLabel);
void   UpdateLevelsOnNewBars();

int    BasketSlot(int direction);
void   ProcessZeroConfluenceTouchTriggers();
void   TryFireTouch(int direction);
void   OpenBasket(int direction,double atrFast);
void   TryAddPyramidLayer(int b,double atrFast);
bool   SubmitLayerOrder(int direction,int b,double lots,double structuralSlDistance,ulong &ticketOut);

void   PruneBasketTickets(int b);
void   UpdateBasketPeakAndTrail(int b,double atrFast);
double BasketFloatingPnL(int b);
void   ManageBasketExit(int b,double atrFast);
void   CloseBasket(int b,string reason);
void   EnforceMaxHoldingTime(int b);

void   DrawBands();
void   DrawLevels();
void   DrawEmaLine();
void   DrawStatusLabel();
void   DrawLiveTradeLevels();
void   ApplyPremiumChartTheme();
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
      Log("EzyEA V5 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   g_handleAtrFast = iATR(_Symbol,PERIOD_M1,MathMax(2,InpAtrFastPeriod));
   g_handleBB      = iBands(_Symbol,PERIOD_M1,MathMax(2,InpBBPeriod),0,InpBBDeviation,PRICE_CLOSE);
   g_handleEmaM5   = iMA(_Symbol,PERIOD_M5,MathMax(1,InpEmaPeriod),0,MODE_EMA,PRICE_CLOSE);

   if(g_handleAtrFast==INVALID_HANDLE || g_handleBB==INVALID_HANDLE || g_handleEmaM5==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed.");
      return INIT_FAILED;
   }

   g_accountUnitDivisor = ResolveAccountUnitDivisor();

   int capacity = SpreadCalibrationTicksEffective();
   ArrayResize(g_spreadCalSamples,capacity);
   g_spreadCalCount        = 0;
   g_spreadCalEffectiveCap = -1.0;

   g_peakEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted = false;

   for(int b=0;b<2;b++)
   {
      g_baskets[b].active = false;
      g_baskets[b].direction = (b==0)?1:-1;
      g_baskets[b].layerCount = 0;
      for(int i=0;i<8;i++) g_baskets[b].tickets[i]=0;
      g_baskets[b].lastLayerEntryPrice = 0.0;
      g_baskets[b].peakFavorablePrice  = 0.0;
      g_baskets[b].trailActive         = false;
      g_baskets[b].trailStopPrice      = 0.0;
      g_baskets[b].openTime            = 0;
      g_baskets[b].lastLayerTime       = 0;
      g_baskets[b].atrAtOpen           = 0.0;
   }

   g_inUpperZone    = false;
   g_inLowerZone    = false;
   g_emaInZone      = false;
   g_hasPreviousCMP = false;
   g_previousCMP    = 0.0;

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      g_levels[i].price=0.0;
      g_levels[i].fadeDirection=0;
      g_levels[i].inZone=false;
      g_levels[i].tfLabel="";
   }
   g_lastM5LevelBarTime  = 0;
   g_lastM15LevelBarTime = 0;
   g_lastH1LevelBarTime  = 0;
   g_lastH4LevelBarTime  = 0;
   g_lastD1LevelBarTime  = 0;
   g_lastW1LevelBarTime  = 0;

   g_lastStatusLogTime = 0;

   ApplyPremiumChartTheme();

   Log("EzyEA V5 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/first-layer="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | zero-confluence sources: BB(dev="+DoubleToString(InpBBDeviation,2)+")"+
       (InpEnableLevelTouchEntries?" + SND levels(12)":"")+
       (InpEnableEmaTouchEntries?" + EMA"+IntegerToString(InpEmaPeriod):"")+
       " | no volatility gate (ATR sizing-only)"+
       " | max pyramid layers="+IntegerToString(InpMaxPyramidLayers)+
       " (size ratio "+DoubleToString(InpPyramidSizeRatio,2)+")"+
       " | concurrent baskets: long+short"+
       " | basket equity stop="+DoubleToString(InpBasketMaxLossEquityPct,2)+"%"+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF"));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAtrFast!=INVALID_HANDLE) IndicatorRelease(g_handleAtrFast);
   if(g_handleBB!=INVALID_HANDLE)      IndicatorRelease(g_handleBB);
   if(g_handleEmaM5!=INVALID_HANDLE)   IndicatorRelease(g_handleEmaM5);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();

   for(int b=0;b<2;b++)
      PruneBasketTickets(b);

   double atrFast=CurrentAtrFast();

   if(!g_tradingHalted)
   {
      UpdateLevelsOnNewBars();
      ProcessZeroConfluenceTouchTriggers();

      for(int b=0;b<2;b++)
         if(g_baskets[b].active && atrFast>0.0)
            TryAddPyramidLayer(b,atrFast);
   }

   for(int b=0;b<2;b++)
   {
      if(!g_baskets[b].active) continue;
      ManageBasketExit(b,atrFast);
      EnforceMaxHoldingTime(b);
   }

   if(InpDrawBands)        DrawBands();
   if(InpDrawLevels)       DrawLevels();
   if(InpDrawEma)          DrawEmaLine();
   if(InpDrawStatusLabel)  DrawStatusLabel();
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
   Print("EzyEA V5 | ",msg);
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

double ComputeFirstLayerLots(int direction,double entry,double sl)
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

      Log("SIZING: risk budget rounded below broker minimum lot - "+
          "using minimum lot "+DoubleToString(minVol,2)+
          " (risking "+DoubleToString(minVolRiskPct,2)+"% of equity instead of "+
          DoubleToString(InpRiskPercentPerTrade,2)+"%)");
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
// Broker minimum distance (zero-stops-level fallback) - broker-guidance
// safety, kept per explicit request.
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
// - broker-guidance safety, kept per explicit request.
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
// Emergency stop: closes every position this EA opened, and clears all
// basket state (used both by the drawdown breaker and the basket-level
// equity stop).
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

   for(int b=0;b<2;b++)
   {
      g_baskets[b].active=false;
      g_baskets[b].layerCount=0;
      for(int i=0;i<8;i++) g_baskets[b].tickets[i]=0;
   }
}

//======================================================================
// Overall drawdown circuit breaker: peak equity seen since attach. A
// risk backstop, not an entry filter - unaffected by the "remove all
// filter" request. Distinct from, and wider than, the basket-level
// equity stop.
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
// ATR - sizing only (structural SL / pyramid step / trail distances).
// Not an entry precondition anywhere in this file anymore.
//======================================================================
double CurrentAtrFast()
{
   double buf[];
   if(CopyBufferSeries(g_handleAtrFast,0,2,buf)<2) return 0.0;
   return buf[1]; // last CLOSED M1 bar's ATR value
}

//======================================================================
// SND swing-level engine (verbatim port of EzyEA V3's pattern): a
// genuine swing pivot within the lookback, zone price = that pivot
// bar's CLOSE (close-to-high for supply/SELL, close-to-low for demand/
// BUY), falling back to the raw window extreme if no pivot qualifies.
//======================================================================
bool IsSwingHigh(ENUM_TIMEFRAMES tf,int shift,int pivotBars)
{
   double h=iHigh(_Symbol,tf,shift);
   if(h<=0.0) return false;

   for(int k=1;k<=pivotBars;k++)
   {
      double older=iHigh(_Symbol,tf,shift+k);
      double newer=iHigh(_Symbol,tf,shift-k);
      if(older<=0.0 || newer<=0.0) return false;
      if(h<older || h<newer) return false;
   }
   return true;
}

bool IsSwingLow(ENUM_TIMEFRAMES tf,int shift,int pivotBars)
{
   double l=iLow(_Symbol,tf,shift);
   if(l<=0.0) return false;

   for(int k=1;k<=pivotBars;k++)
   {
      double older=iLow(_Symbol,tf,shift+k);
      double newer=iLow(_Symbol,tf,shift-k);
      if(older<=0.0 || newer<=0.0) return false;
      if(l>older || l>newer) return false;
   }
   return true;
}

void RebuildLevelForTimeframe(int slotIndex,ENUM_TIMEFRAMES tf,int lookback,string tfLabel)
{
   int pivotBars=MathMax(1,InpZonePivotBars);

   double fallbackHi=-DBL_MAX, fallbackLo=DBL_MAX;
   double swingHi=0.0, swingLo=0.0;
   bool   foundHi=false, foundLo=false;

   int minShift=1+pivotBars;

   for(int shift=minShift;shift<=lookback;shift++)
   {
      double h=iHigh(_Symbol,tf,shift);
      double l=iLow(_Symbol,tf,shift);
      double c=iClose(_Symbol,tf,shift);
      if(h<=0.0 || l<=0.0 || c<=0.0) continue;

      fallbackHi=MathMax(fallbackHi,c);
      fallbackLo=MathMin(fallbackLo,c);

      if(!foundHi && IsSwingHigh(tf,shift,pivotBars))
      {
         swingHi=c;
         foundHi=true;
      }
      if(!foundLo && IsSwingLow(tf,shift,pivotBars))
      {
         swingLo=c;
         foundLo=true;
      }

      if(foundHi && foundLo) break;
   }

   double hi=foundHi?swingHi:fallbackHi;
   double lo=foundLo?swingLo:fallbackLo;

   if(hi<=-DBL_MAX || lo>=DBL_MAX) return;

   int supplyIdx=slotIndex*2;
   int demandIdx=slotIndex*2+1;

   g_levels[supplyIdx].price=RoundPrice(hi);
   g_levels[supplyIdx].fadeDirection=-1;
   g_levels[supplyIdx].tfLabel=tfLabel;

   g_levels[demandIdx].price=RoundPrice(lo);
   g_levels[demandIdx].fadeDirection=1;
   g_levels[demandIdx].tfLabel=tfLabel;
}

void UpdateLevelsOnNewBars()
{
   if(!InpEnableLevelTouchEntries) return;

   datetime m5=iTime(_Symbol,PERIOD_M5,0);
   if(m5!=0 && m5!=g_lastM5LevelBarTime)
   {
      g_lastM5LevelBarTime=m5;
      RebuildLevelForTimeframe(0,PERIOD_M5,InpLevelLookbackM5,"M5");
   }

   datetime m15=iTime(_Symbol,PERIOD_M15,0);
   if(m15!=0 && m15!=g_lastM15LevelBarTime)
   {
      g_lastM15LevelBarTime=m15;
      RebuildLevelForTimeframe(1,PERIOD_M15,InpLevelLookbackM15,"M15");
   }

   datetime h1=iTime(_Symbol,PERIOD_H1,0);
   if(h1!=0 && h1!=g_lastH1LevelBarTime)
   {
      g_lastH1LevelBarTime=h1;
      RebuildLevelForTimeframe(2,PERIOD_H1,InpLevelLookbackH1,"H1");
   }

   datetime h4=iTime(_Symbol,PERIOD_H4,0);
   if(h4!=0 && h4!=g_lastH4LevelBarTime)
   {
      g_lastH4LevelBarTime=h4;
      RebuildLevelForTimeframe(3,PERIOD_H4,InpLevelLookbackH4,"H4");
   }

   datetime d1=iTime(_Symbol,PERIOD_D1,0);
   if(d1!=0 && d1!=g_lastD1LevelBarTime)
   {
      g_lastD1LevelBarTime=d1;
      RebuildLevelForTimeframe(4,PERIOD_D1,InpLevelLookbackD1,"D1");
   }

   datetime w1=iTime(_Symbol,PERIOD_W1,0);
   if(w1!=0 && w1!=g_lastW1LevelBarTime)
   {
      g_lastW1LevelBarTime=w1;
      RebuildLevelForTimeframe(5,PERIOD_W1,InpLevelLookbackW1,"W1");
   }
}

//======================================================================
// Entry: three zero-confluence touch sources (BB band / SND levels /
// EMA13), all edge-triggered with state-based re-arm, all funnelled
// through the same TryFireTouch()/basket-per-direction gate below. No
// volatility gate, no confirmation wait, no confluence requirement.
//======================================================================
int BasketSlot(int direction)
{
   return (direction==1)?0:1;
}

void ProcessZeroConfluenceTouchTriggers()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double observedLo=tick.bid, observedHi=tick.bid;
   if(tick.ask>0.0)
   {
      observedLo=MathMin(observedLo,tick.ask);
      observedHi=MathMax(observedHi,tick.ask);
   }
   if(g_hasPreviousCMP && g_previousCMP>0.0)
   {
      observedLo=MathMin(observedLo,g_previousCMP);
      observedHi=MathMax(observedHi,g_previousCMP);
   }

   // --- Source 1: live M1 Bollinger Band touch ---
   double upperBuf[],lowerBuf[];
   if(CopyBufferSeries(g_handleBB,1,1,upperBuf)>=1 && CopyBufferSeries(g_handleBB,2,1,lowerBuf)>=1)
   {
      double upper=upperBuf[0];
      double lower=lowerBuf[0];
      if(upper>0.0 && lower>0.0 && upper>lower)
      {
         bool touchingUpper=(observedHi>=upper);
         bool touchingLower=(observedLo<=lower);
         bool fireUpper=touchingUpper && !g_inUpperZone;
         bool fireLower=touchingLower && !g_inLowerZone;

         g_inUpperZone=touchingUpper;
         g_inLowerZone=touchingLower;

         if(fireUpper) TryFireTouch(-1); // touched/crossed above upper band -> fade SELL
         if(fireLower) TryFireTouch(1);  // touched/crossed below lower band -> fade BUY
      }
   }

   // --- Source 2: SND swing-level touch (M5/M15/H1/H4/D1/W1) ---
   if(InpEnableLevelTouchEntries)
   {
      double tol=InpLevelTouchTolerancePoints*_Point;
      for(int i=0;i<ArraySize(g_levels);i++)
      {
         if(g_levels[i].price<=0.0) continue;

         bool touching=(observedHi>=g_levels[i].price-tol && observedLo<=g_levels[i].price+tol);
         bool fire=touching && !g_levels[i].inZone;
         g_levels[i].inZone=touching;

         if(fire) TryFireTouch(g_levels[i].fadeDirection);
      }
   }

   // --- Source 3: live M5 EMA13 touch ---
   if(InpEnableEmaTouchEntries)
   {
      double emaBuf[];
      if(CopyBufferSeries(g_handleEmaM5,0,1,emaBuf)>=1)
      {
         double emaValue=emaBuf[0];
         if(emaValue>0.0)
         {
            double tol=InpEmaTouchTolerancePoints*_Point;
            bool touching=(observedHi>=emaValue-tol && observedLo<=emaValue+tol);
            bool fire=touching && !g_emaInZone;
            g_emaInZone=touching;

            if(fire && g_hasPreviousCMP && g_previousCMP>0.0)
            {
               int direction=0;
               if(g_previousCMP>emaValue)      direction=1;  // was above, dipped to touch -> expect bounce up -> BUY
               else if(g_previousCMP<emaValue) direction=-1; // was below, rallied to touch -> expect rejection down -> SELL
               if(direction!=0) TryFireTouch(direction);
            }
         }
      }
   }

   g_previousCMP=(tick.bid>0.0)?tick.bid:tick.last;
   g_hasPreviousCMP=true;
}

void TryFireTouch(int direction)
{
   int slot=BasketSlot(direction);
   if(g_baskets[slot].active) return; // that side already has a running basket - pyramiding handles further adds into it

   g_gateAttempts++;

   if(g_tradingHalted)
   {
      g_gateDrawdownRejects++;
      return;
   }

   double atrFast=CurrentAtrFast();
   if(atrFast<=0.0)
   {
      g_gateVolatilityRejects++; // ATR not ready yet (e.g. warming up) - data availability, not a strategic filter
      return;
   }

   if(!SpreadAllowed())
   {
      g_gateSpreadRejects++;
      return;
   }

   OpenBasket(direction,atrFast);
}

//======================================================================
// Basket open (first layer) / pyramid adds
//======================================================================
void OpenBasket(int direction,double atrFast)
{
   int slot=BasketSlot(direction);
   if(g_baskets[slot].active) return; // safety - caller already checks this

   double structuralSlDistance=MathMax(_Point,InpStructuralSlAtrMult*atrFast);

   ulong ticket=0;
   if(!SubmitLayerOrder(direction,slot,-1.0,structuralSlDistance,ticket))
      return; // SubmitLayerOrder logs its own rejection reason

   g_baskets[slot].active              = true;
   g_baskets[slot].direction           = direction;
   g_baskets[slot].layerCount          = 1;
   g_baskets[slot].tickets[0]          = ticket;
   for(int i=1;i<8;i++) g_baskets[slot].tickets[i]=0;

   double entryPrice=0.0;
   if(PositionSelectByTicket(ticket))
      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);

   g_baskets[slot].lastLayerEntryPrice = entryPrice;
   g_baskets[slot].peakFavorablePrice  = entryPrice;
   g_baskets[slot].trailActive         = false;
   g_baskets[slot].trailStopPrice      = 0.0;
   g_baskets[slot].openTime            = TimeCurrent();
   g_baskets[slot].lastLayerTime       = TimeCurrent();
   g_baskets[slot].atrAtOpen           = atrFast;

   Log("BASKET OPEN ["+(direction==1?"LONG":"SHORT")+"] entry="+PriceText(entryPrice)+
       " atrFast="+PriceText(atrFast)+
       " structuralSL="+PriceText(structuralSlDistance));
}

void TryAddPyramidLayer(int b,double atrFast)
{
   // g_baskets[b].tickets[] is fixed at 8 slots - clamp the effective cap
   // so a mistakenly-large InpMaxPyramidLayers input can never index past it.
   if(g_baskets[b].layerCount>=MathMin(8,InpMaxPyramidLayers)) return;
   if(TimeCurrent()-g_baskets[b].lastLayerTime<MathMax(0,InpPyramidMinSecondsBetweenLayers)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   int direction=g_baskets[b].direction;
   double currentPrice=(direction==1)?tick.bid:tick.ask;
   double favorableFromLastLayer=(direction==1)
                                 ?(currentPrice-g_baskets[b].lastLayerEntryPrice)
                                 :(g_baskets[b].lastLayerEntryPrice-currentPrice);

   double stepDistance=MathMax(_Point,InpPyramidStepAtrMult*atrFast);
   if(favorableFromLastLayer<stepDistance) return;

   if(!SpreadAllowed()) return;

   double structuralSlDistance=MathMax(_Point,InpStructuralSlAtrMult*atrFast);

   ulong ticket=0;
   if(!SubmitLayerOrder(direction,b,-1.0,structuralSlDistance,ticket))
      return;

   double entryPrice=0.0;
   if(PositionSelectByTicket(ticket))
      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);

   g_baskets[b].tickets[g_baskets[b].layerCount]=ticket;
   g_baskets[b].layerCount++;
   g_baskets[b].lastLayerEntryPrice=entryPrice;
   g_baskets[b].lastLayerTime=TimeCurrent();

   Log("PYRAMID LAYER ADDED ["+(direction==1?"LONG":"SHORT")+"] layer="+
       IntegerToString(g_baskets[b].layerCount)+"/"+IntegerToString(InpMaxPyramidLayers)+
       " entry="+PriceText(entryPrice));
}

//======================================================================
// Order submission: first layer sizes off InpRiskPercentPerTrade via
// OneLotLoss(); each subsequent layer decays by InpPyramidSizeRatio off
// the FIRST layer's lot size (a stable base rather than compounding
// rounding error off the previous layer).
//======================================================================
bool SubmitLayerOrder(int direction,int b,double lots,double structuralSlDistance,ulong &ticketOut)
{
   ticketOut=0;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;

   double entry=(direction==1)?tick.ask:tick.bid;
   double sl=RoundPrice((direction==1)?entry-structuralSlDistance:entry+structuralSlDistance);

   double minDist=MinimumStopDistance(entry);
   if(MathAbs(entry-sl)<minDist)
   {
      g_gateDistanceRejects++;
      Log("LAYER REJECTED reason=SL_DISTANCE_TOO_TIGHT slDistance="+
          PriceText(structuralSlDistance)+" minDist="+PriceText(minDist));
      return false;
   }

   if(lots<=0.0)
   {
      if(g_baskets[b].layerCount<=0)
      {
         lots=ComputeFirstLayerLots(direction,entry,sl);
      }
      else
      {
         // Base off layer 1's own lot size (queried live), decayed by
         // the ratio raised to the current layer index.
         double baseLots=0.0;
         if(PositionSelectByTicket(g_baskets[b].tickets[0]))
            baseLots=PositionGetDouble(POSITION_VOLUME);

         double ratio=MathPow(MathMax(0.01,MathMin(1.0,InpPyramidSizeRatio)),(double)g_baskets[b].layerCount);
         lots=NormalizeVolumeDown(baseLots*ratio);
      }
   }

   if(lots<=0.0)
   {
      g_gateSizingRejects++;
      Log("LAYER REJECTED reason=ZERO_LOTS entry="+PriceText(entry)+" sl="+PriceText(sl));
      return false;
   }

   bool sent=(direction==1)
             ? trade.Buy(lots,_Symbol,0.0,sl,0.0,"V5FADE")
             : trade.Sell(lots,_Symbol,0.0,sl,0.0,"V5FADE");

   uint retcode=trade.ResultRetcode();

   if(sent && TradeRetcodeAccepted(retcode))
   {
      g_gateAccepted++;
      ticketOut=trade.ResultOrder();
      // ResultOrder() can be a pending-order/deal ticket depending on
      // execution mode; the position ticket for a market fill is the
      // same value on most brokers, but confirm by re-selecting - if it
      // doesn't resolve to an open position yet, look up the newest
      // position matching this symbol/magic as a fallback.
      if(!PositionSelectByTicket(ticketOut))
      {
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong candidate=PositionGetTicket(i);
            if(candidate==0) continue;
            if(!PositionSelectByTicket(candidate)) continue;
            if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
            ticketOut=candidate;
            break;
         }
      }
      Log("LAYER FILLED dir="+IntegerToString(direction)+
          " lots="+DoubleToString(lots,2)+
          " entry="+PriceText(entry)+
          " sl="+PriceText(sl));
      return true;
   }

   g_gateRejected++;
   Log("LAYER REJECTED retcode="+IntegerToString(retcode)+
       " desc="+trade.ResultRetcodeDescription());
   return false;
}

//======================================================================
// Basket bookkeeping
//======================================================================
void PruneBasketTickets(int b)
{
   if(!g_baskets[b].active) return;

   int remaining=0;
   ulong survivors[8];
   for(int i=0;i<g_baskets[b].layerCount;i++)
   {
      if(g_baskets[b].tickets[i]!=0 && PositionSelectByTicket(g_baskets[b].tickets[i]))
      {
         survivors[remaining]=g_baskets[b].tickets[i];
         remaining++;
      }
   }

   if(remaining==g_baskets[b].layerCount) return; // nothing changed

   for(int i=0;i<remaining;i++) g_baskets[b].tickets[i]=survivors[i];
   for(int i=remaining;i<8;i++) g_baskets[b].tickets[i]=0;
   g_baskets[b].layerCount=remaining;

   if(remaining==0)
   {
      Log("BASKET CLOSED ["+(g_baskets[b].direction==1?"LONG":"SHORT")+"] (all layers gone)");
      g_baskets[b].active=false;
   }
}

double BasketFloatingPnL(int b)
{
   double total=0.0;
   for(int i=0;i<g_baskets[b].layerCount;i++)
   {
      if(g_baskets[b].tickets[i]==0) continue;
      if(!PositionSelectByTicket(g_baskets[b].tickets[i])) continue;
      total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

void UpdateBasketPeakAndTrail(int b,double atrFast)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   int direction=g_baskets[b].direction;
   double currentPrice=(direction==1)?tick.bid:tick.ask;

   if(direction==1)
      g_baskets[b].peakFavorablePrice=MathMax(g_baskets[b].peakFavorablePrice,currentPrice);
   else
      g_baskets[b].peakFavorablePrice=MathMin(g_baskets[b].peakFavorablePrice,currentPrice);

   if(atrFast<=0.0) atrFast=g_baskets[b].atrAtOpen;
   if(atrFast<=0.0) return;

   // Favourable excursion measured from the FIRST layer's entry (the
   // basket's anchor), not a volume-weighted average - simplest stable
   // reference point for trail activation/step math.
   double anchorEntry=0.0;
   if(g_baskets[b].tickets[0]!=0 && PositionSelectByTicket(g_baskets[b].tickets[0]))
      anchorEntry=PositionGetDouble(POSITION_PRICE_OPEN);
   if(anchorEntry<=0.0) return;

   double peakFavorable=(direction==1)
                        ?(g_baskets[b].peakFavorablePrice-anchorEntry)
                        :(anchorEntry-g_baskets[b].peakFavorablePrice);

   double activationDistance=MathMax(_Point,InpBasketTrailActivationAtrMult*atrFast);
   double trailDistance     =MathMax(_Point,InpBasketTrailDistanceAtrMult*atrFast);

   if(!g_baskets[b].trailActive && peakFavorable>=activationDistance)
   {
      g_baskets[b].trailActive=true;
      Log("BASKET TRAIL ARMED ["+(direction==1?"LONG":"SHORT")+"] peakFavorable="+
          PriceText(peakFavorable)+" activationDistance="+PriceText(activationDistance));
   }

   if(g_baskets[b].trailActive)
   {
      double candidateStop=RoundPrice((direction==1)
                                      ?g_baskets[b].peakFavorablePrice-trailDistance
                                      :g_baskets[b].peakFavorablePrice+trailDistance);
      bool improves=(g_baskets[b].trailStopPrice<=0.0) ||
                    ((direction==1)
                     ?(candidateStop>g_baskets[b].trailStopPrice)
                     :(candidateStop<g_baskets[b].trailStopPrice));
      if(improves)
         g_baskets[b].trailStopPrice=candidateStop;
   }
}

void ManageBasketExit(int b,double atrFast)
{
   UpdateBasketPeakAndTrail(b,atrFast);

   // (a) Basket-level hard equity stop - fixed % of equity, independent
   // of whether the trail has armed yet. Risk backstop, not a filter.
   double floatingPnl=BasketFloatingPnL(b);
   double equity=EffectiveAccountEquity();
   if(equity>0.0)
   {
      double lossPct=(-floatingPnl/equity)*100.0;
      if(lossPct>=InpBasketMaxLossEquityPct)
      {
         CloseBasket(b,"basket equity stop ("+DoubleToString(lossPct,2)+"% >= "+
                     DoubleToString(InpBasketMaxLossEquityPct,2)+"%)");
         return;
      }
   }

   // (b) Basket trailing stop, once armed.
   if(g_baskets[b].trailActive && g_baskets[b].trailStopPrice>0.0)
   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
      {
         int direction=g_baskets[b].direction;
         double currentPrice=(direction==1)?tick.bid:tick.ask;
         bool hit=(direction==1)
                  ?(currentPrice<=g_baskets[b].trailStopPrice+_Point*0.25)
                  :(currentPrice>=g_baskets[b].trailStopPrice-_Point*0.25);
         if(hit)
         {
            CloseBasket(b,"basket trailing stop hit at "+PriceText(g_baskets[b].trailStopPrice));
            return;
         }
      }
   }
}

void CloseBasket(int b,string reason)
{
   Log("CLOSING BASKET ["+(g_baskets[b].direction==1?"LONG":"SHORT")+"] | reason="+reason+
       " | layers="+IntegerToString(g_baskets[b].layerCount)+
       " | floatingPnl="+DoubleToString(BasketFloatingPnL(b),2));

   for(int i=0;i<g_baskets[b].layerCount;i++)
   {
      if(g_baskets[b].tickets[i]==0) continue;
      if(!PositionSelectByTicket(g_baskets[b].tickets[i])) continue;

      bool ok=trade.PositionClose(g_baskets[b].tickets[i]);
      uint retcode=trade.ResultRetcode();
      if(!ok || !TradeRetcodeAccepted(retcode))
         Log("BASKET LAYER CLOSE FAILED ticket="+IntegerToString((int)g_baskets[b].tickets[i])+
             " retcode="+IntegerToString(retcode));
   }

   g_baskets[b].active=false;
   g_baskets[b].layerCount=0;
   for(int i=0;i<8;i++) g_baskets[b].tickets[i]=0;
}

void EnforceMaxHoldingTime(int b)
{
   if(InpMaxHoldingMinutes<=0) return;
   if(!g_baskets[b].active) return;

   long cutoffSeconds=(long)InpMaxHoldingMinutes*60;
   long heldSeconds=(long)(TimeCurrent()-g_baskets[b].openTime);
   if(heldSeconds<cutoffSeconds) return;

   CloseBasket(b,"max holding time backstop ("+IntegerToString(InpMaxHoldingMinutes)+" min)");
}

//======================================================================
// Chart drawing
//======================================================================
void DrawBands()
{
   int bars=MathMax(3,InpDrawBarsBack);
   double upperBuf[],lowerBuf[],baseBuf[];
   int n1=CopyBufferSeries(g_handleBB,1,bars,upperBuf);
   int n2=CopyBufferSeries(g_handleBB,2,bars,lowerBuf);
   int n3=CopyBufferSeries(g_handleBB,0,bars,baseBuf);
   int n=MathMin(n1,MathMin(n2,n3));
   if(n<2) return;

   for(int shift=0;shift<n-1;shift++)
   {
      datetime t1=iTime(_Symbol,PERIOD_M1,shift+1);
      datetime t2=iTime(_Symbol,PERIOD_M1,shift);
      if(t1==0 || t2==0) continue;

      string nameU="V5_BBU_"+IntegerToString(shift);
      string nameL="V5_BBL_"+IntegerToString(shift);
      string nameB="V5_BBB_"+IntegerToString(shift);

      if(ObjectFind(0,nameU)<0) ObjectCreate(0,nameU,OBJ_TREND,0,t1,upperBuf[shift+1],t2,upperBuf[shift]);
      else { ObjectMove(0,nameU,0,t1,upperBuf[shift+1]); ObjectMove(0,nameU,1,t2,upperBuf[shift]); }
      ObjectSetInteger(0,nameU,OBJPROP_COLOR,clrDodgerBlue);
      ObjectSetInteger(0,nameU,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameU,OBJPROP_RAY,false);
      ObjectSetInteger(0,nameU,OBJPROP_SELECTABLE,false);

      if(ObjectFind(0,nameL)<0) ObjectCreate(0,nameL,OBJ_TREND,0,t1,lowerBuf[shift+1],t2,lowerBuf[shift]);
      else { ObjectMove(0,nameL,0,t1,lowerBuf[shift+1]); ObjectMove(0,nameL,1,t2,lowerBuf[shift]); }
      ObjectSetInteger(0,nameL,OBJPROP_COLOR,clrDodgerBlue);
      ObjectSetInteger(0,nameL,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameL,OBJPROP_RAY,false);
      ObjectSetInteger(0,nameL,OBJPROP_SELECTABLE,false);

      if(ObjectFind(0,nameB)<0) ObjectCreate(0,nameB,OBJ_TREND,0,t1,baseBuf[shift+1],t2,baseBuf[shift]);
      else { ObjectMove(0,nameB,0,t1,baseBuf[shift+1]); ObjectMove(0,nameB,1,t2,baseBuf[shift]); }
      ObjectSetInteger(0,nameB,OBJPROP_COLOR,clrGray);
      ObjectSetInteger(0,nameB,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nameB,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameB,OBJPROP_RAY,false);
      ObjectSetInteger(0,nameB,OBJPROP_SELECTABLE,false);
   }
}

void DrawLevels()
{
   for(int i=0;i<ArraySize(g_levels);i++)
   {
      string name="V5_LVL_"+IntegerToString(i);
      if(g_levels[i].price<=0.0)
      {
         ObjectDelete(0,name);
         continue;
      }

      color clr=(g_levels[i].fadeDirection==1)?clrLime:clrRed;

      if(ObjectFind(0,name)<0)
         ObjectCreate(0,name,OBJ_HLINE,0,0,g_levels[i].price);

      ObjectSetDouble(0,name,OBJPROP_PRICE,g_levels[i].price);
      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetString(0,name,OBJPROP_TEXT,
                      g_levels[i].tfLabel+" "+
                      (g_levels[i].fadeDirection==1?"DEMAND":"SUPPLY"));
   }
}

void DrawEmaLine()
{
   int bars=MathMax(3,InpDrawBarsBack);
   double emaBuf[];
   int n=CopyBufferSeries(g_handleEmaM5,0,bars,emaBuf);
   if(n<2) return;

   for(int shift=0;shift<n-1;shift++)
   {
      string name="V5_EMA_"+IntegerToString(shift);
      datetime t1=iTime(_Symbol,PERIOD_M5,shift+1);
      datetime t2=iTime(_Symbol,PERIOD_M5,shift);
      double p1=emaBuf[shift+1];
      double p2=emaBuf[shift];
      if(t1==0 || t2==0) continue;

      if(ObjectFind(0,name)<0)
         ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
      else
      {
         ObjectMove(0,name,0,t1,p1);
         ObjectMove(0,name,1,t2,p2);
      }

      ObjectSetInteger(0,name,OBJPROP_COLOR,clrOrange);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_RAY,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   }
}

void DrawStatusLabel()
{
   string name="V5_StatusLabel";
   double atrFast=CurrentAtrFast();

   string longText=g_baskets[0].active
                   ?("LONG layers="+IntegerToString(g_baskets[0].layerCount)+"/"+IntegerToString(InpMaxPyramidLayers)+
                     " trail="+(g_baskets[0].trailActive?"ARMED":"-")+
                     " pnl="+DoubleToString(BasketFloatingPnL(0),2))
                   :"LONG -";
   string shortText=g_baskets[1].active
                    ?("SHORT layers="+IntegerToString(g_baskets[1].layerCount)+"/"+IntegerToString(InpMaxPyramidLayers)+
                      " trail="+(g_baskets[1].trailActive?"ARMED":"-")+
                      " pnl="+DoubleToString(BasketFloatingPnL(1),2))
                    :"SHORT -";

   string text=StringFormat(
      "EzyEA V5 | ATR(fast)=%s | %s | %s | equity=%.2f | %s",
      PriceText(atrFast),longText,shortText,
      EffectiveAccountEquity(),
      g_tradingHalted?"HALTED":"ACTIVE");

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
   ObjectsDeleteAll(0,"V5_LIVE_");

   for(int b=0;b<2;b++)
   {
      if(!g_baskets[b].active) continue;

      color dirColor=(g_baskets[b].direction==1)?InpBuyColor:InpSellColor;

      for(int i=0;i<g_baskets[b].layerCount;i++)
      {
         if(g_baskets[b].tickets[i]==0) continue;
         if(!PositionSelectByTicket(g_baskets[b].tickets[i])) continue;

         double entry=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl   =PositionGetDouble(POSITION_SL);

         string nameE="V5_LIVE_ENTRY_"+IntegerToString((int)g_baskets[b].tickets[i]);
         if(ObjectFind(0,nameE)<0) ObjectCreate(0,nameE,OBJ_HLINE,0,0,entry);
         ObjectSetDouble(0,nameE,OBJPROP_PRICE,entry);
         ObjectSetInteger(0,nameE,OBJPROP_COLOR,InpTradeLevelGold);
         ObjectSetInteger(0,nameE,OBJPROP_STYLE,STYLE_SOLID);
         ObjectSetInteger(0,nameE,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nameE,OBJPROP_SELECTABLE,false);

         if(sl>0.0)
         {
            string nameS="V5_LIVE_SL_"+IntegerToString((int)g_baskets[b].tickets[i]);
            if(ObjectFind(0,nameS)<0) ObjectCreate(0,nameS,OBJ_HLINE,0,0,sl);
            ObjectSetDouble(0,nameS,OBJPROP_PRICE,sl);
            ObjectSetInteger(0,nameS,OBJPROP_COLOR,InpTradeLevelGold);
            ObjectSetInteger(0,nameS,OBJPROP_STYLE,STYLE_DASH);
            ObjectSetInteger(0,nameS,OBJPROP_WIDTH,1);
            ObjectSetInteger(0,nameS,OBJPROP_SELECTABLE,false);
         }
      }

      if(g_baskets[b].trailActive && g_baskets[b].trailStopPrice>0.0)
      {
         string nameT="V5_LIVE_TRAIL_"+IntegerToString(b);
         if(ObjectFind(0,nameT)<0) ObjectCreate(0,nameT,OBJ_HLINE,0,0,g_baskets[b].trailStopPrice);
         ObjectSetDouble(0,nameT,OBJPROP_PRICE,g_baskets[b].trailStopPrice);
         ObjectSetInteger(0,nameT,OBJPROP_COLOR,dirColor);
         ObjectSetInteger(0,nameT,OBJPROP_STYLE,STYLE_DASHDOT);
         ObjectSetInteger(0,nameT,OBJPROP_WIDTH,2);
         ObjectSetInteger(0,nameT,OBJPROP_SELECTABLE,false);
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
   ObjectsDeleteAll(0,"V5_");
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
       " atrNotReadyRejects="+IntegerToString(g_gateVolatilityRejects)+
       " distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " sizingRejects="+IntegerToString(g_gateSizingRejects)+
       " drawdownRejects="+IntegerToString(g_gateDrawdownRejects));
}

void PeriodicStatusLog()
{
   if(InpStatusLogIntervalSeconds<=0) return;
   if(TimeCurrent()-g_lastStatusLogTime<InpStatusLogIntervalSeconds) return;
   g_lastStatusLogTime=TimeCurrent();

   Log("STATUS | equity="+DoubleToString(EffectiveAccountEquity(),2)+
       " | LONG="+(g_baskets[0].active?"ACTIVE layers="+IntegerToString(g_baskets[0].layerCount)+
                   " trail="+(g_baskets[0].trailActive?"ARMED":"OFF")+
                   " pnl="+DoubleToString(BasketFloatingPnL(0),2):"NONE")+
       " | SHORT="+(g_baskets[1].active?"ACTIVE layers="+IntegerToString(g_baskets[1].layerCount)+
                    " trail="+(g_baskets[1].trailActive?"ARMED":"OFF")+
                    " pnl="+DoubleToString(BasketFloatingPnL(1),2):"NONE")+
       " | halted="+(g_tradingHalted?"YES":"NO"));

   Log("DEPLOYMENT GATE BREAKDOWN | attempts="+IntegerToString(g_gateAttempts)+
       " accepted="+IntegerToString(g_gateAccepted)+
       " rejected="+IntegerToString(g_gateRejected)+
       " | spread="+IntegerToString(g_gateSpreadRejects)+
       " atrNotReady="+IntegerToString(g_gateVolatilityRejects)+
       " distance="+IntegerToString(g_gateDistanceRejects)+
       " sizing="+IntegerToString(g_gateSizingRejects)+
       " drawdown="+IntegerToString(g_gateDrawdownRejects));
}
