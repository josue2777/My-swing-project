//+------------------------------------------------------------------+
//|                                           MomentumTrading_EA.mq5 |
//|                                  Copyright 2024, Trading Bot     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>

//--- Inputs - Trend Filter
input int      InpEMAPeriod         = 200;    // Dominant Trend EMA Period
input int      InpADXPeriod         = 14;     // ADX Trend Filter Period
input double   InpMinADX            = 22.0;   // Minimum ADX level for strong trend

//--- Inputs - Momentum Engine
input int      InpROCPeriod         = 10;     // Rate of Change (ROC) Period
input double   InpMinROCPercent     = 0.35;   // Minimum ROC % acceleration threshold
input double   InpBarBodyATRRatio   = 1.10;   // Minimum Candle Body / ATR ratio
input double   InpVolumeIncrease    = 1.20;   // Minimum Volume ratio vs Volume MA(20)

//--- Inputs - Volatility Filter & SL
input int      InpATRPeriod         = 14;     // ATR Period
input double   InpMinATRMulti       = 0.80;   // Minimum ATR relative to SMA(ATR, 50)
input double   InpSL_ATR_Mult       = 1.75;   // Volatility SL multiplier (ATR based)

//--- Inputs - Exit & Slowdown
input double   InpROCExitThreshold  = 0.10;   // ROC % slowdown threshold to trigger early exit
input double   InpTrailATRMult      = 2.20;   // Volatility Trailing Stop multiplier

//--- Inputs - Trade Limiter & Cooldown
input int      InpCooldownBars      = 5;      // Bars to wait between consecutive trades
input int      InpMaxTradeSignals   = 2;      // Max concurrent momentum trade signals allowed
input double   InpMaxSpreadPoints   = 50.0;   // Max allowed spread in points
input bool     InpUseBalanceTiering = true;   // Dynamic Lot sizing based on account balance
input double   InpRiskPercent       = 1.0;    // Risk % per trade if fixed tiering disabled
input int      InpMagic             = 999222; // Magic Number

//--- Global Handles & Variables
CTrade         trade;
int            handle_ema;
int            handle_adx;
int            handle_atr;
int            handle_atr_sma;

datetime       last_trade_time      = 0;
datetime       last_processed_bar   = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);

    // Initialize indicator handles
    handle_ema     = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
    handle_adx     = iADX(_Symbol, _Period, InpADXPeriod);
    handle_atr     = iATR(_Symbol, _Period, InpATRPeriod);
    handle_atr_sma = iMA(_Symbol, _Period, 50, 0, MODE_SMA, handle_atr);

    if(handle_ema == INVALID_HANDLE || handle_adx == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
    {
        Print("Error initializing indicator handles.");
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
//| New bar detection                                                |
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
//| Get Lot Size based on Account Balance or Risk                    |
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
//| Get Dominant Trend (1: Bullish, -1: Bearish, 0: Neutral)         |
//+------------------------------------------------------------------+
int GetDominantTrend()
{
    double close1 = iClose(_Symbol, _Period, 1);
    double ema_buf[];
    if(CopyBuffer(handle_ema, 0, 1, 1, ema_buf) <= 0) return 0;

    double adx_buf[];
    if(CopyBuffer(handle_adx, 0, 1, 1, adx_buf) <= 0) return 0;

    if(adx_buf[0] < InpMinADX) return 0; // Filter out range/weak trend

    if(close1 > ema_buf[0]) return 1;
    if(close1 < ema_buf[0]) return -1;

    return 0;
}

//+------------------------------------------------------------------+
//| Calculate Rate of Change (ROC %)                                 |
//+------------------------------------------------------------------+
double GetROC(int period, int shift)
{
    double close_current = iClose(_Symbol, _Period, shift);
    double close_past = iClose(_Symbol, _Period, shift + period);
    if(close_past <= 0) return 0.0;

    return ((close_current - close_past) / close_past) * 100.0;
}

//+------------------------------------------------------------------+
//| Check Volatility Expansion                                       |
//+------------------------------------------------------------------+
bool IsVolatilitySufficient()
{
    double atr = GetATR(1);
    double atr_sma = 0.0;
    double buf[];
    if(CopyBuffer(handle_atr_sma, 0, 1, 1, buf) > 0) atr_sma = buf[0];

    if(atr_sma <= 0) return true;
    return (atr >= atr_sma * InpMinATRMulti);
}

//+------------------------------------------------------------------+
//| Check Volume Confirmation                                        |
//+------------------------------------------------------------------+
bool IsVolumeConfirmed()
{
    long vol1 = iVolume(_Symbol, _Period, 1);
    long total_vol = 0;
    for(int i = 2; i <= 21; i++)
    {
        total_vol += iVolume(_Symbol, _Period, i);
    }
    double avg_vol = (double)total_vol / 20.0;
    if(avg_vol <= 0) return true;

    return ((double)vol1 >= avg_vol * InpVolumeIncrease);
}

//+------------------------------------------------------------------+
//| Count active trade signals (grouped by entry bar/time)           |
//+------------------------------------------------------------------+
int GetActiveSignalCount(int &buy_signal_cnt, int &sell_signal_cnt)
{
    buy_signal_cnt = 0;
    sell_signal_cnt = 0;
    datetime distinct_buy_times[];
    datetime distinct_sell_times[];
    ArrayResize(distinct_buy_times, 0);
    ArrayResize(distinct_sell_times, 0);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                long pos_type = PositionGetInteger(POSITION_TYPE);
                datetime pos_time = (datetime)PositionGetInteger(POSITION_TIME);

                if(pos_type == POSITION_TYPE_BUY)
                {
                    bool exists = false;
                    for(int b = 0; b < ArraySize(distinct_buy_times); b++)
                    {
                        if(distinct_buy_times[b] == pos_time) { exists = true; break; }
                    }
                    if(!exists)
                    {
                        int sz = ArraySize(distinct_buy_times);
                        ArrayResize(distinct_buy_times, sz + 1);
                        distinct_buy_times[sz] = pos_time;
                    }
                }
                else if(pos_type == POSITION_TYPE_SELL)
                {
                    bool exists = false;
                    for(int s = 0; s < ArraySize(distinct_sell_times); s++)
                    {
                        if(distinct_sell_times[s] == pos_time) { exists = true; break; }
                    }
                    if(!exists)
                    {
                        int sz = ArraySize(distinct_sell_times);
                        ArrayResize(distinct_sell_times, sz + 1);
                        distinct_sell_times[sz] = pos_time;
                    }
                }
            }
        }
    }

    buy_signal_cnt = ArraySize(distinct_buy_times);
    sell_signal_cnt = ArraySize(distinct_sell_times);

    return (buy_signal_cnt + sell_signal_cnt);
}

