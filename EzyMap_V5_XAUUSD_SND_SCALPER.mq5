//+------------------------------------------------------------------+
//| EzyMap_V5_XAUUSD_SND_SCALPER.mq5                                  |
//+------------------------------------------------------------------+
//  EZYMAP V5 - GROUND-UP REBUILD, XAUUSD ONLY                        |
//                                                                    |
//  Built after a full prior session spent hardening the FRESH V3/V4  |
//  family's broker-execution robustness (retry-storm fixes on the    |
//  exit-close path, a zero-stops-level clearance fallback, an        |
//  auto-calibrating spread guard). Despite all of that, a live       |
//  attach of FRESH V3 to a real cent-account chart drew the account  |
//  down ~40% (270 -> 165 USC) in a session where Strategy Tester     |
//  runs on the identical EA never showed more than ~10% drawdown.    |
//  Investigation of the live journal/history confirmed the tester    |
//  structurally cannot reproduce broker-side rejections (FROZEN,     |
//  MARKET CLOSED, INVALID_STOPS) the way a real broker issues them,  |
//  so backtest results were never going to predict this EA family's |
//  live robustness. Per explicit instruction, V5 abandons the old    |
//  multi-layer/confluence trading logic entirely and is a brand new, |
//  deliberately simple design:                                       |
//                                                                    |
//  TRADE IDEA: a flat list of price LEVELS (not zones) made from the |
//  High and Low of every closed bar on H1, H4, D1 and W1. Direction  |
//  is decided purely by which side price approaches a level from at  |
//  the moment of touch - price rising up INTO a level from below     |
//  fires an instant SELL; price falling down INTO a level from above |
//  fires an instant BUY. No confluence filter - every qualifying     |
//  touch on every timeframe is a candidate trade. Fixed bracket only |
//  (TP 37 pips / SL 25 pips), submitted once at entry and NEVER      |
//  modified afterward - no trailing, no breakeven lock. This is a    |
//  deliberate structural choice: with nothing left to retry after    |
//  entry, V5 cannot suffer the "HYBRID VIRTUAL TRAIL CLOSE" retry-   |
//  storm class that dominated the prior session's live failures, by  |
//  construction rather than by patching around it.                   |
//                                                                    |
//  REUSED FROM FRESH V3 (EzyMap_V3_116_FRESH_V3_XAUUSDsc.mq5),        |
//  verbatim or near-verbatim, XAUUSD-only branches:                  |
//    - Cent-account sizing: ResolveAccountUnitDivisor(),              |
//      EffectiveAccountEquity(), LotSizingCapitalUnits(),             |
//      NormalizeVolumeDown(), MinimumTradingEquity().                 |
//    - Cent-aware pip sizing: StrategyPipSize() pattern               |
//      (InpXAUUSDscStrategyPipPrice / InpStandardXAUUSDStrategyPipPrice). |
//    - Auto-calibrating spread guard: SpreadAllowed() with the same   |
//      median*multiplier calibration and decoupled ceiling.           |
//    - Zero-stops-level clearance fallback: ZeroStopsLevelFallbackPrice() |
//      - the fix built after a real BTCUSD.sc log showed brokers can   |
//      report SYMBOL_TRADE_STOPS_LEVEL=0 while still enforcing a real  |
//      wider minimum - applied here to the fixed entry bracket instead |
//      of a trail modify.                                              |
//    - Retcode classification: TradeRetcodeAccepted() /                |
//      TemporaryTradeRetcode() - extended here to also classify        |
//      TRADE_RETCODE_MARKET_CLOSED as temporary/retryable, which was   |
//      missing from EVERY EA in this codebase and was confirmed live   |
//      via a user journal screenshot showing repeated "[Market closed]"|
//      entry rejections on XAUUSD.sc around a session boundary.        |
//    - The global order-request throttle pattern (OrderRequestThrottleOK()), |
//      originally added after a confirmed live entry-spam incident on  |
//      a different EzyMap build that cost real capital.                |
//                                                                    |
//  NEW FOR V5 (not present in any prior file):                       |
//    - Flat multi-timeframe level store with dedup, seeded from       |
//      history at OnInit and incrementally extended on each new bar   |
//      close per timeframe (see RefreshLevelsForTimeframe()).         |
//    - Edge-triggered touch/direction detection per level (see        |
//      ProcessLevelTouches()) - a level only fires on the tick it      |
//      freshly enters the touch tolerance band from a known side, not |
//      on every tick it happens to linger there, which by itself      |
//      already prevents a stationary whipsaw from firing every tick.  |
//    - A per-level cooldown (InpLevelReTouchCooldownMs) applied on     |
//      EVERY fire attempt, win or lose, plus an additional exponential |
//      backoff on genuine rejections (InpEntryRetryMinimumIntervalMs / |
//      InpEntryBackoffCooldownCapMs) - the same shape of fix already   |
//      proven for the exit-close retry storm, applied here on the      |
//      entry side before it has a chance to become one.                |
//    - Position-to-level binding via order comment ("V5@<price>"),     |
//      reconciled every tick by scanning open positions rather than    |
//      trusting CTrade's post-send ticket resolution (which is not     |
//      reliably the same ticket as the resulting position across       |
//      brokers/account modes) - this also means an EA restart/reattach |
//      correctly re-associates any still-open positions with their     |
//      source level without needing any persisted state.               |
//    - Risk-based lot sizing via OneLotLoss()/OrderCalcProfit(), with  |
//      an explicit journal line whenever the broker minimum lot floor  |
//      overrides the nominal risk-% target (expected and normal on a   |
//      true ~$100-scale account - 25 pips of XAUUSD risk on the        |
//      broker's minimum lot is already a large fraction of a balance   |
//      that small, so effective risk-% will usually exceed the nominal |
//      target there; this is reported, not hidden).                    |
//                                                                    |
//  EXPLICITLY NOT PORTED FROM V3/V4 (not needed by this design):     |
//    confluence scoring, supply/demand ZONE detection (replaced by    |
//    flat single-price levels), multi-layer position stacking,        |
//    HybridTrailState / ClosePositionAtVirtualTrail and the whole      |
//    virtual-trailing-close machinery (nothing to trail - fixed        |
//    bracket only), TouchConfirmationSatisfied()'s confirmation-candle |
//    wait (this design wants an instant touch trigger, not a delayed   |
//    confirmation).                                                    |
//                                                                    |
//  NOT YET VERIFIED: compiles in MetaEditor (no MQL5 toolchain in     |
//  this environment), or real trading performance - that is exactly   |
//  what the next live/demo run is for. Verified here: brace/paren/    |
//  bracket balance, and a manual audit that every input referenced in |
//  a log line or helper call is actually declared.                    |
//+------------------------------------------------------------------+
#property copyright "EzyMap"
#property link      ""
#property version   "5.0"
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
// InpTesterAutoModeIsStandard is turned off - a tester deposit must never
// be divided by 100 just because the historical symbol name ends in .sc.
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor   = 100.0;
input bool   InpTesterAutoModeIsStandard = true;
input bool   InpTreatSCSuffixAsCentOnLive = true;
input bool   InpEnableCentSafetyCaps     = true;
input double InpCentAbsoluteMaxLots      = 0.20;
input bool   InpUseBalanceForLotSizing   = true;
input bool   InpUseBrokerNativeDepositUnitsForLots = false;

