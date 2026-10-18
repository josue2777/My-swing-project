//+------------------------------------------------------------------+
//|                                           CycleTrading_2_0_EA.mq5 |
//|                                  Copyright 2024, Trading Bot      |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Trading Bot"
#property link      "https://www.mql5.com"
#property version   "2.00"
#property strict

#include <Trade\Trade.mqh>

//--- Direction Enum
enum ENUM_TRADE_DIRECTION
{
   DIRECTION_BOTH = 0,      // Trader dans les 2 sens (Achat & Vente)
   DIRECTION_BUY_ONLY = 1,  // Achat uniquement
   DIRECTION_SELL_ONLY = 2  // Vente uniquement
};

//--- Inputs
input group "=== Parametres Generaux ==="
input double               InpLotSize               = 0.01;            // Taille des lots fixe
input bool                 InpUseRiskLot            = false;           // Activer le calcul de lot par % de capital (3%)
input double               InpRiskPercent           = 3.0;             // Pourcentage du capital a risquer par trade (%)
input int                  InpPendingDistancePoints = 3000;            // Distance des ordres en attente (points)
input int                  InpSLDistancePoints      = 2000;            // Distance du Stop loss (points)
input bool                 InpKeepOppositeOrder     = false;           // Activer Mode 2 (Garder ordre oppose pendant position)
input ENUM_TRADE_DIRECTION InpTradeDirection        = DIRECTION_BOTH;  // Direction du trading
input ulong                InpMagic                 = 112233;          // Magic Number

//--- Global Variables
CTrade trade;
bool   g_position_was_opened = false;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(InpMagic);
   ConfigureFillingMode();
   g_position_was_opened = false;

   PrintFormat("[INIT] CycleTrading 2.0 initialise avec succes sur %s. Magic: %I64u | RiskLot: %s (%.1f%%) | Mode 2: %s | Direction: %d",
               _Symbol, InpMagic, InpUseRiskLot ? "TRUE" : "FALSE", InpRiskPercent, InpKeepOppositeOrder ? "TRUE" : "FALSE", (int)InpTradeDirection);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   PrintFormat("[DEINIT] EA arrete. Raison: %d", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   int active_positions = CountActivePositions();
   int pending_orders   = CountPendingOrders();

   // Suivre si une position a ete ouverte pendant le cycle en cours
   if(active_positions > 0)
   {
      g_position_was_opened = true;
   }

   // Mode 1: Supprimer l'ordre oppose des qu'une position s'ouvre
   if(!InpKeepOppositeOrder && active_positions > 0 && pending_orders > 0)
   {
      DeleteAllPendingOrders();
      pending_orders = CountPendingOrders();
   }

   // Mode 2: Quand une position etait ouverte et est maintenant fermee, supprimer l'ordre restant
   if(InpKeepOppositeOrder && g_position_was_opened && active_positions == 0 && pending_orders > 0)
   {
      DeleteAllPendingOrders();
      pending_orders = CountPendingOrders();
      g_position_was_opened = false;
   }

   // Lancer un nouveau cycle si aucune position active et aucun ordre en attente
   if(active_positions == 0 && pending_orders == 0)
   {
      g_position_was_opened = false;
      StartNewCycle();
   }
}

//+------------------------------------------------------------------+
//| Configurer le mode de remplissage des ordres                   |
//+------------------------------------------------------------------+
void ConfigureFillingMode()
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
//| Normaliser le lot selon les specifications du courtier           |
//+------------------------------------------------------------------+
double NormalizeLot(double lot)
{
   double min_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_lot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step_lot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step_lot <= 0) step_lot = 0.01;

   lot = MathFloor(lot / step_lot) * step_lot;
   if(lot < min_lot) lot = min_lot;
   if(lot > max_lot) lot = max_lot;

   return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Calculer la taille de lot fixe ou par risque de capital (% capital) |
//+------------------------------------------------------------------+
double CalculateLotSize()
{
   if(!InpUseRiskLot)
   {
      return NormalizeLot(InpLotSize);
   }

   double capital = AccountInfoDouble(ACCOUNT_BALANCE);
   if(capital <= 0) capital = AccountInfoDouble(ACCOUNT_EQUITY);

   double risk_amount = capital * (InpRiskPercent / 100.0);
   double tick_value  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tick_size   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double point_size  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   if(tick_value <= 0 || tick_size <= 0 || point_size <= 0 || InpSLDistancePoints <= 0)
   {
      return NormalizeLot(InpLotSize);
   }

   // Perte par lot pour la distance de SL specifiee
   double loss_per_lot = (InpSLDistancePoints * point_size / tick_size) * tick_value;

   if(loss_per_lot <= 0)
   {
      return NormalizeLot(InpLotSize);
   }

   double calculated_lot = risk_amount / loss_per_lot;
   return NormalizeLot(calculated_lot);
}

