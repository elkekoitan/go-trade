//+------------------------------------------------------------------+
//|                                              TickDecisionEA.mq5  |
//|                         Tick-Based Smart Decision Expert Advisor  |
//|                      Martingale / Anti-Martingale / Fixed Grid    |
//+------------------------------------------------------------------+
#property copyright "TickDecisionEA"
#property version   "3.00"
#property strict

//+------------------------------------------------------------------+
//| ENUM DEFINITIONS                                                  |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_TYPE
{
   STRATEGY_MARTINGALE    = 0,  // Martingale (Zararda Lot Büyüt)
   STRATEGY_ANTIMARTINGALE= 1,  // Anti-Martingale (Kârda Lot Büyüt)
   STRATEGY_FIXED_GRID    = 2   // Sabit Grid (Sabit Lot)
};

enum ENUM_SYMBOL_MODE
{
   SYMBOL_MANUAL = 0,  // Manuel Sembol Seç
   SYMBOL_AUTO   = 1   // Explorer En Yüksek Puanlıyı Seç
};

enum ENUM_ORDER_MODE
{
   ORDER_MARKET_ONLY  = 0,  // Sadece Market
   ORDER_LIMIT_ONLY   = 1,  // Sadece Limit
   ORDER_STOP_ONLY    = 2,  // Sadece Stop
   ORDER_ALL          = 3,  // Market + Limit + Stop
   ORDER_MARKET_LIMIT = 4,  // Market + Limit
   ORDER_MARKET_STOP  = 5,  // Market + Stop
   ORDER_LIMIT_STOP   = 6   // Limit + Stop
};

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+
input string            inp_Sep1           = "══════ SEMBOL AYARLARI ══════"; // ─── Sembol ───
input ENUM_SYMBOL_MODE  inp_SymbolMode     = SYMBOL_AUTO;         // Sembol Seçim Modu
input string            inp_ManualSymbol   = "XAUUSD";            // Manuel Sembol
input string            inp_ExplorerSymbols= "XAUUSD,EURUSD,GBPUSD,USDJPY,GBPJPY,EURJPY,AUDUSD,USDCHF,USDCAD,NZDUSD"; // Explorer Sembol Listesi

input string            inp_Sep2           = "══════ STRATEJİ AYARLARI ══════"; // ─── Strateji ───
input ENUM_STRATEGY_TYPE inp_Strategy      = STRATEGY_MARTINGALE; // Strateji Tipi
input double            inp_InitialLot     = 0.01;                // Başlangıç Lot
input double            inp_LotMultiplier  = 2.0;                 // Lot Çarpanı (Martingale/Anti)
input double            inp_MaxLot         = 5.0;                 // Maksimum Lot
input int               inp_MaxGridLevels  = 10;                  // Maksimum Grid Seviyesi
input int               inp_GridStepPoints = 200;                 // Grid Adımı (Point)

input string            inp_Sep3           = "══════ EMİR AYARLARI ══════"; // ─── Emirler ───
input ENUM_ORDER_MODE   inp_OrderMode      = ORDER_ALL;           // Emir Modu
input int               inp_LimitDistance  = 300;                 // Limit Emir Mesafesi (Point)
input int               inp_StopDistance   = 300;                 // Stop Emir Mesafesi (Point)
input int               inp_PendingExpiry  = 60;                  // Bekleyen Emir Süresi (Dakika, 0=Süresiz)

input string            inp_Sep4           = "══════ KÂR/ZARAR AYARLARI ══════"; // ─── Kâr/Zarar ───
input double            inp_TargetProfit   = 10.0;                // Hedef Kâr ($) - Tümünü Kapat
input double            inp_MaxDrawdown    = 500.0;               // Maksimum Zarar ($) - Tümünü Kapat
input bool              inp_CloseOnProfit  = true;                // Kârda Otomatik Kapat

input string            inp_Sep5           = "══════ İNDİKATÖR AYARLARI ══════"; // ─── İndikatörler ───
input int               inp_RSI_Period     = 14;                  // RSI Periyodu
input int               inp_MACD_Fast      = 12;                  // MACD Hızlı
input int               inp_MACD_Slow      = 26;                  // MACD Yavaş
input int               inp_MACD_Signal    = 9;                   // MACD Sinyal
input int               inp_BB_Period      = 20;                  // Bollinger Periyodu
input double            inp_BB_Deviation   = 2.0;                 // Bollinger Sapması
input int               inp_MA_Fast        = 10;                  // Hızlı MA Periyodu
input int               inp_MA_Slow        = 50;                  // Yavaş MA Periyodu
input int               inp_Stoch_K        = 14;                  // Stochastic %K
input int               inp_Stoch_D        = 3;                   // Stochastic %D
input int               inp_Stoch_Slow     = 3;                   // Stochastic Yavaşlama
input int               inp_ADX_Period     = 14;                  // ADX Periyodu
input int               inp_ATR_Period     = 14;                  // ATR Periyodu
input double            inp_MinScore       = 30.0;                // Minimum İşlem Puanı (0-100)

input string            inp_Sep55          = "══════ ZAMANLAMA AYARLARI ══════"; // ─── Zamanlama ───
input int               inp_TradeInterval  = 1;                   // İşlem Aralığı (Saniye)
input bool              inp_ForceEveryTick = true;                // Her Aralıkta Mutlaka İşlem Aç
input bool              inp_IgnoreGridStep = false;               // Grid Adımını Yoksay (Her Yerde Aç)

input string            inp_Sep6           = "══════ GÖRSEL AYARLAR ══════"; // ─── Görsel ───
input int               inp_MagicNumber    = 777777;              // Magic Number
input bool              inp_ShowPanel      = true;                // Bilgi Paneli Göster
input bool              inp_ShowExplorer   = true;                // Explorer Tablosu Göster
input color             inp_BuyColor       = clrDodgerBlue;       // Buy Rengi
input color             inp_SellColor      = clrOrangeRed;        // Sell Rengi
input color             inp_PanelBG        = clrBlack;            // Panel Arka Plan
input color             inp_PanelText      = clrWhite;            // Panel Yazı Rengi

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
string g_ActiveSymbol = "";
string g_ExplorerList[];
int    g_ExplorerCount = 0;

// İndikatör Handle'ları
int h_RSI, h_MACD, h_BB, h_MA_Fast, h_MA_Slow, h_Stoch, h_ADX, h_ATR;

// Skor değerleri
double g_CompositeScore = 0;
double g_RSI_Score = 0;
double g_MACD_Score = 0;
double g_BB_Score = 0;
double g_MA_Score = 0;
double g_Stoch_Score = 0;
double g_ADX_Score = 0;
double g_TrendStrength = 0;

