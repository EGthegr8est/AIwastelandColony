extends "res://tests/framework/test_case.gd"
## Crossing the river. It is a wall for everything on the ground; boats and planes pass. The map gets an old bridge near the middle (one
## tile wide, every kind of ground party can use it), fords that foot and horseback parties can wade, and you can build bridges out from
## your own bank. The map pass (Game._pass_crossings) also guarantees that your home can reach the fort and Dustwell.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

const SEEDS := [1, 3, 5, 7, 11, 21, 42, 99]

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


func _old_bridge() -> Array:
	return _cells(func(c, t): return t["b"] == "old_bridge")


func _fords() -> Array:
	return _cells(func(c, t): return t.get("f", false))


func _plain_water() -> Vector2i:
	return _cells(func(c, t): return t["t"] == "water" and not t.get("f", false) and t["b"] == "")[0]


func _town() -> Vector2i:
	return _cells(func(c, t): return t["b"] == "town")[0]


## The first and last row of the river's water in column x.
func _channel(x: int) -> Vector2i:
	var rows := Game._river_rows()
	return rows[x]


## A column well away from every crossing, where the river is plain water.
func _quiet_column() -> int:
	var crossings := {}
	for c in _old_bridge() + _fords():
		crossings[c.x] = true
	for x in range(8, Game.w - 8):
		var clear := true
		for k in range(-4, 5):
			if crossings.has(x + k):
				clear = false
		if clear and _channel(x).x > 2:
			return x
	return -1


# ---------------------------------------------------------------- the wall, the fords and the bridges

func test_the_river_is_a_wall_for_everything_on_the_ground_but_boats_and_planes_pass() -> void:
	var c := _plain_water()
	for mover in ["foot", "horse", "car"]:
		assert_eq(Game.move_mult(mover, c), 0.0, mover)
	assert_eq(Game.move_mult("boat", c), 1.0)
	assert_eq(Game.move_mult("plane", c), 1.0)


func test_a_ford_can_be_waded_on_foot_and_on_horseback_but_not_by_a_war_rig() -> void:
	var c: Vector2i = _fords()[0]
	assert_true(Game.is_ford(c))
	assert_eq(Game.tile(c)["t"], "water", "a ford is still river for every other rule")
	assert_eq(Game.move_mult("foot", c), 2.0)
	assert_eq(Game.move_mult("horse", c), 2.0)
	assert_eq(Game.move_mult("car", c), 0.0, "the war rig cannot wade")
	assert_eq(Game.move_mult("boat", c), 2.0, "boats scrape over it")
	assert_eq(Game.move_mult("plane", c), 1.0)


func test_a_ford_and_the_river_have_their_own_names() -> void:
	assert_eq(Game.terrain_name(_fords()[0]), "Shallow ford")
	assert_eq(Game.terrain_name(_plain_water()), "Murky river")
	assert_eq(Game.terrain_name(home), "Ash sand" if Game.tile(home)["t"] == "sand" else Data.TERRAIN[Game.tile(home)["t"]].name)


func test_the_old_bridge_carries_every_ground_party_and_boats_pass_under_it() -> void:
	for c in _old_bridge():
		for mover in Data.MOVERS:
			assert_eq(Game.move_mult(mover, c), 1.0, "%s on the bridge at %s" % [mover, c])


func test_you_cannot_build_ordinary_buildings_on_a_ford() -> void:
	Game.res.merge({"wood": 100, "stone": 100, "metal": 100, "grain": 100}, true)
	var c: Vector2i = _fords()[0]
	Game.tile(c)["o"] = Data.PLAYER
	assert_eq(Game.build_status("outpost", c), "Can't build on water", "a ford is water")
	assert_eq(Game.build_status("farm", c), "Wrong terrain")


# ---------------------------------------------------------------- the map pass

