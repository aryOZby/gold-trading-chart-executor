from __future__ import annotations

import os
from pathlib import Path

from .models import CatalogSignal, PlannedLeg

# Read by GoldChartExecutor.mq5 from MT5's Common\Files folder.
CMD_DIR = "gt_cmd"


def command_key(slot: int, rec: CatalogSignal) -> str:
    return f"{slot}-{rec.telegram_msg_id}"


def write_command(
    common_dir: Path,
    slot: int,
    rec: CatalogSignal,
    legs: list[PlannedLeg],
    trigger: float | None,
) -> Path:
    folder = common_dir / CMD_DIR
    folder.mkdir(parents=True, exist_ok=True)
    key = command_key(slot, rec)
    lines = [
        f"key={key}",
        f"slot={slot}",
        f"side={rec.side.value}",
        f"entry_type={legs[0].entry_type}",
        f"entry={legs[0].entry_price}",
        f"sl={rec.sl}",
        f"trigger={trigger if trigger is not None else 0}",
        f"received_at={int(rec.received_at.timestamp())}",
    ]
    lines += [f"leg={leg.tp_index}|{leg.tp}" for leg in legs]
    path = folder / f"{key}.txt"
    # The EA scans *.txt, so it must never see a half-written file.
    tmp = folder / f"{key}.tmp"
    tmp.write_text("\n".join(lines) + "\n", encoding="ascii")
    os.replace(tmp, path)
    return path
