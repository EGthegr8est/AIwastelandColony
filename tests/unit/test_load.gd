extends "res://tests/framework/test_case.gd"
## What a party can carry: goods have weight, each survivor and each vehicle adds capacity, a party
## over its limit walks slower, and nobody carries more than a ceiling's worth.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Dice = preload("res://scripts/dice.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


## A party of `crew` travelling `mover` carrying `carry` and `food`.
func _party(mover := "foot", crew := 3, carry := {}, food := {}, job := "scav") -> Dictionary:
	var u: Dictionary = Units._make_unit(job, Data.PLAYER, mover, hq, hq)
	u.crew = crew
	u.survivors = Units._make_crew(crew)
	u.carry = carry
	u.food = food
	return u


# ---------------------------------------------------------------- weights and capacity

func test_every_good_has_a_weight_and_heavy_things_weigh_more() -> void:
	for r in Data.RESOURCES:
		assert_true(Data.WEIGHT.has(r), "%s needs a weight" % r)
		assert_gt(Data.WEIGHT[r], 0.0)
	assert_gt(Data.WEIGHT["stone"], Data.WEIGHT["grain"])
	assert_ge(Data.WEIGHT["metal"], Data.WEIGHT["fuel"])
	assert_gt(Data.WEIGHT["fuel"], Data.WEIGHT["grain"], "a can of fuel outweighs a sack of grain")
	assert_lt(Data.WEIGHT["gold"], Data.WEIGHT["grain"], "coins are light")


func test_goods_weigh_what_their_parts_weigh() -> void:
	assert_eq(Units.goods_weight({}), 0.0)
	assert_almost_eq(Units.goods_weight({"metal": 5, "gold": 10}), 5 * Data.WEIGHT["metal"] + 10 * Data.WEIGHT["gold"], 0.0001)


func test_a_party_carries_its_food_pack_and_its_haul() -> void:
	var u := _party("foot", 3, {"metal": 3}, {"grain": 4, "veg": 2})
	assert_almost_eq(Units.load_weight(u), 3 * Data.WEIGHT["metal"] + 4 * Data.WEIGHT["grain"] + 2 * Data.WEIGHT["veg"], 0.0001)


func test_a_vehicles_fuel_tank_does_not_count_as_cargo() -> void:
	var u := _party("car", 2)
	u.fuel = 8.0
	assert_eq(Units.load_weight(u), 0.0)


func test_capacity_grows_with_the_size_of_the_party() -> void:
	var last := 0.0
	for crew in [1, 2, 3, 4]:
		var cap := Units.load_capacity(_party("foot", crew))
		assert_almost_eq(cap, crew * Data.CARRY_PER_PERSON, 0.0001)
		assert_gt(cap, last)
		last = cap


func test_horses_and_vehicles_add_capacity_but_not_excessively() -> void:
	var foot := Units.load_capacity(_party("foot", 3))
	var horse := Units.load_capacity(_party("horse", 3))
	var plane := Units.load_capacity(_party("plane", 3))
	var car := Units.load_capacity(_party("car", 3))
	var boat := Units.load_capacity(_party("boat", 3))
	assert_gt(horse, foot)
	assert_gt(plane, horse)
	assert_gt(car, plane)
	assert_gt(boat, car)
	assert_le(horse / foot, 2.0, "a pack horse is worth a couple of people")
	assert_le(car / foot, 3.5)
	assert_le(boat / foot, 4.0, "even a boat is only a few times a walking party")


func test_losing_people_loses_capacity() -> void:
	var u := _party("foot", 3)
	u.crew = 1   # two of them died
	assert_almost_eq(Units.load_capacity(u), Data.CARRY_PER_PERSON, 0.0001)


# ---------------------------------------------------------------- slowing down

func test_no_slowdown_up_to_the_limit() -> void:
	var u := _party("foot", 3)
	assert_eq(Units.load_slowdown(u), 1.0, "empty-handed")
	u.carry = {"grain": int(Units.load_capacity(u))}   # exactly the limit
	assert_eq(Units.load_weight(u), Units.load_capacity(u))
	assert_eq(Units.load_slowdown(u), 1.0, "at the limit is still fine")


func test_past_the_limit_every_step_takes_longer() -> void:
	var u := _party("foot", 3)
	var cap := int(Units.load_capacity(u))
	u.carry = {"grain": cap + cap / 2}   # 50% over
	assert_almost_eq(Units.load_slowdown(u), 1.0 + 0.5 * Data.OVERLOAD_SLOWDOWN, 0.0001)
	u.carry = {"grain": cap * 2}   # double
	assert_almost_eq(Units.load_slowdown(u), 1.0 + 1.0 * Data.OVERLOAD_SLOWDOWN, 0.0001)
	assert_gt(Units.load_slowdown(u), 1.5)


