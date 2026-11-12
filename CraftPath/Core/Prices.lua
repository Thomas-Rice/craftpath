-- CraftPath: price store. Auction prices come from scans, vendor prices from merchants.

local _, ns = ...
ns.Prices = {}
local Prices = ns.Prices

local MAX_AGE = 7 * 24 * 3600 -- ignore auction prices older than a week

function Prices.AH(name)
  local e = ns.db and ns.db.prices[name]
  if not e or not e.p then return nil end
  if time() - (e.t or 0) > MAX_AGE then return nil end
  return e.p
end

-- How many were listed in the last scan that saw the item.
function Prices.Listed(name)
  local e = ns.db and ns.db.prices[name]
  return e and e.p and e.q or nil
end

function Prices.Vendor(name)
  return ns.db and ns.db.vendor[name]
end

function Prices.Info(name)
  return ns.db and ns.db.prices[name]
end

-- Starts a new scan session; within a session the lowest price seen wins.
function Prices.BeginScan()
  ns.db.scanId = (ns.db.scanId or 0) + 1
  return ns.db.scanId
end

function Prices.Record(name, unitPrice, quantity, itemID)
  if not name or name == "" or not unitPrice or unitPrice <= 0 then return end
  local db = ns.db
  local scan = db.scanId
  local e = db.prices[name]
  if e and e.scan == scan and e.p and e.p <= unitPrice then
    e.q = (e.q or 0) + (quantity or 0)
    return
  end
  db.prices[name] = { p = math.floor(unitPrice + 0.5), q = quantity, id = itemID, t = time(), scan = scan }
  if itemID then db.ids[name] = itemID end
  Prices.Remember(name, unitPrice)
end

-- Price history: the lowest price seen each day, for items any recipe uses or makes, kept
-- for two weeks. The profit finder uses it to tell steady prices from spikes.
local HISTORY_DAYS = 14
local tracked
local function isTracked(name)
  if not tracked then
    tracked = {}
    for _, prof in ipairs(ns.Recipes.Professions()) do
      local data = ns.Recipes.Load(prof)
      local prefixes = (ns.RawData.RecipePrefixes or {})[prof] or {}
      for _, r in ipairs(data.list) do
        tracked[r.name] = true
        for _, g in ipairs(r.reagents) do tracked[g.name] = true end
        for _, pre in ipairs(prefixes) do tracked[pre .. r.name] = true end
      end
    end
  end
  return tracked[name]
end

function Prices.Remember(name, unitPrice)
  if not isTracked(name) then return end
  local db = ns.db
  db.history = db.history or {}
  local day = math.floor(time() / 86400)
  local h = db.history[name]
  if not h then h = {}; db.history[name] = h end
  local last = h[#h]
  if last and last.d == day then
    if unitPrice < last.p then last.p = math.floor(unitPrice + 0.5) end
  else
    h[#h + 1] = { d = day, p = math.floor(unitPrice + 0.5) }
    while #h > HISTORY_DAYS do table.remove(h, 1) end
  end
end

-- Lowest, middle and highest daily price over the last `days` days (default 7), and how
-- many days had a price. nil when the item hasn't been seen.
function Prices.Stats(name, days)
  local h = ns.db and ns.db.history and ns.db.history[name]
  if not h or #h == 0 then return nil end
  local since = math.floor(time() / 86400) - (days or 7)
  local list = {}
  for _, e in ipairs(h) do if e.d > since then list[#list + 1] = e.p end end
  if #list == 0 then return nil end
  table.sort(list)
  local mid = list[math.floor((#list + 1) / 2)]
  return { low = list[1], median = mid, high = list[#list], days = #list }
end

-- Marks an item as searched but not listed, so it shows as "none on AH".
function Prices.RecordNone(name)
  local e = ns.db.prices[name]
  if e and e.scan == ns.db.scanId and e.p then return end
  ns.db.prices[name] = { p = nil, t = time(), scan = ns.db.scanId, none = true }
end

function Prices.RecordVendor(name, unitPrice)
  if name and unitPrice and unitPrice > 0 then ns.db.vendor[name] = unitPrice end
end

function Prices.AgeText(name)
  local e = ns.db.prices[name]
  if not e or not e.t then return "never" end
  local age = time() - e.t
  if age < 3600 then return math.max(1, math.floor(age / 60)) .. "m" end
  if age < 86400 then return math.floor(age / 3600) .. "h" end
  return math.floor(age / 86400) .. "d"
end

function Prices.Money(c)
  if not c then return "—" end
  if GetCoinTextureString then return GetCoinTextureString(math.floor(c + 0.5)) end
  return ns.Planner.Money(c)
end