func test_the_old_bridge_is_one_tile_wide_in_the_middle_of_the_map_and_belongs_to_nobody() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var bridge := _old_bridge()
		assert_false(bridge.is_empty(), "seed %d has an old bridge" % seed_value)
		var x: int = bridge[0].x
		assert_le(absi(x - Game.w / 2), Data.BRIDGE_SEARCH, "seed %d: column %d is near the middle" % [seed_value, x])
		var rows := []
		for c in bridge:
			assert_eq(c.x, x, "one column: one tile wide")
			assert_eq(Game.tile(c)["t"], "water")
			assert_eq(Game.tile(c)["o"], Data.NONE)
			rows.append(c.y)
		rows.sort()
		assert_eq(rows[rows.size() - 1] - rows[0] + 1, rows.size(), "no gaps")
		assert_between(rows.size(), 2, 4, "it spans the river")
		var channel := _channel(x)
		assert_eq(rows[0], channel.x, "from bank to bank")
		assert_eq(rows[rows.size() - 1], channel.y)


func test_a_war_rig_can_drive_from_your_hq_to_the_fort_over_the_old_bridge() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		assert_false(Game.route("car", home, fort).is_empty(), "seed %d: war rig route to the fort" % seed_value)


func test_foot_and_horseback_parties_can_reach_the_fort_and_dustwell() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for mover in ["foot", "horse"]:
			assert_false(Game.route(mover, home, fort).is_empty(), "seed %d: %s to the fort" % [seed_value, mover])
			assert_false(Game.route(mover, home, _town()).is_empty(), "seed %d: %s to Dustwell" % [seed_value, mover])


func test_there_are_two_to_four_fords_each_across_the_whole_channel_and_kept_apart() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		var columns := {}
		for c in _fords():
			columns[c.x] = true
		var xs := columns.keys()
		xs.sort()
		var strips := []   # the first column of each strip of fords
		for x in xs:
			if not columns.has(x - 1):
				strips.append(x)
		assert_between(strips.size(), 2, 4, "seed %d: ford strips %s" % [seed_value, strips])
		for x in strips:
			assert_true(columns.has(x + 1), "a strip is %d columns wide" % Data.FORD_WIDTH)
			for k in Data.FORD_WIDTH:
				var channel := _channel(x + k)
				for y in range(channel.x, channel.y + 1):
					assert_true(Game.tile(Vector2i(x + k, y)).get("f", false), "the whole channel in column %d is ford" % (x + k))
		var bridge_x: int = _old_bridge()[0].x
		var starts: Array = strips.duplicate()
		starts.append(bridge_x)
		for a in starts:
			for b in starts:
				if a != b:
					assert_ge(absi(a - b), 4, "seed %d: crossings at %d and %d are not on top of each other" % [seed_value, a, b])


func test_a_ford_is_on_the_way_to_dustwell_and_one_on_the_way_to_the_fort() -> void:
	for seed_value in [3, 7, 11]:
		_new_map(seed_value)
		var xs := {}
		for c in _fords():
			xs[c.x] = true
		var west := false
		var east := false
		for x in xs:
			if absi(x - roundi(Game.w * Data.FORDS[0])) <= Data.FORD_JITTER + 3:
				west = true
			if absi(x - roundi(Game.w * Data.FORDS[1])) <= Data.FORD_JITTER + 12:
				east = true
		assert_true(west, "seed %d: a ford near the west reach" % seed_value)
		assert_true(east, "seed %d: a ford near the middle-east reach" % seed_value)


func test_the_same_map_gets_the_same_crossings() -> void:
	_new_map(7)
	var first := [_old_bridge(), _fords()]
	_new_map(7)
	assert_eq([_old_bridge(), _fords()], first)


func test_the_crossing_pass_uses_random_numbers_of_its_own() -> void:
	seed(1234)
	var untouched := randi()
	seed(1234)
	Game._pass_crossings()
	assert_eq(randi(), untouched, "the pass left the game's random stream alone")


