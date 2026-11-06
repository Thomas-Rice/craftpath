# CraftPath

A World of Warcraft: Forever addon that works out the **cheapest way to level a profession** from your realm's live auction house prices, then gives you a shopping list you can click through at the auction house.

Starting with **Engineering** and **Blacksmithing**. A companion website showing the same routes is planned.

## What it does

- **Plans the route** from your current skill to your target (up to 300). For every skill point it picks the recipe with the lowest expected gold per point, using the Classic skill-up rule (orange always, yellow and green fall off linearly to grey).
- **Prices every reagent** as the cheapest of the auction house, an NPC vendor, or crafting it yourself (for example, making your own Solid Blasting Powder instead of buying it).
- **Counts schematics and plans**: vendor and auction house recipes are charged once, and Merchant's Favor recipes are free in gold.
- **Builds a shopping list** by replaying the route, so items you make along the way (powders, bolts, grinding stones) are used before anything is bought. Items in your bags and bank are subtracted.
- **Scans the auction house** in three ways:
  - *Passive*: any search you do on the Buy tab records prices.
  - *Scan materials*: searches every reagent the profession uses, one by one, like an Auctionator shopping list.
  - *Full scan*: one-click full AH read (Blizzard allows one every 15 minutes).
- **Learns real vendor prices** when you open a merchant, and **reads the recipes you know** when you open your profession window.
- **Tooltips** show the last auction price CraftPath saw for an item.

### Shopping runs and buying

On the Shopping list tab, click **Start shopping run**. This freezes the list (quantities and planned prices) and notes what was already in your bags, so the route doesn't reshuffle while you buy.

- **Buy next** fetches the live price of the next item. Click again to **Confirm** and buy it.
  - Blizzard only allows a purchase to start from a click, so there is no fully automatic buying: it takes one click to get the price and one to buy.
  - If the live price is more than *Max over plan %* (default 25%) above the plan, the button asks before buying.
  - **Skip** moves on to the next item.
- **Every auction house purchase is tracked**, including ones made in Blizzard's own window. CraftPath watches the purchase calls, so items count as bought immediately, even while they're still in the mailbox.
- Each row shows what's left, bought vs needed, and the average paid against the plan. The run's total spend and what's left are in the summary.
- Vendor items: buy them at the vendor and right-click to tick them off.
- **End shopping run** clears the run. A log of the last 500 purchases is kept.

CraftPath never posts or cancels auctions.

### Crafting helper

Open your profession window and CraftPath opens a panel beside it. The panel shows:
- the current step (recipe, skill range, crafts left);
- the reagents in your bags against what the step needs;
- anything to make first (bolts, powders, grinding stones), and any recipe to learn or rank to train;
- the next recipe after this one.

**Craft N** crafts as many as your bags allow. **Show recipe** selects it in Blizzard's window. After each skill-up the panel replans from your new skill, and when it's time to change recipe it says so in chat. `/cpath craft` turns the panel on or off.

## Install

Copy the `CraftPath` folder into `World of Warcraft/_forever_/Interface/AddOns/` (or your Forever client's `Interface/AddOns`), then `/reload`.

## Use

1. `/cpath` opens the planner (it also opens beside the auction house).
2. Choose a profession. Leave **Start from my current skill** ticked, or set From/To.
3. At the auction house, click **Scan materials** (or **Full scan**).
4. Read the **Route** tab, then work through the **Shopping list** tab.

Options:
- *Buy schematics/plans*
- *Merchant's Favor recipes*
- *Stop at my level's cap*: Journeyman needs level 10, Expert 20, Artisan 35.
- Engineering specialisation (Goblin or Gnomish).
- *Working Overtime rank*: the Legacy perk, +4% skill-up chance per rank.

Commands:
- `/cpath scan`: full scan
- `/cpath list`: materials scan
- `/cpath reset`: clear prices
- `/cpath help`

## Data

The recipe data is in `CraftPath/Data/` as one line per recipe:

`Name|learn|orange|yellow|green|grey|makes|source|Reagent*qty;…`

It comes from the WoW: Forever client data (build 1.60.1.70790) as published by metabot.gg, and is checked against Wowhead's Forever leveling guides. Recipes that need hidden or raid-only items, an Anarchist's Workbench, or are learned at 300+ are left out.

To add a profession, add `Data/<Profession>.lua` in the same format and list it in `CraftPath.toc`.

## Keeping recipes up to date

Forever is new, so recipes are still being added. CraftPath keeps up in two ways:

- **From the game client (daily).** `.github/workflows/recipe-sync.yml` runs `tools/sync_recipes.py` every morning. The script:
  - finds the newest Forever client build on [wago.tools](https://wago.tools), product `wowf`;
  - downloads that build's recipe tables: `SkillLineAbility`, `SpellName`, `SpellReagents`, `SpellEffect` and `ItemSparse`;
  - rebuilds `Data/*.lua`;
  - opens a pull request listing new, changed and removed recipes.

  Sources set by hand are kept: Merchant's Favor, gold vendors, Goblin/Gnomish only. Trainer recipes don't carry a learn skill in the client, so the existing number is kept, and new trainer recipes are estimated and flagged in the PR.
- **From the game itself (as you play).**
  - Opening a profession window logs any recipe the game shows that CraftPath's data lacks, with its reagents.
  - Opening a trainer records the real skill each recipe needs; the planner uses these over the data's estimates.
  - Logged recipes are listed on the Notes tab.

To run the sync by hand: `python3 tools/sync_recipes.py` (or `--build 1.60.1.70790`).

## Known limits

- **Trainer learn skills.** The client doesn't state when a trainer offers some recipes, so a few of those are estimated.
- **Vendor estimates.** Vendor reagent and schematic prices start as Classic-era estimates and are replaced the first time you visit that merchant. Estimated prices are marked "(est.)".
- **Trainer fees** aren't counted.
- **Working Overtime.** The bonus is assumed to add 4 percentage points per rank.
- **Recipe sources.** For recipe items ("R"), the route only uses a recipe once its schematic or plan has been seen on the auction house or at a vendor.

## Development

```
pip install lupa
python3 tests/run_tests.py --show   # planner tests + sample routes
python3 tests/check_addon.py        # whole addon against a stubbed WoW API
python3 tests/test_sync.py          # recipe sync against wago.tools-style CSVs
python3 tools/export_json.py        # recipe data → web/data/recipes.json for the website
```

The planner (`Core/Planner.lua`) and data parser (`Core/Recipes.lua`) are plain Lua 5.1 with no game calls. They run the same in tests, in game, and can be ported to the website.
