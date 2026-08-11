//+------------------------------------------------------------------+
//|                                             EzyEA_V1_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V1 - ground-up regime-aware XAUUSD scalper.                 |
//|                                                                    |
//| Built from scratch (no reused trading logic from the EzyMap V2/   |
//| V3/V4/V5 family, all of which were marked failed on live/tester   |
//| parity). Only proven, self-contained infrastructure patterns from |
//| that codebase are reused: cent-account equity scaling, risk-based |
//| lot sizing via OrderCalcProfit(), trade retcode classification    |
//| (including TRADE_RETCODE_MARKET_CLOSED), the zero-stops-level     |
//| broker fallback, an auto-calibrating spread guard, and a          |
//| TimeCurrent()-based (never GetTickCount64()) modify backoff -     |
//| GetTickCount64() reflects real CPU time, not simulated market     |
//| time, and produced meaningless cooldowns in the Strategy Tester   |
//| during the V5 build. All entry/exit/regime logic below is new.   |
//|                                                                    |
//| CHANGELOG                                                         |
//| 1.000 - Initial build. ADX(14) H1 regime read (RANGING<20,        |
//|         TRENDING>=20, direction via +DI/-DI). M5 entries gated    |
//|         by regime: Bollinger(20,2) mean-reversion when RANGING    |
//|         with a live-tracked middle-band TP, EMA20 pullback        |
//|         continuation when TRENDING with ATR-trail-only (no TP).   |
//|         ATR-based SL for both. 0.25% equity risk per trade, 4     |
//|         concurrent position cap, XAUUSD-only, cent-account aware. |
//| 1.001 - Fixed a real sizing bug found in the first live tester    |
//|         run: ComputeLotsForRisk() divided the risk budget by the  |
//|         cent-account divisor while OneLotLoss()/OrderCalcProfit() |
//|         stayed in raw account currency, undersizing every lot     |
//|         calc ~100x on a real cent (USC) account and silently      |
//|         zeroing every entry. Risk budget now stays raw/undivided  |
//|         to match OrderCalcProfit()'s units - EffectiveAccountEq-  |
//|         uity() is still used for status-log display only. Also   |
//|         split the single distanceRejects gate counter into        |
//|         distanceRejects (SL tighter than broker minimum) vs       |
//|         sizingRejects (computed lots rounded to 0), and added a   |
//|         Log() line with the actual numbers on every reject so the |
//|         next test run pinpoints the exact cause without guessing. |
//| 1.002 - Confirmed via the ENTRY REJECTED log added in 1.001: on a |
//|         $1000 account, XAUUSD's 100oz contract means the broker's |
//|         own 0.01 minimum lot can already risk more than 0.25% at  |
//|         a normal ATR-based SL width (e.g. an $8.75 SL already     |
//|         risks $8.75 at 0.01 lot = 0.875%), so risk-based sizing   |
//|         rounds to 0 and every trade gets rejected - not a code    |
//|         bug, a real small-account/contract-size constraint. Added|
//|         InpAllowMinimumLotFallback: when sizing rounds to 0, fall |
//|         back to the broker minimum lot instead of skipping the    |
//|         trade, but only if that lot's real risk stays under the   |
//|         explicit InpMinimumLotFallbackMaxRiskPct ceiling (default |
//|         1.0%) - restores trade frequency on a small account       |
//|         without silently exceeding the user's risk tolerance.     |
//| 1.003 - Confirmed live: trades now fire and the account was up    |
//|         (1135 vs 1000). Increased trade frequency: range entries  |
//|         now trigger off a wick piercing the Bollinger band (the   |
//|         common case) instead of requiring a full CLOSE beyond it, |
//|         while the entry itself still needs the confirmed close    |
//|         back inside, so nothing repaints. Trend entries dropped   |
//|         the redundant "closed higher than the prior bar" filter   |
//|         (the EMA reclaim on the close is already the real         |
//|         confirmation) and now accept a touch on either of the     |
//|         last two closed bars, not just the second-to-last one.    |
//|         Raised InpMaxConcurrentPositions 4->6 since a sustained    |
//|         trend can otherwise cap out on valid signals. Added        |
//|         WriteFinalReport(): total trades / total lots traded /    |
//|         net P/L from this EA's own deal history (by symbol+magic),|
//|         printed from OnDeinit() alongside the run's final balance.|
//| 1.004 - User asked for 30-70 lots/day on the $1000 tester account,|
//|         explicitly keeping risk-per-trade conservative (declined  |
//|         the V3/V4-style aggressive sizing tradeoff). At the       |
//|         0.01-lot floor that nearly every trade hits on this       |
//|         account size, that's a trade-COUNT target (~30-70         |
//|         trades/day), not a total-lot-volume one - 100 trades/day  |
//|         at 0.01 lots is still only 1.0 lot of volume. Pushed      |
//|         frequency further toward that: InpBandsDeviation 2.0->1.5 |
//|         (narrower bands = far more frequent wick touches for      |
//|         range entries), and widened the trend-entry EMA touch     |
//|         window from the last 2 closed bars to the last 3. Risk    |
//|         model, SL/TP structure, and position sizing untouched.    |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "1.004"
#property strict

