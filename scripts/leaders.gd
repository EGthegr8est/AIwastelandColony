extends RefCounted
## The people who lead a colony. Each of the three classes (Data.LEADERS) is a random person: a name, a face, two small
## perks and one small flaw. Three are made when the game starts (and again when the player rerolls) and the chosen one
## is saved with the game as Game.leader_info:
##   {"class", "title", "name", "image", "face", "perks": [ids], "flaw": id}
## "image" is a picture in art/leaders/ (raider_1.png with an optional raider_1_small.png for the colony panel); a class
## with no pictures gets a drawn face from "face" (a seed for portrait.gd) instead.
##
## What each perk and flaw does is done where the game already works the number out, behind Game.has_quirk(id), the way
## upgrades are behind Game.has(id). The texts here are shown on the leader cards and in the colony panel.

const Data = preload("res://scripts/data.gd")
const Portrait = preload("res://scripts/portrait.gd")

const FOLDER := "res://art/leaders/"
const THEMES := ["Economy", "War", "Exploring", "Trade"]

const TITLES := {
	"raider": ["Warlord", "Sheriff", "Captain", "Chief", "Marauder"],
	"builder": ["Foreman", "Warden", "Mayor", "Elder", "Engineer"],
	"trader": ["Broker", "Merchant", "Quartermaster", "Peddler", "Dealer"],
}
# A picture that is plainly one kind of person always carries that title, and no other picture of the class is given
# it by chance (the sheriff is never a "Chief", and nobody else is a "General"). Other pictures draw from TITLES.
const PICTURE_TITLES := {
	"raider_1": "Sheriff", "raider_2": "Sheriff", "raider_3": "General",
	"builder_3": "Elder",
	"trader_3": "Executive",
}
const SURNAMES := ["Harlan", "Voss", "Kessler", "Marrow", "Quill", "Rask", "Dunmore", "Thorne", "Vance", "Crowe", "Ashby", "Brandt",
	"Calloway", "Draven", "Everett", "Fenwick", "Garrow", "Holloway", "Ingram", "Jarrow", "Kestrel", "Lowry", "Mercer", "Navarro"]

# Two of these a leader, from two different themes.
const PERKS := {
	"green_thumb": {"name": "Green thumb", "theme": "Economy", "text": "Each farm gives +1 veg."},
	"prospector": {"name": "Prospector", "theme": "Economy", "text": "Each mine gives +1 stone."},
	"haggler": {"name": "Haggler", "theme": "Economy", "text": "Market sales pay 25% more gold, purchases cost 20% less."},
	"old_stash": {"name": "Old stash", "theme": "Economy", "text": "Started with +20 gold and +10 metal."},
	"frugal": {"name": "Frugal", "theme": "Economy", "text": "Starvation kills half as many colonists."},
	"big_families": {"name": "Big families", "theme": "Economy", "text": "New settlers arrive from a food surplus of 6, not 10."},
	"pack_rat": {"name": "Pack rat", "theme": "Economy", "text": "Every party carries 25% more."},
	"mechanic": {"name": "Mechanic", "theme": "Economy", "text": "War rigs, boats and planes cost 20% less to build and burn 20% less fuel."},
	"drill_sergeant": {"name": "Drill sergeant", "theme": "War", "text": "Training a troop costs 1 less metal."},
	"veteran_band": {"name": "Veteran band", "theme": "War", "text": "Started with 2 extra troops."},
	"warden": {"name": "Warden", "theme": "War", "text": "A prison break needs more than 6 prisoners, and the old revolt 4 times your troops."},
	"ransom_broker": {"name": "Ransom broker", "theme": "War", "text": "Ransoms pay 1 more gold a prisoner."},
	"siege_breaker": {"name": "Siege breaker", "theme": "War", "text": "The Rust Kings' walls count 20% less when you raid."},
	"stonemason": {"name": "Stonemason", "theme": "War", "text": "Your buildings need 1 more to destroy (DC +1)."},
	"eagle_eyes": {"name": "Eagle eyes", "theme": "Exploring", "text": "Scouting parties see 1 tile further."},
	"rad_proof": {"name": "Rad-proof", "theme": "Exploring", "text": "Radiation poisons your people 25% more slowly."},
	"trailblazer": {"name": "Trailblazer", "theme": "Exploring", "text": "Parties travel 15% faster."},
	"sharp_nose": {"name": "Sharp nose", "theme": "Exploring", "text": "+1 on every scavenge, trap, cache and site roll."},
	"lucky_streak": {"name": "Lucky streak", "theme": "Exploring", "text": "Every party gets one free reroll, like the Lucky trait."},
	"field_medic": {"name": "Field medic", "theme": "Exploring", "text": "Injuries from rolls are one step lighter."},
	"silver_tongue": {"name": "Silver tongue", "theme": "Trade", "text": "Dustwell started 20 relations friendlier, and befriending it costs half."},
	"caravan_master": {"name": "Caravan master", "theme": "Trade", "text": "Caravan and boat trade runs bring home 25% more gold."},
}

