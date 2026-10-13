extends "res://tests/framework/test_case.gd"
## The Hollow Mile: the first tile of the old highway (or the old bridge it runs over) your scouts see finds it, once a game, and repairing the
## highway: any side can pay a stone to turn a highway tile into a road, which ends the ambush rolls on it.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const World = preload("res://tests/helpers/world.gd")

var home: Vector2i
var found_cells := []
var found_hot := []


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
	home = Game.home(Data.PLAYER)
	found_cells = []
	found_hot = []
	if not Game.hollow_mile_found.is_connected(_on_found):
		Game.hollow_mile_found.connect(_on_found)


func _on_found(cell: Vector2i, hot: bool) -> void:
	found_cells.append(cell)
	found_hot.append(hot)


func _cells(pred: Callable) -> Array:
	var out := []
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if pred.call(c, Game.tiles[i]):
			out.append(c)
	return out


func _highway() -> Array:
	return _cells(func(c, t): return t["b"] == "old_road")


## Your people have seen none of the old highway or the bridge.
func _forget_the_mile() -> void:
	for c in _cells(func(c, t): return t["b"] in ["old_road", "old_bridge"]):
		Game.memory[Data.PLAYER][Game.idx(c)] = null
	Game.hollow_found = false


func _rich() -> void:
	Game.res.merge({"stone": 500, "grain": 500, "wood": 500, "metal": 100, "gold": 100}, true)


## A highway tile with a plain free tile beside it, and that tile.
func _highway_with_a_neighbour() -> Array:
	for c in _highway():
		for n in Game.neighbors(c):
			if Game.tile(n)["t"] in ["sand", "scrub", "dunes"] and Game.tile(n)["b"] == "" and Game.tile(n)["o"] == Data.NONE:
				return [c, n]
	return []


# ---------------------------------------------------------------- finding it

func test_a_new_game_starts_with_the_mile_not_found() -> void:
	assert_false(Game.hollow_found)
	assert_eq(found_cells, [])


func test_the_first_highway_tile_your_scouts_see_finds_the_hollow_mile_once() -> void:
	_forget_the_mile()
	var hw := _highway()
	Game.log_lines = []
	Game.reveal(Data.PLAYER, hw[0], 1)
	Units.check_discoveries()
	assert_true(Game.hollow_found)
	assert_eq(found_cells.size(), 1, "the signal for the picture, once")
	assert_true(hw[0].distance_to(found_cells[0]) <= 2.0, "at a tile of it")
	assert_true(Game.log_lines.any(func(l): return "Hollow Mile" in l), "and the log says so")
	Game.reveal(Data.PLAYER, hw[hw.size() - 1], 1)
	Units.check_discoveries()
	assert_eq(found_cells.size(), 1, "never twice")


func test_seeing_a_tile_of_the_old_bridge_counts_too() -> void:
	_forget_the_mile()
	var bridge: Vector2i = _cells(func(c, t): return t["b"] == "old_bridge")[0]
	Game.reveal(Data.PLAYER, bridge, 0)
	Units.check_discoveries()
	assert_true(Game.hollow_found)
	assert_eq(found_cells.size(), 1)


func test_nothing_else_on_the_map_finds_it() -> void:
	_forget_the_mile()
	Game.reveal(Data.PLAYER, home, 6)
	Units.check_discoveries()
	assert_false(Game.hollow_found, "the highway is far from your own land")
	assert_eq(found_cells, [])


func test_the_rust_kings_seeing_the_highway_does_not_find_it_for_you() -> void:
	_forget_the_mile()
	Game.reveal(Data.AI, _highway()[0], 3)
	Units.check_discoveries()
	assert_false(Game.hollow_found)


func test_a_party_walking_into_sight_of_the_highway_finds_it_through_the_fog() -> void:
	_forget_the_mile()
	var scout: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", _highway()[0], home)
	Units.units.append(scout)
	Game.update_fog()
	assert_true(Game.hollow_found)
	assert_eq(found_cells.size(), 1)


func test_a_new_game_forgets_it() -> void:
	_forget_the_mile()
	Game.reveal(Data.PLAYER, _highway()[0], 1)
	Units.check_discoveries()
	assert_true(Game.hollow_found)
	_new_map(7)
	assert_false(Game.hollow_found)


func test_the_find_is_saved_and_a_loaded_game_does_not_show_it_again() -> void:
	_forget_the_mile()
	Game.reveal(Data.PLAYER, _highway()[0], 1)
	Units.check_discoveries()
	Game.save_game("hollow_test")
	_new_map(21)
	assert_false(Game.hollow_found)
	assert_true(Game.load_game("hollow_test"))
	assert_true(Game.hollow_found)
	assert_eq(found_cells.size(), 0, "no picture for a game you already found it in")
	Game.update_fog()
	assert_eq(found_cells.size(), 0)


