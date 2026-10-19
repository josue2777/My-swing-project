//+------------------------------------------------------------------+
//|                            XAUUSD_Momentum_Scalper_Inverse_EA.mq5 |
//|                             Copyright 2025, High-Yield Quant Lab |
//|                             INVERSE STRATEGY VARIANT (Total Rev) |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, High-Yield Quant Lab"
#property link      "https://github.com"
#property version   "1.00"
#property description "Expert Advisor XAUUSD Momentum Scalper - TOTAL INVERSE VARIANT (Explicite inversion of Buy/Sell conditions and parameters)"

#include <Trade\Trade.mqh>

//--- Enums
enum ENUM_RISK_MODE
  {
   RISK_FIXED_LOT,       // Fixed Lot Size
   RISK_PERCENT_EQUITY,  // Percent of Equity per Trade (Compounding)
   RISK_TIERED_BALANCE   // Tiered Capital Risk Allocation
  };

//--- Input Parameters
input group "== Strategy Parameters (TOTAL INVERSE VARIANT) =="
input ENUM_TIMEFRAMES InpTimeframe         = PERIOD_M5;  // Strategy Timeframe
input double          InpSarStep           = 0.02;       // Parabolic SAR Step
input double          InpSarMaximum        = 0.20;       // Parabolic SAR Maximum
input int             InpFastEMAPeriod     = 8;          // Fast EMA Period
input int             InpSlowEMAPeriod     = 21;         // Slow EMA Period
input int             InpATRPeriod         = 14;         // ATR Volatility Period
input double          InpMinATRPoints      = 80.0;       // Minimum Volatility ATR Filter (Points)
input double          InpBreakoutPoints    = 30.0;       // Channel Breakout Offset (Points)