//+------------------------------------------------------------------+
//| Compter les positions actives pour ce symbole et magic number    |
//+------------------------------------------------------------------+
int CountActivePositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagic && PositionGetString(POSITION_SYMBOL) == _Symbol)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Compter les ordres en attente pour ce symbole et magic number    |
//+------------------------------------------------------------------+
int CountPendingOrders()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
            count++;
      }
   }
   return count;
}

//+------------------------------------------------------------------+
//| Supprimer tous les ordres en attente                             |
//+------------------------------------------------------------------+
void DeleteAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(OrderSelect(ticket))
      {
         if(OrderGetInteger(ORDER_MAGIC) == InpMagic && OrderGetString(ORDER_SYMBOL) == _Symbol)
         {
            if(!trade.OrderDelete(ticket))
            {
               PrintFormat("[ERREUR] Echec suppression ordre #%I64u. Code: %u", ticket, trade.ResultRetcode());
            }
            else
            {
               PrintFormat("[INFO] Ordre en attente #%I64u supprime avec succes.", ticket);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Demarrer un nouveau cycle                                        |
//+------------------------------------------------------------------+
void StartNewCycle()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(ask <= 0 || bid <= 0)
   {
      Print("[ERREUR] Impossible de recuperer Ask/Bid valides.");
      return;
   }

   // 1. Calcul du Prix Actuel de reference = (Ask + Bid) / 2
   double ref_price  = NormalizeDouble((ask + bid) / 2.0, _Digits);
   double point_size = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double trade_lot  = CalculateLotSize();

   // Validation de la distance minimale par rapport au StopLevel du courtier
   long stop_level = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int min_distance = (int)MathMax(InpPendingDistancePoints, stop_level);

   PrintFormat("[CYCLE START 2.0] Nouveau cycle demarre. Prix ref: %.*f | Lot: %.2f (RiskMode: %s)",
               _Digits, ref_price, trade_lot, InpUseRiskLot ? "3%" : "Fixed");

   // Placer Ordre Buy Limit
   if(InpTradeDirection == DIRECTION_BOTH || InpTradeDirection == DIRECTION_BUY_ONLY)
   {
      double buy_price = NormalizeDouble(ref_price - min_distance * point_size, _Digits);
      double buy_sl    = NormalizeDouble(buy_price - InpSLDistancePoints * point_size, _Digits);
      double buy_tp    = ref_price; // TP au prix actuel de reference initial

      if(trade.BuyLimit(trade_lot, buy_price, _Symbol, buy_sl, buy_tp, ORDER_TIME_GTC, 0, "Cycle Trading 2.0 Buy Limit"))
      {
         PrintFormat("[ORDER OK] Buy Limit place a %.*f | SL: %.*f | TP: %.*f", _Digits, buy_price, _Digits, buy_sl, _Digits, buy_tp);
      }
      else
      {
         PrintFormat("[ORDER ERROR] Echec placement Buy Limit. Retcode: %u", trade.ResultRetcode());
      }
   }

   // Placer Ordre Sell Limit
   if(InpTradeDirection == DIRECTION_BOTH || InpTradeDirection == DIRECTION_SELL_ONLY)
   {
      double sell_price = NormalizeDouble(ref_price + min_distance * point_size, _Digits);
      double sell_sl    = NormalizeDouble(sell_price + InpSLDistancePoints * point_size, _Digits);
      double sell_tp    = ref_price; // TP au prix actuel de reference initial

      if(trade.SellLimit(trade_lot, sell_price, _Symbol, sell_sl, sell_tp, ORDER_TIME_GTC, 0, "Cycle Trading 2.0 Sell Limit"))
      {
         PrintFormat("[ORDER OK] Sell Limit place a %.*f | SL: %.*f | TP: %.*f", _Digits, sell_price, _Digits, sell_sl, _Digits, sell_tp);
      }
      else
      {
         PrintFormat("[ORDER ERROR] Echec placement Sell Limit. Retcode: %u", trade.ResultRetcode());
      }
   }
}
//+------------------------------------------------------------------+
