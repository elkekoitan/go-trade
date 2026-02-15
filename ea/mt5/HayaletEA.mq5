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
input string InpShmName       = "HayaletSHM";   // Shared memory name
input uint   InpTickCapacity   = 4096;            // Tick ring buffer capacity
input uint   InpPosCapacity    = 1024;            // Position ring buffer capacity
input uint   InpCmdCapacity    = 512;             // Command ring buffer capacity
input uint   InpAcctCapacity   = 64;              // Account ring buffer capacity
input int    InpHeartbeatMs    = 1000;            // Heartbeat interval (ms)
input int    InpMagicStart     = 1000;            // Magic number range start
input int    InpMagicEnd       = 6999;            // Magic number range end
input string InpSymbols        = "";              // Symbols (empty = chart symbol only)

// ── Constants matching Go struct sizes ──
#define SYMBOL_SIZE    16
#define ACCOUNT_SIZE   16
#define REASON_SIZE    32
#define TICK_SIZE      40
#define POSITION_SIZE  80  // without padding: 8+16+4+4+8+8+8+4+16 = 76, aligned to 80
#define COMMAND_SIZE   104
#define ACCOUNT_ST_SIZE 48 // 16+8+8+8+8 = 48

// ── Globals ──
bool g_initialized = false;
datetime g_lastHeartbeat = 0;
string g_symbols[];

//+------------------------------------------------------------------+
//| Pack a tick into byte array matching ShmTick layout               |
//+------------------------------------------------------------------+
void PackTick(uchar &buf[], string symbol, double bid, double ask)
{
   ArrayResize(buf, TICK_SIZE);
   ArrayInitialize(buf, 0);

   // Symbol[16]
   uchar symBytes[];
   StringToCharArray(symbol, symBytes, 0, SYMBOL_SIZE);
   ArrayCopy(buf, symBytes, 0, 0, MathMin(ArraySize(symBytes), SYMBOL_SIZE));

   // Bid (double, offset 16)
   uchar bidBytes[8];
   DoubleToBytes(bid, bidBytes);
   ArrayCopy(buf, bidBytes, 16, 0, 8);

   // Ask (double, offset 24)
   uchar askBytes[8];
   DoubleToBytes(ask, askBytes);
   ArrayCopy(buf, askBytes, 24, 0, 8);

   // TimeNs (int64, offset 32)
   long timeNs = (long)TimeCurrent() * 1000000000LL;
   uchar timeBytes[8];
   LongToBytes(timeNs, timeBytes);
   ArrayCopy(buf, timeBytes, 32, 0, 8);
}

//+------------------------------------------------------------------+
//| Pack a position into byte array matching ShmPosition layout       |
//+------------------------------------------------------------------+
void PackPosition(uchar &buf[], ulong ticket)
{
   ArrayResize(buf, POSITION_SIZE);
   ArrayInitialize(buf, 0);

   if(!PositionSelectByTicket(ticket))
      return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   long magic = PositionGetInteger(POSITION_MAGIC);
   double volume = PositionGetDouble(POSITION_VOLUME);
   double price = PositionGetDouble(POSITION_PRICE_OPEN);
   long posType = PositionGetInteger(POSITION_TYPE);
   datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);

   int side = (posType == POSITION_TYPE_BUY) ? 1 : -1;
   int type = 0; // market order

   // ID (int64, offset 0)
   long id = (long)ticket;
   uchar idBytes[8];
   LongToBytes(id, idBytes);
   ArrayCopy(buf, idBytes, 0, 0, 8);

   // Symbol[16] (offset 8)
   uchar symBytes[];
   StringToCharArray(symbol, symBytes, 0, SYMBOL_SIZE);
   ArrayCopy(buf, symBytes, 8, 0, MathMin(ArraySize(symBytes), SYMBOL_SIZE));

   // Side (int32, offset 24)
   uchar sideBytes[4];
   IntToBytes(side, sideBytes);
   ArrayCopy(buf, sideBytes, 24, 0, 4);

   // Type (int32, offset 28)
   uchar typeBytes[4];
   IntToBytes(type, typeBytes);
   ArrayCopy(buf, typeBytes, 28, 0, 4);

   // Volume (double, offset 32)
   uchar volBytes[8];
   DoubleToBytes(volume, volBytes);
   ArrayCopy(buf, volBytes, 32, 0, 8);

   // Price (double, offset 40)
   uchar priceBytes[8];
   DoubleToBytes(price, priceBytes);
   ArrayCopy(buf, priceBytes, 40, 0, 8);

   // TimeNs (int64, offset 48)
   long timeNs = (long)openTime * 1000000000LL;
   uchar timeBytes[8];
   LongToBytes(timeNs, timeBytes);
   ArrayCopy(buf, timeBytes, 48, 0, 8);

   // Magic (int32, offset 56)
   uchar magicBytes[4];
   IntToBytes((int)magic, magicBytes);
   ArrayCopy(buf, magicBytes, 56, 0, 4);

   // Account[16] (offset 60)
   string acctId = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   uchar acctBytes[];
   StringToCharArray(acctId, acctBytes, 0, ACCOUNT_SIZE);
   ArrayCopy(buf, acctBytes, 60, 0, MathMin(ArraySize(acctBytes), ACCOUNT_SIZE));
}

