from __future__ import annotations

import argparse
import logging
import time
from pathlib import Path

import yaml

from src.config import load_config
from src.engine import ChartEngine
from src.logging_setup import setup_logging

_LOG = logging.getLogger(__name__)


def main() -> int:
    parser = argparse.ArgumentParser(description="Gold Trading — Chart Executor")
    parser.add_argument("--config", default="config.yaml")
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()
    try:
        cfg = load_config(Path(args.config) if args.config else None)
    except yaml.YAMLError as exc:
        print(f"config.yaml syntax error: {exc}")
        return 1
    except (ValueError, KeyError) as exc:
        print(f"config.yaml rejected: {exc}")
        return 1
    setup_logging(cfg.logs_dir)
    _LOG.info(
        "Chart executor start dry_run=%s strategies=%s outbox=%s",
        cfg.dry_run,
        ",".join(str(i) for i in sorted(cfg.strategies)),
        cfg.outbox_dir,
    )
    engine = ChartEngine(cfg)
    if args.once:
        engine.poll_once()
        return 0
    try:
        while True:
            engine.poll_once()
            time.sleep(cfg.poll_seconds)
    except KeyboardInterrupt:
        _LOG.info("Interrupted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
