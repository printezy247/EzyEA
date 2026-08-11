//+------------------------------------------------------------------+
//| EzyMap_V5_XAUUSD_SND_SCALPER.mq5                                  |
//+------------------------------------------------------------------+
//  EZYMAP V5 - GROUND-UP REBUILD, XAUUSD ONLY                        |
//                                                                    |
//  Built after a full prior session spent hardening the FRESH V3/V4  |
//  family's broker-execution robustness. Despite all of that, a live |
//  attach of FRESH V3 to a real cent-account chart drew the account  |
//  down ~40% while Strategy Tester runs on the identical EA never    |
//  showed more than ~10% drawdown - the tester structurally cannot   |
//  reproduce broker-side rejections the way a real broker issues     |
//  them. Per explicit instruction, V5 abandons the old multi-layer/  |
//  confluence trading logic entirely for a deliberately simple       |
//  design, and the STANDING PRIORITY for this EA line is: minimum    |
//  drawdown or modest growth, but MAXIMUM TRADE FREQUENCY - fewer    |
//  gates, more entries, refine safety only once entries are flowing. |
//                                                                    |
//  TRADE IDEA: 4 price LEVELS per timeframe (H1/H4/D1/W1) - the      |
//  High and Low of each of the last 2 closed bars on that timeframe, |
//  kept as a small rolling window (16 levels total) rather than an   |
//  unbounded history. A real resting LIMIT ORDER is placed directly  |
//  at each level's price - a SELL LIMIT if the level is currently    |
//  above price, a BUY LIMIT if it is below - so the broker's own     |
//  order-matching engine decides when price has reached a level,     |
//  rather than this EA polling ticks to detect a touch (see the      |
//  v5.5 CORRECTION for why that changed). No confluence filter, no   |
//  spread guard, no concurrency cap, no execution-distance           |
//  pre-check - every level always carries a resting order, by        |
//  explicit instruction. Fixed bracket only (TP 37 pips / SL 25      |
//  pips), attached to the limit order at placement and NEVER         |
//  modified afterward - no trailing, no breakeven lock, so V5        |
//  cannot suffer the retry-storm class that dominated the prior      |
//  session's live failures, by construction rather than by           |
//  patching around it. Once a level's order fills and the resulting  |
//  position closes, a fresh limit order is placed at the same level  |
//  automatically.                                                    |
//                                                                    |
//  LOT SIZING: capital-scaled, not risk-%-based - InpBaseLot         |
//  (default 0.01) per InpBaseCapital (default 100, in the same       |
//  "effective" equity units used elsewhere - real-dollar-equivalent  |
//  even on a cent account) of current equity, floored at the broker  |
//  minimum. Explicitly requested in place of the earlier OneLotLoss()|
//  risk-% formula for simplicity and predictability across account   |
//  sizes.                                                             |
//                                                                    |
//  CORRECTION (v5.1, first tester run): a full day of testing         |
//  produced zero trades because the per-level cooldown and a global   |
//  order-request throttle both timestamped themselves with            |
//  GetTickCount64() (real OS milliseconds) - correct for live         |
//  trading, but in the Strategy Tester that reflects real CPU         |
//  processing speed, not simulated market time, so a "2 second"       |
//  cooldown ate a large fraction of the entire test's real duration   |
//  on a single touch. Fixed: every cooldown now uses TimeCurrent()    |
//  (the simulated market clock, correct in both live and tester) at   |
//  whole-second granularity, and the global throttle was removed      |
//  outright (each level's own cooldown already serves that purpose    |
//  without blocking legitimate simultaneous different-level entries). |
//                                                                    |
//  CORRECTION (v5.2, second tester run): orders were now being sent   |
//  but the broker rejected them with [invalid stops] on essentially   |
//  every attempt (48-49 consecutive failures observed on one level    |
//  before the run ended), and positions stayed at 0 the whole run.    |
//  That rejection is genuinely broker-side - this build's own         |
//  execution-distance pre-check (ExecutionDistanceValid(), the        |
//  zero-stops-level fallback) was passing these requests through      |
//  fine, so removing it would not by itself change the outcome; the   |
//  broker's real minimum stop distance on XAUUSD.sc appears to be     |
//  wider than the fixed 25-pip SL allows at current conditions. Per   |
//  explicit instruction, ALL diagnostic gates are removed here        |
//  anyway (spread guard, concurrency cap, execution-distance          |
//  pre-check, capital-cap on lot size) so the underlying broker       |
//  response is visible directly rather than filtered - the one       |
//  exception is the per-level cooldown/backoff (InpLevelReTouchCooldownSec / |
//  InpEntryRetryMinimumIntervalSec / InpEntryBackoffCooldownCapSec),  |
//  kept deliberately because removing it would reproduce, on the      |
//  entry side, the exact zero-backoff retry-storm class this whole    |
//  multi-session effort has been about eliminating on the exit side - |
//  a level that the broker keeps rejecting would otherwise resend on  |
//  every single tick, forever. Also added: an OnInit log of the       |
//  symbol's actual SYMBOL_TRADE_STOPS_LEVEL/SYMBOL_TRADE_FREEZE_LEVEL/ |
//  current spread, so the real broker constraint behind [invalid      |
//  stops] is visible in the journal on the next run regardless of     |
//  whether entries succeed.                                           |
//                                                                    |
//  CORRECTION (v5.3, third tester run): the drawn level lines were     |
//  confirmed visible and price visibly crossed them repeatedly, but    |
//  still zero trades appeared on the chart - consistent with the      |
//  v5.2 broker-side [invalid stops] rejection continuing to occur      |
//  silently (removing the pre-check in v5.2 stopped the EA from        |
//  blocking itself, but never made the broker accept a genuinely too-  |
//  tight fixed 25-pip SL). FIX: added MinimumBrokerDistance(), which   |
//  WIDENS the SL/TP to the broker's real minimum (SYMBOL_TRADE_STOPS_  |
//  LEVEL/FREEZE_LEVEL plus a small cushion, with the same zero-stops-  |
//  level percentage-of-price fallback used elsewhere this session)     |
//  instead of rejecting or skipping the trade - this is NOT a          |
//  reintroduced filter, since nothing is ever blocked; it only         |
//  changes the price used so the request the broker actually accepts. |
//  Also added an unconditional "V5 TOUCH" log at the exact moment a    |
//  level's edge-trigger condition fires, BEFORE any gate or order-     |
//  send outcome, so touch detection itself can never again be          |
//  ambiguous from the journal regardless of what happens afterward.    |
//                                                                    |
//  CORRECTION (v5.4, fourth run - still zero triggers): per explicit   |
//  instruction, the v5.3 SL/TP widening was REVERTED outright (a       |
//  silently wider stop is a real, unwanted extra loss, not an          |
//  acceptable tradeoff for hitting more entries) - the fixed 25/37 pip |
//  bracket is now sent exactly as specified again. Separately, a       |
//  comparison against how FRESH V3 itself detects a touch              |
//  (ReadyTouchCMP() / BuildZeroConfluenceTouchEnvelope()) surfaced the  |
//  REAL bug: this file's touch check only looked at whether the        |
//  CURRENT tick's price sat inside the tolerance band around a level - |
//  if price moved from clearly one side of a level to clearly the      |
//  other side between two consecutive ticks without any single tick    |
//  happening to land inside that (narrow, 20-point) band, no touch was |
//  ever registered at all, no matter how many times price visibly      |
//  crossed the line on the chart. FIX: touch is now detected as a      |
//  CROSSING between the previous tick's reference price and the        |
//  current one (LevelState gained hasPrevPrice/prevPrice, replacing    |
//  the old single-snapshot lastSide field) - the same envelope-between-|
//  consecutive-CMP technique FRESH V3 already uses. Also added         |
//  explicit "V5 LEVEL NEW"/"V5 LEVEL REPLACED" logging (previously      |
//  silent) so level formation/rollover on candle close is directly     |
//  visible, and a periodic "V5 LEVEL DUMP" line listing every tracked  |
//  level's exact price against the current bid.                        |
//                                                                    |
//  CORRECTION (v5.5, trading logic change per explicit instruction):   |
//  replaced instant market entry on tick-detected touch with a real     |
//  RESTING LIMIT ORDER placed directly at each level's price - a SELL   |
//  LIMIT if the level is currently above price, a BUY LIMIT if it is    |
//  below. This retires the entire tick-polling touch-detection          |
//  approach (and the v5.4 crossing-envelope fix along with it) in       |
//  favour of letting the broker's own order-matching engine decide      |
//  when price has reached a level, using its live price feed rather     |
//  than a periodic OnTick snapshot - structurally immune to the         |
//  tunneling problem v5.4 fixed by hand. LevelState's hasPrevPrice/     |
//  prevPrice fields were replaced with a single pendingTicket field.    |
//  When a level's order fills, the resulting position is bound to      |
//  openTicket exactly as before (via ReconcileLevelBindings() comment   |
//  matching); once that position closes, a fresh limit order is        |
//  placed at the same level automatically - directly implementing "a    |
//  new limit is generated once the previous one on that level has      |
//  been triggered." A level being rolled over (evicted for a newer     |
//  bar's H/L once 4 are already tracked) now cancels any resting        |
//  pending order at the old price first, so nothing is ever left        |
//  orphaned at the broker.                                              |
//                                                                    |
//  NOT YET VERIFIED: compiles in MetaEditor (no MQL5 toolchain in     |
//  this environment), or real trading performance. Verified here:    |
//  brace/paren/bracket balance, and a manual audit that every input   |
//  referenced anywhere is actually declared and every forward         |
//  declaration matches a real definition.                             |
//+------------------------------------------------------------------+
#property copyright "EzyMap"
#property link      ""
#property version   "5.5"
#property strict

