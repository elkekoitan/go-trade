//+------------------------------------------------------------------+
//|                            TickTrader_Pro_v7_Universal.mq5        |
//|  500$ / 1:1000 / XAUUSD / Evrensel SmartClose / Skor Kafes        |
//+------------------------------------------------------------------+
#property copyright   "TickTrader Pro v7.0 Universal"
#property version     "7.10"
#property description "Skor bazli cift yon kafes + Evrensel SmartClose (DD/Zarar tetiklemeli)"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\OrderInfo.mqh>

//=== SMART CLOSE POZISYON YAPISI =====================================
struct SAllPos
{
   ulong  ticket;
   string symbol;
   int    posType;
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

//=== SMART CLOSE =====================================================
input group "===== SMART CLOSE (EVRENSEL) ====="
input bool     Inp_SmartEnabled         = true;      // SmartClose Aktif
input double   Inp_SmartActivateDDPct   = 10.0;      // Aktiflesme DD % (0=devre disi)
input double   Inp_SmartActivateLossUSD = 20.0;      // Aktiflesme zarar $ (0=devre disi)
input int      Inp_SmartMinGroup        = 3;          // Min karli pozisyon sayisi
input int      Inp_SmartMaxGroup        = 6;          // Maks karli pozisyon sayisi
input double   Inp_SmartMinNet          = 0.05;       // Min net kar ($) kapatma icin
input double   Inp_SmartMinLossUSD      = 1.0;        // Zarardaki poz min kayip ($)
input int      Inp_SmartCheckSec        = 5;          // Kontrol araligi (sn)
input bool     Inp_SmartAggressiveMode  = false;      // Agresif mod (DD yukseldikce daha cok kapat)

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

//=== GENEL ============================================================
input group "===== GENEL ====="
input ulong    Inp_Magic             = 240607;
input int      Inp_Slippage          = 50;

//=== GLOBAL ===========================================================
CTrade         m_trade;
CPositionInfo  m_pos;
COrderInfo     m_ord;

int   h_maF, h_maS, h_rsi, h_atr, h_cci, h_bb, h_macd, h_stoch;

int    g_posBuy, g_posSell, g_posTotal, g_posLoss;
double g_pnlBuy, g_pnlSell, g_pnlTotal;
double g_lotBuy, g_lotSell, g_lotTotal;
double g_avgBuyPx, g_avgSellPx;
double g_lowBuyPx, g_highSellPx;
double g_highBuyPx, g_lowSellPx;

int    g_accTotal, g_accLoss;
double g_accPnl, g_accLotTotal;
double g_accDDPct;           // Hesap drawdown %
double g_accLossUSD;         // Hesap toplam zarar $

int    g_ordBL, g_ordBS, g_ordSL, g_ordSS, g_ordTotal;

int    g_dir;
double g_score;
double g_target;
string g_reason;

double g_anchor;

datetime g_lastSmartCheck;
int      g_smartCloseCount;
string   g_smartInfo;
bool     g_smartActive;      // SmartClose aktif mi?
string   g_smartTrigger;     // Tetikleme sebebi

bool   g_kafes_buy_aktif;
bool   g_kafes_sell_aktif;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   m_trade.SetExpertMagicNumber(Inp_Magic);
   m_trade.SetDeviationInPoints(Inp_Slippage);
   m_trade.SetTypeFilling(ORDER_FILLING_IOC);

   h_maF   = iMA(_Symbol,Inp_TF,Inp_MA_Fast,0,MODE_EMA,PRICE_CLOSE);
   h_maS   = iMA(_Symbol,Inp_TF,Inp_MA_Slow,0,MODE_EMA,PRICE_CLOSE);
   h_rsi   = iRSI(_Symbol,Inp_TF,Inp_RSI_Period,PRICE_CLOSE);
   h_atr   = iATR(_Symbol,Inp_TF,Inp_ATR_Period);
   h_cci   = iCCI(_Symbol,Inp_TF,Inp_CCI_Period,PRICE_TYPICAL);
   h_bb    = iBands(_Symbol,Inp_TF,Inp_BB_Period,0,Inp_BB_Dev,PRICE_CLOSE);
   h_macd  = iMACD(_Symbol,Inp_TF,Inp_MACD_Fast,Inp_MACD_Slow,Inp_MACD_Signal,PRICE_CLOSE);
   h_stoch = iStochastic(_Symbol,Inp_TF,Inp_Stoch_K,Inp_Stoch_D,Inp_Stoch_Slow,MODE_SMA,STO_LOWHIGH);