func test_an_unfound_mile_is_still_unfound_after_loading() -> void:
	_forget_the_mile()
	Game.save_game("hollow_test")
	_new_map(21)
	assert_true(Game.load_game("hollow_test"))
	assert_false(Game.hollow_found)
	Game.reveal(Data.PLAYER, _highway()[0], 1)
	Units.check_discoveries()
	assert_true(Game.hollow_found, "it can still be found")


func test_the_picture_data_has_a_day_a_night_and_a_fallout_version() -> void:
	assert_eq(Data.HOLLOW_MILE.day, "res://art/hollow_mile_day.png")
	assert_eq(Data.HOLLOW_MILE.night, "res://art/hollow_mile_night.png")
	assert_eq(Data.HOLLOW_MILE.fallout, "res://art/hollow_mile_fallout.png")
	assert_eq(Data.HOLLOW_MILE.ratio, 1152.0 / 768.0)
	assert_eq(Data.HOLLOW_MILE.rad_high, Data.RAD_BANDS[3][0], "high radiation is the bottom of the High band")


func test_all_three_pictures_are_in_the_project_at_the_size_the_screen_expects() -> void:
	for version in ["day", "night", "fallout"]:
		var pic: Texture2D = Sprites.picture(Data.HOLLOW_MILE[version])
		assert_not_null(pic, version)
		assert_eq(pic.get_size(), Vector2(1152, 768), version)


## The average colour of a picture, sampled across it.
func _mean_colour(version: String) -> Color:
	var img: Image = Sprites.picture(Data.HOLLOW_MILE[version]).get_image()
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	for y in range(0, img.get_height(), 24):
		for x in range(0, img.get_width(), 24):
			var p := img.get_pixel(x, y)
			r += p.r
			g += p.g
			b += p.b
			n += 1
	return Color(r / n, g / n, b / n)


func test_the_files_are_the_right_way_round() -> void:
	var day := _mean_colour("day")
	var night := _mean_colour("night")
	var fallout := _mean_colour("fallout")
	# the day picture is the grey overcast one: its red, green and blue are close together
	assert_lt(absf(day.r - day.b), 0.25, "day is grey (%s)" % [day])
	assert_gt(day.g, 0.4, "and fairly light (%s)" % [day])
	# the night picture is the orange dusk one: red well above green and blue
	assert_gt(night.r, night.g + 0.03, "night is the orange dusk (%s)" % [night])
	assert_gt(night.r, night.b, "and not blue (%s)" % [night])
	# the high-radiation picture is the green moonlit one: green above red and blue, and dark
	assert_gt(fallout.g, fallout.r + 0.1, "the high-radiation one is green (%s)" % [fallout])
	assert_gt(fallout.g, fallout.b + 0.1, "and not blue (%s)" % [fallout])
	assert_lt(fallout.g, 0.45, "and dark (%s)" % [fallout])


# ---------------------------------------------------------------- the radiation the finders take

## A party of yours standing on the first tile of the highway, in sight of it, on ground with `rad` R/h.
func _find_with(mover: String, rad: int) -> void:
	_forget_the_mile()
	var spot: Vector2i = _highway()[0]
	Game.tile(spot)["rad"] = rad
	var party: Dictionary = Units._make_unit("scout", Data.PLAYER, mover, spot, home)
	Units.units.append(party)
	Game.update_fog()


func test_a_party_on_cool_ground_finds_it_without_the_fallout_picture() -> void:
	_find_with("foot", 10)
	assert_eq(found_hot, [false])


func test_a_party_standing_in_high_radiation_makes_it_a_fallout_find() -> void:
	_find_with("foot", 80)
	assert_eq(found_hot, [true])


func test_the_line_is_the_bottom_of_the_high_band() -> void:
	_find_with("foot", Data.HOLLOW_MILE.rad_high - 1)
	assert_eq(found_hot, [false])
	_new_map(3)
	_find_with("foot", Data.HOLLOW_MILE.rad_high)
	assert_eq(found_hot, [true])


func test_a_war_rig_shields_its_crew_so_the_same_ground_is_not_enough() -> void:
	_find_with("car", 80)   # a rig lets half of it through: 40 R/h
	assert_eq(found_hot, [false])
	_new_map(3)
	_find_with("car", 100)   # 50 R/h
	assert_eq(found_hot, [true])


func test_a_find_made_by_nobodys_sight_is_never_a_fallout_find() -> void:
	_forget_the_mile()
	Game.tile(_highway()[0])["rad"] = 150
	Game.reveal(Data.PLAYER, _highway()[0], 1)   # a flight or a building's sight, no party there
	Units.check_discoveries()
	assert_eq(found_hot, [false])


func test_only_a_party_that_can_see_the_highway_counts() -> void:
	_forget_the_mile()
	var spot: Vector2i = _highway()[0]
	var far := spot + Vector2i(30, 0)
	if not Game.in_bounds(far):
		far = spot - Vector2i(30, 0)
	Game.tile(far)["rad"] = 150
	var party: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", far, home)
	Units.units.append(party)
	Game.reveal(Data.PLAYER, spot, 1)
	Units.check_discoveries()
	assert_eq(found_hot, [false], "a hot party somewhere else did not find it")


