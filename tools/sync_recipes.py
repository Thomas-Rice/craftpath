"""Rebuilds CraftPath's recipe data from the WoW: Forever client's own tables.

wago.tools extracts every Forever client build's DB2 tables (product "wowf"). This script
  1. finds the newest Forever build (or uses --build / --csv-dir),
  2. downloads SkillLineAbility, SpellName, SpellReagents, SpellEffect and ItemSparse,
  3. writes CraftPath/Data/<Profession>.lua for each profession below,
  4. writes a Markdown report of what changed (new / changed / removed recipes).

Sources CraftPath can't read from the tables (Merchant's Favor, gold vendors, Goblin/Gnomish
only, hand-picked exclusions) are kept from the existing data files, so hand edits survive.

    python3 tools/sync_recipes.py                      # newest Forever build
    python3 tools/sync_recipes.py --build 1.60.1.70790
    python3 tools/sync_recipes.py --csv-dir some/dir   # offline, CSVs named <Table>.csv
Exit code 0 always on success; the report says whether anything changed.
"""
import argparse
import csv
import io
import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "CraftPath")
CHANGES = os.path.join(HERE, "..", "data", "recipe-changes.json")  # history shown on the website
KEEP_CHANGES = 365
BUILDS_URL = "https://wago.tools/api/builds"
# useHotfixes=1: the tables with Blizzard's hotfixes applied (what the game client actually
# uses). Without it wago returns the data as shipped in the build, which misses hotfixes such
# as the Nov 2026 vendor price cuts and skill-up changes.
TRAINER_LEVELS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "trainer-levels.json")
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}&useHotfixes=1"
TABLES = ["SkillLineAbility", "SpellName", "SpellReagents", "SpellEffect", "ItemSparse"]

# Profession -> (SkillLine ID, recipe item prefixes, tools needed)
PROFESSIONS = {
    "Engineering": (202, ["Schematic: ", "Blueprint: "], ["Arclight Spanner"]),
    "Blacksmithing": (164, ["Plans: "], ["Blacksmith Hammer"]),
    "Cooking": (185, ["Recipe: "], []),
    "Alchemy": (171, ["Recipe: "], []),
    "Tailoring": (197, ["Pattern: "], []),
    "Leatherworking": (165, ["Pattern: "], []),
    "Enchanting": (333, ["Formula: "], []),
    "First Aid": (129, ["Manual: "], []),
    "Mining": (186, [], []),
}
MAX_SKILL = 300
CREATE_ITEM = 24  # SpellEffect.Effect for "create item"
USER_AGENT = "CraftPath recipe sync (+https://github.com/Thomas-Rice/craftpath)"

# Recipes kept out of the data even though the client has them (need a workbench, a hidden
# reagent, or can't be learned by players). Matched by recipe name.
DEFAULT_EXCLUDE = {
    "Clanking Cord", "Gizmo Girdle", "Serrated Strap", "Whimsical Waistwrap",
    "Bent Goggles", "Dented Goggles", "Floppy Goggles", "Stuckbutton Goggles",
}


# The skill each trainer recipe is taught at isn't in the client data. warcraft.wiki.gg's
# Forever recipe tables have it, and matched all 29 Blacksmithing levels read at a trainer
# in game (Nov 2026). Levels recorded in game (data/trainer-levels.json) still come first.
WIKI_API = "https://warcraft.wiki.gg/api.php?action=parse&format=json&prop=wikitext&page="
WIKI_PAGES = {
    "Engineering": "Forever engineering schematics", "Blacksmithing": "Forever blacksmithing plans",
    "Cooking": "Forever cooking recipes", "Alchemy": "Forever alchemy recipes",
    "Tailoring": "Forever tailoring patterns", "Leatherworking": "Forever leatherworking patterns",
    "Enchanting": "Forever enchanting formulas", "First Aid": "Forever first aid recipes",
    "Mining": "Forever mining techniques",
}
WIKI_ROW = re.compile(r"^\|\s*\[\[([^\]|]+)(?:\|([^\]]*))?\]\]\s*\|\|\s*(\d+)\s*\|\|", re.M)


def parse_wiki_levels(wikitext):
    """Recipe name -> skill from a wiki recipe table ("| [[Name]] || 125 || ...")."""
    out = {}
    for m in WIKI_ROW.finditer(wikitext):
        name = (m.group(2) or m.group(1)).strip()
        out.setdefault(name, int(m.group(3)))
    return out


