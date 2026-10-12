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

var dice = Dice.new()     # every roll of a ruin visit goes through this (tests swap in forced dice)
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
	next_id = 1
	for i in Data.TRIBES_AT_START:
		if randf() < Data.TRIBE_START_CHANCE:
			_spawn_tribe()


func _make_unit(job: String, owner: int, mover: String, pos: Vector2i, target: Vector2i) -> Dictionary:
	next_id += 1
	return {"id": next_id, "job": job, "owner": owner, "mover": mover, "pos": pos, "target": target,
		"home": pos, "stage": "out", "crew": 0, "carry": {}, "strength": 0, "age": 0, "dest": -1, "path": [],
		"survivors": [], "rad_days": 0.0, "moved": false}


## Which entry of Data.UNITS draws this unit: vehicles show as themselves, otherwise the job.
func glyph_kind(u: Dictionary) -> String:
	if u.job == "band":
		return "band"
	if u.mover in ["car", "boat", "plane"]:
		return u.mover
	return u.job


func units_at(c: Vector2i) -> Array:
	return units.filter(func(u): return u.pos == c)


func unit_by_id(id: int) -> Dictionary:
	for u in units:
		if u.id == id:
			return u
	return {}


## How far this unit sees. Scouts see by how they travel, everything else by its glyph.
func sight_of(u: Dictionary) -> int:
	if u.job == "scout":
		var sight: int = Data.SCOUT_SIGHT[u.mover]
		if Game.has_quirk("eagle_eyes"):
			sight += 1
		elif Game.has_quirk("short_sight"):
			sight -= 1
		return maxi(sight, 1)
	return Data.UNITS[glyph_kind(u)].sight


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
	return units.filter(func(u): return u.owner == Data.PLAYER and u.job in ["caravan", "boat"]).size()


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


## How much fuel an expedition takes along: scouts in a war rig or plane, and river trader boats
## (unless you've refitted them with sails). 0 means no tank, so no gauge.
func tank_size(job: String, mover: String) -> int:
	if not mover in Data.VEHICLE_FUEL:
		return 0
	if job == "scout" or (job == "boat" and not Game.has("fv3")):
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


## What an expedition costs to send: the ones with a tank also fill it.
## (Scouts' food pack comes on top of this, from any of your food: see send_cost_text().)
func send_cost(job: String, mover: String) -> Dictionary:
	var cost: Dictionary = Data.EXPEDITIONS[job].cost.duplicate()
	var tank := tank_size(job, mover)
	if tank > 0:
		cost["fuel"] = cost.get("fuel", 0) + tank
	if job == "scav" and mover == "car":
		cost["fuel"] = cost.get("fuel", 0) + Data.SCAV_CAR_FUEL   # a flat trip fee, not a tank
	return cost


## send_cost() as text, with the food pack for scouts.
func send_cost_text(job: String, mover: String) -> String:
	var text := Game.cost_text(send_cost(job, mover))
	if job != "scout":
		return text
	var pack := "%d food" % Data.SCOUT_PACK
	return pack if text == "free" else "%s, %s" % [text, pack]


## "" if this expedition can leave, otherwise why not. Boats leave from `from` (your port).
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
	if job == "scout" and scouts_out() >= Game.scout_parties():
		return "All %d scouting parties are out" % Game.scout_parties()
	if Game.pop <= e.crew + 1:
		return "Need %d colonists to spare" % e.crew
	if job in ["caravan", "boat"] and trade_runs() >= Game.caravan_slots():
		return "All %d caravan slots in use" % Game.caravan_slots()
	if job == "caravan" and dest == -1:
		if not Game.knows(Data.PLAYER, Data.AI):
			return "You haven't found them yet"
		if Game.ai["relations"] <= -50:
			return "They won't trade with you"
	if job == "scav" and units.any(func(u): return u.job == "scav" and u.target == target and u.stage in ["out", "site"]):
		return "A party is already heading there"
	var cost := send_cost(job, mover)
	if not Game.can_afford(cost):
		return "Need " + Game.cost_text(cost)
	if job == "scout" and food_stock() < Data.SCOUT_PACK:
		return "Need %d food for the pack" % Data.SCOUT_PACK
	if outbound_route(job, mover, from, target).is_empty():
		return "No way there" + (" (steep inclines)" if mover == "car" else "")
	return ""