// İstatistikler
int    g_TotalTrades = 0;
int    g_WinTrades = 0;
int    g_LossTrades = 0;
double g_TotalProfit = 0;
int    g_CurrentLevel = 0;
int    g_CycleCount = 0;
double g_LastLot = 0;
bool   g_LastTradeWin = false;

// Explorer skorları
double g_ExplorerScores[];
string g_ExplorerDirections[];

// Tick sayacı
ulong  g_TickCount = 0;
datetime g_LastExplorerUpdate = 0;
datetime g_LastTradeTime = 0;
int    g_TradesThisSecond = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Explorer sembol listesini parse et
   ParseExplorerSymbols();
   
   // Aktif sembolü belirle
   if(inp_SymbolMode == SYMBOL_MANUAL)
   {
      g_ActiveSymbol = inp_ManualSymbol;
      if(!SymbolSelect(g_ActiveSymbol, true))
      {
         Print("HATA: Sembol bulunamadı - ", g_ActiveSymbol);
         return(INIT_FAILED);
      }
   }
   else
   {
      // İlk çalıştırmada explorer ile seç
      RunExplorer();
   }
   
   // İndikatörleri başlat
   if(!InitIndicators())
   {
      Print("HATA: İndikatörler başlatılamadı!");
      return(INIT_FAILED);
   }
   
   // Panel oluştur
   if(inp_ShowPanel)
      CreatePanel();
   
   // Zamanlayıcı başlat
   EventSetTimer(inp_TradeInterval);
   
   Print("✅ TickDecisionEA başlatıldı | Sembol: ", g_ActiveSymbol, 
         " | Strateji: ", EnumToString(inp_Strategy),
         " | İşlem Aralığı: ", inp_TradeInterval, "sn",
         " | Her Aralıkta Aç: ", inp_ForceEveryTick ? "EVET" : "HAYIR");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Zamanlayıcı durdur
   EventKillTimer();
   
   // İndikatörleri serbest bırak
   ReleaseIndicators();
   
   // Panel temizle
   ObjectsDeleteAll(0, "TDE_");
   
   Print("TickDecisionEA kapatıldı. Toplam İşlem: ", g_TotalTrades,
         " | Kâr: ", g_WinTrades, " | Zarar: ", g_LossTrades);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   g_TickCount++;
   
   // Panel güncelle (her 10 tickte)
   if(inp_ShowPanel && g_TickCount % 10 == 0)
      UpdatePanel();
}

//+------------------------------------------------------------------+
//| Timer function - HER SANİYE ÇALIŞIR                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   // ── 1. Explorer güncelleme (her 30 saniyede) ──
   if(inp_SymbolMode == SYMBOL_AUTO && 
      TimeCurrent() - g_LastExplorerUpdate > 30)
   {
      string oldSymbol = g_ActiveSymbol;
      RunExplorer();
      if(oldSymbol != g_ActiveSymbol)
      {
         ReleaseIndicators();
         InitIndicators();
         Print("🔄 Sembol değişti: ", oldSymbol, " → ", g_ActiveSymbol);
      }
   }
   
   // ── 2. Mevcut pozisyon durumunu kontrol et ──
   double totalPL = GetTotalFloatingPL();
   int openPositions = CountPositions();
   int pendingOrders = CountPendingOrders();
   
   // ── 3. Kâr hedefine ulaşıldı mı? ──
   if(inp_CloseOnProfit && totalPL >= inp_TargetProfit && openPositions > 0)
   {
      Print("🎯 HEDEF KÂR ULAŞILDI! Kâr: $", DoubleToString(totalPL, 2));
      CloseAllPositions();
      DeleteAllPendingOrders();
      ResetCycle();
      g_CycleCount++;
      UpdatePanel();
      return;
   }
   
   // ── 4. Maksimum zarar kontrolü ──
   if(totalPL <= -inp_MaxDrawdown && openPositions > 0)
   {
      Print("⛔ MAKSİMUM ZARAR! Zarar: $", DoubleToString(totalPL, 2));
      CloseAllPositions();
      DeleteAllPendingOrders();
      ResetCycle();
      return;
   }
   
   // ── 5. İndikatör analizi ──
   CalculateCompositeScore();
   
   // ── 6. Karar mekanizması (Her saniye çalışır) ──
   MakeTimerDecision(totalPL, openPositions, pendingOrders);
   
   // ── 7. Panel güncelle ──
   if(inp_ShowPanel)
      UpdatePanel();
}

//+------------------------------------------------------------------+
//| EXPLORER - Sembol Tarama ve Puanlama                             |
//+------------------------------------------------------------------+
void ParseExplorerSymbols()
{
   string symbols = inp_ExplorerSymbols;
   StringReplace(symbols, " ", "");
   
   g_ExplorerCount = StringSplit(symbols, ',', g_ExplorerList);
   ArrayResize(g_ExplorerScores, g_ExplorerCount);
   ArrayResize(g_ExplorerDirections, g_ExplorerCount);
   
   // Semboller aktifleştir
   for(int i = 0; i < g_ExplorerCount; i++)
      SymbolSelect(g_ExplorerList[i], true);
}

//+------------------------------------------------------------------+
void RunExplorer()
{
   g_LastExplorerUpdate = TimeCurrent();
   
   double bestScore = 0;
   string bestSymbol = "";
   
   for(int i = 0; i < g_ExplorerCount; i++)
   {
      string sym = g_ExplorerList[i];
      if(!SymbolInfoInteger(sym, SYMBOL_TRADE_MODE)) continue;
      
      double score = CalculateSymbolScore(sym);
      g_ExplorerScores[i] = score;
      g_ExplorerDirections[i] = (score > 0) ? "BUY" : (score < 0) ? "SELL" : "NEUTRAL";
      
      if(MathAbs(score) > MathAbs(bestScore))
      {
         bestScore = score;
         bestSymbol = sym;
      }
   }
   
   if(bestSymbol != "" && MathAbs(bestScore) >= inp_MinScore)
   {
      g_ActiveSymbol = bestSymbol;
   }
   else if(g_ActiveSymbol == "")
   {
      g_ActiveSymbol = (g_ExplorerCount > 0) ? g_ExplorerList[0] : _Symbol;
   }
}

