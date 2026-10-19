//+------------------------------------------------------------------+
//|                                   XAUUSD_Momentum_Scalper_EA.mq5 |
//|                             Copyright 2025, High-Yield Quant Lab |
//|                           Inspired by Zura Kakushadze (151 Strat) |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, High-Yield Quant Lab"
#property link      "https://github.com"
#property version   "1.10"
#property description "Expert Advisor XAUUSD High-Yield Momentum Scalper based on Parabolic SAR, Fast EMA Channel Breakout, and Dynamic Risk Compounding"

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_RISK_MODE
  {
   RISK_FIXED_LOT,       // Fixed Lot Size
   RISK_PERCENT_EQUITY,  // Percent of Equity per Trade (Compounding)
   RISK_TIERED_BALANCE   // Tiered Capital Risk Allocation
  };

//--- Input Parameters
input group "== Strategy Parameters =="
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_M5;  // Strategy Timeframe
input double          InpSarStep           = 0.02;       // Parabolic SAR Step
input double          InpSarMaximum        = 0.20;       // Parabolic SAR Maximum
input int             InpFastEMAPeriod     = 8;          // Fast EMA Period
input int             InpSlowEMAPeriod     = 21;         // Slow EMA Period
input int             InpATRPeriod         = 14;         // ATR Volatility Period
input double          InpMinATRPoints      = 80.0;       // Minimum Volatility ATR Filter (Points)
input double          InpBreakoutPoints    = 30.0;       // Channel Breakout Offset (Points)

input group "== Risk & Capital Management (Target ~50%/Month) =="
input ENUM_RISK_MODE InpRiskMode          = RISK_PERCENT_EQUITY; // Risk Allocation Mode
input double          InpRiskPercent       = 2.5;        // Risk Percent Per Trade (%)
input double          InpFixedLot          = 0.10;       // Fixed Lot Size
input int             InpStopLossPoints    = 250;        // Stop Loss in Points (e.g. 250 = $2.50 XAU)
input int             InpTakeProfitPoints  = 500;        // Take Profit in Points (e.g. 500 = $5.00 XAU)
input int             InpBreakEvenPoints   = 150;        // Trigger Break-Even in Points
input int             InpBreakEvenProfit   = 30;         // Profit Lock in Points on Break-Even
input int             InpTrailingStopPoints= 200;        // Trailing Stop Distance in Points
input int             InpTrailingStepPoints= 50;         // Trailing Step in Points
input int             InpMaxSpreadPoints   = 250;        // Max Allowed Spread in Points
input int             InpMaxOpenTrades     = 2;          // Max Open Concurrent Trades
input ulong           InpMagicNumber       = 151888;     // Magic Number

input group "== Session & Time Filters =="
input bool            InpUseTradingHours   = true;       // Enable Session Time Filter
input int             InpStartHour         = 7;          // Trading Session Start Hour (Server Time)
input int             InpEndHour           = 21;         // Trading Session End Hour (Server Time)