func send(job: String, mover: String, target: Vector2i, dest := -1, from := Vector2i(-1, -1)) -> void:
	if not Game.in_bounds(from):
		from = Game.home(Data.PLAYER)
	if send_status(job, mover, target, dest, from) != "":
		return
	if job == "boat":
		from = launch_tile(from)
	var e: Dictionary = Data.EXPEDITIONS[job]
	Game.pay(send_cost(job, mover))
	Game.note_sent(job)
	Game.pop -= e.crew
	var path := outbound_route(job, mover, from, target)
	var u := _make_unit(job, Data.PLAYER, mover, from, path[-1])
	u.crew = e.crew
	u.survivors = _make_crew(e.crew)
	u.dest = dest
	u.path = path.slice(1)
	if tank_size(job, mover) > 0:
		u.fuel = float(tank_size(job, mover))
	if job == "scout":
		u.food = _pack_food(Data.SCOUT_PACK)
	units.append(u)
	if job == "scout":
		Game.measure(from)
		Game.add_log("%s set out %s toward %d,%d as a scouting party." % [names_text(u), Data.MOVERS[mover].by, u.target.x, u.target.y])
	else:
		Game.add_log("%s (%s) set out %s toward %d,%d." % [e.name, names_text(u), Data.MOVERS[mover].by, u.target.x, u.target.y])
	Game.changed.emit()


# ---------------------------------------------------------------- survivors

## `n` new survivors with names nobody else in the field is using.
func _make_crew(n: int) -> Array:
	var used := []
	for other in units:
		for s in other.survivors:
			used.append(s.name)
	var pool: Array = Data.SURVIVOR_NAMES.filter(func(x): return not x in used)
	if pool.size() < n:
		pool = Data.SURVIVOR_NAMES.duplicate()
	pool.shuffle()
	var crew := []
	var trait_ids: Array = D20Data.TRAITS.keys()
	for i in n:
		trait_ids.shuffle()
		var mine: Array = trait_ids.slice(0, randi_range(1, 3))   # 1 to 3 traits each, no repeats
		crew.append({"name": pool[i], "age": randi_range(17, 58), "traits": mine,
			"injury": "none",   # from this expedition's rolls: none, light or severe, until the party is home
			"hunger": 0, "hp": Data.SURVIVOR_HP, "dose": 0.0, "hurt": false,   # hurt: injured in a crash, until they heal
			"face": randi() & 0x7fffffff})   # the seed for their portrait
	return crew


## "Mara", "Mara and Dex", "Mara, Dex and Odo"; "the crew" if nobody is named.
func names_text(u: Dictionary) -> String:
	var names: Array = u.survivors.map(func(s): return s.name)
	return list_text(names) if not names.is_empty() else "the crew"


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
	if s.get("injury", "none") != "none":
		status += ", %s injury" % s.injury
	if s.hp < Data.SURVIVOR_HP:
		status += ", %d hp" % ceili(s.hp)
	var traits := D20.trait_names(s)
	return "%s, %d, %s(%s)" % [s.name, s.age, traits + " " if traits != "" else "", status]


## Takes one survivor out of the party (a random one, or `who`) and returns their name.
func _casualty(u: Dictionary, who := {}) -> String:
	u.crew = maxi(u.crew - 1, 0)
	Game.note("survivors_lost")
	if u.survivors.is_empty():
		return ""
	var s: Dictionary = who if not who.is_empty() else u.survivors.pick_random()
	u.survivors.erase(s)
	return s.name


## What the party is doing, in a few words.
func stage_text(u: Dictionary) -> String:
	match u.stage:
		"out":
			return "heading out"
		"station":
			return "keeping watch"
		"site":
			return "attacking a building" if u.get("visit", {}).get("ruin", "") == "building" else "at the ruins"
	return "heading home"


# ---------------------------------------------------------------- scouting parties