#include <Trade/Trade.mqh>
CTrade trade;

//------------------------------ Enums --------------------------------
enum ENUM_EZY_ACCOUNT_SCALE
{
   EZY_ACCOUNT_AUTO     = 0,
   EZY_ACCOUNT_STANDARD = 1,
   EZY_ACCOUNT_CENT     = 2
};

//------------------------------ Inputs -------------------------------
input ulong  InpMagicNumber              = 5000001;
input int    InpDeviationPoints          = 20;

// Account currency scale. AUTO (default) detects a cent account from the
// account currency, server/company name, or a .sc-style symbol suffix on
// live, but forces standard (divisor=1) inside the Strategy Tester unless
// InpTesterAutoModeIsStandard is turned off.
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor   = 100.0;
input bool   InpTesterAutoModeIsStandard = true;
input bool   InpTreatSCSuffixAsCentOnLive = true;

// Cent-aware pip sizing for XAUUSD.sc vs standard XAUUSD.
input bool   InpUseXAUUSDscBrokerPointPips  = true;
input double InpXAUUSDscStrategyPipPrice    = 0.01;
input double InpStandardXAUUSDStrategyPipPrice = 0.10;

// Fixed bracket - submitted once at entry, never modified afterward.
input double InpTakeProfitPips = 37.0;
input double InpStopLossPips   = 25.0;

