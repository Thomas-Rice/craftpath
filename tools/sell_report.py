"""What to sell, from the saved files: the stock snapshot CraftPath saves on reload/logout
(CraftPathDB.stock), its prices and price history, and vendor sell prices.

    python3 tools/sell_report.py path/to/SavedVariables/CraftPath.lua [character]

Same rule as the addon (Core/Sell.lua): auction when it sells (10+ listed) and, after the
5% cut at this week's low, beats the vendor by at least 1s and 20%; otherwise vendor.
It doesn't know your route, so it can't say what to keep for later steps: check the
Route tab, or the keep marks in your bags.
"""
import os
import re
import sys
import time

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ITEMS = os.path.join(HERE, "..", "CraftPath", "Data", "Items.lua")
MIN_GAIN, MIN_SHARE, MIN_LISTED, MAX_AGE = 100, 0.2, 10, 7 * 86400


def money(c):
    c = int(round(c))
    g, s, cp = c // 10000, c // 100 % 100, c % 100
    return " ".join(p for p in (f"{g}g" if g else "", f"{s}s" if s else "", f"{cp}c" if cp or not c else "") if p)


def crafted_names():
    names = set()
    data = os.path.join(HERE, "..", "CraftPath", "Data")
    for f in os.listdir(data):
        for line in open(os.path.join(data, f), encoding="utf-8"):
            parts = line.strip().split("|")
            if len(parts) >= 9 and parts[1].isdigit():
                names.add(parts[0])
    return names


def main(argv):
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(argv[0], encoding="utf-8").read())
    db = lua.globals().CraftPathDB
    if not db.stock:
        print("No stock snapshot yet: /reload in game once with CraftPath 0.15.2 or later.")
        return
    chars = [k for k in db.stock.keys()]
    who = argv[1] if len(argv) > 1 else max(chars, key=lambda c: db.stock[c].t or 0)
    snap = db.stock[who]
    sell = {m.group(1): int(m.group(2)) for m in re.finditer(r'\["(.+?)"\] = (\d+),', open(ITEMS, encoding="utf-8").read())}
    crafted = crafted_names()
    print(f"{who}, snapshot {time.strftime('%d %b %H:%M', time.gmtime(snap.t))} UTC")
    rows = []
    now = time.time()
    for name, c in snap["items"].items():
        if name not in crafted:
            continue
        bags, bank, mail = c[1], c[2], c[3]
        n = bags + bank + mail
        v = (db.sell and db.sell[name]) or sell.get(name, 0)
        e = db.prices[name]
        auction = None
        if e and e.p and now - (e.t or 0) <= MAX_AGE and (e.q or 0) >= MIN_LISTED:
            h = db.history and db.history[name]
            low = min([x.p for x in h.values() if x.p] or [e.p]) if h else e.p
            auction = min(e.p, low) * 0.95
        if auction is not None and auction >= v + max(MIN_GAIN, v * MIN_SHARE):
            rows.append(("auction", name, n, bags, auction, auction * n, e.p))
        elif v:
            rows.append(("vendor", name, n, bags, v, v * n, None))
    for how in ("auction", "vendor"):
        part = sorted([r for r in rows if r[0] == how], key=lambda r: -r[5])
        if not part:
            continue
        print(f"\n{how.upper()}: {money(sum(r[5] for r in part))}")
        for _, name, n, bags, each, total, now_p in part:
            where = "" if bags == n else f" ({bags} in bags)"
            extra = f", list at ~{money(now_p - 1)}" if now_p else ""
            print(f"  {n:>4} {name}{where}: {money(each)} each = {money(total)}{extra}")


if __name__ == "__main__":
    main(sys.argv[1:])
