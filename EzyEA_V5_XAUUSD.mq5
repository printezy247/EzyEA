//+------------------------------------------------------------------+
//|                                             EzyEA_V5_XAUUSD.mq5  |
//|                                                                    |
//| EzyEA V5 - ground-up build, a genuinely new strategy shape rather   |
//| than a refinement of the V1-V4 SND/EMA touch-fade lineage. Target:   |
//| high-frequency XAUUSD scalping specifically during volatile market   |
//| windows, using layered (pyramid) entries, volatility-scaled targets   |
//| and stops, and designed for an ultra-low-latency VPS (~2.5ms or       |
//| below to the broker) so execution assumes essentially no slippage      |
//| budget is needed beyond normal broker order-book noise.                 |
//|                                                                            |
//| DESIGN CHOICES (resolved with the user before writing any code,           |
//| each a real fork with financial-safety implications):                      |
//| 1. LAYERING MODE = ANTI-MARTINGALE PYRAMID, not classic martingale.         |
//|    Additional layers are only added when price has already moved            |
//|    FAVOURABLY from the basket's weighted entry (scaling into a winner),      |
//|    each new layer SMALLER than the last (InpPyramidSizeRatio). This           |
//|    deliberately does NOT average down into a loser - the user was             |
//|    offered true/capped martingale as an option and explicitly chose            |
//|    this safer shape instead, because literal martingale on a wide-             |
//|    spread broker at high entry frequency has genuine account-blowup            |
//|    tail risk on a real trending day (every adverse layer needs a               |
//|    bigger reversal just to break even, spread cost compounds per                |
//|    layer). "Cover losses if any" from the original request is handled           |
//|    instead by the basket-level equity stop below, not by an averaging-          |
//|    down mechanism.                                                                |
//| 2. ENTRY SIGNAL = VOLATILITY FADE / MEAN REVERSION on M1: a bar closes             |
//|    outside a Bollinger Band, the next bar closes back inside -> fade               |
//|    toward the mean. Entries are additionally gated by a volatility                  |
//|    filter (fast ATR vs its own slower baseline) so the EA only fires                 |
//|    into genuinely volatile windows ("scalping gold setup when market                  |
//|    volatile") rather than fading routine noise that would just bleed                   |
//|    to the 30-40 point spread this is tuned for.                                          |
//| 3. BASKET-LEVEL HARD STOP = fixed % of equity (InpBasketMaxLossEquityPct),                |
//|    not ATR-scaled - the user explicitly chose predictability of worst-                    |
//|    case drawdown over an adaptive-but-harder-to-reason-about threshold.                     |
//|                                                                                                |
//| MECHANICS                                                                                      |
//| - Only ONE basket (a same-direction sequence of pyramid layers) is                             |
//|   ever active at a time in this build, by deliberate scope choice -                             |
//|   a fresh fade signal in the opposite direction while a basket is                                |
//|   still open is ignored rather than flipping/hedging. Revisit if the                              |
//|   user wants concurrent baskets both directions later.                                             |
//| - Each layer carries its own WIDE, static, ATR-scaled structural SL                                 |
//|   (InpStructuralSlAtrMult, broker-enforced at order-send) purely as a                                |
//|   catastrophic/gap backstop - it is not expected to be the normal exit                                |
//|   path. The REAL exit logic is basket-level, checked every tick:                                       |
//|     (a) basket trailing stop - arms once the basket's combined                                          |
//|         favourable excursion from its weighted entry clears an ATR-                                      |
//|         scaled activation distance, then trails behind the peak by an                                     |
//|         ATR-scaled distance ("hold ... to ride on the wins").                                               |
//|     (b) basket equity stop - fixed % of equity, force-closes every                                          |
//|         open layer in the basket immediately, independent of (a).                                            |
//| - Reuses this codebase's proven infrastructure verbatim in spirit:                                             |
//|   cent-account detection/scaling (ResolveAccountUnitDivisor/                                                    |
//|   EffectiveAccountEquity), risk-%-of-equity lot sizing via                                                       |
//|   OrderCalcProfit() (OneLotLoss), auto-calibrating spread guard,                                                  |
//|   retcode classification (including TRADE_RETCODE_MARKET_CLOSED),                                                 |
//|   and an overall portfolio drawdown breaker as a basic safety                                                     |
//|   backstop distinct from the basket-level equity stop (established                                                 |
//|   EzyEA-family distinction: "strategic filter" vs "basic execution                                                  |
//|   safety" - the latter is always kept regardless of strategy shape).                                                 |
//| - Assumes a hedging-mode account (multiple simultaneous same-symbol                                                   |
//|   positions), matching every other EzyEA variant's assumption - a                                                      |
//|   netting-mode account will auto-merge layers into one net position                                                     |
//|   and per-layer tracking here will degrade to a volume-based                                                              |
//|   approximation (not specifically handled, same as the rest of the                                                        |
//|   family).                                                                                                                   |
//| - No confluence/trend filter beyond the volatility gate itself, by                                                            |
//|   deliberate choice to maximize entry frequency (matching this whole                                                            |
//|   codebase's established zero-confluence philosophy) - a known,                                                                  |
//|   accepted trade-off, not an oversight.                                                                                            |
//| - Market orders only, TimeCurrent()-based timing throughout (never                                                                    |
//|   GetTickCount64, which reflects real CPU time and is meaningless in                                                                    |
//|   the Strategy Tester) - built assuming an ultra-low-latency VPS so no                                                                   |
//|   slippage-defensive geometry is needed beyond normal broker distance                                                                     |
//|   rules.                                                                                                                                     |
//|                                                                                                                                                 |
//| SCOPE NOTE: v1 of this build keeps chart drawing to a compact status                                                                            |
//| label, live basket entry/trail/SL lines, and the Bollinger Band plot -                                                                           |
//| the fuller trade-card/historical-marker presentation from V1-V4 is                                                                                |
//| intentionally deferred to keep this first build's scope manageable;                                                                                 |
//| easy to add on request once the strategy itself is validated in the                                                                                    |
//| tester.                                                                                                                                                 |
//|                                                                                                                                                           |
//| CHANGELOG                                                                                                                                                 |
//| 1.000 - Initial build.                                                                                                                                    |
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
input group "=== Volatility Gate (M1) - only trade into volatile windows ==="
input int    InpAtrFastPeriod               = 14;
input int    InpAtrSlowPeriod               = 50;
// Fast ATR must be at least this many times the slow-ATR baseline for
// the market to be considered "volatile" enough to trade.
input double InpVolatilityMultiplier        = 1.3;

