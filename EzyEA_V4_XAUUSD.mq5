//+------------------------------------------------------------------+
//|                                             EzyEA_V4_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V4 - entry logic replicated from the "EzyMap Scalp Mastery   |
//| V3.184" reference file ("EVERY_ZERO_CONF_LEVEL_NO_ENTRY_GOVERNORS  |
//| SL24_TRAIL13"), per explicit request. Overwrites the earlier       |
//| EzyEA_V4_XAUUSD.mq5 (a copytrade master-account edition, a          |
//| different objective entirely) per explicit confirmation - that     |
//| file is retired.                                                    |
//|                                                                      |
//| LEVEL SYSTEM - replaces the swing-pivot SND+EMA13 engine used by     |
//| V1/V2/V3 with the reference's nearest-bar-CLOSE level system          |
//| (confirmed via direct code reading, not the filename alone):          |
//|   - H1 "current map": every new H1 bar, S1/R1 = the nearest H1 bar     |
//|     CLOSE below/above the last closed M5 bar's close within              |
//|     InpDirectionHistory (48) bars; S2/R2 = the next support/               |
//|     resistance close at least InpH1MinSeparationPips (70) further out.      |
//|   - H4/D1/W1 "outer levels": one nearest support + one nearest              |
//|     resistance close each, same close-anchored rule, wider minimum           |
//|     separation per timeframe (70/120/200 pips) - NOT the swing-pivot          |
//|     high/low system V1/V3 use; this file's levels are always the              |
//|     nearest historical bar CLOSE, no pivot/rejection qualification.            |
//|   - No M5/M15/EMA13 entry source at all - the reference's M5 role is           |
//|     purely to supply the H1 map's reference price, not to generate              |
//|     its own tradeable level or EMA touch.                                       |
//|                                                                                   |
//| ZONE PRECISION (explicit request): each level's touch tolerance is                |
//| derived from its own anchor bar's close-to-high (resistance) or                    |
//| close-to-low (support) distance, not the full candle high-low range,               |
//| floored at a minimum so a near-zero-wick bar still gets a usable zone.              |
//|                                                                                       |
//| RE-ENTRY: state-based, matching the reference exactly - not a time-                  |
//| based cooldown like V1/V2/V3. A level fires once, then will not fire                  |
//| again while price stays inside its touch zone; it only re-arms after                  |
//| price fully leaves the zone and returns.                                                |
//|                                                                                           |
//| NO ENTRY GOVERNORS (matching the reference's naming exactly, confirmed                   |
//| via code reading that its own directional-losing-cap/M5-closed-loss-                      |
//| cap/daily-risk-lock/layer-cap machinery is disabled both by input                          |
//| default AND by not being wired into its live entry path at all): no                        |
//| trend filter, no per-direction concurrency cap. The portfolio drawdown                      |
//| breaker stays as a basic safety backstop though (it does not limit                           |
//| entry frequency, only caps worst-case tail risk), same as the existing                        |
//| spread guard and portfolio margin check - EzyEA's own established                              |
//| distinction between "strategic filter" (dropped) and "basic execution                          |
//| correctness" (kept).                                                                             |
//|                                                                                                     |
//| EXIT - hybrid virtual trail (same mechanism as V1.1/V2.1/V3: a virtual                              |
//| stop tracked in EA memory, checked every tick, enforced by a direct                                  |
//| close independent of the broker accepting a tight SL modify; broker-                                 |
//| side SL still pushed as a best-effort backup, clamped to the closest                                  |
//| legal distance), with the reference's exact preset: InpPresetStopLossPips                             |
//| = 24, InpTrailingDistancePips = 13.                                                                     |
//|                                                                                                          |
//| LIVE PARITY (explicit request, ported from the reference's live-only                                    |
//| trail-arming guards): on a genuine live XAUUSD.sc chart (never in the                                    |
//| Strategy Tester), three extra conditions gate trail activation beyond                                    |
//| InpTrailActivationPips (0 = immediate in tester):                                                        |
//|   - InpLiveXAURequireFullTrailBeforeArm: activation distance is raised                                   |
//|     to at least the full trail distance (13 pips), not just the pip                                     |
//|     threshold alone.                                                                                     |
//|   - InpLiveXAUIncludeSpreadInTrailArm: the current live spread is added                                  |
//|     on top of the activation distance.                                                                   |
//|   - InpLiveXAUTrailWarmupSeconds (15): the trail cannot arm until this                                   |
//|     many seconds have passed since the EA first saw the position - a                                     |
//|     restart mid-trade cannot immediately treat a position as "already                                    |
//|     favourable enough to arm."                                                                           |
//| InpLiveXAUDisableHistoricalPeakRebuild also disables M1 peak                                              |
//| reconstruction specifically on a live XAUUSD.sc chart (peak starts at                                     |
//| the current tick only), matching the same live-vs-tester parity intent.                                   |
//| All of this is inert in the tester (InpReconstructPeakFromM1 still                                         |
//| reconstructs normally there) and on any non-live/non-.sc chart.                                             |
//|                                                                                                              |
//| Everything else unchanged from EzyEA V1 of this generation: risk-based                                       |
//| lot sizing via OrderCalcProfit() (InpRiskPercentPerTrade - kept, NOT the                                      |
//| reference's flat lot-per-$100-balance table, per explicit prior decision                                      |
//| this session to keep honest risk-%-of-equity sizing), portfolio-aware                                          |
//| margin check, TimeCurrent()-based modify backoff, the zero-stops-level                                         |
//| broker fallback, auto-calibrating spread guard, cent-account-aware                                             |
//| equity handling (InpScaleRiskByCentDivisor stays FALSE, same reasoning                                          |
//| already confirmed multiple times this session), and full premium chart                                         |
//| drawing (theme, portfolio trade card, gold live-levels, historical                                              |
//| win/loss markers) matching V3's standard.                                                                        |
//|                                                                                                                    |
//| Distinct magic number (190040) and order-comment/object-prefix tags                                              |
//| (V4SND, V4_ chart objects) so this can run alongside V1/V1.1/V2/V2.1/                                            |
//| V3/V3.1/V3.2/V3b/V3(BTCUSD) without cross-talk.                                                                   |
//|                                                                                                                      |
//| CHANGELOG                                                                                                           |
//| 4.000 - Initial build: entry logic replicated from EzyMap Scalp                                                     |
//|         Mastery V3.184 (H1 nearest-close current map + H4/D1/W1                                                     |
//|         outer levels, close-derived zone tolerance, state-based                                                     |
//|         re-entry, no entry governors), hybrid virtual-trail exit                                                    |
//|         (preset 24p / trail 13p) with live-parity trail-arming                                                      |
//|         guards, full premium chart drawing. Forked from                                                             |
//|         EzyEA_V1_XAUUSD.mq5 1.000.                                                                                   |
//+------------------------------------------------------------------+
#property copyright "EzyEA"
#property version   "4.000"
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
input group "=== Level System: H1 current map + H4/D1/W1 outer levels ==="
// Replicates the EzyMap Scalp Mastery V3.184 reference's entry-trigger
// logic: levels are always the nearest historical bar CLOSE (never a
// swing-pivot high/low), rebuilt on every new bar of their own
// timeframe. H1 gets S1/S2/R1/R2 (nearest + next-nearest close each
// side); H4/D1/W1 each get one nearest support + one nearest
// resistance close. Reference price for H1 is the last CLOSED M5
// bar's close.
input bool   InpEnableLevelTouchEntries     = true;
input int    InpDirectionHistory            = 48;    // H1 lookback bars for S1/S2/R1/R2
input double InpH1MinSeparationPips         = 70.0;
input int    InpH4LookbackBars              = 48;
input double InpH4MinSeparationPips         = 70.0;
input int    InpD1LookbackBars              = 48;
input double InpD1MinSeparationPips         = 120.0;
input int    InpW1LookbackBars              = 48;
input double InpW1MinSeparationPips         = 200.0;
// Per-level touch tolerance is derived from that level's own anchor
// bar's close-to-high (resistance) or close-to-low (support) distance
// - this input is only a FLOOR for when that distance is too small to
// be a usable zone (e.g. a near-zero-wick bar).
input double InpLevelTouchToleranceMinPoints = 15.0;