func scouts_out() -> int:
	return units.filter(func(u): return u.owner == Data.PLAYER and u.job == "scout").size()


## Orders for a party already in the field: "" if it can go there, otherwise why not.
func order_status(u: Dictionary, target: Vector2i) -> String:
	if u.pos == target and u.stage == "station":
		return "Already here"
	if Game.route(u.mover, u.pos, target).is_empty():
		return "No way there" + (" (steep inclines)" if u.mover == "car" else "")
	return ""


func order_scouts(id: int, target: Vector2i) -> void:
	var u := unit_by_id(id)
	if u.is_empty() or order_status(u, target) != "":
		return
	u.target = target
	u.stage = "out"
	u.path = Game.route(u.mover, u.pos, target).slice(1)
	if u.path.is_empty():
		u.stage = "station"
	Game.add_log("%s head for %d,%d." % [names_text(u), target.x, target.y])
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
		Game.add_log("%s are heading back to camp." % names_text(u))
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
			_casualty(u, s)
			Game.add_log("%s starved to death at %d,%d." % [s.name, u.pos.x, u.pos.y])
		elif s.hunger >= Data.STARVING_AT:
			Game.add_log("%s is starving at %d,%d! Bring the party home before it's too late." % [s.name, u.pos.x, u.pos.y])
		else:
			Game.add_log("%s has gone hungry: the pack is empty." % s.name)
	if food_total(u) == 0 and before > 0:
		Game.add_log("%s have eaten the last of their food at %d,%d." % [names_text(u), u.pos.x, u.pos.y])
	elif food_total(u) > 0 and food_days(u) <= 2.0 * Data.SEASON_DAYS:
		Game.add_log("%s are low on food (%d left)." % [names_text(u), food_total(u)])


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
		w += goods[k] * Data.WEIGHT.get(k, 1.0)
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


## `goods` trimmed to what the party can still pick up: nobody carries more than LOAD_CEILING
## times their capacity, so the rest stays behind (in the same mix as what was on offer).
func fit_load(u: Dictionary, goods: Dictionary) -> Dictionary:
	var room := maxf(Data.LOAD_CEILING * load_capacity(u) - load_weight(u), 0.0)
	var weight := goods_weight(goods)
	if weight <= room:
		return goods
	var share := room / weight
	var kept := {}
	var left := {}
	for k in goods:
		var n := int(goods[k] * share)
		if n > 0:
			kept[k] = n
		if goods[k] - n > 0:
			left[k] = goods[k] - n
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
		s.dose = s.dose * Data.DOSE_DECAY + exposure * Game.dose_rate()
		if s.dose < 0.5:
			s.dose = 0.0
		s.hp -= s.dose * Data.POISON_DAMAGE
		if s.hp <= 0.0:
			_casualty(u, s)
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
	Game.vehicles[v] = maxi(Game.vehicles[v] - 1, 0)
	u.mover = "foot"
	u.erase("fuel")
	match v:
		"plane":
			_crash(u, where)
		"boat":
			Game.add_log("OUT OF FUEL: the boat ran dry at %s and was abandoned. %s wade ashore and head home on foot." % [where, names_text(u)])
		_:
			Game.add_log("OUT OF FUEL: the war rig ran dry at %s and was abandoned. %s continue on foot." % [where, names_text(u)])
	if u.crew <= 0:
		_lost(u)   # nobody walked away from the wreck
		return
	if not u.carry.is_empty():
		_haul(u, u.carry.duplicate())   # on foot they can carry less: what doesn't fit is left with the wreck
	u.path = []
	if u.job != "scout":
		u.stage = "back"   # a trade run is off: they walk home
	if u.stage == "back":
		u.path = Game.route("foot", u.pos, u.home).slice(1)
	if u.path.is_empty():
		if u.job == "scout":
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
			died.append(_casualty(u, s))
	var text := "OUT OF FUEL: the plane crashed at %s." % where
	if not died.is_empty():
		text += " %s died in the wreck." % list_text(died)
	if walked.is_empty():
		text += " Nobody walked away."
	else:
		text += " %s survived, injured, and continue on foot." % list_text(walked)
	Game.add_log(text)


