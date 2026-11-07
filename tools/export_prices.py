"""Exports auction prices from a CraftPath SavedVariables file to data/prices.json for the website.

    python3 tools/export_prices.py "D:/World of Warcraft/_forever_/WTF/Account/<ACCOUNT>/SavedVariables/CraftPath.lua"

Only prices of items the recipes use (materials, tools and recipe items) are exported, with the
time each was scanned. Nothing about the character (purchases, known recipes, bags) leaves the file.
"""
import datetime
import json
import os
import sys

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "CraftPath")
OUT = os.path.join(HERE, "..", "data", "prices.json")
FILES = ["Data/Shared.lua", "Data/Engineering.lua", "Data/Blacksmithing.lua", "Data/Cooking.lua", "Core/Recipes.lua"]


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
    if not argv:
        sys.exit(__doc__)
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    with open(argv[0], encoding="utf-8") as fh:
        lua.execute(fh.read())
    db = lua.globals().CraftPathDB
    names = wanted_items()
    prices, newest = {}, 0
    for name, e in (db.prices or {}).items():
        if name in names and e.p:
            prices[name] = {"p": int(e.p), "t": int(e.t or 0)}
            if e.q:
                prices[name]["q"] = int(e.q)
            newest = max(newest, int(e.t or 0))
    vendor = {n: int(p) for n, p in (db.vendor or {}).items() if n in names}
    out = {
        "updated": datetime.datetime.fromtimestamp(newest, datetime.timezone.utc).isoformat() if newest else None,
        "note": "Lowest buyout from the site owner's CraftPath scans (Horde). Prices change constantly; "
                "the addon uses your own live scan.",
        "prices": dict(sorted(prices.items())),
        "vendor": dict(sorted(vendor.items())),
    }
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print(f"Wrote {os.path.relpath(OUT)}: {len(prices)} auction prices, {len(vendor)} vendor prices, newest {out['updated']}")


if __name__ == "__main__":
    main()
