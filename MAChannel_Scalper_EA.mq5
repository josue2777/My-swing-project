//+------------------------------------------------------------------+
//|                                        MAChannel_Scalper_EA.mq5 |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "EA de Scalping M1 XAUUSD base sur un Canal de Moyennes Mobiles"
#property description "Conditions d'Achat : Bar touching Lower MA & Close > Upper MA + MAs orientees a la hausse. Entree sur cassure du High de la bar."
#property description "Conditions de Vente : Bar touching Upper MA & Close < Lower MA + MAs orientees a la baisse. Entree sur cassure du Low de la bar."
#property description "SL au plus bas/haut de la bar de signal. TP a 2-3 largeurs de canal."

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_ENTRY_MODE
{
   ENTRY_MODE_PENDING_STOP, // Ordres Suspendus (Buy Stop / Sell Stop)
   ENTRY_MODE_MARKET_BREAKOUT // Execution au Marché à la Cassure
};

//--- Inputs
input group "=== Paramètres du Canal de Moyennes Mobiles ==="
input int                  InpUpperMAPeriod   = 20;             // Période MA Supérieure / High
input ENUM_MA_METHOD       InpUpperMAMethod   = MODE_EMA;       // Méthode MA Supérieure
input ENUM_APPLIED_PRICE   InpUpperMAPrice    = PRICE_HIGH;     // Prix Appliqué MA Supérieure
input int                  InpLowerMAPeriod   = 20;             // Période MA Inférieure / Low
input ENUM_MA_METHOD       InpLowerMAMethod   = MODE_EMA;       // Méthode MA Inférieure
input ENUM_APPLIED_PRICE   InpLowerMAPrice    = PRICE_LOW;      // Prix Appliqué MA Inférieure

input group "=== Execution & Gestion des Ordres ==="
input ENUM_ENTRY_MODE      InpEntryMode       = ENTRY_MODE_PENDING_STOP; // Mode d'Entrée
input double               InpChannelTPMult   = 2.5;            // Multiplicateur TP (Largeurs de Canal 2.0 - 3.0)
input double               InpBreakoutBuffer  = 10.0;           // Buffer de Cassure en Points
input bool                 InpUseTrailingStop = true;           // Activer le Trailing Stop
input double               InpTrailingStep    = 0.5;            // Trailing Stop (en Multiplicateur de Canal)

input group "=== Gestion des Risques ==="
input ulong                InpMagicNumber     = 555888;         // Magic Number
input double               InpFixedLot        = 0.01;           // Lot Fixe (Si Gestion auto désactivée)
input bool                 InpUseAutoLot      = true;           // Utiliser le Lot Automatique basé sur le Solde
input double               InpRiskPercent     = 1.0;            // % de Risque par Trade (Si AutoLot actif)

//--- Global Variables
CTrade         trade;
int            handle_upper_ma = INVALID_HANDLE;
int            handle_lower_ma = INVALID_HANDLE;
datetime       last_signal_time = 0;

struct SSignalState
{
   bool     valid;
   int      type;          // 1 = Buy, -1 = Sell
   double   signal_high;
   double   signal_low;
   double   channel_width;
   datetime bar_time;
};

SSignalState active_signal;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);

   // Set filling type dynamically
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Initialize Moving Average Indicator Handles
   handle_upper_ma = iMA(_Symbol, _Period, InpUpperMAPeriod, 0, InpUpperMAMethod, InpUpperMAPrice);
   handle_lower_ma = iMA(_Symbol, _Period, InpLowerMAPeriod, 0, InpLowerMAMethod, InpLowerMAPrice);

   if(handle_upper_ma == INVALID_HANDLE || handle_lower_ma == INVALID_HANDLE)
   {
      Print("Erreur lors de la création des handles de moyennes mobiles.");
      return(INIT_FAILED);
   }

   ZeroMemory(active_signal);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(handle_upper_ma != INVALID_HANDLE) IndicatorRelease(handle_upper_ma);
   if(handle_lower_ma != INVALID_HANDLE) IndicatorRelease(handle_lower_ma);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Manage existing positions and pending orders invalidation
   ManageOpenPositions();
   ManagePendingOrders();

   // Check for new signal on candle close
   datetime current_bar_time = iTime(_Symbol, _Period, 0);
   if(current_bar_time != last_signal_time)
   {
      CheckSignalConditions();
      last_signal_time = current_bar_time;
   }

   // Market Breakout Execution if selected
   if(InpEntryMode == ENTRY_MODE_MARKET_BREAKOUT && active_signal.valid)
   {
      CheckMarketBreakoutEntry();
   }
}

