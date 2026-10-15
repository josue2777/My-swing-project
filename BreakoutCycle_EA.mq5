//+------------------------------------------------------------------+
//|                                             BreakoutCycle_EA.mq5 |
//|                                  Copyright 2024, Trading Bot     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Expert Advisor MQL5 - Stratégie de Breakout par Cycles"
#property description "Gère un cycle complet unique avec ordres en attente, annulation opposée,"
#property description "Break Even dynamique, Trailing Stop progressif et gestion stricte des risques."
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Énumérations de Configuration                                   |
//+------------------------------------------------------------------+
enum ENUM_EXECUTION_MODE
{
    MODE_STANDARD    = 0, // Mode Standard (Buy Stop au-dessus, Sell Stop en-dessous)
    MODE_INVERTED    = 1, // Mode Inversé (Sell Limit au-dessus, Buy Limit en-dessous)
    MODE_BUY_ONLY    = 2, // Mode Achat Uniquement (Buy Stop uniquement)
    MODE_SELL_ONLY   = 3  // Mode Vente Uniquement (Sell Stop uniquement)
};

//+------------------------------------------------------------------+
//| Paramètres d'Entrée (Inputs)                                    |
//+------------------------------------------------------------------+
//--- Identifiant Général
input group "=== Paramètres Généraux ==="
input ulong              InpMagic                 = 777888;          // Magic Number
input ENUM_EXECUTION_MODE InpExecutionMode         = MODE_STANDARD;   // Mode d'exécution des ordres
input int                InpDistancePoints        = 150;             // Distance des ordres en attente (en Points)
input ulong              InpSlippage              = 10;              // Slippage maximal autorisé (en Points)
input int                InpMaxSpreadPoints       = 50;              // Spread maximal autorisé (0 = désactivé)

//--- Gestion du Lot et du Risque
input group "=== Gestion du Capital & Lot ==="
input double             InpFixedLotSize          = 0.10;            // Taille de lot fixe
input bool               InpUseAutoLot            = false;           // Activer le calcul de lot automatique (%)
input double             InpRiskPercent           = 1.0;             // Pourcentage de risque par trade (% Solde)

//--- Gestion Dynamic SL / BE / Trailing / Fixed SL-TP
input group "=== Gestion de Position & Protection ==="
input bool               InpUseFixedSLTPMode      = false;           // Mode SL/TP Fixes uniquement (Désactive BE/Trailing)
input int                InpFixedStopLossPoints   = 200;             // Stop Loss Fixe en Points (utilisé en Mode Fixe ou Inversé)
input int                InpFixedTakeProfitPoints = 300;             // Take Profit Fixe en Points (0 = Aucun Take Profit)
input int                InpBreakEvenPoints       = 100;             // Profit pour déclencher le Break Even (en Points)
input int                InpTrailingStartPoints   = 150;             // Profit pour activer le Trailing Stop (en Points)
input int                InpTrailingDistancePoints= 100;             // Distance du Trailing Stop (en Points)

//--- Expiration du Cycle
input group "=== Expiration du Cycle ==="
input int                InpMaxCandlesPending     = 10;              // Nb max de bougies avant expiration des ordres (0 = désactivé)

//--- Filtre ATR (Optionnel)
input group "=== Filtre ATR (Optionnel) ==="
input bool               InpUseATRFilter          = false;           // Activer le filtre ATR
input int                InpATRPeriod             = 14;              // Période de l'ATR
input ENUM_TIMEFRAMES    InpATRTimeframe          = PERIOD_CURRENT;  // Timeframe de l'ATR
input double             InpATRMinPoints          = 50.0;            // Valeur ATR minimale (en Points)
input double             InpATRMaxPoints          = 500.0;           // Valeur ATR maximale (0 = pas de max)

//--- Filtre Horaire (Optionnel / Amélioration)
input group "=== Filtre Horaire (Optionnel) ==="
input bool               InpUseTimeFilter         = false;           // Activer le filtre de session de trading
input int                InpStartHour             = 8;               // Heure de début de session (0-23)
input int                InpEndHour               = 20;              // Heure de fin de session (0-23)

