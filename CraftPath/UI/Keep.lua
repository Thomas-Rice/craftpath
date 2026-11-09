-- CraftPath: marks items in your bags and bank that your profession routes still need, so you
-- don't sell or auction them by mistake. Covers every profession CraftPath plans that this
-- character has, from its current skill to the target in the planner.
--
-- * bag and bank slots get a small profession icon
-- * item tooltips say how many to keep, and for what
-- * the auction house warns when a needed item is put up for sale
-- * selling a needed item to a vendor prints a warning (it can be bought back)

local _, ns = ...
ns.Keep = ns.Keep or {}
local Keep = ns.Keep

local ICONS = {
  Engineering = "Interface\\Icons\\Trade_Engineering",
  Blacksmithing = "Interface\\Icons\\Trade_BlackSmithing",
  Cooking = "Interface\\Icons\\INV_Misc_Food_15",
}

local need = {}      -- item name -> { qty = n, profs = { {prof, qty}, ... } }
local plans = {}     -- prof -> { key = route key, plan = plan }
local building = false
local lastCheck = -10
local slotNames = {} -- "bag:slot" -> item name, for the vendor warning after the item is gone

local function enabled()
  return ns.db and ns.db.settings.markBags ~= false
end

-- The professions CraftPath plans that this character has, below the planner's target.
local function myProfessions()
  local out = {}
  local target = tonumber(ns.db.settings.to) or 300
  for _, prof in ipairs(ns.Recipes.Professions()) do
    local skill = ns.Game.GetSkill(prof)
    if skill and skill > 0 and skill < target then out[#out + 1] = { prof = prof, skill = skill } end
  end
  return out
end

-- A profession's plan is reused until you finish its current step or prices/settings change.
local function current(p)
  local c = plans[p.prof]
  if not c or c.key ~= ns.RouteKey(p.prof) then return false end
  local first = c.plan.steps and c.plan.steps[1]
  if c.plan.error then return c.skill == p.skill end
  return first and p.skill >= c.plan.from and p.skill < first.to
end

local function collect(profs)
  wipe(need)
  for _, p in ipairs(profs) do
    local c = plans[p.prof]
    local demand = c and not c.plan.error and c.plan.demand
    if demand then
      for name, qty in pairs(demand) do
        if qty and qty > 0 then
          local e = need[name] or { qty = 0, profs = {} }
          e.qty = e.qty + qty
          e.profs[#e.profs + 1] = { p.prof, qty }
          need[name] = e
        end
      end
    end
  end
end

-- The "needed" list. Out-of-date plans are rebuilt in the background (no freeze); the
-- marks update when that finishes.
function Keep.Build(force)
  local now = GetTime and GetTime() or 0
  if building or (not force and now - lastCheck < 1) then return need end
  lastCheck = now
  local profs = myProfessions()
  local todo = {}
  for _, p in ipairs(profs) do
    if not current(p) then todo[#todo + 1] = p end
  end
  if #todo == 0 then collect(profs); return need end
  building = true
  ns.Async("keep", function()
    for _, p in ipairs(todo) do
      plans[p.prof] = { key = ns.RouteKey(p.prof), skill = p.skill,
        plan = ns.MakePlan({ profession = p.prof, liveSkill = true }) }
    end
  end, function()
    building = false
    collect(myProfessions())
    Keep.Refresh()
  end)
  return need
end

function Keep.MarkDirty() lastCheck = -10 end

-- How many of this item to keep, and for which professions.
function Keep.For(name)
  if not enabled() or not name then return nil end
  return Keep.Build()[name]
end

local function keepText(e)
  local parts = {}
  for _, pq in ipairs(e.profs) do parts[#parts + 1] = pq[2] .. " for " .. pq[1] end
  return table.concat(parts, ", ")
end
Keep.Text = keepText

---------------------------------------------------------------------------
-- Bag and bank slots
---------------------------------------------------------------------------

local function itemName(bag, slot)
  if not (C_Container and C_Container.GetContainerItemInfo) then return nil end
  local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
  if not ok or not info then return nil end
  if info.hyperlink then
    local n = info.hyperlink:match("%[(.-)%]")
    if n then return n end
  end
  if info.itemID and C_Item and C_Item.GetItemInfo then
    local okName, n = pcall(C_Item.GetItemInfo, info.itemID)
    if okName then return n end
  end
end

-- Bag and slot for an item button: bags, the old bank frame and the newer bank panel differ.
local function bagSlot(b)
  if b.GetBankTabID and b.GetContainerSlotID then
    local ok1, bag = pcall(b.GetBankTabID, b)
    local ok2, slot = pcall(b.GetContainerSlotID, b)
    if ok1 and ok2 and type(bag) == "number" and type(slot) == "number" then return bag, slot end
  end
  if b.GetBagID then
    local ok, bag = pcall(b.GetBagID, b)
    local slot = b:GetID()
    if ok and type(bag) == "number" and type(slot) == "number" then return bag, slot end
  end
  if _G.BankFrame and b:GetParent() == _G.BankFrame and type(b:GetID()) == "number" then -- older bank frame
    return (Enum and Enum.BagIndex and Enum.BagIndex.Bank) or -1, b:GetID()
  end
end

local function mark(b, prof, e)
  local t = b.cpKeep
  if not prof then
    if t then t:Hide(); t.border:Hide() end
    return
  end
  if not t then
    local border = b:CreateTexture(nil, "OVERLAY", nil, 6)
    border:SetColorTexture(0, 0, 0, 0.9)
    border:SetSize(16, 16)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", 1, -1)
    t = b:CreateTexture(nil, "OVERLAY", nil, 7)
    t:SetSize(14, 14)
    t:SetPoint("CENTER", border, "CENTER")
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    t.border = border
    b.cpKeep = t
  end
  t:SetTexture(ICONS[prof] or "Interface\\Icons\\INV_Misc_Note_01")
  t:Show(); t.border:Show()
end

local function updateButton(b)
  if not b or not b.GetID then return end
  local bag, slot = bagSlot(b)
  if not bag or not slot then return end
  local name = itemName(bag, slot)
  slotNames[bag .. ":" .. slot] = name
  local e = enabled() and name and Keep.Build()[name]
  mark(b, e and e.profs[1] and e.profs[1][1] or nil, e)
end

local function eachButton(fn)
  local frames = { _G.ContainerFrameCombinedBags }
  for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
  frames[#frames + 1] = _G.BankPanel
  for _, f in ipairs(frames) do
    if f and f:IsShown() and f.EnumerateValidItems then
      local ok, iter, state, start = pcall(f.EnumerateValidItems, f)
      if ok and iter then
        for _, b in iter, state, start do fn(b) end
      end
    end
  end
  if _G.BankFrame and _G.BankFrame:IsShown() then -- older bank frame
    for i = 1, 28 do
      local b = _G["BankFrameItem" .. i]
      if b then fn(b) end
    end
  end
end

function Keep.Refresh()
  if not ns.db then return end
  eachButton(updateButton)
end

local pending = false
function Keep.RefreshSoon()
  if pending then return end
  pending = true
  local run = function() pending = false; Keep.Refresh() end
  if C_Timer and C_Timer.After then C_Timer.After(0.05, run) else run() end
end

---------------------------------------------------------------------------
-- Auction house and vendor warnings
---------------------------------------------------------------------------

local function nameAt(location)
  if not (location and C_Item and C_Item.GetItemName) then return nil end
  local ok, n = pcall(C_Item.GetItemName, location)
  return ok and n or nil
end

local function sellWarning(frame, location)
  if not frame then return end
  local w = frame.cpKeepWarning
  if not w then
    w = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    w:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 8, 4)
    w:SetPoint("RIGHT", frame, "RIGHT", -8, 0)
    w:SetJustifyH("LEFT")
    w:SetTextColor(1, 0.35, 0.25)
    frame.cpKeepWarning = w
  end
  local name = nameAt(location)
  local e = name and Keep.For(name)
  if e then
    local have = ns.Game.Owned(name)
    w:SetText(("CraftPath: you need %s %s (%s). You have %d."):format(e.qty, name, keepText(e), have))
    w:Show()
  else
    w:Hide()
  end
end

local function hookAuctionHouse()
  local ah = _G.AuctionHouseFrame
  if not ah or ah.cpKeepHooked then return end
  ah.cpKeepHooked = true
  for _, key in ipairs({ "ItemSellFrame", "CommoditiesSellFrame" }) do
    local f = ah[key]
    if type(f) == "table" and f.SetItem then
      hooksecurefunc(f, "SetItem", function(self, location) sellWarning(self, location) end)
    end
  end
end

local function hookVendor()
  if not (C_Container and C_Container.UseContainerItem) or Keep.vendorHooked then return end
  Keep.vendorHooked = true
  hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
    if not (enabled() and _G.MerchantFrame and _G.MerchantFrame:IsShown()) then return end
    local name = slotNames[bag .. ":" .. slot]
    local e = name and Keep.For(name)
    if e then
      ns.Print(("|cffff5533You sold %s, which you need for levelling (%s).|r Buy it back from the vendor's Buyback tab if that was a mistake.")
        :format(name, keepText(e)))
    end
  end)
end

---------------------------------------------------------------------------
-- Wiring
---------------------------------------------------------------------------

local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "PLAYERBANKSLOTS_CHANGED",
  "SKILL_LINES_CHANGED", "AUCTION_HOUSE_SHOW", "MERCHANT_SHOW", "BAG_OPEN" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    hookVendor()
    local frames = { _G.ContainerFrameCombinedBags, _G.BankFrame, _G.BankPanel }
    for i = 1, 13 do frames[#frames + 1] = _G["ContainerFrame" .. i] end
    for _, f in ipairs(frames) do
      if f and f.HookScript then f:HookScript("OnShow", Keep.RefreshSoon) end
      if f and f.UpdateItems then hooksecurefunc(f, "UpdateItems", Keep.RefreshSoon) end
    end
    return
  end
  if event == "SKILL_LINES_CHANGED" then Keep.MarkDirty() end
  if event == "AUCTION_HOUSE_SHOW" then hookAuctionHouse() end
  if event == "MERCHANT_SHOW" then Keep.MarkDirty() end
  Keep.RefreshSoon()
end)

function Keep.Toggle()
  ns.db.settings.markBags = not enabled()
  ns.Print("Marking items you need in your bags and bank " .. (enabled() and "on" or "off") .. ".")
  Keep.MarkDirty(); Keep.Refresh()
end
