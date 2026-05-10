//+------------------------------------------------------------------+
//| ProjectName: Coeur de milliardaire                               |
//| Professional Trading Bot with Telegram Remote Control            |
//+------------------------------------------------------------------+
#include <Trade/Trade.mqh>

#import "kernel32.dll"
long FindFirstFileW(string hPath, uchar &find_data[]);
int  FindNextFileW(long hFindFile, uchar &find_data[]);
int  FindClose(long hFindFile);
long CreateFileW(string hPath, uint dwDesiredAccess, uint dwShareMode, long lpSecurityAttributes, uint dwCreationDisposition, uint dwFlagsAndAttributes, long hTemplateFile);
int  GetFileSize(long hFile, int &lpFileSizeHigh);
int  ReadFile(long hFile, uchar &lpBuffer[], uint nNumberOfBytesToRead, uint &lpNumberOfBytesRead, long lpOverlapped);
int  CloseHandle(long hObject);
#import

CTrade trade;
CPositionInfo pos;
COrderInfo ord;

input group "=== Trading Inputs ==="
input double RiskPercent = 1.0; // Risk as % of Trading Capital
input int Tppoints = 600;      // Take profit (10 points = 1 pip)
input int Slpoints = 300;      // Stoploss points (10 points = 1 pip)
input int TslTriggerPoints = 100; // Points in profit before Trailing SL is activated
input int TslPoints = 100;     // Trailing Stop loss
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // Time frame to run
input int InpMagic = 123;      // Expert advisor identification
input string TradeComment = "Scalping Robot";
input int EmaPeriod = 200;     // Period for trend filter EMA

input group "=== Telegram Settings ==="
input string InpTelegramToken = "7801637901:AAHAoFEk3eXcOneF5hpy6FIAuD3R_clEAtw";
input string InpTelegramChatID = "7505313544";
input bool ShowLogs = true;    // Afficher les logs dans l'Expert

//--- Internal Settings
string ExpirationDate = "2026.12.31";
string TelegramToken = "";
string TelegramChatID = "";

enum StartHour  { S_Inactive=0, S_01, S_02, S_03, S_04, S_05, S_06, S_07, S_08, S_09, S_10, S_11, S_12, S_13, S_14, S_15, S_16, S_17, S_18, S_19, S_20, S_21, S_22, S_23 };
input StartHour SHInput = S_08; // Start Hour

enum EndHour { E_Inactive=0, E_01, E_02, E_03, E_04, E_05, E_06, E_07, E_08, E_09, E_10, E_11, E_12, E_13, E_14, E_15, E_16, E_17, E_18, E_19, E_20, E_21, E_22, E_23 };
input EndHour EHInput = E_21; // End Hour

int BarsN = 5;
int ExpirationBars = 3;
int OrderDistPoints = 3;

//--- Dashboard Constants
#define DASH_BG_NAME "DASH_Background"
#define DASH_TITLE_NAME "DASH_Title"
#define DASH_VAL_BALANCE "DASH_ValBalance"
#define DASH_VAL_EQUITY "DASH_ValEquity"
#define DASH_VAL_PROFIT "DASH_ValProfit"
#define DASH_VAL_DAY_PROFIT "DASH_ValDayProfit"
#define DASH_VAL_LIFETIME "DASH_ValLifetime"
#define DASH_VAL_MSG      "DASH_ValMsg"
#define DASH_VAL_MODE     "DASH_ValMode"
#define DASH_VAL_EMOJI    "DASH_ValEmoji"
#define DASH_VAL_EXPIRY   "DASH_ValExpiry"

color  clrDashBg    = C'30,30,30';
color  clrDashTitle = clrGold;
color  clrDashText  = clrWhite;
int    dashX = 20, dashY = 20, dashWidth = 300, dashHeight = 340, dashLineH = 32;

//--- Global State
bool IsBotDisabled = false, IsStartedNotified = false, IsTelegramActive = true;
int TelegramInterval = 3, TradingMode = 1;
bool IsAuthorized = false, RequireAuthorization = true, IsConnectionLost = false;
long LastUpdateID = 0, GlobalFocusID = 0;
double AccountInitialBalance = 0, MaxDailyProfitLimit = 0, MaxDailyLossLimit = 0;
datetime CurrentExpirationDate = 0, LastTelegramSuccess = 0, LastCommandTime = 0;
string RemoteAdminMsg = "SYSTEME PRET", PendingCommand = "";
int EmaHandle = INVALID_HANDLE;
bool IsAwaitingSecurity = false;

