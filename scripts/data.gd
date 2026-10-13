extends RefCounted
## All the game's tunable numbers live here. Change values in this file to rebalance.

const MAP_W := 120
const MAP_H := 72

# Tile owners
const NONE := 0
const PLAYER := 1
const AI := 2
const TOWN := 3

const PLAYER_START := Vector2i(20, 36)
const AI_START := Vector2i(98, 34)
const TOWN_START := Vector2i(36, 18)

const SEASONS := ["Spring", "Summer", "Autumn", "Winter"]

const RESOURCES := ["wood", "stone", "metal", "fuel", "grain", "veg", "meat", "gold"]

# Fog of war: these colonies each keep their own memory of the map.
const FOG_VIEWERS := [PLAYER, AI]
# Owned tiles see 1 tile around them. Buildings with "sight" see further.
const BASE_SIGHT := 1

# Height contours: a line every CONTOUR_STEP meters. Each string is indexed by which
# neighbors the line connects to (up=1, down=2, left=4, right=8), so pipes join up.
# Single pipes are gentle slopes. Double pipes are steep inclines: a drop of STEEP_DROP
# meters or more to a neighboring tile. Index 0 is unused.
const CONTOUR_STEP := 10
const STEEP_DROP := 12
const CONTOUR_GENTLE := " │││─┘┐┤─└┌├─┴┬┼"
const CONTOUR_STEEP := " ║║║═╝╗╣═╚╔╠═╩╦╬"

# How forces travel across the map. "days" is the time to cross one flat tile; "land", slopes
# and water multiply it. A multiplier of 0 means that mover can't enter the tile at all.
const MOVERS := {
	"foot":  {"name": "On foot",   "by": "on foot",      "color": Color("f0e0c0"), "days": 1.0,  "land": 1.0, "gentle": 1.5, "steep": 4.0, "water": 3.0, "shield": 1.0},
	"horse": {"name": "Horseback", "by": "on horseback", "color": Color("d09050"), "days": 0.5,  "land": 1.0, "gentle": 1.5, "steep": 3.0, "water": 2.0, "shield": 1.0},
	"car":   {"name": "War rig",   "by": "by war rig",   "color": Color("ff5a3c"), "days": 0.25, "land": 1.0, "gentle": 1.5, "steep": 0.0, "water": 4.0, "shield": 0.5},
	"boat":  {"name": "Boat",      "by": "by boat",      "color": Color("8fd0ff"), "days": 0.4,  "land": 0.0, "gentle": 0.0, "steep": 0.0, "water": 1.0, "shield": 0.8},
	"plane": {"name": "Plane",     "by": "by plane",     "color": Color("ffffff"), "days": 0.25, "land": 1.0, "gentle": 1.0, "steep": 1.0, "water": 1.0, "shield": 0.2},
}
# "shield" is the share of the radiation that gets through to the people riding (see RAD_* below).
# The ways of travel shown as route dots when you click a tile, and offered for expeditions.
const TRAVEL_PREVIEW := ["foot", "horse", "car"]
# Troops lose 1% of their raid strength for every 4 days on the march (never below 60%).
const MARCH_FATIGUE_DAYS := 400.0
# Each season, everything on the move travels this many days' worth of its route.
const SEASON_DAYS := 40.0

# Rivers wind north to south, 1-2 tiles wide plus the extra tile where they bend
# (about 2 on average), so boats can use them.
# One river runs the whole width of the map, sloping south as it goes east. It passes between
# the camps' lands: it crosses the middle column at RIVER_MID_Y and drops RIVER_SLOPE rows for
# every column, wandering up to RIVER_WIGGLE rows either side of that line. Boats trade along it.
const RIVER_MID_Y := 34
const RIVER_SLOPE := 0.3
const RIVER_WIGGLE := 1
const RIVER_WIDTH := [2, 3]
# Glowing craters mark the epicenter of a big cluster of pre-war ruins: EPICENTERS of them, each
# with a crater CRATER_RADIUS tiles wide and ruins reaching EPICENTER_RADIUS tiles out, thinning
# toward the edge. A few lone ruins are scattered around too (ruin noise above SCATTERED_RUINS).
const EPICENTERS := 5
const EPICENTER_RADIUS := [7, 11]
const CRATER_RADIUS := [1.5, 2.5]
const SCATTERED_RUINS := 0.62
# The camps start in open desert: no craters or lone ruins within this many tiles, and the river
# passes them at a distance (see RIVER_MID_Y and RIVER_SLOPE). Epicenters keep EPICENTER_CAMP_GAP
# tiles clear of camps and EPICENTER_RIVER_GAP from the river.
const START_CLEAR := 8
const EPICENTER_CAMP_GAP := 20
const EPICENTER_RIVER_GAP := 6
# Greenery is scarce and clumped. Each tile gets a fertility score (slow noise, plus RIVER_FERTILITY
# along the river banks). The most fertile TREE_SHARE of the map grows petrified wood, and the
# GROVE_COUNT most fertile spots the catastrophes spared (kept GROVE_SPACING apart) grow a green
# grove of GROVE_RADIUS tiles. Nothing green grows within GREEN_CAMP_GAP of a camp.
const TREE_SHARE := 0.05
const GROVE_COUNT := 2
const GROVE_RADIUS := [3.0, 4.5]
const GROVE_SPACING := 30
const RIVER_FERTILITY := 0.35
const GREEN_CAMP_GAP := 12

