# Gold Trading — Chart Executor

Execution service for the gold-trading desk: one MT5 Expert Advisor, no extra process. It does not listen to Telegram and does not build reports.

| Service | Role |
|---|---|
| [Telegram Group Listener](https://github.com/aryOZby/gold-signal-listener) | Listen to groups by chat id and hand off each recognized signal |
| **Chart Executor** (this repo) | Read those signals on the MT5 chart and trade them |
| Reporting (planned) | Build monthly Excel tables per group and email them |

The EA sits on a gold chart (`XAUUSD`, `XAUUSD.s`, …) and trades the chart symbol. Its Inputs are the operator controls for each group:

- **Trade** — on/off for opening positions
- **Lot** — volume per position
- **Strategy** — playbook `1`–`5`
- **Chat id** — the Telegram group feeding that slot
- **Max open trades** — how many of that group's trades may run at once; `0` means unlimited

Changes apply as soon as you press OK in Inputs.

A trade is one signal opened with one strategy; all of its positions count as that one trade while any of them is still open or pending.

## Order comment

Every position and order carries the comment `S<strategy>|G<group>|N<number>|tp<row>`, for example `S1|G2|N14|tp5`: strategy 1, slot 2 (Technical Pips), the 14th trade of that group this month, and the leg aimed at the 5th TP row of the signal. All legs of a trade share S, G, and N. Numbering is per group and restarts at `N1` on the first of each month (Israel time). Counters live in `Common\Files\gt_count\`.

## Hand-off

The listener writes each signal to MT5 `Common\Files\gt_signals\<chat_id>_<message_id>.json`. The EA picks it up within a fraction of a second and moves it to `gt_signals\done\` (opened, or logged in dry run) or `gt_signals\skipped\` (Trade off, stale, weekend, invalid). A file whose name is already in either folder is a duplicate and is deleted.

## Strategies

| # | Entry | Positions | Take-profits | Move SL to entry |
|---|---|---|---|---|
| 1 | Market | 3 | Last 3 TP rows | After the 3rd TP from the end |
| 2 | Limit at first header price | One per TP row | Every TP row | After the first TP |
| 3 | Always pending at first header price | 2 | Two farthest TPs | After the 2nd TP from the end |
| 4 | Market | 3 | Last 3 TP rows | After the 3rd TP from the end |
| 5 | Market | 3 | Last 3 TP rows | After the 3rd TP from the end |

All legs share the signal SL. In strategy 2 a limit leg becomes a market order when price is already at or past the entry. Strategy 3 never does: it places a limit when price still has to come to the entry, and a stop order at the entry when price is already better, so every leg opens at the signal price. Only when price is within the broker's minimum stop distance of the entry does it open at market.

## Chart slots

| Slot | Group | Chat id | Magic |
|---|---|---|---|
| 1 | VIP SIGNALS ROOM (LIFETIME) | -1002001216034 | 270101 |
| 2 | Technical Pips | -1001569906975 | 270102 |
| 3 | profit__kings | -1002984909577 | 270103 |
| 4 | GOLD SNIPER | -1001754381715 | 270104 |
| 5 | Trade With Samder | -1002366136201 | 270105 |
| 6 | GOLD BULLET SIGNALS | -1003186082440 | 270106 |

## Protections

They only touch positions and orders with this EA's magics.

| Protection | Behaviour |
|---|---|
| Breakeven | When price touches the strategy's breakeven TP, every open leg of that signal gets SL = its entry price and any unfilled limit is deleted. If the broker refuses the stop, the leg is closed. Tracking survives EA restarts (`gt_state\`). |
| Missing SL/TP | A position without SL or TP for more than 5 seconds gets SL and TP 50 pips (5.00 on XAUUSD) from its open price. If price is already beyond that stop, the position is closed. |
| Friday close | From Friday 23:30 Israel time until Monday 00:00 Israel, all positions are closed, pending orders deleted, and new signals are refused. Israel summer/winter time is calculated in the EA. |
| Stale signals | Signals older than 5 minutes are not opened. |
| Unfilled orders | A pending order still waiting after 12 hours is deleted. Every deleted pending order — expired, removed at breakeven, or removed at the Friday close — is recorded as not executed in `Common\Files\gt_journal\unfilled.csv` with its comment, prices, lot, and reason. |
| Dry run | Signals are logged in the Experts tab and no orders are sent. The guard and Friday close still run. |

Distances, times, and the age limit are EA Inputs.

## Setup

1. In the listener `config.yaml`, set `paths.outbox_dir` to `C:\Users\Administrator\AppData\Roaming\MetaQuotes\Terminal\Common\Files\gt_signals` and restart the listener.
2. Copy `mt5/GoldChartExecutor.mq5` to the terminal's `MQL5\Experts`, compile with F7, and attach it to a gold chart with Algo Trading allowed.
3. Enable Trade for the groups you want in Inputs.
