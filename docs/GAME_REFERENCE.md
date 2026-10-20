# Wasteland Colony: game reference

How every system of the game works, with the code that does it and the tests that pin it. The numbers themselves live in `scripts/data.gd` and `scripts/d20_data.gd`: rebalance there.
For how to run, test and ship the project, and what to do next, see the [README](../README.md); for the controls, see "Controls and interface" there.

**Contents:** Menus and music · Leaders · The living map · Day and night · Fog of war · The survivors · Scavenger Parties · Pixel art · What a party can carry · Slopes and travel · Expeditions, tribes and raider bands · The map · Vehicle upgrades · Resources and money · Scavenging: the d20 rolls · Points of interest · Nukes, craters and the bomber · Prison breaks · Building raids · Fights between armies: the raiding dice · How the Rust Kings raid you · Wild animals and hunting · The Giant Frog · Frog hide, the Drug Factory and Salt · How the game ends

## Menus and music
- **Title screen.** The game opens on `art/title.png` with **New colony**, **Load game** and **Quit** over its dark lower edge (and
  **Resume** too when you open it again with the top bar's **Menu** button mid-game). The picture is 16:9: in a window of another shape it
  keeps its shape, with black bars. If the art can't be read it's the same choices in a plain text panel.
- **Character selection.** **New colony** leads to three randomly made leaders side by side (see "Leaders" below), with the slab-stack
  logo (`art/logo.png`, cropped to the lettering by `LOGO_CROP` in `scripts/sprites.gd`) above them. **Back** returns to the title screen.
- **Music.** `audio/` holds nine tracks. `wasteland_menu.wav` plays, looping, on the title screen, the character selection screen and the
  load screen, and carries on across them without restarting. Starting or loading a colony crossfades into the eight `wasteland_OST_*`
  tracks (`canyon`, `dread`, `breath`, `ashfall`, `winter`, `dustpunk`, and the victory and defeat pieces, `lastcall_Victory` and `signallost_DEFEAT`),
  which play one after another in a shuffled order (about 15 minutes before the shuffle comes round), then shuffle again, and never repeat a
  track back to back. **A new colony always opens with `canyon`** (`Music.OPENING`, `Music.play_opening`, called when you pick your leader) to set
  the mood, then shuffles through the other seven; loading a game carries on with the shuffle instead. The shuffle is remembered between launches (`last_game_track` and `game_queue` in `settings.cfg`), so a new launch
  carries on through the tracks it has not played yet. The victory and defeat tracks play once in the shuffle but loop under their ending
  screens (if one is already playing when its ending arrives, it carries on and loops). A new `wasteland_OST_*.wav` dropped in `audio/` has
  to be added to `Music.GAME` (a test fails until it is). Opening the menu in the middle of a game leaves the game music alone.
  `scripts/music.gd` does it all (an autoload called `Music`).
- **Volume.** The **Music** slider (bottom right of the title screen, on the character selection and load screens, and a small **♪** one in
  the top bar during a game) sets the music volume. All the way down is **completely off**: the music bus is muted, not just very quiet.
  They all show the same volume, and it's remembered between runs in `user://settings.cfg` (`%APPDATA%\Godot\app_userdata\Wasteland Colony\settings.cfg`,
  beside the saves). The tracks are imported uncompressed, exactly as supplied.

## Leaders
The three classes (Raider, Builder, Trader, `Data.LEADERS`) keep their buffs: Raider attack x1.25 and 25% off Warfare upgrades, Builder defense
x1.25 and 25% off Fortification, Trader a second caravan slot and 25% off Commerce. What is new is who leads: **each launch makes three new
people** (`scripts/leaders.gd`, `Leaders.offer`), one per class, shown as three cards side by side. A card has a large picture, a name
("Sheriff Cole Harlan": a title, a first name from the survivor names and a surname), the class buffs, **two perks and one flaw**. Click anywhere
on a card (or its **Choose** button) to start a colony led by that person; **Reroll leaders** draws three new ones, and going Back and returning
keeps the same three.
- **Perks and flaws.** 22 perks and 13 flaws, in four themes (Economy, War, Exploring, Trade), all small. A leader's two perks come from different
  themes and the flaw from a theme neither perk is in, so a flaw never cancels a perk; nobody on a screen shares a name, a perk or a flaw. Each one
  is done where the game already works the number out, behind `Game.has_quirk("id")` (the way upgrades are behind `Game.has`), and the effects are
  pinned by `tests/unit/test_leader_effects.gd`. The texts in `Leaders.PERKS` and `Leaders.FLAWS` are what the screens show.
- **Pictures.** `art/leaders/` holds `<class>_<n>.png` (480 x 480) and an optional `<class>_<n>_small.png` (48 x 48, used in the colony panel).
  Every portrait is shown with a 2 px orange (`AMBER`) line round it, like the rest of the UI's lines.
  The game finds them by itself, so adding `raider_4.png` needs no code. A picture is chosen at random for each class each launch. A class with no
  pictures gets a face from the survivor portrait generator instead. A picture that is plainly one kind of person keeps that title
  (`PICTURE_TITLES`): the monocle general is always a "General", the sheriffs "Sheriff", the elder "Elder", the suited man "Executive", the
  head-mirror doctor (`builder_4`) "Doctor", the hooded figure (`trader_4`) "Professor", and nobody else is given those titles by chance.
  There are 11 pictures: three Raider, four Builder and four Trader.
- **In the game.** The leader is saved with the colony (`leader_info` in the save). The top bar names them,
  and the **Colony** tab opens with their small picture, name, class buffs and a line for each perk and the flaw with what it does, so the numbers
  can be checked mid game.

## The living map
Everything that walks is shown walking, at the same pace (`scripts/season_replay.gd`). The game decides each walk at once, and the map then plays it back so you can
watch it: `Units._advance` notes each tile a unit reaches and the day it got there (a season is 40 days), plus what happened, and the map plays those notes at 3
seconds for the 40 days. Nothing the game decides depends on it. Two kinds of walk are played, the same way (`Units.replay`):
- **A party's walk.** One of your Scavenger Parties walks the moment you order it (see Scavenger Parties), so its walk plays the moment you order it
  (`Units._go`, handed to the map by `Game.walk_played`), its days counted from the start of that walk: a walk of 10 days takes under a second. A walk that starts
  while another is still playing joins it, so every party you send is seen walking together, and a party sent on again while its first walk still plays carries on
  along one trail. Pressing END SEASON during a walk skips it and ends the season.
- **A season's walk.** At END SEASON every caravan, boat, plane, raider band (the Rust Kings' raiding parties among them) and wandering animal glides along the route it
  walked that season (`Units.season_turn()`, handed over by `Game.season_played`). Your Scavenger Parties are not among them: they walk when you order it. A season in
  which nobody walks plays nothing. Pressing END SEASON while one plays only skips it (that press does not end another season).
- **The walk.** Every unit glides along its route at its real speed (a war rig crosses four times the ground of a party on foot). A party that gets home or is wiped
  out fades off the map where it happened; a band that spawned this season appears at its camp and sets off.
- **Fog lifts as they walk.** Ground a party uncovers stays dark until it gets there (`Game.reveal` says which tiles were new).
- **Bands in the fog stay hidden.** A raider band is drawn while its tile was in your sight when the walk began or is now, and fades in and out at the edge of what
  you see. Your own parties are always drawn.
- **A little life.** A hop on every step and a few dust dots behind a walking unit, a waiting party of yours (on station, or paused partway along its route) bobbing
  one pixel, a flicker at each camp fire. Flashes where things happen once the walking is done: crossed swords where a band catches a party or hits your outskirts, an
  exclamation mark where a party reaches its ruin, a gold glint when one gets home with loot, smoke where a vehicle is abandoned or a plane crashes.
- **Skipping.** A click on the map or Enter skips what is playing. If a season ends the game, the ending screen (and the Hollow Mile picture) waits for the replay to
  finish or be skipped.
- **Units have a layer of their own.** `MapView.UnitLayer` draws the units and camp fires every frame over the cached map chunks, so a moving unit redraws no tiles.
  `tests/unit/test_season_replay.gd` and `test_walk_replay.gd`, `tests/render/test_unit_layer.gd`, `test_season_replay_map.gd` and `test_walk_animation.gd` pin all of it;
  the tests turn the walk off (`SeasonReplay.mode = "off"`) unless they are about it.

