from pathlib import Path

from src.chart_inputs import read_chart_inputs
from src.models import GroupSlot


def _groups():
    return [
        GroupSlot(slot=1, name="vip", title="VIP", chat_id=-1001, magic=1),
        GroupSlot(slot=4, name="sniper", title="SNIPER", chat_id=-1004, magic=4),
    ]


def test_chart_inputs_overlay_trade_lot_strategy(tmp_path: Path):
    (tmp_path / "gs_chart.txt").write_text("1=1,0.07,5\n4=0,0.02,3\n", encoding="utf-8")
    groups = read_chart_inputs(tmp_path, _groups())
    vip, sniper = groups
    assert vip.trade is True
    assert vip.lot == 0.07
    assert vip.strategy_id == 5
    assert sniper.trade is False
    assert sniper.lot == 0.02
    assert sniper.strategy_id == 3


def test_half_written_file_is_not_read_as_all_off(tmp_path: Path):
    (tmp_path / "gs_chart.txt").write_text("1=1,0.07,5\n", encoding="utf-8")
    assert read_chart_inputs(tmp_path, _groups()) is None
    (tmp_path / "gs_chart.txt").write_text("", encoding="utf-8")
    assert read_chart_inputs(tmp_path, _groups()) is None
