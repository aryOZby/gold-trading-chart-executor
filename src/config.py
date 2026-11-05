from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from zoneinfo import ZoneInfo

import yaml
from dotenv import load_dotenv

from .models import GroupSlot
from .strategies import load_strategies, Strategy

ROOT = Path(__file__).resolve().parent.parent


@dataclass
class AppConfig:
    timezone: str
    tz: ZoneInfo
    outbox_dir: Path
    processed_dir: Path
    skipped_dir: Path
    poll_seconds: float
    groups: list[GroupSlot]
    strategies: dict[int, Strategy]
    common_files_dir: Path
    data_dir: Path
    logs_dir: Path


def load_config(path: Path | None = None) -> AppConfig:
    load_dotenv(ROOT / ".env")
    cfg_path = path or (ROOT / "config.yaml")
    raw = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
    listener = raw.get("listener") or {}
    paths = raw.get("paths") or {}
    broker = raw.get("broker") or {}
    groups = []
    for item in raw.get("groups") or []:
        groups.append(
            GroupSlot(
                slot=int(item["slot"]),
                name=str(item["name"]),
                title=str(item.get("title") or item["name"]),
                chat_id=int(item["chat_id"]),
                magic=int(item.get("magic") or 270100 + int(item["slot"])),
            )
        )
    if not groups:
        raise ValueError("Configure at least one group slot")
    tz_name = str(raw.get("timezone") or "Asia/Jerusalem")
    common = str(broker.get("common_files_dir") or "")
    return AppConfig(
        timezone=tz_name,
        tz=ZoneInfo(tz_name),
        outbox_dir=Path(str(listener.get("outbox_dir") or "")),
        processed_dir=ROOT / str(listener.get("processed_dir") or "data/processed"),
        skipped_dir=ROOT / str(listener.get("skipped_dir") or "data/skipped"),
        poll_seconds=float(listener.get("poll_seconds") or 1),
        groups=groups,
        strategies=load_strategies(ROOT / "strategies.yaml"),
        common_files_dir=Path(common) if common else Path("."),
        data_dir=ROOT / str(paths.get("data_dir") or "data"),
        logs_dir=ROOT / str(paths.get("logs_dir") or "logs"),
    )


def group_by_chat_id(cfg: AppConfig, chat_id: int) -> GroupSlot | None:
    return next((g for g in cfg.groups if g.chat_id == chat_id), None)
