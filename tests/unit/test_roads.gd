extends "res://tests/framework/test_case.gd"
## Roads and the old highway. The highway is made with the map: ruined, 0.8 times the cost, through every city and over the old bridge, and a party
## walking it rolls for ambushes. Roads are what you and the Rust Kings build: 2 stone and 1 grain a tile, 0.6 times the cost, out over free land
## from your land (or from a road that reaches it), and a road on free land stays free for anyone to use.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

const SEEDS := [3, 7, 11, 21]

var home: Vector2i
var fort: Vector2i


func before_each() -> void:
	_new_map(3)


func _new_map(seed_value: int) -> void:
	World.new_game(seed_value)
	Units.units = []
	Units.tribes = []
	Units.wild_spawns = false
	home = Game.home(Data.PLAYER)
	fort = Game.home(Data.AI)


func assert_between(got, low, high, msg := "") -> void:
	assert_true(got >= low and got <= high, "%s (got %s, wanted %s to %s)" % [msg, got, low, high])


func _cells(pred: Callable) -> Array:
	var out := []
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if pred.call(c, Game.tiles[i]):
			out.append(c)
	return out


func _highway() -> Array:
	return _cells(func(c, t): return t["b"] == "old_road")


## The highway tiles in the order a walk out from the old bridge meets them: the stretch of road the bridge belongs to (the craters break the rest into pieces).
func _from_the_bridge() -> Array:
	var start: Vector2i = _cells(func(c, t): return t["b"] == "old_bridge")[0]
	var seen := {start: true}
	var order := [start]
	var head := 0
	while head < order.size():
		for n in Game.neighbors(order[head]):
			if not seen.has(n) and Game.tile(n)["b"] in ["old_road", "old_bridge"]:
				seen[n] = true
				order.append(n)
		head += 1
	return order


## A plain land tile at least `gap` tiles from home that nothing is on, level and not beside any road, for building tests.
func _plain_tile(near: Vector2i, spare := []) -> Vector2i:
	for r in range(1, 12):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				var c := near + Vector2i(dx, dy)
				if Game.in_bounds(c) and not c in spare and Game.tile(c)["t"] in ["sand", "scrub", "dunes"] and Game.tile(c)["b"] == "" \
						and Game.slopes[Game.idx(c)] == "" and Game.tile(c)["o"] == Data.NONE:
					return c
	return Vector2i(-1, -1)


func _rich() -> void:
	Game.res.merge({"stone": 500, "grain": 500, "wood": 500, "metal": 100, "gold": 100}, true)


# ---------------------------------------------------------------- the buildings

func test_a_road_and_the_old_highway_are_buildings_with_the_planned_numbers() -> void:
	assert_eq(Data.BUILDINGS["road"].cost, {"stone": 2, "grain": 1})
	assert_true(Data.BUILDINGS["road"].road)
	assert_eq(Data.BUILDINGS["old_road"].buildable, false, "nobody builds the old highway")
	assert_true(Data.BUILDINGS["old_road"].highway)
	assert_eq(Data.ROAD.speed, 0.6)
	assert_eq(Data.HIGHWAY.speed, 0.8)
	assert_eq(Data.HIGHWAY.ambush_every, 10)


func test_a_road_tile_takes_0_6_and_a_highway_tile_0_8_of_a_flat_tile_whatever_the_ground() -> void:
	_rich()
	var c := _plain_tile(home + Vector2i(4, 0))
	Game.tile(c)["t"] = "rock"   # rock would cost 1.4 on foot
	Game.tile(c)["b"] = "road"
	for mover in ["foot", "horse", "car"]:
		assert_eq(Game.move_mult(mover, c), 0.6, mover)
	assert_eq(Game.move_mult("boat", c), 0.0, "a boat cannot sail down a road")
	Game.tile(c)["b"] = "old_road"
	for mover in ["foot", "horse", "car"]:
		assert_eq(Game.move_mult(mover, c), 0.8, mover)