## Day and night
Each season the map fades between daylight and moonlight, so you notice the turn change. **Spring and Autumn are day, Summer and Winter are
night** (two days and two nights a year); the top bar says so ("Year 3, Autumn (day)"). It is looks only: sight, travel, raids and every
other rule ignore it. The rules are in `scripts/daylight.gd`; `scripts/map_view.gd` draws them.
- **The fade.** The light follows the season number, so saves hold nothing for it. When END SEASON plays, the light moves from the old
  season's level to the new one over about 3 seconds (the tests, which run with the walk off, use 1.2): slowly, never a snap.
  Skipping the walk does not cut it short. A new game or a loaded one goes straight to its light.
- **The dark.** One moon-blue layer is multiplied over the ground and buildings (`Daylight.NIGHT`: dark, but the grounds stay apart). It is a
  single rectangle whose strength is the light, so no tile is redrawn while it fades. The panels, hover label and selection marks stay as
  they are. Both looks get the dark; only the pixel art also redraws the glowing tiles.
- **What glows.** Drawn again over the dark at full brightness, with a soft flickering halo: **craters**; **ruins that raiders hold** (once you
  have found out: tile state `rogue_seen`); the **raider, trader and builder camps** while one of your units can see them (a camp you only
  remember stays dark, so night shows you nothing you cannot see). **Fallout waste and fused glass** keep their bright speckles without a halo. A
  crater you remember but cannot see glows a little (`Daylight.REMEMBERED_GLOW`).
- **What is on the ground.** Your own parties keep their colours and carry a small, dim glow. Wild animals (deer, bears, the frog) never glow and go
  dark with the ground, and so do enemy parties (`Daylight.THINGS_SHARE`: a band stays easy to see), except an enemy party standing in ruins, which
  lights the ruins and is lit by them.
- **Switch.** **Night: On / Off** in the legend, next to the art style buttons; it is saved in `settings.cfg`. Off keeps it day.
- **Tuning.** `NIGHT`, `THINGS_SHARE`, the `HALOS` (colour, radius, strength) and `REMEMBERED_GLOW` in `scripts/daylight.gd`; the fade length follows
  `SeasonReplay.SECONDS`. The test setup (`tests/setup.gd`) keeps it day, so no snapshot depends on the season; `tests/unit/test_daylight.gd` and
  `tests/render/test_night.gd` cover the night.

## Fog of war
Every colony keeps its own memory of the map (`Game.memory`). Black tiles have never been seen.
Dim tiles were explored but are out of sight, so they show what was there last time.
Click a black or dim tile and press **Send scouts** to send a party there. You must find the Rust Kings and
Dustwell before you can attack, trade with or befriend them. The Rust Kings scout west toward you, and only
raid once they've found you.

## The survivors
The colony's people are named people, not a number (`scripts/roster.gd`, `Game.roster`). Everyone who has ever joined the colony is on the roster with a name nobody
else has (or had), an age, 1 to 3 traits (the 11 in `d20_data.gd`), a portrait seed (their face) and what has become of them: **home**, **away** (in one of your
parties), **enlisted** (trained as a troop) or **dead**. `Game.pop` is the number at home, and it is what the top bar and the upkeep count.
- **They join** when the colony starts (ten of them), when a food surplus brings settlers, when a site's colonists settle in, when a builder tribe joins you and when you
  disband a troop. Each is a new person with a face and traits. Names come from `Data.SURVIVOR_NAMES`; when they run out a surname is added ("Mara Voss"), and the
  name of someone who has fallen is never given again.
- **A party is made of them.** A party you send or form takes real people from the roster (the uninjured first, or the ones you pick) and they come home as the same
  people, rested and healed: a trip's injuries, hunger and doses end at home. The party rolls with its members' traits, so who you send matters.
- **They die for a reason.** Starvation, a lost fight, radiation sickness, a crash, a raid on the colony, a hunter who never came back: each death puts the person on the
  **Fallen** list with the season and the cause ("Mara, 34: starved in the field (Year 2, Summer)"), and the log names them.
- **They age.** Everyone alive is a year older every Spring.
- **The Colony tab** lists every survivor (portrait, name and age, traits, where they are) and, below, the fallen. **Pick** chooses who goes in the next party;
  **Form a party** (Q for one on foot) makes it at your HQ from the ones you picked, or the healthiest. These buttons take no digit key, so the tab's other buttons keep theirs.
- **Saves** carry the roster, and the parties on the map hold the roster's own entries (`sid`); an older save gets a roster made from its head count.
- Troops stay a number (`Game.troops`): training one takes a survivor off the roster ("enlisted"), and disbanding one gives a person back.
- The roster draws its own random numbers (`Roster.reseed`), so who the colony's people turn out to be never changes a seeded map; the test runner pins its seed
  (`Roster.fixed_seed`). `tests/unit/test_roster.gd` and `test_form_party.gd` and `tests/render/test_party_ui.gd` pin all of it.

## Scavenger Parties
Scavenging, scouting and hunting are one kind of party, the **Scavenger Party** (`☺`): 3 survivors from the roster, or 4 for a leader with the **Big party** perk on
scavenging and hunting runs (`Units.crew_for`; a scouting run stays at 3). Each is called by its number: Scavenger Party 1, 2, 3... (the lowest free number, kept until
the party comes home or is lost, then given to the next). **Nothing limits how many you can send except the survivors at home**: a party needs 3 (and one must stay
behind) and a food pack.
- **Making one.** Click a tile and press **Send scouts** (or the send buttons on a ruin, a site, an animal; or Z, X, C): that forms a party at your HQ and walks it off at
  once. Or form one first, on the Colony tab (**Form a party**, or **Q** for one on foot), from the survivors you pick or the healthiest: it waits at your HQ until you
  click where it should go and press **Send Scavenger Party 2 here** (`Units.form_party`).
- **Walking is on your orders and costs days.** A party has 40 days a turn (`move_left`; END SEASON gives them back), and ordering a move walks it right away, as far as its
  days go (`Units._go`, with the same costs as ever: ground, slopes, roads, load, a broken leg, Trailblazer). A route longer than that stops where the days run out and the
  rest waits for you to press **Continue** (G) once the days are back. END SEASON does not move your parties: the Rust Kings and the animals move then. The party's card
  shows its days left (a bar and "17 days left this turn"), and the trip length on "Send ... here" starts from the days it has left. The days it did not walk count as time
  spent where it stands for radiation, and a vehicle waiting burns its idle fuel.
- **Acting where it stands.** A party reaching the ruin or the animal it was sent for starts the visit at once; one that reached other ground keeps watch. A waiting party can
  **Search the ruins here**, **Hunt** an animal on or beside it, **Attack** a camp, a building or a hearth beside it (see Building raids). **Rolls cost no days and there is
  no limit to them**: only the walk is limited. Afterwards it waits where it is, with what it carries, until you send it on or recall it.
