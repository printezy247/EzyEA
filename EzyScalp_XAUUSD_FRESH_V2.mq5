//+------------------------------------------------------------------+
//| EzyScalp XAUUSD FRESH V2                                         |
//| Same proven risk/sizing/safety scaffold as FRESH V1 (flat        |
//| proportional sizing, auto-calibrating spread guard, tester-safe  |
//| cent-account handling, daily circuit breaker, order-rate         |
//| throttle, ATR-relative exits with a profit-gated trail,          |
//| performance reporting) - none of that was criticized and none of |
//| it changed here.                                                 |
//|                                                                   |
//| WHAT'S NEW: the entry signal. V1 used a single-timeframe momentum |
//| breakout. V2 replaces it with the core mean-reversion-at-         |
//| structure logic from the user's own EzyMap V3.140 EA (H4 SNR ->   |
//| M15 zone -> M3 reversal -> M5 READY lineage), simplified to its   |
//| essential mechanism rather than ported wholesale:                 |
//|   1. H1 bias: EMA(13) vs H1 close.                                 |
//|   2. Levels: the nearest H1 CLOSE below price (support) and the   |
//|      nearest H1 CLOSE above price (resistance), scanning the last |
//|      InpDirectionHistory H1 bars - the original's approach, not   |
//|      a full swing-pivot reconstruction.                           |
//|   3. Zone: a price band around each level, sized from live M15    |
//|      ATR (never a fixed pip guess - the same lesson V1 learned).  |
//|   4. Entry: an M5 candle that touched the zone, with price having |
//|      since moved back out of it in the trade's favour, and that   |
//|      candle's own close confirming the same direction (a          |
//|      retest-and-reject pattern). Both trend-following AND         |
//|      counter-trend retests are valid setups (InpAllowCounterTrend,|
//|      default true) - this matches the original's dual-route       |
//|      design and keeps signal frequency high, consistent with the  |
//|      volume-maximization objective from V1.                       |
//|                                                                   |
//| ALSO FIXED (v1.04 regression, carried forward as a lesson): V1.04 |
//| gated BOTH new entries and trailing-stop modifications behind the |
//| SAME global order-rate throttle timestamp. With up to 15          |
//| concurrent positions each eligible for a trail update on any tick |
//| their profit improved, frequent modify calls could consume the    |
//| shared throttle budget and silently block that bar's ONE entry    |
//| attempt - a likely explanation for v1.04 trading less than v1.03. |
//| The throttle here applies ONLY to new position opens. Trailing-   |
//| stop updates are not rate-limited: they only ever make an         |
//| existing position's protection tighter (never open new risk), and |
//| delaying a protective update to respect a shared budget is not a  |
//| trade-off worth making for the exact class of problem the         |
//| throttle exists to prevent (uncontrolled NEW-position spam).      |
//+------------------------------------------------------------------+
#property copyright "EzyScalp"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================== ACCOUNT / SIZING =============================
// Identical to FRESH V1 - see that file's header for the full reasoning.
enum ENUM_EZS_ACCOUNT_SCALE
{
   EZS_ACCOUNT_AUTO     = 0,
   EZS_ACCOUNT_STANDARD = 1,
   EZS_ACCOUNT_CENT     = 2
};

input group "=== Account / Sizing ==="
input ENUM_EZS_ACCOUNT_SCALE InpAccountScaleMode = EZS_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor  = 100.0;
input bool   InpTesterAutoModeIsStandard = true;

// Sizing rule, verbatim from the user's own specification: 100 (USD or USC)
// equity uses 0.01 lot as the baseline, floored below and scaled linearly
// above. No confidence tier, no per-signal multiplier.
input double InpBaseEquity = 100.0;
input double InpBaseLot    = 0.01;

//====================== DAILY RISK CIRCUIT BREAKER ====================
input group "=== Daily Risk ==="
input double InpDailyLossStopPct   = 75.0;
input bool   InpCloseAllAtDailyStop = false;

