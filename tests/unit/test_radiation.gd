extends "res://tests/framework/test_case.gd"
## Radiation: where it comes from, what you know about it, and how it poisons a party.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Icons = preload("res://scripts/icons.gd")
const Portrait = preload("res://scripts/portrait.gd")
const Geiger = preload("res://scripts/geiger.gd")

const SEEDS := [1, 2, 3, 7, 11]


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	Game.res["grain"] = 500


## A party of two standing still on `c`, travelling `mover`.
func _party(c: Vector2i, mover := "foot") -> Dictionary:
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, mover, c, c)
	u.survivors = Units._make_crew(2)
	u.crew = 2
	u.stage = "station"
	u.food = {"grain": 100000}   # these tests are about radiation, so nobody goes hungry
	Units.units.append(u)
	return u


func _far_tile() -> Vector2i:
	var hq := Game.home(Data.PLAYER)
	return World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 15 and c.distance_to(hq) < 25 and Game.tile(c)["o"] == Data.NONE)


# ---------------------------------------------------------------- the radiation field

func test_craters_glow_hardest_and_it_fades_with_distance() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		for cat in Game.catastrophes:
			var center := Game.radiation(cat.pos)
			assert_ge(center, Data.RAD_BANDS[4][0], "seed %d: a crater should be extreme, it reads %d" % [sd, center])
			var near := 0.0
			var far := 0.0
			var n_near := 0
			var n_far := 0
			for p in Game._circle(cat.pos, int(cat.radius * 2.0)):
				var d: float = cat.pos.distance_to(p)
				if d > cat.crater + 1 and d < cat.crater + 3:
					near += Game.radiation(p)
					n_near += 1
				elif d > cat.radius * 1.5 and d < cat.radius * 1.9 and cat.kind != "fallout":
					far += Game.radiation(p)
					n_far += 1
			if n_far > 0:
				assert_gt(near / n_near, far / n_far, "seed %d: it should cool off with distance" % sd)


func test_fallout_waste_and_glass_stay_hot() -> void:
	var waste := []
	var glass := []
	for sd in SEEDS:
		World.new_game(sd)
		for t in Game.tiles:
			if t["t"] == "waste":
				waste.append(t["rad"])
			elif t["t"] == "glass":
				glass.append(t["rad"])
	assert_gt(waste.size(), 20)
	assert_gt(glass.size(), 20)
	assert_gt(waste.reduce(func(a, b): return a + b) / waste.size(), 20)
	assert_gt(glass.reduce(func(a, b): return a + b) / glass.size(), 20)


func test_camps_start_clean_and_most_of_the_map_is_safe() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		for camp in [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]:
			for p in Game._circle(camp, Data.START_CLEAR):
				assert_le(Game.radiation(p), 3, "seed %d: %s is too hot near a camp" % [sd, p])
		var safe := 0
		for t in Game.tiles:
			safe += 1 if t["rad"] < Data.RAD_SAFE else 0
		assert_gt(safe / float(Game.tiles.size()), 0.6, "seed %d: most of the wastes should be safe" % sd)


# ---------------------------------------------------------------- what you know

func test_exact_readings_are_hidden_until_a_party_has_been_there() -> void:
	var c: Vector2i = Game.catastrophes[0].pos
	assert_false(Game.is_measured(c))
	var hidden := Game.reading_text(c)
	assert_true(hidden.begins_with("not measured"), hidden)
	assert_false(hidden.contains("%d R/h (" % Game.radiation(c)), "must not give the exact figure away")
	Game.measure(c)
	assert_true(Game.is_measured(c))
	assert_eq(Game.reading_text(c), "%d R/h (%s)" % [Game.radiation(c), Game.rad_band(Game.radiation(c))[0]])


func test_the_estimate_brackets_the_truth() -> void:
	for c in [Game.catastrophes[0].pos, _far_tile(), Game.home(Data.AI) + Vector2i(0, 20)]:
		var r := Game.radiation(c)
		var text := Game.reading_text(c)
		if text.contains("roughly"):
			var range_text := text.split("roughly ")[1].replace(" R/h", "").split("-")
			assert_le(int(range_text[0]), r)
			assert_ge(int(range_text[1]), r)


func test_your_own_land_is_known() -> void:
	assert_true(Game.is_measured(Game.home(Data.PLAYER)))


func test_scouts_measure_every_tile_they_walk() -> void:
	var hq := Game.home(Data.PLAYER)
	var target := _far_tile()
	var path := Game.route("foot", hq, target)
	var off_path := World.find_tile(func(c, t): return c.distance_to(target) > 6 and not path.has(c) and Game.tile(c)["o"] == Data.NONE)
	Units.send("scout", "foot", target)
	for i in 12:
		Units.season_turn()
	for p in path:
		assert_true(Game.is_measured(p), "the party should have measured %s" % p)
	assert_false(Game.is_measured(off_path), "tiles they never visited stay unmeasured")


func test_measurements_are_kept_for_the_whole_run_and_survive_saving() -> void:
	var c := _far_tile()
	Game.measure(c)
	var u := _party(Game.home(Data.PLAYER))
	u.survivors[0].dose = 42.5
	u.survivors[0].hp = 61.0
	Game.save_game("rad_test")
	Units.units = []
	Game.measured.fill(0)
	assert_true(Game.load_game("rad_test"))
	DirAccess.remove_absolute(Game._path("rad_test"))
	assert_true(Game.is_measured(c))
	assert_almost_eq(Units.units[0].survivors[0].dose, 42.5, 0.001)
	assert_almost_eq(Units.units[0].survivors[0].hp, 61.0, 0.001)


