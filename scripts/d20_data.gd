extends RefCounted
## Every number of the d20 roll system for scavenging and combat. The tables are the ones in the design doc
## "D20 Roll System: Scavenging & Combat" and all of them are starting values to tune here. The logic in
## d20.gd and d20_visit.gd reads these and never hardcodes a value.

# Tier names, spelled exactly like this everywhere. Worst to best.
const CRITICAL_FAILURE := "CRITICAL_FAILURE"
const FAILURE := "FAILURE"
const SUCCESS := "SUCCESS"
const CRITICAL_SUCCESS := "CRITICAL_SUCCESS"
const TIERS := ["CRITICAL_FAILURE", "FAILURE", "SUCCESS", "CRITICAL_SUCCESS"]

# A natural 1 is always a CRITICAL_FAILURE and a natural 20 always a CRITICAL_SUCCESS. Otherwise the margin
# (d20 + modifiers - DC) decides: CRIT_MARGIN or worse below the DC is critical, any other miss is a FAILURE,
# a hit by up to CRIT_MARGIN - 1 is a SUCCESS, and CRIT_MARGIN or more over is critical.
const NAT_FAIL := 1
const NAT_CRIT := 20
const CRIT_MARGIN := 6
# Trait and situational modifiers together are clamped to -MOD_CLAMP..+MOD_CLAMP, so the d20 always matters.
const MOD_CLAMP := 5

const DC := {"easy": 8, "standard": 11, "hard": 14, "deadly": 17}

# Situational modifiers (they stack with trait modifiers, inside the clamp).
const SITUATION := {
	"surprised_light": -2, "surprised_heavy": -4, "springs_ambush": 3, "outnumbered": -2, "night": -1,
	"injury_light": -1, "injury_severe": -2,
}

# Which trait modifiers a check adds up.
const CHECK_MODS := {
	"combat": ["combat"],
	"ambush": ["scavenge", "ambush"],
	"trap": ["scavenge", "trap"],
	"cache": ["scavenge"],
	"site": ["scavenge"],
	"track": ["scavenge"],
	"run": ["scavenge", "ambush"],
	"dodge": ["scavenge", "ambush"],
}

# What a scout runs into: a plain d20, no modifiers, so traits never change what exists at a site. A high roll is a good
# one: a natural 20 finds a cache (the table ran the other way round at first, so a 20 found nothing). The hazard faces,
# 1 to 6, are rerolled at a ruin whose hazards the map has already settled.
const EVENT_TABLE := [
	{"min": 1, "max": 3, "event": "ambush"},
	{"min": 4, "max": 6, "event": "trap"},
	{"min": 7, "max": 10, "event": "nothing"},
	{"min": 11, "max": 15, "event": "minor_find"},
	{"min": 16, "max": 20, "event": "cache"},
]

# Which resource a cache, a minor find or a disarmed trap holds: a plain d20. Metal is the main ruin resource
# (the design doc had none); "veg" is the preserved vegetables, which sell for little, so it is the rare one.
const RESOURCE_TABLE := [
	{"min": 1, "max": 8, "resource": "metal"},
	{"min": 9, "max": 12, "resource": "fuel"},
	{"min": 13, "max": 17, "resource": "gold"},
	{"min": 18, "max": 20, "resource": "veg"},
]

# Loot packages: the dice rolled once the size is known, per resource.
const SIZES := ["small", "medium", "large"]
const PACKAGES := {
	"small": {"metal": "1d6", "fuel": "1d4", "gold": "1d6", "veg": "1d6"},
	"medium": {"metal": "2d6", "fuel": "2d4", "gold": "2d6", "veg": "2d6"},
	"large": {"metal": "4d6", "fuel": "4d4", "gold": "4d6", "veg": "4d6"},
}
# Every package roll is multiplied by this before the traits' multipliers. The design doc's dice are sized for a
# leaner economy than this game's: x3 keeps an average ruin visit near 8.8 gold-equivalent against 10.7 before the
# d20 system, and a player who searches deeper gets close to 10.
const LOOT_SCALE := 3.0
# Trait loot multipliers multiply together and never go above this.
const LOOT_MULT_CAP := 2.0

