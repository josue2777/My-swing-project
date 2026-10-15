//+------------------------------------------------------------------+
//|                                             BreakoutCycle_EA.mq5 |
//|                                  Copyright 2024, Trading Bot     |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "1.10"
#property description "Expert Advisor MQL5 - Stratégie de Breakout par Cycles Optimisée"
#property description "Gère un cycle complet unique avec ordres en attente, annulation opposée,"
#property description "filtre de tendance EMA, distance dynamique ATR, Break Even dynamique,"
#property description "Trailing Stop progressif et gestion stricte des risques."
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
input int                InpDistancePoints        = 250;             // Distance fixe des ordres en attente (en Points)
input bool               InpUseDynamicDistance    = true;            // Utiliser une distance dynamique basée sur l'ATR
input double             InpATRDistanceMultiplier = 1.5;             // Multiplicateur ATR pour la distance dynamique
input ulong              InpSlippage              = 10;              // Slippage maximal autorisé (en Points)
input int                InpMaxSpreadPoints       = 150;             // Spread maximal autorisé (0 = désactivé)

//--- Filtre de Tendance
input group "=== Filtre de Tendance (EMA) ==="
input bool               InpUseTrendFilter        = true;            // Activer le filtre de tendance EMA
input int                InpMAPeriod              = 200;             // Période de la Moyenne Mobile
input ENUM_MA_METHOD     InpMAType                = MODE_EMA;        // Type de Moyenne Mobile

//--- Gestion du Lot et du Risque
input group "=== Gestion du Capital & Lot ==="
input double             InpFixedLotSize          = 0.01;            // Taille de lot fixe
input bool               InpUseAutoLot            = false;           // Activer le calcul de lot automatique (%)
input double             InpRiskPercent           = 1.0;             // Pourcentage de risque par trade (% Solde)

//--- Gestion Dynamic SL / BE / Trailing / Fixed SL-TP
input group "=== Gestion de Position & Protection ==="
input bool               InpUseFixedSLTPMode      = false;           // Mode SL/TP Fixes uniquement (Désactive BE/ProfitLock/Trailing)
input int                InpFixedStopLossPoints   = 200;             // Stop Loss Fixe en Points (utilisé en Mode Fixe ou Inversé)
input int                InpFixedTakeProfitPoints = 300;             // Take Profit Fixe en Points (0 = Aucun Take Profit)

//--- Break Even avec Protection de Profit
input group "=== Break Even Amélioré ==="
input int                InpBreakEvenTriggerPoints= 200;             // Profit requis pour déclencher le Break Even (en Points)
input int                InpBreakEvenProfitPoints = 50;              // Profit sécurisé au Break Even (en Points)

//--- Profit Lock (Verrouillage Progressif des Gains)
input group "=== Verrouillage des Profits (Profit Lock) ==="
input bool               InpUseProfitLock         = true;            // Activer le verrouillage progressif des gains
input int                InpProfitLockLevel1Points= 400;             // Profit Niveau 1 pour verrouiller (en Points)
input int                InpProfitLockLock1Points = 150;             // Profit sécurisé Niveau 1 (en Points)
input int                InpProfitLockLevel2Points= 800;             // Profit Niveau 2 pour verrouiller (en Points)
input int                InpProfitLockLock2Points = 400;             // Profit sécurisé Niveau 2 (en Points)

//--- Trailing Stop (Fixe ou ATR)
input group "=== Trailing Stop Amélioré ==="
input int                InpTrailingStartPoints   = 250;             // Profit pour activer le Trailing Stop (en Points)
input int                InpTrailingDistancePoints= 200;             // Distance du Trailing Stop fixe (en Points)
input bool               InpUseATRTrailing        = false;           // Activer le Trailing Stop dynamique basé sur l'ATR
input int                InpATRTrailingPeriod     = 14;              // Période de l'ATR Trailing
input ENUM_TIMEFRAMES    InpATRTrailingTimeframe  = PERIOD_CURRENT;  // Timeframe de l'ATR Trailing
input double             InpATRTrailingMultiplier = 1.5;             // Multiplicateur ATR pour la distance de trailing

