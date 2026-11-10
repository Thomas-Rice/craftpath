-- CraftPath Profits: its own window listing what you can craft today, at today's prices,
-- for a profit. Opens with /cpath profit, the Profits button on the planner, or the minimap
-- addon menu. Uses the same prices and recipe data as the planner (Core/Profit.lua does the maths).

local _, ns = ...
ns.ProfitUI = {}
local UI = ns.ProfitUI

local W, H = 660, 560
local ROW_H, ROWS_W = 18, 612
local MAX_ROWS_SHOWN = 400
-- item | cost | sells for | profit | safe | listed | notes      (every column ends inside ROWS_W)
local COLS = {
  x = { 4, 214, 286, 358, 430, 502, 548 },
  w = { 206, 68, 68, 68, 68, 42, 62 },
  right = { false, true, true, true, true, true, false },
}
local SORTS = { "safe", "profit", "margin" }
local SORT_LABEL = { safe = "Sort: safe profit", profit = "Sort: profit now", margin = "Sort: margin %" }

local frame, rows, widgets = nil, {}, {}
local results, computing = nil, false

local function settings() return ns.db.settings end
local Money = function(c) return ns.Prices.Money(c) end

local function short(c)
  -- Compact money for narrow columns: 1g20s, 35s, 80c.
  if not c then return "—" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t
  if g > 0 then t = g .. "|cffffd100g|r" .. (s > 0 and (s .. "|cffc7c7cfs|r") or "")
  elseif s > 0 then t = s .. "|cffc7c7cfs|r" .. (cu > 0 and g == 0 and s < 10 and (cu .. "|cffeda55fc|r") or "")
  else t = cu .. "|cffeda55fc|r" end
  return (neg and "|cffff6060-|r" or "") .. t
end