#include <Trade/Trade.mqh>

//======================================================================
// Enums
//======================================================================
enum ENUM_EZY_REGIME
{
   REGIME_RANGING  = 0,
   REGIME_TRENDING = 1
};

enum ENUM_EZY_ACCOUNT_SCALE
{
   EZY_ACCOUNT_AUTO     = 0,
   EZY_ACCOUNT_STANDARD = 1,
   EZY_ACCOUNT_CENT     = 2
};

//======================================================================
// Inputs
//======================================================================
input group "=== Regime Detection (H1 ADX) ==="
input int    InpAdxPeriod                   = 14;
input double InpAdxTrendThreshold           = 20.0;

input group "=== Range Entries: M5 Bollinger Mean-Reversion ==="
input int    InpBandsPeriod                 = 20;
input double InpBandsDeviation              = 1.5;

input group "=== Trend Entries: M5 EMA20 Pullback Continuation ==="
input int    InpEmaPeriod                   = 20;

input group "=== Stops (ATR-based, both regimes) ==="
input int    InpAtrPeriod                   = 14;
input double InpAtrSlMultiplier             = 1.5;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade         = 0.25;
input int    InpMaxConcurrentPositions      = 6;
input double InpMaxLotsAbsolute             = 5.0;
// On a small account, the broker's minimum lot can itself risk more than
// InpRiskPercentPerTrade at a wide ATR-based SL (confirmed live: XAUUSD's
// 100oz contract makes even 0.01 lot risk ~$8.75 on an $8.75 SL, well over
// 0.25% of a $1000 account, which rounds risk-based sizing down to 0 lots
// and silently rejects the trade). When that happens, fall back to the
// broker minimum lot instead of skipping the trade - but only if that
// minimum lot's real risk still stays under this explicit ceiling.
input bool   InpAllowMinimumLotFallback       = true;
input double InpMinimumLotFallbackMaxRiskPct  = 1.0;
input double InpMaxMarginUsePct             = 40.0;

input group "=== Exit Management ==="
input double InpRangeTpMinStepPoints        = 20.0;
input double InpTrendTrailMinStepPoints     = 20.0;

input group "=== Modify Backoff (TimeCurrent()-based, never GetTickCount64) ==="
input int    InpModifyBackoffBaseSeconds    = 5;
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
input ulong  InpMagicNumber                 = 190001;
input int    InpDeviationPoints             = 30;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Chart Drawing ==="
input bool   InpDrawBands                   = true;
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
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

int g_handleAdxH1   = INVALID_HANDLE;
int g_handleBandsM5 = INVALID_HANDLE;
int g_handleEmaM5   = INVALID_HANDLE;
int g_handleAtrM5   = INVALID_HANDLE;

datetime g_lastH1BarTime = 0;
datetime g_lastM5BarTime = 0;

ENUM_EZY_REGIME g_regime         = REGIME_RANGING;
int             g_trendDirection = 0;   // 1 up, -1 down, 0 undetermined
double          g_lastAdxValue   = 0.0;

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
double ComputeLotsForRisk(int direction,double entry,double sl);

bool   TradeRetcodeAccepted(uint code);
bool   TemporaryTradeRetcode(uint code);

double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel);
double MinimumStopDistance(double referencePrice);