// Minimum equity (in the same "effective" units used for sizing - real
// dollar-equivalent even on a cent account) below which V5 stops opening
// new trades entirely, regardless of what the risk-% formula would size.
input double InpCentMinimumEffectiveEquity = 5.0;
input double InpMinimumAccountEquity       = 20.0;

// Cent-aware pip sizing for XAUUSD.sc vs standard XAUUSD - same mechanism
// as FRESH V3's StrategyPipSize(), simplified since V5 is XAUUSD-only and
// has no "legacy" non-cent distances to preserve.
input bool   InpUseXAUUSDscBrokerPointPips  = true;
input double InpXAUUSDscStrategyPipPrice    = 0.01;
input double InpStandardXAUUSDStrategyPipPrice = 0.10;

// Fixed bracket - submitted once at entry, never modified afterward.
input double InpTakeProfitPips = 37.0;
input double InpStopLossPips   = 25.0;

// Level detection: every closed bar's High/Low on each timeframe becomes
// a permanent level once seeded. These lookback counts only bound the
// ONE-TIME historical seed at OnInit for scan-cost sanity; after that,
// each timeframe only ever adds ~1 new bar's worth of levels per period,
// which is negligible growth over any realistic run length.
input int    InpH1LevelLookbackBars = 2000;
input int    InpH4LevelLookbackBars = 1000;
input int    InpD1LevelLookbackBars = 500;
input int    InpW1LevelLookbackBars = 200;

