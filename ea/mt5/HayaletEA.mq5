//+------------------------------------------------------------------+
//| HayaletEA.mq5 — HAYALET Trading System Bridge EA                |
//| Connects MT5 terminal to Go engine via shared memory DLL         |
//+------------------------------------------------------------------+
#property copyright "HAYALET"
#property version   "1.00"
#property strict

// ── DLL imports ──
#import "hayalet_shm.dll"
int  HB_Init(string name, uint tickCap, uint posCap, uint cmdCap, uint acctCap);
int  HB_SendTick(const uchar &tick[]);
int  HB_SendPosition(const uchar &pos[]);
int  HB_GetCommand(uchar &cmd[]);
int  HB_SendAccount(const uchar &acct[]);
void HB_Heartbeat(long ts);
int  HB_Close();
#import

// ── Inputs ──
input string InpShmName       = "HAYALET_SHM";   // Shared memory name
input uint   InpTickCapacity   = 4096;             // Tick ring buffer capacity
input uint   InpPosCapacity    = 1024;             // Position ring buffer capacity
input uint   InpCmdCapacity    = 512;              // Command ring buffer capacity
input uint   InpAcctCapacity   = 64;               // Account ring buffer capacity
input int    InpHeartbeatMs    = 1000;             // Heartbeat interval (ms)
input int    InpMagicStart     = 1000;             // Magic number range start
input int    InpMagicEnd       = 6999;             // Magic number range end
input string InpSymbols        = "";               // Symbols (empty = chart symbol only)

// ── Struct sizes matching Go/C++ layout ──
#define SYMBOL_SIZE     16
#define ACCOUNT_SIZE    16
#define REASON_SIZE     32
#define TICK_BYTES      40
#define POSITION_BYTES  76
#define COMMAND_BYTES   104
#define ACCOUNT_BYTES   48

// ── Structs for StructToCharArray / CharArrayToStruct ──
struct ShmTick
{
   uchar  Symbol[SYMBOL_SIZE]; // 16
   double Bid;                 // 8
   double Ask;                 // 8
   long   TimeNs;              // 8 = 40 total
};

struct ShmPosition
{
   long   ID;                     // 8
   uchar  Symbol[SYMBOL_SIZE];    // 16
   int    Side;                   // 4
   int    Type;                   // 4
   double Volume;                 // 8
   double Price;                  // 8
   long   TimeNs;                 // 8
   int    Magic;                  // 4
   uchar  Account[ACCOUNT_SIZE];  // 16 = 76 total
};

struct ShmCommand
{
   int    Type;                   // 4
   uchar  Symbol[SYMBOL_SIZE];    // 16
   int    Side;                   // 4
   double Volume;                 // 8
   double Price;                  // 8
   double TP;                     // 8
   double SL;                     // 8
   long   Ticket;                 // 8
   int    Magic;                  // 4
   uchar  Account[ACCOUNT_SIZE];  // 16
   uchar  Reason[REASON_SIZE];    // 32 = 104 total... but check padding
   long   TimeNs;                 // 8
};

struct ShmAccount
{
   uchar  Account[ACCOUNT_SIZE];  // 16
   double Balance;                // 8
   double Equity;                 // 8
   double Margin;                 // 8
   long   TimeNs;                 // 8 = 48 total
};

// ── Globals ──
bool     g_initialized = false;
datetime g_lastHeartbeat = 0;
string   g_symbols[];

//+------------------------------------------------------------------+
//| Helper: copy string into fixed-size uchar array                   |
//+------------------------------------------------------------------+
void StringToFixedBytes(const string s, uchar &dest[], int size)
{
   ArrayInitialize(dest, 0);
   uchar tmp[];
   int len = StringToCharArray(s, tmp, 0, -1, CP_ACP);
   int copyLen = MathMin(len, size);
   for(int i = 0; i < copyLen && i < ArraySize(tmp); i++)
      dest[i] = tmp[i];
}

//+------------------------------------------------------------------+
//| Helper: extract string from fixed-size uchar array                |
//+------------------------------------------------------------------+
string FixedBytesToString(const uchar &src[], int size)
{
   // Find null terminator
   int len = 0;
   for(int i = 0; i < size; i++)
   {
      if(src[i] == 0) break;
      len++;
   }
   if(len == 0) return "";
   uchar tmp[];
   ArrayResize(tmp, len);
   ArrayCopy(tmp, src, 0, 0, len);
   return CharArrayToString(tmp, 0, -1, CP_ACP);
}