//====================== ORDER-RATE THROTTLE (entries only) =============
// See the header note: v1.04 throttled both opens and trailing-stop
// modifications off one shared timestamp, which could starve the day's one
// per-bar entry attempt whenever a trail update fired moments earlier.
// This version throttles ONLY new position opens - the actual failure mode
// the throttle exists for (uncontrolled entry spam, per the EzyMap V3.184
// incident) has nothing to do with how fast an existing position's stop
// tightens.
input group "=== Order-Rate Throttle (entries only) ==="
input int    InpMinMsBetweenEntryRequests = 250;

double g_lastEntryRequestMs = 0;

bool EntryRequestThrottleOK()
{
   double nowMs=(double)GetTickCount64();
   if(g_lastEntryRequestMs>0.0 &&
      nowMs-g_lastEntryRequestMs<(double)MathMax(0,InpMinMsBetweenEntryRequests))
      return false;

   g_lastEntryRequestMs=nowMs;
   return true;
}

//====================== SPREAD GUARD (auto-calibrating) ===============
input group "=== Spread Guard ==="
input int    InpSpreadCalibrationTicks      = 100;
input double InpSpreadCalibrationMultiplier = 3.0;
input int    InpSpreadCeilingPoints         = 0;

//====================== ENTRY - ZONE RETEST ============================
input group "=== Entry: Zone Retest ==="
input ENUM_TIMEFRAMES InpDirectionTimeframe = PERIOD_H1;
input int    InpDirectionHistory   = 48;
input int    InpBiasEMAPeriod      = 13;

input ENUM_TIMEFRAMES InpZoneTimeframe = PERIOD_M15;
input int    InpZoneATRPeriod      = 14;
// Zone half-width = M15 ATR * this. Self-scales with live volatility -
// never a fixed pip guess, the same lesson learned building V1.
input double InpZoneATRMultiplier  = 0.90;

input ENUM_TIMEFRAMES InpEntryTimeframe = PERIOD_M5;
input int    InpEntryHistory       = 24;
// Require the touching M5 candle's own close to confirm the retest
// direction (bullish close at a support touch, bearish at resistance).
// false = accept any qualifying zone touch regardless of that candle's
// close - materially more signals, materially less selective.
input bool   InpRequireDirectionalCandle = true;

// The original EzyMap lineage allows BOTH a trend-following retest (bias
// agrees with the zone side) and a counter-trend retest (bias disagrees) -
// two distinct, both-valid setups, not one filtered out as noise. Default
// true, consistent with the volume-maximization objective from V1 (V1's
// H1 trend filter cut roughly half of all candidate signals and was
// switched off for exactly this reason).
input bool   InpAllowCounterTrend  = true;

input int    InpMaxConcurrentPositions = 15;
input int    InpMagicNumber = 20260810;

//====================== EXIT - ATR STOP / TARGET / TRAIL ===============
// Unchanged mechanism from V1 - ATR-relative, never a fixed pip guess, and
// a trail that only arms on real floating profit. Priced off the ENTRY
// timeframe's ATR (M5 by default) since that is now the timeframe the
// actual fill happens on.
input group "=== Exit ==="
input int    InpATRPeriod           = 14;
input double InpATRStopMultiplier   = 1.2;
input double InpRewardRiskMultiple  = 1.2;
input double InpATRTrailMultiplier  = 0.8;

//====================== GLOBALS ========================================
double   g_accountUnitDivisor = 1.0;
int      g_exitAtrHandle      = INVALID_HANDLE; // entry-timeframe ATR, for stop/target/trail
int      g_zoneAtrHandle      = INVALID_HANDLE; // zone-timeframe ATR, for zone width
int      g_biasEmaHandle      = INVALID_HANDLE; // direction-timeframe EMA, for H1 bias

double   g_spreadCalSamples[];
int      g_spreadCalCount        = 0;
double   g_spreadCalEffectiveCap = -1.0;

int      g_dailyDateKey     = 0;
double   g_dayStartEquity   = 0.0;
double   g_dayLossFloor     = 0.0;
bool     g_dayTradingLocked = false;

datetime g_lastSignalBarTime = 0;
datetime g_eaStartTime       = 0;

//====================== ACCOUNT / CENT HELPERS =========================
string Upper(string s) { StringToUpper(s); return s; }

