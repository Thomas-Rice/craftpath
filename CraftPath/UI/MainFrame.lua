-- CraftPath: the planner window.

local _, ns = ...
ns.UI = {}
local UI = ns.UI

local ROW_H, ROWS_W = 18, 556
local Money = function(c) return ns.Prices.Money(c) end
local frame, rows, activeTab = nil, {}, "route"
local widgets = {}

local SPECS = { "none", "goblin", "gnomish" }
local SPEC_LABEL = { none = "No specialisation", goblin = "Goblin", gnomish = "Gnomish" }

local function settings() return ns.db.settings end

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------

local function button(parent, text, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function checkbox(parent, label, key, tip)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", c, "RIGHT", 1, 0)
  fs:SetText(label)
  c:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
  c:SetScript("OnClick", function(self) settings()[key] = self:GetChecked() and true or false; UI.Replan() end)
  if tip then
    c:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tip, nil, nil, nil, nil, true); GameTooltip:Show()
    end)
    c:SetScript("OnLeave", GameTooltip_Hide)
  end
  c.key = key
  return c
end

local function numberBox(parent, w, key, minV, maxV)
  local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  e:SetSize(w, 20)
  e:SetAutoFocus(false)
  e:SetNumeric(true)
  e:SetMaxLetters(3)
  local function commit(self)
    if self.committing then return end
    self.committing = true
    local v = tonumber(self:GetText()) or settings()[key]
    v = math.max(minV, math.min(maxV, v))
    settings()[key] = v
    self:SetText(tostring(v))
    self:ClearFocus()
    self.committing = false
    UI.Replan()
  end
  e:SetScript("OnEnterPressed", commit)
  e:SetScript("OnEditFocusLost", commit)
  e:SetScript("OnEscapePressed", function(self) self:SetText(tostring(settings()[key])); self:ClearFocus() end)
  e.key = key
  return e
end

local function label(parent, text, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormalSmall")
  fs:SetText(text)
  return fs
end

---------------------------------------------------------------------------
-- Auction house search for a clicked item
---------------------------------------------------------------------------

function UI.SearchAH(name)
  local ah = AuctionHouseFrame
  if not (ah and ah:IsShown()) then ns.Print("Open the auction house to search for " .. name .. "."); return end
  pcall(function()
    if AuctionHouseFrameDisplayMode and ah.SetDisplayMode then ah:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy) end
    ah.SearchBar.SearchBox:SetText(name)
    ah.SearchBar:StartSearch()
  end)
end

---------------------------------------------------------------------------
-- List rows
---------------------------------------------------------------------------

local function getRow(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, widgets.content)
  r:SetSize(ROWS_W, ROW_H)
  r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  r.cols = {}
  local x = { 4, 64, 300, 420 }
  local w = { 58, 234, 118, 132 }
  for c = 1, 4 do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", x[c], 0)
    fs:SetWidth(w[c])
    fs:SetJustifyH(c >= 3 and "RIGHT" or "LEFT")
    fs:SetWordWrap(false)
    r.cols[c] = fs
  end
  r:SetScript("OnClick", function(self, btn)
    if not self.item then return end
    if btn == "RightButton" then
      ns.db.done[self.item] = not ns.db.done[self.item] or nil
      UI.Refresh()
    else
      UI.SearchAH(self.item)
    end
  end)
  r:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    for n = 1, table.maxn(self.tip) do
      local line = self.tip[n]
      if line then
        if n == 1 then GameTooltip:SetText(line) else GameTooltip:AddLine(line, 1, 1, 1, true) end
      end
    end
    GameTooltip:Show()
  end)
  r:SetScript("OnLeave", GameTooltip_Hide)
  rows[i] = r
  return r
end

