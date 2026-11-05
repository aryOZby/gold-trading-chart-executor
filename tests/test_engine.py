import json
from pathlib import Path
from zoneinfo import ZoneInfo

from src.config import AppConfig
from src.engine import ChartEngine
from src.models import GroupSlot
from src.strategies import load_strategies

LISTENER_FILE = {
    "id": "-1001569906975_501",
    "group": {"name": "technical_pips", "id": -1001569906975, "title": "Technical Pips ™"},
    "received_at": "2026-11-05T08:15:00+00:00",
    "telegram_msg_id": 501,
    "side": "SELL",
    "symbol": "XAUUSD",
    "entry": 4315.0,
    "zone_low": 4315.0,
    "zone_high": 4318.0,
    "sl": 4327.0,
    "tps": [4312.0, 4309.0, 4305.0, 4300.0, 4295.0, 4285.0],
    "raw_text": "#XAUUSD SELL 4315-4318",
}


def _cfg(tmp_path: Path) -> AppConfig:
    return AppConfig(
        timezone="Asia/Jerusalem",
        tz=ZoneInfo("Asia/Jerusalem"),
        dry_run=True,
        outbox_dir=tmp_path / "outbox",
        processed_dir=tmp_path / "processed",
        skipped_dir=tmp_path / "skipped",
        poll_seconds=1,
        groups=[
            GroupSlot(slot=2, name="technical_pips", title="Technical Pips", chat_id=-1001569906975, magic=270102)
        ],
        strategies=load_strategies(),
        common_files_dir=tmp_path / "common",
        data_dir=tmp_path / "data",
        logs_dir=tmp_path / "logs",
        broker_type="dry_run",
    )


def _drop(cfg: AppConfig) -> Path:
    cfg.outbox_dir.mkdir(parents=True, exist_ok=True)
    path = cfg.outbox_dir / f"{LISTENER_FILE['id']}.json"
    path.write_text(json.dumps(LISTENER_FILE, ensure_ascii=False), encoding="utf-8")
    return path


def _chart(cfg: AppConfig, line: str) -> None:
    cfg.common_files_dir.mkdir(parents=True, exist_ok=True)
    (cfg.common_files_dir / "gs_chart.txt").write_text(line, encoding="utf-8")


def test_listener_file_planned_with_chart_lot_and_strategy(tmp_path: Path):
    cfg = _cfg(tmp_path)
    _chart(cfg, "2=1,0.05,1\n")
    _drop(cfg)
    done = ChartEngine(cfg).poll_once()
    assert len(done) == 1
    rec, legs = done[0]
    assert rec.group_title == "Technical Pips ™"
    assert [leg.tp for leg in legs] == [4300.0, 4295.0, 4285.0]
    assert all(leg.lot == 0.05 for leg in legs)
    assert (cfg.processed_dir / "-1001569906975_501.json").exists()
    assert not list(cfg.outbox_dir.glob("*.json"))


def test_trade_off_moves_signal_to_skipped(tmp_path: Path):
    cfg = _cfg(tmp_path)
    _chart(cfg, "2=0,0.05,1\n")
    _drop(cfg)
    assert ChartEngine(cfg).poll_once() == []
    assert (cfg.skipped_dir / "-1001569906975_501.json").exists()


def test_same_signal_twice_is_executed_once(tmp_path: Path):
    cfg = _cfg(tmp_path)
    _chart(cfg, "2=1,0.05,1\n")
    engine = ChartEngine(cfg)
    _drop(cfg)
    assert len(engine.poll_once()) == 1
    _drop(cfg)
    assert engine.poll_once() == []
    assert not list(cfg.outbox_dir.glob("*.json"))
