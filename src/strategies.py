from __future__ import annotations

from pathlib import Path

import yaml

from .models import ParsedSignal, PlannedLeg, Side, Strategy

ROOT = Path(__file__).resolve().parent.parent


def load_strategies(path: Path | None = None) -> dict[int, Strategy]:
    raw = yaml.safe_load((path or ROOT / "strategies.yaml").read_text(encoding="utf-8")) or {}
    out: dict[int, Strategy] = {}
    for key, item in (raw.get("strategies") or {}).items():
        sid = int(key)
        out[sid] = Strategy(
            id=sid,
            name=str(item["name"]),
            entry=str(item["entry"]).lower(),
            take=str(item["take"]).lower(),
            take_count=int(item.get("take_count") or 0),
            breakeven=str(item["breakeven"]).lower(),
            breakeven_index=int(item.get("breakeven_index") or 1),
        )
    return out


def plan_trades(parsed: ParsedSignal, strategy: Strategy, lot: float) -> list[PlannedLeg]:
    indexed = list(enumerate(parsed.tps, start=1))
    if not indexed:
        return []
    if strategy.take == "all":
        chosen = indexed
    elif strategy.take == "last":
        n = strategy.take_count if strategy.take_count > 0 else len(indexed)
        chosen = indexed[-n:]
    elif strategy.take == "farthest":
        n = strategy.take_count if strategy.take_count > 0 else len(indexed)
        mid = (parsed.zone_low + parsed.zone_high) / 2.0

        def _distance(item: tuple[int, float]) -> float:
            _index, price = item
            return (price - mid) if parsed.side is Side.BUY else (mid - price)

        ranked = sorted(indexed, key=lambda item: (_distance(item), item[0]), reverse=True)
        chosen = sorted(ranked[:n], key=lambda item: item[0])
    else:
        raise ValueError(f"Unknown take mode {strategy.take}")

    trigger_index = _breakeven_tp_index(indexed, strategy)
    entry_price = parsed.entry or parsed.zone_low
    return [
        PlannedLeg(
            tp_index=tp_index,
            tp=price,
            sl=parsed.sl,
            lot=lot,
            entry_type=strategy.entry,
            entry_price=entry_price,
            is_breakeven_trigger=(tp_index == trigger_index),
        )
        for tp_index, price in chosen
    ]


def _breakeven_tp_index(indexed: list[tuple[int, float]], strategy: Strategy) -> int | None:
    if not indexed:
        return None
    if strategy.breakeven == "first":
        return indexed[0][0]
    if strategy.breakeven == "from_end":
        n = strategy.breakeven_index
        if n <= 0 or n > len(indexed):
            return indexed[0][0]
        return indexed[-n][0]
    return None
