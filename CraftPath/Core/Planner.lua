-- CraftPath planner: cheapest expected-gold route between two skill levels.
-- Pure Lua 5.1 (no game API) so it can be unit-tested and later ported to the website.
--
-- How it works
--   * Each craft of recipe r at skill s gives a point with chance p(r, s) (Classic rule).
--     Expected gold for that point = (cost of one craft) / p.
--   * Cost of a reagent = cheapest of: auction house, NPC vendor, or crafting it yourself
--     from a recipe you can already use at that skill (recursively).
--   * Dynamic programming over skill points picks the cheapest recipe for every point.
--     Recipes that cost gold to learn (schematics/plans) are charged once per stretch of use.
--   * The shopping list then replays the route in order, so items you make along the way
--     (blasting powder, bolts, grinding stones...) are used up before anything is bought.

local _, ns = ...
ns.Planner = ns.Planner or {}
local Planner = ns.Planner
local Recipes = ns.Recipes

local INF = math.huge

local function ceil(x) return math.ceil(x - 1e-9) end

-- Options:
--   profession, from, to             skill range (from = current skill)
--   ahPrice(name) -> copper|nil      lowest auction price per item
--   vendorPrice(name) -> copper|nil  price at an NPC vendor (reagents and recipe items)
--   known = { [recipeName]=true }    recipes the character already knows
--   allowRecipeItems (default true)  consider schematics/plans bought from AH or vendors
--   allowFavor (default true)        consider Merchant's Favor recipes (no gold)
--   spec = "goblin"|"gnomish"|nil    engineering specialisation
--   bonus = 0..0.2                   extra skill-up chance (Legacy "Working Overtime")
--   owned(name) -> count             items already in bags/bank
--   charLevel                        if set, the target is capped to what can be trained
--   listed(name) -> count|nil        how many are on the auction house (for "not enough listed")
--   learnOverride = { [recipe]=skill } real learn skill seen at a trainer
--   trainerOffers = { [recipe]=skill } everything a trainer listed; trainer recipes it didn't
--                                      list (up to the highest skill it teaches) are left out
local planOnce