//+------------------------------------------------------------------+
double CalculateSymbolScore(string symbol)
{
   double score = 0;
   int weight = 0;
   
   // RSI
   int rsiH = iRSI(symbol, PERIOD_CURRENT, inp_RSI_Period, PRICE_CLOSE);
   if(rsiH != INVALID_HANDLE)
   {
      double rsiVal[1];
      if(CopyBuffer(rsiH, 0, 0, 1, rsiVal) > 0)
      {
         if(rsiVal[0] < 30) score += (30 - rsiVal[0]) * 2.5;       // Aşırı satım = AL
         else if(rsiVal[0] > 70) score -= (rsiVal[0] - 70) * 2.5;  // Aşırı alım = SAT
         else score += (50 - rsiVal[0]) * 0.5;
         weight++;
      }
      IndicatorRelease(rsiH);
   }
   
   // MACD
   int macdH = iMACD(symbol, PERIOD_CURRENT, inp_MACD_Fast, inp_MACD_Slow, inp_MACD_Signal, PRICE_CLOSE);
   if(macdH != INVALID_HANDLE)
   {
      double macdMain[2], macdSignal[2];
      if(CopyBuffer(macdH, 0, 0, 2, macdMain) > 0 && CopyBuffer(macdH, 1, 0, 2, macdSignal) > 0)
      {
         // Crossover
         if(macdMain[1] > macdSignal[1] && macdMain[0] <= macdSignal[0])
            score += 40; // Bullish cross
         else if(macdMain[1] < macdSignal[1] && macdMain[0] >= macdSignal[0])
            score -= 40; // Bearish cross
         
         // Histogram yönü
         double hist = macdMain[1] - macdSignal[1];
         score += MathMin(MathMax(hist * 1000, -30), 30);
         weight++;
      }
      IndicatorRelease(macdH);
   }
   
   // Moving Average Cross
   int maFastH = iMA(symbol, PERIOD_CURRENT, inp_MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   int maSlowH = iMA(symbol, PERIOD_CURRENT, inp_MA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   if(maFastH != INVALID_HANDLE && maSlowH != INVALID_HANDLE)
   {
      double maF[1], maS[1];
      if(CopyBuffer(maFastH, 0, 0, 1, maF) > 0 && CopyBuffer(maSlowH, 0, 0, 1, maS) > 0)
      {
         double diff = (maF[0] - maS[0]) / SymbolInfoDouble(symbol, SYMBOL_POINT) / 100;
         score += MathMin(MathMax(diff, -35), 35);
         weight++;
      }
      IndicatorRelease(maFastH);
      IndicatorRelease(maSlowH);
   }
   
   // Stochastic
   int stochH = iStochastic(symbol, PERIOD_CURRENT, inp_Stoch_K, inp_Stoch_D, inp_Stoch_Slow, MODE_SMA, STO_LOWHIGH);
   if(stochH != INVALID_HANDLE)
   {
      double stK[1], stD[1];
      if(CopyBuffer(stochH, 0, 0, 1, stK) > 0 && CopyBuffer(stochH, 1, 0, 1, stD) > 0)
      {
         if(stK[0] < 20) score += (20 - stK[0]) * 2;
         else if(stK[0] > 80) score -= (stK[0] - 80) * 2;
         weight++;
      }
      IndicatorRelease(stochH);
   }
   
   // ADX - Trend gücü
   int adxH = iADX(symbol, PERIOD_CURRENT, inp_ADX_Period);
   if(adxH != INVALID_HANDLE)
   {
      double adxVal[1], diPlus[1], diMinus[1];
      if(CopyBuffer(adxH, 0, 0, 1, adxVal) > 0 &&
         CopyBuffer(adxH, 1, 0, 1, diPlus) > 0 &&
         CopyBuffer(adxH, 2, 0, 1, diMinus) > 0)
      {
         double trendMult = adxVal[0] / 25.0; // ADX > 25 = güçlü trend
         if(diPlus[0] > diMinus[0]) score += 15 * trendMult;
         else score -= 15 * trendMult;
         weight++;
      }
      IndicatorRelease(adxH);
   }
   
   // Normalize et
   if(weight > 0)
      score = score / weight;
   
   return MathMin(MathMax(score, -100), 100);
}

//+------------------------------------------------------------------+
//| İNDİKATÖR YÖNETİMİ                                              |
//+------------------------------------------------------------------+
bool InitIndicators()
{
   if(g_ActiveSymbol == "") return false;
   
   h_RSI     = iRSI(g_ActiveSymbol, PERIOD_CURRENT, inp_RSI_Period, PRICE_CLOSE);
   h_MACD    = iMACD(g_ActiveSymbol, PERIOD_CURRENT, inp_MACD_Fast, inp_MACD_Slow, inp_MACD_Signal, PRICE_CLOSE);
   h_BB      = iBands(g_ActiveSymbol, PERIOD_CURRENT, inp_BB_Period, 0, inp_BB_Deviation, PRICE_CLOSE);
   h_MA_Fast = iMA(g_ActiveSymbol, PERIOD_CURRENT, inp_MA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   h_MA_Slow = iMA(g_ActiveSymbol, PERIOD_CURRENT, inp_MA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   h_Stoch   = iStochastic(g_ActiveSymbol, PERIOD_CURRENT, inp_Stoch_K, inp_Stoch_D, inp_Stoch_Slow, MODE_SMA, STO_LOWHIGH);
   h_ADX     = iADX(g_ActiveSymbol, PERIOD_CURRENT, inp_ADX_Period);
   h_ATR     = iATR(g_ActiveSymbol, PERIOD_CURRENT, inp_ATR_Period);
   
   if(h_RSI == INVALID_HANDLE || h_MACD == INVALID_HANDLE || 
      h_BB == INVALID_HANDLE || h_MA_Fast == INVALID_HANDLE ||
      h_MA_Slow == INVALID_HANDLE || h_Stoch == INVALID_HANDLE ||
      h_ADX == INVALID_HANDLE || h_ATR == INVALID_HANDLE)
   {
      Print("HATA: Bir veya daha fazla indikatör oluşturulamadı!");
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
void ReleaseIndicators()
{
   if(h_RSI != INVALID_HANDLE) IndicatorRelease(h_RSI);
   if(h_MACD != INVALID_HANDLE) IndicatorRelease(h_MACD);
   if(h_BB != INVALID_HANDLE) IndicatorRelease(h_BB);
   if(h_MA_Fast != INVALID_HANDLE) IndicatorRelease(h_MA_Fast);
   if(h_MA_Slow != INVALID_HANDLE) IndicatorRelease(h_MA_Slow);
   if(h_Stoch != INVALID_HANDLE) IndicatorRelease(h_Stoch);
   if(h_ADX != INVALID_HANDLE) IndicatorRelease(h_ADX);
   if(h_ATR != INVALID_HANDLE) IndicatorRelease(h_ATR);
}

//+------------------------------------------------------------------+
//| KOMPOZİT SKOR HESAPLAMA                                          |
//+------------------------------------------------------------------+
void CalculateCompositeScore()
{
   double totalScore = 0;
   int totalWeight = 0;
   
   // ── RSI (Ağırlık: 20) ──
   double rsiVal[1];
   if(CopyBuffer(h_RSI, 0, 0, 1, rsiVal) > 0)
   {
      if(rsiVal[0] < 30)
         g_RSI_Score = (30 - rsiVal[0]) * 2.5;
      else if(rsiVal[0] > 70)
         g_RSI_Score = -(rsiVal[0] - 70) * 2.5;
      else
         g_RSI_Score = (50 - rsiVal[0]) * 0.5;
      
      totalScore += g_RSI_Score * 20;
      totalWeight += 20;
   }
   
   // ── MACD (Ağırlık: 25) ──
   double macdMain[3], macdSig[3];
   if(CopyBuffer(h_MACD, 0, 0, 3, macdMain) > 0 && CopyBuffer(h_MACD, 1, 0, 3, macdSig) > 0)
   {
      double histogram = macdMain[2] - macdSig[2];
      double prevHist = macdMain[1] - macdSig[1];
      
      g_MACD_Score = 0;
      
      // Crossover sinyali
      if(macdMain[2] > macdSig[2] && macdMain[1] <= macdSig[1])
         g_MACD_Score += 50;
      else if(macdMain[2] < macdSig[2] && macdMain[1] >= macdSig[1])
         g_MACD_Score -= 50;
      
      // Histogram momentum
      if(histogram > prevHist) g_MACD_Score += 20;
      else g_MACD_Score -= 20;
      
      // Sıfır çizgisi
      if(macdMain[2] > 0) g_MACD_Score += 10;
      else g_MACD_Score -= 10;
      
      g_MACD_Score = MathMin(MathMax(g_MACD_Score, -100), 100);
      totalScore += g_MACD_Score * 25;
      totalWeight += 25;
   }
   
   // ── Bollinger Bands (Ağırlık: 15) ──
   double bbUpper[1], bbMiddle[1], bbLower[1];
   if(CopyBuffer(h_BB, 1, 0, 1, bbUpper) > 0 && 
      CopyBuffer(h_BB, 0, 0, 1, bbMiddle) > 0 &&
      CopyBuffer(h_BB, 2, 0, 1, bbLower) > 0)
   {
      double price = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_BID);
      double bbRange = bbUpper[0] - bbLower[0];
      
      if(bbRange > 0)
      {
         double bbPos = (price - bbLower[0]) / bbRange; // 0-1 arası
         
         if(bbPos < 0.1)       g_BB_Score = 80;   // Alt bant altı = Güçlü AL
         else if(bbPos < 0.3)  g_BB_Score = 40;   // Alt bant yakını = AL
         else if(bbPos > 0.9)  g_BB_Score = -80;  // Üst bant üstü = Güçlü SAT
         else if(bbPos > 0.7)  g_BB_Score = -40;  // Üst bant yakını = SAT
         else                  g_BB_Score = 0;     // Orta = Nötr
         
         totalScore += g_BB_Score * 15;
         totalWeight += 15;
      }
   }
   
   // ── Moving Average (Ağırlık: 20) ──
   double maF[2], maS[2];
   if(CopyBuffer(h_MA_Fast, 0, 0, 2, maF) > 0 && CopyBuffer(h_MA_Slow, 0, 0, 2, maS) > 0)
   {
      g_MA_Score = 0;
      double point = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_POINT);
      
      // Cross sinyali
      if(maF[1] > maS[1] && maF[0] <= maS[0]) g_MA_Score += 60;
      else if(maF[1] < maS[1] && maF[0] >= maS[0]) g_MA_Score -= 60;
      
      // Mesafe
      double dist = (maF[1] - maS[1]) / point / 50;
      g_MA_Score += MathMin(MathMax(dist, -40), 40);
      
      g_MA_Score = MathMin(MathMax(g_MA_Score, -100), 100);
      totalScore += g_MA_Score * 20;
      totalWeight += 20;
   }
   
   // ── Stochastic (Ağırlık: 10) ──
   double stK[2], stD[2];
   if(CopyBuffer(h_Stoch, 0, 0, 2, stK) > 0 && CopyBuffer(h_Stoch, 1, 0, 2, stD) > 0)
   {
      g_Stoch_Score = 0;
      
      if(stK[1] < 20 && stK[1] > stD[1]) g_Stoch_Score = 80;
      else if(stK[1] > 80 && stK[1] < stD[1]) g_Stoch_Score = -80;
      else if(stK[1] < 30) g_Stoch_Score = 30;
      else if(stK[1] > 70) g_Stoch_Score = -30;
      
      totalScore += g_Stoch_Score * 10;
      totalWeight += 10;
   }
   
   // ── ADX - Trend Gücü (Ağırlık: 10) ──
   double adxVal[1], diP[1], diM[1];
   if(CopyBuffer(h_ADX, 0, 0, 1, adxVal) > 0 &&
      CopyBuffer(h_ADX, 1, 0, 1, diP) > 0 &&
      CopyBuffer(h_ADX, 2, 0, 1, diM) > 0)
   {
      g_TrendStrength = adxVal[0];
      double trendMult = MathMin(adxVal[0] / 25.0, 2.0);
      
      if(diP[0] > diM[0]) g_ADX_Score = 40 * trendMult;
      else g_ADX_Score = -40 * trendMult;
      
      totalScore += g_ADX_Score * 10;
      totalWeight += 10;
   }
   
   // ── Kompozit skor ──
   if(totalWeight > 0)
      g_CompositeScore = totalScore / totalWeight;
   else
      g_CompositeScore = 0;
   
   g_CompositeScore = MathMin(MathMax(g_CompositeScore, -100), 100);
}

//+------------------------------------------------------------------+
//| KARAR MEKANİZMASI                                                |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| KARAR MEKANİZMASI - HER SANİYE ÇALIŞIR                          |
//+------------------------------------------------------------------+
void MakeTimerDecision(double totalPL, int openPos, int pendingOrd)
{
   // Maksimum grid seviyesine ulaşıldıysa yeni işlem açma
   if(openPos >= inp_MaxGridLevels) return;
   
   // İşlem yönünü belirle
   bool isBuy = true;
   bool hasSignal = false;
   
   if(MathAbs(g_CompositeScore) >= inp_MinScore)
   {
      // Skor yeterli → yönü skora göre belirle
      isBuy = (g_CompositeScore > 0);
      hasSignal = true;
   }
   else if(inp_ForceEveryTick)
   {
      // Skor yetersiz ama zorla işlem açılacak → en mantıklı yönü seç
      isBuy = DetermineSmartDirection(openPos);
      hasSignal = true;
   }
   
   if(!hasSignal) return;
   
   // Grid adımı kontrolü (opsiyonel)
   if(!inp_IgnoreGridStep && openPos > 0 && !ShouldOpenNewLevel(isBuy))
   {
      if(!inp_ForceEveryTick) return;
      
      // Zorla açılacak ama grid adımı dolmadı → ters yönü dene
      isBuy = !isBuy;
      if(!inp_IgnoreGridStep && openPos > 0 && !ShouldOpenNewLevel(isBuy))
      {
         // Her iki yönde de grid dolmadı ama ForceEvery aktif → grid'i yoksay ve aç
         isBuy = (g_CompositeScore >= 0); // Skora dön
      }
   }
   
   ENUM_ORDER_TYPE marketType = isBuy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   
   // ATR değerini al
   double atrVal[1];
   double atr = 0;
   if(CopyBuffer(h_ATR, 0, 0, 1, atrVal) > 0)
      atr = atrVal[0];
   
   // Lot hesapla
   double lot = CalculateLot();
   g_CurrentLevel = openPos;
   
   double point = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_BID);
   
   bool marketOpened = false;
   
   // ── MARKET EMİR ──
   if(inp_OrderMode == ORDER_MARKET_ONLY || inp_OrderMode == ORDER_ALL ||
      inp_OrderMode == ORDER_MARKET_LIMIT || inp_OrderMode == ORDER_MARKET_STOP)
   {
      if(OpenMarketOrder(marketType, lot))
      {
         g_CurrentLevel++;
         marketOpened = true;
         g_TradesThisSecond++;
         Print("⏱ [", TimeToString(TimeCurrent(), TIME_SECONDS), "] Market ", 
               (isBuy ? "BUY" : "SELL"), " | Lot: ", DoubleToString(lot, 2),
               " | Skor: ", DoubleToString(g_CompositeScore, 1), 
               " | Level: ", g_CurrentLevel,
               " | Float: $", DoubleToString(totalPL, 2));
      }
   }
   
   // ── LIMIT EMİR ──
   if(inp_OrderMode == ORDER_LIMIT_ONLY || inp_OrderMode == ORDER_ALL ||
      inp_OrderMode == ORDER_MARKET_LIMIT || inp_OrderMode == ORDER_LIMIT_STOP)
   {
      // Her saniye eski limitleri sil, yeni koy
      DeletePendingByType(isBuy ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT);
      
      double limitLot = CalculateLot();
      
      // Dinamik limit mesafesi (ATR bazlı veya sabit)
      double limitDist = (atr > 0) ? 
         MathMax(atr * 0.5, inp_LimitDistance * point) : 
         inp_LimitDistance * point;
      
      if(isBuy)
      {
         double limitPrice = ask - limitDist;
         limitPrice = NormalizeDouble(limitPrice, (int)SymbolInfoInteger(g_ActiveSymbol, SYMBOL_DIGITS));
         OpenPendingOrder(ORDER_TYPE_BUY_LIMIT, limitLot, limitPrice);
      }
      else
      {
         double limitPrice = bid + limitDist;
         limitPrice = NormalizeDouble(limitPrice, (int)SymbolInfoInteger(g_ActiveSymbol, SYMBOL_DIGITS));
         OpenPendingOrder(ORDER_TYPE_SELL_LIMIT, limitLot, limitPrice);
      }
   }
   
   // ── STOP EMİR ──
   if(inp_OrderMode == ORDER_STOP_ONLY || inp_OrderMode == ORDER_ALL ||
      inp_OrderMode == ORDER_MARKET_STOP || inp_OrderMode == ORDER_LIMIT_STOP)
   {
      // Her saniye eski stop'ları sil, yeni koy
      DeletePendingByType(isBuy ? ORDER_TYPE_BUY_STOP : ORDER_TYPE_SELL_STOP);
      
      double stopLot = CalculateLot();
      
      double stopDist = (atr > 0) ? 
         MathMax(atr * 0.5, inp_StopDistance * point) : 
         inp_StopDistance * point;
      
      if(isBuy)
      {
         double stopPrice = ask + stopDist;
         stopPrice = NormalizeDouble(stopPrice, (int)SymbolInfoInteger(g_ActiveSymbol, SYMBOL_DIGITS));
         OpenPendingOrder(ORDER_TYPE_BUY_STOP, stopLot, stopPrice);
      }
      else
      {
         double stopPrice = bid - stopDist;
         stopPrice = NormalizeDouble(stopPrice, (int)SymbolInfoInteger(g_ActiveSymbol, SYMBOL_DIGITS));
         OpenPendingOrder(ORDER_TYPE_SELL_STOP, stopLot, stopPrice);
      }
   }
   
   // Market emir açılmadıysa ve force aktifse → sadece market olarak zorla
   if(!marketOpened && inp_ForceEveryTick && 
      (inp_OrderMode == ORDER_LIMIT_ONLY || inp_OrderMode == ORDER_STOP_ONLY || inp_OrderMode == ORDER_LIMIT_STOP))
   {
      // Limit/Stop only modunda market yok, ama force aktif → limit/stop zaten konuldu
      // Ek olarak küçük lotla market da aç
      double forceLot = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_VOLUME_MIN);
      if(OpenMarketOrder(marketType, forceLot))
      {
         g_CurrentLevel++;
         Print("⚡ FORCE Market ", (isBuy ? "BUY" : "SELL"), " | Lot: ", DoubleToString(forceLot, 2));
      }
   }
}

//+------------------------------------------------------------------+
//| AKILLI YÖN BELİRLEME (Skor düşük olduğunda)                    |
//+------------------------------------------------------------------+
bool DetermineSmartDirection(int openPos)
{
   // 1. Mevcut pozisyon yoksa → skora bak (düşük de olsa yön veriyor)
   if(openPos == 0)
      return (g_CompositeScore >= 0);
   
   // 2. Mevcut pozisyon varsa → ortalamayı düşürecek yönde aç
   double buyPL = 0, sellPL = 0;
   int buyCount = 0, sellCount = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_ActiveSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;
      
      double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      if(posType == POSITION_TYPE_BUY) { buyPL += pl; buyCount++; }
      else { sellPL += pl; sellCount++; }
   }
   
   // En çok zararda olan yönü destekle (martingale mantığı)
   if(inp_Strategy == STRATEGY_MARTINGALE)
   {
      if(buyPL < sellPL) return true;   // Buy'lar zararda → buy ekle (ortalamayı düşür)
      else return false;                 // Sell'ler zararda → sell ekle
   }
   
   // Anti-martingale → kârdaki yönü destekle
   if(inp_Strategy == STRATEGY_ANTIMARTINGALE)
   {
      if(buyPL > sellPL) return true;
      else return false;
   }
   
   // Fixed grid → skora göre
   return (g_CompositeScore >= 0);
}

//+------------------------------------------------------------------+
//| LOT HESAPLAMA                                                    |
//+------------------------------------------------------------------+
double CalculateLot()
{
   double lot = inp_InitialLot;
   
   switch(inp_Strategy)
   {
      case STRATEGY_MARTINGALE:
         // Her zararda lot çarpanı ile büyüt
         if(g_CurrentLevel > 0 && !g_LastTradeWin)
         {
            lot = g_LastLot * inp_LotMultiplier;
         }
         else if(g_CurrentLevel > 0)
         {
            // Grid seviyesine göre de büyüt
            lot = inp_InitialLot * MathPow(inp_LotMultiplier, g_CurrentLevel);
         }
         else
         {
            lot = inp_InitialLot;
         }
         break;
         
      case STRATEGY_ANTIMARTINGALE:
         // Her kârda lot çarpanı ile büyüt
         if(g_CurrentLevel > 0 && g_LastTradeWin)
         {
            lot = g_LastLot * inp_LotMultiplier;
         }
         else
         {
            lot = inp_InitialLot; // Zararda başa dön
         }
         break;
         
      case STRATEGY_FIXED_GRID:
         // Her seviyede sabit lot
         lot = inp_InitialLot;
         break;
   }
   
   // Sınırları kontrol et
   double minLot = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_VOLUME_STEP);
   
   lot = MathMin(lot, inp_MaxLot);
   lot = MathMin(lot, maxLot);
   lot = MathMax(lot, minLot);
   lot = MathRound(lot / lotStep) * lotStep;
   
   g_LastLot = lot;
   return lot;
}