func test_the_slowdown_never_gets_worse_than_the_maximum() -> void:
	var u := _party("foot", 1, {"grain": 100000})
	assert_eq(Units.load_slowdown(u), Data.OVERLOAD_MAX)
	u.crew = 0
	assert_eq(Units.load_slowdown(u), Data.OVERLOAD_MAX, "nobody left to carry it")


func test_a_vehicle_carries_the_same_goods_without_slowing() -> void:
	var goods := {"grain": 45}   # a lot for three people on foot...
	assert_gt(Units.load_slowdown(_party("foot", 3, goods)), 1.0)
	assert_eq(Units.load_slowdown(_party("horse", 3, goods)), 1.0, "...but not with a pack horse")
	assert_eq(Units.load_slowdown(_party("car", 3, goods)), 1.0)


func test_units_that_carry_nothing_are_never_slowed() -> void:
	var band: Dictionary = Units._make_unit("band", Data.NONE, "foot", hq, hq)
	assert_eq(band.crew, 0)
	assert_eq(Units.load_slowdown(band), 1.0)


## A straight road of flat sand, `n` tiles long, for timing a walk.
func _road(n: int) -> Array:
	var path := []
	for i in n:
		var c := Vector2i(5 + i, 5)
		Game.tiles[Game.idx(c)]["t"] = "sand"
		Game.tiles[Game.idx(c)]["b"] = ""
		Game.slopes[Game.idx(c)] = ""
		path.append(c)
	return path


## Seasons it takes `u` to walk `path` (the road's first tile is where it starts).
func _seasons_to_walk(u: Dictionary, path: Array) -> int:
	u.pos = path[0]
	u.path = path.slice(1)
	var seasons := 0
	while seasons < 50:
		seasons += 1
		if Units._advance(u):
			break
	return seasons


func test_an_overloaded_party_really_does_take_longer_to_walk_somewhere() -> void:
	var path := _road(101)   # 100 steps: a day each on foot over flat sand
	var light := _party("foot", 3)
	var heavy := _party("foot", 3, {"grain": int(Units.load_capacity(light)) * 2})   # double the limit
	assert_eq(Units.load_slowdown(heavy), 2.0)
	assert_eq(_seasons_to_walk(light, path), 3, "100 days is 2.5 seasons")
	assert_eq(_seasons_to_walk(heavy, path), 5, "200 days is 5")


func test_a_load_spent_on_the_way_speeds_the_party_up_again() -> void:
	var path := _road(101)
	var u := _party("foot", 3, {}, {"grain": 60})   # a big food pack: double the limit of 30
	assert_eq(Units.load_slowdown(u), 2.0)
	u.food = {"grain": 10}
	assert_eq(Units.load_slowdown(u), 1.0, "eaten down to a light load")
	assert_eq(_seasons_to_walk(u, path), 3)


func test_the_route_preview_counts_the_slowdown() -> void:
	var path := _road(101)
	var plain := Units.arrival_days("foot", path)
	var slowed := Units.arrival_days("foot", path, 2.0)
	assert_almost_eq(slowed[-1], plain[-1] * 2.0, 0.0001)
	var heavy := _party("foot", 3, {"grain": int(Units.load_capacity(_party("foot", 3))) * 2})
	assert_eq(ceili(Units.arrival_days("foot", path, Units.load_slowdown(heavy))[-1] / Data.SEASON_DAYS), _seasons_to_walk(heavy, path),
		"the preview says how long it really takes")


func test_a_heavy_load_means_longer_in_the_radiation() -> void:
	var path := _road(40)
	for c in path:
		Game.tiles[Game.idx(c)]["rad"] = 30
	var light := _party("foot", 3)
	var heavy := _party("foot", 3, {"grain": 90})   # three times the limit: as slow as it gets
	assert_eq(Units.load_slowdown(heavy), Data.OVERLOAD_MAX)
	assert_eq(_seasons_to_walk(light, path), 1)
	assert_eq(_seasons_to_walk(heavy, path), 3, "the same road takes three seasons")
	assert_gt(heavy.rad_days, light.rad_days * 2.5, "and three seasons' worth of exposure on the way")


# ---------------------------------------------------------------- the ceiling

func test_nothing_over_the_ceiling_is_picked_up() -> void:
	var u := _party("foot", 3)
	var room := Data.LOAD_CEILING * Units.load_capacity(u)   # 60
	var goods := {"metal": 50, "gold": 100}   # 100 + 20 = 120 weight, twice the room
	var kept := Units.fit_load(u, goods)
	assert_le(Units.goods_weight(kept), room + 0.0001)
	assert_gt(Units.goods_weight(kept), room - Data.WEIGHT["metal"] - Data.WEIGHT["gold"], "takes as much as it can")
	assert_gt(kept["metal"], 0)
	assert_lt(kept["metal"], 50)
	assert_true(Game.log_lines.any(func(l): return l.contains("can't carry it all") and l.contains("stays behind")))


