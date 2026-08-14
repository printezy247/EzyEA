//+------------------------------------------------------------------+
//|                                           EzyEA_V1.1_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V1.1 - branched from EzyEA_V1_XAUUSD.mq5 1.000, per explicit |
//| request, so V1 stays untouched. Same entry philosophy and risk      |
//| layer as V1 (SND M5->Weekly + EMA13 M5 zero-confluence touch, H1    |
//| ADX trend filter, per-direction concurrency cap, portfolio          |
//| drawdown breaker, VPS-tuned modify backoff/re-entry cooldowns) -    |
//| the ONLY thing that changed is the exit mechanism.                  |
//|                                                                      |
//| EXIT LOGIC - V1's original ATR-based single-distance trail-only      |
//| exit is REPLACED with EzyEA V3's hybrid virtual-trail mechanism       |
//| (this generation's A/B-tested winner), fixed-pip rather than          |
//| ATR-relative, with a distinct preset per explicit request:            |
//|   - InpPresetStopLossPips = 30: wide floor protecting from entry.     |
//|   - InpTrailingDistancePips = 15: tight distance used once trailing   |
//|     is armed.                                                         |
//|   - InpTrailActivationPips = 10: the trail arms once floating P&L      |
//|     reaches +10 pips, not merely turning positive - the wide preset    |
//|     floor is the only protection until that threshold clears.          |
//|   - Real stop protection no longer depends on the broker accepting     |
//|     a tight SL modify(): a virtual stop is tracked in EA memory and     |
//|     checked every tick; the moment price crosses it, the position is    |
//|     force-closed directly (CloseAtVirtualStop). The broker-side SL is   |
//|     still pushed as a best-effort backup net via the existing           |
//|     backoff-protected ModifyPositionSafely, clamped to the closest      |
//|     distance the broker will legally accept.                            |
//|   - InpReconstructPeakFromM1: on first seeing a ticket (fresh entry     |
//|     OR an EA restart reattaching to an existing position), the trail    |
//|     peak is rebuilt from M1 bar history since POSITION_TIME instead     |
//|     of seeding it at the current price.                                 |
//|   - ATR is no longer used anywhere in this file - InpAtrPeriod,          |
//|     InpAtrSlMultiplier, and the ATR indicator handle are removed.        |
//|     Pip size uses the same cent-aware convention as EzyEA V2/V3           |
//|     (InpXAUUSDscPipPrice/InpStandardXAUUSDPipPrice, both default 0.10).   |
//|                                                                            |
//| Everything else (entries, trend filter, per-direction cap, drawdown        |
//| breaker, drawing) is byte-for-byte unchanged from EzyEA V1.                 |
//|                                                                               |
//| Distinct magic number (190011) and order-comment/object-prefix tags           |
//| (V11SND/V11EMA, V11_ chart objects) so this can run alongside V1/V2/          |
//| V3/V3.2/V3b/V4/V3(BTCUSD) without cross-talk.                                 |
//|                                                                                 |
//| CHANGELOG                                                                      |
//| 1.100 - Initial build: hybrid virtual-trail exit ported from EzyEA V3          |
//|         6.102, fixed pips (preset 30 / trail 15 / activation +10),             |
//|         ATR removed entirely. Forked from EzyEA_V1_XAUUSD.mq5 1.000.           |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "1.100"
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
input group "=== SND Level-Touch Entries: M5 -> Weekly, raw touch, no confluence ==="
input bool   InpEnableLevelTouchEntries     = true;
input double InpLevelTouchTolerancePoints   = 30.0;
input int    InpLevelReentrySeconds         = 20;
input int    InpLevelLookbackM5             = 24;
input int    InpLevelLookbackM15            = 32;
input int    InpLevelLookbackH1             = 24;
input int    InpLevelLookbackH4             = 15;
input int    InpLevelLookbackD1             = 8;
input int    InpLevelLookbackW1             = 5;

