import sys
from pathlib import Path
import numpy as np
import pandas as pd
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"v2"))
from analytics import NAMES,feature_signals,evaluate,wilson_interval,simulate_paths

def sample(n=400):
    x=np.arange(n)
    close=20000+0.6*x+90*np.sin(x/8)
    return pd.DataFrame({"timestamp":pd.date_range("2026-01-01",periods=n,freq="5min"),
                         "open":close,"high":close+20,"low":close-20,"close":close})

def test_all_ten_strategies_have_signals():
    d,signals,atr=feature_signals(sample())
    assert list(signals.columns)==NAMES
    assert set(np.unique(signals.to_numpy())).issubset({-1,0,1})
    assert (signals.iloc[:199]==0).all().all()

def test_historical_evaluation():
    _,_,journal=evaluate(sample())
    assert set(["strategy","entry","stop","target","outcome_R","win"]).issubset(journal.columns)

def test_wilson_bounds():
    low,high=wilson_interval(6,10)
    assert 0<low<0.6<high<1

def test_bootstrap_reproducible():
    a=simulate_paths([-1,2,1],paths=10,steps=5)
    b=simulate_paths([-1,2,1],paths=10,steps=5)
    assert a.shape==(10,5)
    np.testing.assert_array_equal(a,b)
