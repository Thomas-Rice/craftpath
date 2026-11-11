-- CraftPath Ledger: a history of what you buy, sell and craft, and how much it made you.
--
-- Recorded automatically:
--   buy     auction house purchases (from the shopping/buy tracking)
--   vbuy    things bought from a vendor
--   sell    auction house sales, read from the "Auction successful" mails (sale price and cut)
--   vsell   things sold to a vendor
--   craft   each craft: what it made, and the market value of the materials used
--   skill   profession skill-ups
-- Events are kept for each character in CraftPathDB.ledger (the newest 8000), and running
-- totals per item are kept forever, so the Items view still adds up after old events go.

local _, ns = ...
ns.Ledger = ns.Ledger or {}
local Ledger = ns.Ledger

local MAX_EVENTS = 8000

local function charKey()
  return (UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "")
end
Ledger.CharKey = charKey

local function store()
  local db = ns.db
  db.ledger = db.ledger or {}
  local l = db.ledger
  l.events = l.events or {}
  l.items = l.items or {}
  l.seenMail = l.seenMail or {}
  return l
end

-- Running totals per item: made (count, material value), bought (count, gold), sold (count, gold).
local function itemTotals(name)
  local items = store().items
  local e = items[name]
  if not e then
    e = { made = 0, madeCost = 0, bought = 0, spent = 0, sold = 0, earned = 0 }
    items[name] = e
  end
  return e
end