func _scout_turn(u: Dictionary) -> void:
	_feed(u)
	if u.crew <= 0:
		_lost(u)
		return
	if u.stage == "station":
		_idle(u)
	elif u.stage == "site":
		pass   # in the middle of an attack, waiting for the player's roll
	elif _advance(u):
		_arrive(u)


# ---------------------------------------------------------------- the season

func season_turn() -> void:
	_spawn_wild()
	for u in units.duplicate():
		u.age += 1
		if u.job == "band":
			_band_turn(u)
		elif u.job == "scout":
			_scout_turn(u)
		elif u.stage == "site":
			pass   # waiting at the ruins for the player's roll; _expose below counts the season spent standing there
		elif _advance(u):
			_arrive(u)
		if u.owner == Data.PLAYER and not u.get("gone", false):
			_expose(u)
	_ambushes()
	units = units.filter(func(u): return not u.get("gone", false))


## Walk the path with one season's worth of travel days. True once the path is done.
func _advance(u: Dictionary) -> bool:
	var budget: float = Data.SEASON_DAYS
	var days_per_tile: float = Data.MOVERS[u.mover].days * load_slowdown(u)   # a heavy load takes longer
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
		if u.owner == Data.PLAYER:
			Game.reveal(Data.PLAYER, u.pos, sight_of(u))
			u.rad_days += Game.radiation(u.pos) * cost
			if u.job == "scout":
				Game.measure(u.pos)   # the party's counter clicks away: that reading is kept for good
	if u.owner == Data.PLAYER:
		u.rad_days += Game.radiation(u.pos) * budget   # the rest of the season is spent here
		u.moved = true
	return u.path.is_empty()


func _arrive(u: Dictionary) -> void:
	if u.stage == "back":
		_come_home(u)
		return
	if u.job == "scout":
		u.stage = "station"
		Game.add_log("%s reached %d,%d and are keeping watch." % [names_text(u), u.pos.x, u.pos.y])
		return
	if u.job == "scav":
		_begin_visit(u)
		return
	match u.job:
		"caravan":
			_trade(u)
		"boat":
			var goods := {"gold": Game.trade_gold(10 + Game.vehicle_trade("boat") + (Data.CONTRACT_GOLD if Game.has("c2") else 0))}
			_haul(u, goods)
			Game.note("trade_runs")
			Game.add_log("Your boat traded with river folk downstream: %s. Heading home." % Game.cost_text(u.carry))
		"plane":
			Game.add_log("Recon plane reached %d,%d and turned for home." % [u.pos.x, u.pos.y])
	if u.crew <= 0:
		_lost(u)
		return
	u.stage = "back"
	u.path = Game.route(u.mover, u.pos, u.home).slice(1)
	if u.path.is_empty():
		_come_home(u)


func _come_home(u: Dictionary) -> void:
	for k in u.carry:
		Game.res[k] += u.carry[k]
	Game.pop += u.crew
	var name: String = Data.EXPEDITIONS[u.job].name
	if u.carry.is_empty():
		Game.add_log("%s came home." % name)
	else:
		Game.add_log("%s came home with %s." % [name, Game.cost_text(u.carry)])
	if food_total(u) > 0:   # whatever they didn't eat goes back in the stores
		for k in u.food:
			Game.res[k] += u.food[k]
		Game.add_log("Their unspent food (%s) went back into the stores." % food_text(u))
	if u.get("fuel", 0.0) >= 1.0:   # so does whole units of fuel left in the tank
		var left := int(u.fuel)
		Game.res["fuel"] += left
		Game.add_log("%d fuel left in the tank went back into the stores." % left)
		u.erase("fuel")
	u["gone"] = true


func _lost(u: Dictionary) -> void:
	if u.mover in Data.VEHICLES:
		Game.vehicles[u.mover] = maxi(Game.vehicles[u.mover] - 1, 0)
	Game.add_log("Your %s was wiped out in the wastes." % Data.EXPEDITIONS[u.job].name.to_lower())
	u["gone"] = true