//+------------------------------------------------------------------+
//| Pack and send tick                                                |
//+------------------------------------------------------------------+
void SendTick(string symbol, double bid, double ask)
{
   ShmTick tick;
   ZeroMemory(tick);
   StringToFixedBytes(symbol, tick.Symbol, SYMBOL_SIZE);
   tick.Bid = bid;
   tick.Ask = ask;
   tick.TimeNs = (long)TimeCurrent() * 1000000000;

   uchar buf[];
   StructToCharArray(tick, buf);
   HB_SendTick(buf);
}

//+------------------------------------------------------------------+
//| Pack and send position                                            |
//+------------------------------------------------------------------+
void SendPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return;

   ShmPosition pos;
   ZeroMemory(pos);

   pos.ID = (long)ticket;
   StringToFixedBytes(PositionGetString(POSITION_SYMBOL), pos.Symbol, SYMBOL_SIZE);

   long posType = PositionGetInteger(POSITION_TYPE);
   pos.Side = (posType == POSITION_TYPE_BUY) ? 1 : -1;
   pos.Type = 0; // market
   pos.Volume = PositionGetDouble(POSITION_VOLUME);
   pos.Price = PositionGetDouble(POSITION_PRICE_OPEN);
   pos.TimeNs = (long)PositionGetInteger(POSITION_TIME) * 1000000000;
   pos.Magic = (int)PositionGetInteger(POSITION_MAGIC);
   StringToFixedBytes(IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), pos.Account, ACCOUNT_SIZE);

   uchar buf[];
   StructToCharArray(pos, buf);
   HB_SendPosition(buf);
}

//+------------------------------------------------------------------+
//| Pack and send account state                                       |
//+------------------------------------------------------------------+
void SendAccount()
{
   ShmAccount acct;
   ZeroMemory(acct);

   StringToFixedBytes(IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), acct.Account, ACCOUNT_SIZE);
   acct.Balance = AccountInfoDouble(ACCOUNT_BALANCE);
   acct.Equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   acct.Margin  = AccountInfoDouble(ACCOUNT_MARGIN);
   acct.TimeNs  = (long)TimeCurrent() * 1000000000;

   uchar buf[];
   StructToCharArray(acct, buf);
   HB_SendAccount(buf);
}