# Radiation, in R/h. A crater glows hardest, and the level falls off with distance (RAD_FALLOFF x
# the ruin field's radius). Fused glass, fallout waste and ruins stay hot, and a fallout plume is
# worst near its epicenter. Anything under RAD_SAFE is harmless background. The true level of
# every tile is hidden until one of your scouting parties has stood on it (see Game.measure).
const RAD_BANDS := [
	[0, "Safe", Color("5ad05a")],
	[5, "Low", Color("b8d84a")],
	[20, "Moderate", Color("f0c030")],
	[45, "High", Color("f07a2a")],
	[80, "Extreme", Color("ff3a5a")],
]
const RAD_MAX := 150
const RAD_SAFE := 5
const RAD_CRATER := 120.0
const RAD_FALLOFF := 0.35
const RAD_PLUME := 40.0
const RAD_TERRAIN := {"crater": 40, "glass": 30, "waste": 22, "ruins": 4}
# Radiation sickness works like poison. Each season a survivor's dose is DOSE_DECAY of last season's
# plus RAD_DOSE_RATE per R/h they were exposed to (above RAD_SAFE, after the shielding of how they
# travel). Every point of dose costs POISON_DAMAGE hp a season, so it can't kill outright, but a
# long stay in the hot zones is deadly, and the poison lingers after you leave. Once the dose falls
# below DOSE_ILL they recover RAD_RECOVERY hp a season.
const RAD_DOSE_RATE := 0.6
const DOSE_DECAY := 0.9
const POISON_DAMAGE := 0.12
const RAD_RECOVERY := 3.0
const SURVIVOR_HP := 100.0
const DOSE_ILL := 15.0
const DOSE_SICK := 50.0
const DOSE_CRITICAL := 100.0

# Smoothing passes over the base terrain, so deserts, scrub and rock form clumps not speckle.
const SMOOTH_PASSES := 2

# Every epicenter was hit by one of these catastrophes, long before the game begins.
#   firestorm: burns all greenery out to BURN_REACH x the ruin field's radius
#   fallout:   a plume of poisoned waste, PLUME_LENGTH tiles long, blown off downwind
#   quake:     FAULTS long cracks run out from the crater, FAULT_DROP meters deep
#   glassing:  the desert around the crater is fused to glass, out to GLASS_REACH x the crater
const CATASTROPHES := {
	"firestorm": {"name": "Firestorm", "desc": "A wall of flame burned every green thing for miles around."},
	"fallout":   {"name": "Fallout plume", "desc": "The wind carried poison far downwind, and nothing has lived there since."},
	"quake":     {"name": "Shockwave quake", "desc": "The blast cracked the earth open in long faults and canyons."},
	"glassing":  {"name": "Glassing", "desc": "The heat fused the desert around the crater into glass."},
}
const BURN_REACH := 2.4
const PLUME_LENGTH := [22, 34]
const PLUME_WIDTH := 4.5
const PLUME_CAMP_GAP := 14
const FAULTS := [3, 5]
const FAULT_REACH := 2.0
const FAULT_DROP := 26
const GLASS_REACH := 1.9
const CATASTROPHE_YEARS := [2041, 2089]
const CATASTROPHE_NAMES := [["Ashen", "Hollow", "Black", "Pale", "Screaming", "Weeping", "Sundered", "Burning", "Silent", "Red"],
	["Sky", "Dawn", "Noon", "Dusk", "Reach", "Fall", "Bell", "Mile", "Choir", "Harvest"]]

# Each terrain picks one glyph from its string per tile, like Dwarf Fortress grass.
const TERRAIN := {
	"sand":   {"name": "Ash sand",       "glyph": ".,'`",  "color": Color("c2a26b"), "yield": {}},
	"dunes":  {"name": "Dunes",          "glyph": "~∽",    "color": Color("d8b878"), "yield": {}},
	"scrub":  {"name": "Dead scrub",     "glyph": "\"τ",   "color": Color("8c8a4a"), "yield": {"wood": 1}},
	"trees":  {"name": "Petrified wood", "glyph": "♣♠",    "color": Color("a08050"), "yield": {"wood": 2}, "bg": Color("2e4a22")},
	"grove":  {"name": "Green grove",    "glyph": "♣♠\"",  "color": Color("8fe88f"), "yield": {"wood": 3, "veg": 1}, "bg": Color("2f7a35")},
	"rock":   {"name": "Rock",           "glyph": "▲^",    "color": Color("c8c0b4"), "yield": {"stone": 2}, "bg": Color("68686a")},
	"ruins":  {"name": "Pre-war ruins",  "glyph": "#%π",   "color": Color("e0743a"), "yield": {"metal": 1}, "bg": Color("48484a")},
	"crater": {"name": "Glowing crater", "glyph": "○o",    "color": Color("7cfc00"), "yield": {}},
	"glass":  {"name": "Fused glass",    "glyph": "▒░",    "color": Color("b8a0f0"), "yield": {}, "bg": Color("2c2050")},
	"waste":  {"name": "Fallout waste",  "glyph": ":;'",   "color": Color("d8c850"), "yield": {}, "bg": Color("4c4412")},
	"water":  {"name": "Murky river",    "glyph": "≈~",    "color": Color("5a9a8a"), "yield": {}, "bg": Color("1a3a3c")},
}

