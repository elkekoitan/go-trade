//+------------------------------------------------------------------+
//|                         TickTrader_Pro_v8_Universal.mq5           |
//|  Evrensel Enstrüman / Grafik Panel / 3-Bölüm Pozisyon / SmartClose|
//+------------------------------------------------------------------+
#property copyright   "TickTrader Pro v8.0 Universal"
#property version     "8.00"
#property description "Tüm enstrüman desteği + Grafik Panel + Konsolidasyon Filtresi"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== SMART CLOSE POZISYON YAPISI =====================================
struct SAllPos
{
   ulong  ticket;
   string symbol;
   int    posType;   // 0=BUY, 1=SELL
   double openPx;
   double pnl;
   double lot;
   ulong  magic;
};

//=== LOT VE GUVENLIK =================================================
input group "===== LOT ve GUVENLIK ====="
input double   Inp_LotFixed          = 0.01;
input double   Inp_LotMax            = 0.01;
input double   Inp_MaxTotalLots      = 0.30;
input int      Inp_MaxOpenPos        = 30;
input int      Inp_MaxTotalTrades    = 500;        // Toplam islem siniri (500-1000)
input double   Inp_MinFreeMarginUSD  = 50.0;
input double   Inp_MinFreeMarginPct  = 30.0;
input double   Inp_MaxDrawdownPct    = 40.0;

//=== KAR / ZARAR =====================================================
input group "===== KAR / ZARAR ====="
input double   Inp_TP_Single         = 0.50;
input double   Inp_TP_BuyGroup       = 3.0;
input double   Inp_TP_SellGroup      = 3.0;
input double   Inp_TP_Total          = 5.0;
input double   Inp_SL_Total          = -50.0;

//=== SKOR BAZLI YON ==================================================
input group "===== SKOR YON AYARLARI ====="
input double   Inp_ScoreBuyOnly      = 30.0;
input double   Inp_ScoreSellOnly     = -30.0;

//=== KONSOLIDASYON FILTRESI ==========================================
input group "===== KONSOLIDASYON FILTRESI ====="
input bool     Inp_ConsolidationFilter   = true;    // Konsolidasyon filtresi aktif
input int      Inp_ConsoATR_Period       = 14;      // ATR periyodu (konsolidasyon)
input double   Inp_ConsoATR_MinRatio     = 0.5;     // Min ATR orani (dusuk=yatay)
input double   Inp_ConsoATR_MaxRatio     = 2.5;     // Max ATR orani (yuksek=trend/sert)
input int      Inp_ConsoATR_LookBack     = 50;      // ATR ortalama karsilastirma periyodu
input bool     Inp_ConsoAutoRestart      = false;   // Sert hareket sonrasi otomatik yeniden baslat
input ulong    Inp_ConsoNewMagic         = 0;       // Yeni magic number (0=otomatik)

//=== SMART CLOSE =====================================================
input group "===== SMART CLOSE (EVRENSEL) ====="
input bool     Inp_SmartEnabled         = true;
input double   Inp_SmartActivateDDPct   = 10.0;
input double   Inp_SmartActivateLossUSD = 20.0;
input int      Inp_SmartMinGroup        = 3;
input int      Inp_SmartMaxGroup        = 6;
input double   Inp_SmartMinNet          = 0.05;
input double   Inp_SmartMinLossUSD      = 1.0;
input int      Inp_SmartCheckSec        = 5;
input bool     Inp_SmartAggressiveMode  = false;

//=== GRID / KAFES ====================================================
input group "===== GRID / KAFES ====="
input int      Inp_GridStep          = 100;
input int      Inp_BuyLimitLevels    = 3;
input int      Inp_BuyStopLevels     = 2;
input int      Inp_SellLimitLevels   = 3;
input int      Inp_SellStopLevels    = 2;
input int      Inp_MaxDistance       = 400;
input int      Inp_RefreshDist       = 50;
input int      Inp_MaxRange          = 500;

//=== KURTARMA ========================================================
input group "===== KURTARMA ====="
input bool     Inp_RecoveryEnabled   = true;
input int      Inp_RecoveryGridShift = 20;
input double   Inp_RecoveryMinLoss   = 1.0;

//=== TAHMIN ==========================================================
input group "===== TAHMIN ====="
input int      Inp_MA_Fast           = 5;
input int      Inp_MA_Slow           = 21;
input int      Inp_RSI_Period        = 14;
input int      Inp_ATR_Period        = 14;
input int      Inp_CCI_Period        = 14;
input int      Inp_BB_Period         = 20;
input double   Inp_BB_Dev            = 2.0;
input int      Inp_MACD_Fast         = 12;
input int      Inp_MACD_Slow         = 26;
input int      Inp_MACD_Signal       = 9;
input int      Inp_Stoch_K           = 14;
input int      Inp_Stoch_D           = 3;
input int      Inp_Stoch_Slow        = 3;
input int      Inp_MinScore          = 15;
input ENUM_TIMEFRAMES Inp_TF         = PERIOD_M1;

//=== EMIR RENKLERI ===================================================
input group "===== EMIR RENKLERI ====="
input color    Inp_ClrBuyLimit       = clrDodgerBlue;    // Buy Limit rengi
input color    Inp_ClrBuyStop        = clrLimeGreen;     // Buy Stop rengi
input color    Inp_ClrSellLimit      = clrOrangeRed;     // Sell Limit rengi
input color    Inp_ClrSellStop       = clrMagenta;       // Sell Stop rengi

//=== PANEL ============================================================
input group "===== PANEL ====="
input int      Inp_PanelX            = 10;       // Panel X pozisyonu
input int      Inp_PanelY            = 25;       // Panel Y pozisyonu
input int      Inp_PanelFontSize     = 8;        // Font boyutu
input color    Inp_PanelBgColor      = C'20,20,30';      // Panel arka plan
input color    Inp_PanelBorderColor  = C'60,60,80';      // Panel kenar rengi
input color    Inp_PanelTextColor    = C'200,200,220';    // Metin rengi
input color    Inp_PanelBuyColor     = C'0,180,100';      // Buy rengi
input color    Inp_PanelSellColor    = C'220,60,60';      // Sell rengi
input color    Inp_PanelProfitColor  = C'0,220,100';      // Kar rengi
input color    Inp_PanelLossColor    = C'255,60,60';      // Zarar rengi

//=== GENEL ============================================================
input group "===== GENEL ====="
input ulong    Inp_Magic             = 240607;
input int      Inp_Slippage          = 50;

//=== GLOBAL ===========================================================
CTrade         m_trade;
CPositionInfo  m_pos;
COrderInfo     m_ord;

int   h_maF, h_maS, h_rsi, h_atr, h_cci, h_bb, h_macd, h_stoch;
int   h_consoATR;

// Robot pozisyonlari (kendi magic)
int    g_posBuy, g_posSell, g_posTotal, g_posLoss;
double g_pnlBuy, g_pnlSell, g_pnlTotal;
double g_lotBuy, g_lotSell, g_lotTotal;
double g_avgBuyPx, g_avgSellPx;
double g_lowBuyPx, g_highSellPx;
double g_highBuyPx, g_lowSellPx;

// Diger EA pozisyonlari
int    g_otherPosBuy, g_otherPosSell, g_otherPosTotal;
double g_otherPnlBuy, g_otherPnlSell, g_otherPnlTotal;
double g_otherLotBuy, g_otherLotSell, g_otherLotTotal;

// Manuel pozisyonlar (magic=0)
int    g_manualPosBuy, g_manualPosSell, g_manualPosTotal;
double g_manualPnlBuy, g_manualPnlSell, g_manualPnlTotal;
double g_manualLotBuy, g_manualLotSell, g_manualLotTotal;

// Hesap geneli
int    g_accTotal, g_accLoss;
double g_accPnl, g_accLotTotal;
double g_accDDPct;
double g_accLossUSD;

// Emirler
int    g_ordBL, g_ordBS, g_ordSL, g_ordSS, g_ordTotal;

// Tahmin
int    g_dir;
double g_score;
double g_target;
string g_reason;

// Kafes
double g_anchor;

// SmartClose
datetime g_lastSmartCheck;
int      g_smartCloseCount;
string   g_smartInfo;
bool     g_smartActive;
string   g_smartTrigger;

// Kafes yonler
bool   g_kafes_buy_aktif;
bool   g_kafes_sell_aktif;

// Konsolidasyon
string g_consoStatus;
bool   g_consoOK;
double g_consoRatio;

// Toplam islem sayaci
int    g_totalTradeCount;

// Panel buton durumlari
bool   g_btnSmartCloseEnabled;
bool   g_btnBuyEnabled;
bool   g_btnSellEnabled;

// Panel sabitler
#define PANEL_W        380
#define PANEL_H        720
#define BTN_W          82
#define BTN_H          22
#define LINE_H         14
#define PREFIX         "TTP8_"

