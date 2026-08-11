//+------------------------------------------------------------------+
//|                                             EzyEA_V2_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V2 - ground-up, entry-only rebuild of EzyEA V1's regime      |
//| design per explicit request. V1's ADX-regime + Bollinger mean-     |
//| reversion + EMA pullback-continuation entries are dropped          |
//| entirely. In their place: a pure multi-timeframe supply/demand     |
//| (SND) level-touch trigger, learned from the old EzyMap "EVERY_     |
//| ZERO_CONF_LEVEL_NO_ENTRY_GOVERNORS" build and already proven this  |
//| session as V1's biggest frequency driver by a wide margin (V1.007) |
//| - here it is the ONLY entry mechanism, not a supplement, and       |
//| covers six timeframes instead of four: M5, M15, H1, H4, D1, W1.    |
//|                                                                    |
//| Everything else is the exact proven infrastructure from V1/this    |
//| session: risk-based lot sizing via OrderCalcProfit() with a capped |
//| minimum-lot fallback, ATR-based SL/trail-only exit with the        |
//| activation-floor rule and the trailing-side-validation fix,        |
//| TimeCurrent()-based (never GetTickCount64()) modify backoff, the   |
//| zero-stops-level broker fallback, an auto-calibrating spread       |
//| guard, and cent-account-aware equity handling.                     |
//|                                                                    |
//| CHANGELOG                                                          |
//| 2.000 - Initial build.                                             |
//| 2.001 - First live run: only 2 lots total volume, still short of   |
//|         target. Two structural fixes, both aimed at frequency:     |
//|         (1) H4/D1/W1 lookback shortened 30/20/12 -> 15/8/5. A swing |
//|         high/low over a long lookback on a higher timeframe can    |
//|         sit far from where price actually trades, so it may never  |
//|         get touched in a normal test window at all - the real      |
//|         bottleneck, not a settings issue. Shorter lookbacks keep    |
//|         these levels closer to recent price action. (2) Switched   |
//|         ProcessLevelTouches() from edge-triggered (must fully leave |
//|         the zone before re-firing) to cooldown-only re-arm, per     |
//|         explicit "maximum trade frequency" request - the reference |
//|         file's "no entry governors" design doesn't require a full  |
//|         round-trip out of the zone either, only a cooldown. A level |
//|         price is chopping right at now fires repeatedly every       |
//|         InpLevelReentrySeconds instead of going silent until price  |
//|         fully exits and re-enters.                                 |
//| 2.002 - Frequency confirmed working: 300 trades, but all 300 still  |
//|         at the 0.01 broker-minimum floor (3.00 total lots) - the    |
//|         real risk-based calc (riskBudget/perLotLoss) never crossed  |
//|         the 0.01 threshold at 0.25% risk, so trade count scaling up |
//|         didn't move total volume at all. Per explicit "adjust       |
//|         position sizing to get more lot traded" request:            |
//|         InpRiskPercentPerTrade 0.25->2.5 (still far short of the    |
//|         V3/V4-style 25-47% aggressive sizing already declined, but  |
//|         enough for real sizing to clear the floor instead of        |
//|         flatlining there every trade). InpMinimumLotFallbackMaxRisk |
//|         Pct 1.0->3.0 to stay above the new target risk - otherwise  |
//|         an outlier-wide ATR stop could make the safety-net fallback |
//|         MORE restrictive than the primary risk target it backstops.|
//| 2.003 - 2.5% risk confirmed working (15 lots, no issue). 5% risk    |
//|         triggered a real margin call - traced to a genuine gap,    |
//|         not just "risk too high": ComputeLotsForRisk()'s margin    |
//|         check only validated each NEW trade in isolation against a |
//|         % of equity. With up to InpMaxConcurrentPositions (50) open |
//|         at once, each one could individually pass that check while |
//|         their COMBINED margin usage kept climbing past what the    |
//|         account could support. Fixed: the cap now applies to       |
//|         AccountInfoDouble(ACCOUNT_MARGIN) (every other open         |
//|         position's margin) PLUS this trade's margin together, so   |
//|         total portfolio margin usage self-limits at                |
//|         InpMaxMarginUsePct regardless of how many positions are    |
//|         already open, instead of only checking one trade at a time.|
//| 2.004 - Confirmed live: margin call STILL happened on a different,  |
//|         more strongly trending test date even with the portfolio   |
//|         margin fix. Root cause is structural, not a sizing bug: V2  |
//|         has zero trend awareness by design (that's the whole point |
//|         of dropping ADX), so on a hard trending day it can fade the |
//|         same direction at level after level, piling up many        |
//|         correlated losers that all move against the account        |
//|         together - a margin cap on NEW trades can't do anything     |
//|         about floating losses on trades already open. Two          |
//|         complementary fixes, neither reintroducing trend detection |
//|         into the entry logic itself: (1) InpMaxConcurrentPerDirection|
//|         (15) caps how many BUY (or SELL) positions can be open at   |
//|         once, directly limiting the worst-case same-direction       |
//|         pileup. (2) A drawdown circuit breaker tracks equity's peak |
//|         since attach and halts ALL new entries once floating+       |
//|         realized drawdown crosses InpMaxEquityDrawdownPct (15%),    |
//|         resuming with hysteresis once it recovers to half that -    |
//|         existing positions keep trailing normally, only new entries |
//|         pause. This is the hard backstop against margin calls       |
//|         regardless of what's driving the drawdown.                 |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "2.004"
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
// Learned from the old EzyMap "EVERY_ZERO_CONF_LEVEL_NO_ENTRY_GOVERNORS"
// build per explicit request: track swing high/low (supply/demand)
// levels across six timeframes and fire an immediate fade on ANY tick
// that touches one, with no reclaim/confirmation requirement at all -
// this is the ONLY entry source in V2, not a supplement. Each level
// rebuilds only on its OWN timeframe's new bar close (never intra-bar).
// Touch detection uses the previous-vs-current-tick envelope-crossing
// check proven this session, so a fast tick move through a level is
// never missed.
input bool   InpEnableLevelTouchEntries     = true;
input double InpLevelTouchTolerancePoints   = 30.0;
input int    InpLevelReentrySeconds         = 60;
input int    InpLevelLookbackM5             = 24;
input int    InpLevelLookbackM15            = 32;
input int    InpLevelLookbackH1             = 24;
// H4/D1/W1 shortened from 30/20/12: a swing high/low over a long lookback
// on a higher timeframe can sit far from where price actually trades,
// so it may never get touched in a normal test window at all - the real
// bottleneck behind the first V2 run's low frequency. Shorter lookbacks
// keep these levels closer to recent price action, and still update the
// moment their own timeframe closes a new bar.
input int    InpLevelLookbackH4             = 15;
input int    InpLevelLookbackD1             = 8;
input int    InpLevelLookbackW1             = 5;