# ---------------------------------------------------------------- a visit to the ruins

## A scavenger party that has walked to its ruin stops there. What the ruin hides (a trap, a rogue raider, nothing)
## came with the map, and the d20 rolls that follow, one button press each, are in d20_visit.gd. Arriving measures
## the ruin's radiation, so the player sees what it does to the roll before making it.
func _begin_visit(u: Dictionary) -> void:
	var poi := Game.poi_kind(u.target)
	var anchor: Vector2i = Game.poi_anchor(u.target) if poi != "" else u.target
	var t: Dictionary = Game.tile(anchor)
	var where := "%d,%d" % [u.target.x, u.target.y]
	if t["r"] == "picked":
		Game.add_log("Scavengers found the %s at %s already picked clean." % ["site" if poi != "" else "ruins", where])
		_turn_back(u)
		return
	Game.measure(u.pos)
	var ruin: String = "poi" if poi != "" else {"trap": "trapped", "rogue": "rogue", "rogue_seen": "rogue"}.get(t["r"], "safe")
	var scale: float = D20.loot_scale * (Data.SCAV_CAR_MULT if u.mover == "car" else 1.0)   # a war rig hauls more
	if poi != "":
		scale *= Data.POI_LOOT_MULT
	u["visit"] = D20Visit.begin(ruin, visit_ctx(u), scale, dice, u.survivors, poi)
	u.stage = "site"
	u.path = []
	Game.add_log("%s reached the %s at %s." % [names_text(u), Data.BUILDINGS["poi_" + poi].name.to_lower() if poi != "" else "ruins", where])
	_sync_visit(u)


## What the site does to a roll: its radiation after the vehicle's shield, and how strong the party is.
func visit_ctx(u: Dictionary) -> Dictionary:
	return {"radiation": Game.radiation(u.pos) * Data.MOVERS[u.mover].shield, "party_strength": party_strength(u), "leader": leader_rolls()}


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
	D20Visit.step(u.visit, dice, u.survivors, choice)
	for line in u.visit.last:
		Game.add_log(line)
	var shown := int(u.visit.shown)
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
	if v.ruin == "building":
		_finish_strike(u, v)
		return
	var poi: String = v.get("poi", "")
	var t: Dictionary = Game.tile(Game.poi_anchor(u.target) if poi != "" else u.target)
	var where := "%d,%d" % [u.target.x, u.target.y]
	var place := "site" if poi != "" else "ruins"
	u.erase("visit")
	if v.wiped:
		Game.note("survivors_lost", u.crew)
		u.crew = 0
		u.survivors = []
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
		Game.note("sites_scavenged" if poi != "" else "ruins_scavenged")
	if v.loot.is_empty():
		u.carry = {}
	else:
		_haul(u, v.loot.duplicate())
	if v.outcome == "left":
		Game.add_log("The scavengers left the %s at %s untouched. Heading home." % [place, where])
	elif u.carry.is_empty():
		Game.add_log("The scavengers searched the %s at %s and carry no loot. Heading home." % [place, where] if D20Visit.has_rewards(v)
			else "The scavengers came away from the %s at %s with nothing. Heading home." % [place, where])
	else:
		Game.add_log("Scavengers stripped the %s at %s: %s. Heading home." % [place, where, Game.cost_text(u.carry)])
	_turn_back(u)
	Game.changed.emit()


## The Rust Kings' buildings a stationed scouting party can attack: the one on its own tile and the ones next to it.
func strike_targets(u: Dictionary) -> Array:
	var out := []
	if u.get("job", "") != "scout" or u.get("stage", "") != "station":
		return out
	for c in [u.pos] + Game.neighbors(u.pos):
		if Game.tile(c)["o"] == Data.AI and Game.can_hit(c):
			out.append(c)
	return out