# What each tier does. "injury" is none, light or severe. "carried_loss" is the share of the loot the party was
# already carrying that is lost, rounded down per resource.
const COMBAT := {
	"CRITICAL_FAILURE": {"injury": "severe", "carried_loss": 0.5, "enemy_package": "", "camp_revealed": false},
	"FAILURE": {"injury": "light", "carried_loss": 0.25, "enemy_package": "", "camp_revealed": false},
	"SUCCESS": {"injury": "none", "carried_loss": 0.0, "enemy_package": "small", "camp_revealed": false},
	"CRITICAL_SUCCESS": {"injury": "none", "carried_loss": 0.0, "enemy_package": "medium", "camp_revealed": true},
}

# Ambush: "fight" is true for a forced fight, "choice" when the scout may fight or slip away, and "win" when the party turns
# the ambush on the raiders and beats them outright (a CRITICAL_SUCCESS: it used to force a fight at +3 that could still be
# lost). "situational" is the modifier on that fight's combat check. A CRITICAL_SUCCESS also pays "bonus_package" on a win.
const AMBUSH := {
	"CRITICAL_FAILURE": {"fight": true, "situational": -4, "carried_loss": 0.25, "bonus_package": ""},
	"FAILURE": {"fight": true, "situational": -2, "carried_loss": 0.0, "bonus_package": ""},
	"SUCCESS": {"fight": "choice", "situational": 0, "carried_loss": 0.0, "bonus_package": ""},
	"CRITICAL_SUCCESS": {"fight": "win", "situational": 3, "carried_loss": 0.0, "bonus_package": "small"},
}

const TRAP := {
	"CRITICAL_FAILURE": {"injury": "severe", "carried_loss": 0.25, "package": ""},
	"FAILURE": {"injury": "light", "carried_loss": 0.0, "package": ""},
	"SUCCESS": {"injury": "none", "carried_loss": 0.0, "package": ""},
	"CRITICAL_SUCCESS": {"injury": "none", "carried_loss": 0.0, "package": "small"},
}

# Cache: "package" is the size of the rolled resource, "extra_package" a small one of a different resource, and
# "ambush_situational" (when present) means the noise draws an ambush check at that modifier.
const CACHE := {
	"CRITICAL_FAILURE": {"package": "", "extra_package": "", "ambush_situational": -2},
	"FAILURE": {"package": "small", "extra_package": ""},
	"SUCCESS": {"package": "medium", "extra_package": ""},
	"CRITICAL_SUCCESS": {"package": "large", "extra_package": "small"},
}

