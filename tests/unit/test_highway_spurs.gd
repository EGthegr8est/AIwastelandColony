extends "res://tests/framework/test_case.gd"
## The old highway frays out into the wastes: from the centres of the cities a few spurs run out in directions that point at no other city, a solid stretch
## of real highway and then fragments with gaps between them, until nothing is left. Scouts who see a fragment can follow it to the highway. (The craters
## at the cities' centres took the road around them: tests/unit/test_crater_wear.gd.)

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

const SEEDS := [3, 7, 11, 21, 42, 99]

var found_cells := []


func before_each() -> void:
	_new_map(3)


func after_each() -> void:
	if Game.hollow_mile_found.is_connected(_on_found):
		Game.hollow_mile_found.disconnect(_on_found)


func _new_map(seed_value: int) -> void:
	World.new_game(seed_value)
	Units.units = []
	Units.tribes = []
	Units.wild_spawns = false
	found_cells = []
	if not Game.hollow_mile_found.is_connected(_on_found):
		Game.hollow_mile_found.connect(_on_found)


func _on_found(cell: Vector2i, _hot: bool) -> void:
	found_cells.append(cell)


func _spur_tiles() -> Array:
	var out := []
	for s in Game.spurs:
		out.append_array(s.laid)
	return out


## The tiles of the spurs that lie in no real stretch of road: the fragments out in the wastes.
func _fragments() -> Array:
	var pieces := Game._highway_pieces()
	return _spur_tiles().filter(func(c): return not pieces.has(c))


func _cities() -> Array:
	return Game.catastrophes.map(func(cat): return Vector2i(cat.pos))


# ---------------------------------------------------------------- what is laid

func test_every_map_has_a_few_spurs_out_of_its_cities() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		assert_gt(Game.spurs.size(), 2, "seed %d has a few spurs" % seed_value)
		assert_lt(Game.spurs.size(), Game.catastrophes.size() * Data.SPURS.per_city[1] + 1, "seed %d: no more than the most each city can have" % seed_value)
		for s in Game.spurs:
			assert_has(_cities(), s.city)


func test_every_tile_of_a_spur_is_old_highway() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for c in _spur_tiles():
			assert_eq(Game.tile(c)["b"], "old_road", "seed %d at %s" % [seed_value, c])


func test_spurs_reach_out_of_the_cities_into_the_wastes() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var reaching := 0
		for s in Game.spurs:
			for c in s.laid:
				if Vector2(c).distance_to(Vector2(s.city)) >= 8.0:
					reaching += 1
					break
		assert_gt(reaching, 1, "seed %d: a few spurs run out well past the crater" % seed_value)
		assert_gt(_spur_tiles().size(), 15, "seed %d" % seed_value)


func test_a_city_has_at_most_two_spurs_and_none_goes_the_same_way_twice() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for city in _cities():
			var headings := []
			for s in Game.spurs:
				if s.city == city:
					assert_false(s.heading in headings, "seed %d: a heading is used once" % seed_value)
					headings.append(s.heading)
			assert_lt(headings.size(), Data.SPURS.per_city[1] + 1)


func test_spurs_point_away_from_every_other_city() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for s in Game.spurs:
			for other in _cities():
				if other != s.city:
					var to := Vector2(other - s.city).normalized()
					assert_lt(to.dot(Vector2(s.heading)), Data.SPURS.away + 0.0001, "seed %d: no city lies that way" % seed_value)


func test_a_spur_stays_a_little_way_out_and_never_runs_on_for_ever() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for s in Game.spurs:
			for c in s.laid:
				assert_lt(Vector2(c).distance_to(Vector2(s.city)), 40.0, "seed %d: it frays away within a few dozen tiles" % seed_value)


func test_spurs_keep_away_from_the_bases() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for c in _spur_tiles():
			for base in [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]:
				assert_gt(Vector2(c).distance_to(Vector2(base)), float(Data.SPURS.keep) - 0.01, "seed %d" % seed_value)


func test_spurs_never_cover_water() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for c in _spur_tiles():
			assert_ne(Game.tile(c)["t"], "water")


func test_there_are_fragments_out_in_the_wastes_on_every_map() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		assert_gt(_fragments().size(), 2, "seed %d has road fragments with no real road beside them" % seed_value)


func test_a_fragment_is_a_stretch_of_fewer_than_six_tiles_of_road() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var pieces := Game._highway_pieces()
		for c in _fragments():
			assert_false(pieces.has(c))
			var near := 0
			for n in Game.neighbors(c):
				if Game._carries_road_tile(n):
					near += 1
			assert_lt(near, 3, "seed %d: a bit of road, not a junction" % seed_value)


func test_the_spurs_change_no_random_numbers_and_are_the_same_for_the_same_map() -> void:
	seed(99)
	var a := randi()
	seed(99)
	Game._pass_spurs()
	assert_eq(randi(), a)
	_new_map(11)
	var first := Game.spurs.duplicate(true)
	_new_map(11)
	assert_eq(Game.spurs, first)


# ---------------------------------------------------------------- how they play

func test_a_scout_who_sees_a_fragment_finds_the_hollow_mile() -> void:
	var fragment: Vector2i = _fragments()[0]
	for c in _spur_tiles() + Game._hollow_tiles():
		Game.memory[Data.PLAYER][Game.idx(c)] = null
	Game.hollow_found = false
	var scout: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", fragment, Game.home(Data.PLAYER))
	Units.units.append(scout)
	Game.update_fog()
	assert_true(Game.hollow_found)
	assert_eq(found_cells.size(), 1)


func test_the_rust_kings_never_head_for_a_fragment() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var pieces := Game._highway_pieces()
		var target: Vector2i = Game._ai_road_targets()[0]
		assert_true(pieces.has(target), "seed %d: their road heads for a real stretch of the highway" % seed_value)
		assert_eq(Game.tile(target)["b"], "old_road")


func test_a_fragment_cannot_be_repaired_until_a_road_reaches_it() -> void:
	var fragment: Vector2i = _fragments()[0]
	Game.res.merge({"stone": 100}, true)
	assert_eq(Game.repair_status(fragment), "Not joined to your land or a road of yours")