## A stationed scouting party starts an attack on the building at `cell`: a "visit" like a ruin's, with one roll a press.
func begin_strike(uid: int, cell: Vector2i) -> bool:
	var u := unit_by_id(uid)
	if u.is_empty() or not cell in strike_targets(u):
		return false
	var building: String = Game.tile(cell)["b"]
	Game.measure(u.pos)
	u["visit"] = D20Visit.begin_strike(visit_ctx(u), D20.loot_scale, dice, u.survivors, cell, building, Game.building_dc(cell))
	u.stage = "site"
	Game.add_log("%s get ready to attack the %s at %d,%d." % [names_text(u), Data.BUILDINGS[building].name.to_lower(), cell.x, cell.y])
	_sync_visit(u)
	Game.changed.emit()
	return true


## "Continue" after an attack: the building comes down if the roll hit it, the party takes its package (and loses a share of
## what it carries if the roll went badly) and goes back to keeping watch. A party the attack wiped out is gone.
func _finish_strike(u: Dictionary, v: Dictionary) -> void:
	u.erase("visit")
	var cell := Vector2i(int(v.cell[0]), int(v.cell[1]))
	var what: String = Data.BUILDINGS[v.building].name.to_lower() if Data.BUILDINGS.has(v.building) else "building"
	if v.wiped:
		Game.note("survivors_lost", u.crew)
		u.crew = 0
		u.survivors = []
		_lost(u)
		Game.add_log("The party was wiped out attacking the %s at %d,%d." % [what, cell.x, cell.y])
		Game.changed.emit()
		return
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
	if v.destroyed:
		Game.destroy_building(cell)
		Game.add_log("%s destroyed the %s at %d,%d. Relations with the Rust Kings fall by %d." % [names_text(u), what, cell.x, cell.y, Data.RAID_RELATIONS])
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
	u.stage = "back"
	u.path = Game.route(u.mover, u.pos, u.home).slice(1)
	if u.path.is_empty():
		_come_home(u)


func _trade(u: Dictionary) -> void:
	if u.dest == -1:   # the Rust Kings
		var armored: bool = Game.has("cv2") and u.mover == "car"
		if Game.ai["relations"] < 0 and not armored and randf() < 0.35:
			u.crew -= 1
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
	var good: String = Data.TRIBE_GOODS.pick_random()
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
		if u.owner == Data.PLAYER and not u.mover in ["plane", "boat"]:
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
		u["gone"] = true
		return
	u.target = _band_target(u)
	u.path = Game.route("foot", u.pos, u.target).slice(1)
	_advance(u)
	# Reaching a colony's land means an attack on its outskirts
	var near := [u.pos] + Game.neighbors(u.pos)
	if near.any(func(c): return Game.tile(c)["o"] == Data.PLAYER):
		var def := Game.player_troop_defense() + Game.player_wall_defense()
		if randf() * (u.strength + def) < u.strength:
			var loot := {}
			for k in ["grain", "meat", "metal", "gold"]:
				loot[k] = int(Game.res[k] * 0.1)
				Game.res[k] -= loot[k]
			Game.add_log("A raider band hit your outskirts and made off with %s." % Game.cost_text(loot))
			Game.raider_strike(u.pos, u.strength, def)
		else:
			Game.prisoners += 1
			Game.note("prisoners_taken")
			Game.note("bands_driven_off")
			Game.add_log("Your guards drove off a raider band and caught one of them.")
		u["gone"] = true
	elif near.any(func(c): return Game.tile(c)["o"] == Data.AI):
		Game.ai["food"] = maxi(Game.ai["food"] - 3, 0)   # they raid the Rust Kings' stores instead
		u["gone"] = true


func _ambushes() -> void:
	for band in units:
		if band.job != "band" or band.get("gone", false):
			continue
		for u in units:
			if u.owner != Data.PLAYER or u.get("gone", false) or u.mover in ["plane", "boat"]:
				continue
			if Vector2(u.pos - band.pos).length() <= 1.5:
				_fight(band, u)
				break