input group "=== EMA13 Touch Entries: M5, raw touch, no confluence ==="
// Zero-confluence, same philosophy as SND: price returning to touch the
// EMA from either side is treated as an immediate fade toward it, no
// reclaim/confirmation bar required. Direction is which side price
// approached FROM (previous tick's CMP vs the EMA), not a crossing/
// momentum signal - touch from above -> BUY (expect a bounce away from
// it), touch from below -> SELL.
input bool   InpEnableEmaTouchEntries       = true;
input int    InpEmaPeriod                   = 13;
input double InpEmaTouchTolerancePoints     = 30.0;
input int    InpEmaReentrySeconds           = 20;

input group "=== Trend Filter (H1 ADX) - blocks fades against a strong trend ==="
// Confirmed fix for the correlated-pile margin calls diagnosed on
// EzyEA V2: a zero-confluence system with no trend awareness fades the
// same direction repeatedly through a real trend, piling up correlated
// losers. Blocks ONLY a fade running directly against a confirmed
// strong H1 trend - does not change which mechanism generates entries.
input bool   InpEnableTrendFilter           = true;
input int    InpAdxPeriod                   = 14;
input double InpAdxTrendThreshold           = 25.0;

input group "=== Stops / Trail (fixed pips) ==="
// Ported from EzyEA V3's hybrid virtual-trail exit (this generation's
// A/B-tested winner), per explicit request, with a distinct pip
// preset: preset SL 30 pips, trailing 15 pips, trail arms once
// floating P&L reaches +10 pips. ATR is no longer used anywhere in
// this file for stops. Pip size uses the same cent-aware convention as
// EzyEA V2/V3 (InpXAUUSDscPipPrice/InpStandardXAUUSDPipPrice, both
// default 0.10 - the standard gold convention).
input double InpPresetStopLossPips          = 30.0;
input double InpTrailingDistancePips        = 15.0;
// Trail arms once floating P&L reaches this many pips in profit - the
// wide preset floor is the only protection until this threshold clears.
input double InpTrailActivationPips         = 10.0;
input double InpXAUUSDscPipPrice            = 0.10;
input double InpStandardXAUUSDPipPrice      = 0.10;
input double InpTrailMinStepPoints          = 20.0;

input group "=== Hybrid Virtual Trail ==="
// Real protection no longer depends on the broker accepting a tight SL
// modify(): a virtual stop (fixed-pip preset floor from entry, tightens
// to the fixed-pip trail distance once activation clears) is checked
// every tick in EA memory and the position is force-closed directly the
// instant price crosses it. The broker-side SL (via the existing
// backoff-protected ModifyPositionSafely) is still pushed as a best-
// effort backup net at a safe distance.
input bool   InpUseVirtualTrailFallback     = true;
input int    InpVirtualTrailCloseDeviationPts = 30;
// On first seeing a ticket (fresh entry OR EA restart onto an existing
// position), rebuild the trail peak from M1 bar history since
// POSITION_TIME instead of seeding it at the current price.
input bool   InpReconstructPeakFromM1       = true;

input group "=== Exit Management ==="
// Hard, unconditional force-close regardless of P&L - the direct fix for
// positions sitting open for an extended stretch the way V2's did. Set
// to 0 to disable (not recommended without another safety net in place).
input int    InpMaxHoldingMinutes           = 30;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) ==="
input bool   InpEnableDrawdownBreaker       = true;
input double InpMaxEquityDrawdownPct        = 10.0;
input double InpDrawdownResumeFactor        = 0.5;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade         = 0.25;
// EXPLICIT REQUEST, CONFIRMED KNOWING THE REAL-MONEY CONSEQUENCE: on a
// cent account, multiplies the risk budget by the cent divisor (e.g.
// 100x) so a "500 USC" account sizes trades the same as a "500 USD"
// account would - matching a Strategy Tester run using a same-raw-
// number standard-currency deposit. This makes REAL risk per trade
// roughly (divisor)x LARGER than InpRiskPercentPerTrade alone implies.
// Confirmed live on EzyEA V3 that turning this on then reverting it
// happened for real reasons - DEFAULTS FALSE here too. Only re-enable
// with a full understanding that it multiplies real per-trade risk by
// the divisor.
input bool   InpScaleRiskByCentDivisor      = false;
input int    InpMaxConcurrentPositions      = 500;
// Caps how many same-direction positions can pile up from repeated
// touches within the re-entry cooldown - the other half (alongside the
// trend filter) of the fix for the correlated-pile-crash mechanism.
input int    InpMaxConcurrentPerDirection   = 4;
input double InpMaxLotsAbsolute             = 5.0;
// Portfolio-aware (not per-trade-only) margin cap - basic execution
// correctness, not a strategic filter.
input double InpMaxMarginUsePct             = 40.0;
input bool   InpAllowMinimumLotFallback     = true;
input double InpMinimumLotFallbackMaxRiskPct = 1.0;