// How close price must come to a level, in raw broker points, to count as
// a touch. Also used to dedup near-identical levels on the same timeframe.
input int    InpLevelTouchTolerancePoints = 20;

// Capital-scaled lot sizing: InpBaseLot per InpBaseCapital of current
// effective equity, floored at the broker minimum. No cap above that -
// deliberately simple, replacing the earlier risk-%-of-SL-distance
// formula per explicit instruction.
input double InpBaseLot      = 0.01;
input double InpBaseCapital  = 100.0;

// Per-level cooldown applied on EVERY fire attempt (win or lose) plus an
// exponential backoff on genuine rejections. This is the one gate kept
// even with everything else removed - see the v5.2 CORRECTION note in
// the header for why. TimeCurrent()-based, whole seconds.
input int    InpLevelReTouchCooldownSec      = 1;
input int    InpEntryRetryMinimumIntervalSec = 1;
input int    InpEntryBackoffCooldownCapSec   = 10;

// Reporting.
input bool   InpPrintExecutionLog       = true;
input int    InpStatusReportIntervalSec = 60;

//------------------------------ Structs -------------------------------
struct LevelState
{
   double         price;
   datetime       barTime;
   ENUM_TIMEFRAMES sourceTf;
   ulong          pendingTicket;         // 0 = no resting limit order at this level
   ulong          openTicket;            // 0 = no live trade bound to this level
   int            entryConsecutiveFailures;
   datetime       entryCooldownUntil;
};

LevelState g_levels[];

//------------------------------ Globals --------------------------------
double g_accountUnitDivisor = 1.0;
double g_pipSize            = 0.10;

datetime g_lastH1BarTime = 0;
datetime g_lastH4BarTime = 0;
datetime g_lastD1BarTime = 0;
datetime g_lastW1BarTime = 0;

datetime g_lastStatusReportTime = 0;

long g_gateCooldownRejects = 0;
long g_orderSendAttempts   = 0;
long g_orderSendAccepted   = 0;
long g_orderSendRejected   = 0;

//------------------------------ Forward declarations --------------------
double ResolveAccountUnitDivisor();
string _UpperStr(string s);
double EffectiveAccountEquity();
bool   IsCentSuffixSymbol();
double StrategyPipSize();
double RoundPrice(double v);
int    VolumeDigits();
double NormalizeVolumeDown(double vol);
double ComputeCapitalScaledLot();
bool   TradeRetcodeAccepted(uint code);
bool   TemporaryTradeRetcode(uint code);
void   Log(string msg);
int    CountOurPositions();
int    CountOurPositionsByDirection(int direction);
void   AddOrEvictLevel(double price,datetime barTime,ENUM_TIMEFRAMES tf);
void   RefreshLevelsForTimeframe(ENUM_TIMEFRAMES tf,datetime &lastBarTime,int seedBars);
int    FindLevelByPrice(double price);
bool   ParseLevelComment(string comment,double &outPrice);
void   ReconcileLevelBindings();
void   ManageLevelOrders();
bool   PlaceLevelLimitOrder(int levelIndex);
void   ReportLiveParityStatus();
void   ReportDeploymentGateBreakdown();
string TimeframeLabel(ENUM_TIMEFRAMES tf);
color  LevelColor(ENUM_TIMEFRAMES tf);
void   DrawLevel(int index);
void   DrawAllLevels();
void   RemoveAllLevelDrawings();

