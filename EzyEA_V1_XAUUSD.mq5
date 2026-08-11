//+------------------------------------------------------------------+
//|                                             EzyEA_V1_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V1 (REBUILT) - per explicit instruction, the original ADX-  |
//| regime + Bollinger mean-reversion + EMA pullback-continuation      |
//| design is fully replaced with a single new trigger concept:        |
//| EMA13 / EMA47 / Pivot Point CONFLUENCE. When all three references  |
//| cluster within a small tolerance of each other on M5 and price      |
//| touches that cluster, the touch is FADED (mean-reversion), the      |
//| same "touch a reference, trade the reversion" philosophy already    |
//| proven this session for SND levels and single-EMA touches - just    |
//| applied to a 3-way confluence zone instead of one reference.        |
//|                                                                     |
//| This overwrites the original EzyEA V1 by explicit user confirmation |
//| (they were live-testing the old version on a 200 USC account and    |
//| were told clearly this would replace it before confirming).         |
//|                                                                     |
//| Everything else is the same proven infrastructure from this          |
//| session: risk-based lot sizing via OrderCalcProfit() with a          |
//| portfolio-aware margin check, ATR-based SL/trail-only exit with       |
//| the activation-floor rule and the trailing side-validation fix,       |
//| a hard max-holding-time exit, an overall peak-equity drawdown          |
//| breaker, TimeCurrent()-based modify backoff, the zero-stops-level      |
//| broker fallback, an auto-calibrating spread guard, and cent-account-   |
//| aware equity handling. The minimum-lot fallback defaults OFF, per       |
//| the lesson confirmed live on V4: it can make a risk% input dishonest    |
//| by silently trading at an inflated effective risk once the real          |
//| calculated size rounds below the broker minimum.                          |
//|                                                                             |
//| CHANGELOG                                                                   |
//| 1.000 (rebuild) - Initial build of the confluence-fade design.              |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "1.000"
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
input group "=== EMA13/EMA47/Pivot Confluence Entries: M5, fade the touch ==="
// "Overlap" = the spread between the highest and lowest of the three
// references is within InpConfluenceClusterTolerancePoints - i.e. all
// three are clustered close together. A touch of that cluster (price
// entering within InpConfluenceTouchTolerancePoints of it) is then
// FADED: touch from above -> expect a bounce back up -> BUY; touch from
// below -> expect a rejection back down -> SELL. Same envelope-crossing
// touch detection (previous-vs-current-tick) proven this session, so a
// fast move through the zone is never missed. Pivot is the classic
// daily formula (prevDayHigh+prevDayLow+prevDayClose)/3, recalculated
// only on a new D1 bar close, never intra-bar.
input bool   InpEnableConfluenceEntries      = true;
input int    InpEmaFastPeriod                = 13;
input int    InpEmaSlowPeriod                = 47;
input double InpConfluenceClusterTolerancePoints = 50.0;
input double InpConfluenceTouchTolerancePoints   = 30.0;
input int    InpConfluenceReentrySeconds     = 60;

input group "=== Stops / Trail (ATR-based, M5) ==="
input int    InpAtrPeriod                    = 14;
input double InpAtrSlMultiplier              = 1.5;
input double InpTrailMinStepPoints           = 20.0;

input group "=== Exit Management ==="
input int    InpMaxHoldingMinutes            = 60;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade          = 0.25;
input int    InpMaxConcurrentPositions       = 10;
input double InpMaxLotsAbsolute              = 5.0;
input double InpMaxMarginUsePct              = 40.0;
// Confirmed live on V4: leaving this on let a risk% input become
// dishonest once the real calculated lot rounded below the broker
// minimum - both a 1% and a 0.25% target quietly landed on the same
// floor size. Off by default here from day one instead of waiting to
// find the same bug again.
input bool   InpAllowMinimumLotFallback      = false;
input double InpMinimumLotFallbackMaxRiskPct = 1.0;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) ==="
input bool   InpEnableDrawdownBreaker        = true;
input double InpMaxEquityDrawdownPct         = 10.0;
input double InpDrawdownResumeFactor         = 0.5;