func test_the_old_bridge_and_the_fords_cost_nothing_extra_at_the_edges_of_the_map() -> void:
	for seed_value in SEEDS:
		_new_map(seed_value)
		for c in _fords() + _old_bridge():
			assert_gt(c.y, 0)
			assert_lt(c.y, Game.h - 1)


# ---------------------------------------------------------------- what a blocked trip says

func _wall_everything() -> void:
	for t in Game.tiles:
		t["f"] = false
		if t["b"] == "old_bridge":
			t["b"] = ""
	Game._build_paths()


func test_with_no_crossing_the_far_bank_cannot_be_reached_and_it_says_the_river() -> void:
	_wall_everything()
	for mover in ["foot", "horse", "car"]:
		assert_true(Game.route(mover, home, fort).is_empty(), mover)
		assert_eq(Game.no_way_text(mover, home, fort), "No way there (the river)", mover)
	assert_eq(Game.no_way_reason("foot", home, _plain_water()), "the river", "a tile in the water")


func test_boats_and_planes_are_never_told_it_is_the_river() -> void:
	assert_eq(Game.no_way_reason("boat", home, fort), "")
	assert_eq(Game.no_way_text("plane", home, fort), "No way there")


func test_a_war_rig_held_up_on_its_own_bank_is_told_steep_inclines() -> void:
	Game._label_banks()
	var on_my_bank := func(c, t): return Game.slopes[Game.idx(c)] == "steep" and t["t"] != "water" and Game.banks[Game.idx(c)] == Game.banks[Game.idx(home)]
	var steep: Vector2i = _cells(on_my_bank)[0]
	assert_eq(Game.no_way_reason("car", home, steep), "steep inclines")
	assert_eq(Game.no_way_reason("foot", home, steep), "", "foot can climb it")


# ---------------------------------------------------------------- bridges you build

func _prepare_bridge_site(x: int) -> Dictionary:
	Game.res.merge({"wood": 200, "stone": 200, "metal": 50, "grain": 50}, true)
	var channel := _channel(x)
	var north := Vector2i(x, channel.x - 1)
	var south := Vector2i(x, channel.y + 1)
	Game.tile(north)["o"] = Data.PLAYER   # your bank
	return {"north": north, "south": south, "rows": range(channel.x, channel.y + 1)}


func test_a_bridge_goes_out_from_your_bank_a_tile_at_a_time_and_becomes_yours() -> void:
	var site := _prepare_bridge_site(_quiet_column())
	var x: int = site.north.x
	var wood_before: int = Game.res.wood
	var first := Vector2i(x, site.rows[0])
	assert_eq(Game.build_status("bridge", first), "", "beside your land")
	if site.rows.size() > 1:
		assert_eq(Game.build_status("bridge", Vector2i(x, site.rows[1])), "Not your land", "not yet: it has to touch your land or the last bridge tile")
	for y in site.rows:
		var c := Vector2i(x, y)
		assert_eq(Game.build_status("bridge", c), "", "tile %d" % y)
		Game.build("bridge", c)
		assert_eq(Game.tile(c)["b"], "bridge")
		assert_eq(Game.tile(c)["o"], Data.PLAYER, "the bridge tile is yours")
	assert_eq(Game.res.wood, wood_before - 10 * site.rows.size(), "10 wood a tile")


func test_a_finished_bridge_opens_a_short_way_across_for_every_ground_party() -> void:
	var site := _prepare_bridge_site(_quiet_column())
	var x: int = site.north.x
	var before := {}
	for mover in ["foot", "horse", "car"]:
		before[mover] = Game.route(mover, site.north, site.south).size()
	for y in site.rows:
		Game.build("bridge", Vector2i(x, y))
	for mover in ["foot", "horse", "car"]:
		var after := Game.route(mover, site.north, site.south)
		assert_false(after.is_empty(), mover)
		assert_eq(after.size(), site.rows.size() + 2, "%s: straight across" % mover)
		assert_lt(after.size(), before[mover], "%s: shorter than going round by the other crossings" % mover)


