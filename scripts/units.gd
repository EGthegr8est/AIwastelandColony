extends Node
## Autoload "Units": everything that moves across the map (your expeditions and wild raider
## bands) plus the tribe camps scattered through the wastes. Game.end_season() calls season_turn().
##
## A unit is a Dictionary:
##   job      "scav", "caravan", "boat", "plane", "scout" (your expeditions) or "band" (wild raiders)
##   owner    Data.PLAYER, or Data.NONE for wild bands
##   mover    which route finder it uses: "foot", "horse", "car", "boat" or "plane"
##   pos, target, home   map cells; stage is "out" until the job is done, then "back".
##                       Scouting parties have a third stage, "station": they stay put until given orders.
##                       A scavenger party that reaches its ruin is at the "site" and holds a "visit" (see
##                       d20_visit.gd) that the player rolls through, one button press at a time. A scouting party
##                       attacking a Rust Kings building does the same, then goes back to "station".
##   crew     colonists on board (they rejoin the population when they get home)
##   survivors   the named people on board: {"name", "age", "traits" (ids from d20_data.gd), "injury" (none, light
##               or severe, until the party is home), "hunger", "face"}. crew is their count ("face" seeds their
##               portrait, see portrait.gd). The party's traits combine in a roll, and a trait two of them share counts once.
##   fuel     scouts in a war rig or plane only: what's left in the tank
##   food     scouts only: the pack they eat from, {"grain": 5, "veg": 3}. Filled from your stores when they leave
##            and emptied by the survivors a season at a time. What's left goes back to your stores on arrival.
##   carry    resources being brought home; strength: how hard a band hits
##   dest     tribe id for caravans to a tribe, -1 for the Rust Kings
##   path     the cells still to walk (not saved; rebuilt on load)

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Dice = preload("res://scripts/dice.gd")
const Roster = preload("res://scripts/roster.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

const FROG_ID := 1        # the Giant Frog's id as a hunting target (a unit's id is never below 2)

var dice = Dice.new()     # every roll of a ruin visit goes through this (tests swap in forced dice)
var animals: Array = []   # wild animals: {"id", "kind" (a key of Data.ANIMALS), "pos", "home"}
var frog := {}            # the Giant Frog, see the section on it below
var replay := {}          # the last season_turn() as the map plays it back (see season_replay.gd); not saved
var _recording := false   # true while season_turn() runs: only then are walks and events noted
var _actors := {}         # unit id -> its entry in replay.actors
var units: Array = []
var tribes: Array = []    # {"id", "class", "name", "pos", "strength", "relations", "found"}
var next_id := 1
var wild_spawns := true   # false stops new raider bands and tribes appearing (for tests)
var crash_survival := Data.CRASH_SURVIVAL   # each person's chance of living through a plane crash (tests set it)


func new_world() -> void:
	dice = Dice.new()
	wild_spawns = true
	units = []
	tribes = []
	replay = {}
	_actors = {}
	animals = []
	frog = {}
	next_id = 1
	for i in Data.TRIBES_AT_START:
		if randf() < Data.TRIBE_START_CHANCE:
			_spawn_tribe()
	_spawn_animals()
	_frog_sleeps()


func _make_unit(job: String, owner: int, mover: String, pos: Vector2i, target: Vector2i) -> Dictionary:
	next_id += 1
	return {"id": next_id, "job": job, "owner": owner, "mover": mover, "pos": pos, "target": target,
		"home": pos, "stage": "out", "crew": 0, "carry": {}, "strength": 0, "age": 0, "dest": -1, "path": [],
		"survivors": [], "rad_days": 0.0, "moved": false, "move_left": float(Data.SEASON_DAYS)}


## Which entry of Data.UNITS draws this unit: vehicles show as themselves, otherwise the job.
func glyph_kind(u: Dictionary) -> String:
	if u.job == "band":
		return "band"
	if u.mover in ["car", "boat", "plane", "bomber"]:
		return u.mover
	if u.job in PARTY_JOBS:
		return "scav"   # one Scavenger Party, whatever it was sent to do
	return "caravan" if u.job == "deal" else u.job   # a warhead run is a caravan


## What Data.UNITS says of a kind of unit.
func kind_info(kind: String) -> Dictionary:
	return Data.UNITS[kind]


func units_at(c: Vector2i) -> Array:
	return units.filter(func(u): return u.pos == c)


func unit_by_id(id: int) -> Dictionary:
	for u in units:
		if u.id == id:
			return u
	return {}


## How far this unit sees. Scouts see by how they travel, everything else by its glyph.
func sight_of(u: Dictionary) -> int:
	if u.job in PARTY_JOBS:
		var sight: int = Data.SCOUT_SIGHT[u.mover]
		if Game.has_quirk("eagle_eyes"):
			sight += 1
		elif Game.has_quirk("short_sight"):
			sight -= 1
		return maxi(sight, 1)
	return int(kind_info(glyph_kind(u)).sight)


func tribe_at(c: Vector2i) -> Dictionary:
	for t in tribes:
		if t.pos == c:
			return t
	return {}


func tribe_by_id(id: int) -> Dictionary:
	for t in tribes:
		if t.id == id:
			return t
	return {}


# ---------------------------------------------------------------- your expeditions

## Vehicles away on expeditions can't defend the colony or join raids.
func vehicles_out(v: String) -> int:
	return units.filter(func(u): return u.owner == Data.PLAYER and u.mover == v).size()


func free_vehicles(v: String) -> int:
	return maxi(Game.vehicles[v] - vehicles_out(v), 0)


func trade_runs() -> int:
	return units.filter(func(u): return u.owner == Data.PLAYER and u.job in ["caravan", "boat", "deal"]).size()


func party_strength(u: Dictionary) -> int:
	return u.crew + (3 if u.mover == "car" else 1 if u.mover == "horse" else 0)


## Where a boat from the port at `c` slips into the river: a water tile beside it (or the tile
## itself, for ports saved as docks standing in the water). (-1, -1) if there's no river there.
func launch_tile(c: Vector2i) -> Vector2i:
	if not Game.in_bounds(c):
		return Vector2i(-1, -1)
	if Game.tile(c)["t"] == "water":
		return c
	for n in Game.neighbors(c):
		if Game.tile(n)["t"] == "water":
			return n
	return Vector2i(-1, -1)


## The outbound route for an expedition. Boats head for the nearest river mouth, where the river
## meets the left or right edge of the map.
func outbound_route(job: String, mover: String, from: Vector2i, target: Vector2i) -> Array:
	if job == "boat":
		var best := []
		for y in Game.h:
			for x in [0, Game.w - 1]:
				var c := Vector2i(x, y)
				if Game.tile(c)["t"] == "water":
					var path := Game.route("boat", from, c)
					if not path.is_empty() and (best.is_empty() or path.size() < best.size()):
						best = path
		return best
	return Game.route(mover, from, target)


## How much fuel an expedition takes along: scouts in a war rig or plane, recon flights, and river trader boats
## (unless you've refitted them with sails). 0 means no tank, so no gauge.
func tank_size(job: String, mover: String) -> int:
	if not mover in Data.VEHICLE_FUEL:
		return 0
	if job == "scout" or job == "plane" or job == "bomb" or (job == "boat" and not Game.has("fv3")):
		return Data.VEHICLE_FUEL[mover].tank
	return 0


## The fuel a boat from the port at `c` burns on its whole trip: down to the nearest river mouth and
## back. If that's more than the tank holds, the boat runs dry on the way home.
func boat_trip_fuel(c: Vector2i) -> float:
	var from := launch_tile(c)
	if not Game.in_bounds(from):
		return 0.0
	var path := outbound_route("boat", "boat", from, from)
	var length := 0.0
	for i in range(1, path.size()):
		length += Vector2(path[i] - path[i - 1]).length()
	return 2.0 * length * Data.VEHICLE_FUEL["boat"].burn * fuel_mult()


## The fuel a bomber from `from` burns on a strike on `target`: out and back, the way it flies. Send refuses a strike that is more than its tank holds, so it never runs dry.
func bomb_trip_fuel(from: Vector2i, target: Vector2i) -> float:
	var path := outbound_route("bomb", "bomber", from, target)
	var length := 0.0
	for i in range(1, path.size()):
		length += Vector2(path[i] - path[i - 1]).length()
	return 2.0 * length * Data.VEHICLE_FUEL["bomber"].burn * fuel_mult()


## What an expedition costs to send: the ones with a tank also fill it.
## (Scouts' food pack comes on top of this, from any of your food: see send_cost_text().)
func send_cost(job: String, mover: String) -> Dictionary:
	var cost: Dictionary = Data.EXPEDITIONS[job].cost.duplicate()
	if job == "deal":
		cost["gold"] = Game.warhead_price()   # paid now, and lost with the caravan if it never gets there
	var tank := tank_size(job, mover)
	if tank > 0:
		cost["fuel"] = cost.get("fuel", 0) + tank
	if job == "scav" and mover == "car":
		cost["fuel"] = cost.get("fuel", 0) + Data.SCAV_CAR_FUEL   # a flat trip fee, not a tank
	return cost


## send_cost() as text, with the food pack for scouts.
func send_cost_text(job: String, mover: String) -> String:
	var text := Game.cost_text(send_cost(job, mover))
	if salt_doses(job) > 0:
		text = ("%d Salt" if text == "free" else text + ", %d Salt") % salt_doses(job)
	if not job in PARTY_JOBS:
		return text
	var pack := "%d food" % Data.SCOUT_PACK
	return pack if text == "free" else "%s, %s" % [text, pack]


## "" if this expedition can leave, otherwise why not. Boats leave from `from` (your port).
## How many doses of Salt a party of this job takes with it: one for each survivor, if "Take Salt" is on and the stores have enough.
func salt_doses(job: String) -> int:
	var crew: int = crew_for(job)
	return crew if Game.salt_on and int(Game.items.get("salt", 0)) >= crew else 0


func send_status(job: String, mover: String, target: Vector2i, dest := -1, from := Vector2i(-1, -1)) -> String:
	var e: Dictionary = Data.EXPEDITIONS[job]
	if job == "boat":
		from = launch_tile(from)
		if not Game.in_bounds(from):
			return "Boats launch from a port on the riverbank"
	elif not Game.in_bounds(from):
		from = Game.home(Data.PLAYER)
	if mover in Data.VEHICLES and free_vehicles(mover) <= 0:
		return "No free %s" % Data.VEHICLES[mover].name.to_lower()
	if job == "bomb":
		if int(Game.items.get("nuke", 0)) <= 0:
			return "No nukes in the stores"
		var trip := bomb_trip_fuel(from, target)
		if trip > float(tank_size(job, mover)):
			return "Too far: the round trip burns %.1f fuel and the tank holds %d" % [trip, tank_size(job, mover)]
	if Game.pop <= crew_for(job) + 1:
		return "Need %d colonists to spare" % crew_for(job)
	if job in ["caravan", "boat", "deal"] and trade_runs() >= Game.caravan_slots():
		return "All %d caravan slots in use" % Game.caravan_slots()
	if job == "caravan" and dest == -1:
		if not Game.knows(Data.PLAYER, Data.AI):
			return "You haven't found them yet"
		if Game.ai["relations"] <= -50:
			return "They won't trade with you"
	if job == "deal":
		var camp := tribe_by_id(dest)
		if camp.is_empty() or camp.class != "trader" or not camp.get("warhead", false) or not camp.get("warhead_known", false):
			return "They have no warhead for sale"
		if not mover in ["horse", "car"]:
			return "A warhead is too heavy for a caravan on foot"
		if units.any(func(u): return u.job == "deal" and u.dest == dest):
			return "A caravan is already on its way for it"
	# One party to a ruin or an animal (the Giant Frog is for as many as you can send)
	if job in ["scav", "hunters"] and dest != FROG_ID and units.any(func(u): return u.job in ["scav", "hunters"] and u.target == target and u.stage in ["out", "site"]):
		return "A party is already heading there"
	var cost := send_cost(job, mover)
	if not Game.can_afford(cost):
		return "Need " + Game.cost_text(cost)
	if job in PARTY_JOBS and food_stock() < Data.SCOUT_PACK:
		return "Need %d food for the pack" % Data.SCOUT_PACK
	if outbound_route(job, mover, from, target).is_empty():
		return Game.no_way_text(mover, from, target)
	return ""


func send(job: String, mover: String, target: Vector2i, dest := -1, from := Vector2i(-1, -1)) -> void:
	if not Game.in_bounds(from):
		from = Game.home(Data.PLAYER)
	if send_status(job, mover, target, dest, from) != "":
		return
	if job == "boat":
		from = launch_tile(from)
	var e: Dictionary = Data.EXPEDITIONS[job]
	var crew := crew_for(job)
	Game.pay(send_cost(job, mover))
	if job == "bomb":
		Game.items["nuke"] = int(Game.items["nuke"]) - 1   # it is loaded: it leaves the stores now
	Game.note_sent(job)
	var path := outbound_route(job, mover, from, target)
	var u := _make_unit(job, Data.PLAYER, mover, from, path[-1])
	u.crew = crew
	u.survivors = Game.take_crew(crew)
	if job in PARTY_JOBS:
		u["number"] = _next_party_number()
	var doses := salt_doses(job)
	if doses > 0:
		Game.items["salt"] = int(Game.items["salt"]) - doses
		for s in u.survivors:
			s["salted"] = Data.SALT_SEASONS
	u.dest = dest
	if job == "deal":
		u["paid"] = Game.warhead_price()
	u.path = path.slice(1)
	if tank_size(job, mover) > 0:
		u.fuel = float(tank_size(job, mover))
	if job in PARTY_JOBS:
		u.food = _pack_food(Data.SCOUT_PACK)
	units.append(u)
	if job == "scout":
		Game.measure(from)
		Game.add_log("%s (%s) set out %s toward %d,%d as scouts." % [names_text(u), members_text(u), Data.MOVERS[mover].by, u.target.x, u.target.y])
	else:
		Game.add_log("%s (%s) set out %s toward %d,%d." % [names_text(u) if int(u.get("number", 0)) > 0 else e.name, members_text(u), Data.MOVERS[mover].by, u.target.x, u.target.y])
	if job in PARTY_JOBS:
		_go(u)   # it walks as far as its first day's allowance goes
	Game.changed.emit()


# ---------------------------------------------------------------- survivors

## `n` survivors who are not on the roster (a hunting party's troops, and the crews tests make): names nobody else in the colony or the
## field has. A party you send is made of roster people instead (Game.take_crew).
func _make_crew(n: int, trained := false) -> Array:
	var known: Array = Game.roster.duplicate()
	for other in units:
		known.append_array(other.survivors)
	var crew := []
	for i in n:
		var s := Roster.make(known, Game.season, trained)
		s["sid"] = 0   # no number until they join the roster (Game.welcome_home)
		s["state"] = "troop" if trained else "away"
		known.append(s)
		crew.append(s)
	return crew


## Every survivor still in the party dies, and the party has no crew.
func _wipe(u: Dictionary, cause: String) -> void:
	for s in u.survivors:
		Game.fall(s, cause)
	u.crew = 0
	u.survivors = []


## "Mara", "Mara and Dex", "Mara, Dex and Odo"; "the crew" if nobody is named.
func names_text(u: Dictionary) -> String:
	return party_label(u) if int(u.get("number", 0)) > 0 else members_text(u)


## "Mara", "Mara and Dex", "Mara, Dex and Odo"; "the crew" if nobody is named.
func members_text(u: Dictionary) -> String:
	var names: Array = u.survivors.map(func(s): return s.name)
	return list_text(names) if not names.is_empty() else "the crew"


## "Scavenger Party 2": your parties are numbered 1, 2, 3... for as long as they are out, and the number goes to the next party when
## one comes home or is lost (the party bar and its keys use the same numbers).
func party_label(u: Dictionary) -> String:
	return "%s %d" % [Data.EXPEDITIONS[u.job].name, int(u.number)]


## What to call a unit of yours in a panel: "Scavenger Party 2", or its kind of expedition ("Trade caravan") when it has no number.
func unit_title(u: Dictionary) -> String:
	return party_label(u) if int(u.get("number", 0)) > 0 else Data.EXPEDITIONS[u.job].name


const PARTY_JOBS := ["scav", "scout", "hunters"]   # the three ways to use a Scavenger Party


## The lowest number no party of yours is using.
func _next_party_number() -> int:
	var used := {}
	for other in units:
		if other.owner == Data.PLAYER and int(other.get("number", 0)) > 0:
			used[int(other.number)] = true
	var n := 1
	while used.has(n):
		n += 1
	return n


## How many survivors an expedition takes: a Scavenger Party's 3, or 4 for a leader with Big party on a scavenging or hunting run
## (a scouting party stays light), and what Data.EXPEDITIONS says for everything else.
func crew_for(job: String) -> int:
	var crew: int = Data.EXPEDITIONS[job].crew
	if job in ["scav", "hunters"] and Game.has_quirk("big_party"):
		crew += 1
	return crew


## "Mara", "Mara and Dex", "Mara, Dex and Odo".
func list_text(names: Array) -> String:
	if names.size() <= 1:
		return "".join(names)
	return ", ".join(names.slice(0, -1)) + " and " + names[-1]


func hunger_text(s: Dictionary) -> String:
	if s.hunger >= Data.STARVING_AT:
		return "STARVING"
	return "hungry" if s.hunger > 0 else "fed"


## One line about a survivor for the info panels.
func survivor_line(s: Dictionary) -> String:
	var status := hunger_text(s)
	if sick_level(s) > 0:
		status += ", " + sick_text(s)
	if s.get("hurt", false):
		status += ", injured"
	if s.get("leg", false):
		status += ", broken leg"
	if s.get("injury", "none") != "none":
		status += ", %s injury" % s.injury
	if int(s.get("salted", 0)) > 0:
		status += ", salted (%d seasons)" % int(s.salted)
	if s.hp < Data.SURVIVOR_HP:
		status += ", %d hp" % ceili(s.hp)
	var traits := D20.trait_names(s)
	return "%s, %d, %s(%s)" % [s.name, s.age, traits + " " if traits != "" else "", status]


## Takes one survivor out of the party (a random one, or `who`) and returns their name.
func _casualty(u: Dictionary, who := {}, cause := "lost in the wastes") -> String:
	u.crew = maxi(u.crew - 1, 0)
	Game.note("survivors_lost")
	if u.survivors.is_empty():
		return ""
	var s: Dictionary = who if not who.is_empty() else u.survivors.pick_random()
	u.survivors.erase(s)
	Game.fall(s, cause)
	return s.name


## What the party is doing, in a few words.
func stage_text(u: Dictionary) -> String:
	match u.stage:
		"out":
			return "flying to the target" if u.job == "bomb" else "heading out"
		"station":
			return "keeping watch"
		"site":
			return {"building": "attacking a building", "camp": "attacking a camp", "hunt": "hunting"}.get(u.get("visit", {}).get("ruin", ""), "at the ruins")
	return "heading home"


# ---------------------------------------------------------------- scouting parties

func scouts_out() -> int:
	return units.filter(func(u): return u.owner == Data.PLAYER and u.job in PARTY_JOBS).size()


## Orders for a party already in the field: "" if it can go there, otherwise why not.
func order_status(u: Dictionary, target: Vector2i) -> String:
	if u.pos == target and u.stage == "station":
		return "Already here"
	if Game.route(u.mover, u.pos, target).is_empty():
		return Game.no_way_text(u.mover, u.pos, target)
	return ""


func order_scouts(id: int, target: Vector2i) -> void:
	var u := unit_by_id(id)
	if u.is_empty() or order_status(u, target) != "":
		return
	u.target = target
	u.dest = -1   # new orders: it is no longer after the animal it was sent for
	u.stage = "out"
	u.path = Game.route(u.mover, u.pos, target).slice(1)
	if u.path.is_empty():
		u.stage = "station"
	Game.add_log("%s heads for %d,%d." % [names_text(u), target.x, target.y])
	_go(u)
	Game.changed.emit()


func recall_scouts(id: int) -> void:
	var u := unit_by_id(id)
	if u.is_empty() or u.stage in ["back", "site"]:   # an attack in progress is finished first
		return
	u.stage = "back"
	u.path = Game.route(u.mover, u.pos, u.home).slice(1)
	if u.path.is_empty():
		_come_home(u)
		units.erase(u)
	else:
		Game.add_log("%s is heading back to camp." % names_text(u))
		_go(u)
	Game.changed.emit()


## Each survivor eats from the party's pack. Going hungry builds up, and starving ones eventually die.
func _feed(u: Dictionary) -> void:
	var before := food_total(u)
	u.survivors.sort_custom(func(a, b): return a.hunger > b.hunger)
	for s in u.survivors.duplicate():
		if _eat_from_pack(u, Data.SCOUT_RATION):
			s.hunger = 0
			continue
		s.hunger += 1
		if s.hunger >= Data.STARVE_DEATH:
			_casualty(u, s, "starved in the field")
			Game.add_log("%s starved to death at %d,%d." % [s.name, u.pos.x, u.pos.y])
		elif s.hunger >= Data.STARVING_AT:
			Game.add_log("%s is starving at %d,%d! Bring the party home before it's too late." % [s.name, u.pos.x, u.pos.y])
		else:
			Game.add_log("%s has gone hungry: the pack is empty." % s.name)
	if food_total(u) == 0 and before > 0:
		Game.add_log("%s has eaten the last of its food at %d,%d." % [names_text(u), u.pos.x, u.pos.y])
	elif food_total(u) > 0 and food_days(u) <= 2.0 * Data.SEASON_DAYS:
		Game.add_log("%s is low on food (%d left)." % [names_text(u), food_total(u)])


# ---------------------------------------------------------------- food packs

## Everything you could put in a pack.
func food_stock() -> int:
	var n := 0
	for k in Data.FOOD_KINDS:
		n += Game.res[k]
	return n


## Takes `n` food out of your stores (grain first, then veg, then meat) and returns it as a pack.
func _pack_food(n: int) -> Dictionary:
	var pack := {}
	for k in Data.FOOD_KINDS:
		var take := mini(Game.res[k], n)
		if take > 0:
			Game.res[k] -= take
			pack[k] = take
			n -= take
	return pack


## How much food is in the party's pack.
func food_total(u: Dictionary) -> int:
	var n := 0
	var pack: Dictionary = u.get("food", {})
	for k in pack:
		n += pack[k]
	return n


## "5 grain, 3 veg", or "none".
func food_text(u: Dictionary) -> String:
	var parts := []
	var pack: Dictionary = u.get("food", {})
	for k in Data.FOOD_KINDS:
		if pack.get(k, 0) > 0:
			parts.append("%d %s" % [pack[k], k])
	return ", ".join(parts) if not parts.is_empty() else "none"


## Eats `n` food out of the pack (grain first). False, and nothing eaten, if there isn't that much.
func _eat_from_pack(u: Dictionary, n: int) -> bool:
	if food_total(u) < n:
		return false
	var pack: Dictionary = u.food
	for k in Data.FOOD_KINDS:
		var take := mini(pack.get(k, 0), n)
		if take > 0:
			pack[k] -= take
			n -= take
	return true


## How many days the pack feeds the survivors on board (INF with nobody to feed).
func food_days(u: Dictionary) -> float:
	var eaters: int = u.survivors.size() * Data.SCOUT_RATION
	return INF if eaters <= 0 else float(food_total(u)) * Data.SEASON_DAYS / eaters


## The day each cell of `path` is reached (index 0, where the party stands, is day 0), counting
## from the start of the next season. This mirrors _advance(): a step that doesn't fit in what is
## left of the season waits for the next one. `slowdown` is load_slowdown() for an overloaded party.
func arrival_days(mover: String, path: Array, slowdown := 1.0) -> Array:
	var days := [0.0]
	var day := 0.0
	var left: float = Data.SEASON_DAYS
	var days_per_tile: float = Data.MOVERS[mover].days * slowdown * Game.travel_mult()
	for i in range(1, path.size()):
		var cost: float = Vector2(path[i] - path[i - 1]).length() * Game.move_mult(mover, path[i]) * days_per_tile
		if cost > left:
			day += left
			left = Data.SEASON_DAYS
		day += cost
		left -= cost
		days.append(day)
	return days


## For each day in `days` (see arrival_days), how much of the party's food would be eaten by then:
## 0 at the start, 1 where the pack runs out, and more beyond. (The map colors the route by this.)
func food_ratios(u: Dictionary, days: Array) -> Array:
	var food := food_days(u)
	var out := []
	for d in days:
		if is_inf(food):
			out.append(0.0)
		elif food <= 0.0:
			out.append(0.0 if d <= 0.0 else INF)
		else:
			out.append(d / food)
	return out


# ---------------------------------------------------------------- weight

## What `goods` ({"metal": 5, "gold": 3}) weigh.
func goods_weight(goods: Dictionary) -> float:
	var w := 0.0
	for k in goods:
		w += goods[k] * Data.WEIGHT.get(k, Data.ITEM_WEIGHT.get(k, 1.0))
	return w


## What the party is carrying: its food pack and the goods it's hauling home.
func load_weight(u: Dictionary) -> float:
	return goods_weight(u.get("carry", {})) + goods_weight(u.get("food", {}))


## How much the party can carry before it slows down: so much per survivor, plus what its way of
## travelling adds (a horse, a war rig, a boat or a plane).
func load_capacity(u: Dictionary) -> float:
	var mult := 1.0
	if Game.has_quirk("pack_rat"):
		mult = 1.25
	elif Game.has_quirk("poor_packers"):
		mult = 0.85
	return (u.crew * Data.CARRY_PER_PERSON + Data.CARRY_BY_MOVER.get(u.mover, 0.0)) * mult


## How much fuel your parties burn compared with the usual: a Mechanic's burn 20% less.
func fuel_mult() -> float:
	return 0.8 if Game.has_quirk("mechanic") else 1.0


## 1.0 up to the limit. Past it, how many times longer than usual every step takes: twice as long
## when carrying double, and never worse than OVERLOAD_MAX.
func load_slowdown(u: Dictionary) -> float:
	var weight := load_weight(u)
	if weight <= 0.0:
		return 1.0
	var capacity := load_capacity(u)
	if capacity <= 0.0:
		return Data.OVERLOAD_MAX   # nobody left to carry it
	var ratio := weight / capacity
	if ratio <= 1.0:
		return 1.0
	return minf(1.0 + Data.OVERLOAD_SLOWDOWN * (ratio - 1.0), Data.OVERLOAD_MAX)


## How many of the party's people have a broken leg (or, on horseback, a lame horse).
func broken_legs(u: Dictionary) -> int:
	var n := 0
	for s in u.survivors:
		if s.get("leg", false):
			n += 1
	return n


## 1.0 with no broken leg. With one, every step takes Data.LEG.slow times as long; each further one adds Data.LEG.more, never past Data.LEG.max.
func leg_slowdown(u: Dictionary) -> float:
	var n := broken_legs(u)
	if n <= 0:
		return 1.0
	return minf(float(Data.LEG.slow) + float(Data.LEG.more) * (n - 1), float(Data.LEG.max))


## load_slowdown() and leg_slowdown() together: how many times longer than usual every step of this party takes.
func party_slowdown(u: Dictionary) -> float:
	return load_slowdown(u) * leg_slowdown(u) * crate_slowdown(u)


## A warhead bought from the traders comes crated: Data.TRADERS.crate_slowdown times as long on top of the weight (1.0 for anything else).
func crate_slowdown(u: Dictionary) -> float:
	return float(Data.TRADERS.crate_slowdown) if u.get("crated", false) and int(u.get("carry", {}).get("nuke", 0)) > 0 else 1.0


## A foot or horseback party that has just entered tile `c` and it is rock or a steep incline: maybe someone breaks a leg (Data.LEG). One
## survivor at random who has not already, a Clumsy one more likely; a Light-Footed party halves the chance. True if a leg broke.
func _climb_check(u: Dictionary, c: Vector2i) -> bool:
	if not u.mover in ["foot", "horse"] or u.survivors.is_empty():
		return false
	var steep: bool = Game.slopes[Game.idx(c)] == "steep"
	var chance := 0.0
	if steep:
		chance = float(Data.LEG.steep)
	elif Game.tile(c)["t"] == "rock":
		chance = float(Data.LEG.rock)
	if chance <= 0.0:
		return false
	if u.survivors.any(func(s): return "light_footed" in s.traits):
		chance *= float(Data.LEG.light_footed)
	if randf() >= chance:
		return false
	var pool := []   # a survivor goes in once, and again for each extra turn of being Clumsy
	for s in u.survivors:
		if not s.get("leg", false):
			pool.append(s)
			if "clumsy" in s.traits:
				pool.append(s)
	if pool.is_empty():
		return false
	var victim: Dictionary = pool.pick_random()
	victim["leg"] = true
	_note_event("snap", c, _walk_day(u))
	var where := "on the steep slope" if steep else "on the rocks"
	var what := "%s broke a leg" % victim.name if u.mover == "foot" else "%s's horse went lame" % victim.name
	Game.add_log("%s %s at %d,%d. The party slows down until it gets home." % [what, where, c.x, c.y])
	return true


## A party of yours that has just entered tile `c`, if it is on the old highway: every Data.HIGHWAY.ambush_every tiles of it a party walks, it rolls a
## d20, and a natural 1 is an ambush by a raider band (strength Data.HIGHWAY.band), fought like any ambush on the road. True if it happened.
func _highway_check(u: Dictionary, c: Vector2i) -> bool:
	if u.owner != Data.PLAYER or not u.mover in ["foot", "horse", "car"]:
		return false
	var b: String = Game.tile(c)["b"]
	if b == "" or not Data.BUILDINGS[b].get("highway", false):
		return false
	u["hwy"] = int(u.get("hwy", 0)) + 1
	if int(u.hwy) % int(Data.HIGHWAY.ambush_every) != 0:
		return false
	if randi_range(1, 20) != 1:
		return false
	var band := _make_unit("band", Data.NONE, "foot", c, c)
	band["strength"] = randi_range(int(Data.HIGHWAY.band[0]), int(Data.HIGHWAY.band[1]))
	Game.add_log("Raiders lay in wait on the old highway at %d,%d!" % [c.x, c.y])
	_fight(band, u)
	return true


## `goods` trimmed to what the party can still pick up: nobody carries more than LOAD_CEILING
## times their capacity, so the rest stays behind (in the same mix as what was on offer).
func fit_load(u: Dictionary, goods: Dictionary) -> Dictionary:
	var room := maxf(Data.LOAD_CEILING * load_capacity(u) - load_weight(u), 0.0)
	var weight := goods_weight(goods)
	if weight <= room:
		return goods
	var kept := {}
	var left := {}
	var rest := goods
	var nukes := int(goods.get("nuke", 0))
	if nukes > 0:   # nukes are loaded first, and the rest is trimmed to the room that is left (or a big package of fuel would crowd out the warhead)
		var lift := clampi(int(room / float(Data.ITEM_WEIGHT.nuke)), 0, nukes)
		if lift > 0:
			kept["nuke"] = lift
		if nukes > lift:
			left["nuke"] = nukes - lift
		room = maxf(room - lift * float(Data.ITEM_WEIGHT.nuke), 0.0)
		rest = goods.duplicate()
		rest.erase("nuke")
		weight = goods_weight(rest)
		if weight <= room:
			kept.merge(rest)
			if not left.is_empty():
				Game.add_log("%s can't carry it all: %s stays behind." % [names_text(u), Game.cost_text(left)])
			return kept
	var share := room / weight if weight > 0.0 else 0.0
	for k in rest:
		var n := int(rest[k] * share)
		if n > 0:
			kept[k] = n
		if rest[k] - n > 0:
			left[k] = rest[k] - n
	Game.add_log("%s can't carry it all: %s stays behind." % [names_text(u), Game.cost_text(left)])
	return kept


## Loads the goods a party has just picked up (what fits, see fit_load) and sets off with them.
func _haul(u: Dictionary, goods: Dictionary) -> void:
	u.carry = {}
	u.carry = fit_load(u, goods)


## 0 healthy, 1 ill, 2 radiation sick, 3 critical: how far gone a survivor's dose is.
func sick_level(s: Dictionary) -> int:
	if s.dose >= Data.DOSE_CRITICAL:
		return 3
	if s.dose >= Data.DOSE_SICK:
		return 2
	return 1 if s.dose >= Data.DOSE_ILL else 0


func sick_text(s: Dictionary) -> String:
	return ["", "ill", "radiation sick", "CRITICAL"][sick_level(s)]


## Radiation works like poison. Each season a survivor's dose is a bit less than last season's
## plus whatever the party soaked up on the tiles it walked or stood on (above the harmless
## background, and after the shielding of how it travels). Every point of dose costs some hp, so it
## never kills outright, but staying in the hot zones is fatal, and the poison lingers once you leave.
func _expose(u: Dictionary) -> void:
	if u.survivors.is_empty():
		return
	var days: float = u.get("rad_days", 0.0)
	if not u.get("moved", false):
		days = Game.radiation(u.pos) * Data.SEASON_DAYS   # stood still all season
	u["rad_days"] = 0.0
	u["moved"] = false
	var heat: float = days / Data.SEASON_DAYS * Data.MOVERS[u.mover].shield
	var exposure := maxf(heat - Data.RAD_SAFE, 0.0)
	for s in u.survivors.duplicate():
		var before := sick_level(s)
		var salted := int(s.get("salted", 0)) > 0
		s.dose = s.dose * Data.DOSE_DECAY + exposure * Game.dose_rate() * (Data.SALT_RESIST if salted else 1.0)
		if salted:
			s["salted"] = int(s.salted) - 1
		if s.dose < 0.5:
			s.dose = 0.0
		s.hp -= s.dose * Data.POISON_DAMAGE
		if s.hp <= 0.0:
			_casualty(u, s, "died of radiation sickness")
			Game.add_log("%s died of radiation sickness at %d,%d." % [s.name, u.pos.x, u.pos.y])
			continue
		if s.dose < Data.DOSE_ILL:
			s.hp = minf(s.hp + Data.RAD_RECOVERY, Data.SURVIVOR_HP)
			if s.hp >= Data.SURVIVOR_HP:
				s.hurt = false   # healed up
		if sick_level(s) > before:
			Game.add_log("%s is %s from the radiation at %d,%d (%d hp)." % [s.name, sick_text(s).to_lower(), u.pos.x, u.pos.y, ceili(s.hp)])
	if u.crew <= 0:
		_lost(u)


## True when the vehicle's tank is nearly dry: what the gauge's warning light and the red text go by.
func fuel_low(u: Dictionary) -> bool:
	if not u.has("fuel"):
		return false
	var tank: Dictionary = Data.VEHICLE_FUEL[u.mover]
	return u.fuel < maxf(tank.idle * fuel_mult() * 2.0, tank.tank * Data.FUEL_LOW)


## A party waiting in place: a war rig or plane burns idle fuel.
func _idle(u: Dictionary) -> void:
	if not u.has("fuel"):
		return
	var idle: float = Data.VEHICLE_FUEL[u.mover].idle * fuel_mult()
	if u.fuel < idle:
		_strand(u)
		return
	u.fuel -= idle
	if u.fuel < idle * 2:
		Game.add_log("%s's %s is low on fuel (%.1f left)." % [names_text(u), Data.MOVERS[u.mover].name.to_lower(), u.fuel])


## The tank is dry. The vehicle is lost and the people aboard carry on as a party on foot: a war rig
## or boat is abandoned (a boat's crew walk home, the trade run is off), but a plane crashes.
func _strand(u: Dictionary) -> void:
	var v: String = u.mover
	var where := "%d,%d" % [u.pos.x, u.pos.y]
	_note_event("smoke", u.pos, _walk_day(u))
	Game.vehicles[v] = maxi(Game.vehicles[v] - 1, 0)
	u.mover = "foot"
	u.erase("fuel")
	match v:
		"plane", "bomber":
			_crash(u, where)
		"boat":
			Game.add_log("OUT OF FUEL: the boat ran dry at %s and was abandoned. %s wades ashore and heads home on foot." % [where, names_text(u)])
		_:
			Game.add_log("OUT OF FUEL: the war rig ran dry at %s and was abandoned. %s continues on foot." % [where, names_text(u)])
	if u.crew <= 0:
		_lost(u)   # nobody walked away from the wreck
		return
	if not u.carry.is_empty():
		_haul(u, u.carry.duplicate())   # on foot they can carry less: what doesn't fit is left with the wreck
	u.path = []
	var landing := Game.nearest_walkable(u.home, 3)   # a boat's home is the river tile by its port: on foot they walk to the bank beside it
	if landing.x < 0:
		landing = u.home
	if Game.move_mult("foot", u.pos) <= 0.0:   # they came down in the river: they wade ashore first, on a bank with a way home
		var shore := Game.nearest_walkable(u.pos, 8, landing if not u.job in PARTY_JOBS else Vector2i(-1, -1))
		if shore.x < 0:
			shore = Game.nearest_walkable(u.pos)
		if shore.x >= 0:
			u.pos = shore
	if not u.job in PARTY_JOBS:
		u.stage = "back"   # a trade run is off: they walk home
	if u.stage == "back":
		u.path = Game.route("foot", u.pos, landing).slice(1)
	if u.path.is_empty():
		if u.job in PARTY_JOBS:
			u.stage = "station"
		else:
			_come_home(u)


## A plane with an empty tank comes down hard. Each person aboard lives through it with
## crash_survival; the ones who do are injured (they lose hp, and show a bandage) and go on foot.
func _crash(u: Dictionary, where: String) -> void:
	var died := []
	var walked := []
	for s in u.survivors.duplicate():
		if randf() < crash_survival:
			s.hp = maxf(s.hp - randf_range(Data.CRASH_INJURY.x, Data.CRASH_INJURY.y), 1.0)
			s.hurt = true
			walked.append("%s (%d hp)" % [s.name, ceili(s.hp)])
		else:
			died.append(_casualty(u, s, "killed in a crash"))
	var text := "OUT OF FUEL: the plane crashed at %s." % where
	if not died.is_empty():
		text += " %s died in the wreck." % list_text(died)
	if walked.is_empty():
		text += " Nobody walked away."
	else:
		text += " %s survived, injured, and continue on foot." % list_text(walked)
	Game.add_log(text)


## The end of a season for one of your parties: it eats, its engine idles if it waits (a party in the middle of a visit does not),
## the days it did not walk were spent where it stands, and it has all its days again. It does not walk: it goes where you send it.
func _scout_turn(u: Dictionary) -> void:
	_feed(u)
	if u.crew <= 0:
		_lost(u)
		return
	if u.stage != "site":
		_idle(u)
	if u.get("moved", false):
		u.rad_days += Game.radiation(u.pos) * float(u.move_left)
	u.move_left = float(Data.SEASON_DAYS)


## Walks a party as far as its days allow and does what arriving means (a visit, keeping watch, coming home). True if it got there.
func _go(u: Dictionary) -> bool:
	if u.path.is_empty():
		return false
	var arrived := _advance(u)
	if not u.get("gone", false):
		if arrived:
			_arrive(u)
		elif u.crew <= 0:
			_lost(u)
	if u.get("gone", false):
		units.erase(u)
	Game.update_fog()
	Game.changed.emit()
	return arrived


## "" if the party can walk on now, otherwise why not.
func continue_status(u: Dictionary) -> String:
	if not u.get("job", "") in PARTY_JOBS or u.owner != Data.PLAYER:
		return "Not one of your parties"
	if u.stage == "site":
		return "In the middle of a search"
	if u.path.is_empty():
		return "No orders to carry on with"
	if float(u.move_left) <= 0.0:
		return "No days left this turn"
	return ""


## Carries on along the route a party was given, with the days it has left this turn.
func continue_orders(id: int) -> void:
	var u := unit_by_id(id)
	if u.is_empty() or continue_status(u) != "":
		return
	_go(u)


## "17 days left this turn", for the party panel.
func days_left_text(u: Dictionary) -> String:
	var days := floori(float(u.get("move_left", Data.SEASON_DAYS)))
	return "%d day%s left this turn" % [days, "" if days == 1 else "s"]


# ---------------------------------------------------------------- the season

func season_turn() -> void:
	_spawn_wild()
	_record_start()
	for u in units.duplicate():
		if u.get("gone", false):
			continue   # a blast earlier in this very season took it
		u.age += 1
		if u.job == "band":
			_band_turn(u)
		elif u.job in PARTY_JOBS:
			_scout_turn(u)
		elif u.stage == "site":
			pass   # waiting at the ruins for the player's roll; _expose below counts the season spent standing there
		elif _advance(u):
			_arrive(u)
		if u.owner == Data.PLAYER and not u.get("gone", false):
			_expose(u)
	_animals_turn()
	_frog_turn()
	_ambushes()
	_bear_attacks()
	_recording = false
	SeasonReplay.settle(replay)
	units = units.filter(func(u): return not u.get("gone", false))


# ---------------------------------------------------------------- the season as the map plays it back

## Starts the notes for this season: every unit on the map, at its starting tile on day 0.
func _record_start() -> void:
	replay = {"actors": [], "events": [], "reveals": [], "sight_before": PackedByteArray()}
	_actors = {}
	for u in units:
		var actor := {"id": u.id, "kind": glyph_kind(u), "owner": u.owner, "mover": u.mover,
			"parked": u.job in PARTY_JOBS and u.stage == "station", "trail": [[u.pos, 0.0]], "gone_day": SeasonReplay.STILL}
		replay.actors.append(actor)
		_actors[u.id] = actor
	if frog.get("state", "") == "loose":
		var big := {"id": FROG_ID, "kind": "frog", "owner": Data.NONE, "mover": "foot", "parked": false,
			"trail": [[frog.pos, 0.0]], "gone_day": SeasonReplay.STILL}
		replay.actors.append(big)
		_actors[FROG_ID] = big
	for a in animals:
		var wild := {"id": a.id, "kind": a.kind, "owner": Data.NONE, "mover": "foot", "parked": false, "wild": true,
			"trail": [[a.pos, 0.0]], "gone_day": SeasonReplay.STILL}
		replay.actors.append(wild)
		_actors[a.id] = wild
	_recording = true


## The day (0 to Data.SEASON_DAYS) this unit last moved on: where its walk has got to.
func _walk_day(u: Dictionary) -> float:
	var actor: Dictionary = _actors.get(u.id, {})
	return 0.0 if actor.is_empty() else actor.trail.back()[1]


## u has just reached the tile it stands on, `day` days into the season.
func _note_step(u: Dictionary, day: float) -> void:
	_note_at(u.id, u.pos, day)


## Whatever the actor `id` is (a unit, an animal, the frog) has reached `cell`, `day` days into the season.
func _note_at(id: int, cell: Vector2i, day: float) -> void:
	if _recording and _actors.has(id):
		_actors[id].trail.append([cell, day])


## u leaves the map. `at_end`: not until the walking is done (a fight at the end of the season), otherwise when it stopped.
func _mark_gone(u: Dictionary, at_end := false) -> void:
	u["gone"] = true
	if _recording and _actors.has(u.id):
		_actors[u.id].gone_day = SeasonReplay.AT_END if at_end else _walk_day(u)


func is_recording() -> bool:
	return _recording


## A nuke went off at `cell`, `day` days into the season's walk: the replay plays the explosion then.
func note_blast(cell: Vector2i, day: float) -> void:
	_note_event("blast", cell, day)


## A blast takes every party on `cells`: yours (their crew are lost for good, and a vehicle with them), raider bands, and every wild animal and camp. `spare` holds the
## ids of units that live (the party whose crater roll set it off, which its visit finishes off itself, and the bomber that dropped it). `day` is when in the walk it
## happened, for the replay (-1: now). The Giant Frog is not hurt. Returns {"parties", "yours", "people", "animals", "camps"}.
func blast_kills(cells: Array, spare: Array, day := -1.0) -> Dictionary:
	var out := {"parties": 0, "yours": 0, "people": 0, "animals": 0, "camps": 0}
	for u in units.duplicate():
		if u.get("gone", false) or u.id in spare or not u.pos in cells:
			continue
		out.parties += 1
		if u.owner == Data.PLAYER:
			out.yours += 1
			out.people += u.crew
			Game.note("survivors_lost", u.crew)
			_wipe(u, "wiped out at the ruins")
			u.erase("visit")
			_lost(u)
		else:
			_mark_gone(u)
		if day >= 0.0 and _recording and _actors.has(u.id):
			_actors[u.id].gone_day = day
		if not _recording:
			units.erase(u)   # not mid-season: it leaves the map now
	for a in animals.duplicate():
		if a.pos in cells:
			animals.erase(a)
			out.animals += 1
			if day >= 0.0 and _recording and _actors.has(a.id):
				_actors[a.id].gone_day = day
	for t in tribes.duplicate():
		if t.pos in cells:
			tribes.erase(t)
			out.camps += 1
	return out


## Something to flash or puff where it happened: "clash", "ruin", "home" or "smoke". day: AT_END for when the walking is done.
func _note_event(kind: String, cell: Vector2i, day: float) -> void:
	if _recording:
		replay.events.append({"kind": kind, "cell": cell, "day": day})


## Walk the path with one season's worth of travel days. True once the path is done.
func _advance(u: Dictionary) -> bool:
	var immediate: bool = u.job in PARTY_JOBS   # your parties walk when you order it, with the days they have left this turn
	var budget: float = float(u.move_left) if immediate else float(Data.SEASON_DAYS)
	var days_per_tile: float = Data.MOVERS[u.mover].days * party_slowdown(u)   # a heavy load or a broken leg takes longer
	if u.owner == Data.PLAYER:
		days_per_tile *= Game.travel_mult()
	while not u.path.is_empty():
		var next: Vector2i = u.path[0]
		var cost: float = Vector2(next - u.pos).length() * Game.move_mult(u.mover, next) * days_per_tile
		if cost > budget:
			break
		if u.has("fuel"):
			var burn: float = Data.VEHICLE_FUEL[u.mover].burn * fuel_mult() * Vector2(next - u.pos).length()
			if u.fuel < burn:
				_strand(u)
				return false
			u.fuel -= burn
		budget -= cost
		u.pos = next
		u.path.pop_front()
		_note_step(u, Data.SEASON_DAYS - budget)
		if _climb_check(u, next):   # a broken leg: every step from here takes longer
			days_per_tile = Data.MOVERS[u.mover].days * party_slowdown(u) * (Game.travel_mult() if u.owner == Data.PLAYER else 1.0)
		if _highway_check(u, next) and (u.get("gone", false) or u.crew <= 0):
			return false   # the ambush wiped the party out
		if u.owner == Data.PLAYER:
			var fresh: Array = Game.reveal(Data.PLAYER, u.pos, sight_of(u))
			if _recording:
				for c in fresh:
					replay.reveals.append([c, Data.SEASON_DAYS - budget])
			u.rad_days += Game.radiation(u.pos) * cost
			if u.job == "scout":
				Game.measure(u.pos)   # the party's counter clicks away: that reading is kept for good
	if immediate:
		u.move_left = budget   # what is left is spent where it stands, when the season ends (_scout_turn)
	if u.owner == Data.PLAYER:
		if not immediate:
			u.rad_days += Game.radiation(u.pos) * budget   # the rest of the season is spent here
		u.moved = true
	return u.path.is_empty()


func _arrive(u: Dictionary) -> void:
	if u.stage == "back":
		_come_home(u)
		return
	if u.job in PARTY_JOBS:
		if int(u.dest) > 0 or (u.job != "scout" and scavenge_place(u.target) != ""):
			_begin_visit(u)   # sent after an animal, or to the ruins
			return
		u.stage = "station"
		Game.add_log("%s reached %d,%d and is keeping watch." % [names_text(u), u.pos.x, u.pos.y])
		return
	match u.job:
		"caravan":
			_trade(u)
		"deal":
			_deal(u)
		"boat":
			var goods := {"gold": Game.trade_gold(10 + Game.vehicle_trade("boat") + (Data.CONTRACT_GOLD if Game.has("c2") else 0))}
			_haul(u, goods)
			Game.note("trade_runs")
			Game.add_log("Your boat traded with river folk downstream: %s. Heading home." % Game.cost_text(u.carry))
		"plane":
			Game.add_log("Recon plane reached %d,%d and turned for home." % [u.pos.x, u.pos.y])
		"bomb":
			_drop_nuke(u)
	if u.crew <= 0:
		_lost(u)
		return
	u.stage = "back"
	u.path = Game.route(u.mover, u.pos, u.home).slice(1)
	if u.path.is_empty():
		_come_home(u)


## The bomber is over its tile: the nuke goes down and goes off (on the day of the season's walk it got there), and the bomber turns for home.
func _drop_nuke(u: Dictionary) -> void:
	Game.add_log("Your bomber released its nuke over %d,%d." % [u.pos.x, u.pos.y])
	Game.note("nukes_dropped")
	Game.detonate(u.pos, "bomber", [u.id], _walk_day(u))


func _come_home(u: Dictionary) -> void:
	if not u.carry.is_empty():
		_note_event("home", u.pos, _walk_day(u))
	for k in u.carry:
		if k in Data.ITEMS:
			Game.items[k] = int(Game.items.get(k, 0)) + int(u.carry[k])
		else:
			Game.res[k] += u.carry[k]
	var legs := broken_legs(u)   # counted before they are home and healed
	Game.welcome_home(u.survivors, u.crew)
	var name: String = Data.EXPEDITIONS[u.job].name
	if u.carry.is_empty():
		Game.add_log("%s came home." % name)
	else:
		Game.add_log("%s came home with %s." % [name, Game.cost_text(u.carry)])
	if legs > 0:
		Game.add_log("%s healed at home." % ("The broken leg" if legs == 1 else "%d broken legs" % legs))
	if food_total(u) > 0:   # whatever they didn't eat goes back in the stores
		for k in u.food:
			Game.res[k] += u.food[k]
		Game.add_log("Their unspent food (%s) went back into the stores." % food_text(u))
	if u.get("fuel", 0.0) >= 1.0:   # so does whole units of fuel left in the tank
		var left := int(u.fuel)
		Game.res["fuel"] += left
		Game.add_log("%d fuel left in the tank went back into the stores." % left)
		u.erase("fuel")
	_mark_gone(u)


## `at_end`: it was a fight at the end of the season, so the map shows it until the walking is done.
func _lost(u: Dictionary, at_end := false) -> void:
	if u.mover in Data.VEHICLES:
		Game.vehicles[u.mover] = maxi(Game.vehicles[u.mover] - 1, 0)
	Game.add_log("%s was wiped out in the wastes." % (party_label(u) if int(u.get("number", 0)) > 0 else "Your " + Data.EXPEDITIONS[u.job].name.to_lower()))
	_mark_gone(u, at_end)


# ---------------------------------------------------------------- a visit to the ruins

## A scavenger party that has walked to its ruin stops there. What the ruin hides (a trap, a rogue raider, nothing)
## came with the map, and the d20 rolls that follow, one button press each, are in d20_visit.gd. Arriving measures
## the ruin's radiation, so the player sees what it does to the roll before making it.
func _begin_visit(u: Dictionary) -> void:
	if int(u.dest) > 0:   # sent after an animal
		_arrive_hunt(u)
		return
	var poi := Game.poi_kind(u.target)
	var anchor: Vector2i = Game.poi_anchor(u.target) if poi != "" else u.target
	var t: Dictionary = Game.tile(anchor)
	var where := "%d,%d" % [u.target.x, u.target.y]
	var is_crater: bool = poi == "" and t["t"] == "crater"
	if t["r"] == "picked":
		Game.add_log("Scavengers found the %s at %s already picked clean." % ["site" if poi != "" else ("crater" if is_crater else "ruins"), where])
		_turn_back(u)
		return
	if poi == "missile_silo" and Game.silo_stock(anchor) > 0:
		_collect_warheads(u, anchor)
		return
	Game.measure(u.pos)
	var ruin: String = "poi" if poi != "" else ("crater" if is_crater else {"trap": "trapped", "rogue": "rogue", "rogue_seen": "rogue"}.get(t["r"], "safe"))
	var scale: float = D20.loot_scale * (Data.SCAV_CAR_MULT if u.mover == "car" else 1.0)   # a war rig hauls more
	if poi != "":
		scale *= Data.POI_LOOT_MULT
	u["visit"] = D20Visit.begin(ruin, visit_ctx(u), scale, dice, u.survivors, poi)
	_note_event("ruin", u.pos, _walk_day(u))
	u.stage = "site"
	u.path = []
	Game.add_log("%s reached the %s at %s." % [names_text(u), Data.BUILDINGS["poi_" + poi].name.to_lower() if poi != "" else ("crater" if is_crater else "ruins"), where])
	_sync_visit(u)


## A party reaching a silo that still holds the warheads an earlier party could not carry: there is nothing to roll, they load what they can lift.
func _collect_warheads(u: Dictionary, anchor: Vector2i) -> void:
	var stock := Game.silo_stock(anchor)
	Game.measure(u.pos)
	_haul(u, {"nuke": stock})   # fit_load: as many as the party can lift
	var took := int(u.carry.get("nuke", 0))
	Game.set_silo_stock(anchor, stock - took)
	if took > 0:
		Game.add_log("%s loaded %d unfired %s from the silo at %d,%d.%s Waiting for orders." % [names_text(u), took, "nuke" if took == 1 else "nukes", u.target.x, u.target.y,
			" %d stay behind." % (stock - took) if stock > took else ""])
	else:
		Game.add_log("%s could not lift a nuke. It stays in the silo at %d,%d. Waiting for orders." % [names_text(u), u.target.x, u.target.y])
	_turn_back(u)


## What the site does to a roll: its radiation after the vehicle's shield, and how strong the party is.
func visit_ctx(u: Dictionary) -> Dictionary:
	var rad: float = Game.radiation(u.pos) * Data.MOVERS[u.mover].shield
	if not u.survivors.is_empty() and u.survivors.all(func(s): return int(s.get("salted", 0)) > 0):
		rad *= Data.SALT_RESIST   # a whole party on Salt feels the radiation half as much in its rolls
	return {"radiation": rad, "party_strength": party_strength(u), "leader": leader_rolls()}


## What the leader's perks and flaws do to a party's rolls: a modifier for each kind of check, a reroll every party
## has at least ("min_rerolls") and whether injuries come one step lighter ("medic").
func leader_rolls() -> Dictionary:
	var nose := 1 if Game.has_quirk("sharp_nose") else 0
	var fingers := -1 if Game.has_quirk("butterfingers") else 0
	return {"cache": nose + fingers, "trap": nose + fingers, "site": nose,
		"min_rerolls": 1 if Game.has_quirk("lucky_streak") else 0, "medic": 1 if Game.has_quirk("field_medic") else 0}


## Brings what a roll reads (each survivor's sickness, the site's radiation, the party's strength) up to date.
func _sync_visit(u: Dictionary) -> void:
	for s in u.survivors:
		s["sick"] = sick_level(s)
	u.visit["ctx"] = visit_ctx(u)


## What the player faces at the ruins, or {} if the party isn't at one: the roller, the check, the DC, the
## modifier and its parts, the buttons, and the lines the last roll produced.
func visit_view(u: Dictionary) -> Dictionary:
	if u.get("stage", "") != "site" or not u.has("visit"):
		return {}
	_sync_visit(u)
	if u.visit.stage.begins_with("frog_"):
		return _frog_view(u)
	var view := D20Visit.pending(u.visit, u.survivors)
	view["last"] = u.visit.last
	view["shown"] = u.visit.shown
	view["ruin"] = u.visit.ruin
	view["loot"] = u.visit.loot
	return view


## Does the next roll of a party's visit (`choice` is the id of the button pressed: "roll", "home", "fight", "slip"
## or "deeper"). Returns the d20 the dice should land on, or 0 if the step rolled none.
func visit_do(uid: int, choice := "roll") -> int:
	var u := unit_by_id(uid)
	if u.is_empty() or u.get("stage", "") != "site" or not u.has("visit") or u.visit.stage == "done":
		return 0
	_sync_visit(u)
	if u.visit.stage.begins_with("frog_"):
		return _frog_do(u, choice)
	D20Visit.step(u.visit, dice, u.survivors, choice)
	if bool(u.visit.get("blast", false)) and not bool(u.visit.get("blast_done", false)):
		u.visit["blast_done"] = true
		Game.detonate(u.pos, "crater", [u.id], -1.0, true)   # the party itself is finished off when its visit ends; the explosion plays once the die has landed
	var shown := int(u.visit.shown)
	if shown == 1:
		_frog_wakes(u)   # a natural 1 near the city's ruins may wake the Giant Frog (it adds to u.visit.last)
	for line in u.visit.last:
		Game.add_log(line)
	if shown > 0:
		Game.note("rolls")
		if shown == 20:
			Game.note("natural_20s")
		elif shown == 1:
			Game.note("natural_1s")
	return shown


## "Head home" once the visit is done: the loot is loaded, the ruin is marked, prisoners are taken, and the party
## turns for home. A party that was wiped out is gone for good.
func visit_finish(uid: int) -> void:
	var u := unit_by_id(uid)
	if u.is_empty() or u.get("stage", "") != "site" or not u.has("visit") or u.visit.stage != "done":
		return
	var v: Dictionary = u.visit
	Game.release_blasts()
	if v.ruin == "hunt":
		_finish_hunt(u, v)
		return
	if v.ruin == "building":
		_finish_strike(u, v)
		return
	if v.ruin == "camp":
		_finish_camp_strike(u, v)
		return
	var poi: String = v.get("poi", "")
	var t: Dictionary = Game.tile(Game.poi_anchor(u.target) if poi != "" else u.target)
	var where := "%d,%d" % [u.target.x, u.target.y]
	var place := "site" if poi != "" else ("crater" if v.ruin == "crater" else "ruins")
	u.erase("visit")
	if v.wiped:
		Game.note("survivors_lost", u.crew)
		_wipe(u, "wiped out at the ruins")
		_lost(u)
		Game.add_log("The party was wiped out at the %s at %s." % [place, where])
		Game.changed.emit()
		return
	match v.outcome:
		"slipped", "lost_fight":
			t["r"] = "rogue_seen"   # the raider still holds it
		"left":
			pass
		_:
			for p in (Game.poi_footprint(Game.poi_anchor(u.target)) if poi != "" else [u.target]):
				Game.tile(p)["r"] = "picked"
	Game.prisoners += v.prisoners
	Game.note("prisoners_taken", v.prisoners)
	if poi != "" and v.outcome != "left":
		_site_rewards(v, Game.poi_anchor(u.target))
	if v.outcome != "left" and v.outcome != "slipped" and v.outcome != "lost_fight":
		Game.note("sites_scavenged" if poi != "" else ("craters_searched" if v.ruin == "crater" else "ruins_scavenged"))
	if v.loot.is_empty():
		u.carry = {}
	else:
		_haul(u, v.loot.duplicate())
	var found := int(v.loot.get("nuke", 0))
	if found > 0:
		Game.note("nukes_found", found)
		var left := found - int(u.carry.get("nuke", 0))
		if left > 0 and poi == "missile_silo":
			Game.set_silo_stock(Game.poi_anchor(u.target), left)
			Game.add_log("%d unfired %s stay in the silo. A party that can carry them can fetch them: there is nothing left to roll." % [left, "nuke" if left == 1 else "nukes"])
		elif left > 0:
			Game.add_log("The party could not lift %d of the %d nukes. They are lost." % [left, found])
	if v.outcome == "left":
		Game.add_log("The scavengers left the %s at %s untouched. Waiting for orders." % [place, where])
	elif u.carry.is_empty():
		Game.add_log("The scavengers searched the %s at %s and carry no loot. Waiting for orders." % [place, where] if D20Visit.has_rewards(v)
			else "The scavengers came away from the %s at %s with nothing. Waiting for orders." % [place, where])
	else:
		Game.add_log("Scavengers stripped the %s at %s: %s. Waiting for orders." % [place, where, Game.cost_text(u.carry)])
	_turn_back(u)
	Game.changed.emit()


## The Rust Kings' buildings a stationed scouting party can attack: the one on its own tile and the ones next to it.
func strike_targets(u: Dictionary) -> Array:
	var out := []
	if not u.get("job", "") in PARTY_JOBS or u.get("stage", "") != "station":
		return out
	for c in [u.pos] + Game.neighbors(u.pos):
		if Game.tile(c)["o"] in [Data.AI, Data.TOWN] and Game.can_hit(c):
			out.append(c)
	return out


## The hearths beside a stationed party (its own tile and the four round it) that it cannot attack yet because defences still stand round
## them: [{"cell", "guards"}], the guards being the cells still to bring down.
func guarded_hearths(u: Dictionary) -> Array:
	var out := []
	if not u.get("job", "") in PARTY_JOBS or u.get("stage", "") != "station":
		return out
	for c in [u.pos] + Game.neighbors(u.pos):
		if Game.tile(c)["o"] in [Data.AI, Data.TOWN] and Game.is_hearth(c) and Game.building_dc(c) > 0 and not Game.can_hit(c):
			out.append({"cell": c, "guards": Game.hearth_guards(c)})
	return out


## The raider camps a stationed scouting party can attack: the one on its own tile and the ones next to it.
func camp_targets(u: Dictionary) -> Array:
	var out := []
	if not u.get("job", "") in PARTY_JOBS or u.get("stage", "") != "station":
		return out
	for c in [u.pos] + Game.neighbors(u.pos):
		var t := tribe_at(c)
		if not t.is_empty() and t.class == "raider":
			out.append(t)
	return out


## A stationed scouting party starts an attack on a raider camp beside it: a "visit" like the one for a building, with one roll a
## press against the camp's DC (its strength, 5 to 10, as a fight at the ruins would have it).
func begin_camp_strike(uid: int, tribe_id: int) -> bool:
	var u := unit_by_id(uid)
	var t := tribe_by_id(tribe_id)
	if u.is_empty() or t.is_empty() or not t in camp_targets(u):
		return false
	Game.measure(u.pos)
	u["visit"] = D20Visit.begin_camp_strike(visit_ctx(u), D20.loot_scale, dice, u.survivors, t.id, int(t.strength))
	u.stage = "site"
	Game.add_log("%s gets ready to attack the %s at %d,%d." % [names_text(u), t.name, t.pos.x, t.pos.y])
	_sync_visit(u)
	Game.changed.emit()
	return true


## A stationed scouting party starts an attack on the building at `cell`: a "visit" like a ruin's, with one roll a press.
func begin_strike(uid: int, cell: Vector2i) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or not cell in strike_targets(u):
		return false
	var building: String = Game.tile(cell)["b"]
	Game.measure(u.pos)
	u["visit"] = D20Visit.begin_strike(visit_ctx(u), D20.loot_scale, dice, u.survivors, cell, building, Game.building_dc(cell))
	u.stage = "site"
	Game.add_log("%s gets ready to attack the %s at %d,%d." % [names_text(u), Data.BUILDINGS[building].name.to_lower(), cell.x, cell.y])
	_sync_visit(u)
	Game.changed.emit()
	return true


## What an attack leaves the party with, building or camp: wiped out (gone), or a share of its load lost if the roll went badly, the
## package for a win loaded, and back to keeping watch. False if the party was wiped out.
func _strike_aftermath(u: Dictionary, v: Dictionary, what: String, where: String) -> bool:
	if v.wiped:
		Game.note("survivors_lost", u.crew)
		_wipe(u, "killed attacking the Rust Kings")
		_lost(u)
		Game.add_log("The party was wiped out attacking the %s at %s." % [what, where])
		Game.changed.emit()
		return false
	if float(v.carried_loss) > 0.0 and not u.carry.is_empty():
		var split := D20.lose_share(u.carry, float(v.carried_loss))
		u.carry = split.kept
		if not split.lost.is_empty():
			Game.add_log("They lost %s from their packs." % Game.cost_text(split.lost))
	if not v.loot.is_empty():
		var goods: Dictionary = u.carry.duplicate()
		for r in v.loot:
			goods[r] = goods.get(r, 0) + v.loot[r]
		_haul(u, goods)
	u.stage = "station"
	return true


## "Continue" after an attack on a raider camp: a hit scatters it (and one raider is caught), the party takes its package.
func _finish_camp_strike(u: Dictionary, v: Dictionary) -> void:
	u.erase("visit")
	var t := tribe_by_id(int(v.camp))
	var what: String = t.name if not t.is_empty() else "raider camp"
	var where := "%d,%d" % [t.pos.x, t.pos.y] if not t.is_empty() else "its camp"
	if not _strike_aftermath(u, v, what, where):
		return
	if v.destroyed:
		if not t.is_empty():
			tribes.erase(t)
			Game.note("tribes_scattered")
		Game.prisoners += int(v.prisoners)
		Game.note("prisoners_taken", int(v.prisoners))
		Game.add_log("%s scattered the %s%s." % [names_text(u), what, " and caught %d of the raiders" % int(v.prisoners) if int(v.prisoners) > 0 else ""])
	elif v.outcome == "left":
		Game.add_log("%s backed off from the %s." % [names_text(u), what])
	else:
		Game.add_log("%s could not break the %s." % [names_text(u), what])
	Game.changed.emit()


## "Continue" after an attack: the building comes down if the roll hit it, the party takes its package (and loses a share of
## what it carries if the roll went badly) and goes back to keeping watch. A party the attack wiped out is gone.
func _finish_strike(u: Dictionary, v: Dictionary) -> void:
	u.erase("visit")
	var cell := Vector2i(int(v.cell[0]), int(v.cell[1]))
	var what: String = Data.BUILDINGS[v.building].name.to_lower() if Data.BUILDINGS.has(v.building) else "building"
	if not _strike_aftermath(u, v, what, "%d,%d" % [cell.x, cell.y]):
		return
	if v.destroyed:
		var theirs: bool = Game.tile(cell)["o"] == Data.AI
		Game.destroy_building(cell)
		Game.add_log("%s destroyed the %s at %d,%d.%s" % [names_text(u), what, cell.x, cell.y,
			" Relations with the Rust Kings fall by %d." % Data.RAID_RELATIONS if theirs else ""])
	elif v.outcome == "left":
		Game.add_log("%s backed off from the %s at %d,%d." % [names_text(u), what, cell.x, cell.y])
	else:
		Game.add_log("%s could not bring down the %s at %d,%d." % [names_text(u), what, cell.x, cell.y])
	Game.changed.emit()


## What a site's outcome gives the colony when the party heads home: ground charted (the Rust Kings' fort among it,
## which can be first contact), Dustwell's trust, and recruits (colonists only up to the population cap). The visit only
## recorded these; see SITES in d20_data.gd.
func _site_rewards(v: Dictionary, anchor: Vector2i) -> void:
	if int(v.get("reveal", 0)) > 0:
		Game.reveal(Data.PLAYER, anchor, int(v.reveal))
	if v.get("reveal_fort", false):
		Game.reveal(Data.PLAYER, Game.home(Data.AI), D20Data.SITE_FORT_REVEAL)
	var trust := int(v.get("trust", 0))
	if trust > 0 and Game.town["status"] == "neutral":
		Game.town["relations"] += trust
		if Game.knows(Data.PLAYER, Data.TOWN):
			Game.add_log("Dustwell's trust in you rises by %d (relations %d/60)." % [trust, Game.town["relations"]])
	var colonists := int(v.get("colonists", 0))
	if colonists > 0:
		var joined := mini(colonists, maxi(Game.pop_cap() - Game.pop, 0))
		Game.pop += joined
		Game.add_log("%d colonists settled in the colony." % joined if joined > 0 else "There is no room in the colony for the %d colonists, and they moved on." % colonists)
	var troops := int(v.get("troops", 0))
	if troops > 0:
		Game.troops += troops
		Game.add_log("%d troops joined the colony." % troops)


## Sets a party off for home from wherever it is (or loses it if nobody is left).
func _turn_back(u: Dictionary) -> void:
	if u.crew <= 0:
		_lost(u)
		return
	if u.job in PARTY_JOBS:
		u.stage = "station"   # a party stays where it is, with what it carries, until it is given orders
		u.path = []
		return
	u.stage = "back"
	u.path = Game.route(u.mover, u.pos, u.home).slice(1)
	if u.path.is_empty():
		_come_home(u)


## A warhead run reaches its trader camp: the gold changes hands and the warhead is crated for the long way home. If the camp is gone, or someone else bought it, the gold
## comes back.
func _deal(u: Dictionary) -> void:
	var camp := tribe_by_id(u.dest)
	var price := int(u.get("paid", 0))
	if camp.is_empty() or not camp.get("warhead", false):
		Game.res["gold"] += price
		Game.add_log("Your caravan reached the traders, but there was no warhead for sale. The %d gold came back with it. Heading home." % price)
		return
	camp["warhead"] = false
	_haul(u, {"nuke": 1})
	u["crated"] = true
	Game.note("trade_runs")
	Game.note("nukes_bought")
	Game.add_log("Your caravan bought a warhead from the %s for %d gold. It is crated: a slow, heavy way home." % [camp.name, price])


func _trade(u: Dictionary) -> void:
	if u.dest == -1:   # the Rust Kings
		var armored: bool = Game.has("cv2") and u.mover == "car"
		if Game.ai["relations"] < 0 and not armored and randf() < 0.35:
			_casualty(u, {}, "killed by Rust Kings robbers")
			Game.add_log("The Rust Kings robbed your caravan at their gates! One trader was killed.")
			return
		var goods := {"gold": Game.trade_gold(8 + (2 * Game.vehicle_trade(u.mover) if u.mover in Data.VEHICLES else 0) + (Data.CONTRACT_GOLD if Game.has("c2") else 0))}
		_haul(u, goods)
		Game.ai["relations"] = mini(Game.ai["relations"] + 4, 100)
		Game.note("trade_runs")
		Game.add_log("Caravan traded with the Rust Kings: %s. Heading home." % Game.cost_text(u.carry))
		return
	var tribe := tribe_by_id(u.dest)
	if tribe.is_empty():
		Game.add_log("Your caravan found the trader camp abandoned.")
		return
	if tribe.get("warhead", false) and not tribe.get("warhead_known", false):
		tribe["warhead_known"] = true   # a first trade there: the traders let it be known
		Game.add_log("The %s let slip that they have a warhead for sale: %d gold. Buy it with a caravan on horseback or in a war rig." % [tribe.name, Game.warhead_price()])
	var good: String = Data.TRIBE_GOODS.pick_random()
	if randf() < Data.SALT_CARAVAN_CHANCE:   # now and then the traders have a dose of Salt to spare
		_haul(u, {"gold": Game.trade_gold(5), "salt": 1})
	else:
		_haul(u, {"gold": Game.trade_gold(5), good: 6})
	Game.note("trade_runs")
	Game.add_log("Caravan traded with the %s: %s. Heading home." % [tribe.name, Game.cost_text(u.carry)])


# ---------------------------------------------------------------- wild raider bands

func _spawn_wild() -> void:
	if not wild_spawns:
		return
	for t in tribes:
		if t.class == "raider" and randf() < Data.BAND_SPAWN_CHANCE:
			_spawn_band(t.pos, randi_range(2, 5))
	if randf() < Data.WANDERER_CHANCE:
		var edge := _random_edge_land()
		if Game.in_bounds(edge):
			_spawn_band(edge, randi_range(2, 4))
	if tribes.size() < Data.MAX_TRIBES and randf() < Data.TRIBE_SPAWN_CHANCE:
		_spawn_tribe()


func _spawn_band(pos: Vector2i, strength: int) -> void:
	var u := _make_unit("band", Data.NONE, "foot", pos, pos)
	u.strength = strength
	units.append(u)


## Escaped prisoners form a raider band as strong as they are many, on a free land tile at the edge of your land.
## False (and no band) if your land has no such tile.
func spawn_escaped_band(strength: int) -> bool:
	var spots := []
	for c in Game.owned(Data.PLAYER):
		for n in Game.neighbors(c):
			if Game.tile(n)["o"] == Data.NONE and Game.tile(n)["t"] != "water" and not n in spots:
				spots.append(n)
	if spots.is_empty():
		return false
	_spawn_band(spots.pick_random(), maxi(strength, 1))
	return true


func _random_edge_land() -> Vector2i:
	for attempt in 20:
		var c := Vector2i(randi_range(0, Game.w - 1), [0, Game.h - 1].pick_random())
		if randf() < 0.5:
			c = Vector2i([0, Game.w - 1].pick_random(), randi_range(0, Game.h - 1))
		if Game.tile(c)["t"] != "water" and Game.tile(c)["o"] == Data.NONE:
			return c
	return Vector2i(-1, -1)


## Bands go after your expeditions if one is close, otherwise the nearest colony.
func _band_target(band: Dictionary) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := 1e9
	for u in units:
		if u.owner == Data.PLAYER and not u.mover in ["plane", "bomber", "boat"]:
			var d := Vector2(u.pos - band.pos).length()
			if d < 15 and d < best_d:
				best = u.pos
				best_d = d
	if Game.in_bounds(best):
		return best
	for owner in [Data.PLAYER, Data.AI]:
		var d := Vector2(Game.home(owner) - band.pos).length()
		if d < best_d:
			best = Game.home(owner)
			best_d = d
	return best


func _band_turn(u: Dictionary) -> void:
	if u.age > Data.BAND_LIFETIME:
		_mark_gone(u)
		return
	u.target = _band_target(u)
	u.path = Game.route("foot", u.pos, u.target).slice(1)
	_advance(u)
	# Reaching a colony's land means an attack on its outskirts
	var near := [u.pos] + Game.neighbors(u.pos)
	if near.any(func(c): return Game.tile(c)["o"] == Data.PLAYER):
		_note_event("clash", u.pos, _walk_day(u))
		var def := Game.player_troop_defense() + Game.player_wall_defense()
		var rules: Dictionary = D20Data.RAID_DICE.band
		var roll := Game.raid_roll(float(u.strength), def, "A raider band at the edge of your land")
		if roll.won:
			var loot := {}
			for k in ["grain", "meat", "metal", "gold"]:
				loot[k] = int(Game.res[k] * (rules.crit_loot if roll.crit == "success" else rules.loot))
				Game.res[k] -= loot[k]
			Game.add_log("A raider band hit your outskirts and made off with %s." % Game.cost_text(loot))
			Game.raider_strike(u.pos, u.strength, def)
		else:
			var caught: int = rules.crit_caught if roll.crit == "fail" else rules.caught
			Game.prisoners += caught
			Game.note("prisoners_taken", caught)
			Game.note("bands_driven_off")
			Game.add_log("Your guards drove off a raider band and caught %s of them." % ("one" if caught == 1 else "two"))
		_mark_gone(u)
	elif near.any(func(c): return Game.tile(c)["o"] == Data.AI):
		Game.ai["food"] = maxi(Game.ai["food"] - 3, 0)   # they raid the Rust Kings' stores instead
		_mark_gone(u)


func _ambushes() -> void:
	for band in units:
		if band.job != "band" or band.get("gone", false):
			continue
		for u in units:
			if u.owner != Data.PLAYER or u.get("gone", false) or u.mover in ["plane", "bomber", "boat"]:
				continue
			if Vector2(u.pos - band.pos).length() <= 1.5:
				_fight(band, u)
				break


## A raider band meets one of your parties on the road. It is a ruin fight (d20_visit.gd): the party's best fighter rolls d20 plus
## traits and conditions against the band's DC, and what a miss costs is the combat table's: an injury and a share of what the
## party carries, and only a natural 1 kills someone. A won fight catches one of the band and pays a package.
func _fight(band: Dictionary, u: Dictionary) -> void:
	_note_event("clash", u.pos, SeasonReplay.AT_END)
	var name: String = Data.EXPEDITIONS[u.job].name.to_lower()
	if u.survivors.is_empty():   # a party with nobody named in it (an old save): the army roll
		var plain := Game.raid_roll(float(party_strength(u)), float(band.strength), "Your %s against a raider band" % name)
		_after_field_fight(band, u, name, {"won": plain.won, "d20": plain.d20, "wiped": false, "loot": {}, "carried_loss": 0.25 if not plain.won else 0.0})
		return
	var r: Dictionary = D20Visit.field_fight(visit_ctx(u), dice, u.survivors, int(band.strength), D20.loot_scale)
	for line in r.log:
		Game.add_log(line)
	_after_field_fight(band, u, name, r)


func _after_field_fight(band: Dictionary, u: Dictionary, name: String, r: Dictionary) -> void:
	if r.wiped:
		Game.note("survivors_lost", u.crew)
		_wipe(u, "killed by raiders")
		Game.add_log("A raider band wiped out your %s." % name)
		_lost(u, true)
		return
	if r.won:
		_mark_gone(band, true)
		Game.prisoners += 1
		Game.note("prisoners_taken")
		Game.note("bands_driven_off")
		if not r.loot.is_empty():
			var goods: Dictionary = u.carry.duplicate()
			for k in r.loot:
				goods[k] = goods.get(k, 0) + r.loot[k]
			_haul(u, goods)
		Game.add_log("Your %s fought off a raider band and caught one of them." % name)
		return
	var stolen := ""
	if float(r.carried_loss) > 0.0 and not u.carry.is_empty():
		var split := D20.lose_share(u.carry, float(r.carried_loss))
		u.carry = split.kept
		if not split.lost.is_empty():
			stolen = ", and took " + Game.cost_text(split.lost)
	band.strength += 1
	var who := _casualty(u, {}, "killed by raiders") if int(r.d20) == D20Data.NAT_FAIL else ""
	var toll := "Nobody was killed"
	if int(r.d20) == D20Data.NAT_FAIL:
		toll = who + " was killed" if who != "" else "One killed"
	Game.add_log("A raider band ambushed your %s! %s%s." % [name, toll, stolen])
	if u.crew <= 0:
		_lost(u, true)


# ---------------------------------------------------------------- wild animals

func animal_at(c: Vector2i) -> Dictionary:
	for a in animals:
		if a.pos == c:
			return a
	return {}


func animal_by_id(id: int) -> Dictionary:
	if id == FROG_ID:
		return frog_target()
	for a in animals:
		if a.id == id:
			return a
	return {}


## "black bear", "deer": the animal in lower case, for the log.
func animal_name(a: Dictionary) -> String:
	return Data.FROG.name.to_lower() if a.kind == "frog" else Data.ANIMALS[a.kind].name.to_lower()


## The kill shot's DC for an animal: a bear's is the DC of a raider of its strength.
func kill_dc(kind: String) -> int:
	var spec: Dictionary = D20Data.HUNT[kind]
	return D20Visit.enemy_dc(int(spec.strength)) if int(spec.strength) > 0 else int(spec.kill_dc)


## The animals a game starts with, on open ground away from every camp and colony.
func _spawn_animals() -> void:
	animals = []
	for kind in Data.ANIMALS:
		for i in Data.ANIMALS[kind].start:
			var c := _animal_spot(kind, false)
			if Game.in_bounds(c):
				_add_animal(kind, c)


func _add_animal(kind: String, c: Vector2i) -> Dictionary:
	next_id += 1
	var a := {"id": next_id, "kind": kind, "pos": c, "home": c}
	animals.append(a)
	return a


## A free tile where this kind of animal may start (or, for `arriving`, wander in): its sort of ground, clear of buildings and
## land, ANIMAL_MIN_GAP tiles from every camp and colony and, arriving, ANIMAL_ARRIVE_GAP from your HQ and out of your
## sight. (-1, -1) if there is nowhere.
func _animal_spot(kind: String, arriving: bool) -> Vector2i:
	var terrain: Array = Data.ANIMALS[kind].terrain
	var keep_clear := [Game.home(Data.PLAYER), Game.home(Data.AI), Game.home(Data.TOWN)]
	for t in tribes:
		keep_clear.append(t.pos)
	for attempt in 400:
		var c := Vector2i(randi_range(0, Game.w - 1), randi_range(0, Game.h - 1))
		var t: Dictionary = Game.tile(c)
		if not t["t"] in terrain or t["o"] != Data.NONE or t["b"] != "" or Game.slopes[Game.idx(c)] == "steep":
			continue
		if not animal_at(c).is_empty() or not tribe_at(c).is_empty():
			continue
		if keep_clear.any(func(k): return Vector2(c - k).length() < Data.ANIMAL_MIN_GAP):
			continue
		if arriving and (Vector2(c - Game.home(Data.PLAYER)).length() < Data.ANIMAL_ARRIVE_GAP or Game.in_sight(Data.PLAYER, c)):
			continue
		return c
	return Vector2i(-1, -1)


## Can an animal step onto tile `c`? Open ground nobody owns, with nothing built on it and nothing else standing there.
func _animal_can_stand(c: Vector2i, ignore_id := -1) -> bool:
	if not Game.in_bounds(c):
		return false
	var t: Dictionary = Game.tile(c)
	if t["t"] in ["water", "ruins", "crater", "glass", "waste"] or t["o"] != Data.NONE or t["b"] != "" or Game.slopes[Game.idx(c)] == "steep":
		return false
	var other := animal_at(c)
	if not other.is_empty() and other.id != ignore_id:
		return false
	return tribe_at(c).is_empty()


## Each season an animal may drift a little, staying near where it started; new ones wander in when there are too few.
func _animals_turn() -> void:
	for a in animals:
		if randf() >= Data.ANIMAL_MOVE_CHANCE:
			continue
		var day := randf_range(4.0, 20.0)
		for i in randi_range(1, Data.ANIMALS[a.kind].wander):
			var options: Array = Game.neighbors(a.pos).filter(func(c): return _animal_can_stand(c, a.id) \
				and Vector2(c - a.home).length() <= Data.ANIMAL_HOME_RANGE)
			if options.is_empty():
				break
			a.pos = options.pick_random()
			day += randf_range(2.0, 6.0)
			_note_at(a.id, a.pos, minf(day, Data.SEASON_DAYS - 1.0))
	for kind in Data.ANIMALS:
		var spec: Dictionary = Data.ANIMALS[kind]
		if animals.filter(func(a): return a.kind == kind).size() < int(spec.cap) and randf() < float(spec.respawn):
			var c := _animal_spot(kind, true)
			if Game.in_bounds(c):
				_add_animal(kind, c)


## The animal runs `tiles` steps away from `from` (anywhere, if there is no `from`), and stays where it ends up.
func _scatter_animal(a: Dictionary, tiles: int, from := Vector2i(-1, -1)) -> void:
	for i in tiles:
		var options: Array = Game.neighbors(a.pos).filter(func(c): return _animal_can_stand(c, a.id))
		if options.is_empty():
			break
		if Game.in_bounds(from):
			options.sort_custom(func(p, q): return Vector2(p - from).length() > Vector2(q - from).length())
			a.pos = options[0]
		else:
			a.pos = options.pick_random()
	a.home = a.pos
	_note_at(a.id, a.pos, Data.SEASON_DAYS - 1.0)


## A bear within BEAR_REACH tiles of one of your parties at the end of the season attacks it. It is a field fight on the rules of a raider band
## on the road (see _fight): the party's best fighter rolls against the bear's DC (the DC of a raider of its strength). A win drives the bear
## off; a miss costs what an ambush costs (an injury and a share of the load, and a natural 1 kills someone); the bear stays.
func _bear_attacks() -> void:
	for bear in animals.duplicate():
		if int(D20Data.HUNT[bear.kind].strength) <= 0:
			continue
		for u in units:
			if u.owner != Data.PLAYER or u.get("gone", false) or u.mover in ["plane", "bomber", "boat"] or u.survivors.is_empty():
				continue
			if u.get("stage", "") == "site" and u.get("visit", {}).get("ruin", "") == "hunt" and int(u.visit.get("animal_id", -1)) == bear.id:
				continue   # the hunt is the fight
			if Vector2(u.pos - bear.pos).length() <= Data.BEAR_REACH:
				_bear_fight(bear, u)
				break


func _bear_fight(bear: Dictionary, u: Dictionary) -> void:
	var name: String = Data.EXPEDITIONS[u.job].name.to_lower()
	var kind := animal_name(bear)
	_note_event("clash", u.pos, SeasonReplay.AT_END)
	var r: Dictionary = D20Visit.field_fight(visit_ctx(u), dice, u.survivors, int(D20Data.HUNT[bear.kind].strength), D20.loot_scale)
	for line in r.log:
		Game.add_log(line)
	if r.wiped:
		Game.note("survivors_lost", u.crew)
		_wipe(u, "killed by a wild animal")
		Game.add_log("A %s killed your %s." % [kind, name])
		_lost(u, true)
		return
	if r.won:
		_scatter_animal(bear, Data.BEAR_RETREAT, u.pos)
		Game.add_log("Your %s drove off a %s." % [name, kind])
		return
	var stolen := ""
	if float(r.carried_loss) > 0.0 and not u.carry.is_empty():
		var split := D20.lose_share(u.carry, float(r.carried_loss))
		u.carry = split.kept
		if not split.lost.is_empty():
			stolen = ", and lost " + Game.cost_text(split.lost)
	var toll := "Nobody was killed"
	if int(r.d20) == D20Data.NAT_FAIL:
		var who := _casualty(u, {}, "killed by a bear")
		toll = (who + " was killed") if who != "" else "One killed"
	Game.add_log("A %s mauled your %s! %s%s." % [kind, name, toll, stolen])
	if u.crew <= 0:
		_lost(u, true)


# ---------------------------------------------------------------- hunting

## The animals a stationed scouting party can hunt: the one on its own tile and the ones next to it. Not from a plane or a boat.
func hunt_targets(u: Dictionary) -> Array:
	var out := []
	if not u.get("job", "") in PARTY_JOBS or u.get("stage", "") != "station" or u.mover in ["plane", "bomber", "boat"]:
		return out
	for a in animals:
		if Vector2(a.pos - u.pos).length() <= 1.5:
			out.append(a)
	if _near_frog(u.pos):
		out.append(frog_target())
	return out


## What a party could search where `c` is: "ruins", "crater" or "site", or "" for ground with nothing to search (or that was picked clean).
func scavenge_place(c: Vector2i) -> String:
	var poi := Game.poi_kind(c)
	var t: Dictionary = Game.tile(Game.poi_anchor(c) if poi != "" else c)
	if t["r"] == "picked":
		return ""
	if poi != "":
		return "site"
	return "crater" if t["t"] == "crater" else ("ruins" if t["t"] == "ruins" else "")


## "" if the stationed party can search the ruins it stands on, otherwise why not.
func scavenge_status(u: Dictionary) -> String:
	if not u.get("job", "") in PARTY_JOBS or u.get("stage", "") != "station":
		return "Not waiting for orders"
	if u.mover in ["plane", "bomber", "boat"]:
		return "A plane or a boat cannot search the ruins"
	if scavenge_place(u.pos) == "":
		return "Nothing to search here"
	var poi := Game.poi_kind(u.pos)
	var anchor: Vector2i = Game.poi_anchor(u.pos) if poi != "" else u.pos
	if units.any(func(p): return p.id != u.id and p.stage == "site" and p.owner == Data.PLAYER and (Game.poi_anchor(p.pos) if Game.poi_kind(p.pos) != "" else p.pos) == anchor):
		return "A party is already searching here"
	return ""


## A stationed party searches the ruins, crater or site it stands on: the same visit a scavenger party makes on arriving.
func begin_scavenge(uid: int) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or scavenge_status(u) != "":
		return false
	u.target = u.pos
	u.dest = -1
	_begin_visit(u)
	Game.changed.emit()
	return true


## A stationed scouting party starts a hunt for an animal beside it: a "visit" with a track roll and then a kill shot.
func begin_hunt(uid: int, animal_id: int) -> bool:
	var u := unit_by_id(uid)
	var a := animal_by_id(animal_id)
	if u.is_empty() or a.is_empty() or not a in hunt_targets(u):
		return false
	_start_hunt(u, a)
	Game.changed.emit()
	return true


func _start_hunt(u: Dictionary, a: Dictionary) -> void:
	Game.measure(u.pos)
	var scale: float = D20.loot_scale * (Data.SCAV_CAR_MULT if u.mover == "car" else 1.0)   # a war rig hauls more
	u["visit"] = D20Visit.begin_hunt(visit_ctx(u), scale, dice, u.survivors, a.kind, a.id, animal_name(a))
	u.stage = "site"
	u.path = []
	Game.add_log("%s found the tracks of a %s near %d,%d." % [names_text(u), animal_name(a), a.pos.x, a.pos.y])
	_sync_visit(u)


## A scavenger party sent after an animal has walked to where it was. The animal may have strayed a little: the track roll is the
## search for it, so within 3 tiles there is a hunt, and farther than that the trail is cold and the party goes home.
func _arrive_hunt(u: Dictionary) -> void:
	var a := animal_by_id(u.dest)
	if a.is_empty() or Vector2(a.pos - u.pos).length() > 3.0:
		Game.add_log("%s reached %d,%d, but the tracks have gone cold. Waiting for orders." % [names_text(u), u.pos.x, u.pos.y])
		_turn_back(u)
		return
	_note_event("ruin", u.pos, _walk_day(u))
	_start_hunt(u, a)


## "Continue" after a hunt: the party takes its meat (and a bear's hide gold), an animal that was killed is gone and one that got away
## has run off. A scouting party goes back to keeping watch, a scavenger party heads home.
func _finish_hunt(u: Dictionary, v: Dictionary) -> void:
	if v.animal == "frog":
		_finish_frog(u, v)
		return
	u.erase("visit")
	var a := animal_by_id(int(v.animal_id))
	var kind: String = Data.ANIMALS[v.animal].name.to_lower()
	var where := "%d,%d" % [u.pos.x, u.pos.y]
	if not _strike_aftermath(u, v, kind, where):
		return
	match v.outcome:
		"killed":
			animals.erase(a)
			Game.note("animals_hunted")
			Game.add_log("%s brought down the %s at %s%s." % [names_text(u), kind, where,
				" and carry %s" % Game.cost_text(v.loot) if not v.loot.is_empty() else ""])
		"left":
			Game.add_log("%s gave up the hunt for the %s." % [names_text(u), kind])
		_:
			if not a.is_empty():
				_scatter_animal(a, Data.BEAR_RETREAT if v.animal != "deer" else Data.BEAR_RETREAT + 1, u.pos)
			Game.add_log({"cold": "%s lost the trail of the %s.", "bolted": "The %s bolted when %s came close.",
				"escaped": "%s wounded the %s, but it got away."}.get(v.outcome, "%s lost the %s.") % (
					[kind, names_text(u)] if v.outcome == "bolted" else [names_text(u), kind]))
	_turn_back(u)
	Game.changed.emit()


# ---------------------------------------------------------------- the Giant Frog

## The frog starts asleep under the biggest field of ruins on the map (the epicenter with the most ruin tiles around it).
func _frog_sleeps() -> void:
	frog = {"state": "dormant", "lair": _frog_lair(), "pos": Vector2i(-1, -1), "target": "", "wounds": 0, "rest": 0, "lead": -1}


func _frog_lair() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_n := -1
	for cat in Game.catastrophes:
		var r: int = int(cat.radius) + 1
		var n := 0
		for y in range(cat.pos.y - r, cat.pos.y + r + 1):
			for x in range(cat.pos.x - r, cat.pos.x + r + 1):
				var c := Vector2i(x, y)
				if Game.in_bounds(c) and Game.tile(c)["t"] == "ruins" and Vector2(c - cat.pos).length() <= r:
					n += 1
		if n > best_n:
			best_n = n
			best = cat.pos
	return best


func _load_frog(d: Dictionary) -> void:
	if d.is_empty():
		_frog_sleeps()
		return
	var cell := func(v) -> Vector2i: return Vector2i(int(v[0]), int(v[1]))
	frog = {"state": str(d.get("state", "dormant")), "lair": cell.call(d.get("lair", [-1, -1])), "pos": cell.call(d.get("pos", [-1, -1])),
		"target": str(d.get("target", "")), "wounds": int(d.get("wounds", 0)), "rest": int(d.get("rest", 0)), "lead": int(d.get("lead", -1))}


## The frog as a hunting target, shaped like an animal ({"id", "kind", "pos", "home"}), or {} while it sleeps or after it is dead.
func frog_target() -> Dictionary:
	if frog.get("state", "") != "loose":
		return {}
	return {"id": FROG_ID, "kind": "frog", "pos": frog.pos, "home": frog.pos}


## Is the awake frog on tile `c`? It stands across four tiles: its position and the three right and below.
func frog_at(c: Vector2i) -> bool:
	if frog.get("state", "") != "loose":
		return false
	var d: Vector2i = c - frog.pos
	return d.x >= 0 and d.y >= 0 and d.x <= 1 and d.y <= 1


## Is the party within reach of the frog (any of the four tiles it stands on, or a tile beside them)?
func _near_frog(p: Vector2i) -> bool:
	return frog.get("state", "") == "loose" and p.x >= frog.pos.x - 1 and p.x <= frog.pos.x + 2 and p.y >= frog.pos.y - 1 and p.y <= frog.pos.y + 2


## A natural 1 at a ruin within FROG.wake_radius of the lair, and then a d20 of FROG.wake_roll or less, wakes the frog. It tears out of the ground
## where the party stands and the fight is on: the party's visit becomes "frog_run" (run, or stand and fight), keeping what it has found.
func _frog_wakes(u: Dictionary) -> bool:
	if frog.get("state", "") != "dormant" or not Game.in_bounds(frog.lair) or u.owner != Data.PLAYER:
		return false
	var v: Dictionary = u.visit
	if not v.ruin in ["safe", "trapped", "rogue", "poi"] or v.stage.begins_with("frog_"):
		return false
	if Vector2(u.pos - frog.lair).length() > float(Data.FROG.wake_radius):
		return false
	var woke: int = dice.d20()
	v.last.append("The ground shudders: d20 %d (%d or less wakes the thing under the city)." % [woke, int(Data.FROG.wake_roll)])
	if woke > int(Data.FROG.wake_roll):
		return false
	frog["state"] = "loose"
	frog["pos"] = u.pos
	frog["wounds"] = 0
	frog["rest"] = 0
	frog["lead"] = -1
	frog["target"] = "player" if dice.d20() <= 10 else "ai"
	v["stage"] = "frog_run"
	v["frog_woken"] = true
	v["enemy"] = int(D20Data.FROG_FIGHT.strength)
	v.last.append("THE GIANT FROG WAKES! It tears out of the ruins at %s, and it will go for %s." % [
		names_text(u), "your colony" if frog.target == "player" else "the Rust Kings"])
	Game.add_log("THE GIANT FROG woke under the ruins at %d,%d and is loose. It is heading for %s." % [u.pos.x, u.pos.y,
		"your colony" if frog.target == "player" else "the Rust Kings' fort"])
	Game.note("frog_woken")
	return true


## The player's parties standing at the frog in a frog stage of a visit (`stages`), lowest id first.
func _frog_parties(stages: Array) -> Array:
	var out := []
	for p in units:
		if p.owner == Data.PLAYER and not p.get("gone", false) and p.get("stage", "") == "site" and p.has("visit") \
				and p.visit.stage in stages and _near_frog(p.pos):
			out.append(p)
	out.sort_custom(func(a, b): return a.id < b.id)
	return out


func _frog_standing(p: Dictionary) -> Array:
	return p.survivors.filter(func(s): return s.get("injury", "none") != "severe")


## What the player faces in a frog stage, shaped like D20Visit.pending() for the panel.
func _frog_view(u: Dictionary) -> Dictionary:
	var v: Dictionary = u.visit
	var out := {"stage": v.stage, "text": "", "who": "", "traits": "", "check": "", "dc": 0, "mod": 0, "parts": [], "buttons": []}
	var rule: Dictionary = D20Data.FROG_FIGHT
	match v.stage:
		"frog_run":
			var ctx := D20Visit.check_ctx(v, "run")
			var idx := D20Visit.pick_roller(u.survivors, "run", ctx, 0)
			var scout: Dictionary = D20.party_scout(u.survivors, u.survivors[idx], int(v.rerolls)) if idx >= 0 else {"name": "Nobody", "traits": []}
			var parts := D20Visit.check_parts(scout, "run", ctx, 0, "")
			var mod := D20.clamp_mod(D20Visit.parts_total(parts))
			out["who"] = scout.name
			out["traits"] = D20.trait_names(scout)
			out["check"] = "Run"
			out["dc"] = int(rule.run_dc)
			out["mod"] = mod
			out["parts"] = parts
			out["text"] = "THE GIANT FROG! %d of you against it. %s rolls to run: DC %d, %+d. Or stand and fight." % [_frog_standing(u).size(), scout.name, int(rule.run_dc), mod]
			out["buttons"] = [{"id": "roll", "label": "Run (%+d vs DC %d)" % [mod, int(rule.run_dc)]}, {"id": "fight", "label": "Stand and fight"}]
		"frog_wait":
			var here := _frog_parties(["frog_wait"])
			var fighters := 0
			for p in here:
				fighters += _frog_standing(p).size()
			out["text"] = "You have found the Giant Frog. %d fighters are here. It has %d wounds to take and heals fully each season; six survivors can just do it, nine nearly always." % [fighters, int(rule.wounds)]
			out["buttons"] = [{"id": "frog_attack", "label": "Attack the Giant Frog (%d fighters here)" % fighters}, {"id": "home", "label": "Back off"}]
		"frog_fight":
			var fighters := _frog_parties(["frog_fight"])
			var lead := _frog_lead(fighters)
			if lead != u.id:
				out["text"] = "Fighting the Giant Frog together with the party beside you: use its die."
			else:
				var standing := 0
				for p in fighters:
					standing += _frog_standing(p).size()
				out["text"] = "The Giant Frog has taken %d of %d wounds. %d of your people still stand, and each rolls to hit (DC %d). Then it slams %d times." % [
					int(frog.wounds), int(rule.wounds), standing, int(rule.hit_dc), int(rule.slams)]
				out["buttons"] = [{"id": "roll", "label": "Fight the Giant Frog"}, {"id": "pull", "label": "Pull back"}]
	out["last"] = v.last
	out["shown"] = v.shown
	out["ruin"] = "frog"
	out["loot"] = v.loot
	return out


func _frog_lead(fighters: Array) -> int:
	return int(fighters[0].id) if not fighters.is_empty() else -1


## One press in a frog stage. Returns the d20 the die should land on, or 0.
func _frog_do(u: Dictionary, choice: String) -> int:
	var v: Dictionary = u.visit
	v["last"] = []
	v["shown"] = 0
	match v.stage:
		"frog_run":
			if choice == "fight":
				v["stage"] = "frog_fight"
				v.last.append("You stand and fight.")
				Game.add_log("%s stands and fights the Giant Frog." % names_text(u))
			else:
				_frog_run(u)
		"frog_wait":
			if choice == "frog_attack":
				var here := _frog_parties(["frog_wait"])
				for p in here:
					p.visit["stage"] = "frog_fight"
					p.visit["last"] = []
				Game.add_log("THE FIGHT: %s at the Giant Frog together." % ("a party goes" if here.size() == 1 else "%d parties go" % here.size()))
			elif choice == "home":
				v["stage"] = "done"
				v["outcome"] = "left"
				v.last.append("The party backs off from the frog.")
		"frog_fight":
			var fighters := _frog_parties(["frog_fight"])
			if choice == "pull":
				_frog_end(fighters, "pulled", "You pull back from the Giant Frog.")
			elif not fighters.is_empty() and fighters[0].id == u.id:
				_frog_round(fighters)
	var shown := int(v.shown)
	for line in v.last:
		Game.add_log(line)
	if shown > 0:
		Game.note("rolls")
		if shown == 20:
			Game.note("natural_20s")
		elif shown == 1:
			Game.note("natural_1s")
	return shown


## The run roll of a party the frog woke on: a hit gets them away with what they carry, a miss lets the frog slam them once.
func _frog_run(u: Dictionary) -> void:
	var v: Dictionary = u.visit
	var ctx := D20Visit.check_ctx(v, "run")
	var idx := D20Visit.pick_roller(u.survivors, "run", ctx, 0)
	var scout := D20.party_scout(u.survivors, u.survivors[idx], int(v.rerolls))
	var parts := D20Visit.check_parts(scout, "run", ctx, 0, "")
	var situational := D20Visit.parts_total(parts) - D20.mod_for(scout, "run")
	var result := D20.roll_check(dice, scout, "run", int(D20Data.FROG_FIGHT.run_dc), situational, true, parts)
	v["rerolls"] = scout.rerolls
	v["shown"] = result.d20
	v.last.append(result.log)
	if result.tier == D20Data.SUCCESS or result.tier == D20Data.CRITICAL_SUCCESS:
		v["stage"] = "done"
		v["outcome"] = "left"
		v.last.append("You get away from the Giant Frog.")
		return
	v.last.append("Too slow: the frog is on you.")
	_frog_slams([u], u)
	_frog_after_slams([u])


## A round of the fight: every standing survivor of every party rolls to hit, and the frog slams if it still stands.
func _frog_round(fighters: Array) -> void:
	var rule: Dictionary = D20Data.FROG_FIGHT
	var lead: Dictionary = fighters[0]
	var best_total := -99
	var hits := 0
	var swings := 0
	for p in fighters:
		for s in _frog_standing(p):
			var scout := D20.party_scout(p.survivors, s, int(p.visit.rerolls))
			var ctx := D20Visit.check_ctx(p.visit, "combat")
			var parts := D20Visit.check_parts(scout, "combat", ctx, 0, "")
			var situational := D20Visit.parts_total(parts) - D20.mod_for(scout, "combat")
			var result := D20.roll_check(dice, scout, "combat", int(rule.hit_dc), situational, true, parts)
			p.visit["rerolls"] = scout.rerolls
			var wounds := 2 if result.tier == D20Data.CRITICAL_SUCCESS else (1 if result.tier == D20Data.SUCCESS else 0)
			hits += wounds
			swings += 1
			lead.visit.last.append("%s: d20 %d %+d vs DC %d: %s" % [s.name, result.d20, result.mod, int(rule.hit_dc),
				"%d wound%s" % [wounds, "" if wounds == 1 else "s"] if wounds > 0 else "a miss"])
			if result.total > best_total:
				best_total = result.total
				lead.visit["shown"] = result.d20
	frog["wounds"] = int(frog.wounds) + hits
	lead.visit.last.append("%d swings land %d wounds: the frog has %d of %d." % [swings, hits, mini(int(frog.wounds), int(rule.wounds)), int(rule.wounds)])
	if int(frog.wounds) >= int(rule.wounds):
		_frog_killed(fighters, lead)
		return
	_frog_slams(fighters, lead)
	_frog_after_slams(fighters)


## The frog slams `slams` times. Each picks a standing survivor, who rolls to dodge: a miss fells them (a severe injury, out of the fight), a natural 1 kills them.
func _frog_slams(fighters: Array, lead: Dictionary) -> void:
	var rule: Dictionary = D20Data.FROG_FIGHT
	for i in int(rule.slams):
		var standing := []
		for p in fighters:
			if p.crew <= 0:
				continue
			for s in _frog_standing(p):
				standing.append([p, s])
		if standing.is_empty():
			break
		var pick := clampi(int(dice.roll("1d%d" % standing.size())) - 1, 0, standing.size() - 1)
		var p: Dictionary = standing[pick][0]
		var s: Dictionary = standing[pick][1]
		var scout := D20.party_scout(p.survivors, s, 0)
		var ctx := D20Visit.check_ctx(p.visit, "dodge")
		var parts := D20Visit.check_parts(scout, "dodge", ctx, 0, "")
		var situational := D20Visit.parts_total(parts) - D20.mod_for(scout, "dodge")
		var result := D20.roll_check(dice, scout, "dodge", int(rule.dodge_dc), situational, false, parts)
		if result.tier == D20Data.SUCCESS or result.tier == D20Data.CRITICAL_SUCCESS:
			lead.visit.last.append("The frog slams at %s: d20 %d, dodged." % [s.name, result.d20])
		elif result.tier == D20Data.CRITICAL_FAILURE:
			_casualty(p, s, "killed by the Giant Frog")
			lead.visit.last.append("The frog slams at %s: d20 %d. %s is killed." % [s.name, result.d20, s.name])
			if p.crew <= 0:
				p.visit["wiped"] = true
		else:
			s["injury"] = "severe"
			p.visit.injuries[s.name] = "severe"
			lead.visit.last.append("The frog slams at %s: d20 %d. %s is felled." % [s.name, result.d20, s.name])


## After the slams: a party with nobody left is wiped out, and if nobody at all still stands the frog has won.
func _frog_after_slams(fighters: Array) -> void:
	var standing := 0
	for p in fighters:
		if p.crew <= 0 or p.visit.get("wiped", false):
			p.visit["wiped"] = true
			p.visit["stage"] = "done"
			p.visit["outcome"] = "wiped"
		else:
			standing += _frog_standing(p).size()
	if standing == 0:
		var live := fighters.filter(func(p): return not p.visit.get("wiped", false))
		if not live.is_empty():
			_frog_end(live, "defeated", "Nobody is left on their feet. The survivors drag themselves away from the Giant Frog.")


## The fight is over for these parties and the frog lives: they go home (hurt, with what they carry).
func _frog_end(fighters: Array, outcome: String, line: String) -> void:
	for p in fighters:
		p.visit["stage"] = "done"
		p.visit["outcome"] = outcome if p.visit.get("ruin", "") == "hunt" else "left"
	if not fighters.is_empty():
		fighters[0].visit.last.append(line)


## The twelfth wound: the Giant Frog dies, for good. Its raw hides (FROG.hides of them) go to the parties, one each in turn.
func _frog_killed(fighters: Array, lead: Dictionary) -> void:
	frog["state"] = "dead"
	Game.note("frog_killed")
	var hides := int(Data.FROG.hides)
	var alive := fighters.filter(func(p): return p.crew > 0)
	for i in hides:
		if alive.is_empty():
			break
		var p: Dictionary = alive[i % alive.size()]
		p.visit.loot["hide"] = int(p.visit.loot.get("hide", 0)) + 1
	for p in fighters:
		p.visit["stage"] = "done"
		p.visit["outcome"] = "killed" if p.visit.get("ruin", "") == "hunt" else "looted"
	lead.visit.last.append("THE GIANT FROG IS DEAD. The survivors scrape %d raw hides off it." % hides)
	Game.add_log("THE GIANT FROG IS DEAD! Its raw hides must be carried home and processed in a Drug Factory.")


## "Continue" after a fight with the frog (a party that went looking for it): hides and a bit of loot are taken, and the party heads home or keeps watch.
func _finish_frog(u: Dictionary, v: Dictionary) -> void:
	u.erase("visit")
	var where := "%d,%d" % [u.pos.x, u.pos.y]
	if not _strike_aftermath(u, v, "Giant Frog", where):
		return
	match v.outcome:
		"killed":
			Game.add_log("%s killed the Giant Frog at %s%s." % [names_text(u), where, " and carry %s" % Game.cost_text(v.loot) if not v.loot.is_empty() else ""])
		"cold":
			Game.add_log("%s lost the Giant Frog's trail." % names_text(u))
		"left":
			Game.add_log("%s backed off from the Giant Frog." % names_text(u))
		_:
			Game.add_log("%s limps away from the Giant Frog, hurt." % names_text(u))
	if u.job in ["scav", "hunters"]:
		_turn_back(u)
	Game.changed.emit()


## Each season the awake frog heals, then walks about a tile a day toward its target. When it arrives it raids (once a season).
func _frog_turn() -> void:
	if frog.get("state", "") != "loose":
		return
	frog["wounds"] = 0
	if int(frog.rest) > 0:
		frog["rest"] = int(frog.rest) - 1
		return
	var owner: int = Data.PLAYER if frog.target == "player" else Data.AI
	var dest := Game.home(owner)
	var path := Game.route("foot", frog.pos, dest)
	var steps := int(float(Data.SEASON_DAYS) * float(Data.FROG.pace))
	var i := 1
	while i <= steps and Vector2(frog.pos - dest).length() > 3.0:
		var next: Vector2i
		if i < path.size():
			next = path[i]
		else:
			next = frog.pos + Vector2i(signi(dest.x - frog.pos.x), signi(dest.y - frog.pos.y))
		frog["pos"] = next
		_note_at(FROG_ID, next, float(i) * Data.SEASON_DAYS / float(maxi(steps, 1)))
		i += 1
	if Vector2(frog.pos - dest).length() <= 3.0:
		_frog_raid(owner)
	# parties that were waiting where it was lose it
	for p in units:
		if p.owner == Data.PLAYER and p.get("stage", "") == "site" and p.has("visit") and p.visit.stage in ["frog_wait", "frog_fight"] and not _near_frog(p.pos):
			p.visit["stage"] = "done"
			p.visit["outcome"] = "cold"
			Game.add_log("The Giant Frog moved on from %s." % names_text(p))


## The frog's raid on the colony it has reached: the raiding dice at its strength against that colony's defense. A win costs your colony up to FROG.raid_buildings
## buildings and a share of its troops, and the Rust Kings the same share of theirs and some walls; a miss and it rests a season.
func _frog_raid(owner: int) -> void:
	_note_event("clash", frog.pos, _walk_day_of(FROG_ID))
	var mine := owner == Data.PLAYER
	var def: float = Game.player_troop_defense() + Game.player_wall_defense() if mine else Game.ai_defense(Game.wall_breach())
	var roll := Game.raid_roll(float(Data.FROG.raid_strength), def, "The Giant Frog's raid on %s" % ("your colony" if mine else "the Rust Kings"))
	if not roll.won:
		frog["rest"] = 1
		Game.add_log("%s drove the Giant Frog back." % ("Your defenses" if mine else "The Rust Kings"))
		return
	var share := float(Data.FROG.raid_troops)
	if mine:
		var lost := 0
		for c in Game.buildings_of(Data.PLAYER, frog.pos).slice(0, int(Data.FROG.raid_buildings)):
			Game.add_log("The Giant Frog smashed your %s at %d,%d." % [Data.BUILDINGS[Game.tile(c)["b"]].name.to_lower(), c.x, c.y])
			Game.destroy_building(c)
			lost += 1
		var troops := int(ceil(Game.troops * share))
		Game.troops = maxi(Game.troops - troops, 0)
		Game.add_log("The Giant Frog tore through your colony: %d buildings and %d troops lost." % [lost, troops])
	else:
		var troops := int(ceil(Game.ai["troops"] * share))
		Game.ai["troops"] = maxi(Game.ai["troops"] - troops, 0)
		Game.ai["walls"] = maxi(Game.ai["walls"] - int(Data.FROG.raid_buildings) * Data.WALLS_PER_TILE, 0)
		Game._sync_ai_walls()
		Game.add_log("The Giant Frog tore into the Rust Kings' fort: they lost %d troops and some of their walls." % troops)


func _walk_day_of(id: int) -> float:
	var actor: Dictionary = _actors.get(id, {})
	return 0.0 if actor.is_empty() else actor.trail.back()[1]


# ---------------------------------------------------------------- tribes

## Does a new trader camp hold a warhead for sale? About Data.TRADERS.warhead_chance of them do. It is worked out from the camp's number and place, not drawn from the random
## numbers, so everything made after it (the animals, the frog) is as it was.
func holds_warhead(id: int, pos: Vector2i) -> bool:
	return absi(hash([id, pos.x, pos.y])) % 1000 < int(float(Data.TRADERS.warhead_chance) * 1000.0)


func _spawn_tribe() -> Dictionary:
	for attempt in 80:
		var c := Vector2i(randi_range(3, Game.w - 4), randi_range(3, Game.h - 4))
		var t: Dictionary = Game.tile(c)
		if t["o"] != Data.NONE or t["b"] != "" or t["t"] in ["water", "ruins"] or Game.slopes[Game.idx(c)] == "steep":
			continue
		if Game.bases.values().any(func(b): return c.distance_to(b) < 14):
			continue
		if tribes.any(func(o): return c.distance_to(o.pos) < 10):
			continue
		next_id += 1
		var tribe := {"id": next_id, "class": Data.TRIBE_CLASSES.keys().pick_random(),
			"name": "%s %s" % [Data.TRIBE_NAMES[0].pick_random(), Data.TRIBE_NAMES[1].pick_random()],
			"pos": c, "strength": randi_range(5, 10), "relations": 0, "found": false}
		tribe["warhead"] = tribe["class"] == "trader" and holds_warhead(next_id, c)
		tribe["warhead_known"] = false
		tribes.append(tribe)
		return tribe
	return {}


## Called after the fog updates: log tribes your colony sees for the first time, and the Hollow Mile.
func check_discoveries() -> void:
	Game.check_hollow_mile()
	Game.check_airfield()
	for t in tribes:
		if not t.found and Game.knows_tile(Data.PLAYER, t.pos):
			t["found"] = true
			Game.add_log("Your people found the %s, a %s." % [t.name, Data.TRIBE_CLASSES[t.class].name.to_lower()])


func known_tribes() -> Array:
	return tribes.filter(func(t): return t.found)


const GIFT := {"grain": 10}


func gift_tribe(id: int) -> void:
	var t := tribe_by_id(id)
	if t.is_empty() or not Game.pay(GIFT):
		return
	t.relations += 25
	if t.relations >= 50:
		Game.pop += 4
		Game.note("tribes_joined")
		tribes.erase(t)
		Game.add_log("The %s packed up their camp and joined your colony! +4 colonists." % t.name)
	else:
		Game.add_log("The %s welcomed your gift. (Trust %d/50)" % [t.name, t.relations])
	Game.changed.emit()


# ---------------------------------------------------------------- saving

func to_save() -> Dictionary:
	return {"next_id": next_id, "tribes": tribes.map(_pack), "units": units.map(_pack), "animals": animals.map(_pack), "frog": _pack(frog)}


func load_from(data: Dictionary) -> void:
	replay = {}
	_actors = {}
	next_id = int(data.get("next_id", 1))
	tribes = data.get("tribes", []).map(_unpack)
	units = data.get("units", []).map(_unpack)
	animals = data.get("animals", []).map(_unpack)
	_load_frog(data.get("frog", {}))
	for u in units:
		if u.job != "band" and u.stage != "station" and u.stage != "site":
			u.path = Game.route(u.mover, u.pos, u.target if u.stage == "out" else u.home).slice(1)
		if u.owner == Data.PLAYER and u.job in PARTY_JOBS and int(u.get("number", 0)) <= 0:
			u["number"] = _next_party_number()   # a save from before parties were numbered


## JSON can't store Vector2i, so cells are saved as [x, y] and paths are rebuilt on load.
func _pack(d: Dictionary) -> Dictionary:
	var out := d.duplicate()
	out.erase("path")
	for k in out:
		if out[k] is Vector2i:
			out[k] = [out[k].x, out[k].y]
	return out


func _unpack(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		var v = d[k]
		if k in ["pos", "target", "home"]:
			v = Vector2i(int(v[0]), int(v[1]))
		elif k == "fuel" or k == "move_left":
			v = float(v)   # the numbers that can have a fraction
		elif typeof(v) == TYPE_FLOAT:
			v = int(v)
		elif k in ["carry", "food"]:
			v = Game._ints(v)
			for r in v.keys():
				if not r in Data.RESOURCES and not r in Data.ITEMS:
					v.erase(r)   # scrap and silver are gone from older saves
		elif k == "survivors":
			v = v.map(func(s): return Roster.load_one(s, 0, "away", Game.season))
		out[k] = v
		if k == "visit":
			out[k] = D20Visit.normalize(d[k])
	if not out.has("survivors"):
		out["survivors"] = []   # saves from before named survivors
	if not out.has("move_left"):
		out["move_left"] = float(Data.SEASON_DAYS)   # saves from before parties walked on your orders
	if not out.has("rad_days"):
		out["rad_days"] = 0.0   # saves from before radiation
		out["moved"] = false
	if out.get("job", "") in PARTY_JOBS and not out.has("food"):
		out["food"] = {"grain": Data.SCOUT_PACK}   # saves from before food packs: scouts ate from the stores
	out["path"] = []
	return out