//+------------------------------------------------------------------+
//| Filling tipi otomatik algilama (tum enstrumanlar icin)           |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING DetectFilling()
{
   long fillPolicy = SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   // Bit mask kontrolu
   if((fillPolicy & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;
   if((fillPolicy & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   // Fallback: RETURN (kismi dolum veya geri kalan iptal)
   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Filling tipi otomatik algilansin — tum enstrumanlar icin
   ENUM_ORDER_TYPE_FILLING fillType = DetectFilling();
   m_trade.SetExpertMagicNumber(Inp_Magic);
   m_trade.SetDeviationInPoints(Inp_Slippage);
   m_trade.SetTypeFilling(fillType);

   string fillStr = (fillType == ORDER_FILLING_FOK) ? "FOK" :
                     (fillType == ORDER_FILLING_IOC) ? "IOC" : "RETURN";
   PrintFormat("Sembol: %s | Filling: %s | Digits: %d | Point: %s",
               _Symbol, fillStr, _Digits, DoubleToString(_Point, _Digits));

   h_maF   = iMA(_Symbol,Inp_TF,Inp_MA_Fast,0,MODE_EMA,PRICE_CLOSE);
   h_maS   = iMA(_Symbol,Inp_TF,Inp_MA_Slow,0,MODE_EMA,PRICE_CLOSE);
   h_rsi   = iRSI(_Symbol,Inp_TF,Inp_RSI_Period,PRICE_CLOSE);
   h_atr   = iATR(_Symbol,Inp_TF,Inp_ATR_Period);
   h_cci   = iCCI(_Symbol,Inp_TF,Inp_CCI_Period,PRICE_TYPICAL);
   h_bb    = iBands(_Symbol,Inp_TF,Inp_BB_Period,0,Inp_BB_Dev,PRICE_CLOSE);
   h_macd  = iMACD(_Symbol,Inp_TF,Inp_MACD_Fast,Inp_MACD_Slow,Inp_MACD_Signal,PRICE_CLOSE);
   h_stoch = iStochastic(_Symbol,Inp_TF,Inp_Stoch_K,Inp_Stoch_D,Inp_Stoch_Slow,MODE_SMA,STO_LOWHIGH);

   // Konsolidasyon ATR
   h_consoATR = iATR(_Symbol, Inp_TF, Inp_ConsoATR_Period);

   if(h_maF==INVALID_HANDLE || h_maS==INVALID_HANDLE ||
      h_rsi==INVALID_HANDLE || h_atr==INVALID_HANDLE ||
      h_cci==INVALID_HANDLE || h_bb==INVALID_HANDLE  ||
      h_macd==INVALID_HANDLE|| h_stoch==INVALID_HANDLE||
      h_consoATR==INVALID_HANDLE)
   {
      Alert("Indikator yuklenemedi! Sembol: ", _Symbol);
      return INIT_FAILED;
   }

   g_anchor          = 0;
   g_lastSmartCheck  = 0;
   g_smartCloseCount = 0;
   g_smartInfo       = "Bekleniyor...";
   g_smartActive     = false;
   g_smartTrigger    = "YOK";
   g_kafes_buy_aktif = true;
   g_kafes_sell_aktif= true;
   g_accDDPct        = 0;
   g_accLossUSD      = 0;
   g_consoStatus     = "HESAPLANIYOR";
   g_consoOK         = true;
   g_consoRatio      = 1.0;
   g_totalTradeCount = 0;

   g_btnSmartCloseEnabled = Inp_SmartEnabled;
   g_btnBuyEnabled        = true;
   g_btnSellEnabled       = true;

   // Toplam islem sayisini hesapla (tarihten)
   ToplamIslemSayisiGuncelle();

   // Panel olustur
   PanelOlustur();

   Print("=====================================================");
   PrintFormat("TickTrader Pro v8.0 Universal baslatildi");
   PrintFormat("Sembol: %s | Magic: %llu | Filling: %s", _Symbol, Inp_Magic, fillStr);
   PrintFormat("Islem Siniri: %d | Konsolidasyon Filtresi: %s",
               Inp_MaxTotalTrades, Inp_ConsolidationFilter ? "AKTIF" : "PASIF");
   Print("=====================================================");

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                    |
//+------------------------------------------------------------------+
void OnDeinit(const int r)
{
   IndicatorRelease(h_maF);  IndicatorRelease(h_maS);
   IndicatorRelease(h_rsi);  IndicatorRelease(h_atr);
   IndicatorRelease(h_cci);  IndicatorRelease(h_bb);
   IndicatorRelease(h_macd); IndicatorRelease(h_stoch);
   IndicatorRelease(h_consoATR);

   PanelSil();
   Comment("");
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   double ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double mid = (ask+bid)/2.0;

   PozisyonTara();
   HesapTara();
   EmirTara();

   // Islem siniri kontrol
   if(g_totalTradeCount >= Inp_MaxTotalTrades)
   {
      PanelGuncelle(mid);
      return;
   }

   if(DrawdownKontrol()) { PanelGuncelle(mid); return; }
   if(KarZararKontrol()) { PanelGuncelle(mid); return; }

   // SmartClose tetikleme ve calistirma
   if(g_btnSmartCloseEnabled)
   {
      SmartCloseTetikKontrol();

      if(g_smartActive && g_accTotal >= (Inp_SmartMinGroup + 1))
      {
         datetime now = TimeCurrent();
         if(now - g_lastSmartCheck >= Inp_SmartCheckSec)
         {
            SmartCloseEvrensel();
            g_lastSmartCheck = now;
         }
      }
   }

   // Konsolidasyon kontrol
   KonsolidasyonKontrol();

   bool aralikAsimi = AralikKontrol();
   UzakEmirleriSil(mid);
   GerideBirakmaKontrol(mid);

   TahminHesapla(mid);
   SkorYonBelirle();

   // Buton durumuna gore yon kilitle
   if(!g_btnBuyEnabled)  g_kafes_buy_aktif = false;
   if(!g_btnSellEnabled) g_kafes_sell_aktif = false;

   if(!aralikAsimi && g_consoOK)
      KafesYonet(ask, bid, mid);

   if(Inp_RecoveryEnabled && g_consoOK)
      KurtarmaYonet(ask, bid);

   PanelGuncelle(mid);
}

//+------------------------------------------------------------------+
//| Chart event handler — buton tiklama                               |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return;

   // SELL KAPAT butonu
   if(sparam == PREFIX+"BTN_CLOSE_SELL")
   {
      GrupKapat(POSITION_TYPE_SELL);
      GrupEmirSil(ORDER_TYPE_SELL_LIMIT);
      GrupEmirSil(ORDER_TYPE_SELL_STOP);
      Print(">> BUTON: Tum SELL pozisyonlari kapatildi");
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   // BUY KAPAT butonu
   else if(sparam == PREFIX+"BTN_CLOSE_BUY")
   {
      GrupKapat(POSITION_TYPE_BUY);
      GrupEmirSil(ORDER_TYPE_BUY_LIMIT);
      GrupEmirSil(ORDER_TYPE_BUY_STOP);
      Print(">> BUTON: Tum BUY pozisyonlari kapatildi");
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   // TUMUNU KAPAT butonu
   else if(sparam == PREFIX+"BTN_CLOSE_ALL")
   {
      TumunuKapat();
      TumEmirleriSil();
      g_anchor = 0;
      Print(">> BUTON: TUM pozisyonlar ve emirler kapatildi/silindi");
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   // BUY ACMA toggle
   else if(sparam == PREFIX+"BTN_BUY_TOGGLE")
   {
      g_btnBuyEnabled = !g_btnBuyEnabled;
      string durum = g_btnBuyEnabled ? "AKTIF" : "PASIF";
      PrintFormat(">> BUTON: BUY emirleri %s", durum);
      ButonRenkGuncelle(PREFIX+"BTN_BUY_TOGGLE", g_btnBuyEnabled,
                         Inp_PanelBuyColor, C'80,80,80');
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   // SELL ACMA toggle
   else if(sparam == PREFIX+"BTN_SELL_TOGGLE")
   {
      g_btnSellEnabled = !g_btnSellEnabled;
      string durum = g_btnSellEnabled ? "AKTIF" : "PASIF";
      PrintFormat(">> BUTON: SELL emirleri %s", durum);
      ButonRenkGuncelle(PREFIX+"BTN_SELL_TOGGLE", g_btnSellEnabled,
                         Inp_PanelSellColor, C'80,80,80');
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   // SMART CLOSE toggle
   else if(sparam == PREFIX+"BTN_SMART_TOGGLE")
   {
      g_btnSmartCloseEnabled = !g_btnSmartCloseEnabled;
      string durum = g_btnSmartCloseEnabled ? "AKTIF" : "PASIF";
      PrintFormat(">> BUTON: SmartClose %s", durum);
      ButonRenkGuncelle(PREFIX+"BTN_SMART_TOGGLE", g_btnSmartCloseEnabled,
                         C'0,140,200', C'80,80,80');
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }
   // EMIRLERI SIL butonu
   else if(sparam == PREFIX+"BTN_DEL_ORDERS")
   {
      TumEmirleriSil();
      g_anchor = 0;
      Print(">> BUTON: Tum bekleyen emirler silindi");
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   }

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Toplam islem sayisi guncelle (tarihten)                           |
//+------------------------------------------------------------------+
void ToplamIslemSayisiGuncelle()
{
   HistorySelect(0, TimeCurrent());
   int total = HistoryDealsTotal();
   int count = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      ulong magic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
      if(magic == Inp_Magic)
      {
         long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN)
            count++;
      }
   }
   g_totalTradeCount = count;
}

//+------------------------------------------------------------------+
//| Konsolidasyon kontrol — ATR bazli                                 |
//+------------------------------------------------------------------+
void KonsolidasyonKontrol()
{
   if(!Inp_ConsolidationFilter)
   {
      g_consoOK     = true;
      g_consoStatus = "FILTRE KAPALI";
      g_consoRatio  = 1.0;
      return;
   }

   double atrCurrent[];
   ArrayResize(atrCurrent, 2);
   double atrHistory[];
   ArrayResize(atrHistory, Inp_ConsoATR_LookBack);
   ArraySetAsSeries(atrCurrent, true);
   ArraySetAsSeries(atrHistory, true);

   if(CopyBuffer(h_consoATR, 0, 0, 2, atrCurrent) < 2)
   {
      g_consoOK     = true;
      g_consoStatus = "VERI YOK";
      return;
   }

   if(CopyBuffer(h_consoATR, 0, 0, Inp_ConsoATR_LookBack, atrHistory) < Inp_ConsoATR_LookBack)
   {
      g_consoOK     = true;
      g_consoStatus = "VERI YETERSIZ";
      return;
   }

   // Ortalama ATR hesapla
   double avgATR = 0;
   for(int i = 0; i < Inp_ConsoATR_LookBack; i++)
      avgATR += atrHistory[i];
   avgATR /= Inp_ConsoATR_LookBack;

   if(avgATR <= 0)
   {
      g_consoOK     = true;
      g_consoStatus = "ATR=0";
      return;
   }

   g_consoRatio = atrCurrent[0] / avgATR;

   if(g_consoRatio < Inp_ConsoATR_MinRatio)
   {
      // Cok dusuk volatilite — yatay piyasa, iyi kosul
      g_consoOK     = true;
      g_consoStatus = StringFormat("YATAY (%.2f) — IDEAL", g_consoRatio);
   }
   else if(g_consoRatio <= Inp_ConsoATR_MaxRatio)
   {
      // Normal volatilite — islem yapilabilir
      g_consoOK     = true;
      g_consoStatus = StringFormat("NORMAL (%.2f)", g_consoRatio);
   }
   else
   {
      // Cok yuksek volatilite — sert hareket, dur
      g_consoOK     = false;
      g_consoStatus = StringFormat("SERT HAREKET (%.2f) — DURDU", g_consoRatio);

      if(Inp_ConsoAutoRestart)
      {
         Print("!!! SERT HAREKET ALGILANDI — Robot yeniden baslama modu !!!");
         PrintFormat("ATR Orani: %.2f (Max: %.2f)", g_consoRatio, Inp_ConsoATR_MaxRatio);
      }
   }
}

//+------------------------------------------------------------------+
//| SmartClose tetikleme kontrol                                      |
//+------------------------------------------------------------------+
void SmartCloseTetikKontrol()
{
   if(Inp_SmartActivateDDPct <= 0 && Inp_SmartActivateLossUSD <= 0)
   {
      g_smartActive  = true;
      g_smartTrigger = "HER ZAMAN AKTIF";
      return;
   }

   bool ddTetik   = false;
   bool lossTetik = false;
   string sebep   = "";

   if(Inp_SmartActivateDDPct > 0 && g_accDDPct >= Inp_SmartActivateDDPct)
   {
      ddTetik = true;
      sebep += StringFormat("DD:%.1f%%>=%.1f%% ", g_accDDPct, Inp_SmartActivateDDPct);
   }

   if(Inp_SmartActivateLossUSD > 0 && g_accLossUSD >= Inp_SmartActivateLossUSD)
   {
      lossTetik = true;
      sebep += StringFormat("Zarar:$%.2f>=$%.2f ", g_accLossUSD, Inp_SmartActivateLossUSD);
   }

   if(ddTetik || lossTetik)
   {
      if(!g_smartActive)
      {
         Print("=== SMART CLOSE AKTIFLESTIRILDI ===");
         Print("  Sebep: ", sebep);
      }
      g_smartActive  = true;
      g_smartTrigger = sebep;
   }
   else
   {
      if(g_smartActive && g_smartCloseCount > 0)
         Print("=== SMART CLOSE DEAKTIF ===");
      g_smartActive  = false;
      g_smartTrigger = StringFormat("BEKL DD<%.1f%% Z<$%.1f",
                                    Inp_SmartActivateDDPct, Inp_SmartActivateLossUSD);
   }
}

//+------------------------------------------------------------------+
//| Skor bazli yon belirleme                                          |
//+------------------------------------------------------------------+
void SkorYonBelirle()
{
   if(g_score > Inp_ScoreBuyOnly)
   {
      g_kafes_buy_aktif  = true;
      g_kafes_sell_aktif = false;
   }
   else if(g_score < Inp_ScoreSellOnly)
   {
      g_kafes_buy_aktif  = false;
      g_kafes_sell_aktif = true;
   }
   else
   {
      g_kafes_buy_aktif  = true;
      g_kafes_sell_aktif = true;
   }
}

//+------------------------------------------------------------------+
//| Pozisyon tara — 3 bolum: Robot / Diger EA / Manuel                |
//+------------------------------------------------------------------+
void PozisyonTara()
{
   // Robot pozisyonlari sifirla
   g_posBuy=0; g_posSell=0; g_posTotal=0; g_posLoss=0;
   g_pnlBuy=0; g_pnlSell=0; g_pnlTotal=0;
   g_lotBuy=0; g_lotSell=0; g_lotTotal=0;
   g_avgBuyPx=0; g_avgSellPx=0;
   g_lowBuyPx=DBL_MAX; g_highSellPx=0;
   g_highBuyPx=0; g_lowSellPx=DBL_MAX;
   double sBL=0, sSL=0;

   // Diger EA pozisyonlari sifirla
   g_otherPosBuy=0; g_otherPosSell=0; g_otherPosTotal=0;
   g_otherPnlBuy=0; g_otherPnlSell=0; g_otherPnlTotal=0;
   g_otherLotBuy=0; g_otherLotSell=0; g_otherLotTotal=0;

   // Manuel pozisyonlar sifirla
   g_manualPosBuy=0; g_manualPosSell=0; g_manualPosTotal=0;
   g_manualPnlBuy=0; g_manualPnlSell=0; g_manualPnlTotal=0;
   g_manualLotBuy=0; g_manualLotSell=0; g_manualLotTotal=0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol) continue;

      double pnl = m_pos.Profit()+m_pos.Swap()+m_pos.Commission();
      double px  = m_pos.PriceOpen();
      double vl  = m_pos.Volume();
      ulong magic = m_pos.Magic();
      bool isBuy = (m_pos.PositionType()==POSITION_TYPE_BUY);

      if(magic == Inp_Magic)
      {
         // ---- ROBOT POZISYONLARI ----
         g_pnlTotal += pnl;
         g_posTotal++;
         g_lotTotal += vl;
         if(pnl<0) g_posLoss++;

         if(isBuy)
         {
            g_posBuy++; g_pnlBuy+=pnl; g_lotBuy+=vl;
            sBL += px*vl;
            if(px<g_lowBuyPx)  g_lowBuyPx=px;
            if(px>g_highBuyPx) g_highBuyPx=px;
         }
         else
         {
            g_posSell++; g_pnlSell+=pnl; g_lotSell+=vl;
            sSL += px*vl;
            if(px>g_highSellPx) g_highSellPx=px;
            if(px<g_lowSellPx)  g_lowSellPx=px;
         }
      }
      else if(magic == 0)
      {
         // ---- MANUEL POZISYONLAR ----
         g_manualPosTotal++;
         g_manualPnlTotal += pnl;
         if(isBuy)
         {
            g_manualPosBuy++; g_manualPnlBuy+=pnl; g_manualLotBuy+=vl;
         }
         else
         {
            g_manualPosSell++; g_manualPnlSell+=pnl; g_manualLotSell+=vl;
         }
         g_manualLotTotal += vl;
      }
      else
      {
         // ---- DIGER EA POZISYONLARI ----
         g_otherPosTotal++;
         g_otherPnlTotal += pnl;
         if(isBuy)
         {
            g_otherPosBuy++; g_otherPnlBuy+=pnl; g_otherLotBuy+=vl;
         }
         else
         {
            g_otherPosSell++; g_otherPnlSell+=pnl; g_otherLotSell+=vl;
         }
         g_otherLotTotal += vl;
      }
   }

   if(g_lotBuy>0)  g_avgBuyPx  = sBL/g_lotBuy;
   if(g_lotSell>0) g_avgSellPx = sSL/g_lotSell;
   if(g_lowBuyPx==DBL_MAX)  g_lowBuyPx=0;
   if(g_lowSellPx==DBL_MAX) g_lowSellPx=0;
}

//+------------------------------------------------------------------+
//| Tum hesap taramasi                                                |
//+------------------------------------------------------------------+
void HesapTara()
{
   g_accTotal    = 0;
   g_accLoss     = 0;
   g_accPnl      = 0;
   g_accLotTotal = 0;
   g_accLossUSD  = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;

      double pnl = m_pos.Profit()+m_pos.Swap()+m_pos.Commission();
      g_accTotal++;
      g_accPnl      += pnl;
      g_accLotTotal += m_pos.Volume();

      if(pnl < 0)
      {
         g_accLoss++;
         g_accLossUSD += MathAbs(pnl);
      }
   }

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > 0)
      g_accDDPct = ((balance - equity) / balance) * 100.0;
   else
      g_accDDPct = 0;

   if(g_accDDPct < 0) g_accDDPct = 0;
}

//+------------------------------------------------------------------+
//| Emir taramasi                                                     |
//+------------------------------------------------------------------+
void EmirTara()
{
   g_ordBL=0; g_ordBS=0; g_ordSL=0; g_ordSS=0; g_ordTotal=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!m_ord.SelectByIndex(i)) continue;
      if(m_ord.Symbol()!=_Symbol || m_ord.Magic()!=Inp_Magic) continue;
      g_ordTotal++;
      ENUM_ORDER_TYPE t = m_ord.OrderType();
      if(t==ORDER_TYPE_BUY_LIMIT)       g_ordBL++;
      else if(t==ORDER_TYPE_BUY_STOP)   g_ordBS++;
      else if(t==ORDER_TYPE_SELL_LIMIT)  g_ordSL++;
      else if(t==ORDER_TYPE_SELL_STOP)   g_ordSS++;
   }
}

//+------------------------------------------------------------------+
//| Evrensel Smart Close                                              |
//+------------------------------------------------------------------+
void SmartCloseEvrensel()
{
   int total = PositionsTotal();
   int cnt   = 0;
   SAllPos arr[];
   ArrayResize(arr, 0);

   for(int i=total-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;

      SAllPos d;
      d.ticket  = m_pos.Ticket();
      d.symbol  = m_pos.Symbol();
      d.openPx  = m_pos.PriceOpen();
      d.pnl     = m_pos.Profit()+m_pos.Swap()+m_pos.Commission();
      d.lot     = m_pos.Volume();
      d.magic   = m_pos.Magic();
      d.posType = (m_pos.PositionType()==POSITION_TYPE_BUY) ? 0 : 1;

      cnt++;
      ArrayResize(arr, cnt);
      arr[cnt-1] = d;
   }

   if(cnt < Inp_SmartMinGroup + 1)
   {
      int symSay = SembolSay(arr,cnt);
      g_smartInfo = StringFormat("Yetersiz (%d poz, %d sym)", cnt, symSay);
      return;
   }

   double minLossEsik = Inp_SmartMinLossUSD;
   double minNetEsik  = Inp_SmartMinNet;
   int    maxGrupEsik = Inp_SmartMaxGroup;

   if(Inp_SmartAggressiveMode)
   {
      if(g_accDDPct >= Inp_SmartActivateDDPct * 2.0)
      {
         minLossEsik = minLossEsik * 0.25;
         minNetEsik  = 0.01;
         maxGrupEsik = MathMin(maxGrupEsik + 3, cnt);
      }
      else if(g_accDDPct >= Inp_SmartActivateDDPct * 1.5)
      {
         minLossEsik = minLossEsik * 0.50;
         minNetEsik  = minNetEsik * 0.50;
         maxGrupEsik = MathMin(maxGrupEsik + 2, cnt);
      }
      else
      {
         minLossEsik = minLossEsik * 0.75;
         minNetEsik  = minNetEsik * 0.75;
         maxGrupEsik = MathMin(maxGrupEsik + 1, cnt);
      }
   }

   int    worstIdx = -1;
   double worstPnl = 0;

   for(int i=0; i<cnt; i++)
   {
      if(arr[i].pnl >= 0) continue;
      if(MathAbs(arr[i].pnl) < minLossEsik) continue;
      if(arr[i].pnl < worstPnl)
      {
         worstPnl = arr[i].pnl;
         worstIdx = i;
      }
   }

   if(worstIdx < 0)
   {
      g_smartInfo = StringFormat("Buyuk zarar yok (esik:$%.2f)", minLossEsik);
      return;
   }

   int    profIdx[];
   double profPnl[];
   int    profCnt = 0;

   for(int i=0; i<cnt; i++)
   {
      if(i == worstIdx) continue;
      if(arr[i].pnl <= 0) continue;
      profCnt++;
      ArrayResize(profIdx, profCnt);
      ArrayResize(profPnl, profCnt);
      profIdx[profCnt-1] = i;
      profPnl[profCnt-1] = arr[i].pnl;
   }

   if(profCnt < Inp_SmartMinGroup)
   {
      double topKar = 0;
      for(int k=0; k<profCnt; k++) topKar += profPnl[k];
      g_smartInfo = StringFormat("Karli az(%d) Z:$%.2f K:$%.2f", profCnt, worstPnl, topKar);
      return;
   }

   for(int i=0; i<profCnt-1; i++)
      for(int j=0; j<profCnt-1-i; j++)
         if(profPnl[j] < profPnl[j+1])
         {
            double tmpP = profPnl[j]; profPnl[j]=profPnl[j+1]; profPnl[j+1]=tmpP;
            int tmpI = profIdx[j]; profIdx[j]=profIdx[j+1]; profIdx[j+1]=tmpI;
         }

   int    bestGroup = 0;
   double bestNet   = -999999;
   int    maxGrp    = MathMin(maxGrupEsik, profCnt);

   for(int grpSize = Inp_SmartMinGroup; grpSize <= maxGrp; grpSize++)
   {
      double sumProfit = 0;
      for(int k=0; k<grpSize; k++)
         sumProfit += profPnl[k];
      double net = sumProfit + worstPnl;
      if(net >= minNetEsik && net > bestNet)
      {
         bestNet   = net;
         bestGroup = grpSize;
      }
   }

   if(bestGroup < Inp_SmartMinGroup)
   {
      double topKar = 0;
      int topMax = MathMin(maxGrp,profCnt);
      for(int k=0; k<topMax; k++) topKar += profPnl[k];
      g_smartInfo = StringFormat("Kar<Zarar Z:$%.2f K:$%.2f N:$%.2f",
                                 worstPnl, topKar, topKar+worstPnl);
      return;
   }

   // KAPATMA
   Print("==================================================================");
   PrintFormat("EVRENSEL SMART CLOSE #%d | Net: $%.2f", g_smartCloseCount+1, bestNet);

   // SmartClose icin CTrade ayarla — farkli semboller icin filling kontrol
   CTrade smartTrade;
   smartTrade.SetDeviationInPoints(Inp_Slippage);

   // Zarar pozisyonu kapat
   string worstSym = arr[worstIdx].symbol;
   SetTradeFillingForSymbol(smartTrade, worstSym);
   smartTrade.PositionClose(arr[worstIdx].ticket);
   PrintFormat("  [X] ZARAR #%llu %s $%.2f", arr[worstIdx].ticket, worstSym, worstPnl);

   for(int k=0; k<bestGroup; k++)
   {
      int idx = profIdx[k];
      string profSym = arr[idx].symbol;
      SetTradeFillingForSymbol(smartTrade, profSym);
      smartTrade.PositionClose(arr[idx].ticket);
      PrintFormat("  [X] KAR  #%llu %s $%.2f", arr[idx].ticket, profSym, arr[idx].pnl);
   }

   g_smartCloseCount++;
   g_smartInfo = StringFormat("KAPATTI %d+1 | Net:$%.2f | #%d",
                              bestGroup, bestNet, g_smartCloseCount);
   Print("==================================================================");
}

//+------------------------------------------------------------------+
//| Farkli sembol icin filling ayarla                                 |
//+------------------------------------------------------------------+
void SetTradeFillingForSymbol(CTrade &trade, string symbol)
{
   long fillPolicy = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((fillPolicy & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((fillPolicy & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Farkli sembol sayisini hesapla                                    |
//+------------------------------------------------------------------+
int SembolSay(SAllPos &arr[], int cnt)
{
   string symbols[];
   int symCnt = 0;
   for(int i=0; i<cnt; i++)
   {
      bool found = false;
      for(int j=0; j<symCnt; j++)
         if(symbols[j] == arr[i].symbol) { found = true; break; }
      if(!found)
      {
         symCnt++;
         ArrayResize(symbols, symCnt);
         symbols[symCnt-1] = arr[i].symbol;
      }
   }
   return symCnt;
}

//+------------------------------------------------------------------+
//| Drawdown kontrol                                                  |
//+------------------------------------------------------------------+
bool DrawdownKontrol()
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance <= 0) return true;

   double ddPct = ((balance - equity) / balance) * 100.0;
   if(ddPct >= Inp_MaxDrawdownPct)
   {
      Print("DRAWDOWN LIMITI: %",DoubleToString(ddPct,1));
      TumunuKapat();
      TumEmirleriSil();
      g_anchor = 0;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
//| Teminat kontrol                                                   |
//+------------------------------------------------------------------+
bool TeminatKontrol(double lot, ENUM_ORDER_TYPE tip)
{
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(freeMargin < Inp_MinFreeMarginUSD) return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);
   if(equity > 0 && margin > 0)
   {
      double marginLevel = (equity / margin) * 100.0;
      if(marginLevel < Inp_MinFreeMarginPct + 100.0)
         return false;
   }

   if((g_lotTotal + lot) > Inp_MaxTotalLots) return false;
   if(g_posTotal >= Inp_MaxOpenPos) return false;

   // Islem siniri kontrol
   if(g_totalTradeCount >= Inp_MaxTotalTrades) return false;

   double price = 0;
   ENUM_ORDER_TYPE calcType = ORDER_TYPE_BUY;
   if(tip==ORDER_TYPE_BUY || tip==ORDER_TYPE_BUY_LIMIT || tip==ORDER_TYPE_BUY_STOP)
      price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   else
   {
      price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
      calcType = ORDER_TYPE_SELL;
   }

   double requiredMargin = 0;
   if(!OrderCalcMargin(calcType, _Symbol, lot, price, requiredMargin))
      return false;

   if(requiredMargin > freeMargin * 0.5) return false;
   if(equity < 100.0) return false;

   return true;
}

//+------------------------------------------------------------------+
//| Guvenli lot hesaplama                                             |
//+------------------------------------------------------------------+
double GuvenliLot()
{
   double lot = Inp_LotFixed;
   double mn = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double mx = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double st = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   lot = MathMin(lot, Inp_LotMax);
   lot = MathMax(mn, lot);
   lot = MathMin(mx, lot);
   if(st > 0) lot = MathFloor(lot/st)*st;
   lot = NormalizeDouble(lot, 2);
   if(lot > Inp_LotMax) lot = Inp_LotMax;
   return lot;
}

//+------------------------------------------------------------------+
//| Kar zarar kontrol                                                 |
//+------------------------------------------------------------------+
bool KarZararKontrol()
{
   bool kapatildi = false;

   if(g_posTotal>0 && g_pnlTotal >= Inp_TP_Total)
   {
      Print("TOPLAM KAR: $",DoubleToString(g_pnlTotal,2));
      TumunuKapat(); TumEmirleriSil(); g_anchor=0;
      ToplamIslemSayisiGuncelle();
      return true;
   }

   if(g_posTotal>0 && g_pnlTotal <= Inp_SL_Total)
   {
      Print("MAKS ZARAR: $",DoubleToString(g_pnlTotal,2));
      TumunuKapat(); TumEmirleriSil(); g_anchor=0;
      ToplamIslemSayisiGuncelle();
      return true;
   }

   if(g_posBuy>1 && g_pnlBuy >= Inp_TP_BuyGroup)
   {
      GrupKapat(POSITION_TYPE_BUY);
      GrupEmirSil(ORDER_TYPE_BUY_LIMIT);
      GrupEmirSil(ORDER_TYPE_BUY_STOP);
      kapatildi = true;
   }

   if(g_posSell>1 && g_pnlSell >= Inp_TP_SellGroup)
   {
      GrupKapat(POSITION_TYPE_SELL);
      GrupEmirSil(ORDER_TYPE_SELL_LIMIT);
      GrupEmirSil(ORDER_TYPE_SELL_STOP);
      kapatildi = true;
   }

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol || m_pos.Magic()!=Inp_Magic) continue;
      double pnl = m_pos.Profit()+m_pos.Swap()+m_pos.Commission();
      if(pnl >= Inp_TP_Single)
      {
         m_trade.PositionClose(m_pos.Ticket());
         kapatildi = true;
      }
   }

   if(kapatildi) ToplamIslemSayisiGuncelle();
   return kapatildi;
}

//+------------------------------------------------------------------+
//| Tum pozisyonlari kapat                                           |
//+------------------------------------------------------------------+
void TumunuKapat()
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol || m_pos.Magic()!=Inp_Magic) continue;
      m_trade.PositionClose(m_pos.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Grup kapat                                                        |
//+------------------------------------------------------------------+
void GrupKapat(ENUM_POSITION_TYPE tip)
{
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol || m_pos.Magic()!=Inp_Magic) continue;
      if(m_pos.PositionType()==tip)
         m_trade.PositionClose(m_pos.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Tum emirleri sil                                                  |
//+------------------------------------------------------------------+
void TumEmirleriSil()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!m_ord.SelectByIndex(i)) continue;
      if(m_ord.Symbol()!=_Symbol || m_ord.Magic()!=Inp_Magic) continue;
      m_trade.OrderDelete(m_ord.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Grup emir sil                                                     |
//+------------------------------------------------------------------+
void GrupEmirSil(ENUM_ORDER_TYPE tip)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!m_ord.SelectByIndex(i)) continue;
      if(m_ord.Symbol()!=_Symbol || m_ord.Magic()!=Inp_Magic) continue;
      if(m_ord.OrderType()==tip)
         m_trade.OrderDelete(m_ord.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Aralik kontrol                                                    |
//+------------------------------------------------------------------+
bool AralikKontrol()
{
   if(g_posTotal < 2) return false;
   double minPx=DBL_MAX, maxPx=0;
   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol || m_pos.Magic()!=Inp_Magic) continue;
      double px = m_pos.PriceOpen();
      if(px<minPx) minPx=px;
      if(px>maxPx) maxPx=px;
   }
   if(minPx==DBL_MAX) return false;
   return ((maxPx-minPx)/_Point > Inp_MaxRange);
}

//+------------------------------------------------------------------+
//| Uzak emirleri sil                                                 |
//+------------------------------------------------------------------+
void UzakEmirleriSil(double mid)
{
   double maxDist = Inp_MaxDistance * _Point;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!m_ord.SelectByIndex(i)) continue;
      if(m_ord.Symbol()!=_Symbol || m_ord.Magic()!=Inp_Magic) continue;
      if(MathAbs(m_ord.PriceOpen()-mid) > maxDist)
         m_trade.OrderDelete(m_ord.Ticket());
   }
}

//+------------------------------------------------------------------+
//| Geride birakma kontrol                                            |
//+------------------------------------------------------------------+
void GerideBirakmaKontrol(double mid)
{
   double maxTrail = Inp_MaxDistance * _Point;
   long stopLvl = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double spreadDist = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point*2.0;
   double minDist = MathMax((double)stopLvl*_Point, spreadDist);
   double gridDist = Inp_GridStep * _Point;
   double lot = GuvenliLot();

   if(g_posBuy>0 && g_lowBuyPx>0 && (mid-g_lowBuyPx)>maxTrail)
   {
      double rescuePx = NormalizeDouble(mid - gridDist, _Digits);
      if(rescuePx>0 && (mid-rescuePx)>=minDist && !EmirVarMi(rescuePx,ORDER_TYPE_BUY_LIMIT))
         if(TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT))
            m_trade.BuyLimit(lot,rescuePx,_Symbol,0,0,ORDER_TIME_GTC,0,"TTP_TRAIL_BL");
   }

   if(g_posSell>0 && g_highSellPx>0 && (g_highSellPx-mid)>maxTrail)
   {
      double rescuePx = NormalizeDouble(mid + gridDist, _Digits);
      if((rescuePx-mid)>=minDist && !EmirVarMi(rescuePx,ORDER_TYPE_SELL_LIMIT))
         if(TeminatKontrol(lot,ORDER_TYPE_SELL_LIMIT))
            m_trade.SellLimit(lot,rescuePx,_Symbol,0,0,ORDER_TIME_GTC,0,"TTP_TRAIL_SL");
   }
}

