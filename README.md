# Wasteland Colony

A 2D post-nuclear colony sim for Godot 4.7. Pixel-art tiles (or, if you like, ASCII ones in the style of Dwarf Fortress), with an amber terminal UI.

## Running it
1. Open Godot, click **Import**, and pick `project.godot` in this folder.
2. Press **F5**.

## Menus and music
- **Title screen.** The game opens on `art/title.png` with **New colony**, **Load game** and **Quit** over its dark lower edge (and
  **Resume** too when you open it again with the top bar's **Menu** button mid-game). The picture is 16:9: in a window of another shape it
  keeps its shape, with black bars. If the art can't be read it's the same choices in a plain text panel.
- **Character selection.** **New colony** leads to the three leaders, with the slab-stack logo (`art/logo.png`, cropped to the lettering
  by `LOGO_CROP` in `scripts/sprites.gd`) above them. **Back** returns to the title screen.
- **Music.** `audio/` holds six tracks. `wasteland_menu.wav` plays, looping, on the title screen, the character selection screen and the
  load screen, and carries on across them without restarting. Starting or loading a colony crossfades into the five `wasteland_OST_*`
  tracks, which play one after another in a shuffled order, then shuffle again, and never repeat a track back to back. Opening the menu in
  the middle of a game leaves the game music alone. `scripts/music.gd` does it all (an autoload called `Music`).
- **Volume.** The **Music** slider (bottom right of the title screen, on the character selection and load screens, and a small **♪** one in
  the top bar during a game) sets the music volume. All the way down is **completely off**: the music bus is muted, not just very quiet.
  They all show the same volume, and it's remembered between runs in `user://settings.cfg` (`%APPDATA%\Godot\app_userdata\Wasteland Colony\settings.cfg`,
  beside the saves). The tracks are imported uncompressed, exactly as supplied.