//+------------------------------------------------------------------+
//| GRID SEVİYE KONTROLÜ                                             |
//+------------------------------------------------------------------+
bool ShouldOpenNewLevel(bool isBuy)
{
   double lastPrice = 0;
   double point = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_POINT);
   double gridStep = inp_GridStepPoints * point;
   double currentPrice = isBuy ? 
      SymbolInfoDouble(g_ActiveSymbol, SYMBOL_ASK) : 
      SymbolInfoDouble(g_ActiveSymbol, SYMBOL_BID);
   
   // Son açılan pozisyonun fiyatını bul
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_ActiveSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Aynı yönde mi kontrol et
      if((isBuy && posType == POSITION_TYPE_BUY) || (!isBuy && posType == POSITION_TYPE_SELL))
      {
         lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         break;
      }
   }
   
   if(lastPrice == 0) return true; // Hiç pozisyon yoksa aç
   
   // Grid mesafesi kontrolü
   double distance = MathAbs(currentPrice - lastPrice);
   return (distance >= gridStep);
}

//+------------------------------------------------------------------+
//| EMİR FONKSİYONLARI                                              |
//+------------------------------------------------------------------+
bool OpenMarketOrder(ENUM_ORDER_TYPE type, double lot)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action   = TRADE_ACTION_DEAL;
   request.symbol   = g_ActiveSymbol;
   request.volume   = lot;
   request.type     = type;
   request.price    = (type == ORDER_TYPE_BUY) ? 
                       SymbolInfoDouble(g_ActiveSymbol, SYMBOL_ASK) : 
                       SymbolInfoDouble(g_ActiveSymbol, SYMBOL_BID);
   request.deviation= 30;
   request.magic    = inp_MagicNumber;
   request.comment  = "TDE_L" + IntegerToString(g_CurrentLevel + 1) + 
                      "_S" + DoubleToString(g_CompositeScore, 0);
   request.type_filling = ORDER_FILLING_IOC;
   
   if(!OrderSend(request, result))
   {
      Print("❌ Market emir hatası: ", result.retcode, " - ", GetRetcodeDescription(result.retcode));
      
      // FOK dene
      if(result.retcode == 10030)
      {
         request.type_filling = ORDER_FILLING_FOK;
         if(!OrderSend(request, result))
         {
            Print("❌ FOK de başarısız: ", result.retcode);
            return false;
         }
      }
      else return false;
   }
   
   if(result.retcode == 10009 || result.retcode == 10008)
   {
      g_TotalTrades++;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
bool OpenPendingOrder(ENUM_ORDER_TYPE type, double lot, double price)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   request.action    = TRADE_ACTION_PENDING;
   request.symbol    = g_ActiveSymbol;
   request.volume    = lot;
   request.type      = type;
   request.price     = price;
   request.magic     = inp_MagicNumber;
   request.comment   = "TDE_P_" + EnumToString(type);
   request.type_filling = ORDER_FILLING_IOC;
   
   // Süre
   if(inp_PendingExpiry > 0)
   {
      request.type_time = ORDER_TIME_SPECIFIED;
      request.expiration = TimeCurrent() + inp_PendingExpiry * 60;
   }
   else
   {
      request.type_time = ORDER_TIME_GTC;
   }
   
   if(!OrderSend(request, result))
   {
      // FOK dene
      request.type_filling = ORDER_FILLING_FOK;
      if(!OrderSend(request, result))
      {
         if(result.retcode != 10013) // "Invalid request" sessiz geç
            Print("❌ Bekleyen emir hatası: ", result.retcode, " Tip: ", EnumToString(type));
         return false;
      }
   }
   
   return (result.retcode == 10009 || result.retcode == 10008);
}