def wiki_levels(profs):
    """{profession: {recipe: skill}} from the wiki; a page that can't be read is left out."""
    import urllib.parse
    out, notes = {}, []
    for prof in profs:
        title = WIKI_PAGES.get(prof)
        if not title:
            continue
        try:
            data = json.loads(fetch(WIKI_API + urllib.parse.quote(title)))
            out[prof] = parse_wiki_levels(data["parse"]["wikitext"]["*"])
        except Exception as e:  # the wiki being down mustn't stop a sync
            notes.append(f"Couldn't read the wiki page '{title}' ({e}); kept the trainer levels we had.")
    return out, notes


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def build_key(version):
    return tuple(int(x) for x in version.split("."))


def newest_build():
    data = json.loads(fetch(BUILDS_URL))
    best = None
    for product, entries in data.items():
        if not product.lower().startswith("wowf"):
            continue
        for e in entries if isinstance(entries, list) else []:
            v = str(e.get("version", ""))
            if re.fullmatch(r"1\.\d+\.\d+\.\d+", v) and (best is None or build_key(v) > build_key(best[0])):
                best = (v, product)
    if not best:
        raise SystemExit("wago.tools lists no Forever (wowf) build")
    return best


def read_tables(build=None, csv_dir=None):
    tables = {}
    for t in TABLES:
        if csv_dir:
            with open(os.path.join(csv_dir, t + ".csv"), encoding="utf-8-sig") as fh:
                text = fh.read()
        else:
            text = fetch(CSV_URL.format(table=t, build=build)).decode("utf-8-sig")
        tables[t] = list(csv.DictReader(io.StringIO(text)))
    return tables


def num(row, key, default=0):
    v = row.get(key)
    if v in (None, ""):
        return default
    try:
        return int(float(v))
    except ValueError:
        return default


def parse_existing(path, addon=ADDON):
    """Existing recipe lines -> {name: (source field, learn skill)}."""
    return {n: (f["source"], int(f["learn"])) for n, f in parse_existing_full(path, addon).items()}


FIELDS = ["learn", "orange", "yellow", "green", "grey", "makes", "source", "reagents"]


def parse_existing_full(path, addon=ADDON):
    """Existing recipe lines (sets expanded) -> {name: {field: text}}."""
    out = {}
    if not os.path.exists(path):
        return out
    text = open(path, encoding="utf-8").read()
    m = re.search(r"recipes = \[\[(.*?)\]\]", text, re.S)
    if not m:
        return out
    sets = {}
    shared = os.path.join(addon, "Data", "Shared.lua")
    if os.path.exists(shared):
        stext = open(shared, encoding="utf-8").read()
        for name, body in re.findall(r"(\w+)\s*=\s*\{((?:\s*\{[^}]*\},?)+)\s*\}", stext):
            sets[name] = [re.findall(r'"([^"]*)"', v) for v in re.findall(r"\{([^}]*)\}", body)]
    for line in m.group(1).splitlines():
        line = line.strip()
        if not line or line.startswith("--"):
            continue
        variants = None
        if line.startswith("@SET "):
            _, set_name, line = line.split(" ", 2)
            variants = sets.get(set_name, [])
        lines = []
        for v in (variants if variants is not None else [None]):
            l = line
            if v:
                l = l.replace("%V", v[0])
                if len(v) > 1:
                    l = l.replace("%G", v[1])
            lines.append(l)
        for l in lines:
            f = l.split("|")
            if len(f) < 9:
                continue
            out[f[0]] = dict(zip(FIELDS, f[1:9]))
            out[f[0]]["points"] = f[9] if len(f) > 9 else "1"
    return out