# The ten points of interest. A site is one "site" check (the party's scavenge modifiers, the situation) against its
# "dc", and the tier of the roll picks one outcome: a "name" for the log and a list of "do" effects, done in order.
# A site is searched once and never searched deeper. The picks are the ones approved in the design doc "Points of
# Interest: Dice Outcome Options"; the other options in that doc are not built.
#   {"pkg": size, "res": resource}   a small, medium or large package of that resource
#   {"pkg": size}                    a package of a rolled resource ("other": true rolls one that differs from the last)
#   {"each": size}                   one package of every resource
#   {"injury": "light"|"severe"}     on the survivor who rolled, until the party is home
#   {"dose": n}                      radiation every survivor in the party takes
#   {"fight": n}                     a forced fight against strength n (its DC is ENEMY_DC's); winning ends the visit
#   {"reveal": n}                    the map within n tiles of the site is marked explored when the party heads home
#   {"reveal_fort": true}            the Rust Kings' fort and the land around it is marked explored
#   {"trust": n}                     Dustwell's relations rise by n
#   {"colonists": n} {"troops": n}   join the colony when the party heads home (colonists up to the population cap)
#   {"lose": share}                  that share of what was found at the site so far is lost
const SITE_FORT_REVEAL := 6
const SITES := {
	"crashed_ship": {"dc": 14, "outcomes": {
		"SUCCESS": {"name": "Hull salvage", "do": [{"pkg": "medium", "res": "metal"}, {"pkg": "small", "res": "fuel"}]},
		"CRITICAL_SUCCESS": {"name": "Flight recorder", "do": [{"pkg": "medium", "res": "metal"}, {"reveal": 15}]},
		"FAILURE": {"name": "Sharp wreckage", "do": [{"injury": "light"}, {"pkg": "small", "res": "metal"}]},
		"CRITICAL_FAILURE": {"name": "Reactor leak", "do": [{"injury": "severe"}, {"dose": 40}]},
	}},
	"weather_station": {"dc": 11, "outcomes": {
		"SUCCESS": {"name": "Logbook", "do": [{"pkg": "small", "res": "metal"}, {"reveal": 10}]},
		"CRITICAL_SUCCESS": {"name": "Working radar", "do": [{"pkg": "medium", "res": "metal"}, {"reveal": 20}]},
		"FAILURE": {"name": "Nothing salvageable", "do": []},
		"CRITICAL_FAILURE": {"name": "Fall from the tower", "do": [{"injury": "severe"}]},
	}},
	"chemical_dump": {"dc": 14, "outcomes": {
		"SUCCESS": {"name": "Intact drums", "do": [{"pkg": "medium", "res": "fuel"}, {"pkg": "small", "res": "gold"}]},
		"CRITICAL_SUCCESS": {"name": "Fuel precursors", "do": [{"pkg": "large", "res": "fuel"}]},
		"FAILURE": {"name": "Fumes", "do": [{"injury": "light"}, {"dose": 10}, {"pkg": "small", "res": "fuel"}]},
		"CRITICAL_FAILURE": {"name": "Toxic spill", "do": [{"injury": "severe"}, {"dose": 50}]},
	}},
	"radio_tower": {"dc": 14, "outcomes": {
		"SUCCESS": {"name": "Beacon logs", "do": [{"reveal": 15}]},
		"CRITICAL_SUCCESS": {"name": "Relay still live", "do": [{"reveal": 25}, {"trust": 20}]},
		"FAILURE": {"name": "Slip on the mast", "do": [{"injury": "light"}]},
		"CRITICAL_FAILURE": {"name": "The signal draws raiders", "do": [{"fight": 4}]},
	}},
	"bunker": {"dc": 14, "outcomes": {
		"SUCCESS": {"name": "Supply racks", "do": [{"pkg": "medium", "res": "metal"}, {"pkg": "medium", "res": "veg"}]},
		"CRITICAL_SUCCESS": {"name": "Intact armory", "do": [{"troops": 4}, {"pkg": "medium", "res": "metal"}]},
		"FAILURE": {"name": "Jammed door", "do": [{"injury": "light"}, {"pkg": "small", "res": "metal"}]},
		"CRITICAL_FAILURE": {"name": "Squatters", "do": [{"fight": 5}]},
	}},
	"pumpjack": {"dc": 14, "outcomes": {
		"SUCCESS": {"name": "Crude drums", "do": [{"pkg": "medium", "res": "fuel"}]},
		"CRITICAL_SUCCESS": {"name": "Still pumping", "do": [{"pkg": "large", "res": "fuel"}, {"pkg": "medium", "res": "gold"}]},
		"FAILURE": {"name": "Pressure burst", "do": [{"injury": "light"}]},
		"CRITICAL_FAILURE": {"name": "Oil fire", "do": [{"injury": "severe"}, {"lose": 1.0}]},
	}},
	"water_tower": {"dc": 11, "outcomes": {
		"SUCCESS": {"name": "Stored rations", "do": [{"pkg": "medium", "res": "veg"}]},
		"CRITICAL_SUCCESS": {"name": "Cistern garden", "do": [{"pkg": "large", "res": "veg"}, {"colonists": 2}]},
		"FAILURE": {"name": "Nothing here", "do": []},
		"CRITICAL_FAILURE": {"name": "Tower collapse", "do": [{"injury": "severe"}]},
	}},
	"gas_station": {"dc": 11, "outcomes": {
		"SUCCESS": {"name": "Underground tanks", "do": [{"pkg": "medium", "res": "fuel"}]},
		"CRITICAL_SUCCESS": {"name": "Full tank farm", "do": [{"pkg": "large", "res": "fuel"}, {"pkg": "medium", "res": "metal"}]},
		"FAILURE": {"name": "Already looted", "do": []},
		"CRITICAL_FAILURE": {"name": "Raiders' ambush", "do": [{"fight": 3}]},
	}},
	"missile_silo": {"dc": 17, "outcomes": {
		"SUCCESS": {"name": "Fuel store", "do": [{"pkg": "large", "res": "fuel"}]},
		"CRITICAL_SUCCESS": {"name": "Targeting data", "do": [{"reveal_fort": true}, {"pkg": "medium", "res": "metal"}]},
		"FAILURE": {"name": "Locked down", "do": []},
		"CRITICAL_FAILURE": {"name": "Automated defenses", "do": [{"fight": 5}]},
	}},
	"cargo_yard": {"dc": 11, "outcomes": {
		"SUCCESS": {"name": "Mixed containers", "do": [{"each": "small"}]},
		"CRITICAL_SUCCESS": {"name": "The sealed container", "do": [{"pkg": "large"}, {"pkg": "medium", "other": true}]},
		"FAILURE": {"name": "Falling crate", "do": [{"injury": "light"}]},
		"CRITICAL_FAILURE": {"name": "Crushed by a stack", "do": [{"injury": "severe"}]},
	}},
}

