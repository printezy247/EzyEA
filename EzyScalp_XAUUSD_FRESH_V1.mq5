//+------------------------------------------------------------------+
//| EzyScalp XAUUSD FRESH V1                                         |
//| A clean-slate scalping EA for XAUUSD, built after two weeks of   |
//| patching EzyMap_V2_1b/V2_2 revealed that file's accumulated       |
//| complexity (confidence-tier lot scaling, three separate layer-    |
//| builders, a zero-confluence bypass path, ATR geometry bolted onto |
//| a fixed-pip base) was harder to reason about than the strategy    |
//| itself. Nothing is carried over from that file - this is a fresh  |
//| design, built around three explicit, discussed decisions:         |
//|                                                                   |
//|   1. STYLE: scalping - frequent, small, fast in-and-out trades.   |
//|   2. OBJECTIVE: minimum daily drawdown, maximum daily lot volume  |
//|      traded - NOT a per-trade risk-percentage target. Sizing is   |
//|      flat and proportional (see LotForEquity()), never scaled up  |
//|      by "confidence" - that exact mechanism caused a live lot-    |
//|      doubling bug on the old EA and is deliberately absent here.  |
//|   3. RISK: no specific risk-per-trade; a single daily circuit      |
//|      breaker at InpDailyLossStopPct (default 75%, per explicit    |
//|      user instruction - this is intentionally loose, a backstop   |
//|      against a catastrophic day, not a tight per-trade governor). |
//|                                                                   |
//| PHASE 1 (this file): sizing/risk framework + a Donchian-breakout  |
//| momentum scalper with an optional higher-timeframe trend filter,  |
//| ATR-based stop/target, and a trailing stop that only arms once    |
//| the position's REAL floating profit is positive (not just a       |
//| favourable price move, which can still be a net loss once spread  |
//| is subtracted - the same lesson learned building the old EA's     |
//| FIXEDEXIT test). Every stop/target/spread-gate figure is derived  |
//| from LIVE ATR or a live-measured spread, never a hand-guessed pip |
//| constant - the single most expensive lesson from the old file.    |
//|                                                                   |
//| PHASE 2 (not in this file yet): a news-breakout module using      |
//| MT5's built-in Economic Calendar (CalendarValueHistory) to        |
//| straddle scheduled high-impact releases, per the user's explicit  |
//| choice to trade news deliberately rather than avoid it. Left out  |
//| of this first build so the sizing/risk/baseline-entry skeleton    |
//| can be tested and trusted on its own before adding it.            |
//+------------------------------------------------------------------+
#property copyright "EzyScalp"
#property version   "1.01"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//====================== ACCOUNT / SIZING =============================
// Same tester-safe reasoning as the old EA's ResolveAccountUnitDivisor():
// a Strategy Tester deposit must never be silently divided just because the
// historical symbol name or account currency looks like a cent account -
// that mismatch alone produced a "zero lots, zero trades" bug on the old
// file. AUTO mode detects a real cent account by currency/server/company/
// symbol-suffix, but is forced to STANDARD inside the tester unless the
// user deliberately overrides it.
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
// equity uses 0.01 lot as the baseline. An account BELOW 100 still sizes as
// if it had 100 (floor, never a below-minimum lot). An account ABOVE 100
// scales UP linearly from that same 100/0.01 anchor. This is flat,
// proportional sizing - there is no confidence tier, no per-signal
// multiplier, and no risk-percentage/stop-distance calculation, exactly as
// specified ("i dont have any specific risk per trade").
input double InpBaseEquity = 100.0;
input double InpBaseLot    = 0.01;

//====================== DAILY RISK CIRCUIT BREAKER ====================
input group "=== Daily Risk ==="
// Deliberately loose per explicit instruction - this is a backstop against
// a catastrophic day, not a tight per-trade governor. The objective is
// maximum daily lot volume; this only stops trading once the day is
// genuinely a write-off.
input double InpDailyLossStopPct   = 75.0;
input bool   InpCloseAllAtDailyStop = false;

//====================== SPREAD GUARD (auto-calibrating) ===============
// Ported concept from the old EA's hardest-won lesson: a hand-guessed
// static spread cap is a guess about a broker's point convention that is
// wrong as often as it is right. This measures the SYMBOL'S OWN real
// spread for InpSpreadCalibrationTicks ticks after attach (filter INACTIVE/
// fail-open while collecting - a slow calibration must never itself block
// every trade) and enforces median(observed) * InpSpreadCalibrationMultiplier
// from then on, optionally capped by InpSpreadCeilingPoints as a safety
// backstop (0 = uncapped).
input group "=== Spread Guard ==="
input int    InpSpreadCalibrationTicks      = 100;
input double InpSpreadCalibrationMultiplier = 3.0;
input int    InpSpreadCeilingPoints         = 0;

