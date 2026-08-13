//+------------------------------------------------------------------+
//|                                             EzyEA_V3_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V3 - built from V2's proven SND level-touch infrastructure,  |
//| per explicit discussion. Two independent zero-confluence entry     |
//| sources fire in parallel, no filtering between them:               |
//|   1. SND level touch (M5/M15/H1/H4/D1/W1, unchanged from V2) -     |
//|      swing high/low touch, immediate fade, no reclaim required.    |
//|   2. NEW: EMA13 (M5) touch - price returning to a moving EMA from  |
//|      either side is treated as a fade toward it, same "touch =     |
//|      immediate trade, no confirmation" philosophy as SND.          |
//|                                                                    |
//| Per explicit request this round: NO ADX filter, NO per-direction   |
//| cap, NO auto-drawdown-breaker (all were in V2 - deliberately       |
//| dropped here, to be reintroduced later once frequency and exit     |
//| behaviour are right; the plain portfolio-aware margin check stays, |
//| since that is basic execution correctness, not a strategic filter).|
//|                                                                    |
//| NEW exit rule: every position, regardless of which trigger opened  |
//| it, is force-closed once it has been open InpMaxHoldingMinutes     |
//| (default 30) - a hard, unconditional backstop so a position can    |
//| never sit floating for an extended stretch the way V2's did,       |
//| regardless of whether its SL/trail has resolved yet.               |
//|                                                                    |
//| Everything else is the same proven infrastructure: risk-based lot  |
//| sizing via OrderCalcProfit() with a capped minimum-lot fallback,    |
//| portfolio-aware margin check, ATR-based SL/trail-only exit with     |
//| the activation-floor rule and the trailing side-validation fix,    |
//| TimeCurrent()-based modify backoff, the zero-stops-level broker    |
//| fallback, an auto-calibrating spread guard, and cent-account-aware |
//| equity handling.                                                   |
//|                                                                    |
//| CHANGELOG                                                          |
//| 3.000 - Initial build.                                             |
//| 3.001 - Added InpScaleRiskByCentDivisor (default true, EXPLICIT      |
//|         REQUEST after confirming the real-money consequence): on a   |
//|         cent account, multiplies the risk budget by the cent         |
//|         divisor so a small cent account sizes trades the same as a   |
//|         same-raw-number standard account would - confirmed live      |
//|         that a 500 USD tester deposit traded 78.65 lots while the    |
//|         same EA on a real 500 USC account traded only 1.33 lots      |
//|         over a comparable stretch. Real per-trade risk becomes       |
//|         roughly (divisor)x larger than InpRiskPercentPerTrade alone  |
//|         implies. The portfolio margin-percentage and free-margin     |
//|         checks are UNCHANGED (still use real, unscaled equity) - a   |
//|         genuinely undersized account still gets capped/rejected by   |
//|         real margin availability regardless of this setting.         |
//| 3.002 - REVERTED: InpScaleRiskByCentDivisor default true->false      |
//|         after live confirmation of the predicted consequence - the   |
//|         real 500 USC account dropped to ~146 USC once lot sizes      |
//|         scaled up to match a 500 USD tester run. Explicit request.   |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "3.002"
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
input int    InpLevelReentrySeconds         = 60;
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
input int    InpEmaReentrySeconds           = 60;

input group "=== Stops / Trail (ATR-based, M5) ==="
input int    InpAtrPeriod                   = 14;
input double InpAtrSlMultiplier             = 1.5;
input double InpTrailMinStepPoints          = 20.0;

input group "=== Exit Management ==="
// Hard, unconditional force-close regardless of P&L - the direct fix for
// positions sitting open for an extended stretch the way V2's did. Set
// to 0 to disable (not recommended without another safety net in place).
input int    InpMaxHoldingMinutes           = 30;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade         = 0.25;
// EXPLICIT REQUEST, CONFIRMED KNOWING THE REAL-MONEY CONSEQUENCE: on a
// cent account, multiplies the risk budget by the cent divisor (e.g.
// 100x) so a "500 USC" account sizes trades the same as a "500 USD"
// account would - matching a Strategy Tester run using a same-raw-
// number standard-currency deposit. This makes REAL risk per trade
// roughly (divisor)x LARGER than InpRiskPercentPerTrade alone implies.
// Tried live and reverted: a 500 USD tester run traded 78.65 lots while
// the same EA on a real 500 USC account traded only 1.33 lots over a
// comparable stretch (~59x gap, consistent with a ~100x cent-scaling
// difference, not a units bug). Turning this on then confirmed the
// predicted consequence live: the account dropped from ~700 to ~146
// USC once the lot size scaled up to match. DEFAULTS FALSE - size
// honestly for the account's real economic value (a genuinely tiny
// account trades genuinely tiny size). Only re-enable with a full
// understanding that it multiplies real per-trade risk by the divisor.
input bool   InpScaleRiskByCentDivisor      = false;
// "No cap" per explicit request - kept as a large technical ceiling
// only (MQL5 arrays/loops still need SOME bound for basic sanity), not
// a strategic limit like V2's per-direction cap, which is dropped here.
input int    InpMaxConcurrentPositions      = 500;
input double InpMaxLotsAbsolute             = 5.0;
// Portfolio-aware (not per-trade-only) margin cap - this is basic
// execution correctness, not a strategic filter, so it stays even
// though ADX/per-direction/drawdown-breaker were dropped this round.
input double InpMaxMarginUsePct             = 40.0;
input bool   InpAllowMinimumLotFallback     = true;
input double InpMinimumLotFallbackMaxRiskPct = 1.0;

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
input ulong  InpMagicNumber                 = 190003;
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

