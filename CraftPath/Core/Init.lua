-- CraftPath: saved variables, event dispatch and slash commands.

local addonName, ns = ...
_G.CraftPath = ns

ns.version = C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version") or "dev"

local DEFAULTS = {
  prices = {},      -- [itemName] = { p = copper, q = quantity, id = itemID, t = time, scan = scanId }
  vendor = {},      -- [itemName] = copper per unit, learned at merchants
  vendorWhere = {}, -- [recipe item] = { npc, where } for recipes seen at a merchant
  ids = {},         -- [itemName] = itemID
  known = {},       -- [profession] = { [recipeName] = true }
  recipeIDs = {},   -- [profession] = { [recipeName] = recipeID } from the profession window
  trainer = {},     -- [profession] = { [recipeName] = skill needed, as the trainer shows it }
  seen = {},        -- [profession] = { [recipeName] = {...} } recipes the game has that the data lacks
  done = {},        -- [itemName] = true  (ticked off the shopping list)
  purchases = {},   -- log of auction house purchases { t, item, qty, total }
  -- shop = { ... } -- the active shopping run (Core/Shopping.lua), nil when none
  lastFullScan = 0,
  scanId = 0,
  settings = {
    profession = "Engineering",
    from = 1, to = 300, useMySkill = true, capToLevel = true,
    allowRecipeItems = true, allowFavor = true, spec = "none", overtimeRank = 0,
    openWithAH = true, tooltip = true, maxOverPct = 25, craftHelper = true, useOwned = true, markBags = true,
  },
}

local function applyDefaults(db, defaults)
  for k, v in pairs(defaults) do
    if db[k] == nil then
      if type(v) == "table" then db[k] = {}; applyDefaults(db[k], v) else db[k] = v end
    elseif type(v) == "table" and type(db[k]) == "table" then
      applyDefaults(db[k], v)
    end
  end
end

function ns.Print(...)
  local msg = table.concat({ tostringall(...) }, " ")
  DEFAULT_CHAT_FRAME:AddMessage("|cff33bbffCraftPath|r: " .. msg)
end

-- Tiny event bus: ns.On("EVENT", fn)
local frame = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
  if not handlers[event] then
    handlers[event] = {}
    frame:RegisterEvent(event)
  end
  table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do
    local ok, err = pcall(list[i], ...)
    if not ok then geterrorhandler()(err) end
  end
end)

ns.On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  CraftPathDB = CraftPathDB or {}
  applyDefaults(CraftPathDB, DEFAULTS)
  ns.db = CraftPathDB
  if ns.Shopping then ns.Shopping.InstallHooks() end
  if ns.OnLoaded then ns.OnLoaded() end
end)

-- Background jobs: fn runs spread over frames, a few milliseconds per frame, so planning
-- never freezes the game; done(result) is called when it finishes. A newer job with the
-- same key replaces one still waiting. Without debugprofilestop (tests) it runs at once.
local jobs, runner = {}, CreateFrame("Frame")
runner:Hide()
local SLICE_MS = 5
function ns.Async(key, fn, done)
  if not debugprofilestop then
    local result = fn()
    if done then done(result) end
    return
  end
  for i = #jobs, 2, -1 do
    if jobs[i].key == key then table.remove(jobs, i) end
  end
  jobs[#jobs + 1] = { key = key, co = coroutine.create(fn), done = done }
  runner:Show()
end
runner:SetScript("OnUpdate", function(self)
  local job = jobs[1]
  if not job then self:Hide(); return end
  ns.Planner.sliceEnd = debugprofilestop() + SLICE_MS
  local ok, result = coroutine.resume(job.co)
  ns.Planner.sliceEnd = nil
  if not ok then
    table.remove(jobs, 1)
    geterrorhandler()(result)
  elseif coroutine.status(job.co) == "dead" then
    table.remove(jobs, 1)
    if job.done then
      local okDone, err = pcall(job.done, result)
      if not okDone then geterrorhandler()(err) end
    end
  end
end)

-- Everything except your skill that changes a route: plans made with the same key can be
-- reused while you level (the crafting helper and bag marks rely on this).
function ns.RouteKey(prof)
  local s = ns.db.settings
  return table.concat({ prof, tostring(ns.db.scanId), tostring(#ns.db.purchases),
    tostring(s.allowRecipeItems), tostring(s.allowFavor), tostring(s.useOwned), tostring(s.spec),
    tostring(s.overtimeRank), tostring(s.to), tostring(s.capToLevel), tostring(ns.db.knownVersion) }, "|")
end

-- Build planner options from saved settings and live game state, then plan.
-- override (optional): { profession = ..., liveSkill = true } for the crafting helper.
function ns.MakePlan(override)
  local s = ns.db.settings
  local prof = override and override.profession or s.profession
  local from, to = tonumber(s.from) or 1, tonumber(s.to) or 300
  if s.useMySkill or (override and override.liveSkill) then
    local skill = ns.Game.GetSkill(prof)
    if skill then from = skill end
  end
  if override and override.from then from = override.from end
  local opts = {
    profession = prof, from = from, to = to,
    ahPrice = ns.Prices.AH, vendorPrice = ns.Prices.Vendor,
    known = ns.db.known[prof] or {},
    learnOverride = ns.db.trainer[prof],
    trainerOffers = ns.db.trainer[prof],
    allowRecipeItems = s.allowRecipeItems, allowFavor = s.allowFavor,
    spec = (s.spec ~= "none") and s.spec or nil,
    bonus = 0.04 * (tonumber(s.overtimeRank) or 0),
    owned = ns.Game.Owned,
    listed = ns.Prices.Listed,
    useOwned = s.useOwned,
    faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    vendorWhere = function(item) return ns.db.vendorWhere[item] end,
    charLevel = s.capToLevel and UnitLevel("player") or nil,
  }
  local plan = ns.Planner.Plan(opts)
  if not override then ns.lastPlan = plan end
  return plan
end

SLASH_CRAFTPATH1 = "/craftpath"
SLASH_CRAFTPATH2 = "/cpath"
SlashCmdList.CRAFTPATH = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "scan" then
    ns.Scanner.FullScan()
  elseif msg == "list" then
    ns.Scanner.ScanShoppingList()
  elseif msg == "craft" then
    ns.db.settings.craftHelper = not ns.db.settings.craftHelper
    ns.Print("Crafting helper " .. (ns.db.settings.craftHelper and "on" or "off") .. ".")
    ns.CraftHelper.Update()
  elseif msg == "keep" then
    ns.Keep.Toggle()
  elseif msg == "reset" then
    wipe(ns.db.prices); wipe(ns.db.done)
    ns.Print("Auction prices cleared.")
  elseif msg == "help" then
    ns.Print("/cpath — open the planner")
    ns.Print("/cpath scan — full auction house scan (at the AH, every 15 min)")
    ns.Print("/cpath list — scan just the items on your shopping list")
    ns.Print("/cpath craft — turn the crafting helper (beside the profession window) on or off")
    ns.Print("/cpath keep — turn marking of items you need in your bags and bank on or off")
    ns.Print("/cpath reset — forget all auction prices")
  else
    ns.UI.Toggle()
  end
end

function CraftPath_OnAddonCompartmentClick()
  ns.UI.Toggle()
end