//+------------------------------------------------------------------+
//| POZİSYON YÖNETİMİ                                               |
//+------------------------------------------------------------------+
double GetTotalFloatingPL()
{
   double totalPL = 0;
   
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_ActiveSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;
      
      totalPL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   }
   
   return totalPL;
}

//+------------------------------------------------------------------+
int CountPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_ActiveSymbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != g_ActiveSymbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
bool HasPendingOfType(ENUM_ORDER_TYPE type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != g_ActiveSymbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) == type) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void CloseAllPositions()
{
   int closed = 0;
   double closedPL = 0;
   
   for(int attempt = 0; attempt < 3; attempt++)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != g_ActiveSymbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != inp_MagicNumber) continue;
         
         double pl = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         
         MqlTradeRequest request = {};
         MqlTradeResult result = {};
         
         request.action   = TRADE_ACTION_DEAL;
         request.symbol   = g_ActiveSymbol;
         request.volume   = PositionGetDouble(POSITION_VOLUME);
         request.position = ticket;
         request.deviation = 30;
         request.magic    = inp_MagicNumber;
         request.type_filling = ORDER_FILLING_IOC;
         
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
         request.price = (posType == POSITION_TYPE_BUY) ? 
                          SymbolInfoDouble(g_ActiveSymbol, SYMBOL_BID) : 
                          SymbolInfoDouble(g_ActiveSymbol, SYMBOL_ASK);
         
         if(OrderSend(request, result))
         {
            if(result.retcode == 10009 || result.retcode == 10008)
            {
               closed++;
               closedPL += pl;
               if(pl > 0) g_WinTrades++; else g_LossTrades++;
            }
         }
      }
      
      if(CountPositions() == 0) break;
      Sleep(100);
   }
   
   g_TotalProfit += closedPL;
   g_LastTradeWin = (closedPL > 0);
   
   Print("🔒 ", closed, " pozisyon kapatıldı | Kâr: $", DoubleToString(closedPL, 2),
         " | Toplam: $", DoubleToString(g_TotalProfit, 2));
}