bool IsBTC()
{
   string s=Upper(_Symbol);
   return (StringFind(s,"BTC")>=0 || StringFind(s,"XBT")>=0);
}

bool IsGold()
{
   string s=Upper(_Symbol);
   return (StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0);
}

double StrategyPipSize()
{
   if(IsGold()) return MathMax(0.10,_Point);
   if(IsBTC())  return MathMax(1.0,_Point);
   return _Point;
}

double ResolveAccountUnitDivisor()
{
   if(InpAccountScaleMode==EZS_ACCOUNT_STANDARD)
      return 1.0;

   double configured=MathMax(1.0,InpCentAccountUnitDivisor);

   if(InpAccountScaleMode==EZS_ACCOUNT_CENT)
      return configured;

   if((bool)MQLInfoInteger(MQL_TESTER) && InpTesterAutoModeIsStandard)
      return 1.0;

   string currency=Upper(AccountInfoString(ACCOUNT_CURRENCY));
   string server  =Upper(AccountInfoString(ACCOUNT_SERVER));
   string company =Upper(AccountInfoString(ACCOUNT_COMPANY));
   string symbol  =Upper(_Symbol);

   bool centCurrency=(currency=="USC" || currency=="USCENT" ||
                      StringFind(currency,"CENT")>=0);
   bool centBrand=(StringFind(server,"CENT")>=0 ||
                   StringFind(company,"CENT")>=0);
   bool centSuffix=(StringFind(symbol,".SC")>=0 ||
                    StringFind(symbol,"_SC")>=0 ||
                    StringFind(symbol,"CENT")>=0);

   return (centCurrency || centBrand || centSuffix)?configured:1.0;
}

double EffectiveAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY)/MathMax(1.0,g_accountUnitDivisor);
}

//====================== SIZING ==========================================
double NormalizeVolumeDown(double vol)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

   if(step<=0) step=minVol;
   if(step<=0) return 0.0;

   double steps=MathFloor((vol+1e-9)/step);
   double v=steps*step;

   if(v<minVol) return 0.0;
   if(maxVol>0 && v>maxVol) v=maxVol;

   int digits=0;
   double s=step;
   while(s<0.999999 && digits<8) { s*=10.0; digits++; }

   return NormalizeDouble(v,digits);
}

double LotForEquity()
{
   double equity=EffectiveAccountEquity();
   double baseEquity=MathMax(1.0,InpBaseEquity);
   double effective=MathMax(baseEquity,equity);
   double scale=effective/baseEquity;
   double lot=MathMax(0.0,InpBaseLot)*scale;
   return NormalizeVolumeDown(lot);
}

//====================== SPREAD GUARD ====================================
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

      if(InpSpreadCeilingPoints>0)
         effective=MathMin(effective,(double)InpSpreadCeilingPoints);

      g_spreadCalEffectiveCap=MathMax(1.0,effective);

      Log("SPREAD AUTO-CALIBRATION COMPLETE"+
          " | samples="+IntegerToString(g_spreadCalCount)+
          " | median observed="+DoubleToString(median,1)+" points"+
          " | multiplier="+DoubleToString(mult,2)+
          " | ceiling="+(InpSpreadCeilingPoints>0
                         ?IntegerToString(InpSpreadCeilingPoints)
                         :"uncapped")+
          " | EFFECTIVE CAP="+DoubleToString(g_spreadCalEffectiveCap,1)+
          " points");
   }

   return true; // fail open while calibrating
}

//====================== LOGGING =========================================
void Log(string msg)
{
   Print("EzyScalp XAUUSD FRESH V2: "+msg);
}

//====================== DAILY RISK CIRCUIT BREAKER ======================
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
   g_dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct=MathMax(0.0,MathMin(99.0,InpDailyLossStopPct));
   g_dayLossFloor=g_dayStartEquity*(1.0-lossPct/100.0);
   g_dayTradingLocked=false;

   Log("BROKER-DAY RISK RESET"+
       " | date="+IntegerToString(g_dailyDateKey)+
       " | start equity="+DoubleToString(g_dayStartEquity,2)+
       " | daily risk="+DoubleToString(InpDailyLossStopPct,1)+"%"+
       " | lock floor="+DoubleToString(g_dayLossFloor,2));
}

