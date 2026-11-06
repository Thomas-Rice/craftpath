"""Loads every addon file in .toc order against a stubbed WoW API and drives the
in-game flow: login, auction house open, browse results, shopping-list scan, merchant,
profession window, and opening the planner window. Catches syntax errors, nil calls and
typos in the game-facing code that the pure planner tests can't reach.
"""
import os
from lupa import lua51

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CraftPath")

STUBS = r"""
local unpack = unpack
local timers, events, frames = {}, {}, {}
_G.__timers, _G.__frames = timers, frames
local now = 1800000000
function time() return now end
function __advance(sec) now = now + sec end
function tostringall(...) local t = {...} for i=1,select('#',...) do t[i]=tostring(t[i]) end return unpack(t) end
function wipe(t) for k in pairs(t) do t[k]=nil end return t end
function tinsert(t, v) table.insert(t, v) end
function geterrorhandler() return function(e) error(e, 0) end end
UISpecialFrames = {}
SlashCmdList = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) table.insert(__chat, m) end }
__chat = {}
function UnitLevel() return 30 end
function GetCoinTextureString(c) return tostring(c) .. "c" end
function GameTooltip_Hide() end
Enum = { AuctionHouseSortOrder = { Price = 0 }, TooltipDataType = { Item = 0 }, ItemCommodityStatus = { Item = 1, Commodity = 2 } }
function hooksecurefunc(t, name, fn)
  local orig = t[name]
  t[name] = function(...) local r = { orig(...) }; fn(...); return unpack(r) end
end
AuctionHouseFrameDisplayMode = { Buy = 1 }
C_AddOns = { GetAddOnMetadata = function() return "0.1.0" end }
C_Timer = { After = function(sec, fn) table.insert(timers, fn) end }
function __runTimers() local n=0 while #timers>0 and n<500 do local fn=table.remove(timers,1) fn() n=n+1 end end

-- Generic widget: every method exists and returns a widget/self.
local Widget = {}
local function newWidget(kind, name)
  local w = setmetatable({ __kind = kind, __scripts = {}, __shown = true, __text = "", __points = {},
    __w = false, __h = false, __wrap = "unset", __template = false, __parent = false, __fs = false }, Widget)
  if name then _G[name] = w end
  table.insert(frames, w)
  return w
end
Widget.__index = function(t, k)
  local m = rawget(Widget, k)
  if m then return m end
  -- Only WoW-style method names (Capitalised) get a do-nothing stand-in; data fields stay nil.
  if type(k) == "string" and k:match("^%u") then return function(self, ...) return self end end
  return nil
end
function Widget:SetScript(k, fn) self.__scripts[k] = fn end
function Widget:SetSize(w, h) self.__w, self.__h = w, h end
function Widget:SetWidth(w) self.__w = w end
function Widget:SetHeight(h) self.__h = h end
function Widget:GetParent() return self.__parent end
function Widget:ClearAllPoints() self.__points = {} end
function Widget:SetPoint(point, a, b, c, d)
  self.__points = self.__points or {}
  local rel, relPoint, x
  if type(a) == "number" or a == nil then rel, relPoint, x = self.__parent, point, a or 0
  elseif type(b) == "string" then rel, relPoint, x = a, b, c or 0
  else rel, relPoint, x = a, point, b or 0 end
  self.__points[point] = { rel = rel, relPoint = relPoint, x = x }
end
function Widget:SetWordWrap(v) self.__wrap = v end
function Widget:SetScrollChild(c) c.__parent = self; c.__points = { TOPLEFT = { rel = self, relPoint = "TOPLEFT", x = 0 } } end
function Widget:GetFontString() if not self.__fs then self.__fs = newWidget("FontString"); self.__fs.__parent = self end return self.__fs end
function Widget:GetScript(k) return self.__scripts[k] end
function Widget:CreateFontString(_, _, template)
  local fs = newWidget("FontString"); fs.__parent = self; fs.__template = template; return fs
end
function Widget:CreateTexture() return newWidget("Texture") end
function Widget:SetText(t) self.__text = t; if self.__kind == "Button" and self.__fs then self.__fs.__text = t end end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return 50 end
function Widget:GetStringHeight() local _, n = tostring(self.__text):gsub("\n", "") return (n + 1) * 12 end
function Widget:Show() self.__shown = true; local f = self.__scripts.OnShow; if f then f(self) end end
function Widget:Hide() self.__shown = false end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self.__shown end
function Widget:GetChecked() return self.__checked end
function Widget:SetChecked(v) self.__checked = v end
function Widget:HasFocus() return false end
function Widget:RegisterEvent(e) events[e] = events[e] or {}; table.insert(events[e], self) end
function Widget:Click(btn) self.__scripts.OnClick(self, btn or "LeftButton") end
function CreateFrame(kind, name, parent, template)
  local w = newWidget(kind, name)
  w.__parent = parent or false
  if template and template:find("FrameTemplate") then w.TitleText = newWidget("FontString") end
  return w
end
UIParent = newWidget("Frame")
GameTooltip = newWidget("GameTooltip")
function __fire(event, ...)
  for _, f in ipairs(events[event] or {}) do f.__scripts.OnEvent(f, event, ...) end
end

-- Game data
function GetProfessions() return 1, 2 end
function GetProfessionInfo(i) if i == 1 then return "Engineering", 0, __engSkill, 150 else return "Mining", 0, 90, 150 end end
__engSkill = 112
C_Item = {
  GetItemCount = function(n) if n == "Copper Bar" then return 20 end return 0 end,
  GetItemInfo = function(id) return __itemNames[id] end,
  GetItemNameByID = function(id) return __itemNames[id] end,
}
__itemNames = { [2840] = "Copper Bar", [2841] = "Bronze Bar", [2835] = "Rough Stone" }
local nextId = 900000
local function idFor(name)
  for id, n in pairs(__itemNames) do if n == name then return id end end
  nextId = nextId + 1; __itemNames[nextId] = name; return nextId
end
__browse = {}
__queries = {}
C_AuctionHouse = {
  GetItemKeyInfo = function(key) return { itemName = __itemNames[key.itemID] } end,
  GetBrowseResults = function() return __browse end,
  IsThrottledMessageSystemReady = function() return true end,
  SendBrowseQuery = function(q)
    table.insert(__queries, q.searchString)
    local price = __ahPrices[q.searchString]
    __browse = {}
    if price then __browse = { { itemKey = { itemID = idFor(q.searchString) }, minPrice = price, totalQuantity = 50 } } end
    C_Timer.After(0, function() __fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED") end)
  end,
  GetItemCommodityStatus = function(id) return (__itemNames[id] or ""):find("^Plans:") and 1 or 2 end,
  StartCommoditiesPurchase = function(id, qty)
    table.insert(__ahCalls, "start " .. __itemNames[id] .. " " .. qty)
    local unit = __livePrice[__itemNames[id]] or 0
    C_Timer.After(0, function() __fire("COMMODITY_PRICE_UPDATED", unit, unit * qty) end)
  end,
  ConfirmCommoditiesPurchase = function(id, qty)
    table.insert(__ahCalls, "confirm " .. __itemNames[id] .. " " .. qty)
    C_Timer.After(0, function() __fire("COMMODITY_PURCHASE_SUCCEEDED") end)
  end,
  CancelCommoditiesPurchase = function() table.insert(__ahCalls, "cancel") end,
  MakeItemKey = function(id) return { itemID = id } end,
  SendSearchQuery = function(key)
    C_Timer.After(0, function() __fire("ITEM_SEARCH_RESULTS_UPDATED", key) end)
  end,
  GetNumItemSearchResults = function() return 1 end,
  GetItemSearchResultInfo = function(key, i) return { auctionID = 4242, buyoutAmount = __livePrice[__itemNames[key.itemID]] } end,
  PlaceBid = function(auctionID, amount)
    table.insert(__ahCalls, "bid " .. auctionID .. " " .. amount)
    C_Timer.After(0, function() __fire("AUCTION_HOUSE_PURCHASE_COMPLETED", auctionID) end)
  end,
  ReplicateItems = function() C_Timer.After(0, function() __fire("REPLICATE_ITEM_LIST_UPDATE") end) end,
  GetNumReplicateItems = function() return #__replicate end,
  GetReplicateItemInfo = function(i)
    local r = __replicate[i + 1]
    return r.name, nil, r.count, 1, true, 1, 0, 0, 0, r.buyout, 0, false, nil, "x", "x", 0, idFor(r.name), true
  end,
}
__replicate = {}
__ahCalls = {}
__livePrice = {}
C_TradeSkillUI = {
  GetBaseProfessionInfo = function() return { professionName = "Engineering" } end,
  GetAllRecipeIDs = function() if __helperRecipe then return { 1, 2, 3, 99 } end return { 1, 2, 3 } end,
  GetRecipeInfo = function(id) if id == 99 then return { name = __helperRecipe, learned = true, numAvailable = 5 } end return ({ { name = "Rough Blasting Powder", learned = true }, { name = "Thorium Widget", learned = true },
    { name = "Shiny New Gizmo", learned = false } })[id] end,
  CraftRecipe = function(id, n) __crafted = { id, n } end,
  StopRecipeRepeat = function() __stopped = (__stopped or 0) + 1 end,
  OpenRecipe = function(id) __opened = id end,
  GetRecipeSchematic = function(id) return { quantityMin = 2, reagentSlotSchematics = {
    { quantityRequired = 3, reagents = { { itemID = 2840 } } } } } end,
}
function GetMerchantNumItems() return 2 end
__trainerFilter = { available = 1, unavailable = 0, used = 0 }
function GetTrainerServiceTypeFilter(f) return __trainerFilter[f] == 1 end
function SetTrainerServiceTypeFilter(f, v) __trainerFilter[f] = v end
function GetNumTrainerServices() return 3 end
function GetTrainerServiceInfo(i) return ({ "Copper Tube", "Journeyman Engineering", "Trainer Only Widget" })[i] end
function GetTrainerServiceSkillReq(i) return "Engineering", ({ 60, 50, 140 })[i] end
C_MerchantFrame = { GetItemInfo = function(i)
  return ({ { name = "Weak Flux", price = 95, stackCount = 1 }, { name = "Schematic: Thorium Widget", price = 4500, stackCount = 1 } })[i]
end }
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) __tooltipFn = fn end }
AuctionHouseFrame = newWidget("Frame", "AuctionHouseFrame")
AuctionHouseFrame.SearchBar = newWidget("Frame")
AuctionHouseFrame.SearchBar.SearchBox = newWidget("EditBox")
function AuctionHouseFrame.SearchBar:StartSearch() __searched = self.SearchBox:GetText() end
"""