//+------------------------------------------------------------------+
//| Pack account state into byte array matching ShmAccount layout     |
//+------------------------------------------------------------------+
void PackAccount(uchar &buf[])
{
   ArrayResize(buf, ACCOUNT_ST_SIZE);
   ArrayInitialize(buf, 0);

   string acctId = IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN));
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double margin = AccountInfoDouble(ACCOUNT_MARGIN);

   // Account[16] (offset 0)
   uchar acctBytes[];
   StringToCharArray(acctId, acctBytes, 0, ACCOUNT_SIZE);
   ArrayCopy(buf, acctBytes, 0, 0, MathMin(ArraySize(acctBytes), ACCOUNT_SIZE));

   // Balance (double, offset 16)
   uchar balBytes[8];
   DoubleToBytes(balance, balBytes);
   ArrayCopy(buf, balBytes, 16, 0, 8);

   // Equity (double, offset 24)
   uchar eqBytes[8];
   DoubleToBytes(equity, eqBytes);
   ArrayCopy(buf, eqBytes, 24, 0, 8);

   // Margin (double, offset 32)
   uchar marBytes[8];
   DoubleToBytes(margin, marBytes);
   ArrayCopy(buf, marBytes, 32, 0, 8);

   // TimeNs (int64, offset 40)
   long timeNs = (long)TimeCurrent() * 1000000000LL;
   uchar timeBytes[8];
   LongToBytes(timeNs, timeBytes);
   ArrayCopy(buf, timeBytes, 40, 0, 8);
}

//+------------------------------------------------------------------+
//| Byte packing helpers                                              |
//+------------------------------------------------------------------+
void DoubleToBytes(double value, uchar &bytes[])
{
   ArrayResize(bytes, 8);
   union { double d; uchar b[8]; } u;
   // MQL5 workaround: use struct copy
   long bits = 0;
   // Direct memory layout
   uchar temp[];
   if(StringToCharArray(DoubleToString(value, 20), temp) > 0) {}
   // Use MathSwap workaround
   ArrayResize(bytes, 8);
   // Direct approach: copy double bytes
   struct DoubleBytes { double val; };
   struct RawBytes { uchar b[8]; };
   DoubleBytes db;
   db.val = value;
   RawBytes rb;
   // MQL5 struct copy preserves memory layout
   ArrayInitialize(bytes, 0);
   // Use the MQL5 built-in approach
   long longVal = 0;
   // Reinterpret double as long
   struct DL { double d; };
   struct LL { long l; };
   DL dl; dl.d = value;
   // In MQL5, we need to use StructToCharArray or similar
   MqlRates rates[];
   // Simplest reliable approach in MQL5:
   ArrayResize(bytes, 8);
   ResetLastError();
   // MQL5 has no direct double-to-bytes, use FileWriteDouble trick
   // Alternative: bit manipulation is needed
   // Since MQL5 lacks union/reinterpret_cast, use global variable trick
   string filename = "hayalet_tmp.bin";
   int handle = FileOpen(filename, FILE_WRITE|FILE_BIN);
   if(handle != INVALID_HANDLE)
   {
      FileWriteDouble(handle, value);
      FileClose(handle);
      handle = FileOpen(filename, FILE_READ|FILE_BIN);
      if(handle != INVALID_HANDLE)
      {
         FileReadArray(handle, bytes, 0, 8);
         FileClose(handle);
      }
      FileDelete(filename);
   }
}