# Tile backgrounds. Every land tile gets a wash of SAND whose opacity shows its height, from
# SAND_ALPHA.x on the lowest ground to SAND_ALPHA.y on the highest. Terrain with its own "bg"
# (forests green, rock and ruins grey, water teal) sits under the sand, which only covers
# SAND_OVER_BG of its usual opacity there so the color still shows. Water gets no sand.
const SAND := Color("d8b878")
const SAND_ALPHA := Vector2(0.06, 0.55)
const SAND_OVER_BG := 0.45

# "on": terrain allowed ([] = any land). "req": upgrade needed. "tier": branch tier needed.
const BUILDINGS := {
	"hq":       {"name": "Colony HQ",     "glyph": "Ω", "color": Color("ffd27a"), "buildable": false, "sight": 5, "desc": "Your colony's heart. Sees 5 tiles."},
	"ai_hq":    {"name": "Raider fort",   "glyph": "¥", "color": Color("ff5a3c"), "buildable": false, "sight": 5, "desc": "Rust Kings stronghold."},
	"town":     {"name": "Settlement",    "glyph": "Π", "color": Color("8fc4ff"), "buildable": false, "sight": 4, "desc": "The local settlement."},
	"ai_wall":  {"name": "Raider wall",   "glyph": "▓", "color": Color("d0603c"), "buildable": false, "desc": "A stretch of Rust Kings wall, standing for 4 of their walls. A scouting party next to it can attack it."},
	"farm":     {"name": "Farm",          "glyph": "≡", "color": Color("b8d060"), "cost": {"wood": 5}, "on": ["sand", "scrub"], "yield": {"grain": 3, "veg": 2}, "desc": "Grows grain and vegetables."},
	"lodge":    {"name": "Hunting lodge", "glyph": "h", "color": Color("d08050"), "cost": {"wood": 8}, "on": ["sand", "scrub", "trees", "dunes", "grove"], "yield": {"meat": 3}, "desc": "Hunts in the wastes for meat (+2 in a green grove). Hunters sometimes don't come back."},
	"mine":     {"name": "Mine",          "glyph": "∩", "color": Color("c8c0b0"), "cost": {"wood": 10}, "on": ["rock"], "yield": {"stone": 2, "metal": 2}, "desc": "Digs stone and metal."},
	"salvage":  {"name": "Salvage yard",  "glyph": "Σ", "color": Color("e07a3a"), "cost": {"wood": 6}, "on": ["ruins"], "yield": {"metal": 3}, "desc": "Strips ruins for metal."},
	"refinery": {"name": "Refinery",      "glyph": "Φ", "color": Color("e0c040"), "cost": {"metal": 10, "stone": 5}, "on": [], "desc": "Turns 4 veg into 3 fuel each season once you switch it on. It starts off, and never takes veg the colony needs to eat."},
	"outpost":  {"name": "Outpost",       "glyph": "†", "color": Color("ffb642"), "cost": {"wood": 15, "metal": 5}, "on": [], "sight": 3, "desc": "Claims all free land within 2 tiles. Sees 3 tiles."},
	"market":   {"name": "Trading post",  "glyph": "$", "color": Color("ffe066"), "cost": {"wood": 10, "metal": 4}, "on": [], "yield": {"gold": 1}, "desc": "+1 gold per season and +1 caravan slot."},
	"wall":     {"name": "Wall",          "glyph": "█", "color": Color("a09080"), "cost": {"wood": 4, "stone": 4}, "on": [], "req": "f1", "defense": 2, "desc": "+2 defense (more with Stone Walls)."},
	"tower":    {"name": "Watchtower",    "glyph": "↑", "color": Color("d0b090"), "cost": {"wood": 10, "stone": 10}, "on": [], "req": "f3", "defense": 2, "sight": 7, "desc": "+2 defense. Sees 7 tiles."},
	"keep":     {"name": "Garrison keep", "glyph": "◙", "color": Color("e0d0b0"), "cost": {"stone": 30, "metal": 10}, "on": [], "req": "f4", "defense": 5, "sight": 4, "desc": "+5 defense. Sees 4 tiles."},
	"citadel":  {"name": "Citadel",       "glyph": "☼", "color": Color("ffffff"), "cost": {"stone": 60, "metal": 30, "gold": 20}, "on": [], "req": "f5", "defense": 15, "sight": 5, "desc": "+15 defense. While it stands your land can't be taken."},
	"horse_farm": {"name": "Horse farm",  "glyph": "H", "color": Color("c08a50"), "cost": {"wood": 12, "grain": 10}, "on": ["sand", "scrub"], "desc": "Breeds horses."},
	"motor_pool": {"name": "Motor pool",  "glyph": "&", "color": Color("c06030"), "cost": {"metal": 15, "wood": 10}, "on": [], "tier": 2, "desc": "Builds war rigs."},
	"port":       {"name": "Port",        "glyph": "Ψ", "color": Color("70c0c0"), "cost": {"wood": 20, "metal": 10, "gold": 10}, "on": [], "shore": true, "tier": 3, "desc": "Builds boats and launches them onto the river. Must stand on the riverbank."},
	"airfield":   {"name": "Airfield",    "glyph": "Æ", "color": Color("e0e0e0"), "cost": {"metal": 40, "stone": 30, "gold": 30}, "on": [], "tier": 4, "desc": "Builds airplanes."},
	# Points of interest: 2 x 2 tile sites placed when the map is made (see POIS below and Game._pass_pois). All four
	# of a site's tiles carry the same id, they can't be built on or demolished, and a scavenger party works the
	# whole site as one tile.
	"poi_crashed_ship":    {"name": "Crashed ship",       "glyph": "C", "color": Color("9fd8d0"), "buildable": false, "poi": "crashed_ship",    "desc": "A wrecked ship from before the war."},
	"poi_weather_station": {"name": "Weather station",    "glyph": "W", "color": Color("78a8e8"), "buildable": false, "poi": "weather_station", "desc": "A weather station, still standing."},
	"poi_chemical_dump":   {"name": "Chemical dump",      "glyph": "X", "color": Color("a8e040"), "buildable": false, "poi": "chemical_dump",   "desc": "Leaking drums of chemicals."},
	"poi_radio_tower":     {"name": "Radio tower",        "glyph": "R", "color": Color("78d8c8"), "buildable": false, "poi": "radio_tower",     "desc": "A tall pre-war radio tower."},
	"poi_bunker":          {"name": "Bunker",             "glyph": "B", "color": Color("c8a060"), "buildable": false, "poi": "bunker",          "desc": "A sealed pre-war bunker."},
	"poi_pumpjack":        {"name": "Oil pumpjack",       "glyph": "P", "color": Color("d07040"), "buildable": false, "poi": "pumpjack",        "desc": "A rusted oil pumpjack."},
	"poi_water_tower":     {"name": "Water tower",        "glyph": "T", "color": Color("d08050"), "buildable": false, "poi": "water_tower",     "desc": "A tall rusted water tower."},
	"poi_gas_station":     {"name": "Ruined gas station", "glyph": "G", "color": Color("f0c040"), "buildable": false, "poi": "gas_station",     "desc": "A ruined roadside gas station."},
	"poi_missile_silo":    {"name": "Missile silo",       "glyph": "M", "color": Color("e04848"), "buildable": false, "poi": "missile_silo",    "desc": "A pre-war missile silo."},
	"poi_cargo_yard":      {"name": "Cargo yard",         "glyph": "Y", "color": Color("c06838"), "buildable": false, "poi": "cargo_yard",      "desc": "Stacked shipping containers."},
}

