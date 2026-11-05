from __future__ import annotations

import logging
import re
import unicodedata
from typing import Optional

from .models import ParsedSignal, Side

_LOG = logging.getLogger(__name__)

_DASHES = str.maketrans(
    {
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2212": "-",
        "\xa0": " ",
        "\u202f": " ",
        "\u2007": " ",
    }
)

_HEADER = re.compile(
    r"^#?\s*(?P<symbol>[A-Za-z0-9._]+)\s+"
    r"(?P<side>BUY|SELL)"
    r"(?:\s+PLAN)?\s+"
    r"@?(?P<first>\d+(?:\.\d+)?)"
    r"(?:\s*[-_/,]\s*@?(?P<second>\d+(?:\.\d+)?))?\s*$",
    re.IGNORECASE,
)
_MORE = re.compile(r"^MORE\s+(BUY|SELL)\b", re.IGNORECASE)
_TP = re.compile(
    r"^T(?:P|ake\s*Profit)(?:\d{1,2})?\s*(?:\([^)]*\))?\s*[:@]?\s*@?(?P<price>\d+(?:\.\d+)?)\s*$",
    re.IGNORECASE,
)
_SL = re.compile(
    r"^S(?:L|top(?:\s*Loss)?)\s*(?:\([^)]*\))?\s*[:@]?\s*@?(?P<price>\d+(?:\.\d+)?)\b",
    re.IGNORECASE,
)


def _normalize(text: str) -> str:
    text = unicodedata.normalize("NFKC", text)
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = text.translate(_DASHES)
    lines = [" ".join(line.strip().split()) for line in text.split("\n")]
    return "\n".join(line for line in lines if line)


def parse_signal(text: str) -> Optional[ParsedSignal]:
    if not text or not text.strip():
        return None
    normalized = _normalize(text)
    lines = normalized.split("\n")
    header = None
    header_index = None
    for i, line in enumerate(lines):
        match = _HEADER.match(line)
        if match:
            header = match
            header_index = i
            break
    if header is None:
        return None
    tps: list[float] = []
    sl: float | None = None
    for line in lines[header_index + 1 :]:
        if _MORE.match(line) or line.upper() in {"TP OPEN", "TOPEN"}:
            continue
        tp_match = _TP.match(line)
        if tp_match:
            tps.append(float(tp_match.group("price")))
            continue
        sl_match = _SL.match(line)
        if sl_match:
            sl = float(sl_match.group("price"))
    if not tps or sl is None:
        _LOG.info("Header matched but missing TP/SL: tps=%s sl=%s", tps, sl)
        return None
    first = float(header.group("first"))
    second_raw = header.group("second")
    second = float(second_raw) if second_raw else first
    symbol = header.group("symbol").upper()
    if symbol == "GOLD":
        symbol = "XAUUSD"
    return ParsedSignal(
        symbol=symbol,
        side=Side.BUY if header.group("side").upper() == "BUY" else Side.SELL,
        zone_low=min(first, second),
        zone_high=max(first, second),
        tps=tuple(tps),
        sl=sl,
        raw_text=text.strip(),
        entry=first,
    )