   if(h_maF==INVALID_HANDLE || h_maS==INVALID_HANDLE ||
      h_rsi==INVALID_HANDLE || h_atr==INVALID_HANDLE ||
      h_cci==INVALID_HANDLE || h_bb==INVALID_HANDLE  ||
      h_macd==INVALID_HANDLE|| h_stoch==INVALID_HANDLE)
   {
      Alert("Indikator yuklenemedi!");
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

   Print("TickTrader Pro v7.1 Universal baslatildi");
   Print("SmartClose Tetikleme: DD>=",Inp_SmartActivateDDPct,
         "% VEYA Zarar>=",Inp_SmartActivateLossUSD,"$");
   Print("Agresif Mod: ", Inp_SmartAggressiveMode ? "AKTIF" : "PASIF");

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

   if(DrawdownKontrol()) return;
   if(KarZararKontrol()) return;

   // SmartClose tetikleme ve calistirma
   if(Inp_SmartEnabled)
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

   bool aralikAsimi = AralikKontrol();
   UzakEmirleriSil(mid);
   GerideBirakmaKontrol(mid);

   TahminHesapla(mid);
   SkorYonBelirle();

   if(!aralikAsimi)
      KafesYonet(ask, bid, mid);

   if(Inp_RecoveryEnabled)
      KurtarmaYonet(ask, bid);

   PanelGoster(mid);
}

//+------------------------------------------------------------------+
//| SmartClose tetikleme kontrol                                      |
//| DD % veya dolar zarar esigine gore aktiflesir                     |
//+------------------------------------------------------------------+
void SmartCloseTetikKontrol()
{
   // Her iki esik de 0 ise SmartClose her zaman aktif
   if(Inp_SmartActivateDDPct <= 0 && Inp_SmartActivateLossUSD <= 0)
   {
      g_smartActive  = true;
      g_smartTrigger = "HER ZAMAN AKTIF";
      return;
   }

   bool ddTetik   = false;
   bool lossTetik = false;
   string sebep   = "";

   // DD % kontrol
   if(Inp_SmartActivateDDPct > 0 && g_accDDPct >= Inp_SmartActivateDDPct)
   {
      ddTetik = true;
      sebep += StringFormat("DD:%.1f%%>=%.1f%% ", g_accDDPct, Inp_SmartActivateDDPct);
   }

   // Dolar zarar kontrol (mutlak deger olarak karsilastir)
   if(Inp_SmartActivateLossUSD > 0 && g_accLossUSD >= Inp_SmartActivateLossUSD)
   {
      lossTetik = true;
      sebep += StringFormat("Zarar:$%.2f>=$%.2f ", g_accLossUSD, Inp_SmartActivateLossUSD);
   }

   // En az biri tetiklendiyse aktif
   if(ddTetik || lossTetik)
   {
      if(!g_smartActive)
      {
         Print("=== SMART CLOSE AKTIFLESTIRILDI ===");
         Print("  Sebep: ", sebep);
         PrintFormat("  Hesap DD: %.1f%% | Zarar: $%.2f", g_accDDPct, g_accLossUSD);
      }
      g_smartActive  = true;
      g_smartTrigger = sebep;
   }
   else
   {
      if(g_smartActive && g_smartCloseCount > 0)
      {
         // Daha once aktifti, simdi esik altina indi
         Print("=== SMART CLOSE DEAKTIF (esik altina indi) ===");
         PrintFormat("  Hesap DD: %.1f%% | Zarar: $%.2f", g_accDDPct, g_accLossUSD);
      }
      g_smartActive  = false;
      g_smartTrigger = StringFormat("BEKLENIYOR DD<%.1f%% Zarar<$%.2f",
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
//| Robot pozisyonlari tara                                           |
//+------------------------------------------------------------------+
void PozisyonTara()
{
   g_posBuy=0; g_posSell=0; g_posTotal=0; g_posLoss=0;
   g_pnlBuy=0; g_pnlSell=0; g_pnlTotal=0;
   g_lotBuy=0; g_lotSell=0; g_lotTotal=0;
   g_avgBuyPx=0; g_avgSellPx=0;
   g_lowBuyPx=DBL_MAX; g_highSellPx=0;
   g_highBuyPx=0; g_lowSellPx=DBL_MAX;
   double sBL=0, sSL=0;

   for(int i=PositionsTotal()-1; i>=0; i--)
   {
      if(!m_pos.SelectByIndex(i)) continue;
      if(m_pos.Symbol()!=_Symbol || m_pos.Magic()!=Inp_Magic) continue;

      double pnl = m_pos.Profit()+m_pos.Swap()+m_pos.Commission();
      double px  = m_pos.PriceOpen();
      double vl  = m_pos.Volume();

      g_pnlTotal += pnl;
      g_posTotal++;
      g_lotTotal += vl;
      if(pnl<0) g_posLoss++;

      if(m_pos.PositionType()==POSITION_TYPE_BUY)
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

   if(g_lotBuy>0)  g_avgBuyPx  = sBL/g_lotBuy;
   if(g_lotSell>0) g_avgSellPx = sSL/g_lotSell;
   if(g_lowBuyPx==DBL_MAX)  g_lowBuyPx=0;
   if(g_lowSellPx==DBL_MAX) g_lowSellPx=0;
}

//+------------------------------------------------------------------+
//| Tum hesap taramasi — DD ve zarar hesaplama dahil                  |
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
         g_accLossUSD += MathAbs(pnl);  // Toplam zarar (pozitif deger)
      }
   }

   // Hesap drawdown % hesapla
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if(balance > 0)
      g_accDDPct = ((balance - equity) / balance) * 100.0;
   else
      g_accDDPct = 0;

   // Negatif DD olmasin (equity > balance durumu)
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
      g_smartInfo = StringFormat("Yetersiz (%d poz, %d sembol)", cnt, symSay);
      return;
   }

   // ──── Agresif modda min kayip esigini dusur ────
   double minLossEsik = Inp_SmartMinLossUSD;
   double minNetEsik  = Inp_SmartMinNet;
   int    maxGrupEsik = Inp_SmartMaxGroup;

   if(Inp_SmartAggressiveMode)
   {
      // DD arttikca daha agresif ol
      if(g_accDDPct >= Inp_SmartActivateDDPct * 2.0)
      {
         // Cok yuksek DD — cok agresif
         minLossEsik = minLossEsik * 0.25;
         minNetEsik  = 0.01;
         maxGrupEsik = MathMin(maxGrupEsik + 3, cnt);
      }
      else if(g_accDDPct >= Inp_SmartActivateDDPct * 1.5)
      {
         // Yuksek DD — orta agresif
         minLossEsik = minLossEsik * 0.50;
         minNetEsik  = minNetEsik * 0.50;
         maxGrupEsik = MathMin(maxGrupEsik + 2, cnt);
      }
      else
      {
         // Normal esik — hafif agresif
         minLossEsik = minLossEsik * 0.75;
         minNetEsik  = minNetEsik * 0.75;
         maxGrupEsik = MathMin(maxGrupEsik + 1, cnt);
      }
   }

   // ──── En buyuk zarardaki pozisyonu bul ────
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
      g_smartInfo = StringFormat("Buyuk zarar yok (esik:$%.2f, %d poz)",
                                 minLossEsik, cnt);
      return;
   }

