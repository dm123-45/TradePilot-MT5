"""TradePilot V2 historical research companion; no broker connectivity or order execution."""
import io
import numpy as np
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from engine import load_ohlc

NAMES=["EMA cross","RSI reversal","MACD","Bollinger re-entry","Range breakout",
       "Support/resistance rejection","VWAP proxy","Liquidity sweep",
       "Opening range","Trend alignment"]

def feature_signals(frame):
    d=frame.copy().reset_index(drop=True)
    c=d.close
    ema=lambda n:c.ewm(span=n,adjust=False,min_periods=n).mean()
    e9,e20,e50,e200=[ema(n) for n in (9,20,50,200)]
    delta=c.diff()
    gain=delta.clip(lower=0).ewm(alpha=1/14,adjust=False,min_periods=14).mean()
    loss=(-delta.clip(upper=0)).ewm(alpha=1/14,adjust=False,min_periods=14).mean()
    rsi=100-100/(1+gain/loss.replace(0,np.nan))
    macd=ema(12)-ema(26)
    macds=macd.ewm(span=9,adjust=False,min_periods=9).mean()
    mid=c.rolling(20).mean()
    std=c.rolling(20).std()
    hi=d.high.shift(1).rolling(20).max()
    lo=d.low.shift(1).rolling(20).min()
    tr=pd.concat([(d.high-d.low),(d.high-c.shift()).abs(),(d.low-c.shift()).abs()],axis=1).max(axis=1)
    atr=tr.rolling(14).mean()
    # Historical CSV may lack real exchange volume. Use tick_volume only if supplied.
    vol=d["tick_volume"] if "tick_volume" in d else pd.Series(1.0,index=d.index)
    typical=(d.high+d.low+c)/3
    vwap=(typical*vol).rolling(20).sum()/vol.rolling(20).sum().replace(0,np.nan)
    def binary(buy,sell):
        return pd.Series(np.select([buy.fillna(False),sell.fillna(False)],[1,-1],default=0),index=d.index)
    out={}
    out[NAMES[0]]=binary((e20>e50)&(e20.shift()<=e50.shift()),(e20<e50)&(e20.shift()>=e50.shift()))
    out[NAMES[1]]=binary((rsi.shift()<=30)&(rsi>30),(rsi.shift()>=70)&(rsi<70))
    out[NAMES[2]]=binary((macd>macds)&(macd.shift()<=macds.shift()),(macd<macds)&(macd.shift()>=macds.shift()))
    out[NAMES[3]]=binary((c.shift()< (mid-2*std).shift())&(c>mid-2*std),(c.shift()>(mid+2*std).shift())&(c<mid+2*std))
    out[NAMES[4]]=binary(c>hi,c<lo)
    sh=d.low.shift(1).rolling(3).min()
    rh=d.high.shift(1).rolling(3).max()
    out[NAMES[5]]=binary((d.low<sh)&(c>sh)&(c>d.open),(d.high>rh)&(c<rh)&(c<d.open))
    out[NAMES[6]]=binary((c>vwap)&(c.shift()<=vwap.shift()),(c<vwap)&(c.shift()>=vwap.shift()))
    out[NAMES[7]]=binary((d.low<d.low.shift())&(c>d.low.shift())&(c>d.open),
                         (d.high>d.high.shift())&(c<d.high.shift())&(c<d.open))
    # Approximate opening range in timestamp's own timezone; assumes 09:00 is broker-server time.
    times=pd.to_datetime(d.timestamp)
    day=times.dt.date
    hour=times.dt.hour
    minute=times.dt.minute
    opening=(hour==9)&(minute<15)
    first_high=d.high.where(opening).groupby(day).transform("max")
    first_low=d.low.where(opening).groupby(day).transform("min")
    later=(hour==9)&(minute>=15)&(minute<=55)
    out[NAMES[8]]=binary(later&(c>first_high),later&(c<first_low))
    out[NAMES[9]]=binary((e9>e20)&(e20>e50)&(e50>e200)&(c>e9),
                          (e9<e20)&(e20<e50)&(e50<e200)&(c<e9))
    # Prevent warm-up signals from using unavailable 200-EMA data.
    result=pd.DataFrame(out)
    result.loc[e200.isna(),:]=0
    return d,result,atr

def evaluate(frame,horizon=6,stop_atr=1.5,reward_risk=2.0):
    """Evaluate non-overlapping historical setups using future candles, separate from live signals.
    Conservative: if stop and target both hit in one candle, score as loss.
    Entry at next candle open; exits start on entry candle. Static costs excluded.
    """
    d,signals,atr=feature_signals(frame)
    records=[]
    for name in NAMES:
        last_exit=-1
        for i in range(200,len(d)-1):
            side=int(signals[name].iloc[i])
            if side==0 or i<=last_exit or not np.isfinite(atr.iloc[i]) or atr.iloc[i]<=0:continue
            entry=float(d.open.iloc[i+1])
            dist=float(atr.iloc[i]*stop_atr)
            stop=entry-side*dist
            target=entry+side*dist*reward_risk
            result=0.0
            exit_i=min(i+horizon,len(d)-1)
            for j in range(i+1,exit_i+1):
                hit_stop=(d.low.iloc[j]<=stop) if side>0 else (d.high.iloc[j]>=stop)
                hit_target=(d.high.iloc[j]>=target) if side>0 else (d.low.iloc[j]<=target)
                if hit_stop:
                    result=-1.0;exit_i=j;break
                if hit_target:
                    result=reward_risk;exit_i=j;break
            if result==0:
                result=float((d.close.iloc[exit_i]-entry)*side/dist)
            last_exit=exit_i
            records.append({"strategy":name,"entry_time":d.timestamp.iloc[i+1],"direction":"BUY" if side>0 else "SELL",
                            "entry":entry,"stop":stop,"target":target,"exit_time":d.timestamp.iloc[exit_i],
                            "outcome_R":result,"win":result>0})
    return d,signals,pd.DataFrame(records)