//--- Global Variables
CTrade         trade;
int            handle_sar   = INVALID_HANDLE;
int            handle_ema_f = INVALID_HANDLE;
int            handle_ema_s = INVALID_HANDLE;
int            handle_atr   = INVALID_HANDLE;
datetime       last_bar_time= 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetMarginMode();

   // Determine symbol filling mode
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);
   if((filling & SYMBOL_FILLING_FOK) != 0)
      trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if((filling & SYMBOL_FILLING_IOC) != 0)
      trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      trade.SetTypeFilling(ORDER_FILLING_RETURN);

   // Initialize Indicator Handles
   handle_sar = iSAR(_Symbol, InpTimeframe, InpSarStep, InpSarMaximum);
   if(handle_sar == INVALID_HANDLE)
     {
      Print("Error creating Parabolic SAR handle!");
      return(INIT_FAILED);
     }

   handle_ema_f = iMA(_Symbol, InpTimeframe, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema_f == INVALID_HANDLE)
     {
      Print("Error creating Fast EMA handle!");
      return(INIT_FAILED);
     }

   handle_ema_s = iMA(_Symbol, InpTimeframe, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(handle_ema_s == INVALID_HANDLE)
     {
      Print("Error creating Slow EMA handle!");
      return(INIT_FAILED);
     }

   handle_atr = iATR(_Symbol, InpTimeframe, InpATRPeriod);
   if(handle_atr == INVALID_HANDLE)
     {
      Print("Error creating ATR handle!");
      return(INIT_FAILED);
     }

   Print("XAUUSD_Momentum_Scalper_EA initialized successfully.");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(handle_sar   != INVALID_HANDLE) IndicatorRelease(handle_sar);
   if(handle_ema_f != INVALID_HANDLE) IndicatorRelease(handle_ema_f);
   if(handle_ema_s != INVALID_HANDLE) IndicatorRelease(handle_ema_s);
   if(handle_atr   != INVALID_HANDLE) IndicatorRelease(handle_atr);
   Print("XAUUSD_Momentum_Scalper_EA deinitialized.");
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   // 1. Manage Active Positions
   ManageOpenPositions();

   // 2. Check Bar Confirmation for New Signal Execution
   datetime current_bar_time = iTime(_Symbol, InpTimeframe, 0);
   if(current_bar_time == last_bar_time)
      return; // Wait for new bar

   // 3. Spread Filter Check
   long current_spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(current_spread > InpMaxSpreadPoints)
     {
      return;
     }

   // 4. Session Time Filter
   if(InpUseTradingHours && !IsTradingSessionActive())
      return;

   // 5. Check Concurrent Positions Count
   if(CountActivePositions() >= InpMaxOpenTrades)
      return;

   // 6. Fetch Indicator Values for Bar 1 (Closed Bar)
   double sar_val[1], ema_f_val[1], ema_s_val[1], atr_val[1];

   if(CopyBuffer(handle_sar, 0, 1, 1, sar_val) < 1 ||
      CopyBuffer(handle_ema_f, 0, 1, 1, ema_f_val) < 1 ||
      CopyBuffer(handle_ema_s, 0, 1, 1, ema_s_val) < 1 ||
      CopyBuffer(handle_atr, 0, 1, 1, atr_val) < 1)
     {
      Print("Error reading indicator buffers!");
      return;
     }

   double close_1 = iClose(_Symbol, InpTimeframe, 1);
   double high_1  = iHigh(_Symbol, InpTimeframe, 1);
   double low_1   = iLow(_Symbol, InpTimeframe, 1);

   // Volatility Threshold Check
   double atr_points = atr_val[0] / _Point;
   if(atr_points < InpMinATRPoints)
      return;

   // Original Strategy Signal Conditions
   bool buy_trend  = (close_1 > sar_val[0]) && (ema_f_val[0] > ema_s_val[0]);
   bool sell_trend = (close_1 < sar_val[0]) && (ema_f_val[0] < ema_s_val[0]);

   bool buy_breakout  = buy_trend  && (high_1 > (ema_f_val[0] + InpBreakoutPoints * _Point));
   bool sell_breakout = sell_trend && (low_1  < (ema_f_val[0] - InpBreakoutPoints * _Point));

   // Execute Trade
   if(buy_breakout)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = (InpStopLossPoints > 0) ? NormalizeDouble(ask - InpStopLossPoints * _Point, _Digits) : 0;
      double tp  = (InpTakeProfitPoints > 0) ? NormalizeDouble(ask + InpTakeProfitPoints * _Point, _Digits) : 0;
      double lot = CalculateLotSize(InpStopLossPoints);

      if(lot > 0)
        {
         if(trade.Buy(lot, _Symbol, ask, sl, tp, "XAU_MOM_BUY"))
           {
            Print("BUY Order Opened: Lot ", lot, " Ask: ", ask, " SL: ", sl, " TP: ", tp);
            last_bar_time = current_bar_time;
           }
        }
     }
   else if(sell_breakout)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = (InpStopLossPoints > 0) ? NormalizeDouble(bid + InpStopLossPoints * _Point, _Digits) : 0;
      double tp  = (InpTakeProfitPoints > 0) ? NormalizeDouble(bid - InpTakeProfitPoints * _Point, _Digits) : 0;
      double lot = CalculateLotSize(InpStopLossPoints);

      if(lot > 0)
        {
         if(trade.Sell(lot, _Symbol, bid, sl, tp, "XAU_MOM_SELL"))
           {
            Print("SELL Order Opened: Lot ", lot, " Bid: ", bid, " SL: ", sl, " TP: ", tp);
            last_bar_time = current_bar_time;
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Calculate Lot Size based on Risk Mode & Account Parameters        |
//+------------------------------------------------------------------+
double CalculateLotSize(int sl_points)
  {
   double lot = InpFixedLot;

   if(InpRiskMode == RISK_PERCENT_EQUITY)
     {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double risk_amount = equity * (InpRiskPercent / 100.0);
      double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

      if(sl_points > 0 && tick_value > 0 && tick_size > 0)
        {
         double point_value = tick_value * (_Point / tick_size);
         lot = risk_amount / (sl_points * point_value);
        }
     }
   else if(InpRiskMode == RISK_TIERED_BALANCE)
     {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance < 1000.0)        lot = 0.01;
      else if(balance < 5000.0)   lot = 0.05;
      else if(balance < 15000.0)  lot = 0.15;
      else if(balance < 50000.0)  lot = 0.50;
      else                        lot = 1.50;
     }

   // Normalize Volume to Broker Constraints
   double vol_min  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vol_max  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vol_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   lot = MathFloor(lot / vol_step) * vol_step;
   if(lot < vol_min) lot = vol_min;
   if(lot > vol_max) lot = vol_max;

   // Check Margin Requirement
   double margin_required = 0;
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lot, SymbolInfoDouble(_Symbol, SYMBOL_ASK), margin_required))
     {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin_required > free_margin)
        {
         Print("Insufficient margin for calculated lot size ", lot, ". Adjusting...");
         lot = MathFloor((free_margin * 0.95 / margin_required) * lot / vol_step) * vol_step;
         if(lot < vol_min) lot = 0;
        }
     }

   return NormalizeDouble(lot, 2);
  }

