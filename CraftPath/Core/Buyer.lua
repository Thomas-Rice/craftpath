-- CraftPath: one-click buying for the shopping run.
--
-- Blizzard only lets a purchase start from a real click, so this never buys on its own:
--   click "Get price" -> asks the auction house for the live price of the next item
--   click "Buy ..."   -> buys it, if the live price is within your limit over the plan
-- Purchases are recorded by Core/Shopping.lua's hooks, the same as Blizzard-window buys.

local _, ns = ...
ns.Buyer = {}
local Buyer = ns.Buyer

-- state: nil | "quoting" | "confirm" | "pricey" | "buying"
Buyer.state = nil
Buyer.current = nil -- { name, itemID, qty, kind = "commodity"|"item", unit, total, auctionID }

local function changed()
  if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
end

local function fail(msg)
  Buyer.state, Buyer.current = nil, nil
  if msg then ns.Print(msg) end
  changed()
end

local function limitFor(name)
  local e = ns.Shopping.Get().items[name]
  local over = (tonumber(ns.db.settings.maxOverPct) or 25) / 100
  return e.unit * (1 + over), e.unit
end

local function isCommodity(itemID)
  if C_AuctionHouse.GetItemCommodityStatus and Enum.ItemCommodityStatus then
    local ok, status = pcall(C_AuctionHouse.GetItemCommodityStatus, itemID)
    if ok and status == Enum.ItemCommodityStatus.Item then return false end
    if ok and status == Enum.ItemCommodityStatus.Commodity then return true end
  end
  return true -- crafting reagents stack, so assume commodity when the game won't say
end

-- First click: get a live quote for the next item.
function Buyer.Next()
  if not ns.Scanner.atAH then ns.Print("Open the auction house first."); return end
  if Buyer.state == "quoting" or Buyer.state == "buying" then return end
  local name = ns.Shopping.NextToBuy()
  if not name then ns.Print("Nothing left to buy on the auction house."); fail(); return end
  local itemID = ns.db.ids[name]
  if not itemID then
    ns.Print(name .. " hasn't been seen on the auction house yet. Searching for it now; click Get price again.")
    ns.UI.SearchAH(name)
    return
  end
  local qty = ns.Shopping.Left(name)
  local listed = ns.Prices.Listed(name)
  if listed and listed > 0 and qty > listed then qty = listed end
  Buyer.current = { name = name, itemID = itemID, qty = qty }
  Buyer.state = "quoting"
  if isCommodity(itemID) then
    Buyer.current.kind = "commodity"
    local ok, err = pcall(C_AuctionHouse.StartCommoditiesPurchase, itemID, qty)
    if not ok then fail("The auction house refused: " .. tostring(err)) end
  else
    Buyer.current.kind, Buyer.current.qty = "item", 1
    local key = C_AuctionHouse.MakeItemKey(itemID)
    Buyer.current.itemKey = key
    local sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } }
    local ok, err = pcall(C_AuctionHouse.SendSearchQuery, key, sorts, false)
    if not ok then fail("The auction house refused: " .. tostring(err)) end
  end
  changed()
end

local function quoted(unit, total)
  local c = Buyer.current
  c.unit, c.total = unit, total
  local limit = limitFor(c.name)
  Buyer.state = (unit <= limit) and "confirm" or "pricey"
  changed()
end

ns.On("COMMODITY_PRICE_UPDATED", function(unit, total)
  if Buyer.state == "quoting" and Buyer.current and Buyer.current.kind == "commodity" then quoted(unit, total) end
end)

ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
  if Buyer.current and Buyer.current.kind == "commodity" and Buyer.state ~= "buying" then
    fail("Price unavailable for " .. Buyer.current.name .. " (sold out or changed). Scan again and retry.")
  end
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(itemKey)
  local c = Buyer.current
  if Buyer.state ~= "quoting" or not c or c.kind ~= "item" or not itemKey or itemKey.itemID ~= c.itemID then return end
  local ok, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, 1)
  if not ok or not info or not info.buyoutAmount then
    fail("No buyout listing for " .. c.name .. ".")
    return
  end
  c.auctionID = info.auctionID
  quoted(info.buyoutAmount, info.buyoutAmount)
end)

-- Second click: buy at the quoted price.
function Buyer.Confirm()
  local c = Buyer.current
  if not c or (Buyer.state ~= "confirm" and Buyer.state ~= "pricey") then return end
  Buyer.state = "buying"
  local ok, err
  if c.kind == "commodity" then
    ok, err = pcall(C_AuctionHouse.ConfirmCommoditiesPurchase, c.itemID, c.qty)
  else
    ok, err = pcall(C_AuctionHouse.PlaceBid, c.auctionID, c.total)
  end
  if not ok then fail("Purchase failed: " .. tostring(err)) end
  changed()
end

function Buyer.Cancel()
  if Buyer.current and Buyer.current.kind == "commodity" and C_AuctionHouse.CancelCommoditiesPurchase then
    pcall(C_AuctionHouse.CancelCommoditiesPurchase)
  end
  fail()
end

function Buyer.SkipCurrent()
  local c = Buyer.current
  local name = c and c.name or ns.Shopping.NextToBuy()
  if name then ns.Shopping.Skip(name) end
  Buyer.Cancel()
end

local function done()
  if Buyer.state == "buying" then Buyer.state, Buyer.current = nil, nil; changed() end
end
ns.On("COMMODITY_PURCHASE_SUCCEEDED", function() C_Timer.After(0, done) end)
ns.On("AUCTION_HOUSE_PURCHASE_COMPLETED", function() C_Timer.After(0, done) end)
ns.On("COMMODITY_PURCHASE_FAILED", function() fail("Purchase failed (someone may have bought it first). Click Get price to retry.") end)
ns.On("AUCTION_HOUSE_CLOSED", function() Buyer.state, Buyer.current = nil, nil end)

-- Text for the main button.
function Buyer.ButtonText()
  local c = Buyer.current
  if Buyer.state == "quoting" then return "Getting live price…" end
  if Buyer.state == "buying" then return "Buying…" end
  if Buyer.state == "confirm" then
    return ("Buy %d× %s for %s"):format(c.qty, c.name, ns.Prices.Money(c.total))
  end
  if Buyer.state == "pricey" then
    local _, planned = limitFor(c.name)
    local pct = planned > 0 and math.floor((c.unit / planned - 1) * 100 + 0.5) or 0
    return ("Buy anyway? +%d%% over plan (%s each)"):format(pct, ns.Prices.Money(c.unit))
  end
  local name = ns.Shopping.NextToBuy()
  return name and ("Get price: %d× %s"):format(ns.Shopping.Left(name), name) or "All bought"
end

function Buyer.Click()
  if Buyer.state == "confirm" or Buyer.state == "pricey" then Buyer.Confirm() else Buyer.Next() end
end
