//+------------------------------------------------------------------+
//|                                     BuyLowSellHigh_Gold_EA.mq5    |
//|                                  Copyright 2024, Trading EA      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading EA"
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Expert Advisor 'Buy Low, Sell High' spécialement optimisé pour le Gold (XAUUSD)."
#property description "Stratégie basée sur RSI, Bollinger Bands, filtre de tendance EMA 200, et gestion avancée du risque."
#property strict

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_LOT_MODE
  {
   LOT_MODE_TIERED = 0, // Taille de lot dynamique selon la balance (Tiered)
   LOT_MODE_FIXED  = 1, // Taille de lot fixe
   LOT_MODE_RISK   = 2  // Pourcentage de risque par trade
  };

//--- Inputs Général & Trading
input group "=== Paramètres Généraux ==="
input ulong         InpMagic          = 777888;     // Numéro Magique (Magic Number)
input ENUM_LOT_MODE InpLotMode        = LOT_MODE_TIERED; // Mode de gestion des lots
input double        InpFixedLot       = 0.01;       // Lot fixe (si mode Fixe)
input double        InpRiskPercent    = 1.0;        // Risque en % par trade (si mode Risque)
input int           InpMaxSpread      = 60;         // Spread Max autorise (en points, ex: 60 = $0.60 pour Gold)

input group "=== Indicateurs Stratégie (Gold Optimisé) ==="
input int           InpRsiPeriod      = 14;         // RSI Période
input double        InpRsiOversold    = 30.0;       // RSI Niveau Survendu (Buy Low)
input double        InpRsiOverbought  = 70.0;       // RSI Niveau Suracheté (Sell High)
input int           InpBBPeriod       = 20;         // Bollinger Bands Période
input double        InpBBDev          = 2.0;        // Bollinger Bands Déviation
input bool          InpUseEmaFilter   = true;       // Activer le filtre de tendance EMA 200
input int           InpEmaPeriod      = 200;        // EMA Période de Tendance

input group "=== Stop Loss & Take Profit (Points XAUUSD) ==="
input bool          InpUseAtrSLTP     = false;      // Utiliser ATR pour SL/TP dynamique
input int           InpAtrPeriod      = 14;         // ATR Période
input double        InpAtrMultSL      = 1.5;        // Multiplicateur ATR pour Stop Loss
input double        InpAtrMultTP      = 3.0;        // Multiplicateur ATR pour Take Profit
input int           InpStopLossPoints = 400;        // Stop Loss fixe (points, 400 = $4.00)
input int           InpTakeProfitPts  = 800;        // Take Profit fixe (points, 800 = $8.00)

input group "=== Gestion du Breakeven & Trailing Stop ==="
input bool          InpUseBreakeven   = true;       // Activer Breakeven
input int           InpBETriggerPts   = 300;        // Points de profit pour déclencher Breakeven
input int           InpBELockPts      = 50;         // Points de profit verrouillés au Breakeven
input bool          InpUseTrailing    = true;       // Activer Trailing Stop
input int           InpTrailingStart  = 400;        // Points de profit pour démarrer Trailing
input int           InpTrailingDist   = 250;        // Distance du Trailing Stop (points)
input int           InpTrailingStep   = 50;         // Pas de mise à jour du Trailing (points)

//--- Global Variables
CTrade         trade;
int            handle_rsi       = INVALID_HANDLE;
int            handle_bb        = INVALID_HANDLE;
int            handle_ema       = INVALID_HANDLE;
int            handle_atr       = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagic);

   // Création des handles des indicateurs
   handle_rsi = iRSI(_Symbol, _Period, InpRsiPeriod, PRICE_CLOSE);
   handle_bb  = iBands(_Symbol, _Period, InpBBPeriod, 0, InpBBDev, PRICE_CLOSE);
   handle_ema = iMA(_Symbol, _Period, InpEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   handle_atr = iATR(_Symbol, _Period, InpAtrPeriod);

   if(handle_rsi == INVALID_HANDLE || handle_bb == INVALID_HANDLE ||
      handle_ema == INVALID_HANDLE || handle_atr == INVALID_HANDLE)
     {
      Print("Erreur lors de l'initialisation des indicateurs.");
      return(INIT_FAILED);
     }

   Print("BuyLowSellHigh EA pour Gold initialise avec succes.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   // Libération des handles
   if(handle_rsi != INVALID_HANDLE) IndicatorRelease(handle_rsi);
   if(handle_bb  != INVALID_HANDLE) IndicatorRelease(handle_bb);
   if(handle_ema != INVALID_HANDLE) IndicatorRelease(handle_ema);
   if(handle_atr != INVALID_HANDLE) IndicatorRelease(handle_atr);

   Comment("");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // Gestion des positions ouvertes (Breakeven & Trailing Stop)
   ManagePositions();

   // Mise à jour du Dashboard sur le graphique
   UpdateDashboard();

   // Vérification du contrôle des nouvelles bougies pour les signaux d'entrée
   if(!IsNewBar()) return;

   // Vérification du spread max
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpread)
     {
      PrintFormat("Spread trop eleve: %d points (Max autorise: %d)", spread, InpMaxSpread);
      return;
     }

   // Vérification des signaux d'achat et vente
   CheckEntrySignals();
  }