struct TradeTracking { ulong ticket; bool notified; };
TradeTracking trackedPositions[], trackedOrders[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);
   ChartSetInteger(0, CHART_SHOW_GRID, false);
   AccountInitialBalance = AccountInfoDouble(ACCOUNT_BALANCE);

   TelegramToken = InpTelegramToken;
   TelegramChatID = InpTelegramChatID;
   StringTrimLeft(TelegramToken); StringTrimRight(TelegramToken);
   StringTrimLeft(TelegramChatID); StringTrimRight(TelegramChatID);

   EventSetTimer(3);
   if(CurrentExpirationDate == 0) CurrentExpirationDate = StringToTime(ExpirationDate);

   if(TimeCurrent() > CurrentExpirationDate)
     { Alert("❌ License expired: " + TimeToString(CurrentExpirationDate, TIME_DATE)); return INIT_FAILED; }

   CreateDashboard(); UpdateDashboard();
   if(!VerifyWebRequest()) return INIT_FAILED;

   EmaHandle = iMA(_Symbol, Timeframe, EmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(EmaHandle == INVALID_HANDLE) { Print("Error creating EMA handle"); return INIT_FAILED; }

   CheckAuthorization(); LoadPerformanceLimits(); LoadExpiration();
   LastTelegramSuccess = TimeCurrent(); LastCommandTime = TimeCurrent();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   IndicatorRelease(EmaHandle); EventKillTimer(); DeleteDashboard();
   SendTelegramMessage("🛑 Bot Stopped on " + _Symbol + "\nReason: " + IntegerToString(reason));
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   static datetime lastDashUpdate = 0;
   if(TimeCurrent() - lastDashUpdate >= 5) { UpdateDashboard(); lastDashUpdate = TimeCurrent(); }

   if(!IsAuthorized || IsBotDisabled || TimeCurrent() > CurrentExpirationDate) return;

   double dayProfit = GetDailyProfit();
   if(MaxDailyProfitLimit > 0 && dayProfit >= MaxDailyProfitLimit) return;
   if(MaxDailyLossLimit > 0 && dayProfit <= -MaxDailyLossLimit) return;

   TrailStop(); CheckTradeEvents();

   if(!IsNewBar()) return;

   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < (int)SHInput || (EHInput != 0 && dt.hour >= (int)EHInput)) { CloseAllOrders(); return; }

   int BuyTotal=0, SellTotal=0;
   for(int i = PositionsTotal()-1; i>=0; i--)
      if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic)
         if(pos.PositionType()==POSITION_TYPE_BUY) BuyTotal++; else SellTotal++;

   for(int i = OrdersTotal()-1; i>=0; i--)
      if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic)
         if(ord.OrderType()==ORDER_TYPE_BUY_STOP) BuyTotal++; else if(ord.OrderType()==ORDER_TYPE_SELL_STOP) SellTotal++;

   double ema[]; ArraySetAsSeries(ema, true);
   if(CopyBuffer(EmaHandle, 0, 0, 1, ema) <= 0) return;
   double curEma = ema[0], curBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(BuyTotal <= 0 && curBid > curEma)
     { double h = findHigh(); if(h > 0) { if(TradingMode == 1) SendBuyOrder(h); else SendSellOrder(h, true); } }
   if(SellTotal <= 0 && curBid < curEma)
     { double l = findLow(); if(l > 0) { if(TradingMode == 1) SendSellOrder(l); else SendBuyOrder(l, true); } }
  }

//+------------------------------------------------------------------+
//| Logic Functions                                                  |
//+------------------------------------------------------------------+
double findHigh() { double hh = 0; for(int i = 0; i < 400; i++) { double h = iHigh(_Symbol, Timeframe, i); if(i > BarsN && iHighest(_Symbol, Timeframe, MODE_HIGH, BarsN*2+1, i-BarsN) == i) if(h > hh) return h; hh = MathMax(h, hh); } return -1; }
double findLow() { double ll = DBL_MAX; for(int i = 0; i < 400; i++) { double l = iLow(_Symbol, Timeframe, i); if(i > BarsN && iLowest(_Symbol, Timeframe, MODE_LOW, BarsN*2+1, i-BarsN) == i) if(l < ll) return l; ll = MathMin(l, ll); } return -1; }
bool IsNewBar() { static datetime pt = 0; datetime ct = iTime(_Symbol, Timeframe, 0); if(pt != ct) { pt = ct; return true; } return false; }