def build_profession(tables, prof, skill_line, prefixes, existing_sources, exclude, trainer_levels=None,
                     wiki_levels=None, how_learn=None):
    how_learn = how_learn if how_learn is not None else {"game": 0, "wiki": 0, "kept": 0, "guess": 0}
    spell_name = {num(r, "ID"): r.get("Name_lang", "") for r in tables["SpellName"]}
    item_name = {num(r, "ID"): r.get("Display_lang", "") for r in tables["ItemSparse"]}
    item_names = set(item_name.values())
    reagents_by_spell = {}
    for r in tables["SpellReagents"]:
        regs = []
        for i in range(8):
            iid, qty = num(r, f"Reagent_{i}"), num(r, f"ReagentCount_{i}")
            if iid > 0 and qty > 0:
                regs.append((iid, qty))
        reagents_by_spell[num(r, "SpellID")] = regs
    creates = {}
    for r in tables["SpellEffect"]:
        if num(r, "Effect") == CREATE_ITEM and num(r, "EffectItemType") > 0:
            sid = num(r, "SpellID")
            if sid not in creates or num(r, "EffectIndex") < creates[sid][2]:
                count = max(1, int(round(float(r.get("EffectBasePointsF") or 1))))
                creates[sid] = (num(r, "EffectItemType"), count, num(r, "EffectIndex"))

    recipes, problems, hidden = {}, [], []
    for r in tables["SkillLineAbility"]:
        if num(r, "SkillLine") != skill_line:
            continue
        sid = num(r, "Spell")
        learn = num(r, "MinSkillLineRank")
        yellow, grey = num(r, "TrivialSkillLineRankLow"), num(r, "TrivialSkillLineRankHigh")
        if grey <= 1:
            continue  # not a skill-up craft
        made = creates.get(sid)
        name = item_name.get(made[0]) if made else None
        name = name or spell_name.get(sid)
        if not name or name in exclude:
            continue
        regs = reagents_by_spell.get(sid, [])
        if not regs:
            continue
        missing = [iid for iid, _ in regs if not item_name.get(iid)]
        if missing:
            hidden.append(f"{name} (learn {learn}): reagent item(s) {missing} have no name yet")
            continue

        kept, kept_learn = existing_sources.get(name, (None, None))
        # Trainer recipes say 1 in the client; the real number is on the trainer NPC. In order:
        # a level recorded at a trainer in game, the wiki's Forever tables, the number we had,
        # and last the yellow skill (never too low: a guess that's too low has the route ask
        # for a recipe you can't learn yet). Recipes from recipe items, vendors, factions and
        # quests keep their own number.
        auto = num(r, "AcquireMethod") in (1, 2)
        from_item = any(p + name in item_names for p in prefixes) or (kept and kept[0] in "RFVGNQ")
        seen = (trainer_levels or {}).get(name)
        wiki = (wiki_levels or {}).get(name)
        if seen and not auto and not from_item:
            # what the trainer showed in game beats everything, even the client's own number
            learn, how_learn["game"] = seen, how_learn["game"] + 1
        elif learn <= 1 and not auto and yellow > 1:
            if from_item and kept_learn:
                learn = kept_learn
            elif wiki:
                learn, how_learn["wiki"] = wiki, how_learn["wiki"] + 1
                if wiki > yellow:  # taught after it's already yellow: unusual, may be a wiki slip
                    problems.append(f"{name}: the wiki says it's taught at {wiki}, above its yellow skill "
                                    f"({yellow}); a visit to the trainer would confirm")
            elif kept_learn:
                learn, how_learn["kept"] = kept_learn, how_learn["kept"] + 1
            else:
                learn, how_learn["guess"] = yellow, how_learn["guess"] + 1
                problems.append(f"{name}: no trainer level known; assumed {learn} (its yellow skill)")
        if learn >= MAX_SKILL or grey <= learn:
            continue  # can't help reach the cap
        orange = learn
        if yellow <= 0:
            yellow = learn
        green = (max(yellow, learn) + grey) // 2
        if kept and kept[0] in "FVGNQ":
            source = kept
        elif any(p + name in item_names for p in prefixes):
            source = "R"
        elif auto:
            source = "A"
        else:
            source = kept if kept in ("T", "A", "R") else "T"
        line = {
            "name": name, "learn": learn, "orange": orange, "yellow": yellow, "green": green, "grey": grey,
            "makes": made[1] if made else 1, "source": source,
            "reagents": ";".join(f"{item_name[iid]}*{qty}" for iid, qty in regs),
            "points": max(1, num(r, "NumSkillUps", 1)),
        }
        old = recipes.get(name)
        if old is None or line["learn"] < old["learn"]:
            recipes[name] = line
    return recipes, problems, hidden


NEEDS_FIRE = {"Cooking"}