# Building raids. Destroying a building is one attack roll, d20 + a modifier against the building's DC here (a building
# that isn't listed, such as an HQ, the Rust Kings' fort, the citadel, Dustwell or a point of interest, can't be
# destroyed). A scouting party rolls like a fight, with its own traits. A raid or a raider band is a number: its
# modifier is RAID_BONUS's value for the first row its strength reaches, in multiples of the defense it meets
# (RAID_PENALTY below that). Stone walls (the f2 upgrade) make your own walls STONE_WALL_DC harder.
const BUILDING_DC := {
	"farm": 8, "lodge": 8, "horse_farm": 8, "salvage": 8, "market": 8,
	"mine": 10, "refinery": 10, "motor_pool": 10, "port": 10, "airfield": 10,
	"outpost": 11, "wall": 12, "tower": 12, "keep": 15, "ai_wall": 12, "drug_factory": 10,
}
const STONE_WALL_DC := 2
const RAID_BONUS := [[2.0, 4], [1.5, 2], [1.0, 0]]
const RAID_PENALTY := -2

# The fights between armies (the Raiding Dice plan): your attacks on a raider camp, the Rust Kings' fort and Dustwell, their
# raids on you, and the wild bands that reach your land. Each is one d20 against a DC worked out from the odds
# (Game.raid_dc: 21 - round(20 * attack / (attack + defense)), kept within "dc_min" and "dc_max"), so the chance of winning is
# what attack / (attack + defense) always gave, to the nearest 5%. Only a natural 20 and a natural 1 are critical. The shares
# are of troops, or of what is stolen. A win and a miss do what they always did; the "crit_" rows are what changes.
const RAID_DICE := {
	"dc_min": 2, "dc_max": 20,
	"camp": {"prisoners": 2, "crit_prisoners": 3, "crit_loot_mult": 1.5, "troops_lost": 0.4, "crit_troops_lost": 0.6, "crit_camp_grows": 1},
	"fort": {"troops_lost": 0.4, "crit_troops_lost": 0.6, "crit_prisoners": 1, "crit_strikes": 1},
	"town": {"prisoners": 5, "crit_prisoners": 7, "troops_lost": 0.4, "crit_troops_lost": 0.6},
	"their_raid": {"loot": 0.2, "crit_loot": 0.3, "their_troops_lost": 0.4, "crit_their_troops_lost": 0.6, "caught": 1, "crit_caught": 2},
	"band": {"loot": 0.1, "crit_loot": 0.2, "caught": 1, "crit_caught": 2},
}

# An injury lasts until the party is home and costs the survivor SITUATION's injury_light / injury_severe on every roll.
# Worst last: a worse injury replaces a lighter one, never the other way round.
const INJURY_RANK := ["none", "light", "severe"]