void LongToBytes(long value, uchar &bytes[])
{
   ArrayResize(bytes, 8);
   for(int i = 0; i < 8; i++)
      bytes[i] = (uchar)((value >> (i * 8)) & 0xFF);
}

void IntToBytes(int value, uchar &bytes[])
{
   ArrayResize(bytes, 4);
   for(int i = 0; i < 4; i++)
      bytes[i] = (uchar)((value >> (i * 8)) & 0xFF);
}

//+------------------------------------------------------------------+
//| Parse command and execute trade                                   |
//+------------------------------------------------------------------+
void ExecuteCommand(uchar &cmdBuf[])
{
   // Unpack command fields
   int cmdType = BytesToInt(cmdBuf, 0);
   string symbol = CharArrayToString(cmdBuf, 4, SYMBOL_SIZE);
   // Trim null bytes
   int nullPos = StringFind(symbol, "\x00");
   if(nullPos >= 0) symbol = StringSubstr(symbol, 0, nullPos);

   int side = BytesToInt(cmdBuf, 20);
   double volume = BytesToDouble(cmdBuf, 24);
   double price = BytesToDouble(cmdBuf, 32);
   double tp = BytesToDouble(cmdBuf, 40);
   double sl = BytesToDouble(cmdBuf, 48);
   long ticket = BytesToLong(cmdBuf, 56);
   int magic = BytesToInt(cmdBuf, 64);
   string reason = CharArrayToString(cmdBuf, 84, REASON_SIZE);

   MqlTradeRequest request = {};
   MqlTradeResult result = {};

   switch(cmdType)
   {
      case 1: // OPEN
         request.action = TRADE_ACTION_DEAL;
         request.symbol = symbol;
         request.volume = volume;
         request.type = (side > 0) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         request.price = (side > 0) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
         if(tp > 0) request.tp = tp;
         if(sl > 0) request.sl = sl;
         request.magic = magic;
         request.deviation = 20;
         request.type_filling = ORDER_FILLING_IOC;
         if(!OrderSend(request, result))
            PrintFormat("[HAYALET] OPEN failed: %s vol=%.2f err=%d", symbol, volume, GetLastError());
         else
            PrintFormat("[HAYALET] OPEN ok: %s vol=%.2f ticket=%lld reason=%s", symbol, volume, result.order, reason);
         break;

      case 2: // CLOSE
         if(ticket > 0 && PositionSelectByTicket((ulong)ticket))
         {
            request.action = TRADE_ACTION_DEAL;
            request.position = (ulong)ticket;
            request.symbol = PositionGetString(POSITION_SYMBOL);
            request.volume = (volume > 0) ? volume : PositionGetDouble(POSITION_VOLUME);
            long posType = PositionGetInteger(POSITION_TYPE);
            request.type = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price = (posType == POSITION_TYPE_BUY) ?
               SymbolInfoDouble(request.symbol, SYMBOL_BID) :
               SymbolInfoDouble(request.symbol, SYMBOL_ASK);
            request.deviation = 20;
            request.type_filling = ORDER_FILLING_IOC;
            if(!OrderSend(request, result))
               PrintFormat("[HAYALET] CLOSE failed: ticket=%lld err=%d", ticket, GetLastError());
            else
               PrintFormat("[HAYALET] CLOSE ok: ticket=%lld reason=%s", ticket, reason);
         }
         break;

      case 3: // MODIFY
         if(ticket > 0 && PositionSelectByTicket((ulong)ticket))
         {
            request.action = TRADE_ACTION_SLTP;
            request.position = (ulong)ticket;
            request.symbol = PositionGetString(POSITION_SYMBOL);
            if(tp > 0) request.tp = tp;
            if(sl > 0) request.sl = sl;
            if(!OrderSend(request, result))
               PrintFormat("[HAYALET] MODIFY failed: ticket=%lld err=%d", ticket, GetLastError());
            else
               PrintFormat("[HAYALET] MODIFY ok: ticket=%lld tp=%.5f sl=%.5f", ticket, tp, sl);
         }
         break;

      default:
         PrintFormat("[HAYALET] Unknown command type: %d", cmdType);
         break;
   }
}

