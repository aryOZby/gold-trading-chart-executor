from __future__ import annotations

from pathlib import Path

from .models import GroupSlot

# Written by GoldChartExecutor.mq5: slot=trade,lot,strategy
CHART_FILE = "gs_chart.txt"


def read_chart_inputs(common_dir: Path, groups: list[GroupSlot]) -> list[GroupSlot]:
    path = common_dir / CHART_FILE
    if not path.exists():
        return groups
    overlay: dict[int, tuple[bool, float, int]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or "=" not in line or line.startswith("#"):
            continue
        slot_s, rest = line.split("=", 1)
        parts = rest.split(",")
        if len(parts) < 3:
            continue
        overlay[int(slot_s)] = (parts[0].strip() == "1", float(parts[1]), int(float(parts[2])))
    updated = []
    for group in groups:
        row = overlay.get(group.slot)
        if row is None:
            updated.append(group)
            continue
        trade, lot, strategy_id = row
        updated.append(
            GroupSlot(
                slot=group.slot,
                name=group.name,
                title=group.title,
                chat_id=group.chat_id,
                magic=group.magic,
                trade=trade,
                lot=lot,
                strategy_id=strategy_id,
            )
        )
    return updated
