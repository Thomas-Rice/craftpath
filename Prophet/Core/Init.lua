-- Prophet: CraftPath's profit companion. What to craft today for a profit, whether to smelt
-- your ore or sell it, and a history of what you've bought, sold and crafted.
--
-- It runs on CraftPath's shared core (CraftPathAPI: prices and scans, recipes, game state,
-- the profit engine), so it needs CraftPath installed; CraftPath doesn't need Prophet.
-- Its own data and settings are in ProphetDB (ns.pdb).

local ns = CraftPathAPI
ns.Prophet = ns.Prophet or {}
local Prophet = ns.Prophet

local DEFAULTS = { profitUnknown = false, profitSort = "safe", ledgerPeriod = "week", ledgerMine = false }

local function setup()
  ProphetDB = ProphetDB or {}
  local db = ProphetDB
  db.settings = db.settings or {}
  -- Moving over from CraftPath, where Profits and History used to live: bring their history
  -- and settings with them (once).
  local old = CraftPathDB
  if not db.migrated and type(old) == "table" then
    if old.ledger and not db.ledger then db.ledger, old.ledger = old.ledger, nil end
    local os_ = old.settings or {}
    for k in pairs(DEFAULTS) do
      if db.settings[k] == nil and os_[k] ~= nil then db.settings[k] = os_[k] end
    end
    db.migrated = true
  end
  for k, v in pairs(DEFAULTS) do
    if db.settings[k] == nil then db.settings[k] = v end
  end
  ns.pdb = db
end

ns.On("ADDON_LOADED", function(name)
  if name == "Prophet" then setup() end
end)

function Prophet.Slash(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if msg == "history" or msg == "ledger" then
    ns.LedgerUI.Toggle()
  elseif msg == "help" then
    ns.Print("/prophet — Profits: what to craft today for a profit, and smelt your ore or sell it")
    ns.Print("/prophet history — what you've bought, sold and crafted, and what made a profit")
  else
    ns.ProfitUI.Toggle()
  end
end

SLASH_PROPHET1 = "/prophet"
SLASH_PROPHET2 = "/cprofit"
SlashCmdList.PROPHET = function(msg) Prophet.Slash(msg) end

function Prophet_OnAddonCompartmentClick()
  ns.ProfitUI.Toggle()
end
