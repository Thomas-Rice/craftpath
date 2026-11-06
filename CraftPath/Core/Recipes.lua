-- CraftPath: turns the compact recipe text in Data/*.lua into recipe tables.
-- Pure Lua 5.1, no game API, so the same code runs in tests and in-game.

local _, ns = ...
ns.Recipes = ns.Recipes or {}
local Recipes = ns.Recipes

local cache = {}

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function split(s, sep)
  local out = {}
  for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end
  return out
end

local function parseReagents(text)
  local list = {}
  for _, chunk in ipairs(split(text, ";")) do
    chunk = trim(chunk)
    if chunk ~= "" then
      local name, qty = chunk:match("^(.-)%*(%d+)$")
      if not name then error("CraftPath: bad reagent '" .. chunk .. "'") end
      list[#list + 1] = { name = name, qty = tonumber(qty) }
    end
  end
  return list
end

local function parseLine(line, profession)
  local f = split(line, "|")
  if #f ~= 9 and #f ~= 10 then error("CraftPath: bad recipe line (" .. #f .. " fields): " .. line) end
  local src, vendor = f[8], nil
  local quest
  if src:sub(1, 2) == "V:" then vendor = src:sub(3); src = "V" end
  if src:sub(1, 2) == "Q:" then quest = src:sub(3); src = "Q" end
  local r = {
    name = f[1], profession = profession,
    learn = tonumber(f[2]), orange = tonumber(f[3]), yellow = tonumber(f[4]),
    green = tonumber(f[5]), grey = tonumber(f[6]), makes = tonumber(f[7]),
    source = src, vendor = vendor, quest = quest, reagents = parseReagents(f[9]),
    points = tonumber(f[10]) or 1, -- skill points per successful craft
  }
  for _, k in ipairs({ "learn", "orange", "yellow", "green", "grey", "makes" }) do
    if not r[k] then error("CraftPath: bad number in " .. k .. ": " .. line) end
  end
  return r
end

local function expandSet(line, sets)
  local setName, rest = line:match("^@SET%s+(%S+)%s+(.+)$")
  local set = setName and sets[setName]
  if not set then error("CraftPath: unknown @SET in: " .. line) end
  local lines = {}
  for _, v in ipairs(set) do
    local l = rest:gsub("%%V", v[1])
    if v[2] then l = l:gsub("%%G", v[2]) end
    if l:find("%%G") then error("CraftPath: set " .. setName .. " has no gem for: " .. line) end
    lines[#lines + 1] = l
  end
  return lines
end

-- Returns the parsed recipe list for a profession, plus the profession's tools.
function Recipes.Load(profession)
  if cache[profession] then return cache[profession] end
  local raw = ns.RawData[profession]
  if not raw then return nil end
  local list, byName = {}, {}
  for line in raw.recipes:gmatch("[^\r\n]+") do
    line = trim(line)
    if line ~= "" and line:sub(1, 2) ~= "--" then
      local lines = (line:sub(1, 5) == "@SET ") and expandSet(line, ns.RawData.Sets) or { line }
      for _, l in ipairs(lines) do
        local r = parseLine(l, profession)
        if byName[r.name] then error("CraftPath: duplicate recipe " .. r.name) end
        r.index = #list + 1
        list[r.index] = r
        byName[r.name] = r
      end
    end
  end
  local data = { profession = profession, list = list, byName = byName, tools = raw.tools or {}, needsFire = raw.needsFire }
  cache[profession] = data
  return data
end

function Recipes.Professions()
  local out = {}
  for name, v in pairs(ns.RawData) do
    if type(v) == "table" and v.recipes then out[#out + 1] = name end
  end
  table.sort(out)
  return out
end

-- Every item name the profession's recipes use, for targeted auction house scans.
function Recipes.AllReagents(profession)
  local data = Recipes.Load(profession)
  local seen, out = {}, {}
  for _, r in ipairs(data.list) do
    for _, g in ipairs(r.reagents) do
      if not seen[g.name] then seen[g.name] = true; out[#out + 1] = g.name end
    end
  end
  for _, t in ipairs(data.tools) do
    if not seen[t] then seen[t] = true; out[#out + 1] = t end
  end
  table.sort(out)
  return out
end

-- Expected skill points from one craft of r at skill s.
function Recipes.PointsPerCraft(r, s, bonus)
  return Recipes.SkillUpChance(r, s, bonus) * (r.points or 1)
end

-- Chance of a skill point when crafting recipe r at skill s (Classic rule:
-- orange always, then falling linearly from yellow to 0 at grey).
function Recipes.SkillUpChance(r, s, bonus)
  if s < r.learn or s >= r.grey then return 0 end
  local p
  if s < r.yellow then p = 1 else p = (r.grey - s) / (r.grey - r.yellow) end
  if p <= 0 then return 0 end
  p = p + (bonus or 0)
  if p > 1 then p = 1 end
  return p
end
