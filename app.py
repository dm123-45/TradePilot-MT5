"""TradePilot: historical backtesting only. No live orders or broker connection."""
import io
import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from engine import Settings, load_ohlc, backtest

st.set_page_config(page_title="TradePilot | MT5 Paper Lab",page_icon="📈",layout="wide")
st.title("📈 TradePilot — MT5 Paper Lab")
st.warning("SIMULATION ONLY · No broker connection or real orders. Historical results do not predict future performance.")
st.caption("Upload NAS100 historical OHLC CSV exported from MT5. Columns: timestamp (or date + time), open, high, low, close.")
with st.sidebar:
    st.header("Strategy & risk")
    equity=st.number_input("Starting balance ($)",100.0,1000000.0,5000.0,100.0)
    risk=st.slider("Risk per trade (%)",0.1,2.0,0.5,0.1)
    daily=st.slider("Daily loss lock (%)",0.5,10.0,2.0,0.5)
    drawdown=st.slider("Max realized drawdown halt (%)",1.0,50.0,8.0,1.0)
    fast=st.number_input("Fast EMA",2,100,20)
    slow=st.number_input("Slow EMA",3,300,50)
    stop=st.slider("Stop distance (ATR multiple)",0.5,5.0,1.5,0.25)
    rr=st.slider("Reward / risk",0.5,5.0,2.0,0.5)
    st.divider()
    st.caption("Contract specifications vary by broker. Set these to match your MT5 symbol.")
    point_value=st.number_input("USD per index point per 1.0 lot",min_value=0.01,value=1.0)
    step=st.number_input("Minimum lot increment",min_value=0.001,value=0.01,format="%.3f")
    max_lots=st.number_input("Max lots",min_value=0.01,value=10.0)
    spread=st.number_input("Spread (index points)",min_value=0.0,value=2.0)
    slip=st.number_input("Slippage per side (points)",min_value=0.0,value=1.0)
    commission=st.number_input("Roundtrip commission ($/lot)",min_value=0.0,value=0.0)
uploaded=st.file_uploader("Upload MT5 historical OHLC CSV",type="csv")
if uploaded is None:
    st.info("Upload historical CSV data to run a backtest. No fabricated market data is used.")
    st.code("timestamp,open,high,low,close\n2026-01-05 09:00,21000,21020,20980,21010\n2026-01-05 10:00,21010,21035,21000,21030",language="csv")
    st.stop()
if uploaded.size>20*1024*1024:
    st.error("File exceeds the 20 MB limit.")
    st.stop()
try:
    cfg=Settings(initial_equity=equity,risk_pct=risk,max_daily_loss_pct=daily,max_drawdown_pct=drawdown,ema_fast=int(fast),ema_slow=int(slow),atr_stop=stop,reward_risk=rr,spread_points=spread,slippage_points=slip,commission_per_lot_roundtrip=commission,dollars_per_point_per_lot=point_value,lot_step=step,max_lots=max_lots)
    df=load_ohlc(io.BytesIO(uploaded.getvalue()))
    if len(df)<slow+2:
        st.error(f"At least {slow+2} valid candles required.")
        st.stop()
    enriched,trades,curve,position,halted=backtest(df,cfg)
except (ValueError,pd.errors.ParserError,UnicodeError) as exc:
    st.error(f"Unable to backtest: {exc}")
    st.stop()
final=float(curve.realized_equity.iloc[-1])
win=(trades.pnl>0).mean()*100 if len(trades) else 0
peak=curve.realized_equity.cummax()
mdd=((peak-curve.realized_equity)/peak).max()*100
c1,c2,c3,c4=st.columns(4)
c1.metric("Realized balance",f"${final:,.2f}",f"${final-equity:,.2f}")
c2.metric("Closed trades",len(trades))
c3.metric("Win rate",f"{win:.1f}%")
c4.metric("Max realized drawdown",f"{mdd:.2f}%")
if halted: st.error("Backtest halted by maximum realized drawdown or account depletion.")
if position: st.info("One simulated position remains open. Unrealized P&L is not included in realized balance.")
price=go.Figure(data=[go.Candlestick(x=enriched.timestamp,open=enriched.open,high=enriched.high,low=enriched.low,close=enriched.close,name="NAS100 historical candles")])
price.add_trace(go.Scatter(x=enriched.timestamp,y=enriched.fast,name="Fast EMA"))
price.add_trace(go.Scatter(x=enriched.timestamp,y=enriched.slow,name="Slow EMA"))
price.update_layout(title="Price & moving averages",height=520,xaxis_rangeslider_visible=False)
st.plotly_chart(price,use_container_width=True)
st.line_chart(curve.set_index("timestamp").realized_equity)
st.subheader("Simulated trade journal")
if trades.empty: st.info("No completed trades for these settings and this dataset.")
else:
    st.dataframe(trades,hide_index=True,use_container_width=True)
    st.download_button("Download trade journal",trades.to_csv(index=False).encode(),"tradepilot_paper_trades.csv","text/csv")
with st.expander("Assumptions and limitations"):
    st.write("EMA signals use completed candle closes; simulated entries occur at the next candle open. Stops and targets are checked from subsequent candles. If both are touched, the stop wins. Gap-through stops use the worse open. Costs are approximations. Equity is realized-only; daily locks do not include open risk. Session, margin, swap, partial fills, market closures and changing contract specifications are not modeled. Educational simulation only.")