input group "=== Stops / Trail (fixed pips) ==="
// Exact preset from the reference file: SL24 / TRAIL13.
input double InpPresetStopLossPips          = 24.0;
input double InpTrailingDistancePips        = 13.0;
input double InpTrailActivationPips         = 0.0;
input double InpXAUUSDscPipPrice            = 0.10;
input double InpStandardXAUUSDPipPrice      = 0.10;
input double InpTrailMinStepPoints          = 20.0;

input group "=== Hybrid Virtual Trail ==="
input bool   InpUseVirtualTrailFallback     = true;
input int    InpVirtualTrailCloseDeviationPts = 30;
input bool   InpReconstructPeakFromM1       = true;

input group "=== Live Parity (live XAUUSD.sc chart only, inert in tester) ==="
// Ported from the reference file's live-only trail-arming guards - a
// restart mid-trade or a fresh live attach cannot immediately treat a
// position as "already favourable enough to arm," the way it can in
// the Strategy Tester where these are all inert.
input bool   InpLiveXAUProtectionParity     = true;
input bool   InpLiveXAURequireFullTrailBeforeArm = true;
input bool   InpLiveXAUIncludeSpreadInTrailArm   = true;
input int    InpLiveXAUTrailWarmupSeconds   = 15;
input bool   InpLiveXAUDisableHistoricalPeakRebuild = true;

input group "=== Exit Management ==="
input int    InpMaxHoldingMinutes           = 30;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) ==="
input bool   InpEnableDrawdownBreaker       = true;
input double InpMaxEquityDrawdownPct        = 10.0;
input double InpDrawdownResumeFactor        = 0.5;

input group "=== Risk / Sizing ==="
input double InpRiskPercentPerTrade         = 0.25;
input bool   InpScaleRiskByCentDivisor      = false;
input int    InpMaxConcurrentPositions      = 500;
input double InpMaxLotsAbsolute             = 5.0;
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
input ulong  InpMagicNumber                 = 190040;
input int    InpDeviationPoints             = 30;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Chart Drawing ==="
input bool   InpDrawLevels                  = true;
input bool   InpDrawStatusLabel             = true;

