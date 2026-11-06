-- CraftPath: auction house scanning for Forever's retail-style auction house.
--   * Passive: any search you run on the Buy tab records the lowest price of what it shows.
--   * Shopping-list scan: searches each item the plan needs, one by one (like Auctionator lists).
--   * Full scan: C_AuctionHouse.ReplicateItems (Blizzard allows one every 15 minutes).
-- CraftPath never buys, posts or cancels anything; purchases stay in Blizzard's window.

local _, ns = ...
ns.Scanner = {}
local Scanner = ns.Scanner

local FULL_SCAN_COOLDOWN = 15 * 60
local QUERY_TIMEOUT = 6

Scanner.atAH = false
Scanner.queue = nil
Scanner.status = ""

local function setStatus(text)
  Scanner.status = text
  if ns.UI and ns.UI.SetStatus then ns.UI.SetStatus(text) end
end

local function itemNameFromKey(itemKey)
  if not itemKey then return nil end
  local ok, info = pcall(C_AuctionHouse.GetItemKeyInfo, itemKey)
  if ok and info and info.itemName then return info.itemName end
  if C_Item and C_Item.GetItemNameByID then
    local ok2, n = pcall(C_Item.GetItemNameByID, itemKey.itemID)
    if ok2 and n then return n end
  end
  if C_Item and C_Item.GetItemInfo then
    local ok3, n = pcall(C_Item.GetItemInfo, itemKey.itemID)
    if ok3 and n then return n end
  end
  return nil
end

-- Browse results whose item name isn't cached yet wait here for ITEM_KEY_ITEM_INFO_RECEIVED.
local pendingKeys = {}

local function recordBrowseResult(res)
  if not res or not res.itemKey or not res.minPrice then return nil end
  local name = itemNameFromKey(res.itemKey)
  if name then
    ns.Prices.Record(name, res.minPrice, res.totalQuantity, res.itemKey.itemID)
    ns.Game.NoteRecipeItem(name, res.minPrice)
  else
    pendingKeys[res.itemKey.itemID] = res
  end
  return name
end

ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", function(itemID)
  local res = pendingKeys[itemID]
  if res then
    pendingKeys[itemID] = nil
    recordBrowseResult(res)
  end
end)

local function onBrowseResults(results)
  local names = {}
  for _, res in ipairs(results or {}) do
    local n = recordBrowseResult(res)
    if n then names[n] = true end
  end
  if Scanner.queue and Scanner.queue.waiting then Scanner.OnQueryResults(names) end
end

ns.On("AUCTION_HOUSE_SHOW", function()
  Scanner.atAH = true
  ns.Prices.BeginScan()
  if ns.UI and ns.UI.OnAuctionHouse then ns.UI.OnAuctionHouse(true) end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
  Scanner.atAH = false
  if Scanner.queue then Scanner.queue = nil; setStatus("Scan stopped: auction house closed.") end
  if ns.UI and ns.UI.OnAuctionHouse then ns.UI.OnAuctionHouse(false) end
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
  local ok, results = pcall(C_AuctionHouse.GetBrowseResults)
  if ok then onBrowseResults(results) end
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
  onBrowseResults(added)
end)

---------------------------------------------------------------------------
-- Shopping-list scan
---------------------------------------------------------------------------

local function sendQuery(name)
  local query = {
    searchString = name,
    sorts = { { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false } },
    filters = {},
    itemClassFilters = {},
  }
  local ok, err = pcall(C_AuctionHouse.SendBrowseQuery, query)
  return ok, err
end

