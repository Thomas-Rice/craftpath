-- CraftPath History: what you've bought, sold and crafted, and what it made you.
-- Opens with /cpath history (or /cpath ledger) and the History buttons. Core/Ledger.lua records.
--
-- Summary  money in and out, net, crafting profit, skill-ups, best and worst items
-- Items    per item: made, bought, sold, average cost, average sale, profit
-- History  every event, newest first

local _, ns = ...
ns.LedgerUI = {}
local UI = ns.LedgerUI

local W, H = 640, 540
local ROW_H, ROWS_W = 18, 592
local MAX_HISTORY = 500

local LAYOUTS = {
  summary = { x = { 4, 300 }, w = { 290, 288 }, right = { false, false } },
  -- item | made | bought | sold | avg cost | avg sale | profit
  items = { x = { 4, 214, 262, 310, 358, 430, 502 }, w = { 206, 44, 44, 44, 68, 68, 86 },
    right = { false, true, true, true, true, true, true } },
  -- when | what | item | qty | gold
  history = { x = { 4, 96, 200, 452, 496 }, w = { 88, 100, 248, 40, 92 },
    right = { false, false, false, true, true } },
}
local PERIODS = { "today", "week", "month", "all" }
local PERIOD_LABEL = { today = "Today", week = "Last 7 days", month = "Last 30 days", all = "All time" }
local KIND_LABEL = {
  buy = "|cffff9933Bought (AH)|r", vbuy = "|cffff9933Bought (vendor)|r",
  sell = "|cff33ff33Sold (AH)|r", vsell = "|cff33ff33Sold (vendor)|r",
  craft = "|cff66ccffCrafted|r", skill = "|cffffd100Skill-up|r",
}

local frame, rows, widgets = nil, {}, {}
local view = "summary"

local function settings() return ns.db.settings end
local Money = function(c) return ns.Prices.Money(c) end

local function short(c)
  if not c then return "—" end
  local neg = c < 0
  c = math.floor(math.abs(c) + 0.5)
  local g, s, cu = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t
  if g > 0 then t = g .. "|cffffd100g|r" .. (s > 0 and (s .. "|cffc7c7cfs|r") or "")
  elseif s > 0 then t = s .. "|cffc7c7cfs|r" .. (cu > 0 and s < 10 and (cu .. "|cffeda55fc|r") or "")
  else t = cu .. "|cffeda55fc|r" end
  return (neg and "|cffff6060-|r" or "") .. t
end

local function signed(c)
  if not c then return "—" end
  if c > 0 then return "|cff33ff33+" .. short(c) .. "|r" end
  return short(c)
end

local function addTip(widget, title, body)
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
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