local function setRows(list)
  for i, data in ipairs(list) do
    local r = getRow(i)
    for c = 1, 4 do r.cols[c]:SetText(data[c] or "") end
    r.item, r.tip = data.item, data.tip
    r:Show()
  end
  for i = #list + 1, #rows do rows[i]:Hide(); rows[i].item = nil end
  widgets.content:SetHeight(math.max(1, #list * ROW_H))
end

local function header(text) return { "|cffffd100" .. text .. "|r" } end

local function sourceText(b)
  if b.source == "vendor" then return b.estimate and "vendor (est.)" or "vendor" end
  return "AH " .. ns.Prices.AgeText(b.name)
end

local function learnText(l)
  if l.how == "favor" then return "Merchant's Favor — Fritz Fizzle, Three Corners (Redridge)" end
  local where = l.vendor and (" from " .. l.vendor) or (l.how == "ah" and " on the AH" or "")
  local est = l.how == "vendor-est" and " (price estimated until you visit the vendor)" or ""
  return (l.item or l.recipe) .. where .. est
end

local function buildRoute(plan)
  local out = {}
  for _, st in ipairs(plan.steps) do
    local r = st.recipe
    local tip = { r.name, ("Skill %d to %d, about %.0f crafts"):format(st.from, st.to, st.expectedCrafts) }
    for _, g in ipairs(r.reagents) do tip[#tip + 1] = ("%d× %s"):format(g.qty, g.name) end
    if r.makes > 1 then tip[#tip + 1] = ("Makes %d per craft"):format(r.makes) end
    out[#out + 1] = { ("%d–%d"):format(st.from, st.to), r.name, "×" .. st.crafts, Money(st.costPerCraft) .. " each", tip = tip }
    if st.learnCost or st.learnHow == "favor" or st.learnHow == "vendor-est" then
      out[#out + 1] = { "", "|cff999999  learn: " .. learnText({ how = st.learnHow, item = st.learnItem, vendor = r.vendor, recipe = r.name }) .. "|r", "",
        st.learnCost and Money(st.learnCost) or "" }
    end
  end
  return out
end

local function buildShopping(plan)
  local out = {}
  for _, b in ipairs(plan.shopping) do
    if b.buy > 0 or b.have > 0 then
      local done = ns.db.done[b.name]
      local shown = b.short and ("|cffff9933" .. b.name .. "|r") or b.name
      local name = done and ("|cff777777" .. b.name .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t|r") or shown
      local qty = b.have > 0 and ("%d |cff999999(+%d)|r"):format(b.buy, b.have) or tostring(b.buy)
      out[#out + 1] = {
        qty, name, Money(b.unit), Money(b.total), item = b.name,
        tip = { b.name, ("Need %d, you have %d, buy %d"):format(b.qty, b.have, b.buy),
          "Price: " .. sourceText(b),
          b.short and ("|cffff9933Only %d listed at the last scan, so the rest may cost more.|r"):format(b.listed) or nil,
          "Click: search the auction house", "Right-click: tick off" },
      }
    end
  end
  return out
end

local function buildNotes(plan)
  local out = {}
  if plan.error then
    out[#out + 1] = header(plan.error)
    out[#out + 1] = { "", "Scan the auction house so CraftPath knows what's for sale." }
    if plan.blocked then
      out[#out + 1] = header(("Recipes that would work at %d:"):format(plan.reached or 0))
      for i, b in ipairs(plan.blocked) do
        if i > 12 then break end
        local miss = #b.missing > 0 and ("needs prices: " .. table.concat(b.missing, ", ")) or "ok"
        out[#out + 1] = { "", b.recipe, "", "", tip = { b.recipe, miss } }
      end
    end
  end
  for _, n in ipairs(plan.notes or {}) do out[#out + 1] = { "", n } end
  if plan.learn and #plan.learn > 0 then
    out[#out + 1] = header("Recipes to get")
    for _, l in ipairs(plan.learn) do
      out[#out + 1] = { "@" .. l.at, l.recipe, "", l.cost > 0 and Money(l.cost) or "", tip = { l.recipe, learnText(l) } }
    end
  end
  if plan.craftYourself and #plan.craftYourself > 0 then
    out[#out + 1] = header("Craft these yourself (cheaper than buying)")
    for _, c in ipairs(plan.craftYourself) do
      out[#out + 1] = { "×" .. c.crafts, c.name, c.makes > 1 and ("makes " .. c.makes) or "" }
    end
  end
  out[#out + 1] = header("How this works")
  out[#out + 1] = { "", "Crafts are averages: yellow and green recipes can miss." }
  out[#out + 1] = { "", "Trainer fees aren't included." }
  return out
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------

function UI.SetStatus(text)
  if widgets.status then widgets.status:SetText(text or "") end
end

local function syncControls()
  local s = settings()
  for _, c in ipairs(widgets.checks) do c:SetChecked(s[c.key]) end
  for _, e in ipairs(widgets.edits) do if not e:HasFocus() then e:SetText(tostring(s[e.key])) end end
  for prof, b in pairs(widgets.profButtons) do
    if prof == s.profession then b:LockHighlight() else b:UnlockHighlight() end
  end
  widgets.spec:SetText(SPEC_LABEL[s.spec] or SPEC_LABEL.none)
  widgets.spec:SetShown(s.profession == "Engineering")
  widgets.fromBox:SetEnabled(not s.useMySkill)
  local atAH = ns.Scanner.atAH
  widgets.scanList:SetEnabled(atAH)
  widgets.fullScan:SetEnabled(atAH)
  for name, t in pairs(widgets.tabs) do
    if name == activeTab then t:LockHighlight() else t:UnlockHighlight() end
  end
end

function UI.Refresh()
  if not frame or not frame:IsShown() then return end
  syncControls()
  local plan = ns.lastPlan
  if not plan then setRows({}); return end
  if plan.error and activeTab ~= "notes" then
    widgets.summary:SetText("|cffff6060" .. plan.error .. "|r  See Notes.")
  elseif plan.total then
    local short = plan.short and ("   |cffff9933%d item%s short on the AH|r"):format(plan.short, plan.short > 1 and "s" or "") or ""
    widgets.summary:SetText(("Skill %d to %d   Buy: %s   Recipes: %s   |cffffd100Total: %s|r%s"):format(
      plan.from, plan.to, Money(plan.buyTotal), Money(plan.learnTotal), Money(plan.total), short))
  else
    widgets.summary:SetText(plan.error or "")
  end
  local list
  if activeTab == "route" then list = plan.steps and buildRoute(plan) or {}
  elseif activeTab == "shop" then list = plan.shopping and buildShopping(plan) or {}
  else list = buildNotes(plan) end
  setRows(list)
end

function UI.Replan()
  if not ns.db then return end
  ns.MakePlan()
  UI.Refresh()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

local function create()
  frame = CreateFrame("Frame", "CraftPathFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(600, 540)
  frame:SetPoint("CENTER")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:SetClampedToScreen(true)
  frame:SetFrameStrata("HIGH")
  tinsert(UISpecialFrames, "CraftPathFrame")
  if frame.TitleText then frame.TitleText:SetText("CraftPath — cheapest way to level a profession") end

  local s = settings()
  widgets.checks, widgets.edits, widgets.profButtons, widgets.tabs = {}, {}, {}, {}

  -- Row 1: profession and specialisation
  local x = 14
  for _, prof in ipairs(ns.Recipes.Professions()) do
    local b = button(frame, prof, 110, function() settings().profession = prof; UI.Replan() end)
    b:SetPoint("TOPLEFT", x, -30)
    widgets.profButtons[prof] = b
    x = x + 114
  end
  widgets.spec = button(frame, "", 150, function()
    local cur = settings().spec
    for i, v in ipairs(SPECS) do if v == cur then settings().spec = SPECS[i % #SPECS + 1] break end end
    UI.Replan()
  end)
  widgets.spec:SetPoint("TOPRIGHT", -14, -30)

  -- Row 2: skill range
  local useSkill = checkbox(frame, "Start from my current skill", "useMySkill")
  useSkill:SetPoint("TOPLEFT", 12, -58)
  table.insert(widgets.checks, useSkill)
  local fromL = label(frame, "From")
  fromL:SetPoint("TOPLEFT", 222, -64)
  widgets.fromBox = numberBox(frame, 36, "from", 1, 299)
  widgets.fromBox:SetPoint("LEFT", fromL, "RIGHT", 8, 0)
  local toL = label(frame, "To")
  toL:SetPoint("LEFT", widgets.fromBox, "RIGHT", 10, 0)
  local toBox = numberBox(frame, 36, "to", 2, 300)
  toBox:SetPoint("LEFT", toL, "RIGHT", 8, 0)
  local otL = label(frame, "Working Overtime rank")
  otL:SetPoint("LEFT", toBox, "RIGHT", 14, 0)
  local ot = numberBox(frame, 24, "overtimeRank", 0, 5)
  ot:SetMaxLetters(1)
  ot:SetPoint("LEFT", otL, "RIGHT", 8, 0)
  widgets.edits = { widgets.fromBox, toBox, ot }

  -- Row 3: options
  local opts = {
    { "Buy schematics/plans", "allowRecipeItems", "Let the route use recipes you have to buy from a vendor or the auction house." },
    { "Merchant's Favor recipes", "allowFavor", "Let the route use recipes bought with Merchant's Favor (no gold)." },
    { "Stop at my level's cap", "capToLevel", "Only plan as far as your character level lets you train (Journeyman 10, Expert 20, Artisan 35)." },
  }
  x = 12
  for _, o in ipairs(opts) do
    local c = checkbox(frame, o[1], o[2], o[3])
    c:SetPoint("TOPLEFT", x, -84)
    table.insert(widgets.checks, c)
    x = x + 190
  end

  -- Row 4: actions
  local planB = button(frame, "Plan", 80, function() UI.Replan() end)
  planB:SetPoint("TOPLEFT", 14, -114)
  widgets.scanList = button(frame, "Scan materials", 120, function() ns.Scanner.ScanShoppingList() end)
  widgets.scanList:SetPoint("LEFT", planB, "RIGHT", 6, 0)
  widgets.fullScan = button(frame, "Full scan", 90, function() ns.Scanner.FullScan() end)
  widgets.fullScan:SetPoint("LEFT", widgets.scanList, "RIGHT", 6, 0)
  widgets.status = label(frame, ns.Scanner.status ~= "" and ns.Scanner.status or "Open the auction house to scan prices.", "GameFontDisableSmall")
  widgets.status:SetPoint("LEFT", widgets.fullScan, "RIGHT", 10, 0)
  widgets.status:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  widgets.status:SetJustifyH("LEFT")
  widgets.status:SetWordWrap(false)

  widgets.summary = label(frame, "", "GameFontHighlight")
  widgets.summary:SetPoint("TOPLEFT", 16, -146)
  widgets.summary:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  widgets.summary:SetJustifyH("LEFT")

  -- Tabs
  x = 14
  for _, t in ipairs({ { "route", "Route" }, { "shop", "Shopping list" }, { "notes", "Notes" } }) do
    local b = button(frame, t[2], 110, function() activeTab = t[1]; UI.Refresh() end)
    b:SetPoint("TOPLEFT", x, -168)
    widgets.tabs[t[1]] = b
    x = x + 114
  end

  -- Scrolling list
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -196)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(ROWS_W, 1)
  scroll:SetScrollChild(content)
  widgets.content = content

  frame:SetScript("OnShow", function() UI.Replan() end)
  frame:Hide()
end

function UI.Toggle()
  if not ns.db then return end
  if not frame then create() end
  frame:SetShown(not frame:IsShown())
end

function UI.OnAuctionHouse(open)
  if not ns.db then return end
  if open and settings().openWithAH then
    if not frame then create() end
    if AuctionHouseFrame then
      frame:ClearAllPoints()
      frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 4, 0)
    end
    frame:Show()
  end
  if frame and frame:IsShown() then UI.Refresh() end
end

---------------------------------------------------------------------------
-- Tooltip: last auction price for any item CraftPath has seen
---------------------------------------------------------------------------

function ns.OnLoaded()
  if not (TooltipDataProcessor and Enum.TooltipDataType and Enum.TooltipDataType.Item) then return end
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
    if not settings().tooltip or not data or not data.id then return end
    local ok, name = pcall(C_Item.GetItemInfo, data.id)
    if not ok or not name then return end
    local e = ns.Prices.Info(name)
    if e and e.p then
      tooltip:AddDoubleLine("|cff33bbffCraftPath|r AH", Money(e.p) .. " |cff999999(" .. ns.Prices.AgeText(name) .. ")|r", 1, 1, 1, 1, 1, 1)
    elseif e and e.none then
      tooltip:AddDoubleLine("|cff33bbffCraftPath|r AH", "none listed |cff999999(" .. ns.Prices.AgeText(name) .. ")|r", 1, 1, 1, 0.6, 0.6, 0.6)
    end
  end)
end