# One of these a leader, from a theme neither perk is in.
const FLAWS := {
	"spendthrift": {"name": "Spendthrift", "theme": "Economy", "text": "Claiming a tile costs 1 more wood."},
	"big_appetites": {"name": "Big appetites", "theme": "Economy", "text": "The colony eats 1 more food for every 5 colonists."},
	"poor_packers": {"name": "Poor packers", "theme": "Economy", "text": "Every party carries 15% less."},
	"lax_guards": {"name": "Lax guards", "theme": "War", "text": "A prison break starts at more than 3 prisoners."},
	"thin_walls": {"name": "Thin walls", "theme": "War", "text": "Walls, towers and keeps give 10% less defense."},
	"shaky_buildings": {"name": "Shaky buildings", "theme": "War", "text": "Your buildings need 1 less to destroy (DC -1)."},
	"butterfingers": {"name": "Butterfingers", "theme": "Exploring", "text": "-1 on every trap and cache roll."},
	"frail_colonists": {"name": "Frail colonists", "theme": "Exploring", "text": "Radiation poisons your people 15% faster."},
	"slow_marchers": {"name": "Slow marchers", "theme": "Exploring", "text": "Parties travel 10% slower."},
	"short_sight": {"name": "Short sight", "theme": "Exploring", "text": "Scouting parties see 1 tile less."},
	"poor_haggler": {"name": "Poor haggler", "theme": "Trade", "text": "Market sales pay 15% less gold."},
	"hard_to_like": {"name": "Hard to like", "theme": "Trade", "text": "Dustwell started 10 relations lower."},
	"bad_blood": {"name": "Bad blood", "theme": "Trade", "text": "The Rust Kings started 15 relations lower, so they raid more often."},
}

static var offered: Array = []        # the three leaders on the selection screen, made once and kept until a reroll
static var _pictures: Dictionary = {}  # class -> picture ids found in FOLDER, filled on first use
static var _textures: Dictionary = {}  # "id" or "id_small" -> Texture2D


# ---------------------------------------------------------------- making leaders

## The three leaders on offer, one per class. Made once per launch: asking again returns the same three unless `reroll`.
static func offer(reroll := false) -> Array:
	if reroll or offered.is_empty():
		offered = make_three()
	return offered


## Three new people, one per class, who share no name, perk or flaw.
static func make_three() -> Array:
	var out := []
	var names := {}
	var perks_used := {}
	var flaws_used := {}
	for cls in Data.LEADERS:
		var leader := {"class": cls}
		var pool := pictures(cls)
		var image: String = pool.pick_random() if not pool.is_empty() else ""
		leader["image"] = image
		leader["title"] = title_for(cls, image)
		var first := ""
		var last := ""
		for attempt in 50:
			first = Data.SURVIVOR_NAMES.pick_random()
			last = SURNAMES.pick_random()
			if not names.has(first + last):
				break
		names[first + last] = true
		leader["name"] = "%s %s %s" % [leader.title, first, last]
		var picks := _pick_perks(perks_used)
		for id in picks:
			perks_used[id] = true
		leader["perks"] = picks
		var flaw := _pick_flaw(picks, flaws_used)
		flaws_used[flaw] = true
		leader["flaw"] = flaw
		leader["face"] = randi() & 0x7fffffff
		out.append(fill(cls, leader))
	return out