# Where each kind of point of interest likes to stand (every kind gets one per map). "near":
#   any     anywhere open
#   river   2 to 7 tiles from the river
#   rock    on or beside rock
#   waste   within 4 tiles of fallout waste (the footprint becomes waste too)
#   crater  6 to 16 tiles from the centre of a ruin field
#   open    deep desert: 8+ tiles from ruins, craters, waste and water
# If no spot meets the rule after POI_TRIES tries, the rule is dropped so every kind still gets placed.
const POIS := {
	"crashed_ship": {"near": "any"}, "weather_station": {"near": "rock"}, "chemical_dump": {"near": "waste"},
	"radio_tower": {"near": "rock"}, "bunker": {"near": "crater"}, "pumpjack": {"near": "open"},
	"water_tower": {"near": "river"}, "gas_station": {"near": "any"}, "missile_silo": {"near": "crater"},
	"cargo_yard": {"near": "river"},
}
const POI_BASE_GAP := 12     # tiles from any camp or town, so none starts on your doorstep
const POI_GAP := 10          # tiles between two sites
const POI_TRIES := 600       # random spots tried for each kind before a rule is dropped
const POI_TERRAIN := ["sand", "dunes", "scrub", "rock", "trees", "waste"]   # what a site may be built over
# A site's packages (the dice outcomes are in d20_data.gd, SITES) pay this many times what the same package
# pays at an ordinary ruin, on top of the loot scale.
const POI_LOOT_MULT := 1.5

# Prison breaks. A season that ends with more than PRISON_HIGH prisoners and fewer than PRISON_OUTPOSTS of your
# outposts within PRISON_CIRCLE tiles of the HQ (your circle of control) starts one: PRISON_ESCAPE of the prisoners
# (rounded up) get out and you lose a troop guarding them. The escapees become a raider band at the edge of your
# land, as strong as they are many.
const PRISON_HIGH := 4
const PRISON_CIRCLE := 6
const PRISON_OUTPOSTS := 2
const PRISON_ESCAPE := 0.5

# Building raids (the attack rolls and each building's DC are in d20_data.gd). One Raider wall tile stands for
# WALLS_PER_TILE of the Rust Kings' walls. At most RAID_LOSS_CAP of your buildings can be destroyed in a season,
# whoever attacks, and each Rust Kings building you destroy costs RAID_RELATIONS relations with them.
const WALLS_PER_TILE := 4
const RAID_LOSS_CAP := 3
const RAID_RELATIONS := 10
# The Rust Kings attack your buildings from this season on: a winning raid of theirs rolls at up to AI_RAID_ROLLS of them,
# and each of their scouts that ends its move within AI_SCOUT_REACH tiles of one of your buildings (more than
# AI_SCOUT_HOME_GAP tiles from your HQ) has an AI_SCOUT_STRIKE chance of one roll at it, with no bonus.
const AI_BUILDING_ATTACKS_FROM := 6
const AI_RAID_ROLLS := 3
const AI_SCOUT_STRIKE := 0.1
const AI_SCOUT_REACH := 2
const AI_SCOUT_HOME_GAP := 3

const LEADERS := {
	"raider":  {"name": "Raider",  "branch": "warfare",       "attack": 1.25, "defense": 1.0,  "caravans": 1, "desc": "Best attack. 25% off Warfare upgrades.",
		"buffs": ["Attack x1.25", "Warfare upgrades 25% off"]},
	"builder": {"name": "Builder", "branch": "fortification", "attack": 1.0,  "defense": 1.25, "caravans": 1, "desc": "Best defense. 25% off Fortification upgrades.",
		"buffs": ["Defense x1.25", "Fortification upgrades 25% off"]},
	"trader":  {"name": "Trader",  "branch": "commerce",      "attack": 1.0,  "defense": 1.0,  "caravans": 2, "desc": "Extra caravan. 25% off Commerce upgrades.",
		"buffs": ["2 caravan slots", "Commerce upgrades 25% off"]},
}