//+------------------------------------------------------------------+
//| Count active positions owned by EA                               |
//+------------------------------------------------------------------+
int CountActivePositions()
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) == _Symbol)
        {
         if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Dynamic Trailing Stop and Break-Even Management (Conflict-Free)   |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   // Query Broker Limit Constraints
   int stops_level  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   int freeze_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   int min_dist_pts = MathMax(stops_level, freeze_level);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // Ensure position matches symbol and magic number (Compatible with Netting & Hedging)
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      long   pos_type  = PositionGetInteger(POSITION_TYPE);
      double open_price= PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl= PositionGetDouble(POSITION_SL);
      double current_tp= PositionGetDouble(POSITION_TP);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // --- BUY POSITIONS MANAGEMENT ---
      if(pos_type == POSITION_TYPE_BUY)
        {
         // Target Break-Even level (Entry Price + Lock Offset)
         double target_be_sl = NormalizeDouble(open_price + InpBreakEvenProfit * _Point, _Digits);

         // Internal State Flag: Check if Break-Even was ALREADY executed successfully or disabled by user
         bool is_be_applied = (InpBreakEvenPoints <= 0) || ((current_sl > 0) && (current_sl >= target_be_sl - _Point));

         // --- ETAPE 1 : EXECUTION UNIQUE DU BREAK-EVEN ---
         if(!is_be_applied)
           {
            // Evaluate if profit threshold for Break-Even is reached
            if(InpBreakEvenPoints > 0 && (bid - open_price) >= InpBreakEvenPoints * _Point)
              {
               // Verify Broker distance constraint: Bid - target_be_sl > min_dist_pts * _Point
               if((bid - target_be_sl) > min_dist_pts * _Point)
                 {
                  if(trade.PositionModify(ticket, target_be_sl, current_tp))
                    {
                     Print("BUY Position #", ticket, " successfully secured to Break-Even at ", target_be_sl);
                    }
                 }
              }
            // Trailing Stop is strictly BLOCKED until Break-Even is applied
            continue;
           }

         // --- ETAPE 2 : RELAIS EXCLUSIF DU TRAILING STOP (Apres Break-Even) ---
         if(InpTrailingStopPoints > 0)
           {
            // Calculate candidate Trailing Stop level
            double new_trailing_sl = NormalizeDouble(bid - InpTrailingStopPoints * _Point, _Digits);

            // Constraint Check: New Trailing SL MUST strictly improve current SL by at least InpTrailingStepPoints
            if((new_trailing_sl - current_sl) >= InpTrailingStepPoints * _Point)
              {
               // Check broker distance constraint from current market bid price
               if((bid - new_trailing_sl) > min_dist_pts * _Point)
                 {
                  if(trade.PositionModify(ticket, new_trailing_sl, current_tp))
                    {
                     Print("BUY Trailing Stop updated for #", ticket, " from ", current_sl, " to ", new_trailing_sl);
                    }
                 }
              }
           }
        }

      // --- SELL POSITIONS MANAGEMENT ---
      else if(pos_type == POSITION_TYPE_SELL)
        {
         // Target Break-Even level for SELL (Entry Price - Lock Offset)
         double target_be_sl = NormalizeDouble(open_price - InpBreakEvenProfit * _Point, _Digits);

         // Internal State Flag: Check if Break-Even was ALREADY executed successfully or disabled by user
         bool is_be_applied = (InpBreakEvenPoints <= 0) || ((current_sl > 0) && (current_sl <= target_be_sl + _Point));

         // --- ETAPE 1 : EXECUTION UNIQUE DU BREAK-EVEN ---
         if(!is_be_applied)
           {
            // Evaluate if profit threshold for Break-Even is reached
            if(InpBreakEvenPoints > 0 && (open_price - ask) >= InpBreakEvenPoints * _Point)
              {
               // Verify Broker distance constraint: target_be_sl - Ask > min_dist_pts * _Point
               if((target_be_sl - ask) > min_dist_pts * _Point)
                 {
                  if(trade.PositionModify(ticket, target_be_sl, current_tp))
                    {
                     Print("SELL Position #", ticket, " successfully secured to Break-Even at ", target_be_sl);
                    }
                 }
              }
            // Trailing Stop is strictly BLOCKED until Break-Even is applied
            continue;
           }

         // --- ETAPE 2 : RELAIS EXCLUSIF DU TRAILING STOP (Apres Break-Even) ---
         if(InpTrailingStopPoints > 0)
           {
            // Calculate candidate Trailing Stop level
            double new_trailing_sl = NormalizeDouble(ask + InpTrailingStopPoints * _Point, _Digits);

            // Constraint Check: New Trailing SL MUST strictly improve current SL (lower for SELL) by at least InpTrailingStepPoints
            if((current_sl - new_trailing_sl) >= InpTrailingStepPoints * _Point)
              {
               // Check broker distance constraint from current market ask price
               if((new_trailing_sl - ask) > min_dist_pts * _Point)
                 {
                  if(trade.PositionModify(ticket, new_trailing_sl, current_tp))
                    {
                     Print("SELL Trailing Stop updated for #", ticket, " from ", current_sl, " to ", new_trailing_sl);
                    }
                 }
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Check if current server time is within active trading session    |
//+------------------------------------------------------------------+
bool IsTradingSessionActive()
  {
   MqlDateTime dt;
   TimeCurrent(dt);
   if(dt.hour >= InpStartHour && dt.hour < InpEndHour)
      return true;
   return false;
  }
//+------------------------------------------------------------------+