//+------------------------------------------------------------------+
//| Détecte l'apparition d'une nouvelle bougie                       |
//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime last_bar_time = 0;
   datetime current_bar_time = iTime(_Symbol, _Period, 0);

   if(current_bar_time != last_bar_time)
     {
      last_bar_time = current_bar_time;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Calcul dynamique du lot selon la balance ou le risque            |
//+------------------------------------------------------------------+
double GetLotSize(double sl_distance_points)
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);

   if(InpLotMode == LOT_MODE_FIXED)
     {
      return InpFixedLot;
     }

   if(InpLotMode == LOT_MODE_TIERED)
     {
      if(balance <= 1000)   return 0.01;
      if(balance <= 5000)   return 0.03;
      if(balance <= 13000)  return 0.05;
      if(balance <= 50000)  return 0.10;
      if(balance <= 150000) return 0.50;
      if(balance <= 350000) return 1.00;
      return 3.00;
     }

   if(InpLotMode == LOT_MODE_RISK)
     {
      double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double point      = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

      if(tick_size == 0 || tick_value == 0 || sl_distance_points <= 0) return 0.01;

      double risk_amount = balance * (InpRiskPercent / 100.0);
      double point_value = tick_value * (point / tick_size);
      double calculated_lot = risk_amount / (sl_distance_points * point_value);

      double min_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      double max_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
      double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

      calculated_lot = MathFloor(calculated_lot / step_lot) * step_lot;
      calculated_lot = MathMax(min_lot, MathMin(max_lot, calculated_lot));

      return calculated_lot;
     }

   return 0.01;
  }

//+------------------------------------------------------------------+
//| Analyse et exécution des signaux Buy Low / Sell High             |
//+------------------------------------------------------------------+
void CheckEntrySignals()
  {
   // Ne pas ouvrir de nouvelle position si une position est déjà ouverte sur cet EA
   if(CountOpenPositions() > 0) return;

   // Lecture des buffers d'indicateurs sur la bougie 1 (dernière bougie clôturée)
   double rsi_buf[2], bb_upper_buf[2], bb_lower_buf[2], bb_middle_buf[2], ema_buf[2], atr_buf[1];

   if(CopyBuffer(handle_rsi, 0, 1, 2, rsi_buf) < 2) return;
   if(CopyBuffer(handle_bb, 1, 1, 2, bb_upper_buf) < 2) return; // Upper Band
   if(CopyBuffer(handle_bb, 2, 1, 2, bb_lower_buf) < 2) return; // Lower Band
   if(CopyBuffer(handle_bb, 0, 1, 2, bb_middle_buf) < 2) return; // Middle Band
   if(CopyBuffer(handle_ema, 0, 1, 2, ema_buf) < 2) return;
   if(CopyBuffer(handle_atr, 0, 1, 1, atr_buf) < 1) return;

   double close1 = iClose(_Symbol, _Period, 1);
   double low1   = iLow(_Symbol, _Period, 1);
   double high1  = iHigh(_Symbol, _Period, 1);
   double open1  = iOpen(_Symbol, _Period, 1);

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   // --- STRATÉGIE BUY LOW (Achat Bas) ---
   // Conditions:
   // 1. RSI en zone de survente (< InpRsiOversold)
   // 2. Le prix a touché/enfoncé la bande de Bollinger inférieure (low1 <= bb_lower_buf[1])
   // 3. Confirmation de rejet hausser: bougie fermée verte (close1 > open1)
   // 4. Filtre EMA: Si activé, le prix est au-dessus de l'EMA 200 (tendance globale haussière)
   bool buy_condition = (rsi_buf[1] <= InpRsiOversold) &&
                        (low1 <= bb_lower_buf[1]) &&
                        (close1 > open1);

   if(InpUseEmaFilter)
     {
      buy_condition = buy_condition && (close1 > ema_buf[1]);
     }

   // --- STRATÉGIE SELL HIGH (Vente Haute) ---
   // Conditions:
   // 1. RSI en zone de surachat (> InpRsiOverbought)
   // 2. Le prix a touché/enfoncé la bande de Bollinger supérieure (high1 >= bb_upper_buf[1])
   // 3. Confirmation de rejet baissier: bougie fermée rouge (close1 < open1)
   // 4. Filtre EMA: Si activé, le prix est en-dessous de l'EMA 200 (tendance globale baissière)
   bool sell_condition = (rsi_buf[1] >= InpRsiOverbought) &&
                         (high1 >= bb_upper_buf[1]) &&
                         (close1 < open1);

   if(InpUseEmaFilter)
     {
      sell_condition = sell_condition && (close1 < ema_buf[1]);
     }

   // Calcul SL/TP
   double sl_pts = InpStopLossPoints;
   double tp_pts = InpTakeProfitPts;

   if(InpUseAtrSLTP && atr_buf[0] > 0)
     {
      sl_pts = (atr_buf[0] * InpAtrMultSL) / point;
      tp_pts = (atr_buf[0] * InpAtrMultTP) / point;
     }

   // Exécution Achat
   if(buy_condition)
     {
      double sl = ask - sl_pts * point;
      double tp = ask + tp_pts * point;
      double lot = GetLotSize(sl_pts);

      if(trade.Buy(lot, _Symbol, ask, sl, tp, "Buy Low Gold"))
        {
         PrintFormat("BUY LOW Execute: Lot=%.2f, Price=%.2f, SL=%.2f, TP=%.2f", lot, ask, sl, tp);
        }
      return;
     }

   // Exécution Vente
   if(sell_condition)
     {
      double sl = bid + sl_pts * point;
      double tp = bid - tp_pts * point;
      double lot = GetLotSize(sl_pts);

      if(trade.Sell(lot, _Symbol, bid, sl, tp, "Sell High Gold"))
        {
         PrintFormat("SELL HIGH Execute: Lot=%.2f, Price=%.2f, SL=%.2f, TP=%.2f", lot, bid, sl, tp);
        }
      return;
     }
  }