//+------------------------------------------------------------------+
//| Check MA Channel Signal Conditions on Completed Candle (Index 1) |
//+------------------------------------------------------------------+
void CheckSignalConditions()
{
   double upper_ma[];
   double lower_ma[];
   MqlRates rates[];

   ArraySetAsSeries(upper_ma, true);
   ArraySetAsSeries(lower_ma, true);
   ArraySetAsSeries(rates, true);

   if(CopyBuffer(handle_upper_ma, 0, 1, 3, upper_ma) < 3) return;
   if(CopyBuffer(handle_lower_ma, 0, 1, 3, lower_ma) < 3) return;
   if(CopyRates(_Symbol, _Period, 1, 3, rates) < 3) return;

   // Index 0 in copied buffers corresponds to bar 1 (completed bar)
   // Index 1 corresponds to bar 2
   double close1     = rates[0].close;
   double high1      = rates[0].high;
   double low1       = rates[0].low;
   datetime time1    = rates[0].time;

   double upper_ma1  = upper_ma[0];
   double upper_ma2  = upper_ma[1];

   double lower_ma1  = lower_ma[0];
   double lower_ma2  = lower_ma[1];

   // Check Slopes
   bool is_upper_ma_up   = (upper_ma1 > upper_ma2);
   bool is_lower_ma_up   = (lower_ma1 > lower_ma2);
   bool is_upper_ma_down = (upper_ma1 < upper_ma2);
   bool is_lower_ma_down = (lower_ma1 < lower_ma2);

   bool all_mas_up   = (is_upper_ma_up && is_lower_ma_up);
   bool all_mas_down = (is_upper_ma_down && is_lower_ma_down);

   double channel_width = MathAbs(upper_ma1 - lower_ma1);
   if(channel_width <= 0) return;

   // BUY Signal Condition:
   // 1. Touches lower channel (Low <= Lower MA)
   // 2. Closes above upper channel (Close > Upper MA)
   // 3. Both MAs pointing upwards
   if(low1 <= lower_ma1 && close1 > upper_ma1 && all_mas_up)
   {
      // Cancel previous opposite pending orders or outdated signals
      CancelPendingOrders();

      active_signal.valid = true;
      active_signal.type = 1;
      active_signal.signal_high = high1;
      active_signal.signal_low = low1;
      active_signal.channel_width = channel_width;
      active_signal.bar_time = time1;

      PrintFormat("[SIGNAL ACHAT] Bar Time: %s, High: %.5f, Low: %.5f, Width: %.5f",
                  TimeToString(time1), high1, low1, channel_width);

      if(InpEntryMode == ENTRY_MODE_PENDING_STOP)
      {
         PlacePendingOrder(1);
      }
   }
   // SELL Signal Condition:
   // 1. Touches upper channel (High >= Upper MA)
   // 2. Closes below lower channel (Close < Lower MA)
   // 3. Both MAs pointing downwards
   else if(high1 >= upper_ma1 && close1 < lower_ma1 && all_mas_down)
   {
      CancelPendingOrders();

      active_signal.valid = true;
      active_signal.type = -1;
      active_signal.signal_high = high1;
      active_signal.signal_low = low1;
      active_signal.channel_width = channel_width;
      active_signal.bar_time = time1;

      PrintFormat("[SIGNAL VENTE] Bar Time: %s, High: %.5f, Low: %.5f, Width: %.5f",
                  TimeToString(time1), high1, low1, channel_width);

      if(InpEntryMode == ENTRY_MODE_PENDING_STOP)
      {
         PlacePendingOrder(-1);
      }
   }
}

//+------------------------------------------------------------------+
//| Place Pending Buy Stop or Sell Stop Order                        |
//+------------------------------------------------------------------+
void PlacePendingOrder(int type)
{
   if(HasOpenPosition()) return;

   double lot = CalculateLotSize(active_signal.type, active_signal.signal_high, active_signal.signal_low);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(type == 1) // Buy Stop
   {
      double entry_price = active_signal.signal_high + (InpBreakoutBuffer * point);
      double sl = active_signal.signal_low;
      double tp = entry_price + (active_signal.channel_width * InpChannelTPMult);

      entry_price = NormalizeDouble(entry_price, _Digits);
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(trade.BuyStop(lot, entry_price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "MA Channel BuyStop"))
      {
         PrintFormat("Ordre Buy Stop placé à %.5f, SL: %.5f, TP: %.5f", entry_price, sl, tp);
      }
   }
   else if(type == -1) // Sell Stop
   {
      double entry_price = active_signal.signal_low - (InpBreakoutBuffer * point);
      double sl = active_signal.signal_high;
      double tp = entry_price - (active_signal.channel_width * InpChannelTPMult);

      entry_price = NormalizeDouble(entry_price, _Digits);
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(trade.SellStop(lot, entry_price, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "MA Channel SellStop"))
      {
         PrintFormat("Ordre Sell Stop placé à %.5f, SL: %.5f, TP: %.5f", entry_price, sl, tp);
      }
   }
}