// How close price must come to a level, in raw broker points, to count as
// a touch. Also used to dedup near-identical levels detected on different
// timeframes so the same real price isn't double-counted as two triggers.
input int    InpLevelTouchTolerancePoints = 20;

// Total concurrent open positions across all levels/directions combined.
input int    InpMaxConcurrentPositions = 6;

// Risk-based lot sizing: lots = (equity * risk%) / OneLotLoss(entry,sl).
// On a true ~$100-scale account this will usually round UP to the broker
// minimum lot rather than down to a fractional lot - see the header note.
input double InpRiskPercentPerTrade = 1.0;

// Auto-calibrating spread guard - identical mechanism to FRESH V3's
// SpreadAllowed(): while InpAutoCalibrateSpreadCap is on, the filter
// fails OPEN (allows trading) for the first InpSpreadCalibrationTicks
// ticks while it measures this broker's real median spread, then locks
// in effective_cap = median * InpSpreadCalibrationMultiplier (optionally
// clamped by InpMaxSpreadPoints if that is set above 0).
input int    InpMaxSpreadPoints          = 0;
input bool   InpAutoCalibrateSpreadCap   = true;
input int    InpSpreadCalibrationTicks   = 100;
input double InpSpreadCalibrationMultiplier = 3.0;

// Global floor on time between ANY two order-send requests, regardless of
// which level triggered them - the same single-choke-point pattern used
// in FRESH V3 after a confirmed live entry-spam incident.
input int    InpMinMsBetweenOrderRequests = 250;

// Per-level cooldown applied on EVERY fire attempt (win or lose), so a
// level whipsawing right at its price cannot re-fire faster than this,
// independent of the exponential backoff below which only engages on
// genuine broker rejections.
input int    InpLevelReTouchCooldownMs = 2000;

// Entry-side retry backoff on genuine rejections (mirrors this session's
// exit-close retry-storm fix, applied here on the entry side before it
// has a chance to become one).
input int    InpEntryRetryMinimumIntervalMs = 500;
input int    InpEntryBackoffCooldownCapMs   = 15000;

// Execution-distance safety for the fixed entry bracket.
input int    InpExecutionStopCushionPoints = 2;
input double InpZeroStopsLevelFallbackPct  = 0.05;

// Reporting.
input bool   InpPrintExecutionLog       = true;
input int    InpStatusReportIntervalSec = 60;

//------------------------------ Structs -------------------------------
struct LevelState
{
   double         price;
   datetime       barTime;
   ENUM_TIMEFRAMES sourceTf;
   int            lastSide;              // +1 above, -1 below, 0 = touching/unknown
   ulong          openTicket;            // 0 = no live trade bound to this level
   int            entryConsecutiveFailures;
   ulong          entryCooldownUntilMs;
};

LevelState g_levels[];

//------------------------------ Globals --------------------------------
double g_accountUnitDivisor = 1.0;
double g_pipSize            = 0.10;

double g_spreadCalSamples[];
int    g_spreadCalCount        = 0;
double g_spreadCalEffectiveCap = -1.0;

double g_lastOrderRequestMs = 0;

datetime g_lastH1BarTime = 0;
datetime g_lastH4BarTime = 0;
datetime g_lastD1BarTime = 0;
datetime g_lastW1BarTime = 0;

