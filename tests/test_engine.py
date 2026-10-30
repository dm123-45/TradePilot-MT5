import io
import numpy as np
import pandas as pd
import pytest
from engine import Settings, load_ohlc, indicators, backtest

def sample(n=130):
    dates=pd.date_range("2026-01-01",periods=n,freq="h")
    close=21000+np.sin(np.arange(n)/6)*90
    return pd.DataFrame({"timestamp":dates,"open":close,"high":close+20,"low":close-20,"close":close})

def test_mt5_csv_import():
    data=b"<DATE>,<TIME>,<OPEN>,<HIGH>,<LOW>,<CLOSE>\n2026.01.01,09:00:00,100,102,99,101\n"
    frame=load_ohlc(io.BytesIO(data))
    assert len(frame)==1
    assert frame.close.iloc[0]==101

def test_reject_invalid_ohlc():
    with pytest.raises(ValueError):
        load_ohlc(io.BytesIO(b"timestamp,open,high,low,close\n2026-01-01,100,90,80,101\n"))

def test_indicator_warmup():
    result=indicators(sample(),Settings())
    assert pd.isna(result.slow.iloc[0])
    assert result.slow.notna().iloc[-1]

def test_backtest_runs_without_broker():
    data,trades,curve,position,halted=backtest(sample(),Settings())
    assert len(curve)==len(data)
    assert (curve.realized_equity>0).all()
    assert set(["timestamp","realized_equity"]).issubset(curve.columns)

def test_invalid_risk_rejected():
    with pytest.raises(ValueError):
        backtest(sample(),Settings(risk_pct=10))