   // ──── Karli pozisyonlari topla ────
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

      g_smartInfo = StringFormat("Karli az(%d) Z:$%.2f K:$%.2f [%d poz]",
                                 profCnt, worstPnl, topKar, cnt);
      return;
   }

   // ──── Sirala (buyukten kucuge) ────
   for(int i=0; i<profCnt-1; i++)
   {
      for(int j=0; j<profCnt-1-i; j++)
      {
         if(profPnl[j] < profPnl[j+1])
         {
            double tmpP = profPnl[j];
            profPnl[j]  = profPnl[j+1];
            profPnl[j+1]= tmpP;

            int tmpI    = profIdx[j];
            profIdx[j]  = profIdx[j+1];
            profIdx[j+1]= tmpI;
         }
      }
   }

   // ──── Optimal grup boyutunu bul ────
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
      for(int k=0; k<topMax; k++)
         topKar += profPnl[k];

      g_smartInfo = StringFormat("Kar<Zarar | Z:$%.2f K:$%.2f N:$%.2f [%d]",
                                 worstPnl, topKar, topKar+worstPnl, cnt);
      return;
   }

   // ──── KAPATMA ────
   Print("==================================================================");
   PrintFormat("EVRENSEL SMART CLOSE BASLATILDI (DD:%.1f%% Zarar:$%.2f)",
               g_accDDPct, g_accLossUSD);

   int symSayisi = SembolSay(arr,cnt);
   PrintFormat("  Taranan: %d pozisyon, %d farkli sembol", cnt, symSayisi);
   PrintFormat("  Tetik: %s", g_smartTrigger);

   if(Inp_SmartAggressiveMode)
      PrintFormat("  AGRESIF MOD | MinLoss:$%.2f MinNet:$%.4f MaxGrp:%d",
                  minLossEsik, minNetEsik, maxGrupEsik);

   string worstTip = (arr[worstIdx].posType==0) ? "BUY" : "SELL";
   PrintFormat("  ZARAR: #%llu %s %s $%.2f Magic:%llu",
               arr[worstIdx].ticket,
               arr[worstIdx].symbol,
               worstTip,
               worstPnl,
               arr[worstIdx].magic);

   m_trade.PositionClose(arr[worstIdx].ticket);
   PrintFormat("  [X] KAPATILDI #%llu %s $%.2f",
               arr[worstIdx].ticket,
               arr[worstIdx].symbol,
               worstPnl);

   for(int k=0; k<bestGroup; k++)
   {
      int idx = profIdx[k];
      string tip = (arr[idx].posType==0) ? "BUY" : "SELL";

      m_trade.PositionClose(arr[idx].ticket);
      PrintFormat("  [X] KAR #%llu %s %s $%.2f Magic:%llu",
                  arr[idx].ticket,
                  arr[idx].symbol,
                  tip,
                  arr[idx].pnl,
                  arr[idx].magic);
   }

   g_smartCloseCount++;
   int symSon = SembolSay(arr,cnt);
   g_smartInfo = StringFormat("KAPATILDI %d+1 | Net:$%.2f | #%d | %d sym",
                              bestGroup, bestNet, g_smartCloseCount, symSon);

   PrintFormat("EVRENSEL SMART CLOSE TAMAMLANDI #%d | Net: $%.2f",
               g_smartCloseCount, bestNet);
   Print("==================================================================");
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
      {
         if(symbols[j] == arr[i].symbol)
         {
            found = true;
            break;
         }
      }
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
      return true;
   }

   if(g_posTotal>0 && g_pnlTotal <= Inp_SL_Total)
   {
      Print("MAKS ZARAR: $",DoubleToString(g_pnlTotal,2));
      TumunuKapat(); TumEmirleriSil(); g_anchor=0;
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
   double maF[5],maS[5],rsi[5],atr[3],cci[5];
   double bbUp[3],bbMid[3],bbLo[3];
   double macdM[5],macdS[5];
   double stK[5],stD[5];

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
//| Kafes yonetimi                                                    |
//+------------------------------------------------------------------+
void KafesYonet(double ask, double bid, double mid)
{
   double refreshDist = Inp_RefreshDist * _Point;
   if(g_anchor!=0 && MathAbs(mid-g_anchor) < refreshDist)
      return;

   if(g_posTotal >= Inp_MaxOpenPos) return;
   if(g_lotTotal >= Inp_MaxTotalLots) return;

   TumEmirleriSil();

   long stopLvl = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   double spreadDist = (double)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD)*_Point*2.0;
   double minDist = MathMax((double)stopLvl*_Point, spreadDist);
   double gridDist = Inp_GridStep * _Point;
   if(gridDist < minDist) gridDist = minDist + _Point;

   double lot = GuvenliLot();
   if(!TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT))
   { g_anchor=mid; return; }

   // BUY LIMIT
   if(g_kafes_buy_aktif)
   {
      for(int lv=1; lv<=Inp_BuyLimitLevels; lv++)
      {
         double px = NormalizeDouble(ask - gridDist*lv, _Digits);
         if(px<=0 || ask-px<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_BUY_LIMIT)) break;
         m_trade.BuyLimit(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                          StringFormat("TTP_BL%d",lv));
      }
   }

   // BUY STOP
   if(g_kafes_buy_aktif)
   {
      for(int lv=1; lv<=Inp_BuyStopLevels; lv++)
      {
         double px = NormalizeDouble(ask + gridDist*lv, _Digits);
         if(px-ask<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_BUY_STOP)) break;
         m_trade.BuyStop(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                         StringFormat("TTP_BS%d",lv));
      }
   }

   // SELL LIMIT
   if(g_kafes_sell_aktif)
   {
      for(int lv=1; lv<=Inp_SellLimitLevels; lv++)
      {
         double px = NormalizeDouble(bid + gridDist*lv, _Digits);
         if(px-bid<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_SELL_LIMIT)) break;
         m_trade.SellLimit(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                           StringFormat("TTP_SL%d",lv));
      }
   }

   // SELL STOP
   if(g_kafes_sell_aktif)
   {
      for(int lv=1; lv<=Inp_SellStopLevels; lv++)
      {
         double px = NormalizeDouble(bid - gridDist*lv, _Digits);
         if(px<=0 || bid-px<minDist) continue;
         if(!TeminatKontrol(lot,ORDER_TYPE_SELL_STOP)) break;
         m_trade.SellStop(lot,px,_Symbol,0,0,ORDER_TIME_GTC,0,
                          StringFormat("TTP_SS%d",lv));
      }
   }

   g_anchor = mid;
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