func test_a_road_over_a_gentle_slope_is_flat_and_a_war_rig_still_cannot_climb_a_steep_one() -> void:
	var steep: Vector2i = _cells(func(c, t): return Game.slopes[Game.idx(c)] == "steep" and t["t"] != "water" and t["b"] == "")[0]
	Game.tile(steep)["b"] = "old_road"
	assert_eq(Game.move_mult("car", steep), 0.0)
	assert_eq(Game.move_mult("foot", steep), 0.8, "a road is cut into the slope for people on foot")
	var gentle: Vector2i = _cells(func(c, t): return Game.slopes[Game.idx(c)] == "gentle" and t["t"] != "water" and t["b"] == "")[0]
	Game.tile(gentle)["b"] = "road"
	assert_eq(Game.move_mult("car", gentle), 0.6)


# ---------------------------------------------------------------- the old highway

func test_the_old_highway_is_made_with_the_map_and_is_a_long_road() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		assert_between(_highway().size(), 60, 300, "seed %d: highway tiles, the spurs out of the cities included and what the craters took left out" % seed_value)


func test_the_old_highway_comes_to_every_city_but_the_crater_at_its_centre_took_the_road() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for cat in Game.catastrophes:
			assert_ne(Game.tile(Vector2i(cat.pos))["b"], "old_road", "seed %d: nothing is left of the road on the crater at %s" % [seed_value, cat.pos])
			var near := _highway().any(func(c): return Vector2(c).distance_to(Vector2(cat.pos)) <= 8.0)
			assert_true(near, "seed %d: but the highway comes to the city at %s" % [seed_value, cat.pos])


func test_the_old_highway_runs_on_from_both_ends_of_the_old_bridge() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var bridge := _cells(func(c, t): return t["b"] == "old_bridge")
		var onward := {}
		for b in bridge:
			for n in Game.neighbors(b):
				if Game.tile(n)["b"] == "old_road":
					onward[n] = true
		assert_gt(onward.size(), 1, "seed %d: the highway leaves the bridge on each bank" % seed_value)
		var pieces := Game._highway_pieces()
		for n in onward:
			assert_true(pieces.has(n), "seed %d: in a real stretch of road, not a stray tile" % seed_value)


func test_the_old_highway_touches_neither_hq() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for c in _highway():
			assert_gt(c.distance_to(Vector2(home)), 10.0, "seed %d" % seed_value)
			assert_gt(c.distance_to(Vector2(fort)), 10.0, "seed %d" % seed_value)


func test_the_highway_pass_changes_no_random_numbers() -> void:
	seed(99)
	var a := randi()
	seed(99)
	Game._pass_highway()
	assert_eq(randi(), a)


func test_the_highway_is_the_same_for_the_same_map() -> void:
	_new_map(11)
	var first := _highway()
	_new_map(11)
	assert_eq(_highway(), first)


func test_a_trip_along_the_highway_is_quicker_than_over_open_ground() -> void:
	var hw := _from_the_bridge()
	assert_gt(hw.size(), 12, "a good stretch of highway runs on from the bridge")
	var a: Vector2i = hw[0]
	var b: Vector2i = hw[mini(hw.size() - 1, 25)]
	var path := Game.route("foot", a, b)
	assert_false(path.is_empty())
	var days := Game.route_days("foot", path)
	var was := {}
	for c in hw:
		if Game.tile(c)["b"] == "old_road":
			was[c] = true
			Game.tile(c)["b"] = ""
	Game._update_paths_at(was.keys())
	var open_days := Game.route_days("foot", Game.route("foot", a, b))
	assert_lt(days, open_days, "the same trip with the highway worn away takes longer: it is faster than open ground")


# ---------------------------------------------------------------- the ambush rolls

## A seed whose first d20 is `want` (a natural 1 or not).
func _seed_with_d20(want_one: bool) -> int:
	for s in range(1, 400):
		seed(s)
		if (randi_range(1, 20) == 1) == want_one:
			return s
	return -1


func _walker(mover := "foot") -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, mover, home, home)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = ["veteran"]
	Units.units.append(u)
	return u


func test_only_every_tenth_highway_tile_brings_a_roll() -> void:
	var u := _walker()
	var hw := _highway()
	seed(_seed_with_d20(true))
	Game.log_lines = []
	for k in 9:
		assert_false(Units._highway_check(u, hw[k]), "tile %d is not a tenth" % (k + 1))
	assert_eq(int(u.hwy), 9)
	assert_eq(Game.log_lines.size(), 0, "no ambush before the tenth")