---------------------------------------------------------------------------
-- Rows
---------------------------------------------------------------------------

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, widgets.content)
  r:SetSize(ROWS_W, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.cols = {}
  for c = 1, 7 do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWordWrap(false)
    r.cols[c] = fs
  end
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

local function setRows(list, layout)
  for i, data in ipairs(list) do
    local r = getRow(i)
    for c = 1, 7 do
      local fs = r.cols[c]
      if layout.x[c] then
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", layout.x[c], 0)
        -- a lone first column (headings, notes) may run the full width
        fs:SetWidth((c == 1 and not data[2]) and (ROWS_W - 8) or layout.w[c])
        fs:SetJustifyH(layout.right[c] and "RIGHT" or "LEFT")
        fs:SetText(data[c] or "")
        fs:Show()
      else
        fs:SetText(""); fs:Hide()
      end
    end
    r.tip = data.tip
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide(); rows[i].tip = nil end
  widgets.content:SetHeight(math.max(1, #list * ROW_H))
end

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------

local function since()
  local p = settings().ledgerPeriod or "week"
  local now = time()
  if p == "today" then
    local d = date("*t", now)
    d.hour, d.min, d.sec = 0, 0, 0
    return time(d)
  end
  if p == "week" then return now - 7 * 86400 end
  if p == "month" then return now - 30 * 86400 end
  return nil
end

local function itemTip(e)
  local t = { e.name }
  if e.made > 0 then
    t[#t + 1] = ("Made %d. Materials worth %s (%s each)."):format(e.made, Money(e.madeCost), Money(e.madeCost / e.made))
  end
  if e.bought > 0 then t[#t + 1] = ("Bought %d for %s."):format(e.bought, Money(e.spent)) end
  if e.sold > 0 then t[#t + 1] = ("Sold %d for %s (%s each, after the auction cut)."):format(e.sold, Money(e.earned), Money(e.earned / e.sold)) end
  if e.unitCost then t[#t + 1] = "Average cost of one (all time): " .. Money(e.unitCost) end
  if e.profit then
    t[#t + 1] = (e.profit >= 0 and "|cff33ff33" or "|cffff6060") .. "Profit on the ones sold: " .. Money(e.profit) .. "|r"
  elseif e.sold > 0 then
    t[#t + 1] = "|cff999999No cost recorded: made or bought before CraftPath kept a history.|r"
  end
  return t
end

local function summaryRows(s)
  local out = {}
  local function head(text) out[#out + 1] = { "|cffffd100" .. text .. "|r" } end
  local function line(a, b, tip) out[#out + 1] = { a, b, tip = tip } end
  local function gap() out[#out + 1] = { "" } end
  head("Gold")
  line("Sold on the auction house", signed(s.income.sell), { "Auction sales", "From your 'Auction successful' mails, after the 5% cut. Open your mailbox to record them." })
  line("Sold to vendors", signed(s.income.vsell))
  line("Bought on the auction house", short(-s.spend.buy))
  line("Bought from vendors", short(-s.spend.vbuy))
  line("|cffffffffNet gold|r", signed(s.net), { "Net gold", "Everything sold minus everything bought in this period." })
  gap()
  head("Crafting")
  line("Crafts", s.crafts .. (s.crafts > 0 and ("  |cff999999(materials worth " .. short(s.craftValue) .. ")|r") or ""),
    { "Crafts", "Materials are valued at the auction (or vendor) price when you crafted." })
  line("Profit on crafted items you sold", signed(s.craftProfit), { "Crafting profit",
    "What your crafted items sold for, minus what their materials were worth." })
  local skills = {}
  for _, k in pairs(s.skills) do skills[#skills + 1] = k end
  table.sort(skills, function(a, b) return a.name < b.name end)
  for _, k in ipairs(skills) do
    local spent = 0 -- materials used in this profession in the period
    for _, e in ipairs(s.list) do if e.profession == k.name then spent = spent + e.madeCost end end
    local per = (k.to - k.from) > 0 and spent > 0 and ("  |cff999999(" .. short(spent / (k.to - k.from)) .. " a point)|r") or ""
    line(k.name .. " skill", ("%d → %d  (+%d)%s"):format(k.from, k.to, k.to - k.from, per))
  end
  -- What works: the items that made (and lost) the most.
  local best, worst = {}, {}
  for _, e in ipairs(s.list) do
    if e.profit and e.profit > 0 and #best < 8 then best[#best + 1] = e end
  end
  for i = #s.list, 1, -1 do
    local e = s.list[i]
    if e.profit and e.profit < 0 and #worst < 5 then worst[#worst + 1] = e end
  end
  local function each(e)
    return ("%s  |cff999999(%d sold, %s each)|r"):format(e.name, e.sold, short(e.unitSale)),
      signed(e.profit) .. (e.unitCost and e.unitSale and ("  |cff999999" .. short(e.unitSale - e.unitCost) .. " a sale|r") or "")
  end
  if #best > 0 then
    gap(); head("What worked: best earners")
    for _, e in ipairs(best) do local a, b = each(e); line(a, b, itemTip(e)) end
  end
  if #worst > 0 then
    gap(); head("What didn't: sold at a loss")
    for _, e in ipairs(worst) do local a, b = each(e); line(a, b, itemTip(e)) end
  end
  if #best == 0 and #worst == 0 then
    gap()
    out[#out + 1] = { "|cff999999Sell something you crafted (open your mailbox to pick up auction sales) and its profit shows here.|r" }
  end
  return out
end

local function itemRows(s)
  local out = { { "|cff999999Item (hover for details)|r", "|cff999999Made|r", "|cff999999Bought|r", "|cff999999Sold|r",
    "|cff999999Avg cost|r", "|cff999999Avg sale|r", "|cffffd100Profit|r" } }
  for _, e in ipairs(s.list) do
    out[#out + 1] = {
      e.name, e.made > 0 and tostring(e.made) or "", e.bought > 0 and tostring(e.bought) or "",
      e.sold > 0 and tostring(e.sold) or "", short(e.unitCost), e.unitSale and short(e.unitSale) or "—",
      e.profit and signed(e.profit) or "—", tip = itemTip(e),
    }
  end
  if #s.list == 0 then out[#out + 1] = { "|cff999999Nothing recorded in this period yet.|r" } end
  return out
end

local function historyRows(events)
  local out = { { "|cff999999When|r", "|cff999999What|r", "|cff999999Item|r", "|cff999999Qty|r", "|cff999999Gold|r" } }
  local n = 0
  for i = #events, 1, -1 do
    local ev = events[i]
    n = n + 1
    if n > MAX_HISTORY then break end
    local gold
    if ev.k == "skill" then gold = ""
    elseif ev.k == "craft" then gold = "|cff999999" .. short(-ev.g) .. "|r"
    else gold = signed(ev.g) end
    local tip = { ev.n, date("%d %b %Y %H:%M", ev.t) .. "  " .. (ev.ch or "") }
    if ev.k == "craft" then tip[#tip + 1] = "Materials worth " .. Money(-ev.g) end
    if ev.k == "sell" and ev.cut then tip[#tip + 1] = ("Sold for %s, auction cut %s"):format(Money(ev.g + ev.cut), Money(ev.cut)) end
    if ev.buyer and ev.buyer ~= "" then tip[#tip + 1] = "Buyer: " .. ev.buyer end
    out[#out + 1] = {
      date("%d %b %H:%M", ev.t), KIND_LABEL[ev.k] or ev.k,
      ev.k == "skill" and (ev.n .. " " .. (ev.from or ev.q - 1) .. " → " .. ev.q) or ev.n,
      ev.k ~= "skill" and tostring(ev.q) or "", gold, tip = tip,
    }
  end
  if #events == 0 then out[#out + 1] = { "|cff999999Nothing recorded in this period yet.|r" } end
  return out
end

function UI.Refresh()
  if not frame or not frame:IsShown() then return end
  local s = settings()
  widgets.period:SetText(PERIOD_LABEL[s.ledgerPeriod or "week"])
  widgets.mine:SetChecked(s.ledgerMine and true or false)
  for k, b in pairs(widgets.tabs) do
    if b.LockHighlight then if k == view then b:LockHighlight() else b:UnlockHighlight() end end
  end
  local events = ns.Ledger.Events(since(), s.ledgerMine)
  local sum = ns.Ledger.Summarise(events)
  if view == "items" then setRows(itemRows(sum), LAYOUTS.items)
  elseif view == "history" then setRows(historyRows(events), LAYOUTS.history)
  else setRows(summaryRows(sum), LAYOUTS.summary) end
  widgets.status:SetText(("%s: %d events.  Net %s,  crafting profit %s."):format(
    PERIOD_LABEL[s.ledgerPeriod or "week"], #events, signed(sum.net), signed(sum.craftProfit)))
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

local function create()
  frame = CreateFrame("Frame", "CraftPathLedgerFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(W, H)
  frame:SetPoint("CENTER", -40, 10)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "CraftPathLedgerFrame")
  if frame.TitleText then frame.TitleText:SetText("CraftPath History — what you've bought, sold and crafted") end

  -- Row 1 (y -30): view tabs   12 ... 300 | period, this character   ... 626
  widgets.tabs = {}
  local prev
  for _, v in ipairs({ { "summary", "Summary" }, { "items", "Items" }, { "history", "History" } }) do
    local b = button(frame, v[2], 92, function() view = v[1]; UI.Refresh() end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 12, -30) end
    widgets.tabs[v[1]] = b
    prev = b
  end
  widgets.period = button(frame, "", 110, function()
    local cur = settings().ledgerPeriod or "week"
    for i, v in ipairs(PERIODS) do if v == cur then settings().ledgerPeriod = PERIODS[i % #PERIODS + 1] break end end
    UI.Refresh()
  end, "Period", "Click to cycle: today, the last 7 days, the last 30 days, all time.")
  widgets.period:SetPoint("TOPRIGHT", -150, -30)
  local mine = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
  mine:SetSize(24, 24)
  mine:SetPoint("TOPRIGHT", -112, -29)
  local fs = mine:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", mine, "RIGHT", 1, 0)
  fs:SetText("This character")
  mine:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
  mine:SetScript("OnClick", function(self) settings().ledgerMine = self:GetChecked() and true or false; UI.Refresh() end)
  addTip(mine, "This character only", "Untick to add up every character on this account.")
  widgets.mine = mine

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
  help:SetText("Recorded as you play. Auction sales are picked up from your mail, so open your mailbox after selling.")

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -98)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROWS_W, 1)
  scroll:SetScrollChild(content)
  widgets.content = content

  frame:SetScript("OnShow", function() UI.Refresh() end)
  frame:Hide()
end

function UI.Toggle()
  if not ns.db then return end
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function UI.Show(which)
  if not ns.db then return end
  if not frame then create() end
  if which then view = which end
  frame:Show()
  UI.Refresh()
end