input group "=== Stops / Trail (ATR-based, M5) ==="
input int    InpAtrPeriod                   = 14;
input double InpAtrSlMultiplier             = 1.5;
input double InpTrailMinStepPoints          = 20.0;

input group "=== Risk / Sizing ==="
// 300 trades in the last run, all still at the 0.01 broker-minimum floor
// - the real risk-based calc (riskBudget/perLotLoss) never crossed the
// 0.01 threshold at 0.25%, so every trade fell back to the same fixed
// size regardless of trade count. Raised so real sizing actually scales
// above the floor instead of flatlining there every time.
input double InpRiskPercentPerTrade         = 2.5;
input int    InpMaxConcurrentPositions      = 50;
// Confirmed live: on a strongly trending day, V2's level-touch entries
// have no trend awareness at all (that's the whole point of dropping ADX
// for V2), so they can pile up many SAME-DIRECTION fades against a real
// trend, all losing together. A total concurrency cap alone doesn't stop
// that pileup if every open slot ends up the same direction - this caps
// how many BUY (or SELL) positions can be open at once, independent of
// the total cap.
input int    InpMaxConcurrentPerDirection   = 15;
input double InpMaxLotsAbsolute             = 5.0;
input double InpMaxMarginUsePct             = 40.0;
// On a small account, the broker's minimum lot can itself risk more than
// InpRiskPercentPerTrade at a wide ATR-based SL (see EzyEA V1's own
// changelog - confirmed live: XAUUSD's 100oz contract makes even 0.01
// lot risk far more than 0.25% of a small account). When risk-based
// sizing rounds to 0, fall back to the broker minimum lot instead of
// skipping the trade, but only if that minimum lot's real risk still
// stays under this explicit ceiling. Kept slightly above
// InpRiskPercentPerTrade so an outlier-wide ATR stop can't make this
// safety-net fallback MORE restrictive than the primary risk target
// it's meant to backstop.
input bool   InpAllowMinimumLotFallback     = true;
input double InpMinimumLotFallbackMaxRiskPct = 3.0;