func test_a_natural_1_on_the_tenth_tile_is_an_ambush() -> void:
	var u := _walker()
	var hw := _highway()
	for k in 9:
		Units._highway_check(u, hw[k])
	seed(_seed_with_d20(true))
	Game.log_lines = []
	assert_true(Units._highway_check(u, hw[9]))
	assert_true(Game.log_lines.any(func(l): return "lay in wait on the old highway" in l), "the log says so")
	assert_true(Game.log_lines.size() >= 2, "and the fight is told")


func test_any_other_roll_on_the_tenth_tile_is_safe() -> void:
	var u := _walker()
	var hw := _highway()
	for k in 9:
		Units._highway_check(u, hw[k])
	seed(_seed_with_d20(false))
	Game.log_lines = []
	assert_false(Units._highway_check(u, hw[9]))
	assert_eq(Game.log_lines.size(), 0)
	assert_eq(int(u.hwy), 10)


func test_the_count_goes_on_across_seasons_and_the_next_roll_is_at_twenty() -> void:
	var u := _walker()
	var hw := _highway()
	seed(_seed_with_d20(false))
	for k in 20:
		Units._highway_check(u, hw[k])
	assert_eq(int(u.hwy), 20)


func test_roads_and_open_ground_never_roll() -> void:
	_rich()
	var u := _walker()
	var c := _plain_tile(home + Vector2i(3, 0))
	Game.tile(c)["b"] = "road"
	seed(_seed_with_d20(true))
	for k in 30:
		assert_false(Units._highway_check(u, c))
	assert_false(u.has("hwy"))


func test_boats_planes_and_other_peoples_parties_never_roll() -> void:
	var hw := _highway()
	for mover in ["boat", "plane"]:
		var u := _walker(mover)
		seed(_seed_with_d20(true))
		for k in 30:
			assert_false(Units._highway_check(u, hw[k % hw.size()]))
	var theirs: Dictionary = Units._make_unit("caravan", Data.AI, "horse", fort, fort)
	for k in 30:
		assert_false(Units._highway_check(theirs, hw[k]))


func test_a_war_rig_and_a_horseback_party_roll_like_one_on_foot() -> void:
	var hw := _highway()
	for mover in ["foot", "horse", "car"]:
		var u := _walker(mover)
		for k in 9:
			Units._highway_check(u, hw[k])
		seed(_seed_with_d20(true))
		assert_true(Units._highway_check(u, hw[9]), mover)


# ---------------------------------------------------------------- building roads

func test_you_can_build_a_road_on_your_own_land_and_it_stays_yours() -> void:
	_rich()
	var c := home + Vector2i(1, 1)
	Game.tile(c)["t"] = "sand"
	Game.tile(c)["b"] = ""
	Game.slopes[Game.idx(c)] = ""
	assert_eq(Game.tile(c)["o"], Data.PLAYER)
	var stone: int = Game.res.stone
	var grain: int = Game.res.grain
	assert_eq(Game.build_status("road", c), "")
	Game.build("road", c)
	assert_eq(Game.tile(c)["b"], "road")
	assert_eq(Game.tile(c)["o"], Data.PLAYER)
	assert_eq(Game.res.stone, stone - 2)
	assert_eq(Game.res.grain, grain - 1, "the grain feeds the workers")
	assert_eq(Game.move_mult("foot", c), 0.6)


func _edge_of_your_land() -> Vector2i:
	## A free tile touching your land, level, plain and not water
	for c in Game.owned(Data.PLAYER):
		for n in Game.neighbors(c):
			if Game.tile(n)["o"] == Data.NONE and Game.tile(n)["t"] in ["sand", "scrub", "dunes"] and Game.tile(n)["b"] == "" \
					and Game.slopes[Game.idx(n)] == "":
				return n
	return Vector2i(-1, -1)


func test_you_can_build_a_road_on_free_land_beside_your_land_and_the_land_stays_free() -> void:
	_rich()
	var c := _edge_of_your_land()
	assert_true(Game.in_bounds(c))
	assert_eq(Game.build_status("road", c), "")
	Game.build("road", c)
	assert_eq(Game.tile(c)["b"], "road")
	assert_eq(Game.tile(c)["o"], Data.NONE, "free land stays free: anyone can use the road")