input group "=== Modify Backoff (TimeCurrent()-based, never GetTickCount64) ==="
input int    InpModifyBackoffBaseSeconds     = 5;
input int    InpModifyBackoffMaxSeconds      = 300;
input int    InpModifyMaxConsecutiveFail     = 6;

input group "=== Broker Minimum Distance ==="
input int    InpExecutionStopCushionPoints   = 10;
input double InpZeroStopsLevelFallbackPct    = 0.05;

input group "=== Spread Guard (auto-calibrating) ==="
input bool   InpAutoCalibrateSpreadCap       = true;
input int    InpSpreadCalibrationTicks       = 200;
input double InpSpreadCalibrationMultiplier  = 2.5;
input int    InpMaxSpreadPoints              = 350;

input group "=== Cent-Account Handling ==="
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor       = 100.0;
input bool   InpTesterAutoModeIsStandard     = true;
input bool   InpTreatSCSuffixAsCentOnLive    = true;

input group "=== Execution ==="
input ulong  InpMagicNumber                  = 190001;
input int    InpDeviationPoints              = 30;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds     = 60;

input group "=== Chart Drawing ==="
input bool   InpDrawReferences                = true;
input bool   InpDrawStatusLabel               = true;
input int    InpDrawBarsBack                  = 60;

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

int g_handleAtrM5     = INVALID_HANDLE;
int g_handleEmaFastM5 = INVALID_HANDLE;
int g_handleEmaSlowM5 = INVALID_HANDLE;

datetime g_lastPivotD1BarTime = 0;
double   g_pivotValue         = 0.0;

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

bool     g_confluenceInZone        = false;
datetime g_confluenceCooldownUntil = 0;

bool   g_hasPreviousCMP = false;
double g_previousCMP    = 0.0;

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

void   CloseAllPositions(string reason);
void   UpdateDrawdownBreaker();

void   TryOpenPosition(int direction,string tag,double slDistance);

int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
void   ManageTrailing();
void   EnforceMaxHoldingTime();

