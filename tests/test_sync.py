"""Tests tools/sync_recipes.py offline: turns the current recipe data into wago.tools-style
CSVs (real column names), regenerates the data from them, and checks the result matches,
that hand-kept sources survive, and that new and changed recipes show up in the report.
"""
import csv
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "tools"))
from run_tests import load_core, lua_list  # noqa: E402
import sync_recipes  # noqa: E402

SKILL_LINES = {"Engineering": 202, "Blacksmithing": 164}


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(header)
        w.writerows(rows)


def make_csvs(ns, out, extra=None, change=None, hidden_reagent=None):
    items, item_rows = {}, []

    def item(name):
        if name not in items:
            items[name] = 100000 + len(items)
            item_rows.append([items[name], name])
        return items[name]

    sla, names, reagents, effects = [], [], [], []
    spell = 50000
    for prof, line in SKILL_LINES.items():
        data = ns.Recipes.Load(prof)
        recipes = [dict(r.items()) for r in lua_list(data.list)]
        recipes = [dict(r, reagents=[(g.name, g.qty) for g in lua_list(r["reagents"])]) for r in recipes]
        if extra and prof in extra:
            recipes.append(extra[prof])
        for r in recipes:
            r = dict(r)
            if change and r["name"] in change:
                r.update(change[r["name"]])
            spell += 1
            acquire = 1 if r["source"] == "A" else 0
            client_learn = r["learn"] if acquire else 1  # the client lists trainer recipes at 1
            sla.append([len(sla) + 1, line, spell, client_learn, acquire, r["grey"], r["yellow"], r.get("points", 1)])
            names.append([spell, r["name"]])
            regs = r["reagents"]
            row = [len(reagents) + 1, spell] + [item(n) for n, _ in regs] + [0] * (8 - len(regs)) \
                  + [q for _, q in regs] + [0] * (8 - len(regs))
            reagents.append(row)
            effects.append([len(effects) + 1, spell, 0, sync_recipes.CREATE_ITEM, item(r["name"]), float(r["makes"])])
            if r["source"] in ("R", "V"):
                item(sync_recipes.PROFESSIONS[prof][1][0] + r["name"])
    write_csv(os.path.join(out, "SkillLineAbility.csv"),
              ["ID", "SkillLine", "Spell", "MinSkillLineRank", "AcquireMethod", "TrivialSkillLineRankHigh",
               "TrivialSkillLineRankLow", "NumSkillUps"], sla)
    write_csv(os.path.join(out, "SpellName.csv"), ["ID", "Name_lang"], names)
    write_csv(os.path.join(out, "SpellReagents.csv"),
              ["ID", "SpellID"] + [f"Reagent_{i}" for i in range(8)] + [f"ReagentCount_{i}" for i in range(8)], reagents)
    write_csv(os.path.join(out, "SpellEffect.csv"),
              ["ID", "SpellID", "EffectIndex", "Effect", "EffectItemType", "EffectBasePointsF"], effects)
    if hidden_reagent:  # the client ships this item with no name yet
        item_rows = [[i, "" if n == hidden_reagent else n] for i, n in item_rows]
    item_rows = [[i, n, 40 if n == "Empty Vial" else 0, 7 if n == "Copper Bar" else 0] for i, n in item_rows]
    write_csv(os.path.join(out, "ItemSparse.csv"), ["ID", "Display_lang", "BuyPrice", "SellPrice"], item_rows)


def snapshot(ns, prof):
    out = {}
    for r in lua_list(ns.Recipes.Load(prof).list):
        out[r.name] = (r.learn, r.yellow, r.grey, r.makes, r.source, r.vendor,
                       tuple((g.name, g.qty) for g in lua_list(r.reagents)), r.points)
    return out