func _fight(band: Dictionary, u: Dictionary) -> void:
	var name: String = Data.EXPEDITIONS[u.job].name.to_lower()
	var party := party_strength(u)
	if randf() * (party + band.strength) < party:
		band["gone"] = true
		Game.prisoners += 1
		Game.note("prisoners_taken")
		Game.note("bands_driven_off")
		Game.add_log("Your %s fought off a raider band and caught one of them." % name)
		return
	var who := _casualty(u)
	var stolen := "" if u.carry.is_empty() else ", and took " + Game.cost_text(u.carry)
	u.carry = {}
	band.strength += 1
	Game.add_log("A raider band ambushed your %s! %s%s." % [name, who + " was killed" if who != "" else "One killed", stolen])
	if u.crew <= 0:
		_lost(u)


# ---------------------------------------------------------------- tribes

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
		tribes.append(tribe)
		return tribe
	return {}


## Called after the fog updates: log tribes your colony sees for the first time.
func check_discoveries() -> void:
	for t in tribes:
		if not t.found and Game.knows_tile(Data.PLAYER, t.pos):
			t["found"] = true
			Game.add_log("Your people found the %s, a %s." % [t.name, Data.TRIBE_CLASSES[t.class].name.to_lower()])


func known_tribes() -> Array:
	return tribes.filter(func(t): return t.found)


func attack_tribe_status(t: Dictionary) -> String:
	if Game.troops <= 0:
		return "No troops"
	if Game.raided_this_season:
		return "Already attacked this season"
	return ""


func attack_tribe(id: int) -> void:
	var t := tribe_by_id(id)
	if t.is_empty() or attack_tribe_status(t) != "":
		return
	Game.raided_this_season = true
	var att := Game.player_attack(t.pos)
	if randf() * (att + t.strength) < att:
		var loot := {"gold": randi_range(5, 15), "metal": randi_range(5, 10), "meat": randi_range(5, 10)}
		for k in loot:
			Game.res[k] += loot[k]
		Game.prisoners += 2
		Game.note("prisoners_taken", 2)
		Game.note("tribes_scattered")
		tribes.erase(t)
		Game.add_log("You scattered the %s! Took %s and 2 prisoners." % [t.name, Game.cost_text(loot)])
	else:
		var lost := int(ceil(Game.troops * 0.4))
		Game.troops -= lost
		Game.add_log("The %s beat back your attack. %d troops lost." % [t.name, lost])
	Game.changed.emit()


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
	return {"next_id": next_id, "tribes": tribes.map(_pack), "units": units.map(_pack)}


func load_from(data: Dictionary) -> void:
	next_id = int(data.get("next_id", 1))
	tribes = data.get("tribes", []).map(_unpack)
	units = data.get("units", []).map(_unpack)
	for u in units:
		if u.job != "band" and u.stage != "station" and u.stage != "site":
			u.path = Game.route(u.mover, u.pos, u.target if u.stage == "out" else u.home).slice(1)


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
		elif k == "fuel":
			v = float(v)   # the one number that can have a fraction
		elif typeof(v) == TYPE_FLOAT:
			v = int(v)
		elif k in ["carry", "food"]:
			v = Game._ints(v)
			for r in v.keys():
				if not r in Data.RESOURCES:
					v.erase(r)   # scrap and silver are gone from older saves
		elif k == "survivors":
			v = v.map(func(s): return {"name": s["name"], "age": int(s["age"]),
				"traits": s.get("traits", []).filter(func(id): return D20Data.TRAITS.has(id)),   # none in saves from before the d20 rolls
				"injury": s.get("injury", "none"),
				"hunger": int(s["hunger"]), "hp": float(s.get("hp", Data.SURVIVOR_HP)), "dose": float(s.get("dose", 0.0)),
				"hurt": bool(s.get("hurt", false)),
				"face": int(s["face"]) if s.has("face") else hash(s["name"]) & 0x7fffffff})
		out[k] = v
		if k == "visit":
			out[k] = D20Visit.normalize(d[k])
	if not out.has("survivors"):
		out["survivors"] = []   # saves from before named survivors
	if not out.has("rad_days"):
		out["rad_days"] = 0.0   # saves from before radiation
		out["moved"] = false
	if out.get("job", "") == "scout" and not out.has("food"):
		out["food"] = {"grain": Data.SCOUT_PACK}   # saves from before food packs: scouts ate from the stores
	out["path"] = []
	return out
