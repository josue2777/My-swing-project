//+------------------------------------------------------------------+
//|                                           BreakoutTrading_EA.mq5 |
//|                                  Copyright 2024, Trading Bot     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs - Consolidation & Range
input int      InpConsolidationBars = 20;     // Lookback bars for consolidation range
input double   InpMaxRangeATRMult   = 3.5;    // Max range height in ATR multiples
input double   InpATRCompression    = 0.90;   // ATR compression threshold vs SMA(ATR)

//--- Inputs - Confirmation & Retest
input double   InpVolumeMult        = 1.25;   // Minimum volume multiplier vs SMA(Volume)
input double   InpBarExpansionMult  = 1.20;   // Minimum bar range expansion vs ATR
input bool     InpRequireRetest     = false;  // Require retest of breakout level before entry
input double   InpRetestATRDist     = 0.50;   // Retest tolerance zone (in ATR multiples)

//--- Inputs - Risk & Liquidity Filters
input double   InpMaxSpreadPoints   = 50.0;   // Maximum allowed spread in points
input double   InpSL_ATR_Mult       = 1.50;   // Stop Loss multiplier (ATR based)
input double   InpRiskPercent       = 1.0;    // Risk per trade (% of balance if dynamic lot)
input bool     InpUseBalanceTiering = true;   // Use balance tiered lot size and trade count
input int      InpMagic             = 888111; // Magic Number

//--- Inputs - Exit & Trailing
input double   InpTP1_ATR_Mult      = 2.0;    // Take Profit 1 multiplier (ATR based)
input double   InpTP2_ATR_Mult      = 4.0;    // Take Profit 2 multiplier (ATR based)
input double   InpTP3_ATR_Mult      = 6.0;    // Take Profit 3 multiplier (ATR based)
input double   InpTrailATRMult      = 2.0;    // Dynamic Trailing Stop multiplier (ATR based)
input int      InpLateralBars       = 6;      // Bars to check for post-breakout lateral stall
input double   InpLateralDistATR    = 1.0;    // Min price movement required to avoid lateral suspension

//--- Global Handles & Variables
CTrade         trade;
int            handle_atr;
int            handle_atr_sma;
int            handle_vol_sma;

double         breakout_high_level = 0.0;
double         breakout_low_level  = 0.0;
int            pending_breakout_dir = 0; // 1: Buy breakout detected, -1: Sell breakout detected
datetime       breakout_bar_time    = 0;
datetime       last_processed_bar   = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);

    // Initialize indicator handles
    handle_atr = iATR(_Symbol, _Period, 14);
    handle_atr_sma = iMA(_Symbol, _Period, 14, 0, MODE_SMA, handle_atr);
    handle_vol_sma = iMA(_Symbol, _Period, 20, 0, MODE_SMA, PRICE_CLOSE);

    if(handle_atr == INVALID_HANDLE)
    {
        Print("Error initializing ATR handle.");
        return(INIT_FAILED);
    }

    // Configure filling mode dynamically
    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((filling & SYMBOL_FILLING_FOK) != 0)
        trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if((filling & SYMBOL_FILLING_IOC) != 0)
        trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        trade.SetTypeFilling(ORDER_FILLING_RETURN);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
}

//+------------------------------------------------------------------+
//| Check if new bar arrived                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    if(current_bar_time != last_processed_bar)
    {
        last_processed_bar = current_bar_time;
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Lot Size based on Account Balance                            |
//+------------------------------------------------------------------+
double GetLotSize()
{
    if(!InpUseBalanceTiering)
    {
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
        double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
        double atr = GetATR(1);
        if(atr <= 0 || tick_size <= 0 || tick_value <= 0) return 0.01;

        double sl_dist = atr * InpSL_ATR_Mult;
        double risk_amount = balance * (InpRiskPercent / 100.0);
        double loss_per_lot = (sl_dist / tick_size) * tick_value;
        if(loss_per_lot <= 0) return 0.01;

        double lot = NormalizeDouble(risk_amount / loss_per_lot, 2);
        double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
        double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
        double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

        lot = MathMax(min_lot, MathMin(max_lot, MathFloor(lot / step_lot) * step_lot));
        return lot;
    }

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
    if(!InpUseBalanceTiering) return 1;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance <= 300)    return 2;
    if(balance <= 5000)   return 4;
    if(balance <= 15000)  return 6;
    if(balance <= 75000)  return 10;
    if(balance <= 400000) return 16;
    return 20;
}

//+------------------------------------------------------------------+
//| Get ATR Value                                                    |
//+------------------------------------------------------------------+
double GetATR(int shift)
{
    double buf[];
    if(CopyBuffer(handle_atr, 0, shift, 1, buf) > 0)
        return buf[0];
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get Average Volume over lookback                                 |
//+------------------------------------------------------------------+
double GetAverageVolume(int lookback, int shift)
{
    long total_vol = 0;
    for(int i = shift; i < shift + lookback; i++)
    {
        total_vol += iVolume(_Symbol, _Period, i);
    }
    return (double)total_vol / lookback;
}

//+------------------------------------------------------------------+
//| Check Liquidity and Spread                                       |
//+------------------------------------------------------------------+
bool IsLiquidityAcceptable()
{
    double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if(spread > InpMaxSpreadPoints)
    {
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Count active positions for this EA                               |
//+------------------------------------------------------------------+
int GetActivePositionCount(int &buy_count, int &sell_count)
{
    buy_count = 0;
    sell_count = 0;
    int total = 0;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                total++;
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
                    buy_count++;
                else if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
                    sell_count++;
            }
        }
    }
    return total;
}