void CheckCampaignDay()
{
   ResetCampaignDay(false);
   if(g_dayTradingLocked) return;

   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(InpDailyLossStopPct>0 && equity<=g_dayLossFloor)
   {
      g_dayTradingLocked=true;

      if(InpCloseAllAtDailyStop)
         CloseAllPositions();

      Log("DAILY RISK LOCK"+
          " | risk="+DoubleToString(InpDailyLossStopPct,1)+"%"+
          " | start equity="+DoubleToString(g_dayStartEquity,2)+
          " | current equity="+DoubleToString(equity,2)+
          " | floor="+DoubleToString(g_dayLossFloor,2)+
          " | reset=next broker day");
   }
}

bool DailyRiskCapacityAvailable()
{
   CheckCampaignDay();
   return !g_dayTradingLocked;
}

// Deliberately NOT rate-limited - see the Order-Rate Throttle section.
void CloseAllPositions()
{
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=(ulong)InpMagicNumber) continue;
      trade.PositionClose(ticket);
   }
}

//====================== ENVIRONMENT GATE ================================
bool TradingEnvironmentReady(string &reason)
{
   reason="";

   if((bool)MQLInfoInteger(MQL_TESTER))
      return true;

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

   return true;
}

//====================== POSITION COUNTING ================================
int CountOurPositions()
{
   int count=0;
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=(ulong)InpMagicNumber) continue;
      count++;
   }
   return count;
}

//====================== ATR / BIAS HELPERS ==============================
double ExitATR()
{
   if(g_exitAtrHandle==INVALID_HANDLE) return 0.0;
   double buffer[];
   ArraySetAsSeries(buffer,true);
   if(CopyBuffer(g_exitAtrHandle,0,1,1,buffer)<1) return 0.0;
   if(buffer[0]<=0.0) return 0.0;
   return buffer[0];
}

double ZoneATR()
{
   if(g_zoneAtrHandle==INVALID_HANDLE) return 0.0;
   double buffer[];
   ArraySetAsSeries(buffer,true);
   if(CopyBuffer(g_zoneAtrHandle,0,1,1,buffer)<1) return 0.0;
   if(buffer[0]<=0.0) return 0.0;
   return buffer[0];
}

// Returns 1 for bullish H1 bias, -1 for bearish, 0 if unavailable.
int H1Bias()
{
   if(g_biasEmaHandle==INVALID_HANDLE) return 0;

   double emaBuf[];
   ArraySetAsSeries(emaBuf,true);
   if(CopyBuffer(g_biasEmaHandle,0,1,1,emaBuf)<1) return 0;

   double close=iClose(_Symbol,InpDirectionTimeframe,1);
   if(close<=0.0) return 0;

   if(close>emaBuf[0]) return 1;
   if(close<emaBuf[0]) return -1;
   return 0;
}

// Nearest H1 CLOSE below (support) and above (resistance) current price,
// scanning the last InpDirectionHistory CLOSED H1 bars. This is the
// original EzyMap lineage's own approach (PickDirectionLevels) - proximate
// recent closes acting as levels, not a full swing-pivot reconstruction.
bool FindNearestLevels(double reference,double &support,double &resistance)
{
   support=0.0;
   resistance=0.0;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int maxN=MathMax(5,InpDirectionHistory);
   int copied=CopyRates(_Symbol,InpDirectionTimeframe,1,maxN,rates);
   if(copied<5)
      return false;

   double bestSupportDist=DBL_MAX;
   double bestResistanceDist=DBL_MAX;

   for(int i=0;i<copied;i++)
   {
      double level=rates[i].close;

      if(level<reference)
      {
         double dist=reference-level;
         if(dist<bestSupportDist) { bestSupportDist=dist; support=level; }
      }
      else if(level>reference)
      {
         double dist=level-reference;
         if(dist<bestResistanceDist) { bestResistanceDist=dist; resistance=level; }
      }
   }

   return (support>0.0 || resistance>0.0);
}