input group "=== Drawdown Circuit Breaker ==="
// Confirmed live: even with a portfolio-level margin cap, floating losses
// across many already-open correlated positions can crash equity fast
// enough to trigger a margin call without any single new trade being too
// big - the margin cap only limits NEW trades, it can't do anything about
// existing ones moving against the account. This tracks equity's peak
// since attach and halts ALL new entries once floating+realized drawdown
// from that peak crosses the threshold - existing positions keep trailing
// normally, only new entries pause. Resumes once drawdown recovers back
// to InpDrawdownResumeFactor x the trigger threshold (hysteresis, so it
// doesn't flap on/off right at the boundary).
input bool   InpEnableDrawdownBreaker       = true;
input double InpMaxEquityDrawdownPct        = 15.0;
input double InpDrawdownResumeFactor        = 0.5;

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
input ulong  InpMagicNumber                 = 190002;
input int    InpDeviationPoints             = 30;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Chart Drawing ==="
input bool   InpDrawLevels                  = true;
input bool   InpDrawStatusLabel             = true;

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

double g_peakEquity          = 0.0;
bool   g_tradingHalted       = false;

// 6 timeframes (M5/M15/H1/H4/D1/W1) x 2 levels (swing high=supply,
// swing low=demand) each.
LevelTouchState g_levels[12];

datetime g_lastM5LevelBarTime  = 0;
datetime g_lastM15LevelBarTime = 0;
datetime g_lastH1LevelBarTime  = 0;
datetime g_lastH4LevelBarTime  = 0;
datetime g_lastD1LevelBarTime  = 0;
datetime g_lastW1LevelBarTime  = 0;

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
int    CountOpenPositionsByDirection(int direction);
void   UpdateDrawdownBreaker();

int    CopyBufferSeries(int handle,int bufferIndex,int count,double &out[]);

void   TryOpenPosition(int direction,string tag,double slDistance);

int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
void   ManageTrailing();

void   RebuildLevelForTimeframe(int slotIndex,ENUM_TIMEFRAMES tf,int lookback,string tfLabel);
void   UpdateLevelsOnNewBars();
void   TryLevelEntry(int direction,double levelPrice);
void   ProcessLevelTouches();

void   DrawLevels();
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
      Log("EzyEA V2 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   g_handleAtrM5 = iATR(_Symbol,PERIOD_M5,InpAtrPeriod);
   if(g_handleAtrM5==INVALID_HANDLE)
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
   g_hasPreviousCMP=false;
   g_previousCMP=0.0;

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted=false;

   Log("EzyEA V2 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions)+
       " (per-direction="+IntegerToString(InpMaxConcurrentPerDirection)+")"+
       " | drawdown breaker="+string(InpEnableDrawdownBreaker?"ON":"OFF")+
       " at "+DoubleToString(InpMaxEquityDrawdownPct,1)+"%"+
       " | SND levels=M5/M15/H1/H4/D1/W1 (12 total)");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAtrM5!=INVALID_HANDLE) IndicatorRelease(g_handleAtrM5);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();

   if(InpEnableLevelTouchEntries)
   {
      UpdateLevelsOnNewBars();
      ProcessLevelTouches();
      DrawLevels();
   }

   ManageTrailing();
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
   Print("EzyEA V2 | ",msg);
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
   // OrderCalcProfit() (via OneLotLoss below) returns - dividing it by
   // the cent-account divisor while perLotLoss stays undivided was a
   // real, confirmed bug in V1's first tester run.
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
      // Portfolio-level cap, not just this one trade: with up to
      // InpMaxConcurrentPositions open at once, each individually passing
      // a per-trade-only check still let COMBINED margin usage climb past
      // what the account could support - confirmed live as the real cause
      // of a margin call at 5% risk. usedMargin already reflects every
      // other open position; the cap now applies to usedMargin+this
      // trade's margin together, so it self-limits regardless of how many
      // positions are already open.
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
// Drawdown circuit breaker: halts new entries once floating+realized
// drawdown from the peak equity seen since attach crosses the threshold.
// Existing positions are untouched - ManageTrailing() keeps managing them
// normally - only new entries pause. Resumes with hysteresis so it
// doesn't flap on/off right at the boundary.
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
      Log("DRAWDOWN BREAKER TRIPPED - new entries halted"+
          " | drawdown="+DoubleToString(drawdownPct,2)+"%"+
          " | peakEquity="+DoubleToString(g_peakEquity,2)+
          " | equity="+DoubleToString(equity,2));
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
// Indicator buffer helper (as-series: out[0]=forming bar, out[1]=last
// closed bar, out[2]=the bar before it)
//======================================================================
int CopyBufferSeries(int handle,int bufferIndex,int count,double &out[])
{
   ArraySetAsSeries(out,true);
   int copied=CopyBuffer(handle,bufferIndex,0,count,out);
   if(copied<=0) return 0;
   return copied;
}