//+------------------------------------------------------------------+
//| Compte les positions ouvertes gérées par cet EA                 |
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
//| Gestion des Trailing Stop et Breakeven                           |
//+------------------------------------------------------------------+
void ManagePositions()
  {
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

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
         double current_price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

         // --- GESTION BREAKEVEN ---
         if(InpUseBreakeven)
           {
            if(type == POSITION_TYPE_BUY)
              {
               if(current_price - open_price >= InpBETriggerPts * point)
                 {
                  double new_sl = open_price + InpBELockPts * point;
                  if(current_sl < new_sl)
                    {
                     trade.PositionModify(ticket, new_sl, current_tp);
                     PrintFormat("Breakeven applique sur Buy #%d: Nouveau SL = %.2f", ticket, new_sl);
                    }
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               if(open_price - current_price >= InpBETriggerPts * point)
                 {
                  double new_sl = open_price - InpBELockPts * point;
                  if(current_sl == 0 || current_sl > new_sl)
                    {
                     trade.PositionModify(ticket, new_sl, current_tp);
                     PrintFormat("Breakeven applique sur Sell #%d: Nouveau SL = %.2f", ticket, new_sl);
                    }
                 }
              }
           }

         // --- GESTION TRAILING STOP ---
         if(InpUseTrailing)
           {
            if(type == POSITION_TYPE_BUY)
              {
               if(current_price - open_price >= InpTrailingStart * point)
                 {
                  double new_sl = current_price - InpTrailingDist * point;
                  if(new_sl > current_sl + InpTrailingStep * point)
                    {
                     trade.PositionModify(ticket, new_sl, current_tp);
                     PrintFormat("Trailing Stop applique sur Buy #%d: Nouveau SL = %.2f", ticket, new_sl);
                    }
                 }
              }
            else if(type == POSITION_TYPE_SELL)
              {
               if(open_price - current_price >= InpTrailingStart * point)
                 {
                  double new_sl = current_price + InpTrailingDist * point;
                  if(current_sl == 0 || new_sl < current_sl - InpTrailingStep * point)
                    {
                     trade.PositionModify(ticket, new_sl, current_tp);
                     PrintFormat("Trailing Stop applique sur Sell #%d: Nouveau SL = %.2f", ticket, new_sl);
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Dashboard d'information sur le graphique                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   double rsi_val[1], ema_val[1];
   if(CopyBuffer(handle_rsi, 0, 0, 1, rsi_val) < 1) return;
   if(CopyBuffer(handle_ema, 0, 0, 1, ema_val) < 1) return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);

   string text = "=========================================\n";
   text += "    EA BUY LOW & SELL HIGH (GOLD XAUUSD)  \n";
   text += "=========================================\n";
   text += StringFormat(" Symbole        : %s\n", _Symbol);
   text += StringFormat(" Prix Actuel    : %.2f | Spread: %d pts\n", ask, spread);
   text += StringFormat(" RSI (14)       : %.2f (Survente < %.1f | Surachat > %.1f)\n", rsi_val[0], InpRsiOversold, InpRsiOverbought);
   text += StringFormat(" EMA (%d)      : %.2f (%s)\n", InpEmaPeriod, ema_val[0], (ask > ema_val[0] ? "Tendance HAUSSIERE" : "Tendance BAISSIERE"));
   text += StringFormat(" Dynamic Lot    : Mode %s\n", EnumToString(InpLotMode));
   text += StringFormat(" Positions Ex.  : %d / 1\n", CountOpenPositions());
   text += "=========================================";

   Comment(text);
  }
//+------------------------------------------------------------------+