input group "=== Chart Drawing: Premium Theme ==="
input bool   InpApplyPremiumTheme           = true;
input color  InpChartBackground             = C'8,11,15';
input color  InpChartForeground             = C'176,185,195';
input color  InpBullCandleColor             = C'0,208,142';
input color  InpBearCandleColor             = C'235,72,96';
input bool   InpHideNativeTickerOHLC        = true;
input bool   InpShowTradeCard               = true;
input color  InpPanelColor                  = C'7,10,14';
input color  InpPanelBorderColor            = C'56,65,76';
input color  InpBuyColor                    = C'0,208,142';
input color  InpSellColor                   = C'235,72,96';
input color  InpNeutralColor                = C'204,211,218';
input bool   InpShowLiveTradeLevels         = true;
input color  InpTradeLevelGold              = C'255,215,0';
input bool   InpShowHistoricalMarkers       = true;
input int    InpMaxHistoricalMarkers        = 100;

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
   datetime firstSeenTime;     // when this EA first saw this ticket - live-parity warmup timer
};

struct LevelTouchState
{
   double   price;
   double   tolerance;        // per-level touch tolerance, derived from close-to-high/low
   int      fadeDirection;    // 1 = demand (support), fade BUY; -1 = supply (resistance), fade SELL
   bool     inZone;
   bool     consumed;         // state-based re-entry: fires once, resets only after price leaves the zone
   string   tfLabel;
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

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

// H1: S1/S2/R1/R2 (indices 0-3). H4: S/R (4-5). D1: S/R (6-7). W1: S/R (8-9).
LevelTouchState g_levels[10];

// All four level groups share one M5-close-driven rebuild gate: the
// reference price they're all anchored to (last closed M5 close)
// only changes on a new M5 bar, so that is the natural cadence to
// re-evaluate "nearest close to reference" for every timeframe.
datetime g_lastLevelRebuildM5Time = 0;

bool   g_hasPreviousCMP = false;
double g_previousCMP    = 0.0;

datetime g_histMarkerTimes[];
double   g_histMarkerPrices[];
bool     g_histMarkerWins[];
int      g_histMarkerCount = 0;
ulong    g_lastSeenDealTicket = 0;

//======================================================================
// Forward declarations
//======================================================================
int    OnInit();
void   OnDeinit(const int reason);
void   OnTick();

string Upper(string s);
bool   IsGold();
bool   IsCentSuffixSymbol();
bool   IsLiveXAUUSDscProtectionChart();
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

void   TryOpenPosition(int direction,string tag,double slDistance);

double ReconstructPeakFromM1(int direction,double entry,double current,datetime positionTime);
bool   CloseAtVirtualStop(ulong ticket,string context,double current,double stop,double peak);
int    EnsureManagedSlot(ulong ticket);
void   PruneManagedSlots();
void   ModifyPositionSafely(ulong ticket,double sl,double tp);
void   ManageTrailing();
void   EnforceMaxHoldingTime();

bool   FindNearestCloses(ENUM_TIMEFRAMES tf,int lookback,double reference,double minSeparation,
                         bool wantSecondTier,
                         double &s1,datetime &s1Time,double &s2,datetime &s2Time,
                         double &r1,datetime &r1Time,double &r2,datetime &r2Time);
double LevelToleranceFromAnchor(ENUM_TIMEFRAMES tf,datetime anchorTime,int fadeDirection);
void   SetLevelSlot(int idx,double price,int fadeDirection,double tolerance,string tfLabel);
void   RebuildH1CurrentMap();
void   RebuildOuterLevel(int slotBase,ENUM_TIMEFRAMES tf,int lookback,double minSeparation,string tfLabel);
void   UpdateLevelsOnNewBars();
void   TryLevelEntry(int direction,double levelPrice);
void   ProcessTouchTriggers();

void   ApplyPremiumChartTheme();
void   DrawTradeCard();
void   DrawLiveTradeLevels();
void   AddHistoricalMarker(bool win,datetime tm,double price);
void   RemoveOldestHistoricalMarker();
void   ClearHistoricalMarkers();
void   CheckForClosedDeals();

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
      Log("EzyEA V4 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

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
      g_levels[i].tolerance=0.0;
      g_levels[i].fadeDirection=0;
      g_levels[i].inZone=false;
      g_levels[i].consumed=false;
      g_levels[i].tfLabel="";
   }
   g_lastLevelRebuildM5Time = 0;

   g_hasPreviousCMP=false;
   g_previousCMP=0.0;

   g_peakEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted=false;

   ArrayResize(g_histMarkerTimes,0);
   ArrayResize(g_histMarkerPrices,0);
   ArrayResize(g_histMarkerWins,0);
   g_histMarkerCount=0;
   g_lastSeenDealTicket=0;

   ApplyPremiumChartTheme();

   Log("EzyEA V4 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/trade="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max concurrent="+IntegerToString(InpMaxConcurrentPositions)+" (no entry governors)"+
       " | max holding="+IntegerToString(InpMaxHoldingMinutes)+" min"+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF")+
       " | preset="+DoubleToString(InpPresetStopLossPips,0)+"p trail="+DoubleToString(InpTrailingDistancePips,0)+"p"+
       " | live parity="+(InpLiveXAUProtectionParity?"ON":"OFF")+
       " | levels=H1(4)+H4/D1/W1(2 each)=10");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();
   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();