# ---------------------------------------------------------------- repairing the highway

func test_any_side_can_pay_a_stone_to_repair_a_tile() -> void:
	assert_eq(Data.HIGHWAY.repair, {"stone": 1})


func test_a_tile_out_in_the_wastes_cannot_be_repaired_until_your_road_or_land_reaches_it() -> void:
	_rich()
	var hw := _highway()
	assert_eq(Game.repair_status(hw[0]), "Not joined to your land or a road of yours")
	assert_eq(Game.repair_status(home), "Not part of the old highway", "only the highway can be repaired")


func test_a_tile_beside_your_land_can_be_repaired_and_enemy_land_cannot() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	assert_eq(pair.size(), 2)
	Game.tile(pair[1])["o"] = Data.PLAYER   # your land touches the highway
	assert_eq(Game.repair_status(pair[0]), "")
	Game.tile(pair[0])["o"] = Data.AI
	assert_eq(Game.repair_status(pair[0]), "Not your land")


func test_repairing_needs_the_stone() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	Game.tile(pair[1])["o"] = Data.PLAYER
	Game.res["stone"] = 0
	assert_true(Game.repair_status(pair[0]).begins_with("Need "))
	Game.repair(pair[0])
	assert_eq(Game.tile(pair[0])["b"], "old_road", "nothing happens without the stone")


func test_repairing_costs_a_stone_and_makes_a_road_that_never_ambushes() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	Game.tile(pair[1])["o"] = Data.PLAYER
	var c: Vector2i = pair[0]
	assert_eq(Game.move_mult("foot", c), 0.8)
	var stone: int = Game.res["stone"]
	Game.repair(c)
	assert_eq(Game.res["stone"], stone - 1)
	assert_eq(Game.tile(c)["b"], "road")
	assert_eq(Game.tile(c)["o"], Data.NONE, "free land stays free")
	assert_eq(Game.move_mult("foot", c), 0.6, "quicker than the highway was")
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", c, home)
	seed(1)
	for k in 40:
		assert_false(Units._highway_check(u, c), "a repaired tile never rolls")
	assert_false(u.has("hwy"))
	assert_true(Game.log_lines.any(func(l): return "Repaired a stretch" in l))


func test_after_a_repair_the_next_highway_tile_is_within_reach() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	Game.tile(pair[1])["o"] = Data.PLAYER
	var c: Vector2i = pair[0]
	var next := Vector2i(-1, -1)
	for n in Game.neighbors(c):
		if Game.tile(n)["b"] == "old_road" and not Game.borders(n, Data.PLAYER):
			next = n
			break
	if next.x < 0:
		return   # this stretch of the map has no second highway tile out of reach to test with
	assert_eq(Game.repair_status(next), "Not joined to your land or a road of yours" if not Game.road_reaches(next, Data.PLAYER) else "")
	Game.repair(c)
	assert_eq(Game.repair_status(next), "", "the repaired road joins the next tile to your network")


func test_a_repaired_tile_on_free_land_is_permanent_and_one_on_your_land_can_be_pulled_down() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	Game.tile(pair[1])["o"] = Data.PLAYER
	var c: Vector2i = pair[0]
	Game.repair(c)
	Game.demolish(c)
	assert_eq(Game.tile(c)["b"], "road", "a road on free land cannot be pulled down")
	Game.tile(c)["o"] = Data.PLAYER
	Game.demolish(c)
	assert_eq(Game.tile(c)["b"], "", "on your own land it can")


func test_the_old_highway_cannot_be_pulled_down_even_on_your_land() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	Game.tile(pair[0])["o"] = Data.PLAYER
	Game.demolish(pair[0])
	assert_eq(Game.tile(pair[0])["b"], "old_road")


func test_repairing_a_tile_makes_routes_follow_it() -> void:
	_rich()
	var pair := _highway_with_a_neighbour()
	Game.tile(pair[1])["o"] = Data.PLAYER
	var c: Vector2i = pair[0]
	var before := Game.route_days("foot", [pair[1], c])
	Game.repair(c)
	assert_lt(Game.route_days("foot", [pair[1], c]), before)


func test_the_rust_kings_repair_the_highway_tiles_that_lie_on_their_road_and_only_those() -> void:
	# their road meets the highway after about 40 seasons of two tiles; from there a tile of it on their way costs one stone and no food
	var before := _highway().size()
	for season in 200:
		Game.ai["stone"] = 60
		Game.ai["food"] = 60
		Game._ai_roads()
	var repaired := before - _highway().size()
	assert_gt(repaired, 0, "some of the old highway is theirs to use as a road now")
	assert_lt(repaired, before / 2, "but only the stretch on their way, not the whole highway")
	assert_eq(_highway().size() + _cells(func(c, t): return t["b"] == "road").size() >= before, true, "every repaired tile is a road")