//+------------------------------------------------------------------+
//| Tahmin hesaplama                                                  |
//+------------------------------------------------------------------+
void TahminHesapla(double mid)
{
   double maF[],maS[],rsi[],atr[],cci[];
   double bbUp[],bbMid[],bbLo[];
   double macdM[],macdS[];
   double stK[],stD[];

   ArrayResize(maF,5); ArrayResize(maS,5); ArrayResize(rsi,5);
   ArrayResize(atr,3); ArrayResize(cci,5);
   ArrayResize(bbUp,3); ArrayResize(bbMid,3); ArrayResize(bbLo,3);
   ArrayResize(macdM,5); ArrayResize(macdS,5);
   ArrayResize(stK,5); ArrayResize(stD,5);

   ArraySetAsSeries(maF,true);  ArraySetAsSeries(maS,true);
   ArraySetAsSeries(rsi,true);  ArraySetAsSeries(atr,true);
   ArraySetAsSeries(cci,true);
   ArraySetAsSeries(bbUp,true); ArraySetAsSeries(bbMid,true); ArraySetAsSeries(bbLo,true);
   ArraySetAsSeries(macdM,true);ArraySetAsSeries(macdS,true);
   ArraySetAsSeries(stK,true);  ArraySetAsSeries(stD,true);

   bool ok = true;
   if(CopyBuffer(h_maF,0,0,5,maF)<5)    ok=false;
   if(CopyBuffer(h_maS,0,0,5,maS)<5)    ok=false;
   if(CopyBuffer(h_rsi,0,0,5,rsi)<5)    ok=false;
   if(CopyBuffer(h_atr,0,0,3,atr)<3)    ok=false;
   if(CopyBuffer(h_cci,0,0,5,cci)<5)    ok=false;
   if(CopyBuffer(h_bb,1,0,3,bbUp)<3)    ok=false;
   if(CopyBuffer(h_bb,2,0,3,bbLo)<3)    ok=false;
   if(CopyBuffer(h_bb,0,0,3,bbMid)<3)   ok=false;
   if(CopyBuffer(h_macd,0,0,5,macdM)<5) ok=false;
   if(CopyBuffer(h_macd,1,0,5,macdS)<5) ok=false;
   if(CopyBuffer(h_stoch,0,0,5,stK)<5)  ok=false;
   if(CopyBuffer(h_stoch,1,0,5,stD)<5)  ok=false;

   if(!ok){ g_dir=0; g_score=0; g_target=mid; g_reason="VeriYok"; return; }

   MqlRates R[];
   ArraySetAsSeries(R,true);
   if(CopyRates(_Symbol,Inp_TF,0,10,R)<10)
   { g_dir=0; g_score=0; g_target=mid; g_reason="BarYok"; return; }

   g_score=0; g_reason="";

   // 1) EMA
   if(maF[0]>maS[0]){ g_score+=18; g_reason+="EMA^ "; }
   else              { g_score-=18; g_reason+="EMAv "; }

   // 2) EMA ivme
   double sF=(maF[0]-maF[3])/_Point;
   double sS=(maS[0]-maS[3])/_Point;
   if(sF>0 && sF>sS)     { g_score+=7; g_reason+="Iv^ "; }
   else if(sF<0 && sF<sS){ g_score-=7; g_reason+="Ivv "; }

   // 3) RSI
   if(rsi[0]<22)      { g_score+=22; g_reason+="RSI_OS "; }
   else if(rsi[0]<38) { g_score+=10; }
   else if(rsi[0]>78) { g_score-=22; g_reason+="RSI_OB "; }
   else if(rsi[0]>62) { g_score-=10; }
   if(rsi[0]>rsi[1]) g_score+=3; else g_score-=3;

   // 4) CCI
   if(cci[0]<-160)     { g_score+=16; g_reason+="CCI^ "; }
   else if(cci[0]<-60) { g_score+=6; }
   else if(cci[0]>160) { g_score-=16; g_reason+="CCIv "; }
   else if(cci[0]>60)  { g_score-=6; }

   // 5) Bollinger
   if(mid<=bbLo[0])      { g_score+=16; g_reason+="BB_Lo "; }
   else if(mid>=bbUp[0]) { g_score-=16; g_reason+="BB_Hi "; }
   else if(mid<bbMid[0]) { g_score+=4; }
   else                  { g_score-=4; }

   // 6) MACD
   if(macdM[0]>macdS[0] && macdM[1]<=macdS[1]){ g_score+=14; g_reason+="MACD^ "; }
   if(macdM[0]<macdS[0] && macdM[1]>=macdS[1]){ g_score-=14; g_reason+="MACDv "; }
   if(macdM[0]>0 && macdM[0]>macdS[0]) g_score+=4;
   if(macdM[0]<0 && macdM[0]<macdS[0]) g_score-=4;

   // 7) Stochastic
   if(stK[0]<20 && stK[0]>stD[0]){ g_score+=12; g_reason+="ST^ "; }
   if(stK[0]>80 && stK[0]<stD[0]){ g_score-=12; g_reason+="STv "; }

   // 8) Mum analizi
   double body  = R[1].close-R[1].open;
   double range = R[1].high-R[1].low;
   double upW   = R[1].high-MathMax(R[1].open,R[1].close);
   double dnW   = MathMin(R[1].open,R[1].close)-R[1].low;
   double pBody = R[2].close-R[2].open;

   if(dnW>MathAbs(body)*2.0 && body>0 && range>atr[0]*0.25)
   { g_score+=11; g_reason+="Hammer "; }
   if(upW>MathAbs(body)*2.0 && body<0 && range>atr[0]*0.25)
   { g_score-=11; g_reason+="ShStar "; }
   if(body>0 && pBody<0 && MathAbs(body)>MathAbs(pBody)*1.15)
   { g_score+=10; g_reason+="BullEng "; }
   if(body<0 && pBody>0 && MathAbs(body)>MathAbs(pBody)*1.15)
   { g_score-=10; g_reason+="BearEng "; }

   // 9) Momentum
   double mom=(R[0].close-R[5].close)/_Point;
   if(mom>40)      { g_score+=8; g_reason+="Mom^ "; }
   else if(mom<-40){ g_score-=8; g_reason+="Momv "; }

   // 10) Kurtarma agirligi
   if(g_posBuy>0 && g_pnlBuy<-Inp_RecoveryMinLoss && g_score>0)
   { g_score+=10; g_reason+="RecB "; }
   if(g_posSell>0 && g_pnlSell<-Inp_RecoveryMinLoss && g_score<0)
   { g_score-=10; g_reason+="RecS "; }

   g_score = MathMax(-100.0, MathMin(100.0, g_score));

   if(g_score >= Inp_MinScore)
   { g_dir=1; g_target=mid+atr[0]*0.6; }
   else if(g_score <= -Inp_MinScore)
   { g_dir=-1; g_target=mid-atr[0]*0.6; }
   else
   { g_dir=0; g_target=mid; }
}

