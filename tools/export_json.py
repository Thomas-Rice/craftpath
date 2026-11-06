"""Exports the addon's recipe data to JSON for the website (one source of truth).

    python3 tools/export_json.py            # writes web/data/recipes.json
"""
import json
import os

from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "CraftPath")
OUT = os.path.join(HERE, "..", "web", "data", "recipes.json")
FILES = ["Data/Shared.lua", "Data/Engineering.lua", "Data/Blacksmithing.lua", "Core/Recipes.lua"]


def to_py(obj):
    if hasattr(obj, "items"):
        d = dict(obj.items())
        if d and all(isinstance(k, int) for k in d):
            return [to_py(d[i]) for i in range(1, len(d) + 1)]
        return {k: to_py(v) for k, v in d.items()}
    return obj


def main():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    loader = lua.eval("function(src, name) return assert(loadstring(src, name)) end")
    for rel in FILES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            loader(fh.read(), "@" + rel)("CraftPath", ns)
    out = {"professions": {}, "vendorItems": to_py(ns.RawData.VendorItems),
           "ranks": to_py(ns.RawData.Ranks), "recipePrefixes": to_py(ns.RawData.RecipePrefixes)}
    for prof in to_py(ns.Recipes.Professions()):
        data = ns.Recipes.Load(prof)
        recipes = []
        for r in to_py(data.list):
            r.pop("index", None)
            recipes.append(r)
        out["professions"][prof] = {"tools": to_py(data.tools), "recipes": recipes}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1, ensure_ascii=False)
    counts = {p: len(v["recipes"]) for p, v in out["professions"].items()}
    print("Wrote", os.path.relpath(OUT), counts)


if __name__ == "__main__":
    main()
