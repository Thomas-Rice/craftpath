#!/usr/bin/env python3
"""Where the profession trainers and the vendors selling crafting materials are.

NPCs, their spawns, what each trainer teaches and what each vendor sells come from WoW
Classic 1.12 (cmangos classic-db, https://github.com/cmangos/classic-db, GPL-3.0); Forever
keeps Classic's world. Zone names, map coordinates and which faction an NPC serves come from
Forever's own client data (wago.tools: UiMapAssignment, UiMap, FactionTemplate, ItemSparse).

Writes data/npc-locations.json and CraftPath/Data/Locations.lua:

  ns.RawData.Trainers[profession] = { { npc, title, zone, x, y, faction, rank }, ... }
      rank: the highest rank they teach (1 Apprentice .. 4 Artisan). faction: "Horde",
      "Alliance" or nil (both).
  ns.RawData.MaterialVendors[item] = { { npc, zone, x, y, faction }, ... }  (a few per faction)

Usage: npc_locations.py --cmangos ClassicDB.sql.gz [--csv-dir DIR | --build VERSION]
"""
import argparse
import gzip
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sync_recipes  # noqa: E402  (fetch, CSV reading, newest build)

ADDON = os.path.join(HERE, "..", "CraftPath")
OUT_JSON = os.path.join(HERE, "..", "data", "npc-locations.json")
OUT_LUA = os.path.join(ADDON, "Data", "Locations.lua")
WAGO_TABLES = ["UiMapAssignment", "UiMap", "FactionTemplate", "ItemSparse"]

# Trainer rank spells are named "<Rank> <Title>" ("Artisan Alchemist").
TITLES = {"Alchemist": "Alchemy", "Blacksmith": "Blacksmithing", "Cook": "Cooking", "Engineer": "Engineering",
          "Leatherworker": "Leatherworking", "Tailor": "Tailoring", "Enchanter": "Enchanting", "Miner": "Mining",
          "Fisherman": "Fishing", "Herbalist": "Herbalism", "Skinner": "Skinning"}
RANKS = ["Apprentice", "Journeyman", "Expert", "Artisan"]
CITIES = {"Orgrimmar", "Undercity", "Thunder Bluff", "Stormwind City", "Ironforge", "Darnassus"}
PER_FACTION = 4  # vendors listed per item and faction


# --- cmangos dump -------------------------------------------------------------------------