//+------------------------------------------------------------------+
//| Kafes yonetimi — renkli emirler                                   |
//+------------------------------------------------------------------+
void KafesYonet(double ask, double bid, double mid)
{
   double refreshDist = Inp_RefreshDist * _Point;
   if(g_anchor!=0 && MathAbs(mid-g_anchor) < refreshDist)
      return;

   if(g_posTotal >= Inp_MaxOpenPos) return;
   if(g_lotTotal >= Inp_MaxTotalLots) return;
   if(g_totalTradeCount >= Inp_MaxTotalTrades) return;

   TumEmirleriSil();

   long stopLvl = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double spreadDist = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point*2.0;
   double minDist = MathMax((double)stopLvl*_Point, spreadDist);
   double gridDist = Inp_GridStep * _Point;
   if(gridDist < minDist) gridDist = minDist + _Point;

   double lot = GuvenliLot();
   if(!TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT))
   { g_anchor=mid; return; }

   // BUY LIMIT — mavi
   if(g_kafes_buy_aktif && g_btnBuyEnabled)
   {
      for(int lv=1; lv<=Inp_BuyLimitLevels; lv++)
      {
         double px = NormalizeDouble(ask - gridDist*lv, _Digits);
         if(px<=0 || ask-px<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT)) break;
         m_trade.BuyLimit(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                          StringFormat("TTP_BL%d",lv));
         // Renk ayarla
         EmirRenkAyarla(ORDER_TYPE_BUY_LIMIT, px, Inp_ClrBuyLimit);
      }
   }

   // BUY STOP — yesil
   if(g_kafes_buy_aktif && g_btnBuyEnabled)
   {
      for(int lv=1; lv<=Inp_BuyStopLevels; lv++)
      {
         double px = NormalizeDouble(ask + gridDist*lv, _Digits);
         if(px-ask<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_BUY_STOP)) break;
         m_trade.BuyStop(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                         StringFormat("TTP_BS%d",lv));
         EmirRenkAyarla(ORDER_TYPE_BUY_STOP, px, Inp_ClrBuyStop);
      }
   }

   // SELL LIMIT — turuncu
   if(g_kafes_sell_aktif && g_btnSellEnabled)
   {
      for(int lv=1; lv<=Inp_SellLimitLevels; lv++)
      {
         double px = NormalizeDouble(bid + gridDist*lv, _Digits);
         if(px-bid<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_SELL_LIMIT)) break;
         m_trade.SellLimit(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                           StringFormat("TTP_SL%d",lv));
         EmirRenkAyarla(ORDER_TYPE_SELL_LIMIT, px, Inp_ClrSellLimit);
      }
   }

   // SELL STOP — mor
   if(g_kafes_sell_aktif && g_btnSellEnabled)
   {
      for(int lv=1; lv<=Inp_SellStopLevels; lv++)
      {
         double px = NormalizeDouble(bid - gridDist*lv, _Digits);
         if(px<=0 || bid-px<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_SELL_STOP)) break;
         m_trade.SellStop(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                          StringFormat("TTP_SS%d",lv));
         EmirRenkAyarla(ORDER_TYPE_SELL_STOP, px, Inp_ClrSellStop);
      }
   }

   g_anchor = mid;
}