import re as _re

def text_width(fs):
    """Rough pixel width of a font string's visible text (WoW fonts, colour codes removed)."""
    t = fs.__text if isinstance(fs.__text, str) else ""
    t = _re.sub(r"\|c[0-9a-fA-F]{8}|\|r|\|T[^|]*\|t", "", t)
    per = 7.2 if fs.__template in ("GameFontNormal", "GameFontHighlight") else 6.0
    if fs.__template == "GameFontHighlightLarge":
        per = 8.5
    longest = max((len(l) for l in t.split("\n")), default=0)
    return longest * per


def check_layout(G, root_name):
    frames = [G.__frames[i] for i in range(1, len(G.__frames) + 1)]
    root = G[root_name]

    def parent_chain(w):
        while w is not None and w is not False:
            yield w
            w = w.__parent

    def width(w, depth=0):
        pts = w.__points or {}
        if depth > 30:
            return 0
        if ("LEFT" in pts or "TOPLEFT" in pts) and ("RIGHT" in pts or "TOPRIGHT" in pts):
            return right_anchor(w, depth) - left(w, depth)
        if w.__w:
            return w.__w
        if w.__kind == "FontString":
            return text_width(w)
        return 0

    def anchor_x(p, depth):
        rel = p.rel
        if rel is None or rel is False:
            return 0
        base = left(rel, depth + 1)
        rp = p.relPoint
        if rp in ("RIGHT", "TOPRIGHT", "BOTTOMRIGHT"):
            base += width(rel, depth + 1)
        elif rp in ("CENTER", "TOP", "BOTTOM"):
            base += width(rel, depth + 1) / 2
        return base + p.x

    def right_anchor(w, depth):
        pts = w.__points
        p = pts["RIGHT"] if "RIGHT" in pts else pts["TOPRIGHT"]
        return anchor_x(p, depth)

    def left(w, depth=0):
        if depth > 30 or w is None or w is False:
            return 0
        pts = w.__points or {}
        for name in ("LEFT", "TOPLEFT", "BOTTOMLEFT"):
            if name in pts:
                return anchor_x(pts[name], depth)
        for name in ("RIGHT", "TOPRIGHT", "BOTTOMRIGHT"):
            if name in pts:
                return anchor_x(pts[name], depth) - width(w, depth)
        if "CENTER" in pts:
            return anchor_x(pts["CENTER"], depth) - width(w, depth) / 2
        return 0

    root_left, root_right = left(root), left(root) + root.__w
    root.__layoutRoot = True
    bad = []
    for f in frames:
        if f.__layoutRoot is True or not any(x.__layoutRoot is True for x in parent_chain(f.__parent)):
            continue
        if not all(x.__shown for x in parent_chain(f)):
            continue
        if not isinstance(f.__text, str) and f.__kind == "FontString":
            continue
        pts = f.__points or {}
        if f.__kind == "FontString" and f.__wrap is False and len([k for k in pts if "LEFT" in k or "RIGHT" in k]) >= 2:
            continue  # spans two anchors and cuts its text: always fits
        if f.__kind == "FontString" and f.__parent and f.__parent.__kind == "Button" and f.__wrap is False:
            continue  # button label sized to the button and cut with "..."
        l = left(f)
        r = l + width(f)
        if r > root_right - 6 or l < root_left + 4:
            what = f.__text if isinstance(f.__text, str) and f.__text else f.__kind
            bad.append(f"{what!r}: x {l:.0f}..{r:.0f}, window {root_left:.0f}..{root_right:.0f}")
    root.__layoutRoot = False
    assert not bad, root_name + " has elements outside its window:\n  " + "\n  ".join(bad)