input group "=== Modify Backoff (TimeCurrent()-based, never GetTickCount64) ==="
input int    InpModifyBackoffBaseSeconds    = 2;
input int    InpModifyBackoffMaxSeconds     = 300;
input int    InpModifyMaxConsecutiveFail    = 6;

input group "=== Broker Minimum Distance ==="
input int    InpExecutionStopCushionPoints  = 10;
input double InpZeroStopsLevelFallbackPct   = 0.05;

input group "=== Spread Guard (auto-calibrating) ==="
input bool   InpAutoCalibrateSpreadCap      = true;
input int    InpSpreadCalibrationTicks      = 200;
input double InpSpreadCalibrationMultiplier = 2.5;
input int    InpMaxSpreadPoints             = 350;

input group "=== Cent-Account Handling ==="
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor      = 100.0;
input bool   InpTesterAutoModeIsStandard    = true;
input bool   InpTreatSCSuffixAsCentOnLive   = true;

input group "=== Execution ==="
input ulong  InpMagicNumber                 = 190011;
input int    InpDeviationPoints             = 30;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Chart Drawing ==="
input bool   InpDrawLevels                  = true;
input bool   InpDrawEma                     = true;
input bool   InpDrawStatusLabel             = true;
input int    InpDrawBarsBack                = 60;

//======================================================================
// Types
//======================================================================
struct ManagedPositionState
{
   ulong    ticket;
   int      consecutiveFailures;
   datetime cooldownUntil;
   double   peakPrice;
   double   virtualStop;       // tight logical stop, checked every tick, enforced by direct close
   bool     peakReconstructed;
};