   if(InpEnableLevelTouchEntries)
   {
      UpdateLevelsOnNewBars();
      ProcessTouchTriggers();
      DrawLevels();
   }

   ManageTrailing();
   EnforceMaxHoldingTime();
   CheckForClosedDeals();
   DrawTradeCard();
   DrawLiveTradeLevels();
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

// True only outside the Strategy Tester, on a gold symbol carrying a
// cent-style suffix - the live-parity trail-arming guards are inert
// everywhere else (tester runs, non-XAU symbols, standard-suffix live
// symbols).
bool IsLiveXAUUSDscProtectionChart()
{
   if(!InpLiveXAUProtectionParity) return false;
   if((bool)MQLInfoInteger(MQL_TESTER)) return false;
   return IsGold() && IsCentSuffixSymbol();
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
   Print("EzyEA V4 | ",msg);
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
// Entry execution (shared by all level triggers). No entry governors:
// no trend filter, no per-direction cap - matching the reference
// file's "NO_ENTRY_GOVERNORS" naming, confirmed via code reading that
// its own directional-losing-cap/M5-closed-loss-cap/daily-risk-lock/
// layer-cap machinery is disabled both by input default AND by not
// being wired into its live entry path. The drawdown breaker below is
// a basic safety backstop, not an entry governor - it doesn't limit
// which signals fire, only caps worst-case tail risk.
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
// Level system: replicates the EzyMap Scalp Mastery V3.184 reference's
// entry-trigger logic. Levels are always the nearest historical bar
// CLOSE (never a swing-pivot high/low) relative to a shared reference
// price (the last closed M5 bar's close) - H1 gets a full S1/S2/R1/R2
// "current map", H4/D1/W1 each get one nearest support + one nearest
// resistance ("outer levels"). All four groups rebuild together on
// every new M5 bar close, since that is what moves the reference price
// they are all anchored to.
//======================================================================
bool FindNearestCloses(ENUM_TIMEFRAMES tf,int lookback,double reference,double minSeparation,
                       bool wantSecondTier,
                       double &s1,datetime &s1Time,double &s2,datetime &s2Time,
                       double &r1,datetime &r1Time,double &r2,datetime &r2Time)
{
   s1=0.0; s2=0.0; r1=0.0; r2=0.0;
   s1Time=0; s2Time=0; r1Time=0; r2Time=0;

   bool foundS1=false, foundR1=false;

   for(int shift=1;shift<=lookback;shift++)
   {
      double c=iClose(_Symbol,tf,shift);
      if(c<=0.0) continue;
      datetime t=iTime(_Symbol,tf,shift);

      if(c<=reference && (!foundS1 || c>s1))
      {
         s1=c; s1Time=t; foundS1=true;
      }
      if(c>=reference && (!foundR1 || c<r1))
      {
         r1=c; r1Time=t; foundR1=true;
      }
   }

   if(!foundS1 && !foundR1) return false;

   if(wantSecondTier)
   {
      bool foundS2=false, foundR2=false;
      double s1Floor=foundS1?(s1-minSeparation):-DBL_MAX;
      double r1Ceil =foundR1?(r1+minSeparation):DBL_MAX;

      for(int shift=1;shift<=lookback;shift++)
      {
         double c=iClose(_Symbol,tf,shift);
         if(c<=0.0) continue;
         datetime t=iTime(_Symbol,tf,shift);

         if(foundS1 && c<=s1Floor && (!foundS2 || c>s2))
         {
            s2=c; s2Time=t; foundS2=true;
         }
         if(foundR1 && c>=r1Ceil && (!foundR2 || c<r2))
         {
            r2=c; r2Time=t; foundR2=true;
         }
      }
   }

   return true;
}

// Zone precision (explicit request): the touch tolerance around a
// level is derived from that level's own anchor bar's close-to-high
// (resistance/SELL) or close-to-low (support/BUY) distance, not the
// full candle high-low range - a wick can be a brief spike; the close
// is where price actually settled. Floored at
// InpLevelTouchToleranceMinPoints so a near-zero-wick bar still gets a
// usable zone.
double LevelToleranceFromAnchor(ENUM_TIMEFRAMES tf,datetime anchorTime,int fadeDirection)
{
   double floorTol=MathMax(0.0,InpLevelTouchToleranceMinPoints)*_Point;
   if(anchorTime<=0) return floorTol;

   int shift=iBarShift(_Symbol,tf,anchorTime,true);
   if(shift<0) return floorTol;

   double h=iHigh(_Symbol,tf,shift);
   double l=iLow(_Symbol,tf,shift);
   double c=iClose(_Symbol,tf,shift);
   if(h<=0.0 || l<=0.0 || c<=0.0) return floorTol;

   double dist=(fadeDirection==-1)?(h-c):(c-l);
   return MathMax(floorTol,dist);
}

void SetLevelSlot(int idx,double price,int fadeDirection,double tolerance,string tfLabel)
{
   if(idx<0 || idx>=ArraySize(g_levels)) return;

   if(price<=0.0)
   {
      g_levels[idx].price=0.0;
      g_levels[idx].tolerance=0.0;
      g_levels[idx].fadeDirection=0;
      g_levels[idx].inZone=false;
      g_levels[idx].consumed=false;
      g_levels[idx].tfLabel="";
      return;
   }

   g_levels[idx].price=RoundPrice(price);
   g_levels[idx].fadeDirection=fadeDirection;
   g_levels[idx].tolerance=tolerance;
   g_levels[idx].tfLabel=tfLabel;
   // inZone/consumed are deliberately NOT reset here - a rebuild that
   // reproduces the same level shouldn't let a position that already
   // fired re-fire immediately just because the slot was repopulated.
}

void RebuildH1CurrentMap()
{
   double reference=iClose(_Symbol,PERIOD_M5,1);
   if(reference<=0.0) return;

   double minSep=MathMax(0.0,InpH1MinSeparationPips)*StrategyPipSize();

   double s1,s2,r1,r2;
   datetime s1Time,s2Time,r1Time,r2Time;
   if(!FindNearestCloses(PERIOD_H1,MathMax(1,InpDirectionHistory),reference,minSep,true,
                          s1,s1Time,s2,s2Time,r1,r1Time,r2,r2Time))
      return;

   SetLevelSlot(0,s1,1, LevelToleranceFromAnchor(PERIOD_H1,s1Time,1), "H1-S1");
   SetLevelSlot(1,s2,1, LevelToleranceFromAnchor(PERIOD_H1,s2Time,1), "H1-S2");
   SetLevelSlot(2,r1,-1,LevelToleranceFromAnchor(PERIOD_H1,r1Time,-1),"H1-R1");
   SetLevelSlot(3,r2,-1,LevelToleranceFromAnchor(PERIOD_H1,r2Time,-1),"H1-R2");
}

void RebuildOuterLevel(int slotBase,ENUM_TIMEFRAMES tf,int lookback,double minSeparationPips,string tfLabel)
{
   double reference=iClose(_Symbol,PERIOD_M5,1);
   if(reference<=0.0) return;

   double minSep=MathMax(0.0,minSeparationPips)*StrategyPipSize();

   double s1,s2,r1,r2;
   datetime s1Time,s2Time,r1Time,r2Time;
   if(!FindNearestCloses(tf,MathMax(1,lookback),reference,minSep,false,
                          s1,s1Time,s2,s2Time,r1,r1Time,r2,r2Time))
      return;

   SetLevelSlot(slotBase,  s1,1, LevelToleranceFromAnchor(tf,s1Time,1), tfLabel+"-S");
   SetLevelSlot(slotBase+1,r1,-1,LevelToleranceFromAnchor(tf,r1Time,-1),tfLabel+"-R");
}

void UpdateLevelsOnNewBars()
{
   if(!InpEnableLevelTouchEntries) return;

   datetime m5=iTime(_Symbol,PERIOD_M5,0);
   if(m5==0 || m5==g_lastLevelRebuildM5Time) return;
   g_lastLevelRebuildM5Time=m5;

   RebuildH1CurrentMap();
   RebuildOuterLevel(4,PERIOD_H4,InpH4LookbackBars,InpH4MinSeparationPips,"H4");
   RebuildOuterLevel(6,PERIOD_D1,InpD1LookbackBars,InpD1MinSeparationPips,"D1");
   RebuildOuterLevel(8,PERIOD_W1,InpW1LookbackBars,InpW1MinSeparationPips,"W1");
}

void TryLevelEntry(int direction,double levelPrice)
{
   double slDistance=PresetSlDistance();
   if(slDistance<=0.0) return;

   TryOpenPosition(direction,"V4SND",slDistance);
}

//======================================================================
// Touch trigger processing. Direction is by level type (support=BUY,
// resistance=SELL), never by which side price approached from - touch
// = immediate trade, no reclaim/confirmation required, matching the
// reference exactly. Re-entry is STATE-based, not time-based: a level
// fires once (consumed=true) and will not fire again while price stays
// inside its touch zone; it only re-arms once price fully leaves the
// zone (consumed resets to false the moment it's observed out-of-zone).
//======================================================================
void ProcessTouchTriggers()
{
   if(!InpEnableLevelTouchEntries) return;

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

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      if(g_levels[i].price<=0.0) continue;

      double tolerance=(g_levels[i].tolerance>0.0)
                       ?g_levels[i].tolerance
                       :MathMax(0.0,InpLevelTouchToleranceMinPoints)*_Point;

      bool touching=(observedHi>=g_levels[i].price-tolerance &&
                     observedLo<=g_levels[i].price+tolerance);

      if(!touching)
      {
         g_levels[i].inZone=false;
         g_levels[i].consumed=false;
         continue;
      }

      g_levels[i].inZone=true;

      if(g_levels[i].consumed) continue;

      TryLevelEntry(g_levels[i].fadeDirection,g_levels[i].price);
      g_levels[i].consumed=true;
   }

   g_previousCMP=cmp;
   g_hasPreviousCMP=true;
}

//======================================================================
// Per-position management state (backoff + peak tracking + live-parity
// warmup timer)
//======================================================================
double ReconstructPeakFromM1(int direction,double entry,double current,datetime positionTime)
{
   double peak=current;

   if(!InpReconstructPeakFromM1 || positionTime<=0)
      return peak;

   // Live parity: on a genuine live XAUUSD.sc chart, skip historical M1
   // reconstruction entirely - the peak starts at the current tick
   // only, so a restart mid-trade cannot immediately treat a position
   // as "already favourable" purely from replayed history.
   if(IsLiveXAUUSDscProtectionChart() && InpLiveXAUDisableHistoricalPeakRebuild)
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
   g_managed[idx].firstSeenTime=TimeCurrent();
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
// Exit 1: hybrid virtual trail, no TP - preset SL 24 pips, trail 13
// pips (exact reference values). Real protection no longer depends on
// the broker accepting a tight SL modify() - a virtual stop is tracked
// in EA memory and checked every tick; the moment price crosses it the
// position is force-closed directly. The broker-side SL is still
// pushed via the existing backoff-protected ModifyPositionSafely as a
// best-effort backup net, clamped to whatever distance the broker will
// actually accept.
//
// Live parity: on a genuine live XAUUSD.sc chart, trail activation
// requires the FULL trail distance (not just InpTrailActivationPips),
// adds the current spread on top, and cannot arm until
// InpLiveXAUTrailWarmupSeconds have passed since the EA first saw the
// position - a restart mid-trade cannot immediately treat a position
// as "already favourable enough to arm." All inert in the tester.
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
      double favorable=(direction==1)?(peak-openPrice):(openPrice-peak);

      double activationDistance=TrailActivationDistance();
      bool liveParity=IsLiveXAUUSDscProtectionChart();
      bool warmedUp=true;

      if(liveParity)
      {
         if(InpLiveXAURequireFullTrailBeforeArm)
            activationDistance=MathMax(activationDistance,trailDistance);

         if(InpLiveXAUIncludeSpreadInTrailArm)
         {
            MqlTick liveTick;
            if(SymbolInfoTick(_Symbol,liveTick))
               activationDistance+=MathMax(0.0,liveTick.ask-liveTick.bid);
         }

         warmedUp=(TimeCurrent()-g_managed[slot].firstSeenTime)>=MathMax(0,InpLiveXAUTrailWarmupSeconds);
      }

      // WIDE preset floor from entry - always the starting protection,
      // regardless of activation state.
      if(g_managed[slot].virtualStop<=0.0)
         g_managed[slot].virtualStop=RoundPrice((direction==1)?openPrice-slDistance:openPrice+slDistance);

      if(warmedUp && favorable>=activationDistance)
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
// resolved yet.
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
// Premium presentation: dark chart theme, portfolio trade card, gold
// live entry/SL/virtual-trail lines per open position, small win/loss
// markers at each closed trade. Purely visual - no effect on entries
// or exits.
//======================================================================
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

void DrawTradeCard()
{
   if(!InpShowTradeCard)
   {
      ObjectDelete(0,"V4_CARD_PANEL");
      for(int i=0;i<8;i++)
         ObjectDelete(0,"V4_CARD_ROW_"+IntegerToString(i));
      return;
   }

   int buys =CountOpenPositionsByDirection(1);
   int sells=CountOpenPositionsByDirection(-1);
   int total=buys+sells;

   double floatingPl=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      floatingPl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }

   int rows=6;
   string panel="V4_CARD_PANEL";
   if(ObjectFind(0,panel)<0)
      ObjectCreate(0,panel,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,panel,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
   ObjectSetInteger(0,panel,OBJPROP_XDISTANCE,14);
   ObjectSetInteger(0,panel,OBJPROP_YDISTANCE,38);
   ObjectSetInteger(0,panel,OBJPROP_XSIZE,290);
   ObjectSetInteger(0,panel,OBJPROP_YSIZE,20+rows*17);
   ObjectSetInteger(0,panel,OBJPROP_BGCOLOR,InpPanelColor);
   ObjectSetInteger(0,panel,OBJPROP_BORDER_COLOR,InpPanelBorderColor);
   ObjectSetInteger(0,panel,OBJPROP_COLOR,InpPanelBorderColor);
   ObjectSetInteger(0,panel,OBJPROP_STYLE,STYLE_SOLID);
   ObjectSetInteger(0,panel,OBJPROP_WIDTH,1);
   ObjectSetInteger(0,panel,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,panel,OBJPROP_BACK,false);

   color plColor=(floatingPl>0.0)?InpBuyColor:(floatingPl<0.0?InpSellColor:InpNeutralColor);

   string rowText[6];
   color  rowColor[6];
   rowText[0]=_Symbol+" - EzyEA V4";                                             rowColor[0]=InpNeutralColor;
   rowText[1]="OPEN  "+IntegerToString(total)+"  (BUY "+IntegerToString(buys)+" / SELL "+IntegerToString(sells)+")"; rowColor[1]=InpNeutralColor;
   rowText[2]="FLOATING P/L  "+DoubleToString(floatingPl,2)+" "+AccountInfoString(ACCOUNT_CURRENCY); rowColor[2]=plColor;
   rowText[3]="LEVELS  "+IntegerToString(CountActiveLevels())+"/"+IntegerToString(ArraySize(g_levels)); rowColor[3]=InpNeutralColor;
   rowText[4]="EXIT  preset="+DoubleToString(InpPresetStopLossPips,0)+"p trail="+DoubleToString(InpTrailingDistancePips,0)+"p" +(IsLiveXAUUSDscProtectionChart()?" [LIVE PARITY]":""); rowColor[4]=InpNeutralColor;
   rowText[5]=g_tradingHalted?"DRAWDOWN BREAKER: HALTED":"STATUS: ACTIVE"; rowColor[5]=g_tradingHalted?InpSellColor:InpBuyColor;

   for(int r=0;r<rows;r++)
   {
      string n="V4_CARD_ROW_"+IntegerToString(r);
      if(ObjectFind(0,n)<0)
         ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_RIGHT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_RIGHT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,30);
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,50+r*17);
      ObjectSetInteger(0,n,OBJPROP_COLOR,rowColor[r]);
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,(r==0)?9:8);
      ObjectSetString(0,n,OBJPROP_FONT,(r==0)?"Arial Bold":"Arial");
      ObjectSetString(0,n,OBJPROP_TEXT,rowText[r]);
      ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   }
}

