-- CraftPath: reads the character's professions, known recipes, bags and merchant prices.
-- Every game call is guarded, because Forever runs a trimmed-down retail API.

local _, ns = ...
ns.Game = {}
local Game = ns.Game

local SKILL_LINES = { Engineering = 202, Blacksmithing = 164, Cooking = 185 }

-- Current skill in a profession, or nil if the character doesn't have it.
function Game.GetSkill(profession)
  -- With the profession window open its own numbers update first, so prefer them.
  if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then
    local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
    if ok and info and info.professionName == profession and info.skillLevel and info.skillLevel > 0 then
      return info.skillLevel, info.maxSkillLevel
    end
  end
  if GetProfessions and GetProfessionInfo then
    -- GetProfessions returns prof1, prof2, archaeology, fishing, cooking; any can be nil.
    local ok, p1, p2, p3, p4, p5 = pcall(GetProfessions)
    if ok then
      for _, idx in pairs({ p1, p2, p3, p4, p5 }) do
        if idx then
          local ok2, name, _, skill, maxSkill = pcall(GetProfessionInfo, idx)
          if ok2 and name == profession then return skill, maxSkill end
        end
      end
    end
  end
  local line = SKILL_LINES[profession]
  if line and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, line)
    if ok and info and info.skillLevel and info.skillLevel > 0 then return info.skillLevel, info.maxSkillLevel end
  end
  return nil
end

