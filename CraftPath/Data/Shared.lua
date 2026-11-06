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
-- These are Classic-era estimates; the addon replaces each one with the real price
-- the first time you open a merchant that sells it.
ns.RawData.VendorItems = {
  ["Weak Flux"] = 100,
  ["Strong Flux"] = 200,
  ["Coarse Thread"] = 10,
  ["Green Dye"] = 100,
  ["Nightcrawlers"] = 50,
  ["Blank Parchment"] = 125,
  ["Engineer's Ink"] = 400,
  ["Refreshing Spring Water"] = 25,
  ["Razor Arrow"] = 2,
  ["Flask of Oil"] = 80,
  ["Wooden Stock"] = 200,
  ["Heavy Stock"] = 400,
  ["Blacksmith Hammer"] = 20,
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