datetime g_lastStatusReportTime = 0;

long g_gateConcurrencyRejects = 0;
long g_gateCooldownRejects    = 0;
long g_gateSpreadRejects      = 0;
long g_gateDistanceRejects    = 0;
long g_orderSendAttempts      = 0;
long g_orderSendAccepted      = 0;
long g_orderSendRejected      = 0;

//------------------------------ Forward declarations --------------------
double ResolveAccountUnitDivisor();
string _UpperStr(string s);
double EffectiveAccountEquity();
double LotSizingCapitalUnits();
bool   IsLiveCentAccount();
double MinimumTradingEquity();
bool   IsCentSuffixSymbol();
double StrategyPipSize();
double RoundPrice(double v);
int    VolumeDigits();
double NormalizeVolumeDown(double vol);
double OneLotLoss(int direction,double entry,double sl);
double ComputeRiskLot(int direction,double entry,double sl);
double MedianOfSpreadSamples(double &values[],int count);
bool   SpreadAllowed();
bool   OrderRequestThrottleOK();
double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel);
bool   ExecutionDistanceValid(int direction,double entryPrice,double sl,double tp);
bool   TradeRetcodeAccepted(uint code);
bool   TemporaryTradeRetcode(uint code);
void   Log(string msg);
int    CountOurPositions();
int    CountOurPositionsByDirection(int direction);
void   AddLevel(double price,datetime barTime,ENUM_TIMEFRAMES tf);
void   RefreshLevelsForTimeframe(ENUM_TIMEFRAMES tf,datetime &lastBarTime,int lookbackBars);
int    FindLevelByPrice(double price);
bool   ParseLevelComment(string comment,double &outPrice);
void   ReconcileLevelBindings();
void   ProcessLevelTouches();
bool   TryFireLevel(int levelIndex,int direction);
void   ReportLiveParityStatus();
void   ReportDeploymentGateBreakdown();

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

double LotSizingCapitalUnits()
{
   double raw=InpUseBalanceForLotSizing
              ? AccountInfoDouble(ACCOUNT_BALANCE)
              : AccountInfoDouble(ACCOUNT_EQUITY);

   if(InpUseBrokerNativeDepositUnitsForLots)
      return MathMax(0.0,raw);

   return MathMax(0.0,raw/MathMax(1.0,g_accountUnitDivisor));
}

bool IsLiveCentAccount()
{
   return (!(bool)MQLInfoInteger(MQL_TESTER) && g_accountUnitDivisor>1.0);
}