//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != g_ActiveSymbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber) continue;
      
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_REMOVE;
      request.order  = ticket;
      
      OrderSend(request, result);
   }
}

//+------------------------------------------------------------------+
void DeletePendingByType(ENUM_ORDER_TYPE type)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetString(ORDER_SYMBOL) != g_ActiveSymbol) continue;
      if(OrderGetInteger(ORDER_MAGIC) != inp_MagicNumber) continue;
      if((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE) != type) continue;
      
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      
      request.action = TRADE_ACTION_REMOVE;
      request.order  = ticket;
      
      OrderSend(request, result);
   }
}

//+------------------------------------------------------------------+
void ResetCycle()
{
   g_CurrentLevel = 0;
   g_LastLot = inp_InitialLot;
}

//+------------------------------------------------------------------+
//| BİLGİ PANELİ                                                     |
//+------------------------------------------------------------------+
void CreatePanel()
{
   ObjectsDeleteAll(0, "TDE_");
}

//+------------------------------------------------------------------+
void UpdatePanel()
{
   int x = 10, y = 30;
   int lineH = 18;
   int col2 = 160;
   
   ObjectsDeleteAll(0, "TDE_");
   
   // ── BAŞLIK ──
   CreateLabel("TDE_Title", x, y, "═══ TICK DECISION EA ═══", clrGold, 11);
   y += lineH + 5;
   
   // ── AKTİF SEMBOL ──
   string modeStr = (inp_SymbolMode == SYMBOL_AUTO) ? " (AUTO)" : " (MANUAL)";
   CreateLabel("TDE_Sym", x, y, "Sembol: " + g_ActiveSymbol + modeStr, clrCyan, 9);
   y += lineH;
   
   // ── STRATEJİ ──
   string stratStr = "";
   switch(inp_Strategy)
   {
      case STRATEGY_MARTINGALE:     stratStr = "MARTINGALE"; break;
      case STRATEGY_ANTIMARTINGALE: stratStr = "ANTI-MARTINGALE"; break;
      case STRATEGY_FIXED_GRID:     stratStr = "FIXED GRID"; break;
   }
   CreateLabel("TDE_Strat", x, y, "Strateji: " + stratStr, clrWhite, 9);
   y += lineH;
   
   // ── FİYAT ──
   double bid = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(g_ActiveSymbol, SYMBOL_ASK);
   int digits = (int)SymbolInfoInteger(g_ActiveSymbol, SYMBOL_DIGITS);
   CreateLabel("TDE_Price", x, y, "Fiyat: " + DoubleToString(bid, digits) + " / " + DoubleToString(ask, digits), clrWhite, 9);
   y += lineH + 5;
   
   // ── İNDİKATÖR SKORLARI ──
   CreateLabel("TDE_IndTitle", x, y, "─── İNDİKATÖR SKORLARI ───", clrYellow, 9);
   y += lineH;
   
   CreateLabel("TDE_Score", x, y, "KOMPOZİT SKOR:", clrWhite, 9);
   CreateLabel("TDE_ScoreV", col2, y, DoubleToString(g_CompositeScore, 1), 
               (g_CompositeScore > 0 ? inp_BuyColor : g_CompositeScore < 0 ? inp_SellColor : clrGray), 10);
   y += lineH;
   
   CreateLabel("TDE_RSI", x, y, "RSI:", clrSilver, 8);
   CreateLabel("TDE_RSIV", col2, y, ScoreBar(g_RSI_Score), ScoreColor(g_RSI_Score), 8);
   y += lineH;
   
   CreateLabel("TDE_MACD", x, y, "MACD:", clrSilver, 8);
   CreateLabel("TDE_MACDV", col2, y, ScoreBar(g_MACD_Score), ScoreColor(g_MACD_Score), 8);
   y += lineH;
   
   CreateLabel("TDE_BB", x, y, "Bollinger:", clrSilver, 8);
   CreateLabel("TDE_BBV", col2, y, ScoreBar(g_BB_Score), ScoreColor(g_BB_Score), 8);
   y += lineH;
   
   CreateLabel("TDE_MA", x, y, "MA Cross:", clrSilver, 8);
   CreateLabel("TDE_MAV", col2, y, ScoreBar(g_MA_Score), ScoreColor(g_MA_Score), 8);
   y += lineH;
   
   CreateLabel("TDE_Stch", x, y, "Stochastic:", clrSilver, 8);
   CreateLabel("TDE_StchV", col2, y, ScoreBar(g_Stoch_Score), ScoreColor(g_Stoch_Score), 8);
   y += lineH;
   
   CreateLabel("TDE_ADX", x, y, "ADX/Trend:", clrSilver, 8);
   CreateLabel("TDE_ADXV", col2, y, ScoreBar(g_ADX_Score) + " [" + DoubleToString(g_TrendStrength, 0) + "]", ScoreColor(g_ADX_Score), 8);
   y += lineH;
   
   // Yön
   string direction = "NÖTR";
   color dirColor = clrGray;
   if(g_CompositeScore > inp_MinScore) { direction = "▲ BUY"; dirColor = inp_BuyColor; }
   else if(g_CompositeScore < -inp_MinScore) { direction = "▼ SELL"; dirColor = inp_SellColor; }
   
   CreateLabel("TDE_Dir", x, y, "Sinyal: " + direction, dirColor, 10);
   y += lineH + 5;
   
   // ── POZİSYON BİLGİSİ ──
   CreateLabel("TDE_PosTitle", x, y, "─── POZİSYON DURUMU ───", clrYellow, 9);
   y += lineH;
   
   int posCount = CountPositions();
   int pendCount = CountPendingOrders();
   double floatPL = GetTotalFloatingPL();
   
   CreateLabel("TDE_Pos", x, y, "Açık Poz: " + IntegerToString(posCount) + " | Level: " + IntegerToString(g_CurrentLevel), clrWhite, 9);
   y += lineH;
   
   CreateLabel("TDE_Pend", x, y, "Bekleyen: " + IntegerToString(pendCount), clrWhite, 9);
   y += lineH;
   
   CreateLabel("TDE_Float", x, y, "Anlık K/Z: $" + DoubleToString(floatPL, 2), 
               (floatPL >= 0 ? clrLime : clrRed), 9);
   y += lineH;
   
   CreateLabel("TDE_Lot", x, y, "Son Lot: " + DoubleToString(g_LastLot, 2), clrWhite, 9);
   y += lineH;
   
   // Kâr hedefine mesafe
   double remaining = inp_TargetProfit - floatPL;
   CreateLabel("TDE_Target", x, y, "Hedef: $" + DoubleToString(inp_TargetProfit, 2) + 
               " | Kalan: $" + DoubleToString(remaining, 2), clrGold, 9);
   y += lineH + 5;
   
   // ── İSTATİSTİKLER ──
   CreateLabel("TDE_StatTitle", x, y, "─── İSTATİSTİKLER ───", clrYellow, 9);
   y += lineH;
   
   CreateLabel("TDE_Total", x, y, "Toplam İşlem: " + IntegerToString(g_TotalTrades), clrWhite, 9);
   y += lineH;
   
   CreateLabel("TDE_WinLoss", x, y, "Kâr: " + IntegerToString(g_WinTrades) + " | Zarar: " + IntegerToString(g_LossTrades), clrWhite, 9);
   y += lineH;
   
   double winRate = (g_TotalTrades > 0) ? (double)g_WinTrades / g_TotalTrades * 100 : 0;
   CreateLabel("TDE_WR", x, y, "Başarı: %" + DoubleToString(winRate, 1), 
               (winRate >= 50 ? clrLime : clrOrange), 9);
   y += lineH;
   
   CreateLabel("TDE_NetPL", x, y, "Net Kâr: $" + DoubleToString(g_TotalProfit, 2), 
               (g_TotalProfit >= 0 ? clrLime : clrRed), 10);
   y += lineH;
   
   CreateLabel("TDE_Cycle", x, y, "Döngü: " + IntegerToString(g_CycleCount), clrWhite, 9);
   y += lineH;
   
   CreateLabel("TDE_Timer", x, y, "⏱ Aralık: " + IntegerToString(inp_TradeInterval) + "sn | Force: " + 
               (inp_ForceEveryTick ? "ON" : "OFF"), clrMagenta, 9);
   y += lineH;
   
   CreateLabel("TDE_SecTrade", x, y, "İşlem/Sn: " + IntegerToString(g_TradesThisSecond), clrMagenta, 9);
   y += lineH + 5;
   
   // ── EXPLORER TABLOSU ──
   if(inp_ShowExplorer && inp_SymbolMode == SYMBOL_AUTO)
   {
      CreateLabel("TDE_ExpTitle", x, y, "─── EXPLORER ───", clrYellow, 9);
      y += lineH;
      
      // Skorlara göre sırala
      int indices[];
      ArrayResize(indices, g_ExplorerCount);
      for(int i = 0; i < g_ExplorerCount; i++) indices[i] = i;
      
      // Basit sıralama
      for(int i = 0; i < g_ExplorerCount - 1; i++)
      {
         for(int j = i + 1; j < g_ExplorerCount; j++)
         {
            if(MathAbs(g_ExplorerScores[indices[j]]) > MathAbs(g_ExplorerScores[indices[i]]))
            {
               int temp = indices[i];
               indices[i] = indices[j];
               indices[j] = temp;
            }
         }
      }
      
      int maxShow = MathMin(g_ExplorerCount, 8);
      for(int i = 0; i < maxShow; i++)
      {
         int idx = indices[i];
         string sym = g_ExplorerList[idx];
         double sc = g_ExplorerScores[idx];
         string dir = g_ExplorerDirections[idx];
         
         string marker = (sym == g_ActiveSymbol) ? " ◄" : "";
         color lineColor = (sc > 0) ? inp_BuyColor : (sc < 0) ? inp_SellColor : clrGray;
         
         CreateLabel("TDE_Exp" + IntegerToString(i), x, y, 
                     StringFormat("%-10s %6s %5.1f%s", sym, dir, sc, marker),
                     lineColor, 8);
         y += lineH - 2;
      }
   }
   
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
   }
   
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
}

