-- CraftPath: crafting helper. Opens beside your profession window and walks the route:
-- the current step, reagents in your bags, intermediates to make first, and a Craft button.
-- It replans from your live skill after every skill-up, so it moves on by itself.

local _, ns = ...
ns.CraftHelper = {}
local Helper = ns.CraftHelper

local frame, w = nil, {}
local Money = function(c) return ns.Prices.Money(c) end

local function inBags(name)
  if not C_Item or not C_Item.GetItemCount then return 0 end
  local id = ns.db.ids[name]
  local ok, n = pcall(C_Item.GetItemCount, id or name, false)
  return ok and n or 0
end

local function craftableFromBags(prof, recipe)
  local id = ns.db.recipeIDs[prof] and ns.db.recipeIDs[prof][recipe.name]
  if id then
    local ok, r = pcall(C_TradeSkillUI.GetRecipeInfo, id)
    if ok and r and type(r.numAvailable) == "number" then return r.numAvailable end
  end
  local n = math.huge
  for _, g in ipairs(recipe.reagents) do n = math.min(n, math.floor(inBags(g.name) / g.qty)) end
  return n == math.huge and 0 or n
end

local function profFrame()
  return (ProfessionsFrame and ProfessionsFrame:IsShown() and ProfessionsFrame)
      or (TradeSkillFrame and TradeSkillFrame:IsShown() and TradeSkillFrame) or nil
end

local function line(parent, template)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  return fs
end

local function button(parent, text, width, onClick, tipTitle, tipBody)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  local fs = b.GetFontString and b:GetFontString()
  if fs then fs:SetWidth(width - 14); fs:SetWordWrap(false) end
  b:SetScript("OnClick", onClick)
  if tipTitle then
    b:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(tipTitle)
      if tipBody then GameTooltip:AddLine(tipBody, 1, 1, 1, true) end
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
  end
  return b
end

local function create()
  frame = CreateFrame("Frame", "CraftPathCraftHelper", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(320, 330) -- height grows to fit the text (see fitHeight)
  frame:SetPoint("CENTER", 320, 0)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); self.userMoved = true end)
  frame:SetClampedToScreen(true)
  if frame.TitleText then frame.TitleText:SetText("CraftPath — what to craft") end

  w.skill = line(frame, "GameFontNormal")
  w.skill:SetPoint("TOPLEFT", 14, -30)
  w.skill:SetPoint("RIGHT", -14, 0)

  w.step = line(frame, "GameFontHighlightLarge")
  w.step:SetPoint("TOPLEFT", w.skill, "BOTTOMLEFT", 0, -8)
  w.step:SetPoint("RIGHT", -14, 0)

  w.detail = line(frame)
  w.detail:SetPoint("TOPLEFT", w.step, "BOTTOMLEFT", 0, -4)
  w.detail:SetPoint("RIGHT", -14, 0)

  w.reagents = line(frame)
  w.reagents:SetPoint("TOPLEFT", w.detail, "BOTTOMLEFT", 0, -8)
  w.reagents:SetPoint("RIGHT", -14, 0)

  w.first = line(frame)
  w.first:SetPoint("TOPLEFT", w.reagents, "BOTTOMLEFT", 0, -8)
  w.first:SetPoint("RIGHT", -14, 0)

  w.next = line(frame, "GameFontDisableSmall")
  w.next:SetPoint("TOPLEFT", w.first, "BOTTOMLEFT", 0, -8)
  w.next:SetPoint("RIGHT", -14, 0)

  -- Buttons: 12 + 120 + 6 + 90 + 6 + 72 = 306, inside 320 - 12.
  w.craft = button(frame, "Craft", 120, function() Helper.Craft() end,
    "Craft", "Craft as many of this step's recipe as your bags allow.")
  w.craft:SetPoint("BOTTOMLEFT", 12, 12)
  w.open = button(frame, "Show recipe", 90, function() Helper.ShowRecipe() end,
    "Show recipe", "Select this recipe in the profession window.")
  w.open:SetPoint("LEFT", w.craft, "RIGHT", 6, 0)
  w.planner = button(frame, "Planner", 72, function()
    if Helper.preview then Helper.preview = nil; Helper.Update() else ns.UI.Toggle() end
  end, "Planner / Back", "Open the CraftPath planner. When you're looking at another step, go back to your current step.")
  w.planner:SetPoint("LEFT", w.open, "RIGHT", 6, 0)
  frame:Hide()
end

-- The step being worked on is "locked" until you reach the end of its skill range, so the
-- panel doesn't flip between recipes on small price changes. At the end of the range it
-- moves to the next step of a fresh plan.
Helper.lock = nil -- { prof, recipe = name, to = skill, cost = copper per craft }

