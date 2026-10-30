#property strict
#property version "3.00"
#property description "TradePilot Advanced: beginner-first, demo-only multi-market EA"
#include <Trade/Trade.mqh>
CTrade trader;
input bool EnableDemoAutoTrading=false;
input string NAS100Symbol="";
input string GoldSymbol="XAUUSD";
input string EuroSymbol="EURUSD";
input ENUM_TIMEFRAMES SignalTimeframe=PERIOD_M5;
input double RiskPerTradePercent=0.50;
input double DailyEquityLossLimitPercent=2.0;
input int MaximumPositions=3;
input int MinimumAgreement=3;
input double StopATR=1.5;
input double RewardToRisk=2.0;
input double MaximumSpreadATRRatio=0.15;
input int TimerIntervalSeconds=10;
input long ExpertMagic=260303;
string markets[3];
datetime seen[3];
int dayStamp=-1;
double dayEquity=0;
bool locked=false;
string explanation="Waiting for completed candles.";
string latestMarket="";
int journal=INVALID_HANDLE;

bool DemoOnly() {return AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO;}
int DayStamp() {MqlDateTime t; TimeToStruct(TimeTradeServer(),t);return t.year*1000+t.day_of_year;}
void DayReset()
{
 int d=DayStamp();
 if(d!=dayStamp){dayStamp=d;dayEquity=AccountInfoDouble(ACCOUNT_EQUITY);}
}
double ReadBuffer(int handle,int buffer,int shift)
{
 if(handle==INVALID_HANDLE)return EMPTY_VALUE;
 double values[];
 int n=CopyBuffer(handle,buffer,shift,1,values);
 IndicatorRelease(handle);
 return n==1?values[0]:EMPTY_VALUE;
}
double EMA(string s,int period,int shift){return ReadBuffer(iMA(s,SignalTimeframe,period,0,MODE_EMA,PRICE_CLOSE),0,shift);}
double RSI(string s,int shift){return ReadBuffer(iRSI(s,SignalTimeframe,14,PRICE_CLOSE),0,shift);}
double ATR(string s,int shift){return ReadBuffer(iATR(s,SignalTimeframe,14),0,shift);}
double MACD(string s,int buffer,int shift){return ReadBuffer(iMACD(s,SignalTimeframe,12,26,9,PRICE_CLOSE),buffer,shift);}
double BB(string s,int buffer,int shift){return ReadBuffer(iBands(s,SignalTimeframe,20,0,2.0,PRICE_CLOSE),buffer,shift);}
double CloseAt(string s,int shift){return iClose(s,SignalTimeframe,shift);}
double HighAt(string s,int shift){return iHigh(s,SignalTimeframe,shift);}
double LowAt(string s,int shift){return iLow(s,SignalTimeframe,shift);}
double OpenAt(string s,int shift){return iOpen(s,SignalTimeframe,shift);}
int Sign(double x){return x>0?1:(x<0?-1:0);}
bool Valid(double v){return v!=EMPTY_VALUE && MathIsValidNumber(v);}
void Record(string market,string eventType,string side,string detail,double price,double sl,double tp,double lots)
{
 if(journal==INVALID_HANDLE)return;
 FileWrite(journal,TimeToString(TimeTradeServer(),TIME_DATE|TIME_SECONDS),market,eventType,side,detail,
           DoubleToString(price,5),DoubleToString(sl,5),DoubleToString(tp,5),DoubleToString(lots,4));
 FileFlush(journal);
}
int OwnedPositions()
{
 int count=0;
 for(int i=PositionsTotal()-1;i>=0;i--)
 {
  ulong ticket=PositionGetTicket(i);
  if(ticket>0 && PositionGetInteger(POSITION_MAGIC)==ExpertMagic)count++;
 }
 return count;
}
double SizeForRisk(string symbol,double stop)
{
 double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
 double tickLoss=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
 double step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
 double minimum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN);
 double maximum=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
 if(tickSize<=0||tickLoss<=0||step<=0||stop<=0)return 0;
 double raw=AccountInfoDouble(ACCOUNT_EQUITY)*RiskPerTradePercent/100.0/(stop/tickSize*tickLoss);
 double lots=MathFloor(raw/step)*step;
 if(lots<minimum)return 0;
 return NormalizeDouble(MathMin(lots,maximum),8);
}
// Each candidate returns +1 BUY, -1 SELL or 0 WAIT.
// These are heuristic signals, not statistically calibrated probabilities.
void TenSignals(string s,int &votesBuy,int &votesSell,string &details,double &atr)
{
 votesBuy=0;votesSell=0;details="";
 int signal[10];ArrayInitialize(signal,0);
 double c1=CloseAt(s,1),c2=CloseAt(s,2),o1=OpenAt(s,1);
 double e9=EMA(s,9,1),e20=EMA(s,20,1),e50=EMA(s,50,1),e200=EMA(s,200,1);
 double old20=EMA(s,20,2),old50=EMA(s,50,2);
 double r1=RSI(s,1),r2=RSI(s,2);
 double m1=MACD(s,0,1),ms1=MACD(s,1,1),m2=MACD(s,0,2),ms2=MACD(s,1,2);
 double upper=BB(s,1,1),lower=BB(s,2,1);
 atr=ATR(s,1);
 if(!Valid(e9)||!Valid(e20)||!Valid(e50)||!Valid(e200)||!Valid(r1)||!Valid(r2)||
    !Valid(m1)||!Valid(ms1)||!Valid(m2)||!Valid(ms2)||!Valid(upper)||!Valid(lower)||
    !Valid(atr)||atr<=0)return;
 // 1: EMA 20/50 crossover
 if(old20<=old50&&e20>e50)signal[0]=1;
 if(old20>=old50&&e20<e50)signal[0]=-1;
 // 2: RSI threshold recovery
 if(r2<=30&&r1>30)signal[1]=1;
 if(r2>=70&&r1<70)signal[1]=-1;
 // 3: MACD signal-line crossover
 if(m2<=ms2&&m1>ms1)signal[2]=1;
 if(m2>=ms2&&m1<ms1)signal[2]=-1;
 // 4: Bollinger re-entry
 if(c2<BB(s,2,2)&&c1>lower)signal[3]=1;
 if(c2>BB(s,1,2)&&c1<upper)signal[3]=-1;
 // 5: Previous 20-bar range breakout
 double hh=-DBL_MAX,ll=DBL_MAX;
 for(int k=2;k<=21;k++){hh=MathMax(hh,HighAt(s,k));ll=MathMin(ll,LowAt(s,k));}
 if(c1>hh)signal[4]=1;
 if(c1<ll)signal[4]=-1;
 // 6: Swing support/resistance rejection
 double support=MathMin(LowAt(s,2),MathMin(LowAt(s,3),LowAt(s,4)));
 double resist=MathMax(HighAt(s,2),MathMax(HighAt(s,3),HighAt(s,4)));
 if(LowAt(s,1)<support&&c1>support&&c1>o1)signal[5]=1;
 if(HighAt(s,1)>resist&&c1<resist&&c1<o1)signal[5]=-1;
 // 7: Session VWAP proxy: volume-weighted typical price over 20 completed bars.
 // Tick volume is broker-specific; this is NOT exchange-wide consolidated VWAP.
 double weighted=0,volume=0;
 for(int j=1;j<=20;j++)
 {
  double v=(double)iVolume(s,SignalTimeframe,j);
  weighted+=((HighAt(s,j)+LowAt(s,j)+CloseAt(s,j))/3.0)*v;volume+=v;
 }
 if(volume>0){double vwap=weighted/volume;if(c1>vwap&&c2<=vwap)signal[6]=1;
                if(c1<vwap&&c2>=vwap)signal[6]=-1;}
 // 8: Prior candle liquidity sweep and rejection
 if(LowAt(s,1)<LowAt(s,2)&&c1>LowAt(s,2)&&c1>o1)signal[7]=1;
 if(HighAt(s,1)>HighAt(s,2)&&c1<HighAt(s,2)&&c1<o1)signal[7]=-1;
 // 9: Opening-range approximation: first 3 completed M5 bars after server 09:00
 MqlDateTime t;TimeToStruct(iTime(s,SignalTimeframe,1),t);
 if(t.hour==9&&t.min>=15&&t.min<=55)
 {
  double rangeHi=-DBL_MAX,rangeLo=DBL_MAX;
  for(int b=1;b<=20;b++)
  {
   MqlDateTime q;TimeToStruct(iTime(s,SignalTimeframe,b),q);
   if(q.hour==9&&q.min<15){rangeHi=MathMax(rangeHi,HighAt(s,b));rangeLo=MathMin(rangeLo,LowAt(s,b));}
  }
  if(rangeHi>-DBL_MAX&&c1>rangeHi)signal[8]=1;
  if(rangeLo<DBL_MAX&&c1<rangeLo)signal[8]=-1;
 }
 // 10: Long-term EMA alignment
 if(e9>e20&&e20>e50&&e50>e200&&c1>e9)signal[9]=1;
 if(e9<e20&&e20<e50&&e50<e200&&c1<e9)signal[9]=-1;
 string names[10]={"EMA cross","RSI reversal","MACD","Bollinger","Breakout",
                    "S/R rejection","VWAP proxy","Liquidity sweep","Opening range","Trend alignment"};
 for(int z=0;z<10;z++)
 {
  if(signal[z]>0){votesBuy++;details+=names[z]+":BUY; ";}
  if(signal[z]<0){votesSell++;details+=names[z]+":SELL; ";}
 }
}
void Scan(int index)
{
 string s=markets[index];
 if(s==""||!SymbolSelect(s,true))return;
 datetime bar=iTime(s,SignalTimeframe,0);
 if(bar<=0||seen[index]==bar)return;
 seen[index]=bar;
 int buys=0,sells=0;string reasons="";double atr=0;
 TenSignals(s,buys,sells,reasons,atr);
 if(atr<=0)return;
 int side=0;
 if(buys>=MinimumAgreement&&buys>sells)side=1;
 if(sells>=MinimumAgreement&&sells>buys)side=-1;
 string decision=side==1?"BUY":side==-1?"SELL":"WAIT";
 latestMarket=s;
 explanation=s+" | "+decision+" | BUY votes="+IntegerToString(buys)+
             " SELL votes="+IntegerToString(sells)+"\n"+
             (side==0?"No clear consensus; protect your capital.":"Review spread, risk and stop distance.")+
             "\n"+reasons;
 Print(explanation);
 Record(s,"SIGNAL",decision,reasons,CloseAt(s,1),0,0,0);
 if(!EnableDemoAutoTrading||side==0||locked||!DemoOnly()||
    OwnedPositions()>=MaximumPositions||PositionSelect(s))return;
 MqlTick tick;if(!SymbolInfoTick(s,tick)||tick.ask<=0||tick.bid<=0)return;
 double spread=tick.ask-tick.bid;
 if(spread>atr*MaximumSpreadATRRatio){Record(s,"SKIP",decision,"Spread too wide",0,0,0,0);return;}
 double distance=atr*StopATR;
 double point=SymbolInfoDouble(s,SYMBOL_POINT);
 if(point<=0||distance<((double)SymbolInfoInteger(s,SYMBOL_TRADE_STOPS_LEVEL)+2)*point)return;
 double lots=SizeForRisk(s,distance);
 if(lots<=0){Record(s,"SKIP",decision,"Lot size below minimum risk-safe volume",0,0,0,0);return;}
 int digits=(int)SymbolInfoInteger(s,SYMBOL_DIGITS);
 double entry=side>0?tick.ask:tick.bid;
 double sl=NormalizeDouble(entry-side*distance,digits);
 double tp=NormalizeDouble(entry+side*distance*RewardToRisk,digits);
 trader.SetTypeFillingBySymbol(s);
 trader.SetDeviationInPoints(20);
 bool ok=side>0?trader.Buy(lots,s,0,sl,tp,"TradePilot demo"):
                trader.Sell(lots,s,0,sl,tp,"TradePilot demo");
 string result=StringFormat("submitted=%d retcode=%u %s",(int)ok,
                           trader.ResultRetcode(),trader.ResultRetcodeDescription());
 Record(s,"ORDER",decision,result,entry,sl,tp,lots);
 Print(s," ",decision," ",result);
}
int OnInit()
{
 if(!DemoOnly()){Print("BLOCKED: Demo account required.");return INIT_FAILED;}
 if(RiskPerTradePercent<=0||RiskPerTradePercent>1||DailyEquityLossLimitPercent<=0||
    DailyEquityLossLimitPercent>5||MaximumPositions<1||MaximumPositions>3||
    MinimumAgreement<2||MinimumAgreement>10||StopATR<=0||RewardToRisk<=0||
    MaximumSpreadATRRatio<=0)return INIT_PARAMETERS_INCORRECT;
 markets[0]=NAS100Symbol;markets[1]=GoldSymbol;markets[2]=EuroSymbol;
 for(int i=0;i<3;i++){seen[i]=0;if(markets[i]!="")SymbolSelect(markets[i],true);}
 trader.SetExpertMagicNumber(ExpertMagic);
 DayReset();
 journal=FileOpen("TradePilotV2_Decisions.csv",FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_ANSI,',');
 if(journal!=INVALID_HANDLE)
 {
  if(FileSize(journal)==0)FileWrite(journal,"timestamp","symbol","event","side","explanation","price","sl","tp","lots");
  FileSeek(journal,0,SEEK_END);
 }
 EventSetTimer(MathMax(1,TimerIntervalSeconds));
 return INIT_SUCCEEDED;
}
void OnDeinit(const int reason)
{
 EventKillTimer();Comment("");
 if(journal!=INVALID_HANDLE)FileClose(journal);
}
void OnTimer()
{
 if(!DemoOnly()){locked=true;Comment("TradePilot BLOCKED: not a demo account");return;}
 DayReset();
 double eq=AccountInfoDouble(ACCOUNT_EQUITY);
 if(dayEquity>0&&eq<=dayEquity*(1-DailyEquityLossLimitPercent/100.0))locked=true;
 if(!locked)for(int i=0;i<3;i++)Scan(i);
 Comment("TRADEPILOT V2 | DEMO ONLY\n",
         "Auto: ",EnableDemoAutoTrading?"ON":"OFF (signals only)",
         " | Locked: ",locked?"YES":"NO","\n",
         "Equity: ",DoubleToString(eq,2),
         " | Daily baseline: ",DoubleToString(dayEquity,2),"\n",
         "Risk/trade: ",DoubleToString(RiskPerTradePercent,2),"%\n",
         explanation,"\n",
         "Trade journal: MQL5/Files/TradePilotV2_Decisions.csv");
}

void OnTradeTransaction(const MqlTradeTransaction &transaction,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
 if(transaction.type!=TRADE_TRANSACTION_DEAL_ADD || transaction.deal==0)return;
 if(!HistoryDealSelect(transaction.deal))return;
 if(HistoryDealGetInteger(transaction.deal,DEAL_MAGIC)!=ExpertMagic)return;
 string symbol=HistoryDealGetString(transaction.deal,DEAL_SYMBOL);
 long entry=HistoryDealGetInteger(transaction.deal,DEAL_ENTRY);
 double pnl=HistoryDealGetDouble(transaction.deal,DEAL_PROFIT)+
            HistoryDealGetDouble(transaction.deal,DEAL_COMMISSION)+
            HistoryDealGetDouble(transaction.deal,DEAL_SWAP);
 string detail="Deal #"+IntegerToString((long)transaction.deal)+
               " entry_code="+IntegerToString(entry)+
               " realized_PnL="+DoubleToString(pnl,2);
 Record(symbol,"DEAL",entry==DEAL_ENTRY_OUT?"CLOSED":"FILLED",
        detail,HistoryDealGetDouble(transaction.deal,DEAL_PRICE),0,0,
        HistoryDealGetDouble(transaction.deal,DEAL_VOLUME));
}