//+------------------------------------------------------------------+
//| Fast Exit on Momentum Slowdown                                   |
//+------------------------------------------------------------------+
void CheckMomentumSlowdownExit()
{
    double roc = GetROC(InpROCPeriod, 1);

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
                continue;

            long pos_type = PositionGetInteger(POSITION_TYPE);

            // Exit Buy if momentum weakens significantly
            if(pos_type == POSITION_TYPE_BUY && roc < InpROCExitThreshold)
            {
                trade.PositionClose(ticket);
            }
            // Exit Sell if momentum weakens significantly
            else if(pos_type == POSITION_TYPE_SELL && roc > -InpROCExitThreshold)
            {
                trade.PositionClose(ticket);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage Trailing Stop based on Volatility                         |
//+------------------------------------------------------------------+
void ManagePositions()
{
    double atr = GetATR(1);
    if(atr <= 0) return;

    CheckMomentumSlowdownExit();

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
//| Execute Momentum Trades                                          |
//+------------------------------------------------------------------+
void ExecuteMomentumTrade(int signal)
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double price = (signal == 1) ? ask : bid;
    double atr = GetATR(1);
    if(atr <= 0) return;

    double sl = (signal == 1) ? price - (InpSL_ATR_Mult * atr) : price + (InpSL_ATR_Mult * atr);

    // Dynamic exit relies on Trailing Stop and Momentum Slowdown check
    double tp = 0.0;

    int count = GetTradeCount();
    double lot = GetLotSize();

    for(int i = 0; i < count; i++)
    {
        string comment = StringFormat("Momentum L:%d", i + 1);
        if(signal == 1)
            trade.Buy(lot, _Symbol, price, sl, tp, comment);
        else
            trade.Sell(lot, _Symbol, price, sl, tp, comment);
    }

    last_trade_time = iTime(_Symbol, _Period, 0);
}

//+------------------------------------------------------------------+
//| Check Momentum Entry Signal                                      |
//+------------------------------------------------------------------+
void CheckMomentumSignal()
{
    // Spread & Liquidity Filter
    double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if(spread > InpMaxSpreadPoints) return;

    // Active Trade Signal Count Limit
    int buy_signals = 0, sell_signals = 0;
    int total_signals = GetActiveSignalCount(buy_signals, sell_signals);
    if(total_signals >= InpMaxTradeSignals) return;

    // Cooldown check (prevent overtrading in high volatility)
    if(last_trade_time > 0)
    {
        int elapsed_bars = iBarShift(_Symbol, _Period, last_trade_time);
        if(elapsed_bars < InpCooldownBars) return;
    }

    // Dominant Trend Confirmation
    int trend = GetDominantTrend();
    if(trend == 0) return; // Reject trades in range or counter-trend

    // Volatility Filter
    if(!IsVolatilitySufficient()) return;

    // Momentum Multi-Confirmation
    double roc = GetROC(InpROCPeriod, 1);
    double close1 = iClose(_Symbol, _Period, 1);
    double open1  = iOpen(_Symbol, _Period, 1);
    double candle_body = MathAbs(close1 - open1);
    double atr = GetATR(1);
    if(atr <= 0) return;

    bool body_confirmed = (candle_body >= atr * InpBarBodyATRRatio);
    bool volume_confirmed = IsVolumeConfirmed();

    // Bullish Momentum Signal
    if(trend == 1 && roc >= InpMinROCPercent && body_confirmed && volume_confirmed && buy_signals == 0)
    {
        ExecuteMomentumTrade(1);
    }
    // Bearish Momentum Signal
    else if(trend == -1 && roc <= -InpMinROCPercent && body_confirmed && volume_confirmed && sell_signals == 0)
    {
        ExecuteMomentumTrade(-1);
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
        CheckMomentumSignal();
    }
}
//+------------------------------------------------------------------+