//+------------------------------------------------------------------+
//| Check Market Breakout Entry Mode                                 |
//+------------------------------------------------------------------+
void CheckMarketBreakoutEntry()
{
   if(!active_signal.valid || HasOpenPosition()) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(active_signal.type == 1) // Buy Breakout
   {
      double target_breakout = active_signal.signal_high + (InpBreakoutBuffer * point);
      if(ask >= target_breakout)
      {
         double sl = active_signal.signal_low;
         double tp = ask + (active_signal.channel_width * InpChannelTPMult);
         double lot = CalculateLotSize(1, active_signal.signal_high, active_signal.signal_low);

         sl = NormalizeDouble(sl, _Digits);
         tp = NormalizeDouble(tp, _Digits);

         if(trade.Buy(lot, _Symbol, ask, sl, tp, "MA Channel Market Buy"))
         {
            PrintFormat("Achat au marché exécuté à %.5f sur cassure du High (%.5f)", ask, active_signal.signal_high);
            active_signal.valid = false;
         }
      }
      else if(bid < active_signal.signal_low) // Signal invalidated before entry
      {
         Print("Signal d'achat annulé : le prix a franchi le plus bas de la bougie de signal.");
         active_signal.valid = false;
      }
   }
   else if(active_signal.type == -1) // Sell Breakout
   {
      double target_breakout = active_signal.signal_low - (InpBreakoutBuffer * point);
      if(bid <= target_breakout)
      {
         double sl = active_signal.signal_high;
         double tp = bid - (active_signal.channel_width * InpChannelTPMult);
         double lot = CalculateLotSize(-1, active_signal.signal_high, active_signal.signal_low);

         sl = NormalizeDouble(sl, _Digits);
         tp = NormalizeDouble(tp, _Digits);

         if(trade.Sell(lot, _Symbol, bid, sl, tp, "MA Channel Market Sell"))
         {
            PrintFormat("Vente au marché exécutée à %.5f sur cassure du Low (%.5f)", bid, active_signal.signal_low);
            active_signal.valid = false;
         }
      }
      else if(ask > active_signal.signal_high) // Signal invalidated before entry
      {
         Print("Signal de vente annulé : le prix a franchi le plus haut de la bougie de signal.");
         active_signal.valid = false;
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Pending Orders (Check Invalidation Rule)                  |
//+------------------------------------------------------------------+
void ManagePendingOrders()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber || OrderGetString(ORDER_SYMBOL) != _Symbol)
            continue;

         ENUM_ORDER_TYPE order_type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         // Invalidation rule for Buy Stop: if price breaks below signal bar low
         if(order_type == ORDER_TYPE_BUY_STOP && active_signal.valid && active_signal.type == 1)
         {
            if(bid < active_signal.signal_low)
            {
               trade.OrderDelete(ticket);
               active_signal.valid = false;
               Print("Ordre Buy Stop annulé : le prix a franchi le plus bas de la barre de signal.");
            }
         }
         // Invalidation rule for Sell Stop: if price breaks above signal bar high
         else if(order_type == ORDER_TYPE_SELL_STOP && active_signal.valid && active_signal.type == -1)
         {
            if(ask > active_signal.signal_high)
            {
               trade.OrderDelete(ticket);
               active_signal.valid = false;
               Print("Ordre Sell Stop annulé : le prix a franchi le plus haut de la barre de signal.");
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Manage Open Positions (Trailing Stop and Signal Invalidation)    |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber || PositionGetString(POSITION_SYMBOL) != _Symbol)
            continue;

         ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
         double current_sl = PositionGetDouble(POSITION_SL);
         double current_tp = PositionGetDouble(POSITION_TP);
         double current_price = (pos_type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         // Dynamic Trailing Stop based on channel width
         if(InpUseTrailingStop && active_signal.channel_width > 0)
         {
            double trail_dist = active_signal.channel_width * InpTrailingStep;
            if(pos_type == POSITION_TYPE_BUY)
            {
               double new_sl = current_price - trail_dist;
               new_sl = NormalizeDouble(new_sl, _Digits);
               if(new_sl > current_sl + SymbolInfoDouble(_Symbol, SYMBOL_POINT) && new_sl < current_price)
               {
                  trade.PositionModify(ticket, new_sl, current_tp);
               }
            }
            else if(pos_type == POSITION_TYPE_SELL)
            {
               double new_sl = current_price + trail_dist;
               new_sl = NormalizeDouble(new_sl, _Digits);
               if((current_sl == 0 || new_sl < current_sl - SymbolInfoDouble(_Symbol, SYMBOL_POINT)) && new_sl > current_price)
               {
                  trade.PositionModify(ticket, new_sl, current_tp);
               }
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Cancel existing pending orders for this EA                       |
//+------------------------------------------------------------------+
void CancelPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagicNumber && OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            trade.OrderDelete(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Check if position is currently open for this EA                  |
//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetString(POSITION_SYMBOL) == _Symbol)
            return true;
      }
   }
   return false;
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk or Fixed Lot                    |
//+------------------------------------------------------------------+
double CalculateLotSize(int type, double signal_high, double signal_low)
{
   if(!InpUseAutoLot) return InpFixedLot;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double risk_amount = balance * (InpRiskPercent / 100.0);

   double sl_distance = MathAbs(signal_high - signal_low);
   if(sl_distance <= 0) return InpFixedLot;

   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tick_value <= 0 || tick_size <= 0) return InpFixedLot;

   double risk_per_lot = (sl_distance / tick_size) * tick_value;
   if(risk_per_lot <= 0) return InpFixedLot;

   double lot = risk_amount / risk_per_lot;

   double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / step_lot) * step_lot;
   lot = MathMax(min_lot, MathMin(max_lot, lot));

   return lot;
}
//+------------------------------------------------------------------+