- **Recall to camp** (B, or the button on the party's card, on the Tile tab and under Expeditions on the Colony tab: every party has its own, with how many seasons the way home takes).
  The party turns for home and walks as far as its days this turn allow at once; after that it **walks home by itself**, a turn's days at each END SEASON, for as many seasons as the
  way takes (`Units._scout_turn`, recorded with the season's walking so the map plays it), with nothing to press. Its card says "Heading home" and "By itself: home in 2 seasons".
  It eats on the way, so the Tile tab warns when its pack will not last the walk. Orders given to it on the way (send it somewhere) cancel the recall; a party in the middle of a search
  or an attack finishes that first. At camp it is disbanded: its people, its food and what it carries come home (recalled while already at camp, it is disbanded at once).
- **The party bar**: a numbered button for each party along the bottom of the map (red when somebody is starving or ill, green in the middle of a search, bright for the
  picked one; the tooltip says who is in it, where it is and its days). Click one, or press **Shift** and its number (0 is the tenth), or its number on the **numpad**; **[** and **]**
  go through them. Parties past ten keep their numbers and are picked by the bar or the brackets.
- Click a party on the map and a **portrait** of each member appears in the bottom
  panel, with a hunger bar under it. Faces are drawn in code (`scripts/portrait.gd`) from a per-survivor seed, so the same person
  always looks the same, and they go grey and gaunt as they age or starve. The card lists each survivor on one short line (`Units.survivor_brief`: name, traits,
  and how they are doing only when that is more than fed); hover the line or the portrait for the whole thing (`Units.survivor_line`, with the age).
- **Food pack**: every party leaves with `SCOUT_PACK` (10, what one survivor can carry) food taken from your stores, whatever it is sent to do. It can be any food
  you have, grain, veg or meat, in any mix (grain first, then veg, then meat: `Units._pack_food`); a colony with less than 10 food in all cannot send one. Each survivor eats 1 a season from
  the pack, so a party of three lasts about 3 seasons. The **Inventory** column beside the portraits shows what's in the pack and how many days it will last. **Food a party finds
  joins its pack** (the veg from a ruin, the meat from a hunt: `Units._haul`), so scavenging and hunting keep it out longer; nothing else resupplies it in the field. When the pack is
  empty they go hungry, then starve, and die after 3 hungry seasons in a row. Whatever is left, found or not, goes back into your stores when they come home, so recall them in time.
- **Picking a party**: click a party, press **Shift** and its number (or **Pick** on its card) and the map draws its route from where it stands, not from
  your HQ: click any tile to see the way there. The dots fade **white** (plenty of food) to **yellow** (running low, from 75% eaten,
  `FOOD_WARN`) to **red**, and a red ring marks the tile where the pack runs out. Red dots mean not enough food for that stretch of
  the journey. A party already on the move shows the rest of its path the same way. The tile panel adds the trip length and how many
  days short the food is. **Esc**, **Deselect**, or clicking your own land lets go and brings the HQ routes back. No dotted line is drawn to your settlement: it is not somewhere to send a party.
- **Fuel**: a party in a war rig or plane takes a tank from your fuel stores (8 / 10), and so does a recon flight (10, the whole of its cost: it
  burns what the trip takes and the rest comes home, so a flight further than about 100 tiles out cannot make it back), and a river trader boat (3, enough for a
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
The map and the legend are drawn from `art/atlas16.png` (26 sprites of 16 x 16 pixels, described by `art/atlas16.json`: the 12 kinds of ground and the shallow ford, the two slope ledges, the 8 kinds of unit
and the three tribe camps), with `art/building_atlas.png` (22 buildings, 16 x 16), `art/animals.png` (the deer and bears 16 x 16, the Giant Frog 32 x 32) and `art/poi_atlas.png` (10 sites, 32 x 32 across 2 x 2 tiles) beside it.
A tile is 16 pixels wide, so every sprite shows at exactly 1x, crisp, with no gaps: one art pixel is one screen pixel at zoom 1. (The art was 8 x 8 shown at 2x until 2026-10-14; the pixel level is doubled.)
- **Two looks.** The pixel art (what the game starts on) and the old **text glyphs** (the Dwarf Fortress look, "ASCII"). The **field tablet** in the top bar (or **M**) switches between
  them: off, its screen shows a colour map and the map is the pixel art; click it and the screen turns to a green sonar sweep (with a short blip) and the map is text glyphs. The legend's
  **Map art: Pixel art / ASCII** buttons do the same and the tablet follows them. It changes the map and the legend together. `Sprites.CHOICES` is `[Sprites.CLEAN, 0]`.
  `scripts/sonar_tablet_button.gd` is the radiation meter's script with the tablet's frames (`art/sonar_tablet_sheet.png`), turned a quarter clockwise; `tools/make_sonar_tablet.py` draws the sheet (needs Pillow).
- **The look.** Made to be easy to read: every ground is one flat colour with one bold shape on it, and the colours are far apart (sand pale tan, dunes orange-yellow, scrub olive,
  petrified wood dark brown, grove green, rock grey, ruins slate, river blue). It is a dusk palette, darkened and warmed, and **only the hazards glow**: the crater's green ring, the fallout waste's and
  fused glass's bright specks and the lit windows in ruins. Each ground has five shades (the fill, a dark and a light one, the deepest and the lightest). Height is three quiet shades (a third of the land
  each) and a slope is a dark **ledge** along the tile's lower edge (two rows for a gentle slope, with teeth for a steep incline). Half the tiles are mirrored so a wide field is not wallpaper, and a feature
  (rock, water, ruins, trees, grove, waste, glass, crater) gets a 1 pixel dark **rim** on the sides that meet plainer ground (never next to unexplored tiles). Your land keeps its border line and a faint tint.
  **Buildings have pictures** (22, the two bridges among them), each with a dark outline, as do the units and camps. Roads are drawn from rectangles (see "Roads and the old highway"). The pictures are text rows in
  `tools/make_tiles16.gd` (the grounds, ledges, units and camps) and `tools/make_buildings.gd`: edit the rows and run the tool (the command is in each file's header). The frog and the 10 sites are 2x upscales of
  their 16 x 16 originals in `art/source/` (`tools/upscale_sites.py`, Scale2x): they have the new pixel size but not new detail yet, and are the next pictures to redraw by hand. In the text look a building is its letter.
- **Zoom.** The wheel steps between 0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 2.5 and 3 (`Main.ZOOM_STEPS`). At 0.5, 1, 2 and 3 every art pixel is the same size on screen; at the steps between, some are a little wider than others. One wheel notch moves one step. Code-drawn marks (rims, dust, camp embers, a hopping party) are one art pixel, `MapView.ART_PIXEL`.
- **Hover.** Move the mouse over a tile and a small label names it: what stands there, the ground and its height ("Farm on Ash sand, +5 m"), or "Unexplored". It is drawn at one size whatever the zoom,
  stays inside the window and is hidden while the mouse is over a panel.
- **Speed.** Every sprite is drawn from one atlas texture, so they batch: an idle frame takes about 100 draw calls where the glyphs took about 380. See `rendering_perf.md`.
- **Tuning.** `scripts/sprites.gd` says which sprite draws which thing (`TERRAIN`, `SLOPES`, `UNITS`, `CAMPS`) and sets the default style; `SHADE_*`, `OWN_TINT` and `RIM_*` in `scripts/map_view.gd` tune the
  clean look. If the atlas can't be read, everything falls back to the text glyphs.

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
around the inclines stay home. Tune speeds and penalties in `MOVERS` and `TERRAIN_SPEED` in `scripts/data.gd`.

### Ground speeds
Every kind of ground has a speed for foot, horseback and war rigs (`Data.TERRAIN_SPEED`: how many times as long a tile takes as sand). It
multiplies with the slope, so a steep incline on rock is 4.0 x 1.4 = 5.6 times as slow on foot. Boats and planes ignore the ground.

| Ground | On foot | Horseback | War rig |
|---|---|---|---|
| Ash sand | 1.0 | 1.0 | 1.0 |
| Dead scrub, fallout waste | 1.1 | 1.1 | 1.2 |
| Dunes | 1.2 | 1.3 | 1.5 |
| Fused glass | 1.2 | 1.4 | 1.2 |
| Petrified wood | 1.3 | 1.5 | 1.8 |
| Green grove | 1.3 | 1.4 | 1.6 |
| Pre-war ruins | 1.3 | 1.5 | 1.8 |
| Glowing crater | 1.3 | 1.4 | 1.6 |
| Rock | 1.4 | 1.6 | 2.0 |

The route finder weighs tiles by the same number, so parties go round slow ground when it pays. On four maps a typical trip comes out 6 to
13% longer than with flat ground (a war rig's nearby trip 17%), and parties cross far less rock than before. The tile panel and the legend say
what a ground costs. `Game.move_mult` is the one cost that routes, day counts, the season replay, food use and the Rust Kings' marches all use.

### The broken leg
A foot or horseback party that enters a **rock** tile has a 2% chance, and a **steep incline** 4%, that one of its people breaks a leg (a horse
goes lame, for a party on horseback; `Data.LEG`). War rigs, boats and planes never do. It is one survivor at random: a Clumsy one is twice as
likely, and a party with a Light-Footed member halves the chance. A broken leg slows the whole party: every step takes 1.5 times as long (1.75
with a second, never past 2; `Units.leg_slowdown`, which multiplies with the load slowdown in `Units.party_slowdown`). The log says who and where,
the survivor's line says "broken leg", and the map flashes a white crack on the tile during the season replay. It **heals when the party gets
home**, or ends if that person dies on the road; a scouting party on station can be sent home to heal.

## Expeditions, tribes and raider bands
The map is 120 x 72. Things on the move are drawn over the tile they stand on:

| Symbol | What | |
|---|---|---|
| ☺ | Scavenger Party | Yours, numbered: it scavenges, scouts, hunts and attacks. Form one on the Colony tab or send one from any tile; ruins may hide a booby trap or a rogue raider. |
| ♦ | Trade caravan | Send from the Diplomacy tab to the Rust Kings or a trader tribe. Gold comes home with it. |
| Θ | War rig | Any expedition sent by war rig (faster, tougher, hauls 1.5x loot). |
| ◊ | Boat | Click your port to send a boat downriver to trade. |
| Ж | Recon plane | Click any tile to fly recon over it; it maps everything it passes. |
| ☻ | Raider band | Wild raiders, and the Rust Kings' raiding parties (see How the Rust Kings raid you). They ambush expeditions and hit colony outskirts. |
| Δ | Tribe camp | Red: raiders (a Scavenger Party attacks the camp). Yellow: traders (send caravans). Blue: builders (gift food and they join you). |

Crew leave your population while they're out, and vehicles on expeditions can't fight.
Swap any symbol in `UNITS` in `scripts/data.gd`. `docs/unit_glyph_options.png` shows the alternatives.

## The map
One river runs from the left edge of the map to the right, sloping south as it goes (`RIVER_MID_Y` and `RIVER_SLOPE` in
`scripts/data.gd`). It passes between the two camps' lands, so you start on one bank and the Rust Kings on the other. Both camps start in
open desert, with no craters or lone ruins nearby.

Each glowing crater (`o`) marks the epicenter of a big field of pre-war ruins (`EPICENTERS` of them). Ruins thin out toward the
edge, and a few lone ruins are scattered around too. Scavenge them for loot, but watch for traps and rogue raiders.

### Crossing the river
**The river is a wall** for everything on the ground: foot, horseback and war rigs cannot enter a river tile (`Data.MOVERS` `water` is 0). Boats
and planes cross it as before. A trip that would need to cross says "No way there (the river)", and so does the route preview. It can be crossed in
three ways, all made by `Game._pass_crossings`, the last pass of map making (it has a random number generator of its own, so it changes nothing
made before or after it, and the same map always gets the same crossings):
- **The old bridge**: one tile wide (so it is a chokepoint), in the middle column of the map, or the nearest column (within `BRIDGE_SEARCH`)
  where a war rig can drive from your HQ to the Rust Kings' fort over it (steep inclines can wall off an end). Every ground party can use it,
  yours and your enemies', and boats pass under it. It belongs to nobody: it cannot be claimed, built over or pulled down, and an outpost's
  claim skips it.
- **Fords**: strips of shallow river, `FORD_WIDTH` columns wide across the whole channel. Two are placed on the way to Dustwell (near the
  west reach) and on the way to the fort (middle-east), a few columns off from map to map, and a third at random. Foot and horseback parties
  wade a ford at twice the cost of land; war rigs cannot; boats scrape through at half speed. A ford is still "water" for every other rule
  (you cannot build on it) with a flag on the tile (`Game.is_ford`), and has a picture of its own (lighter blue over pale sand and pebbles).
- **Bridges you build** (wood 10, stone 5 a tile): from your own bank, a tile at a time, each tile touching your land or the last bridge tile. A bridge
  tile becomes yours, every ground party can use it (the Rust Kings and raiders too), boats pass under it, and you can pull it down, except
  with a party standing on it. The Build button shows on free water beside your land.

The pass checks that your home can reach the fort and Dustwell on foot, and adds fords until it can. On all maps tried, both are across the river
from you, so the crossings matter: the west ford and the old bridge keep the walks to Dustwell and the fort within about 5 to 13% of the straight line.

### Roads and the old highway
- **The old highway** is made with the map (`Game._pass_highway`, after the crossings; it takes no random numbers): one long ruined road that
  runs to **every city** and over the old bridge (the crater at each city's centre has since taken the road there, and some round it: see "The craters took the road"). On each bank it goes from the bridge to the nearest city, then the next nearest, along the
  cheapest ground (round rock, steep inclines and craters where it can). That is 4 or 5 cities and 120 to 160 tiles, about a quarter of it ruins, and it
  touches neither HQ (the nearest tile is 24 to 39 tiles from yours). A ground party takes 0.8 times as long on a highway tile, whatever the ground
  under it. It belongs to nobody and cannot be built over, claimed or pulled down.
- **Ambushes.** A party of yours walking the old highway (foot, horseback or war rig) rolls a d20 for every 10 highway tiles it walks, and a natural
  1 is an ambush: a raider band of strength 3 to 6 jumps it and it is fought like any ambush on the road (the best fighter rolls against the band;
  a miss costs an injury and a share of the load, and a natural 1 on that roll kills someone). Over the whole highway that is about 14 rolls, so about
  an even chance of one ambush; a 40-tile trip is about 1 in 5. Built roads never ambush (`Units._highway_check`, `Data.HIGHWAY`).
- **Roads you build.** Click free ground beside your land, or one of your own tiles, and Build a **Road**: 2 stone and 1 grain a tile (the grain feeds the
  workers). It goes on your own land, or on **free land** that touches your land or a road that reaches it, so it grows out from your border a tile at
  a time (never on water, steep inclines, sites, buildings or the other side's land). A road makes its tile 0.6 times as long for ground parties
  on any ground. **A road on free land stays free**: anyone can use it, your parties, the Rust Kings' marches and raider bands alike, so a road you
  build to the highway is also a road for them to come down. You can pull down roads on your own land; roads on free land are permanent.
  A road network is the roads, bridges and fords joined to your land, the old highway included (`Game.road_network`, `road_reaches`).
- **The Rust Kings build too** (`Game._ai_roads`, in their season turn): when they have 8 stone and 8 food to spare after their walls, they lay up to 2
  road tiles a season (2 stone and 1 food each), heading for the old highway first, then Dustwell, then your land, along a route that keeps to straight
  lines and avoids steep inclines, water without a crossing, and other people's land (`Game._road_path`).
- **Spurs and fragments.** After the highway is laid, `Game._pass_spurs` runs a few **spurs** out of the cities' centres in directions that point at no
  other city (`Data.SPURS`; own random numbers, so no other pass moves): 5 to 7 a map, at most 2 a city. Each is a solid stretch of real highway (5 to 11
  tiles, with a sideways jog now and then), then 2 to 4 **fragments** (up to 3 tiles each, shorter as it goes) with 1 to 3 tiles missing between them,
  until the road is gone; the river, the map edge or the ground near a base (18 tiles) ends one early and a building swallows the tile under it. So a
  scout who finds a lone bit of road in the wastes can follow it back towards a city. Fragments are ordinary `old_road` tiles (0.8 times as long, they
  roll for ambushes, and seeing one finds the Hollow Mile); the Rust Kings only head for a stretch of 6 or more road tiles (`Game._highway_pieces`).
- **The craters took the road.** `Game._pass_crater_wear` (last of the map passes, own random numbers) destroys the old road around every crater: none is
  left on a crater tile, and within 5 tiles of one a tile survives with the chance (distance to the nearest crater tile) / 5, so the road gets patchier
  and patchier towards the glowing craters. That breaks the highway where it meets each city's crater, about 45 to 65 tiles a map, and the spurs start
  out of the crater (`Data.CRATER_WEAR`, `Game.worn`).
- **Repairing the highway.** Any side can pay **1 stone** (`Data.HIGHWAY.repair`) to turn a tile of the old highway into a road: select the tile and press
  "Repair into a road". It has to be free land or yours, joined to your land or to a road that reaches it (the highway counts once your road meets it), so a
  repair runs along the highway a tile at a time. The tile stops rolling for ambushes and takes 0.6 instead of 0.8, for everyone; on free land it stays free
  and cannot be pulled down (`Game.repair_status`, `Game.repair`). The Rust Kings repair the highway tiles that lie on their road to Dustwell or your land
  (1 stone each, counted in their 2 tiles a season; about 7 tiles of 129 over 200 seasons on seed 3), so the fight over the highway is also a fight over
  where it stays dangerous.
- **The Hollow Mile.** That is the old highway's name. The first time your colony sees any tile of it (or of the old bridge it crosses), through a scout, a
  party or a building's sight, `Game.check_hollow_mile` (called from `Units.check_discoveries` after every fog update) logs it, sets `Game.hollow_found`
  (saved) and emits `hollow_mile_found(cell, hot)`. The HUD (`Hud.show_hollow_mile`) then puts up a full-screen picture, once the season's walk has finished
  playing: `art/hollow_mile_day.png` (the grey overcast one with the stalled traffic) in a day season (always, with the night switched off), whatever the
  radiation; in a night season `art/hollow_mile_night.png` (the orange dusk one with the viaduct), or `art/hollow_mile_fallout.png` (the green moonlit one) if
  the party that found it was taking **high radiation**: the R/h on the tile it stands on times the shielding of how it travels (`Data.MOVERS.shield`: a war rig lets half through) is 45 or more, the
  bottom of the High band (`Data.HOLLOW_MILE.rad_high`, `Game._finders_heat`: the hottest of your parties that has a tile of the highway in sight; a find
  made by a building's sight or a flight is never "hot"). A click, Enter, Space or Escape closes it. If a picture is missing, a title card stands in for
  it. The pictures are 1152 x 768 and carry their own title.
  The same three pictures also sit in **the bottom right corner** whenever you pick a tile of the highway or its bridge that your colony has seen (the corner picture,
  below, under Points of interest), by the same rules: the grey one in a day season (always, with the night switched off), at night the dusk one, or the green one
  when the tile's own reading is high radiation (45 R/h or more, and only once your scouts have measured it: an unmeasured tile gives nothing away). A stretch you
  have repaired into a road is no longer the highway and shows nothing.
- **Drawing.** In the clean look a road is a strip of rectangles that joins up with the next road, bridge or ford (pale packed earth for a road, cracked
  grey for the highway) with a dark one-pixel edge; the other looks show an `=`. The legend has a row for each.
- Tune the numbers in `HIGHWAY`, `ROAD` and `AI_ROAD` in `scripts/data.gd`.

### Radiation
Every tile has a hidden radiation level in R/h. Craters glow hardest and it fades with distance; fused glass, fallout waste and the
ruin fields stay hot, and the camps start clean. Most of the wastes are harmless background (under 5 R/h).

- **Readings.** You only see a rough range for a tile (e.g. "roughly 30-80 R/h") until one of your scouting parties has stood on it.
  Scouts take a reading of every tile they walk across, and the exact figure is yours for the rest of the run, as is any land you own.
  The **radiation meter** in the top bar (the yellow survey meter lying on its side) tints the tiles you've measured by band: safe,
  low, moderate, high, extreme. Click it (or press **R**): the view flips at once and the meter plays its power-on animation (needle swinging, dial glowing green, then idling with
  the needle wandering) or its power-off one; a click while it is still animating does nothing. Only the meter's own pixels are clickable. It follows the game, so
  a new game or a load puts it back to off. (`scripts/rad_meter_button.gd`, art in `art/rad_meter_sheet.png`, sounds in `audio/`.)
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
and more, and at the top of Warfare the Strategic bombers that unlock the bomber (see "Nukes, craters and the bomber"). The Rust Kings build horses, war
rigs, boats and planes as the years pass.

**Refineries** turn 4 **veg** into 3 fuel each season (4 with Ethanol synthesis), but only once you switch them on: a new refinery
starts **off**. Click it on the map and press **Start refinery** (or **Stop refinery**); the Colony tab shows how many are running.
Switching is per refinery, and demolishing one resets it. A running refinery holds back whenever taking its veg would leave grain
+ veg short of feeding everyone (colonists and prisoners), so it can't starve the colony, and the log says when it did.

## Resources and money
There are eight resources: **wood, stone, metal, fuel, grain, veg, meat and gold**.
- **Farms** yield **3.5 grain and 1.5 veg** each a season (`Data.BUILDINGS.farm.yield`): 5 food, mostly grain. The yields of all your
  tiles are added up and then rounded, so 1 farm gives 4 grain and 2 veg, 2 farms 7 and 3, 3 farms 11 and 5, 4 farms 14 and 6. Irrigation (+1 grain a farm) and a Green Thumb
  leader (+1 veg a farm) still add whole ones.
- **Metal** is what ruins give. A pre-war ruin you own makes 1 a season, a Salvage yard on it makes 3 more, and a scavenger party
  strips a ruin once for loot that is mostly metal (see "Scavenging: the d20 rolls": about 9 gold-equivalent a visit).
  A war rig brings back half as much again, but burns 2 fuel on the way (`SCAV_CAR_MULT`, `SCAV_CAR_FUEL`).
  War rigs cost 11 metal and 4 wood, and the War rig workshops upgrade 20 metal.
- **Gold** is the one currency. It pays for the Port, Airfield, planes, claiming land, and the upgrades Bribery (63 gold) and Merchant empire
  (128 gold); a plane takes 28 gold. Trade contracts (Commerce tier 2) add 4 gold to every
  caravan and river boat, and Toll roads pay 1 gold for every 2 walls.
- **Fuel** comes from refineries and ruins, and sells 5 for 4 gold (buying costs double). A scouting party or boat brings home
  whole units of fuel left in its tank. Vehicles pay upkeep (a war rig 1, a plane 2 and 1 gold) only while they're at home:
  one that's out lives off its own tank.

The top bar shows each resource as its name, its amount, then a tiny picture to the right of the amount (`art/icons/res_<id>.png`, 8 x 8,
with `res_<id>_bar.png` the doubled 18 x 16 copy the bar actually uses, its 2 px gap on the left; `_resource_icon` in `scripts/hud.gd`). With three-digit amounts in all eight resources the bar still holds
two lines; with all eight in the thousands the last amount wraps to a third line, which still fits inside the bar.

## Scavenging: the d20 rolls
A scavenger party that reaches a ruin stops there and waits. Select it and the right panel shows **Scavenge**, a clickable pixel-art
d20 below it (`d20_dice/`, played at 1.25x), and what the next roll is. Click the die: it tumbles, lands on the number that was rolled,
and the number stays up for a second until you click off it. Every roll is one click.
- **Each roll** is one d20 plus modifiers against a DC, and the margin gives `CRITICAL_FAILURE`, `FAILURE`, `SUCCESS` or
  `CRITICAL_SUCCESS` (a natural 1 or 20 always gives the critical ones). Modifiers are clamped to -5..+5.
- **The arithmetic is hidden on screen.** The panel shows who rolls, the party's perks ("Traits: ...") and the die, then what came of it; the DC, the modifiers, the sum and
  the "d20 8 +4 = 12 vs DC 11" line are left out, in the panel, on the buttons ("Attack the camp (strength 5)") and in the log ("Mara (Sharp-Eyed) trap: success"). `D20.plain`
  strips them from what is drawn (the Hud's label and button helpers and the log); the game's own log, its saves and its tests keep the full lines, and
  `D20.show_math = true` puts the numbers back.
- **The party rolls as one.** Every survivor has 1 to 3 traits (the 11 in `d20_data.gd`, rolled when they join the colony). The traits of
  the whole party combine, and a trait two survivors share counts once (three Magpies are worth one). The survivor in the best
  condition makes the roll; injuries and fumbles land on them. A Lucky trait gives the party one reroll.
- **Situation modifiers come from the game:** the ruin's radiation after the vehicle's shield (20 R/h -1, 45 -2, 80 -3), the roller's
  radiation sickness, hunger and injuries, and in a fight the enemy's strength against the party's (outnumbered -2; Veteran ignores
  it, Cowardly doubles it). A fight's DC is 6 + 2 x the enemy's strength. Arriving at a ruin measures its radiation, so the panel
  shows the modifier before the roll.
- **What a ruin starts with** comes from the map: a safe ruin rolls a plain d20 for what it holds (`EVENT_TABLE`: 1-3 ambush and 4-6 trap, both
  rerolled because the map has already settled the hazards, 7-10 nothing, 11-15 a small find, 16-20 a cache, so a natural 20 on the search finds
  a cache), a trapped ruin starts with a trap check at DC 14, a rogue-held one with an ambush check at DC 14 and a fight. A trap or a won fight is
  a toll: the ruin is then searched like a safe one, with its own search roll (a natural 20 on the trap check pays a small package and is followed
  by that search). A natural 20 on an ambush check cannot lose: the raiders are beaten outright, the enemy's small package and the ambush's bonus are
  paid, one raider is caught and their camp is revealed. A won fight takes 1 prisoner. The panel's last line says what happened: "The ruins are
  stripped. The party carries 6 metal." (or "There was nothing here." only when the visit found nothing at all, or "You were driven off" when a
  ruined cache's noise drew a fight that was lost).
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
Each map has one of ten 2 x 2 sites (`Data.POIS`, art in `art/poi_atlas.png`, 32 x 32 each): a crashed ship, weather station, chemical dump, radio tower,
bunker, oil pumpjack, water tower, ruined gas station, missile silo and cargo yard. Each stands where it fits (the gas station beside the old highway, water towers and cargo yards
by the river, bunkers and silos 6 to 16 tiles from a ruin field, towers on or beside rock, the chemical dump on fallout waste, the pumpjack
in deep desert), 12 tiles from any camp and 10 from the next site. A site is four tiles that carry one building id (`poi_<kind>`), so the
fog, saves and the map treat it like a building: each tile draws its quarter of the sprite. You can't build on one or demolish it. Click any
of its tiles and send one scavenger party; it works the whole site as one tile and all four read "picked clean" afterwards.

**The corner picture.** While one of a site's four tiles is picked and your colony has seen it, its picture shows in the bottom right corner of the screen, under
the Tile panel, with the site's name below it (`Data.POI_SCENES`, 1152 x 768 PNGs in `art/scenes/`, drawn at 288 x 192: the art at 4 times its size, so one art
pixel is one screen pixel). The Tile panel gets that much shorter while it is up (a Scavenge button is still in view at 1600 x 900), and goes back to the whole
side on the other tabs, on any other tile, and while a party is searching the site (that panel, with the die, needs all the room).

**Which picture a site shows is chance, for now.** Most kinds have two ("A" and "B", set on other sorts of ground) and the gas station has four; `Game.poi_scene(c)` picks
one from the site's kind and place (a hash, not the game's random numbers, so nothing else moves). A site therefore always shows the same picture: click after click,
through a save, after a blast. Across sites each picture comes up about equally often. A later pass can pick by the ground around the site instead (it is the one
function to change).

| Site | Pictures in `art/scenes/` |
|---|---|
| Crashed ship | `crashed_ship_A_1` (a salt flat), `crashed_ship_B_1` (lava and ash) |
| Weather station | `weather_station_A_1` (stony ground), `weather_station_B_1` (dry grass) |
| Chemical dump | `chemical_dump_A_1` (toxic marsh), `chemical_dump_B_1` (a ruined factory city) |
| Radio tower | `radio_tower_A_1` (green hills), `radio_tower_B_1` (red-rock desert) |
| Bunker | `bunker_A_1` (open desert), `bunker_B_1` (a dead wood) |
| Oil pumpjack | `oil_pumpjack_A_1` (orange desert), `oil_pumpjack_B_1` (cracked earth with a railway) |
| Water tower | `water_tower_A_1` (farmland), `water_tower_B_1` (a wrecked town) |
| Ruined gas station | `ruined_gas_station_A`, `_A_1` (with an overpass and poles), `_B`, `_B_1` (a road along the front) |
| Missile silo, Cargo yard | `missile_silo_A_1`, `cargo_yard_A` (the only ones) |

**Searching a site** is one d20 "Site check" in the right-hand Scavenge panel (the party's scavenge modifiers and the situation, against the
site's DC), and the tier of the roll picks that site's outcome. There is no search deeper, and "Leave without searching" keeps the site
unsearched. The DCs: weather station, water tower, gas station and cargo yard 11; crashed ship, chemical dump, radio tower, bunker and
pumpjack 14; missile silo 17. `SITES` in `scripts/d20_data.gd` holds every outcome as data (a name and a list of effects, documented
above the table), so changing one is a one-line edit. Packages pay `POI_LOOT_MULT` (1.5) times an ordinary ruin's. The outcomes:

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
| Missile silo | large fuel, 1 unfired nuke | the Rust Kings' fort charted, medium metal, 2 or 3 unfired nukes | nothing | fight at strength 5 |
| Cargo yard | a small package of each resource | large and medium packages of two rolled resources | light injury | severe injury |

A dose poisons every survivor in the party (the existing radiation sickness, so it shows in the panel and costs hp each season). A site's
fight has a fixed strength (its DC is 6 + 2 x strength, so 3 is DC 12, 4 is DC 14 and 5 is DC 16) and no search follows it: winning pays the
enemy's package, losing drives the party off, and either way the site is spent. The fatal fumble (a natural-1-style CRITICAL_FAILURE at DC 14 or
more, then a d20 of 5 or less kills the whole party) therefore applies to the strength 4 and 5 fights and never to strength 3. Charting the map,
Dustwell's trust, troops and colonists are recorded by the visit and handed over when the party heads home (colonists only up to the
population cap; trust only while Dustwell is still neutral).

## Nukes, craters and the bomber
The wastes still hold live nukes. A **glowing crater** (the green circles at the heart of each ruin field: 40 to 73 tiles a map, 82 to 150 R/h) can be searched
once, and the **missile silo** can hold up to three. A nuke is a very heavy item you bring home and spend from a Bomber.
- **Searching a crater.** Click one and send a scavenger party (one party a tile, each tile once; the panel is "Search the crater"). The roll is one d20 against
  DC 11 (`D20Data.CRATER`) with the party's scavenge and trap modifiers, and the crater's radiation counts (a party on foot starts at -3). **Only a natural 1
  and a natural 20 are critical** (the usual margin would make a bad roll a blast 40% of the time): a natural 1 sets the nuke off, a natural 20 disarms it,
  and anything else is scrap (a small package of metal) or nothing. So about 5% of searches are a blast and 5% a nuke, whatever the modifier; about 2.8 of
  each on an average map if every crater tile were searched. Lucky's reroll works, and a **Sharp-Eyed** survivor turns the blast into a plain failure, as on
  any trap roll (so about half your parties cannot set one off). **Leave without searching** is always offered.
- **The silo.** Still one roll against DC 17 and one chance. A Success adds 1 unfired nuke to the fuel store, a Critical success adds 2 or 3 to the targeting
  data (a second d20: 1 to 12 gives 2, 13 to 20 gives 3). At modifier 0 that is 15% for one, 3% for two and 2% for three. Warheads a party cannot carry stay in
  the silo (its tiles read `stockN`, see `Game.silo_stock`): a later party that reaches it loads them with nothing to roll.
- **Weight.** A nuke is an item (`Data.ITEMS`, like frog hides and Salt) that weighs 50 (`ITEM_WEIGHT`), loaded before any other loot (`Units.fit_load`). A
  party of three lifts 1 on foot (the trip home takes 1.7 times as long), 2 on horseback, 3 in a war rig. In the stores it has no top-bar line, raids do
  not take it, and it is saved with the game.
- **The blast** (`Game.detonate`, the same for a crater that goes wrong and a bomber's drop): the 3 x 3 square becomes **Scorched ash sand** (terrain `ash`:
  moves like sand, yields nothing, no farms) at 120 R/h, cooling 2 R/h a season down to 60 (`Data.NUKE`). Water and glowing craters stay what they were.
  Every party in the square dies (yours too, with its vehicle), and so do wild animals; any camp is wiped out; the Giant Frog is not hurt. Buildings fall,
  roads and the old highway with them, except an HQ, the Raider fort, Dustwell, the old bridge and the sites. A strike that destroys Rust Kings buildings
  costs 10 relations each (a crater accident does not). The new ground and its radiation are in the save already; the map redraws its ground.
- **The explosion.** A small, bright fireball with a shock ring, smoke and a green glow, drawn as added light over the units and the night
  (`MapView.BlastLayer`), so it glows by day and by night, for 2.8 seconds. At a crater it plays when the die lands; a bomber's plays in the season replay on the
  day the bomber got there. The ash keeps its speckles lit at night, like fallout waste and fused glass.
- **The bomber.** The Warfare upgrade **Strategic bombers** (tier 5, needs Bombing runs; 60 metal, 30 fuel, 60 gold) lets the Airfield build **Bombers**: 60 metal,
  25 fuel and 70 gold each, upkeep 4 fuel and 3 gold a season whether it flies or not, at most 2, a crew of 2, a 14-fuel tank (it reaches 116 tiles and flies
  home; a strike further than that is refused, so it never runs dry). It does nothing but carry one nuke: no sight, raid attack or air freight, and Bombing runs
  does nothing for it.
- **A strike.** With a bomber, every tile's panel has a **Nuclear strike** block. Hover its button and the map outlines the 3 x 3 square in red and the panel lists
  what you know is in it (your own things in red). The first press arms it and the second sends the bomber (the nuke leaves the stores then; there is no
  recall). It flies in a straight line, the nuke goes off over the tile on the day it gets there, and it flies home.
- **The Rust Kings' nukes, late game only** (`Data.AI_NUKES`, `Game._ai_nukes`). They build an **airfield** at season 46 (a building on their land, 3 to 6 tiles from
  the fort on the side away from you: 30 metal, 25 stone, 25 gold), one **bomber** at season 50 (40 metal, 30 gold), and get a **warhead** at season 52 and another every
  12 seasons, holding 2 at most. (Both cost metal, and their metal never builds up: their war rigs and planes take it as it comes, about 0.3 a season on eight maps. So
  their scavengers turn up a **cache of metal**, 80 at season 44 and 60 more every 12 seasons: enough for the airfield and the bomber on pace, and to rebuild the airfield
  now and then.)
  Each season they have an airfield, a bomber and a warhead and have not struck in the last 4 seasons, there is a 30% chance they plan a strike; it lands the next
  season on the 3 x 3 square holding most of your buildings (at least 2; the camera jumps to it and the stats count it as a nuke you suffered). **Watchtowers** warn
  you the season before, with the tile; **Flak towers** shoot the bomber down 7 times in 10 (the warhead and the bomber are lost). **Their airfield is a building you
  can destroy**: DC 12, by a scouting party beside it, a raid's strike roll, or a nuke of yours. While none stands nothing launches and a planned strike is called
  off; the bomber and the warheads wait, and after 8 seasons they rebuild if they can pay again. The Diplomacy tab shows their bombers and whether you have found the
  airfield. Nuking them does not change their schedule.
- **Buying a warhead from the traders** (`Data.TRADERS`). About 15% of trader camps hold one for sale (worked out from the camp's number and place, not the random
  numbers, so about 1 game in 5 meets one). A caravan's first trade there tells you ("Warhead for sale"). Then a **Buy the warhead** caravan (crew 2, one of your
  caravan slots) can fetch it: **500 gold**, 250 for a Trader leader, paid when it sets out and lost with it if it never arrives (a camp that has vanished sends the
  gold back). Only a caravan on horseback or in a war rig can lift 50. The crate slows the trip home 1.5 times on top of the weight (about 1.9 times as long on
  horseback, 1.5 in a war rig), and the warhead is yours only when the caravan reaches your HQ: a wiped-out caravan loses it and the gold.
- **Only you and the Rust Kings** have nukes. Dustwell, the raider bands and the tribes never launch one.
- **Tuning.** `D20Data.CRATER`, the silo rows of `SITES`, `Data.NUKE`, `ITEM_WEIGHT.nuke`, `VEHICLES.bomber`, `VEHICLE_FUEL.bomber`, `UPGRADES.wv5` and
  `SeasonReplay.BLAST_SECONDS`. The ash and bomber pictures are in `tools/make_tiles16.gd` with the rest.

## Prison breaks
A season whose upkeep finds more than 4 prisoners and fewer than 2 of your outposts within 6 tiles of the HQ (your circle of control; the
numbers are `PRISON_*` in `scripts/data.gd`) ends in a prison break, with no warning: half the prisoners (rounded up) escape, you lose a
guard, and the escapees form a raider band at the edge of your land as strong as they are many, which then attacks like any wild band. Ransom
prisoners or build the two outposts to stop it. The older revolt (prisoners above three times your troops, 30% a season) still happens when
the new rule does not apply, and a season never has both.

## Building raids
Any building can be destroyed with one attack roll: d20 plus a modifier against the building's DC (`BUILDING_DC` in `scripts/d20_data.gd`).
Farms, lodges, horse farms, salvage yards and trading posts are DC 8; mines, refineries, motor pools, ports and airfields 10; outposts 11;
walls and watchtowers 12 (14 for your walls with Stone walls); keeps 15. The citadel and the points of interest cannot be destroyed. A destroyed building leaves its tile
bare and with its owner. At most 3 of your buildings fall in a season, whoever attacks (`RAID_LOSS_CAP`).
- **The three hearths** are attacked the same way: your HQ (DC 16), the Rust Kings' fort (DC 16) and Dustwell's centre (DC 14) (`HEARTHS` in `d20_data.gd`). But a hearth
  cannot be attacked while a wall, tower, outpost or keep of its owner stands within 4 tiles of it (`HEARTH_GUARD_RADIUS`: bring those down first, one roll each), nor at
  all while its owner has a citadel. Your own hearth is also safe once 3 of your buildings have fallen that season, and Dustwell is a target only while it is neutral and
  found (never an ally). Bringing a hearth down ends a colony: **the fort falling is the win** ("Raiders defeated"), **your HQ falling is the defeat** (the colony is
  overrun), and Dustwell's centre falling conquers it (its land turns yours, with 5 prisoners). `Game.is_hearth`, `Game.hearth_guards`, `Game.can_hit`.
- **The Rust Kings' walls are tiles now.** Their wall count is still what counts in a raid (2 defense each), but each 4 walls stand as one
  Raider wall tile (`▓`) on their land nearest your HQ. Destroying a tile removes its 4 walls and costs 10 relations with them; a wall tile
  you take with their land takes its 4 walls with it, and you cannot buy one.
- **Your Scavenger Parties attack in person, and this is how you raid.** A waiting party on or next to a building, a camp or a hearth of theirs gets an "Attack the ..."
  button (a hearth that is still guarded says what stands in the way and its DC). The right panel then shows "Attack" and the clickable die, and the party rolls like a
  fight at a ruin (its traits, injuries and the radiation all count). A hit pays the usual package for a won fight and the building comes down when you press Continue; a
  miss injures the roller (light, or severe on a bad miss, which also loses half of what the party carries) and the party can try again or "Back off". A building is
  attacked like this by a party standing there, so its walk is days and its rolls are free. There is no Raid button.
- **Raider bands** that beat your guards at your edge also roll once at the building nearest them (never at a hearth).
- **A raid or band's modifier** comes from its strength against the defense it meets: +4 at double, +2 at 1.5 times, 0 at even, -2 below.
  Each roll is written to the log with its d20, modifier and DC.
- **The Rust Kings' raiding parties** (see How the Rust Kings raid you) roll at your buildings from season 6 on (`AI_BUILDING_ATTACKS_FROM`), but only when they win the guards'
  roll: once, once more if their attack is at least double your defense, and once more if they have planes (Flak towers cancel that one), each at a different building, the
  ones nearest their fort first, with the same modifier table. When their attack is at least `hearth_ratio` (2) times your defense and nothing guards your hearth, the
  first roll is at your hearth. Build walls and towers round your HQ, or a citadel, to keep it safe.
- **The Rust Kings' scouts** (2 a season, up to 4 with horses) each have a 10% chance, also from season 6, to roll once with no bonus at one of
  your buildings, when the spot they stop at is within 2 tiles of it and the building is more than 3 tiles from your HQ.
Wild bands, escaped prisoners, their raids and their scouts all count toward the same limit of 3 buildings lost a season.
`tests/unit/test_prison_break.gd`, `test_building_raids.gd` and `test_hearths.gd` pin all of it.

## Fights between armies: the raiding dice
The Rust Kings' raids on you, the wild bands that reach your land and the Giant Frog's raids are each one d20 against a DC worked out from the odds (`Game.raid_dc`):
`DC = 21 - round(20 x attack / (attack + defense))`, kept between 2 and 20. That keeps the chance of winning what attack / (attack + defense) always gave, to the
nearest 5% (even odds are DC 11, 50%; double the defense DC 8, 65%; three times DC 6, 75%; a quarter DC 17, 20%). A natural 20 always wins and a natural 1 never
does, and they are the only critical results. The roll is written to the log ("The Rust Kings' raid on your colony: d20 14 vs DC 9 (60% to win), won."). Every die goes
through `Units.dice`, so tests force them. Your own attacks are not armies any more: your Scavenger Parties attack with the building rolls (see Building raids), and
there is no Raid button. `D20Data.RAID_DICE` holds the numbers:
- **A Rust Kings raid on you** is rolled for them when their raiding party reaches your land: a win takes 20% of your stores (30% on a natural 20), 30% of your troops and a
  person, a tile of your land if it borders theirs, and may roll at your buildings from season 6; the party loses a fifth of its troops. A miss costs the party 40% of its troops and
  you catch a raider (60% and two raiders on a natural 1). It is no longer the whole of their troops: only the party's.
- **A band at your land** is rolled by the band: a win takes 10% of your grain, meat, metal and gold (20% on a natural 20) and rolls at a building; a
  miss gets it driven off with one caught (two on a natural 1).
- **A band ambushing a party on the road** is a ruin fight (`D20Visit.field_fight`): the party's best fighter rolls d20 plus traits and conditions
  against the band's DC (6 + 2 x its strength), and a hit catches one of the band and pays a package. A plain miss costs a light injury and a
  quarter of the load, a critical miss a severe injury and half the load, and only a natural 1 kills someone (the fatal fumble still applies against
  a strength 4 or 5 band). The Rust Kings' raiding parties are bands, so your parties can meet them like this.
- **Scavenger Parties attack camps in person**, like buildings: a party keeping watch on or next to a raider camp gets an "Attack the <camp>" button, and the
  right panel shows "Attack" and the clickable die against the camp's DC (its strength as at a ruin: 16 for a strength 5 camp, with -2 if the camp
  outnumbers the party). A hit scatters the camp, catches a raider and pays the package for a won fight; a miss injures the roller and costs part of
  the load, and the party can try again or "Back off".
`tests/unit/test_raid_dice.gd`, `test_field_fight.gd`, `test_camp_strike.gd`, `test_nat20.gd` and `tests/render/test_raid_panel.gd` pin all of it.

## How the Rust Kings raid you
A raid has to be made and then has to walk to you (`Data.AI_RAID`, `Game._ai_raid_readiness`, `Units.launch_raid`, `Units._raid_turn`):
- **Readiness.** From season 4 (`min_season`), once they have found you and while there is no truce, their raid readiness grows each season by their troops times how
  much they dislike you (1 at relations 0, 2 at -100, 0.3 at the least), with a little luck (x0.7 to x1.3), up to 1.5 times the threshold (40). They need at least 4 troops.
  It keeps growing while a party is out.
- **A party sets out** when the readiness reaches 40 and fewer than 2 parties are out: three quarters of their troops, with that share of their strength, on a war rig or horses
  if they have them and a way for them, on foot otherwise. Those troops leave the fort, so it is weaker while the party is away. It is one of the raider bands, theirs.
- **It walks** 40 days a season (the season replay shows it), fighting any of your parties it meets on the road. You are told when it comes into sight. With the
  **Watchtower** upgrade you are also told when it sets out and how long it has to walk, and the Diplomacy tab shows their readiness.
- **It attacks** where it reaches your land: the guards' roll (see Fights between armies), then, if it won, loot, losses, a tile and rolls at your buildings and, when it is
  strong enough and nothing guards it, at your hearth first. What is left of it walks home and rejoins their troops; a party with none left is gone. Beating one back counts as a raid beaten back.
- **A bribe or a truce** turns the parties that are still on their way back, and a bribe empties the readiness. Truces also stop it growing.
- Saves carry the readiness (`ai.raid_progress`) and the parties. `tests/unit/test_ai_raid_party.gd` pins all of it.

## Wild animals and hunting
Deer, black bears and brown bears roam the wastes (`Data.ANIMALS`, drawn from `art/animals.png`, one 16 x 16 picture to a tile). A game starts with 8 deer, 3
black bears and 2 brown bears on open ground at least 12 tiles from any camp or colony (deer on scrub, dunes and groves; bears on groves, rock and petrified
wood). Each season an animal may drift a tile or two, never more than 5 from where it started and never onto land that is anybody's. They are shown only where
you can see them, like raider bands, and they walk in the season replay. A killed animal is replaced in time: below the cap there is a chance each season (15% a
deer, 6% a bear) that one wanders in from 20 or more tiles from your HQ and out of your sight.
- **Hunting** is two rolls, one die press each, in the panel headed "Hunt" (`D20Visit.begin_hunt`, stages "track" and "kill"). Click an animal's tile and press
  "Hunt with scavengers on foot / on horseback / by war rig" to send a Scavenger Party after it; a waiting party (not in a plane or boat) standing on or beside it gets
  a "Hunt the ..." button. The party arrives, and the animal may have strayed up to 3 tiles (the track roll is the search for it; farther and the trail is
  cold). The **track roll** (the scavenging traits) is DC 8 for a deer, 11 for a black bear and 13 for a brown bear: a CRITICAL_SUCCESS creeps up unseen (+3 on the
  kill shot), a FAILURE loses the trail (the animal wanders off), a CRITICAL_FAILURE spooks it (a deer bolts, a bear charges: the kill shot is forced at -4). The
  **kill shot** (the combat traits) is DC 10 for a deer, and for a bear the DC of a raider of its strength (3 or 5, so 12 and 16, `D20Visit.enemy_dc`) with the
  outnumbered penalty against a party weaker than the bear (a war rig adds 3 to the party's strength). A hit pays meat: a medium package for a deer, a large one
  for a bear, a small package of gold more for a brown bear's hide, one size more on a critical (`HUNT` and `HUNT_PACKAGE` in `d20_data.gd`, times the loot scale). A
  miss against a deer costs nothing; against a bear it mauls the party like any fight (an injury, a quarter of the load, a fatal fumble at DC 14 and up) and the
  bear lives and runs off.
- **Hunting parties are ordinary parties now.** A party sent after an animal is a Scavenger Party of 3 survivors from the roster (a hunting party no longer takes your
  troops, and no longer has the Veteran trait for free: a survivor who is a Veteran still is one). "Send hunting party" is beside the scavengers' "Hunt with scavengers" on an
  animal's tile and on the Giant Frog's. It counts toward the six survivors it takes to kill the frog. Tests: `tests/unit/test_hunting_party.gd`.
- **Bears attack parties that come too close.** At the end of a season a bear within `BEAR_REACH` (2) tiles of one of your parties (not a plane or boat, standing
  parties included) attacks it as a field fight on the raider-band rules (`Units._bear_attacks`): a win drives the bear 5 tiles away, a miss costs an injury and
  a quarter of the load, and a natural 1 kills someone. A party that is hunting that bear is not also attacked by it. Hunting bears makes the land safe until
  another wanders in.
- Tests: `tests/unit/test_hunting.gd`, `tests/render/test_animals_map.gd`.

## The Giant Frog
One frog, asleep under the biggest field of ruins (the epicenter with the most ruin tiles around it, `Units.frog.lair`), not drawn and not huntable while it sleeps
(`Data.FROG`, `FROG_FIGHT` in `d20_data.gd`).
- **Waking.** A natural 1 on any roll of a scavenging visit within 10 tiles of the lair rolls another d20, and 3 or less wakes it (`Units._frog_wakes`). It tears
  out where the party stands and the fight is on: the party may try to run once (DC 11; a miss lets the frog slam them) or stand and fight. A coin flip picks its
  target: your HQ or the Rust Kings' fort.
- **Loose.** Awake, it walks about a tile a day toward its target, is drawn across 2 x 2 tiles whenever you can see it, and each season it stands at a colony it
  raids once on the raiding dice at strength 14 (`Units._frog_raid`): a win costs the colony up to 3 buildings and a fifth of its troops (the Rust Kings a fifth of
  theirs and some walls), a miss makes it rest a season. It heals fully each season.
- **Killing it.** Send parties to its tile (the same "Hunt" buttons). Each rolls the track roll (DC 14); a party that finds it waits, and when you press Attack
  every party waiting there fights together, one die press a round: every standing survivor rolls a combat check against DC 13 (a hit is a wound, a natural 20 or
  6 over two), the frog has 12 wounds, and then it slams 3 times; each slam picks a standing survivor who rolls to dodge (DC 11): a miss fells them (a severe injury,
  out of the fight) and a natural 1 kills them. "Pull back" between rounds. With random traits, over 600 fights each: 3 survivors win 2% of the time, 5 win 16%,
  6 win 38%, 7 win 58%, 9 win 93% and 12 always. It drops 3 raw frog hides, shared round-robin between the parties, which have to carry them home.
- Tests: `tests/unit/test_frog.gd`, `tests/render/test_animals_map.gd`.

## Frog hide, the Drug Factory and Salt
Raw frog hides and Salt are not resources: they live in `Game.items` (`Data.ITEMS`) with no line in the top bar, and parties carry them home like loot.
- **Drug Factory** (10 wood, 15 metal, 10 stone, any land of yours): +1 defense, and each season each factory turns 1 hide from the stores into 2 Salt
  (`Game._drug_factories`). Click it to see how many hides and how much Salt the colony holds.
- **Salt**: a dose protects one survivor for 5 seasons by halving the radiation they take in (`Units._expose`), and a whole salted party halves the radiation that
  penalises its rolls (`Units.visit_ctx`). Switch "Take Salt" on (it appears beside the send buttons once you hold some; off by default) and a party takes a dose
  for each survivor when it leaves, if there are enough. Salted survivors say so in the party panel.
- **Trade**: a dose sells for 30 gold at the Rust Kings' market and costs 60; the market has 1 or 2 for sale in about one season in ten, and a caravan to a trader
  camp brings a dose home instead of its usual goods about one trip in twenty.
- Tests: `tests/unit/test_salt.gd`, `tests/render/test_drug_factory_panel.gd`.

## How the game ends
There are three endings (`Data.ENDINGS` holds the numbers), each shown once: the ending picture (click, or press Enter, to continue), then a
stats screen, then a click on **Return to main menu**. The win or defeat music loops the whole way (`wasteland_OST_lastcall_Victory.wav` for
both wins, `wasteland_OST_signallost_DEFEAT.wav` for a loss) until the menu music takes over. A finished game is not autosaved.
- **Raiders defeated** (you win by force): your parties bring down the Rust Kings' fort (its hearth, once its defences are down: see Building raids), or they are
  left with 6 tiles of land or fewer.
- **The colony prospers** (the long game, and rare): from season 80, the Rust Kings' raid strength stays under a quarter of your defense for 6
  seasons in a row, after at least 2 raids between you, with 20+ colonists, 30+ tiles and nobody starving.
- **Defeat:** your own hearth, the colony HQ, is brought down (a raid of theirs rolls at it first when it is strong enough and nothing guards it; a Citadel stops that),
  your land falls to 6 tiles or fewer, or the colony starves down to 2 people.
- **Stats** (`Game.stats`, saved with the game) cover seasons survived, peak colonists and land, buildings, upgrades, vehicles, their raids beaten
  back or suffered, bands and tribes beaten, prisoners, survivors lost, buildings lost and Rust Kings buildings destroyed, parties sent, ruins and sites stripped, craters searched, nukes found and dropped and blasts, d20 rolls with natural 20s and
  1s, trade runs and resources gathered.
