from dataclasses import dataclass
import numpy as np
import pandas as pd

@dataclass(frozen=True)
class Settings:
    initial_equity: float = 5000
    risk_pct: float = 0.5
    max_daily_loss_pct: float = 2
    max_drawdown_pct: float = 8
    ema_fast: int = 20
    ema_slow: int = 50
    atr_period: int = 14
    atr_stop: float = 1.5
    reward_risk: float = 2
    spread_points: float = 2
    slippage_points: float = 1
    commission_per_lot_roundtrip: float = 0
    dollars_per_point_per_lot: float = 1
    lot_step: float = 0.01
    max_lots: float = 10

def load_ohlc(file):
    frame = pd.read_csv(file, sep=None, engine="python")
    frame.columns = [str(c).strip().lower().replace("<","").replace(">","") for c in frame.columns]
    if "date" in frame and "time" in frame:
        frame["timestamp"] = pd.to_datetime(frame["date"].astype(str)+" "+frame["time"].astype(str), errors="coerce")
    else:
        col = next((c for c in ("timestamp","datetime","time") if c in frame), None)
        if col is None: raise ValueError("Include timestamp, datetime or date + time.")
        frame["timestamp"] = pd.to_datetime(frame[col], errors="coerce")
    missing = [c for c in ("open","high","low","close") if c not in frame]
    if missing: raise ValueError("Missing OHLC columns: "+", ".join(missing))
    for c in ("open","high","low","close"):
        frame[c] = pd.to_numeric(frame[c], errors="coerce")
    frame = frame.dropna(subset=["timestamp","open","high","low","close"]).sort_values("timestamp").drop_duplicates("timestamp")
    if frame.empty or (frame["high"] < frame[["open","close","low"]].max(axis=1)).any() or (frame["low"] > frame[["open","close","high"]].min(axis=1)).any() or (frame[["open","high","low","close"]] <= 0).any().any():
        raise ValueError("Invalid OHLC prices or empty data.")
    return frame.reset_index(drop=True)

def indicators(df, cfg):
    d = df.copy()
    d["fast"] = d.close.ewm(span=cfg.ema_fast, adjust=False, min_periods=cfg.ema_fast).mean()
    d["slow"] = d.close.ewm(span=cfg.ema_slow, adjust=False, min_periods=cfg.ema_slow).mean()
    prev = d.close.shift(1)
    tr = pd.concat([d.high-d.low, (d.high-prev).abs(), (d.low-prev).abs()], axis=1).max(axis=1)
    d["atr"] = tr.rolling(cfg.atr_period, min_periods=cfg.atr_period).mean()
    d["signal"] = 0
    up = (d.fast>d.slow)&(d.fast.shift(1)<=d.slow.shift(1))
    down = (d.fast<d.slow)&(d.fast.shift(1)>=d.slow.shift(1))
    d.loc[up & d.atr.notna(),"signal"] = 1
    d.loc[down & d.atr.notna(),"signal"] = -1
    return d

def backtest(df,cfg):
    if not (0<cfg.risk_pct<=2 and 0<cfg.max_daily_loss_pct<=10 and 0<cfg.max_drawdown_pct<=50 and cfg.ema_fast<cfg.ema_slow and cfg.atr_stop>0 and cfg.reward_risk>0 and cfg.dollars_per_point_per_lot>0 and cfg.lot_step>0 and cfg.max_lots>0 and cfg.spread_points>=0 and cfg.slippage_points>=0 and cfg.commission_per_lot_roundtrip>=0):
        raise ValueError("Invalid risk or execution settings.")
    d = indicators(df,cfg)
    equity = float(cfg.initial_equity)
    if equity<=0: raise ValueError("Initial equity must be positive.")
    peak=equity; day=None; day_start=equity; position=None; trades=[]; curve=[]; halted=False
    for i,row in d.iterrows():
        today=row.timestamp.date()
        if today!=day: day,day_start=today,equity
        if position is not None:
            p=position
            stop_hit=row.low<=p["stop"] if p["side"]==1 else row.high>=p["stop"]
            target_hit=row.high>=p["target"] if p["side"]==1 else row.low<=p["target"]
            if stop_hit or target_hit:
                level=p["stop"] if stop_hit else p["target"]
                if stop_hit: level=min(level,row.open) if p["side"]==1 else max(level,row.open)
                exit_price=level-p["side"]*(cfg.spread_points/2+cfg.slippage_points)
                pnl=(exit_price-p["entry"])*p["side"]*p["lots"]*cfg.dollars_per_point_per_lot-cfg.commission_per_lot_roundtrip*p["lots"]
                equity+=pnl
                trades.append({**p,"exit_time":row.timestamp,"exit":exit_price,"pnl":pnl,"equity_after":equity,"reason":"Stop" if stop_hit else "Target"})
                position=None
                peak=max(peak,equity)
        if equity<=0 or (peak-equity)/peak*100>=cfg.max_drawdown_pct: halted=True
        daily_locked=(day_start-equity)/day_start*100>=cfg.max_daily_loss_pct if day_start>0 else True
        if i>0 and not halted and not daily_locked and position is None:
            prior=d.iloc[i-1]
            if prior.signal!=0 and np.isfinite(prior.atr) and prior.atr>0:
                side=int(prior.signal)
                entry=float(row.open+side*(cfg.spread_points/2+cfg.slippage_points))
                distance=float(prior.atr*cfg.atr_stop)
                loss_per_lot=(distance+cfg.spread_points+2*cfg.slippage_points)*cfg.dollars_per_point_per_lot+cfg.commission_per_lot_roundtrip
                raw_lots=equity*cfg.risk_pct/100/loss_per_lot
                lots=min(np.floor((raw_lots+1e-10)/cfg.lot_step)*cfg.lot_step,cfg.max_lots)
                if lots>=cfg.lot_step:
                    position={"entry_time":row.timestamp,"side":side,"entry":entry,"stop":entry-side*distance,"target":entry+side*distance*cfg.reward_risk,"lots":round(float(lots),8)}
        curve.append({"timestamp":row.timestamp,"realized_equity":equity,"open_position":position is not None})
    return d,pd.DataFrame(trades),pd.DataFrame(curve),position,halted
