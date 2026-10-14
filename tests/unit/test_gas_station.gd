extends "res://tests/framework/test_case.gd"
## The ruined gas station stands by the old highway: within Data.GAS_STATION.reach tiles of one of its tiles (touching it where there is room), never over it, and still
## every other rule of a site (clear of the camps and of other sites, on open ground).

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

const SEEDS := [3, 7, 11, 21, 42, 99, 5, 13, 17, 31, 2, 8, 64, 100]


func _anchor() -> Vector2i:
	var found := World.find_tile(func(c, t): return t["b"] == "poi_gas_station")
	return found   # the first tile in reading order is the top-left one


func _sites(kind: String) -> Array:
	return Game.tiles.filter(func(t): return t["b"] == "poi_" + kind)


func test_the_gas_station_is_beside_the_highway_on_every_map() -> void:
	var touching := 0
	for seed_value in SEEDS:
		World.new_game(seed_value)
		var highway := Game.tiles.filter(func(t): return t["b"] == "old_road").size()
		assert_gt(highway, 20, "seed %d has a highway" % seed_value)
		var at := _anchor()
		assert_eq(_sites("gas_station").size(), 4, "seed %d: one site of four tiles" % seed_value)
		var gap := Game.highway_gap(at)
		assert_le(gap, Data.GAS_STATION.reach, "seed %d: the gas station is %d tiles from the highway" % [seed_value, gap])
		if gap == 1:
			touching += 1
	assert_ge(touching, SEEDS.size() * 2 / 3, "most touch it: %d of %d" % [touching, SEEDS.size()])


func test_it_never_stands_on_the_highway() -> void:
	for seed_value in SEEDS:
		World.new_game(seed_value)
		var at := _anchor()
		for p in Game.poi_footprint(at):
			assert_eq(Game.tile(p)["b"], "poi_gas_station", "seed %d at %s" % [seed_value, p])
			assert_ne(Game.tile(p)["b"], "old_road")
		# and no highway tile was swallowed: every old_road tile still has a road under it
		for i in Game.tiles.size():
			if Game.tiles[i]["b"] == "old_road":
				assert_false(Game.tiles[i]["t"] == "water")


func test_it_keeps_every_other_rule_of_a_site() -> void:
	for seed_value in SEEDS:
		World.new_game(seed_value)
		var at := _anchor()
		for p in Game.poi_footprint(at):
			assert_has(Data.POI_TERRAIN, Game.tile(p)["t"], "seed %d" % seed_value)
			assert_eq(Game.tile(p)["o"], Data.NONE)
			assert_ne(Game.tile(p)["t"], "waste", "only the chemical dump stands on fallout")
		for b in Game.bases.values():
			assert_ge(Vector2(at).distance_to(Vector2(b)), float(Data.POI_BASE_GAP), "seed %d: clear of the camps" % seed_value)
		for kind in Game.poi_sites:
			if kind == "gas_station":
				continue
			var other: Vector2i = Game.poi_sites[kind]
			assert_ge(maxi(absi(at.x - other.x), absi(at.y - other.y)), Data.POI_GAP, "seed %d: clear of the %s" % [seed_value, kind])


func test_a_station_that_moved_leaves_the_ground_it_stood_on_as_it_was() -> void:
	for seed_value in SEEDS:
		World.new_game(seed_value)
		assert_eq(_sites("gas_station").size(), 4, "seed %d: no second site left behind" % seed_value)
		assert_eq(Game.tiles.filter(func(t): return str(t["b"]).begins_with("poi_")).size() % 4, 0, "every site still has its four tiles")


func test_the_gap_counts_tiles_from_the_highway() -> void:
	World.new_game(7)
	var at := Vector2i(60, 30)
	for dx in range(-6, 8):
		for dy in range(-6, 8):
			var c := at + Vector2i(dx, dy)
			if Game.tile(c)["b"] == "old_road":
				Game.tile(c)["b"] = ""
	assert_eq(Game.highway_gap(at), 99, "none near")
	Game.tile(at + Vector2i(3, 0))["b"] = "old_road"   # the site is (60,30)-(61,31): this is 2 tiles to the right of it
	assert_eq(Game.highway_gap(at), 2)
	Game.tile(at + Vector2i(2, 1))["b"] = "old_road"
	assert_eq(Game.highway_gap(at), 1, "touching")
	Game.tile(at + Vector2i(2, 1))["b"] = ""
	Game.tile(at + Vector2i(-1, -1))["b"] = "old_road"
	assert_eq(Game.highway_gap(at), 1, "a corner counts")
	Game.tile(at + Vector2i(-1, -1))["b"] = ""
	Game.tile(at + Vector2i(3, 0))["b"] = ""
	Game.tile(at + Vector2i(0, 5))["b"] = "old_road"
	assert_eq(Game.highway_gap(at), 4)
	Game.tile(at + Vector2i(0, 5))["b"] = ""
	Game.tile(at + Vector2i(0, 6))["b"] = "old_road"
	assert_eq(Game.highway_gap(at), 99, "five tiles away is not beside it")


func test_the_maps_are_otherwise_the_same_as_before() -> void:
	# the move has random numbers of its own: the same seed makes the same radiation, ruins and so on
	World.new_game(7)
	var rad := Game.tiles.map(func(t): return t["rad"])
	var ruins := Game.tiles.filter(func(t): return t["t"] == "ruins").size()
	World.new_game(7)
	assert_eq(Game.tiles.map(func(t): return t["rad"]), rad)
	assert_eq(Game.tiles.filter(func(t): return t["t"] == "ruins").size(), ruins)