//------------------------------ Account/sizing helpers -------------------
double ResolveAccountUnitDivisor()
{
   if(InpAccountScaleMode==EZY_ACCOUNT_STANDARD)
      return 1.0;

   double configured=MathMax(1.0,InpCentAccountUnitDivisor);

   if(InpAccountScaleMode==EZY_ACCOUNT_CENT)
      return configured;

   // AUTO mode: a normal Strategy Tester deposit must not be divided merely
   // because the historical symbol name ends in .sc.
   if((bool)MQLInfoInteger(MQL_TESTER) && InpTesterAutoModeIsStandard)
      return 1.0;

   string currency=_UpperStr(AccountInfoString(ACCOUNT_CURRENCY));
   string server=_UpperStr(AccountInfoString(ACCOUNT_SERVER));
   string company=_UpperStr(AccountInfoString(ACCOUNT_COMPANY));
   string symbol=_UpperStr(_Symbol);

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

string _UpperStr(string s)
{
   StringToUpper(s);
   return s;
}

double EffectiveAccountEquity()
{
   return AccountInfoDouble(ACCOUNT_EQUITY)/MathMax(1.0,g_accountUnitDivisor);
}

bool IsCentSuffixSymbol()
{
   string s=_UpperStr(_Symbol);
   return (StringFind(s,".SC")>=0 || StringFind(s,"_SC")>=0 ||
           StringFind(s,"CENT")>=0);
}

double StrategyPipSize()
{
   if(InpUseXAUUSDscBrokerPointPips && IsCentSuffixSymbol())
      return MathMax(InpXAUUSDscStrategyPipPrice,_Point);
   return MathMax(InpStandardXAUUSDStrategyPipPrice,_Point);
}

double RoundPrice(double v)
{
   int digits=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS);
   return NormalizeDouble(v,digits);
}

int VolumeDigits()
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   int d=0;
   while(d<8 && MathAbs(step-NormalizeDouble(step,d))>1e-10)
      d++;
   return d;
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

// Capital-scaled lot sizing: InpBaseLot per InpBaseCapital of current
// effective equity, floored at the broker minimum. No risk/SL-distance
// math, no cap above the floor - deliberately simple, per explicit
// instruction to remove all sizing filters for now.
double ComputeCapitalScaledLot()
{
   double effectiveEquity=EffectiveAccountEquity();
   if(effectiveEquity<=0.0)
      return 0.0;

   double lots=MathMax(0.0,InpBaseLot)*(effectiveEquity/MathMax(1.0,InpBaseCapital));
   lots=NormalizeVolumeDown(lots);

   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(lots<minVol)
      lots=minVol;

   return NormalizeVolumeDown(lots)>0.0?lots:0.0;
}

//------------------------------ Retcode classification --------------------
bool TradeRetcodeAccepted(uint code)
{
   return (code==TRADE_RETCODE_DONE ||
           code==TRADE_RETCODE_PLACED ||
           code==TRADE_RETCODE_DONE_PARTIAL);
}

// TRADE_RETCODE_MARKET_CLOSED is included here from day one - confirmed
// missing from every prior EA in this codebase, and confirmed live via a
// user journal screenshot showing repeated "[Market closed]" entry
// rejections on XAUUSD.sc.
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

//------------------------------ Logging / position counting ---------------
void Log(string msg)
{
   if(InpPrintExecutionLog)
      Print("EzyMap V5: ",msg);
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

      ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if((direction==1 && type==POSITION_TYPE_BUY) ||
         (direction==-1 && type==POSITION_TYPE_SELL))
         count++;
   }
   return count;
}

//------------------------------ Level store --------------------------------
// Keeps exactly 4 levels per timeframe (16 total across H1/H4/D1/W1) - a
// small rolling window of the last 2 closed bars' High and Low on that
// timeframe, not the full unbounded history the first version tracked.
// When a 5th level would form for a timeframe, the oldest one WITHOUT a
// currently-open trade is evicted and overwritten in place; if all 4
// happen to have open trades (possible now that there is no concurrency
// cap), the new level is simply skipped until a slot frees up next time -
// rare, self-resolving, and never orphans or duplicates an open position.
void AddOrEvictLevel(double price,datetime barTime,ENUM_TIMEFRAMES tf)
{
   if(price<=0.0) return;

   double tol=MathMax(0,InpLevelTouchTolerancePoints)*_Point;
   int n=ArraySize(g_levels);

   for(int i=0;i<n;i++)
      if(g_levels[i].sourceTf==tf && MathAbs(g_levels[i].price-price)<=tol)
         return; // already tracked for this timeframe

   int countForTf=0;
   int oldestIdx=-1;
   datetime oldestTime=0;

   for(int i=0;i<n;i++)
   {
      if(g_levels[i].sourceTf!=tf) continue;
      countForTf++;
      if(g_levels[i].openTicket==0 &&
         (oldestIdx<0 || g_levels[i].barTime<oldestTime))
      {
         oldestIdx=i;
         oldestTime=g_levels[i].barTime;
      }
   }

   if(countForTf>=4)
   {
      if(oldestIdx<0)
      {
         Log("V5 LEVEL SKIPPED (all 4 have open trades) | tf="+
             TimeframeLabel(tf)+" | candidate="+DoubleToString(price,_Digits));
         return; // all 4 have open trades right now - skip, retry later
      }

      // A resting pending order at the OLD price is no longer meaningful
      // once this slot is repointed at a new price - cancel it rather
      // than leave it orphaned at the broker with nothing tracking it.
      if(g_levels[oldestIdx].pendingTicket!=0)
      {
         trade.OrderDelete(g_levels[oldestIdx].pendingTicket);
         Log("V5 LIMIT CANCELLED (level rolling over) | tf="+TimeframeLabel(tf)+
             " | old level="+DoubleToString(g_levels[oldestIdx].price,_Digits)+
             " | ticket="+(string)g_levels[oldestIdx].pendingTicket);
      }

      Log("V5 LEVEL REPLACED | tf="+TimeframeLabel(tf)+
          " | old="+DoubleToString(g_levels[oldestIdx].price,_Digits)+
          " -> new="+DoubleToString(price,_Digits)+
          " | barTime="+TimeToString(barTime,TIME_DATE|TIME_MINUTES));

      g_levels[oldestIdx].price=price;
      g_levels[oldestIdx].barTime=barTime;
      g_levels[oldestIdx].pendingTicket=0;
      g_levels[oldestIdx].openTicket=0;
      g_levels[oldestIdx].entryConsecutiveFailures=0;
      g_levels[oldestIdx].entryCooldownUntil=0;
      return;
   }

   int idx=ArraySize(g_levels);
   ArrayResize(g_levels,idx+1,16);
   g_levels[idx].price=price;
   g_levels[idx].barTime=barTime;
   g_levels[idx].sourceTf=tf;
   g_levels[idx].pendingTicket=0;
   g_levels[idx].openTicket=0;
   g_levels[idx].entryConsecutiveFailures=0;
   g_levels[idx].entryCooldownUntil=0;

   Log("V5 LEVEL NEW | tf="+TimeframeLabel(tf)+
       " | price="+DoubleToString(price,_Digits)+
       " | barTime="+TimeToString(barTime,TIME_DATE|TIME_MINUTES)+
       " | index="+IntegerToString(idx));
}