//+------------------------------------------------------------------+
//| Emir renk ayarla (chart uzerinde gorsel)                          |
//+------------------------------------------------------------------+
void EmirRenkAyarla(ENUM_ORDER_TYPE tip, double fiyat, color clr)
{
   string objName = "";
   double tol = Inp_GridStep * _Point * 0.3;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!m_ord.SelectByIndex(i)) continue;
      if(m_ord.Symbol()!=_Symbol || m_ord.Magic()!=Inp_Magic) continue;
      if(m_ord.OrderType()!=tip) continue;
      if(MathAbs(m_ord.PriceOpen()-fiyat) < tol)
      {
         // Chart objesi olarak isaretle
         ulong ticket = m_ord.Ticket();
         string name = StringFormat(PREFIX+"ORD_%llu", ticket);
         if(ObjectFind(0, name) < 0)
         {
            ObjectCreate(0, name, OBJ_ARROW, 0, TimeCurrent(), fiyat);
            ObjectSetInteger(0, name, OBJPROP_ARROWCODE, 159);
            ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
            ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
            ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         }
         break;
      }
   }
}

//+------------------------------------------------------------------+
//| Kurtarma yonetimi                                                 |
//+------------------------------------------------------------------+
void KurtarmaYonet(double ask, double bid)
{
   long stopLvl = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double spreadDist = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point*2.0;
   double minDist = MathMax((double)stopLvl*_Point, spreadDist);
   double gridDist = Inp_GridStep * _Point;
   double recShift = Inp_RecoveryGridShift * _Point;
   double recGrid  = MathMax(gridDist - recShift, minDist + _Point);
   double lot = GuvenliLot();

   if(g_posBuy>0 && g_pnlBuy < -Inp_RecoveryMinLoss && g_lowBuyPx>0)
   {
      double recPx = NormalizeDouble(g_lowBuyPx - recGrid, _Digits);
      if(recPx>0 && (ask-recPx)>=minDist && !EmirVarMi(recPx,ORDER_TYPE_BUY_LIMIT))
         if(TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT))
            m_trade.BuyLimit(lot,recPx,_Symbol,0,0,ORDER_TIME_GTC,0,"TTP_REC_BL");

      double closeBL = NormalizeDouble(ask - recGrid*0.5, _Digits);
      if(closeBL>0 && (ask-closeBL)>=minDist && !EmirVarMi(closeBL,ORDER_TYPE_BUY_LIMIT))
         if(TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT))
            m_trade.BuyLimit(lot,closeBL,_Symbol,0,0,ORDER_TIME_GTC,0,"TTP_RECX_BL");
   }

   if(g_posSell>0 && g_pnlSell < -Inp_RecoveryMinLoss && g_highSellPx>0)
   {
      double recPx = NormalizeDouble(g_highSellPx + recGrid, _Digits);
      if((recPx-bid)>=minDist && !EmirVarMi(recPx,ORDER_TYPE_SELL_LIMIT))
         if(TeminatKontrol(lot,ORDER_TYPE_SELL_LIMIT))
            m_trade.SellLimit(lot,recPx,_Symbol,0,0,ORDER_TIME_GTC,0,"TTP_REC_SL");

      double closeSL = NormalizeDouble(bid + recGrid*0.5, _Digits);
      if((closeSL-bid)>=minDist && !EmirVarMi(closeSL,ORDER_TYPE_SELL_LIMIT))
         if(TeminatKontrol(lot,ORDER_TYPE_SELL_LIMIT))
            m_trade.SellLimit(lot,closeSL,_Symbol,0,0,ORDER_TIME_GTC,0,"TTP_RECX_SL");
   }
}