input group "=== Entry Signal: M1 Bollinger Band Fade (mean reversion) ==="
input int    InpBBPeriod                    = 20;
input double InpBBDeviation                 = 2.0;
// A bar closes outside the band, then the NEXT closed bar closes back
// inside -> fade toward the mean. Evaluated once per new closed M1 bar.

input group "=== Anti-Martingale Pyramid Layering ==="
input int    InpMaxPyramidLayers            = 3;
// Each added layer's volume = previous layer's volume * this ratio
// (<1.0 = decreasing size, the anti-martingale convention).
input double InpPyramidSizeRatio            = 0.6;
// Price must move this many ATR(fast) multiples further in favour of
// the basket, from the MOST RECENT layer's own entry, before the next
// layer is added.
input double InpPyramidStepAtrMult          = 1.0;
input int    InpPyramidMinSecondsBetweenLayers = 5;

input group "=== Structural SL (per layer, catastrophic backstop only) ==="
// Wide and static - not expected to be the normal exit path. The real
// exit logic is the basket-level trail/equity-stop below.
input double InpStructuralSlAtrMult         = 3.0;

input group "=== Basket Exit: Trailing (ride the wins) ==="
input double InpBasketTrailActivationAtrMult = 1.5;
input double InpBasketTrailDistanceAtrMult   = 0.8;

input group "=== Basket Exit: Hard Equity Stop (cover losses) ==="
// Fixed % of equity, not ATR-scaled - user's explicit choice for a
// predictable worst-case-per-basket figure.
input double InpBasketMaxLossEquityPct      = 3.0;

input group "=== Backstop: Max Holding Time (safety net, not a strategy exit) ==="
input int    InpMaxHoldingMinutes           = 180;

input group "=== Overall Drawdown Circuit Breaker (peak since attach) ==="
input bool   InpEnableDrawdownBreaker       = true;
input double InpMaxEquityDrawdownPct        = 10.0;
input double InpDrawdownResumeFactor        = 0.5;

input group "=== Risk / Sizing (first layer; later layers decay by InpPyramidSizeRatio) ==="
input double InpRiskPercentPerTrade         = 0.25;
input double InpMaxLotsAbsolute             = 5.0;
input double InpMaxMarginUsePct             = 40.0;

input group "=== Spread Guard (auto-calibrating) ==="
input bool   InpAutoCalibrateSpreadCap      = true;
input int    InpSpreadCalibrationTicks      = 200;
input double InpSpreadCalibrationMultiplier = 2.5;
input int    InpMaxSpreadPoints             = 400;

input group "=== Cent-Account Handling ==="
input ENUM_EZY_ACCOUNT_SCALE InpAccountScaleMode = EZY_ACCOUNT_AUTO;
input double InpCentAccountUnitDivisor      = 100.0;
input bool   InpTesterAutoModeIsStandard    = true;
input bool   InpTreatSCSuffixAsCentOnLive   = true;

input group "=== Execution (tuned for ultra-low-latency VPS) ==="
input ulong  InpMagicNumber                 = 190050;
input int    InpDeviationPoints             = 10;

input group "=== Reporting ==="
input int    InpStatusLogIntervalSeconds    = 60;

input group "=== Chart Drawing ==="
input bool   InpApplyPremiumTheme           = true;
input color  InpChartBackground             = C'8,11,15';
input color  InpChartForeground             = C'176,185,195';
input color  InpBullCandleColor             = C'0,208,142';
input color  InpBearCandleColor             = C'235,72,96';
input bool   InpHideNativeTickerOHLC        = true;
input bool   InpDrawBands                   = true;
input int    InpDrawBarsBack                = 60;
input bool   InpDrawStatusLabel             = true;
input bool   InpShowLiveTradeLevels         = true;
input color  InpBuyColor                    = C'0,208,142';
input color  InpSellColor                   = C'235,72,96';
input color  InpTradeLevelGold              = C'255,215,0';