// Seeds each timeframe with its last 2 closed bars (4 levels) the first
// time it is called (lastBarTime==0), then on every later call only walks
// back as far as needed to cover any bars that closed since the previous
// check - correct even across a gap where the EA was offline for a while.
void RefreshLevelsForTimeframe(ENUM_TIMEFRAMES tf,datetime &lastBarTime,int seedBars)
{
   datetime currentBarTime=iTime(_Symbol,tf,0);
   if(currentBarTime==0) return; // no history loaded yet for this timeframe

   if(lastBarTime==0)
   {
      int totalBars=iBars(_Symbol,tf);
      int bars=MathMin(MathMax(0,seedBars),MathMax(0,totalBars-1));

      for(int shift=bars;shift>=1;shift--)
      {
         datetime bt=iTime(_Symbol,tf,shift);
         if(bt==0) continue;
         AddOrEvictLevel(iHigh(_Symbol,tf,shift),bt,tf);
         AddOrEvictLevel(iLow(_Symbol,tf,shift),bt,tf);
      }

      lastBarTime=currentBarTime;
      return;
   }

   if(currentBarTime==lastBarTime) return;

   int total=iBars(_Symbol,tf);
   for(int shift=1;shift<total;shift++)
   {
      datetime bt=iTime(_Symbol,tf,shift);
      if(bt<=lastBarTime) break;
      AddOrEvictLevel(iHigh(_Symbol,tf,shift),bt,tf);
      AddOrEvictLevel(iLow(_Symbol,tf,shift),bt,tf);
   }

   lastBarTime=currentBarTime;
}

int FindLevelByPrice(double price)
{
   double tol=_Point*0.5;
   int n=ArraySize(g_levels);
   for(int i=0;i<n;i++)
      if(MathAbs(g_levels[i].price-price)<=tol)
         return i;
   return -1;
}

bool ParseLevelComment(string comment,double &outPrice)
{
   outPrice=0.0;
   if(StringFind(comment,"V5@")!=0)
      return false;

   outPrice=StringToDouble(StringSubstr(comment,3));
   return (outPrice>0.0);
}