//====================== ENTRY - DONCHIAN BREAKOUT MOMENTUM =============
input group "=== Entry: Momentum Breakout ==="
// FREQUENCY TUNING (v1.01): the first test run came back with very low
// trade frequency, which directly conflicts with the stated objective of
// maximum daily lot volume. Three levers control how often a breakout
// signal can fire, and all three were tightened toward "quality over
// quantity" by the v1.00 defaults - loosened here toward "quantity":
//   - InpSignalTimeframe: M5 -> M1. 5x more bars/day means 5x more chances
//     for price to clear a channel edge.
//   - InpChannelLookbackBars: 20 -> 10. A shorter channel is cleared far
//     more often - this is the single biggest lever on signal count.
//   - InpBreakoutATRFraction: 0.15 -> 0.05. A smaller required clearance
//     lets more marginal breaks qualify instead of being filtered out.
// Understood tradeoff: more signals from a shorter/looser channel means
// more of them will be noise rather than a genuine sustained move, which
// should show up as a lower win rate per trade in exchange for materially
// higher trade count and lot volume - the explicit priority you set.
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_M1;
input int    InpChannelLookbackBars = 10;
// Minimum breakout distance beyond the channel, expressed as a fraction of
// live ATR, so the filter self-scales with volatility instead of using a
// fixed price/point distance.
input double InpBreakoutATRFraction = 0.05;
// Raised 3 -> 5 alongside the frequency changes above so more concurrent
// signals can actually be acted on instead of being blocked by this cap.
input int    InpMaxConcurrentPositions = 5;
input int    InpMagicNumber = 20260809;

//====================== TREND FILTER (optional, default ON) ===========
// Gold has been a choppy, news-driven correction inside a longer bull
// structure through 2026 (Fed-leadership uncertainty, geopolitical spikes) -
// a pure breakout scalper with no trend filter will get chopped up trading
// both directions through that noise. This refuses counter-trend breakouts
// outright rather than trying to score or weight them.
input group "=== Trend Filter ==="
input bool   InpUseTrendFilter = true;
input ENUM_TIMEFRAMES InpTrendTimeframe = PERIOD_H1;
input int    InpTrendEMAPeriod = 50;

//====================== EXIT - ATR STOP / TARGET / TRAIL ===============
input group "=== Exit ==="
input int    InpATRPeriod           = 14;
input double InpATRStopMultiplier   = 1.2;
input double InpRewardRiskMultiple  = 1.2;
// The trail does not arm on a favourable price move - it arms only once
// POSITION_PROFIT (the position's real floating profit, which already nets
// out the spread since a BUY closes at bid and a SELL at ask) is positive.
// This is deliberately stricter than a pip-distance arm check, to avoid the
// EA doing any premature profit-taking or loss-cutting via an early trail
// move on a position that is not genuinely in profit yet.
input double InpATRTrailMultiplier  = 0.8;

//====================== GLOBALS ========================================
double   g_accountUnitDivisor = 1.0;
int      g_atrHandle          = INVALID_HANDLE;
int      g_trendEMAHandle     = INVALID_HANDLE;

double   g_spreadCalSamples[];
int      g_spreadCalCount       = 0;
double   g_spreadCalEffectiveCap = -1.0;

int      g_dailyDateKey    = 0;
double   g_dayStartEquity  = 0.0;
double   g_dayLossFloor    = 0.0;
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

   // AUTO mode: a normal Strategy Tester deposit must not be divided merely
   // because the historical symbol name or account currency looks like a
   // cent account - the same lesson the old EA learned the hard way.
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

// Verbatim implementation of the user's sizing rule: floor at InpBaseEquity,
// scale linearly above it. No confidence tier, no risk-percentage/stop-
// distance calculation - flat, proportional, and identical for every setup
// this EA takes.
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
   Print("EzyScalp XAUUSD FRESH V1: "+msg);
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

//====================== ATR / TREND HELPERS ==============================
double CurrentATR()
{
   if(g_atrHandle==INVALID_HANDLE) return 0.0;

   double buffer[];
   ArraySetAsSeries(buffer,true);
   if(CopyBuffer(g_atrHandle,0,1,1,buffer)<1) return 0.0;
   if(buffer[0]<=0.0) return 0.0;
   return buffer[0];
}

// Returns 1 for uptrend, -1 for downtrend, 0 if unavailable/disabled.
int TrendDirection()
{
   if(!InpUseTrendFilter) return 0;
   if(g_trendEMAHandle==INVALID_HANDLE) return 0;

   double emaBuf[];
   ArraySetAsSeries(emaBuf,true);
   if(CopyBuffer(g_trendEMAHandle,0,1,1,emaBuf)<1) return 0;

   double close=iClose(_Symbol,InpTrendTimeframe,1);
   if(close<=0.0) return 0;

   if(close>emaBuf[0]) return 1;
   if(close<emaBuf[0]) return -1;
   return 0;
}