# Trade supplies sold by profession and general goods vendors. Their buy price comes from the
# game data (ItemSparse.BuyPrice), so crafts using them can be costed without a vendor visit.
VENDOR_GOODS = [
    "Empty Vial", "Leaded Vial", "Crystal Vial", "Coarse Thread", "Fine Thread", "Silken Thread",
    "Heavy Silken Thread", "Rune Thread", "Salt", "Bleach", "Red Dye", "Blue Dye", "Green Dye", "Gray Dye",
    "Black Dye", "Pink Dye", "Purple Dye", "Orange Dye", "Yellow Dye", "Weak Flux", "Strong Flux",
    "Flask of Oil", "Blank Parchment", "Copper Rod", "Simple Wood", "Star Wood", "Wooden Stock",
    "Heavy Stock", "Mild Spices", "Hot Spices", "Soothing Spices", "Simple Flour", "Ice Cold Milk",
    "Refreshing Spring Water", "Fishing Bait", "Nightcrawlers", "Thick Logs", "Holy Water",
    "Spool of Light Chartreuse Silk Thread", "Enchanted Vial",
]


def read_item_prices(addon):
    """The ItemSell and VendorGoods tables in the current Data/Items.lua, as two dicts."""
    path = os.path.join(addon, "Data", "Items.lua")
    out = {"ItemSell": {}, "VendorGoods": {}}
    if not os.path.exists(path):
        return out
    table = None
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"ns\.RawData\.(\w+) = \{", line)
            if m:
                table = m.group(1)
                continue
            m = re.match(r'\s*\["(.*)"\] = (\d+),', line)
            if m and table in out:
                out[table][m.group(1).replace('\\"', '"').replace("\\\\", "\\")] = int(m.group(2))
    return out


def money(c):
    g, s, cp = c // 10000, c // 100 % 100, c % 100
    parts = [f"{g}g" if g else "", f"{s}s" if s else "", f"{cp}c" if cp or c == 0 else ""]
    return " ".join(p for p in parts if p)


def price_changes(before, sell, goods):
    """Items whose vendor price changed (items new to or gone from the list aren't changes)."""
    out = []
    for n in sorted(sell):
        old = before["ItemSell"].get(n)
        if old is not None and old != sell[n]:
            out.append({"name": n, "change": f"vendors pay {money(sell[n])} (was {money(old)})"})
    for n in sorted(goods):
        old = before["VendorGoods"].get(n)
        if old is not None and old != goods[n]:
            out.append({"name": n, "change": f"vendors charge {money(goods[n])} (was {money(old)})"})
    return out


def write_items(addon, tables, names, build):
    """Data/Items.lua: vendor sell prices for every recipe item and material, and buy prices of
    VENDOR_GOODS. Skipped (with a note) if the game data has no price columns.
    Returns (message, list of price changes)."""
    rows = tables["ItemSparse"]
    if not rows or "SellPrice" not in rows[0]:
        return "ItemSparse has no SellPrice column; Items.lua left alone.", []
    before = read_item_prices(addon)
    by_name = {}
    for r in sorted(rows, key=lambda r: num(r, "ID")):
        n = r.get("Display_lang", "")
        if n and n not in by_name:
            by_name[n] = (num(r, "BuyPrice"), num(r, "SellPrice"))
    sell = {n: by_name[n][1] for n in sorted(names) if n in by_name and by_name[n][1] > 0}
    goods = {n: by_name[n][0] for n in VENDOR_GOODS if n in by_name and by_name[n][0] > 0}
    esc = lambda n: n.replace("\\", "\\\\").replace('"', '\\"')
    lines = [
        "-- CraftPath item prices: what vendors pay (ItemSell) and charge for trade supplies (VendorGoods).",
        f"-- GENERATED by tools/sync_recipes.py from Forever client build {build} (via wago.tools).",
        "local _, ns = ...", "ns.RawData = ns.RawData or {}", "ns.RawData.ItemSell = {",
    ]
    lines += [f'  ["{esc(n)}"] = {v},' for n, v in sell.items()]
    lines += ["}", "ns.RawData.VendorGoods = {"]
    lines += [f'  ["{esc(n)}"] = {v},' for n, v in goods.items()]
    lines += ["}", ""]
    with open(os.path.join(addon, "Data", "Items.lua"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines))
    return f"Items.lua: {len(sell)} sell prices, {len(goods)} vendor supplies.", price_changes(before, sell, goods)


