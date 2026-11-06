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
  local w = setmetatable({ __kind = kind, __scripts = {}, __shown = true, __text = "" }, Widget)
  if name then _G[name] = w end
  table.insert(frames, w)
  return w
end
Widget.__index = function(t, k)
  local m = rawget(Widget, k)
  if m then return m end
  return function(self, ...) return self end
end
function Widget:SetScript(k, fn) self.__scripts[k] = fn end
function Widget:GetScript(k) return self.__scripts[k] end
function Widget:CreateFontString() return newWidget("FontString") end
function Widget:CreateTexture() return newWidget("Texture") end
function Widget:SetText(t) self.__text = t end
function Widget:GetText() return self.__text end
function Widget:GetStringWidth() return 50 end
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
function GetProfessionInfo(i) if i == 1 then return "Engineering", 0, 112 else return "Mining", 0, 90 end end
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
  GetAllRecipeIDs = function() return { 1, 2, 3 } end,
  GetRecipeInfo = function(id) return ({ { name = "Rough Blasting Powder", learned = true }, { name = "Thorium Widget", learned = true },
    { name = "Shiny New Gizmo", learned = false } })[id] end,
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
    tabs = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Shopping list"]
    tabs[0].Click(tabs[0])
    rows = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__kind == "Button" and isinstance(f.item, str)]
    assert rows, "no shopping rows"
    rows[0].Click(rows[0], "LeftButton")
    assert G.__searched == rows[0].item
    rows[0].Click(rows[0], "RightButton")
    assert ns.db.done[rows[0].item]
    notes = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Notes"]
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
    assert "Confirm" in ns.Buyer.ButtonText()
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
    assert "buy anyway" in ns.Buyer.ButtonText()
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
    shop = [f for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if f.__text == "Shopping list"]
    shop[0].Click(shop[0])
    texts = [f.__text for f in [G.__frames[i] for i in range(1, len(G.__frames) + 1)] if isinstance(f.__text, str)]
    assert any(t.startswith("Engineering run") for t in texts), "run summary missing"
    ns.Shopping.Stop()

    # Slash command and closing the AH.
    G.SlashCmdList.CRAFTPATH("help")
    fire("AUCTION_HOUSE_CLOSED")
    print("Addon smoke test passed.")


if __name__ == "__main__":
    main()
