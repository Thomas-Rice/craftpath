-- CraftPath: shopping runs and purchase tracking.
--
-- A shopping run freezes the plan's buy list (quantities and planned prices) and a snapshot
-- of what was already in your bags, so buying doesn't reshuffle the route mid-run.
-- Every auction house purchase is recorded, whether made with CraftPath's Buy button or
-- Blizzard's own window, by watching the purchase calls (hooksecurefunc) and their events.

local _, ns = ...
ns.Shopping = {}
local Shopping = ns.Shopping

local LOG_MAX = 500

function Shopping.Get()
  return ns.db and ns.db.shop
end

function Shopping.Start(plan)
  if not plan or not plan.shopping then return end
  local items, order = {}, {}
  for _, b in ipairs(plan.shopping) do
    if b.buy > 0 or b.have > 0 then
      items[b.name] = { need = b.qty, have = b.have, unit = b.unit, source = b.source, bought = 0, spent = 0 }
      order[#order + 1] = b.name
    end
  end
  ns.db.shop = {
    profession = plan.profession, from = plan.from, to = plan.to, started = time(),
    items = items, order = order, plannedTotal = plan.buyTotal, skipped = {},
  }
  wipe(ns.db.done)
end

function Shopping.Stop()
  ns.db.shop = nil
end

function Shopping.Left(name)
  local s = Shopping.Get()
  local e = s and s.items[name]
  if not e then return 0 end
  return math.max(0, e.need - e.have - e.bought)
end

function Shopping.Totals()
  local s = Shopping.Get()
  if not s then return nil end
  local spent, leftCost, leftItems = 0, 0, 0
  for name, e in pairs(s.items) do
    spent = spent + e.spent
    local left = Shopping.Left(name)
    if left > 0 then leftItems = leftItems + 1; leftCost = leftCost + left * e.unit end
  end
  return { spent = spent, leftCost = leftCost, leftItems = leftItems, planned = s.plannedTotal }
end

-- Next item still to buy on the auction house (skipping ones the player skipped).
function Shopping.NextToBuy()
  local s = Shopping.Get()
  if not s then return nil end
  for _, name in ipairs(s.order) do
    local e = s.items[name]
    if e.source == "ah" and not s.skipped[name] and Shopping.Left(name) > 0 then return name, e end
  end
  return nil
end

function Shopping.Skip(name)
  local s = Shopping.Get()
  if s then s.skipped[name] = true end
end

-- Records a completed purchase (any purchase, shopping run or not).
function Shopping.Record(name, qty, total)
  if not name or not qty or qty <= 0 then return end
  local log = ns.db.purchases
  log[#log + 1] = { t = time(), item = name, qty = qty, total = total }
  while #log > LOG_MAX do table.remove(log, 1) end
  local s = Shopping.Get()
  local e = s and s.items[name]
  if e then
    e.bought = e.bought + qty
    e.spent = e.spent + (total or 0)
  end
  if total and qty > 0 then ns.Prices.Record(name, total / qty, nil, ns.db.ids[name]) end
  ns.Print(("Bought %d× %s for %s"):format(qty, name, ns.Prices.Money(total)))
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

---------------------------------------------------------------------------
-- Watching purchases
---------------------------------------------------------------------------

local function nameOf(itemID)
  if not itemID then return nil end
  if C_Item and C_Item.GetItemNameByID then
    local ok, n = pcall(C_Item.GetItemNameByID, itemID)
    if ok and n then return n end
  end
  for name, id in pairs(ns.db.ids) do if id == itemID then return name end end
  return nil
end
Shopping.NameOf = nameOf

-- Commodities (stackable goods): Start -> price quote -> Confirm -> success/failure.
local commodity = nil -- { itemID, qty, unit, total, confirmed }
-- Single auctions (plans, gear): search results tell us the item behind each auctionID.
local auctionItems, bids = {}, {}

function Shopping.InstallHooks()
  if not C_AuctionHouse or Shopping.hooked then return end
  Shopping.hooked = true
  if C_AuctionHouse.StartCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, qty)
      commodity = { itemID = itemID, qty = qty }
    end)
  end
  if C_AuctionHouse.ConfirmCommoditiesPurchase then
    hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, qty)
      if commodity and commodity.itemID == itemID then
        commodity.confirmed, commodity.qty = true, qty or commodity.qty
      else
        commodity = { itemID = itemID, qty = qty, confirmed = true }
      end
    end)
  end
  if C_AuctionHouse.PlaceBid then
    hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, amount)
      local a = auctionItems[auctionID]
      bids[auctionID] = { itemID = a and a.itemID, amount = amount, buyout = a and a.buyout }
    end)
  end
end

ns.On("COMMODITY_PRICE_UPDATED", function(unit, total)
  if commodity then commodity.unit, commodity.total = unit, total end
end)

ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
  local c = commodity
  commodity = nil
  if c and c.confirmed then
    local total = c.total or (c.unit and c.unit * c.qty)
    Shopping.Record(nameOf(c.itemID), c.qty, total)
  end
end)

ns.On("COMMODITY_PURCHASE_FAILED", function() commodity = nil end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  if not itemKey or not C_AuctionHouse.GetNumItemSearchResults then return end
  local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
  for i = 1, n do
    local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, i)
    if ok and info and info.auctionID then
      auctionItems[info.auctionID] = { itemID = itemKey.itemID, buyout = info.buyoutAmount }
    end
  end
end)

ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function(auctionID)
  local b = bids[auctionID]
  bids[auctionID] = nil
  -- Only a buyout is a purchase; a plain bid may still be outbid.
  if b and b.buyout and b.amount and b.amount >= b.buyout then
    Shopping.Record(nameOf(b.itemID), 1, b.amount)
  end
end)
