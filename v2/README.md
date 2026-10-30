# TradePilot V2 — Native MetaTrader 5 Demo Expert Advisor

TradePilot V2 is a **native MQL5 Expert Advisor**. It does **not** require Streamlit.

## Markets

- NAS100: set `Nas100Symbol` to the exact name shown in your broker's MT5 Market Watch, such as `USTEC` or `US100`. It defaults to blank to avoid accidental symbol mismatches.
- Gold: `XAUUSD`
- EUR/USD: `EURUSD`

Your demo broker must offer each instrument. The EA skips unavailable symbols.

## Getting started

1. Install MetaTrader 5 desktop and open a **demo account**. MetaQuotes-Demo can be a starting point, but availability of all three markets is not guaranteed.
2. Open MT5 → File → Open Data Folder → `MQL5/Experts`.
3. Copy `TradePilotV2.mq5` there.
4. Open the file in MetaEditor and compile it (F7). Check for compiler errors.
5. In MT5, open a chart and attach the TradePilot V2 EA from Navigator.
6. Set the broker-specific symbols in Inputs. Leave `EnableDemoAutoTrading=false` to observe signals first.
7. To enable **demo** execution, set `EnableDemoAutoTrading=true` and enable algorithmic trading in MT5. It will refuse to initialise on a real account.

**No demo account or credentials are included in this repository.** Never commit broker credentials.

## Current implementation scope

This is a **first functional EA prototype**, not the full ten-strategy platform. It uses a single EMA crossover with RSI confirmation and ATR stops on M5, across up to three symbols. It scans on a timer and only evaluates new bars. Stop-loss and take-profit are attached to submitted demo orders. Lot sizing uses broker-reported tick size and tick value. Daily equity loss lock pauses new entries; it does not liquidate open positions. One open position per instrument and three positions maximum.

The full planned V2 includes ten selectable strategies, calibrated probability charts, scenario simulation, beginner tutorials, detailed decision explanations and a persistent trade journal. **These are not yet implemented.** MT5's native Trade/History tabs show submitted demo orders and outcomes in the meantime.

## Safety and limitations

- Demo-account check uses `ACCOUNT_TRADE_MODE_DEMO`.
- Automatic trading defaults to **off**.
- Risk per trade defaults to 0.5% of equity, capped at 1% via inputs validation.
- Daily equity drawdown lock defaults to 2%, capped at 5% via inputs validation.
- No promise of profitable trades. Execution may fail due to margin, market status, contract rules or broker restrictions.
- The EA is not yet compiled or forward-tested on an MT5 terminal. Verify in MetaEditor and MT5 Strategy Tester before enabling demo orders.
- Broker-reported tick values, margin and slippage can affect realized risk. Do not assume the stated risk cap is guaranteed under gaps or execution differences.
- This prototype has no live-money execution capability by design.
