# 📈 TradePilot — MT5 NAS100 Paper Lab

**Historical NAS100 strategy backtesting and offline paper simulation built with Python and Streamlit.**

> **SIMULATION ONLY:** No MT5 login, broker connection, live order placement or real-money trading. Educational research, not investment advice.

## Features

- Import historical OHLC CSV exported from MetaTrader 5
- EMA 20/50 crossover signals and ATR-based stops
- Next-bar entries, adjustable reward/risk, spread, slippage and commission
- Risk-based lot sizing, daily realized-loss lock and maximum realized-drawdown halt
- Interactive candlestick chart, moving averages, realized-equity curve
- Simulated trade journal with CSV export
- Automated Python tests and GitHub Actions

## Streamlit deployment

Choose repository `dm123-45/TradePilot-MT5`, branch `main`, entry point `app.py`, and Python 3.11.

## Run locally

```bash
python -m pip install -r requirements.txt
streamlit run app.py
```

## Run tests

```bash
python -m pip install pytest
python -m pytest -q tests/
```

## Input CSV

Accepts `timestamp,open,high,low,close` or MT5-style `<DATE>,<TIME>,<OPEN>,<HIGH>,<LOW>,<CLOSE>` headers. Example:

```csv
timestamp,open,high,low,close
2026-01-05 09:00,21000,21020,20980,21010
2026-01-05 10:00,21010,21035,21000,21030
```

This two-row example only demonstrates formatting; backtesting needs sufficient history to calculate indicators.

## Strategy

EMA crossover signals are computed on completed bars, with simulated entry at the next candle open. ATR sets the stop distance; reward/risk sets the target. Position sizes are rounded down to the lot increment. If both stop and target are touched in a candle, the stop is assumed to trigger first.

## Limitations

The simulator uses OHLC candles rather than tick-level execution. Entry-bar stops and targets are not assessed. Equity and loss limits use **realized** P&L, not floating P&L; actual open risk can exceed limits. Spreads and slippage are static estimates. Margin, swaps, partial fills, session rules, market closures and broker contract changes are not modeled. Configure the actual broker's NAS100 point value and lot size before interpreting results. Backtests do not predict future profitability.

## Roadmap

Walk-forward validation, stronger execution simulation, persistent offline paper trading, and eventually optional **demo-only** MT5 connectivity. No live-money execution is enabled.