void   RecalculatePivotOnNewD1Bar();
void   TryConfluenceEntry(int direction);
void   CheckConfluenceTouch(double observedLo,double observedHi);
void   ProcessConfluenceTrigger();

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

   g_handleAtrM5     = iATR(_Symbol,PERIOD_M5,InpAtrPeriod);
   g_handleEmaFastM5 = iMA(_Symbol,PERIOD_M5,InpEmaFastPeriod,0,MODE_EMA,PRICE_CLOSE);
   g_handleEmaSlowM5 = iMA(_Symbol,PERIOD_M5,InpEmaSlowPeriod,0,MODE_EMA,PRICE_CLOSE);
   if(g_handleAtrM5==INVALID_HANDLE || g_handleEmaFastM5==INVALID_HANDLE || g_handleEmaSlowM5==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed.");
      return INIT_FAILED;
   }

   g_lastPivotD1BarTime=0;
   g_pivotValue=0.0;

   g_accountUnitDivisor = ResolveAccountUnitDivisor();

   int capacity = SpreadCalibrationTicksEffective();
   ArrayResize(g_spreadCalSamples,capacity);
   g_spreadCalCount        = 0;
   g_spreadCalEffectiveCap = -1.0;

   g_lastStatusLogTime = 0;

   ArrayResize(g_managed,0);

   g_confluenceInZone=false;
   g_confluenceCooldownUntil=0;

   g_hasPreviousCMP=false;
   g_previousCMP=0.0;

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted=false;

   Log("EzyEA V1 (confluence rebuild) initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions)+
       " | trigger=EMA"+IntegerToString(InpEmaFastPeriod)+"/EMA"+IntegerToString(InpEmaSlowPeriod)+"/Pivot confluence (M5)"+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF"));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAtrM5!=INVALID_HANDLE)     IndicatorRelease(g_handleAtrM5);
   if(g_handleEmaFastM5!=INVALID_HANDLE) IndicatorRelease(g_handleEmaFastM5);
   if(g_handleEmaSlowM5!=INVALID_HANDLE) IndicatorRelease(g_handleEmaSlowM5);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();
   RecalculatePivotOnNewD1Bar();

   if(InpEnableConfluenceEntries)
   {
      ProcessConfluenceTrigger();
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
// EMA13/EMA47/Pivot confluence entries. Pivot only rebuilds on its own
// D1 bar close, never intra-bar. EMA values are read LIVE (shift=0) -
// an EMA is a smoothed lagging price, not a bar pattern, so reading it
// live carries no repaint risk.
//======================================================================
void RecalculatePivotOnNewD1Bar()
{
   datetime d1=iTime(_Symbol,PERIOD_D1,0);
   if(d1==0 || d1==g_lastPivotD1BarTime) return;
   g_lastPivotD1BarTime=d1;

   double prevHigh =iHigh(_Symbol,PERIOD_D1,1);
   double prevLow  =iLow(_Symbol,PERIOD_D1,1);
   double prevClose=iClose(_Symbol,PERIOD_D1,1);
   if(prevHigh<=0.0 || prevLow<=0.0 || prevClose<=0.0) return;

   g_pivotValue=RoundPrice((prevHigh+prevLow+prevClose)/3.0);
}

void TryConfluenceEntry(int direction)
{
   double atrBuf[];
   if(CopyBufferSeries(g_handleAtrM5,0,3,atrBuf)<3) return;

   double slDistance=InpAtrSlMultiplier*atrBuf[1];
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V1CONF",slDistance);
}

void CheckConfluenceTouch(double observedLo,double observedHi)
{
   g_confluenceInZone=false;

   if(!InpEnableConfluenceEntries) return;
   if(g_pivotValue<=0.0) return;

   double emaFastBuf[],emaSlowBuf[];
   if(CopyBufferSeries(g_handleEmaFastM5,0,1,emaFastBuf)<1) return;
   if(CopyBufferSeries(g_handleEmaSlowM5,0,1,emaSlowBuf)<1) return;

   double emaFast=emaFastBuf[0];
   double emaSlow=emaSlowBuf[0];
   if(emaFast<=0.0 || emaSlow<=0.0) return;

   double clusterHi=MathMax(emaFast,MathMax(emaSlow,g_pivotValue));
   double clusterLo=MathMin(emaFast,MathMin(emaSlow,g_pivotValue));

   // All three references must be clustered together first - the actual
   // "confluence" condition - before a touch of that cluster means
   // anything.
   double clusterTolerance=InpConfluenceClusterTolerancePoints*_Point;
   if((clusterHi-clusterLo)>clusterTolerance) return;

   double touchTolerance=InpConfluenceTouchTolerancePoints*_Point;
   double zoneLo=clusterLo-touchTolerance;
   double zoneHi=clusterHi+touchTolerance;

   bool touching=(observedHi>=zoneLo && observedLo<=zoneHi);
   g_confluenceInZone=touching;

   if(!touching) return;
   if(TimeCurrent()<g_confluenceCooldownUntil) return;
   if(!g_hasPreviousCMP) return;

   int direction=0;
   if(g_previousCMP>clusterHi)      direction=1;  // was clearly above -> expect bounce up -> BUY
   else if(g_previousCMP<clusterLo) direction=-1; // was clearly below -> expect rejection down -> SELL
   if(direction==0) return; // was already inside the cluster - no clear approach side

   TryConfluenceEntry(direction);
   g_confluenceCooldownUntil=TimeCurrent()+MathMax(0,InpConfluenceReentrySeconds);
}

void ProcessConfluenceTrigger()
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

   CheckConfluenceTouch(observedLo,observedHi);

   g_previousCMP=cmp;
   g_hasPreviousCMP=true;
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
// Chart drawing (EMA13/EMA47/pivot references + status label)
//======================================================================
void DrawReferences()
{
   if(!InpDrawReferences) return;

   int bars=MathMax(3,InpDrawBarsBack);

   double emaFastBuf[];
   int nFast=CopyBufferSeries(g_handleEmaFastM5,0,bars,emaFastBuf);
   if(nFast>=2)
   {
      for(int shift=0;shift<nFast-1;shift++)
      {
         string name="V1_EMAFAST_"+IntegerToString(shift);
         datetime t1=iTime(_Symbol,PERIOD_M5,shift+1);
         datetime t2=iTime(_Symbol,PERIOD_M5,shift);
         if(t1==0 || t2==0) continue;

         if(ObjectFind(0,name)<0)
            ObjectCreate(0,name,OBJ_TREND,0,t1,emaFastBuf[shift+1],t2,emaFastBuf[shift]);
         else
         {
            ObjectMove(0,name,0,t1,emaFastBuf[shift+1]);
            ObjectMove(0,name,1,t2,emaFastBuf[shift]);
         }
         ObjectSetInteger(0,name,OBJPROP_COLOR,clrDodgerBlue);
         ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,name,OBJPROP_RAY,false);
         ObjectSetInteger(0,name,OBJPROP_BACK,true);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      }
   }

   double emaSlowBuf[];
   int nSlow=CopyBufferSeries(g_handleEmaSlowM5,0,bars,emaSlowBuf);
   if(nSlow>=2)
   {
      for(int shift=0;shift<nSlow-1;shift++)
      {
         string name="V1_EMASLOW_"+IntegerToString(shift);
         datetime t1=iTime(_Symbol,PERIOD_M5,shift+1);
         datetime t2=iTime(_Symbol,PERIOD_M5,shift);
         if(t1==0 || t2==0) continue;

         if(ObjectFind(0,name)<0)
            ObjectCreate(0,name,OBJ_TREND,0,t1,emaSlowBuf[shift+1],t2,emaSlowBuf[shift]);
         else
         {
            ObjectMove(0,name,0,t1,emaSlowBuf[shift+1]);
            ObjectMove(0,name,1,t2,emaSlowBuf[shift]);
         }
         ObjectSetInteger(0,name,OBJPROP_COLOR,clrOrange);
         ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,name,OBJPROP_RAY,false);
         ObjectSetInteger(0,name,OBJPROP_BACK,true);
         ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      }
   }

   string pivotName="V1_PIVOT";
   if(g_pivotValue>0.0)
   {
      if(ObjectFind(0,pivotName)<0)
         ObjectCreate(0,pivotName,OBJ_HLINE,0,0,g_pivotValue);

      ObjectSetDouble(0,pivotName,OBJPROP_PRICE,g_pivotValue);
      ObjectSetInteger(0,pivotName,OBJPROP_COLOR,clrYellow);
      ObjectSetInteger(0,pivotName,OBJPROP_STYLE,STYLE_DASH);
      ObjectSetInteger(0,pivotName,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,pivotName,OBJPROP_BACK,true);
      ObjectSetInteger(0,pivotName,OBJPROP_SELECTABLE,false);
   }
   else
      ObjectDelete(0,pivotName);

   if(InpDrawStatusLabel) DrawStatusLabel();
}

void DrawStatusLabel()
{
   string name="V1_StatusLabel";
   string text=StringFormat("EzyEA V1 | EMA%d/EMA%d/Pivot confluence=%s | Open=%d/%d | %s",
                InpEmaFastPeriod,InpEmaSlowPeriod,
                (g_confluenceInZone?"IN-ZONE":"-"),
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

   Log("V1 LIVE PARITY STATUS"+
       " | confluence="+(g_confluenceInZone?"IN-ZONE":"-")+
       " | pivot="+(g_pivotValue>0.0?PriceText(g_pivotValue):"n/a")+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
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
       " | drawdownRejects="+IntegerToString(g_gateDrawdownRejects));
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