//+------------------------------------------------------------------+
//| Panel goster                                                      |
//+------------------------------------------------------------------+
void PanelGoster(double mid)
{
   string skorYon;
   if(g_kafes_buy_aktif && g_kafes_sell_aktif)
      skorYon = "CIFT YON (BUY+SELL)";
   else if(g_kafes_buy_aktif)
      skorYon = "SADECE BUY";
   else
      skorYon = "SADECE SELL";

   string tahminYon;
   if(g_dir>0)       tahminYon="YUKARI";
   else if(g_dir<0)  tahminYon="ASAGI";
   else              tahminYon="NOTR";

   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double freeM   = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double usedM   = AccountInfoDouble(ACCOUNT_MARGIN);
   double ddPct   = 0;
   if(balance>0) ddPct = ((balance-equity)/balance)*100.0;
   double mLvl = 0;
   if(usedM>0) mLvl = (equity/usedM)*100.0;

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

   string smartDurum;
   if(!Inp_SmartEnabled)
      smartDurum = "DEVRE DISI";
   else if(g_smartActive)
      smartDurum = "AKTIF";
   else
      smartDurum = "BEKLENIYOR";

   string agresifStr = Inp_SmartAggressiveMode ? "ACIK" : "KAPALI";

   string s = "";
   s += "================================================\n";
   s += "  TICK TRADER PRO v7.1 UNIVERSAL\n";
   s += "  Skor Kafes + SmartClose (DD/Zarar Tetiklemeli)\n";
   s += "================================================\n";
   s += "-------- HESAP ------------------------------\n";
   s += StringFormat(" Bakiye      : $%.2f\n",balance);
   s += StringFormat(" Equity      : $%.2f\n",equity);
   s += StringFormat(" Serbest     : $%.2f\n",freeM);
   s += StringFormat(" Kullanilan  : $%.2f\n",usedM);
   s += StringFormat(" Margin Lv   : %.1f%%\n",mLvl);
   s += StringFormat(" Drawdown    : %.1f%% (max %.0f%%)\n",ddPct,Inp_MaxDrawdownPct);
   s += "-------- TAHMIN & SKOR ----------------------\n";
   s += StringFormat(" Skor        : %.0f / 100\n",g_score);
   s += StringFormat(" Tahmin      : %s\n",tahminYon);
   s += StringFormat(" Kafes Yon   : %s\n",skorYon);
   s += StringFormat(" Hedef       : %s\n",DoubleToString(g_target,_Digits));
   s += StringFormat(" Gerekce     : %s\n",g_reason);
   s += StringFormat(" Yon Siniri  : <%.0f SELL | >+%.0f BUY | Ara CIFT\n",
                      Inp_ScoreSellOnly, Inp_ScoreBuyOnly);
   s += "-------- ROBOT POZISYONLARI -----------------\n";
   s += StringFormat(" Toplam      : %d / %d\n",g_posTotal,Inp_MaxOpenPos);
   s += StringFormat(" BUY         : %d  Lot:%.2f  $%.2f\n",g_posBuy,g_lotBuy,g_pnlBuy);
   s += StringFormat(" SELL        : %d  Lot:%.2f  $%.2f\n",g_posSell,g_lotSell,g_pnlSell);
   s += StringFormat(" TopLot      : %.2f / %.2f\n",g_lotTotal,Inp_MaxTotalLots);
   s += StringFormat(" Zararda     : %d\n",g_posLoss);
   s += StringFormat(" Aralik      : %.0f pt\n",rangeP);
   s += StringFormat(" Robot PnL   : $%.2f\n",g_pnlTotal);
   s += "-------- TUM HESAP --------------------------\n";
   s += StringFormat(" Hesap Poz   : %d\n",g_accTotal);
   s += StringFormat(" Hesap PnL   : $%.2f\n",g_accPnl);
   s += StringFormat(" Hesap Lot   : %.2f\n",g_accLotTotal);
   s += StringFormat(" Hesap Zarar : %d islem ($%.2f)\n",g_accLoss,g_accLossUSD);
   s += StringFormat(" Hesap DD    : %.1f%%\n",g_accDDPct);
   s += "-------- SMART CLOSE ------------------------\n";
   s += StringFormat(" Durum       : %s\n",smartDurum);
   s += StringFormat(" Tetik DD    : %.1f%% (ayar:%.1f%%)\n",g_accDDPct,Inp_SmartActivateDDPct);
   s += StringFormat(" Tetik Zarar : $%.2f (ayar:$%.2f)\n",g_accLossUSD,Inp_SmartActivateLossUSD);
   s += StringFormat(" Tetik Sebep : %s\n",g_smartTrigger);
   s += StringFormat(" Agresif Mod : %s\n",agresifStr);
   s += StringFormat(" Min Kayip   : $%.2f\n",Inp_SmartMinLossUSD);
   s += StringFormat(" Bilgi       : %s\n",g_smartInfo);
   s += StringFormat(" Kapamalar   : %d\n",g_smartCloseCount);
   s += "-------- EMIRLER ----------------------------\n";
   s += StringFormat(" BL:%d BS:%d SL:%d SS:%d = %d\n",
                      g_ordBL,g_ordBS,g_ordSL,g_ordSS,g_ordTotal);
   s += "-------- HEDEFLER ---------------------------\n";
   s += StringFormat(" Tek:$%.2f BG:$%.2f SG:$%.2f T:$%.2f Z:$%.2f\n",
                      Inp_TP_Single,Inp_TP_BuyGroup,Inp_TP_SellGroup,
                      Inp_TP_Total,Inp_SL_Total);
   s += "================================================\n";

   Comment(s);
}
//+------------------------------------------------------------------+