"""The website runs the addon's own Lua planner in wasmoon (Lua 5.4). This checks it gives
the same routes and totals as the addon's Lua 5.1 run (lupa) for the same prices."""
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from run_tests import SAMPLE_PRICES, load_core, lua_list, plan  # noqa: E402


def main():
    lua, ns = load_core()
    prices = dict(SAMPLE_PRICES)
    for prof in ("Engineering", "Blacksmithing", "Cooking", "Alchemy", "Tailoring"):
        for name in lua_list(ns.Recipes.AllReagents(prof)):
            prices.setdefault(name, 60 + 7 * len(name))
    cases = [
        {"profession": "Engineering", "from": 1, "to": 300, "faction": "Horde"},
        {"profession": "Blacksmithing", "from": 1, "to": 225, "faction": "Horde", "allowFavor": False},
        {"profession": "Blacksmithing", "from": 95, "to": 300, "faction": "Alliance"},
        {"profession": "Engineering", "from": 150, "to": 300, "faction": "Horde", "spec": "Gnomish"},
        {"profession": "Cooking", "from": 1, "to": 300, "faction": "Horde"},
        {"profession": "Cooking", "from": 1, "to": 300, "faction": "Horde", "charLevel": 30},
        {"profession": "Alchemy", "from": 1, "to": 300, "faction": "Horde"},
        {"profession": "Tailoring", "from": 50, "to": 250, "faction": "Alliance"},
    ]
    for c in cases:
        c["prices"] = prices
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
        json.dump(cases, fh)
    try:
        res = subprocess.run(["node", os.path.join(HERE, "web_plan.mjs"), fh.name], capture_output=True,
                             text=True, cwd=os.path.join(HERE, ".."))
    finally:
        os.remove(fh.name)
    assert res.returncode == 0, res.stderr
    out = json.loads(res.stdout)
    for c, web in zip(cases, out["plans"]):
        extra = {k: v for k, v in c.items() if k not in ("profession", "from", "to", "prices")}
        ref = plan(lua, ns, c["profession"], c["from"], c["to"], prices=prices, **extra)
        label = f'{c["profession"]} {c["from"]}-{c["to"]} {extra}'
        assert not web.get("error"), (label, web.get("error"))
        assert not ref.error, (label, ref.error)
        ref_steps = [(s["from"], s.to, s.recipe.name, s.crafts) for s in lua_list(ref.steps)]
        web_steps = [(s["from"], s["to"], s["recipe"]["name"], s["crafts"]) for s in web["steps"]]
        assert ref_steps == web_steps, (label, ref_steps, web_steps)
        assert abs(ref.total - web["total"]) < 1, (label, ref.total, web["total"])
        assert len(lua_list(ref.shopping)) == len(web["shopping"]), label
    print("Web planner matches the addon:", len(cases), "plans;",
          {p: v["count"] for p, v in out["data"]["professions"].items()})


if __name__ == "__main__":
    main()
