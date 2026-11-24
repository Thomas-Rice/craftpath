-- CraftPath: what to do with what you've crafted while levelling. For each crafted item in
-- your bags: keep it (a later step of your route uses it), put it on the auction house (it
-- sells, and for clearly more than a vendor pays), or sell it to a vendor.
-- Shown on the Route tab, in item tooltips, and by /cpath sell.

local _, ns = ...
ns.Sell = ns.Sell or {}
local Sell = ns.Sell

-- The auction has to beat the vendor by this much to be worth listing (time, deposit, risk).
local MIN_GAIN, MIN_GAIN_SHARE = 100, 0.2 -- at least 1 silver each and 20% over the vendor price

-- What to do with one of these. nil if it isn't something your professions craft.
--   { how = "keep" | "auction" | "vendor" | "none", vendor = copper, auction = copper you'd
--     get after the cut, listAt = suggested price, keep = { qty, text } }
function Sell.Advice(name, profession)
  if not name then return nil end
  local crafted = false
  for _, prof in ipairs(profession and { profession } or ns.Recipes.Professions()) do
    local data = ns.Recipes.Load(prof)
    if data and data.byName[name] and (profession or (ns.Game.GetSkill(prof) or 0) > 0) then crafted = true break end
  end
  if not crafted then return nil end

  local a = { vendor = ns.SellPrice(name) }
  local keep = ns.Keep and ns.Keep.For(name)
  if keep then a.keep = keep end

  local now = ns.Prices.AH(name)
  if now then
    local st = ns.Prices.Stats(name)
    local safe = (st and st.low and st.low < now) and st.low or now
    local listed = ns.Prices.Listed(name) or 0
    local sales = ns.TSM and ns.TSM.Sales(name)
    local sells = listed >= ns.RESALE_MIN_LISTED
    if sales and sales.perDay then sells = sales.perDay >= 1 end
    if sells then
      a.auction = math.floor(safe * 0.95)
      a.listAt = now > 1 and (now - 1) or now
      a.listed, a.perDay = listed, sales and sales.perDay
    end
  end
  local v = a.vendor or 0
  if a.auction and a.auction >= v + math.max(MIN_GAIN, v * MIN_GAIN_SHARE) then
    a.how, a.each = "auction", a.auction
  elseif v > 0 then
    a.how, a.each = "vendor", v
  else
    a.how = "none"
  end
  a.sellHow = a.how -- for any you have beyond what the route needs
  if keep then a.how = "keep" end
  return a
end

-- Your crafts in your bags (for a profession, or all of yours), with advice, best value first.
function Sell.InBags(profession)
  local out = {}
  for _, prof in ipairs(profession and { profession } or ns.Recipes.Professions()) do
    local data = ns.Recipes.Load(prof)
    if data and (profession or (ns.Game.GetSkill(prof) or 0) > 0) then
      for _, r in ipairs(data.list) do
        local n = ns.Game.Bags(r.name)
        if n > 0 and not out[r.name] then
          local a = Sell.Advice(r.name, prof)
          if a then
            a.name, a.count = r.name, n
            -- keep only what the route needs; the rest can go
            if a.keep then a.spare = math.max(0, n - a.keep.qty) end
            out[r.name] = a
          end
        end
      end
    end
  end
  local list = {}
  for _, a in pairs(out) do list[#list + 1] = a end
  local rank = { auction = 1, vendor = 2, keep = 3, none = 4 }
  table.sort(list, function(x, y)
    if rank[x.how] ~= rank[y.how] then return rank[x.how] < rank[y.how] end
    return (x.each or 0) * x.count > (y.each or 0) * y.count
  end)
  return list
end

-- One line of advice, for tooltips and chat.
function Sell.Text(a)
  local M = ns.Prices.Money
  if a.how == "keep" then
    local t = "keep " .. a.keep.qty .. " (" .. ns.Keep.Text(a.keep) .. ")"
    if (a.spare or 0) > 0 and a.sellHow ~= "none" then
      t = t .. (", %s the other %d"):format(a.sellHow == "auction" and "auction" or "vendor", a.spare)
    end
    return t
  elseif a.how == "auction" then
    return ("auction it: about %s each after the cut (list at %s; vendor %s)"):format(
      M(a.auction), M(a.listAt), a.vendor and M(a.vendor) or "nothing")
  elseif a.how == "vendor" then
    return ("sell to a vendor: %s each%s"):format(M(a.vendor),
      a.auction and (" (auction ~" .. M(a.auction) .. ", not worth listing)") or "")
  end
  return "no vendor or auction value"
end

-- /cpath sell: what to do with the crafts in your bags, in chat.
function Sell.Report()
  local list = Sell.InBags()
  if #list == 0 then ns.Print("No crafts from your professions in your bags.") return end
  local M = ns.Prices.Money
  local vendorTotal, auctionTotal = 0, 0
  for _, a in ipairs(list) do
    if a.how == "vendor" then vendorTotal = vendorTotal + a.vendor * a.count end
    if a.how == "auction" then auctionTotal = auctionTotal + a.auction * a.count end
    ns.Print(("%dx %s: %s"):format(a.count, a.name, Sell.Text(a)))
  end
  ns.Print(("Vendor: %s. Auction house: about %s after the cut."):format(M(vendorTotal), M(auctionTotal)))
end

-- At a merchant: a heads-up when some of your crafts are worth more on the auction house.
ns.On("MERCHANT_SHOW", function()
  if not ns.db or ns.db.settings.sellHints == false then return end
  local n = 0
  for _, a in ipairs(Sell.InBags()) do if a.how == "auction" then n = n + 1 end end
  if n > 0 then
    ns.Print(("%d of your crafts are worth more on the auction house than here. /cpath sell lists them."):format(n))
  end
end)

-- A snapshot of what you have, saved when you reload or log out (CraftPathDB.stock), so the
-- advice can also be worked out outside the game. Only items your professions craft or use,
-- and only counts: { [character] = { t = time, items = { [name] = { bags, bank, mail } } } }.
function Sell.SaveStock()
  if not ns.db then return end
  local names = {}
  for _, prof in ipairs(ns.Recipes.Professions()) do
    if (ns.Game.GetSkill(prof) or 0) > 0 then
      local data = ns.Recipes.Load(prof)
      for _, r in ipairs(data and data.list or {}) do
        names[r.name] = true
        for _, g in ipairs(r.reagents) do names[g.name] = true end
      end
    end
  end
  local items = {}
  for name in pairs(names) do
    local bags = ns.Game.Bags(name)
    local bank = math.max(0, ns.Game.BagsAndBank(name) - bags)
    local mail = ns.Game.Mail(name)
    if bags + bank + mail > 0 then items[name] = { bags, bank, mail } end
  end
  ns.db.stock = ns.db.stock or {}
  ns.db.stock[ns.Ledger and ns.Ledger.CharKey and ns.Ledger.CharKey()
    or ((UnitName and UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or ""))] = { t = time(), items = items }
end

ns.On("PLAYER_LOGOUT", function() pcall(Sell.SaveStock) end) -- also fires on /reload
