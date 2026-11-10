-- CraftPath website bridge: runs the addon's own planner (Data + Recipes + Planner)
-- in the browser and talks JSON with the page. Lua 5.4 (wasmoon).

local ns = CP_NS

local json = {}

local function esc(s)
  return (s:gsub('[%c"\\]', function(c)
    local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
    return map[c] or string.format("\\u%04x", c:byte())
  end))
end

local function isArray(t)
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
    n = n + 1
  end
  return n == #t
end

function json.encode(v, seen)
  local t = type(v)
  if t == "nil" then return "null" end
  if t == "boolean" then return tostring(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
    return string.format("%.6g", v)
  end
  if t == "string" then return '"' .. esc(v) .. '"' end
  if t ~= "table" then return "null" end
  seen = seen or {}
  if seen[v] then return "null" end
  seen[v] = true
  local out = {}
  if next(v) ~= nil and isArray(v) then
    for i = 1, #v do out[i] = json.encode(v[i], seen) end
    seen[v] = nil
    return "[" .. table.concat(out, ",") .. "]"
  end
  for k, val in pairs(v) do
    local tv = type(val)
    if tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then
      out[#out + 1] = '"' .. esc(tostring(k)) .. '":' .. json.encode(val, seen)
    end
  end
  seen[v] = nil
  return "{" .. table.concat(out, ",") .. "}"
end

-- Small JSON decoder for the options the page sends.
function json.decode(s)
  local pos = 1
  local function ws() pos = s:find("[^ \t\r\n]", pos) or #s + 1 end
  local value
  local function str()
    local out, i = {}, pos + 1
    while true do
      local c = s:sub(i, i)
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local n = s:sub(i + 1, i + 1)
        if n == "u" then
          local cp = tonumber(s:sub(i + 2, i + 5), 16)
          out[#out + 1] = utf8.char(cp); i = i + 6
        else
          out[#out + 1] = ({ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[n] or n; i = i + 2
        end
      else
        out[#out + 1] = c; i = i + 1
      end
    end
  end
  function value()
    ws()
    local c = s:sub(pos, pos)
    if c == "{" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "}" then pos = pos + 1; return t end
      while true do
        ws(); local k = str(); ws(); pos = pos + 1 -- :
        t[k] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "}" then return t end
      end
    elseif c == "[" then
      local t = {}; pos = pos + 1; ws()
      if s:sub(pos, pos) == "]" then pos = pos + 1; return t end
      while true do
        t[#t + 1] = value(); ws()
        local d = s:sub(pos, pos); pos = pos + 1
        if d == "]" then return t end
      end
    elseif c == '"' then return str()
    elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      pos = pos + #num
      return tonumber(num)
    end
  end
  return value()
end

-- opts: profession, from, to, faction, allowRecipeItems, allowFavor, spec, bonus, charLevel,
-- prices {name = copper}, vendor {name = copper}
function CP_Plan(optsJson)
  local o = json.decode(optsJson)
  local prices, vendor, listed = o.prices or {}, o.vendor or {}, o.listed or {}
  local opts = {
    profession = o.profession, from = o.from, to = o.to,
    ahPrice = function(n) return prices[n] end,
    vendorPrice = function(n) return vendor[n] end,
    known = {}, allowRecipeItems = o.allowRecipeItems ~= false, allowFavor = o.allowFavor ~= false,
    spec = o.spec, bonus = o.bonus or 0, faction = o.faction, charLevel = o.charLevel,
    listed = function(n) return listed[n] end,
  }
  local ok, plan = pcall(ns.Planner.Plan, opts)
  if not ok then return json.encode({ error = tostring(plan) }) end
  return json.encode(plan)
end

function CP_Data()
  local out = { professions = {}, ranks = ns.RawData.Ranks, vendorItems = ns.RawData.VendorItems }
  for _, prof in ipairs(ns.Recipes.Professions()) do
    local d = ns.Recipes.Load(prof)
    out.professions[prof] = { count = #d.list, reagents = ns.Recipes.AllReagents(prof), build = ns.RawData[prof].build }
  end
  return json.encode(out)
end

-- Profit finder for the website. opts: prices { name = { p, q, low, med, high, days } },
-- vendor { name = copper }, faction, professions (list of names; default all).
function CP_Profit(optsJson)
  local o = json.decode(optsJson)
  local prices, vendor = o.prices or {}, o.vendor or {}
  local profs = {}
  for _, name in ipairs(o.professions or ns.Recipes.Professions()) do profs[#profs + 1] = { prof = name } end
  local ok, list = pcall(ns.Profit.Find, {
    professions = profs, includeUnknown = true, faction = o.faction,
    ahPrice = function(n) local e = prices[n]; return e and e.p end,
    vendorPrice = function(n) return vendor[n] end,
    listed = function(n) local e = prices[n]; return e and e.q end,
    stats = function(n)
      local e = prices[n]
      if e and e.low then return { low = e.low, median = e.med, high = e.high, days = e.days } end
    end,
  })
  if not ok then return json.encode({ error = tostring(list) }) end
  local out = {}
  for i, e in ipairs(list) do
    local l = e.learn or {}
    out[i] = {
      name = e.name, profession = e.profession, makes = e.makes, skill = e.recipe.learn,
      cost = e.cost, price = e.price, sale = e.sale, profit = e.profit, safeProfit = e.safeProfit,
      vendorSell = e.vendorSell, vendorProfit = e.vendorProfit, margin = e.margin, listed = e.listed,
      swings = e.swings, stats = e.stats, materials = e.materials, payback = e.payback,
      learnHow = l.how, learnCost = e.learnCost, learnWhere = l.where, learnItem = l.item, source = e.recipe.source,
    }
  end
  return json.encode(out)
end