# Permadeath is on. A fatal fumble: a CRITICAL_FAILURE on a "check" against an enemy of DC "min_dc" or more (Hard
# and up) rolls a d20, and "roll_max" or less kills the scout ("scope": "roller") or the whole party ("party").
# That is about 0.8% of ruin visits. The design doc's own rule needed a DC 17 enemy, which scavenging never meets.
const PERMADEATH := true
const FATAL_FUMBLE := {"check": "combat", "tier": "CRITICAL_FAILURE", "min_dc": 14, "roll_max": 5, "scope": "party"}

# Searching deeper: a CRITICAL_SUCCESS on a cache check offers another cache check at DC +dc_step for each step
# already taken, up to max_depth times. Each step down pays packages one size larger (a FAILURE gives the next
# size up from small, a SUCCESS from medium). A CRITICAL_FAILURE on a deeper search collapses the cache: collapse_loss
# of everything found at this site is lost (and the noise draws an ambush check, as for any ruined cache).
const SEARCH_DEEPER := {"trigger": "CRITICAL_SUCCESS", "dc_step": 3, "max_depth": 2, "collapse_loss": 0.5}

# Situational modifiers worked out from the game, on top of the doc's fixed ones in SITUATION:
#   RADIATION_PENALTY   [reading in R/h after the vehicle's shield, modifier]: the highest band reached counts
#   SICK_PENALTY        by radiation sickness level (0 healthy, 1 ill, 2 radiation sick, 3 critical)
#   HUNGER_PENALTY      [seasons hungry, modifier]
#   HURT_PENALTY        a survivor with the plane-crash injured mark
# "Outnumbered" (SITUATION) applies when the enemy's strength is above the party's. A fight's DC comes from the
# enemy's strength: base + per_strength x strength, held between min and max. A noise ambush and a rogue raider
# have a strength in ENEMY_STRENGTH.
const RADIATION_PENALTY := [[20, -1], [45, -2], [80, -3]]
const SICK_PENALTY := [0, -1, -2, -3]
const HUNGER_PENALTY := [[1, -1], [2, -2]]
const HURT_PENALTY := -1
const ENEMY_DC := {"base": 6, "per_strength": 2, "min": 8, "max": 17}
const ENEMY_STRENGTH := [2, 5]

# The starter traits. Each has "mods" per kind of check, and optionally:
#   tier_shifts         [{check, from, to}]        a tier moves once, after the roll
#   outcome_flags       [{check, tier, flag}]      a flag the outcome reads ("no_injury", "injury_severe")
#   loot_mult           {resource or "all": x}     multiplies loot of that resource
#   loot_size_shift     [{check, tier, steps}]     bumps the loot package up this many sizes
#   reroll_charges_per_expedition                  rerolls of one check that landed FAILURE or worse
#   situation           {name: multiplier}         scales one of the situational penalties (0 ignores it)
const TRAITS := {
	"sharp_eyed": {"name": "Sharp-Eyed", "mods": {"combat": 0, "scavenge": 2, "ambush": 0, "trap": 2},
		"tier_shifts": [
			{"check": "trap", "from": "CRITICAL_FAILURE", "to": "FAILURE"},
			{"check": "ambush", "from": "CRITICAL_FAILURE", "to": "FAILURE"},
		]},
	"light_footed": {"name": "Light-Footed", "mods": {"combat": -1, "scavenge": 1, "ambush": 3, "trap": 0}},
	"trigger_happy": {"name": "Trigger-Happy", "mods": {"combat": 2, "scavenge": -1, "ambush": -2, "trap": 0},
		"loot_size_shift": [{"check": "combat", "tier": "CRITICAL_SUCCESS", "steps": 1}]},
	"veteran": {"name": "Veteran", "mods": {"combat": 2, "scavenge": 0, "ambush": 1, "trap": 0},
		"tier_shifts": [{"check": "combat", "from": "CRITICAL_FAILURE", "to": "FAILURE"}],
		"situation": {"outnumbered": 0.0}},
	"cowardly": {"name": "Cowardly", "mods": {"combat": -3, "scavenge": 0, "ambush": 2, "trap": 0},
		"outcome_flags": [{"check": "combat", "tier": "FAILURE", "flag": "no_injury"}],
		"situation": {"outnumbered": 2.0}},
	"clumsy": {"name": "Clumsy", "mods": {"combat": -1, "scavenge": -1, "ambush": 0, "trap": -3},
		"outcome_flags": [{"check": "trap", "tier": "FAILURE", "flag": "injury_severe"}]},
	"paranoid": {"name": "Paranoid", "mods": {"combat": 0, "scavenge": -1, "ambush": 4, "trap": 2},
		"loot_mult": {"all": 0.85}},
	"lucky": {"name": "Lucky", "mods": {"combat": 0, "scavenge": 0, "ambush": 0, "trap": 0},
		"reroll_charges_per_expedition": 1},
	"gearhead": {"name": "Gearhead", "mods": {"combat": 0, "scavenge": 0, "ambush": 0, "trap": 0},
		"loot_mult": {"fuel": 1.5}},
	"green_thumb": {"name": "Green Thumb", "mods": {"combat": 0, "scavenge": 0, "ambush": 0, "trap": 0},
		"loot_mult": {"veg": 1.5}},
	"magpie": {"name": "Magpie", "mods": {"combat": -1, "scavenge": 1, "ambush": 0, "trap": 0},
		"loot_mult": {"gold": 1.5}},
}