//======================================================================
// Entry execution (shared by the level-touch trigger)
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
// Level-touch entries: multi-timeframe swing-high/low (supply/demand)
// levels, raw tick touch, no reclaim/confirmation - learned from the old
// EzyMap "every zero-confluence level, no entry governors" build, now
// the ONLY entry source in V2 (not a supplement, as it was in V1) and
// covering six timeframes instead of four. Levels only rebuild on their
// OWN timeframe's new bar close, never intra-bar. Touch detection uses
// the same previous-vs-current-tick envelope crossing this session
// settled on, so a fast tick move through a level is never missed.
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

   TryOpenPosition(direction,"V2SND",slDistance);
}

void ProcessLevelTouches()
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

   double tolerance=InpLevelTouchTolerancePoints*_Point;

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      if(g_levels[i].price<=0.0) continue;

      bool touching=(observedHi>=g_levels[i].price-tolerance &&
                     observedLo<=g_levels[i].price+tolerance);

      g_levels[i].inZone=touching; // kept for drawing/diagnostics only

      if(!touching) continue;

      // Cooldown-only re-arm, per explicit "maximum trade frequency"
      // request: the reference file's "no entry governors" design does not
      // require price to fully leave the zone before a level can fire
      // again - only InpLevelReentrySeconds gates it. A level price is
      // chopping right at now fires repeatedly on cooldown instead of
      // going silent until a full round-trip out of the zone.
      if(TimeCurrent()<g_levels[i].cooldownUntil) continue;

      TryLevelEntry(g_levels[i].fadeDirection,g_levels[i].price);
      g_levels[i].cooldownUntil=TimeCurrent()+MathMax(0,InpLevelReentrySeconds);
   }

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
// Exit: trail-only, no TP. Activates once favourable excursion has run
// the full SL distance (never sooner - the activation-floor rule proven
// on the FRESH V3/V4 family this session, and ported to V1). Every
// candidate stop must land on the CORRECT SIDE of current price, not
// just far enough from it - a stale peak-based candidate can otherwise
// get rejected every attempt after a pullback (the bug found and fixed
// on V1 this session).
//======================================================================
void ManageTrailing()
{
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
// Chart drawing (12 SND levels + status label)
//======================================================================
void DrawLevels()
{
   if(!InpDrawLevels) return;

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      string name="V2_LVL_"+IntegerToString(i);
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

   if(InpDrawStatusLabel)
      DrawStatusLabel();
}

void DrawStatusLabel()
{
   string name="V2_StatusLabel";
   string text=StringFormat("EzyEA V2 | SND levels active=%d/%d | Open=%d/%d | %s",
                CountActiveLevels(),ArraySize(g_levels),
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

int CountActiveLevels()
{
   int n=0;
   for(int i=0;i<ArraySize(g_levels);i++)
      if(g_levels[i].price>0.0) n++;
   return n;
}

void RemoveAllDrawings()
{
   for(int i=ObjectsTotal(0,0,-1)-1;i>=0;i--)
   {
      string name=ObjectName(0,i,0,-1);
      if(StringFind(name,"V2_")==0)
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

   double equityNow=AccountInfoDouble(ACCOUNT_EQUITY);
   double drawdownPctNow=(g_peakEquity>0.0)?(g_peakEquity-equityNow)/g_peakEquity*100.0:0.0;

   Log("V2 LIVE PARITY STATUS"+
       " | SND levels active="+IntegerToString(CountActiveLevels())+"/"+IntegerToString(ArraySize(g_levels))+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
       " | drawdown="+DoubleToString(drawdownPctNow,2)+"%"+(g_tradingHalted?" (HALTED)":"")+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY));

   Log("V2 DEPLOYMENT GATE BREAKDOWN"+
       " | attempts="+IntegerToString(g_gateAttempts)+
       " | accepted="+IntegerToString(g_gateAccepted)+
       " | rejected="+IntegerToString(g_gateRejected)+
       " | spreadRejects="+IntegerToString(g_gateSpreadRejects)+
       " | concurrencyRejects="+IntegerToString(g_gateConcurrencyRejects)+
       " | distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " | sizingRejects="+IntegerToString(g_gateSizingRejects)+
       " | drawdownRejects="+IntegerToString(g_gateDrawdownRejects));
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

   Log("V2 FINAL REPORT"+
       " | trades="+IntegerToString(trades)+
       " | total lots traded="+DoubleToString(lotsTraded,2)+
       " | net P/L="+DoubleToString(netPnl,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
}
//+------------------------------------------------------------------+