//====================== ENTRY - DONCHIAN BREAKOUT ========================
bool DetectMomentumBreakout(int &direction)
{
   direction=0;

   datetime barTime=iTime(_Symbol,InpSignalTimeframe,0);
   if(barTime<=0 || barTime==g_lastSignalBarTime)
      return false; // already evaluated this bar

   int lookback=MathMax(5,InpChannelLookbackBars);

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   // Shift 1 onward: the channel is built from CLOSED bars only, so the
   // breakout is measured against a range the still-forming bar cannot
   // itself have widened.
   int copied=CopyRates(_Symbol,InpSignalTimeframe,1,lookback,rates);
   if(copied<lookback)
      return false;

   double channelHigh=rates[0].high;
   double channelLow=rates[0].low;
   for(int i=1;i<copied;i++)
   {
      channelHigh=MathMax(channelHigh,rates[i].high);
      channelLow=MathMin(channelLow,rates[i].low);
   }

   double atr=CurrentATR();
   if(atr<=0.0)
      return false; // no live volatility reading yet - do not guess

   double breakoutBuffer=MathMax(0.0,InpBreakoutATRFraction)*atr;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   int trend=TrendDirection();

   bool buyBreak = (tick.ask>=channelHigh+breakoutBuffer) &&
                   (!InpUseTrendFilter || trend>=0);
   bool sellBreak= (tick.bid<=channelLow-breakoutBuffer) &&
                   (!InpUseTrendFilter || trend<=0);

   // A bar that breaks both sides (a wide-range whipsaw bar) is not a clean
   // breakout in either direction - skip it rather than guess.
   if(buyBreak && sellBreak)
      return false;

   if(!buyBreak && !sellBreak)
      return false;

   g_lastSignalBarTime=barTime; // one decision per bar, win or lose

   direction=buyBreak?1:-1;
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
   if(!DetectMomentumBreakout(direction))
      return;

   double atr=CurrentATR();
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

   string comment="EZS "+IntegerToString(direction==1?1:-1)+" "+
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
void ManagePositions()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double atr=CurrentATR();
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
      // directionally, profitable - see the header note on why.
      if(currentProfit<=0.0)
         continue;

      double current=(direction==1)?tick.bid:tick.ask;
      double candidateSL=(direction==1)
                         ? current-trailDistance
                         : current+trailDistance;

      int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
      candidateSL=NormalizeDouble(candidateSL,digits);

      // Monotonic ratchet - a new stop is only ever accepted if it is
      // strictly more protective than the one already on the position.
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
// The user's first test run came back "no reporting" - this pulls the
// EA's own deal history (scoped to g_eaStartTime, not the whole account
// history, so it stays fast and never mixes in a different EA's trades)
// and prints exactly the three numbers asked for: lot traded, win rate,
// net profit. Runs once at OnDeinit, same point the old EA printed its
// final summary.
void PrintPerformanceReport()
{
   if(!HistorySelect(g_eaStartTime,TimeCurrent()))
   {
      Log("PERFORMANCE REPORT | HistorySelect failed - no report available");
      return;
   }

   int totalDeals=HistoryDealsTotal();

   double lotsTraded=0.0;   // sum of ENTRY deal volumes - capital actually put to work
   double netProfit=0.0;    // profit + swap + commission across all deals
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

   g_atrHandle=iATR(_Symbol,InpSignalTimeframe,MathMax(1,InpATRPeriod));
   if(g_atrHandle==INVALID_HANDLE)
   {
      Log("ATR HANDLE FAILED | timeframe="+EnumToString(InpSignalTimeframe)+
          " | period="+IntegerToString(InpATRPeriod));
      return INIT_FAILED;
   }

   g_trendEMAHandle=INVALID_HANDLE;
   if(InpUseTrendFilter)
   {
      g_trendEMAHandle=iMA(_Symbol,InpTrendTimeframe,
                           MathMax(1,InpTrendEMAPeriod),0,MODE_EMA,PRICE_CLOSE);
      if(g_trendEMAHandle==INVALID_HANDLE)
      {
         Log("TREND EMA HANDLE FAILED | timeframe="+EnumToString(InpTrendTimeframe)+
             " | period="+IntegerToString(InpTrendEMAPeriod));
         return INIT_FAILED;
      }
   }

   g_spreadCalCount=0;
   g_spreadCalEffectiveCap=-1.0;
   ArrayResize(g_spreadCalSamples,MathMax(20,InpSpreadCalibrationTicks));

   g_dailyDateKey=0;
   ResetCampaignDay(true);

   g_lastSignalBarTime=0;
   g_eaStartTime=TimeCurrent();

   trade.SetExpertMagicNumber(InpMagicNumber);

   Log("INIT"+
       " | symbol="+_Symbol+
       " | account profile="+string(g_accountUnitDivisor>1.0?"CENT":"STANDARD")+
       " | divisor="+DoubleToString(g_accountUnitDivisor,0)+
       " | base equity="+DoubleToString(InpBaseEquity,2)+
       " | base lot="+DoubleToString(InpBaseLot,2)+
       " | daily risk stop="+DoubleToString(InpDailyLossStopPct,1)+"%"+
       " | signal timeframe="+EnumToString(InpSignalTimeframe)+
       " | channel lookback="+IntegerToString(InpChannelLookbackBars)+
       " | trend filter="+string(InpUseTrendFilter?"ON":"OFF"));

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

   if(g_atrHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
      g_atrHandle=INVALID_HANDLE;
   }

   if(g_trendEMAHandle!=INVALID_HANDLE)
   {
      IndicatorRelease(g_trendEMAHandle);
      g_trendEMAHandle=INVALID_HANDLE;
   }
}