## Sending it to a friend (Windows)
Run `.\tools\build_windows.ps1`. It exports the game as a single `WastelandColony.exe` (the art and music are inside it), runs the
game's own self-check on the result (`WastelandColony.exe -- --selftest` prints one ok/FAIL line per thing the game loads: the atlas, the
title screen and logo, all six tracks, the data), and zips it with `tools/PLAY_ME.txt` (how to run it, the Windows "unrecognized app"
warning, where saves live). The zip lands in `..\WastelandColony3-release\`: send `WastelandColony-Windows.zip`.
- It needs Godot's Windows **export templates** once (Editor > Manage Export Templates), and the `Windows Desktop` preset in `export_presets.cfg`.
- Files the game reads at run time that aren't pictures or sound (`art/atlas.json`) have to be listed in that preset's include filter, and the
  tests and docs are left out. A pixel-art sprite that works from the editor but shows as text in the built game means a file didn't make it:
  run the self-check.
- On a screen smaller than the 1600 x 900 window, the game opens maximized.
- The exe has Godot's default icon and isn't code-signed. Setting a custom icon needs Godot's `rcedit` setting.

## Controls
- **WASD / arrows**: pan. **Mouse wheel**: zoom. **Right-drag**: pan.
- **Left-click** a tile to inspect, claim or build on it. Click one of your scouting parties to pick it. **Esc** deselects it.
- **END SEASON** runs gather, upkeep and the AI turn, then autosaves.
- **Map: ...** button (top bar) switches whose knowledge the map shows: yours, the Rust Kings', or no fog (debug).

## Fog of war
Every colony keeps its own memory of the map (`Game.memory`). Black tiles have never been seen.
Dim tiles were explored but are out of sight, so they show what was there last time.
Click a black or dim tile and press **Send scouts** to send a party there. You must find the Rust Kings and
Dustwell before you can raid, trade or befriend them. The Rust Kings scout west toward you, and only
raid once they've found you.

## Scouting parties
Scouts (`@`) walk to the tile you pick and **stay there, keeping watch**, until you click another tile and
send them on, or press **Recall to camp**. How many parties you can have out grows with horses and war rigs.
- Every survivor has a name, age and quirk. Click a party on the map and a **portrait** of each member appears in the bottom
  panel, with a hunger bar under it. Faces are drawn in code (`scripts/portrait.gd`) from a per-survivor seed, so the same person
  always looks the same, and they go grey and gaunt as they age or starve.
- **Food pack**: a party leaves with `SCOUT_PACK` (8) food taken from your stores (grain, then veg, then meat), and each survivor
  eats 1 a season from that pack, so two scouts last 4 seasons. The **Inventory** column beside the portraits shows what's in the pack
  and how many days it will last. Nothing resupplies them in the field: when the pack is empty they go hungry, then starve, and die
  after 3 hungry seasons in a row. Whatever is left goes back into your stores when they come home, so recall them in time.
- **Picking a party**: click a scouting party (or **Pick** on its card) and the map draws its route from where it stands, not from
  your HQ: click any tile to see the way there. The dots fade **white** (plenty of food) to **yellow** (running low, from 75% eaten,
  `FOOD_WARN`) to **red**, and a red ring marks the tile where the pack runs out. Red dots mean not enough food for that stretch of
  the journey. A party already on the move shows the rest of its path the same way. The tile panel adds the trip length and how many
  days short the food is. **Esc**, **Deselect**, or clicking your own land lets go and brings the HQ routes back.
- **Fuel**: a party in a war rig or plane takes a tank from your fuel stores (8 / 10), and so does a river trader boat (3, enough for a
  round trip of about 75 tiles, so a port more than ~37 tiles from a river mouth will run its boat dry on the way home; the Sail refits
  upgrade removes the tank). Driving burns fuel, and waiting burns more (a plane has to keep circling). The **fuel gauge** beside the
  portraits shows what's left, and its warning light blinks when the tank is low. Each vehicle has its own instrument, drawn in code
  (`scripts/fuel_gauge.gd`): a dashboard half-dial with a pump light for the war rig, a round cockpit dial for the plane, and a brass
  sight tube with a float on a teak board for the boat. Whole units of fuel still in the tank when the party comes home go back into
  your stores.
- **Out of fuel**: the vehicle is lost and the people aboard carry on as a party on foot. A war rig or boat is simply abandoned (a
  boat's crew wade ashore and walk home with what they traded). A **plane crashes**: each person aboard lives through it with a
  60% chance (`CRASH_SURVIVAL`), and the survivors lose 10-45 hp (`CRASH_INJURY`), show a bandage on their portrait and read "injured"
  until they heal (3 hp a season while they aren't irradiated). If nobody walks away, the party is gone. Tune it all in `VEHICLE_FUEL`,
  `FUEL_LOW`, `CRASH_*` and `SCOUT_RATION` in `scripts/data.gd`.

## Pixel art
The map and the Legend (the Tile tab with nothing selected) are drawn with pixel art: `art/atlas.png` holds 23 sprites of 8 x 8
pixels, three styles each, described by `art/atlas.json`. They cover the 11 kinds of ground, the two slopes, the 7 kinds of unit
(scavengers, scouts, caravans, war rigs, boats, recon planes, raider bands) and the three tribe camps.
- **Switching.** The **Art:** button in the top bar cycles style 1, style 2, style 3 and the old **text glyphs** (the Dwarf Fortress
  look), and the **Art style: 1 2 3 ASCII** buttons at the top of the legend do the same. It changes the map and the legend together.
- **The map.** A tile is 16 pixels wide, so every sprite shows at exactly 2x, crisp, with no gaps between tiles (it used to be 18).
  The ground sprite goes on every tile; a slope's mark goes on top of it at half strength so it doesn't drown the ground. Units and
  tribe camps are drawn over the ground. Ownership colors, borders, fog, the dimming of remembered land and the radiation tint all work
  as before (the tint goes over the sprites). **Buildings are still text**, because the atlas has no building art yet.
- **Speed.** Every sprite is drawn from the one atlas texture, so they batch: an idle frame takes about 100 draw calls where the glyphs
  took about 380. See `docs/rendering_perf.md`.
- **Tuning.** `scripts/sprites.gd` says which sprite draws which thing (`TERRAIN`, `SLOPES`, `UNITS`, `CAMPS`), sets the default style
  (`Sprites.style`) and can pin one sprite to a style whatever the buttons say (`PINNED`, e.g. `{"war_rig": 2}`). `SLOPE_TINT` in
  `scripts/map_view.gd` sets how faint the slope marks are. If the atlas can't be read, everything falls back to the text glyphs. To change
  the art, replace `art/atlas.png` and keep `art/atlas.json` describing it.

## What a party can carry
Goods have weight (`WEIGHT` in `scripts/data.gd`: grain, veg and meat 1 each, wood, metal and fuel 2, stone 3, gold 0.5). A party
counts its food pack and whatever it's hauling home, and the **Load** bar in its Inventory shows that against what it
can carry: **10 per survivor**, plus **20 for a horse, 30 for a plane, 50 for a war rig, 80 for a boat** (`CARRY_PER_PERSON`,
`CARRY_BY_MOVER`). So a foot party of three carries 30, with a horse 50, in a war rig 80. A vehicle's own fuel tank doesn't count.
- **Up to the limit nothing changes.** Past it, every step takes longer: twice as long for every 100% over (`OVERLOAD_SLOWDOWN`), and
  never worse than three times as long (`OVERLOAD_MAX`). That also means longer in the radiation, and a food pack that runs out before
  you arrive, and the route preview for a picked scouting party counts it.
- **Nobody picks up more than twice their limit** (`LOAD_CEILING`): they leave the rest behind, and the log says so. The same goes
  for what a party can still carry once its vehicle is lost.
- **Tuned so normal play is comfortable.** An average scavenger haul (about 22) leaves a foot party of three room to spare, a jackpot
  (up to 38) slows them down, and a horse or war rig party never notices. A full scout food pack (8) fits even a lone survivor.

## Slopes and travel
Every tile has a height in meters. Contour lines mark each 10 m step:
- `─ │ ┌ ┐` single lines are **gentle slopes**: everyone crosses them 1.5x slower.
- `═ ║ ╔ ╗` double lines are **steep inclines** (mesa and canyon edges): war rigs can't climb them
  and must find a way around; people on foot (4x slower) and horses (3x slower) can cross them.

Click any tile to see dotted routes from your HQ to it: white for foot, tan for horses, red for war rigs. (With a scouting party
picked, you get its own food-coloured route instead: see Scouting parties.)
Raids use the same routes. Long marches tire troops (down to 60% strength), and war rigs with no way
around the inclines stay home. Tune speeds and penalties in `MOVERS` in `scripts/data.gd`.

## Expeditions, tribes and raider bands
The map is 120 x 72. Things on the move are drawn over the tile they stand on:

| Symbol | What | |
|---|---|---|
| ☺ | Scavenger party | Click pre-war ruins to send one. Ruins may hide a booby trap or a rogue raider. |
| ♦ | Trade caravan | Send from the Diplomacy tab to the Rust Kings or a trader tribe. Gold comes home with it. |
| Θ | War rig | Any expedition sent by war rig (faster, tougher, hauls 1.5x loot). |
| ◊ | Boat | Click your port to send a boat downriver to trade. |
| Ж | Recon plane | Click any tile to fly recon over it; it maps everything it passes. |
| ☻ | Raider band | Wild raiders. They ambush expeditions and hit colony outskirts. |
| Δ | Tribe camp | Red: raiders (attack the camp). Yellow: traders (send caravans). Blue: builders (gift food and they join you). |

Crew leave your population while they're out, and vehicles on expeditions can't fight.
Swap any symbol in `UNITS` in `scripts/data.gd`. `docs/unit_glyph_options.png` shows the alternatives.

## The map
One river runs from the left edge of the map to the right, sloping south as it goes (`RIVER_MID_Y` and `RIVER_SLOPE` in
`scripts/data.gd`). It passes between the two camps' lands, so you start on one bank and the Rust Kings on the other. Both camps start in
open desert, with no craters or lone ruins nearby.

Each glowing crater (`o`) marks the epicenter of a big field of pre-war ruins (`EPICENTERS` of them). Ruins thin out toward the
edge, and a few lone ruins are scattered around too. Scavenge them for loot, but watch for traps and rogue raiders.

### Radiation
Every tile has a hidden radiation level in R/h. Craters glow hardest and it fades with distance; fused glass, fallout waste and the
ruin fields stay hot, and the camps start clean. Most of the wastes are harmless background (under 5 R/h).

- **Readings.** You only see a rough range for a tile (e.g. "roughly 30-80 R/h") until one of your scouting parties has stood on it.
  Scouts take a reading of every tile they walk across, and the exact figure is yours for the rest of the run, as is any land you own.
  The **Radiation** button in the top bar tints the tiles you've measured by band: safe, low, moderate, high, extreme.
- **Geiger counter.** Select a scouting party and a Geiger counter appears beside its panel: a needle on a log scale, a lamp that
  clicks faster the hotter it is, the reading, and how much poison a season there would cost.
- **Poison.** Radiation works like poison. Each survivor builds up a dose (decaying 10% a season) and loses hp for every point of
  it, so it never kills outright, but a long stay in a hot zone is fatal (about 17 seasons at 20 R/h, 8 at 60 R/h and 5 at crater level, on foot), and the
  poison lingers after you leave. Below 15 dose they start recovering. The portrait greens and sinks as they get sicker, and a purple
  bar under it is their health. War rigs, boats and planes shield the people inside (x0.5, x0.8, x0.2).
- **Travel icons.** Beside the portraits a small pixel icon shows how the party moves: a boot, a horse, a war rig, a boat or a plane.

### Catastrophes
Every crater was the epicenter of a catastrophe long before the game began, and each of the four kinds leaves its mark on the land
(click any tile in a ruin field or fallout plume to read its history):

| Catastrophe | What it did |
|---|---|
| Firestorm | Burned every scrap of greenery for miles around the ruins, so no wood grows there. |
| Fallout plume | A long tapering streak of yellow **fallout waste** blown off downwind, kept clear of the camps. |
| Glassing | Fused the ground round the crater into violet **glass**, ruins and all. |
| Shockwave quake | Split the ground with deep faults (steep inclines that war rigs can't cross) running out from the crater. |

All craters also have a raised rim. Greenery is scarce: about 4% of the map, down from 11%. Trees gather in a few big clumps (mostly
along the river), and just two green groves survive, well away from the ruin fields. The map is built in passes (`_generate_map` in
`scripts/game.gd` lists them): terrain, smoothing, river, trees, ruin fields, catastrophes, oases, lone ruins, camps, heights.

Build a **Port** (tier 3) on your riverbank to build boats; click it to launch one downriver to trade. Boats sail to the river
mouth where it meets the map edge.

Rare **green groves** (bright green ♣) yield 3 wood and 1 vegetable
per tile, and a hunting lodge in one gets +2 meat.

## Vehicle upgrades
Each leader branch (Warfare, Fortification, Commerce) has its own vehicle line on the Upgrades tab:
cheaper or stronger war rigs, sail-powered boats, counters to enemy vehicles, ethanol fuel, air freight
and more. The Rust Kings build horses, war rigs, boats and planes as the years pass.

**Refineries** turn 4 **veg** into 3 fuel each season (4 with Ethanol synthesis), but only once you switch them on: a new refinery
starts **off**. Click it on the map and press **Start refinery** (or **Stop refinery**); the Colony tab shows how many are running.
Switching is per refinery, and demolishing one resets it. A running refinery holds back whenever taking its veg would leave grain
+ veg short of feeding everyone (colonists and prisoners), so it can't starve the colony, and the log says when it did. Saves from
before the switch load with every refinery off.

## Resources and money
There are eight resources: **wood, stone, metal, fuel, grain, veg, meat and gold**. There is no scrap and no silver any more.
- **Metal** is what ruins give. A pre-war ruin you own makes 1 a season, a Salvage yard on it makes 3 more, and a scavenger party
  strips a ruin once for loot that is mostly metal (see "Scavenging: the d20 rolls": about 9 gold-equivalent a visit).
  A war rig brings back half as much again, but burns 2 fuel on the way (`SCAV_CAR_MULT`, `SCAV_CAR_FUEL`).
  War rigs cost 11 metal and 4 wood, and the War rig workshops upgrade 20 metal.
- **Gold** is the one currency. It pays for the Port, Airfield, planes, claiming land, and the upgrades that silver used to gate:
  Bribery (63 gold) and Merchant empire (128 gold), and a plane takes 28 gold. Silver was worth 1.25 gold at the old exchange rate
  (10 gold for 8 silver), and that is how those prices were converted. Trade contracts (Commerce tier 2) add 4 gold to every
  caravan and river boat, and Toll roads pay 1 gold for every 2 walls.
- **Fuel** comes from refineries and ruins, and sells 5 for 4 gold (buying costs double). A scouting party or boat brings home
  whole units of fuel left in its tank. Vehicles pay upkeep (a war rig 1, a plane 2 and 1 gold) only while they're at home:
  one that's out lives off its own tank.
- Old saves load fine: any scrap or silver in them is simply dropped.

## Scavenging: the d20 rolls
A scavenger party that reaches a ruin stops there and waits. Select it and the right panel shows **Scavenge**, a clickable pixel-art
d20 below it (`d20_dice/`, played at 1.25x), and what the next roll is. Click the die: it tumbles, lands on the number that was rolled,
and the number stays up for a second until you click off it. Every roll is one click; the design is in "D20 Roll System: Scavenging &
Combat" and the integration plan.
- **Each roll** is one d20 plus modifiers against a DC, and the margin gives `CRITICAL_FAILURE`, `FAILURE`, `SUCCESS` or
  `CRITICAL_SUCCESS` (a natural 1 or 20 always gives the critical ones). Modifiers are clamped to -5..+5.
- **The party rolls as one.** Every survivor has 1 to 3 traits (the 11 in `d20_data.gd`, rolled when the party is sent). The traits of
  the whole party combine, and a trait two survivors share counts once (three Magpies are worth one). The survivor in the best
  condition makes the roll; injuries and fumbles land on them. A Lucky trait gives the party one reroll.
- **Situation modifiers come from the game:** the ruin's radiation after the vehicle's shield (20 R/h -1, 45 -2, 80 -3), the roller's
  radiation sickness, hunger and injuries, and in a fight the enemy's strength against the party's (outnumbered -2; Veteran ignores
  it, Cowardly doubles it). A fight's DC is 6 + 2 x the enemy's strength. Arriving at a ruin measures its radiation, so the panel
  shows the modifier before the roll.
- **What a ruin starts with** comes from the map: a safe ruin rolls a plain d20 for what it holds (cache, small find or nothing, with
  the ambush and trap rows rerolled), a trapped ruin starts with a trap check at DC 14, a rogue-held one with an ambush check at DC 14
  and a fight. A trap or a won fight is a toll: the ruin is then searched like a safe one. A won fight takes 1 prisoner.
- **Loot** is a package (small, medium or large) of one resource picked by a d20 (metal 40%, fuel 20%, gold 25%, veg 15%), its dice
  times `LOOT_SCALE` (3) and a war rig's 1.5.
- **Search deeper:** a CRITICAL_SUCCESS on a cache check offers another cache check at DC +3 (twice at most), paying a size larger. A
  CRITICAL_FAILURE on a deeper search loses half of what was found at the site and draws an ambush.
- **Injuries replace deaths:** light is -1 and severe means that survivor can't roll, both until the party is home. With permadeath on
  (it is), a CRITICAL_FAILURE in a fight at DC 14 or more rolls a fumble d20, and 1 to 5 kills the whole party.
- `scripts/d20_data.gd` holds every number, `scripts/d20.gd` the rules, `scripts/d20_visit.gd` one visit as a series of rolls,
  `scripts/dice.gd` the dice. Tests use `tests/helpers/forced_dice.gd` to choose each number (`tests/unit/test_d20.gd`, `test_visit.gd`,
  and `tests/render/test_visit_panel.gd` for the panel).

## Points of interest
Each map has one of ten 2 x 2 sites (`Data.POIS`, art in `art/poi_atlas.png`): a crashed ship, weather station, chemical dump, radio tower,
bunker, oil pumpjack, water tower, ruined gas station, missile silo and cargo yard. Each stands where it fits (water towers and cargo yards
by the river, bunkers and silos 6 to 16 tiles from a ruin field, towers on or beside rock, the chemical dump on fallout waste, the pumpjack
in deep desert), 12 tiles from any camp and 10 from the next site. A site is four tiles that carry one building id (`poi_<kind>`), so the
fog, saves and the map treat it like a building: each tile draws its quarter of the sprite. You can't build on one or demolish it. Click any
of its tiles and send one scavenger party; it works the whole site as one tile and all four read "picked clean" afterwards.

**Searching a site** is one d20 "Site check" in the right-hand Scavenge panel (the party's scavenge modifiers and the situation, against the
site's DC), and the tier of the roll picks that site's outcome. There is no search deeper, and "Leave without searching" keeps the site
unsearched. The DCs: weather station, water tower, gas station and cargo yard 11; crashed ship, chemical dump, radio tower, bunker and
pumpjack 14; missile silo 17. `SITES` in `scripts/d20_data.gd` holds every outcome as data (a name and a list of effects, documented
above the table), so changing one is a one-line edit. Packages pay `POI_LOOT_MULT` (1.5) times an ordinary ruin's. The outcomes, as approved in
the doc "Points of Interest: Dice Outcome Options":

| Site | SUCCESS | CRITICAL_SUCCESS | FAILURE | CRITICAL_FAILURE |
|---|---|---|---|---|
| Crashed ship | medium metal, small fuel | medium metal, map within 15 charted | light injury, small metal | severe injury, dose 40 |
| Weather station | small metal, map within 10 | medium metal, map within 20 | nothing | severe injury |
| Chemical dump | medium fuel, small gold | large fuel | light injury, dose 10, small fuel | severe injury, dose 50 |
| Radio tower | map within 15 | map within 25, Dustwell's trust +20 | light injury | fight at strength 4 |
| Bunker | medium metal, medium veg | 4 troops join, medium metal | light injury, small metal | fight at strength 5 |
| Oil pumpjack | medium fuel | large fuel, medium gold | light injury | severe injury |
| Water tower | medium veg | large veg, 2 colonists settle | nothing | severe injury |
| Ruined gas station | medium fuel | large fuel, medium metal | nothing | fight at strength 3 |
| Missile silo | large fuel | the Rust Kings' fort charted, medium metal | nothing | fight at strength 5 |
| Cargo yard | a small package of each resource | large and medium packages of two rolled resources | light injury | severe injury |

A dose poisons every survivor in the party (the existing radiation sickness, so it shows in the panel and costs hp each season). A site's
fight has a fixed strength (its DC is 6 + 2 x strength, so 3 is DC 12, 4 is DC 14 and 5 is DC 16) and no search follows it: winning pays the
enemy's package, losing drives the party off, and either way the site is spent. The fatal fumble (a natural-1-style CRITICAL_FAILURE at DC 14 or
more, then a d20 of 5 or less kills the whole party) therefore applies to the strength 4 and 5 fights and never to strength 3. Charting the map,
Dustwell's trust, troops and colonists are recorded by the visit and handed over when the party heads home (colonists only up to the
population cap; trust only while Dustwell is still neutral).

## How the game ends
There are three endings (`Data.ENDINGS` holds the numbers), each shown once: the ending picture (click, or press Enter, to continue), then a
stats screen, then a click on **Return to main menu**. The win or defeat music loops the whole way (`wasteland_OST_lastcall_Victory.wav` for
both wins, `wasteland_OST_signallost_DEFEAT.wav` for a loss) until the menu music takes over. A finished game is not autosaved.
- **Raiders defeated** (you win by force): a raid of yours that wins with attack at least 2.5 times the Rust Kings' defense storms their
  fort, or they are left with 6 tiles of land or fewer.
- **The colony prospers** (the long game, and rare): from season 80, the Rust Kings' raid strength stays under a quarter of your defense for 6
  seasons in a row, after at least 2 raids between you, with 20+ colonists, 30+ tiles and nobody starving.
- **Defeat:** a raid of theirs that wins with attack at least 3 times your defense overruns the colony (a Citadel stops that), your land falls
  to 6 tiles or fewer, or the colony starves down to 2 people.
- **Stats** (`Game.stats`, saved with the game) cover seasons survived, peak colonists and land, buildings, upgrades, vehicles, raids won and
  lost both ways, bands and tribes beaten, prisoners, survivors lost, parties sent, ruins and sites stripped, d20 rolls with natural 20s and
  1s, trade runs and resources gathered.

## Files
| File | What it does |
|---|---|
| `scripts/data.gd` | Every number in the game: terrain, buildings, leaders, upgrades, vehicles, market. Rebalance here. |
| `scripts/d20_data.gd`, `d20.gd`, `d20_visit.gd`, `dice.gd` | The d20 roll system: its numbers, its rules, one ruin visit, and the dice. |
| `d20_dice/` | The pixel-art d20 and its roll animations, used by the right panel. |
| `scripts/game.gd` | Autoload `Game`. The whole simulation, plus save/load (JSON in `user://saves/`). |
| `scripts/map_view.gd` | Draws the map: pixel-art sprites, or colored text glyphs. |
| `scripts/hud.gd` | All the UI, built in code. |
| `scripts/portrait.gd` | Draws the pixel-art survivor portraits. |
| `scripts/icons.gd` | The small pixel icons for how a party travels. |
| `scripts/geiger.gd` | The Geiger counter dial. |
| `scripts/fuel_gauge.gd` | The three fuel gauges (war rig, plane, boat). |
| `scripts/sprites.gd` | Looks up the pixel-art sprites in `art/atlas.png`, and the title screen and logo pictures. |
| `scripts/selftest.gd` | The `--selftest` check for a built copy of the game. |
| `tools/build_windows.ps1` | Exports the Windows version and zips it for sending. |
| `scripts/music.gd` | Autoload `Music`: which track plays when, and the volume. |
| `scripts/main.gd` | Puts the map, camera and UI together. |

Saves live in `%APPDATA%\Godot\app_userdata\Wasteland Colony\saves\`.