def main():
    lua, ns = load_core()
    before = {p: snapshot(ns, p) for p in SKILL_LINES}
    tmp = tempfile.mkdtemp()
    try:
        addon = os.path.join(tmp, "CraftPath")
        shutil.copytree(os.path.join(HERE, "..", "CraftPath"), addon)
        # A recipe marked by hand as giving no skill-ups keeps that, though the game data says 1.
        eng = os.path.join(addon, "Data", "Engineering.lua")
        text = open(eng, encoding="utf-8").read()
        line = next(l for l in text.splitlines() if l.startswith("Rough Blasting Powder|"))
        open(eng, "w", encoding="utf-8").write(text.replace(line, line + "|0"))
        csvs = os.path.join(tmp, "csv")
        os.makedirs(csvs)
        new = {"name": "Thorium Shield Wall", "learn": 285, "yellow": 290, "grey": 320, "makes": 1, "source": "T",
               "reagents": [("Thorium Bar", 20), ("Dense Grinding Stone", 2)], "points": 2}
        secret = {"name": "Mysterious Gadget", "learn": 150, "yellow": 160, "grey": 180, "makes": 1, "source": "A",
                  "reagents": [("Iron Bar", 2), ("Glimmering Hidden Cog", 1)]}
        make_csvs(ns, csvs, extra={"Blacksmithing": new, "Engineering": secret}, change={"Copper Tube": {"grey": 112}},
                  hidden_reagent="Glimmering Hidden Cog")
        report = os.path.join(tmp, "report.md")
        changes = os.path.join(tmp, "changes.json")
        sync_recipes.main(["--csv-dir", csvs, "--build", "1.60.1.99999", "--report", report, "--addon-dir", addon,
                           "--changes", changes])
        items = open(os.path.join(addon, "Data", "Items.lua"), encoding="utf-8").read()
        assert '["Copper Bar"] = 7,' in items, items[:400]
        synced = open(eng, encoding="utf-8").read()
        assert any(l.startswith("Rough Blasting Powder|") and l.endswith("|0") for l in synced.splitlines()), \
            "hand-set 0 skill-ups was lost"
        import json
        hist = json.load(open(changes, encoding="utf-8"))
        assert len(hist) == 1 and hist[0]["build"] == "1.60.1.99999", hist
        bsh = {e["profession"]: e for e in hist[0]["professions"]}
        assert bsh["Blacksmithing"]["added"][0]["name"] == "Thorium Shield Wall"
        assert any(c["name"] == "Copper Tube" for c in bsh["Engineering"]["changed"])

        # Load the regenerated data with the same core code.
        sys_path = sys.modules["run_tests"]
        old_root = sys_path.ROOT
        sys_path.ROOT = addon
        try:
            lua2, ns2 = load_core()
        finally:
            sys_path.ROOT = old_root
        after = {p: snapshot(ns2, p) for p in SKILL_LINES}

        for prof in SKILL_LINES:
            for name, b in before[prof].items():
                a = after[prof].get(name)
                if b[4] == "T" and b[1] >= 300:
                    continue  # learned at 300: no skill-ups left, so not in a route
                assert a, f"{prof}: {name} lost"
                if b[4] == "T":  # trainer recipes are learned where they turn yellow
                    assert a[0] == b[1] and a[1:] == b[1:] or name == "Copper Tube", (name, a, b)
                    if name == "Copper Tube":
                        assert a[0] == a[1] and a[2] == 112, a  # grey from the client
                    continue
                if name == "Copper Tube":
                    assert a[2] == 112, a
                    continue
                if name == "Rough Blasting Powder":
                    assert a[:-1] == b[:-1] and a[-1] == 0, a  # hand-set "no skill-ups" kept
                    continue
                assert a == b, f"{prof}: {name}\n before {b}\n after  {a}"
        wall = after["Blacksmithing"]["Thorium Shield Wall"]
        assert wall[0] == 290 and wall[7] == 2, wall  # new trainer recipe: learned at its yellow skill
        assert after["Engineering"]["Thorium Widget"][5] == "Sovik (Orgrimmar)"  # hand-kept vendor
        assert after["Engineering"]["SAF-T Dynamite"][4] == "F"                 # hand-kept Favor

        text = open(report, encoding="utf-8").read()
        if os.environ.get("SHOW_REPORT"):
            print(text)
        assert "Worth a look" in text and "**Copper Tube**: learn 75 → 80; orange 75 → 80; grey 110 → 112" in text, text[:1500]
        assert "Changes found." in text
        assert "Thorium Shield Wall" in text and "Copper Tube" in text
        assert "Hidden in the client (1)" in text and "Mysterious Gadget" in text
        assert "Mysterious Gadget" not in after["Engineering"]
        assert "build = \"1.60.1.99999\"" in open(os.path.join(addon, "Data", "Engineering.lua")).read()

        # A second run with the same tables reports no changes.
        sync_recipes.main(["--csv-dir", csvs, "--build", "1.60.1.99999", "--report", report, "--addon-dir", addon,
                           "--changes", changes])
        assert len(json.load(open(changes, encoding="utf-8"))) == 1  # no new entry without changes
        assert "No recipe changes." in open(report, encoding="utf-8").read()

        # A hotfix that changes what vendors pay is reported and recorded on the updates page.
        path = os.path.join(csvs, "ItemSparse.csv")
        rows = open(path, encoding="utf-8").read().replace(",Copper Bar,0,7", ",Copper Bar,0,5")
        open(path, "w", encoding="utf-8").write(rows)
        sync_recipes.main(["--csv-dir", csvs, "--build", "1.60.1.99999", "--report", report, "--addon-dir", addon,
                           "--changes", changes])
        text = open(report, encoding="utf-8").read()
        assert "Changes found." in text and "Copper Bar: vendors pay 5c (was 7c)" in text, text[:800]
        hist = json.load(open(changes, encoding="utf-8"))
        vend = [p for p in hist[0]["professions"] if p["profession"] == "Vendor prices"]
        assert vend and vend[0]["changed"][0]["name"] == "Copper Bar", hist[0]
        assert '["Copper Bar"] = 5,' in open(os.path.join(addon, "Data", "Items.lua"), encoding="utf-8").read()
        # A level recorded at a trainer in game wins over the yellow-skill guess.
        tl = os.path.join(tmp, "trainer-levels.json")
        json.dump({"Blacksmithing": {"Thorium Shield Wall": 285}}, open(tl, "w"))
        sync_recipes.main(["--csv-dir", csvs, "--build", "1.60.1.99999", "--report", report, "--addon-dir", addon,
                           "--changes", changes, "--trainer-levels", tl])
        bs = open(os.path.join(addon, "Data", "Blacksmithing.lua"), encoding="utf-8").read()
        assert "\nThorium Shield Wall|285|285|290|" in bs, [l for l in bs.splitlines() if "Shield Wall" in l]
        print("Sync test passed:", {p: len(after[p]) for p in after})
    finally:
        shutil.rmtree(tmp)


if __name__ == "__main__":
    main()