input group "== Risk & Capital Management (Mirrored Risk Parameters) =="
input ENUM_RISK_MODE InpRiskMode          = RISK_PERCENT_EQUITY; // Risk Allocation Mode
input double          InpRiskPercent       = 2.5;        // Risk Percent Per Trade (%)
input double          InpFixedLot          = 0.10;       // Fixed Lot Size
input int             InpStopLossPoints    = 500;        // Inverted Stop Loss (Inverted SL = V1 Take Profit = 500 points)
input int             InpTakeProfitPoints  = 250;        // Inverted Take Profit (Inverted TP = V1 Stop Loss = 250 points)
input int             InpBreakEvenPoints   = 150;        // Trigger Break-Even in Points
input int             InpBreakEvenProfit   = 30;         // Profit Lock in Points on Break-Even
input int             InpTrailingStopPoints= 200;        // Trailing Stop Distance in Points
input int             InpTrailingStepPoints= 50;         // Trailing Step in Points
input int             InpMaxSpreadPoints   = 250;        // Max Allowed Spread in Points
input int             InpMaxOpenTrades     = 2;          // Max Open Concurrent Trades
input ulong           InpMagicNumber       = 151889;     // Magic Number (Inverse Variant)

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

   Print("XAUUSD_Momentum_Scalper_Inverse_EA (Total Inverse Variant) initialized successfully.");
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
   Print("XAUUSD_Momentum_Scalper_Inverse_EA deinitialized.");
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

   // --- TOTAL INVERSION OF CONDITIONS ---
   // V1 Buy Condition:  (close_1 > sar_val[0]) && (ema_f_val[0] > ema_s_val[0]) && (high_1 > ema_f_val[0] + InpBreakoutPoints * _Point)
   // V1 Sell Condition: (close_1 < sar_val[0]) && (ema_f_val[0] < ema_s_val[0]) && (low_1  < ema_f_val[0] - InpBreakoutPoints * _Point)

   // In V2 (Inverse EA):
   // - V2 BUY Condition  = V1 Sell Condition (When V1 triggers SELL, V2 buys)
   // - V2 SELL Condition = V1 Buy Condition  (When V1 triggers BUY, V2 sells)

   bool v1_buy_signal  = (close_1 > sar_val[0]) && (ema_f_val[0] > ema_s_val[0]) && (high_1 > (ema_f_val[0] + InpBreakoutPoints * _Point));
   bool v1_sell_signal = (close_1 < sar_val[0]) && (ema_f_val[0] < ema_s_val[0]) && (low_1  < (ema_f_val[0] - InpBreakoutPoints * _Point));

   bool v2_buy_condition  = v1_sell_signal; // Condition de Vente V1 devient Condition d'Achat V2
   bool v2_sell_condition = v1_buy_signal;  // Condition d'Achat V1 devient Condition de Vente V2

   // Execute Trade for V2
   if(v2_buy_condition)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double sl  = (InpStopLossPoints > 0) ? NormalizeDouble(ask - InpStopLossPoints * _Point, _Digits) : 0;
      double tp  = (InpTakeProfitPoints > 0) ? NormalizeDouble(ask + InpTakeProfitPoints * _Point, _Digits) : 0;
      double lot = CalculateLotSize(InpStopLossPoints);

      if(lot > 0)
        {
         if(trade.Buy(lot, _Symbol, ask, sl, tp, "XAU_INV_BUY"))
           {
            Print("TOTAL INVERSE BUY Opened (V1 Sell Signal): Lot ", lot, " Ask: ", ask, " SL: ", sl, " TP: ", tp);
            last_bar_time = current_bar_time;
           }
        }
     }
   else if(v2_sell_condition)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double sl  = (InpStopLossPoints > 0) ? NormalizeDouble(bid + InpStopLossPoints * _Point, _Digits) : 0;
      double tp  = (InpTakeProfitPoints > 0) ? NormalizeDouble(bid - InpTakeProfitPoints * _Point, _Digits) : 0;
      double lot = CalculateLotSize(InpStopLossPoints);

      if(lot > 0)
        {
         if(trade.Sell(lot, _Symbol, bid, sl, tp, "XAU_INV_SELL"))
           {
            Print("TOTAL INVERSE SELL Opened (V1 Buy Signal): Lot ", lot, " Bid: ", bid, " SL: ", sl, " TP: ", tp);
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
//| Dynamic Trailing Stop and Break-Even Management                  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
  {
   int stops_level = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      if(PositionGetSymbol(i) != _Symbol) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

      ulong  ticket    = PositionGetInteger(POSITION_TICKET);
      long   pos_type  = PositionGetInteger(POSITION_TYPE);
      double open_price= PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl= PositionGetDouble(POSITION_SL);
      double ask       = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid       = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      // --- BUY POSITIONS ---
      if(pos_type == POSITION_TYPE_BUY)
        {
         // 1. Break-Even Check
         if(InpBreakEvenPoints > 0)
           {
            double be_price = NormalizeDouble(open_price + InpBreakEvenProfit * _Point, _Digits);
            if(bid - open_price >= InpBreakEvenPoints * _Point && (current_sl < be_price || current_sl == 0))
              {
               if(bid - be_price > stops_level * _Point)
                 {
                  trade.PositionModify(ticket, be_price, PositionGetDouble(POSITION_TP));
                  Print("BUY Position #", ticket, " set to Break-Even at ", be_price);
                  continue;
                 }
              }
           }

         // 2. Trailing Stop Check
         if(InpTrailingStopPoints > 0)
           {
            double desired_sl = NormalizeDouble(bid - InpTrailingStopPoints * _Point, _Digits);
            if(bid - open_price > InpTrailingStopPoints * _Point)
              {
               if(desired_sl - current_sl >= InpTrailingStepPoints * _Point || current_sl == 0)
                 {
                  if(bid - desired_sl > stops_level * _Point)
                    {
                     trade.PositionModify(ticket, desired_sl, PositionGetDouble(POSITION_TP));
                     Print("BUY Trailing Stop updated for #", ticket, " to ", desired_sl);
                    }
                 }
              }
           }
        }

      // --- SELL POSITIONS ---
      else if(pos_type == POSITION_TYPE_SELL)
        {
         // 1. Break-Even Check
         if(InpBreakEvenPoints > 0)
           {
            double be_price = NormalizeDouble(open_price - InpBreakEvenProfit * _Point, _Digits);
            if(open_price - ask >= InpBreakEvenPoints * _Point && (current_sl > be_price || current_sl == 0))
              {
               if(be_price - ask > stops_level * _Point)
                 {
                  trade.PositionModify(ticket, be_price, PositionGetDouble(POSITION_TP));
                  Print("SELL Position #", ticket, " set to Break-Even at ", be_price);
                  continue;
                 }
              }
           }

         // 2. Trailing Stop Check
         if(InpTrailingStopPoints > 0)
           {
            double desired_sl = NormalizeDouble(ask + InpTrailingStopPoints * _Point, _Digits);
            if(open_price - ask > InpTrailingStopPoints * _Point)
              {
               if(current_sl - desired_sl >= InpTrailingStepPoints * _Point || current_sl == 0)
                 {
                  if(desired_sl - ask > stops_level * _Point)
                    {
                     trade.PositionModify(ticket, desired_sl, PositionGetDouble(POSITION_TP));
                     Print("SELL Trailing Stop updated for #", ticket, " to ", desired_sl);
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
