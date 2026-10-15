//+------------------------------------------------------------------+
//|                                              Breakout20_EA.mq5   |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input ulong    InpMagic            = 334455;   // Magic Number
input int      InpLookbackBars     = 20;       // Number of bars for High/Low identification
input int      InpRecalcBars       = 10;       // Refresh cycle (bars untouched)
input int      InpStopLossPoints   = 2000;     // Stop Loss in Points
input int      InpTakeProfitPoints = 3000;     // Take Profit in Points
input double   InpRiskPercent      = 3.0;      // Risk per trade (% of balance)

//--- Global Variables
CTrade         trade;
datetime       g_last_bar_time     = 0;
int            g_bars_since_setup  = 0;
bool           g_need_recalc       = true;
int            g_prev_pos_count    = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);

    // Set filling type dynamically according to symbol capabilities
    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((filling & SYMBOL_FILLING_FOK) != 0)
        trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if((filling & SYMBOL_FILLING_IOC) != 0)
        trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        trade.SetTypeFilling(ORDER_FILLING_RETURN);

    g_last_bar_time    = 0;
    g_bars_since_setup = 0;
    g_need_recalc      = true;
    g_prev_pos_count   = GetPositionCount();

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Calculate Lot Size based on 3% Risk of Balance                   |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 0) return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double risk_amount = balance * (InpRiskPercent / 100.0);

    double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

    if(tick_size <= 0 || tick_value <= 0 || point <= 0)
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double sl_ticks = (InpStopLossPoints * point) / tick_size;
    double risk_per_lot = sl_ticks * tick_value;

    if(risk_per_lot <= 0)
        return SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);

    double raw_lot = risk_amount / risk_per_lot;

    double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double lot_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(lot_step <= 0) lot_step = 0.01;

    double lot = MathFloor(raw_lot / lot_step) * lot_step;
    lot = MathMax(min_lot, MathMin(max_lot, lot));

    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Get count of active positions for this EA                        |
//+------------------------------------------------------------------+
int GetPositionCount()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == (long)InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Get count of active pending orders for this EA                   |
//+------------------------------------------------------------------+
int GetPendingOrderCount()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Delete all pending orders for this EA                            |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == (long)InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                trade.OrderDelete(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get Highest High and Lowest Low over lookback bars               |
//+------------------------------------------------------------------+
bool GetHighLow20(double &highest_high, double &lowest_low)
{
    highest_high = -DBL_MAX;
    lowest_low   = DBL_MAX;

    for(int i = 1; i <= InpLookbackBars; i++)
    {
        double h = iHigh(_Symbol, _Period, i);
        double l = iLow(_Symbol, _Period, i);

        if(h <= 0 || l <= 0) return false;

        if(h > highest_high) highest_high = h;
        if(l < lowest_low)   lowest_low   = l;
    }

    return (highest_high > 0 && lowest_low < DBL_MAX && highest_high > lowest_low);
}

//+------------------------------------------------------------------+
//| Recalculate High/Low and place new pending orders                |
//+------------------------------------------------------------------+
void RecalculateAndPlaceOrders()
{
    DeleteAllPendingOrders();

    if(GetPositionCount() > 0) return;

    double high_val = 0, low_val = 0;
    if(!GetHighLow20(high_val, low_val)) return;

    double lot = CalculateLotSize();
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

    // Adjust prices to satisfy broker stop level requirements if needed
    double buy_price = high_val;
    if(buy_price <= ask + stop_level)
        buy_price = ask + stop_level + point;

    double sell_price = low_val;
    if(sell_price >= bid - stop_level)
        sell_price = bid - stop_level - point;

    buy_price  = NormalizeDouble(buy_price, _Digits);
    sell_price = NormalizeDouble(sell_price, _Digits);

    double buy_sl  = NormalizeDouble(buy_price - InpStopLossPoints * point, _Digits);
    double buy_tp  = NormalizeDouble(buy_price + InpTakeProfitPoints * point, _Digits);

    double sell_sl = NormalizeDouble(sell_price + InpStopLossPoints * point, _Digits);
    double sell_tp = NormalizeDouble(sell_price - InpTakeProfitPoints * point, _Digits);

    trade.BuyStop(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Breakout20 Buy");
    trade.SellStop(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Breakout20 Sell");

    g_bars_since_setup = 0;
    g_need_recalc      = false;
}

//+------------------------------------------------------------------+
//| Trade transaction callback                                       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
    {
        ulong deal_ticket = trans.deal;
        if(HistoryDealSelect(deal_ticket))
        {
            long magic  = HistoryDealGetInteger(deal_ticket, DEAL_MAGIC);
            string sym  = HistoryDealGetString(deal_ticket, DEAL_SYMBOL);
            long entry  = HistoryDealGetInteger(deal_ticket, DEAL_ENTRY);

            if(magic == (long)InpMagic && sym == _Symbol)
            {
                // Position closed (SL, TP, or manual exit)
                if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
                {
                    g_need_recalc = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    int current_pos_count = GetPositionCount();

    // Secondary check for position closure
    if(g_prev_pos_count > 0 && current_pos_count == 0)
    {
        g_need_recalc = true;
    }
    g_prev_pos_count = current_pos_count;

    // Detect new bar
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    bool is_new_bar = (current_bar_time != g_last_bar_time);

    if(is_new_bar)
    {
        g_last_bar_time = current_bar_time;

        // If no open positions and pending orders exist, track elapsed candles
        if(current_pos_count == 0 && GetPendingOrderCount() > 0)
        {
            g_bars_since_setup++;
            if(g_bars_since_setup >= InpRecalcBars)
            {
                g_need_recalc = true;
            }
        }
    }

    // Execute recalculation if flag is set and no active position
    if(g_need_recalc && current_pos_count == 0)
    {
        RecalculateAndPlaceOrders();
    }
}