def fmt(r):
    s = "{name}|{learn}|{orange}|{yellow}|{green}|{grey}|{makes}|{source}|{reagents}".format(**r)
    if r.get("points", 1) != 1:
        s += f"|{r['points']}"
    return s


def write_profession(path, prof, recipes, tools, build):
    lines = sorted(recipes.values(), key=lambda r: (r["learn"], r["name"]))
    extra = "\n  needsFire = true," if prof in NEEDS_FIRE else ""
    body = "\n".join(fmt(r) for r in lines)
    header = f"""-- CraftPath recipe data: {prof} (WoW: Forever)
-- GENERATED by tools/sync_recipes.py from Forever client build {build} (via wago.tools).
-- Hand-kept sources (F/V/G/N/Q) and "|0" skill-ups (recipes that no longer give skill) are carried over between runs. Edit tools/sync_recipes.py
-- (or the source letter on a line) rather than re-ordering this file by hand.
--
-- Line format:
--   Name|learn|orange|yellow|green|grey|makes|source|Reagent*qty;Reagent*qty[|skill-ups per craft]
-- Sources:
--   A = learned automatically     T = trainer
--   R = recipe item (drop/AH)     F = Merchant's Favor vendor (no gold)
--   V:Vendor name = gold vendor   G = Goblin Engineering only   N = Gnomish Engineering only
--   Q:Quest name = quest reward

local _, ns = ...
ns.RawData = ns.RawData or {{}}

ns.RawData["{prof}"] = {{
  build = "{build}",
  tools = {{ {", ".join('"%s"' % t for t in tools)} }},{extra}
  recipes = [[
{body}
]],
}}
"""
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(header)


SPEC_WORDS = ("Gnomish", "Goblin")
LABEL = {"learn": "learn", "orange": "orange", "yellow": "yellow", "grey": "grey", "makes": "makes",
         "source": "source", "reagents": "materials", "points": "skill-ups"}


def summarise(prof, before, after):
    """Plain-English findings for one profession. before/after: {name: {field: text}}."""
    added = sorted(set(after) - set(before), key=lambda n: (int(after[n]["learn"]), n))
    removed = sorted(set(before) - set(after), key=lambda n: (int(before[n]["learn"]), n))
    big, minor = [], []
    for n in sorted(set(before) & set(after), key=lambda n: (int(after[n]["learn"]), n)):
        diffs = [k for k in LABEL if str(before[n].get(k, "1")) != str(after[n].get(k, "1"))]
        if diffs:
            big.append((n, diffs))
        elif before[n]["green"] != after[n]["green"]:
            minor.append(n)
    look = []
    for n in removed:
        look.append(f"**{n}** (skill {before[n]['learn']}) is no longer in the game data. Routes will go around it.")
    for n, diffs in big:
        parts = []
        for k in diffs:
            if k == "reagents":
                parts.append(f"materials now {after[n]['reagents'].replace(';', ', ').replace('*', ' x')}")
            else:
                parts.append(f"{LABEL[k]} {before[n].get(k, '1')} → {after[n].get(k, '1')}")
        look.append(f"**{n}**: " + "; ".join(parts))
    if prof == "Engineering":
        for n in added:
            if any(w in n for w in SPEC_WORDS) and after[n]["source"] not in ("G", "N"):
                look.append(f"**{n}** may need Goblin or Gnomish Engineering; it came in as an ordinary recipe.")
    def change_text(n, diffs):
        return "; ".join(
            f"materials now {after[n]['reagents'].replace(';', ', ').replace('*', ' x')}" if k == "reagents"
            else f"{LABEL[k]} {before[n].get(k, '1')} → {after[n].get(k, '1')}" for k in diffs)
    entry = {
        "profession": prof, "before": len(before), "after": len(after), "minor": len(minor),
        "added": [{"name": n, "skill": int(after[n]["learn"]), "source": src_text(after[n]),
                   "materials": after[n]["reagents"].replace(";", ", ").replace("*", " x")} for n in added],
        "removed": [{"name": n, "skill": int(before[n]["learn"])} for n in removed],
        "changed": [{"name": n, "change": change_text(n, d)} for n, d in big],
    }
    return {"added": added, "removed": removed, "big": big, "minor": minor, "look": look, "entry": entry}