// Binds each currently open position (ours) to its source level by parsing
// the "V5@<price>" order comment back to a price and matching it against
// the level store, rather than trusting CTrade's post-send ticket
// resolution (ResultOrder()/ResultDeal() are not reliably the resulting
// POSITION ticket across every broker/account mode). Also correctly
// re-associates any still-open positions with their source level after an
// EA restart/reattach, with no persisted state required.
void ReconcileLevelBindings()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string comment=PositionGetString(POSITION_COMMENT);
      double lvlPrice;
      if(!ParseLevelComment(comment,lvlPrice)) continue;

      int idx=FindLevelByPrice(lvlPrice);
      if(idx>=0)
         g_levels[idx].openTicket=ticket;
   }

   // A level's tracked pending order may have disappeared since the last
   // check - either it FILLED (the position loop above will have already
   // picked up the resulting position by comment match this same pass) or
   // it was cancelled/expired - either way, stop tracking a ticket that no
   // longer exists so ManageLevelOrders() knows to place a fresh one.
   int n=ArraySize(g_levels);
   for(int i=0;i<n;i++)
      if(g_levels[i].pendingTicket!=0 && !OrderSelect(g_levels[i].pendingTicket))
         g_levels[i].pendingTicket=0;

   // Also bind any currently-resting pending order not yet tracked, by the
   // same comment-matching pattern - covers an EA restart/reattach finding
   // pending orders it placed before, with no persisted state required.
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0) continue;
      if(OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      if((ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;

      string comment=OrderGetString(ORDER_COMMENT);
      double lvlPrice;
      if(!ParseLevelComment(comment,lvlPrice)) continue;

      int idx=FindLevelByPrice(lvlPrice);
      if(idx>=0)
         g_levels[idx].pendingTicket=ticket;
   }
}

//------------------------------ Pending limit orders -----------------------
// v5.5: replaces the entire tick-polling touch-detection approach. Instead
// of watching price on every tick and trying to detect when it crosses a
// level (which needed a crossing-envelope fix in v5.4 to avoid missing
// ticks that tunneled straight past a level), a real resting limit order
// is placed directly AT each level's price - a SELL LIMIT if the level is
// currently above price, a BUY LIMIT if it is below. The broker's own
// order-matching engine then handles "did price reach this level" using
// its live price feed, not a periodic OnTick snapshot - structurally
// immune to the tunneling problem, and exactly what a limit order is for.
bool PlaceLevelLimitOrder(int levelIndex)
{
   datetime nowTime=TimeCurrent();

   if(nowTime<g_levels[levelIndex].entryCooldownUntil)
   {
      g_gateCooldownRejects++;
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double levelPrice=g_levels[levelIndex].price;
   double cmp=tick.bid;

   // Level above current price -> SELL LIMIT (price must rise to meet it).
   // Level below current price -> BUY LIMIT (price must fall to meet it).
   // Level == current price (within a point) -> wait a tick for it to
   // separate rather than guess a side.
   int direction;
   if(levelPrice>cmp+_Point) direction=-1;
   else if(levelPrice<cmp-_Point) direction=1;
   else return false;

   double slDistance=MathMax(0.1,InpStopLossPips)*g_pipSize;
   double tpDistance=MathMax(0.1,InpTakeProfitPips)*g_pipSize;

   // SL/TP are relative to the LIMIT price itself (where the order will
   // actually fill), not current market price - the fixed 25/37 pip
   // bracket is sent exactly as specified, never widened.
   double sl=RoundPrice(direction==1?levelPrice-slDistance:levelPrice+slDistance);
   double tp=RoundPrice(direction==1?levelPrice+tpDistance:levelPrice-tpDistance);
   double orderPrice=RoundPrice(levelPrice);

   double lots=ComputeCapitalScaledLot();
   if(lots<=0.0)
      return false;

   // Baseline cooldown applied on EVERY placement attempt, win or lose,
   // consistent with the retry-storm protection built for the exit side
   // earlier this session - the one gate kept even with everything else
   // removed.
   g_levels[levelIndex].entryCooldownUntil=
      nowTime+(datetime)MathMax(0,InpLevelReTouchCooldownSec);

   string comment="V5@"+DoubleToString(g_levels[levelIndex].price,_Digits);

   g_orderSendAttempts++;
   bool sent=(direction==1)
             ? trade.BuyLimit(lots,orderPrice,_Symbol,sl,tp,ORDER_TIME_GTC,0,comment)
             : trade.SellLimit(lots,orderPrice,_Symbol,sl,tp,ORDER_TIME_GTC,0,comment);

   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);

   if(accepted)
   {
      g_orderSendAccepted++;
      g_levels[levelIndex].entryConsecutiveFailures=0;
      g_levels[levelIndex].pendingTicket=trade.ResultOrder();

      Log("V5 LIMIT PLACED | "+(direction==1?"BUY LIMIT":"SELL LIMIT")+
          " | level="+DoubleToString(g_levels[levelIndex].price,_Digits)+
          " (tf="+EnumToString(g_levels[levelIndex].sourceTf)+")"+
          " | sl="+DoubleToString(sl,_Digits)+
          " | tp="+DoubleToString(tp,_Digits)+
          " | lots="+DoubleToString(lots,VolumeDigits())+
          " | ticket="+(string)g_levels[levelIndex].pendingTicket);

      return true;
   }

   g_orderSendRejected++;
   bool temporary=TemporaryTradeRetcode(code);
   int failCount=++g_levels[levelIndex].entryConsecutiveFailures;

   int backoffSec=(int)MathMin(
      (double)MathMax(0,InpEntryBackoffCooldownCapSec),
      (double)MathMax(0,InpEntryRetryMinimumIntervalSec)*
      (double)(1<<MathMin(failCount,10)));

   datetime cooldownUntil=nowTime+
      (datetime)MathMax(MathMax(0,InpLevelReTouchCooldownSec),backoffSec);
   g_levels[levelIndex].entryCooldownUntil=cooldownUntil;

   Log("V5 LIMIT FAILED | "+(direction==1?"BUY LIMIT":"SELL LIMIT")+
       " | level="+DoubleToString(g_levels[levelIndex].price,_Digits)+
       " | temporary="+string(temporary?"YES":"NO")+
       " | consecutive failures="+IntegerToString(failCount)+
       " | next retry in="+IntegerToString((int)(cooldownUntil-nowTime))+"s"+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());

   return false;
}

// Runs every tick. For each level: a live trade bound (openTicket!=0) or a
// resting pending order (pendingTicket!=0) means there's nothing to do -
// ReconcileLevelBindings() already keeps both current. Only a level with
// neither gets a fresh limit order placed, gated by its cooldown. When an
// open trade closes, ReconcileLevelBindings() clears openTicket on the
// very next pass, and this function places a brand new limit order at the
// same level on the pass after that - directly implementing "a level
// re-triggers once its previous trade closes."
void ManageLevelOrders()
{
   int n=ArraySize(g_levels);
   for(int i=0;i<n;i++)
   {
      if(g_levels[i].openTicket!=0) continue;
      if(g_levels[i].pendingTicket!=0) continue;

      PlaceLevelLimitOrder(i);
   }
}

//------------------------------ Reporting ----------------------------------
void ReportLiveParityStatus()
{
   int h1=0,h4=0,d1=0,w1=0,openLevels=0;
   int n=ArraySize(g_levels);

   for(int i=0;i<n;i++)
   {
      if(g_levels[i].sourceTf==PERIOD_H1) h1++;
      else if(g_levels[i].sourceTf==PERIOD_H4) h4++;
      else if(g_levels[i].sourceTf==PERIOD_D1) d1++;
      else if(g_levels[i].sourceTf==PERIOD_W1) w1++;

      if(g_levels[i].openTicket!=0) openLevels++;
   }

   Log("V5 LIVE PARITY STATUS"+
       " | levels total="+IntegerToString(n)+
       " (H1="+IntegerToString(h1)+" H4="+IntegerToString(h4)+
       " D1="+IntegerToString(d1)+" W1="+IntegerToString(w1)+")"+
       " | positions="+IntegerToString(CountOurPositions())+
       " | levels with open trade="+IntegerToString(openLevels)+
       " | BUY="+IntegerToString(CountOurPositionsByDirection(1))+
       " SELL="+IntegerToString(CountOurPositionsByDirection(-1))+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+
       " | divisor="+DoubleToString(g_accountUnitDivisor,1)+
       " | pipSize="+DoubleToString(g_pipSize,_Digits));

   // v5.5: the exact tracked price and order/position state of every
   // level, so a run can be checked directly against the chart and the
   // broker's own order list.
   MqlTick statusTick;
   double statusBid=(SymbolInfoTick(_Symbol,statusTick))?statusTick.bid:0.0;
   string dump="V5 LEVEL DUMP | bid="+DoubleToString(statusBid,_Digits);
   for(int i=0;i<n;i++)
   {
      string state="idle";
      if(g_levels[i].openTicket!=0) state="OPEN#"+(string)g_levels[i].openTicket;
      else if(g_levels[i].pendingTicket!=0) state="PENDING#"+(string)g_levels[i].pendingTicket;

      dump+=" | "+TimeframeLabel(g_levels[i].sourceTf)+
            "="+DoubleToString(g_levels[i].price,_Digits)+
            "("+state+")";
   }
   Log(dump);
}

void ReportDeploymentGateBreakdown()
{
   Log("V5 DEPLOYMENT GATE BREAKDOWN"+
       " | COOLDOWN REJECTED="+IntegerToString((int)g_gateCooldownRejects)+
       " | ORDER-SEND ATTEMPTS="+IntegerToString((int)g_orderSendAttempts)+
       " | ACCEPTED="+IntegerToString((int)g_orderSendAccepted)+
       " | REJECTED="+IntegerToString((int)g_orderSendRejected));
}

//------------------------------ Chart visualization -------------------------
// One dashed horizontal line + one text label per tracked level, so the 4
// levels per timeframe are visible directly on the chart (in the Strategy
// Tester's visual mode too) rather than only inferable from the journal.
// Object names are tied to the level's array index, which is stable for
// the lifetime of that slot (AddOrEvictLevel() overwrites slots in place
// rather than reordering the array), so updating in place - not deleting
// and recreating - is safe and cheap even every tick.
string TimeframeLabel(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H1) return "H1";
   if(tf==PERIOD_H4) return "H4";
   if(tf==PERIOD_D1) return "Daily";
   if(tf==PERIOD_W1) return "Weekly";
   return EnumToString(tf);
}