void SendBuyOrder(double entry, bool isLimit=false)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(!isLimit && ask > entry - OrderDistPoints * _Point) return;
   double tp = entry + Tppoints * _Point, sl = entry - Slpoints * _Point, lots = calcLots(entry-sl);
   trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe));
  }

void SendSellOrder(double entry, bool isLimit=false)
  {
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(!isLimit && bid < entry + OrderDistPoints * _Point) return;
   double tp = entry - Tppoints * _Point, sl = entry + Slpoints * _Point, lots = calcLots(sl - entry);
   trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_SPECIFIED, iTime(_Symbol, Timeframe, 0) + ExpirationBars * PeriodSeconds(Timeframe));
  }

double calcLots(double slP)
  {
   double risk = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
   double tv = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE), ts = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE), ls = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(slP == 0) return 0.01;
   double lots = MathFloor(risk / (MathAbs(slP) / ts * tv * ls)) * ls;
   lots = MathMax(lots, SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN));
   double maxV = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX); if(maxV > 0) lots = MathMin(lots, maxV);
   return NormalizeDouble(lots, 2);
  }

void CloseAllOrders()
  {
   for(int i = OrdersTotal()-1; i >= 0; i--) if(ord.SelectByIndex(i) && ord.Symbol() == _Symbol && ord.Magic() == InpMagic) trade.OrderDelete(ord.Ticket());
   for(int i = PositionsTotal()-1; i >= 0; i--) if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == InpMagic) trade.PositionClose(pos.Ticket());
  }

void TrailStop()
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   for(int i=PositionsTotal()-1; i>=0; i--)
      if(pos.SelectByIndex(i) && pos.Magic()==InpMagic && pos.Symbol()==_Symbol)
        {
         if(pos.PositionType()==POSITION_TYPE_BUY && bid-pos.PriceOpen()>TslTriggerPoints*_Point)
           { double sl=bid-(TslPoints*_Point); if(sl > pos.StopLoss() && sl!=0) trade.PositionModify(pos.Ticket(), sl, pos.TakeProfit()); }
         else if(pos.PositionType()==POSITION_TYPE_SELL && ask+(TslTriggerPoints*_Point)<pos.PriceOpen())
           { double sl = ask + (TslPoints * _Point); if(sl<pos.StopLoss() && sl!=0) trade.PositionModify(pos.Ticket(), sl, pos.TakeProfit()); }
        }
  }

//+------------------------------------------------------------------+
//| Trade Events                                                     |
//+------------------------------------------------------------------+
void CheckTradeEvents() { CheckNewPositions(); CheckClosedPositions(); CheckNewOrders(); CheckDeletedOrders(); }
void CheckNewPositions() { for(int i=PositionsTotal()-1; i>=0; i--) if(pos.SelectByIndex(i) && pos.Symbol()==_Symbol && pos.Magic()==InpMagic && !IsPositionTracked(pos.Ticket())) { AddTrackedPosition(pos.Ticket()); SendTelegramMessage("✅ Trade Opened: " + _Symbol + " " + (pos.PositionType()==0?"BUY":"SELL")); } }
void CheckClosedPositions() { for(int i=ArraySize(trackedPositions)-1; i>=0; i--) { bool f=false; for(int j=PositionsTotal()-1; j>=0; j--) if(pos.SelectByIndex(j) && pos.Ticket()==trackedPositions[i].ticket) { f=true; break; } if(!f) { SendTelegramMessage("💰 Trade Closed: " + IntegerToString(trackedPositions[i].ticket)); RemoveTrackedPosition(i); } } }
void CheckNewOrders() { for(int i=OrdersTotal()-1; i>=0; i--) if(ord.SelectByIndex(i) && ord.Symbol()==_Symbol && ord.Magic()==InpMagic && !IsOrderTracked(ord.Ticket())) { AddTrackedOrder(ord.Ticket()); SendTelegramMessage("📝 Order Set: " + IntegerToString(ord.Ticket())); } }
void CheckDeletedOrders() { for(int i=ArraySize(trackedOrders)-1; i>=0; i--) { bool f=false; for(int j=OrdersTotal()-1; j>=0; j--) if(ord.SelectByIndex(j) && ord.Ticket()==trackedOrders[i].ticket) { f=true; break; } if(!f) { SendTelegramMessage("🗑️ Order Removed: " + IntegerToString(trackedOrders[i].ticket)); RemoveTrackedOrder(i); } } }