func test_a_road_grows_out_a_tile_at_a_time_from_the_last_one() -> void:
	_rich()
	var c := _edge_of_your_land()
	Game.build("road", c)
	# the next tile out touches only the road
	var out := c
	for n in Game.neighbors(c):
		if Game.tile(n)["o"] == Data.NONE and not Game.borders(n, Data.PLAYER) and Game.tile(n)["t"] in ["sand", "scrub", "dunes"] \
				and Game.slopes[Game.idx(n)] == "" and Game.tile(n)["b"] == "":
			out = n
	if out == c:
		skip("no free tile touching only the road on this map")
		return
	assert_eq(Game.build_status("road", out), "", "beside the road you built")
	Game.build("road", out)
	assert_eq(Game.tile(out)["b"], "road")


func test_a_road_cannot_start_in_the_middle_of_nowhere() -> void:
	_rich()
	var far := _plain_tile(home + Vector2i(12, 8))
	assert_eq(Game.build_status("road", far), "Not your land")


func test_a_road_cannot_go_on_water_steep_inclines_enemy_land_or_a_building() -> void:
	_rich()
	var steep: Vector2i = _cells(func(c, t): return Game.slopes[Game.idx(c)] == "steep" and t["t"] != "water" and t["b"] == "")[0]
	Game.tile(steep)["o"] = Data.PLAYER
	assert_eq(Game.build_status("road", steep), "Too steep for a road")
	var water: Vector2i = _cells(func(c, t): return t["t"] == "water" and t["b"] == "" and not t.get("f", false))[0]
	Game.tile(water)["o"] = Data.PLAYER
	assert_eq(Game.build_status("road", water), "Can't build on water")
	var theirs := _edge_of_your_land()
	Game.tile(theirs)["o"] = Data.AI
	assert_eq(Game.build_status("road", theirs), "Not your land")
	assert_eq(Game.build_status("road", home), "Tile already has a building")


func test_a_road_needs_the_stone_and_the_grain() -> void:
	_rich()
	var c := _edge_of_your_land()
	Game.res["stone"] = 1
	assert_true(Game.build_status("road", c).begins_with("Need "))
	Game.res["stone"] = 50
	Game.res["grain"] = 0
	assert_true(Game.build_status("road", c).begins_with("Need "))


func test_a_road_on_your_land_can_be_pulled_down_and_one_on_free_land_cannot() -> void:
	_rich()
	var own := home + Vector2i(1, 1)
	Game.tile(own)["b"] = ""
	var plain := Game.move_mult("foot", own)
	Game.build("road", own)
	assert_eq(Game.move_mult("foot", own), 0.6)
	Game.demolish(own)
	assert_eq(Game.tile(own)["b"], "", "pulled down")
	assert_eq(Game.move_mult("foot", own), plain, "and the ground is as it was")
	var free := _edge_of_your_land()
	Game.build("road", free)
	Game.demolish(free)
	assert_eq(Game.tile(free)["b"], "road", "free land: permanent")
	var old: Vector2i = _highway()[0]
	Game.tile(old)["o"] = Data.PLAYER   # even if somebody owned the tile
	Game.demolish(old)
	assert_eq(Game.tile(old)["b"], "old_road", "nobody pulls the old highway down")


func test_the_road_network_joins_roads_bridges_and_fords_and_the_old_highway() -> void:
	_rich()
	var c := _edge_of_your_land()
	Game.build("road", c)
	var net := Game.road_network(Data.PLAYER)
	assert_true(net.has(c))
	var stretch := _from_the_bridge()
	var far: Vector2i = stretch[stretch.size() - 1]
	assert_false(net.has(far), "the highway is not part of your network until a road reaches it")
	# a road tile of the highway touching your land puts the whole highway in the network
	Game.tile(far)["o"] = Data.NONE
	var beside := far + Vector2i(1, 0)
	Game.tile(beside)["o"] = Data.PLAYER
	var net2 := Game.road_network(Data.PLAYER)
	assert_true(net2.has(far))
	assert_gt(net2.size(), stretch.size() - 3, "and with it the whole stretch of old highway and the bridge it runs from")
	assert_true(net2.has(stretch[0]), "the old bridge too")


