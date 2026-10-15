//+------------------------------------------------------------------+
//|                                              Breakout20_EA.mq5   |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Input Parameters
input group "=== Paramètres Généraux ==="
input ulong    InpMagic            = 334455;   // Magic Number
input int      InpLookbackBars     = 20;       // Bougies pour calcul du High/Low
input int      InpRecalcBars       = 10;       // Bougies sans déclenchement avant recalcul
input int      InpStopLossPoints   = 2000;     // Stop Loss (Points) = 1R
input int      InpTakeProfitPoints = 3000;     // Take Profit (Points)
input double   InpRiskPercent      = 3.0;      // Risque par trade (% du solde)

input group "=== Filtre Tendance EMA ==="
input bool     InpUseEMA           = true;     // Activer le filtre EMA
input int      InpEMAPeriod        = 200;      // Période EMA

input group "=== Filtre Mouvement ADX ==="
input bool     InpUseADX           = true;     // Activer le filtre ADX
input int      InpADXPeriod        = 14;       // Période ADX
input double   InpADXMinLevel      = 25.0;     // Seuil ADX minimum pour filtrer le range

input group "=== Filtre Volatilité ATR & Décalage ==="
input bool     InpUseATR           = true;     // Activer le filtre ATR
input int      InpATRPeriod        = 14;       // Période ATR
input double   InpMinATR           = 0.00030;  // Seuil ATR minimum (en prix)
input double   InpATROffsetMult    = 0.5;      // Multiplicateur ATR pour le décalage des ordres

input group "=== Break Even & Trailing Stop ==="
input bool     InpUseBreakEven     = true;     // Activer le Break Even à +1R
input bool     InpUseTrailingStop  = true;     // Activer le Trailing Stop dynamique
input double   InpTrailingATRMult  = 2.0;      // Distance du Trailing Stop (x ATR)

input group "=== Gestion des Pertes ==="
input int      InpMaxLosses        = 2;        // Nombre de SL consécutifs avant pause
input int      InpPauseBars        = 10;       // Nombre de bougies de pause après N pertes

//--- Global Variables
CTrade         trade;
datetime       g_last_bar_time     = 0;
int            g_bars_since_setup  = 0;
bool           g_need_recalc       = true;
int            g_prev_pos_count    = 0;

int            g_consecutive_losses     = 0;
int            g_pause_bars_remaining   = 0;

int            g_handle_ema        = INVALID_HANDLE;
int            g_handle_adx        = INVALID_HANDLE;
int            g_handle_atr        = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    trade.SetExpertMagicNumber(InpMagic);

    // Configuration dynamique du mode de remplissage des ordres
    uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
    if((filling & SYMBOL_FILLING_FOK) != 0)
        trade.SetTypeFilling(ORDER_FILLING_FOK);
    else if((filling & SYMBOL_FILLING_IOC) != 0)
        trade.SetTypeFilling(ORDER_FILLING_IOC);
    else
        trade.SetTypeFilling(ORDER_FILLING_RETURN);

    // Initialisation des indicateurs
    if(InpUseEMA)
    {
        g_handle_ema = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(g_handle_ema == INVALID_HANDLE)
        {
            Print("Erreur lors de la création de l'indicateur EMA");
            return(INIT_FAILED);
        }
    }

    if(InpUseADX)
    {
        g_handle_adx = iADX(_Symbol, _Period, InpADXPeriod);
        if(g_handle_adx == INVALID_HANDLE)
        {
            Print("Erreur lors de la création de l'indicateur ADX");
            return(INIT_FAILED);
        }
    }

    if(InpUseATR || InpATROffsetMult > 0 || InpUseTrailingStop)
    {
        g_handle_atr = iATR(_Symbol, _Period, InpATRPeriod);
        if(g_handle_atr == INVALID_HANDLE)
        {
            Print("Erreur lors de la création de l'indicateur ATR");
            return(INIT_FAILED);
        }
    }

    g_last_bar_time          = 0;
    g_bars_since_setup       = 0;
    g_need_recalc            = true;
    g_prev_pos_count         = GetPositionCount();
    g_consecutive_losses     = 0;
    g_pause_bars_remaining   = 0;

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if(g_handle_ema != INVALID_HANDLE) IndicatorRelease(g_handle_ema);
    if(g_handle_adx != INVALID_HANDLE) IndicatorRelease(g_handle_adx);
    if(g_handle_atr != INVALID_HANDLE) IndicatorRelease(g_handle_atr);
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

    int digits = 2;
    if(lot_step >= 1.0) digits = 0;
    else if(lot_step >= 0.1) digits = 1;

    return NormalizeDouble(lot, digits);
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
//| Get EMA Value at index 1                                         |
//+------------------------------------------------------------------+
double GetEMA()
{
    if(g_handle_ema == INVALID_HANDLE) return 0;
    double buf[1];
    if(CopyBuffer(g_handle_ema, 0, 1, 1, buf) > 0)
        return buf[0];
    return 0;
}

