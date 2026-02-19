//+------------------------------------------------------------------+
//|                                     SuperBollingerSR_EA.mq5       |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs SB
input int      InpSBPeriod = 12;          // SB Period
input double   InpSBMult   = 2.0;         // SB Multiplier

//--- Inputs SR
input int      InpSRLookback = 20;        // SR Lookback Period
input int      InpSRVolLen   = 2;         // Delta Volume Filter Length
input double   InpSRBoxWidth = 1.0;       // Adjust Box Width (ATR Mult)

//--- Inputs Trade
input double   InpTP4Interval = 0.01500;  // TP4 Search Interval (Price)
input double   InpFallbackDist = 0.00310; // Fallback Distance (Price)
input int      InpMagic = 123456;         // Magic Number

//--- Global Variables
CTrade         trade;
int            handle_atr, handle_sma_high, handle_sma_low;
double         sbt_s = 0;
color          sbt_c = CLR_NONE;
int            sbt_signal = 0; // 1: Buy, -1: Sell
double         last_close = 0;

// Struct to store SR Zones
struct SRZone {
    double top;
    double bottom;
    bool isSupport;
    bool isBroken;
    datetime time;
};

SRZone zones[];
int    zones_count = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);
    ArrayResize(zones, 0);
    handle_atr = iATR(_Symbol, _Period, 200);
    handle_sma_high = iMA(_Symbol, _Period, InpSBPeriod, 0, MODE_SMA, PRICE_HIGH);
    handle_sma_low = iMA(_Symbol, _Period, InpSBPeriod, 0, MODE_SMA, PRICE_LOW);

    if(handle_atr == INVALID_HANDLE || handle_sma_high == INVALID_HANDLE || handle_sma_low == INVALID_HANDLE)
    {
        Print("Error creating indicator handles");
        return(INIT_FAILED);
    }

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

    if(!isNewBar()) return;

    UpdateSB();
    UpdateSR();

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
//| Pivot Points Functions                                           |
//+------------------------------------------------------------------+
double PivotHigh(int period, int shift)
{
    double val = iHigh(_Symbol, _Period, shift + period);
    for(int i = 1; i <= period; i++)
    {
        if(iHigh(_Symbol, _Period, shift + period + i) > val || iHigh(_Symbol, _Period, shift + period - i) >= val)
            return -1;
    }
    return val;
}

double PivotLow(int period, int shift)
{
    double val = iLow(_Symbol, _Period, shift + period);
    for(int i = 1; i <= period; i++)
    {
        if(iLow(_Symbol, _Period, shift + period + i) < val || iLow(_Symbol, _Period, shift + period - i) <= val)
            return -1;
    }
    return val;
}

