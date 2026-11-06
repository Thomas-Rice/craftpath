-- CraftPath shared data: variant sets, vendor-sold reagents and profession facts.

local _, ns = ...
ns.RawData = ns.RawData or {}

-- "@SET NAME" lines in the recipe files expand once per variant here.
-- Each entry is { variant name, gem/extra reagent (or false) }.
ns.RawData.Sets = {
  ROCKET   = { {"Blue"}, {"Green"}, {"Purple"}, {"Red"}, {"White"}, {"Yellow"} },
  FIREWORK = { {"Blue"}, {"Green"} }, -- Red Firework is sold by Sovik (own line)
  ORDER    = { {"Acolyte's", "Strange Dust"}, {"Crusader's", "Lesser Magic Essence"},
               {"Guard's", "Shadowgem"}, {"Protector's", "Tigerseye"},
               {"Veteran's", "Small Lustrous Pearl"} },
  SKY      = { {"Azure"}, {"Cloudy"} },
  SKYGEM   = { {"Azure", "Aquamarine"}, {"Cloudy", "Small Lustrous Pearl"} },
  WATCH    = { {"Justicar's", "Globe of Water"}, {"Officer's", "Jade"},
               {"Prefect's", "Golden Pearl"}, {"Sentinel's", "Purple Lotus"},
               {"Warder's", "Black Pearl"} },
}

-- Reagents sold by NPC vendors, with a starting price estimate in copper.
-- Most were seen at Forever vendors (Nov 2026); the addon replaces any of them with the
-- price it sees the next time you open a merchant that sells it.
ns.RawData.VendorItems = {
  ["Weak Flux"] = 100,              -- seen at a Forever vendor
  ["Strong Flux"] = 2000,           -- seen at a Forever vendor
  ["Coarse Thread"] = 10,           -- seen at a Forever vendor
  ["Fine Thread"] = 100,            -- seen at a Forever vendor
  ["Green Dye"] = 100,              -- seen at a Forever vendor
  ["Nightcrawlers"] = 100,          -- seen at a Forever vendor
  ["Refreshing Spring Water"] = 5,  -- seen at a Forever vendor
  ["Razor Arrow"] = 2,              -- seen at a Forever vendor
  ["Wooden Stock"] = 200,           -- seen at a Forever vendor
  ["Heavy Stock"] = 2000,           -- seen at a Forever vendor
  ["Blacksmith Hammer"] = 18,       -- seen at a Forever vendor
  ["Elemental Flux"] = 150000,      -- seen at a Forever vendor
  -- Cooking supplies (seen at Forever vendors)
  ["Mild Spices"] = 2, ["Hot Spices"] = 40, ["Soothing Spices"] = 160,
  ["Simple Flour"] = 200, ["Ice Cold Milk"] = 25, ["Shiny Red Apple"] = 5,
  ["Melon Juice"] = 100, ["Moonberry Juice"] = 400, ["Sweet Nectar"] = 200, ["Morning Glory Dew"] = 800,
  ["Simple Wood"] = 38, ["Star Wood"] = 4500, ["Thick Logs"] = 200000, ["Flint and Tinder"] = 135,
  ["Expert Cookbook"] = 10000,      -- estimate
  ["Alterac Swiss"] = 1600,         -- estimate, cheese vendors
  ["Blank Parchment"] = 125,        -- estimate
  ["Engineer's Ink"] = 400,         -- estimate
  ["Flask of Oil"] = 80,            -- estimate
}

-- Vendor prices above that are still guesses (shown as "est.").
ns.RawData.VendorEstimates = { ["Blank Parchment"] = true, ["Engineer's Ink"] = true, ["Flask of Oil"] = true,
  ["Expert Cookbook"] = true, ["Alterac Swiss"] = true }

-- Price guess (copper) for gold-vendor recipes until the merchant has been seen.
ns.RawData.VendorRecipeEstimate = 5000
ns.RawData.VendorRecipeEstimateBy = { Cooking = 400 }

-- Rank caps and the character level each trainer rank needs (Forever follows Classic).
ns.RawData.Ranks = {
  { name = "Apprentice", cap = 75,  trainAt = 1,   level = 1 },
  { name = "Journeyman", cap = 150, trainAt = 50,  level = 10 },
  { name = "Expert",     cap = 225, trainAt = 125, level = 20 },
  { name = "Artisan",    cap = 300, trainAt = 200, level = 35 },
}