int    SpreadCalibrationTicksEffective();
double MedianOfSpreadSamples(double &values[],int count);
bool   SpreadAllowed();

int    CountOpenPositions();

int    CopyBufferSeries(int handle,int bufferIndex,int count,double &out[]);
void   UpdateRegimeOnNewH1Bar();
bool   UpdateOnNewM5Bar();
bool   EvaluateRangeEntry(int &direction);
bool   EvaluateTrendEntry(int &direction);
void   EvaluateEntries();
void   TryOpenPosition(int direction,string tag,double slDistance,double initialTp);

int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
void   UpdateRangeTakeProfits();
void   ManageTrendTrailing();

void   DrawSeriesLine(string prefix,double &values[],color clr);
void   DrawStatusLabel();
void   DrawChart();
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

   g_handleAdxH1   = iADX(_Symbol,PERIOD_H1,InpAdxPeriod);
   g_handleBandsM5 = iBands(_Symbol,PERIOD_M5,InpBandsPeriod,0,InpBandsDeviation,PRICE_CLOSE);
   g_handleEmaM5   = iMA(_Symbol,PERIOD_M5,InpEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_handleAtrM5   = iATR(_Symbol,PERIOD_M5,InpAtrPeriod);

   if(g_handleAdxH1==INVALID_HANDLE || g_handleBandsM5==INVALID_HANDLE ||
      g_handleEmaM5==INVALID_HANDLE || g_handleAtrM5==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed.");
      return INIT_FAILED;
   }

   g_accountUnitDivisor = ResolveAccountUnitDivisor();

   int capacity = SpreadCalibrationTicksEffective();
   ArrayResize(g_spreadCalSamples,capacity);
   g_spreadCalCount        = 0;
   g_spreadCalEffectiveCap = -1.0;

   g_lastH1BarTime    = 0;
   g_lastM5BarTime    = 0;
   g_lastStatusLogTime= 0;

   ArrayResize(g_managed,0);

   Log("EzyEA V1 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAdxH1!=INVALID_HANDLE)   IndicatorRelease(g_handleAdxH1);
   if(g_handleBandsM5!=INVALID_HANDLE) IndicatorRelease(g_handleBandsM5);
   if(g_handleEmaM5!=INVALID_HANDLE)   IndicatorRelease(g_handleEmaM5);
   if(g_handleAtrM5!=INVALID_HANDLE)   IndicatorRelease(g_handleAtrM5);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateRegimeOnNewH1Bar();

   bool newM5=UpdateOnNewM5Bar();
   if(newM5)
   {
      PruneManagedSlots();
      EvaluateEntries();
      UpdateRangeTakeProfits();
      DrawChart();
   }

   ManageTrendTrailing();
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

   // AUTO: Strategy Tester deposits are normally entered in standard
   // account currency even when the tested symbol carries a .sc suffix.
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
   // Risk budget must stay in the SAME raw account-currency units that
   // OrderCalcProfit() (via OneLotLoss below) returns. EffectiveAccountEquity()
   // divides by the cent-account divisor purely for human-readable status
   // logging - dividing it here while perLotLoss stays undivided undersized
   // every lot calculation ~100x on a real cent account and silently zeroed
   // every entry attempt (confirmed live: 23/23 attempts, 0 trades, on a
   // USC-denominated account).
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
      if(equity>0.0 && marginRequired>0.0 && (marginRequired/equity)*100.0>InpMaxMarginUsePct)
      {
         double scale=(InpMaxMarginUsePct/100.0*equity)/marginRequired;
         lots=NormalizeVolumeDown(lots*scale);
      }

      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(marginRequired>freeMargin)
         lots=0.0;
   }

   return NormalizeVolumeDown(lots);
}

//======================================================================
// Retcode classification (includes TRADE_RETCODE_MARKET_CLOSED, missing
// from every prior EA in this codebase until this session's fixes)
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

//======================================================================
// Indicator buffer helper. Buffers are read as-series so out[shift]
// matches the shift language used throughout the regime/entry logic
// below (shift 0 = forming bar, never used for a signal; shift 1 =
// last closed bar; shift 2 = the bar before it).
//======================================================================
int CopyBufferSeries(int handle,int bufferIndex,int count,double &out[])
{
   ArraySetAsSeries(out,true);
   int copied=CopyBuffer(handle,bufferIndex,0,count,out);
   if(copied<=0) return 0;
   return copied;
}