func test_once_your_land_touches_the_highway_a_road_can_go_on_from_it() -> void:
	_rich()
	var old := Vector2i(-1, -1)
	var around := []
	for c in _highway():
		var plain := Game.neighbors(c).filter(func(n): return Game.tile(n)["t"] in ["sand", "scrub", "dunes"] and Game.tile(n)["b"] == "" and Game.slopes[Game.idx(n)] == "" and Game.tile(n)["o"] == Data.NONE)
		if plain.size() >= 2:
			old = c
			around = plain
			break
	assert_true(Game.in_bounds(old), "a highway tile with two plain tiles beside it")
	var beside: Vector2i = around[0]
	assert_eq(Game.build_status("road", beside), "Not your land", "the highway does not reach your land yet")
	Game.tile(around[1])["o"] = Data.PLAYER   # your land touches the highway
	assert_true(Game.road_network(Data.PLAYER).has(old), "so the highway is in your network")
	assert_eq(Game.build_status("road", beside), "", "and a road can go on from it")


# ---------------------------------------------------------------- the Rust Kings

func test_the_rust_kings_lay_roads_when_they_can_afford_to() -> void:
	Game.ai["stone"] = 50
	Game.ai["food"] = 50
	var before := _cells(func(c, t): return t["b"] == "road").size()
	Game._ai_roads()
	var after := _cells(func(c, t): return t["b"] == "road").size()
	assert_between(after - before, 1, Data.AI_ROAD.tiles, "up to two tiles a season")
	assert_eq(Game.ai["stone"], 50 - 2 * (after - before))
	assert_eq(Game.ai["food"], 50 - (after - before))


func test_the_rust_kings_wait_with_too_little_stone_or_food() -> void:
	var before := _cells(func(c, t): return t["b"] == "road").size()
	Game.ai["stone"] = Data.AI_ROAD.stone - 1
	Game.ai["food"] = 50
	Game._ai_roads()
	Game.ai["stone"] = 50
	Game.ai["food"] = Data.AI_ROAD.food - 1
	Game._ai_roads()
	assert_eq(_cells(func(c, t): return t["b"] == "road").size(), before)


func test_their_first_road_tile_starts_at_their_own_land() -> void:
	Game.ai["stone"] = 50
	Game.ai["food"] = 50
	Game._ai_roads()
	var roads := _cells(func(c, t): return t["b"] == "road")
	assert_false(roads.is_empty())
	for c in roads:
		assert_true(Game.tile(c)["o"] == Data.AI or Game.road_reaches(c, Data.AI), "joined to their land")


func test_the_rust_kings_road_heads_for_the_old_highway_and_reaches_it() -> void:
	for season in 60:
		Game.ai["stone"] = 50
		Game.ai["food"] = 50
		Game._ai_roads()
	var net := Game.road_network(Data.AI)
	assert_true(net.keys().any(func(c): return Game.tile(c)["b"] == "old_road"), "after enough seasons their road meets the highway")


func test_everyone_uses_the_rust_kings_roads_too() -> void:
	# a march along a road the Rust Kings laid takes your parties less time as well
	var target: Vector2i = Game._ai_road_targets()[0]
	var before := Game.route_days("foot", Game.route("foot", fort, target))
	for season in 60:
		Game.ai["stone"] = 50
		Game.ai["food"] = 50
		Game._ai_roads()
	var after := Game.route_days("foot", Game.route("foot", fort, target))
	assert_lt(after, before, "their road makes the way to the highway quicker for anyone walking it")


func test_a_road_changes_the_routes_parties_take() -> void:
	_rich()
	var a := home + Vector2i(1, 0)
	var path_before := Game.route_days("foot", Game.route("foot", a, a + Vector2i(1, 0)))
	assert_gt(path_before, 0.0)
	Game.tile(a + Vector2i(1, 0))["b"] = "road"
	Game._update_paths_at([a + Vector2i(1, 0)])
	var path_after := Game.route_days("foot", Game.route("foot", a, a + Vector2i(1, 0)))
	assert_lt(path_after, path_before)