local function stepFromLock(lock, skill, plan, data)
  local r = data.byName[lock.recipe]
  if not r then return nil end
  local bonus = 0.04 * (tonumber(ns.db.settings.overtimeRank) or 0)
  if ns.Recipes.PointsPerCraft(r, skill, bonus) <= 0 then return nil end -- turned grey early
  local first = plan.steps and plan.steps[1]
  if first and first.recipe.name == r.name then
    first.to = lock.to
  end
  local exp = 0
  for k = skill, lock.to - 1 do
    local p = ns.Recipes.PointsPerCraft(r, k, bonus)
    if p <= 0 then break end
    exp = exp + 1 / p
  end
  return {
    recipe = r, from = skill, to = lock.to, expectedCrafts = exp, crafts = math.ceil(exp - 1e-9),
    costPerCraft = (first and first.recipe.name == r.name and first.costPerCraft) or lock.cost,
    learnHow = first and first.recipe.name == r.name and first.learnHow or nil,
    learnItem = first and first.recipe.name == r.name and first.learnItem or nil,
    learnWhere = first and first.recipe.name == r.name and first.learnWhere or nil,
    learnFavor = first and first.recipe.name == r.name and first.learnFavor or nil,
  }
end

-- A step picked on the planner's Route & shopping tab, shown instead of the current step.
Helper.preview = nil -- { prof, step, index, total }

-- Plans are reused until your skill leaves the current step, or prices, settings, known
-- recipes or purchases change. A missing plan is worked out in the background (a few ms per
-- frame) and the panel updates when it's ready, so crafting never stutters.
local planCache, cacheSize = {}, 0
local waiting = {}
local function cachedPlan(prof, skill, from)
  local key = ns.RouteKey(prof) .. "|" .. tostring(skill) .. "|" .. tostring(from)
  local c = planCache[key]
  if c then return c end
  if not waiting[key] then
    waiting[key] = true
    ns.Async("helper", function()
      return ns.MakePlan({ profession = prof, liveSkill = from == nil, from = from, noCompare = true })
    end, function(plan)
      waiting[key] = nil
      if cacheSize >= 6 then planCache, cacheSize = {}, 0 end -- keep only the latest few
      planCache[key], cacheSize = plan, cacheSize + 1
      if Helper.Update then Helper.Update() end
    end)
  end
  return nil
end
function Helper.ClearCache() planCache, cacheSize, waiting = {}, 0, {} end

