extends "res://tests/framework/test_case.gd"
## The craters destroyed the old road long ago: none of it is left on a crater, and near one each tile survives only with the chance
## (distance to the nearest crater tile) / Data.CRATER_WEAR.radius, so there is less and less road the closer you get.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

const SEEDS := [3, 7, 11, 21, 42, 99]


func before_each() -> void:
	_new_map(3)


func _new_map(seed_value: int) -> void:
	World.new_game(seed_value)
	Units.units = []
	Units.tribes = []
	Units.wild_spawns = false


func _craters() -> Array:
	var out := []
	for i in Game.tiles.size():
		if Game.tiles[i]["t"] == "crater":
			out.append(Vector2i(i % Game.w, i / Game.w))
	return out


func _distance_to_a_crater(c: Vector2i, craters: Array) -> float:
	var d := 99.0
	for k in craters:
		d = minf(d, Vector2(c).distance_to(Vector2(k)))
	return d


func _old_road() -> Array:
	var out := []
	for i in Game.tiles.size():
		if Game.tiles[i]["b"] == "old_road":
			out.append(Vector2i(i % Game.w, i / Game.w))
	return out


func test_no_old_road_is_left_on_a_crater() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for c in _old_road():
			assert_ne(Game.tile(c)["t"], "crater", "seed %d at %s" % [seed_value, c])


func test_the_craters_took_some_road_and_only_near_them() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var craters := _craters()
		assert_gt(Game.worn.size(), 10, "seed %d: the craters took a good deal of road" % seed_value)
		for c in Game.worn:
			assert_lt(_distance_to_a_crater(c, craters), float(Data.CRATER_WEAR.radius), "seed %d: only within the radius of a crater" % seed_value)
			assert_eq(Game.tile(c)["b"], "", "and what they took is gone")


func test_the_nearer_a_crater_the_less_road_is_left() -> void:
	# over six maps: of the road that was laid at each distance from a crater, the share that survived goes up as the distance does
	var kept := [0, 0, 0, 0, 0]
	var lost := [0, 0, 0, 0, 0]
	for seed_value in SEEDS:
		_new_map(seed_value)
		var craters := _craters()
		for c in _old_road():
			var d := _distance_to_a_crater(c, craters)
			if d < Data.CRATER_WEAR.radius:
				kept[int(d)] += 1
		for c in Game.worn:
			lost[int(_distance_to_a_crater(c, craters))] += 1
	var share := []
	for k in 5:
		share.append(float(kept[k]) / float(maxi(kept[k] + lost[k], 1)))
	assert_eq(kept[0], 0, "none on a crater")
	assert_lt(share[1], share[3], "closer to a crater less survives (%s)" % [share])
	assert_lt(share[2], share[4], "and again further out (%s)" % [share])
	assert_lt(share[1], 0.45, "next to a crater most of it is gone")
	assert_gt(share[4], 0.6, "at the edge of the reach most of it is still there")


func test_the_wear_changes_no_random_numbers() -> void:
	seed(99)
	var a := randi()
	seed(99)
	Game._pass_crater_wear()
	assert_eq(randi(), a)


func test_the_wear_is_the_same_for_the_same_map() -> void:
	_new_map(11)
	var first := _old_road()
	var lost := Game.worn.duplicate()
	_new_map(11)
	assert_eq(_old_road(), first)
	assert_eq(Game.worn, lost)


func test_the_spurs_forget_the_tiles_the_craters_took() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for s in Game.spurs:
			for c in s.laid:
				assert_false(c in Game.worn, "seed %d" % seed_value)


func test_the_old_bridge_is_far_from_every_crater_so_it_is_untouched() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var craters := _craters()
		for i in Game.tiles.size():
			if Game.tiles[i]["b"] == "old_bridge":
				var c := Vector2i(i % Game.w, i / Game.w)
				assert_gt(_distance_to_a_crater(c, craters), 0.0)