void DrawLiveTradeLevels()
{
   if(!InpShowLiveTradeLevels)
   {
      ObjectsDeleteAll(0,"V4_LIVE_");
      return;
   }

   ObjectsDeleteAll(0,"V4_LIVE_");

   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;

      string key=IntegerToString((int)ticket);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   =PositionGetDouble(POSITION_SL);

      string entryName="V4_LIVE_ENTRY_"+key;
      if(ObjectFind(0,entryName)<0)
         ObjectCreate(0,entryName,OBJ_HLINE,0,0,entry);
      ObjectSetDouble(0,entryName,OBJPROP_PRICE,entry);
      ObjectSetInteger(0,entryName,OBJPROP_COLOR,InpTradeLevelGold);
      ObjectSetInteger(0,entryName,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,entryName,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,entryName,OBJPROP_BACK,true);
      ObjectSetInteger(0,entryName,OBJPROP_SELECTABLE,false);

      if(sl>0.0)
      {
         string slName="V4_LIVE_SL_"+key;
         if(ObjectFind(0,slName)<0)
            ObjectCreate(0,slName,OBJ_HLINE,0,0,sl);
         ObjectSetDouble(0,slName,OBJPROP_PRICE,sl);
         ObjectSetInteger(0,slName,OBJPROP_COLOR,InpTradeLevelGold);
         ObjectSetInteger(0,slName,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,slName,OBJPROP_WIDTH,2);
         ObjectSetInteger(0,slName,OBJPROP_BACK,true);
         ObjectSetInteger(0,slName,OBJPROP_SELECTABLE,false);
      }

      int slot=EnsureManagedSlot(ticket);
      if(slot>=0 && g_managed[slot].virtualStop>0.0)
      {
         string vName="V4_LIVE_VSL_"+key;
         if(ObjectFind(0,vName)<0)
            ObjectCreate(0,vName,OBJ_HLINE,0,0,g_managed[slot].virtualStop);
         ObjectSetDouble(0,vName,OBJPROP_PRICE,g_managed[slot].virtualStop);
         ObjectSetInteger(0,vName,OBJPROP_COLOR,InpTradeLevelGold);
         ObjectSetInteger(0,vName,OBJPROP_STYLE,STYLE_DOT);
         ObjectSetInteger(0,vName,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,vName,OBJPROP_BACK,true);
         ObjectSetInteger(0,vName,OBJPROP_SELECTABLE,false);
      }
   }
}