//======================================================================
// Regime read (H1, once per new bar close)
//======================================================================
void UpdateRegimeOnNewH1Bar()
{
   datetime t=iTime(_Symbol,PERIOD_H1,0);
   if(t==0 || t==g_lastH1BarTime) return;
   g_lastH1BarTime=t;

   double adxBuf[],plusBuf[],minusBuf[];
   if(CopyBufferSeries(g_handleAdxH1,0,3,adxBuf)<3)   return;
   if(CopyBufferSeries(g_handleAdxH1,1,3,plusBuf)<3)  return;
   if(CopyBufferSeries(g_handleAdxH1,2,3,minusBuf)<3) return;

   double adx    =adxBuf[1];
   double plusDI =plusBuf[1];
   double minusDI=minusBuf[1];

   g_lastAdxValue=adx;
   g_regime=(adx>=InpAdxTrendThreshold)?REGIME_TRENDING:REGIME_RANGING;
   g_trendDirection=(plusDI>minusDI)?1:((minusDI>plusDI)?-1:0);
}

//======================================================================
// Entry evaluation (M5, once per new bar close)
//======================================================================
bool UpdateOnNewM5Bar()
{
   datetime t=iTime(_Symbol,PERIOD_M5,0);
   if(t==0 || t==g_lastM5BarTime) return false;
   g_lastM5BarTime=t;
   return true;
}

bool EvaluateRangeEntry(int &direction)
{
   double upperBuf[],lowerBuf[];
   if(CopyBufferSeries(g_handleBandsM5,1,3,upperBuf)<3) return false;
   if(CopyBufferSeries(g_handleBandsM5,2,3,lowerBuf)<3) return false;

   double close1=iClose(_Symbol,PERIOD_M5,1);
   double high2 =iHigh(_Symbol,PERIOD_M5,2);
   double low2  =iLow(_Symbol,PERIOD_M5,2);

   // A wick piercing the band is a far more common event than a full close
   // beyond it, so the "outside" leg uses the high/low; the entry itself
   // still requires the confirmed CLOSE back inside, so nothing repaints.

   // Wicked above the upper band, closed back inside -> SELL toward the mean.
   if(high2>upperBuf[2] && close1<=upperBuf[1])
   {
      direction=-1;
      return true;
   }

   // Wicked below the lower band, closed back inside -> BUY toward the mean.
   if(low2<lowerBuf[2] && close1>=lowerBuf[1])
   {
      direction=1;
      return true;
   }

   return false;
}

bool EvaluateTrendEntry(int &direction)
{
   if(g_trendDirection==0) return false;

   double emaBuf[];
   if(CopyBufferSeries(g_handleEmaM5,0,4,emaBuf)<4) return false;

   double close1=iClose(_Symbol,PERIOD_M5,1);
   double low1  =iLow(_Symbol,PERIOD_M5,1);
   double high1 =iHigh(_Symbol,PERIOD_M5,1);
   double low2  =iLow(_Symbol,PERIOD_M5,2);
   double high2 =iHigh(_Symbol,PERIOD_M5,2);
   double low3  =iLow(_Symbol,PERIOD_M5,3);
   double high3 =iHigh(_Symbol,PERIOD_M5,3);

   if(g_trendDirection==1)
   {
      // Pulled back to/through EMA20 against the uptrend (on any of the
      // last three closed bars) and reclaimed it on the close -> continuation
      // BUY. Dropped the extra "closed higher than the prior bar" filter -
      // the EMA reclaim on the close is already the real confirmation, and
      // requiring both roughly halved how often a valid pullback qualified.
      if((low3<=emaBuf[3] || low2<=emaBuf[2] || low1<=emaBuf[1]) && close1>emaBuf[1])
      {
         direction=1;
         return true;
      }
   }
   else
   {
      if((high3>=emaBuf[3] || high2>=emaBuf[2] || high1>=emaBuf[1]) && close1<emaBuf[1])
      {
         direction=-1;
         return true;
      }
   }

   return false;
}