double MinimumTradingEquity()
{
   if(g_accountUnitDivisor>1.0)
      return MathMax(0.0,InpCentMinimumEffectiveEquity);

   return MathMax(0.0,InpMinimumAccountEquity);
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

double OneLotLoss(int direction,double entry,double sl)
{
   if(entry<=0 || sl<=0) return 0.0;
   if(direction==1 && sl>=entry) return 0.0;
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

// Risk-based lot sizing. On a true ~$100-scale account the risk-% formula
// will usually round up to the broker minimum lot rather than down to a
// fractional lot - that is a real structural fact (25 pips of XAUUSD risk
// on 1.0 lot is a large dollar amount relative to $100), not a bug, so the
// resulting effective risk-% is logged explicitly whenever the minimum
// floor overrides the nominal target.
double ComputeRiskLot(int direction,double entry,double sl)
{
   double effectiveEquity=EffectiveAccountEquity();
   if(effectiveEquity<MinimumTradingEquity())
      return 0.0;

   double riskBudget=effectiveEquity*MathMax(0.0,InpRiskPercentPerTrade)/100.0;
   double lossPerLot=OneLotLoss(direction,entry,sl);
   if(lossPerLot<=0.0)
      return 0.0;

   double rawLots=riskBudget/lossPerLot;
   double lots=NormalizeVolumeDown(rawLots);

   double minVol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   bool flooredToMinimum=false;

   if(lots<minVol)
   {
      lots=minVol;
      flooredToMinimum=true;
   }

   if(InpEnableCentSafetyCaps && InpCentAbsoluteMaxLots>0.0)
      lots=MathMin(lots,InpCentAbsoluteMaxLots);

   lots=NormalizeVolumeDown(lots);
   if(lots<minVol)
      return 0.0;

   if(flooredToMinimum)
   {
      double actualRiskCash=lots*lossPerLot;
      double actualRiskPct=(effectiveEquity>0.0)?(actualRiskCash/effectiveEquity*100.0):0.0;

      Log("V5 LOT SIZE FLOORED TO BROKER MINIMUM"+
          " | nominal risk%="+DoubleToString(InpRiskPercentPerTrade,2)+
          " | effective risk%="+DoubleToString(actualRiskPct,2)+
          " | lots="+DoubleToString(lots,VolumeDigits())+
          " | equity="+DoubleToString(effectiveEquity,2));
   }

   return lots;
}

//------------------------------ Spread guard -----------------------------
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

      if(InpMaxSpreadPoints>0)
         effective=MathMin(effective,(double)InpMaxSpreadPoints);

      g_spreadCalEffectiveCap=MathMax(1.0,effective);

      Log("V5 SPREAD AUTO-CALIBRATION COMPLETE"+
          " | samples="+IntegerToString(g_spreadCalCount)+
          " | median observed="+DoubleToString(median,1)+" points"+
          " | multiplier="+DoubleToString(mult,2)+
          " | ceiling(InpMaxSpreadPoints)="+IntegerToString(InpMaxSpreadPoints)+
          (InpMaxSpreadPoints<=0?" (uncapped)":"")+
          " | EFFECTIVE CAP NOW ENFORCED="+
          DoubleToString(g_spreadCalEffectiveCap,1)+" points");
   }

   return true; // fail open while calibrating
}

bool OrderRequestThrottleOK()
{
   double nowMs=(double)GetTickCount64();
   if(g_lastOrderRequestMs>0.0 &&
      nowMs-g_lastOrderRequestMs<(double)MathMax(0,InpMinMsBetweenOrderRequests))
      return false;

   g_lastOrderRequestMs=nowMs;
   return true;
}

//------------------------------ Execution-distance safety ----------------
double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel)
{
   if(stopsLevel>0 || freezeLevel>0 || referencePrice<=0.0)
      return 0.0;
   return referencePrice*MathMax(0.0,InpZeroStopsLevelFallbackPct)/100.0;
}

bool ExecutionDistanceValid(int direction,double entryPrice,double sl,double tp)
{
   if(entryPrice<=0.0 || sl<=0.0 || tp<=0.0)
      return false;

   long stopsLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double minimumDistance=
      MathMax(_Point,
              ((double)MathMax(stopsLevel,freezeLevel)+
               MathMax(0,InpExecutionStopCushionPoints))*_Point)+
      ZeroStopsLevelFallbackPrice(entryPrice,stopsLevel,freezeLevel);

   if(direction==1)
   {
      if(sl>entryPrice-minimumDistance+_Point*0.25) return false;
      if(tp<entryPrice+minimumDistance-_Point*0.25) return false;
      return true;
   }

   if(sl<entryPrice+minimumDistance-_Point*0.25) return false;
   if(tp>entryPrice-minimumDistance+_Point*0.25) return false;
   return true;
}

//------------------------------ Retcode classification --------------------
bool TradeRetcodeAccepted(uint code)
{
   return (code==TRADE_RETCODE_DONE ||
           code==TRADE_RETCODE_PLACED ||
           code==TRADE_RETCODE_DONE_PARTIAL);
}