//+------------------------------------------------------------------+
//| Variables Globales                                              |
//+------------------------------------------------------------------+
CTrade         trade;                 // Objet d'exécution des transactions
int            handle_atr = INVALID_HANDLE; // Handle pour l'indicateur ATR
datetime       cycle_start_time = 0;  // Heure de début du cycle actuel
bool           is_be_applied = false; // Drapeau indiquant si le Break Even a déjà été appliqué dans le cycle actuel

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Configuration de l'objet CTrade
    trade.SetExpertMagicNumber(InpMagic);
    trade.SetDeviationInPoints(InpSlippage);
    trade.SetTypeFillingByOrderSymbol(_Symbol);

    // Initialisation du filtre ATR si activé
    if(InpUseATRFilter)
    {
        handle_atr = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
        if(handle_atr == INVALID_HANDLE)
        {
            PrintFormat("ERREUR [OnInit]: Échec de création du handle ATR pour %s.", _Symbol);
            return(INIT_FAILED);
        }
    }

    PrintFormat("INITIALISATION [OnInit]: BreakoutCycle_EA chargé avec succès sur %s (%s). Magic Number: %i",
                _Symbol, EnumToString(_Period), InpMagic);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Libération du handle ATR
    if(handle_atr != INVALID_HANDLE)
    {
        IndicatorRelease(handle_atr);
        handle_atr = INVALID_HANDLE;
    }

    PrintFormat("DÉSINITIALISATION [OnDeinit]: BreakoutCycle_EA déchargé. Raison: %d", reason);
}

//+------------------------------------------------------------------+
//| FONCTIONS UTILITAIRES BROKER & FILTRES                          |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Normalise un prix selon les spécifications du symbole            |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
    double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
    if(tick_size > 0)
    {
        return NormalizeDouble(MathRound(price / tick_size) * tick_size, _Digits);
    }
    return NormalizeDouble(price, _Digits);
}

//+------------------------------------------------------------------+
//| Normalise un volume (lot) selon les contraintes du broker        |
//+------------------------------------------------------------------+
double NormalizeVolume(double volume)
{
    double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
    double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

    if(step_lot <= 0) step_lot = 0.01;

    // Arrondi au pas de lot le plus proche
    double normalized = MathFloor(volume / step_lot) * step_lot;

    // Respect des bornes Min et Max
    if(normalized < min_lot) normalized = min_lot;
    if(normalized > max_lot) normalized = max_lot;

    // Calcul dynamique de la précision décimale des lots
    int lot_digits = 0;
    if(step_lot < 0.01)       lot_digits = 3;
    else if(step_lot < 0.1)   lot_digits = 2;
    else if(step_lot < 1.0)   lot_digits = 1;

    return NormalizeDouble(normalized, lot_digits);
}