//+------------------------------------------------------------------+
//| Process a command from Go engine                                  |
//+------------------------------------------------------------------+
void ProcessCommand(ShmCommand &cmd)
{
   string symbol = FixedBytesToString(cmd.Symbol, SYMBOL_SIZE);
   string reason = FixedBytesToString(cmd.Reason, REASON_SIZE);

   MqlTradeRequest request = {};
   MqlTradeResult  result  = {};

   switch(cmd.Type)
   {
      case 1: // OPEN
         request.action       = TRADE_ACTION_DEAL;
         request.symbol       = symbol;
         request.volume       = cmd.Volume;
         request.type         = (cmd.Side > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         request.price        = (cmd.Side > 0) ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                                               : SymbolInfoDouble(symbol, SYMBOL_BID);
         if(cmd.TP > 0) request.tp = cmd.TP;
         if(cmd.SL > 0) request.sl = cmd.SL;
         request.magic        = cmd.Magic;
         request.deviation    = 20;
         request.type_filling = ORDER_FILLING_IOC;

         if(!OrderSend(request, result))
            PrintFormat("[HAYALET] OPEN fail: %s vol=%.2f err=%d", symbol, cmd.Volume, GetLastError());
         else
            PrintFormat("[HAYALET] OPEN ok: %s vol=%.2f ticket=%I64d reason=%s", symbol, cmd.Volume, result.order, reason);
         break;

      case 2: // CLOSE
         if(cmd.Ticket > 0 && PositionSelectByTicket((ulong)cmd.Ticket))
         {
            request.action       = TRADE_ACTION_DEAL;
            request.position     = (ulong)cmd.Ticket;
            request.symbol       = PositionGetString(POSITION_SYMBOL);
            request.volume       = (cmd.Volume > 0) ? cmd.Volume : PositionGetDouble(POSITION_VOLUME);
            long posType         = PositionGetInteger(POSITION_TYPE);
            request.type         = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price        = (posType == POSITION_TYPE_BUY)
                                   ? SymbolInfoDouble(request.symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(request.symbol, SYMBOL_ASK);
            request.deviation    = 20;
            request.type_filling = ORDER_FILLING_IOC;

            if(!OrderSend(request, result))
               PrintFormat("[HAYALET] CLOSE fail: ticket=%I64d err=%d", cmd.Ticket, GetLastError());
            else
               PrintFormat("[HAYALET] CLOSE ok: ticket=%I64d reason=%s", cmd.Ticket, reason);
         }
         break;

      case 3: // MODIFY
         if(cmd.Ticket > 0 && PositionSelectByTicket((ulong)cmd.Ticket))
         {
            request.action   = TRADE_ACTION_SLTP;
            request.position = (ulong)cmd.Ticket;
            request.symbol   = PositionGetString(POSITION_SYMBOL);
            if(cmd.TP > 0) request.tp = cmd.TP;
            if(cmd.SL > 0) request.sl = cmd.SL;

            if(!OrderSend(request, result))
               PrintFormat("[HAYALET] MODIFY fail: ticket=%I64d err=%d", cmd.Ticket, GetLastError());
            else
               PrintFormat("[HAYALET] MODIFY ok: ticket=%I64d tp=%.5f sl=%.5f", cmd.Ticket, cmd.TP, cmd.SL);
         }
         break;

      default:
         PrintFormat("[HAYALET] Unknown cmd type: %d", cmd.Type);
         break;
   }
}

//+------------------------------------------------------------------+
//| Parse symbol list from input                                      |
//+------------------------------------------------------------------+
void ParseSymbols()
{
   if(InpSymbols == "")
   {
      ArrayResize(g_symbols, 1);
      g_symbols[0] = Symbol();
      return;
   }
   string parts[];
   int count = StringSplit(InpSymbols, ',', parts);
   ArrayResize(g_symbols, count);
   for(int i = 0; i < count; i++)
   {
      g_symbols[i] = parts[i];
      StringTrimLeft(g_symbols[i]);
      StringTrimRight(g_symbols[i]);
   }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();

   if(!HB_Init(InpShmName, InpTickCapacity, InpPosCapacity, InpCmdCapacity, InpAcctCapacity))
   {
      Print("[HAYALET] Failed to initialize shared memory!");
      return INIT_FAILED;
   }

   g_initialized = true;
   PrintFormat("[HAYALET] Bridge initialized: %s | symbols=%d | tick=%d pos=%d cmd=%d acct=%d",
      InpShmName, ArraySize(g_symbols), InpTickCapacity, InpPosCapacity, InpCmdCapacity, InpAcctCapacity);

   EventSetMillisecondTimer(50);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_initialized)
   {
      HB_Close();
      g_initialized = false;
      Print("[HAYALET] Bridge closed");
   }
}

//+------------------------------------------------------------------+
//| Tick handler — send tick data to Go on every price change         |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;
   SendTick(Symbol(), SymbolInfoDouble(Symbol(), SYMBOL_BID), SymbolInfoDouble(Symbol(), SYMBOL_ASK));
}

//+------------------------------------------------------------------+
//| Timer handler — main 50ms processing loop                        |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_initialized) return;

   // ── Send ticks for all watched symbols ──
   for(int i = 0; i < ArraySize(g_symbols); i++)
   {
      double bid = SymbolInfoDouble(g_symbols[i], SYMBOL_BID);
      double ask = SymbolInfoDouble(g_symbols[i], SYMBOL_ASK);
      if(bid > 0 && ask > 0)
         SendTick(g_symbols[i], bid, ask);
   }

   // ── Send all open positions in our magic range ──
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic >= InpMagicStart && magic <= InpMagicEnd)
         SendPosition(ticket);
   }

   // ── Send account state ──
   SendAccount();

   // ── Process commands from Go engine ──
   uchar cmdBuf[];
   ArrayResize(cmdBuf, COMMAND_BYTES);
   while(HB_GetCommand(cmdBuf))
   {
      ShmCommand cmd;
      CharArrayToStruct(cmd, cmdBuf);
      ProcessCommand(cmd);
      ArrayInitialize(cmdBuf, 0);
   }

   // ── Heartbeat ──
   datetime now = TimeCurrent();
   if(now - g_lastHeartbeat >= InpHeartbeatMs / 1000)
   {
      HB_Heartbeat((long)now * 1000000000);
      g_lastHeartbeat = now;
   }
}
//+------------------------------------------------------------------+
