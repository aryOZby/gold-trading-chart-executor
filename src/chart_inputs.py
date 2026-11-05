from __future__ import annotations

from pathlib import Path

from .models import GroupSlot

# Written by GoldChartExecutor.mq5: slot=trade,lot,strategy
CHART_FILE = "gs_chart.txt"


def read_chart_inputs(common_dir: Path, groups: list[GroupSlot]) -> list[GroupSlot] | None:
    """Overlay the chart Inputs on the configured groups.

    Returns the groups unchanged when the EA has never written the file, and None when the
    file exists but cannot be read completely, so the caller can retry instead of treating
    every group as off.
    """
    path = common_dir / CHART_FILE
    if not path.exists():
        return groups
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    overlay: dict[int, tuple[bool, float, int]] = {}
    try:
        for line in text.splitlines():
            line = line.strip()
            if not line or "=" not in line or line.startswith("#"):
                continue
            slot_s, rest = line.split("=", 1)
            parts = rest.split(",")
            if len(parts) < 3:
                return None
            overlay[int(slot_s)] = (parts[0].strip() == "1", float(parts[1]), int(float(parts[2])))
    except ValueError:
        return None
    if any(group.slot not in overlay for group in groups):
        return None
    updated = []
    for group in groups:
        trade, lot, strategy_id = overlay[group.slot]
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


def describe(groups: list[GroupSlot]) -> str:
    return " | ".join(
        f"{g.slot} {g.title or g.name}: {'ON' if g.trade else 'off'} lot={g.lot} S{g.strategy_id}"
        for g in groups
    )
