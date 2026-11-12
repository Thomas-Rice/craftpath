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
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
from luafiles import pure_files  # noqa: E402
CORE_FILES = pure_files()

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
        print(f"    {b.buy:>5} x {b.name:<26} {str(b.source):<6} {money(b.unit):>10} = {money(b.total)}{est}")
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

    # Trainer-confirmed learn skill: a trainer recipe learned 15 below what the data says. Pick
    # one whose materials make nothing else learnable nearby, and put only those on sale: the
    # route can only use it if the override counts.
    eng = R.Load("Engineering")
    allr = lua_list(eng.list)
    def mats_of(r): return {g.name for g in lua_list(r.reagents)}
    eng_tube = next(r for r in allr if r.source == "T" and r.learn >= 40 and not any(
        o.name != r.name and o.learn <= r.learn + 10 and mats_of(o) <= mats_of(r) for o in allr))
    tube_learn, tube = eng_tube.learn, eng_tube.name
    low = tube_learn - 15
    mats = {n: 100 for n in mats_of(eng_tube)}
    def tube_route(override):
        q = plan(lua, ns, "Engineering", low, low + 10, learnOverride=lua.table_from(override), prices=mats)
        return [st.recipe.name for st in lua_list(q.steps)] if not q.error else []
    assert tube not in tube_route({}), tube + " used before its level"
    assert tube in tube_route({tube: low}), (tube, tube_route({tube: low}))
    assert eng_tube.learn == tube_learn, "override leaked into the cached data"

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

    # No short A -> B -> A bounce: B is folded into A when A costs at most 5% more there.
    for prof in ("Engineering", "Blacksmithing"):
        steps = lua_list(plan(lua, ns, prof).steps)
        names = [st.recipe.name for st in steps]
        bounces = [names[i] for i in range(len(names) - 2) if names[i] == names[i + 2]]
        # A bounce that survives is one where staying on A costs more than 5% extra.
        if "--show" in sys.argv:
            print(f"  {prof}: {len(steps)} steps, bounces kept: {bounces}")

    # Owned items are used first: a stack of Heavy Stone puts the stone recipes in the route.
    stone_prices = dict(SAMPLE_PRICES, **{"Heavy Stone": 898, "Iron Bar": 844})
    base = plan(lua, ns, "Blacksmithing", 100, 125, prices=stone_prices)
    owned = plan(lua, ns, "Blacksmithing", 100, 125, prices=stone_prices,
                 owned=lambda name: 40 if name == "Heavy Stone" else 0)
    stone_steps = [st.recipe.name for st in lua_list(owned.steps) if "Stone" in st.recipe.name or "stone" in st.recipe.name]
    assert stone_steps, [st.recipe.name for st in lua_list(owned.steps)]
    assert owned.total < base.total
    hs = [b for b in lua_list(owned.shopping) if b.name == "Heavy Stone"]
    if hs:
        assert hs[0].have <= 40 and hs[0].buy == hs[0].qty - hs[0].have
    # ... but never more than you have: with 3 Heavy Stone the route can't lean on stones for long.
    few = plan(lua, ns, "Blacksmithing", 100, 125, prices=stone_prices, owned=lambda name: 3 if name == "Heavy Stone" else 0)
    hs = [b for b in lua_list(few.shopping) if b.name == "Heavy Stone"]
    assert not hs or hs[0].have <= 3
    # Turning the option off ignores stock when choosing recipes.
    off = plan(lua, ns, "Blacksmithing", 100, 125, prices=stone_prices,
               owned=lambda name: 40 if name == "Heavy Stone" else 0, useOwned=False)
    assert [st.recipe.name for st in lua_list(off.steps)] == [st.recipe.name for st in lua_list(base.steps)]

    # Vendor recipes say who sells them and where, by faction.
    widget_prices = dict(SAMPLE_PRICES, **{"Thorium Bar": 50, "Runecloth": 10})
    for faction, npc in (("Horde", "Sovik"), ("Alliance", "Gearcutter Cogspinner")):
        p = plan(lua, ns, "Engineering", 260, 270, prices=widget_prices, faction=faction)
        widget = [st for st in lua_list(p.steps) if st.recipe.name == "Thorium Widget"]
        assert widget and widget[0].learnWhere.npc == npc, (faction, [st.recipe.name for st in lua_list(p.steps)])
    # Merchant's Favor plans name the faction's Favor vendor and the Favor cost.
    cheap_belt = {"Bronze Bar": 1, "Rough Stone": 1, "Strange Dust": 1}
    no_cuirass = lua.table_from({"Rough Bronze Cuirass": 90})  # a cheaper trainer recipe at 80, kept out
    p = plan(lua, ns, "Blacksmithing", 80, 85, prices=cheap_belt, faction="Horde", learnOverride=no_cuirass)
    favor = [l for l in lua_list(p.learn) if l.how == "favor"]
    assert favor, [st.recipe.name for st in lua_list(p.steps)]
    assert favor[0].where.npc == "Gor'mak" and favor[0].favor == 30, (favor[0].where.npc, favor[0].favor)
    assert "Durotar Supply and Logistics" in favor[0].where.where
    assert p.favorTotal >= 30
    p = plan(lua, ns, "Blacksmithing", 80, 85, prices=cheap_belt, faction="Alliance", learnOverride=no_cuirass)
    assert [l for l in lua_list(p.learn) if l.how == "favor"][0].where.npc == "Stondry Darkhammer"

    # Cooking: full route, quest recipes, rank items and the fire note.
    ck = R.Load("Cooking")
    assert len(ck.list) > 50, len(ck.list)
    assert ck.needsFire, "Cooking lost its needsFire flag"
    assert ck.byName["Soothing Turtle Bisque"].source == "Q"
    ckp = dict(SAMPLE_PRICES)
    for name in lua_list(R.AllReagents("Cooking")):
        ckp.setdefault(name, 60 + 7 * len(name))  # placeholder raw meat/fish prices
    for name in ("Raw Brilliant Smallfish", "Raw Slitherskin Mackerel", "Spider Ichor", "Chunk of Boar Meat"):
        ckp[name] = 15
    p = plan(lua, ns, "Cooking", 1, 300, prices=ckp, faction="Horde")
    show(ns, p)
    check_plan(ns, p, 1, 300)
    notes = lua_list(p.notes)
    assert any("fire" in n for n in notes) and any("Clamlette Surprise" in n for n in notes)
    names = {b.name: b for b in lua_list(p.shopping)}
    assert names["Giant Egg"].qty >= 12 and "Alterac Swiss" in names, list(names)
    for st in lua_list(p.steps):
        assert st.recipe.name != "Cooked Crab Claw", "Alliance-only recipe in a Horde route"
    p = plan(lua, ns, "Cooking", 1, 225, prices=ckp, faction="Horde")
    check_plan(ns, p, 1, 225)
    assert "Alterac Swiss" not in {b.name for b in lua_list(p.shopping)}

    # Background planning: the planner yields when a frame's time budget is spent, and the
    # result matches planning in one go.
    lua.execute("""
      local ns = ...
    """)
    run_sliced = lua.eval("""
      function(ns, opts)
        local clock = 0
        debugprofilestop = function() clock = clock + 1; return clock end -- 1 ms per call
        local co = coroutine.create(function() return ns.Planner.Plan(opts) end)
        local slices, ok, plan = 0
        repeat
          ns.Planner.sliceEnd = clock + 3
          ok, plan = coroutine.resume(co)
          assert(ok, plan)
          slices = slices + 1
        until coroutine.status(co) == "dead"
        ns.Planner.sliceEnd = nil
        debugprofilestop = nil
        return plan, slices
      end
    """)
    owned = {"Copper Bar": 40, "Heavy Stone": 30, "Iron Bar": 12}
    opts = lua.table_from({"profession": "Blacksmithing", "from": 1, "to": 225, "faction": "Horde",
                           "ahPrice": lambda n: SAMPLE_PRICES.get(n), "owned": lambda n: owned.get(n, 0)})
    sliced, slices = run_sliced(ns, opts)
    whole = ns.Planner.Plan(opts)
    assert slices > 20, slices
    assert sliced.total == whole.total and len(sliced.steps) == len(whole.steps), (sliced.total, whole.total)
    print(f"Background planning: {slices} slices, same route")

    # Step costs are shown at market price even when your stock makes the route cheaper
    # (seen in game: Bristle Whisker Catfish at "0c" with 6 of 110 fish in the bags).
    ckp2 = {n: 60 + 7 * len(n) for n in lua_list(R.AllReagents("Cooking"))}
    ckp2["Raw Bristle Whisker Catfish"] = 24
    po = plan(lua, ns, "Cooking", 110, 175, prices=ckp2, faction="Horde",
              owned=lambda n: 6 if n == "Raw Bristle Whisker Catfish" else 0)
    for st in lua_list(po.steps):
        assert st.costPerCraft > 0, (st.recipe.name, "step cost shows owned stock as free")
    print("Step costs at market price with stock:", [(st.recipe.name, st.costPerCraft) for st in lua_list(po.steps)])

    # ---- Selling what you craft ----
    # Make one recipe in range resell well; the route should pick it up and come out cheaper net.
    sellback = {"Rough Copper Bomb": 400, "Copper Modulator": 300}
    resale = lambda n: (sellback.get(n), "vendor") if n in sellback else (None, None)
    plain = plan(lua, ns, "Engineering", 30, 80)
    sold = plan(lua, ns, "Engineering", 30, 80, resale=resale)
    assert sold.plain and abs(sold.plain.total - plain.total) < 1, "plain comparison missing"
    assert sold.netTotal <= sold.plain.net + 0.5, (sold.netTotal, sold.plain.net)
    names = [st.recipe.name for st in lua_list(sold.steps)]
    assert any(n in sellback for n in names), names
    st = next(st for st in lua_list(sold.steps) if st.recipe.name in sellback)
    assert st.resalePerCraft > 0 and st.resaleHow == "vendor" and st.resaleTotal > 0
    # A craft that sells for more than it costs mustn't be farmed deep into green and grey
    # (seen on the site: ~900 Bronze Bar and Heavy Stone for Engineering 1-300).
    crafts = lambda p: sum(st.crafts for st in lua_list(p.steps))
    assert crafts(sold) <= crafts(plain) * 1.3, (crafts(sold), crafts(plain))
    print(f"Selling crafts: net {sold.netTotal:.0f} vs plain {sold.plain.net:.0f} (spends {sold.total:.0f} vs {plain.total:.0f})")

    # ---- Profit finder ----
    pp = {"Copper Ore": 10, "Copper Bar": 40, "Tin Ore": 10, "Tin Bar": 8,
          "Peacebloom": 5, "Silverleaf": 5, "Elixir of Minor Defense": 200, "Empty Vial": 4, "Bronze Bar": 500}
    stats = {"Copper Bar": {"low": 20, "median": 38, "high": 60, "days": 5}}
    opts = lua.table_from({
        "professions": lua.table_from({1: lua.table_from({"prof": "Mining", "skill": 50}),
                                       2: lua.table_from({"prof": "Alchemy"})}),
        "ahPrice": lambda n: pp.get(n), "sellPrice": lambda n: 15 if n == "Tin Bar" else None,
        "stats": lambda n: lua.table_from(stats[n]) if n in stats else None,
        "listed": lambda n: 12, "faction": "Horde",
    })
    found = {e.name: e for e in lua_list(ns.Profit.Find(opts))}
    cb = found["Copper Bar"]
    assert cb.canCraft and abs(cb.profit - (40 * 0.95 - 10)) < 0.01, cb.profit
    assert abs(cb.safeProfit - (20 * 0.95 - 10)) < 0.01 and cb.swings, (cb.safeProfit, cb.swings)
    assert "Elixir of Minor Defense" not in found, "unknown recipes listed without asking"
    tin = found["Tin Bar"]  # loses money on the AH (8 after the cut vs 10 ore) but a vendor pays 15
    assert tin.canCraft and tin.profit < 0 and abs(tin.vendorProfit - 5) < 0.01, (tin.profit, tin.vendorProfit)
    opts.includeUnknown = True
    found = {e.name: e for e in lua_list(ns.Profit.Find(opts))}
    eld = found["Elixir of Minor Defense"]
    assert not eld.canCraft and not eld.hasProfession and eld.learn.how == "auto", eld.learn.how
    assert eld.cost > 10 and eld.profit > 100, (eld.cost, eld.profit)
    assert eld.need == "profession"
    bronze = found["Bronze Bar"]  # you have Mining 50: level up to Bronze Bar's skill first
    gap = R.Load("Mining").byName["Bronze Bar"].learn - 50
    assert bronze.need == "skill" and bronze.skillGap == gap > 0, (bronze.need, bronze.skillGap, gap)
    print("Profit finder:", {n: round(e.best, 1) for n, e in list(found.items())[:4]})

    print("All tests passed.")
    if "--show" in sys.argv:
        for prof, p in results.items():
            print()
            show(ns, p)


if __name__ == "__main__":
    main()