//+------------------------------------------------------------------+
//| Emir var mi kontrol                                               |
//+------------------------------------------------------------------+
bool EmirVarMi(double fiyat, ENUM_ORDER_TYPE tip)
{
   double tol = Inp_GridStep * _Point * 0.3;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!m_ord.SelectByIndex(i)) continue;
      if(m_ord.Symbol()!=_Symbol || m_ord.Magic()!=Inp_Magic) continue;
      if(m_ord.OrderType()!=tip) continue;
      if(MathAbs(m_ord.PriceOpen()-fiyat) < tol)
         return true;
   }
   return false;
}

//======================================================================
//                    GRAFIK PANEL SISTEMI
//======================================================================

//+------------------------------------------------------------------+
//| Buton olustur                                                     |
//+------------------------------------------------------------------+
void ButonOlustur(string name, int x, int y, int w, int h,
                  string text, color bgClr, color txtClr)
{
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, txtClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, Inp_PanelBorderColor);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Buton renk guncelle                                               |
//+------------------------------------------------------------------+
void ButonRenkGuncelle(string name, bool aktif, color aktifClr, color pasifClr)
{
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, aktif ? aktifClr : pasifClr);
   string txt = ObjectGetString(0, name, OBJPROP_TEXT);

   // Toggle butonlari icin metin guncelle
   if(StringFind(name, "BUY_TOGGLE") >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, aktif ? "BUY:ON" : "BUY:OFF");
   else if(StringFind(name, "SELL_TOGGLE") >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, aktif ? "SELL:ON" : "SELL:OFF");
   else if(StringFind(name, "SMART_TOGGLE") >= 0)
      ObjectSetString(0, name, OBJPROP_TEXT, aktif ? "SC:ON" : "SC:OFF");
}

