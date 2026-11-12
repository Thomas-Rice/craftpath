"""Exports auction prices from a CraftPath SavedVariables file to data/prices.json for the website.

    python3 tools/export_prices.py "D:/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/CraftPath.lua"

Only prices of items the recipes use (materials, tools and recipe items) are exported, with the
time each was scanned. Also adds the skill each trainer recipe is taught at, as recorded at
trainers in game, to data/trainer-levels.json (the recipe sync uses it). Nothing about the character (purchases, known recipes, bags) leaves the file.
"""
import datetime
import json
import os
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "CraftPath")
OUT = os.path.join(HERE, "..", "data", "prices.json")
TRAINER_OUT = os.path.join(HERE, "..", "data", "trainer-levels.json")
from luafiles import pure_files  # noqa: E402
FILES = pure_files()


def wanted_items():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    loader = lua.eval("function(src, name) return assert(loadstring(src, name)) end")
    for rel in FILES:
        with open(os.path.join(ADDON, rel), encoding="utf-8") as fh:
            loader(fh.read(), "@" + rel)("CraftPath", ns)
    names = set()
    profs = ns.Recipes.Professions()
    for i in range(1, len(profs) + 1):
        prof = profs[i]
        reagents = ns.Recipes.AllReagents(prof)
        names.update(reagents[j] for j in range(1, len(reagents) + 1))
        data = ns.Recipes.Load(prof)
        prefixes = ns.RawData.RecipePrefixes[prof]
        for j in range(1, len(data.list) + 1):
            r = data.list[j]
            names.add(r.name)  # intermediate crafts can be bought too
            for k in range(1, len(prefixes) + 1):
                names.add(prefixes[k] + r.name)
    return names


def main(argv=None):
    argv = argv or sys.argv[1:]
    args = [a for a in argv if not a.startswith("--")]
    if not argv:
        sys.exit(__doc__)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(args[0], encoding="utf-8") as fh:
        lua.execute(fh.read())
    db = lua.globals().CraftPathDB
    names = wanted_items()
    # Only recent prices: anything not seen in the 36 hours before the newest price is no
    # longer listed, and old prices mislead. (Full and targeted scans both count.)
    newest_seen = max((int(e.t or 0) for e in (db.prices or {}).values() if e.p), default=0)
    since = newest_seen - 36 * 3600
    prices, newest, dropped = {}, 0, 0
    for name, e in (db.prices or {}).items():
        if name in names and e.p and int(e.t or 0) < since:
            dropped += 1
            continue
        if name in names and e.p:
            prices[name] = {"p": int(e.p), "t": int(e.t or 0)}
            if e.q:
                prices[name]["q"] = int(e.q)
            newest = max(newest, int(e.t or 0))
    vendor = {n: int(p) for n, p in (db.vendor or {}).items() if n in names}
    # Last week's daily lows, so the website can show a "safe" profit like the addon.
    today = newest // 86400 if newest else 0
    for name, h in (db.history or {}).items():
        if name not in prices:
            continue
        days = sorted(int(e.p) for e in h.values() if e.p and int(e.d) > today - 7)
        if len(days) >= 2:
            prices[name].update(low=days[0], med=days[(len(days) - 1) // 2], high=days[-1], days=len(days))
    out = {
        "updated": datetime.datetime.fromtimestamp(newest, datetime.timezone.utc).isoformat() if newest else None,
        "note": "Lowest buyout from the site owner's CraftPath scans (Horde). Prices change constantly; "
                "the addon uses your own live scan.",
        "prices": dict(sorted(prices.items())),
        "vendor": dict(sorted(vendor.items())),
    }
    # Safety: a scan that stopped early would wipe most of the site's prices.
    if os.path.exists(OUT) and "--force" not in argv:
        with open(OUT, encoding="utf-8") as fh:
            before = len(json.load(fh).get("prices", {}))
        if before and len(prices) < 0.6 * before:
            sys.exit(f"Refusing: only {len(prices)} prices vs {before} published (a partial scan?). "
                     "Run a full scan and wait for 'Full scan done', or pass --force.")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print(export_trainer_levels(db))
    print(f"Wrote {os.path.relpath(OUT)}: {len(prices)} auction prices, {len(vendor)} vendor prices, "
          f"newest {out['updated']}; left out {dropped} not seen in the last 36 hours")


def export_trainer_levels(db, path=TRAINER_OUT):
    """Merges the trainer levels this character has seen into data/trainer-levels.json. The game
    shows them at the trainer and the client data doesn't have them."""
    levels = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            levels = json.load(fh)
    added = 0
    for prof, recipes in (db.trainer or {}).items():
        for name, rank in (recipes or {}).items():
            if rank and int(rank) > 0 and levels.setdefault(prof, {}).get(name) != int(rank):
                levels[prof][name] = int(rank)
                added += 1
    if not added:
        return "Trainer levels: nothing new."
    levels = {p: dict(sorted(v.items())) for p, v in sorted(levels.items())}
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(levels, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    return f"Trainer levels: {added} new or changed in {os.path.relpath(path)}."


if __name__ == "__main__":
    main()