//+------------------------------------------------------------------+
//| Get ADX Value at index 1                                         |
//+------------------------------------------------------------------+
double GetADX()
{
    if(g_handle_adx == INVALID_HANDLE) return 0;
    double buf[1];
    if(CopyBuffer(g_handle_adx, 0, 1, 1, buf) > 0)
        return buf[0];
    return 0;
}

//+------------------------------------------------------------------+
//| Get ATR Value at index 1                                         |
//+------------------------------------------------------------------+
double GetATR()
{
    if(g_handle_atr == INVALID_HANDLE) return 0;
    double buf[1];
    if(CopyBuffer(g_handle_atr, 0, 1, 1, buf) > 0)
        return buf[0];
    return 0;
}

//+------------------------------------------------------------------+
//| Recalculate High/Low and place new pending orders                |
//+------------------------------------------------------------------+
void RecalculateAndPlaceOrders()
{
    DeleteAllPendingOrders();

    if(GetPositionCount() > 0) return;

    // Vérification de la pause consécutive post-perte
    if(g_pause_bars_remaining > 0)
    {
        g_need_recalc = false;
        return;
    }

    double high_val = 0, low_val = 0;
    if(!GetHighLow20(high_val, low_val))
    {
        g_need_recalc = false;
        return;
    }

    // Filtre ADX >= 25
    if(InpUseADX)
    {
        double adx = GetADX();
        if(adx < InpADXMinLevel)
        {
            g_need_recalc = false;
            return;
        }
    }

    // Filtre ATR Minimum
    double atr = GetATR();
    if(InpUseATR && atr < InpMinATR)
    {
        g_need_recalc = false;
        return;
    }

    double ema = GetEMA();
    double close1 = iClose(_Symbol, _Period, 1);

    double offset = (InpATROffsetMult > 0 && atr > 0) ? (InpATROffsetMult * atr) : 0;

    double lot = CalculateLotSize();
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double stop_level = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

    bool allow_buy  = true;
    bool allow_sell = true;

    // Filtre de tendance EMA 200
    if(InpUseEMA && ema > 0)
    {
        if(close1 <= ema) allow_buy  = false;
        if(close1 >= ema) allow_sell = false;
    }

    bool placed_buy = false;
    bool placed_sell = false;

    // Placement Buy Stop à High + 0.5 * ATR
    if(allow_buy)
    {
        double buy_price = high_val + offset;
        if(buy_price <= ask + stop_level)
            buy_price = ask + stop_level + point;

        buy_price = NormalizeDouble(buy_price, _Digits);
        double buy_sl = NormalizeDouble(buy_price - InpStopLossPoints * point, _Digits);
        double buy_tp = NormalizeDouble(buy_price + InpTakeProfitPoints * point, _Digits);

        placed_buy = trade.BuyStop(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Breakout20 Buy");
    }

    // Placement Sell Stop à Low - 0.5 * ATR
    if(allow_sell)
    {
        double sell_price = low_val - offset;
        if(sell_price >= bid - stop_level)
            sell_price = bid - stop_level - point;

        sell_price = NormalizeDouble(sell_price, _Digits);
        double sell_sl = NormalizeDouble(sell_price + InpStopLossPoints * point, _Digits);
        double sell_tp = NormalizeDouble(sell_price - InpTakeProfitPoints * point, _Digits);

        placed_sell = trade.SellStop(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Breakout20 Sell");
    }

    g_bars_since_setup = 0;
    g_need_recalc      = false;
}

//+------------------------------------------------------------------+
//| Manage Active Trades (Break Even at +1R and Dynamic Trailing SL)  |
//+------------------------------------------------------------------+
void ManageActiveTrades()
{
    if(!InpUseBreakEven && !InpUseTrailingStop) return;

    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    double atr   = GetATR();

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != (long)InpMagic || PositionGetString(POSITION_SYMBOL) != _Symbol)
                continue;

            long type        = PositionGetInteger(POSITION_TYPE);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);
            double price      = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

            double profit_points = (type == POSITION_TYPE_BUY) ? (price - open_price) / point : (open_price - price) / point;

            // 1. Break Even à +1R (profit >= InpStopLossPoints)
            if(InpUseBreakEven && profit_points >= InpStopLossPoints)
            {
                if((type == POSITION_TYPE_BUY && current_sl < open_price) ||
                   (type == POSITION_TYPE_SELL && (current_sl > open_price || current_sl == 0)))
                {
                    double new_sl = NormalizeDouble(open_price, _Digits);
                    trade.PositionModify(ticket, new_sl, current_tp);
                    current_sl = new_sl;
                }
            }

            // 2. Trailing Stop dynamique basé sur 2.0 * ATR après BE
            if(InpUseTrailingStop && atr > 0 && profit_points >= InpStopLossPoints)
            {
                double trail_dist = InpTrailingATRMult * atr;

                if(type == POSITION_TYPE_BUY)
                {
                    double new_sl = NormalizeDouble(price - trail_dist, _Digits);
                    if(new_sl > current_sl + point)
                    {
                        trade.PositionModify(ticket, new_sl, current_tp);
                    }
                }
                else if(type == POSITION_TYPE_SELL)
                {
                    double new_sl = NormalizeDouble(price + trail_dist, _Digits);
                    if(current_sl == 0 || new_sl < current_sl - point)
                    {
                        trade.PositionModify(ticket, new_sl, current_tp);
                    }
                }
            }
        }
    }
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
                // Un ordre est déclenché (entrée en position) : suppression immédiate de l'ordre opposé
                if(entry == DEAL_ENTRY_IN)
                {
                    DeleteAllPendingOrders();
                }
                // Une position est clôturée (sortie)
                else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
                {
                    double profit = HistoryDealGetDouble(deal_ticket, DEAL_PROFIT) +
                                   HistoryDealGetDouble(deal_ticket, DEAL_SWAP) +
                                   HistoryDealGetDouble(deal_ticket, DEAL_COMMISSION);

                    if(profit < 0)
                    {
                        g_consecutive_losses++;
                        if(g_consecutive_losses >= InpMaxLosses)
                        {
                            g_pause_bars_remaining = InpPauseBars;
                        }
                    }
                    else if(profit > 0)
                    {
                        g_consecutive_losses = 0;
                    }

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
    int current_pending_count = GetPendingOrderCount();

    // Gestion active du Break Even et du Trailing Stop
    if(current_pos_count > 0)
    {
        ManageActiveTrades();

        // Nettoyage de sécurité si un ordre opposé subsiste
        if(current_pending_count > 0)
        {
            DeleteAllPendingOrders();
            current_pending_count = 0;
        }
    }

    // Détection de la fermeture d'une position
    if(g_prev_pos_count > 0 && current_pos_count == 0)
    {
        g_need_recalc = true;
    }
    g_prev_pos_count = current_pos_count;

    // Détection de la clôture d'une nouvelle bougie
    datetime current_bar_time = iTime(_Symbol, _Period, 0);
    bool is_new_bar = (current_bar_time != g_last_bar_time);

    if(is_new_bar)
    {
        g_last_bar_time = current_bar_time;

        // Décrémentation de la pause après pertes consécutives
        if(g_pause_bars_remaining > 0)
        {
            g_pause_bars_remaining--;
            if(g_pause_bars_remaining == 0)
            {
                g_consecutive_losses = 0;
                g_need_recalc = true;
            }
        }

        // Sur nouvelle bougie, si aucune position ni ordre n'est actif, planifier un recalcul
        if(current_pos_count == 0 && current_pending_count == 0 && g_pause_bars_remaining == 0)
        {
            g_need_recalc = true;
        }

        // Compteur de 10 bougies sans déclenché
        if(current_pos_count == 0 && current_pending_count > 0)
        {
            g_bars_since_setup++;
            if(g_bars_since_setup >= InpRecalcBars)
            {
                g_need_recalc = true;
            }
        }
    }

    // Exécution du recalcul uniquement si nécessaire et aucune position active
    if(g_need_recalc && current_pos_count == 0 && g_pause_bars_remaining == 0)
    {
        RecalculateAndPlaceOrders();
    }
}
