-- CraftPath recipe data: Engineering (WoW: Forever)
-- Source: WoW Forever client data (build 1.60.1.70790) as published by metabot.gg,
-- cross-checked against Wowhead's "Tried & Tested in Forever" Engineering route (Nov 2026).
--
-- Line format:
--   Name|learn|orange|yellow|green|grey|makes|source|Reagent*qty;Reagent*qty
-- Sources:
--   A = learned automatically     T = trainer
--   R = recipe item (drop/AH)     F = Merchant's Favor vendor (no gold)
--   V:Vendor name = gold vendor   G = Goblin Engineering only   N = Gnomish Engineering only
-- A line starting with "@SET " is expanded once per variant: %V = variant name, %G = its gem.
-- Recipes that need rare/hidden items, an Anarchist's Workbench, or are learned at 300+
-- are left out: they can't help reach 300.

local _, ns = ...
ns.RawData = ns.RawData or {}

ns.RawData.Engineering = {
  tools = { "Arclight Spanner" },
  recipes = [[
Rough Blasting Powder|1|1|20|30|40|1|A|Rough Stone*1
Crafted Light Shot|1|1|30|45|60|200|A|Rough Blasting Powder*1;Copper Bar*1
Rough Dynamite|1|1|30|45|60|2|A|Rough Blasting Powder*1;Linen Cloth*1
Reagent Bot|20|20|20|23|25|1|T|Handful of Copper Bolts*1;Copper Tube*1
SAF-T Dynamite|25|25|25|30|35|1|F|Rough Blasting Powder*2;Linen Cloth*1
SAF-T Tabs|25|25|25|28|30|1|F|Linen Cloak*1;Cerulean Dye*1
Handful of Copper Bolts|30|30|45|53|60|1|T|Copper Bar*1
Arclight Spanner|50|50|70|80|90|1|T|Copper Bar*6
Rough Copper Bomb|51|51|60|75|90|2|T|Copper Bar*1;Handful of Copper Bolts*1;Rough Blasting Powder*2;Linen Cloth*1
SAF-T Copper Bomb|55|55|55|60|65|1|F|Copper Bar*1;Handful of Copper Bolts*1;Rough Blasting Powder*2;Linen Cloak*1;SAF-T Tabs*2
Copper Tube|75|75|80|95|110|1|T|Copper Bar*2;Weak Flux*1
Mechanical Squirrel Box|75|75|105|120|135|1|R|Copper Modulator*1;Handful of Copper Bolts*1;Copper Bar*1;Malachite*2
Rough Boomstick|80|80|80|95|110|1|T|Copper Tube*1;Handful of Copper Bolts*1;Wooden Stock*1
Coarse Blasting Powder|75|75|85|90|95|1|T|Coarse Stone*1
Crafted Heavy Shot|85|85|85|90|95|200|T|Coarse Blasting Powder*1;Copper Bar*1
Coarse Dynamite|85|85|90|98|105|2|T|Coarse Blasting Powder*3;Linen Cloth*1
Crude Scope|90|90|90|105|120|1|T|Copper Tube*1;Malachite*1;Handful of Copper Bolts*1
Satchel of Copper Bombs|85|85|90|93|95|1|F|Rough Copper Bomb*20;Light Leather*6;Handful of Copper Bolts*4
Copper Modulator|90|90|95|110|125|1|T|Handful of Copper Bolts*2;Copper Bar*1;Linen Cloth*2
Bronze Tube|100|100|105|130|155|1|T|Bronze Bar*2;Weak Flux*1
Ez-Thro Dynamite|100|100|115|123|130|2|R|Coarse Blasting Powder*3;Linen Cloth*1;EZ-Thro Wrap*1
EZ-Thro Wrap|100|100|100|103|105|1|F|Wool Cloth*1;Sulfuric Acid*1
Large Copper Bomb|100|100|105|130|155|3|T|Copper Bar*3;Coarse Blasting Powder*4;Silver Contact*1
Small Seaforium Charge|100|100|130|145|160|1|R|Coarse Blasting Powder*2;Copper Modulator*1;Light Leather*1;Refreshing Spring Water*1
Silver Contact|100|100|110|125|140|5|T|Silver Bar*1
Practice Lock|110|110|115|123|130|1|T|Bronze Bar*1;Handful of Copper Bolts*2;Weak Flux*1
Target Dummy|110|110|115|130|145|1|T|Copper Modulator*1;Handful of Copper Bolts*2;Bronze Bar*1;Wool Cloth*1
Small Bronze Bomb|115|115|120|145|170|2|T|Coarse Blasting Powder*4;Bronze Bar*2;Silver Contact*1;Wool Cloth*1
9-60 Battery Pack|120|120|125|135|145|1|R|Cerulean Dye*1;Pyrite*1;Iron Bar*1
Heavy Blasting Powder|120|120|125|135|145|1|T|Heavy Stone*1
Heavy Dynamite|120|120|125|135|145|3|T|Heavy Blasting Powder*2;Wool Cloth*1
Crafted Solid Shot|125|125|125|135|145|200|T|Heavy Blasting Powder*1;Bronze Bar*1
Lovingly Crafted Boomstick|120|120|145|158|170|1|R|Bronze Tube*2;Handful of Copper Bolts*2;Heavy Stock*1;Moss Agate*3
Shadow Goggles|120|120|145|158|170|1|R|Medium Leather*4;Shadowgem*2
Whirring Bronze Gizmo|120|120|125|150|175|1|T|Bronze Bar*2;Wool Cloth*1
Deadly Blunderbuss|125|125|130|143|155|1|T|Copper Tube*2;Handful of Copper Bolts*4;Wooden Stock*1;Medium Leather*2
Flame Deflector|125|125|125|150|175|1|R|Whirring Bronze Gizmo*1;Small Flame Sac*1
Flying Tiger Goggles|125|125|130|145|160|1|T|Light Leather*6;Tigerseye*2
Gnomish Universal Remote|125|125|150|163|175|1|R|Bronze Bar*6;Whirring Bronze Gizmo*1;Flask of Oil*2;Tigerseye*1;Malachite*1
Sandpaper|125|125|130|143|155|1|T|Bauxite*2;Bolt of Linen Cloth*1
@SET ROCKET Small %V Rocket|125|125|125|138|150|5|R|Coarse Blasting Powder*1;Medium Leather*1
EZ-Thro Copper Bomb XL|130|130|130|155|180|1|F|Copper Bar*3;Coarse Blasting Powder*4;Silver Contact*1;EZ-Thro Wrap*1
Standard Scope|130|130|135|148|160|1|T|Bronze Tube*1;Moss Agate*1
Big Bronze Bomb|135|135|140|165|190|3|T|Heavy Blasting Powder*2;Bronze Bar*3;Silver Contact*1
Shredder Autosalvage Unit|135|135|135|140|145|1|R|Bronze Framework*1;Whirring Bronze Gizmo*2;Heavy Leather*1
Bronze Framework|140|140|145|170|195|1|T|Bronze Bar*2;Medium Leather*1;Wool Cloth*1
Hoof-Shaped Foot Pedal|140|140|150|155|160|1|R|Iron Strut*3;Bronze Framework*2;Gyrochronatom*1;Gold Power Core*1;Heavy Leather*4
Minor Recombobulator|140|140|165|178|190|1|R|Bronze Tube*1;Whirring Bronze Gizmo*2;Medium Leather*2;Moss Agate*1
Repair Bot|140|140|140|143|145|1|R|Whirring Bronze Gizmo*2;Bronze Tube*1;Heavy Leather*1
Aquadynamic Fish Attractor|145|145|150|160|170|3|T|Bronze Bar*2;Nightcrawlers*1;Coarse Blasting Powder*1
Gold Power Core|145|145|150|170|190|3|T|Gold Bar*1
Moonsight Rifle|145|145|170|183|195|1|R|Bronze Tube*3;Whirring Bronze Gizmo*3;Heavy Stock*1;Lesser Moonstone*2
No Slip SAF-T Padding|145|145|145|148|150|1|F|Heavy Leather*1;Magenta Dye*1
SAF-T Bronze Bomb|145|145|145|170|195|1|R|Coarse Blasting Powder*4;Bronze Bar*2;Silver Contact*1;Wool Cloth*1;No Slip SAF-T Padding*1
@SET FIREWORK %V Firework|150|150|150|163|175|3|R|Heavy Blasting Powder*1;Heavy Leather*1
SAF-T Jumbo Dynamite|150|150|150|160|170|1|R|Heavy Blasting Powder*2;Wool Cloth*1;No Slip SAF-T Padding*1
Silver-plated Shotgun|150|150|155|168|180|1|T|Bronze Tube*2;Whirring Bronze Gizmo*2;Heavy Stock*1;Silver Bar*3
Ice Deflector|155|155|175|185|195|1|R|Whirring Bronze Gizmo*1;Frost Oil*1
Iron Strut|155|155|160|170|180|1|T|Iron Bar*2
Ornate Spyglass|155|155|160|173|185|1|T|Bronze Tube*2;Whirring Bronze Gizmo*2;Copper Modulator*1;Moss Agate*1
Explosive Sheep|160|160|175|188|200|1|T|Bronze Framework*1;Whirring Bronze Gizmo*1;Heavy Blasting Powder*2;Wool Cloth*2
Discombobulator Ray|160|160|180|190|200|1|R|Whirring Bronze Gizmo*3;Silk Cloth*2;Jade*1;Bronze Tube*1
Goblin Jumper Cables|165|165|165|180|200|1|R|Iron Bar*6;Whirring Bronze Gizmo*2;Flask of Oil*2;Silk Cloth*2;Shadowgem*2;Fused Wiring*1
Gyrochronatom|165|165|170|190|210|1|T|Iron Bar*1;Gold Power Core*1
Portable Bronze Mortar|165|165|185|195|205|1|R|Bronze Tube*4;Iron Strut*1;Heavy Blasting Powder*4;Medium Leather*4
Satchel of Bronze Bombs|165|165|170|173|175|1|F|Big Bronze Bomb*20;Medium Leather*6;Whirring Bronze Gizmo*1
Compact Harvest Reaper Kit|170|170|175|195|215|1|T|Iron Strut*2;Bronze Framework*1;Gyrochronatom*2;Heavy Leather*4
Green Tinted Goggles|170|170|175|188|200|1|T|Medium Leather*4;Moss Agate*2;Flying Tiger Goggles*1
Gyromatic Micro-Adjustor|170|170|175|195|215|1|T|Steel Bar*4
Iron Grenade|170|170|175|195|215|3|T|Iron Bar*1;Heavy Blasting Powder*1;Silk Cloth*1
Solid Blasting Powder|170|170|175|185|195|1|T|Solid Stone*2
Solid Dynamite|170|170|175|185|195|2|T|Solid Blasting Powder*1;Silk Cloth*1
Bright-Eye Goggles|175|175|195|205|215|1|R|Heavy Leather*6;Citrine*2
@SET ROCKET Large %V Rocket|175|175|175|188|200|5|R|Heavy Blasting Powder*1;Heavy Leather*1
SAF-T Bell|175|175|175|178|180|1|F|Bronze Bar*2;Sandpaper*1
Shafety Sheep|175|175|200|213|225|1|R|Bronze Framework*1;Whirring Bronze Gizmo*1;Heavy Blasting Powder*2;Wool Cloth*2;SAF-T Bell*1
Accurate Scope|180|180|200|210|220|1|R|Bronze Tube*1;Jade*1;Citrine*1
Advanced Target Dummy|180|180|185|205|225|1|T|Iron Strut*1;Bronze Framework*1;Gyrochronatom*1;Heavy Leather*4
Big Iron Bomb|185|185|190|210|230|2|T|Iron Bar*3;Heavy Blasting Powder*3;Silver Contact*1
Craftsman's Monocle|185|185|205|215|225|1|R|Heavy Leather*6;Citrine*2
Flash Bomb|185|185|185|205|225|1|R|Blue Pearl*1;Heavy Blasting Powder*1;Silk Cloth*1
Centaur Banner Deployment Device|190|190|190|198|205|1|R|Iron Strut*6;Gyrochronatom*2;Gold Power Core*4;Heavy Leather*30
EZ-Thro Bronze Mortar|190|190|210|220|230|1|R|Bronze Tube*4;Iron Strut*1;Heavy Blasting Powder*4;Medium Leather*4;EZ-Thro Fireproof Fuse*1
EZ-Thro Fireproof Fuse|190|190|190|193|195|1|F|Silver Contact*1;Pristine Hide*1
Mithril Tube|190|190|195|215|235|1|T|Mithril Bar*3
Snowmaster 9000|190|190|190|210|230|1|R|Mithril Bar*8;Gyrochronatom*4;Snowball*4;Frost Oil*1
Goblin Land Mine|195|195|215|225|235|1|R|Heavy Blasting Powder*3;Iron Bar*2;Gyrochronatom*1
Mechanical Repair Kit|195|195|200|220|240|1|T|Mithril Bar*1;Mageweave Cloth*1;Solid Blasting Powder*1
Unstable Trigger|195|195|200|220|240|1|T|Mithril Bar*1;Mageweave Cloth*1;Solid Blasting Powder*1
Ez-Thro Dynamite II|200|200|200|210|220|1|R|Solid Blasting Powder*1;Silk Cloth*1;EZ-Thro Fireproof Fuse*1
EZ-Thro Grenade|200|200|200|220|240|1|R|Iron Bar*1;Heavy Blasting Powder*1;Silk Cloth*1;EZ-Thro Fireproof Fuse*1
Gnomish Cloaking Device|200|200|220|230|240|1|R|Gyrochronatom*4;Jade*2;Lesser Moonstone*2;Citrine*2;Fused Wiring*1
Recipe: Goblin Rocket Fuel|200|200|205|205|205|1|G|Blank Parchment*1;Engineer's Ink*1
Plans: Inlaid Mithril Cylinder|200|200|205|205|205|1|N|Blank Parchment*1;Engineer's Ink*1
Goblin Sapper Charge|200|200|205|225|245|1|G|Mageweave Cloth*1;Solid Blasting Powder*3;Unstable Trigger*1
Large Seaforium Charge|200|200|200|220|240|1|R|Solid Blasting Powder*2;Heavy Leather*2;Refreshing Spring Water*1
Mechanical Dragonling|200|200|220|230|240|1|R|Bronze Framework*1;Iron Strut*4;Gyrochronatom*4;Citrine*2;Fused Wiring*1
Mobile Alarm|200|200|205|225|245|1|T|Mithril Tube*1;Unstable Trigger*1;Mithril Bar*4
Explosive Arrow|205|205|210|230|250|100|T|Razor Arrow*100;Solid Blasting Powder*2;Mithril Bar*2
Hi-Impact Mithril Slugs|205|205|210|230|250|200|T|Mithril Bar*1;Solid Blasting Powder*1
Goblin Mining Helmet|205|205|225|235|245|1|G|Mithril Bar*8;Citrine*1;Elemental Earth*4
Deadly Scope|210|210|230|240|250|1|R|Mithril Tube*1;Aquamarine*2;Thick Leather*2
Mithril Casing|210|210|215|235|255|1|T|Mithril Bar*3
Mithril Frag Bomb|210|210|215|235|255|3|T|Mithril Casing*1;Unstable Trigger*1;Solid Blasting Powder*1
SAF-T Bomb|215|215|215|230|245|1|R|Iron Bar*3;Heavy Blasting Powder*3;Silver Contact*1;SAF-T Casing*1
SAF-T Casing|215|215|215|218|220|1|R|Mithril Casing*1;Heavy Leather*1
Fire Goggles|220|220|225|235|245|1|T|Green Tinted Goggles*1;Citrine*2;Elemental Fire*2;Heavy Leather*4
Goblin Construction Helmet|220|220|225|235|245|1|G|Mithril Bar*8;Citrine*1;Elemental Fire*4
Goblin Mortar|220|220|225|235|245|1|G|Mithril Tube*2;Mithril Bar*4;Solid Blasting Powder*5;Gold Power Core*1;Elemental Fire*1
Gnomish Shrink Ray|220|220|225|235|245|1|N|Mithril Tube*1;Unstable Trigger*1;Mithril Bar*4;Flask of Mojo*4;Jade*2
Mithril Blunderbuss|220|220|225|235|245|1|T|Mithril Tube*1;Unstable Trigger*1;Heavy Stock*1;Mithril Bar*4;Elemental Fire*2
Mithril Heavy-bore Rifle|220|220|240|250|260|1|R|Mithril Tube*2;Unstable Trigger*1;Heavy Stock*1;Mithril Bar*6;Citrine*2
@SET ROCKET %V Rocket Cluster|225|225|225|238|250|5|R|Solid Blasting Powder*1;Thick Leather*1
Compact Critter Carrier|225|225|230|233|235|1|F|Heavy Leather*10;Mithril Tube*10;Greater Nether Essence*2;Gold Power Core*1
Emergency Field Cloak|225|225|245|255|265|1|F|Gnomish Cloaking Device*1;SAF-T Casing*1
Ez-Thro Radiation Bomb|225|225|225|230|235|3|R|Solid Blasting Powder*2;Gnomeregan Fallout*1;Mithril Bar*2
High-Yield Radiation Bomb|225|225|225|230|235|3|R|Solid Blasting Powder*1;Gnomeregan Fallout*1;Mithril Bar*2
Firework Launcher|225|225|245|255|265|1|R|Inlaid Mithril Cylinder*2;Goblin Rocket Fuel*2;Unstable Trigger*2;Mithril Casing*1
Parachute Cloak|225|225|245|255|265|1|R|Bolt of Mageweave*4;Shadow Silk*2;Unstable Trigger*1;Solid Blasting Powder*4
Spellpower Goggles Xtreme|225|225|245|255|265|1|R|Thick Leather*4;Star Ruby*2
Deepdive Helmet|230|230|250|260|270|1|R|Mithril Bar*8;Mithril Casing*1;Truesilver Bar*1;Tigerseye*4;Malachite*4
Goblin "Boom" Box|230|230|235|245|255|1|T|Mithril Casing*1;Solid Blasting Powder*2;Gold Power Core*1;Mithril Bar*2
Hi-Explosive Bomb|230|230|235|255|275|4|T|Mithril Casing*2;Unstable Trigger*1;Solid Blasting Powder*2
Satchel of Iron Bombs|230|230|235|238|240|1|F|Big Iron Bomb*20;Thick Leather*6;Gyrochronatom*1
Gnomish Ham Radio|235|235|240|250|260|1|T|Mithril Casing*1;Mithril Bar*2;Gyrochronatom*1;Unstable Trigger*1
Goblin Radio|235|235|240|250|260|1|T|Mithril Casing*1;Mithril Bar*2;Gyrochronatom*1;Unstable Trigger*1
EZ-Thro Tru-Trigger|240|240|240|243|245|1|R|Truesilver Bar*1;Viridian Dye*1
Mithril Gyro-Shot|240|240|245|265|285|200|T|Mithril Bar*2;Solid Blasting Powder*2
Sniper Scope|240|240|260|270|280|1|R|Mithril Tube*1;Star Ruby*1;Truesilver Bar*2
Tru-Trigger Frag Bomb|240|240|240|260|280|1|R|Mithril Casing*1;Unstable Trigger*1;Solid Blasting Powder*1;EZ-Thro Tru-Trigger*1
Dense Blasting Powder|245|245|250|255|260|1|T|Dense Stone*2
Dense Dynamite|245|245|250|260|270|2|T|Dense Blasting Powder*2;Runecloth*3
Rose Colored Goggles|245|245|250|260|270|1|T|Thick Leather*6;Star Ruby*2
Creepy Censor Sensors|250|250|275|278|280|1|R|Rugged Leather*8;Azerothian Diamond*2
Gnomish Army Knife|250|250|250|253|255|1|F|Mithril Casing*1;Gold Power Core*1;Thorium Widget*2
Mithril Mechanical Dragonling|250|250|270|280|290|1|R|Mithril Bar*14;Heart of Fire*4;Truesilver Bar*4;Inlaid Mithril Cylinder*2;Goblin Rocket Fuel*2;Star Ruby*2
Pop-Up Shrub|250|250|255|258|260|1|R|Thorium Widget*1;Unstable Trigger*1;Bronze Framework*1
Snake Burst Firework|250|250|250|260|270|4|R|Dense Blasting Powder*2;Runecloth*2;Deeprock Salt*1
Tinkerbox|255|255|260|270|280|1|R|Mithril Casing*1;Gold Power Core*2
Green Lens|260|260|265|275|285|1|T|Thick Leather*8;Jade*3;Aquamarine*3;Heart of the Wild*2;Wildvine*2
Thorium Grenade|260|260|280|290|300|3|R|Thorium Widget*1;Thorium Bar*3;Dense Blasting Powder*3;Runecloth*3
Thorium Rifle|260|260|280|290|300|1|R|Mithril Tube*2;Mithril Casing*2;Thorium Widget*2;Thorium Bar*4;Deadly Scope*1
Thorium Widget|260|260|280|290|300|1|V:Sovik (Orgrimmar)|Thorium Bar*3;Runecloth*1
Truesilver Transformer|260|260|270|275|280|1|R|Truesilver Bar*2;Elemental Earth*2;Elemental Air*1
Lifelike Mechanical Toad|265|265|285|295|305|1|R|Living Essence*1;Thorium Widget*4;Gold Power Core*1;Rugged Leather*1
Salt Shaker|265|265|270|280|290|1|T|Mithril Casing*1;Thorium Bar*6;Gold Power Core*1;Unstable Trigger*4
Spellpower Goggles Xtreme Plus|270|270|290|300|310|1|R|Spellpower Goggles Xtreme*1;Star Ruby*4;Enchanted Leather*2;Runecloth*8
Dark Iron Rifle|275|275|295|305|315|1|R|Thorium Tube*2;Dark Iron Bar*6;Deadly Scope*2;Blue Sapphire*2;Large Opal*2;Rugged Leather*4
Cluster Launcher|275|275|295|305|315|1|R|Inlaid Mithril Cylinder*3;Goblin Rocket Fuel*3;Truesilver Transformer*1;Mithril Casing*1
@SET ROCKET Large %V Rocket Cluster|275|275|275|280|285|5|R|Dense Blasting Powder*1;Rugged Leather*1
Loot-A-Rang|275|275|275|278|280|1|R|Thorium Bar*5;Greater Eternal Essence*5
Major Recombobulator|275|275|285|290|295|1|R|Thorium Tube*2;Truesilver Transformer*1;Runecloth*2
Masterwork Target Dummy|275|275|295|305|315|1|R|Mithril Casing*1;Thorium Tube*1;Thorium Widget*2;Truesilver Bar*1;Rugged Leather*2;Runecloth*4
Powerful Seaforium Charge|275|275|275|285|295|1|R|Thorium Widget*2;Dense Blasting Powder*3;Rugged Leather*2;Refreshing Spring Water*1
SAF-T Clever Dynamite|275|275|275|285|295|1|R|Dense Blasting Powder*2;Runecloth*3;SAF-T Tube*1
SAF-T Tube|275|275|275|278|280|1|R|Thorium Bar*1;Azerothium Bar*1
Steam Tonk Controller|275|275|295|305|315|1|R|Thorium Widget*2;Mithril Casing*1;Gold Power Core*1
Thorium Tube|275|275|295|305|315|1|V:Xizzer Fizzbolt (Winterspring)|Thorium Bar*6
Dark Iron Bomb|285|285|305|315|325|3|R|Thorium Widget*2;Dark Iron Bar*1;Dense Blasting Powder*3;Runecloth*3
Delicate Arcanite Converter|285|285|305|315|325|1|R|Arcanite Bar*1;Ironweb Spider Silk*1
EZ-Thro Shell|285|285|285|288|290|1|R|Thorium Bar*2;Pristine Scale*1
EZ-Thro Thorium Grenade|285|285|285|295|305|1|R|Thorium Widget*1;Thorium Bar*3;Dense Blasting Powder*3;Runecloth*3;EZ-Thro Shell*1
Thorium Shells|285|285|305|315|325|200|R|Thorium Bar*2;Dense Blasting Powder*1
Master Engineer's Goggles|290|290|310|320|330|1|R|Fire Goggles*1;Huge Emerald*2;Enchanted Leather*4
]],
}
