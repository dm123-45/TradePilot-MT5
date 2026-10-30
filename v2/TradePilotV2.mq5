//+------------------------------------------------------------------+
//| TradePilot V2 — DEMO-ONLY MT5 Expert Advisor                      |
//| Three instruments, beginner-friendly EMA/RSI/ATR strategy         |
//| Research software. No real-account execution.                    |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"
#include <Trade/Trade.mqh>
CTrade trade;

input bool EnableDemoAutoTrading=false;
input string Nas100Symbol="";     // Set from Market Watch, e.g. USTEC
input string GoldSymbol="XAUUSD";
input string EurUsdSymbol="EURUSD";
input double RiskPercent=0.50;
input double MaxDailyLossPercent=2.0;
input int MaxOpenPositions=3;
input double MaxSpreadPoints=100;
input int FastEMA=20;
input int SlowEMA=50;
input int RSIPeriod=14;
input int ATRPeriod=14;
input double StopATRMultiple=1.5;
input double RewardRisk=2.0;
input long MagicNumber=260302;
input int TimerSeconds=15;

string symbols[3];
datetime lastBar[3];
double dayStartEquity=0;
int dayKey=-1;
bool paused=false;

bool IsDemo()
{
   return AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;
}
int TodayKey()
{
   MqlDateTime t; TimeToStruct(TimeTradeServer(),t);
   return t.year*1000+t.day_of_year;
}
void RefreshDaily()
{
   int k=TodayKey();
   if(k!=dayKey)
   {
      dayKey=k;
      dayStartEquity=AccountInfoDouble(ACCOUNT_EQUITY);
   }
}
int OnInit()
{
   if(!IsDemo())
   {
      Print("TradePilot V2 REFUSED: Only MT5 demo accounts are supported.");
      return INIT_FAILED;
   }
   if(RiskPercent<=0 || RiskPercent>1 || MaxDailyLossPercent<=0 ||
      MaxDailyLossPercent>5 || FastEMA>=SlowEMA || StopATRMultiple<=0 ||
      RewardRisk<=0 || MaxOpenPositions<1 || MaxOpenPositions>3)
      return INIT_PARAMETERS_INCORRECT;
   symbols[0]=Nas100Symbol;
   symbols[1]=GoldSymbol;
   symbols[2]=EurUsdSymbol;
   for(int i=0;i<3;i++)
   {
      if(symbols[i]!="" && !SymbolSelect(symbols[i],true))
         Print("Symbol unavailable: ",symbols[i]);
      lastBar[i]=0;
   }
   RefreshDaily();
   EventSetTimer(MathMax(1,TimerSeconds));
   trade.SetExpertMagicNumber(MagicNumber);
   Print("TradePilot V2 loaded. DEMO ONLY. Auto trading=",EnableDemoAutoTrading);
   return INIT_SUCCEEDED;
}
void OnDeinit(const int reason) { EventKillTimer(); Comment(""); }
int OurPositions()
{
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==MagicNumber)
         count++;
   }
   return count;
}
bool HasPosition(string symbol)
{
   // Avoid interfering with any manual or other EA positions on this symbol.
   return PositionSelect(symbol);
}
double IndicatorValue(int handle,int shift)
{
   if(handle==INVALID_HANDLE) return EMPTY_VALUE;
   double a[];
   int n=CopyBuffer(handle,0,shift,1,a);
   IndicatorRelease(handle);
   return n==1 ? a[0] : EMPTY_VALUE;
}
double GetValue(string symbol,ENUM_TIMEFRAMES tf,int kind,int period,int shift)
{
   int h=INVALID_HANDLE;
   if(kind==0) h=iMA(symbol,tf,period,0,MODE_EMA,PRICE_CLOSE);
   if(kind==1) h=iRSI(symbol,tf,period,PRICE_CLOSE);
   if(kind==2) h=iATR(symbol,tf,period);
   return IndicatorValue(h,shift);
}
double LotSize(string symbol,double stopDistance)
{
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
   double minLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
   double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   if(tickSize<=0 || tickValue<=0 || step<=0 || stopDistance<=0) return 0;
   double lossPerLot=stopDistance/tickSize*tickValue;
   if(lossPerLot<=0) return 0;
   double raw=equity*RiskPercent/100.0/lossPerLot;
   double lots=MathFloor(raw/step)*step;
   if(lots<minLot) return 0; // Never round up beyond risk budget.
   return NormalizeDouble(MathMin(lots,maxLot),8);
}
void Evaluate(int i)
{
   string symbol=symbols[i];
   if(symbol=="" || !SymbolSelect(symbol,true)) return;
   datetime current=iTime(symbol,PERIOD_M5,0);
   if(current<=0 || current==lastBar[i]) return;
   lastBar[i]=current;
   double fast1=GetValue(symbol,PERIOD_M5,0,FastEMA,1);
   double fast2=GetValue(symbol,PERIOD_M5,0,FastEMA,2);
   double slow1=GetValue(symbol,PERIOD_M5,0,SlowEMA,1);
   double slow2=GetValue(symbol,PERIOD_M5,0,SlowEMA,2);
   double rsi=GetValue(symbol,PERIOD_M5,1,RSIPeriod,1);
   double atr=GetValue(symbol,PERIOD_M5,2,ATRPeriod,1);
   if(fast1==EMPTY_VALUE || fast2==EMPTY_VALUE || slow1==EMPTY_VALUE ||
      slow2==EMPTY_VALUE || rsi==EMPTY_VALUE || atr==EMPTY_VALUE || atr<=0) return;
   bool buy=fast2<=slow2 && fast1>slow1 && rsi>50 && rsi<70;
   bool sell=fast2>=slow2 && fast1<slow1 && rsi<50 && rsi>30;
   if(!buy && !sell) return;
   string side=buy?"BUY":"SELL";
   PrintFormat("TradePilot signal: %s %s | RSI %.1f | ATR %.5f",symbol,side,rsi,atr);
   if(!EnableDemoAutoTrading || paused || !IsDemo() || HasPosition(symbol) ||
      OurPositions()>=MaxOpenPositions) return;
   MqlTick tick;
   if(!SymbolInfoTick(symbol,tick) || tick.ask<=0 || tick.bid<=0) return;
   double point=SymbolInfoDouble(symbol,SYMBOL_POINT);
   if(point<=0 || (tick.ask-tick.bid)/point>MaxSpreadPoints) return;
   double stopDistance=atr*StopATRMultiple;
   long stops=SymbolInfoInteger(symbol,SYMBOL_TRADE_STOPS_LEVEL);
   if(stopDistance<stops*point+2*point) return;
   double lots=LotSize(symbol,stopDistance);
   if(lots<=0) return;
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double price=buy?tick.ask:tick.bid;
   double sl=NormalizeDouble(price+(buy?-1:1)*stopDistance,digits);
   double tp=NormalizeDouble(price+(buy?1:-1)*stopDistance*RewardRisk,digits);
   trade.SetTypeFillingBySymbol(symbol);
   trade.SetDeviationInPoints(20);
   bool submitted=buy?trade.Buy(lots,symbol,0,sl,tp,"TradePilot V2 demo"):
                       trade.Sell(lots,symbol,0,sl,tp,"TradePilot V2 demo");
   PrintFormat("TradePilot demo order %s %s lots=%.4f result=%d retcode=%u %s",
               side,symbol,lots,(int)submitted,trade.ResultRetcode(),
               trade.ResultRetcodeDescription());
}
void OnTimer()
{
   if(!IsDemo()) { paused=true; Comment("TRADEPILOT BLOCKED: NOT A DEMO ACCOUNT"); return; }
   RefreshDaily();
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(dayStartEquity>0 && equity<=dayStartEquity*(1-MaxDailyLossPercent/100.0))
      paused=true; // Persistent pause until EA is manually restarted.
   Comment("TradePilot V2 | DEMO ONLY\n",
           "Auto trading: ",EnableDemoAutoTrading?"ON":"OFF (signals only)","\n",
           "Paused: ",paused?"YES":"NO","\n",
           "Daily start equity: ",DoubleToString(dayStartEquity,2),"\n",
           "Current equity: ",DoubleToString(equity,2),"\n",
           "Markets: ",symbols[0],", ",symbols[1],", ",symbols[2]);
   if(paused) return;
   for(int i=0;i<3;i++) Evaluate(i);
}