void RemoveOldestHistoricalMarker()
{
   if(g_histMarkerCount<=0) return;

   ObjectDelete(0,"V4_HIST_"+IntegerToString(0));

   for(int i=1;i<g_histMarkerCount;i++)
   {
      string old="V4_HIST_"+IntegerToString(i);
      string fresh="V4_HIST_"+IntegerToString(i-1);
      if(ObjectFind(0,old)>=0)
         ObjectSetString(0,old,OBJPROP_NAME,fresh);

      g_histMarkerTimes[i-1] =g_histMarkerTimes[i];
      g_histMarkerPrices[i-1]=g_histMarkerPrices[i];
      g_histMarkerWins[i-1]  =g_histMarkerWins[i];
   }

   g_histMarkerCount--;
   ArrayResize(g_histMarkerTimes,g_histMarkerCount);
   ArrayResize(g_histMarkerPrices,g_histMarkerCount);
   ArrayResize(g_histMarkerWins,g_histMarkerCount);
}

void ClearHistoricalMarkers()
{
   ObjectsDeleteAll(0,"V4_HIST_");
   ArrayResize(g_histMarkerTimes,0);
   ArrayResize(g_histMarkerPrices,0);
   ArrayResize(g_histMarkerWins,0);
   g_histMarkerCount=0;
}