def wilson_interval(wins,n,z=1.96):
    if n<=0:return (np.nan,np.nan)
    p=wins/n
    center=(p+z*z/(2*n))/(1+z*z/n)
    half=z*np.sqrt(p*(1-p)/n+z*z/(4*n*n))/(1+z*z/n)
    return max(0,center-half),min(1,center+half)

def simulate_paths(returns,starting=5000,risk_fraction=0.005,paths=1000,steps=30,seed=42):
    values=np.asarray(returns,dtype=float)
    values=values[np.isfinite(values)]
    if not len(values):return np.empty((0,0))
    rng=np.random.default_rng(seed)
    samples=rng.choice(values,size=(paths,steps),replace=True)
    # Each outcome_R represents an R-multiple; risk_fraction of current equity is at risk.
    return starting*np.cumprod(1+samples*risk_fraction,axis=1)

def main():
    st.set_page_config(page_title="TradePilot V2 Research",layout="wide")
    st.title("TradePilot V2 — Strategy Probability Lab")
    st.warning("Historical research only. Not live signals. Estimates are not guarantees; no orders are sent.")
    file=st.file_uploader("Upload historical NAS100, XAUUSD or EURUSD OHLC CSV",type=["csv"])
    if file is None:
        st.info("Upload MT5 historical candles (preferably 1,000+ M5 bars).")
        return
    try:
        data=load_ohlc(io.BytesIO(file.getvalue()))
        if len(data)<260:st.error("At least 260 candles are required.");return
        horizon=st.slider("Maximum holding period (candles)",2,30,6)
        stop=st.slider("Stop ATR multiple",0.5,4.0,1.5,0.25)
        rr=st.slider("Target reward/risk",1.0,5.0,2.0,0.5)
        data,signals,trades=evaluate(data,horizon,stop,rr)
    except (ValueError,pd.errors.ParserError,UnicodeError) as e:
        st.error(str(e));return
    if trades.empty:st.info("No qualifying completed trades in this historical sample.");return
    summary=trades.groupby("strategy").agg(trades=("win","size"),wins=("win","sum"),
        mean_R=("outcome_R","mean"),total_R=("outcome_R","sum")).reset_index()
    summary["win_rate"]=summary.wins/summary.trades
    bounds=summary.apply(lambda x:wilson_interval(int(x.wins),int(x.trades)),axis=1)
    summary["win_rate_low"]=[x[0] for x in bounds]
    summary["win_rate_high"]=[x[1] for x in bounds]
    summary=summary.sort_values("mean_R",ascending=False)
    st.subheader("Historical strategy comparison")
    st.caption("Win-rate confidence intervals are Wilson 95% intervals; they do not account for market regime changes. No costs or spread included.")
    st.dataframe(summary,hide_index=True,use_container_width=True)
    fig=go.Figure()
    fig.add_trace(go.Bar(x=summary.strategy,y=summary.win_rate*100,name="Observed win rate (%)",
        error_y=dict(type="data",symmetric=False,array=(summary.win_rate_high-summary.win_rate)*100,
                     arrayminus=(summary.win_rate-summary.win_rate_low)*100)))
    fig.update_layout(title="Historical win rates and uncertainty",yaxis_title="Win rate (%)")
    st.plotly_chart(fig,use_container_width=True)
    choice=st.selectbox("Explore a strategy",summary.strategy.tolist())
    subset=trades[trades.strategy==choice]
    paths=simulate_paths(subset.outcome_R.to_numpy(),starting=5000,paths=1000,steps=30)
    st.subheader("Bootstrap scenario simulator — 30 hypothetical trades")
    st.caption("Resamples historical R outcomes independently. Does not predict market prices; ignores fees, correlation and regime shifts.")
    if len(paths):
        steps=np.arange(1,paths.shape[1]+1)
        low,mid,high=np.percentile(paths,[5,50,95],axis=0)
        fig=go.Figure()
        fig.add_trace(go.Scatter(x=steps,y=high,mode="lines",line=dict(width=0),showlegend=False))
        fig.add_trace(go.Scatter(x=steps,y=low,mode="lines",fill="tonexty",name="5th–95th percentile",line=dict(width=0)))
        fig.add_trace(go.Scatter(x=steps,y=mid,mode="lines",name="Median"))
        fig.update_layout(xaxis_title="Simulated trade number",yaxis_title="Hypothetical demo balance ($)")
        st.plotly_chart(fig,use_container_width=True)
    st.subheader("Beginner explanation")
    count=len(subset)
    rate=subset.win.mean()*100
    st.write(f"{choice} produced {count} non-overlapping historical examples with a {rate:.1f}% observed win rate on this dataset. "
             "A higher win rate does not automatically mean a better strategy: losses, reward/risk, spreads and sample size matter. "
             "WAIT if signals conflict, the spread is high or the stop would require more than your risk budget.")
    st.subheader("Historical trade journal")
    st.dataframe(subset,hide_index=True,use_container_width=True)
    st.download_button("Download journal CSV",trades.to_csv(index=False),"tradepilot_v2_historical_journal.csv","text/csv")
if __name__=="__main__":main()
