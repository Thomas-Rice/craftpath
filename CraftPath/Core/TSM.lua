-- CraftPath: TradeSkillMaster as an optional price source (in game only).
--
-- When TSM is installed with its AppHelper data, CraftPath asks it, through TSM's public
-- in-game API (TSM_API), for:
--   * a price for items your own scans haven't seen this week (realm min buyout, then
--     realm market value, then the region's market average)
--   * how well an item sells across the region: sold per day and sale rate (the share of
--     listings that sell), which your own scans can't measure
-- Your own scans always come first. Nothing from TSM is saved or sent to the website.
-- Turn it off with /cpath tsm off.

local _, ns = ...
ns.TSM = ns.TSM or {}
local TSM = ns.TSM

local CACHE_SECONDS = 600
local cache = {} -- name -> { t = time(), price, how, perDay, rate, market, region }

local function enabled()
  return ns.db and ns.db.settings.tsm ~= false
end

function TSM.Available()
  local api = _G.TSM_API
  return type(api) == "table" and type(api.GetCustomPriceValue) == "function"
end

local function itemString(name)
  local id = ns.db and ns.db.ids[name]
  if not id and C_Item and C_Item.GetItemInfoInstant then
    local ok, got = pcall(C_Item.GetItemInfoInstant, name)
    if ok and type(got) == "number" then id = got end
  end
  return id and ("i:" .. id) or nil
end

-- One TSM value ("DBMarket", "DBRegionSoldPerDay", ...), or nil.
local function value(source, item)
  local ok, v = pcall(_G.TSM_API.GetCustomPriceValue, source, item)
  if ok and type(v) == "number" and v > 0 then return v end
  return nil
end

-- Everything TSM knows about an item (cached for 10 minutes), or nil.
function TSM.Info(name)
  if not (name and enabled() and TSM.Available()) then return nil end
  local now = time()
  local c = cache[name]
  if c and now - c.t < CACHE_SECONDS then return c.item and c or nil end
  local item = itemString(name)
  c = { t = now, item = item }
  if item then
    c.minBuyout = value("DBMinBuyout", item)
    c.market = value("DBMarket", item)
    c.region = value("DBRegionMarketAvg", item)
    c.regionSale = value("DBRegionSaleAvg", item)
    c.perDay = value("DBRegionSoldPerDay", item)
    c.rate = value("DBRegionSaleRate", item)
    if c.minBuyout then c.price, c.how = c.minBuyout, "TSM realm lowest"
    elseif c.market then c.price, c.how = c.market, "TSM realm market value"
    elseif c.region then c.price, c.how = c.region, "TSM region market value" end
  end
  cache[name] = c
  return item and c or nil
end

-- A price to use when your own scans have none: copper, and where it came from.
function TSM.Price(name)
  local c = TSM.Info(name)
  if c and c.price then return c.price, c.how end
end

-- How well it sells across the region: { perDay = n, rate = 0..1 } or nil.
function TSM.Sales(name)
  local c = TSM.Info(name)
  if not c or not (c.perDay or c.rate) then return nil end
  local rate = c.rate
  if rate and rate > 1 then rate = rate / 100 end -- some TSM versions give a percentage
  return { perDay = c.perDay, rate = rate }
end

function TSM.Forget() wipe(cache) end

-- /cpath tsm [on|off|item name]: switch it, or show what TSM says about an item.
function TSM.Slash(arg)
  arg = (arg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if arg == "off" or arg == "on" then
    ns.db.settings.tsm = arg == "on"
    TSM.Forget()
    ns.Print("TSM prices and sale rates " .. (arg == "on" and "on" or "off") .. ".")
    return
  end
  if not TSM.Available() then
    ns.Print("TradeSkillMaster isn't loaded, so CraftPath uses your own scans only.")
    return
  end
  -- slash text arrives lower case: "copper bar" -> "Copper Bar"
  local name = arg ~= "" and arg:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end) or "Copper Bar"
  if name:find(" Of ") then name = name:gsub(" Of ", " of ") end
  cache[name] = nil
  local c = TSM.Info(name)
  if not c then ns.Print("TSM: no item found called " .. name .. ".") return end
  local M = function(v) return v and ns.Prices.Money(v) or "-" end
  ns.Print(("TSM for %s (%s): lowest %s, market %s, region %s, region sale %s, sold/day %s, sale rate %s.%s"):format(
    name, c.item, M(c.minBuyout), M(c.market), M(c.region), M(c.regionSale), tostring(c.perDay), tostring(c.rate),
    enabled() and "" or " (off: /cpath tsm on)"))
end
