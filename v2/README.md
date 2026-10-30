# TradePilot V2 — beginner-first demo trading

## What is included
- Native MT5 Expert Advisor (`TradePilotV2.mq5`) for demo-only execution, NAS100, XAUUSD and EURUSD.
- `TradePilotAdvanced.mq5`: enhanced ten-strategy scanner with conservative confirmation, scenario estimates, beginner explanation panel, demo order management and CSV decision journal.
- `analytics.py`: independent Python research companion for historical CSVs, ten setup backtests, probability charts, bootstrapped outcome scenarios and trade-journal analysis.
- `requirements-v2.txt`: companion dependencies.
- `tests/test_analytics.py`: analytics regression tests.

## Installation
1. Open MT5 desktop and log in to a **demo** account.
2. File → Open Data Folder → MQL5 → Experts. Copy `TradePilotAdvanced.mq5` into that folder.
3. Open MetaEditor (F4), compile with F7. Resolve any errors before continuing.
4. In Market Watch, identify your broker's exact names for NAS100, XAUUSD and EURUSD. Enter those in EA inputs. NAS100 is blank by default.
5. Attach the EA to a chart. Start with `EnableDemoAutoTrading=false` and watch signals in Experts and on-chart comments.
6. Only after Strategy Tester and demo validation, switch `EnableDemoAutoTrading=true` and enable Algo Trading. The EA rejects non-demo accounts.

## Historical probability dashboard
From the repository root:

```bash
python -m pip install -r v2/requirements-v2.txt
python -m streamlit run v2/analytics.py
```

This separate **research companion** uses historical CSVs, not a live broker feed. The trading engine itself is native MT5 and does not require Streamlit.

## Design constraints
The 10 strategies produce **candidate signals**, not a mandate to place ten trades. An order is considered only if sufficient independent strategies agree and a completed candle provides a signal. Stop-loss and take-profit are required. Estimated win rates are derived from past observations and have uncertainty, not guarantees. Never use the system on a real account.

## Current verification
Source code is provided, but compilation and end-to-end demo execution **must be verified on the user's installed MT5 terminal**. This environment cannot access the user's Windows MT5 session. No claim of successful live session execution is made.