//+------------------------------------------------------------------+
//| Tracking Management                                              |
//+------------------------------------------------------------------+
bool IsPositionTracked(ulong t) { for(int i=0; i<ArraySize(trackedPositions); i++) if(trackedPositions[i].ticket == t) return true; return false; }
bool IsOrderTracked(ulong t) { for(int i=0; i<ArraySize(trackedOrders); i++) if(trackedOrders[i].ticket == t) return true; return false; }
void AddTrackedPosition(ulong t) { int s=ArraySize(trackedPositions); ArrayResize(trackedPositions, s+1); trackedPositions[s].ticket=t; }
void AddTrackedOrder(ulong t) { int s=ArraySize(trackedOrders); ArrayResize(trackedOrders, s+1); trackedOrders[s].ticket=t; }
void RemoveTrackedPosition(int idx) { int s=ArraySize(trackedPositions); for(int i=idx; i<s-1; i++) trackedPositions[i]=trackedPositions[i+1]; ArrayResize(trackedPositions, s-1); }
void RemoveTrackedOrder(int idx) { int s=ArraySize(trackedOrders); for(int i=idx; i<s-1; i++) trackedOrders[i]=trackedOrders[i+1]; ArrayResize(trackedOrders, s-1); }

//+------------------------------------------------------------------+
//| Dashboard & Utils                                                |
//+------------------------------------------------------------------+
void CreateDashboard() { ObjectCreate(0, DASH_BG_NAME, OBJ_RECTANGLE_LABEL, 0, 0, 0); ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_XDISTANCE, dashX); ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_YDISTANCE, dashY); ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_XSIZE, dashWidth); ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_YSIZE, dashHeight); ObjectSetInteger(0, DASH_BG_NAME, OBJPROP_BGCOLOR, clrDashBg); CreateLabel(DASH_TITLE_NAME, "COEUR DE MILLIARDAIRE", dashX + 10, dashY + 8, 11, clrDashTitle, "Impact"); CreateLabel(DASH_VAL_BALANCE, "0.00", dashX + 140, dashY + 50, 10, clrDashText, "Consolas"); CreateLabel(DASH_VAL_EQUITY, "0.00", dashX + 140, dashY + 82, 10, clrDashText, "Consolas"); CreateLabel(DASH_VAL_PROFIT, "0.00", dashX + 140, dashY + 114, 10, clrDashText, "Consolas"); CreateLabel(DASH_VAL_DAY_PROFIT, "0.00", dashX + 140, dashY + 146, 10, clrDashText, "Consolas"); CreateLabel(DASH_VAL_LIFETIME, "0.00", dashX + 140, dashY + 178, 10, clrDashText, "Consolas"); CreateLabel(DASH_VAL_MSG, "SYSTEME PRET", dashX + 65, dashY + 225, 8, clrDashText, "Segoe UI"); CreateLabel(DASH_VAL_MODE, "MODE: NORMAL", dashX + 160, dashY + 10, 8, clrGold, "Impact"); CreateLabel(DASH_VAL_EXPIRY, "0000.00.00", dashX + 160, dashY + 210, 8, clrDashText, "Consolas"); }
void CreateLabel(string n, string t, int x, int y, int s, color c, string f="Trebuchet MS") { ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0); ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x); ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y); ObjectSetString(0, n, OBJPROP_TEXT, t); ObjectSetString(0, n, OBJPROP_FONT, f); ObjectSetInteger(0, n, OBJPROP_FONTSIZE, s); ObjectSetInteger(0, n, OBJPROP_COLOR, c); }
void UpdateDashboard() { ObjectSetString(0, DASH_VAL_BALANCE, OBJPROP_TEXT, DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2)); ObjectSetString(0, DASH_VAL_EQUITY, OBJPROP_TEXT, DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2)); ObjectSetString(0, DASH_VAL_PROFIT, OBJPROP_TEXT, DoubleToString(AccountInfoDouble(ACCOUNT_PROFIT), 2)); ObjectSetString(0, DASH_VAL_DAY_PROFIT, OBJPROP_TEXT, DoubleToString(GetDailyProfit(), 2)); ObjectSetString(0, DASH_VAL_LIFETIME, OBJPROP_TEXT, DoubleToString(GetLifetimeProfit(), 2)); ObjectSetString(0, DASH_VAL_EXPIRY, OBJPROP_TEXT, TimeToString(CurrentExpirationDate, TIME_DATE)); ObjectSetString(0, DASH_VAL_MSG, OBJPROP_TEXT, RemoteAdminMsg); ChartRedraw(); }
void DeleteDashboard() { ObjectsDeleteAll(0, "DASH_"); ChartRedraw(); }
double GetDailyProfit() { double p=0; if(HistorySelect(iTime(_Symbol, PERIOD_D1, 0), TimeCurrent())) for(int i=0; i<HistoryDealsTotal(); i++) { ulong t=HistoryDealGetTicket(i); if(HistoryDealGetInteger(t, DEAL_MAGIC)==InpMagic) p+=HistoryDealGetDouble(t, DEAL_PROFIT)+HistoryDealGetDouble(t, DEAL_COMMISSION)+HistoryDealGetDouble(t, DEAL_SWAP); } return p; }
double GetLifetimeProfit() { double p=0; if(HistorySelect(0, TimeCurrent())) for(int i=0; i<HistoryDealsTotal(); i++) { ulong t=HistoryDealGetTicket(i); if(HistoryDealGetInteger(t, DEAL_MAGIC)==InpMagic) p+=HistoryDealGetDouble(t, DEAL_PROFIT)+HistoryDealGetDouble(t, DEAL_COMMISSION)+HistoryDealGetDouble(t, DEAL_SWAP); } return p; }