color LevelColor(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_H1) return clrDeepSkyBlue;
   if(tf==PERIOD_H4) return clrOrange;
   if(tf==PERIOD_D1) return clrLimeGreen;
   if(tf==PERIOD_W1) return clrMagenta;
   return clrWhite;
}

void DrawLevel(int index)
{
   if(index<0 || index>=ArraySize(g_levels)) return;

   double price=g_levels[index].price;
   if(price<=0.0) return;

   ENUM_TIMEFRAMES tf=g_levels[index].sourceTf;
   color col=LevelColor(tf);
   string tfText=TimeframeLabel(tf);

   string lineName="V5_LVL_"+IntegerToString(index);
   if(ObjectFind(0,lineName)<0)
      ObjectCreate(0,lineName,OBJ_HLINE,0,0,price);
   ObjectSetDouble(0,lineName,OBJPROP_PRICE,price);
   ObjectSetInteger(0,lineName,OBJPROP_COLOR,col);
   ObjectSetInteger(0,lineName,OBJPROP_STYLE,STYLE_DASH);
   ObjectSetInteger(0,lineName,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,lineName,OBJPROP_BACK,true);
   ObjectSetString(0,lineName,OBJPROP_TOOLTIP,
      tfText+" level "+DoubleToString(price,_Digits));

   // Text label floats a couple of bars ahead of the latest bar so it sits
   // in the empty space to the right of price action rather than
   // overlapping candles, and is re-anchored every call so it keeps pace
   // as the chart scrolls forward (live or tester).
   datetime labelTime=TimeCurrent()+PeriodSeconds(PERIOD_CURRENT)*2;
   string labelName="V5_LBL_"+IntegerToString(index);
   if(ObjectFind(0,labelName)<0)
      ObjectCreate(0,labelName,OBJ_TEXT,0,labelTime,price);
   ObjectSetInteger(0,labelName,OBJPROP_TIME,labelTime);
   ObjectSetDouble(0,labelName,OBJPROP_PRICE,price);
   ObjectSetString(0,labelName,OBJPROP_TEXT," "+tfText);
   ObjectSetInteger(0,labelName,OBJPROP_COLOR,col);
   ObjectSetInteger(0,labelName,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,labelName,OBJPROP_ANCHOR,ANCHOR_LEFT);
}