void EvaluateEntries()
{
   double atrBuf[];
   if(CopyBufferSeries(g_handleAtrM5,0,3,atrBuf)<3) return;

   double slDistance=InpAtrSlMultiplier*atrBuf[1];
   if(slDistance<=0.0) return;

   int direction=0;

   if(g_regime==REGIME_RANGING)
   {
      if(!EvaluateRangeEntry(direction)) return;

      double baseBuf[];
      double initialTp=0.0;
      if(CopyBufferSeries(g_handleBandsM5,0,3,baseBuf)>=3)
         initialTp=RoundPrice(baseBuf[1]);

      TryOpenPosition(direction,"V1R",slDistance,initialTp);
   }
   else
   {
      if(!EvaluateTrendEntry(direction)) return;
      TryOpenPosition(direction,"V1T",slDistance,0.0);
   }
}

void TryOpenPosition(int direction,string tag,double slDistance,double initialTp)
{
   g_gateAttempts++;

   if(CountOpenPositions()>=InpMaxConcurrentPositions)
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

   // Defer TP attachment rather than widening it - it will be added by
   // UpdateRangeTakeProfits() on the next M5 bar once it clears distance.
   double tp=initialTp;
   if(tp>0.0 && MathAbs(entry-tp)<minDist)
      tp=0.0;

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
             ? trade.Buy(lots,_Symbol,0.0,sl,tp,tag)
             : trade.Sell(lots,_Symbol,0.0,sl,tp,tag);

   uint retcode=trade.ResultRetcode();

   if(sent && TradeRetcodeAccepted(retcode))
   {
      g_gateAccepted++;
      Log("ENTRY "+tag+" dir="+IntegerToString(direction)+
          " lots="+DoubleToString(lots,2)+
          " entry="+PriceText(entry)+
          " sl="+PriceText(sl)+
          " tp="+(tp>0.0?PriceText(tp):"none"));
   }
   else
   {
      g_gateRejected++;
      Log("ENTRY REJECTED "+tag+" retcode="+IntegerToString(retcode)+
          " desc="+trade.ResultRetcodeDescription());
   }
}

//======================================================================
// Per-position management state (backoff + trend peak tracking)
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
// RANGING exit: TP tracks the live (last closed bar) middle band
//======================================================================
void UpdateRangeTakeProfits()
{
   double baseBuf[];
   if(CopyBufferSeries(g_handleBandsM5,0,3,baseBuf)<3) return;
   double middle=RoundPrice(baseBuf[1]);

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,"V1R")!=0) continue;

      double currentTp=PositionGetDouble(POSITION_TP);
      double minStep=InpRangeTpMinStepPoints*_Point;
      if(currentTp>0.0 && MathAbs(middle-currentTp)<minStep) continue;

      double currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);
      double minDist=MinimumStopDistance(currentPrice);
      if(MathAbs(middle-currentPrice)<minDist) continue;

      ModifyPositionSafely(ticket,PositionGetDouble(POSITION_SL),middle);
   }
}

//======================================================================
// TRENDING exit: trail-only, activates once favourable excursion has
// run the full SL distance (never sooner - the activation-floor rule
// proven this session on the FRESH V3/V4 family).
//======================================================================
void ManageTrendTrailing()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      if(StringFind(comment,"V1T")!=0) continue;

      int direction=((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?1:-1;
      double openPrice   =PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl   =PositionGetDouble(POSITION_SL);
      double currentPrice=PositionGetDouble(POSITION_PRICE_CURRENT);

      double slDistance=MathAbs(openPrice-currentSl);
      if(slDistance<=0.0) continue;

      int slot=EnsureManagedSlot(ticket);
      if(slot<0) continue;

      if(direction==1)
         g_managed[slot].peakPrice=MathMax(g_managed[slot].peakPrice,currentPrice);
      else
         g_managed[slot].peakPrice=MathMin(g_managed[slot].peakPrice,currentPrice);

      double favorable=(direction==1)
                       ?(g_managed[slot].peakPrice-openPrice)
                       :(openPrice-g_managed[slot].peakPrice);

      if(favorable<slDistance) continue;

      double candidateSl=RoundPrice((direction==1)
                         ?g_managed[slot].peakPrice-slDistance
                         :g_managed[slot].peakPrice+slDistance);

      bool improves=(direction==1)?(candidateSl>currentSl):(candidateSl<currentSl);
      if(!improves) continue;

      double minStep=InpTrendTrailMinStepPoints*_Point;
      if(MathAbs(candidateSl-currentSl)<minStep) continue;

      double minDist=MinimumStopDistance(currentPrice);
      if(MathAbs(currentPrice-candidateSl)<minDist) continue;

      ModifyPositionSafely(ticket,candidateSl,PositionGetDouble(POSITION_TP));
   }
}

