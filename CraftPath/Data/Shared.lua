-- CraftPath shared data: variant sets, vendor-sold reagents and profession facts.

local _, ns = ...
ns.RawData = ns.RawData or {}

-- "@SET NAME" lines in the recipe files expand once per variant here.
-- Each entry is { variant name, gem/extra reagent (or false) }.
ns.RawData.Sets = {
  ROCKET   = { {"Blue"}, {"Green"}, {"Purple"}, {"Red"}, {"White"}, {"Yellow"} },
  FIREWORK = { {"Blue"}, {"Green"}, {"Red"} },
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

-- Price guess (copper) for gold-vendor recipes until the merchant has been seen.
ns.RawData.VendorRecipeEstimate = 5000

-- Rank caps and the character level each trainer rank needs (Forever follows Classic).
ns.RawData.Ranks = {
  { name = "Apprentice", cap = 75,  trainAt = 1,   level = 1 },
  { name = "Journeyman", cap = 150, trainAt = 50,  level = 10 },
  { name = "Expert",     cap = 225, trainAt = 125, level = 20 },
  { name = "Artisan",    cap = 300, trainAt = 200, level = 35 },
}

-- Recipe items are named "<prefix><recipe name>" on the auction house.
ns.RawData.RecipePrefixes = {
  Engineering = { "Schematic: ", "Blueprint: " },
  Blacksmithing = { "Plans: " },
}