// V5: TRADE_RETCODE_MARKET_CLOSED is included here from day one - it was
// confirmed missing from every prior EA in this codebase, and confirmed
// live via a user journal screenshot showing repeated "[Market closed]"
// entry rejections on XAUUSD.sc, retried by the deployment-retry interval
// but never actually classified as "temporary" in the EA's own reporting.
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
void AddLevel(double price,datetime barTime,ENUM_TIMEFRAMES tf)
{
   if(price<=0.0) return;

   double tol=MathMax(0,InpLevelTouchTolerancePoints)*_Point;
   int n=ArraySize(g_levels);

   for(int i=0;i<n;i++)
      if(MathAbs(g_levels[i].price-price)<=tol)
         return; // dedup: an equivalent real price is already tracked

   ArrayResize(g_levels,n+1,256);
   g_levels[n].price=price;
   g_levels[n].barTime=barTime;
   g_levels[n].sourceTf=tf;
   g_levels[n].lastSide=0;
   g_levels[n].openTicket=0;
   g_levels[n].entryConsecutiveFailures=0;
   g_levels[n].entryCooldownUntilMs=0;
}

// Seeds the historical lookback window the first time it is called for a
// timeframe (lastBarTime==0), then on every later call only walks back as
// far as needed to cover any bars that closed since the previous check -
// correct even across a gap where the EA was detached/offline for a
// while, since it stops as soon as it reaches a bar time already seen.
void RefreshLevelsForTimeframe(ENUM_TIMEFRAMES tf,datetime &lastBarTime,int lookbackBars)
{
   datetime currentBarTime=iTime(_Symbol,tf,0);
   if(currentBarTime==0) return; // no history loaded yet for this timeframe

   if(lastBarTime==0)
   {
      int totalBars=iBars(_Symbol,tf);
      int bars=MathMin(MathMax(0,lookbackBars),MathMax(0,totalBars-1));

      for(int shift=bars;shift>=1;shift--)
      {
         datetime bt=iTime(_Symbol,tf,shift);
         if(bt==0) continue;
         AddLevel(iHigh(_Symbol,tf,shift),bt,tf);
         AddLevel(iLow(_Symbol,tf,shift),bt,tf);
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
      AddLevel(iHigh(_Symbol,tf,shift),bt,tf);
      AddLevel(iLow(_Symbol,tf,shift),bt,tf);
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
// the level store. Deliberately does NOT rely on CTrade's post-send ticket
// resolution (ResultOrder()/ResultDeal() are not reliably the resulting
// POSITION ticket across every broker/account mode) - this same pass also
// correctly re-associates any still-open positions with their source level
// after an EA restart/reattach, with no persisted state required.
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
}

//------------------------------ Touch detection / entry -------------------
bool TryFireLevel(int levelIndex,int direction)
{
   ulong nowMs=GetTickCount64();

   if(nowMs<g_levels[levelIndex].entryCooldownUntilMs)
   {
      g_gateCooldownRejects++;
      return false;
   }

   if(CountOurPositions()>=InpMaxConcurrentPositions)
   {
      g_gateConcurrencyRejects++;
      return false;
   }

   if(!OrderRequestThrottleOK())
   {
      g_gateCooldownRejects++;
      return false;
   }

   if(!SpreadAllowed())
   {
      g_gateSpreadRejects++;
      return false;
   }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;

   double entryPrice=(direction==1)?tick.ask:tick.bid;
   double slDistance=MathMax(0.1,InpStopLossPips)*g_pipSize;
   double tpDistance=MathMax(0.1,InpTakeProfitPips)*g_pipSize;

   double sl=RoundPrice(direction==1?entryPrice-slDistance:entryPrice+slDistance);
   double tp=RoundPrice(direction==1?entryPrice+tpDistance:entryPrice-tpDistance);

   if(!ExecutionDistanceValid(direction,entryPrice,sl,tp))
   {
      g_gateDistanceRejects++;
      return false;
   }

   double lots=ComputeRiskLot(direction,entryPrice,sl);
   if(lots<=0.0)
      return false;

   // Baseline cooldown applied on EVERY attempt, win or lose, so a
   // whipsaw at the exact level price cannot re-fire faster than
   // InpLevelReTouchCooldownMs - independent of the exponential backoff
   // below, which only extends this further on genuine rejections.
   g_levels[levelIndex].entryCooldownUntilMs=
      nowMs+(ulong)MathMax(0,InpLevelReTouchCooldownMs);

   string comment="V5@"+DoubleToString(g_levels[levelIndex].price,_Digits);

   g_orderSendAttempts++;
   bool sent=(direction==1)
             ? trade.Buy(lots,_Symbol,entryPrice,sl,tp,comment)
             : trade.Sell(lots,_Symbol,entryPrice,sl,tp,comment);

   uint code=trade.ResultRetcode();
   bool accepted=sent && TradeRetcodeAccepted(code);

   if(accepted)
   {
      g_orderSendAccepted++;
      g_levels[levelIndex].entryConsecutiveFailures=0;

      Log("V5 ENTRY | "+(direction==1?"BUY":"SELL")+
          " | level="+DoubleToString(g_levels[levelIndex].price,_Digits)+
          " (tf="+EnumToString(g_levels[levelIndex].sourceTf)+")"+
          " | entry="+DoubleToString(entryPrice,_Digits)+
          " | sl="+DoubleToString(sl,_Digits)+
          " | tp="+DoubleToString(tp,_Digits)+
          " | lots="+DoubleToString(lots,VolumeDigits()));

      // The exact resulting position ticket is bound on the next tick's
      // ReconcileLevelBindings() pass via the order comment, rather than
      // trusted here from trade.ResultOrder()/ResultDeal() - see that
      // function's header comment for why.
      return true;
   }

   g_orderSendRejected++;
   bool temporary=TemporaryTradeRetcode(code);
   int failCount=++g_levels[levelIndex].entryConsecutiveFailures;

   int backoff=(int)MathMin(
      (double)MathMax(0,InpEntryBackoffCooldownCapMs),
      (double)MathMax(0,InpEntryRetryMinimumIntervalMs)*
      (double)(1<<MathMin(failCount,10)));

   ulong cooldownUntil=nowMs+
      (ulong)MathMax(MathMax(0,InpLevelReTouchCooldownMs),backoff);
   g_levels[levelIndex].entryCooldownUntilMs=cooldownUntil;

   Log("V5 ENTRY FAILED | "+(direction==1?"BUY":"SELL")+
       " | level="+DoubleToString(g_levels[levelIndex].price,_Digits)+
       " | temporary="+string(temporary?"YES":"NO")+
       " | consecutive failures="+IntegerToString(failCount)+
       " | next retry in="+IntegerToString((int)(cooldownUntil-nowMs))+"ms"+
       " | retcode="+IntegerToString((int)code)+
       " | "+trade.ResultRetcodeDescription());

   return false;
}

// Runs every tick. For each level: if it has a live trade bound, verify
// the position still exists (clear the binding and re-arm the level the
// instant it does not); otherwise evaluate touch/direction. A level only
// fires on the tick it freshly enters the touch-tolerance band from a
// known side (side flips from non-zero to zero) - not on every tick it
// happens to linger inside the band - which by itself already prevents a
// stationary whipsaw from firing every single tick, before the cooldown
// in TryFireLevel() even engages.
void ProcessLevelTouches()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;

   double tol=MathMax(0,InpLevelTouchTolerancePoints)*_Point;
   double refPrice=tick.bid;

   int n=ArraySize(g_levels);
   for(int i=0;i<n;i++)
   {
      if(g_levels[i].openTicket!=0)
      {
         if(!PositionSelectByTicket(g_levels[i].openTicket))
            g_levels[i].openTicket=0;
         else
            continue; // blocked while a trade from this level is open
      }

      double lvl=g_levels[i].price;
      int side;
      if(refPrice>lvl+tol) side=1;
      else if(refPrice<lvl-tol) side=-1;
      else side=0;

      if(side==0 && g_levels[i].lastSide!=0)
      {
         // lastSide==-1: price was below the level, just rose into it -
         //   "cmp touch the level above it" -> SELL (direction=-1).
         // lastSide==+1: price was above the level, just fell into it -
         //   "cmp touch the level below it" -> BUY (direction=+1).
         int direction=(g_levels[i].lastSide==-1)?-1:1;
         TryFireLevel(i,direction);
      }

      g_levels[i].lastSide=side;
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
       "/"+IntegerToString(InpMaxConcurrentPositions)+
       " | levels with open trade="+IntegerToString(openLevels)+
       " | BUY="+IntegerToString(CountOurPositionsByDirection(1))+
       " SELL="+IntegerToString(CountOurPositionsByDirection(-1))+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+
       " | divisor="+DoubleToString(g_accountUnitDivisor,1)+
       " | pipSize="+DoubleToString(g_pipSize,_Digits));
}

void ReportDeploymentGateBreakdown()
{
   Log("V5 DEPLOYMENT GATE BREAKDOWN"+
       " | CONCURRENCY CAP REJECTED="+IntegerToString((int)g_gateConcurrencyRejects)+
       " | COOLDOWN REJECTED="+IntegerToString((int)g_gateCooldownRejects)+
       " | SPREAD REJECTED="+IntegerToString((int)g_gateSpreadRejects)+
       " | EXECUTION-DISTANCE REJECTED="+IntegerToString((int)g_gateDistanceRejects)+
       " | ORDER-SEND ATTEMPTS="+IntegerToString((int)g_orderSendAttempts)+
       " | ACCEPTED="+IntegerToString((int)g_orderSendAccepted)+
       " | REJECTED="+IntegerToString((int)g_orderSendRejected));
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

   g_spreadCalCount=0;
   g_spreadCalEffectiveCap=-1.0;
   ArrayResize(g_spreadCalSamples,MathMax(20,InpSpreadCalibrationTicks));
   g_lastOrderRequestMs=0;

   g_gateConcurrencyRejects=0;
   g_gateCooldownRejects=0;
   g_gateSpreadRejects=0;
   g_gateDistanceRejects=0;
   g_orderSendAttempts=0;
   g_orderSendAccepted=0;
   g_orderSendRejected=0;
   g_lastStatusReportTime=0;

   RefreshLevelsForTimeframe(PERIOD_H1,g_lastH1BarTime,InpH1LevelLookbackBars);
   RefreshLevelsForTimeframe(PERIOD_H4,g_lastH4BarTime,InpH4LevelLookbackBars);
   RefreshLevelsForTimeframe(PERIOD_D1,g_lastD1BarTime,InpD1LevelLookbackBars);
   RefreshLevelsForTimeframe(PERIOD_W1,g_lastW1BarTime,InpW1LevelLookbackBars);

   ReconcileLevelBindings();

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();
   trade.SetAsyncMode(false);

   Log("V5 INIT"+
       " | symbol="+_Symbol+
       " | cent-suffix="+string(IsCentSuffixSymbol()?"YES":"NO")+
       " | account divisor="+DoubleToString(g_accountUnitDivisor,1)+
       " | pipSize="+DoubleToString(g_pipSize,_Digits)+
       " | levels seeded="+IntegerToString(ArraySize(g_levels))+
       " | TP="+DoubleToString(InpTakeProfitPips,1)+"p"+
       " | SL="+DoubleToString(InpStopLossPips,1)+"p"+
       " | maxConcurrent="+IntegerToString(InpMaxConcurrentPositions)+
       " | riskPerTrade="+DoubleToString(InpRiskPercentPerTrade,2)+"%");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
}

void OnTick()
{
   RefreshLevelsForTimeframe(PERIOD_H1,g_lastH1BarTime,InpH1LevelLookbackBars);
   RefreshLevelsForTimeframe(PERIOD_H4,g_lastH4BarTime,InpH4LevelLookbackBars);
   RefreshLevelsForTimeframe(PERIOD_D1,g_lastD1BarTime,InpD1LevelLookbackBars);
   RefreshLevelsForTimeframe(PERIOD_W1,g_lastW1BarTime,InpW1LevelLookbackBars);

   ReconcileLevelBindings();
   ProcessLevelTouches();

   if(InpStatusReportIntervalSec>0 &&
      TimeCurrent()-g_lastStatusReportTime>=InpStatusReportIntervalSec)
   {
      g_lastStatusReportTime=TimeCurrent();
      ReportLiveParityStatus();
      ReportDeploymentGateBreakdown();
   }
}
