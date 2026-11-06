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
  ["Blank Parchment"] = 125,        -- estimate
  ["Engineer's Ink"] = 400,         -- estimate
  ["Flask of Oil"] = 80,            -- estimate
}

-- Vendor prices above that are still guesses (shown as "est.").
ns.RawData.VendorEstimates = { ["Blank Parchment"] = true, ["Engineer's Ink"] = true, ["Flask of Oil"] = true }

-- Price guess (copper) for gold-vendor recipes until the merchant has been seen.
ns.RawData.VendorRecipeEstimate = 5000

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
}