func test_a_bridge_cannot_start_away_from_your_land_or_on_land_or_on_enemy_water() -> void:
	var site := _prepare_bridge_site(_quiet_column())
	var far := Vector2i(site.north.x + 6, site.rows[0])
	assert_eq(Game.build_status("bridge", far), "Not your land", "water you do not border")
	Game.tile(Vector2i(site.north.x, site.rows[0]))["o"] = Data.AI
	assert_eq(Game.build_status("bridge", Vector2i(site.north.x, site.rows[0])), "Not your land", "the Rust Kings' water")
	assert_eq(Game.build_status("bridge", site.north), "Wrong terrain", "a bridge goes on water")
	assert_eq(Game.build_status("old_bridge", _old_bridge()[0]), "Can't be built")


func test_a_bridge_needs_the_wood_and_the_stone() -> void:
	var site := _prepare_bridge_site(_quiet_column())
	Game.res["stone"] = 0
	assert_ne(Game.build_status("bridge", Vector2i(site.north.x, site.rows[0])), "")
	assert_true(Game.build_status("bridge", Vector2i(site.north.x, site.rows[0])).begins_with("Need "))


func test_pulling_a_bridge_down_shuts_the_way_again_but_not_with_a_party_on_it() -> void:
	var site := _prepare_bridge_site(_quiet_column())
	var x: int = site.north.x
	for y in site.rows:
		Game.build("bridge", Vector2i(x, y))
	var middle := Vector2i(x, site.rows[0])
	var party: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", middle, home)
	Units.units.append(party)
	Game.demolish(middle)
	assert_eq(Game.tile(middle)["b"], "bridge", "it stays up while a party stands on it")
	Units.units.clear()
	Game.demolish(middle)
	assert_eq(Game.tile(middle)["b"], "")
	assert_eq(Game.move_mult("foot", middle), 0.0, "river again")
	assert_gt(Game.route("foot", site.north, site.south).size(), site.rows.size() + 2, "back to going round")


func test_nobody_can_claim_the_old_bridge_or_take_it_with_an_outpost() -> void:
	var c: Vector2i = _old_bridge()[0]
	assert_eq(Game.claim_status(c), "The old bridge belongs to nobody")
	Game.res.merge({"wood": 100, "stone": 100, "metal": 100, "grain": 100}, true)
	var bank := Vector2i(-1, -1)   # a free bank tile within the outpost's reach of the bridge (the old highway takes the tile at the bridge's end)
	for b in _old_bridge():
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				var p: Vector2i = b + Vector2i(dx, dy)
				if bank.x < 0 and Game.in_bounds(p) and Game.tile(p)["t"] != "water" and Game.tile(p)["b"] == "":
					bank = p
	assert_ne(bank, Vector2i(-1, -1), "somewhere to put the outpost")
	Game.tile(bank)["o"] = Data.PLAYER
	Game.build("outpost", bank)
	assert_eq(Game.tile(bank)["b"], "outpost")
	for b in _old_bridge():
		assert_eq(Game.tile(b)["o"], Data.NONE, "the outpost's claim skips the old bridge")


# ---------------------------------------------------------------- saving

func test_fords_and_bridges_survive_saving_and_loading() -> void:
	var site := _prepare_bridge_site(_quiet_column())
	Game.build("bridge", Vector2i(site.north.x, site.rows[0]))
	var fords := _fords()
	var old := _old_bridge()
	Game.save_game("crossing_test")
	_new_map(21)
	assert_ne(_old_bridge(), old, "a different map first")
	assert_true(Game.load_game("crossing_test"))
	assert_eq(_fords(), fords)
	assert_eq(_old_bridge(), old)
	assert_eq(Game.tile(Vector2i(site.north.x, site.rows[0]))["b"], "bridge")
	assert_eq(Game.move_mult("foot", fords[0]), 2.0, "the route costs are rebuilt on load")
	assert_false(Game.route("car", Game.home(Data.PLAYER), Game.home(Data.AI)).is_empty())