local function addTip(widget, title, body)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tipTitle or title)
    if self.tipBody or body then GameTooltip:AddLine(self.tipBody or body, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", GameTooltip_Hide)
end

local function button(parent, text, w, onClick, tipTitle, tipBody)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  local fs = b.GetFontString and b:GetFontString()
  if fs then fs:SetWidth(w - 14); fs:SetWordWrap(false) end
  b:SetScript("OnClick", onClick)
  addTip(b, tipTitle or text, tipBody)
  return b
end

local function checkbox(parent, text, key, tip)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", c, "RIGHT", 1, 0)
  fs:SetText(text)
  c:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
  c:SetScript("OnClick", function(self) settings()[key] = self:GetChecked() and true or false; UI.Recompute() end)
  addTip(c, text, tip)
  return c
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------

-- What a vendor pays for an item (remembered once the game has told us).
local function sellPrice(name)
  local known = ns.db.sell[name]
  if known then return known > 0 and known or nil end
  local fromData = ns.RawData.ItemSell and ns.RawData.ItemSell[name]
  if fromData then return fromData end
  if C_Item and C_Item.GetItemInfo then
    local ok, n, _, _, _, _, _, _, _, _, _, sell = pcall(C_Item.GetItemInfo, ns.db.ids[name] or name)
    if ok and n and type(sell) == "number" then
      ns.db.sell[name] = sell
      return sell > 0 and sell or nil
    end
  end
end

local function professions()
  local list = {}
  for _, prof in ipairs(ns.Recipes.Professions()) do
    local skill = ns.Game.GetSkill(prof)
    if skill and skill <= 0 then skill = nil end
    list[#list + 1] = { prof = prof, skill = skill, known = ns.db.known[prof] }
  end
  return list
end

local function findOpts()
  return {
    professions = professions(),
    includeUnknown = true, -- the window filters; one pass covers both views
    ahPrice = ns.Prices.AH, vendorPrice = ns.Prices.Vendor, sellPrice = sellPrice,
    listed = ns.Prices.Listed, stats = ns.Prices.Stats,
    faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    allowFavor = settings().allowFavor,
    vendorWhere = function(item) return ns.db.vendorWhere[item] end,
  }
end

function UI.Recompute()
  if not frame or not frame:IsShown() then return end
  if computing then return end
  computing = true
  widgets.status:SetText("Working out today's profits…")
  ns.Async("profit", function()
    local list = ns.Profit.Find(findOpts())
    -- For recipes that need more skill: what levelling there costs (planner, without your stock).
    local cache = {}
    for _, e in ipairs(list) do
      if e.need == "skill" and e.skill then
        local key = e.profession .. "|" .. e.skill .. "|" .. e.needSkill
        if cache[key] == nil then
          local plan = ns.MakePlan({ profession = e.profession, from = e.skill, to = e.needSkill, noStock = true })
          cache[key] = plan and not plan.error and plan.total or false
        end
        e.levelCost = cache[key] or nil
      end
    end
    return list
  end, function(list)
    computing = false
    results = list
    UI.Refresh()
  end)
end

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, widgets.content)
  r:SetSize(ROWS_W, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:RegisterForClicks("LeftButtonUp")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.cols = {}
  for c = 1, #COLS.x do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", COLS.x[c], 0)
    fs:SetWidth(COLS.w[c])
    fs:SetJustifyH(COLS.right[c] and "RIGHT" or "LEFT")
    fs:SetWordWrap(false)
    r.cols[c] = fs
  end
  r:SetScript("OnClick", function(self) if self.item and ns.UI and ns.UI.SearchAH then ns.UI.SearchAH(self.item) end end)
  r:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tip[1])
    for i = 2, #self.tip do GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  rows[i] = r
  return r
end

local function setRows(list)
  for i, data in ipairs(list) do
    local r = getRow(i)
    for c = 1, #COLS.x do r.cols[c]:SetText(data[c] or "") end
    r.item, r.tip = data.item, data.tip
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide(); rows[i].item, rows[i].tip = nil, nil end
  widgets.content:SetHeight(math.max(1, #list * ROW_H))
end

local HOW = { ah = "auction house", vendor = "vendor", craft = "craft it" }

local function learnLine(e)
  local l = e.learn or {}
  local how = ({ trainer = "Trainer", auto = "Learned automatically", favor = "Merchant's Favor", quest = "Quest reward",
    vendor = "Vendor", ["vendor-est"] = "Vendor", ah = "Auction house", ["not at trainer"] = "Not at your trainer yet",
    ["other faction"] = "Other faction only", goblin = "Goblin Engineering only",
    gnomish = "Gnomish Engineering only" })[l.how] or "Drop or rare recipe"
  local w = l.where
  local where = w and ((w.quest and ("quest \"" .. w.quest .. "\"") or w.npc or "") .. (w.where and (", " .. w.where) or "")) or nil
  local cost = e.learnCost and e.learnCost > 0 and Money(e.learnCost) or nil
  return how .. (cost and (" " .. cost) or "") .. (where and where ~= "" and (" — " .. where) or ""), l
end

local function tipFor(e)
  local t = { e.name .. "  |cff999999(" .. e.profession .. ")|r" }
  t[#t + 1] = "|cffffd100Materials (cheapest way to get each):|r"
  for _, m in ipairs(e.materials) do
    t[#t + 1] = ("  %d× %s  %s  |cff999999(%s)|r"):format(m.qty, m.name, Money(m.unit * m.qty), HOW[m.how] or "no price")
  end
  if e.makes > 1 then t[#t + 1] = ("Each craft makes %d, so cost per item %s"):format(e.makes, Money(e.cost)) end
  t[#t + 1] = "Cost to make: " .. Money(e.cost)
  if e.price then
    t[#t + 1] = ("Lowest on the auction house: %s (%s after the 5%% cut)"):format(Money(e.price), Money(e.sale))
    t[#t + 1] = "Profit now: " .. Money(e.profit)
  end
  if e.stats then
    t[#t + 1] = ("Last %d days: low %s, middle %s, high %s"):format(e.stats.days, Money(e.stats.low), Money(e.stats.median), Money(e.stats.high))
    t[#t + 1] = "Safe profit (at the week's low): " .. Money(e.safeProfit)
  end
  if e.swings then t[#t + 1] = "|cffff9933The price jumps around: don't count on today's price.|r" end
  if e.listed then t[#t + 1] = ("%d listed at the last scan%s"):format(e.listed, e.listed > 40 and " — a crowded market" or "") end
  if e.vendorSell then
    t[#t + 1] = ("A vendor pays %s%s"):format(Money(e.vendorSell),
      e.vendorProfit and e.vendorProfit > 0 and ("  |cff33ff33(guaranteed %s profit)|r"):format(Money(e.vendorProfit)) or "")
  end
  if e.levelsYou then t[#t + 1] = "|cff33ff33Still gives you skill-ups.|r" end
  if not e.canCraft then
    if not e.hasProfession then
      t[#t + 1] = "|cffff9933You don't have " .. e.profession .. ".|r"
    elseif e.skill and e.skill < e.needSkill then
      t[#t + 1] = ("|cffff9933Needs %s %d: you have %d, so level up %d points first.|r"):format(
        e.profession, e.needSkill, e.skill, e.needSkill - e.skill)
      if e.levelCost then
        t[#t + 1] = ("Levelling %d to %d costs about %s (see the CraftPath planner)."):format(e.skill, e.needSkill, Money(e.levelCost))
      end
    else
      t[#t + 1] = "|cff33ff33You have the skill: just get the recipe.|r"
    end
    local text = learnLine(e)
    t[#t + 1] = "Get the recipe: " .. text
    if e.learn and e.learn.where and e.learn.where.note then t[#t + 1] = e.learn.where.note end
    if e.payback then t[#t + 1] = ("Pays for itself after %d crafts."):format(e.payback) end
  end
  t[#t + 1] = "Click: search the auction house"
  return t
end

local function rowFor(e)
  local notes = {}
  if e.vendorProfit and e.vendorProfit > 0 and e.vendorProfit >= (e.safeProfit or -math.huge) then
    notes[#notes + 1] = "|cff33ff33sell to vendor|r"
  end
  if e.swings then notes[#notes + 1] = "|cffff9933swings|r" end
  if e.levelsYou then notes[#notes + 1] = "|cff66ccffskill|r" end
  local name = e.name .. (e.makes > 1 and ("|cff999999 ×" .. e.makes .. "|r") or "")
  if not e.canCraft then
    local how = e.learn and e.learn.how
    local tag = ({ trainer = "trainer", auto = "auto", favor = "favor", quest = "quest", vendor = "vendor",
      ["vendor-est"] = "vendor", ah = "AH", goblin = "goblin", gnomish = "gnomish" })[how] or "drop"
    if e.need == "skill" then
      notes = { ("|cff66ccffskill %d|r"):format(e.needSkill) }
    else
      notes = { "|cff999999learn: " .. tag .. "|r" }
    end
    name = "|cffbbbbbb" .. name .. "|r"
  end
  local function green(v) return v and (v > 0 and ("|cff33ff33" .. short(v) .. "|r") or short(v)) or "—" end
  return {
    name .. " |cff777777" .. e.profession:sub(1, 3) .. "|r", short(e.cost),
    e.profit and short(e.profit) or "—", green(e.safeProfit), green(e.vendorProfit),
    e.listed and tostring(e.listed) or "—", table.concat(notes, " "),
    item = e.name, tip = tipFor(e),
  }
end

local function keyOf(e)
  local s = settings().profitSort or "safe"
  if s == "profit" then return e.profit or e.vendorProfit or -math.huge end
  if s == "margin" then return e.margin or -math.huge end
  return math.max(e.safeProfit or -math.huge, e.vendorProfit or -math.huge)
end

function UI.Refresh()
  if not frame or not frame:IsShown() then return end
  local s = settings()
  widgets.unknown:SetChecked(s.profitUnknown and true or false)
  widgets.sort:SetText(SORT_LABEL[s.profitSort or "safe"])
  local scan = ns.db.lastFullScan
  local newest = 0
  for _, e in pairs(ns.db.prices) do if e.t and e.t > newest then newest = e.t end end
  local when = newest > 0 and date("%d %b %H:%M", newest) or "never"
  if not results then
    widgets.status:SetText(computing and "Working out today's profits…" or "")
    setRows({})
    return
  end
  local mine, groups = {}, { learn = {}, skill = {}, profession = {} }
  for _, e in ipairs(results) do
    if e.canCraft then mine[#mine + 1] = e
    elseif e.need and (e.need ~= "profession" or s.profitUnknown) then table.insert(groups[e.need], e) end
  end
  table.sort(mine, function(a, b) return keyOf(a) > keyOf(b) end)
  for _, g in pairs(groups) do table.sort(g, function(a, b) return keyOf(a) > keyOf(b) end) end
  local other = groups.profession
  local out = {
    { "|cff999999Item  (hover for details, click to search)|r", "|cff999999Cost|r", "|cff999999AH profit|r",
      "|cffffd100AH safe|r", "|cff999999Vendor|r", "|cff999999Listed|r", "|cff999999Notes|r" },
  }
  if #mine == 0 then
    out[#out + 1] = { "|cffff9933Nothing you can craft makes a profit at these prices.|r" }
    out[#out + 1] = { "See below for recipes you could learn, or tick 'Show other professions'." }
  end
  for i, e in ipairs(mine) do
    if i > MAX_ROWS_SHOWN then break end
    out[#out + 1] = rowFor(e)
  end
  local function section(title, list)
    if #list == 0 then return end
    out[#out + 1] = { "" }
    out[#out + 1] = { ("|cffffd100%s (%d)|r"):format(title, #list) }
    for i, e in ipairs(list) do
      if i > MAX_ROWS_SHOWN then break end
      out[#out + 1] = rowFor(e)
    end
  end
  -- Your professions: recipes you could add by learning them, or by levelling up first.
  section("Learn the recipe: you have the skill", groups.learn)
  section("Level up first, then learn the recipe", groups.skill)
  if s.profitUnknown then section("Professions you don't have", other) end
  setRows(out)
  widgets.status:SetText(("Prices from %s.  %d you can craft now, %d to learn, %d after levelling up%s."):format(
    when, #mine, #groups.learn, #groups.skill, s.profitUnknown and (", " .. #other .. " in other professions") or ""))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function create()
  frame = CreateFrame("Frame", "CraftPathProfitFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(W, H)
  frame:SetPoint("CENTER", 40, -20)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "CraftPathProfitFrame")
  if frame.TitleText then frame.TitleText:SetText("CraftPath Profits — what to craft today") end

  -- Row 1 (y -30): show unknown, sort, refresh          12 ... 300 | 340 ... 646
  widgets.unknown = checkbox(frame, "Show other professions", "profitUnknown",
    "Also list profitable crafts from professions you don't have. Recipes you could learn in your own professions are always shown, below the ones you can craft now.")
  widgets.unknown:SetPoint("TOPLEFT", 12, -30)
  widgets.sort = button(frame, "", 140, function()
    local cur = settings().profitSort or "safe"
    for i, v in ipairs(SORTS) do if v == cur then settings().profitSort = SORTS[i % #SORTS + 1] break end end
    UI.Refresh()
  end, "Sort", "Safe profit: at the lowest price of the last week (the default, it allows for prices moving). Profit now: at today's lowest price. Margin: profit as a share of the cost.")
  widgets.sort:SetPoint("TOPRIGHT", -112, -30)
  widgets.refresh = button(frame, "Refresh", 90, function() UI.Recompute() end,
    "Refresh", "Work the list out again from your latest prices. Scan the auction house from the planner for fresh prices.")
  widgets.refresh:SetPoint("TOPRIGHT", -14, -30)

  -- Row 2 (y -58): status line, explanation
  widgets.status = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  widgets.status:SetPoint("TOPLEFT", 16, -62)
  widgets.status:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  widgets.status:SetJustifyH("LEFT")
  widgets.status:SetWordWrap(false)
  local help = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("TOPLEFT", 16, -78)
  help:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  help:SetJustifyH("LEFT")
  help:SetWordWrap(false)
  help:SetText("AH profit is after the 5% cut; AH safe uses the week's lowest price. Vendor = profit selling to a vendor (guaranteed).")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -98)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROWS_W, 1)
  scroll:SetScrollChild(content)
  widgets.content = content

  frame:SetScript("OnShow", function() UI.Recompute() end)
  frame:Hide()
end

function UI.Toggle()
  if not ns.db then return end
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function UI.Show()
  if not frame then create() end
  frame:Show()
end

-- New prices: work the list out again if it's open.
ns.On("AUCTION_HOUSE_CLOSED", function() UI.Recompute() end)