# ---------------------------------------------------------------- hunting
# A hunt is two rolls, one die press each. The track roll (a "track" check, the party's scavenging traits) against the animal's
# "track_dc" finds it; the kill shot (a "combat" check) against its kill DC brings it down. A bear's kill DC is the one a raider
# of its "strength" has (ENEMY_DC), so a bear that catches a party on the road and one the party hunts are the same animal; a
# deer (strength 0) has its own "kill_dc". "pays" is the size of the meat package (HUNT_PACKAGE, times the loot scale like any
# loot), "extra" a second package of gold for a hide. A CRITICAL_SUCCESS on the kill shot pays one size more.
const HUNT := {
	"deer": {"track_dc": 8, "strength": 0, "kill_dc": 10, "pays": "medium", "extra": ""},
	"black_bear": {"track_dc": 11, "strength": 3, "kill_dc": 0, "pays": "large", "extra": ""},
	"brown_bear": {"track_dc": 13, "strength": 5, "kill_dc": 0, "pays": "large", "extra": "small"},
	"frog": {"track_dc": 14, "strength": 0, "kill_dc": 0, "pays": "", "extra": ""},   # tracked like the rest, then fought in rounds: see FROG_FIGHT
}
const HUNT_PACKAGE := {"small": "1d6", "medium": "2d6", "large": "4d6"}
# Tracking: a CRITICAL_SUCCESS creeps up unseen (the kill shot gets this much), a CRITICAL_FAILURE spooks it: a deer bolts and a
# bear charges (the kill shot is forced, at this penalty). A FAILURE loses the trail.
const HUNT_UNSEEN := 3
const HUNT_CHARGED := -4

# The Giant Frog fight (see FROG in data.gd for where it sleeps and what it does). Track it at "track_dc", then fight in rounds,
# one die press each: every standing survivor rolls a combat check against "hit_dc" (a hit is one wound, a natural 20 or 6 over
# two, a natural 1 a miss), then the frog slams "slams" times. A slam picks a standing survivor, who rolls to dodge at "dodge_dc":
# a miss fells them (severe injury, out of the fight) and a natural 1 kills them. "strength" is what a party's strength is
# measured against for the outnumbered penalty: 0, because no party of three is "as strong" as the frog and the fight is tuned without it. A party that wakes it by a natural 1 may try to run once at "run_dc"; a miss costs
# a round of slams. The frog's wounds heal fully each season.
const FROG_FIGHT := {"track_dc": 14, "wounds": 12, "hit_dc": 13, "slams": 3, "dodge_dc": 11, "run_dc": 11, "strength": 0}