const BRANCHES := ["warfare", "fortification", "commerce"]

# "needs": upgrades required first. "both": bridge node, needs both branches committed (tier 3+).
const UPGRADES := {
	"farming": {"name": "Irrigation",        "branch": "core", "tier": 1, "cost": {"wood": 10}, "desc": "Farms +1 grain."},
	"hunting": {"name": "Tracking",          "branch": "core", "tier": 1, "cost": {"wood": 10}, "desc": "Lodges +1 meat, fewer hunters lost."},
	"mining":  {"name": "Deep shafts",       "branch": "core", "tier": 1, "cost": {"wood": 10, "stone": 5}, "desc": "Mines +1 metal."},
	"basics":  {"name": "Settlement basics", "branch": "core", "tier": 1, "cost": {"wood": 15}, "desc": "+10 population cap."},

	"w1": {"name": "Raiding parties",        "branch": "warfare", "tier": 1, "cost": {"metal": 10, "meat": 10}, "desc": "+25% attack."},
	"w2": {"name": "Prisoner capture",       "branch": "warfare", "tier": 2, "cost": {"metal": 15, "gold": 10}, "needs": ["w1"], "desc": "+2 prisoners per won raid."},
	"w3": {"name": "Hunter-warriors",        "branch": "warfare", "tier": 3, "cost": {"metal": 20, "meat": 25, "gold": 15}, "needs": ["w2"], "desc": "+50% attack, but troops eat 2 meat."},
	"w4": {"name": "Siege tactics",          "branch": "warfare", "tier": 4, "cost": {"metal": 35, "stone": 20, "gold": 25}, "needs": ["w3"], "desc": "Enemy walls count half."},
	"w5": {"name": "Warlord",                "branch": "warfare", "tier": 5, "cost": {"metal": 50, "meat": 40, "gold": 50}, "needs": ["w4"], "desc": "Won raids annex 3 tiles and keep their buildings."},
	# Warfare vehicles
	"wv1": {"name": "Horse cavalry",         "branch": "warfare", "vehicle": true, "tier": 1, "cost": {"wood": 10, "grain": 15}, "needs": ["w1"], "desc": "Horses +1 attack."},
	"wv2": {"name": "War rig workshops",     "branch": "warfare", "vehicle": true, "tier": 2, "cost": {"metal": 20}, "needs": ["w2"], "desc": "War rigs cost 25% less and get +1 attack from armor."},
	"wv3": {"name": "Naval raiders",         "branch": "warfare", "vehicle": true, "tier": 3, "cost": {"metal": 20, "wood": 20}, "needs": ["w3"], "desc": "Boats +2 attack."},
	"wv4": {"name": "Bombing runs",          "branch": "warfare", "vehicle": true, "tier": 4, "cost": {"metal": 30, "fuel": 15, "gold": 20}, "needs": ["w4"], "desc": "Planes +2 attack. If you have a plane, enemy walls count for nothing."},

	"f1": {"name": "Palisades",              "branch": "fortification", "tier": 1, "cost": {"wood": 20}, "desc": "Unlocks walls."},
	"f2": {"name": "Stone walls",            "branch": "fortification", "tier": 2, "cost": {"stone": 25, "wood": 10}, "needs": ["f1"], "desc": "Walls give +2 more defense."},
	"f3": {"name": "Watchtowers",            "branch": "fortification", "tier": 3, "cost": {"stone": 30, "wood": 20, "gold": 10}, "needs": ["f2"], "desc": "Unlocks towers, warns of raids, +10% defense."},
	"f4": {"name": "Garrison keeps",         "branch": "fortification", "tier": 4, "cost": {"stone": 50, "metal": 20, "gold": 25}, "needs": ["f3"], "desc": "Unlocks keeps. Raiders only take land if they double your defense."},
	"f5": {"name": "Citadel",                "branch": "fortification", "tier": 5, "cost": {"stone": 80, "metal": 40, "gold": 50}, "needs": ["f4"], "desc": "Unlocks the citadel: no land lost while it stands."},
	# Fortification vehicles (mostly counters to enemy vehicles)
	"fv1": {"name": "Spike barricades",      "branch": "fortification", "vehicle": true, "tier": 1, "cost": {"wood": 15}, "needs": ["f1"], "desc": "Enemy horses and war rigs attack at half strength."},
	"fv2": {"name": "Harbor chains",         "branch": "fortification", "vehicle": true, "tier": 2, "cost": {"metal": 15, "stone": 10}, "needs": ["f2"], "desc": "Enemy boats can't attack you."},
	"fv3": {"name": "Sail refits",           "branch": "fortification", "vehicle": true, "tier": 3, "cost": {"wood": 25, "gold": 10}, "needs": ["f3"], "desc": "Your boats need no fuel."},
	"fv4": {"name": "Flak towers",           "branch": "fortification", "vehicle": true, "tier": 4, "cost": {"metal": 30, "stone": 25}, "needs": ["f4"], "desc": "Enemy planes can't attack you or bomb your walls."},

	"c1": {"name": "Extra caravan",          "branch": "commerce", "tier": 1, "cost": {"gold": 15, "wood": 10}, "desc": "+1 caravan slot."},
	"c2": {"name": "Trade contracts",        "branch": "commerce", "tier": 2, "cost": {"gold": 20, "metal": 5}, "needs": ["c1"], "desc": "Caravans and boats bring +4 gold."},
	"c3": {"name": "Trade routes",           "branch": "commerce", "tier": 3, "cost": {"gold": 35, "wood": 20}, "needs": ["c2"], "desc": "+3 gold per ally each season."},
	"c4": {"name": "Bribery",                "branch": "commerce", "tier": 4, "cost": {"gold": 63}, "needs": ["c3"], "desc": "Pay raiders to leave you alone."},
	"c5": {"name": "Merchant empire",        "branch": "commerce", "tier": 5, "cost": {"gold": 128}, "needs": ["c4"], "desc": "Friendly neighbors pay tribute. Buy enemy land."},
	# Commerce vehicles
	"cv1": {"name": "Pack trains",           "branch": "commerce", "vehicle": true, "tier": 1, "cost": {"grain": 15, "gold": 10}, "needs": ["c1"], "desc": "Each horse adds +2 gold to every caravan."},
	"cv2": {"name": "Armored caravans",      "branch": "commerce", "vehicle": true, "tier": 2, "cost": {"metal": 15, "gold": 15}, "needs": ["c2"], "desc": "If you own a war rig, caravans can't be ambushed."},
	"cv3": {"name": "Ethanol synthesis",     "branch": "commerce", "vehicle": true, "tier": 2, "cost": {"metal": 10, "veg": 20}, "needs": ["c2"], "desc": "Refineries turn 4 veg into 4 fuel instead of 3."},
	"cv4": {"name": "Shipwrights",           "branch": "commerce", "vehicle": true, "tier": 3, "cost": {"wood": 25, "gold": 25}, "needs": ["c3"], "desc": "Boats cost 25% less. Owning a port adds a water trade route (+1 caravan)."},
	"cv5": {"name": "Air freight",           "branch": "commerce", "vehicle": true, "tier": 4, "cost": {"fuel": 20, "gold": 30}, "needs": ["c4"], "desc": "Each plane flies supply runs for +6 gold a season."},

	"b_wc": {"name": "Ransom houses",        "branch": "bridge", "tier": 3, "cost": {"gold": 30, "stone": 15}, "both": ["warfare", "commerce"], "desc": "Prisoners sell for 8 gold each."},
	"b_wf": {"name": "Fortified war camps",  "branch": "bridge", "tier": 3, "cost": {"stone": 30, "metal": 20}, "both": ["warfare", "fortification"], "desc": "Outposts defend like walls."},
	"b_fc": {"name": "Toll roads",           "branch": "bridge", "tier": 3, "cost": {"stone": 25, "gold": 25}, "both": ["fortification", "commerce"], "desc": "Every 2 walls earn 1 gold per season."},
}