//+------------------------------------------------------------------+
//| Support and Resistance Logic                                     |
//+------------------------------------------------------------------+
void UpdateSR()
{
    int shift = 1;
    double ph = PivotHigh(InpSRLookback, shift);
    double pl = PivotLow(InpSRLookback, shift);

    // Delta Volume
    double vol = 0;
    if(iClose(_Symbol, _Period, shift) > iOpen(_Symbol, _Period, shift))
        vol = (double)iVolume(_Symbol, _Period, shift);
    else if(iClose(_Symbol, _Period, shift) < iOpen(_Symbol, _Period, shift))
        vol = -(double)iVolume(_Symbol, _Period, shift);

    // Vol filter
    double vol_hi = -DBL_MAX;
    double vol_lo = DBL_MAX;
    for(int i=0; i<InpSRVolLen; i++)
    {
        double v = 0;
        if(iClose(_Symbol, _Period, shift+i) > iOpen(_Symbol, _Period, shift+i))
            v = (double)iVolume(_Symbol, _Period, shift+i);
        else if(iClose(_Symbol, _Period, shift+i) < iOpen(_Symbol, _Period, shift+i))
            v = -(double)iVolume(_Symbol, _Period, shift+i);

        vol_hi = MathMax(vol_hi, v / 2.5);
        vol_lo = MathMin(vol_lo, v / 2.5);
    }

    double atr = 0;
    double buffer[];
    if(CopyBuffer(handle_atr, 0, shift, 1, buffer) > 0) atr = buffer[0];
    double width = atr * InpSRBoxWidth;

    // Support
    if(pl != -1 && vol > vol_hi)
    {
        zones_count++;
        ArrayResize(zones, zones_count);
        zones[zones_count-1].top = pl;
        zones[zones_count-1].bottom = pl - width;
        zones[zones_count-1].isSupport = true;
        zones[zones_count-1].isBroken = false;
        zones[zones_count-1].time = iTime(_Symbol, _Period, shift + InpSRLookback);
    }

    // Resistance
    if(ph != -1 && vol < vol_lo)
    {
        zones_count++;
        ArrayResize(zones, zones_count);
        zones[zones_count-1].top = ph + width;
        zones[zones_count-1].bottom = ph;
        zones[zones_count-1].isSupport = false;
        zones[zones_count-1].isBroken = false;
        zones[zones_count-1].time = iTime(_Symbol, _Period, shift + InpSRLookback);
    }

    // Update active zones (breakouts)
    double close1 = iClose(_Symbol, _Period, 1);
    double high1  = iHigh(_Symbol, _Period, 1);
    double low1   = iLow(_Symbol, _Period, 1);

    for(int i=0; i<zones_count; i++)
    {
        if(zones[i].isBroken) continue;

        if(zones[i].isSupport)
        {
            if(high1 < zones[i].bottom) // Breakout Support
                zones[i].isBroken = true;
        }
        else
        {
            if(low1 > zones[i].top) // Breakout Resistance
                zones[i].isBroken = true;
        }
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
//| Check Entry Conditions                                           |
//+------------------------------------------------------------------+
void CheckEntry()
{
    if(sbt_signal == 0) return;

    double close1 = iClose(_Symbol, _Period, 1);
    bool inZone = false;
    int zoneIdx = -1;

    for(int i=0; i<zones_count; i++)
    {
        if(zones[i].isBroken) continue;

        if(sbt_signal == 1 && zones[i].isSupport)
        {
            if(close1 >= zones[i].bottom && close1 <= zones[i].top)
            {
                inZone = true;
                zoneIdx = i;
                break;
            }
        }
        else if(sbt_signal == -1 && !zones[i].isSupport)
        {
            if(close1 >= zones[i].bottom && close1 <= zones[i].top)
            {
                inZone = true;
                zoneIdx = i;
                break;
            }
        }
    }

    if(inZone)
    {
        ExecuteTrade(sbt_signal, zones[zoneIdx]);
    }
}

//+------------------------------------------------------------------+
//| Manage Ongoing Trades                                            |
//+------------------------------------------------------------------+
void ManageTrades()
{
    bool level1_exists = false, level2_exists = false, level3_exists = false, level4_exists = false;
    int count4 = 0, total4 = 0;

    // First pass: identify which levels are still active
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
            string comment = PositionGetString(POSITION_COMMENT);
            int level = (int)StringToInteger(StringSubstr(comment, 8));

            if(level == 1) level1_exists = true;
            if(level == 2) level2_exists = true;
            if(level == 3) level3_exists = true;
            if(level == 4) { level4_exists = true; count4++; }

            // Special check for total TP4 trades (stored in comment maybe?)
            // For now, assume if level 4 exists, we check how many.
        }
    }

    // Second pass: trailing and exit
    for(int i=PositionsTotal()-1; i>=0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            int level = (int)StringToInteger(StringSubstr(PositionGetString(POSITION_COMMENT), 8));
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            int type = (int)PositionGetInteger(POSITION_TYPE);

            // Adverse signal exit
            if((type == POSITION_TYPE_BUY && sbt_signal == -1) || (type == POSITION_TYPE_SELL && sbt_signal == 1))
            {
                trade.PositionClose(ticket);
                continue;
            }

            // Adverse SR creation exit
            bool adverseSR = false;
            double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            for(int z=0; z<zones_count; z++)
            {
                if(zones[z].isBroken) continue;
                if(type == POSITION_TYPE_BUY && !zones[z].isSupport && zones[z].bottom > entry && price >= zones[z].bottom) { adverseSR = true; break; }
                if(type == POSITION_TYPE_SELL && zones[z].isSupport && zones[z].top < entry && price <= zones[z].top) { adverseSR = true; break; }
            }
            if(adverseSR)
            {
                trade.PositionClose(ticket);
                continue;
            }

            // Trailing Logic
            double new_sl = current_sl;

            // TP1 Hit (Level 1 gone) -> SL to Entry
            if(!level1_exists && level > 1)
            {
                new_sl = entry;
            }
            // TP2 Hit (Level 2 gone) -> SL to TP1? Wait, we don't know TP1 price.
            // But we can estimate it or just use the logic if we had stored it.
            // For now, let's at least implement Breakeven.

            if(new_sl != current_sl)
                trade.PositionModify(ticket, new_sl, PositionGetDouble(POSITION_TP));
        }
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
        sl = zone.bottom - SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10; // Slightly below support
    else
        sl = zone.top + SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 10;    // Slightly above resistance

    // TP4 Search
    double target_tp4 = 0;
    bool foundSR = false;
    for(int i=0; i<zones_count; i++)
    {
        if(zones[i].isBroken) continue;
        if(signal == 1 && !zones[i].isSupport && zones[i].bottom > price && (zones[i].bottom - price) <= InpTP4Interval)
        {
            target_tp4 = zones[i].bottom;
            foundSR = true;
            break;
        }
        else if(signal == -1 && zones[i].isSupport && zones[i].top < price && (price - zones[i].top) <= InpTP4Interval)
        {
            target_tp4 = zones[i].top;
            foundSR = true;
            break;
        }
    }

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double dist = 0;

    if(!foundSR)
    {
        // Fallback case
        dist = InpFallbackDist;
        tp1 = (signal == 1) ? price + 0.00310 : price - 0.00310;
        tp2 = 0; // Alternative exit
    }
    else
    {
        dist = MathAbs(target_tp4 - price);
        if(balance <= 5000)
        {
            tp1 = (signal == 1) ? price + dist * 0.5 : price - dist * 0.5;
        }
        else if(balance <= 400000)
        {
            tp1 = (signal == 1) ? price + dist * (3.0/6.0) : price - dist * (3.0/6.0);
            tp2 = (signal == 1) ? price + dist * (5.0/6.0) : price - dist * (5.0/6.0);
            tp3 = (signal == 1) ? price + dist * (6.0/6.0) : price - dist * (6.0/6.0);
        }
        else
        {
            tp1 = (signal == 1) ? price + dist * (3.0/6.0) : price - dist * (3.0/6.0);
            tp2 = (signal == 1) ? price + dist * (4.0/6.0) : price - dist * (4.0/6.0);
            tp3 = (signal == 1) ? price + dist * (5.0/6.0) : price - dist * (5.0/6.0);
            tp4 = (signal == 1) ? price + dist * (6.0/6.0) : price - dist * (6.0/6.0);
        }
    }

    // Order Sending
    int count = GetTradeCount();
    double lot = GetLotSize();

    for(int i=0; i<count; i++)
    {
        double current_tp = 0;
        if(!foundSR)
        {
            if(i < count * 0.7) current_tp = tp1;
            else current_tp = 0; // Alternative exit
        }
        else
        {
            if(balance <= 5000) current_tp = tp1;
            else if(balance <= 400000)
            {
                if(i < count * 0.5) current_tp = tp1;
                else if(i < count * 0.8) current_tp = tp2; // 50% + 30%
                else current_tp = tp3;
            }
            else
            {
                if(i < count * 0.5) current_tp = tp1;
                else if(i < count * 0.7) current_tp = tp2; // 50% + 20%
                else if(i < count * 0.9) current_tp = tp3; // 50% + 20% + 20%
                else current_tp = tp4;
            }
        }

        string comment = StringFormat("TPLevel:%d", (current_tp == tp1 ? 1 : (current_tp == tp2 ? 2 : (current_tp == tp3 ? 3 : (current_tp == tp4 ? 4 : 0)))));
        if(signal == 1)
            trade.Buy(lot, _Symbol, price, sl, current_tp, comment);
        else
            trade.Sell(lot, _Symbol, price, sl, current_tp, comment);
    }
}

