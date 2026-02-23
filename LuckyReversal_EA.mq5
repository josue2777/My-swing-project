//+------------------------------------------------------------------+
//|                                           LuckyReversal_EA.mq5 |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs Indicator
input string   InpIndiName   = "lucky-reversal"; // Indicator Name
input int      InpBuyBuffer  = 0;                // Buy Signal Buffer Index
input int      InpSellBuffer = 1;                // Sell Signal Buffer Index
input int      InpSupBuffer  = 2;                // Support Zone Buffer Index
input int      InpResBuffer  = 3;                // Resistance Zone Buffer Index

//--- Inputs Trade Management
input double   InpTP4Interval  = 0.01500;  // TP4 Search Interval (Price)
input double   InpFallbackDist = 0.00310;  // Fallback Distance (Price)
input int      InpMagic        = 654321;   // Magic Number
input int      InpStopLossPips = 300;      // Fixed Stop Loss in Pips (fallback)

//--- Global Variables
CTrade         trade;
int            handle_lucky;
int            lucky_signal = 0; // 1: Buy, -1: Sell
double         last_close = 0;

// Struct to store SR Zones from Indicator
struct SRZone {
    double top;
    double bottom;
    bool isSupport;
};

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);

    handle_lucky = iCustom(_Symbol, _Period, InpIndiName);
    if(handle_lucky == INVALID_HANDLE)
    {
        Print("Error creating lucky-reversal handle");
        return(INIT_FAILED);
    }

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    IndicatorRelease(handle_lucky);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Manage existing trades
    ManageTrades();

    // Check for new bar or specific signal logic
    if(!isNewBar()) return;

    // Detect Signals and Zones
    DetectSignals();

    // Check for entry
    CheckEntry();

    last_close = iClose(_Symbol, _Period, 1);
}

//+------------------------------------------------------------------+
//| Check for new bar                                                |
//+------------------------------------------------------------------+
bool isNewBar()
{
    static datetime last_time = 0;
    datetime current_time = iTime(_Symbol, _Period, 0);
    if(current_time != last_time)
    {
        last_time = current_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Detect Signals from Indicator                                    |
//+------------------------------------------------------------------+
void DetectSignals()
{
    double buy_buf[], sell_buf[];
    ArraySetAsSeries(buy_buf, true);
    ArraySetAsSeries(sell_buf, true);

    if(CopyBuffer(handle_lucky, InpBuyBuffer, 1, 1, buy_buf) <= 0) return;
    if(CopyBuffer(handle_lucky, InpSellBuffer, 1, 1, sell_buf) <= 0) return;

    lucky_signal = 0;
    if(buy_buf[0] != 0 && buy_buf[0] != EMPTY_VALUE)
        lucky_signal = 1;
    else if(sell_buf[0] != 0 && sell_buf[0] != EMPTY_VALUE)
        lucky_signal = -1;
}

//+------------------------------------------------------------------+
//| Get Lot Size based on Balance                                    |
//+------------------------------------------------------------------+
double GetLotSize()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 1000)   return 0.01;
    if(balance <= 5000)   return 0.03;
    if(balance <= 13000)  return 0.05;
    if(balance <= 50000)  return 0.1;
    if(balance <= 150000) return 0.5;
    if(balance <= 350000) return 1.0;
    return 3.0;
}

//+------------------------------------------------------------------+
//| Get Trade Count based on Balance                                 |
//+------------------------------------------------------------------+
int GetTradeCount()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 300)    return 2;
    if(balance <= 5000)   return 4;
    if(balance <= 15000)  return 6;
    if(balance <= 75000)  return 10;
    if(balance <= 400000) return 16;
    return 20;
}