-- kind, item name, quantity, gold (copper: + money in, - money out or material value used), extra fields
function Ledger.Add(kind, name, qty, gold, extra)
  if not ns.db or not name then return end
  local l = store()
  local ev = { t = time(), k = kind, n = name, q = qty or 1, g = math.floor((gold or 0) + 0.5), ch = charKey() }
  if extra then for k, v in pairs(extra) do ev[k] = v end end
  l.events[#l.events + 1] = ev
  if #l.events > MAX_EVENTS then table.remove(l.events, 1) end
  local it = kind ~= "skill" and itemTotals(name)
  if kind == "craft" then
    it.made = it.made + ev.q; it.madeCost = it.madeCost - ev.g
  elseif kind == "buy" or kind == "vbuy" then
    it.bought = it.bought + ev.q; it.spent = it.spent - ev.g
  elseif kind == "sell" or kind == "vsell" then
    it.sold = it.sold + ev.q; it.earned = it.earned + ev.g
  end
  if ns.LedgerUI and ns.LedgerUI.Refresh then ns.LedgerUI.Refresh() end
  return ev
end

---------------------------------------------------------------------------
-- Adding up
---------------------------------------------------------------------------

-- Events since a time (nil = all), optionally only this character's.
function Ledger.Events(since, onlyMe)
  local out, me = {}, charKey()
  for _, ev in ipairs(store().events) do
    if (not since or ev.t >= since) and (not onlyMe or ev.ch == me) then out[#out + 1] = ev end
  end
  return out
end

-- Summary of a list of events: money in/out by kind, crafting, skill-ups, and per-item results.
-- Profit on an item = what it sold for, minus what making (or buying) the sold ones cost.
function Ledger.Summarise(events)
  local s = { income = { sell = 0, vsell = 0 }, spend = { buy = 0, vbuy = 0 }, crafts = 0, craftValue = 0,
    skills = {}, items = {} }
  local function item(n)
    local e = s.items[n]
    if not e then
      e = { name = n, made = 0, madeCost = 0, bought = 0, spent = 0, sold = 0, earned = 0 }
      s.items[n] = e
    end
    return e
  end
  for _, ev in ipairs(events) do
    if ev.k == "sell" or ev.k == "vsell" then
      s.income[ev.k] = s.income[ev.k] + ev.g
      local e = item(ev.n); e.sold = e.sold + ev.q; e.earned = e.earned + ev.g
    elseif ev.k == "buy" or ev.k == "vbuy" then
      s.spend[ev.k] = s.spend[ev.k] - ev.g
      local e = item(ev.n); e.bought = e.bought + ev.q; e.spent = e.spent - ev.g
    elseif ev.k == "craft" then
      s.crafts = s.crafts + 1
      s.craftValue = s.craftValue - ev.g
      local e = item(ev.n); e.made = e.made + ev.q; e.madeCost = e.madeCost - ev.g
      e.profession = ev.p or e.profession
    elseif ev.k == "skill" then
      local k = s.skills[ev.n]
      if not k then k = { name = ev.n, from = ev.from or ev.q - 1, to = ev.q }; s.skills[ev.n] = k end
      if ev.q > k.to then k.to = ev.q end
      if (ev.from or ev.q - 1) < k.from then k.from = ev.from or ev.q - 1 end
    end
  end
  s.moneyIn = s.income.sell + s.income.vsell
  s.moneyOut = s.spend.buy + s.spend.vbuy
  s.net = s.moneyIn - s.moneyOut
  -- Per item: average cost of one (made, else bought), and profit on the ones sold.
  local list = {}
  for _, e in pairs(s.items) do
    local all = itemTotals(e.name) -- lifetime averages are steadier than one week's
    if all.made > 0 then e.unitCost = all.madeCost / all.made
    elseif all.bought > 0 then e.unitCost = all.spent / all.bought end
    if e.sold > 0 then
      e.unitSale = e.earned / e.sold
      if e.unitCost then e.profit = e.earned - e.unitCost * e.sold end
    end
    list[#list + 1] = e
  end
  table.sort(list, function(a, b) return (a.profit or -math.huge) > (b.profit or -math.huge) end)
  s.list = list
  s.craftProfit = 0
  for _, e in ipairs(list) do if e.made > 0 and e.profit then s.craftProfit = s.craftProfit + e.profit end end
  return s
end

---------------------------------------------------------------------------
-- Recording: vendor, mail (auction sales), crafting, skill-ups
---------------------------------------------------------------------------

local function sellPriceOf(name)
  local v = ns.RawData.ItemSell and ns.RawData.ItemSell[name] or ns.db.sell[name]
  if v then return v end
  if C_Item and C_Item.GetItemInfo then
    local ok, n, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, ns.db.ids[name] or name)
    if ok and n and type(sell) == "number" then return sell end
  end
end

-- Bag contents just before a vendor sale (the item is gone afterwards).
local bagSnap = {}
local function snapBags()
  if not (C_Container and C_Container.GetContainerNumSlots) then return end
  wipe(bagSnap)
  for bag = 0, 4 do
    for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
      local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
      if ok and info then
        local n = info.hyperlink and info.hyperlink:match("%[(.-)%]")
        if n then bagSnap[bag .. ":" .. slot] = { n = n, q = info.stackCount or 1 } end
      end
    end
  end
end
Ledger.SnapBags = snapBags

function Ledger.Hook()
  if Ledger.hooked then return end
  Ledger.hooked = true
  -- Selling to a vendor (right-click at a merchant)
  if C_Container and C_Container.UseContainerItem then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
      if not (MerchantFrame and MerchantFrame:IsShown()) then return end
      local e = bagSnap[bag .. ":" .. slot]
      if not e then return end
      local each = sellPriceOf(e.n)
      if each and each > 0 then Ledger.Add("vsell", e.n, e.q, each * e.q) end
      bagSnap[bag .. ":" .. slot] = nil
    end)
  end
  -- Buying from a vendor
  if BuyMerchantItem then
    hooksecurefunc("BuyMerchantItem", function(index, qty)
      local name, price, stack
      if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local ok, info = pcall(C_MerchantFrame.GetItemInfo, index)
        if ok and info then name, price, stack = info.name, info.price, info.stackCount end
      elseif GetMerchantItemInfo then
        local _
        name, _, price, stack = GetMerchantItemInfo(index)
      end
      if not name or not price or price <= 0 then return end
      qty = qty or (stack or 1)
      local each = price / math.max(1, stack or 1)
      Ledger.Add("vbuy", name, qty, -each * qty)
    end)
  end
end

-- Auction sales: every "Auction successful" mail carries an invoice with the item, sale price
-- and the auction house's cut. Each mail is counted once.
local function readInvoices()
  if not (GetInboxNumItems and GetInboxInvoiceInfo and GetInboxHeaderInfo) then return end
  local l = store()
  local now = time()
  for i = 1, GetInboxNumItems() or 0 do
    local ok, kind, itemName, buyer, bid, _, _, cut, _, _, count = pcall(GetInboxInvoiceInfo, i)
    if ok and kind == "seller" and itemName and bid then
      local daysLeft = select(7, GetInboxHeaderInfo(i))
      -- A mail's expiry time is fixed, so (item, price, count, buyer, expiry) identifies it on
      -- later visits; expiry is worked out from "days left", so allow it to drift a little.
      local expires = now + (daysLeft or 0) * 86400
      local key = table.concat({ itemName, bid, count or 1, buyer or "" }, "|")
      local seen = l.seenMail[key]
      local dup = false
      if type(seen) == "table" then
        for _, x in ipairs(seen.x) do if math.abs(x - expires) < 1800 then dup = true break end end
      else
        seen = { t = now, x = {} }; l.seenMail[key] = seen
      end
      if not dup then
        seen.x[#seen.x + 1] = math.floor(expires)
        seen.t = now
        Ledger.Add("sell", itemName, count or 1, bid - (cut or 0), { buyer = buyer, cut = cut })
      end
    end
  end
  -- forget mail keys after 40 days (mail lasts 30)
  for k, v in pairs(l.seenMail) do
    if type(v) ~= "table" or now - (v.t or 0) > 40 * 86400 then l.seenMail[k] = nil end
  end
end
Ledger.ReadInvoices = readInvoices

-- Crafting: the recipe that was cast, and the market value of the materials it used.
local byName
local function recipeFor(spellName)
  if not byName then
    byName = {}
    for _, prof in ipairs(ns.Recipes.Professions()) do
      for _, r in ipairs(ns.Recipes.Load(prof).list) do byName[r.name] = byName[r.name] or r end
    end
  end
  return byName[spellName]
end

function Ledger.Crafted(spellName)
  local r = recipeFor(spellName)
  if not r then return end
  local value = 0
  for _, g in ipairs(r.reagents) do
    local p = ns.Prices.AH(g.name) or ns.Prices.Vendor(g.name) or ns.RawData.VendorItems[g.name]
      or (ns.RawData.VendorGoods or {})[g.name] or 0
    value = value + g.qty * p
  end
  return Ledger.Add("craft", r.name, r.makes, -value, { p = r.profession })
end

local lastSkill = {}
local function onSkillMessage(msg)
  -- "Your skill in Blacksmithing has increased to 120."
  local prof, to = (msg or ""):match("[Yy]our skill in (.-) has increased to (%d+)")
  if not prof then return end
  to = tonumber(to)
  Ledger.Add("skill", prof, to, 0, { from = lastSkill[prof] or (to - 1) })
  lastSkill[prof] = to
end
Ledger.OnSkillMessage = onSkillMessage

ns.On("PLAYER_LOGIN", function() Ledger.Hook() end)
ns.On("MERCHANT_SHOW", snapBags)
ns.On("BAG_UPDATE_DELAYED", function() if MerchantFrame and MerchantFrame:IsShown() then snapBags() end end)
ns.On("MAIL_INBOX_UPDATE", readInvoices)
ns.On("CHAT_MSG_SKILL", onSkillMessage)
-- Which recipe a successful cast was, or nil if it wasn't a craft. Crafting needs the
-- profession window open, and the game knows every recipe spell; that keeps out spells that
-- share a name with an item (drinking a Healing Potion, say).
local function windowOpen()
  local f = _G.ProfessionsFrame or _G.TradeSkillFrame
  return f and f.IsShown and f:IsShown()
end

function Ledger.RecipeForCast(spellID, spellName)
  if not windowOpen() then return nil end
  local api = C_TradeSkillUI
  if api and api.GetRecipeInfo then
    local ok, info = pcall(api.GetRecipeInfo, spellID)
    if not (ok and info) then return nil end
    spellName = spellName or info.name
  end
  local r = spellName and recipeFor(spellName)
  if r then return r end
  if api and api.GetRecipeOutputItemData then -- "Smelt Copper" makes Copper Bar
    local ok, out = pcall(api.GetRecipeOutputItemData, spellID)
    local n = ok and out and (out.hyperlink and out.hyperlink:match("%[(.-)%]")
      or (out.itemID and C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(out.itemID)))
    r = n and recipeFor(n)
    if r then return r end
  end
  local metal = spellName and spellName:match("^Smelt (.+)$")
  return metal and (recipeFor(metal .. " Bar") or recipeFor(metal))
end

ns.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
  if unit ~= "player" or not spellID then return end
  local name
  if C_Spell and C_Spell.GetSpellName then name = C_Spell.GetSpellName(spellID)
  elseif GetSpellInfo then name = GetSpellInfo(spellID) end
  local r = Ledger.RecipeForCast(spellID, name)
  if r then Ledger.Crafted(r.name) end
end)