//====================== ENTRY - ZONE RETEST ==============================
// See the file header for the full mechanism. One decision per M5 bar.
bool DetectZoneRetestSignal(int &direction)
{
   direction=0;

   datetime barTime=iTime(_Symbol,InpEntryTimeframe,0);
   if(barTime<=0 || barTime==g_lastSignalBarTime)
      return false; // already evaluated this bar

   double zoneAtr=ZoneATR();
   if(zoneAtr<=0.0)
      return false; // no live volatility reading yet - do not guess

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double cmp=(tick.bid+tick.ask)*0.5;

   double support=0.0,resistance=0.0;
   if(!FindNearestLevels(cmp,support,resistance))
      return false;

   int bias=H1Bias(); // 1 bullish, -1 bearish, 0 unavailable/neutral

   double zoneHalfWidth=MathMax(_Point,zoneAtr*MathMax(0.05,InpZoneATRMultiplier));

   MqlRates entryRates[];
   ArraySetAsSeries(entryRates,true);
   int maxN=MathMax(3,InpEntryHistory);
   int copied=CopyRates(_Symbol,InpEntryTimeframe,1,maxN,entryRates);
   if(copied<3)
      return false;

   bool buySignal=false;
   bool sellSignal=false;

   // ---- Support retest (candidate BUY) ----
   if(support>0.0)
   {
      double zoneLo=support-zoneHalfWidth;
      double zoneHi=support+zoneHalfWidth;

      for(int i=0;i<copied;i++)
      {
         bool overlaps=(entryRates[i].low<=zoneHi && entryRates[i].high>=zoneLo);
         if(!overlaps) continue;

         // Price must have since moved back above the zone - a genuine
         // retest-and-reject, not price still sitting inside the zone.
         if(entryRates[i].high>=cmp-_Point) continue;

         bool directional=(entryRates[i].close>entryRates[i].open);
         if(InpRequireDirectionalCandle && !directional) continue;

         bool trendAgrees=(bias>=0); // bullish or neutral bias
         if(!trendAgrees && !InpAllowCounterTrend) continue;

         buySignal=true;
         break;
      }
   }

   // ---- Resistance retest (candidate SELL) ----
   if(resistance>0.0)
   {
      double zoneLo=resistance-zoneHalfWidth;
      double zoneHi=resistance+zoneHalfWidth;

      for(int i=0;i<copied;i++)
      {
         bool overlaps=(entryRates[i].low<=zoneHi && entryRates[i].high>=zoneLo);
         if(!overlaps) continue;

         if(entryRates[i].low<=cmp+_Point) continue;

         bool directional=(entryRates[i].close<entryRates[i].open);
         if(InpRequireDirectionalCandle && !directional) continue;

         bool trendAgrees=(bias<=0); // bearish or neutral bias
         if(!trendAgrees && !InpAllowCounterTrend) continue;

         sellSignal=true;
         break;
      }
   }

   // Both sides qualifying at once is a squeeze/indecision condition, not a
   // clean signal in either direction - skip it rather than guess.
   if(buySignal && sellSignal)
      return false;

   if(!buySignal && !sellSignal)
      return false;

   g_lastSignalBarTime=barTime; // one decision per bar, win or lose

   direction=buySignal?1:-1;
   return true;
}

