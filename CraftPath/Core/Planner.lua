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
function Planner.Plan(opts)
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

  -- Gold needed to learn a recipe; nil = can't be learned right now.
  local learnInfo = {}
  local function learnCost(r)
    local cached = learnInfo[r]
    if cached ~= nil then return cached.cost, cached end
    local info = { cost = nil }
    if known[r.name] then
      info.cost, info.how = 0, "known"
    elseif r.source == "A" then
      info.cost, info.how = 0, "auto"
    elseif r.source == "T" then
      info.cost, info.how = 0, "trainer"
    elseif r.source == "F" then
      if allowFavor then info.cost, info.how = 0, "favor" end
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
        info.cost, info.how, info.item = ns.RawData.VendorRecipeEstimate, "vendor-est", prefixes[1] .. r.name
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
    st.costPerCraft = craftCost(r, st.from)
    local lc, info = learnCost(r)
    st.learnHow = info.how
    st.learnItem = info.item
    if lc > 0 and not learned[r] then
      learned[r] = true
      st.learnCost = lc
    end
    st.expectedGold = gold + (st.learnCost or 0)
  end

  local plan = {
    profession = opts.profession, from = from, to = to, steps = steps, notes = notes,
    expectedGold = best[to],
  }
  Planner.BuildShoppingList(plan, data, unitCost, opts.owned, opts.listed)
  Planner.AddRankNotes(plan)
  return plan
end

-- Replays the route to produce a buy list, a craft-yourself list and recipes to learn.
function Planner.BuildShoppingList(plan, data, unitCost, owned, listed)
  local inv, buy, crafted, order = {}, {}, {}, {}
  local learn = {}

  local function acquire(name, qty, s)
    local have = inv[name] or 0
    if have > 0 then
      local take = math.min(have, qty)
      inv[name] = have - take
      qty = qty - take
    end
    if qty <= 0 then return end
    local cost, how = unitCost(name, s)
    if how.how == "craft" then
      local r = how.recipe
      local n = ceil(qty / r.makes)
      if not crafted[name] then crafted[name] = { name = name, crafts = 0, makes = r.makes }; order[#order + 1] = name end
      crafted[name].crafts = crafted[name].crafts + n
      for _, g in ipairs(r.reagents) do acquire(g.name, n * g.qty, s) end
      inv[name] = (inv[name] or 0) + n * r.makes - qty
    else
      local b = buy[name]
      if not b then
        b = { name = name, qty = 0, unit = cost, source = how.how, estimate = how.est }
        buy[name] = b
      end
      b.qty = b.qty + qty
    end
  end

  -- Tools first (needed from the start or as soon as they can be made).
  for _, tool in ipairs(data.tools) do
    local have = owned and owned(tool) or 0
    if have < 1 then
      local r = data.byName[tool]
      local s = plan.from
      if r and s < r.learn and r.learn < plan.to then s = r.learn end
      local cost = unitCost(tool, s)
      if cost < INF then acquire(tool, 1, s) else plan.notes[#plan.notes + 1] = "You need a " .. tool .. "." end
    end
  end

  for _, st in ipairs(plan.steps) do
    local r = st.recipe
    for _, g in ipairs(r.reagents) do acquire(g.name, st.crafts * g.qty, st.from) end
    inv[r.name] = (inv[r.name] or 0) + st.crafts * r.makes
    if st.learnCost or st.learnHow == "favor" or st.learnHow == "vendor-est" then
      learn[#learn + 1] = { recipe = r.name, cost = st.learnCost or 0, how = st.learnHow, item = st.learnItem, vendor = r.vendor, at = st.from }
    end
  end

  local list, total = {}, 0
  for _, b in pairs(buy) do
    local have = owned and owned(b.name) or 0
    b.have = math.min(have, b.qty)
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
  for _, name in ipairs(order) do craftList[#craftList + 1] = crafted[name] end

  local learnTotal = 0
  for _, l in ipairs(learn) do learnTotal = learnTotal + l.cost end

  plan.shopping = list
  plan.craftYourself = craftList
  plan.learn = learn
  plan.buyTotal = total
  plan.learnTotal = learnTotal
  plan.total = total + learnTotal
end

function Planner.AddRankNotes(plan)
  for _, rank in ipairs(ns.RawData.Ranks) do
    if rank.trainAt > 1 then
      local prevCap = rank.cap - 75
      if plan.from < rank.cap and plan.to > prevCap then
        plan.notes[#plan.notes + 1] = ("Train %s (character level %d, skill %d+) before you reach %d."):format(
          rank.name, rank.level, rank.trainAt, prevCap)
      end
    end
  end
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