# A refinery you've switched on turns REFINERY_VEG veg into REFINERY_FUEL fuel each season (the
# Ethanol synthesis upgrade makes it REFINERY_FUEL_ETHANOL). Refineries start switched off, and a
# running one holds back if taking the veg would leave grain + veg short of feeding everyone.
const REFINERY_VEG := 4
const REFINERY_FUEL := 3
const REFINERY_FUEL_ETHANOL := 4

# "tier": highest branch tier you need in any branch (0 = no requirement).
const VEHICLES := {
	"horse": {"name": "Horses",   "building": "horse_farm", "tier": 0, "cost": {"wood": 4, "grain": 6}, "upkeep": {"grain": 1}, "attack": 1, "trade": 1},
	"car":   {"name": "War rigs", "building": "motor_pool", "tier": 2, "cost": {"metal": 11, "wood": 4}, "upkeep": {"fuel": 1}, "attack": 3, "trade": 2},
	"boat":  {"name": "Boats",    "building": "port",       "tier": 3, "cost": {"wood": 10, "metal": 6, "gold": 5}, "upkeep": {"fuel": 1}, "attack": 2, "trade": 4},
	"plane": {"name": "Airplanes","building": "airfield",   "tier": 4, "cost": {"metal": 20, "fuel": 10, "gold": 28}, "upkeep": {"fuel": 2, "gold": 1}, "attack": 5, "trade": 0, "max": 3, "desc": "Each plane widens your HQ's sight by 4 and lets scouts fly anywhere."},
}

# The Rust Kings build vehicles too, once enough seasons have passed.
const AI_VEHICLES := {
	"horse": {"season": 6,  "max": 4, "cost": {"food": 6}},
	"car":   {"season": 10, "max": 3, "cost": {"metal": 8}},
	"boat":  {"season": 16, "max": 2, "cost": {"gold": 10}},
	"plane": {"season": 28, "max": 2, "cost": {"metal": 20, "gold": 15}},
}

# ---------------------------------------------------------------- things on the move

