//+------------------------------------------------------------------+
//|                                           Gann50_EA.mq5           |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs
input int      InpMagic = 222333;         // Magic Number
input int      InpStopLossPips = 300;     // Default SL in Pips (if no better level)

//--- Global Variables
CTrade         trade;
double         yesterday_high = 0;
double         yesterday_low = 0;
double         gann_50 = 0;
bool           gann_50_touched_from_above = false;
bool           gann_50_touched_from_below = false;
datetime       last_trade_day = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
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
    ManageTrades();
    UpdateGannLevels();
    CheckEntry();
}

//+------------------------------------------------------------------+
//| Check Entry Conditions (50% Rebound)                             |
//+------------------------------------------------------------------+
void CheckEntry()
{
    if(gann_50 == 0) return;

    double close0 = iClose(_Symbol, _Period, 0);
    double high0  = iHigh(_Symbol, _Period, 0);
    double low0   = iLow(_Symbol, _Period, 0);

    // Check for touch
    if(low0 <= gann_50 && iClose(_Symbol, _Period, 1) > gann_50)
        gann_50_touched_from_above = true;
    if(high0 >= gann_50 && iClose(_Symbol, _Period, 1) < gann_50)
        gann_50_touched_from_below = true;

    // Detect New Bar for confirming signal
    static datetime last_time = 0;
    datetime current_time = iTime(_Symbol, _Period, 0);
    if(current_time != last_time)
    {
        double close1 = iClose(_Symbol, _Period, 1);
        double open1  = iOpen(_Symbol, _Period, 1);

        datetime current_day = iTime(_Symbol, PERIOD_D1, 0);

        // Bullish Rebound confirmation
        if(gann_50_touched_from_above && close1 > gann_50 && close1 > open1 && last_trade_day != current_day)
        {
            ExecuteTrade(1); // Buy
            gann_50_touched_from_above = false;
            last_trade_day = current_day;
        }
        // Bearish Rebound confirmation
        else if(gann_50_touched_from_below && close1 < gann_50 && close1 < open1 && last_trade_day != current_day)
        {
            ExecuteTrade(-1); // Sell
            gann_50_touched_from_below = false;
            last_trade_day = current_day;
        }

        // Reset touches if price moves too far or a new day starts
        // (Resetting on new bar for simplicity if not confirmed)
        if(close1 < gann_50 - (yesterday_high - yesterday_low)*0.1) gann_50_touched_from_above = false;
        if(close1 > gann_50 + (yesterday_high - yesterday_low)*0.1) gann_50_touched_from_below = false;

        last_time = current_time;
    }
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
//| Manage Ongoing Trades                                            |
//+------------------------------------------------------------------+
void ManageTrades()
{
    bool level1_exists = false;

    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "L:1") >= 0) level1_exists = true;
        }
    }

    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            string comment = PositionGetString(POSITION_COMMENT);

            // Trailing Logic: BE after TP1 hit
            if(!level1_exists && StringFind(comment, "L:1") < 0)
            {
                if(MathAbs(current_sl - entry) > _Point)
                {
                    trade.PositionModify(ticket, entry, PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Execute Trade with Multi-TP/SL                                   |
//+------------------------------------------------------------------+
void ExecuteTrade(int signal)
{
    double price = (signal == 1) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double range = yesterday_high - yesterday_low;
    if(range <= 0) return;

    double sl = (signal == 1) ? gann_50 - range * 0.125 : gann_50 + range * 0.125;
    double tp1 = (signal == 1) ? gann_50 + range * 0.125 : gann_50 - range * 0.125;
    double tp2 = (signal == 1) ? gann_50 + range * 0.250 : gann_50 - range * 0.250;
    double tp3 = (signal == 1) ? gann_50 + range * 0.375 : gann_50 - range * 0.375;
    double tp4 = (signal == 1) ? yesterday_high : yesterday_low;

    int count = GetTradeCount();
    double lot = GetLotSize();

    for(int i=0; i<count; i++)
    {
        double current_tp = 0;
        int level = 0;

        if(i < count * 0.5) { current_tp = tp1; level = 1; }
        else if(i < count * 0.8) { current_tp = tp2; level = 2; }
        else if(i < count * 0.95) { current_tp = tp3; level = 3; }
        else { current_tp = tp4; level = 4; }

        string comment = StringFormat("Gann50 L:%d", level);
        if(signal == 1)
            trade.Buy(lot, _Symbol, price, sl, current_tp, comment);
        else
            trade.Sell(lot, _Symbol, price, sl, current_tp, comment);
    }
}

//+------------------------------------------------------------------+
//| Update Gann Levels from Yesterday's Range                        |
//+------------------------------------------------------------------+
void UpdateGannLevels()
{
    static datetime last_calc_day = 0;
    datetime current_day = iTime(_Symbol, PERIOD_D1, 0);

    if(current_day != last_calc_day)
    {
        MqlRates rates[];
        if(CopyRates(_Symbol, PERIOD_D1, 1, 1, rates) > 0)
        {
            yesterday_high = rates[0].high;
            yesterday_low = rates[0].low;
            gann_50 = (yesterday_high + yesterday_low) / 2.0;
            last_calc_day = current_day;
            PrintFormat("Gann Levels Updated: High=%.5f, Low=%.5f, 50%%=%.5f", yesterday_high, yesterday_low, gann_50);
        }
    }
}
//+------------------------------------------------------------------+