//+------------------------------------------------------------------+
//| Detect Consolidation / Range Compression                         |
//+------------------------------------------------------------------+
bool IsConsolidating(double &range_high, double &range_low)
{
    double highest = -DBL_MAX;
    double lowest  = DBL_MAX;

    for(int i = 2; i <= InpConsolidationBars + 1; i++)
    {
        double h = iHigh(_Symbol, _Period, i);
        double l = iLow(_Symbol, _Period, i);
        if(h > highest) highest = h;
        if(l < lowest)  lowest = l;
    }

    range_high = highest;
    range_low  = lowest;

    double range_height = highest - lowest;
    double atr = GetATR(2);
    if(atr <= 0) return false;

    // Check Range height condition
    bool range_compressed = (range_height <= InpMaxRangeATRMult * atr);

    // Check ATR volatility compression condition
    double atr_sma = 0.0;
    double atr_buf[];
    if(CopyBuffer(handle_atr_sma, 0, 2, 1, atr_buf) > 0) atr_sma = atr_buf[0];

    bool atr_compressed = (atr_sma > 0 && atr <= atr_sma * InpATRCompression);

    return (range_compressed || atr_compressed);
}

//+------------------------------------------------------------------+
//| Check Post-Breakout Lateral Market Stall                         |
//+------------------------------------------------------------------+
bool IsPostBreakoutLateral()
{
    int buy_cnt = 0, sell_cnt = 0;
    if(GetActivePositionCount(buy_cnt, sell_cnt) == 0) return false;

    double atr = GetATR(1);
    if(atr <= 0) return false;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
                continue;

            datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
            int bar_index = iBarShift(_Symbol, _Period, open_time);

            if(bar_index >= InpLateralBars)
            {
                double entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
                double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
                double move_dist = MathAbs(current_price - entry_price);

                if(move_dist < InpLateralDistATR * atr)
                {
                    return true; // Lateral stall detected post breakout
                }
            }
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Execute Breakout Trades                                          |
//+------------------------------------------------------------------+
void ExecuteBreakoutTrade(int signal, double range_high, double range_low)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (signal == 1) ? ask : bid;
    double atr = GetATR(1);
    if(atr <= 0) return;

    // SL based on market structure or ATR multiplier
    double sl = 0.0;
    if(signal == 1)
    {
        double structure_sl = range_low;
        double atr_sl = price - (InpSL_ATR_Mult * atr);
        sl = MathMax(structure_sl, atr_sl);
    }
    else
    {
        double structure_sl = range_high;
        double atr_sl = price + (InpSL_ATR_Mult * atr);
        sl = MathMin(structure_sl, atr_sl);
    }

    double risk_dist = MathAbs(price - sl);
    if(risk_dist <= 0) return;

    double tp1 = (signal == 1) ? price + (InpTP1_ATR_Mult * atr) : price - (InpTP1_ATR_Mult * atr);
    double tp2 = (signal == 1) ? price + (InpTP2_ATR_Mult * atr) : price - (InpTP2_ATR_Mult * atr);
    double tp3 = (signal == 1) ? price + (InpTP3_ATR_Mult * atr) : price - (InpTP3_ATR_Mult * atr);

    int count = GetTradeCount();
    double lot = GetLotSize();

    for(int i = 0; i < count; i++)
    {
        double current_tp = 0;
        int level = 1;

        if(i < count * 0.5)
        {
            current_tp = tp1;
            level = 1;
        }
        else if(i < count * 0.8)
        {
            current_tp = tp2;
            level = 2;
        }
        else
        {
            current_tp = tp3;
            level = 3;
        }

        string comment = StringFormat("Breakout L:%d", level);

        if(signal == 1)
            trade.Buy(lot, _Symbol, price, sl, current_tp, comment);
        else
            trade.Sell(lot, _Symbol, price, sl, current_tp, comment);
    }
}