int g_handleAtrM5 = INVALID_HANDLE;
int g_handleEmaM5 = INVALID_HANDLE;

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

void   TryOpenPosition(int direction,string tag,double slDistance);

int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
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
      Log("EzyEA V3 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   g_handleAtrM5 = iATR(_Symbol,PERIOD_M5,InpAtrPeriod);
   g_handleEmaM5 = iMA(_Symbol,PERIOD_M5,InpEmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   if(g_handleAtrM5==INVALID_HANDLE || g_handleEmaM5==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed.");
      return INIT_FAILED;
   }

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

   Log("EzyEA V3 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions)+" (no strategic cap)"+
       " | max holding="+IntegerToString(InpMaxHoldingMinutes)+" min"+
       " | SND levels=M5/M15/H1/H4/D1/W1 (12) + EMA"+IntegerToString(InpEmaPeriod)+" (M5)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAtrM5!=INVALID_HANDLE) IndicatorRelease(g_handleAtrM5);
   if(g_handleEmaM5!=INVALID_HANDLE) IndicatorRelease(g_handleEmaM5);

   RemoveAllDrawings();
}

void OnTick()
{
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
   Print("EzyEA V3 | ",msg);
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
// Entry execution (shared by both trigger sources)
//======================================================================
void TryOpenPosition(int direction,string tag,double slDistance)
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
   double atrBuf[];
   if(CopyBufferSeries(g_handleAtrM5,0,3,atrBuf)<3) return;

   double slDistance=InpAtrSlMultiplier*atrBuf[1];
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V3SND",slDistance);
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
   double atrBuf[];
   if(CopyBufferSeries(g_handleAtrM5,0,3,atrBuf)<3) return;

   double slDistance=InpAtrSlMultiplier*atrBuf[1];
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V3EMA",slDistance);
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
// the full SL distance (never sooner). Every candidate stop must land on
// the CORRECT SIDE of current price, not just far enough from it (the
// bug found and fixed on V1/V2 this session).
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
      string name="V3_LVL_"+IntegerToString(i);
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
      string name="V3_EMA_"+IntegerToString(shift);
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
   string name="V3_StatusLabel";
   string text=StringFormat("EzyEA V3 | SND active=%d/%d | EMA%d touch=%s | Open=%d/%d",
                CountActiveLevels(),ArraySize(g_levels),
                InpEmaPeriod,(g_emaInZone?"IN-ZONE":"-"),
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

void RemoveAllDrawings()
{
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,"V3_")==0)
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

   Log("V3 LIVE PARITY STATUS"+
       " | SND active="+IntegerToString(CountActiveLevels())+"/"+IntegerToString(ArraySize(g_levels))+
       " | EMA"+IntegerToString(InpEmaPeriod)+" touch="+(g_emaInZone?"IN-ZONE":"-")+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY));

   Log("V3 DEPLOYMENT GATE BREAKDOWN"+
       " | attempts="+IntegerToString(g_gateAttempts)+
       " | accepted="+IntegerToString(g_gateAccepted)+
       " | rejected="+IntegerToString(g_gateRejected)+
       " | spreadRejects="+IntegerToString(g_gateSpreadRejects)+
       " | concurrencyRejects="+IntegerToString(g_gateConcurrencyRejects)+
       " | distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " | sizingRejects="+IntegerToString(g_gateSizingRejects));
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

   Log("V3 FINAL REPORT"+
       " | trades="+IntegerToString(trades)+
       " | total lots traded="+DoubleToString(lotsTraded,2)+
       " | net P/L="+DoubleToString(netPnl,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
}
//+------------------------------------------------------------------+