-- Works out what to show for the open profession.
function Helper.Compute(prof)
  local skill, maxSkill = ns.Game.GetSkill(prof)
  local lock = Helper.lock
  local locked = lock and lock.prof == prof and skill and skill >= (lock.from or 0) and skill < lock.to
  -- On a step, keep using the plan made when it started; replan only at its end.
  local plan = locked and cachedPlan(prof, lock.from) or cachedPlan(prof, skill)
  local view = { prof = prof, skill = skill, maxSkill = maxSkill, plan = plan }
  local pv = Helper.preview
  if not plan then
    if Helper.view and Helper.view.prof == prof and not Helper.view.pending then
      Helper.view.switchedFrom = nil -- already announced
      return Helper.view -- keep showing the last step until the new plan is ready
    end
    view.pending = true
    return view
  end
  if plan.error and not (pv and pv.prof == prof) then view.error = plan.error; return view end
  local data = ns.Recipes.Load(prof)
  local step
  if pv and pv.prof == prof then
    step = pv.step
    view.preview = pv
    view.after = pv.next
  elseif locked then
    step = stepFromLock(lock, skill, plan, data)
  end
  if view.preview then
    -- previewing: leave the lock alone
  elseif step then
    -- What comes after this step: the next step of the same plan.
    view.after = plan.steps and plan.steps[2] or nil
  else
    step = plan.steps[1]
    view.switchedFrom = lock and lock.prof == prof and lock.recipe ~= step.recipe.name and lock.recipe or nil
    Helper.lock = { prof = prof, recipe = step.recipe.name, from = step.from, to = step.to, cost = step.costPerCraft }
    view.after = plan.steps[2]
  end
  view.step = step
  local r = step.recipe
  view.recipe = r
  view.known = (ns.db.known[prof] or {})[r.name] or r.source == "A"
  view.recipeID = ns.db.recipeIDs[prof] and ns.db.recipeIDs[prof][r.name]
  view.craftable = craftableFromBags(prof, r)
  -- Remaining crafts for this step from the current skill.
  view.crafts = step.crafts
  view.toDo = math.min(view.crafts, view.craftable)

  -- Reagents for the rest of this step vs bags.
  view.reagents = {}
  for _, g in ipairs(r.reagents) do
    local need = g.qty * view.crafts
    view.reagents[#view.reagents + 1] = { name = g.name, need = need, have = inBags(g.name), per = g.qty }
  end

  -- Intermediates the plan has you make yourself, that you're short of for this step.
  view.makeFirst = {}
  local selfMade = {}
  for _, c in ipairs(plan.craftYourself or (pv and pv.craftYourself) or {}) do selfMade[c.name] = true end
  for _, g in ipairs(view.reagents) do
    local sub = data.byName[g.name]
    if sub and selfMade[g.name] and g.have < g.need then
      local short = g.need - g.have
      view.makeFirst[#view.makeFirst + 1] = { name = g.name, crafts = math.ceil(short / sub.makes), recipe = sub }
    end
  end

  -- Rank training due: you're near your current cap (e.g. 150 at Journeyman).
  if view.skill and view.maxSkill and view.maxSkill < 300 and view.skill >= view.maxSkill - 10 then
    for _, rank in ipairs(ns.RawData.Ranks) do
      if rank.cap - 75 == view.maxSkill then view.train = rank end
    end
  end
  return view
end

local function colour(have, need)
  return have >= need and "|cff33ff33" or "|cffff6060"
end

function Helper.Render(view)
  Helper.view = view
  local prof = view.prof
  if view.preview then
    w.skill:SetText(("|cffff9933Previewing step %d of %d. You're at %s %s: click Back.|r"):format(
      view.preview.index, view.preview.total, prof, view.skill and tostring(view.skill) or "?"))
    w.planner:SetText("Back")
  else
    w.skill:SetText(("%s  %s"):format(prof, view.skill and ("skill " .. view.skill) or ""))
    w.planner:SetText("Planner")
  end
  w.craft:Disable()
  w.open:SetEnabled(view.recipeID ~= nil)
  if view.pending then
    w.step:SetText("Working out your route…")
    w.detail:SetText("This takes a moment and won't slow the game down.")
    w.reagents:SetText(""); w.first:SetText(""); w.next:SetText("")
    w.craft:SetText("Craft")
    return
  end
  if view.error then
    w.step:SetText("No route yet")
    w.detail:SetText(view.error .. "\nScan the auction house from the planner so CraftPath knows prices.")
    w.reagents:SetText(""); w.first:SetText(""); w.next:SetText("")
    w.craft:SetText("Craft")
    return
  end
  local st, r = view.step, view.recipe
  w.step:SetText(r.name)
  local per = Money(st.costPerCraft)
  w.detail:SetText(("Skill %d to %d — about %d crafts left (%s each)"):format(st.from, st.to, view.crafts, per))

  local lines = { "|cffffd100Reagents (in bags / needed for this step)|r" }
  for _, g in ipairs(view.reagents) do
    local elsewhere = g.have < g.need and ns.Game.Elsewhere(g.name)
    lines[#lines + 1] = ("%s%d|r / %d  %s%s"):format(colour(g.have, g.need), g.have, g.need, g.name,
      elsewhere and ("  |cff66ccff(" .. elsewhere .. ")|r") or "")
  end
  w.reagents:SetText(table.concat(lines, "\n"))

  local first = {}
  if not view.known then
    local w = st.learnWhere
    local who = w and w.npc and (w.npc .. (w.where and (", " .. w.where) or "")) or nil
    local how
    if st.learnHow == "favor" then
      how = ("%s from %s"):format(st.learnFavor and (st.learnFavor .. " Merchant's Favor") or "Merchant's Favor", who or "the Favor vendor")
    elseif who and (st.learnHow == "trainer" or (w and w.trainer)) then
      how = "from " .. who
    elseif st.learnHow == "trainer" then
      how = "from your trainer"
    elseif who then
      how = ("buy %s from %s"):format(st.learnItem or "the recipe", who)
    elseif st.learnItem then
      how = "buy " .. st.learnItem .. (st.learnHow == "ah" and " on the auction house" or "")
    else
      how = "first"
    end
    first[#first + 1] = "|cffff9933Learn " .. r.name .. ": " .. how .. "|r"
    if w and w.note then first[#first + 1] = "|cff999999" .. w.note .. "|r" end
  end
  if view.train then
    first[#first + 1] = ("|cffff9933Train %s at your trainer (character level %d): you're capped at %d|r"):format(
      view.train.name, view.train.level, view.maxSkill)
  end
  if #view.makeFirst > 0 then
    first[#first + 1] = "|cffffd100Make first|r"
    for _, m in ipairs(view.makeFirst) do
      first[#first + 1] = ("%d× %s"):format(m.crafts, m.name)
    end
  end
  w.first:SetText(table.concat(first, "\n"))

  if view.after then
    w.next:SetText(("Then at %d: %s"):format(view.after.from, view.after.recipe.name))
  else
    w.next:SetText(("This step takes you to %d."):format(st.to))
  end

  local windowOpen = ns.Game.OpenProfession() == prof
  if view.known and view.recipeID and view.toDo > 0 and windowOpen then
    w.craft:SetText(("Craft %d"):format(view.toDo))
    w.craft:Enable()
  elseif view.known and view.craftable == 0 then
    w.craft:SetText(#view.makeFirst > 0 and "Make reagents first" or "Need reagents")
  else
    w.craft:SetText("Craft")
  end
end

-- Grow or shrink the panel so the text never runs past the buttons or the border.
local function fitHeight()
  local h = 30
  for _, key in ipairs({ "skill", "step", "detail", "reagents", "first", "next" }) do
    local fs = w[key]
    local text = fs:GetText()
    if text and text ~= "" then h = h + fs:GetStringHeight() + 8 end
  end
  frame:SetHeight(math.max(200, h + 46))
end

function Helper.Update()
  if not ns.db or not ns.db.settings.craftHelper then return end
  local prof = ns.Game.OpenProfession() or (Helper.preview and Helper.preview.prof)
  if not prof then if frame then frame:Hide() end return end
  if not frame then create() end
  local parent = profFrame() or (Helper.preview and CraftPathFrame and CraftPathFrame:IsShown() and CraftPathFrame)
  if parent and not frame.userMoved then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
  end
  frame:Show()
  local view = Helper.Compute(prof)
  Helper.Render(view)
  fitHeight()
  if view.switchedFrom then
    -- End of a step: stop any batch still crafting the old recipe, select the new one.
    if C_TradeSkillUI.StopRecipeRepeat then pcall(C_TradeSkillUI.StopRecipeRepeat) end
    ns.Print(("Skill %d: %s is done for this route. Next: |cffffd100%s|r (to %d)."):format(
      view.skill or 0, view.switchedFrom, view.recipe.name, view.step.to))
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST then
      pcall(PlaySound, SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST)
    end
  end
  -- Keep Blizzard's window on the step's recipe (once per recipe, so you can browse freely).
  if view.recipeID and Helper.selected ~= view.recipeID and ns.Game.OpenProfession() == prof then
    Helper.selected = view.recipeID
    Helper.ShowRecipe()
  end
end

-- Opens a route step from the planner in this panel.
function Helper.ShowStep(prof, step, index, total, plan)
  plan = plan or ns.lastPlan
  Helper.preview = {
    prof = prof, step = step, index = index, total = total,
    next = plan and plan.steps and plan.steps[index + 1] or nil,
    craftYourself = plan and plan.craftYourself or nil,
  }
  Helper.Update()
end

function Helper.Craft()
  local v = Helper.view
  if not v or not v.recipeID or not v.toDo or v.toDo < 1 then return end
  local ok, err = pcall(C_TradeSkillUI.CraftRecipe, v.recipeID, v.toDo)
  if not ok then ns.Print("Couldn't start crafting: " .. tostring(err)) end
end

function Helper.ShowRecipe()
  local v = Helper.view
  if not v or not v.recipeID then return end
  if C_TradeSkillUI.OpenRecipe then pcall(C_TradeSkillUI.OpenRecipe, v.recipeID) end
  if ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.RecipeList then
    pcall(function() ProfessionsFrame.CraftingPage.RecipeList:SelectRecipe(C_TradeSkillUI.GetRecipeInfo(v.recipeID)) end)
  end
end

-- Refresh after bag changes (throttled) and straight after every skill-up.
local pending = false
local function soon(delay)
  if pending or not frame or not frame:IsShown() then return end
  pending = true
  C_Timer.After(delay or 0.5, function() pending = false; Helper.Update() end)
end
ns.On("BAG_UPDATE_DELAYED", function() soon(0.5) end)
-- A skill-up while crafting means you're back on the route: drop any preview.
local function skillUp()
  if Helper.preview and ns.Game.OpenProfession() then Helper.preview = nil end
  soon(0.1)
end
ns.On("SKILL_LINES_CHANGED", skillUp)
ns.On("CHAT_MSG_SKILL", skillUp)
-- Opening the profession window always starts on your current step.
ns.On("TRADE_SKILL_SHOW", function() Helper.preview = nil end)

ns.On("TRADE_SKILL_CLOSE", function()
  Helper.selected = nil
  if Helper.preview then C_Timer.After(0, Helper.Update) elseif frame then frame:Hide() end
end)