def add_changes_entry(path, build, entries, date=None):
    """Prepends one run's summary to the website's change history (newest first)."""
    import datetime
    history = []
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            history = json.load(fh)
    # One entry per build: a later run for the same build adds to it (per profession) rather
    # than replacing what an earlier run recorded.
    same = next((h for h in history if h.get("build") == build), None)
    if same:
        history.remove(same)
        merged = {e["profession"]: e for e in same.get("professions", [])}
        for e in entries:
            old = merged.get(e["profession"])
            if old:
                names = {a["name"] for a in old["added"]}
                old["added"] += [a for a in e["added"] if a["name"] not in names]
                old["removed"] += e["removed"]
                old["changed"] += e["changed"]
                old["after"] = e["after"]
            else:
                merged[e["profession"]] = e
        entries = list(merged.values())
    history.insert(0, {"date": date or datetime.date.today().isoformat(), "build": build, "professions": entries})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(history[:KEEP_CHANGES], fh, indent=1, ensure_ascii=False)
        fh.write("\n")


def src_text(f):
    src = f["source"]
    return {"A": "automatic", "T": "trainer", "R": "recipe item", "F": "Favor", "G": "Goblin", "N": "Gnomish"}.get(
        src, "vendor " + src[2:] if src.startswith("V:") else "quest " + src[2:] if src.startswith("Q:") else src)


