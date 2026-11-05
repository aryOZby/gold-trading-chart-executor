from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import Enum


class Side(str, Enum):
    BUY = "BUY"
    SELL = "SELL"


@dataclass(frozen=True)
class ParsedSignal:
    symbol: str
    side: Side
    zone_low: float
    zone_high: float
    tps: tuple[float, ...]
    sl: float
    raw_text: str
    entry: float = 0.0

    @property
    def tp_count(self) -> int:
        return len(self.tps)


@dataclass
class GroupSlot:
    slot: int
    name: str
    title: str
    chat_id: int
    magic: int
    trade: bool = False
    lot: float = 0.01
    strategy_id: int = 1


@dataclass(frozen=True)
class Strategy:
    id: int
    name: str
    entry: str  # market | limit
    take: str  # last | all | farthest
    take_count: int
    breakeven: str  # first | from_end
    breakeven_index: int


@dataclass(frozen=True)
class PlannedLeg:
    tp_index: int
    tp: float
    sl: float
    lot: float
    entry_type: str
    entry_price: float
    is_breakeven_trigger: bool


@dataclass
class CatalogSignal:
    id: str
    group_name: str
    group_id: int
    group_title: str
    received_at: datetime
    side: Side
    symbol: str
    entry: float
    zone_low: float
    zone_high: float
    sl: float
    tps: tuple[float, ...]
    raw_text: str