//======================================================================
// Types
//======================================================================
struct PyramidBasket
{
   bool     active;
   int      direction;         // 1 buy, -1 sell
   int      layerCount;
   ulong    tickets[8];
   double   lastLayerEntryPrice;
   double   peakFavorablePrice; // best price reached since basket open
   bool     trailActive;
   double   trailStopPrice;
   datetime openTime;
   datetime lastLayerTime;
   double   atrAtOpen;          // ATR(fast) snapshot at basket open, used for this basket's trail/step math
};

//======================================================================
// Globals
//======================================================================
CTrade trade;

int g_handleAtrFast = INVALID_HANDLE;
int g_handleAtrSlow = INVALID_HANDLE;
int g_handleBB      = INVALID_HANDLE;

datetime g_lastM1BarTime = 0;

double g_accountUnitDivisor = 1.0;

double g_spreadCalSamples[];
int    g_spreadCalCount        = 0;
double g_spreadCalEffectiveCap = -1.0;

double g_peakEquity    = 0.0;
bool   g_tradingHalted = false;

PyramidBasket g_basket;

datetime g_lastStatusLogTime = 0;

int g_gateAttempts           = 0;
int g_gateAccepted           = 0;
int g_gateRejected           = 0;
int g_gateSpreadRejects      = 0;
int g_gateVolatilityRejects  = 0;
int g_gateDistanceRejects    = 0;
int g_gateSizingRejects      = 0;
int g_gateDrawdownRejects    = 0;

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
double ComputeFirstLayerLots(int direction,double entry,double sl);

bool   TradeRetcodeAccepted(uint code);
bool   TemporaryTradeRetcode(uint code);

double ZeroStopsLevelFallbackPrice(double referencePrice,long stopsLevel,long freezeLevel);
double MinimumStopDistance(double referencePrice);

int    SpreadCalibrationTicksEffective();
double MedianOfSpreadSamples(double &values[],int count);
bool   SpreadAllowed();

int    CopyBufferSeries(int handle,int bufferIndex,int count,double &out[]);

void   CloseAllPositions(string reason);
void   UpdateDrawdownBreaker();

double CurrentAtrFast();
bool   IsMarketVolatile(double &atrFastOut);

void   CheckFadeSignalOnNewM1Bar();
void   OpenBasket(int direction,double atrFast);
void   TryAddPyramidLayer(double atrFast);
bool   SubmitLayerOrder(int direction,double lots,double structuralSlDistance,ulong &ticketOut);

void   PruneBasketTickets();
void   UpdateBasketPeakAndTrail(double atrFast);
double BasketFloatingPnL();
void   ManageBasketExit(double atrFast);
void   CloseBasket(string reason);
void   EnforceMaxHoldingTime();

void   DrawBands();
void   DrawStatusLabel();
void   DrawLiveTradeLevels();
void   ApplyPremiumChartTheme();
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
      Log("EzyEA V5 is XAUUSD-only. Attach to a XAUUSD/XAUUSD.sc chart. Current symbol="+_Symbol);
      return INIT_FAILED;
   }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);

   g_handleAtrFast = iATR(_Symbol,PERIOD_M1,MathMax(2,InpAtrFastPeriod));
   g_handleAtrSlow = iATR(_Symbol,PERIOD_M1,MathMax(2,InpAtrSlowPeriod));
   g_handleBB      = iBands(_Symbol,PERIOD_M1,MathMax(2,InpBBPeriod),0,InpBBDeviation,PRICE_CLOSE);

   if(g_handleAtrFast==INVALID_HANDLE || g_handleAtrSlow==INVALID_HANDLE || g_handleBB==INVALID_HANDLE)
   {
      Log("Indicator handle creation failed.");
      return INIT_FAILED;
   }

   g_lastM1BarTime = 0;

   g_accountUnitDivisor = ResolveAccountUnitDivisor();

   int capacity = SpreadCalibrationTicksEffective();
   ArrayResize(g_spreadCalSamples,capacity);
   g_spreadCalCount        = 0;
   g_spreadCalEffectiveCap = -1.0;

   g_peakEquity    = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradingHalted = false;

   g_basket.active = false;
   g_basket.direction = 0;
   g_basket.layerCount = 0;
   for(int i=0;i<8;i++) g_basket.tickets[i]=0;
   g_basket.lastLayerEntryPrice = 0.0;
   g_basket.peakFavorablePrice  = 0.0;
   g_basket.trailActive         = false;
   g_basket.trailStopPrice      = 0.0;
   g_basket.openTime            = 0;
   g_basket.lastLayerTime       = 0;
   g_basket.atrAtOpen           = 0.0;

   g_lastStatusLogTime = 0;

   ApplyPremiumChartTheme();

   Log("EzyEA V5 initialized on "+_Symbol+
       " | account unit divisor="+DoubleToString(g_accountUnitDivisor,2)+
       " | risk/first-layer="+DoubleToString(InpRiskPercentPerTrade,2)+"%"+
       " | max pyramid layers="+IntegerToString(InpMaxPyramidLayers)+
       " (size ratio "+DoubleToString(InpPyramidSizeRatio,2)+")"+
       " | basket equity stop="+DoubleToString(InpBasketMaxLossEquityPct,2)+"%"+
       " | drawdown breaker="+(InpEnableDrawdownBreaker?DoubleToString(InpMaxEquityDrawdownPct,1)+"%":"OFF"));

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   WriteFinalReport();

   if(g_handleAtrFast!=INVALID_HANDLE) IndicatorRelease(g_handleAtrFast);
   if(g_handleAtrSlow!=INVALID_HANDLE) IndicatorRelease(g_handleAtrSlow);
   if(g_handleBB!=INVALID_HANDLE)      IndicatorRelease(g_handleBB);

   RemoveAllDrawings();
}

