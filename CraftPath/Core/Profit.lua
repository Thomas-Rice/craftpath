-- CraftPath profit finder: what to craft today, at today's prices, to make money.
-- Pure Lua (no game API): the addon and the website run the same code.
--
-- For every recipe that makes something sellable it works out:
--   cost      materials at the cheapest of auction house, vendor, or crafting them yourself
--   sale      the auction price now, after the auction house's cut
--   safe      the sale at the lowest daily price of the last week (prices move about)
--   vendor    what a vendor pays for it: profit there is guaranteed
-- and, for recipes you don't know, how to get them and how many crafts pay that back.

local _, ns = ...
ns.Profit = ns.Profit or {}
local Profit = ns.Profit
local Recipes = ns.Recipes

Profit.AH_CUT = 0.05      -- the auction house keeps 5% of the sale
Profit.SWING = 0.25       -- (high - low) / median above this = "prices jump around"

-- opts:
--   professions  list of { prof = name, skill = number or nil, known = set or nil }
--                (skill nil = you don't have the profession)
--   includeUnknown  true to also list recipes you don't know / professions you don't have
--   ahPrice(name), vendorPrice(name), sellPrice(name), listed(name), stats(name) -> {low, median, high, days}
--   faction, allowFavor
-- Returns a list sorted by profit, best first: see the fields set in `entry` below.
function Profit.Find(opts)
  local ahPrice = opts.ahPrice or function() return nil end
  local vendorPrice = opts.vendorPrice or function() return nil end
  local itemSell = ns.RawData.ItemSell or {}
  local sellPrice = opts.sellPrice or function(n) return itemSell[n] end
  local listed = opts.listed or function() return nil end
  local stats = opts.stats or function() return nil end
  local cut = 1 - Profit.AH_CUT

  -- Who can make what: recipes of every listed profession, and whether you can craft them now.
  local all, producers = {}, {}
  for _, p in ipairs(opts.professions) do
    local data = Recipes.Load(p.prof)
    if data then
      local learner = ns.Planner.Learner({
        profession = p.prof, ahPrice = ahPrice, vendorPrice = vendorPrice, known = p.known or {},
        faction = opts.faction, allowFavor = opts.allowFavor, vendorWhere = opts.vendorWhere,
      }, data.list)
      for _, r in ipairs(data.list) do
        local knownIt
        if p.skill then
          if p.known and next(p.known) then
            knownIt = p.known[r.name] or r.source == "A"
          else
            -- Profession window not opened yet: assume trainer/automatic recipes up to your skill.
            knownIt = (r.source == "A" or r.source == "T") and r.learn <= p.skill
          end
        end
        local item = { r = r, prof = p.prof, skill = p.skill, known = knownIt and true or false,
          canCraft = knownIt and p.skill and p.skill >= r.learn, learner = learner }
        all[#all + 1] = item
        producers[r.name] = producers[r.name] or {}
        table.insert(producers[r.name], item)
      end
    end
  end

  -- Cheapest way to get one of an item. Crafting counts only with recipes you can make now
  -- (or any recipe, when looking at ones you don't know).
  local memo = {}
  local function unitCost(name, depth, anyRecipe)
    local key = name .. (anyRecipe and "*" or "")
    local m = memo[key]
    if m then return m.cost, m.how end
    local best, how = math.huge, nil
    local a = ahPrice(name)
    if a and a < best then best, how = a, "ah" end
    local v = vendorPrice(name) or ns.RawData.VendorItems[name] or (ns.RawData.VendorGoods or {})[name]
    if v and v < best then best, how = v, "vendor" end
    if (depth or 0) < 4 and producers[name] then
      memo[key] = { cost = best, how = how } -- guard against cycles while we look deeper
      for _, it in ipairs(producers[name]) do
        if it.canCraft or anyRecipe then
          local total = 0
          for _, g in ipairs(it.r.reagents) do
            total = total + g.qty * (unitCost(g.name, (depth or 0) + 1, anyRecipe))
            if total == math.huge then break end
          end
          local per = total / it.r.makes
          if per < best then best, how = per, "craft" end
        end
      end
    end
    memo[key] = { cost = best, how = how }
    return best, how
  end

  local out = {}
  for _, it in ipairs(all) do
    local r = it.r
    local show = it.canCraft or opts.includeUnknown
    local price = show and ahPrice(r.name)
    local vend = show and sellPrice(r.name)
    if price or vend then
      local anyRecipe = not it.canCraft
      local cost, mats = 0, {}
      for _, g in ipairs(r.reagents) do
        local c, how = unitCost(g.name, 0, anyRecipe)
        mats[#mats + 1] = { name = g.name, qty = g.qty, unit = c, how = how }
        cost = cost + g.qty * c
        if cost == math.huge then break end
      end
      if cost < math.huge then
        cost = cost / r.makes
        local st = stats(r.name)
        local sale = price and price * cut or nil
        local safeSale = sale
        if st and st.low and price then safeSale = math.min(price, st.low) * cut end
        local profit = sale and (sale - cost) or nil
        local safe = safeSale and (safeSale - cost) or nil
        local vendorProfit = vend and (vend - cost) or nil
        if (profit and profit > 0) or (vendorProfit and vendorProfit > 0) then
          local entry = {
            name = r.name, profession = it.prof, recipe = r, makes = r.makes,
            cost = cost, price = price, sale = sale, profit = profit, safeProfit = safe,
            vendorSell = vend, vendorProfit = vendorProfit,
            margin = (profit and cost > 0) and profit / cost or nil,
            listed = listed(r.name), stats = st,
            swings = st and st.median and st.median > 0 and st.days >= 2 and (st.high - st.low) / st.median > Profit.SWING or false,
            known = it.known, canCraft = it.canCraft and true or false, skill = it.skill,
            hasProfession = it.skill ~= nil, materials = mats,
            levelsYou = it.skill and Recipes.SkillUpChance(r, it.skill) > 0 or false,
          }
          if not it.canCraft then
            local learnCost, info = it.learner(r)
            entry.learn = info
            entry.learnCost = learnCost
            if not info.how and (r.source == "G" or r.source == "N") then
              info.how = r.source == "G" and "goblin" or "gnomish"
            end
            entry.needSkill = r.learn
            local per = math.max(safe or 0, vendorProfit or 0, profit or 0)
            if learnCost and learnCost > 0 and per > 0 then entry.payback = math.ceil(learnCost / per) end
          end
          entry.best = math.max(safe or -math.huge, vendorProfit or -math.huge)
          out[#out + 1] = entry
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.canCraft ~= b.canCraft then return a.canCraft end
    return a.best > b.best
  end)
  return out
end
