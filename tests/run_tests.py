"""Runs CraftPath's pure-Lua core (Data + Recipes + Planner) under Lua 5.1 via lupa.

Usage:  python3 tests/run_tests.py            # run assertions
        python3 tests/run_tests.py --show     # also print the sample plans
The sample prices below are rough placeholders to exercise the planner, not real
Forever auction prices.
"""
import os
import sys

from lupa import lua51

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CraftPath")
CORE_FILES = ["Data/Shared.lua", "Data/Engineering.lua", "Data/Blacksmithing.lua",
              "Core/Recipes.lua", "Core/Planner.lua"]

# Placeholder prices in copper, loosely Classic-like.
SAMPLE_PRICES = {
    "Rough Stone": 10, "Coarse Stone": 30, "Heavy Stone": 60, "Solid Stone": 80, "Dense Stone": 150,
    "Copper Bar": 40, "Bronze Bar": 100, "Silver Bar": 150, "Iron Bar": 120, "Gold Bar": 600,
    "Steel Bar": 200, "Mithril Bar": 250, "Truesilver Bar": 800, "Thorium Bar": 300,
    "Dark Iron Bar": 5000, "Arcanite Bar": 40000, "Azerothium Bar": 1500,
    "Linen Cloth": 10, "Wool Cloth": 40, "Silk Cloth": 60, "Mageweave Cloth": 100, "Runecloth": 150,
    "Light Leather": 20, "Medium Leather": 40, "Heavy Leather": 80, "Thick Leather": 120, "Rugged Leather": 250,
    "Moss Agate": 300, "Malachite": 50, "Tigerseye": 80, "Shadowgem": 150, "Jade": 400, "Citrine": 500,
    "Aquamarine": 600, "Star Ruby": 1200, "Large Opal": 2000, "Blue Sapphire": 3000, "Black Pearl": 2500,
    "Elemental Fire": 600, "Elemental Earth": 500, "Elemental Air": 1000, "Heart of Fire": 1500,
    "Essence of Air": 8000, "Fiery Core": 20000, "Lava Core": 20000, "Small Obsidian Shard": 3000,
    "Green Dye": 150, "Bolt of Linen Cloth": 30, "Bauxite": 200,
    "Schematic: Thorium Shells": 30000, "Schematic: Large Blue Rocket Cluster": 8000,
    "Plans: Dark Iron Shoulders": 20000,
}


def load_core():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    for rel in CORE_FILES:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            chunk = lua.execute("return function(src, name) return assert(loadstring(src, name)) end")(fh.read(), "@" + rel)
        chunk("CraftPath", ns)
    return lua, ns


def plan(lua, ns, prof, frm=1, to=300, prices=None, **extra):
    prices = SAMPLE_PRICES if prices is None else prices
    opts = lua.table_from({
        "profession": prof, "from": frm, "to": to,
        "ahPrice": lambda name: prices.get(name),
        **extra,
    })
    return ns.Planner.Plan(opts)


def lua_list(t):
    return [t[i] for i in range(1, len(t) + 1)] if t else []


def show(ns, p):
    money = ns.Planner.Money
    if p.error:
        print("ERROR:", p.error)
        for b in lua_list(p.blocked)[:5]:
            print("   ", b.recipe, b.source, lua_list(b.missing))
        return
    print(f"{p.profession} {p.frm if False else p['from']}-{p.to}: expected {money(p.expectedGold)}, list {money(p.total)}")
    for st in lua_list(p.steps):
        learn = f" (learn {money(st.learnCost)} via {st.learnHow})" if st.learnCost else ""
        print(f"  {st['from']:>3}-{st.to:<3} {st.recipe.name:<32} x{st.crafts:<4} {money(st.costPerCraft):>12}/craft{learn}")
    print("  Buy:")
    for b in lua_list(p.shopping):
        est = " (est)" if b.estimate else ""
        print(f"    {b.buy:>5} x {b.name:<26} {b.source:<6} {money(b.unit):>10} = {money(b.total)}{est}")
    print("  Craft yourself:", ", ".join(f"{c.crafts}x {c.name}" for c in lua_list(p.craftYourself)))
    print("  Learn:", ", ".join(f"{l.recipe} ({l.how})" for l in lua_list(p.learn)))
    for n in lua_list(p.notes):
        print("  Note:", n)


def check_plan(ns, p, frm, to):
    assert not p.error, p.error
    steps = lua_list(p.steps)
    assert steps, "no steps"
    assert steps[0]["from"] == frm and steps[-1].to == to, "route does not span range"
    for a, b in zip(steps, steps[1:]):
        assert a.to == b["from"], "gap in route"
    for st in steps:
        r = st.recipe
        assert r.learn <= st["from"], f"{r.name} used before learnable"
        assert st.to <= r.grey, f"{r.name} used while grey"
        assert st.crafts >= st.to - st["from"], "fewer crafts than points"
    assert p.total > 0 and p.total < 10 ** 9