void AddHistoricalMarker(bool win,datetime tm,double price)
{
   if(!InpShowHistoricalMarkers) return;
   if(tm<=0 || price<=0.0) return;

   int cap=MathMax(1,InpMaxHistoricalMarkers);
   while(g_histMarkerCount>=cap)
      RemoveOldestHistoricalMarker();

   int idx=g_histMarkerCount;
   ArrayResize(g_histMarkerTimes,idx+1);
   ArrayResize(g_histMarkerPrices,idx+1);
   ArrayResize(g_histMarkerWins,idx+1);
   g_histMarkerTimes[idx] =tm;
   g_histMarkerPrices[idx]=price;
   g_histMarkerWins[idx]  =win;
   g_histMarkerCount++;

   string n="V4_HIST_"+IntegerToString(idx);
   if(ObjectFind(0,n)<0)
      ObjectCreate(0,n,OBJ_TEXT,0,tm,price);
   else
      ObjectMove(0,n,0,tm,price);

   ObjectSetString(0,n,OBJPROP_TEXT,win?"W":"L");
   ObjectSetInteger(0,n,OBJPROP_COLOR,win?InpBuyColor:InpSellColor);
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,8);
   ObjectSetInteger(0,n,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetString(0,n,OBJPROP_FONT,"Arial Bold");
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
}