//--- Sécurité Broker & Délai de Modification
input group "=== Sécurités & Délais Broker ==="
input int                InpMinSecondsBetweenSLMod= 2;               // Délai minimum entre deux modifications de SL (en secondes)

//--- Expiration du Cycle
input group "=== Expiration du Cycle ==="
input int                InpMaxCandlesPending     = 10;              // Nb max de bougies avant expiration des ordres (0 = désactivé)

//--- Filtre ATR (Optionnel)
input group "=== Filtre ATR (Optionnel) ==="
input bool               InpUseATRFilter          = true;            // Activer le filtre ATR
input int                InpATRPeriod             = 14;              // Période de l'ATR
input ENUM_TIMEFRAMES    InpATRTimeframe          = PERIOD_CURRENT;  // Timeframe de l'ATR
input double             InpATRMinPoints          = 80.0;            // Valeur ATR minimale (en Points)
input double             InpATRMaxPoints          = 800.0;           // Valeur ATR maximale (0 = pas de max)

//--- Filtre Horaire (Optionnel)
input group "=== Filtre Horaire (Optionnel) ==="
input bool               InpUseTimeFilter         = false;           // Activer le filtre de session de trading
input int                InpStartHour             = 8;               // Heure de début de session (0-23)
input int                InpEndHour               = 20;              // Heure de fin de session (0-23)

//+------------------------------------------------------------------+
//| Variables Globales                                              |
//+------------------------------------------------------------------+
CTrade         trade;                       // Objet d'exécution des transactions
int            handle_atr = INVALID_HANDLE;          // Handle pour le filtre ATR & distance dynamique
int            handle_atr_trailing = INVALID_HANDLE; // Handle pour le Trailing ATR
int            handle_ma = INVALID_HANDLE;           // Handle pour le filtre de tendance EMA
datetime       cycle_start_time = 0;        // Heure de début du cycle actuel
bool           is_be_applied = false;       // Drapeau indiquant si le Break Even a été appliqué
datetime       last_sl_mod_time = 0;        // Horodatage de la dernière modification du Stop Loss

//+------------------------------------------------------------------+
//| Prototypes de fonctions                                         |
//+------------------------------------------------------------------+
void   SetTradeFillingType();
double NormalizePrice(double price);
double NormalizeVolume(double volume);
bool   CheckStopLevel(double order_price, double market_price);
bool   CheckSLModificationValid(double new_sl, double current_price);
double CalculateLotSize(double sl_distance_points);
double CalculateReferencePrice();
double GetEffectiveDistancePoints();
int    GetTrendDirection();
bool   CheckSpread();
bool   CheckTimeFilter();
bool   CheckATRFilter();
int    CountOpenPositions();
int    CountPendingOrders();
void   CancelAllPendingOrders();
void   CheckPendingOrdersExpiration();
void   PlacePendingOrders();
void   ManageOpenPosition();