//+------------------------------------------------------------------+
//| Telegram & Auth                                                  |
//+------------------------------------------------------------------+
void SendTelegramMessage(string t) { if(TelegramToken=="" || TelegramChatID=="") return; string u = "https://api.telegram.org/bot"+TelegramToken+"/sendMessage", p = "chat_id="+TelegramChatID+"&text="+UrlEncode(t)+"&parse_mode=Markdown"; uchar d[], r[]; string h; int ds = StringToCharArray(p, d, 0, WHOLE_ARRAY, CP_UTF8)-1; if(ds>0) ArrayResize(d, ds); WebRequest("POST", u, "Content-Type: application/x-www-form-urlencoded\r\n", 2000, d, r, h); }
string UrlEncode(string t) { string res = ""; uchar a[]; StringToCharArray(t, a, 0, WHOLE_ARRAY, CP_UTF8); for(int i=0; i<ArraySize(a)-1; i++) if((a[i]>='0'&&a[i]<='9')||(a[i]>='a'&&a[i]<='z')||(a[i]>='A'&&a[i]<='Z')) res+=CharToString(a[i]); else res+=StringFormat("%%%02X", a[i]); return res; }
void OnTimer() { if(!IsTelegramActive) return; CheckAuthorization(); FetchTelegramUpdates(); }
bool VerifyWebRequest() { uchar d[], r[]; string h; return WebRequest("GET", "https://api.telegram.org", (string)NULL, 2000, d, r, h) != -1; }
void FetchTelegramUpdates() { if(TelegramToken=="") return; string u = "https://api.telegram.org/bot"+TelegramToken+"/getUpdates?offset="+IntegerToString(LastUpdateID+1)+"&timeout=1"; uchar d[], r[]; string h; if(WebRequest("GET", u, (string)NULL, 1500, d, r, h)==200) ProcessTelegramResponse(CharArrayToString(r,0,WHOLE_ARRAY,CP_UTF8)); }
void ProcessTelegramResponse(string j) { int uP=0; while((uP=StringFind(j, "{\"update_id\":", uP))!=-1) { int iI=StringFind(j, "\"update_id\":", uP), eI=StringFind(j, ",", iI); LastUpdateID=StringToInteger(StringSubstr(j, iI+12, eI-(iI+12))); uP=iI+1; } }
void CheckAuthorization() { IsAuthorized = (FileIsExist("auth_"+IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN))+".dat", FILE_COMMON) || !RequireAuthorization); }
void LoadPerformanceLimits() {} void LoadExpiration() {}