# Characters drawn over the tile when something is standing on it. Other good fits
# (docs/unit_glyph_options.png shows them all on real tiles):
#   scav:    @  ☻  ♀  ¶          caravan: $  ¤  Ö  ∞
#   car:     ö  ▬  Ä  æ          boat:    ►  ◄  ∩  ≡
#   plane:   +  ×  Ŧ  †          band:    &  R  ☺  Ř        tribe camp: Λ  Å  ⌂  ∩
# Avoid ✈ (Consolas has no plane, it draws blank) and box-drawing pipes (they look like contours).
# $ ∩ ≡ † are also building symbols, so pick those only if you don't mind the overlap.
const UNITS := {
	"scav":    {"name": "Scavenger party", "glyph": "☺", "color": Color("f0e0c0"), "sight": 2},
	"scout":   {"name": "Scouting party",   "glyph": "@", "color": Color("9fe8c0"), "sight": 4},
	"caravan": {"name": "Trade caravan",   "glyph": "♦", "color": Color("ffe066"), "sight": 2},
	"car":     {"name": "War rig",         "glyph": "Θ", "color": Color("ff8a4a"), "sight": 3},
	"boat":    {"name": "Boat",            "glyph": "◊", "color": Color("8fd0ff"), "sight": 3},
	"plane":   {"name": "Recon plane",     "glyph": "Ж", "color": Color("ffffff"), "sight": 5},
	"band":    {"name": "Raider band",     "glyph": "☻", "color": Color("ff4a3a"), "sight": 0},
}

# Expeditions you can send out. Crew leave your population until they come home.
const EXPEDITIONS := {
	"scav":    {"name": "Scavenger party", "verb": "Scavenge", "crew": 3, "cost": {"grain": 3}},
	"caravan": {"name": "Trade caravan",   "verb": "Send caravan", "crew": 2, "cost": {"grain": 5, "wood": 3}},
	"boat":    {"name": "River trader",    "verb": "Send boat downriver", "crew": 2, "cost": {"grain": 3}},
	"plane":   {"name": "Recon flight",    "verb": "Fly recon", "crew": 1, "cost": {}},   # the tank it fills is its cost
	"scout":   {"name": "Scouting party",  "verb": "Send scouts", "crew": 2, "cost": {}},
}

# Scouting parties stay where you send them until you give new orders. They leave with a pack of
# SCOUT_PACK food taken from your stores (FOOD_KINDS, in that order) and each survivor eats
# SCOUT_RATION of it a season, so a pack feeds a party of two for SCOUT_PACK / 2 seasons. Once it's
# empty they go hungry: a survivor who goes hungry for STARVE_DEATH seasons in a row dies, and at
# STARVING_AT they are starving. Unspent food goes back to your stores when they come home.
const SCOUT_RATION := 1
const SCOUT_PACK := 8
const FOOD_KINDS := ["grain", "veg", "meat"]
# The route a selected party would take fades from white to yellow to red as its pack runs down:
# yellow once FOOD_WARN of the food would be eaten by that point, red from where it runs out.
const FOOD_WARN := 0.75
const STARVING_AT := 2
const STARVE_DEATH := 3
const SCOUT_MOVERS := ["foot", "horse", "car", "plane"]
# Scouts in a war rig or plane, recon flights, and river trader boats (unless refitted with sails), carry a tank
# filled from your fuel stores when they leave (what is left in it comes home). The party panel shows it as a fuel gauge.
# burn: fuel per tile travelled. idle: fuel per season spent waiting (a plane has to keep circling).
# A dry tank strands them: the vehicle is lost and the people aboard carry on as a party on foot
# (a boat's crew walk home). A plane doesn't land gently, see CRASH_* below.
# The boat's tank covers a round trip of about 75 tiles: ports within ~37 tiles of a river mouth.
const VEHICLE_FUEL := {
	"car":   {"tank": 8,  "burn": 0.1,  "idle": 1.0},
	"plane": {"tank": 10, "burn": 0.05, "idle": 2.0},
	"boat":  {"tank": 3,  "burn": 0.04, "idle": 0.0},
}
# A gauge counts as low (its warning light blinks) under this share of the tank, or under two
# seasons of idle burn, whichever is more.
const FUEL_LOW := 0.2
# A plane that runs dry crashes. Each person aboard lives through it with CRASH_SURVIVAL, and the
# survivors lose CRASH_INJURY hp (of SURVIVOR_HP) and are injured until they heal.
const CRASH_SURVIVAL := 0.6
const CRASH_INJURY := Vector2(10.0, 45.0)

# What a party can carry. Goods have a weight (WEIGHT per unit). Each survivor carries
# CARRY_PER_PERSON, and the way the party travels adds CARRY_BY_MOVER on top: a pack horse is worth
# two people, a war rig five, a plane three (it's weight-limited), a boat eight. Up to that limit
# nothing changes. Past it, travel takes OVERLOAD_SLOWDOWN times as long for every 100% over (never
# worse than OVERLOAD_MAX times as long). A party can't pick up more than LOAD_CEILING times its
# capacity: it leaves the rest behind. What counts is the food pack and the goods being hauled home.
# A vehicle's own fuel tank doesn't count.
# Tuned so a foot party of three (30) carries an average scavenger haul (about 22) with room to spare
# and strains only under a lucky one (up to 38), while a horse or war rig party never notices (50 / 80).
# Bulk classes: stone is bulk, wood, metal and fuel are heavy, food is light, and gold is coin.
const WEIGHT := {
	"wood": 2.0, "stone": 3.0, "metal": 2.0, "fuel": 2.0,
	"grain": 1.0, "veg": 1.0, "meat": 1.0, "gold": 0.5,
}
const CARRY_PER_PERSON := 10.0
const CARRY_BY_MOVER := {"foot": 0.0, "horse": 20.0, "car": 50.0, "boat": 80.0, "plane": 30.0}
const OVERLOAD_SLOWDOWN := 1.0
const OVERLOAD_MAX := 3.0
const LOAD_CEILING := 2.0
# Sight of a scouting party by how it travels (a horse sees further than a walker).
const SCOUT_SIGHT := {"foot": 4, "horse": 5, "car": 3, "plane": 5}