//====================== ENTRY EXECUTION ==================================
void TryOpenPosition()
{
   if(!DailyRiskCapacityAvailable())
      return;

   if(!SpreadAllowed())
      return;

   if(CountOurPositions()>=MathMax(1,InpMaxConcurrentPositions))
      return;

   int direction=0;
   if(!DetectZoneRetestSignal(direction))
      return;

   double atr=ExitATR();
   if(atr<=0.0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double entry=(direction==1)?tick.ask:tick.bid;
   double stopDistance=MathMax(_Point,atr*MathMax(0.1,InpATRStopMultiplier));
   double targetDistance=stopDistance*MathMax(0.1,InpRewardRiskMultiple);

   double sl=(direction==1)?entry-stopDistance:entry+stopDistance;
   double tp=(direction==1)?entry+targetDistance:entry-targetDistance;

   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   sl=NormalizeDouble(sl,digits);
   tp=NormalizeDouble(tp,digits);

   double lot=LotForEquity();
   if(lot<=0.0)
   {
      Log("ENTRY SKIPPED | LotForEquity() returned 0 - equity below broker minimum lot");
      return;
   }

   if(!EntryRequestThrottleOK())
      return; // global entry-rate floor - see the Order-Rate Throttle section

   string comment="EZS2 "+IntegerToString(direction==1?1:-1)+" "+
                  TimeToString(TimeCurrent(),TIME_DATE|TIME_MINUTES);

   trade.SetExpertMagicNumber(InpMagicNumber);

   bool sent=(direction==1)
             ? trade.Buy(lot,_Symbol,0.0,sl,tp,comment)
             : trade.Sell(lot,_Symbol,0.0,sl,tp,comment);

   uint retcode=trade.ResultRetcode();

   Log("ENTRY "+string(sent?"SENT":"FAILED")+
       " | direction="+string(direction==1?"BUY":"SELL")+
       " | lot="+DoubleToString(lot,2)+
       " | entry="+DoubleToString(entry,digits)+
       " | sl="+DoubleToString(sl,digits)+
       " | tp="+DoubleToString(tp,digits)+
       " | atr="+DoubleToString(atr,digits)+
       " | retcode="+IntegerToString((int)retcode)+
       " | "+trade.ResultRetcodeDescription());
}

//====================== EXIT / TRAIL MANAGEMENT ==========================
// Unchanged from V1 except: NOT rate-limited (see the header note on why).
void ManagePositions()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double atr=ExitATR();
   if(atr<=0.0)
      return; // no live volatility reading - do not move any stop blind

   double trailDistance=MathMax(_Point,atr*MathMax(0.1,InpATRTrailMultiplier));

   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=(ulong)InpMagicNumber) continue;

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int direction=(type==POSITION_TYPE_BUY)?1:-1;
      double currentSL=PositionGetDouble(POSITION_SL);
      double currentProfit=PositionGetDouble(POSITION_PROFIT);

      // Trail arms ONLY once the position is genuinely, not just
      // directionally, profitable.
      if(currentProfit<=0.0)
         continue;

      double current=(direction==1)?tick.bid:tick.ask;
      double candidateSL=(direction==1)
                         ? current-trailDistance
                         : current+trailDistance;

      int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      candidateSL=NormalizeDouble(candidateSL,digits);

      bool improves=(currentSL<=0.0) ||
                    (direction==1 && candidateSL>currentSL+_Point*0.25) ||
                    (direction==-1 && candidateSL<currentSL-_Point*0.25);

      if(!improves)
         continue;

      double currentTP=PositionGetDouble(POSITION_TP);
      bool sent=trade.PositionModify(ticket,candidateSL,currentTP);

      if(sent)
      {
         Log("TRAIL UPDATED | ticket="+(string)ticket+
             " | direction="+string(direction==1?"BUY":"SELL")+
             " | floating profit="+DoubleToString(currentProfit,2)+
             " | new sl="+DoubleToString(candidateSL,digits));
      }
   }
}

//====================== PERFORMANCE REPORT ================================
void PrintPerformanceReport()
{
   if(!HistorySelect(g_eaStartTime,TimeCurrent()))
   {
      Log("PERFORMANCE REPORT | HistorySelect failed - no report available");
      return;
   }

   int totalDeals=HistoryDealsTotal();

   double lotsTraded=0.0;
   double netProfit=0.0;
   int wins=0,losses=0,flat=0;
   int roundTrips=0;

   for(int i=0;i<totalDeals;i++)
   {
      ulong dealTicket=HistoryDealGetTicket(i);
      if(dealTicket==0) continue;

      if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=(ulong)InpMagicNumber) continue;

      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY);
      double volume=HistoryDealGetDouble(dealTicket,DEAL_VOLUME);
      double profit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+
                    HistoryDealGetDouble(dealTicket,DEAL_SWAP)+
                    HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);

      netProfit+=profit;

      if(entry==DEAL_ENTRY_IN)
      {
         lotsTraded+=volume;
      }
      else if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_OUT_BY)
      {
         roundTrips++;
         if(profit>0.01)      wins++;
         else if(profit<-0.01) losses++;
         else                  flat++;
      }
   }

   double winRatePct=(roundTrips>0)?(100.0*wins/(double)roundTrips):0.0;

   Log("=============== PERFORMANCE REPORT ===============");
   Log("PERFORMANCE REPORT"+
       " | closed trades="+IntegerToString(roundTrips)+
       " | wins="+IntegerToString(wins)+
       " | losses="+IntegerToString(losses)+
       " | flat="+IntegerToString(flat)+
       " | win rate="+DoubleToString(winRatePct,1)+"%"+
       " | lots traded="+DoubleToString(lotsTraded,2)+
       " | net profit="+DoubleToString(netProfit,2)+" "+
       AccountInfoString(ACCOUNT_CURRENCY));
   Log("====================================================");
}