def main():
    lua = lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(STUBS)
    toc = open(os.path.join(ROOT, "CraftPath.toc"), encoding="utf-8").read().splitlines()
    files = [l.strip().replace("\\", "/") for l in toc if l.strip() and not l.startswith("##")]
    ns = lua.table()
    loader = lua.eval("function(src, name) return assert(loadstring(src, name)) end")
    for rel in files:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            loader(fh.read(), "@" + rel)("CraftPath", ns)

    G = lua.globals()
    fire = G.__fire
    prices = {
        "Rough Stone": 10, "Coarse Stone": 30, "Heavy Stone": 60, "Solid Stone": 80, "Dense Stone": 150,
        "Copper Bar": 40, "Bronze Bar": 100, "Silver Bar": 150, "Iron Bar": 120, "Gold Bar": 600,
        "Steel Bar": 200, "Mithril Bar": 250, "Thorium Bar": 300, "Linen Cloth": 10, "Wool Cloth": 40,
        "Silk Cloth": 60, "Mageweave Cloth": 100, "Runecloth": 150, "Medium Leather": 40, "Heavy Leather": 80,
    }
    G.__ahPrices = lua.table_from(prices)

    fire("ADDON_LOADED", "CraftPath")
    assert ns.db is not None, "saved variables not set up"

    # Opening the AH docks the window and plans with no prices (expect a clean error).
    fire("AUCTION_HOUSE_SHOW")
    G.__runTimers()
    assert G.CraftPathFrame is not None and G.CraftPathFrame.__shown
    assert ns.lastPlan.error, "expected 'no prices' error before scanning"

    # Passive capture of a manual search.
    G.__browse = lua.table_from([lua.table_from({"itemKey": lua.table_from({"itemID": 2840}), "minPrice": 38, "totalQuantity": 200})])
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    assert ns.Prices.AH("Copper Bar") == 38

    # Shopping-list scan: searches every reagent, records prices and "none listed".
    ns.Scanner.ScanShoppingList()
    G.__runTimers()
    queries = [G.__queries[i] for i in range(1, len(G.__queries) + 1)]
    assert "Thorium Bar" in queries and "Weak Flux" not in queries, queries[:10]
    assert ns.Prices.AH("Thorium Bar") == 300
    assert ns.db.prices["Star Ruby"].none

    # Merchant prices replace the vendor estimates.
    fire("MERCHANT_SHOW")
    assert ns.Prices.Vendor("Weak Flux") == 95
    assert ns.Prices.Vendor("Schematic: Thorium Widget") == 4500

    # Known recipes are read from the profession window.
    fire("TRADE_SKILL_SHOW")
    assert ns.db.known["Engineering"]["Thorium Widget"]

    # Recipes the game shows that the data lacks, and trainer learn levels.
    seen = ns.db.seen["Engineering"]
    assert seen["Shiny New Gizmo"].reagents == "Copper Bar*3" and seen["Shiny New Gizmo"].makes == 2
    fire("TRAINER_SHOW")
    assert ns.db.trainer["Engineering"]["Copper Tube"] == 60
    assert seen["Trainer Only Widget"].learn == 140
    assert seen["Journeyman Engineering"] is None, "rank training logged as a recipe"
    assert G.__trainerFilter.unavailable == 0 and G.__trainerFilter.used == 0, "trainer filters not restored"

    # A plan item for a recipe CraftPath doesn't know, seen on the AH.
    G.__itemNames[777777] = "Plans: Secret Forever Hammer"
    G.__browse = lua.table_from([lua.table_from({"itemKey": lua.table_from({"itemID": 777777}), "minPrice": 50000, "totalQuantity": 1})])
    fire("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
    hammer = ns.db.seen["Blacksmithing"]["Secret Forever Hammer"]
    assert hammer and hammer.recipeItem == "Plans: Secret Forever Hammer" and hammer.price == 50000

    # Plan from the character's real skill (112), capped by level 30 -> 225.
    plan = ns.MakePlan()
    assert not plan.error, plan.error
    assert plan["from"] == 112 and plan.to == 225, (plan["from"], plan.to)

    # Window: tabs, row click searches the AH, right-click ticks off.
    ns.UI.Refresh()
    tabs = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "What to buy"]
    tabs[0].Click(tabs[0])
    rows = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__kind == "Button" and isinstance(f.item, str)]
    assert rows, "no shopping rows"
    rows[0].Click(rows[0], "LeftButton")
    assert G.__searched == rows[0].item
    rows[0].Click(rows[0], "RightButton")
    assert ns.db.done[rows[0].item]
    notes = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Notes & tips"]
    notes[0].Click(notes[0])
    texts = [f.__text for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if isinstance(f.__text, str)]
    assert any("Shiny New Gizmo" == t for t in texts), "unknown recipe not on Notes tab"

    # Full scan via ReplicateItems, then the 15-minute cooldown.
    G.__replicate = lua.table_from([lua.table_from({"name": "Mithril Bar", "count": 20, "buyout": 4000}),
                                    lua.table_from({"name": "Mithril Bar", "count": 5, "buyout": 1100})])
    ns.Scanner.FullScan()
    G.__runTimers()
    assert ns.Prices.AH("Mithril Bar") == 200, ns.Prices.AH("Mithril Bar")
    ns.Scanner.FullScan()
    assert any("15 minutes" in G.__chat[i] for i in range(1, len(G.__chat) + 1))

    # Tooltip line.
    tip = lua.eval("{ AddDoubleLine = function(self, a, b) self.line = b end }")
    G.__tooltipFn(tip, lua.table_from({"id": 2840}))
    assert tip.line and "38" in tip.line

    # ---- Shopping run and one-click buying ----
    plan = ns.MakePlan()
    ns.Shopping.Start(plan)
    run = ns.Shopping.Get()
    first, e = ns.Shopping.NextToBuy()
    assert first and e.source == "ah", first
    need = ns.Shopping.Left(first)
    G.__livePrice[first] = e.unit  # live price matches the plan
    ns.Buyer.Click()               # "Buy next": asks for a quote
    G.__runTimers()
    assert ns.Buyer.state == "confirm", ns.Buyer.state
    assert ns.Buyer.ButtonText().startswith("Buy "), ns.Buyer.ButtonText()
    ns.Buyer.Click()               # "Confirm": buys
    G.__runTimers()
    assert ns.Buyer.state is None
    assert run["items"][first].bought > 0, "purchase not tracked"
    assert run["items"][first].spent == run["items"][first].bought * e.unit

    # Too expensive: it stops and asks; Skip moves on.
    second, e2 = ns.Shopping.NextToBuy()
    if second == first:   # first item was capped by listed quantity; skip it for this check
        ns.Shopping.Skip(first); second, e2 = ns.Shopping.NextToBuy()
    G.__livePrice[second] = e2.unit * 3
    ns.Buyer.Click(); G.__runTimers()
    assert ns.Buyer.state == "pricey", ns.Buyer.state
    assert ns.Buyer.ButtonText().startswith("Buy anyway?"), ns.Buyer.ButtonText()
    ns.Buyer.SkipCurrent()
    assert ns.Shopping.NextToBuy() != second and run.skipped[second]

    # A purchase made in Blizzard's own window is tracked too.
    third, e3 = ns.Shopping.NextToBuy()
    tid = ns.db.ids[third]
    G.__livePrice[third] = e3.unit
    G.C_AuctionHouse.StartCommoditiesPurchase(tid, 2); G.__runTimers()
    G.C_AuctionHouse.ConfirmCommoditiesPurchase(tid, 2); G.__runTimers()
    assert run["items"][third].bought == 2, run["items"][third].bought

    # A single auction (a plan) bought by buyout is logged.
    G.__itemNames[3611] = "Plans: Green Iron Boots"; ns.db.ids["Plans: Green Iron Boots"] = 3611
    G.__livePrice["Plans: Green Iron Boots"] = 700
    fire("ITEM_SEARCH_RESULTS_UPDATED", lua.table_from({"itemID": 3611}))
    G.C_AuctionHouse.PlaceBid(4242, 700); G.__runTimers()
    log = [ns.db.purchases[i] for i in range(1, len(ns.db.purchases) + 1)]
    assert log[-1].item == "Plans: Green Iron Boots" and log[-1].total == 700

    # The Shopping list tab shows the run.
    shop = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "What to buy"]
    shop[0].Click(shop[0])
    texts = [f.__text for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if isinstance(f.__text, str)]
    assert any(t.startswith("Buying for Engineering") for t in texts), "run summary missing"
    ns.Shopping.Stop()

    # ---- Crafting helper ----
    view = ns.CraftHelper.Compute("Engineering")
    assert view.recipe and view.step["from"] == 112, view.error
    G.__helperRecipe = view.recipe.name
    fire("TRADE_SKILL_SHOW")              # profession window opens: helper reads recipe 99
    helper = G.CraftPathCraftHelper
    assert helper is not None and helper.__shown, "helper not shown"
    v = ns.CraftHelper.view
    assert v.recipeID == 99 and v.known and v.toDo == 5, (v.recipeID, v.known, v.toDo)
    craft = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Craft 5"]
    assert craft, "Craft button missing"
    craft[0].Click(craft[0])
    assert G.__crafted[1] == 99 and G.__crafted[2] == 5
    # Step boundary: reaching the end of the step stops the batch and selects the next recipe.
    step_recipe, step_to = v.recipe.name, v.step.to
    assert G.__opened == 99, "step recipe not selected in Blizzard's window on open"
    G.__engSkill = step_to - 1 if step_to - 1 > 112 else 112
    fire("CHAT_MSG_SKILL"); G.__runTimers()
    assert ns.CraftHelper.view.recipe.name == step_recipe, "switched before the end of the step"
    nxt = ns.MakePlan(lua.table_from({"profession": "Engineering", "from": step_to})).steps[1].recipe.name
    ns.db.recipeIDs["Engineering"][nxt] = 100
    ns.db.known["Engineering"][nxt] = True
    G.__engSkill = step_to
    fire("CHAT_MSG_SKILL"); G.__runTimers()
    v2 = ns.CraftHelper.view
    assert v2.recipe.name == nxt and v2.recipe.name != step_recipe, (v2.recipe.name, step_recipe)
    assert G.__stopped == 1, "batch not stopped at the step boundary"
    assert G.__opened == 100, "next recipe not selected"
    assert any("is done for this route" in G.__chat[i] for i in range(1, len(G.__chat) + 1))
    Gcraft = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if isinstance(f.__text, str) and f.__text.startswith("Craft")]
    G.__engSkill = 112
    ns.CraftHelper.lock = None

    # Clicking a step on the Leveling steps tab shows its materials and opens it in the helper.
    steps_tab = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Leveling steps"][0]
    steps_tab.Click(steps_tab)
    plan = ns.lastPlan
    target = plan.steps[2]
    rows = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)]
            if f.__kind == "Button" and f.__shown and f.onClick and f.cols and isinstance(f.cols[2].__text, str)
            and f.cols[2].__text.endswith(target.recipe.name)]
    assert rows, "step row not found"
    rows[0].Click(rows[0], "LeftButton")
    texts = [f.__text for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if isinstance(f.__text, str)]
    reagent = target.recipe.reagents[1]
    assert any(t.strip() == ("%d× %s" % (reagent.qty, reagent.name)) for t in texts), "materials not shown"
    pv = ns.CraftHelper.view
    assert pv.preview and pv.recipe.name == target.recipe.name, "step not opened in the helper"
    assert G.CraftPathCraftHelper.__shown
    helper_texts = [f.__text for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if isinstance(f.__text, str)]
    assert any(t.startswith("|cff33bbffStep 2 of") for t in helper_texts), "preview header missing"
    back = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Back"]
    assert back, "Back button missing"
    back[0].Click(back[0])
    assert not ns.CraftHelper.preview and not ns.CraftHelper.view.preview
    rows[0].Click(rows[0], "LeftButton")                      # click again: collapses
    ns.CraftHelper.preview = None

    # Near the Journeyman cap: reminds to train Expert.
    G.__engSkill = 145
    v = ns.CraftHelper.Compute("Engineering")
    assert v.train and v.train.name == "Expert", v.train
    G.__engSkill = 112
    fire("TRADE_SKILL_CLOSE")
    assert not helper.__shown

    # ---- From box: always editable; typing a skill turns off "use my skill" ----
    ns.db.settings.useMySkill = True
    ns.UI.Refresh()
    from_box = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.key == "from"][0]
    assert from_box.__text == "112", from_box.__text        # shows live skill
    from_box.__scripts.OnEditFocusGained(from_box)
    from_box.__scripts.OnEditFocusLost(from_box)              # click in and out: nothing changes
    assert ns.db.settings.useMySkill
    ns.Shopping.Start(ns.MakePlan())                         # buying list, nothing bought yet
    from_box.__scripts.OnEditFocusGained(from_box)
    from_box.SetText(from_box, "130")
    from_box.__scripts.OnEnterPressed(from_box)
    assert not ns.db.settings.useMySkill and ns.db.settings["from"] == 130
    assert ns.Shopping.Get()["from"] == 130, "unbought list didn't follow the new range"
    first, _ = ns.Shopping.NextToBuy()
    ns.Shopping.Record(first, 1, 100)                        # buy something: list now locks
    from_box.__scripts.OnEditFocusGained(from_box)
    from_box.SetText(from_box, "140")
    from_box.__scripts.OnEnterPressed(from_box)
    assert ns.Shopping.Get()["from"] == 130 and ns.Shopping.Get().stale
    ns.Shopping.Stop()
    ns.db.settings.useMySkill = True
    ns.db.settings["from"] = 1

    # ---- Layout: nothing may stick out of its window ----
    check_layout(G, "CraftPathFrame")                 # buying bar, no session
    ns.Shopping.Start(ns.MakePlan()); ns.UI.Refresh()
    check_layout(G, "CraftPathFrame")                 # buying bar with session
    ns.Shopping.Stop()
    for tab in ("Leveling steps", "Notes & tips", "What to buy"):
        t = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == tab][0]
        t.Click(t)
        check_layout(G, "CraftPathFrame")
    fire("TRADE_SKILL_SHOW")
    check_layout(G, "CraftPathCraftHelper")
    fire("TRADE_SKILL_CLOSE")

    # Slash command and closing the AH.
    G.SlashCmdList.CRAFTPATH("help")
    fire("AUCTION_HOUSE_CLOSED")
    print("Addon smoke test passed.")


if __name__ == "__main__":
    main()