def main():
    lua, ns = load_core()
    R = ns.Recipes

    # Data parses and expands sets.
    eng, bs = R.Load("Engineering"), R.Load("Blacksmithing")
    assert len(eng.list) > 150 and len(bs.list) > 250, (len(eng.list), len(bs.list))
    assert eng.byName["Small Purple Rocket"] and bs.byName["Warder's Sabatons"]
    assert eng.byName["Thorium Widget"].vendor == "Sovik (Orgrimmar)"

    # Skill-up chance follows the Classic rule.
    rbp = eng.byName["Rough Blasting Powder"]  # 1/20/30/40
    assert R.SkillUpChance(rbp, 10, 0) == 1
    assert abs(R.SkillUpChance(rbp, 30, 0) - 0.5) < 1e-9
    assert R.SkillUpChance(rbp, 40, 0) == 0
    assert R.SkillUpChance(rbp, 30, 0.2) == 0.7

    results = {}
    for prof in ("Engineering", "Blacksmithing"):
        p = plan(lua, ns, prof)
        check_plan(ns, p, 1, 300)
        results[prof] = p

    # A mid-way start and a level cap.
    p = plan(lua, ns, "Engineering", 150, 225)
    check_plan(ns, p, 150, 225)
    p = plan(lua, ns, "Blacksmithing", 1, 300, charLevel=30)
    check_plan(ns, p, 1, 225)
    assert any("stops at 225" in n for n in lua_list(p.notes))

    # Excluding recipe items still works for the trainer-only part of the range.
    p = plan(lua, ns, "Engineering", 1, 225, allowRecipeItems=False, allowFavor=False)
    check_plan(ns, p, 1, 225)
    for st in lua_list(p.steps):
        assert st.recipe.source in ("A", "T"), st.recipe.name

    # Missing prices are reported, not crashed on.
    p = plan(lua, ns, "Engineering", 1, 300, prices={"Rough Stone": 10})
    assert p.error and p.reached >= 20

    # Owned items reduce what has to be bought.
    base = plan(lua, ns, "Engineering", 1, 300)
    owned = plan(lua, ns, "Engineering", 1, 300, owned=lambda name: 1000 if name == "Mithril Bar" else 0)
    assert owned.total < base.total

    # Raising Mithril makes the planner move off Mithril recipes where it can.
    pricey = dict(SAMPLE_PRICES, **{"Mithril Bar": 5000})
    p = plan(lua, ns, "Engineering", 1, 300, prices=pricey)
    check_plan(ns, p, 1, 300)
    assert p.expectedGold > base.expectedGold

    # Too few listed: the shopping list flags it.
    p = plan(lua, ns, "Engineering", 1, 300, listed=lambda name: 3 if name == "Copper Bar" else None)
    short = [b for b in lua_list(p.shopping) if b.short]
    assert [b.name for b in short] == ["Copper Bar"] and p.short == 1, [b.name for b in short]

    # Trainer-confirmed learn skill: Copper Tube (data 75) learned at 60 at the trainer.
    eng_tube = R.Load("Engineering").byName["Copper Tube"]
    p = plan(lua, ns, "Engineering", 60, 75, learnOverride=lua.table_from({"Copper Tube": 60}),
             prices={"Copper Bar": 100, "Rough Stone": 10000, "Linen Cloth": 10000})
    assert not p.error, p.error
    assert lua_list(p.steps)[0].recipe.name == "Copper Tube", lua_list(p.steps)[0].recipe.name
    assert eng_tube.learn == 75, "override leaked into the cached data"

    # A trainer list that doesn't include a recipe keeps it out of the route.
    p_all = plan(lua, ns, "Engineering", 1, 300)
    used = {st.recipe.name for st in lua_list(p_all.steps) if st.recipe.source == "T"}
    victim = sorted(used)[0]
    offers = {r.name: r.learn for r in lua_list(R.Load("Engineering").list) if r.source == "T" and r.name != victim}
    p = plan(lua, ns, "Engineering", 1, 300, trainerOffers=lua.table_from(offers))
    assert victim not in {st.recipe.name for st in lua_list(p.steps)}, victim

    # Recipes that give 2 points per craft need half the crafts.
    r2 = lua.table_from({"name": "X", "learn": 1, "yellow": 50, "grey": 100, "points": 2})
    assert R.PointsPerCraft(r2, 10, 0) == 2

    print("All tests passed.")
    if "--show" in sys.argv:
        for prof, p in results.items():
            print()
            show(ns, p)


if __name__ == "__main__":
    main()