func test_radiation_map_toggle() -> void:
	assert_false(Game.show_radiation)
	Game.toggle_radiation_view()
	assert_true(Game.show_radiation)


# ---------------------------------------------------------------- the poison

func test_radiation_does_not_kill_outright_but_you_cant_stay_long() -> void:
	var c := _far_tile()
	Game.tile(c)["rad"] = 60
	var u := _party(c)
	Units.season_turn()
	assert_eq(Units.units.size(), 1, "a season in the hot zone is survivable")
	assert_gt(u.survivors[0].dose, 10.0)
	assert_gt(u.survivors[0].hp, 80.0, "it shouldn't kill outright")
	assert_lt(u.survivors[0].hp, Data.SURVIVOR_HP)
	var seasons := 1
	while not Units.units.is_empty() and seasons < 30:
		Units.season_turn()
		seasons += 1
	assert_true(Units.units.is_empty(), "a long stay is fatal")
	assert_lt(seasons, 15, "it should be fatal within a few seasons at 60 R/h")
	assert_true(Game.log_lines.any(func(l): return l.contains("died of radiation sickness")))


func test_the_hotter_the_tile_the_faster_the_end() -> void:
	var seasons := []
	for rad in [30, 60, 120]:
		Units.units = []
		var c := _far_tile()
		Game.tile(c)["rad"] = rad
		_party(c)
		var n := 0
		while not Units.units.is_empty() and n < 80:
			Units.season_turn()
			n += 1
		seasons.append(n)
	assert_gt(seasons[0], seasons[1])
	assert_gt(seasons[1], seasons[2])
	assert_lt(seasons[2], 8, "the craters themselves are deadly")


func test_background_radiation_is_harmless() -> void:
	var c := _far_tile()
	Game.tile(c)["rad"] = Data.RAD_SAFE
	var u := _party(c)
	for i in 10:
		Units.season_turn()
	assert_eq(u.survivors[0].dose, 0.0)
	assert_eq(u.survivors[0].hp, Data.SURVIVOR_HP)


func test_vehicles_shield_the_people_inside() -> void:
	var c := _far_tile()
	Game.tile(c)["rad"] = 60
	var doses := {}
	for mover in ["foot", "car", "plane"]:
		var u := _party(c, mover)
		Units._expose(u)
		doses[mover] = u.survivors[0].dose
	assert_gt(doses.foot, doses.car)
	assert_gt(doses.car, doses.plane)


func test_poison_lingers_then_wears_off() -> void:
	var c := _far_tile()
	Game.tile(c)["rad"] = 0
	var u := _party(c)
	u.survivors[0].dose = 80.0
	u.survivors[0].hp = 70.0
	Units._expose(u)
	assert_lt(u.survivors[0].hp, 70.0, "the poison keeps working after you leave the hot zone")
	for i in 40:
		Units._expose(u)
		if u.survivors.is_empty():
			break
	if not u.survivors.is_empty():
		assert_lt(u.survivors[0].dose, Data.DOSE_ILL)


func test_a_party_passing_through_picks_up_less_than_one_that_stays() -> void:
	var c := _far_tile()
	Game.tile(c)["rad"] = 60
	var u := _party(c)
	u.moved = true
	u.rad_days = 60.0 * Data.SEASON_DAYS * 0.1   # a tenth of the season in a 60 R/h tile
	Units._expose(u)
	var v := _party(c)
	Units._expose(v)
	assert_lt(u.survivors[0].dose, v.survivors[0].dose)


func test_sickness_shows_in_the_party_line() -> void:
	var s: Dictionary = Units._make_crew(1)[0]
	assert_false(Units.survivor_line(s).contains("sick"))
	s.dose = 60.0
	s.hp = 72.0
	var line := Units.survivor_line(s)
	assert_true(line.contains("radiation sick"), line)
	assert_true(line.contains("72 hp"), line)
	assert_eq(Units.sick_level(s), 2)


# ---------------------------------------------------------------- art and gauge

func test_every_way_of_travel_has_an_icon() -> void:
	for mover in Data.MOVERS:
		var img := Icons.image(mover)
		assert_eq(img.get_size(), Vector2i(Icons.SIZE, Icons.SIZE))
		var opaque := 0
		for y in Icons.SIZE:
			for x in Icons.SIZE:
				opaque += 1 if img.get_pixel(x, y).a > 0.0 else 0
		assert_gt(opaque, 60, "the %s icon is nearly empty" % mover)
	assert_ne(Icons.image("foot").get_data(), Icons.image("car").get_data())


func test_icon_art_rows_are_all_the_same_width() -> void:
	for mover in Icons.ART:
		assert_eq(Icons.ART[mover].size(), Icons.SIZE)
		for row in Icons.ART[mover]:
			assert_eq(row.length(), Icons.SIZE, mover)


func test_sick_survivors_look_different() -> void:
	assert_ne(Portrait.image(99, 30, 0, 2).get_data(), Portrait.image(99, 30, 0, 0).get_data())


func test_geiger_scale_runs_from_zero_to_the_top() -> void:
	assert_eq(Geiger.scale_fraction(0.0), 0.0)
	assert_almost_eq(Geiger.scale_fraction(Data.RAD_MAX), 1.0, 0.001)
	assert_gt(Geiger.scale_fraction(5.0), 0.2, "low readings still move the needle")
	assert_lt(Geiger.scale_fraction(20.0), Geiger.scale_fraction(80.0))