-- Plans, using what you already own first (opts.useOwned, default on):
--   1. price owned items at 0 and plan;
--   2. where the route needs more than you own, charge the market price for the share it
--      doesn't cover, and plan again; repeat until the route settles (a few passes).
function Planner.Plan(opts)
  if opts.useOwned == false or not opts.owned then return planOnce(opts, nil) end
  -- Using stock is a quantity problem (the first 40 Heavy Stone are free, the 41st isn't),
  -- so try a few routes and keep the one with the lowest real gold cost. The shopping list
  -- always uses your stock first and charges market price for the rest, so plan.total is
  -- the gold you'd actually spend.
  local ownedCache = {}
  local function ownedOf(name)
    local n = ownedCache[name]
    if n == nil then n = opts.owned(name) or 0; ownedCache[name] = n end
    return n
  end
  local function flat(f) return function(name) return ownedOf(name) > 0 and f or 1 end end

  local best
  local function consider(p)
    if p.error then return end
    if not best or p.total < best.total - 0.5 or (math.abs(p.total - best.total) <= 0.5 and #p.steps < #best.steps) then
      best = p
    end
  end
  local free = planOnce(opts, flat(0))
  if free.error then return planOnce(opts, nil) end
  consider(free)
  consider(planOnce(opts, nil))

  -- Items the all-free route wants more of than you have: find, per item, the price at
  -- which the route uses about what you own (a binary search, 6 passes each, max 3 items).
  local demand = free.demand or {}
  local contested = {}
  for name, have in pairs(ownedCache) do
    if have > 0 and (demand[name] or 0) > have then contested[#contested + 1] = name end
  end
  table.sort(contested, function(a, b) return (demand[a] or 0) > (demand[b] or 0) end)
  local factor = {}
  local function priced(name)
    if ownedOf(name) <= 0 then return 1 end
    return factor[name] or 0
  end
  for i = 1, math.min(3, #contested) do
    local name, have = contested[i], ownedOf(contested[i])
    local lo, hi = 0, 1
    for _ = 1, 6 do
      local mid = (lo + hi) / 2
      factor[name] = mid
      local p = planOnce(opts, priced)
      consider(p)
      if ((p.demand or {})[name] or 0) > have then lo = mid else hi = mid end
    end
    factor[name] = hi
    consider(planOnce(opts, priced))
  end  return best
end

planOnce = function(opts, ownedFactor)
  local data = Recipes.Load(opts.profession)
  if not data then return { error = "Unknown profession: " .. tostring(opts.profession) } end

  local from = math.max(1, math.floor(opts.from or 1))
  local to = math.min(300, math.floor(opts.to or 300))
  local notes = {}

  if opts.charLevel then
    local cap = 0
    for _, rank in ipairs(ns.RawData.Ranks) do
      if opts.charLevel >= rank.level then cap = rank.cap end
    end
    if to > cap then
      notes[#notes + 1] = ("Level %d can train up to %d skill, so the plan stops at %d."):format(opts.charLevel, cap, cap)
      to = cap
    end
  end
  if to <= from then return { error = "Target skill must be above current skill.", from = from, to = to, notes = notes } end

  local ahPrice = opts.ahPrice or function() return nil end
  local vendorPrice = opts.vendorPrice or function() return nil end
  local known = opts.known or {}
  local allowRecipeItems = opts.allowRecipeItems ~= false
  local allowFavor = opts.allowFavor ~= false
  local bonus = opts.bonus or 0
  local prefixes = ns.RawData.RecipePrefixes[opts.profession] or {}

  -- Trainer-confirmed learn skills replace the data's estimates (copies, so the cache is untouched).
  local list = data.list
  if opts.learnOverride and next(opts.learnOverride) then
    list = {}
    for i, r in ipairs(data.list) do
      local learn = opts.learnOverride[r.name]
      if learn and learn ~= r.learn then
        local c = {}
        for k, v in pairs(r) do c[k] = v end
        c.learn = learn
        if c.orange < learn then c.orange = learn end
        list[i] = c
      else
        list[i] = r
      end
    end
  end

  -- Which recipes produce which item (item name == recipe name in these professions).
  local producers = {}
  for _, r in ipairs(list) do
    producers[r.name] = producers[r.name] or {}
    table.insert(producers[r.name], r)
  end

  local trainerOffers, trainerMax = opts.trainerOffers, nil
  if trainerOffers then
    for _, skill in pairs(trainerOffers) do
      if not trainerMax or skill > trainerMax then trainerMax = skill end
    end
    -- Only trust the list if it looks complete (a filtered or partial list must not
    -- knock out recipes): it has to cover at least half the trainer recipes we expect.
    if trainerMax then
      local expected, covered = 0, 0
      for _, r in ipairs(list) do
        if r.source == "T" and r.learn <= trainerMax then
          expected = expected + 1
          if trainerOffers[r.name] then covered = covered + 1 end
        end
      end
      if expected == 0 or covered < expected / 2 then trainerMax = nil end
    end
  end

  -- Gold needed to learn a recipe; nil = can't be learned right now.
  local learnInfo = {}
  local vendorTable = (ns.RawData.RecipeVendors or {})[opts.profession] or {}
  local favorVendors = (ns.RawData.FavorVendors or {})[opts.profession] or {}
  local faction = opts.faction
  local function learnCost(r)
    local cached = learnInfo[r]
    if cached ~= nil then return cached.cost, cached end
    local info = { cost = nil }
    if known[r.name] then
      info.cost, info.how = 0, "known"
    elseif r.source == "A" then
      info.cost, info.how = 0, "auto"
    elseif r.source == "T" then
      if trainerMax and r.learn <= trainerMax and not trainerOffers[r.name] then
        info.how = "not at trainer" -- in the client data, but trainers don't teach it (yet)
      else
        info.cost, info.how = 0, "trainer"
      end
    elseif r.source == "F" then
      if allowFavor then info.cost, info.how = 0, "favor" end
    elseif r.source == "Q" then
      info.cost, info.how = 0, "quest"
    elseif r.source == "G" then
      if opts.spec == "goblin" then info.cost, info.how = 0, "trainer" end
    elseif r.source == "N" then
      if opts.spec == "gnomish" then info.cost, info.how = 0, "trainer" end
    elseif allowRecipeItems then
      -- R or V: buy the recipe item. Cheapest of vendor / auction house.
      for _, pre in ipairs(prefixes) do
        local item = pre .. r.name
        local v, a = vendorPrice(item), ahPrice(item)
        if v and (not info.cost or v < info.cost) then info.cost, info.how, info.item = v, "vendor", item end
        if a and (not info.cost or a < info.cost) then info.cost, info.how, info.item = a, "ah", item end
      end
      if not info.cost and r.source == "V" then
        local listPrice = vendorTable[r.name] and vendorTable[r.name].price
        local estimate = (ns.RawData.VendorRecipeEstimateBy or {})[opts.profession] or ns.RawData.VendorRecipeEstimate
        info.cost = listPrice or estimate
        info.how = listPrice and "vendor" or "vendor-est"
        info.item = prefixes[1] .. r.name
      end
    end
    -- Where to get it: a named vendor or trainer, a Merchant's Favor vendor, or a vendor you
    -- have visited that sold the recipe.
    if info.how ~= "known" and info.how ~= "auto" then
      local v = vendorTable[r.name]
      if r.source == "F" then
        info.where = favorVendors[faction] or favorVendors.Horde
        for _, pat in ipairs(ns.RawData.FavorCosts) do
          if r.name:find(pat[1]) then info.favor = pat[2]; break end
        end
      elseif v then
        if v.faction and faction and v.faction ~= faction then
          info.where = v.alt
          if not v.alt and (r.source == "V" or r.source == "Q") then
            info.cost, info.how = nil, "other faction" -- only the other faction can get it
          end
        else
          info.where = v
        end
      elseif info.item and opts.vendorWhere then
        info.where = opts.vendorWhere(info.item)
      end
    end
    learnInfo[r] = info
    return info.cost, info
  end

  -- Cheapest way to get one unit of an item while at skill s.
  local unitMemo = {}
  local function unitCost(name, s, visiting)
    local key = name .. "@" .. s
    local m = unitMemo[key]
    if m then return m.cost, m end
    local best = { cost = INF }
    local a = ahPrice(name)
    if a and a < best.cost then best = { cost = a, how = "ah" } end
    local v = vendorPrice(name) or ns.RawData.VendorItems[name]
    if v and v < best.cost then
      best = { cost = v, how = "vendor", est = not vendorPrice(name) and ns.RawData.VendorEstimates[name] or nil }
    end
    -- Items you own cost only the share of them you'd still have to buy.
    local f = ownedFactor and ownedFactor(name) or 1
    if f < 1 then
      if best.cost < INF then
        best = { cost = best.cost * f, how = best.how, est = best.est, market = best.cost, owned = true }
      elseif f == 0 then
        best = { cost = 0, how = "owned", owned = true } -- you have enough, even with no price seen
      end
    end
    visiting = visiting or {}
    if producers[name] and not visiting[name] then
      visiting[name] = true
      for _, r in ipairs(producers[name]) do
        local lc = learnCost(r)
        if s >= r.learn and lc == 0 then
          local total = 0
          for _, g in ipairs(r.reagents) do
            total = total + g.qty * (unitCost(g.name, s, visiting))
            if total == INF then break end
          end
          local per = total / r.makes
          if per < best.cost then best = { cost = per, how = "craft", recipe = r } end
          -- (owning some already is handled when the shopping list uses your stock first)
        end
      end
      visiting[name] = nil
    end
    -- Only memoise results computed without a cycle guard in play.
    if not next(visiting) then unitMemo[key] = best end
    return best.cost, best
  end

  local function craftCost(r, s)
    local total = 0
    for _, g in ipairs(r.reagents) do
      total = total + g.qty * (unitCost(g.name, s))
      if total == INF then return INF end
    end
    return total
  end

  local cppMemo = {}
  local function costPerPoint(r, s)
    local key = r.index * 1000 + s
    local m = cppMemo[key]
    if m then return m end
    local p = Recipes.PointsPerCraft(r, s, bonus)
    local c = INF
    if p > 0 then c = craftCost(r, s) / p end
    cppMemo[key] = c
    return c
  end

  -- Candidate recipes: usable somewhere in range and learnable.
  local candidates = {}
  for _, r in ipairs(list) do
    if r.grey > from and r.learn < to and learnCost(r) then candidates[#candidates + 1] = r end
  end

  local best, parent = {}, {}
  for s = from, to do best[s] = INF end
  best[from] = 0
  for s = from, to - 1 do
    if best[s] < INF then
      for _, r in ipairs(candidates) do
        if s >= r.learn and s < r.grey then
          local lc = learnCost(r)
          if lc == 0 then
            local c = costPerPoint(r, s)
            if c < INF and best[s] + c < best[s + 1] then
              best[s + 1] = best[s] + c
              parent[s + 1] = { from = s, recipe = r }
            end
          else
            local acc = best[s] + lc
            for t = s, math.min(to, r.grey) - 1 do
              local c = costPerPoint(r, t)
              if c == INF then break end
              acc = acc + c
              if acc < best[t + 1] then
                best[t + 1] = acc
                parent[t + 1] = { from = s, recipe = r }
              end
            end
          end
        end
      end
    end
  end

  if best[to] == INF then
    local reached = from
    for s = from, to do if best[s] < INF then reached = s end end
    return {
      error = ("No priced recipe can take you past skill %d."):format(reached),
      blocked = Planner.Blockers(list, reached, unitCost, learnCost, bonus),
      reached = reached, from = from, to = to, notes = notes,
    }
  end

  -- Rebuild the route, then merge neighbouring stretches of the same recipe.
  local segs = {}
  local s = to
  while s > from do
    local pnode = parent[s]
    table.insert(segs, 1, { recipe = pnode.recipe, from = pnode.from, to = s })
    s = pnode.from
  end
  local steps = {}
  for _, seg in ipairs(segs) do
    local last = steps[#steps]
    if last and last.recipe == seg.recipe and last.to == seg.from then
      last.to = seg.to
    else
      steps[#steps + 1] = { recipe = seg.recipe, from = seg.from, to = seg.to }
    end
  end

  -- Smooth out short back-and-forth switches (A, B, A): stay on A through B's stretch when
  -- that costs at most 5% more for it. Changing recipe for a few points isn't worth it.
  local SWITCH_TOLERANCE = 1.05
  local changed = true
  while changed do
    changed = false
    for i = 1, #steps - 2 do
      local a, b, c = steps[i], steps[i + 1], steps[i + 2]
      if a.recipe == c.recipe and b.recipe ~= a.recipe then
        local costA, costB = 0, 0
        for k = b.from, b.to - 1 do
          costA = costA + costPerPoint(a.recipe, k)
          costB = costB + costPerPoint(b.recipe, k)
        end
        if costA < INF and costA <= costB * SWITCH_TOLERANCE then
          a.to = c.to
          table.remove(steps, i + 2)
          table.remove(steps, i + 1)
          changed = true
          break
        end
      end
    end
  end

  -- Cost per craft shown at market prices (your stock is accounted for in the shopping list).
  local function marketCraftCost(r, at)
    local savedF, savedMemo = ownedFactor, unitMemo
    ownedFactor, unitMemo = nil, {}
    local c = craftCost(r, at)
    ownedFactor, unitMemo = savedF, savedMemo
    return c
  end

  local learned = {}
  for _, st in ipairs(steps) do
    local r = st.recipe
    local exp, gold = 0, 0
    for k = st.from, st.to - 1 do
      exp = exp + 1 / Recipes.PointsPerCraft(r, k, bonus)
      gold = gold + costPerPoint(r, k)
    end
    st.expectedCrafts = exp
    st.crafts = ceil(exp)
    st.costPerCraft = ownedFactor and marketCraftCost(r, st.from) or craftCost(r, st.from)
    if ownedFactor then
      for _, g in ipairs(r.reagents) do
        if ownedFactor(g.name) < 1 then st.usesStock = true end
      end
    end
    local lc, info = learnCost(r)
    st.learnHow = info.how
    st.learnItem = info.item
    st.learnWhere = info.where
    st.learnFavor = info.favor
    if lc > 0 and not learned[r] then
      learned[r] = true
      st.learnCost = lc
    end
    st.expectedGold = gold + (st.learnCost or 0)
  end

  local total = 0
  for _, st in ipairs(steps) do total = total + st.expectedGold end
  local plan = {
    profession = opts.profession, from = from, to = to, steps = steps, notes = notes,
    expectedGold = total,
  }
  Planner.BuildShoppingList(plan, data, unitCost, opts.owned, opts.listed)
  Planner.AddRankNotes(plan)
  return plan
end

-- Replays the route to produce a buy list, a craft-yourself list and recipes to learn.
function Planner.BuildShoppingList(plan, data, unitCost, owned, listed)
  local inv, buy, crafted, order = {}, {}, {}, {}
  local learn = {}
  local ownedLeft, demand = {}, {}

  local function buyEntry(name, how, cost)
    local b = buy[name]
    if not b then
      b = { name = name, qty = 0, have = 0, unit = how.market or cost, source = how.how, estimate = how.est }
      buy[name] = b
    end
    return b
  end

  local function acquire(name, qty, s)
    -- 1. things made earlier on the route
    local have = inv[name] or 0
    if have > 0 then
      local take = math.min(have, qty)
      inv[name] = have - take
      qty = qty - take
    end
    if qty <= 0 then return end
    demand[name] = (demand[name] or 0) + qty
    local cost, how = unitCost(name, s)
    -- 2. what's already in your bags and bank
    if ownedLeft[name] == nil then ownedLeft[name] = owned and owned(name) or 0 end
    local fromStock = math.min(ownedLeft[name], qty)
    if fromStock > 0 then
      ownedLeft[name] = ownedLeft[name] - fromStock
      qty = qty - fromStock
      if how.how ~= "craft" then
        local b = buyEntry(name, how, cost)
        b.qty, b.have = b.qty + fromStock, b.have + fromStock
      else
        crafted[name] = crafted[name] or { name = name, crafts = 0, makes = how.recipe.makes, fromStock = 0 }
        if not crafted[name].listed then crafted[name].listed = true; order[#order + 1] = name end
        crafted[name].fromStock = (crafted[name].fromStock or 0) + fromStock
      end
    end
    if qty <= 0 then return end
    -- 3. craft it or buy it
    if how.how == "craft" then
      local r = how.recipe
      local n = ceil(qty / r.makes)
      crafted[name] = crafted[name] or { name = name, crafts = 0, makes = r.makes, fromStock = 0 }
      if not crafted[name].listed then crafted[name].listed = true; order[#order + 1] = name end
      crafted[name].crafts = crafted[name].crafts + n
      for _, g in ipairs(r.reagents) do acquire(g.name, n * g.qty, s) end
      inv[name] = (inv[name] or 0) + n * r.makes - qty
    else
      local b = buyEntry(name, how, cost)
      b.qty = b.qty + qty
    end
  end

  -- Tools first (needed from the start or as soon as they can be made).
  for _, tool in ipairs(data.tools) do
    do
      local r = data.byName[tool]
      local s = plan.from
      if r and s < r.learn and r.learn < plan.to then s = r.learn end
      local cost = unitCost(tool, s)
      if cost < INF then acquire(tool, 1, s) else plan.notes[#plan.notes + 1] = "You need a " .. tool .. "." end
    end
  end

  -- Items some ranks need (e.g. the Artisan Cooking quest), when the route passes that rank.
  local rules = (ns.RawData.RankRules or {})[plan.profession] or {}
  for _, rank in ipairs(ns.RawData.Ranks) do
    local rule = rules[rank.name]
    local needAt = rank.cap - 75
    if rule and rule.items and plan.from <= needAt and plan.to > needAt then
      for _, it in ipairs(rule.items) do acquire(it[1], it[2], needAt) end
      plan.rankItems = plan.rankItems or {}
      plan.rankItems[#plan.rankItems + 1] = { rank = rank.name, items = rule.items }
    end
  end

  for _, st in ipairs(plan.steps) do
    local r = st.recipe
    for _, g in ipairs(r.reagents) do acquire(g.name, st.crafts * g.qty, st.from) end
    inv[r.name] = (inv[r.name] or 0) + st.crafts * r.makes
    if st.learnCost or st.learnHow == "favor" or st.learnHow == "quest" or st.learnHow == "vendor-est" or st.learnWhere then
      learn[#learn + 1] = { recipe = r.name, cost = st.learnCost or 0, how = st.learnHow, item = st.learnItem,
        where = st.learnWhere, favor = st.learnFavor, at = st.from }
      if st.learnFavor then plan.favorTotal = (plan.favorTotal or 0) + st.learnFavor end
    end
  end

  local list, total = {}, 0
  for _, b in pairs(buy) do
    if not b.unit or b.unit == INF then b.unit = 0 end -- owned, never priced
    b.buy = b.qty - b.have
    b.total = b.buy * b.unit
    total = total + b.total
    if b.source == "ah" and listed then
      b.listed = listed(b.name)
      if b.listed and b.buy > b.listed then
        b.short = true
        plan.short = (plan.short or 0) + 1
      end
    end
    list[#list + 1] = b
  end
  table.sort(list, function(x, y) if x.total ~= y.total then return x.total > y.total end return x.name < y.name end)

  local craftList = {}
  for _, name in ipairs(order) do
    if crafted[name].crafts > 0 then craftList[#craftList + 1] = crafted[name] end
  end

  local learnTotal = 0
  for _, l in ipairs(learn) do learnTotal = learnTotal + l.cost end

  plan.shopping = list
  plan.demand = demand
  plan.craftYourself = craftList
  plan.learn = learn
  plan.buyTotal = total
  plan.learnTotal = learnTotal
  plan.total = total + learnTotal
end

function Planner.AddRankNotes(plan)
  local rules = (ns.RawData.RankRules or {})[plan.profession] or {}
  for _, rank in ipairs(ns.RawData.Ranks) do
    if rank.trainAt > 1 then
      local prevCap = rank.cap - 75
      if plan.from < rank.cap and plan.to > prevCap then
        local rule = rules[rank.name]
        plan.notes[#plan.notes + 1] = rule and rule.note or ("Train %s (character level %d, skill %d+) before you reach %d."):format(
          rank.name, rank.level, rank.trainAt, prevCap)
      end
    end
  end
  local data = Recipes.Load(plan.profession)
  if data and data.needsFire then table.insert(plan.notes, 1, ns.RawData.FireNote) end
end

-- Explains why the route stops: which recipes would work at this skill and what's unpriced.
function Planner.Blockers(list, s, unitCost, learnCost, bonus)
  local out = {}
  for _, r in ipairs(list) do
    if Recipes.SkillUpChance(r, s, bonus) > 0 then
      local missing = {}
      if not learnCost(r) then missing[#missing + 1] = "recipe" end
      for _, g in ipairs(r.reagents) do
        if unitCost(g.name, s) == INF then missing[#missing + 1] = g.name end
      end
      out[#out + 1] = { recipe = r.name, source = r.source, missing = missing }
    end
  end
  table.sort(out, function(a, b) return #a.missing < #b.missing end)
  return out
end

-- Copper -> "1g 23s 45c"
function Planner.Money(c)
  if not c or c == INF then return "?" end
  c = math.floor(c + 0.5)
  local g, sv, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  if g > 0 then return ("%dg %02ds %02dc"):format(g, sv, cp) end
  if sv > 0 then return ("%ds %02dc"):format(sv, cp) end
  return ("%dc"):format(cp)
end