//+------------------------------------------------------------------+
//| Intelligent Trailing Stop & Position Management                  |
//+------------------------------------------------------------------+
void ManagePositions()
{
    double atr = GetATR(1);
    if(atr <= 0) return;

    bool level1_exists = false;
    bool multi_level_trading = false;

    // Check position comments and level status
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
                continue;

            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "L:1") >= 0)
                level1_exists = true;

            if(StringFind(comment, "L:2") >= 0 || StringFind(comment, "L:3") >= 0)
                multi_level_trading = true;
        }
    }

    // Dynamic Trailing Stop & BE
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
                continue;

            long pos_type = PositionGetInteger(POSITION_TYPE);
            double entry = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_price = PositionGetDouble(POSITION_PRICE_CURRENT);
            string comment = PositionGetString(POSITION_COMMENT);

            // 1. Break-Even Trigger: Only if multi-level tiering opened L:1 and L:1 has hit TP
            if(multi_level_trading && !level1_exists && StringFind(comment, "L:1") < 0)
            {
                if(pos_type == POSITION_TYPE_BUY && current_sl < entry)
                {
                    trade.PositionModify(ticket, entry, PositionGetDouble(POSITION_TP));
                    continue;
                }
                else if(pos_type == POSITION_TYPE_SELL && (current_sl > entry || current_sl == 0.0))
                {
                    trade.PositionModify(ticket, entry, PositionGetDouble(POSITION_TP));
                    continue;
                }
            }

            // 2. Volatility-Based Dynamic Trailing Stop
            if(pos_type == POSITION_TYPE_BUY)
            {
                double new_sl = current_price - (InpTrailATRMult * atr);
                if(new_sl > current_sl + (10 * _Point) && new_sl > entry)
                {
                    trade.PositionModify(ticket, NormalizeDouble(new_sl, _Digits), PositionGetDouble(POSITION_TP));
                }
            }
            else if(pos_type == POSITION_TYPE_SELL)
            {
                double new_sl = current_price + (InpTrailATRMult * atr);
                if((current_sl == 0.0 || new_sl < current_sl - (10 * _Point)) && new_sl < entry)
                {
                    trade.PositionModify(ticket, NormalizeDouble(new_sl, _Digits), PositionGetDouble(POSITION_TP));
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check Breakout Conditions                                        |
//+------------------------------------------------------------------+
void CheckBreakoutSignal()
{
    if(!IsLiquidityAcceptable()) return;

    // Post-Breakout Lateral Stall check
    if(IsPostBreakoutLateral()) return;

    int buy_cnt = 0, sell_cnt = 0;
    if(GetActivePositionCount(buy_cnt, sell_cnt) > 0)
    {
        // Rule: Never open multiple positions in the same direction while previous breakout is active
        return;
    }

    double close1 = iClose(_Symbol, _Period, 1);
    double open1  = iOpen(_Symbol, _Period, 1);
    double high1  = iHigh(_Symbol, _Period, 1);
    double low1   = iLow(_Symbol, _Period, 1);

    double atr = GetATR(1);
    if(atr <= 0) return;

    // Retest Execution Logic for Pending Breakout Signal
    if(InpRequireRetest && pending_breakout_dir != 0)
    {
        int elapsed_bars = iBarShift(_Symbol, _Period, breakout_bar_time);
        if(elapsed_bars > 0 && elapsed_bars <= 10)
        {
            if(pending_breakout_dir == 1) // Buy Breakout pending Retest
            {
                if(low1 <= breakout_high_level + (InpRetestATRDist * atr) && close1 >= breakout_high_level)
                {
                    ExecuteBreakoutTrade(1, breakout_high_level, breakout_low_level);
                    pending_breakout_dir = 0;
                    return;
                }
            }
            else if(pending_breakout_dir == -1) // Sell Breakout pending Retest
            {
                if(high1 >= breakout_low_level - (InpRetestATRDist * atr) && close1 <= breakout_low_level)
                {
                    ExecuteBreakoutTrade(-1, breakout_high_level, breakout_low_level);
                    pending_breakout_dir = 0;
                    return;
                }
            }
        }
        else if(elapsed_bars > 10)
        {
            pending_breakout_dir = 0; // Expire pending retest signal
        }
    }

    double range_high = 0.0, range_low = 0.0;
    bool is_consolidated = IsConsolidating(range_high, range_low);
    if(!is_consolidated) return;

    // Volume and Volatility Expansion Check
    double avg_vol = GetAverageVolume(20, 2);
    long vol1 = iVolume(_Symbol, _Period, 1);
    bool vol_confirmed = (avg_vol > 0) ? ((double)vol1 >= avg_vol * InpVolumeMult) : true;
    bool range_expanded = ((high1 - low1) >= atr * InpBarExpansionMult);

    if(!vol_confirmed && !range_expanded) return;

    // Confirmed Breakout Detection
    if(close1 > range_high && open1 <= range_high)
    {
        if(!InpRequireRetest)
        {
            ExecuteBreakoutTrade(1, range_high, range_low);
            pending_breakout_dir = 0;
        }
        else
        {
            pending_breakout_dir = 1;
            breakout_high_level = range_high;
            breakout_low_level = range_low;
            breakout_bar_time = iTime(_Symbol, _Period, 1);
        }
    }
    else if(close1 < range_low && open1 >= range_low)
    {
        if(!InpRequireRetest)
        {
            ExecuteBreakoutTrade(-1, range_high, range_low);
            pending_breakout_dir = 0;
        }
        else
        {
            pending_breakout_dir = -1;
            breakout_high_level = range_high;
            breakout_low_level = range_low;
            breakout_bar_time = iTime(_Symbol, _Period, 1);
        }
    }
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    ManagePositions();

    if(IsNewBar())
    {
        CheckBreakoutSignal();
    }
}
//+------------------------------------------------------------------+
