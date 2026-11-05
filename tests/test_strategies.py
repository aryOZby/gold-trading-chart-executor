from src.parser import parse_signal
from src.strategies import breakeven_price, load_strategies, plan_trades

STRATEGIES = load_strategies()

S1 = """#XAUUSD SELL 4315-4318

TP 4312
TP 4309
TP 4305
TP 4300
TP 4295
TP 4285

SL 4327
"""

S2 = """XAUUSD BUY PLAN @4397_4395

tp @4418
tp @4444

SL@4381
"""

S3 = """XAUUSD BUY 4116
MORE BUY 4113

TP1 4119
TP2 4122
TP3 4126

TP OPEN

SL 4106 SCALPING
"""

S4 = """GOLD SELL 4146/4150

SL 4150

TP 4143
TP 4140
TP 4137
TP 4134
TP 4130
TP 4125
TP 4115
"""

S5 = """#XAUUSD SELL  4164
#XAUUSD SELL 4167

TP1 4161
TP2 4158
TP3 4155
TP4 4152
TP5 4149
TP6 4143

SL   4177
"""


def test_strategy_1_last_three_market_be_third_from_end():
    parsed = parse_signal(S1)
    assert parsed is not None
    legs = plan_trades(parsed, STRATEGIES[1], 0.05)
    assert [leg.tp for leg in legs] == [4300, 4295, 4285]
    assert all(leg.entry_type == "market" for leg in legs)
    assert all(leg.sl == 4327 and leg.lot == 0.05 for leg in legs)
    triggers = [leg.tp_index for leg in legs if leg.is_breakeven_trigger]
    assert triggers == [4]


def test_strategy_2_limit_all_tps_be_first():
    parsed = parse_signal(S2)
    assert parsed is not None
    legs = plan_trades(parsed, STRATEGIES[2], 0.01)
    assert [leg.tp for leg in legs] == [4418, 4444]
    assert all(leg.entry_type == "limit" for leg in legs)
    assert legs[0].entry_price == 4397
    assert legs[0].is_breakeven_trigger is True
    assert legs[1].is_breakeven_trigger is False


def test_strategy_3_two_farthest_limit_be_second_from_end():
    parsed = parse_signal(S3)
    assert parsed is not None
    legs = plan_trades(parsed, STRATEGIES[3], 0.02)
    assert [leg.tp for leg in legs] == [4122, 4126]
    assert all(leg.entry_type == "limit" for leg in legs)
    assert legs[0].entry_price == 4116
    triggers = [leg.tp for leg in legs if leg.is_breakeven_trigger]
    assert triggers == [4122]


def test_strategy_4_gold_slash_last_three():
    parsed = parse_signal(S4)
    assert parsed is not None
    legs = plan_trades(parsed, STRATEGIES[4], 0.01)
    assert [leg.tp for leg in legs] == [4130, 4125, 4115]
    assert all(leg.entry_type == "market" for leg in legs)
    assert [leg.tp for leg in legs if leg.is_breakeven_trigger] == [4130]


def test_strategy_5_double_header_last_three():
    parsed = parse_signal(S5)
    assert parsed is not None
    legs = plan_trades(parsed, STRATEGIES[5], 0.03)
    assert parsed.entry == 4164
    assert [leg.tp for leg in legs] == [4152, 4149, 4143]
    assert all(leg.entry_type == "market" for leg in legs)


def test_breakeven_price_per_strategy():
    expected = {1: (S1, 4300), 2: (S2, 4418), 3: (S3, 4122), 4: (S4, 4130), 5: (S5, 4152)}
    for strategy_id, (text, price) in expected.items():
        parsed = parse_signal(text)
        assert parsed is not None
        assert breakeven_price(parsed, STRATEGIES[strategy_id]) == price
