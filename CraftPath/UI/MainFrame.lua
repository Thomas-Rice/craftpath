-- CraftPath: the planner window.

local _, ns = ...
ns.UI = {}
local UI = ns.UI

local ROW_H, ROWS_W = 18, 556
local FRAME_W, FRAME_H = 600, 600
local LIST_TOP, LIST_TOP_BUY = -196, -250 -- list top, without / with the buying bar
local Money = function(c) return ns.Prices.Money(c) end
local frame, rows, activeTab = nil, {}, "route"
local widgets = {}

local SPECS = { "none", "goblin", "gnomish" }
local SPEC_LABEL = { none = "No specialisation", goblin = "Goblin", gnomish = "Gnomish" }

local function settings() return ns.db.settings end

---------------------------------------------------------------------------
-- Small widget helpers
---------------------------------------------------------------------------

-- Tooltip helper shared by buttons, boxes and checkboxes.
local function addTip(widget, title, body)
  if not title then return end
  widget:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tipTitle or title)
    local text = self.tipBody or body
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  widget:SetScript("OnLeave", GameTooltip_Hide)
end

-- Buttons never draw text past their edges: long labels are cut with "…".
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

local function checkbox(parent, label, key, tip)
  local c = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  c:SetSize(24, 24)
  local fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", c, "RIGHT", 1, 0)
  fs:SetText(label)
  c:SetHitRectInsets(0, -fs:GetStringWidth() - 4, 0, 0)
  c:SetScript("OnClick", function(self) settings()[key] = self:GetChecked() and true or false; UI.Replan() end)
  if tip then addTip(c, label, tip) end
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
    local typed = self:GetText()
    local changed = typed ~= self.before
    local v = tonumber(typed) or settings()[key]
    v = math.max(minV, math.min(maxV, v))
    self:ClearFocus()
    self.committing = false
    if not changed then UI.Refresh(); return end
    settings()[key] = v
    -- Typing a starting skill means "plan from this skill", not from the character's.
    if key == "from" and settings().useMySkill then
      settings().useMySkill = false
      ns.Print(("Planning from skill %d. Tick \"Start from my current skill\" to go back."):format(v))
    end
    UI.Replan()
  end
  e:SetScript("OnEditFocusGained", function(self) self.before = self:GetText(); self:HighlightText() end)
  e:SetScript("OnEnterPressed", commit)
  e:SetScript("OnEditFocusLost", commit)
  e:SetScript("OnEscapePressed", function(self) self:SetText(self.before or ""); self:ClearFocus() end)
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
local function columns(a, b, c, d)
  local g = function(t) return t and ("|cff999999" .. t .. "|r") or "" end
  return { g(a), g(b), g(c), g(d) }
end

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
  local out = { columns("Skill", "Recipe to craft", "Crafts", "Cost per craft") }
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