//+------------------------------------------------------------------+
//| YARDIMCI FONKSİYONLAR                                           |
//+------------------------------------------------------------------+
string ScoreBar(double score)
{
   string bar = "";
   int blocks = (int)(MathAbs(score) / 10);
   
   if(score > 0)
      for(int i = 0; i < blocks; i++) bar += "█";
   else
      for(int i = 0; i < blocks; i++) bar += "█";
   
   return StringFormat("%+6.1f ", score) + bar;
}

//+------------------------------------------------------------------+
color ScoreColor(double score)
{
   if(score > 30) return clrLime;
   if(score > 0)  return clrDodgerBlue;
   if(score < -30) return clrRed;
   if(score < 0)  return clrOrangeRed;
   return clrGray;
}

//+------------------------------------------------------------------+
string GetRetcodeDescription(uint retcode)
{
   switch(retcode)
   {
      case 10004: return "Requote";
      case 10006: return "Request rejected";
      case 10007: return "Request canceled by trader";
      case 10008: return "Order placed";
      case 10009: return "Request completed";
      case 10010: return "Only part filled";
      case 10011: return "Request handling error";
      case 10012: return "Request canceled by timeout";
      case 10013: return "Invalid request";
      case 10014: return "Invalid volume";
      case 10015: return "Invalid price";
      case 10016: return "Invalid stops";
      case 10017: return "Trade disabled";
      case 10018: return "Market closed";
      case 10019: return "Not enough money";
      case 10020: return "Prices changed";
      case 10021: return "No quotes";
      case 10022: return "Invalid order expiration";
      case 10023: return "Order changed";
      case 10024: return "Too many requests";
      case 10025: return "No changes in request";
      case 10026: return "Autotrading disabled by server";
      case 10027: return "Autotrading disabled by client";
      case 10028: return "Request locked for processing";
      case 10029: return "Order or position frozen";
      case 10030: return "Invalid order filling type";
      case 10031: return "No connection with trade server";
      case 10032: return "Only for real accounts";
      case 10033: return "Pending orders limit reached";
      case 10034: return "Volume limit reached";
      default:    return "Unknown error " + IntegerToString(retcode);
   }
}
//+------------------------------------------------------------------+