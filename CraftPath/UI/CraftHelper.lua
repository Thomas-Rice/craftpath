-- CraftPath: crafting helper. Opens beside your profession window and walks the route:
-- the current step, reagents in your bags, intermediates to make first, and a Craft button.
-- It replans from your live skill after every skill-up, so it moves on by itself.

local _, ns = ...
ns.CraftHelper = {}
local Helper = ns.CraftHelper

local frame, w = nil, {}
local Money = function(c) return ns.Prices.Money(c) end
local lastStep -- recipe name of the step shown last time, to announce changes

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

local function button(parent, text, width, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function create()
  frame = CreateFrame("Frame", "CraftPathCraftHelper", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(300, 330)
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

  w.craft = button(frame, "Craft", 130, function() Helper.Craft() end)
  w.craft:SetPoint("BOTTOMLEFT", 12, 12)
  w.open = button(frame, "Show recipe", 90, function() Helper.ShowRecipe() end)
  w.open:SetPoint("LEFT", w.craft, "RIGHT", 6, 0)
  w.planner = button(frame, "Planner", 60, function() ns.UI.Toggle() end)
  w.planner:SetPoint("LEFT", w.open, "RIGHT", 6, 0)
  frame:Hide()
end

-- Works out what to show for the open profession.
function Helper.Compute(prof)
  local plan = ns.MakePlan({ profession = prof, liveSkill = true })
  local skill, maxSkill = ns.Game.GetSkill(prof)
  local view = { prof = prof, skill = skill, maxSkill = maxSkill, plan = plan }
  if plan.error then view.error = plan.error; return view end
  local step = plan.steps[1]
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
  for _, c in ipairs(plan.craftYourself or {}) do selfMade[c.name] = true end
  local data = ns.Recipes.Load(prof)
  for _, g in ipairs(view.reagents) do
    local sub = data.byName[g.name]
    if sub and selfMade[g.name] and g.have < g.need then
      local short = g.need - g.have
      view.makeFirst[#view.makeFirst + 1] = { name = g.name, crafts = math.ceil(short / sub.makes), recipe = sub }
    end
  end

  view.after = plan.steps[2]
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
  w.skill:SetText(("%s  %s"):format(prof, view.skill and ("skill " .. view.skill) or ""))
  w.craft:Disable()
  w.open:SetEnabled(view.recipeID ~= nil)
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
    lines[#lines + 1] = ("%s%d|r / %d  %s"):format(colour(g.have, g.need), g.have, g.need, g.name)
  end
  w.reagents:SetText(table.concat(lines, "\n"))

  local first = {}
  if not view.known then
    local how = st.learnHow == "trainer" and "from your trainer"
      or (st.learnItem and ("— buy " .. st.learnItem)) or "first"
    first[#first + 1] = "|cffff9933Learn " .. r.name .. " " .. how .. "|r"
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

  if view.known and view.recipeID and view.toDo > 0 then
    w.craft:SetText(("Craft %d"):format(view.toDo))
    w.craft:Enable()
  elseif view.known and view.craftable == 0 then
    w.craft:SetText(#view.makeFirst > 0 and "Make reagents first" or "Missing reagents")
  else
    w.craft:SetText("Craft")
  end
end

function Helper.Update()
  if not ns.db or not ns.db.settings.craftHelper then return end
  local prof = ns.Game.OpenProfession()
  if not prof then if frame then frame:Hide() end return end
  if not frame then create() end
  local parent = profFrame()
  if parent and not frame.userMoved then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPRIGHT", 4, 0)
  end
  frame:Show()
  local view = Helper.Compute(prof)
  if view.recipe and lastStep and lastStep ~= view.recipe.name then
    ns.Print(("Skill %d: switch to |cffffd100%s|r."):format(view.skill or 0, view.recipe.name))
    if PlaySound and SOUNDKIT and SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST then
      pcall(PlaySound, SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED_TOAST)
    end
  end
  lastStep = view.recipe and view.recipe.name or nil
  Helper.Render(view)
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

-- Refresh after crafts, skill-ups and bag changes (throttled).
local pending = false
local function soon()
  if pending or not frame or not frame:IsShown() then return end
  pending = true
  C_Timer.After(0.5, function() pending = false; Helper.Update() end)
end
ns.On("BAG_UPDATE_DELAYED", soon)
ns.On("SKILL_LINES_CHANGED", soon)
ns.On("CHAT_MSG_SKILL", soon)
ns.On("TRADE_SKILL_CLOSE", function() if frame then frame:Hide() end end)
