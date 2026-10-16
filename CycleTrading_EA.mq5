//+------------------------------------------------------------------+
//|                                              CycleTrading_EA.mq5 |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Direction Enum
enum ENUM_TRADE_DIRECTION
{
   DIRECTION_BOTH = 0,      // Trader dans les 2 sens (Achat & Vente)
   DIRECTION_BUY_ONLY = 1,  // Achat uniquement
   DIRECTION_SELL_ONLY = 2  // Vente uniquement
};

//--- Inputs
input double               InpLotSize               = 0.01;            // Taille des lots
input int                  InpPendingDistancePoints = 3000;            // Distance des ordres en attente (points)
input int                  InpSLDistancePoints      = 2000;            // Distance du Stop loss (points)
input bool                 InpKeepOppositeOrder     = false;           // Activer Mode 2 (Garder ordre oppose pendant position)
input ENUM_TRADE_DIRECTION InpTradeDirection        = DIRECTION_BOTH;  // Direction du trading
input ulong                InpMagic                 = 112233;          // Magic Number

//--- Global Variables
CTrade trade;
bool   g_position_was_opened = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   ConfigureFillingMode();
   g_position_was_opened = false;
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   int active_positions = CountActivePositions();
   int pending_orders   = CountPendingOrders();

   // Track if a position has opened during the current cycle
   if(active_positions > 0)
   {
      g_position_was_opened = true;
   }

   // Mode 1: Delete opposite pending order immediately when a position opens
   if(!InpKeepOppositeOrder && active_positions > 0 && pending_orders > 0)
   {
      DeleteAllPendingOrders();
      pending_orders = CountPendingOrders();
   }

   // Mode 2: When position was opened and is now closed, delete any remaining pending orders
   if(InpKeepOppositeOrder && g_position_was_opened && active_positions == 0 && pending_orders > 0)
   {
      DeleteAllPendingOrders();
      pending_orders = CountPendingOrders();
      g_position_was_opened = false;
   }

   // If no active position and no pending orders, start a new cycle
   if(active_positions == 0 && pending_orders == 0)
   {
      g_position_was_opened = false;
      StartNewCycle();
   }
}

//+------------------------------------------------------------------+
//| Configure dynamic order filling mode                             |
//+------------------------------------------------------------------+
void ConfigureFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);
}

//+------------------------------------------------------------------+
//| Count active positions for this EA symbol & magic number         |
//+------------------------------------------------------------------+
int CountActivePositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Count pending orders for this EA symbol & magic number          |
//+------------------------------------------------------------------+
int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Delete all pending orders for this EA symbol & magic number      |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            trade.OrderDelete(ticket);
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Start a new cycle: calculate reference price and place orders    |
//+------------------------------------------------------------------+
void StartNewCycle()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0)
      return;

   // 1. Reference price = (Ask + Bid) / 2
   double ref_price = NormalizeDouble((ask + bid) / 2.0, _Digits);
   double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Place Buy Limit Order if allowed
   if(InpTradeDirection == DIRECTION_BOTH || InpTradeDirection == DIRECTION_BUY_ONLY)
   {
      double buy_price = NormalizeDouble(ref_price - InpPendingDistancePoints * point_size, _Digits);
      double buy_sl    = NormalizeDouble(buy_price - InpSLDistancePoints * point_size, _Digits);
      double buy_tp    = ref_price; // TP at initial reference price

      trade.BuyLimit(InpLotSize, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Cycle Trading Buy Limit");
   }

   // Place Sell Limit Order if allowed
   if(InpTradeDirection == DIRECTION_BOTH || InpTradeDirection == DIRECTION_SELL_ONLY)
   {
      double sell_price = NormalizeDouble(ref_price + InpPendingDistancePoints * point_size, _Digits);
      double sell_sl    = NormalizeDouble(sell_price + InpSLDistancePoints * point_size, _Digits);
      double sell_tp    = ref_price; // TP at initial reference price

      trade.SellLimit(InpLotSize, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Cycle Trading Sell Limit");
   }
}
//+------------------------------------------------------------------+