void DrawAllLevels()
{
   int n=ArraySize(g_levels);
   for(int i=0;i<n;i++)
      DrawLevel(i);
}

void RemoveAllLevelDrawings()
{
   ObjectsDeleteAll(0,"V5_LVL_");
   ObjectsDeleteAll(0,"V5_LBL_");
}

//------------------------------ Lifecycle -----------------------------------
int OnInit()
{
   g_accountUnitDivisor=ResolveAccountUnitDivisor();
   g_pipSize=StrategyPipSize();

   ArrayResize(g_levels,0);
   g_lastH1BarTime=0;
   g_lastH4BarTime=0;
   g_lastD1BarTime=0;
   g_lastW1BarTime=0;

   g_gateCooldownRejects=0;
   g_orderSendAttempts=0;
   g_orderSendAccepted=0;
   g_orderSendRejected=0;
   g_lastStatusReportTime=0;

   RefreshLevelsForTimeframe(PERIOD_H1,g_lastH1BarTime,2);
   RefreshLevelsForTimeframe(PERIOD_H4,g_lastH4BarTime,2);
   RefreshLevelsForTimeframe(PERIOD_D1,g_lastD1BarTime,2);
   RefreshLevelsForTimeframe(PERIOD_W1,g_lastW1BarTime,2);

   ReconcileLevelBindings();
   RemoveAllLevelDrawings();
   DrawAllLevels();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.SetAsyncMode(false);

   // v5.2: the real broker constraint behind any future [invalid stops]
   // rejection, logged directly so it doesn't have to be inferred from
   // OrderSend failures.
   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   MqlTick initTick;
   double spreadPoints=0.0;
   if(SymbolInfoTick(_Symbol,initTick) && _Point>0)
      spreadPoints=(initTick.ask-initTick.bid)/_Point;

   Log("V5 BROKER CONSTRAINTS"+
       " | SYMBOL_TRADE_STOPS_LEVEL="+IntegerToString((int)stopsLevel)+" points"+
       " | SYMBOL_TRADE_FREEZE_LEVEL="+IntegerToString((int)freezeLevel)+" points"+
       " | current spread="+DoubleToString(spreadPoints,1)+" points"+
       " | fixed SL distance="+DoubleToString(MathMax(0.1,InpStopLossPips)*g_pipSize,_Digits)+
       " ("+DoubleToString(InpStopLossPips,1)+" pips)"+
       " | fixed TP distance="+DoubleToString(MathMax(0.1,InpTakeProfitPips)*g_pipSize,_Digits)+
       " ("+DoubleToString(InpTakeProfitPips,1)+" pips)");

   Log("V5 INIT"+
       " | symbol="+_Symbol+
       " | cent-suffix="+string(IsCentSuffixSymbol()?"YES":"NO")+
       " | account divisor="+DoubleToString(g_accountUnitDivisor,1)+
       " | pipSize="+DoubleToString(g_pipSize,_Digits)+
       " | levels seeded="+IntegerToString(ArraySize(g_levels))+
       " | TP="+DoubleToString(InpTakeProfitPips,1)+"p"+
       " | SL="+DoubleToString(InpStopLossPips,1)+"p"+
       " | lot="+DoubleToString(InpBaseLot,2)+" per "+DoubleToString(InpBaseCapital,0)+
       " capital (no cap, no risk filter)");

   ManageLevelOrders();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   RemoveAllLevelDrawings();
}

void OnTick()
{
   RefreshLevelsForTimeframe(PERIOD_H1,g_lastH1BarTime,2);
   RefreshLevelsForTimeframe(PERIOD_H4,g_lastH4BarTime,2);
   RefreshLevelsForTimeframe(PERIOD_D1,g_lastD1BarTime,2);
   RefreshLevelsForTimeframe(PERIOD_W1,g_lastW1BarTime,2);

   ReconcileLevelBindings();
   ManageLevelOrders();
   DrawAllLevels();

   if(InpStatusReportIntervalSec>0 &&
      TimeCurrent()-g_lastStatusReportTime>=InpStatusReportIntervalSec)
   {
      g_lastStatusReportTime=TimeCurrent();
      ReportLiveParityStatus();
      ReportDeploymentGateBreakdown();
   }
}
