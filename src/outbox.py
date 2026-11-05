from __future__ import annotations

import json
import shutil
from datetime import datetime
from pathlib import Path

from .models import CatalogSignal, Side


def list_new_signals(outbox_dir: Path) -> list[Path]:
    if not outbox_dir.exists():
        return []
    return sorted(p for p in outbox_dir.glob("*.json") if p.is_file())


def load_signal(path: Path) -> CatalogSignal:
    raw = json.loads(path.read_text(encoding="utf-8"))
    group = raw.get("group") or {}
    return CatalogSignal(
        id=str(raw["id"]),
        group_name=str(group.get("name") or ""),
        group_id=int(group["id"]),
        group_title=str(group.get("title") or ""),
        telegram_msg_id=int(raw["telegram_msg_id"]),
        received_at=datetime.fromisoformat(raw["received_at"]),
        side=Side.BUY if str(raw["side"]).upper() == "BUY" else Side.SELL,
        symbol=str(raw["symbol"]),
        entry=float(raw["entry"]),
        zone_low=float(raw["zone_low"]),
        zone_high=float(raw["zone_high"]),
        sl=float(raw["sl"]),
        tps=tuple(float(x) for x in raw.get("tps") or ()),
        raw_text=str(raw.get("raw_text") or ""),
    )


def already_handled(path: Path, *dirs: Path) -> bool:
    return any((d / path.name).exists() for d in dirs)


def archive(path: Path, dest_dir: Path) -> Path:
    dest_dir.mkdir(parents=True, exist_ok=True)
    target = dest_dir / path.name
    shutil.move(str(path), str(target))
    return target