//====================== LIFECYCLE ========================================
int OnInit()
{
   g_accountUnitDivisor=ResolveAccountUnitDivisor();

   g_exitAtrHandle=iATR(_Symbol,InpEntryTimeframe,MathMax(1,InpATRPeriod));
   if(g_exitAtrHandle==INVALID_HANDLE)
   {
      Log("EXIT ATR HANDLE FAILED | timeframe="+EnumToString(InpEntryTimeframe)+
          " | period="+IntegerToString(InpATRPeriod));
      return INIT_FAILED;
   }

   g_zoneAtrHandle=iATR(_Symbol,InpZoneTimeframe,MathMax(1,InpZoneATRPeriod));
   if(g_zoneAtrHandle==INVALID_HANDLE)
   {
      Log("ZONE ATR HANDLE FAILED | timeframe="+EnumToString(InpZoneTimeframe)+
          " | period="+IntegerToString(InpZoneATRPeriod));
      return INIT_FAILED;
   }

   g_biasEmaHandle=iMA(_Symbol,InpDirectionTimeframe,
                       MathMax(1,InpBiasEMAPeriod),0,MODE_EMA,PRICE_CLOSE);
   if(g_biasEmaHandle==INVALID_HANDLE)
   {
      Log("BIAS EMA HANDLE FAILED | timeframe="+EnumToString(InpDirectionTimeframe)+
          " | period="+IntegerToString(InpBiasEMAPeriod));
      return INIT_FAILED;
   }

   g_spreadCalCount=0;
   g_spreadCalEffectiveCap=-1.0;
   ArrayResize(g_spreadCalSamples,MathMax(20,InpSpreadCalibrationTicks));

   g_dailyDateKey=0;
   ResetCampaignDay(true);

   g_lastSignalBarTime=0;
   g_eaStartTime=TimeCurrent();
   g_lastEntryRequestMs=0;

   trade.SetExpertMagicNumber(InpMagicNumber);

   Log("INIT"+
       " | symbol="+_Symbol+
       " | account profile="+string(g_accountUnitDivisor>1.0?"CENT":"STANDARD")+
       " | divisor="+DoubleToString(g_accountUnitDivisor,0)+
       " | base equity="+DoubleToString(InpBaseEquity,2)+
       " | base lot="+DoubleToString(InpBaseLot,2)+
       " | daily risk stop="+DoubleToString(InpDailyLossStopPct,1)+"%"+
       " | direction tf="+EnumToString(InpDirectionTimeframe)+
       " | zone tf="+EnumToString(InpZoneTimeframe)+
       " | entry tf="+EnumToString(InpEntryTimeframe)+
       " | allow counter-trend="+string(InpAllowCounterTrend?"YES":"NO")+
       " | min ms between entry requests="+IntegerToString(InpMinMsBetweenEntryRequests));

   return INIT_SUCCEEDED;
}

void OnTick()
{
   string reason="";
   if(!TradingEnvironmentReady(reason))
      return;

   ManagePositions();
   TryOpenPosition();
}

void OnDeinit(const int reason)
{
   PrintPerformanceReport();

   if(g_exitAtrHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_exitAtrHandle);
      g_exitAtrHandle=INVALID_HANDLE;
   }

   if(g_zoneAtrHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_zoneAtrHandle);
      g_zoneAtrHandle=INVALID_HANDLE;
   }

   if(g_biasEmaHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_biasEmaHandle);
      g_biasEmaHandle=INVALID_HANDLE;
   }
}