func test_goods_that_fit_are_taken_whole_and_unremarked() -> void:
	var u := _party("foot", 3)
	var goods := {"metal": 10, "fuel": 5}
	Game.log_lines = []
	assert_eq(Units.fit_load(u, goods), goods)
	assert_true(Game.log_lines.is_empty())


func test_a_party_already_loaded_has_less_room() -> void:
	var u := _party("foot", 3, {}, {"grain": 8})   # the food pack takes 8 of the 60
	var kept := Units.fit_load(u, {"grain": 100})
	var expected := int(Data.LOAD_CEILING * Units.load_capacity(u)) - 8
	assert_ge(kept["grain"], expected - 1)
	assert_le(kept["grain"], expected)


func test_hauling_replaces_what_was_carried_and_trims_to_fit() -> void:
	var u := _party("foot", 3, {"fuel": 5})
	Units._haul(u, {"metal": 200})
	assert_false(u.carry.has("fuel"), "it set off with the new haul")
	assert_le(Units.load_weight(u), Data.LOAD_CEILING * Units.load_capacity(u) + 0.0001)
	# loaded right up to the ceiling, so as slow as a party is allowed to be at the ceiling
	assert_almost_eq(Units.load_slowdown(u), 1.0 + (Data.LOAD_CEILING - 1.0) * Data.OVERLOAD_SLOWDOWN, 0.0001)


func test_losing_the_vehicle_costs_the_cargo_it_carried() -> void:
	var u := _party("car", 2, {"metal": 40}, {}, "scav")   # 80 weight: fine in a war rig (cap 70), too much on foot (cap 20, ceiling 40)
	u.pos = Vector2i(hq.x + 8, hq.y)
	Game.vehicles["car"] = 1
	Units.units.append(u)
	assert_almost_eq(Units.load_slowdown(u), 1.0 + (80.0 / 70.0 - 1.0) * Data.OVERLOAD_SLOWDOWN, 0.0001)
	Units._strand(u)
	assert_eq(u.mover, "foot")
	assert_le(Units.load_weight(u), Data.LOAD_CEILING * Units.load_capacity(u) + 0.0001, "only what two people can carry comes along")
	assert_gt(u.carry["metal"], 0)
	assert_lt(u.carry["metal"], 40)


# ---------------------------------------------------------------- tuning: what the game really hands out

## The weights of `visits` finished visits to safe ruins at this loot scale, by a scout with no traits.
func _haul_weights(scale: float, visits: int) -> Array:
	seed(5)
	var party := [D20.new_scout("Mara", [])]
	var weights := []
	for i in visits:
		var v := D20Visit.begin("safe", {"radiation": 0.0, "party_strength": 3}, scale, Dice.new())
		var guard := 0
		while v.stage != "done" and guard < 30:
			guard += 1
			D20Visit.step(v, Dice.new(), party, {"deeper": "home", "choice": "slip"}.get(v.stage, "roll"))
		weights.append(Units.goods_weight(v.loot))
	return weights


func _share(weights: Array, over: float) -> float:
	return float(weights.filter(func(w): return w > over).size()) / weights.size()


func test_most_ruin_hauls_fit_a_foot_party_and_only_the_big_ones_slow_it() -> void:
	var weights := _haul_weights(D20.loot_scale, 3000)
	var foot := Units.load_capacity(_party("foot", 3))
	assert_lt(_share(weights, foot), 0.3, "most hauls are no trouble")
	assert_gt(_share(weights, foot), 0.03, "but a big find is more than three people carry comfortably")
	assert_lt(_share(weights, Data.LOAD_CEILING * foot), 0.12, "and few are turned away at the ceiling")


func test_horses_and_war_rigs_carry_what_a_ruin_gives() -> void:
	var horse := Units.load_capacity(_party("horse", 3))
	assert_lt(_share(_haul_weights(D20.loot_scale, 2000), horse), 0.12)
	var rig := Units.load_capacity(_party("car", 3))
	assert_lt(_share(_haul_weights(D20.loot_scale * Data.SCAV_CAR_MULT, 2000), rig), 0.12, "a war rig hauls half as much again")


func test_a_lone_scout_can_always_carry_a_full_food_pack() -> void:
	assert_le(Data.SCOUT_PACK * Data.WEIGHT["grain"], Data.CARRY_PER_PERSON, "even with only one of them left")
	for mover in ["foot", "horse", "car", "plane"]:
		var u := _party(mover, 1, {}, {"grain": Data.SCOUT_PACK}, "scout")
		assert_eq(Units.load_slowdown(u), 1.0, mover)


func test_a_caravans_trade_goods_fit_a_foot_party() -> void:
	var u := _party("foot", 2, {}, {}, "caravan")
	var worst := Units.goods_weight({"gold": 5, "metal": 6})
	assert_lt(worst, Units.load_capacity(u))