//+------------------------------------------------------------------+
//| Check Entry Conditions                                           |
//+------------------------------------------------------------------+
void CheckEntry()
{
    if(lucky_signal == 0) return;

    double close1 = iClose(_Symbol, _Period, 1);

    // Read Zones
    double sup_buf[], res_buf[];
    ArraySetAsSeries(sup_buf, true);
    ArraySetAsSeries(res_buf, true);

    bool inZone = false;
    SRZone zone;

    if(lucky_signal == 1)
    {
        if(CopyBuffer(handle_lucky, InpSupBuffer, 1, 1, sup_buf) > 0)
        {
            if(sup_buf[0] != 0 && sup_buf[0] != EMPTY_VALUE)
            {
                // Price is near support zone?
                // Lucky reversal zones are often single values representing the line/box level
                if(MathAbs(close1 - sup_buf[0]) < InpTP4Interval) // Example proximity check
                {
                    inZone = true;
                    zone.top = sup_buf[0];
                    zone.bottom = sup_buf[0] - InpFallbackDist; // Estimate width
                    zone.isSupport = true;
                }
            }
        }
    }
    else if(lucky_signal == -1)
    {
        if(CopyBuffer(handle_lucky, InpResBuffer, 1, 1, res_buf) > 0)
        {
            if(res_buf[0] != 0 && res_buf[0] != EMPTY_VALUE)
            {
                if(MathAbs(close1 - res_buf[0]) < InpTP4Interval)
                {
                    inZone = true;
                    zone.top = res_buf[0] + InpFallbackDist;
                    zone.bottom = res_buf[0];
                    zone.isSupport = false;
                }
            }
        }
    }

    if(inZone)
    {
        ExecuteTrade(lucky_signal, zone);
    }
}

//+------------------------------------------------------------------+
//| Execute Trade with Multi-TP/SL                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal, SRZone &zone)
{
    double price = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double sl = 0;
    double tp1 = 0, tp2 = 0, tp3 = 0, tp4 = 0;

    // SL calculation
    if(signal == 1)
        sl = price - InpStopLossPips * _Point;
    else
        sl = price + InpStopLossPips * _Point;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dist = InpFallbackDist;

    // Determine TPs based on tiers
    if(balance <= 5000)
    {
        tp1 = (signal == 1) ? price + dist : price - dist;
    }
    else if(balance <= 400000)
    {
        tp1 = (signal == 1) ? price + dist * 0.5 : price - dist * 0.5;
        tp2 = (signal == 1) ? price + dist * 0.8 : price - dist * 0.8;
        tp3 = (signal == 1) ? price + dist : price - dist;
    }
    else
    {
        tp1 = (signal == 1) ? price + dist * 0.5 : price - dist * 0.5;
        tp2 = (signal == 1) ? price + dist * 0.7 : price - dist * 0.7;
        tp3 = (signal == 1) ? price + dist * 0.9 : price - dist * 0.9;
        tp4 = (signal == 1) ? price + dist : price - dist;
    }

    int count = GetTradeCount();
    double lot = GetLotSize();

    for(int i=0; i<count; i++)
    {
        double current_tp = 0;
        int level = 0;
        if(balance <= 5000) { current_tp = tp1; level = 1; }
        else if(balance <= 400000)
        {
            if(i < count * 0.5) { current_tp = tp1; level = 1; }
            else if(i < count * 0.8) { current_tp = tp2; level = 2; }
            else { current_tp = tp3; level = 3; }
        }
        else
        {
            if(i < count * 0.5) { current_tp = tp1; level = 1; }
            else if(i < count * 0.7) { current_tp = tp2; level = 2; }
            else if(i < count * 0.9) { current_tp = tp3; level = 3; }
            else { current_tp = tp4; level = 4; }
        }

        string comment = StringFormat("TPLevel:%d", level);
        if(signal == 1)
            trade.Buy(lot, _Symbol, price, sl, current_tp, comment);
        else
            trade.Sell(lot, _Symbol, price, sl, current_tp, comment);
    }
}

//+------------------------------------------------------------------+
//| Manage Ongoing Trades                                            |
//+------------------------------------------------------------------+
void ManageTrades()
{
    bool level1_exists = false;

    // First pass: identify which levels are still active
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "TPLevel:1") >= 0) level1_exists = true;
        }
    }

    // Second pass: trailing and exit
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            int type = (int)PositionGetInteger(POSITION_TYPE);

            // Adverse signal exit
            if((type == POSITION_TYPE_BUY && lucky_signal == -1) || (type == POSITION_TYPE_SELL && lucky_signal == 1))
            {
                trade.PositionClose(ticket);
                continue;
            }

            // Trailing Logic: SL to Break-Even after TP1 hit
            if(!level1_exists)
            {
                if((type == POSITION_TYPE_BUY && current_sl < entry) || (type == POSITION_TYPE_SELL && (current_sl > entry || current_sl == 0)))
                {
                    trade.PositionModify(ticket, entry, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}
//+------------------------------------------------------------------+
