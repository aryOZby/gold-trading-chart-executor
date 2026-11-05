# Gold Trading — Chart Executor

Execution service for the gold-trading desk. It does not listen to Telegram and does not build reports.

| Service | Role |
|---|---|
| [Telegram Group Listener](https://github.com/aryOZby/gold-signal-listener) | Listen to groups by chat id and hand off each recognized signal |
| **Chart Executor** (this repo) | Pull those signals and trade them from the chart |
| Reporting (planned) | Build monthly Excel tables per group and email them |

The Expert Advisor sits on gold. Its Inputs are the operator controls for each group:

- **Trade** — on/off for opening positions
- **Lot** — volume per position
- **Strategy** — playbook `1`–`5` from `strategies.yaml`

## Strategies

| # | Entry | Positions | Take-profits | Move SL to entry |
|---|---|---|---|---|
| 1 | Market | 3 | Last 3 TP rows | After the 3rd TP from the end |
| 2 | Limit at first header price | One per TP row | Every TP row | After the first TP |
| 3 | Limit at first header price | 2 | Two farthest TPs | After the 2nd TP from the end |
| 4 | Market | 3 | Last 3 TP rows | After the 3rd TP from the end |
| 5 | Market | 3 | Last 3 TP rows | After the 3rd TP from the end |

All legs share the signal SL. Lot comes from the chart Input for that group.

## Chart slots

1. VIP SIGNALS ROOM (LIFETIME)
2. Technical Pips
3. profit__kings
4. GOLD SNIPER
5. Trade With Samder
6. GOLD BULLET SIGNALS

## Setup

```bat
cd C:\Users\Administrator\gold-trading-chart-executor
copy config.example.yaml config.yaml
py -3 -m venv .venv
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe main.py
```

Point `listener.outbox_dir` at the listener `data\outbox` folder and `broker.common_files_dir` at MT5 `Common\Files`. Each signal file is moved to `data\processed` or `data\skipped` after it is handled; a file whose name is already there is treated as a duplicate and discarded. Compile `mt5/GoldChartExecutor.mq5` and attach it to XAUUSD. Trade stays off until you enable a group in Inputs, and **Dry run** is on until you turn it off.

## How orders reach the chart

Python writes one order file per signal to `Common\Files\gt_cmd\<slot>-<msg id>.txt`. The EA reads it, deletes it, and opens the legs with magic `270100 + slot`. Python never talks to MT5 directly.

## Protections

All protections run inside the EA, so they keep working when Python is stopped. They only touch positions and orders with this EA's magics (`270101`–`270106`).

| Protection | Behaviour |
|---|---|
| Breakeven | When price touches the strategy's breakeven TP, every open leg of that signal gets SL = its entry price and any unfilled limit is deleted. If the broker refuses the stop, the leg is closed. Tracking survives EA restarts (`gt_state\`). |
| Missing SL/TP | A position without SL or TP for more than 5 seconds gets SL and TP 50 pips (5.00 on XAUUSD) from its open price. If price is already beyond that stop, the position is closed. |
| Friday close | From Friday 23:30 Israel time until Monday 00:00 Israel, all positions are closed, pending orders deleted, and new signals are refused. Israel summer/winter time is calculated in the EA. |
| Stale signals | Signals older than 5 minutes are not opened. |
| Dry run | On by default: signals are logged in the Experts tab, no orders are sent. The guard and Friday close still run. |

Distances, times, and the age limit are EA Inputs.