//+------------------------------------------------------------------+
//| Calculate SB Logic                                               |
//+------------------------------------------------------------------+
void UpdateSB()
{
    double close1 = iClose(_Symbol, _Period, 1);

    // BB Calculations
    double sma_high_buf[], sma_low_buf[];
    if(CopyBuffer(handle_sma_high, 0, 1, 1, sma_high_buf) <= 0) return;
    if(CopyBuffer(handle_sma_low, 0, 1, 1, sma_low_buf) <= 0) return;

    double sma_high = sma_high_buf[0];
    double sma_low  = sma_low_buf[0];

    double sum_high = 0, sum_low = 0;
    for(int i=1; i<=InpSBPeriod; i++)
    {
        sum_high += MathPow(iHigh(_Symbol, _Period, i) - sma_high, 2);
        sum_low  += MathPow(iLow(_Symbol, _Period, i) - sma_low, 2);
    }
    double stdev_high = MathSqrt(sum_high / InpSBPeriod);
    double stdev_low  = MathSqrt(sum_low / InpSBPeriod);

    double bbup = sma_high + stdev_high * InpSBMult;
    double bbdn = sma_low - stdev_low * InpSBMult;

    double prev_sbt_s = sbt_s;

    if(sbt_s == 0) // Initialization
    {
        sbt_s = (close1 > bbup) ? bbdn : bbup;
    }
    else
    {
        if(close1 > sbt_s)
            sbt_s = MathMax(sbt_s, bbdn);
        else if(close1 < sbt_s)
            sbt_s = MathMin(sbt_s, bbup);

        // Crossover logic
        sbt_signal = 0;
        if(last_close <= prev_sbt_s && close1 > sbt_s) // Crossover
        {
            sbt_s = bbdn;
            sbt_c = clrLime;
            sbt_signal = 1;
        }
        else if(last_close >= prev_sbt_s && close1 < sbt_s) // Crossunder
        {
            sbt_s = bbup;
            sbt_c = clrRed;
            sbt_signal = -1;
        }
    }
}
//+------------------------------------------------------------------+