void OnTick()
{
   UpdateDrawdownBreaker();
   PruneBasketTickets();

   double atrFast=CurrentAtrFast();

   if(!g_tradingHalted)
   {
      CheckFadeSignalOnNewM1Bar();

      if(g_basket.active && atrFast>0.0)
         TryAddPyramidLayer(atrFast);
   }

   if(g_basket.active)
   {
      ManageBasketExit(atrFast);
      EnforceMaxHoldingTime();
   }

   if(InpDrawBands)        DrawBands();
   if(InpDrawStatusLabel)  DrawStatusLabel();
   if(InpShowLiveTradeLevels) DrawLiveTradeLevels();

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
   Print("EzyEA V5 | ",msg);
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

double ComputeFirstLayerLots(int direction,double entry,double sl)
{
   double equity=EffectiveAccountEquity();
   double riskBudget=equity*InpRiskPercentPerTrade/100.0;
   if(riskBudget<=0.0) return 0.0;

   double perLotLoss=OneLotLoss(direction,entry,sl);
   if(perLotLoss<=0.0) return 0.0;

   double lots=NormalizeVolumeDown(riskBudget/perLotLoss);
   if(lots<=0.0) return 0.0;

   lots=MathMin(lots,InpMaxLotsAbsolute);

   double marginRequired=0.0;
   ENUM_ORDER_TYPE type=(direction==1)?ORDER_TYPE_BUY:ORDER_TYPE_SELL;
   if(OrderCalcMargin(type,_Symbol,lots,entry,marginRequired))
   {
      double rawEquity=AccountInfoDouble(ACCOUNT_EQUITY);
      double usedMargin=AccountInfoDouble(ACCOUNT_MARGIN);
      double projectedMarginPct=(rawEquity>0.0)
                                ?((usedMargin+marginRequired)/rawEquity)*100.0
                                :DBL_MAX;

      if(projectedMarginPct>InpMaxMarginUsePct)
      {
         double remainingBudget=MathMax(0.0,InpMaxMarginUsePct/100.0*rawEquity-usedMargin);
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
   return referencePrice*0.05/100.0;
}

double MinimumStopDistance(double referencePrice)
{
   long stopsLevel =SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freezeLevel=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);

   double base=MathMax(_Point,((double)MathMax(stopsLevel,freezeLevel)+10.0)*_Point);

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
// Emergency stop: closes every position this EA opened, and clears the
// basket state (used both by the drawdown breaker and the basket-level
// equity stop).
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

   g_basket.active=false;
}

//======================================================================
// Overall drawdown circuit breaker: peak equity seen since attach.
// Distinct from, and wider than, the basket-level equity stop below -
// this is the last-resort account-wide backstop.
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
// Volatility gate
//======================================================================
double CurrentAtrFast()
{
   double buf[];
   if(CopyBufferSeries(g_handleAtrFast,0,2,buf)<2) return 0.0;
   return buf[1]; // last CLOSED M1 bar's ATR value
}

bool IsMarketVolatile(double &atrFastOut)
{
   atrFastOut=0.0;

   double fastBuf[],slowBuf[];
   if(CopyBufferSeries(g_handleAtrFast,0,2,fastBuf)<2) return false;
   if(CopyBufferSeries(g_handleAtrSlow,0,2,slowBuf)<2) return false;

   double atrFast=fastBuf[1];
   double atrSlow=slowBuf[1];
   if(atrFast<=0.0 || atrSlow<=0.0) return false;

   atrFastOut=atrFast;
   return (atrFast>=atrSlow*InpVolatilityMultiplier);
}

//======================================================================
// Entry signal: M1 Bollinger Band fade, confirmed on the 2nd closed bar.
// Only opens a NEW basket - ignored while one is already active,
// including a fresh signal in the opposite direction (no flip/hedge by
// deliberate scope choice - see header).
//======================================================================
void CheckFadeSignalOnNewM1Bar()
{
   datetime m1=iTime(_Symbol,PERIOD_M1,0);
   if(m1==0 || m1==g_lastM1BarTime) return;
   g_lastM1BarTime=m1;

   if(g_basket.active) return; // one basket at a time, by design

   double upperBuf[],lowerBuf[],closeBuf[];
   if(CopyBufferSeries(g_handleBB,1,3,upperBuf)<3) return; // UPPER_BAND
   if(CopyBufferSeries(g_handleBB,2,3,lowerBuf)<3) return; // LOWER_BAND

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   if(CopyRates(_Symbol,PERIOD_M1,0,3,rates)<3) return;

   double close1=rates[1].close; // last closed bar
   double close2=rates[2].close; // bar before that
   double upper1=upperBuf[1], upper2=upperBuf[2];
   double lower1=lowerBuf[1], lower2=lowerBuf[2];

   bool bearishFade = (close2>upper2) && (close1<=upper1); // was outside above, back inside -> SELL
   bool bullishFade = (close2<lower2) && (close1>=lower1); // was outside below, back inside -> BUY

   if(!bearishFade && !bullishFade) return;

   g_gateAttempts++;

   if(g_tradingHalted)
   {
      g_gateDrawdownRejects++;
      return;
   }

   double atrFast;
   if(!IsMarketVolatile(atrFast))
   {
      g_gateVolatilityRejects++;
      return;
   }

   if(!SpreadAllowed())
   {
      g_gateSpreadRejects++;
      return;
   }

   int direction = bullishFade ? 1 : -1;
   OpenBasket(direction,atrFast);
}

//======================================================================
// Basket open (first layer) / pyramid adds
//======================================================================
void OpenBasket(int direction,double atrFast)
{
   double structuralSlDistance=MathMax(_Point,InpStructuralSlAtrMult*atrFast);

   ulong ticket=0;
   if(!SubmitLayerOrder(direction,-1.0,structuralSlDistance,ticket))
      return; // SubmitLayerOrder logs its own rejection reason

   g_basket.active              = true;
   g_basket.direction           = direction;
   g_basket.layerCount          = 1;
   g_basket.tickets[0]          = ticket;
   for(int i=1;i<8;i++) g_basket.tickets[i]=0;

   double entryPrice=0.0;
   if(PositionSelectByTicket(ticket))
      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);

   g_basket.lastLayerEntryPrice = entryPrice;
   g_basket.peakFavorablePrice  = entryPrice;
   g_basket.trailActive         = false;
   g_basket.trailStopPrice      = 0.0;
   g_basket.openTime            = TimeCurrent();
   g_basket.lastLayerTime       = TimeCurrent();
   g_basket.atrAtOpen           = atrFast;

   Log("BASKET OPEN dir="+IntegerToString(direction)+
       " entry="+PriceText(entryPrice)+
       " atrFast="+PriceText(atrFast)+
       " structuralSL="+PriceText(structuralSlDistance));
}

void TryAddPyramidLayer(double atrFast)
{
   // g_basket.tickets[] is fixed at 8 slots - clamp the effective cap so
   // a mistakenly-large InpMaxPyramidLayers input can never index past it.
   if(g_basket.layerCount>=MathMin(8,InpMaxPyramidLayers)) return;
   if(TimeCurrent()-g_basket.lastLayerTime<MathMax(0,InpPyramidMinSecondsBetweenLayers)) return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double currentPrice=(g_basket.direction==1)?tick.bid:tick.ask;
   double favorableFromLastLayer=(g_basket.direction==1)
                                 ?(currentPrice-g_basket.lastLayerEntryPrice)
                                 :(g_basket.lastLayerEntryPrice-currentPrice);

   double stepDistance=MathMax(_Point,InpPyramidStepAtrMult*atrFast);
   if(favorableFromLastLayer<stepDistance) return;

   if(!SpreadAllowed()) return;

   double structuralSlDistance=MathMax(_Point,InpStructuralSlAtrMult*atrFast);

   ulong ticket=0;
   if(!SubmitLayerOrder(g_basket.direction,-1.0,structuralSlDistance,ticket))
      return;

   double entryPrice=0.0;
   if(PositionSelectByTicket(ticket))
      entryPrice=PositionGetDouble(POSITION_PRICE_OPEN);

   g_basket.tickets[g_basket.layerCount]=ticket;
   g_basket.layerCount++;
   g_basket.lastLayerEntryPrice=entryPrice;
   g_basket.lastLayerTime=TimeCurrent();

   Log("PYRAMID LAYER ADDED layer="+IntegerToString(g_basket.layerCount)+
       "/"+IntegerToString(InpMaxPyramidLayers)+
       " entry="+PriceText(entryPrice));
}

//======================================================================
// Order submission: first layer sizes off InpRiskPercentPerTrade via
// OneLotLoss(); each subsequent layer decays by InpPyramidSizeRatio off
// the FIRST layer's lot size (a stable base rather than compounding
// rounding error off the previous layer).
//======================================================================
bool SubmitLayerOrder(int direction,double lots,double structuralSlDistance,ulong &ticketOut)
{
   ticketOut=0;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;

   double entry=(direction==1)?tick.ask:tick.bid;
   double sl=RoundPrice((direction==1)?entry-structuralSlDistance:entry+structuralSlDistance);

   double minDist=MinimumStopDistance(entry);
   if(MathAbs(entry-sl)<minDist)
   {
      g_gateDistanceRejects++;
      Log("LAYER REJECTED reason=SL_DISTANCE_TOO_TIGHT slDistance="+
          PriceText(structuralSlDistance)+" minDist="+PriceText(minDist));
      return false;
   }

   if(lots<=0.0)
   {
      if(g_basket.layerCount<=0)
      {
         lots=ComputeFirstLayerLots(direction,entry,sl);
      }
      else
      {
         // Base off layer 1's own lot size (queried live), decayed by
         // the ratio raised to the current layer index.
         double baseLots=0.0;
         if(PositionSelectByTicket(g_basket.tickets[0]))
            baseLots=PositionGetDouble(POSITION_VOLUME);

         double ratio=MathPow(MathMax(0.01,MathMin(1.0,InpPyramidSizeRatio)),(double)g_basket.layerCount);
         lots=NormalizeVolumeDown(baseLots*ratio);
      }
   }

   if(lots<=0.0)
   {
      g_gateSizingRejects++;
      Log("LAYER REJECTED reason=ZERO_LOTS entry="+PriceText(entry)+" sl="+PriceText(sl));
      return false;
   }

   bool sent=(direction==1)
             ? trade.Buy(lots,_Symbol,0.0,sl,0.0,"V5FADE")
             : trade.Sell(lots,_Symbol,0.0,sl,0.0,"V5FADE");

   uint retcode=trade.ResultRetcode();

   if(sent && TradeRetcodeAccepted(retcode))
   {
      g_gateAccepted++;
      ticketOut=trade.ResultOrder();
      // ResultOrder() can be a pending-order/deal ticket depending on
      // execution mode; the position ticket for a market fill is the
      // same value on most brokers, but confirm by re-selecting - if it
      // doesn't resolve to an open position yet, look up the newest
      // position matching this symbol/magic as a fallback.
      if(!PositionSelectByTicket(ticketOut))
      {
         for(int i=PositionsTotal()-1;i>=0;i--)
         {
            ulong candidate=PositionGetTicket(i);
            if(candidate==0) continue;
            if(!PositionSelectByTicket(candidate)) continue;
            if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
            if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
            ticketOut=candidate;
            break;
         }
      }
      Log("LAYER FILLED dir="+IntegerToString(direction)+
          " lots="+DoubleToString(lots,2)+
          " entry="+PriceText(entry)+
          " sl="+PriceText(sl));
      return true;
   }

   g_gateRejected++;
   Log("LAYER REJECTED retcode="+IntegerToString(retcode)+
       " desc="+trade.ResultRetcodeDescription());
   return false;
}

//======================================================================
// Basket bookkeeping
//======================================================================
void PruneBasketTickets()
{
   if(!g_basket.active) return;

   int remaining=0;
   ulong survivors[8];
   for(int i=0;i<g_basket.layerCount;i++)
   {
      if(g_basket.tickets[i]!=0 && PositionSelectByTicket(g_basket.tickets[i]))
      {
         survivors[remaining]=g_basket.tickets[i];
         remaining++;
      }
   }

   if(remaining==g_basket.layerCount) return; // nothing changed

   for(int i=0;i<remaining;i++) g_basket.tickets[i]=survivors[i];
   for(int i=remaining;i<8;i++) g_basket.tickets[i]=0;
   g_basket.layerCount=remaining;

   if(remaining==0)
   {
      Log("BASKET CLOSED (all layers gone)");
      g_basket.active=false;
   }
}

double BasketFloatingPnL()
{
   double total=0.0;
   for(int i=0;i<g_basket.layerCount;i++)
   {
      if(g_basket.tickets[i]==0) continue;
      if(!PositionSelectByTicket(g_basket.tickets[i])) continue;
      total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return total;
}

void UpdateBasketPeakAndTrail(double atrFast)
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   double currentPrice=(g_basket.direction==1)?tick.bid:tick.ask;

   if(g_basket.direction==1)
      g_basket.peakFavorablePrice=MathMax(g_basket.peakFavorablePrice,currentPrice);
   else
      g_basket.peakFavorablePrice=MathMin(g_basket.peakFavorablePrice,currentPrice);

   if(atrFast<=0.0) atrFast=g_basket.atrAtOpen;
   if(atrFast<=0.0) return;

   // Favourable excursion measured from the FIRST layer's entry (the
   // basket's anchor), not a volume-weighted average - simplest stable
   // reference point for trail activation/step math.
   double anchorEntry=0.0;
   if(g_basket.tickets[0]!=0 && PositionSelectByTicket(g_basket.tickets[0]))
      anchorEntry=PositionGetDouble(POSITION_PRICE_OPEN);
   if(anchorEntry<=0.0) return;

   double peakFavorable=(g_basket.direction==1)
                        ?(g_basket.peakFavorablePrice-anchorEntry)
                        :(anchorEntry-g_basket.peakFavorablePrice);

   double activationDistance=MathMax(_Point,InpBasketTrailActivationAtrMult*atrFast);
   double trailDistance     =MathMax(_Point,InpBasketTrailDistanceAtrMult*atrFast);

   if(!g_basket.trailActive && peakFavorable>=activationDistance)
   {
      g_basket.trailActive=true;
      Log("BASKET TRAIL ARMED peakFavorable="+PriceText(peakFavorable)+
          " activationDistance="+PriceText(activationDistance));
   }

   if(g_basket.trailActive)
   {
      double candidateStop=RoundPrice((g_basket.direction==1)
                                      ?g_basket.peakFavorablePrice-trailDistance
                                      :g_basket.peakFavorablePrice+trailDistance);
      bool improves=(g_basket.trailStopPrice<=0.0) ||
                    ((g_basket.direction==1)
                     ?(candidateStop>g_basket.trailStopPrice)
                     :(candidateStop<g_basket.trailStopPrice));
      if(improves)
         g_basket.trailStopPrice=candidateStop;
   }
}

void ManageBasketExit(double atrFast)
{
   UpdateBasketPeakAndTrail(atrFast);

   // (a) Basket-level hard equity stop - fixed % of equity, independent
   // of whether the trail has armed yet.
   double floatingPnl=BasketFloatingPnL();
   double equity=EffectiveAccountEquity();
   if(equity>0.0)
   {
      double lossPct=(-floatingPnl/equity)*100.0;
      if(lossPct>=InpBasketMaxLossEquityPct)
      {
         CloseBasket("basket equity stop ("+DoubleToString(lossPct,2)+"% >= "+
                     DoubleToString(InpBasketMaxLossEquityPct,2)+"%)");
         return;
      }
   }

   // (b) Basket trailing stop, once armed.
   if(g_basket.trailActive && g_basket.trailStopPrice>0.0)
   {
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
      {
         double currentPrice=(g_basket.direction==1)?tick.bid:tick.ask;
         bool hit=(g_basket.direction==1)
                  ?(currentPrice<=g_basket.trailStopPrice+_Point*0.25)
                  :(currentPrice>=g_basket.trailStopPrice-_Point*0.25);
         if(hit)
         {
            CloseBasket("basket trailing stop hit at "+PriceText(g_basket.trailStopPrice));
            return;
         }
      }
   }
}

void CloseBasket(string reason)
{
   Log("CLOSING BASKET | reason="+reason+
       " | layers="+IntegerToString(g_basket.layerCount)+
       " | floatingPnl="+DoubleToString(BasketFloatingPnL(),2));

   for(int i=0;i<g_basket.layerCount;i++)
   {
      if(g_basket.tickets[i]==0) continue;
      if(!PositionSelectByTicket(g_basket.tickets[i])) continue;

      bool ok=trade.PositionClose(g_basket.tickets[i]);
      uint retcode=trade.ResultRetcode();
      if(!ok || !TradeRetcodeAccepted(retcode))
         Log("BASKET LAYER CLOSE FAILED ticket="+IntegerToString((int)g_basket.tickets[i])+
             " retcode="+IntegerToString(retcode));
   }

   g_basket.active=false;
   g_basket.layerCount=0;
   for(int i=0;i<8;i++) g_basket.tickets[i]=0;
}

void EnforceMaxHoldingTime()
{
   if(InpMaxHoldingMinutes<=0) return;
   if(!g_basket.active) return;

   long cutoffSeconds=(long)InpMaxHoldingMinutes*60;
   long heldSeconds=(long)(TimeCurrent()-g_basket.openTime);
   if(heldSeconds<cutoffSeconds) return;

   CloseBasket("max holding time backstop ("+IntegerToString(InpMaxHoldingMinutes)+" min)");
}

//======================================================================
// Chart drawing
//======================================================================
void DrawBands()
{
   int bars=MathMax(3,InpDrawBarsBack);
   double upperBuf[],lowerBuf[],baseBuf[];
   int n1=CopyBufferSeries(g_handleBB,1,bars,upperBuf);
   int n2=CopyBufferSeries(g_handleBB,2,bars,lowerBuf);
   int n3=CopyBufferSeries(g_handleBB,0,bars,baseBuf);
   int n=MathMin(n1,MathMin(n2,n3));
   if(n<2) return;

   for(int shift=0;shift<n-1;shift++)
   {
      datetime t1=iTime(_Symbol,PERIOD_M1,shift+1);
      datetime t2=iTime(_Symbol,PERIOD_M1,shift);
      if(t1==0 || t2==0) continue;

      string nameU="V5_BBU_"+IntegerToString(shift);
      string nameL="V5_BBL_"+IntegerToString(shift);
      string nameB="V5_BBB_"+IntegerToString(shift);

      if(ObjectFind(0,nameU)<0) ObjectCreate(0,nameU,OBJ_TREND,0,t1,upperBuf[shift+1],t2,upperBuf[shift]);
      else { ObjectMove(0,nameU,0,t1,upperBuf[shift+1]); ObjectMove(0,nameU,1,t2,upperBuf[shift]); }
      ObjectSetInteger(0,nameU,OBJPROP_COLOR,clrDodgerBlue);
      ObjectSetInteger(0,nameU,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameU,OBJPROP_RAY,false);
      ObjectSetInteger(0,nameU,OBJPROP_SELECTABLE,false);

      if(ObjectFind(0,nameL)<0) ObjectCreate(0,nameL,OBJ_TREND,0,t1,lowerBuf[shift+1],t2,lowerBuf[shift]);
      else { ObjectMove(0,nameL,0,t1,lowerBuf[shift+1]); ObjectMove(0,nameL,1,t2,lowerBuf[shift]); }
      ObjectSetInteger(0,nameL,OBJPROP_COLOR,clrDodgerBlue);
      ObjectSetInteger(0,nameL,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameL,OBJPROP_RAY,false);
      ObjectSetInteger(0,nameL,OBJPROP_SELECTABLE,false);

      if(ObjectFind(0,nameB)<0) ObjectCreate(0,nameB,OBJ_TREND,0,t1,baseBuf[shift+1],t2,baseBuf[shift]);
      else { ObjectMove(0,nameB,0,t1,baseBuf[shift+1]); ObjectMove(0,nameB,1,t2,baseBuf[shift]); }
      ObjectSetInteger(0,nameB,OBJPROP_COLOR,clrGray);
      ObjectSetInteger(0,nameB,OBJPROP_STYLE,STYLE_DOT);
      ObjectSetInteger(0,nameB,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameB,OBJPROP_RAY,false);
      ObjectSetInteger(0,nameB,OBJPROP_SELECTABLE,false);
   }
}

void DrawStatusLabel()
{
   string name="V5_StatusLabel";
   double atrFast=CurrentAtrFast();

   string text=StringFormat(
      "EzyEA V5 | ATR(fast)=%s | basket=%s | dir=%s | layers=%d/%d | trail=%s | equity=%.2f | %s",
      PriceText(atrFast),
      g_basket.active?"ACTIVE":"-",
      g_basket.active?(g_basket.direction==1?"BUY":"SELL"):"-",
      g_basket.layerCount,InpMaxPyramidLayers,
      g_basket.trailActive?"ARMED":"-",
      EffectiveAccountEquity(),
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

void DrawLiveTradeLevels()
{
   ObjectsDeleteAll(0,"V5_LIVE_");

   if(!g_basket.active) return;

   color dirColor=(g_basket.direction==1)?InpBuyColor:InpSellColor;

   for(int i=0;i<g_basket.layerCount;i++)
   {
      if(g_basket.tickets[i]==0) continue;
      if(!PositionSelectByTicket(g_basket.tickets[i])) continue;

      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl   =PositionGetDouble(POSITION_SL);

      string nameE="V5_LIVE_ENTRY_"+IntegerToString((int)g_basket.tickets[i]);
      if(ObjectFind(0,nameE)<0) ObjectCreate(0,nameE,OBJ_HLINE,0,0,entry);
      ObjectSetDouble(0,nameE,OBJPROP_PRICE,entry);
      ObjectSetInteger(0,nameE,OBJPROP_COLOR,InpTradeLevelGold);
      ObjectSetInteger(0,nameE,OBJPROP_STYLE,STYLE_SOLID);
      ObjectSetInteger(0,nameE,OBJPROP_WIDTH,1);
      ObjectSetInteger(0,nameE,OBJPROP_SELECTABLE,false);

      if(sl>0.0)
      {
         string nameS="V5_LIVE_SL_"+IntegerToString((int)g_basket.tickets[i]);
         if(ObjectFind(0,nameS)<0) ObjectCreate(0,nameS,OBJ_HLINE,0,0,sl);
         ObjectSetDouble(0,nameS,OBJPROP_PRICE,sl);
         ObjectSetInteger(0,nameS,OBJPROP_COLOR,InpTradeLevelGold);
         ObjectSetInteger(0,nameS,OBJPROP_STYLE,STYLE_DASH);
         ObjectSetInteger(0,nameS,OBJPROP_WIDTH,1);
         ObjectSetInteger(0,nameS,OBJPROP_SELECTABLE,false);
      }
   }

   if(g_basket.trailActive && g_basket.trailStopPrice>0.0)
   {
      string nameT="V5_LIVE_TRAIL";
      if(ObjectFind(0,nameT)<0) ObjectCreate(0,nameT,OBJ_HLINE,0,0,g_basket.trailStopPrice);
      ObjectSetDouble(0,nameT,OBJPROP_PRICE,g_basket.trailStopPrice);
      ObjectSetInteger(0,nameT,OBJPROP_COLOR,dirColor);
      ObjectSetInteger(0,nameT,OBJPROP_STYLE,STYLE_DASHDOT);
      ObjectSetInteger(0,nameT,OBJPROP_WIDTH,2);
      ObjectSetInteger(0,nameT,OBJPROP_SELECTABLE,false);
   }
}

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

void RemoveAllDrawings()
{
   ObjectsDeleteAll(0,"V5_");
}

//======================================================================
// Reporting
//======================================================================
void WriteFinalReport()
{
   Log("FINAL REPORT | attempts="+IntegerToString(g_gateAttempts)+
       " accepted="+IntegerToString(g_gateAccepted)+
       " rejected="+IntegerToString(g_gateRejected)+
       " | spreadRejects="+IntegerToString(g_gateSpreadRejects)+
       " volatilityRejects="+IntegerToString(g_gateVolatilityRejects)+
       " distanceRejects="+IntegerToString(g_gateDistanceRejects)+
       " sizingRejects="+IntegerToString(g_gateSizingRejects)+
       " drawdownRejects="+IntegerToString(g_gateDrawdownRejects));
}

void PeriodicStatusLog()
{
   if(InpStatusLogIntervalSeconds<=0) return;
   if(TimeCurrent()-g_lastStatusLogTime<InpStatusLogIntervalSeconds) return;
   g_lastStatusLogTime=TimeCurrent();

   Log("STATUS | equity="+DoubleToString(EffectiveAccountEquity(),2)+
       " | basket="+(g_basket.active?"ACTIVE dir="+IntegerToString(g_basket.direction)+
                     " layers="+IntegerToString(g_basket.layerCount)+
                     " trail="+(g_basket.trailActive?"ARMED":"OFF")+
                     " floatingPnl="+DoubleToString(BasketFloatingPnL(),2):"NONE")+
       " | halted="+(g_tradingHalted?"YES":"NO"));

   Log("DEPLOYMENT GATE BREAKDOWN | attempts="+IntegerToString(g_gateAttempts)+
       " accepted="+IntegerToString(g_gateAccepted)+
       " rejected="+IntegerToString(g_gateRejected)+
       " | spread="+IntegerToString(g_gateSpreadRejects)+
       " volatility="+IntegerToString(g_gateVolatilityRejects)+
       " distance="+IntegerToString(g_gateDistanceRejects)+
       " sizing="+IntegerToString(g_gateSizingRejects)+
       " drawdown="+IntegerToString(g_gateDrawdownRejects));
}