def parse_lines(path):
    """name -> line (without @SET expansion handled by parse_existing for sources)."""
    out = {}
    if not os.path.exists(path):
        return out
    m = re.search(r"recipes = \[\[(.*?)\]\]", open(path, encoding="utf-8").read(), re.S)
    for line in (m.group(1) if m else "").splitlines():
        line = line.strip()
        if line and not line.startswith(("--", "@SET")):
            out[line.split("|")[0]] = line
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--build")
    ap.add_argument("--csv-dir")
    ap.add_argument("--report", default=os.path.join(HERE, "..", "recipe-sync-report.md"))
    ap.add_argument("--addon-dir", default=ADDON, help="CraftPath folder to update (default: this repo's)")
    ap.add_argument("--changes", default=CHANGES, help="website change-history JSON to add this run to")
    ap.add_argument("--wiki-levels", help="JSON {profession: {recipe: skill}} to use instead of reading the wiki "
                    "(tests); with --csv-dir and without this, the wiki isn't read")
    ap.add_argument("--trainer-levels", default=TRAINER_LEVELS,
                    help="skill each trainer recipe is taught at, recorded in game (export_prices.py writes it)")
    args = ap.parse_args(argv)
    trainer_levels = {}
    if args.trainer_levels and os.path.exists(args.trainer_levels):
        with open(args.trainer_levels, encoding="utf-8") as fh:
            trainer_levels = json.load(fh)
    addon = args.addon_dir

    if args.csv_dir:
        build, product = args.build or "local", "local"
    elif args.build:
        build, product = args.build, "wowf"
    else:
        build, product = newest_build()
    tables = read_tables(build=None if args.csv_dir else build, csv_dir=args.csv_dir)
    wiki, wiki_notes = {}, []
    if args.wiki_levels:
        with open(args.wiki_levels, encoding="utf-8") as fh:
            wiki = json.load(fh)
    elif not args.csv_dir:
        wiki, wiki_notes = wiki_levels(PROFESSIONS)

    report = [f"# Recipe sync: Forever build {build} ({product})", ""]
    changed_any = False
    summary_rows, look, sections, details, entries = [], [], [], [], []
    item_names = set()
    for prof, (skill_line, prefixes, tools) in PROFESSIONS.items():
        path = os.path.join(addon, "Data", f"{prof.replace(' ', '')}.lua")
        before_full = parse_existing_full(path, addon)
        before_sources = parse_existing(path, addon)
        before_lines = parse_lines(path)
        how_learn = {"game": 0, "wiki": 0, "kept": 0, "guess": 0}
        recipes, problems, hidden = build_profession(tables, prof, skill_line, prefixes, before_sources, DEFAULT_EXCLUDE,
                                                     trainer_levels.get(prof), wiki.get(prof), how_learn)
        # Hand-set "gives no skill-ups" (points 0) wins over the game data, which can still list
        # skill-ups for a recipe that no longer gives them in game (e.g. Basic Campfire).
        for n, f in before_full.items():
            if f.get("points") == "0" and n in recipes:
                recipes[n]["points"] = 0
        if not recipes:
            sections.append(f"## {prof}\n\nNo recipes found for skill line {skill_line}; left the file alone.\n")
            continue
        write_profession(path, prof, recipes, tools, build)
        print(f"{prof}: {len(recipes)} recipes")
        for r in recipes.values():
            item_names.add(r["name"])
            item_names.update(part.split("*")[0] for part in r["reagents"].split(";"))
        after = {r["name"]: fmt(r) for r in recipes.values()}
        after_full = {n: dict(zip(FIELDS, l.split("|")[1:9]), points=(l.split("|") + ["1"])[9]) for n, l in after.items()}
        found = summarise(prof, before_full, after_full)
        changed_any |= bool(found["added"] or found["removed"] or found["big"] or found["minor"])
        summary_rows.append(f"| {prof} | {len(before_full)} | {len(after)} | {len(found['added'])} | "
                            f"{len(found['removed'])} | {len(found['big'])} | {len(found['minor'])} |")
        look.extend(found["look"])
        if found["added"] or found["removed"] or found["big"]:
            entries.append(found["entry"])
        sec = [f"## {prof}"]
        if found["added"]:
            sec.append(f"\n**New ({len(found['added'])})**")
            sec.extend(f"- {n} (skill {after_full[n]['learn']}, {src_text(after_full[n])})" for n in found["added"])
        if found["minor"]:
            sec.append(f"\n{len(found['minor'])} recipes only had their green skill move, which doesn't affect routes.")
        if not (found["added"] or found["removed"] or found["big"] or found["minor"]):
            sec.append("\nNo changes.")
        sec.append(f"\nTrainer levels: {how_learn['game']} recorded in game, {how_learn['wiki']} from the wiki, "
                   f"{how_learn['kept']} kept from before, {how_learn['guess']} assumed.")
        if hidden:
            sec.append(f"\n### Hidden in the client ({len(hidden)})")
            sec.append("Recipes the client ships with names or reagents still hidden. They join the data "
                       "automatically once a build reveals them.")
            sec.extend("- " + h for h in hidden[:100])
        if problems:
            sec.append("\n### Notes")
            sec.extend("- " + p for p in problems[:50])
        detail_lines = [f"{n}\n    {before_lines.get(n, '(in a set)')}\n -> {after[n]}" for n, _ in found["big"]]
        detail_lines += [f"+ {after[n]}" for n in found["added"]] + [f"- {n}" for n in found["removed"]]
        if detail_lines:
            details.append(f"<details><summary>{prof} raw lines</summary>\n\n```\n" + "\n".join(detail_lines) + "\n```\n</details>")
        sections.append("\n".join(sec) + "\n")
    msg, prices = write_items(addon, tables, item_names, build)
    print(msg)
    if prices:
        changed_any = True
        entries.append({"profession": "Vendor prices", "kind": "items", "before": len(prices), "after": len(prices),
                        "minor": 0, "added": [], "removed": [], "changed": prices})
        sections.append(f"## Vendor prices\n\n{len(prices)} items changed price:\n"
                        + "\n".join(f"- {c['name']}: {c['change']}" for c in prices[:200]) + "\n")
    report.insert(1, "Changes found." if changed_any else "No recipe changes.")
    if wiki_notes:
        look.extend(wiki_notes)
    report.append("| Profession | Before | After | New | Removed | Changed | Minor |")
    report.append("|---|---|---|---|---|---|---|")
    report.extend(summary_rows)
    report.append("\n*Changed* = something the planner uses (learn, orange, yellow or grey skill, materials, source). "
                  "*Minor* = only the green skill moved.\n")
    if look:
        report.append("## Worth a look before merging")
        report.extend("- " + l for l in look)
        report.append("")
    report.extend(sections)
    report.extend(["", *details])
    if entries:  # green-only runs don't make the website history
        add_changes_entry(args.changes, build, entries)
    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(report) + "\n")
    print("\n".join(report[:3]))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"changed={'true' if changed_any else 'false'}\nbuild={build}\n")


if __name__ == "__main__":
    main()
