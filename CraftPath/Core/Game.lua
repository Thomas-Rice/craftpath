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

-- Remember which recipes the character knows whenever a profession window is open.
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
    if okR and r and r.learned and r.name then known[r.name] = true end
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