# Survivors in your parties get a name, an age and 1 to 3 traits (see d20_data.gd).
const SURVIVOR_NAMES := ["Mara", "Dex", "Hollis", "Tam", "Juno", "Rook", "Wren", "Cal", "Nell", "Odo",
	"Pike", "Sable", "Tobias", "Ivy", "Brann", "Lark", "Moss", "Reed", "Cass", "Finn", "Dara", "Gus",
	"Hazel", "Jory", "Kit", "Lena", "Milo", "Nora", "Orin", "Pia", "Quill", "Roan", "Sunny", "Teague",
	"Una", "Vik", "Wade", "Yara", "Zeke", "Bett", "Clay", "Dot", "Eli", "Faye", "Gil", "Hank", "Ines", "Jed"]

# A war rig scavenging brings back SCAV_CAR_MULT times the loot (on top of the d20 loot scale) but burns SCAV_CAR_FUEL
# fuel to go. What a ruin pays is in d20_data.gd (the dice, the loot scale, the resource table).
const SCAV_CAR_MULT := 1.5
const SCAV_CAR_FUEL := 2
# Gold the Trade contracts upgrade (c2) adds to every caravan and river trader boat.
const CONTRACT_GOLD := 4
# Goods a trader tribe may pay with, on top of 5 gold.
const TRIBE_GOODS := ["grain", "veg", "meat", "metal", "fuel"]

# Pre-war ruins can hide a rogue raider or a booby trap. Ruins near the settlements are safe.
const RUIN_ROGUE_CHANCE := 0.12
const RUIN_TRAP_CHANCE := 0.10

# Wandering raider bands: raider tribes send them out, and loose ones drift in from the map edge.
const BAND_SPAWN_CHANCE := 0.25   # per raider camp, per season
const WANDERER_CHANCE := 0.10     # per season
const BAND_LIFETIME := 10         # seasons before a band gives up and scatters

# Tribes camp in the wastes. A few may exist at the start, and more can appear later.
const TRIBES_AT_START := 4        # chances of TRIBE_START_CHANCE each
const TRIBE_START_CHANCE := 0.6
const TRIBE_SPAWN_CHANCE := 0.04  # per season
const MAX_TRIBES := 8
const TRIBE_CLASSES := {
	"raider":  {"name": "Raider tribe",  "glyph": "Δ", "color": Color("ff5a3c"), "desc": "Sends raider bands into the wastes. Attack the camp to scatter them."},
	"trader":  {"name": "Trader tribe",  "glyph": "Δ", "color": Color("ffe066"), "desc": "Nomad merchants. Send caravans here to trade."},
	"builder": {"name": "Builder tribe", "glyph": "Δ", "color": Color("8fc4ff"), "desc": "Settled survivors. Gift them food and they may join your colony."},
}
const TRIBE_NAMES := [["Ash", "Dust", "Bone", "Glass", "Rust", "Salt", "Sun", "Ember", "Static", "Cinder"],
	["Jackals", "Walkers", "Kin", "Drifters", "Hands", "Clan", "Eaters", "Children"]]

# Market with the neighbor: [amount, gold received when selling]. Buying costs double.
const MARKET := {
	"wood": [10, 3], "stone": [10, 3], "metal": [5, 4],
	"fuel": [5, 4], "grain": [10, 2], "veg": [10, 2], "meat": [5, 3],
}


# ---------------------------------------------------------------- how the game ends
# There are three endings, each shown once, then a stats screen, then the main menu:
#   raiders_defeated  you win by force: a raid of yours that wins with attack at least decisive_win times their
#                     defense storms their fort, or they are left with broken_land tiles or fewer.
#   defeat            you lose: a raid of theirs that wins with attack at least decisive_loss times your defense
#                     overruns the colony (a Citadel stops that), your land falls to lose_land tiles or fewer, or the
#                     colony starves down to lose_pop people.
#   colony_prospers   the long game, and rare: from season "season" on, the Rust Kings' raid strength stays under "ratio"
#                     of your defense for "streak" seasons in a row, after at least "battles" raids between the two
#                     of you, with the colony healthy ("pop" people, "land" tiles, nobody starving).
const ENDINGS := {
	"decisive_win": 2.5, "decisive_loss": 3.0, "broken_land": 6, "lose_land": 6, "lose_pop": 2,
	"prosper": {"season": 80, "ratio": 0.25, "streak": 6, "battles": 2, "pop": 20, "land": 30},
}
# The picture shown for each ending (they carry their own title text), whether it is a win (which music plays),
# and the heading of the stats screen after it.
const ENDING_SCREENS := {
	"raiders_defeated": {"title": "Raiders defeated", "win": true, "art": "res://art/end_raiders_defeated.png"},
	"colony_prospers": {"title": "The colony prospers", "win": true, "art": "res://art/end_victory.png"},
	"defeat": {"title": "The colony has fallen", "win": false, "art": "res://art/end_defeat.png"},
}

# One line under the stats heading for each way a game ends.
const ENDING_WHY := {
	"stormed": "Your attack was overwhelming and the Rust Kings' fort fell.",
	"broken": "The Rust Kings were left with almost no land.",
	"long game": "The Rust Kings could no longer threaten you, and the colony outlasted them.",
	"overrun": "The Rust Kings overran the colony.",
	"starved": "The colony starved.",
}