//======================================================================
// Scans newly-closed deals (DEAL_ENTRY_OUT) for this EA's magic number
// and drops a small win/loss marker at the close price/time. Tracks
// the highest deal ticket already seen so each deal is only marked
// once; a cold start (fresh chart attach) seeds from the newest
// existing deal rather than replaying all history as markers.
//======================================================================
void CheckForClosedDeals()
{
   if(!InpShowHistoricalMarkers) return;

   if(g_lastSeenDealTicket==0)
   {
      if(!HistorySelect(0,TimeCurrent())) return;
      ulong newest=0;
      int total=HistoryDealsTotal();
      for(int i=0;i<total;i++)
      {
         ulong dealTicket=HistoryDealGetTicket(i);
         if(dealTicket>newest) newest=dealTicket;
      }
      g_lastSeenDealTicket=newest;
      return;
   }

   if(!HistorySelect(0,TimeCurrent())) return;

   int total=HistoryDealsTotal();
   for(int i=0;i<total;i++)
   {
      ulong dealTicket=HistoryDealGetTicket(i);
      if(dealTicket<=g_lastSeenDealTicket) continue;
      if(dealTicket>g_lastSeenDealTicket) g_lastSeenDealTicket=dealTicket;

      if(HistoryDealGetString(dealTicket,DEAL_SYMBOL)!=_Symbol) continue;
      if((ulong)HistoryDealGetInteger(dealTicket,DEAL_MAGIC)!=InpMagicNumber) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket,DEAL_ENTRY)!=DEAL_ENTRY_OUT) continue;

      double profit=HistoryDealGetDouble(dealTicket,DEAL_PROFIT)+
                    HistoryDealGetDouble(dealTicket,DEAL_SWAP)+
                    HistoryDealGetDouble(dealTicket,DEAL_COMMISSION);
      double price =HistoryDealGetDouble(dealTicket,DEAL_PRICE);
      datetime tm  =(datetime)HistoryDealGetInteger(dealTicket,DEAL_TIME);

      AddHistoricalMarker(profit>=0.0,tm,price);
   }
}

//======================================================================
// Chart drawing (10 levels: H1 S1/S2/R1/R2 + H4/D1/W1 S/R)
//======================================================================
void DrawLevels()
{
   if(!InpDrawLevels) return;

   for(int i=0;i<ArraySize(g_levels);i++)
   {
      string name="V4_LVL_"+IntegerToString(i);
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

int CountActiveLevels()
{
   int n=0;
   for(int i=0;i<ArraySize(g_levels);i++)
      if(g_levels[i].price>0.0) n++;
   return n;
}

void DrawStatusLabel()
{
   string name="V4_StatusLabel";
   string text=StringFormat("EzyEA V4 | Levels active=%d/%d | Open=%d/%d | %s",
                CountActiveLevels(),ArraySize(g_levels),
                CountOpenPositions(),InpMaxConcurrentPositions,
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
      if(StringFind(name,"V4_")==0)
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

   Log("V4 LIVE PARITY STATUS"+
       " | levels active="+IntegerToString(CountActiveLevels())+"/"+IntegerToString(ArraySize(g_levels))+
       " | open="+IntegerToString(CountOpenPositions())+"/"+IntegerToString(InpMaxConcurrentPositions)+
       " | drawdown="+DoubleToString(ddPct,2)+"%"+(g_tradingHalted?" (HALTED)":"")+
       " | live parity="+(IsLiveXAUUSDscProtectionChart()?"ACTIVE":"inert")+
       " | equity="+DoubleToString(EffectiveAccountEquity(),2)+" "+AccountInfoString(ACCOUNT_CURRENCY));

   Log("V4 DEPLOYMENT GATE BREAKDOWN"+
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

   Log("V4 FINAL REPORT"+
       " | trades="+IntegerToString(trades)+
       " | total lots traded="+DoubleToString(lotsTraded,2)+
       " | net P/L="+DoubleToString(netPnl,2)+" "+AccountInfoString(ACCOUNT_CURRENCY));
}
//+------------------------------------------------------------------+