-- Mailbox: the game only shows mail while the mailbox is open, so CraftPath remembers what
-- was in this character's mail at the last visit. Cash-on-delivery mail isn't counted
-- (you'd have to pay for it), and only the mail the game lists (up to 50) is seen.
local function charKey()
  return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end

local function readMail()
  if not (GetInboxNumItems and GetInboxItem) then return end
  local counts = {}
  for i = 1, GetInboxNumItems() or 0 do
    local cod = GetInboxHeaderInfo and select(6, GetInboxHeaderInfo(i))
    if not cod or cod == 0 then
      for j = 1, ATTACHMENTS_MAX_RECEIVE or 12 do
        local name, _, _, count = GetInboxItem(i, j)
        if name and count and count > 0 then counts[name] = (counts[name] or 0) + count end
      end
    end
  end
  ns.db.mail = ns.db.mail or {}
  ns.db.mail[charKey()] = { counts = counts, t = time() }
  if ns.Keep then ns.Keep.MarkDirty() end
end
ns.On("MAIL_INBOX_UPDATE", readMail)

-- How many of an item are in this character's mailbox (as of the last visit).
function Game.Mail(name)
  local m = ns.db.mail and ns.db.mail[charKey()]
  return m and m.counts[name] or 0
end

-- Bags only, and bags plus bank.
function Game.Bags(name)
  if not C_Item or not C_Item.GetItemCount then return 0 end
  local ok, n = pcall(C_Item.GetItemCount, ns.db.ids[name] or name, false)
  return ok and n or 0
end
function Game.BagsAndBank(name)
  if not C_Item or not C_Item.GetItemCount then return 0 end
  local ok, n = pcall(C_Item.GetItemCount, ns.db.ids[name] or name, true)
  return ok and n or 0
end

-- Everything you own: bags, bank and mailbox.
function Game.Owned(name)
  return Game.BagsAndBank(name) + Game.Mail(name)
end

---------------------------------------------------------------------------
-- Ore you can smelt counts as bars
---------------------------------------------------------------------------

-- Bar name -> { ore, per, makes, learn } for every smelt that takes a single ore.
local smelts
local function smeltTable()
  if smelts then return smelts end
  smelts = {}
  local data = ns.Recipes and ns.Recipes.Load("Mining")
  for _, r in ipairs(data and data.list or {}) do
    local g = r.reagents
    if #g == 1 and g[1].name:find(" Ore$") then
      smelts[r.name] = { ore = g[1].name, per = g[1].qty, makes = r.makes, learn = r.learn }
    end
  end
  return smelts
end

-- How to smelt this bar, if this character can: Mining at the recipe's skill.
function Game.Smelt(name)
  local s = smeltTable()[name]
  if not s then return nil end
  local skill = Game.GetSkill("Mining")
  if not skill or skill < s.learn then return nil end
  return s
end

-- Bars you could smelt from the ore in bags, bank and mailbox: three numbers.
function Game.FromOre(name)
  local s = Game.Smelt(name)
  if not s then return 0, 0, 0 end
  local bags = Game.Bags(s.ore)
  local bank = math.max(0, Game.BagsAndBank(s.ore) - bags)
  local mail = Game.Mail(s.ore)
  local function bars(n) return math.floor(n / s.per) * s.makes end
  return bars(bags), bars(bank), bars(mail)
end

-- Everything you own, counting ore you can smelt as bars (for routes in other professions).
function Game.OwnedWithOre(name)
  local a, b, c = Game.FromOre(name)
  return Game.Owned(name) + a + b + c
end

-- "12 in bank, 20 in mailbox" style breakdown of what isn't in your bags, or nil.
-- Includes bars you could smelt from ore ("smelt 8 from Iron Ore").
function Game.Elsewhere(name)
  local bags, all = Game.Bags(name), Game.BagsAndBank(name)
  local parts = {}
  if all - bags > 0 then parts[#parts + 1] = (all - bags) .. " in bank" end
  local mail = Game.Mail(name)
  if mail > 0 then parts[#parts + 1] = mail .. " in mailbox" end
  local a, b, c = Game.FromOre(name)
  if a + b + c > 0 then
    local s = Game.Smelt(name)
    parts[#parts + 1] = ("smelt %d from %s%s"):format(a + b + c, s.ore, a == a + b + c and " in bags" or "")
  end
  return #parts > 0 and table.concat(parts, ", ") or nil
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
--
-- A profession can list hundreds of recipes, so the read runs in the background over a few
-- frames (ns.Async) instead of in one go. It runs when the window opens and when you learn
-- a recipe; the many list updates while you craft only re-read if the list itself changed.
local lastCount, lastRead = {}, {} -- [prof] = recipe IDs seen / GetTime() of the last full read
local noted = {}                   -- [recipeID] = true: unknown recipes already looked up this session
local REREAD_AFTER = 30            -- seconds; a safety re-read for list updates with no visible change

local function readKnownRecipes(force)
  if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then return end
  local prof = Game.OpenProfession()
  if not prof then return end
  local okIds, ids = pcall(C_TradeSkillUI.GetAllRecipeIDs)
  if not okIds or not ids or #ids == 0 then return end -- list not ready yet; a list update follows
  local now = GetTime and GetTime() or 0
  if not force and lastCount[prof] == #ids and now - (lastRead[prof] or -1e9) < REREAD_AFTER then return end
  lastCount[prof], lastRead[prof] = #ids, now

  ns.Async("recipes", function()
    local known = {}
    ns.db.recipeIDs[prof] = ns.db.recipeIDs[prof] or {}
    local idMap = ns.db.recipeIDs[prof]
    local byName = ns.Recipes.Load(prof).byName
    for _, id in ipairs(ids) do
      ns.Planner.Tick() -- hands the frame back when this frame's time is used up
      local okR, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
      if okR and r and r.name then
        idMap[r.name] = id
        if r.learned then known[r.name] = true end
        if not byName[r.name] and not noted[id] then
          noted[id] = true
          local reagents, makes = recipeReagents(id)
          noteUnknown(prof, r.name, { recipeID = id, learned = r.learned or nil, reagents = reagents, makes = makes })
        end
      end
    end
    -- The window closed or switched profession mid-read: don't save a partial list.
    if Game.OpenProfession() ~= prof then lastCount[prof] = nil; return false end
    if next(known) then
      local old, same = ns.db.known[prof] or {}, true
      for k in pairs(known) do if not old[k] then same = false; break end end
      if same then for k in pairs(old) do if not known[k] then same = false; break end end end
      if not same then
        ns.db.known[prof] = known
        ns.db.knownVersion = (ns.db.knownVersion or 0) + 1
        return true
      end
    end
    return false
  end, function(changed)
    Game.openProfession = prof
    if changed and ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
    if (changed or force) and ns.CraftHelper then ns.CraftHelper.Update() end
  end)
end
-- The profession currently open, or nil.
function Game.OpenProfession()
  if not C_TradeSkillUI or not C_TradeSkillUI.GetBaseProfessionInfo then return nil end
  local ok, info = pcall(C_TradeSkillUI.GetBaseProfessionInfo)
  local prof = ok and info and info.professionName
  if prof and ns.RawData[prof] then return prof end
  return nil
end

-- How many times a known recipe can be crafted from what's in your bags.
function Game.Craftable(prof, recipe)
  local id = ns.db.recipeIDs[prof] and ns.db.recipeIDs[prof][recipe.name]
  if id then
    local ok, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if ok and r and r.numAvailable then return r.numAvailable end
  end
  local n = math.huge
  for _, g in ipairs(recipe.reagents) do
    n = math.min(n, math.floor(Game.Owned(g.name) / g.qty))
  end
  return n == math.huge and 0 or n
end

ns.On("TRADE_SKILL_SHOW", function()
  if ns.CraftHelper then ns.CraftHelper.preview = nil end -- opening the window: back to your current step
  readKnownRecipes(true)
end)
-- This fires several times per craft. It only triggers a read (at most about once a second)
-- when the list changed, so crafting doesn't keep re-reading every recipe.
local readPending = false
ns.On("TRADE_SKILL_LIST_UPDATE", function()
  if readPending then return end
  readPending = true
  C_Timer.After(0.75, function() readPending = false; readKnownRecipes(false) end)
end)
-- Learning a recipe (trainer, plans or schematic) doesn't change the list's length.
local learnRead = false
local function learned()
  if learnRead then return end
  learnRead = true
  C_Timer.After(0.5, function() learnRead = false; readKnownRecipes(true) end)
end
pcall(ns.On, "NEW_RECIPE_LEARNED", learned) -- not every client has this event

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
    -- Remember who sells recipes and where, to tell you later.
    if name then
      for _, prefixes in pairs(ns.RawData.RecipePrefixes) do
        for _, pre in ipairs(prefixes) do
          if name:sub(1, #pre) == pre then ns.db.vendorWhere[name] = Game.HereNPC() end
        end
      end
    end
  end
end
-- The NPC you're talking to and where you are, e.g. "Sovik" / "Orgrimmar, Valley of Honor (37.2, 85.0)".
function Game.HereNPC()
  local npc = UnitName and UnitName("npc") or nil
  local zone = GetRealZoneText and GetRealZoneText() or ""
  local sub = GetSubZoneText and GetSubZoneText() or ""
  local where = (sub ~= "" and sub ~= zone) and (zone .. ", " .. sub) or zone
  if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
    local ok, pos = pcall(function()
      return C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player")
    end)
    if ok and pos and pos.GetXY then
      local x, y = pos:GetXY()
      if x and y and x > 0 then where = ("%s (%.1f, %.1f)"):format(where, x * 100, y * 100) end
    end
  end
  return { npc = npc, where = where }
end

ns.On("MERCHANT_SHOW", readMerchant)
ns.On("MERCHANT_UPDATE", readMerchant)

-- Trainers show the real skill needed to learn each recipe; the client tables only
-- give an estimate for some trainer recipes.
-- Calls the first trainer function that exists: the old globals, or C_Trainer in newer clients.
local function trainerCall(names, ...)
  for _, n in ipairs(names) do
    local f = _G.C_Trainer and _G.C_Trainer[n] or _G[n]
    if type(f) == "function" then
      local res = { n = 0 }
      local function pack(...) res.n = select("#", ...); for i = 1, res.n do res[i] = (select(i, ...)) end end
      pack(pcall(f, ...))
      if res[1] then return true, unpack(res, 2, res.n) end
      return false, res[2]
    end
  end
  return false, "missing"
end

local function readTrainer(why)
  -- What the game offered, saved every time, so a trainer that records nothing can be looked into.
  local probe = { t = time(), why = why, version = ns.version, errors = {} }
  if type(_G.C_Trainer) == "table" then
    local keys = {}
    for k in pairs(_G.C_Trainer) do keys[#keys + 1] = k end
    table.sort(keys)
    probe.cTrainer = table.concat(keys, " ")
  end
  ns.db.trainerProbe = probe
  local function note(step, err) probe.errors[#probe.errors + 1] = step .. ": " .. tostring(err) end
  -- Show everything the trainer teaches, not just what you can learn right now,
  -- then put the player's filters back.
  local filters = {}
  for _, f in ipairs({ "available", "unavailable", "used" }) do
    local ok, on = trainerCall({ "GetTrainerServiceTypeFilter", "GetServiceTypeFilter" }, f)
    if ok then
      filters[f] = on
      if not on then trainerCall({ "SetTrainerServiceTypeFilter", "SetServiceTypeFilter" }, f, 1) end
    else
      note("filter " .. f, on)
    end
  end
  local okN, n = trainerCall({ "GetNumTrainerServices", "GetNumServices" })
  if not okN then note("count", n); n = 0 end
  n = tonumber(n) or 0
  probe.n = n
  local saved = 0
  for i = 1, n do
    local ok, name = trainerCall({ "GetTrainerServiceInfo", "GetServiceInfo" }, i)
    local ok2, skill, rank = trainerCall({ "GetTrainerServiceSkillReq", "GetServiceSkillReq" }, i)
    if type(name) == "table" then name = name.name end -- newer APIs return a table
    if i == 1 then probe.first = tostring(name) .. " / " .. tostring(skill) .. " / " .. tostring(rank) end
    if not ok then note("info " .. i, name) elseif not ok2 then note("skill " .. i, skill) end
    -- Skip rank training such as "Journeyman Engineering".
    if ok and ok2 and type(name) == "string" and skill and tonumber(rank) and ns.RawData[skill]
      and not name:find(skill, 1, true) then
      ns.db.trainer[skill] = ns.db.trainer[skill] or {}
      ns.db.trainer[skill][name] = tonumber(rank)
      saved = saved + 1
      noteUnknown(skill, name, { trainer = true, learn = tonumber(rank) })
    end
    if #probe.errors > 5 then break end
  end
  probe.saved = saved
  for f, v in pairs(filters) do
    if not v then trainerCall({ "SetTrainerServiceTypeFilter", "SetServiceTypeFilter" }, f, 0) end
  end
end
local function trainerOpened(why)
  readTrainer(why)
  -- the list can arrive a moment after the window opens
  if C_Timer and C_Timer.After then C_Timer.After(0.5, function() readTrainer(why .. "+0.5s") end) end
end
ns.On("TRAINER_SHOW", function() trainerOpened("TRAINER_SHOW") end)
ns.On("TRAINER_UPDATE", function() readTrainer("TRAINER_UPDATE") end)
-- Newer clients open NPC windows through the interaction manager (type 7 = trainer).
pcall(ns.On, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", function(kind)
  local trainer = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Trainer or 7
  if kind == trainer then trainerOpened("INTERACTION") end
end)
