-- CraftPath: the planner window.

local _, ns = ...
ns.UI = {}
local UI = ns.UI

local ROW_H, ROWS_W = 18, 556
-- Column layouts for the list (x, width, right-aligned). Every column ends inside ROWS_W.
local MAX_COLS = 7
local LAYOUT = { x = { 4, 64, 300, 420 }, w = { 58, 234, 118, 132 }, right = { false, false, true, true } }
-- Shopping list: item, then need / in bags / in bank / in mailbox / to buy, then cost.
local SHOP_LAYOUT = {
  x = { 4, 196, 244, 292, 340, 388, 440 },
  w = { 188, 44, 44, 44, 44, 48, 112 },
  right = { false, true, true, true, true, true, true },
}
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
  for c = 1, MAX_COLS do
    local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWordWrap(false)
    r.cols[c] = fs
  end
  r:SetScript("OnClick", function(self, btn)
    if self.onClick then self.onClick(btn); return end
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

local function placeColumns(r, layout)
  if r.layout == layout then return end
  r.layout = layout
  for c = 1, MAX_COLS do
    local fs, x = r.cols[c], layout.x[c]
    fs:ClearAllPoints()
    if x then
      fs:SetPoint("LEFT", x, 0)
      fs:SetWidth(layout.w[c])
      fs:SetJustifyH(layout.right[c] and "RIGHT" or "LEFT")
      fs:Show()
    else
      fs:SetText("")
      fs:Hide()
    end
  end
end

local function setRows(list, layout)
  for i, data in ipairs(list) do
    local r = getRow(i)
    local l = data.layout or layout or LAYOUT
    placeColumns(r, l)
    for c = 1, #l.x do r.cols[c]:SetText(data[c] or "") end
    r.item, r.tip, r.onClick = data.item, data.tip, data.onClick
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

-- How to get a recipe, with the vendor and where to find them.
local function learnText(l)
  local w = l.where
  local who = w and w.npc and (w.npc .. (w.where and (", " .. w.where) or "")) or (w and w.where) or nil
  if l.how == "favor" then
    local cost = l.favor and (l.favor .. " Merchant's Favor") or "Merchant's Favor"
    return ("%s from %s"):format(cost, who or "the Merchant's Favor vendor") .. " (may need reputation)"
  end
  if w and w.trainer then return "Learn from " .. who end
  if l.how == "trainer" then return who and ("Learn from " .. who) or "Learn from your trainer" end
  local item = l.item or l.recipe
  if who then
    local est = l.how == "vendor-est" and " (price is a guess until you visit)" or ""
    return ("Buy %s from %s%s"):format(item, who, est)
  end
  if l.how == "ah" then return "Buy " .. item .. " on the auction house" end
  return "Buy " .. item
end

local function stockCols(name)
  local bags = ns.Game.Bags(name)
  local bank = math.max(0, ns.Game.BagsAndBank(name) - bags)
  return bags, bank, ns.Game.Mail(name)
end
local function dim(n) return n > 0 and tostring(n) or "|cff555555–|r" end
local function grey(t) return "|cff999999" .. t .. "|r" end

local function buildRun(run)
  local out = { { grey("Item  (buying now)"), grey("Need"), grey("Bags"), grey("Bank"), grey("Mail"), "|cffffd100Bought|r", grey("Paid") } }
  for _, name in ipairs(run.order) do
    local e = run.items[name]
    local left = ns.Shopping.Left(name)
    local doneRow = left == 0 or ns.db.done[name]
    local label = doneRow and ("|cff777777" .. name .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t|r")
      or (run.skipped[name] and ("|cff999999" .. name .. " (skipped)|r")) or name
    local toBuy = e.need - e.have
    local avg = e.bought > 0 and (e.spent / e.bought) or nil
    local over = avg and e.unit > 0 and math.floor((avg / e.unit - 1) * 100 + 0.5) or 0
    local paid = avg and (Money(e.spent) .. (over > 0 and (" |cffff9933+" .. over .. "%|r") or "")) or ""
    local bags, bank, mail = stockCols(name)
    out[#out + 1] = {
      label, tostring(e.need), dim(bags), dim(bank), dim(mail),
      left > 0 and ("|cffffd100%d/%d|r"):format(e.bought, toBuy) or "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t",
      paid, item = name,
      tip = { name,
        ("Need %d, had %d at the start, bought %d, %d left to buy"):format(e.need, e.have, e.bought, left),
        ("Now: %d in bags, %d in bank, %d in mailbox"):format(bags, bank, mail),
        ("Planned %s each"):format(Money(e.unit)),
        avg and ("Paid %s on average (%s in total)"):format(Money(avg), Money(e.spent)) or "Nothing bought yet",
        e.source == "vendor" and "Buy this from a vendor (right-click to tick off)" or "Click: search the auction house",
        "Right-click: tick off" },
    }
  end
  return out
end

local function buildShopping(plan)
  local run = ns.Shopping.Get()
  if run then return buildRun(run) end
  local out = { { grey("Item  (click to search the AH)"), grey("Need"), grey("Bags"), grey("Bank"), grey("Mail"), "|cffffd100Buy|r", grey("Cost") } }
  for _, b in ipairs(plan.shopping) do
    if b.buy > 0 or b.have > 0 then
      local done = ns.db.done[b.name]
      local shown = b.short and ("|cffff9933" .. b.name .. "|r") or b.name
      local name = done and ("|cff777777" .. b.name .. " |TInterface\\RaidFrame\\ReadyCheck-Ready:12|t|r") or shown
      local bags, bank, mail = stockCols(b.name)
      local buy = b.buy > 0 and ("|cffffd100" .. b.buy .. "|r") or "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
      out[#out + 1] = {
        name, tostring(b.qty), dim(bags), dim(bank), dim(mail), buy, b.buy > 0 and Money(b.total) or "",
        item = b.name,
        tip = (function()
          local t = { b.name, ("Need %d for the route"):format(b.qty),
            ("You have %d: %d in bags, %d in bank, %d in mailbox"):format(bags + bank + mail, bags, bank, mail) }
          t[#t + 1] = b.buy > 0 and ("Buy %d at about %s each (%s)"):format(b.buy, Money(b.unit), sourceText(b))
            or "You have enough: nothing to buy"
          if b.short then t[#t + 1] = ("|cffff9933Only %d listed at the last scan, so the rest may cost more.|r"):format(b.listed) end
          if mail > 0 then t[#t + 1] = "|cff66ccffMailbox counts are from your last visit.|r" end
          t[#t + 1] = "Click: search the auction house"
          t[#t + 1] = "Right-click: tick off"
          return t
        end)(),
      }
    end
  end
  return out
end

-- Route & shopping: each step with its materials (your stock used up in route order: bags,
-- then bank, then mailbox), then the shopping list for the whole route.
local function buildRoute(plan)
  local out = {}
  local cap = plan.levelCap
  if cap then
    out[#out + 1] = { "", ("|cffff9933Stops at %d: the next rank needs level %d.|r"):format(cap.cap, cap.needLevel or 0),
      tip = { "Level cap", ("Your character is level %d, which can train up to %d skill."):format(cap.level, cap.cap),
        "Untick Stop at level cap to see the route to " .. cap.wanted .. "." } }
    out[#out + 1] = { "", "|cffff9933Untick Stop at level cap to plan to " .. cap.wanted .. ".|r" }
  end
  -- Selling what you craft: how this route compares with the cheapest one that ignores selling.
  local pl = plan.plain
  if plan.resaleTotal and plan.resaleTotal > 0 then
    local function net(v) return v < 0 and ("+" .. Money(-v) .. " profit") or Money(v) end
    if pl and pl.net - plan.netTotal >= 100 then
      out[#out + 1] = { "", ("|cff33ff33Selling what you craft saves %s on this route.|r"):format(Money(pl.net - plan.netTotal)),
        tip = { "Selling what you craft", ("This route: spend %s, sell back %s, net %s."):format(Money(plan.total), Money(plan.resaleTotal), net(plan.netTotal)),
          ("Cheapest route without selling: spend %s, net %s even if you sold its crafts."):format(Money(pl.total), net(pl.net)),
          "Change with the Sell button at the top." } }
      out[#out + 1] = { "", ("|cff999999Net %s here vs %s on the plain route (spend %s vs %s).|r"):format(
        net(plan.netTotal), net(pl.net), Money(plan.total), Money(pl.total)) }
    else
      out[#out + 1] = { "", ("|cff33ff33Selling what you make gets back %s (net %s).|r"):format(Money(plan.resaleTotal), net(plan.netTotal)) }
    end
  end
  out[#out + 1] = columns("Skill", "Recipe  (click to open in the crafting helper)", "Crafts", "Step total")
  out[#out + 1] = { grey("    Materials"), grey("Need"), grey("Bags"), grey("Bank"), grey("Mail"), "|cffffd100Buy|r", grey("Cost"),
    layout = SHOP_LAYOUT }

  local selfMade = {}
  for _, c in ipairs(plan.craftYourself or {}) do selfMade[c.name] = true end
  local pools = {}
  local function pool(name)
    local p = pools[name]
    if not p then
      local bags, bank, mail = stockCols(name)
      p = { bags, bank, mail }
      pools[name] = p
    end
    return p
  end

  for i, st in ipairs(plan.steps) do
    local r = st.recipe
    local total = st.costPerCraft * st.crafts
    out[#out + 1] = {
      ("|cffffd100%d–%d|r"):format(st.from, st.to), "|cffffffff" .. r.name .. "|r", "×" .. st.crafts, Money(total),
      tip = { r.name, ("Skill %d to %d, about %.0f crafts"):format(st.from, st.to, st.expectedCrafts),
        ("%s per craft, %s for the step%s"):format(Money(st.costPerCraft), Money(total),
          st.learnCost and st.learnCost > 0 and (" plus " .. Money(st.learnCost) .. " for the recipe") or ""),
        "Click: open this step in the crafting helper" },
      onClick = function()
        if ns.CraftHelper then ns.CraftHelper.ShowStep(plan.profession, st, i, #plan.steps) end
      end,
    }
    if st.learnCost or st.learnHow == "favor" or st.learnHow == "vendor-est" or st.learnWhere then
      local text = learnText({ how = st.learnHow, item = st.learnItem, where = st.learnWhere, favor = st.learnFavor, recipe = r.name })
      local note = st.learnWhere and st.learnWhere.note
      out[#out + 1] = { "", "|cffff9933First: " .. text .. "|r", "", st.learnCost and Money(st.learnCost) or "",
        tip = { "Get the recipe first", text, note } }
    end
    if st.resaleTotal and st.resaleTotal > 0 then
      local made = st.crafts * r.makes
      local where = st.resaleHow == "ah" and "on the auction house" or "to a vendor"
      out[#out + 1] = { "", ("|cff33ff33Sell the %d made %s|r"):format(made, where), "",
        "|cff33ff33+" .. Money(st.resaleTotal) .. "|r",
        tip = { "Sell what you make", ("%d × %s %s at about %s each."):format(made, r.name, where, Money(st.resalePerCraft / r.makes)),
          ("Step: materials %s, back %s, net %s."):format(Money(total), Money(st.resaleTotal), Money(total - st.resaleTotal)),
          st.resaleHow == "ah" and "Auction sales aren't guaranteed: this uses the week's lowest price after the 5% cut." or "Vendors always buy at this price." } }
    end
    for _, g in ipairs(r.reagents) do
      local need = g.qty * st.crafts
      local p = pool(g.name)
      local use, left = { 0, 0, 0 }, need
      for k = 1, 3 do
        use[k] = math.min(left, p[k]); p[k] = p[k] - use[k]; left = left - use[k]
      end
      local unit = ns.Prices.AH(g.name) or ns.Prices.Vendor(g.name) or ns.RawData.VendorItems[g.name]
      local buyCol, cost
      if left <= 0 then
        buyCol = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12|t"
      elseif selfMade[g.name] then
        buyCol, cost = "|cff66ccffmake " .. left .. "|r", nil
      else
        buyCol, cost = "|cffffd100" .. left .. "|r", unit and unit * left
      end
      out[#out + 1] = {
        ("    %s |cff999999(%d each)|r"):format(g.name, g.qty), tostring(need), dim(use[1]), dim(use[2]), dim(use[3]), buyCol,
        cost and Money(cost) or "", layout = SHOP_LAYOUT, item = g.name,
        tip = { g.name, ("%d per craft, %d for this step"):format(g.qty, need),
          ("From your stock: %d from bags, %d from bank, %d from mailbox"):format(use[1], use[2], use[3]),
          left > 0 and (selfMade[g.name] and ("Make %d yourself (its materials are in the shopping list below)"):format(left)
            or ("Buy %d%s"):format(left, unit and (" at about " .. Money(unit) .. " each") or "")) or "Covered by your stock",
          "Stock is used up in route order, so earlier steps get it first.",
          "Click: search the auction house" },
      }
    end
  end

  out[#out + 1] = { "" }
  local run = ns.Shopping.Get()
  out[#out + 1] = { run and "|cffffd100Buying now|r" or "|cffffd100Shopping list for the whole route|r" }
  local shop = run and buildRun(run) or (plan.shopping and buildShopping(plan)) or {}
  for _, row in ipairs(shop) do
    row.layout = SHOP_LAYOUT
    out[#out + 1] = row
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
    out[#out + 1] = header(plan.favorTotal and ("Recipes to get (%d Merchant's Favor in total)"):format(plan.favorTotal) or "Recipes to get")
    for _, l in ipairs(plan.learn) do
      out[#out + 1] = { "@" .. l.at, l.recipe, "", l.cost > 0 and Money(l.cost) or (l.favor and (l.favor .. " Favor") or ""),
        tip = { l.recipe, learnText(l), l.where and l.where.note or nil } }
      out[#out + 1] = { "", "|cff999999    " .. learnText(l) .. "|r" }
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
    local skill = ns.Game.GetSkill(prof)
    b:SetText(skill and skill > 0 and ("%s |cff999999%d|r"):format(prof, skill) or prof)
  end
  widgets.profMenu:SetText(s.profession .. "  |cffffd100v|r")
  widgets.resale:SetText(({ off = "Sell: off", vendor = "Sell: vendor", auction = "Sell: vendor+AH" })[s.resale or "vendor"])
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
    if plan.resaleTotal and plan.resaleTotal > 0 then
      widgets.summary:SetText(("Skill %d to %d   Spend: %s   Sell back: |cff33ff33%s|r   |cffffd100Net: %s|r%s"):format(
        plan.from, plan.to, Money(plan.total), Money(plan.resaleTotal), plan.netTotal < 0
          and ("|cff33ff33+" .. Money(-plan.netTotal) .. " profit|r") or Money(plan.netTotal), short))
    else
      widgets.summary:SetText(("Skill %d to %d   Buy: %s   Recipes: %s   |cffffd100Total: %s|r%s"):format(
        plan.from, plan.to, Money(plan.buyTotal), Money(plan.learnTotal), Money(plan.total), short))
    end
  else
    widgets.summary:SetText(plan.error or "")
  end
  local run = ns.Shopping.Get()
  if run and activeTab == "route" then
    local t = ns.Shopping.Totals()
    if run.stale then
      widgets.summary:SetText(("|cffff9933List locked at %d to %d while buying. Click Finish buying to use your new range.|r"):format(run.from, run.to))
    else
      widgets.summary:SetText(("Buying for %s %d to %d   Spent: %s of %s   |cffffd100Left: %d items, about %s|r"):format(
        run.profession, run.from, run.to, Money(t.spent), Money(t.planned), t.leftItems, Money(t.leftCost)))
    end
  end
  local onShop = activeTab == "route" and plan.steps ~= nil
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
  else list = buildNotes(plan) end
  setRows(list, LAYOUT)
end

function UI.ToggleProfessionMenu()
  if widgets.menu then
    widgets.menu:SetShown(not widgets.menu:IsShown())
    if widgets.menu:IsShown() then syncControls() end
  end
end

function UI.Replan()
  if not ns.db then return end
  if ns.CraftHelper and ns.CraftHelper.ClearCache then ns.CraftHelper.ClearCache() end
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

  -- Row 1 (y -30): profession menu, profits, specialisation   14 ... 214 | 220 ... 330 | 436 ... 586
  widgets.profMenu = button(frame, "", 200, function() UI.ToggleProfessionMenu() end,
    "Profession", "Choose which profession to plan. Ones your character has show your skill.")
  widgets.profMenu:SetPoint("TOPLEFT", 14, -30)
  widgets.profitsButton = button(frame, "Profits", 110, function() if ns.ProfitUI then ns.ProfitUI.Toggle() end end,
    "CraftPath Profits", "What you can craft today at today's prices to make a profit.")
  widgets.profitsButton:SetPoint("LEFT", widgets.profMenu, "RIGHT", 6, 0)
  widgets.resale = button(frame, "", 114, function()
    local order = { "off", "vendor", "auction" }
    local cur = settings().resale or "vendor"
    for i, v in ipairs(order) do if v == cur then settings().resale = order[i % #order + 1] break end end
    UI.Replan()
  end, "Sell what you craft", "Count what you get back for the items you make while levelling, so the route can pick recipes that cost more but sell back well. Off: ignore selling. Vendor: what a vendor pays (guaranteed). Vendor + AH: also the auction price at the week's low, after the 5% cut.")
  widgets.resale:SetPoint("LEFT", widgets.profitsButton, "RIGHT", 6, 0)

  -- The menu itself: every profession, two columns, over the list area.
  local menu = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  menu:SetPoint("TOPLEFT", widgets.profMenu, "BOTTOMLEFT", 0, -2)
  menu:SetSize(300, 20 + 26 * math.ceil(#ns.Recipes.Professions() / 2))
  menu:SetFrameLevel(frame:GetFrameLevel() + 20)
  if menu.SetBackdrop then
    menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    menu:SetBackdropColor(0.05, 0.05, 0.05, 0.97)
  end
  menu:Hide()
  widgets.menu = menu
  for i, prof in ipairs(ns.Recipes.Professions()) do
    local b = button(menu, prof, 136, function()
      settings().profession = prof
      menu:Hide()
      UI.Replan()
    end, prof, "Plan the cheapest way to level " .. prof .. ".")
    b:SetPoint("TOPLEFT", 10 + ((i - 1) % 2) * 142, -10 - math.floor((i - 1) / 2) * 26)
    widgets.profButtons[prof] = b
  end
  widgets.spec = button(frame, "", 130, function()
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
    { "Bought recipes", "allowRecipeItems", "Let the route use schematics and plans you buy from a vendor or the auction house." },
    { "Favor recipes", "allowFavor", "Let the route use recipes bought with Merchant's Favor (no gold, but some need reputation)." },
    { "Use my stock", "useOwned", "Count materials already in your bags and bank as free when choosing recipes, and only buy what's missing." },
    { "Stop at level cap", "capToLevel", "Only plan as far as your character level lets you train: Journeyman at level 10, Expert at 20, Artisan at 35." },
  }
  local optX = { 12, 150, 286, 422 }
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
    { "route", "Route & shopping", 150, "Each step with its materials and what you have in bags, bank and mailbox, then the shopping list for the whole route. Start buying here to track purchases." },
    { "notes", "Notes & tips", 120, "Recipes to get, things to craft yourself, training reminders and new recipes found in game." },
  }
  for _, t in ipairs(tabs) do
    local b = button(frame, t[2], t[3], function() activeTab = t[1]; UI.Refresh() end, t[2], t[4])
    b:SetPoint("TOPLEFT", x, -168)
    widgets.tabs[t[1]] = b
    x = x + t[3] + 4
  end

  -- Buying bar, Route & shopping tab (y -194, two lines)
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
    if not data or not data.id then return end
    local ok, name = pcall(C_Item.GetItemInfo, data.id)
    if not ok or not name then return end
    local keep = ns.Keep and ns.Keep.For(name)
    if keep then
      tooltip:AddDoubleLine("|cff33bbffCraftPath|r keep", keep.qty .. " (" .. ns.Keep.Text(keep) .. ")", 1, 1, 1, 1, 0.82, 0)
    end
    if not settings().tooltip then return end
    local e = ns.Prices.Info(name)
    if e and e.p then
      tooltip:AddDoubleLine("|cff33bbffCraftPath|r AH", Money(e.p) .. " |cff999999(" .. ns.Prices.AgeText(name) .. ")|r", 1, 1, 1, 1, 1, 1)
    elseif e and e.none then
      tooltip:AddDoubleLine("|cff33bbffCraftPath|r AH", "none listed |cff999999(" .. ns.Prices.AgeText(name) .. ")|r", 1, 1, 1, 0.6, 0.6, 0.6)
    end
  end)
end