//======================================================================
// Chart drawing (live bands/EMA + regime status label)
//======================================================================
void DrawSeriesLine(string prefix,double &values[],color clr)
{
   int n=ArraySize(values);
   for(int shift=0;shift<n-1;shift++)
   {
      string name=prefix+"_"+IntegerToString(shift);
      datetime t1=iTime(_Symbol,PERIOD_M5,shift+1);
      datetime t2=iTime(_Symbol,PERIOD_M5,shift);
      double p1=values[shift+1];
      double p2=values[shift];
      if(t1==0 || t2==0) continue;

      if(ObjectFind(0,name)<0)
         ObjectCreate(0,name,OBJ_TREND,0,t1,p1,t2,p2);
      else
      {
         ObjectMove(0,name,0,t1,p1);
         ObjectMove(0,name,1,t2,p2);
      }

      ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
      ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,name,OBJPROP_RAY,false);
      ObjectSetInteger(0,name,OBJPROP_BACK,true);
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   }
}

void DrawStatusLabel()
{
   string name="V1_StatusLabel";
   string text=StringFormat("EzyEA V1 | Regime=%s | ADX=%.1f | Dir=%s | Open=%d/%d",
                (g_regime==REGIME_TRENDING?"TRENDING":"RANGING"),
                g_lastAdxValue,
                (g_trendDirection==1?"UP":(g_trendDirection==-1?"DOWN":"-")),
                CountOpenPositions(),InpMaxConcurrentPositions);

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

void DrawChart()
{
   int bars=MathMax(3,InpDrawBarsBack);

   if(InpDrawBands)
   {
      double upperBuf[],baseBuf[],lowerBuf[];
      int nU=CopyBufferSeries(g_handleBandsM5,1,bars,upperBuf);
      int nB=CopyBufferSeries(g_handleBandsM5,0,bars,baseBuf);
      int nL=CopyBufferSeries(g_handleBandsM5,2,bars,lowerBuf);

      if(nU>=2) DrawSeriesLine("V1_UpperBand",upperBuf,clrDodgerBlue);
      if(nB>=2) DrawSeriesLine("V1_BaseBand",baseBuf,clrSilver);
      if(nL>=2) DrawSeriesLine("V1_LowerBand",lowerBuf,clrDodgerBlue);
   }

   if(InpDrawEma)
   {
      double emaBuf[];
      int nE=CopyBufferSeries(g_handleEmaM5,0,bars,emaBuf);
      if(nE>=2) DrawSeriesLine("V1_Ema20",emaBuf,clrOrange);
   }

   if(InpDrawStatusLabel)
      DrawStatusLabel();
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

   Log("V1 LIVE PARITY STATUS"+
       " | regime="+(g_regime==REGIME_TRENDING?"TRENDING":"RANGING")+
       " | adx="+DoubleToString(g_lastAdxValue,1)+
       " | dir="+(g_trendDirection==1?"UP":(g_trendDirection==-1?"DOWN":"-"))+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY));

   Log("V1 DEPLOYMENT GATE BREAKDOWN"+
       " | attempts="+IntegerToString(g_gateAttempts)+
       " | accepted="+IntegerToString(g_gateAccepted)+
       " | rejected="+IntegerToString(g_gateRejected)+
       " | spreadRejects="+IntegerToString(g_gateSpreadRejects)+
       " | concurrencyRejects="+IntegerToString(g_gateConcurrencyRejects)+
       " | distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " | sizingRejects="+IntegerToString(g_gateSizingRejects));
}

// Summarizes this EA's own deal history (by symbol+magic, so it never
// picks up manual or other-EA trades sharing the account) at shutdown -
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