def read_sql(path):
    opener = gzip.open if path.endswith(".gz") else open
    with opener(path, "rt", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def columns(src, table):
    m = re.search(r"CREATE TABLE `%s` \((.*?)\) ENGINE" % table, src, re.S)
    return re.findall(r"^\s+`(\w+)`", m.group(1), re.M)


def rows(src, table):
    """Rows of a table's INSERT statements, as dicts (values are strings, NULL is None)."""
    cols = columns(src, table)
    for m in re.finditer(r"INSERT INTO `%s` VALUES (.*?);\n" % table, src, re.S):
        s, i, n = m.group(1), 0, len(m.group(1))
        while i < n:
            if s[i] != "(":
                i += 1
                continue
            i += 1
            row, cur = [], ""
            while True:
                c = s[i]
                if c == "'":
                    i += 1
                    buf = []
                    while True:
                        c = s[i]
                        if c == "\\":
                            buf.append(s[i + 1])
                            i += 2
                            continue
                        if c == "'":
                            if i + 1 < n and s[i + 1] == "'":
                                buf.append("'")
                                i += 2
                                continue
                            i += 1
                            break
                        buf.append(c)
                        i += 1
                    cur = "".join(buf)
                    continue
                if c in ",)":
                    row.append(None if cur == "NULL" else cur)
                    cur = ""
                    i += 1
                    if c == ")":
                        break
                    continue
                cur += c
                i += 1
            yield dict(zip(cols, row))


# --- Forever client data ------------------------------------------------------------------

def to_int(v):
    try:
        return int(float(v))
    except (TypeError, ValueError):
        return 0


def to_float(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


class World:
    """World position -> (zone, x, y) on Forever's maps."""

    def __init__(self, tables):
        self.maps = {to_int(r["ID"]): r for r in tables["UiMap"]}
        self.assign = {}
        for r in tables["UiMapAssignment"]:
            ui = self.maps.get(to_int(r["UiMapID"]))
            if not ui or to_int(ui.get("Type")) not in (3, 5, 6):  # zone, micro, orphan
                continue
            a = {k: to_float(r.get(k)) for k in ("UiMin_0", "UiMin_1", "UiMax_0", "UiMax_1",
                                                  "Region_0", "Region_1", "Region_3", "Region_4")}
            a["name"] = ui.get("Name_lang", "")
            a["type"] = to_int(ui.get("Type"))
            self.assign.setdefault(to_int(r["MapID"]), []).append(a)

    def locate(self, map_id, x, y):
        best = None
        for a in self.assign.get(map_id, []):
            if a["Region_0"] <= x <= a["Region_3"] and a["Region_1"] <= y <= a["Region_4"]:
                area = (a["Region_3"] - a["Region_0"]) * (a["Region_4"] - a["Region_1"])
                if a["type"] == 3 and (best is None or best[0] != 3 or area < best[1]):
                    best = (3, area, a)
                elif best is None:
                    best = (a["type"], area, a)
        if not best:
            return None
        a = best[2]
        # map x runs west -> east (world y falling), map y north -> south (world x falling)
        fx = (a["Region_4"] - y) / max(a["Region_4"] - a["Region_1"], 1e-6)
        fy = (a["Region_3"] - x) / max(a["Region_3"] - a["Region_0"], 1e-6)
        mx = a["UiMin_0"] + fx * (a["UiMax_0"] - a["UiMin_0"])
        my = a["UiMin_1"] + fy * (a["UiMax_1"] - a["UiMin_1"])
        return a["name"], round(mx * 100, 1), round(my * 100, 1)


def faction_of(tables):
    """FactionTemplate id -> "Horde", "Alliance", None (serves both) or False (serves neither)."""
    out = {}
    for r in tables["FactionTemplate"]:
        own, friend, enemy = to_int(r.get("FactionGroup")), to_int(r.get("FriendGroup")), to_int(r.get("EnemyGroup"))
        horde = bool((own | friend) & 4)
        alliance = bool((own | friend) & 2)
        if horde and not alliance:
            out[to_int(r["ID"])] = "Horde"
        elif alliance and not horde:
            out[to_int(r["ID"])] = "Alliance"
        elif horde and alliance or not enemy & 6:
            out[to_int(r["ID"])] = None
        else:
            out[to_int(r["ID"])] = False
    return out


# --- building -----------------------------------------------------------------------------

def materials():
    """Names of the crafting materials vendors sell (VendorItems and VendorGoods in Shared.lua)."""
    from lupa import lua51
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    ns = lua.table()
    with open(os.path.join(ADDON, "Data", "Shared.lua"), encoding="utf-8") as fh:
        lua.execute("return function(src, ns) assert(loadstring(src))('CraftPath', ns) end")(fh.read(), ns)
    names = set()
    for key in ("VendorItems", "VendorGoods"):
        t = ns.RawData[key]
        if t is not None:
            names.update(str(k) for k in t.keys())
    return names


def build(src, tables):
    world = World(tables)
    factions = faction_of(tables)
    spells = {to_int(r["Id"]): r["SpellName"] for r in rows(src, "spell_template")}
    templates = {}
    for r in rows(src, "creature_template"):
        templates[to_int(r["Entry"])] = r
    spawns = {}
    for r in rows(src, "creature"):
        spawns.setdefault(to_int(r["id"]), []).append((to_int(r["map"]), to_float(r["position_x"]), to_float(r["position_y"])))

    def where(entry):
        for m, x, y in spawns.get(entry, []):
            loc = world.locate(m, x, y)
            if loc:
                return loc
        return None

    def npc_faction(t):
        return factions.get(to_int(t.get("Faction")), None)

    # Trainers: what rank spells each NPC (or its template) teaches.
    teach = {}
    for table in ("npc_trainer", "npc_trainer_template"):
        for r in rows(src, table):
            teach.setdefault((table, to_int(r["entry"])), []).append(to_int(r["spell"]))
    trainers = {}
    for entry, t in templates.items():
        taught = teach.get(("npc_trainer", entry), []) + teach.get(("npc_trainer_template", to_int(t.get("TrainerTemplateId"))), [])
        best = {}
        for sp in taught:
            parts = (spells.get(sp) or "").split(" ", 1)
            if len(parts) == 2 and parts[0] in RANKS and parts[1] in TITLES:
                prof = TITLES[parts[1]]
                best[prof] = max(best.get(prof, 0), RANKS.index(parts[0]) + 1)
        if not best:
            continue
        fac = npc_faction(t)
        loc = where(entry)
        if fac is False or not loc:
            continue
        for prof, rank in best.items():
            trainers.setdefault(prof, []).append({"npc": t["Name"], "title": t.get("SubName") or "", "zone": loc[0],
                                                  "x": loc[1], "y": loc[2], "faction": fac, "rank": rank})

    # Vendors of crafting materials (unlimited stock only).
    ids = {}
    for r in tables["ItemSparse"]:
        ids.setdefault(to_int(r["ID"]), r.get("Display_lang", ""))
    wanted = materials()
    sells = {}
    for table in ("npc_vendor", "npc_vendor_template"):
        for r in rows(src, table):
            if to_int(r.get("maxcount")) == 0:
                name = ids.get(to_int(r["item"]))
                if name in wanted:
                    sells.setdefault((table, to_int(r["entry"])), set()).add(name)
    vendors = {}
    for entry, t in templates.items():
        items = sells.get(("npc_vendor", entry), set()) | sells.get(("npc_vendor_template", to_int(t.get("VendorTemplateId"))), set())
        if not items:
            continue
        fac = npc_faction(t)
        loc = where(entry)
        if fac is False or not loc:
            continue
        for item in items:
            vendors.setdefault(item, []).append({"npc": t["Name"], "zone": loc[0], "x": loc[1], "y": loc[2], "faction": fac})

    def order(v):
        return (v["zone"] not in CITIES, v["zone"], v["npc"])

    for prof in trainers:
        trainers[prof].sort(key=lambda v: (-v["rank"],) + order(v))
    for item, vs in vendors.items():
        keep = []
        for fac in ("Horde", "Alliance", None):
            keep += sorted((v for v in vs if v["faction"] == fac), key=order)[:PER_FACTION]
        vendors[item] = sorted(keep, key=order)
    return {"trainers": dict(sorted(trainers.items())), "vendors": dict(sorted(vendors.items()))}


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def entry_lua(v, keys):
    bits = []
    for k in keys:
        val = v.get(k)
        if val is None or val == "":
            continue
        bits.append(f"{k} = {lua_str(val) if isinstance(val, str) else val}")
    return "{ " + ", ".join(bits) + " }"


def write_lua(data, path=OUT_LUA):
    lines = [
        "-- CraftPath: where profession trainers and crafting-material vendors are (WoW: Forever).",
        "-- GENERATED by tools/npc_locations.py from WoW Classic's NPC data (cmangos classic-db) and",
        "-- Forever's maps. Coordinates are map percentages (x, y).",
        "local _, ns = ...",
        "ns.RawData = ns.RawData or {}",
        "ns.RawData.Trainers = {",
    ]
    for prof, vs in data["trainers"].items():
        lines.append(f"  [{lua_str(prof)}] = {{")
        for v in vs:
            lines.append("    " + entry_lua(v, ("npc", "title", "zone", "x", "y", "faction", "rank")) + ",")
        lines.append("  },")
    lines.append("}")
    lines.append("ns.RawData.MaterialVendors = {")
    for item, vs in data["vendors"].items():
        lines.append(f"  [{lua_str(item)}] = {{")
        for v in vs:
            lines.append("    " + entry_lua(v, ("npc", "zone", "x", "y", "faction")) + ",")
        lines.append("  },")
    lines.append("}")
    with open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--cmangos", required=True, help="cmangos classic-db full dump (.sql or .sql.gz)")
    ap.add_argument("--csv-dir", help="folder with the wago.tools CSVs (else they're downloaded)")
    ap.add_argument("--build", help="Forever build (default: newest)")
    args = ap.parse_args(argv)
    tables = {}
    build_id = args.build or (None if args.csv_dir else sync_recipes.newest_build()[0])
    for t in WAGO_TABLES:
        if args.csv_dir:
            with open(os.path.join(args.csv_dir, t + ".csv"), encoding="utf-8-sig") as fh:
                text = fh.read()
        else:
            text = sync_recipes.fetch(sync_recipes.CSV_URL.format(table=t, build=build_id)).decode("utf-8-sig")
        import csv
        import io
        tables[t] = list(csv.DictReader(io.StringIO(text)))
    data = build(read_sql(args.cmangos), tables)
    with open(OUT_JSON, "w", encoding="utf-8", newline="\n") as fh:
        json.dump(data, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    write_lua(data)
    print(f"Trainers: { {p: len(v) for p, v in data['trainers'].items()} }")
    print(f"Material vendors for {len(data['vendors'])} items")


if __name__ == "__main__":
    main()
