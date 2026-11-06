-- CraftPath: reads the character's professions, known recipes, bags and merchant prices.
-- Every game call is guarded, because Forever runs a trimmed-down retail API.

local _, ns = ...
ns.Game = {}
local Game = ns.Game

local SKILL_LINES = { Engineering = 202, Blacksmithing = 164 }

-- Current skill in a profession, or nil if the character doesn't have it.
function Game.GetSkill(profession)
  if GetProfessions and GetProfessionInfo then
    local ok, p1, p2 = pcall(GetProfessions)
    if ok then
      for _, idx in ipairs({ p1, p2 }) do
        if idx then
          local ok2, name, _, skill = pcall(GetProfessionInfo, idx)
          if ok2 and name == profession then return skill end
        end
      end
    end
  end
  local line = SKILL_LINES[profession]
  if line and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
    if ok and info and info.skillLevel and info.skillLevel > 0 then return info.skillLevel end
  end
  return nil
end

function Game.Owned(name)
  if not C_Item or not C_Item.GetItemCount then return 0 end
  local id = ns.db.ids[name]
  local ok, n = pcall(C_Item.GetItemCount, id or name, true)
  return ok and n or 0
end

-- Recipes the game shows that CraftPath's data doesn't have yet (a new patch or hotfix).
local function noteUnknown(prof, name, info)
  local data = ns.Recipes.Load(prof)
  if not data or data.byName[name] then return end
  ns.db.seen[prof] = ns.db.seen[prof] or {}
  local e = ns.db.seen[prof][name] or {}
  for k, v in pairs(info) do e[k] = v end
  e.t = time()
  ns.db.seen[prof][name] = e
end
Game.NoteUnknown = noteUnknown

-- A "Plans: X" / "Schematic: X" seen on the auction house for a recipe the data lacks.
function Game.NoteRecipeItem(itemName, price)
  for prof, prefixes in pairs(ns.RawData.RecipePrefixes) do
    for _, pre in ipairs(prefixes) do
      if itemName:sub(1, #pre) == pre then
        noteUnknown(prof, itemName:sub(#pre + 1), { recipeItem = itemName, price = price })
        return
      end
    end
  end
end

local function recipeReagents(recipeID)
  if not C_TradeSkillUI.GetRecipeSchematic then return nil end
  local ok, sch = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
  if not ok or not sch or not sch.reagentSlotSchematics then return nil end
  local out = {}
  for _, slot in ipairs(sch.reagentSlotSchematics) do
    local reagent = slot.reagents and slot.reagents[1]
    if reagent and reagent.itemID then
      local name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(reagent.itemID)
      out[#out + 1] = (name or ("item:" .. reagent.itemID)) .. "*" .. (slot.quantityRequired or 1)
    end
  end
  return table.concat(out, ";"), sch.quantityMin
end

-- Remember which recipes the character knows whenever a profession window is open,
-- and note any recipe (learned or not) that CraftPath's data doesn't list.
local function readKnownRecipes()
  if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then return end
  local prof
  local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
  if ok and info then prof = info.professionName end
  if not prof or not ns.RawData[prof] then return end
  local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
  if not okIds or not ids then return end
  local known = {}
  for _, id in ipairs(ids) do
    local okR, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if okR and r and r.name then
      if r.learned then known[r.name] = true end
      if not ns.Recipes.Load(prof).byName[r.name] then
        local reagents, makes = recipeReagents(id)
        noteUnknown(prof, r.name, { recipeID = id, learned = r.learned or nil, reagents = reagents, makes = makes })
      end
    end
  end
  if next(known) then
    ns.db.known[prof] = known
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  end
end
ns.On("TRADE_SKILL_SHOW", readKnownRecipes)
ns.On("TRADE_SKILL_LIST_UPDATE", readKnownRecipes)

-- Learn real vendor prices (reagents and schematics/plans) whenever a merchant is open.
local function readMerchant()
  local n = GetMerchantNumItems and GetMerchantNumItems() or 0
  for i = 1, n do
    local name, price, qty, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
      if ok and info then name, price, qty, extended = info.name, info.price, info.stackCount, info.hasExtendedCost end
    elseif GetMerchantItemInfo then
      local nm, _, pr, q, _, _, _, ext = GetMerchantItemInfo(i)
      name, price, qty, extended = nm, pr, q, ext
    end
    if name and price and price > 0 and not extended then
      ns.Prices.RecordVendor(name, price / math.max(1, qty or 1))
    end
  end
end
ns.On("MERCHANT_SHOW", readMerchant)
ns.On("MERCHANT_UPDATE", readMerchant)

-- Trainers show the real skill needed to learn each recipe; the client tables only
-- give an estimate for some trainer recipes.
local function readTrainer()
  if not GetNumTrainerServices or not GetTrainerServiceSkillReq then return end
  -- Show everything the trainer teaches, not just what you can learn right now,
  -- then put the player's filters back.
  local saved = {}
  if SetTrainerServiceTypeFilter and GetTrainerServiceTypeFilter then
    for _, f in ipairs({ "available", "unavailable", "used" }) do
      saved[f] = GetTrainerServiceTypeFilter(f)
      if not saved[f] then SetTrainerServiceTypeFilter(f, 1) end
    end
  end
  local n = GetNumTrainerServices() or 0
  for i = 1, n do
    local ok, name = pcall(GetTrainerServiceInfo, i)
    local ok2, skill, rank = pcall(GetTrainerServiceSkillReq, i)
    -- Skip rank training such as "Journeyman Engineering".
    if ok and ok2 and name and skill and rank and ns.RawData[skill] and not name:find(skill, 1, true) then
      ns.db.trainer[skill] = ns.db.trainer[skill] or {}
      ns.db.trainer[skill][name] = rank
      noteUnknown(skill, name, { trainer = true, learn = rank })
    end
  end
  for f, v in pairs(saved) do
    if not v then SetTrainerServiceTypeFilter(f, 0) end
  end
end
ns.On("TRAINER_SHOW", readTrainer)
ns.On("TRAINER_UPDATE", readTrainer)
