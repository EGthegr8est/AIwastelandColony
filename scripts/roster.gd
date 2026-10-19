extends RefCounted
## The colony's people, one by one. Game.roster holds every survivor the colony has ever had: a name that no one else
## has (or had), an age, 1 to 3 traits, a portrait seed and what has happened to them. A survivor is one Dictionary and it
## stays the same Dictionary: a party that goes out holds the very entries of the roster, so injuries, hunger and Salt
## follow a person home, and a death is a name on the memorial list (state "dead") instead of a smaller number.
##   {"sid", "name", "age", "traits", "face", "state", "joined", "salted", "injury", "hunger", "hp", "dose", "hurt", "leg"}
##   state   "home" (in the colony), "away" (in a party on the map), "enlisted" (trained as a troop) or "dead"
##   dead ones also have "died" (the season) and "cause"

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const Leaders = preload("res://scripts/leaders.gd")

## The roster draws its own random numbers, so making or losing a survivor never moves the game's seeded streams (a map made from a
## seed comes out the same whatever the colony's people turn out to be).
static var _rng := RandomNumberGenerator.new()
## Tests set this to get the same people every time: reseed() then starts the draws from it. 0 means a different colony each game.
static var fixed_seed := 0


## A new game starts the draws again: from fixed_seed in the tests, from the clock otherwise.
static func reseed() -> void:
	if fixed_seed != 0:
		_rng.seed = fixed_seed
	else:
		_rng.randomize()


static func pick(items: Array):
	return items[_rng.randi_range(0, items.size() - 1)]


static func shuffled(items: Array) -> Array:
	var out := items.duplicate()
	for i in range(out.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = out[i]
		out[i] = out[j]
		out[j] = t
	return out


## A new survivor, with a name that is not in `roster` (living or dead). The names run out after Data.SURVIVOR_NAMES, and then
## a surname is added: "Mara Voss". `trained` makes a troop's Veteran trait and one or two of their own.
static func make(roster: Array, season: int, trained := false) -> Dictionary:
	var used := {}
	var top := 0
	for s in roster:
		used[s.name] = true
		top = maxi(top, int(s.sid))
	var pool: Array = Data.SURVIVOR_NAMES.filter(func(n): return not used.has(n))
	var name: String
	if not pool.is_empty():
		name = pick(pool)
	else:
		name = ""
		for tries in 200:
			var tried: String = "%s %s" % [pick(Data.SURVIVOR_NAMES), pick(Leaders.SURNAMES)]
			if not used.has(tried):
				name = tried
				break
		if name == "":
			name = "%s %d" % [pick(Data.SURVIVOR_NAMES), top + 1]
	var trait_ids: Array = shuffled(D20Data.TRAITS.keys())
	var mine: Array = trait_ids.slice(0, _rng.randi_range(1, 3))   # 1 to 3 traits each, no repeats
	if trained:
		var others: Array = trait_ids.filter(func(id): return id != "veteran")
		mine = ["veteran"] + others.slice(0, _rng.randi_range(0, 2))
	return {"sid": top + 1, "name": name, "age": _rng.randi_range(17, 58), "traits": mine, "state": "home", "joined": season,
		"salted": 0,   # seasons of Salt left: the radiation they take in is halved while this is above 0
		"injury": "none",   # from this expedition's rolls: none, light or severe, until the party is home
		"hunger": 0, "hp": Data.SURVIVOR_HP, "dose": 0.0, "hurt": false,   # hurt: injured in a crash, until they heal
		"leg": false,   # a broken leg (or a lame horse): slows the party until it gets home or this person dies
		"face": _rng.randi() & 0x7fffffff}   # the seed for their portrait


## A survivor read back from a save (JSON gives every number as a float). Saves from before the roster have no "sid" or "state".
static func load_one(s: Dictionary, sid: int, state: String, season: int) -> Dictionary:
	var out := {"sid": int(s.get("sid", sid)), "name": s["name"], "age": int(s["age"]),
		"traits": s.get("traits", []).filter(func(id): return D20Data.TRAITS.has(id)),   # none in saves from before the d20 rolls
		"state": s.get("state", state), "joined": int(s.get("joined", season)),
		"injury": s.get("injury", "none"),
		"hunger": int(s.get("hunger", 0)), "hp": float(s.get("hp", Data.SURVIVOR_HP)), "dose": float(s.get("dose", 0.0)),
		"hurt": bool(s.get("hurt", false)), "salted": int(s.get("salted", 0)), "leg": bool(s.get("leg", false)),
		"face": int(s["face"]) if s.has("face") else hash(s["name"]) & 0x7fffffff}
	if out.state == "dead":
		out["died"] = int(s.get("died", 0))
		out["cause"] = s.get("cause", "")
	return out