double BytesToDouble(const uchar &buf[], int offset)
{
   uchar temp[8];
   ArrayCopy(temp, buf, 0, offset, 8);
   // Use file trick to convert bytes back to double
   string filename = "hayalet_tmp2.bin";
   int handle = FileOpen(filename, FILE_WRITE|FILE_BIN);
   if(handle == INVALID_HANDLE) return 0;
   FileWriteArray(handle, temp, 0, 8);
   FileClose(handle);
   handle = FileOpen(filename, FILE_READ|FILE_BIN);
   if(handle == INVALID_HANDLE) return 0;
   double val = FileReadDouble(handle);
   FileClose(handle);
   FileDelete(filename);
   return val;
}

long BytesToLong(const uchar &buf[], int offset)
{
   long val = 0;
   for(int i = 0; i < 8; i++)
      val |= ((long)buf[offset + i]) << (i * 8);
   return val;
}

int BytesToInt(const uchar &buf[], int offset)
{
   int val = 0;
   for(int i = 0; i < 4; i++)
      val |= ((int)buf[offset + i]) << (i * 8);
   return val;
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

   EventSetMillisecondTimer(50); // 50ms processing loop
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
//| Tick handler — send tick data to Go                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;

   // Send tick for chart symbol
   uchar tickBuf[];
   PackTick(tickBuf, Symbol(), SymbolInfoDouble(Symbol(), SYMBOL_BID), SymbolInfoDouble(Symbol(), SYMBOL_ASK));
   HB_SendTick(tickBuf);
}

//+------------------------------------------------------------------+
//| Timer handler — main processing loop                              |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_initialized) return;

   // ── Send ticks for all watched symbols ──
   for(int i = 0; i < ArraySize(g_symbols); i++)
   {
      string sym = g_symbols[i];
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      double ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(bid > 0 && ask > 0)
      {
         uchar tickBuf[];
         PackTick(tickBuf, sym, bid, ask);
         HB_SendTick(tickBuf);
      }
   }

   // ── Send all open positions in our magic range ──
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      long magic = PositionGetInteger(POSITION_MAGIC);
      if(magic >= InpMagicStart && magic <= InpMagicEnd)
      {
         uchar posBuf[];
         PackPosition(posBuf, ticket);
         HB_SendPosition(posBuf);
      }
   }

   // ── Send account state ──
   uchar acctBuf[];
   PackAccount(acctBuf);
   HB_SendAccount(acctBuf);

   // ── Process commands from Go ──
   uchar cmdBuf[];
   ArrayResize(cmdBuf, COMMAND_SIZE);
   while(HB_GetCommand(cmdBuf))
   {
      ExecuteCommand(cmdBuf);
      ArrayInitialize(cmdBuf, 0);
   }

   // ── Heartbeat ──
   datetime now = TimeCurrent();
   if(now - g_lastHeartbeat >= InpHeartbeatMs / 1000)
   {
      HB_Heartbeat((long)now * 1000000000LL);
      g_lastHeartbeat = now;
   }
}
//+------------------------------------------------------------------+
