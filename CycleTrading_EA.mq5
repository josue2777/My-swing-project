//+------------------------------------------------------------------+
//|                                             CycleTrading_EA.mq5   |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input ulong    InpMagic               = 334455;   // Magic Number
input double   InpLotSize             = 0.01;     // Lot Size
input int      InpPendingDistancePoints = 2000;   // Pending Order Distance (Points)
input int      InpTPDistancePoints    = 3000;     // Take Profit Distance (Points)
input bool     InpKeepOppositeOrder   = false;    // Keep Opposite Pending Order (Mode 2)

//--- Global Variables
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    SetFillingType();
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
    int positionsCount = GetPositionsCount();
    int ordersCount = GetOrdersCount();

    // Mode 1 (InpKeepOppositeOrder = false):
    // Delete opposite pending order as soon as one position is triggered.
    if(!InpKeepOppositeOrder && positionsCount > 0 && ordersCount > 0)
    {
        DeletePendingOrders();
        ordersCount = GetOrdersCount();
    }

    // Mode 2 (InpKeepOppositeOrder = true):
    // If a trade was closed (SL or TP) and we have no active positions left,
    // clean up any remaining pending orders before starting a new cycle.
    if(InpKeepOppositeOrder && positionsCount == 0 && ordersCount > 0)
    {
        DeletePendingOrders();
        ordersCount = GetOrdersCount();
    }

    // Start a new cycle when no open positions and no pending orders exist
    if(positionsCount == 0 && ordersCount == 0)
    {
        PlaceCycleOrders();
    }
}

//+------------------------------------------------------------------+
//| Set appropriate filling mode for CTrade                          |
//+------------------------------------------------------------------+
void SetFillingType()
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
//| Get count of active positions for this EA                        |
//+------------------------------------------------------------------+
int GetPositionsCount()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get count of active pending orders for this EA                   |
//+------------------------------------------------------------------+
int GetOrdersCount()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Delete all pending orders for this EA                            |
//+------------------------------------------------------------------+
void DeletePendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                if(!trade.OrderDelete(ticket))
                {
                    PrintFormat("Failed to delete pending order #%I64u, retcode=%uint", ticket, trade.ResultRetcode());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Place Buy Stop and Sell Stop pending orders                      |
//+------------------------------------------------------------------+
void PlaceCycleOrders()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if(ask <= 0 || bid <= 0)
        return;

    // Validate broker stops level distance
    long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int pendingDistance = InpPendingDistancePoints;
    if(stopsLevel > 0 && pendingDistance < stopsLevel)
    {
        pendingDistance = (int)stopsLevel;
        PrintFormat("Adjusting pending distance to broker minimum stops level: %d points", pendingDistance);
    }

    // Calculate current reference price
    double current_price = NormalizeDouble((ask + bid) / 2.0, _Digits);

    // Buy Stop parameters
    double buy_price = NormalizeDouble(current_price + pendingDistance * _Point, _Digits);
    double buy_sl    = current_price;
    double buy_tp    = NormalizeDouble(buy_price + InpTPDistancePoints * _Point, _Digits);

    // Sell Stop parameters
    double sell_price = NormalizeDouble(current_price - pendingDistance * _Point, _Digits);
    double sell_sl    = current_price;
    double sell_tp    = NormalizeDouble(sell_price - InpTPDistancePoints * _Point, _Digits);

    // Execute Buy Stop
    if(!trade.BuyStop(InpLotSize, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Cycle BuyStop"))
    {
        PrintFormat("BuyStop order failed, retcode=%uint", trade.ResultRetcode());
        return;
    }

    // Execute Sell Stop
    if(!trade.SellStop(InpLotSize, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Cycle SellStop"))
    {
        PrintFormat("SellStop order failed, retcode=%uint", trade.ResultRetcode());
        // Clean up Buy Stop if Sell Stop fails to maintain cycle integrity
        DeletePendingOrders();
    }
}
//+------------------------------------------------------------------+