local function buildRun(run)
  local out = { columns("Left", "Item", "Bought", "Paid (plan)") }
  for _, name in ipairs(run.order) do
    local e = run.items[name]
    local left = ns.Shopping.Left(name)
    local doneRow = left == 0 or ns.db.done[name]
    local label = doneRow and ("|cff777777" .. name .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t|r")
      or (run.skipped[name] and ("|cff999999" .. name .. " (skipped)|r")) or name
    local toBuy = e.need - e.have
    local avg = e.bought > 0 and (e.spent / e.bought) or nil
    local over = avg and e.unit > 0 and math.floor((avg / e.unit - 1) * 100 + 0.5) or 0
    local priceCol = avg and (Money(avg) .. (over > 0 and (" |cffff9933+" .. over .. "%|r") or "")) or Money(e.unit)
    out[#out + 1] = {
      left > 0 and (left .. " left") or "done", label, ("%d/%d"):format(e.bought, toBuy), priceCol, item = name,
      tip = { name,
        ("Need %d, had %d in bags at the start, bought %d, %d left"):format(e.need, e.have, e.bought, left),
        ("Planned %s each"):format(Money(e.unit)),
        avg and ("Paid %s on average (%s in total)"):format(Money(avg), Money(e.spent)) or nil,
        e.source == "vendor" and "Buy this from a vendor (right-click to tick off)" or "Click: search the auction house",
        "Right-click: tick off" },
    }
  end
  return out
end

local function buildShopping(plan)
  local run = ns.Shopping.Get()
  if run then return buildRun(run) end
  local out = { columns("Buy", "Item", "Price each", "Total") }
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
  local seen = ns.db.seen[plan.profession or settings().profession]
  if seen and next(seen) then
    local names = {}
    for name in pairs(seen) do names[#names + 1] = name end
    table.sort(names)
    out[#out + 1] = header(("New in game, not in CraftPath's data yet (%d)"):format(#names))
    for _, name in ipairs(names) do
      local e = seen[name]
      local tip = { name, e.reagents and ("Reagents: " .. e.reagents:gsub(";", ", ")) or nil,
        e.learn and ("Trainer: needs skill " .. e.learn) or nil,
        e.recipeItem and ("On the AH: " .. e.recipeItem .. " for " .. Money(e.price)) or nil,
        "CraftPath can't plan with this until its data is updated." }
      out[#out + 1] = { e.learn and ("@" .. e.learn) or "", name, e.learned and "known" or "", "", tip = tip }
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
  -- With "Start from my current skill" on, the From box shows the live skill.
  if s.useMySkill and not widgets.fromBox:HasFocus() then
    local live = ns.Game.GetSkill(s.profession)
    if live then widgets.fromBox:SetText(tostring(live)) end
  end
  for prof, b in pairs(widgets.profButtons) do
    if prof == s.profession then b:LockHighlight() else b:UnlockHighlight() end
  end
  widgets.spec:SetText(SPEC_LABEL[s.spec] or SPEC_LABEL.none)
  widgets.spec:SetShown(s.profession == "Engineering")
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
  local run = ns.Shopping.Get()
  if run and activeTab == "shop" then
    local t = ns.Shopping.Totals()
    if run.stale then
      widgets.summary:SetText(("|cffff9933List locked at %d to %d while buying. Click Finish buying to use your new range.|r"):format(run.from, run.to))
    else
      widgets.summary:SetText(("Buying for %s %d to %d   Spent: %s of %s   |cffffd100Left: %d items, about %s|r"):format(
        run.profession, run.from, run.to, Money(t.spent), Money(t.planned), t.leftItems, Money(t.leftCost)))
    end
  end
  local onShop = activeTab == "shop"
  widgets.buyBar:SetShown(onShop)
  widgets.scroll:ClearAllPoints()
  widgets.scroll:SetPoint("TOPLEFT", 12, onShop and LIST_TOP_BUY or LIST_TOP)
  widgets.scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  if onShop then
    widgets.runButton:SetText(run and "Finish buying" or "Start buying")
    widgets.runButton.tipTitle = run and "Finish buying" or "Start buying"
    widgets.runButton.tipBody = run and "Stop tracking this list. Purchases stay in the log." or nil
    widgets.runButton:SetEnabled(run ~= nil or (plan.shopping ~= nil))
    widgets.buyButton:SetShown(run ~= nil)
    widgets.skipButton:SetShown(run ~= nil)
    widgets.buyButton:SetText(ns.Buyer.ButtonText())
    widgets.buyButton:SetEnabled(ns.Scanner.atAH and ns.Buyer.state ~= "quoting" and ns.Buyer.state ~= "buying")
    widgets.hint:SetShown(run == nil)
  end
  local list
  if activeTab == "route" then list = plan.steps and buildRoute(plan) or {}
  elseif activeTab == "shop" then list = plan.shopping and buildShopping(plan) or {}
  else list = buildNotes(plan) end
  setRows(list)
end

function UI.Replan()
  if not ns.db then return end
  local plan = ns.MakePlan()
  -- A buying list with nothing bought yet follows the new plan; once you've bought
  -- something it stays locked so purchases keep counting against it.
  local run = ns.Shopping.Get()
  if run and plan.shopping and (run.from ~= plan.from or run.to ~= plan.to or run.profession ~= plan.profession) then
    if ns.Shopping.BoughtAnything() then
      run.stale = true
    else
      ns.Buyer.Cancel()
      ns.Shopping.Start(plan)
    end
  elseif run then
    run.stale = nil
  end
  UI.Refresh()
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------

-- Layout: the frame is FRAME_W wide; content sits between x = 14 and x = 586 (572 px).
-- Every row below is sized to fit inside that.

local function create()
  frame = CreateFrame("Frame", "CraftPathFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(FRAME_W, FRAME_H)
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

  widgets.checks, widgets.edits, widgets.profButtons, widgets.tabs = {}, {}, {}, {}

  -- Row 1 (y -30): profession, specialisation           14 ... 238 | 436 ... 586
  local x = 14
  for _, prof in ipairs(ns.Recipes.Professions()) do
    local b = button(frame, prof, 110, function() settings().profession = prof; UI.Replan() end,
      prof, "Plan the cheapest way to level " .. prof .. ".")
    b:SetPoint("TOPLEFT", x, -30)
    widgets.profButtons[prof] = b
    x = x + 114
  end
  widgets.spec = button(frame, "", 150, function()
    local cur = settings().spec
    for i, v in ipairs(SPECS) do if v == cur then settings().spec = SPECS[i % #SPECS + 1] break end end
    UI.Replan()
  end, "Engineering specialisation", "Click to cycle: none, Goblin, Gnomish. Goblin and Gnomish recipes are only used if you have that specialisation.")
  widgets.spec:SetPoint("TOPRIGHT", -14, -30)

  -- Row 2 (y -58): skill range and perk                 12 ... ~530
  local useSkill = checkbox(frame, "Start from my current skill", "useMySkill",
    "Plan from your character's real skill. Untick to type a starting skill yourself.")
  useSkill:SetPoint("TOPLEFT", 12, -58)
  table.insert(widgets.checks, useSkill)
  local fromL = label(frame, "From")
  fromL:SetPoint("TOPLEFT", 226, -64)
  widgets.fromBox = numberBox(frame, 36, "from", 1, 299)
  widgets.fromBox:SetPoint("LEFT", fromL, "RIGHT", 8, 0)
  addTip(widgets.fromBox, "Starting skill", "Type a skill to plan from it. This turns off \"Start from my current skill\".")
  local toL = label(frame, "To")
  toL:SetPoint("LEFT", widgets.fromBox, "RIGHT", 10, 0)
  local toBox = numberBox(frame, 36, "to", 2, 300)
  toBox:SetPoint("LEFT", toL, "RIGHT", 8, 0)
  addTip(toBox, "Target skill", "The skill you want to reach (up to 300).")
  local otL = label(frame, "Overtime perk (0-5)")
  otL:SetPoint("LEFT", toBox, "RIGHT", 16, 0)
  local ot = numberBox(frame, 24, "overtimeRank", 0, 5)
  ot:SetMaxLetters(1)
  ot:SetPoint("LEFT", otL, "RIGHT", 8, 0)
  addTip(ot, "Working Overtime (Legacy perk)", "Your rank in the perk. Each rank adds 4% skill-up chance, so you need fewer crafts.")
  widgets.edits = { widgets.fromBox, toBox, ot }

  -- Row 3 (y -84): route options                        12 | 200 | 400 ... ~560
  local opts = {
    { "Use bought recipes", "allowRecipeItems", "Let the route use schematics and plans you buy from a vendor or the auction house." },
    { "Use Merchant's Favor recipes", "allowFavor", "Let the route use recipes bought with Merchant's Favor (no gold)." },
    { "Stop at my level's cap", "capToLevel", "Only plan as far as your character level lets you train: Journeyman at level 10, Expert at 20, Artisan at 35." },
  }
  local optX = { 12, 200, 400 }
  for i, o in ipairs(opts) do
    local c = checkbox(frame, o[1], o[2], o[3])
    c:SetPoint("TOPLEFT", optX[i], -84)
    table.insert(widgets.checks, c)
  end

  -- Row 4 (y -114): actions and status                  14 ... 360 | 368 ... 586
  local planB = button(frame, "Recalculate", 100, function() UI.Replan() end,
    "Recalculate", "Work out the cheapest route again with the latest prices and settings.")
  planB:SetPoint("TOPLEFT", 14, -114)
  widgets.scanList = button(frame, "Scan AH prices", 120, function() ns.Scanner.ScanShoppingList() end,
    "Scan AH prices", "At the auction house: search every material and recipe this profession uses, one by one (about a minute).")
  widgets.scanList:SetPoint("LEFT", planB, "RIGHT", 6, 0)
  widgets.fullScan = button(frame, "Full AH scan", 110, function() ns.Scanner.FullScan() end,
    "Full AH scan", "At the auction house: read every auction in one go. Blizzard allows this once every 15 minutes.")
  widgets.fullScan:SetPoint("LEFT", widgets.scanList, "RIGHT", 6, 0)
  widgets.status = label(frame, ns.Scanner.status ~= "" and ns.Scanner.status or "Open the auction house to scan prices.", "GameFontDisableSmall")
  widgets.status:SetPoint("LEFT", widgets.fullScan, "RIGHT", 8, 0)
  widgets.status:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  widgets.status:SetJustifyH("LEFT")
  widgets.status:SetWordWrap(false)

  -- Row 5 (y -146): one-line summary (cut with "…" if too long)
  widgets.summary = label(frame, "", "GameFontHighlight")
  widgets.summary:SetPoint("TOPLEFT", 16, -146)
  widgets.summary:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  widgets.summary:SetJustifyH("LEFT")
  widgets.summary:SetWordWrap(false)

  -- Row 6 (y -168): tabs                                14 ... 386
  x = 14
  local tabs = {
    { "route", "Leveling steps", "Which recipe to craft at each skill, how many, and the cost per craft." },
    { "shop", "What to buy", "Everything to buy for the route, with prices. Start buying here to track purchases." },
    { "notes", "Notes & tips", "Recipes to get, things to craft yourself, training reminders and new recipes found in game." },
  }
  for _, t in ipairs(tabs) do
    local b = button(frame, t[2], 120, function() activeTab = t[1]; UI.Refresh() end, t[2], t[3])
    b:SetPoint("TOPLEFT", x, -168)
    widgets.tabs[t[1]] = b
    x = x + 124
  end

  -- Buying bar, "What to buy" tab only (y -194, two lines)
  --   line 1: [Start/Finish buying 120] [Buy button 300] [Skip 80]   12 ... 530
  --   line 2: price limit                                           12 ... ~360
  local bar = CreateFrame("Frame", nil, frame)
  bar:SetPoint("TOPLEFT", 12, -194)
  bar:SetPoint("RIGHT", frame, "RIGHT", -14, 0)
  bar:SetHeight(50)
  widgets.buyBar = bar
  widgets.runButton = button(bar, "Start buying", 120, function()
    if ns.Shopping.Get() then ns.Buyer.Cancel(); ns.Shopping.Stop() else ns.Shopping.Start(ns.lastPlan) end
    UI.Refresh()
  end, "Start buying", "Locks this list (quantities and prices) and counts everything you buy, so the route doesn't change while you shop. Click again when you're done.")
  widgets.runButton:SetPoint("TOPLEFT", 2, 0)
  widgets.buyButton = button(bar, "Get price", 300, function() ns.Buyer.Click() end,
    "Buy the next item", "First click gets the live price. Second click buys it. Blizzard needs a click for each purchase.")
  widgets.buyButton:SetPoint("LEFT", widgets.runButton, "RIGHT", 6, 0)
  widgets.skipButton = button(bar, "Skip item", 80, function() ns.Buyer.SkipCurrent(); UI.Refresh() end,
    "Skip item", "Leave this item for now and move on to the next one.")
  widgets.skipButton:SetPoint("LEFT", widgets.buyButton, "RIGHT", 6, 0)
  widgets.hint = label(bar, "Locks this list and counts every purchase.", "GameFontDisableSmall")
  widgets.hint:SetPoint("LEFT", widgets.runButton, "RIGHT", 8, 0)
  widgets.hint:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
  widgets.hint:SetJustifyH("LEFT")
  widgets.hint:SetWordWrap(false)
  local overL = label(bar, "Only buy if the price is at most")
  overL:SetPoint("TOPLEFT", 4, -32)
  local over = numberBox(bar, 34, "maxOverPct", 0, 500)
  over:SetPoint("LEFT", overL, "RIGHT", 8, 0)
  addTip(over, "Price limit", "If the live price is more than this % above the plan, CraftPath asks before buying.")
  table.insert(widgets.edits, over)
  local overR = label(bar, "% above the plan")
  overR:SetPoint("LEFT", over, "RIGHT", 4, 0)

  -- Scrolling list (moves down when the buying bar is showing)
  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, LIST_TOP)
  scroll:SetPoint("BOTTOMRIGHT", -32, 12)
  widgets.scroll = scroll
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
