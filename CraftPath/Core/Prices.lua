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
  if not name or not unitPrice or unitPrice <= 0 then return end
  local db = ns.db
  local scan = db.scanId
  local e = db.prices[name]
  if e and e.scan == scan and e.p and e.p <= unitPrice then
    e.q = (e.q or 0) + (quantity or 0)
    return
  end
  db.prices[name] = { p = math.floor(unitPrice + 0.5), q = quantity, id = itemID, t = time(), scan = scan }
  if itemID then db.ids[name] = itemID end
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
