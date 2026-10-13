extends "res://tests/framework/test_case.gd"
## Ground speeds: every kind of ground has a speed for foot, horseback and war rigs (Data.TERRAIN_SPEED), it multiplies with the slope's
## cost, and the route finder, the day counts and the party's trip all follow it. Boats and planes ignore the ground.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(3)
	Units.units = []
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


## A tile of the given ground with the given slope ("" for none, or "gentle" or "steep"), made by changing a plain land tile.
func _tile_of(ground: String, slope := "") -> Vector2i:
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		var t: Dictionary = Game.tiles[i]
		if t["t"] in ["sand", "scrub", "dunes"] and t["b"] == "" and Game.slopes[i] == slope and c.distance_to(Vector2(hq)) > 6:
			t["t"] = ground
			return c
	return Vector2i(-1, -1)


func test_every_ground_but_the_river_has_a_speed_for_foot_horse_and_war_rig() -> void:
	for id in Data.TERRAIN:
		if id == "water":
			continue
		assert_true(Data.TERRAIN_SPEED.has(id), id)
		for mover in ["foot", "horse", "car"]:
			assert_true(Data.TERRAIN_SPEED[id].has(mover), "%s for %s" % [id, mover])
			assert_ge(Data.TERRAIN_SPEED[id][mover], 1.0, "nothing is quicker than sand yet: %s %s" % [id, mover])
	assert_false(Data.TERRAIN_SPEED.has("water"), "the river has its own rules")


func test_sand_is_the_baseline_and_rock_is_the_slowest_on_foot() -> void:
	for mover in ["foot", "horse", "car"]:
		assert_eq(Data.TERRAIN_SPEED["sand"][mover], 1.0)
	for id in Data.TERRAIN_SPEED:
		assert_le(Data.TERRAIN_SPEED[id]["foot"], Data.TERRAIN_SPEED["rock"]["foot"], id)
		assert_le(Data.TERRAIN_SPEED[id]["car"], Data.TERRAIN_SPEED["rock"]["car"], id)


func test_a_war_rig_is_hit_harder_by_rough_ground_than_a_party_on_foot() -> void:
	for id in ["dunes", "trees", "grove", "ruins", "rock"]:
		assert_gt(Data.TERRAIN_SPEED[id]["car"], Data.TERRAIN_SPEED[id]["foot"], id)


func test_a_tile_costs_the_ground_times_the_slope() -> void:
	var rock := _tile_of("rock")
	assert_eq(Game.move_mult("foot", rock), 1.4)
	assert_eq(Game.move_mult("horse", rock), 1.6)
	assert_eq(Game.move_mult("car", rock), 2.0)
	var steep_rock := _tile_of("rock", "steep")
	assert_almost_eq(Game.move_mult("foot", steep_rock), 4.0 * 1.4, 0.0001, "a steep incline on rock is the slowest tile there is")
	assert_almost_eq(Game.move_mult("horse", steep_rock), 3.0 * 1.6, 0.0001)
	assert_eq(Game.move_mult("car", steep_rock), 0.0, "a war rig still cannot climb it")
	var gentle_trees := _tile_of("trees", "gentle")
	assert_almost_eq(Game.move_mult("foot", gentle_trees), 1.5 * 1.3, 0.0001)
	var sand := _tile_of("sand")
	assert_eq(Game.move_mult("foot", sand), 1.0)


func test_boats_and_planes_ignore_the_ground() -> void:
	var rock := _tile_of("rock")
	assert_eq(Game.move_mult("plane", rock), 1.0)
	assert_eq(Game.move_mult("boat", rock), 0.0, "a boat still cannot sail over land")
	for id in Data.TERRAIN_SPEED:
		assert_eq(Game.ground_speed(id, "boat"), 1.0)
		assert_eq(Game.ground_speed(id, "plane"), 1.0)


func test_settlements_always_have_a_way_in_at_the_plain_cost() -> void:
	assert_eq(Game.move_mult("foot", hq), 1.0)
	assert_eq(Game.move_mult("car", hq), 1.0)


func test_a_party_walks_slower_across_forest_than_across_sand() -> void:
	var start := _tile_of("sand")
	var path := []
	for k in 6:
		path.append(start + Vector2i(k, 0))
	for k in 6:
		Game.tile(path[k])["t"] = "sand"
		Game.tile(path[k])["b"] = ""
		Game.slopes[Game.idx(path[k])] = ""   # level, so only the ground differs
	var open := Units.arrival_days("foot", path)
	for k in range(1, 6):
		Game.tile(path[k])["t"] = "grove"
	var forest := Units.arrival_days("foot", path)
	assert_almost_eq(open[5], 5.0, 0.001)
	assert_almost_eq(forest[5], 5.0 * 1.3, 0.001)


func test_the_speed_text_names_the_movers_that_are_slowed() -> void:
	assert_eq(Game.speed_text("sand"), "")
	assert_eq(Game.speed_text("rock"), "on foot 1.4x, horseback 1.6x, war rig 2.0x slower")
	assert_eq(Game.speed_text("scrub"), "on foot 1.1x, horseback 1.1x, war rig 1.2x slower")
	assert_eq(Game.speed_text("water"), "")


func test_the_trip_numbers_in_the_plan_hold_for_a_nearby_ruin() -> void:
	# trips to the nearest ruins take a few days longer, not a season longer
	var ruins := []
	for i in Game.tiles.size():
		if Game.tiles[i]["t"] == "ruins":
			ruins.append(Vector2i(i % Game.w, i / Game.w))
	ruins.sort_custom(func(a, b): return a.distance_to(hq) < b.distance_to(hq))
	var days := 0.0
	var count := 0
	for r in ruins.slice(0, 8):
		var path := Game.route("foot", hq, r)
		if not path.is_empty():
			days += Game.route_days("foot", path)
			count += 1
	assert_gt(count, 0)
	assert_lt(days / count, Data.SEASON_DAYS, "a nearby ruin is less than a season away on foot")
