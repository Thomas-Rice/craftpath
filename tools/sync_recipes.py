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
BUILDS_URL = "https://wago.tools/api/builds"
CSV_URL = "https://wago.tools/db2/{table}/csv?build={build}"
TABLES = ["SkillLineAbility", "SpellName", "SpellReagents", "SpellEffect", "ItemSparse"]

# Profession -> (SkillLine ID, recipe item prefixes, tools needed)
PROFESSIONS = {
    "Engineering": (202, ["Schematic: ", "Blueprint: "], ["Arclight Spanner"]),
    "Blacksmithing": (164, ["Plans: "], ["Blacksmith Hammer"]),
    "Cooking": (185, ["Recipe: "], []),
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


def build_profession(tables, prof, skill_line, prefixes, existing_sources, exclude):
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
        # Trainer recipes usually say 1 in the client; the real number is on the trainer NPC,
        # so keep the number we already have, or estimate it and say so in the report.
        auto = num(r, "AcquireMethod") in (1, 2)
        estimated = False
        if learn <= 1 and not auto and yellow > 1:
            if kept_learn:
                learn = kept_learn
            else:
                learn = max(1, yellow - 5)
                estimated = True
        if learn >= MAX_SKILL or grey <= learn:
            continue  # can't help reach the cap
        orange = learn
        if yellow <= 0:
            yellow = learn
        green = (max(yellow, learn) + grey) // 2
        if estimated:
            problems.append(f"{name}: client gives no trainer skill; learn skill estimated as {learn} (yellow - 5)")
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


def fmt(r):
    s = "{name}|{learn}|{orange}|{yellow}|{green}|{grey}|{makes}|{source}|{reagents}".format(**r)
    if r.get("points", 1) > 1:
        s += f"|{r['points']}"
    return s


def write_profession(path, prof, recipes, tools, build):
    lines = sorted(recipes.values(), key=lambda r: (r["learn"], r["name"]))
    extra = "\n  needsFire = true," if prof in NEEDS_FIRE else ""
    body = "\n".join(fmt(r) for r in lines)
    header = f"""-- CraftPath recipe data: {prof} (WoW: Forever)
-- GENERATED by tools/sync_recipes.py from Forever client build {build} (via wago.tools).
-- Hand-kept sources (F/V/G/N/Q) are carried over between runs. Edit tools/sync_recipes.py
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

ns.RawData.{prof} = {{
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
    return {"added": added, "removed": removed, "big": big, "minor": minor, "look": look}


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
    args = ap.parse_args(argv)
    addon = args.addon_dir

    if args.csv_dir:
        build, product = args.build or "local", "local"
    elif args.build:
        build, product = args.build, "wowf"
    else:
        build, product = newest_build()
    tables = read_tables(build=None if args.csv_dir else build, csv_dir=args.csv_dir)

    report = [f"# Recipe sync: Forever build {build} ({product})", ""]
    changed_any = False
    summary_rows, look, sections, details = [], [], [], []
    for prof, (skill_line, prefixes, tools) in PROFESSIONS.items():
        path = os.path.join(addon, "Data", f"{prof}.lua")
        before_full = parse_existing_full(path, addon)
        before_sources = parse_existing(path, addon)
        before_lines = parse_lines(path)
        recipes, problems, hidden = build_profession(tables, prof, skill_line, prefixes, before_sources, DEFAULT_EXCLUDE)
        if not recipes:
            sections.append(f"## {prof}\n\nNo recipes found for skill line {skill_line}; left the file alone.\n")
            continue
        write_profession(path, prof, recipes, tools, build)
        print(f"{prof}: {len(recipes)} recipes")
        after = {r["name"]: fmt(r) for r in recipes.values()}
        after_full = {n: dict(zip(FIELDS, l.split("|")[1:9]), points=(l.split("|") + ["1"])[9]) for n, l in after.items()}
        found = summarise(prof, before_full, after_full)
        changed_any |= bool(found["added"] or found["removed"] or found["big"] or found["minor"])
        summary_rows.append(f"| {prof} | {len(before_full)} | {len(after)} | {len(found['added'])} | "
                            f"{len(found['removed'])} | {len(found['big'])} | {len(found['minor'])} |")
        look.extend(found["look"])
        sec = [f"## {prof}"]
        if found["added"]:
            sec.append(f"\n**New ({len(found['added'])})**")
            sec.extend(f"- {n} (skill {after_full[n]['learn']}, {src_text(after_full[n])})" for n in found["added"])
        if found["minor"]:
            sec.append(f"\n{len(found['minor'])} recipes only had their green skill move, which doesn't affect routes.")
        if not (found["added"] or found["removed"] or found["big"] or found["minor"]):
            sec.append("\nNo changes.")
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
    report.insert(1, "Changes found." if changed_any else "No recipe changes.")
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
    with open(args.report, "w", encoding="utf-8") as fh:
        fh.write("\n".join(report) + "\n")
    print("\n".join(report[:3]))
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
            fh.write(f"changed={'true' if changed_any else 'false'}\nbuild={build}\n")


if __name__ == "__main__":
    main()