-- Where to get recipes that come from a particular NPC (checked against wow-professions.com,
-- lfcarry.com and method.gg's Forever guides, Nov 2026). price = copper, when known.
-- Vendors you visit in game are also recorded with their location (see Core/Game.lua).
local SOVIK = { npc = "Sovik", where = "Orgrimmar, Valley of Honor", faction = "Horde",
  alt = { npc = "Gearcutter Cogspinner", where = "Ironforge", faction = "Alliance" } }
local MAGNUS = { npc = "Magnus Frostwake", where = "Western Plaguelands, a house in Caer Darrow (68, 77)",
  note = "He only appears while you wear the Spectral Essence (Scholomance quest chain). The plans are bind on pickup." }
local function with(base, extra)
  local t = {}
  for k, v in pairs(base) do t[k] = v end
  for k, v in pairs(extra or {}) do t[k] = v end
  return t
end
ns.RawData.RecipeVendors = {
  Engineering = {
    ["Thorium Widget"] = with(SOVIK, { price = 12000 }),
    ["Thorium Grenade"] = with(SOVIK, { price = 12000 }),
    ["Red Firework"] = with(SOVIK, { price = 1800 }),
    ["Thorium Tube"] = { npc = "Xizzer Fizzbolt", where = "Winterspring" },
  },
  Cooking = (function()
    -- npc / where for your faction; "also" lists other vendors. No faction = anyone.
    local function v(npc, where, faction, also, alt)
      return { npc = npc, where = where, faction = faction, also = also, alt = alt }
    end
    local A = "Alliance"
    local H = "Horde"
    return {
      ["Brilliant Smallfish"] = v("Harn Longcast", "Mulgore", H, "Sewa Mistrunner (Thunder Bluff), Martine Tramblay (Tirisfal Glades), Lizbeth Cromwell (Undercity)",
        v("Tharynn Bouden", "Elwynn Forest", A, "Gretta Ganter (Dun Morogh), Khara Deepwater (Loch Modan), Catherine Leland (Stormwind), Nyoma (Teldrassil)")),
      ["Slitherskin Mackerel"] = v("Zansoa", "Durotar", H, "Martine Tramblay (Tirisfal Glades)",
        v("Tansy Puddlefizz", "Ironforge", A, "Nessa Shadowsong (Teldrassil), Kriggon Talsone (Westfall)")),
      ["Crispy Bat Wing"] = v("Abigail Shiel", "Tirisfal Glades", H),
      ["Scorpid Surprise"] = v("Grimtak", "Durotar", H),
      ["Kaldorei Spider Kabob"] = { quest = "Recipe of the Kaldorei", npc = "Zarrin", where = "Teldrassil", faction = A },
      ["Longjaw Mud Snapper"] = v("Harn Longcast", "Mulgore", H, "Killian Sanatha (Silverpine Forest), Naal Mistrunner (Thunder Bluff), Lizbeth Cromwell (Undercity)",
        v("Tharynn Bouden", "Elwynn Forest", A, "Tansy Puddlefizz (Ironforge), Khara Deepwater (Loch Modan), Nyoma (Teldrassil)")),
      ["Rainbow Fin Albacore"] = v("Shankys", "Orgrimmar", H, "Zansoa (Durotar), Killian Sanatha (Silverpine Forest), Ronald Burch (Undercity), Kilxx (The Barrens)",
        v("Catherine Leland", "Stormwind", A, "Heldan Galesong (Darkshore), Nessa Shadowsong (Teldrassil), Kriggon Talsone (Westfall), Stuart Fleming (Wetlands), Kilxx (The Barrens)")),
      ["Smoked Bear Meat"] = v("Andrew Hilbert", "Silverpine Forest", H, nil, v("Drac Roughcut", "Loch Modan", A)),
      ["Strider Stew"] = v("Tari'qa", "The Barrens", H, nil, { quest = "Easy Strider Living", faction = A }),
      ["Bristle Whisker Catfish"] = v("Derak Nightfall", "Hillsbrad Foothills", H, "Naal Mistrunner and Sewa Mistrunner (Thunder Bluff), Ronald Burch (Undercity), Kilxx (The Barrens)",
        v("Lindea Rabonne", "Hillsbrad Foothills", A, "Catherine Leland (Stormwind), Kilxx (The Barrens)")),
      ["Cooked Crab Claw"] = v("Kendor Kabonka", "Stormwind", A),
      ["Hot Lion Chops"] = v("Zargh", "The Barrens", H),
      ["Curiously Tasty Omelet"] = v("Keena", "Arathi Highlands", H, nil, v("Kendor Kabonka", "Stormwind", A)),
      ["Mithril Head Trout"] = v("Shankys", "Orgrimmar", H, "Wik'Tar (Ashenvale), Lizbeth Cromwell (Undercity), Wulan (Desolace), Kelsey Yance (Stranglethorn Vale)",
        v("Tansy Puddlefizz", "Ironforge", A, "Stuart Fleming (Wetlands), Heldan Galesong (Darkshore), Lindea Rabonne (Hillsbrad Foothills), Kelsey Yance (Stranglethorn Vale)")),
      ["Roast Raptor"] = v("Keena", "Arathi Highlands", H, "Ogg'marr (Dustwallow Marsh)", v("Hammon Karwn", "Arathi Highlands", A)),
      ["Soothing Turtle Bisque"] = { quest = "Soothing Turtle Bisque", npc = "Christoph Jeffcoat", where = "Hillsbrad Foothills", faction = H,
        alt = { quest = "Soothing Turtle Bisque", npc = "Chef Jessen", where = "Hillsbrad Foothills", faction = A } },
      ["Spotted Yellowtail"] = v("Gikkix", "Tanaris, Steamwheedle Port"),
      ["Filet of Redgill"] = v("Kelsey Yance", "Stranglethorn Vale, Booty Bay"),
      ["Undermine Clam Chowder"] = v("Jabbey", "Tanaris"),
      ["Monster Omelet"] = v("Bale", "Felwood", H, "Himmik (Winterspring)", v("Malygen", "Felwood", A, "Himmik (Winterspring)")),
      ["Tender Wolf Steak"] = v("Dirge Quikcleave", "Tanaris, Gadgetzan"),
      ["Poached Sunscale Salmon"] = v("Gikkix", "Tanaris, Steamwheedle Port"),
      ["Nightfin Soup"] = v("Gikkix", "Tanaris, Steamwheedle Port"),
      ["Smoked Desert Dumplings"] = { quest = "Desert Recipe", where = "Silithus", note = "Then \"Sharing the Knowledge\". Sandworm Meat drops from Dredge Strikers and Crushers in Silithus." },
    }
  end)(),
  Blacksmithing = {
    ["Ebon Shiv"] = MAGNUS,
    ["Ornate Thorium Handaxe"] = MAGNUS,
    ["Huge Thorium Battleaxe"] = MAGNUS,
    ["Bold Dirk"] = { npc = "Pexmit", where = "Mount Hyjal" },
    ["Mithril Coif"] = { npc = "Brikk Keencraft", where = "Booty Bay", trainer = true,
      note = "Taught by this Artisan trainer, not by the usual trainers." },
  },
}

-- Merchant's Favor recipe vendors, by faction.
local DSL = "The Barrens, Durotar Supply and Logistics by the Crossroads (49.4, 28.9)"
local ACA = "Redridge Mountains, Azeroth Commerce Authority at Three Corners (9.7, 71.8)"
ns.RawData.FavorVendors = {
  Engineering = { Horde = { npc = "Fizzlefuse", where = DSL }, Alliance = { npc = "Fritz Fizzle", where = ACA } },
  Blacksmithing = { Horde = { npc = "Gor'mak", where = DSL }, Alliance = { npc = "Stondry Darkhammer", where = ACA } },
}
-- Merchant's Favor cost by recipe name pattern (lfcarry.com tiers); some also need reputation.
ns.RawData.FavorCosts = {
  { "^Acolyte's ", 30 }, { "^Crusader's ", 30 }, { "^Guard's ", 30 }, { "^Protector's ", 30 }, { "^Veteran's ", 30 },
  { "Gauntlet$", 60 }, { "Pauldrons$", 60 },
  { "Wristguards$", 90 }, { "Sabatons$", 90 }, { "Waistguard$", 90 },
  { "^Thorium Cestus$", 90 }, { "^Thorium Greatmace$", 90 },
}

-- Recipe items are named "<prefix><recipe name>" on the auction house.
ns.RawData.RecipePrefixes = {
  Engineering = { "Schematic: ", "Blueprint: " },
  Blacksmithing = { "Plans: " },
  Cooking = { "Recipe: " },
}

-- Extra steps some professions need to reach a rank, with items for the shopping list.
-- Keyed by profession and rank name (see Ranks above).
ns.RawData.RankRules = {
  Cooking = {
    Expert = {
      note = "Expert Cooking needs the Expert Cookbook: Horde from Wulan (Shadowprey Village, Desolace), Alliance from Shandrina (Mystral Lake, Ashenvale).",
      items = { { "Expert Cookbook", 1 } },
    },
    Artisan = {
      note = "Artisan Cooking is the reward for \"Clamlette Surprise\" from Dirge Quikcleave in Gadgetzan (level 35). Get the travel quest from Zamja in Orgrimmar (Horde) or Daryl Riknussun in Ironforge (Alliance).",
      items = { { "Giant Egg", 12 }, { "Zesty Clam Meat", 10 }, { "Alterac Swiss", 20 } },
    },
  },
}

-- Professions that need a fire to craft.
ns.RawData.FireNote = "Cook at a fire: an inn or camp fire, or your own Basic Campfire (Simple Wood, needs Flint and Tinder)."