## The title of a leader with this picture: the picture's own (a general is a "General"), otherwise one of the class's
## titles that no picture keeps for itself.
static func title_for(cls: String, image: String) -> String:
	if PICTURE_TITLES.has(image):
		return PICTURE_TITLES[image]
	var free: Array = TITLES[cls].filter(func(t): return not t in PICTURE_TITLES.values())
	return free.pick_random()


## Two perks from two different themes, not ones another leader already has.
static func _pick_perks(used: Dictionary) -> Array:
	var free := PERKS.keys().filter(func(id): return not used.has(id))
	if free.size() < 2:
		free = PERKS.keys()
	var first: String = free.pick_random()
	var others := free.filter(func(id): return PERKS[id].theme != PERKS[first].theme)
	if others.is_empty():
		others = PERKS.keys().filter(func(id): return PERKS[id].theme != PERKS[first].theme)
	return [first, others.pick_random()]


## A flaw from a theme neither of the perks is in, not one another leader already has.
static func _pick_flaw(perks: Array, used: Dictionary) -> String:
	var themes := perks.map(func(id): return PERKS[id].theme)
	var free := FLAWS.keys().filter(func(id): return not used.has(id) and not FLAWS[id].theme in themes)
	if free.is_empty():
		free = FLAWS.keys().filter(func(id): return not FLAWS[id].theme in themes)
	return free.pick_random()


## A leader dictionary with every key in place and only known perks and flaws (old saves, and a new game started with
## no leader given, have none).
static func fill(cls: String, info := {}) -> Dictionary:
	var perks := []
	for id in info.get("perks", []):
		if PERKS.has(str(id)):
			perks.append(str(id))
	var flaw := str(info.get("flaw", ""))
	return {"class": cls, "title": str(info.get("title", "")), "name": str(info.get("name", "")), "image": str(info.get("image", "")),
		"face": int(info.get("face", 0)), "perks": perks, "flaw": flaw if FLAWS.has(flaw) else ""}


## "Sheriff Cole Harlan (Raider)", or just the class if the leader has no name.
static func label(info: Dictionary) -> String:
	var cls: String = Data.LEADERS[info.get("class", "builder")].name
	var who := str(info.get("name", ""))
	return "%s (%s)" % [who, cls] if who != "" else cls


## What a leader's perks and flaw do, for the screens: [{"kind": "perk" or "flaw", "name", "text"}].
static func quirk_lines(info: Dictionary) -> Array:
	var out := []
	for id in info.get("perks", []):
		out.append({"kind": "perk", "name": PERKS[id].name, "text": PERKS[id].text})
	if info.get("flaw", "") != "":
		out.append({"kind": "flaw", "name": FLAWS[info.flaw].name, "text": FLAWS[info.flaw].text})
	return out


# ---------------------------------------------------------------- faces

## The picture ids for a class found in art/leaders/ (raider_1, raider_2, ...), without the small versions. Works in
## an exported game too, where the folder lists "raider_1.png.import" instead of the png.
static func pictures(cls: String) -> Array:
	if _pictures.is_empty():
		for c in Data.LEADERS:
			_pictures[c] = []
		for file in DirAccess.get_files_at(FOLDER):
			var name := file.trim_suffix(".import").trim_suffix(".remap")
			if not name.ends_with(".png") or name.ends_with("_small.png"):
				continue
			var id := name.trim_suffix(".png")
			var cls_of: String = id.get_slice("_", 0)
			if _pictures.has(cls_of) and not id in _pictures[cls_of] and ResourceLoader.exists(FOLDER + name):
				_pictures[cls_of].append(id)
		for c in _pictures:
			_pictures[c].sort()
	return _pictures.get(cls, [])


## A leader's portrait: their picture (or its small version, falling back to the big one), or a drawn face if they have none.
static func portrait(info: Dictionary, small := false) -> Texture2D:
	var id: String = info.get("image", "")
	if id != "":
		var key := id + ("_small" if small else "")
		if not _textures.has(key):
			var path := FOLDER + key + ".png"
			if not ResourceLoader.exists(path):
				path = FOLDER + id + ".png"
			_textures[key] = load(path) if ResourceLoader.exists(path) else null
		if _textures[key] != null:
			return _textures[key]
	return Portrait.texture(int(info.get("face", 0)), 45, 0)
