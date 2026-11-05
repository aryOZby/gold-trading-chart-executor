from __future__ import annotations

import logging

from .chart_inputs import read_chart_inputs
from .config import AppConfig
from .models import CatalogSignal, ParsedSignal, PlannedLeg
from .outbox import archive, list_new_signals, load_signal
from .strategies import plan_trades

_LOG = logging.getLogger(__name__)


class ChartEngine:
    def __init__(self, cfg: AppConfig):
        self.cfg = cfg

    def poll_once(self) -> list[tuple[CatalogSignal, list[PlannedLeg]]]:
        groups = {g.chat_id: g for g in read_chart_inputs(self.cfg.common_files_dir, self.cfg.groups)}
        executed: list[tuple[CatalogSignal, list[PlannedLeg]]] = []
        for path in list_new_signals(self.cfg.outbox_dir):
            rec = load_signal(path)
            group = groups.get(rec.group_id)
            if group is None or not group.trade:
                _LOG.info(
                    "Skip %s from %s | %s — Trade is off",
                    rec.id,
                    rec.group_title,
                    rec.group_id,
                )
                archive(path, self.cfg.skipped_dir)
                continue
            strategy = self.cfg.strategies.get(group.strategy_id)
            if strategy is None:
                _LOG.warning(
                    "Skip %s — unknown strategy %s on slot %s",
                    rec.id,
                    group.strategy_id,
                    group.slot,
                )
                archive(path, self.cfg.skipped_dir)
                continue
            parsed = ParsedSignal(
                symbol=rec.symbol,
                side=rec.side,
                zone_low=rec.zone_low,
                zone_high=rec.zone_high,
                tps=rec.tps,
                sl=rec.sl,
                raw_text=rec.raw_text,
                entry=rec.entry,
            )
            legs = plan_trades(parsed, strategy, group.lot)
            _LOG.info(
                "Execute %s [%s | %s] strategy=%s (%s) lot=%s legs=%s %s %s",
                rec.id,
                rec.group_title,
                rec.group_id,
                strategy.id,
                strategy.name,
                group.lot,
                len(legs),
                rec.side.value,
                rec.symbol,
            )
            for leg in legs:
                _LOG.info(
                    "  %s %s lot=%s entry=%s sl=%s tp%s=%s%s",
                    rec.side.value,
                    leg.entry_type,
                    leg.lot,
                    leg.entry_price,
                    leg.sl,
                    leg.tp_index,
                    leg.tp,
                    " BE-trigger" if leg.is_breakeven_trigger else "",
                )
            archive(path, self.cfg.processed_dir)
            executed.append((rec, legs))
        return executed