//+------------------------------------------------------------------+
//| Vérifie si la distance respecte le Stop Level du Broker         |
//+------------------------------------------------------------------+
bool CheckStopLevel(double order_price, double market_price)
{
    int stop_level_points = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double min_distance   = stop_level_points * _Point;

    if(MathAbs(order_price - market_price) < min_distance)
    {
        PrintFormat("AVERTISSEMENT [Broker]: Distance du prix d'ordre de %d points inférieure au StopLevel du broker (%d points).",
                    (int)(MathAbs(order_price - market_price) / _Point), stop_level_points);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| CALCUL DE LA TAILLE DU LOT (FIXE OU AUTO RISK)                  |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl_distance_points)
{
    if(!InpUseAutoLot)
    {
        return NormalizeVolume(InpFixedLotSize);
    }

    double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
    double risk_amount= balance * (InpRiskPercent / 100.0);

    double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
    double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

    if(tick_value <= 0 || tick_size <= 0 || sl_distance_points <= 0)
    {
        return NormalizeVolume(InpFixedLotSize);
    }

    // Calcul de la valeur par point pour 1 lot complet
    double point_value_per_lot = (tick_value / tick_size) * _Point;
    double calculated_lot     = risk_amount / (sl_distance_points * point_value_per_lot);

    return NormalizeVolume(calculated_lot);
}

//+------------------------------------------------------------------+
//| PLACEMENT DES ORDRES EN ATTENTE POUR UN NOUVEAU CYCLE           |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
    // Vérification des filtres généraux avant de lancer un cycle
    if(!CheckSpread() || !CheckTimeFilter() || !CheckATRFilter()) return;

    double ref_price = CalculateReferencePrice();
    double distance  = InpDistancePoints * _Point;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double buy_price  = 0;
    double sell_price = 0;

    double buy_sl  = 0;
    double sell_sl = 0;

    double buy_tp  = 0;
    double sell_tp = 0;

    // Détermination de la distance de SL pour le calcul du lot
    double sl_distance_pts = InpDistancePoints;
    if(InpUseFixedSLTPMode || InpExecutionMode == MODE_INVERTED)
    {
        sl_distance_pts = (InpFixedStopLossPoints > 0) ? InpFixedStopLossPoints : InpDistancePoints;
    }

    double lot = CalculateLotSize(sl_distance_pts);

    // Initialisation du drapeau BE pour le nouveau cycle
    is_be_applied = false;
    cycle_start_time = TimeCurrent();

    // Mode Standard (Buy Stop au-dessus, Sell Stop en-dessous)
    if(InpExecutionMode == MODE_STANDARD)
    {
        buy_price  = NormalizePrice(ref_price + distance);
        buy_sl     = InpUseFixedSLTPMode ? ((InpFixedStopLossPoints > 0) ? NormalizePrice(buy_price - InpFixedStopLossPoints * _Point) : 0) : NormalizePrice(ref_price);
        buy_tp     = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(buy_price + InpFixedTakeProfitPoints * _Point) : 0;

        sell_price = NormalizePrice(ref_price - distance);
        sell_sl    = InpUseFixedSLTPMode ? ((InpFixedStopLossPoints > 0) ? NormalizePrice(sell_price + InpFixedStopLossPoints * _Point) : 0) : NormalizePrice(ref_price);
        sell_tp    = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(sell_price - InpFixedTakeProfitPoints * _Point) : 0;

        if(CheckStopLevel(buy_price, ask) && CheckStopLevel(sell_price, bid))
        {
            if(trade.BuyStop(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Breakout BuyStop"))
                PrintFormat("CYCLE DEBUT: Buy Stop placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", buy_price, buy_sl, buy_tp, lot);
            else
                PrintFormat("ERREUR: Échec du Buy Stop. Code: %d", trade.ResultRetcode());

            if(trade.SellStop(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Breakout SellStop"))
                PrintFormat("CYCLE DEBUT: Sell Stop placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", sell_price, sell_sl, sell_tp, lot);
            else
                PrintFormat("ERREUR: Échec du Sell Stop. Code: %d", trade.ResultRetcode());
        }
    }
    // Mode Inversé (Sell Limit au-dessus, Buy Limit en-dessous)
    else if(InpExecutionMode == MODE_INVERTED)
    {
        sell_price = NormalizePrice(ref_price + distance);
        sell_sl    = (InpFixedStopLossPoints > 0) ? NormalizePrice(sell_price + InpFixedStopLossPoints * _Point) : 0;
        sell_tp    = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(sell_price - InpFixedTakeProfitPoints * _Point) : 0;

        buy_price  = NormalizePrice(ref_price - distance);
        buy_sl     = (InpFixedStopLossPoints > 0) ? NormalizePrice(buy_price - InpFixedStopLossPoints * _Point) : 0;
        buy_tp     = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(buy_price + InpFixedTakeProfitPoints * _Point) : 0;

        if(CheckStopLevel(sell_price, ask) && CheckStopLevel(buy_price, bid))
        {
            if(trade.SellLimit(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Inverted SellLimit"))
                PrintFormat("CYCLE DEBUT: Sell Limit placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", sell_price, sell_sl, sell_tp, lot);
            else
                PrintFormat("ERREUR: Échec du Sell Limit. Code: %d", trade.ResultRetcode());

            if(trade.BuyLimit(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Inverted BuyLimit"))
                PrintFormat("CYCLE DEBUT: Buy Limit placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", buy_price, buy_sl, buy_tp, lot);
            else
                PrintFormat("ERREUR: Échec du Buy Limit. Code: %d", trade.ResultRetcode());
        }
    }
    // Mode Achat Uniquement (Buy Stop uniquement)
    else if(InpExecutionMode == MODE_BUY_ONLY)
    {
        buy_price  = NormalizePrice(ref_price + distance);
        buy_sl     = InpUseFixedSLTPMode ? ((InpFixedStopLossPoints > 0) ? NormalizePrice(buy_price - InpFixedStopLossPoints * _Point) : 0) : NormalizePrice(ref_price);
        buy_tp     = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(buy_price + InpFixedTakeProfitPoints * _Point) : 0;

        if(CheckStopLevel(buy_price, ask))
        {
            if(trade.BuyStop(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Buy Only BuyStop"))
                PrintFormat("CYCLE DEBUT: Buy Stop (Achat Seul) placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", buy_price, buy_sl, buy_tp, lot);
            else
                PrintFormat("ERREUR: Échec du Buy Stop. Code: %d", trade.ResultRetcode());
        }
    }
    // Mode Vente Uniquement (Sell Stop uniquement)
    else if(InpExecutionMode == MODE_SELL_ONLY)
    {
        sell_price = NormalizePrice(ref_price - distance);
        sell_sl    = InpUseFixedSLTPMode ? ((InpFixedStopLossPoints > 0) ? NormalizePrice(sell_price + InpFixedStopLossPoints * _Point) : 0) : NormalizePrice(ref_price);
        sell_tp    = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(sell_price - InpFixedTakeProfitPoints * _Point) : 0;

        if(CheckStopLevel(sell_price, bid))
        {
            if(trade.SellStop(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Sell Only SellStop"))
                PrintFormat("CYCLE DEBUT: Sell Stop (Vente Seule) placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", sell_price, sell_sl, sell_tp, lot);
            else
                PrintFormat("ERREUR: Échec du Sell Stop. Code: %d", trade.ResultRetcode());
        }
    }
}

//+------------------------------------------------------------------+
//| GESTION DYNAMIQUE DE LA POSITION OUVERTE (BE & TRAILING)        |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    // Si le mode SL/TP fixes uniquement est activé, BE et Trailing sont désactivés
    if(InpUseFixedSLTPMode) return;

    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) != InpMagic ||
               PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP);

            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

            //--- 1. GESTION DU BREAK EVEN (Effectué une seule fois par cycle)
            if(!is_be_applied && InpBreakEvenPoints > 0)
            {
                if(type == POSITION_TYPE_BUY)
                {
                    if(bid >= open_price + InpBreakEvenPoints * _Point)
                    {
                        double new_sl = NormalizePrice(open_price);
                        if(current_sl < new_sl)
                        {
                            if(trade.PositionModify(ticket, new_sl, current_tp))
                            {
                                is_be_applied = true;
                                PrintFormat("POSITION #%I64u: Break Even appliqué à %.5f", ticket, new_sl);
                            }
                        }
                    }
                }
                else if(type == POSITION_TYPE_SELL)
                {
                    if(ask <= open_price - InpBreakEvenPoints * _Point)
                    {
                        double new_sl = NormalizePrice(open_price);
                        if(current_sl == 0 || current_sl > new_sl)
                        {
                            if(trade.PositionModify(ticket, new_sl, current_tp))
                            {
                                is_be_applied = true;
                                PrintFormat("POSITION #%I64u: Break Even appliqué à %.5f", ticket, new_sl);
                            }
                        }
                    }
                }
            }

            //--- 2. GESTION DU TRAILING STOP (Progression constante sans jamais reculer)
            if(InpTrailingStartPoints > 0 && InpTrailingDistancePoints > 0)
            {
                if(type == POSITION_TYPE_BUY)
                {
                    if(bid >= open_price + InpTrailingStartPoints * _Point)
                    {
                        double desired_sl = NormalizePrice(bid - InpTrailingDistancePoints * _Point);
                        if(desired_sl > current_sl + _Point) // S'assure que le SL ne fait qu'avancer
                        {
                            if(trade.PositionModify(ticket, desired_sl, current_tp))
                            {
                                PrintFormat("POSITION #%I64u: Trailing Stop mis à jour à %.5f", ticket, desired_sl);
                            }
                        }
                    }
                }
                else if(type == POSITION_TYPE_SELL)
                {
                    if(ask <= open_price - InpTrailingStartPoints * _Point)
                    {
                        double desired_sl = NormalizePrice(ask + InpTrailingDistancePoints * _Point);
                        if(current_sl == 0 || desired_sl < current_sl - _Point) // S'assure que le SL ne fait qu me réculer (avancer en faveur du profit)
                        {
                            if(trade.PositionModify(ticket, desired_sl, current_tp))
                            {
                                PrintFormat("POSITION #%I64u: Trailing Stop mis à jour à %.5f", ticket, desired_sl);
                            }
                        }
                    }
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
    int open_positions = CountOpenPositions();
    int pending_orders = CountPendingOrders();

    // RÈGLE CRUCIALE DE LA STRATÉGIE: Supprimer tout ordre opposé dès qu'une position est active
    if(open_positions > 0 && pending_orders > 0)
    {
        CancelAllPendingOrders();
        pending_orders = CountPendingOrders();
    }

    // SI AUCUNE POSITION ET AUCUN ORDRE => DÉBUT D'UN NOUVEAU CYCLE
    if(open_positions == 0 && pending_orders == 0)
    {
        PlacePendingOrders();
    }
    // SI AUCUNE POSITION MAIS ORDRES EN ATTENTE => VÉRIFIER L'EXPIRATION
    else if(open_positions == 0 && pending_orders > 0)
    {
        CheckPendingOrdersExpiration();
    }
    // SI POSITION OUVERTE => GÉRER LE DYNAMIC BE / TRAILING STOP
    else if(open_positions > 0)
    {
        ManageOpenPosition();
    }
}

//+------------------------------------------------------------------+
//| COMPTAGE DES POSITIONS ET ORDRES EN ATTENTE POUR LE MAGIC NUMBER |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Compte le nombre de positions ouvertes pour cet EA              |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
    int count = 0;
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
               PositionGetString(POSITION_SYMBOL) == _Symbol)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Compte le nombre d'ordres en attente pour cet EA                |
//+------------------------------------------------------------------+
int CountPendingOrders()
{
    int count = 0;
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic &&
               OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                count++;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| GESTION DU CYCLE DE LIFE & PLACEMENT DES ORDRES                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Calcule le prix de référence : Milieu entre Bid et Ask          |
//+------------------------------------------------------------------+
double CalculateReferencePrice()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    return NormalizePrice((ask + bid) / 2.0);
}

//+------------------------------------------------------------------+
//| Annule tous les ordres en attente opposés                        |
//+------------------------------------------------------------------+
void CancelAllPendingOrders()
{
    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic &&
               OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                if(trade.OrderDelete(ticket))
                {
                    PrintFormat("CYCLE [Ordre Opposé]: Ordre en attente #%I64u annulé avec succès.", ticket);
                }
                else
                {
                    PrintFormat("ERREUR [Ordre Opposé]: Échec de l'annulation de l'ordre #%I64u. Code: %d",
                                ticket, trade.ResultRetcode());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifie l'expiration des ordres en attente basée sur le nb bougies|
//+------------------------------------------------------------------+
void CheckPendingOrdersExpiration()
{
    if(InpMaxCandlesPending <= 0) return; // Fonctionnalité désactivée
    if(CountPendingOrders() == 0) return;

    datetime current_bar_time = iTime(_Symbol, _Period, 0);

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic &&
               OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                datetime order_setup_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);

                // Calcul du nombre de barres écoulées depuis le placement
                int bars_elapsed = iBarShift(_Symbol, _Period, order_setup_time);

                if(bars_elapsed >= InpMaxCandlesPending)
                {
                    PrintFormat("EXPIRATION CYCLE: %d bougies écoulées (>= Max: %d). Annulation des ordres.",
                                bars_elapsed, InpMaxCandlesPending);
                    CancelAllPendingOrders();
                    break;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Vérifie si le spread actuel est dans les limites autorisées     |
//+------------------------------------------------------------------+
bool CheckSpread()
{
    if(InpMaxSpreadPoints <= 0) return true; // Désactivé

    long current_spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
    if(current_spread > InpMaxSpreadPoints)
    {
        PrintFormat("FILTRE [Spread]: Spread actuel (%d points) supérieur au max autorisé (%d points).",
                    current_spread, InpMaxSpreadPoints);
        return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Vérifie si l'heure actuelle est dans la plage autorisée          |
//+------------------------------------------------------------------+
bool CheckTimeFilter()
{
    if(!InpUseTimeFilter) return true;

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);

    if(InpStartHour <= InpEndHour)
    {
        if(dt.hour < InpStartHour || dt.hour >= InpEndHour) return false;
    }
    else // Plage chevauchant minuit (ex: 22h à 04h)
    {
        if(dt.hour < InpStartHour && dt.hour >= InpEndHour) return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Vérifie la valeur actuelle de l'ATR par rapport aux seuils       |
//+------------------------------------------------------------------+
bool CheckATRFilter()
{
    if(!InpUseATRFilter) return true;
    if(handle_atr == INVALID_HANDLE) return false;

    double atr_values[];
    ArraySetAsSeries(atr_values, true);

    if(CopyBuffer(handle_atr, 0, 0, 1, atr_values) < 1)
    {
        Print("ERREUR [ATR]: Impossible de lire la valeur de l'ATR.");
        return false;
    }

    double atr_in_points = atr_values[0] / _Point;

    if(atr_in_points < InpATRMinPoints)
    {
        PrintFormat("FILTRE [ATR]: Volatilité insuffisante (ATR = %.1f pts < Min = %.1f pts).",
                    atr_in_points, InpATRMinPoints);
        return false;
    }

    if(InpATRMaxPoints > 0 && atr_in_points > InpATRMaxPoints)
    {
        PrintFormat("FILTRE [ATR]: Volatilité excessive (ATR = %.1f pts > Max = %.1f pts).",
                    atr_in_points, InpATRMaxPoints);
        return false;
    }

    return true;
}