//+------------------------------------------------------------------+
//| Label olustur                                                     |
//+------------------------------------------------------------------+
void LabelOlustur(string name, int x, int y, string text, color clr, int fontSize=0)
{
   if(fontSize == 0) fontSize = Inp_PanelFontSize;
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Arka plan kutusu olustur                                          |
//+------------------------------------------------------------------+
void KutuOlustur(string name, int x, int y, int w, int h, color bgClr, color borderClr)
{
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, borderClr);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
}

//+------------------------------------------------------------------+
//| Panel olustur                                                     |
//+------------------------------------------------------------------+
void PanelOlustur()
{
   int px = Inp_PanelX;
   int py = Inp_PanelY;

   // Ana arka plan
   KutuOlustur(PREFIX+"BG", px, py, PANEL_W, PANEL_H,
               Inp_PanelBgColor, Inp_PanelBorderColor);

   // Baslik
   LabelOlustur(PREFIX+"TITLE", px+10, py+5,
                "TICK TRADER PRO v8.0", C'100,200,255', 10);
   LabelOlustur(PREFIX+"SUBTITLE", px+10, py+20,
                "Universal | " + _Symbol, Inp_PanelTextColor, 7);

   // Butonlar — usten 38px
   int btnY = py + 36;
   int btnX = px + 5;
   int gap  = 3;

   ButonOlustur(PREFIX+"BTN_CLOSE_BUY", btnX, btnY, BTN_W-10, BTN_H,
                "KAPAT BUY", C'0,100,60', clrWhite);
   btnX += BTN_W - 10 + gap;

   ButonOlustur(PREFIX+"BTN_CLOSE_SELL", btnX, btnY, BTN_W-10, BTN_H,
                "KAPAT SELL", C'140,30,30', clrWhite);
   btnX += BTN_W - 10 + gap;

   ButonOlustur(PREFIX+"BTN_CLOSE_ALL", btnX, btnY, BTN_W-15, BTN_H,
                "TUM KAPAT", C'160,40,40', clrWhite);
   btnX += BTN_W - 15 + gap;

   ButonOlustur(PREFIX+"BTN_DEL_ORDERS", btnX, btnY, BTN_W-15, BTN_H,
                "EMIR SIL", C'100,80,20', clrWhite);
   btnX += BTN_W - 15 + gap;

   ButonOlustur(PREFIX+"BTN_BUY_TOGGLE", btnX, btnY, 55, BTN_H,
                "BUY:ON", Inp_PanelBuyColor, clrWhite);

   // Ikinci satir butonlar
   btnY += BTN_H + 2;
   btnX = px + 5;

   ButonOlustur(PREFIX+"BTN_SELL_TOGGLE", btnX, btnY, 58, BTN_H,
                "SELL:ON", Inp_PanelSellColor, clrWhite);
   btnX += 61;

   ButonOlustur(PREFIX+"BTN_SMART_TOGGLE", btnX, btnY, 58, BTN_H,
                g_btnSmartCloseEnabled ? "SC:ON" : "SC:OFF",
                g_btnSmartCloseEnabled ? C'0,140,200' : C'80,80,80', clrWhite);

   // Bolum baslik label'lari olustur (sonra guncellenecek)
   int startY = btnY + BTN_H + 8;

   // Hesap bolumu
   KutuOlustur(PREFIX+"SEC_ACC", px+3, startY, PANEL_W-6, 80,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_ACC_T", px+8, startY+2, "HESAP", C'130,180,255', 8);

   for(int i=0; i<5; i++)
      LabelOlustur(PREFIX+"ACC_L"+IntegerToString(i), px+8, startY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   // Tahmin bolumu
   int secTahY = startY + 84;
   KutuOlustur(PREFIX+"SEC_TAH", px+3, secTahY, PANEL_W-6, 66,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_TAH_T", px+8, secTahY+2, "TAHMIN & SKOR", C'130,180,255', 8);

   for(int i=0; i<4; i++)
      LabelOlustur(PREFIX+"TAH_L"+IntegerToString(i), px+8, secTahY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   // Robot pozisyonlari bolumu
   int secRobY = secTahY + 70;
   KutuOlustur(PREFIX+"SEC_ROB", px+3, secRobY, PANEL_W-6, 94,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_ROB_T", px+8, secRobY+2,
                "ROBOT POZISYONLARI (Magic:"+IntegerToString(Inp_Magic)+")",
                C'130,180,255', 8);

   for(int i=0; i<6; i++)
      LabelOlustur(PREFIX+"ROB_L"+IntegerToString(i), px+8, secRobY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   // Diger EA pozisyonlari
   int secOthY = secRobY + 98;
   KutuOlustur(PREFIX+"SEC_OTH", px+3, secOthY, PANEL_W-6, 66,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_OTH_T", px+8, secOthY+2,
                "DIGER EA POZISYONLARI", C'200,180,100', 8);

   for(int i=0; i<4; i++)
      LabelOlustur(PREFIX+"OTH_L"+IntegerToString(i), px+8, secOthY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   // Manuel pozisyonlar
   int secManY = secOthY + 70;
   KutuOlustur(PREFIX+"SEC_MAN", px+3, secManY, PANEL_W-6, 66,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_MAN_T", px+8, secManY+2,
                "MANUEL POZISYONLAR", C'200,150,100', 8);

   for(int i=0; i<4; i++)
      LabelOlustur(PREFIX+"MAN_L"+IntegerToString(i), px+8, secManY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   // SmartClose bolumu
   int secSmtY = secManY + 70;
   KutuOlustur(PREFIX+"SEC_SMT", px+3, secSmtY, PANEL_W-6, 80,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_SMT_T", px+8, secSmtY+2, "SMART CLOSE", C'100,200,220', 8);

   for(int i=0; i<5; i++)
      LabelOlustur(PREFIX+"SMT_L"+IntegerToString(i), px+8, secSmtY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   // Emirler ve konsolidasyon
   int secEmrY = secSmtY + 84;
   KutuOlustur(PREFIX+"SEC_EMR", px+3, secEmrY, PANEL_W-6, 66,
               C'25,25,38', Inp_PanelBorderColor);
   LabelOlustur(PREFIX+"SEC_EMR_T", px+8, secEmrY+2, "EMIRLER & KONSOLIDASYON", C'130,180,255', 8);

   for(int i=0; i<4; i++)
      LabelOlustur(PREFIX+"EMR_L"+IntegerToString(i), px+8, secEmrY+16+i*LINE_H,
                   "", Inp_PanelTextColor);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Panel tum objeleri sil                                            |
//+------------------------------------------------------------------+
void PanelSil()
{
   int total = ObjectsTotal(0);
   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i);
      if(StringFind(name, PREFIX) == 0)
         ObjectDelete(0, name);
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Panel guncelle — tum label'lari yaz                               |
//+------------------------------------------------------------------+
void PanelGuncelle(double mid)
{
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double freeM   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double usedM   = AccountInfoDouble(ACCOUNT_MARGIN);
   double ddPct   = (balance > 0) ? ((balance-equity)/balance)*100.0 : 0;
   if(ddPct < 0) ddPct = 0;
   double mLvl    = (usedM > 0) ? (equity/usedM)*100.0 : 0;

   // HESAP
   ObjectSetString(0, PREFIX+"ACC_L0", OBJPROP_TEXT,
      StringFormat("Bakiye: $%.2f  |  Equity: $%.2f", balance, equity));
   ObjectSetString(0, PREFIX+"ACC_L1", OBJPROP_TEXT,
      StringFormat("Serbest: $%.2f  |  Kullanilan: $%.2f", freeM, usedM));
   ObjectSetString(0, PREFIX+"ACC_L2", OBJPROP_TEXT,
      StringFormat("Margin Lv: %.1f%%  |  DD: %.1f%% (max %.0f%%)", mLvl, ddPct, Inp_MaxDrawdownPct));
   ObjectSetInteger(0, PREFIX+"ACC_L2", OBJPROP_COLOR,
      ddPct > Inp_MaxDrawdownPct * 0.7 ? Inp_PanelLossColor : Inp_PanelTextColor);
   ObjectSetString(0, PREFIX+"ACC_L3", OBJPROP_TEXT,
      StringFormat("Islem: %d / %d  |  Filling: %s",
                   g_totalTradeCount, Inp_MaxTotalTrades,
                   (DetectFilling()==ORDER_FILLING_FOK) ? "FOK" :
                   (DetectFilling()==ORDER_FILLING_IOC) ? "IOC" : "RETURN"));
   ObjectSetString(0, PREFIX+"ACC_L4", OBJPROP_TEXT,
      StringFormat("Hesap PnL: $%.2f  |  Toplam Poz: %d", g_accPnl, g_accTotal));
   ObjectSetInteger(0, PREFIX+"ACC_L4", OBJPROP_COLOR,
      g_accPnl >= 0 ? Inp_PanelProfitColor : Inp_PanelLossColor);

   // TAHMIN & SKOR
   string skorYon = (g_kafes_buy_aktif && g_kafes_sell_aktif) ? "CIFT YON" :
                     g_kafes_buy_aktif ? "SADECE BUY" : "SADECE SELL";
   string tahminYon = (g_dir>0) ? "YUKARI" : (g_dir<0) ? "ASAGI" : "NOTR";
   color  tahminClr = (g_dir>0) ? Inp_PanelBuyColor : (g_dir<0) ? Inp_PanelSellColor : Inp_PanelTextColor;

   ObjectSetString(0, PREFIX+"TAH_L0", OBJPROP_TEXT,
      StringFormat("Skor: %.0f  |  Yon: %s  |  Kafes: %s", g_score, tahminYon, skorYon));
   ObjectSetInteger(0, PREFIX+"TAH_L0", OBJPROP_COLOR, tahminClr);
   ObjectSetString(0, PREFIX+"TAH_L1", OBJPROP_TEXT,
      StringFormat("Hedef: %s", DoubleToString(g_target,_Digits)));
   ObjectSetString(0, PREFIX+"TAH_L2", OBJPROP_TEXT,
      StringFormat("Gerekce: %s", g_reason));
   ObjectSetString(0, PREFIX+"TAH_L3", OBJPROP_TEXT,
      StringFormat("Sinir: <%.0f SELL | >+%.0f BUY", Inp_ScoreSellOnly, Inp_ScoreBuyOnly));

   // ROBOT POZISYONLARI
   double rangeP = 0;
   if(g_posTotal>=2)
   {
      double minP=DBL_MAX, maxP=0;
      for(int i=PositionsTotal()-1; i>=0; i--)
      {
         if(!m_pos.SelectByIndex(i)) continue;
         if(m_pos.Symbol()!=_Symbol || m_pos.Magic()!=Inp_Magic) continue;
         double px=m_pos.PriceOpen();
         if(px<minP) minP=px;
         if(px>maxP) maxP=px;
      }
      if(minP<DBL_MAX) rangeP=(maxP-minP)/_Point;
   }

   ObjectSetString(0, PREFIX+"ROB_L0", OBJPROP_TEXT,
      StringFormat("Toplam: %d/%d  |  Lot: %.2f/%.2f  |  Aralik: %.0f pt",
                   g_posTotal, Inp_MaxOpenPos, g_lotTotal, Inp_MaxTotalLots, rangeP));
   ObjectSetString(0, PREFIX+"ROB_L1", OBJPROP_TEXT,
      StringFormat("BUY : %d poz  Lot:%.2f  PnL:$%.2f", g_posBuy, g_lotBuy, g_pnlBuy));
   ObjectSetInteger(0, PREFIX+"ROB_L1", OBJPROP_COLOR,
      g_pnlBuy >= 0 ? Inp_PanelBuyColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"ROB_L2", OBJPROP_TEXT,
      StringFormat("SELL: %d poz  Lot:%.2f  PnL:$%.2f", g_posSell, g_lotSell, g_pnlSell));
   ObjectSetInteger(0, PREFIX+"ROB_L2", OBJPROP_COLOR,
      g_pnlSell >= 0 ? Inp_PanelSellColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"ROB_L3", OBJPROP_TEXT,
      StringFormat("Robot PnL: $%.2f  |  Zararda: %d", g_pnlTotal, g_posLoss));
   ObjectSetInteger(0, PREFIX+"ROB_L3", OBJPROP_COLOR,
      g_pnlTotal >= 0 ? Inp_PanelProfitColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"ROB_L4", OBJPROP_TEXT,
      StringFormat("BUY Fark: $%.2f  |  SELL Fark: $%.2f",
                   g_pnlBuy, g_pnlSell));
   ObjectSetString(0, PREFIX+"ROB_L5", OBJPROP_TEXT,
      StringFormat("TP: Tek:$%.2f BG:$%.1f SG:$%.1f T:$%.1f Z:$%.1f",
                   Inp_TP_Single, Inp_TP_BuyGroup, Inp_TP_SellGroup, Inp_TP_Total, Inp_SL_Total));

   // DIGER EA POZISYONLARI
   ObjectSetString(0, PREFIX+"OTH_L0", OBJPROP_TEXT,
      StringFormat("Toplam: %d  |  Lot: %.2f", g_otherPosTotal, g_otherLotTotal));
   ObjectSetString(0, PREFIX+"OTH_L1", OBJPROP_TEXT,
      StringFormat("BUY : %d poz  Lot:%.2f  PnL:$%.2f", g_otherPosBuy, g_otherLotBuy, g_otherPnlBuy));
   ObjectSetInteger(0, PREFIX+"OTH_L1", OBJPROP_COLOR,
      g_otherPnlBuy >= 0 ? Inp_PanelBuyColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"OTH_L2", OBJPROP_TEXT,
      StringFormat("SELL: %d poz  Lot:%.2f  PnL:$%.2f", g_otherPosSell, g_otherLotSell, g_otherPnlSell));
   ObjectSetInteger(0, PREFIX+"OTH_L2", OBJPROP_COLOR,
      g_otherPnlSell >= 0 ? Inp_PanelSellColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"OTH_L3", OBJPROP_TEXT,
      StringFormat("Diger EA PnL: $%.2f", g_otherPnlTotal));
   ObjectSetInteger(0, PREFIX+"OTH_L3", OBJPROP_COLOR,
      g_otherPnlTotal >= 0 ? Inp_PanelProfitColor : Inp_PanelLossColor);

   // MANUEL POZISYONLAR
   ObjectSetString(0, PREFIX+"MAN_L0", OBJPROP_TEXT,
      StringFormat("Toplam: %d  |  Lot: %.2f", g_manualPosTotal, g_manualLotTotal));
   ObjectSetString(0, PREFIX+"MAN_L1", OBJPROP_TEXT,
      StringFormat("BUY : %d poz  Lot:%.2f  PnL:$%.2f", g_manualPosBuy, g_manualLotBuy, g_manualPnlBuy));
   ObjectSetInteger(0, PREFIX+"MAN_L1", OBJPROP_COLOR,
      g_manualPnlBuy >= 0 ? Inp_PanelBuyColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"MAN_L2", OBJPROP_TEXT,
      StringFormat("SELL: %d poz  Lot:%.2f  PnL:$%.2f", g_manualPosSell, g_manualLotSell, g_manualPnlSell));
   ObjectSetInteger(0, PREFIX+"MAN_L2", OBJPROP_COLOR,
      g_manualPnlSell >= 0 ? Inp_PanelSellColor : Inp_PanelLossColor);
   ObjectSetString(0, PREFIX+"MAN_L3", OBJPROP_TEXT,
      StringFormat("Manuel PnL: $%.2f", g_manualPnlTotal));
   ObjectSetInteger(0, PREFIX+"MAN_L3", OBJPROP_COLOR,
      g_manualPnlTotal >= 0 ? Inp_PanelProfitColor : Inp_PanelLossColor);

   // SMART CLOSE
   string smartDurum = !g_btnSmartCloseEnabled ? "DEVRE DISI (Buton)" :
                        g_smartActive ? "AKTIF" : "BEKLENIYOR";
   color  smartClr   = g_smartActive ? C'0,220,180' :
                        !g_btnSmartCloseEnabled ? C'120,120,120' : Inp_PanelTextColor;

   ObjectSetString(0, PREFIX+"SMT_L0", OBJPROP_TEXT,
      StringFormat("Durum: %s  |  Agresif: %s", smartDurum,
                   Inp_SmartAggressiveMode ? "ACIK" : "KAPALI"));
   ObjectSetInteger(0, PREFIX+"SMT_L0", OBJPROP_COLOR, smartClr);
   ObjectSetString(0, PREFIX+"SMT_L1", OBJPROP_TEXT,
      StringFormat("Tetik DD: %.1f%% (ayar:%.1f%%)  Zarar: $%.2f (ayar:$%.1f)",
                   g_accDDPct, Inp_SmartActivateDDPct, g_accLossUSD, Inp_SmartActivateLossUSD));
   ObjectSetString(0, PREFIX+"SMT_L2", OBJPROP_TEXT,
      StringFormat("Tetik: %s", g_smartTrigger));
   ObjectSetString(0, PREFIX+"SMT_L3", OBJPROP_TEXT,
      StringFormat("Min Kayip: $%.2f  |  Min Net: $%.2f", Inp_SmartMinLossUSD, Inp_SmartMinNet));
   ObjectSetString(0, PREFIX+"SMT_L4", OBJPROP_TEXT,
      StringFormat("Kapamalar: %d  |  %s", g_smartCloseCount, g_smartInfo));

   // EMIRLER & KONSOLIDASYON
   ObjectSetString(0, PREFIX+"EMR_L0", OBJPROP_TEXT,
      StringFormat("BL:%d  BS:%d  SL:%d  SS:%d  =  %d",
                   g_ordBL, g_ordBS, g_ordSL, g_ordSS, g_ordTotal));

   // Emir renklerini goster
   ObjectSetString(0, PREFIX+"EMR_L1", OBJPROP_TEXT,
      "Renkler: BL=Mavi BS=Yesil SL=Turuncu SS=Mor");

   ObjectSetString(0, PREFIX+"EMR_L2", OBJPROP_TEXT,
      StringFormat("Konsol: %s", g_consoStatus));
   ObjectSetInteger(0, PREFIX+"EMR_L2", OBJPROP_COLOR,
      g_consoOK ? Inp_PanelProfitColor : Inp_PanelLossColor);

   ObjectSetString(0, PREFIX+"EMR_L3", OBJPROP_TEXT,
      StringFormat("ATR Oran: %.2f  |  Filtre: %s",
                   g_consoRatio, Inp_ConsolidationFilter ? "AKTIF" : "PASIF"));

   ChartRedraw();
}

//+------------------------------------------------------------------+