struct LevelTouchState
{
   double   price;
   int      fadeDirection;   // 1 = demand (support), fade BUY; -1 = supply (resistance), fade SELL
   bool     inZone;
   datetime cooldownUntil;
   string   tfLabel;
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

int g_handleEmaM5 = INVALID_HANDLE;
int g_handleAdxH1 = INVALID_HANDLE;

datetime g_lastAdxH1BarTime = 0;
int      g_trendDirection   = 0;   // 1 up, -1 down, 0 no strong trend
double   g_lastAdxValue     = 0.0;

double g_peakEquity    = 0.0;
bool   g_tradingHalted = false;

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

// 6 timeframes (M5/M15/H1/H4/D1/W1) x 2 levels (swing high=supply,
// swing low=demand) each.
LevelTouchState g_levels[12];

datetime g_lastM5LevelBarTime  = 0;
datetime g_lastM15LevelBarTime = 0;
datetime g_lastH1LevelBarTime  = 0;
datetime g_lastH4LevelBarTime  = 0;
datetime g_lastD1LevelBarTime  = 0;
datetime g_lastW1LevelBarTime  = 0;

bool     g_emaInZone        = false;
datetime g_emaCooldownUntil = 0;

bool   g_hasPreviousCMP = false;
double g_previousCMP    = 0.0;

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
double PresetSlDistance();
double TrailDistance();
double TrailActivationDistance();
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
double ReconstructPeakFromM1(int direction,double entry,double current,datetime positionTime);
bool   CloseAtVirtualStop(ulong ticket,string context,double current,double stop,double peak);
void   ManageTrailing();
void   EnforceMaxHoldingTime();

void   RebuildLevelForTimeframe(int slotIndex,ENUM_TIMEFRAMES tf,int lookback,string tfLabel);
void   UpdateLevelsOnNewBars();
void   TryLevelEntry(int direction,double levelPrice);
void   CheckEmaTouch(double observedLo,double observedHi);
void   TryEmaEntry(int direction,double emaValue);
void   ProcessTouchTriggers();

void   DrawLevels();
void   DrawEmaLine();
void   DrawStatusLabel();
int    CountActiveLevels();
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
      Log("EzyEA V1.1 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   g_handleEmaM5 = iMA(_Symbol,PERIOD_M5,InpEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_handleAdxH1 = iADX(_Symbol,PERIOD_H1,InpAdxPeriod);
   if(g_handleEmaM5==INVALID_HANDLE || g_handleAdxH1==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed.");
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
      g_levels[i].cooldownUntil=0;
      g_levels[i].tfLabel="";
   }
   g_lastM5LevelBarTime  = 0;
   g_lastM15LevelBarTime = 0;
   g_lastH1LevelBarTime  = 0;
   g_lastH4LevelBarTime  = 0;
   g_lastD1LevelBarTime  = 0;
   g_lastW1LevelBarTime  = 0;

   g_emaInZone=false;
   g_emaCooldownUntil=0;

   g_hasPreviousCMP=false;
   g_previousCMP=0.0;

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted=false;

   Log("EzyEA V1.1 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions)+
       " (per-direction="+IntegerToString(InpMaxConcurrentPerDirection)+")"+
       " | max holding="+IntegerToString(InpMaxHoldingMinutes)+" min"+
       " | trend filter="+(InpEnableTrendFilter?"ON (ADX>="+DoubleToString(InpAdxTrendThreshold,0)+")":"OFF")+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF")+
       " | SND levels=M5/M15/H1/H4/D1/W1 (12) + EMA"+IntegerToString(InpEmaPeriod)+" (M5)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleEmaM5!=INVALID_HANDLE) IndicatorRelease(g_handleEmaM5);
   if(g_handleAdxH1!=INVALID_HANDLE) IndicatorRelease(g_handleAdxH1);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();
   UpdateTrendFilterOnNewH1Bar();

   if(InpEnableLevelTouchEntries || InpEnableEmaTouchEntries)
   {
      UpdateLevelsOnNewBars();
      ProcessTouchTriggers();
      DrawLevels();
      DrawEmaLine();
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

double PresetSlDistance()
{
   return MathMax(0.1,InpPresetStopLossPips)*StrategyPipSize();
}

double TrailDistance()
{
   return MathMax(0.1,InpTrailingDistancePips)*StrategyPipSize();
}

double TrailActivationDistance()
{
   return MathMax(0.0,InpTrailActivationPips)*StrategyPipSize();
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
   Print("EzyEA V1.1 | ",msg);
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
   // See InpScaleRiskByCentDivisor's declaration comment: this is a
   // deliberate, confirmed choice to size a cent account's trades as if
   // it had (divisor)x more real buying power than it actually does.
   double sizingEquity=(InpScaleRiskByCentDivisor)
                       ?equity*MathMax(1.0,g_accountUnitDivisor)
                       :equity;
   double riskBudget=sizingEquity*InpRiskPercentPerTrade/100.0;
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
      // Portfolio-level: usedMargin already reflects every other open
      // position, so the cap applies to usedMargin+this trade together,
      // not just this trade in isolation.
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
// entries (SND/EMA13 touches are still the only triggers) - it only
// blocks a fade that runs directly against a confirmed strong trend.
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
// Entry execution (shared by both trigger sources)
//======================================================================
void TryOpenPosition(int direction,string tag,double slDistance)
{
   g_gateAttempts++;

   if(g_tradingHalted)
   {
      g_gateDrawdownRejects++;
      return;
   }

   if(!TrendFilterAllows(direction))
   {
      g_gateTrendRejects++;
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
// SND level-touch entries: unchanged from V2. Levels only rebuild on
// their OWN timeframe's new bar close, never intra-bar.
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

   int supplyIdx=slotIndex*2;
   int demandIdx=slotIndex*2+1;

   g_levels[supplyIdx].price=RoundPrice(hi);
   g_levels[supplyIdx].fadeDirection=-1;
   g_levels[supplyIdx].inZone=false;
   g_levels[supplyIdx].cooldownUntil=0;
   g_levels[supplyIdx].tfLabel=tfLabel;

   g_levels[demandIdx].price=RoundPrice(lo);
   g_levels[demandIdx].fadeDirection=1;
   g_levels[demandIdx].inZone=false;
   g_levels[demandIdx].cooldownUntil=0;
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

void TryLevelEntry(int direction,double levelPrice)
{
   double slDistance=PresetSlDistance();
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V11SND",slDistance);
}

//======================================================================
// EMA13 touch entries: same zero-confluence philosophy as SND, but the
// reference is a moving M5 EMA read LIVE (shift=0, the forming bar's
// continuously-updating value) rather than a static level - an EMA is
// just a smoothed lagging price, not a bar pattern, so reading it live
// carries none of the repaint risk a bar-pattern signal would.
//======================================================================
void TryEmaEntry(int direction,double emaValue)
{
   double slDistance=PresetSlDistance();
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V11EMA",slDistance);
}

void CheckEmaTouch(double observedLo,double observedHi)
{
   if(!InpEnableEmaTouchEntries) return;

   double emaBuf[];
   if(CopyBufferSeries(g_handleEmaM5,0,1,emaBuf)<1) return;
   double emaValue=emaBuf[0];
   if(emaValue<=0.0) return;

   double tolerance=InpEmaTouchTolerancePoints*_Point;
   bool touching=(observedHi>=emaValue-tolerance && observedLo<=emaValue+tolerance);

   g_emaInZone=touching; // diagnostic only

   if(!touching) return;
   if(TimeCurrent()<g_emaCooldownUntil) return;
   if(!g_hasPreviousCMP) return;

   int direction=0;
   if(g_previousCMP>emaValue)      direction=1;  // was above, dipped to touch -> expect bounce up -> BUY
   else if(g_previousCMP<emaValue) direction=-1; // was below, rallied to touch -> expect rejection down -> SELL
   if(direction==0) return;                       // previous CMP sat exactly on the EMA - no clear side

   TryEmaEntry(direction,emaValue);
   g_emaCooldownUntil=TimeCurrent()+MathMax(0,InpEmaReentrySeconds);
}

//======================================================================
// Shared per-tick trigger processing: builds the tick envelope once
// (previous-vs-current-tick crossing check, proven this session to
// catch a fast move a single-tick snapshot would miss) and feeds it to
// both the SND level loop and the EMA touch check.
//======================================================================
void ProcessTouchTriggers()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double cmp=(tick.bid>0.0)?tick.bid:tick.last;
   if(cmp<=0.0) return;

   double observedLo=cmp, observedHi=cmp;
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
   if(g_hasPreviousCMP && g_previousCMP>0.0)
   {
      observedLo=MathMin(observedLo,g_previousCMP);
      observedHi=MathMax(observedHi,g_previousCMP);
   }

   if(InpEnableLevelTouchEntries)
   {
      double tolerance=InpLevelTouchTolerancePoints*_Point;

      for(int i=0;i<ArraySize(g_levels);i++)
      {
         if(g_levels[i].price<=0.0) continue;

         bool touching=(observedHi>=g_levels[i].price-tolerance &&
                        observedLo<=g_levels[i].price+tolerance);

         g_levels[i].inZone=touching; // diagnostic only

         if(!touching) continue;

         // Cooldown-only re-arm: no requirement to fully leave the zone
         // before re-firing, only InpLevelReentrySeconds gates it.
         if(TimeCurrent()<g_levels[i].cooldownUntil) continue;

         TryLevelEntry(g_levels[i].fadeDirection,g_levels[i].price);
         g_levels[i].cooldownUntil=TimeCurrent()+MathMax(0,InpLevelReentrySeconds);
      }
   }

   // Uses g_previousCMP for touch direction, so this must run BEFORE it
   // is overwritten by the current tick below.
   CheckEmaTouch(observedLo,observedHi);

   g_previousCMP=cmp;
   g_hasPreviousCMP=true;
}

//======================================================================
// Per-position management state (backoff + peak tracking)
//======================================================================
double ReconstructPeakFromM1(int direction,double entry,double current,datetime positionTime)
{
   double peak=current;

   if(!InpReconstructPeakFromM1 || positionTime<=0)
      return peak;

   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied=CopyRates(_Symbol,PERIOD_M1,positionTime,TimeCurrent(),rates);
   if(copied<=0)
      return peak;

   for(int i=0;i<copied;i++)
   {
      if(direction==1)
         peak=MathMax(peak,rates[i].high);
      else
         peak=MathMin(peak,rates[i].low);
   }

   if(direction==1)
      peak=MathMax(peak,entry);
   else
      peak=MathMin(peak,entry);

   return RoundPrice(peak);
}

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
      Log("VIRTUAL TRAIL CLOSE | "+context+
          " | ticket="+IntegerToString((int)ticket)+
          " | current="+PriceText(current)+
          " | virtualSL="+PriceText(stop)+
          " | peak="+PriceText(peak));
      return true;
   }

   Log("VIRTUAL TRAIL CLOSE FAILED | "+context+
       " | ticket="+IntegerToString((int)ticket)+
       " | current="+PriceText(current)+
       " | virtualSL="+PriceText(stop)+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());
   return false;
}

//======================================================================
// Exit 1: hybrid virtual trail, no TP. Real protection no longer
// depends on the broker accepting a tight SL modify() - a virtual stop
// is tracked in EA memory and checked every tick; the moment price
// crosses it the position is force-closed directly. The broker-side SL
// is still pushed via the existing backoff-protected
// ModifyPositionSafely as a best-effort backup net, clamped to
// whatever distance the broker will actually accept.
//
// Exit shape: a WIDE fixed-pip preset floor (PresetSlDistance(), 30p
// default) protects from entry, but the trail arms using a SEPARATE,
// TIGHTER fixed-pip distance (TrailDistance(), 15p default) once
// floating P&L reaches InpTrailActivationPips (10p default) in profit.
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

      int slot=EnsureManagedSlot(ticket);
      if(slot<0) continue;

      double slDistance=PresetSlDistance();
      if(slDistance<=0.0) continue;

      double trailDistance=TrailDistance();
      if(trailDistance<=0.0) trailDistance=slDistance;

      int direction=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      double openPrice   =PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl   =PositionGetDouble(POSITION_SL);
      double currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      if(direction==1)
         g_managed[slot].peakPrice=MathMax(g_managed[slot].peakPrice,currentPrice);
      else
         g_managed[slot].peakPrice=MathMin(g_managed[slot].peakPrice,currentPrice);

      double peak=g_managed[slot].peakPrice;
      // POSITION_PRICE_CURRENT is already the side the position would
      // close at (bid for a BUY, ask for a SELL), so favorable tracks
      // real floating P&L, not just "price moved" - spread is already
      // netted out.
      double favorable=(direction==1)?(peak-openPrice):(openPrice-peak);
      double activationDistance=TrailActivationDistance();

      // WIDE preset floor from entry - always the starting protection,
      // regardless of activation state.
      if(g_managed[slot].virtualStop<=0.0)
         g_managed[slot].virtualStop=RoundPrice((direction==1)?openPrice-slDistance:openPrice+slDistance);

      // Trail arms once floating P&L reaches InpTrailActivationPips in
      // profit. The TIGHT trailDistance candidate only actually improves
      // on the wide preset floor once peak has moved far enough to
      // overtake it - the monotonic "improves" comparison below handles
      // that transition naturally, no special-casing needed.
      if(favorable>=activationDistance)
      {
         double trailedStop=RoundPrice((direction==1)?peak-trailDistance:peak+trailDistance);
         bool trailedImproves=(direction==1)
                              ?(trailedStop>g_managed[slot].virtualStop)
                              :(trailedStop<g_managed[slot].virtualStop);
         if(trailedImproves)
            g_managed[slot].virtualStop=trailedStop;
      }

      double virtualStop=g_managed[slot].virtualStop;

      bool virtualHit=(direction==1)
                      ?currentPrice<=virtualStop+_Point*0.25
                      :currentPrice>=virtualStop-_Point*0.25;

      if(InpUseVirtualTrailFallback && virtualHit)
      {
         CloseAtVirtualStop(ticket,"ManageTrailing",currentPrice,virtualStop,peak);
         continue;
      }

      // Best-effort broker-side SL backup only from here - clamp to the
      // closest the broker will legally accept rather than skip
      // outright, so the backup net stays as tight as the broker allows
      // even when the true virtual stop is tighter still.
      double minDist=MinimumStopDistance(currentPrice);
      double brokerAllowed=(direction==1)?currentPrice-minDist:currentPrice+minDist;
      double desiredSl=(direction==1)
                       ?MathMin(virtualStop,brokerAllowed)
                       :MathMax(virtualStop,brokerAllowed);
      desiredSl=RoundPrice(desiredSl);

      bool improves=(currentSl<=0.0) ||
                    ((direction==1)?(desiredSl>currentSl):(desiredSl<currentSl));
      if(!improves) continue;

      double minStep=InpTrailMinStepPoints*_Point;
      if(currentSl>0.0 && MathAbs(desiredSl-currentSl)<minStep) continue;

      bool validSide=(direction==1)?(desiredSl<currentPrice):(desiredSl>currentPrice);
      if(!validSide) continue;

      ModifyPositionSafely(ticket,desiredSl,PositionGetDouble(POSITION_TP));
   }
}

//======================================================================
// Exit 2: hard, unconditional force-close once a position has been open
// InpMaxHoldingMinutes, regardless of P&L or whether the trail has
// resolved yet. Direct fix for positions sitting open for an extended
// stretch the way V2's did.
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
// Chart drawing (12 SND levels + EMA13 line + status label)
//======================================================================
void DrawLevels()
{
   if(!InpDrawLevels) return;

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      string name="V11_LVL_"+IntegerToString(i);
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
   if(!InpDrawEma) return;

   int bars=MathMax(3,InpDrawBarsBack);
   double emaBuf[];
   int n=CopyBufferSeries(g_handleEmaM5,0,bars,emaBuf);
   if(n<2) return;

   for(int shift=0;shift<n-1;shift++)
   {
      string name="V11_EMA_"+IntegerToString(shift);
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

int CountActiveLevels()
{
   int n=0;
   for(int i=0;i<ArraySize(g_levels);i++)
      if(g_levels[i].price>0.0) n++;
   return n;
}

void DrawStatusLabel()
{
   string name="V11_StatusLabel";
   string text=StringFormat("EzyEA V1.1 | SND active=%d/%d | EMA%d touch=%s | Open=%d/%d | trend=%s | %s",
                CountActiveLevels(),ArraySize(g_levels),
                InpEmaPeriod,(g_emaInZone?"IN-ZONE":"-"),
                CountOpenPositions(),InpMaxConcurrentPositions,
                (g_trendDirection==1?"UP":(g_trendDirection==-1?"DOWN":"NONE")),
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

void RemoveAllDrawings()
{
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,"V11_")==0)
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

   if(InpDrawStatusLabel) DrawStatusLabel();

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct =(g_peakEquity>0.0)?(g_peakEquity-equity)/g_peakEquity*100.0:0.0;
   string trendText=(g_trendDirection==1?"UP":(g_trendDirection==-1?"DOWN":"NONE"));

   Log("V1.1 LIVE PARITY STATUS"+
       " | SND active="+IntegerToString(CountActiveLevels())+"/"+IntegerToString(ArraySize(g_levels))+
       " | EMA"+IntegerToString(InpEmaPeriod)+" touch="+(g_emaInZone?"IN-ZONE":"-")+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
       " | adx="+DoubleToString(g_lastAdxValue,1)+" trend="+trendText+
       " | drawdown="+DoubleToString(ddPct,2)+"%"+(g_tradingHalted?" (HALTED)":"")+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY));

   Log("V1.1 DEPLOYMENT GATE BREAKDOWN"+
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

   Log("V1.1 FINAL REPORT"+
       " | trades="+IntegerToString(trades)+
       " | total lots traded="+DoubleToString(lotsTraded,2)+
       " | net P/L="+DoubleToString(netPnl,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
}
//+------------------------------------------------------------------+