local function nextQuery()
  local q = Scanner.queue
  if not q then return end
  if not Scanner.atAH then Scanner.queue = nil; return end
  q.i = q.i + 1
  local name = q.items[q.i]
  if not name then
    Scanner.queue = nil
    setStatus(("Scanned %d items."):format(#q.items))
    if q.onDone then q.onDone() end
    return
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady and not C_AuctionHouse.IsThrottledMessageSystemReady() then
    q.i = q.i - 1
    q.waitingThrottle = true
    -- Fallback in case the "ready" event never arrives.
    C_Timer.After(1.5, function()
      if Scanner.queue == q and q.waitingThrottle then q.waitingThrottle = false; nextQuery() end
    end)
    return
  end
  setStatus(("Scanning %d/%d: %s"):format(q.i, #q.items, name))
  q.waiting, q.current, q.token = true, name, (q.token or 0) + 1
  local token = q.token
  local ok = sendQuery(name)
  if not ok then
    q.waiting = false
    setStatus("The auction house refused the search. Click an item on the list to search it yourself.")
    Scanner.queue = nil
    return
  end
  C_Timer.After(QUERY_TIMEOUT, function()
    if Scanner.queue == q and q.waiting and q.token == token then
      q.waiting = false
      ns.Prices.RecordNone(name)
      nextQuery()
    end
  end)
end

function Scanner.OnQueryResults(names)
  local q = Scanner.queue
  if not q or not q.waiting then return end
  q.waiting = false
  if not names[q.current] then ns.Prices.RecordNone(q.current) end
  C_Timer.After(0.3, nextQuery)
end

ns.On("AUCTION_HOUSE_THROTTLED_SYSTEM_READY", function()
  local q = Scanner.queue
  if q and q.waitingThrottle then q.waitingThrottle = false; nextQuery() end
end)

-- Searches a list of item names one at a time.
function Scanner.ScanItems(items, onDone)
  if not Scanner.atAH then ns.Print("Open the auction house first."); return end
  if Scanner.queue then ns.Print("A scan is already running."); return end
  if #items == 0 then return end
  Scanner.queue = { items = items, i = 0, onDone = onDone }
  nextQuery()
end

-- Every reagent the current profession could use, so the planner can compare routes.
function Scanner.ScanShoppingList()
  local prof = ns.db.settings.profession
  local items = ns.Recipes.AllReagents(prof)
  -- Recipe items for schematics/plans the planner might buy.
  local data = ns.Recipes.Load(prof)
  local prefixes = ns.RawData.RecipePrefixes[prof] or {}
  for _, r in ipairs(data.list) do
    if (r.source == "R" or r.source == "V") and not (ns.db.known[prof] or {})[r.name] then
      items[#items + 1] = prefixes[1] .. r.name
    end
  end
  -- Vendor-sold reagents don't need an AH search.
  local filtered = {}
  for _, name in ipairs(items) do
    if not ns.RawData.VendorItems[name] then filtered[#filtered + 1] = name end
  end
  Scanner.ScanItems(filtered, function() if ns.UI then ns.UI.Replan() end end)
end

---------------------------------------------------------------------------
-- Full scan (ReplicateItems)
---------------------------------------------------------------------------

function Scanner.FullScan()
  if not Scanner.atAH then ns.Print("Open the auction house first."); return end
  if not C_AuctionHouse.ReplicateItems then ns.Print("Full scans aren't available on this client."); return end
  local wait = FULL_SCAN_COOLDOWN - (time() - (ns.db.lastFullScan or 0))
  if wait > 0 then
    ns.Print(("Blizzard allows one full scan every 15 minutes. Try again in %d min, or use the shopping-list scan."):format(math.ceil(wait / 60)))
    return
  end
  Scanner.fullPending = true
  setStatus("Full scan requested…")
  local ok, err = pcall(C_AuctionHouse.ReplicateItems)
  if not ok then
    Scanner.fullPending = false
    setStatus("Full scan failed: " .. tostring(err))
    return
  end
  ns.db.lastFullScan = time()
end

ns.On("REPLICATE_ITEM_LIST_UPDATE", function()
  if not Scanner.fullPending then return end
  Scanner.fullPending = false
  local total = C_AuctionHouse.GetNumReplicateItems() or 0
  ns.Prices.BeginScan()
  local best = {} -- itemID -> { unit, qty, name }
  local i = 0
  local function chunk()
    local stop = math.min(total, i + 400)
    for idx = i, stop - 1 do
      local name, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
      if itemID and buyout and buyout > 0 and count and count > 0 then
        local unit = buyout / count
        local b = best[itemID]
        if not b then best[itemID] = { unit = unit, qty = count, name = name }
        else
          b.qty = b.qty + count
          if unit < b.unit then b.unit = unit end
          b.name = b.name or name
        end
      end
    end
    i = stop
    setStatus(("Reading full scan: %d/%d"):format(i, total))
    if i < total then
      C_Timer.After(0, chunk)
    else
      local named, waiting = 0, 0
      for itemID, b in pairs(best) do
        if b.name then
          ns.Prices.Record(b.name, b.unit, b.qty, itemID); named = named + 1
        elseif Item and Item.CreateFromItemID then
          waiting = waiting + 1
          local item = Item:CreateFromItemID(itemID)
          item:ContinueOnItemLoad(function()
            ns.Prices.Record(item:GetItemName(), b.unit, b.qty, itemID)
          end)
        end
      end
      setStatus(("Full scan done: %d auctions, %d items."):format(total, named + waiting))
      if ns.UI then ns.UI.Replan() end
    end
  end
  chunk()
end)