//+------------------------------------------------------------------+
//| Configure le type de remplissage (Filling Type) selon le symbole |
//+------------------------------------------------------------------+
void SetTradeFillingType()
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
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Configuration de l'objet CTrade
    trade.SetExpertMagicNumber(InpMagic);
    trade.SetDeviationInPoints(InpSlippage);
    SetTradeFillingType();

    // Initialisation du handle ATR (utilisé pour le filtre ATR et/ou la distance dynamique)
    if(InpUseATRFilter || InpUseDynamicDistance)
    {
        handle_atr = iATR(_Symbol, InpATRTimeframe, InpATRPeriod);
        if(handle_atr == INVALID_HANDLE)
        {
            PrintFormat("ERREUR [OnInit]: Échec de création du handle ATR pour %s.", _Symbol);
            return(INIT_FAILED);
        }
    }

    // Initialisation du filtre de tendance EMA si activé
    if(InpUseTrendFilter)
    {
        handle_ma = iMA(_Symbol, PERIOD_CURRENT, InpMAPeriod, 0, InpMAType, PRICE_CLOSE);
        if(handle_ma == INVALID_HANDLE)
        {
            PrintFormat("ERREUR [OnInit]: Échec de création du handle MA pour %s.", _Symbol);
            return(INIT_FAILED);
        }
    }

    // Initialisation de l'ATR Trailing si activé
    if(InpUseATRTrailing)
    {
        handle_atr_trailing = iATR(_Symbol, InpATRTrailingTimeframe, InpATRTrailingPeriod);
        if(handle_atr_trailing == INVALID_HANDLE)
        {
            PrintFormat("ERREUR [OnInit]: Échec de création du handle ATR Trailing pour %s.", _Symbol);
            return(INIT_FAILED);
        }
    }

    PrintFormat("INITIALISATION [OnInit]: BreakoutCycle_EA v1.10 chargé avec succès sur %s (%s). Magic Number: %i",
                _Symbol, EnumToString(_Period), InpMagic);

    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Libération des handles
    if(handle_atr != INVALID_HANDLE)
    {
        IndicatorRelease(handle_atr);
        handle_atr = INVALID_HANDLE;
    }

    if(handle_ma != INVALID_HANDLE)
    {
        IndicatorRelease(handle_ma);
        handle_ma = INVALID_HANDLE;
    }

    if(handle_atr_trailing != INVALID_HANDLE)
    {
        IndicatorRelease(handle_atr_trailing);
        handle_atr_trailing = INVALID_HANDLE;
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
//| Vérifie la validité d'une modification de Stop Loss             |
//+------------------------------------------------------------------+
bool CheckSLModificationValid(double new_sl, double current_price)
{
    if(InpMinSecondsBetweenSLMod > 0)
    {
        datetime current_time = TimeCurrent();
        if(last_sl_mod_time > 0 && (current_time - last_sl_mod_time) < InpMinSecondsBetweenSLMod)
        {
            return false;
        }
    }

    if(!CheckSpread()) return false;

    int stop_level   = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
    int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

    double min_stop_dist   = stop_level * _Point;
    double min_freeze_dist = freeze_level * _Point;

    double dist_to_market = MathAbs(new_sl - current_price);

    if(dist_to_market < min_stop_dist)
    {
        PrintFormat("REFUS BROKER [StopLevel]: Nouveau SL (%.5f) trop proche du prix (%.5f). Min requis: %d pts",
                    new_sl, current_price, stop_level);
        return false;
    }

    if(freeze_level > 0 && dist_to_market < min_freeze_dist)
    {
        PrintFormat("REFUS BROKER [FreezeLevel]: Ordre gelé par le broker (FreezeLevel = %d pts).", freeze_level);
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

    double point_value_per_lot = (tick_value / tick_size) * _Point;
    double calculated_lot     = risk_amount / (sl_distance_points * point_value_per_lot);

    return NormalizeVolume(calculated_lot);
}

//+------------------------------------------------------------------+
//| Calcule la distance effective des ordres (Fixe ou Dynamique ATR) |
//+------------------------------------------------------------------+
double GetEffectiveDistancePoints()
{
    if(InpUseDynamicDistance && handle_atr != INVALID_HANDLE)
    {
        double atr_val[];
        ArraySetAsSeries(atr_val, true);
        if(CopyBuffer(handle_atr, 0, 0, 1, atr_val) > 0)
        {
            double atr_points = atr_val[0] / _Point;
            double dyn_dist = atr_points * InpATRDistanceMultiplier;
            if(dyn_dist > 10.0) return dyn_dist;
        }
    }
    return (double)InpDistancePoints;
}

//+------------------------------------------------------------------+
//| Obtenir la direction de tendance de la Moyenne Mobile            |
//| Retourne: 1 (Haussier), -1 (Baissier), 0 (Neutre/Non actif)      |
//+------------------------------------------------------------------+
int GetTrendDirection()
{
    if(!InpUseTrendFilter || handle_ma == INVALID_HANDLE) return 0;

    double ma_val[];
    ArraySetAsSeries(ma_val, true);
    if(CopyBuffer(handle_ma, 0, 0, 1, ma_val) < 1)
    {
        Print("ERREUR [MA]: Impossible de lire la valeur de la Moyenne Mobile.");
        return 0;
    }

    double close_prices[];
    ArraySetAsSeries(close_prices, true);
    if(CopyClose(_Symbol, PERIOD_CURRENT, 0, 1, close_prices) < 1)
    {
        return 0;
    }

    double current_close = close_prices[0];

    if(current_close > ma_val[0]) return 1;  // Tendance haussière -> Achats autorisés
    if(current_close < ma_val[0]) return -1; // Tendance baissière -> Ventes autorisées

    return 0;
}

//+------------------------------------------------------------------+
//| PLACEMENT DES ORDRES EN ATTENTE POUR UN NOUVEAU CYCLE           |
//+------------------------------------------------------------------+
void PlacePendingOrders()
{
    // Vérification des filtres généraux avant de lancer un cycle
    if(!CheckSpread() || !CheckTimeFilter() || !CheckATRFilter()) return;

    double ref_price = CalculateReferencePrice();
    double dist_pts  = GetEffectiveDistancePoints();
    double distance  = dist_pts * _Point;

    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    double buy_price  = 0;
    double sell_price = 0;

    double buy_sl  = 0;
    double sell_sl = 0;

    double buy_tp  = 0;
    double sell_tp = 0;

    // Détermination de la distance de SL pour le calcul du lot
    double sl_distance_pts = dist_pts;
    if(InpUseFixedSLTPMode || InpExecutionMode == MODE_INVERTED)
    {
        sl_distance_pts = (InpFixedStopLossPoints > 0) ? InpFixedStopLossPoints : dist_pts;
    }

    double lot = CalculateLotSize(sl_distance_pts);

    // Récupération de la direction du filtre de tendance
    int trend = GetTrendDirection();

    // Initialisation du drapeau BE pour le nouveau cycle
    is_be_applied = false;
    cycle_start_time = TimeCurrent();

    // Mode Standard (Buy Stop au-dessus, Sell Stop en-dessous)
    if(InpExecutionMode == MODE_STANDARD)
    {
        // Place Buy Stop si la tendance est neutre (0) ou haussière (1)
        if(trend >= 0)
        {
            buy_price  = NormalizePrice(ref_price + distance);
            buy_sl     = InpUseFixedSLTPMode ? ((InpFixedStopLossPoints > 0) ? NormalizePrice(buy_price - InpFixedStopLossPoints * _Point) : 0) : NormalizePrice(ref_price);
            buy_tp     = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(buy_price + InpFixedTakeProfitPoints * _Point) : 0;

            if(CheckStopLevel(buy_price, ask))
            {
                if(trade.BuyStop(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Breakout BuyStop"))
                    PrintFormat("CYCLE DEBUT: Buy Stop placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", buy_price, buy_sl, buy_tp, lot);
                else
                    PrintFormat("ERREUR: Échec du Buy Stop. Code: %d", trade.ResultRetcode());
            }
        }

        // Place Sell Stop si la tendance est neutre (0) ou baissière (-1)
        if(trend <= 0)
        {
            sell_price = NormalizePrice(ref_price - distance);
            sell_sl    = InpUseFixedSLTPMode ? ((InpFixedStopLossPoints > 0) ? NormalizePrice(sell_price + InpFixedStopLossPoints * _Point) : 0) : NormalizePrice(ref_price);
            sell_tp    = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(sell_price - InpFixedTakeProfitPoints * _Point) : 0;

            if(CheckStopLevel(sell_price, bid))
            {
                if(trade.SellStop(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Breakout SellStop"))
                    PrintFormat("CYCLE DEBUT: Sell Stop placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", sell_price, sell_sl, sell_tp, lot);
                else
                    PrintFormat("ERREUR: Échec du Sell Stop. Code: %d", trade.ResultRetcode());
            }
        }
    }
    // Mode Inversé (Sell Limit au-dessus, Buy Limit en-dessous)
    else if(InpExecutionMode == MODE_INVERTED)
    {
        if(trend >= 0)
        {
            sell_price = NormalizePrice(ref_price + distance);
            sell_sl    = (InpFixedStopLossPoints > 0) ? NormalizePrice(sell_price + InpFixedStopLossPoints * _Point) : 0;
            sell_tp    = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(sell_price - InpFixedTakeProfitPoints * _Point) : 0;

            if(CheckStopLevel(sell_price, ask))
            {
                if(trade.SellLimit(lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Inverted SellLimit"))
                    PrintFormat("CYCLE DEBUT: Sell Limit placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", sell_price, sell_sl, sell_tp, lot);
                else
                    PrintFormat("ERREUR: Échec du Sell Limit. Code: %d", trade.ResultRetcode());
            }
        }

        if(trend <= 0)
        {
            buy_price  = NormalizePrice(ref_price - distance);
            buy_sl     = (InpFixedStopLossPoints > 0) ? NormalizePrice(buy_price - InpFixedStopLossPoints * _Point) : 0;
            buy_tp     = (InpFixedTakeProfitPoints > 0) ? NormalizePrice(buy_price + InpFixedTakeProfitPoints * _Point) : 0;

            if(CheckStopLevel(buy_price, bid))
            {
                if(trade.BuyLimit(lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Inverted BuyLimit"))
                    PrintFormat("CYCLE DEBUT: Buy Limit placé à %.5f (SL: %.5f, TP: %.5f, Lot: %.2f)", buy_price, buy_sl, buy_tp, lot);
                else
                    PrintFormat("ERREUR: Échec du Buy Limit. Code: %d", trade.ResultRetcode());
            }
        }
    }
    // Mode Achat Uniquement (Buy Stop uniquement)
    else if(InpExecutionMode == MODE_BUY_ONLY)
    {
        if(trend >= 0)
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
    }
    // Mode Vente Uniquement (Sell Stop uniquement)
    else if(InpExecutionMode == MODE_SELL_ONLY)
    {
        if(trend <= 0)
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
}

//+------------------------------------------------------------------+
//| GESTION DYNAMIQUE DE LA POSITION OUVERTE (BE, PROFIT LOCK & TS) |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
    // Mode SL/TP fixes uniquement => Désactiver BE, ProfitLock et Trailing
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

            double target_sl = current_sl;

            //--- BREAK EVEN AVEC PROTECTION DE PROFIT
            if(InpBreakEvenTriggerPoints > 0)
            {
                if(type == POSITION_TYPE_BUY)
                {
                    if(bid >= open_price + InpBreakEvenTriggerPoints * _Point)
                    {
                        double be_sl = NormalizePrice(open_price + InpBreakEvenProfitPoints * _Point);
                        if(be_sl > target_sl + _Point)
                        {
                            target_sl = be_sl;
                            is_be_applied = true;
                        }
                    }
                }
                else if(type == POSITION_TYPE_SELL)
                {
                    if(ask <= open_price - InpBreakEvenTriggerPoints * _Point)
                    {
                        double be_sl = NormalizePrice(open_price - InpBreakEvenProfitPoints * _Point);
                        if(target_sl == 0 || be_sl < target_sl - _Point)
                        {
                            target_sl = be_sl;
                            is_be_applied = true;
                        }
                    }
                }
            }

            //--- VERROUILLAGE DES PROFITS (PROFIT LOCK PROGRESSIF)
            if(InpUseProfitLock)
            {
                if(type == POSITION_TYPE_BUY)
                {
                    // Profit Lock Level 2
                    if(InpProfitLockLevel2Points > 0 && bid >= open_price + InpProfitLockLevel2Points * _Point)
                    {
                        double lock2_sl = NormalizePrice(open_price + InpProfitLockLock2Points * _Point);
                        if(lock2_sl > target_sl + _Point) target_sl = lock2_sl;
                    }
                    // Profit Lock Level 1
                    else if(InpProfitLockLevel1Points > 0 && bid >= open_price + InpProfitLockLevel1Points * _Point)
                    {
                        double lock1_sl = NormalizePrice(open_price + InpProfitLockLock1Points * _Point);
                        if(lock1_sl > target_sl + _Point) target_sl = lock1_sl;
                    }
                }
                else if(type == POSITION_TYPE_SELL)
                {
                    // Profit Lock Level 2
                    if(InpProfitLockLevel2Points > 0 && ask <= open_price - InpProfitLockLevel2Points * _Point)
                    {
                        double lock2_sl = NormalizePrice(open_price - InpProfitLockLock2Points * _Point);
                        if(target_sl == 0 || lock2_sl < target_sl - _Point) target_sl = lock2_sl;
                    }
                    // Profit Lock Level 1
                    else if(InpProfitLockLevel1Points > 0 && ask <= open_price - InpProfitLockLevel1Points * _Point)
                    {
                        double lock1_sl = NormalizePrice(open_price - InpProfitLockLock1Points * _Point);
                        if(target_sl == 0 || lock1_sl < target_sl - _Point) target_sl = lock1_sl;
                    }
                }
            }

            //--- TRAILING STOP AMÉLIORÉ (FIXE OU ATR)
            if(InpTrailingStartPoints > 0)
            {
                double trailing_dist = InpTrailingDistancePoints * _Point;

                // Calcul ATR de la distance si le Trailing ATR est activé
                if(InpUseATRTrailing && handle_atr_trailing != INVALID_HANDLE)
                {
                    double atr_vals[];
                    ArraySetAsSeries(atr_vals, true);
                    if(CopyBuffer(handle_atr_trailing, 0, 0, 1, atr_vals) > 0)
                    {
                        trailing_dist = atr_vals[0] * InpATRTrailingMultiplier;
                    }
                }

                if(type == POSITION_TYPE_BUY)
                {
                    if(bid >= open_price + InpTrailingStartPoints * _Point)
                    {
                        double desired_ts_sl = NormalizePrice(bid - trailing_dist);
                        if(desired_ts_sl > target_sl + _Point)
                        {
                            target_sl = desired_ts_sl;
                        }
                    }
                }
                else if(type == POSITION_TYPE_SELL)
                {
                    if(ask <= open_price - InpTrailingStartPoints * _Point)
                    {
                        double desired_ts_sl = NormalizePrice(ask + trailing_dist);
                        if(target_sl == 0 || desired_ts_sl < target_sl - _Point)
                        {
                            target_sl = desired_ts_sl;
                        }
                    }
                }
            }

            //--- VALIDATION ET EMPECHEMENT DE TOUT RECUL DE SL
            bool is_valid_mod = false;
            double current_check_price = (type == POSITION_TYPE_BUY) ? bid : ask;

            if(type == POSITION_TYPE_BUY && target_sl > current_sl + _Point)
            {
                is_valid_mod = CheckSLModificationValid(target_sl, current_check_price);
            }
            else if(type == POSITION_TYPE_SELL && (current_sl == 0 || target_sl < current_sl - _Point))
            {
                is_valid_mod = CheckSLModificationValid(target_sl, current_check_price);
            }

            // Application de la modification auprès du broker
            if(is_valid_mod)
            {
                if(trade.PositionModify(ticket, target_sl, current_tp))
                {
                    last_sl_mod_time = TimeCurrent();
                    PrintFormat("POSITION #%I64u: Stop Loss mis à jour à %.5f (Prix actuel: %.5f)",
                                ticket, target_sl, current_check_price);
                }
                else
                {
                    PrintFormat("ERREUR MODIFICATION #%I64u: Échec de modif du SL à %.5f. Retcode: %d",
                                ticket, target_sl, trade.ResultRetcode());
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

    // Supprimer tout ordre opposé dès qu'une position est active
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
//| COMPTAGE DES POSITIONS ET ORDRES EN ATTENTE                      |
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
//| Calcule le prix de référence : Milieu entre Bid et Ask          |
//+------------------------------------------------------------------+
double CalculateReferencePrice()
{
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    return NormalizePrice((ask + bid) / 2.0);
}

//+------------------------------------------------------------------+
//| Annule tous les ordres en attente                                |
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
    if(InpMaxCandlesPending <= 0) return;
    if(CountPendingOrders() == 0) return;

    for(int i = OrdersTotal() - 1; i >= 0; i--)
    {
        ulong ticket = OrderGetTicket(i);
        if(OrderSelect(ticket))
        {
            if(OrderGetInteger(ORDER_MAGIC) == InpMagic &&
               OrderGetString(ORDER_SYMBOL) == _Symbol)
            {
                datetime order_setup_time = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
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
    if(InpMaxSpreadPoints <= 0) return true;

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
    else
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
