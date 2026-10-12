extends "res://tests/framework/test_case.gd"
## Map layout (the river, ruin clusters and craters, clear starts) and ports.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

const SEEDS := [1, 2, 3, 7, 11, 21]
const CAMPS := [Data.PLAYER_START, Data.AI_START, Data.TOWN_START]


func _water_rows(x: int) -> Array:
	var rows := []
	for y in Game.h:
		if Game.tile(Vector2i(x, y))["t"] == "water":
			rows.append(y)
	return rows


func test_one_river_runs_from_left_to_right() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		var prev := []
		for x in Game.w:
			var rows := _water_rows(x)
			assert_gt(rows.size(), 1, "seed %d has no river in column %d" % [sd, x])
			if not prev.is_empty() and not rows.is_empty():
				assert_true(rows.min() <= prev.max() and rows.max() >= prev.min(), "seed %d: the river breaks at column %d" % [sd, x])
			prev = rows


func test_river_slopes_south_toward_the_east() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		var west: int = _water_rows(2).min()
		var east: int = _water_rows(Game.w - 3).min()
		assert_gt(east - west, 15, "seed %d: river should drop toward the east" % sd)
		assert_lt(east - west, 40, "seed %d: the slant should be slight" % sd)


func test_boats_can_sail_the_whole_river() -> void:
	World.new_game(7)
	var left := Vector2i(0, _water_rows(0)[0])
	var right := Vector2i(Game.w - 1, _water_rows(Game.w - 1)[0])
	assert_false(Game.route("boat", left, right).is_empty())


func test_camps_start_in_open_desert() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		for camp in CAMPS:
			var ruins := 0
			for y in range(camp.y - Data.START_CLEAR, camp.y + Data.START_CLEAR + 1):
				for x in range(camp.x - Data.START_CLEAR, camp.x + Data.START_CLEAR + 1):
					if camp.distance_to(Vector2i(x, y)) > Data.START_CLEAR:
						continue
					var t: String = Game.tile(Vector2i(x, y))["t"]
					if camp != Data.TOWN_START:
						assert_ne(t, "water", "seed %d: river reaches the camp at %s" % [sd, camp])
					assert_ne(t, "crater", "seed %d: crater at the camp %s" % [sd, camp])
					assert_false(t in ["glass", "waste"], "seed %d: catastrophe fallout at the camp %s" % [sd, camp])
					ruins += 1 if t == "ruins" else 0
			assert_le(ruins, 1, "seed %d: ruins crowd the camp at %s" % [sd, camp])
		# Both colonies have land to grow on before they reach the river
		for camp in [Data.PLAYER_START, Data.AI_START]:
			assert_gt(_distance_to_river(camp), 6.0, "seed %d: the river is too close to %s" % [sd, camp])


func _distance_to_river(c: Vector2i) -> float:
	var best := 1000.0
	for y in Game.h:
		for x in range(maxi(c.x - 12, 0), mini(c.x + 13, Game.w)):
			if Game.tile(Vector2i(x, y))["t"] == "water":
				best = minf(best, c.distance_to(Vector2i(x, y)))
	return best


func test_every_crater_is_the_center_of_a_ruin_cluster() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		var craters := 0
		for y in Game.h:
			for x in Game.w:
				if Game.tile(Vector2i(x, y))["t"] != "crater":
					continue
				craters += 1
				var ruins := 0
				for dy in range(-7, 8):
					for dx in range(-7, 8):
						var p := Vector2i(x + dx, y + dy)
						# Glass is ruins that the blast fused
						if Game.in_bounds(p) and Game.tile(p)["t"] in ["ruins", "glass"]:
							ruins += 1
				assert_gt(ruins, 25, "seed %d: crater at %d,%d has only %d ruins around it" % [sd, x, y, ruins])
		assert_gt(craters, 4, "seed %d has no craters" % sd)


func test_clusters_are_far_bigger_than_stray_ruins() -> void:
	World.new_game(7)
	var ruins := 0
	for t in Game.tiles:
		ruins += 1 if t["t"] == "ruins" else 0
	assert_gt(ruins, 150)


# ---------------------------------------------------------------- ports

func _shore_tile() -> Vector2i:
	return World.find_tile(func(c, t): return t["t"] != "water" and Game.neighbors(c).any(func(n): return Game.tile(n)["t"] == "water"))


func _ready_to_build_ports() -> void:
	Game.upgrades = ["w3"]
	for r in ["wood", "metal", "gold", "grain", "fuel"]:
		Game.res[r] = 200
	assert_ge(Game.highest_tier(), 3)


func test_ports_only_go_on_the_riverbank() -> void:
	World.new_game(7)
	_ready_to_build_ports()
	var shore := _shore_tile()
	Game.tile(shore)["o"] = Data.PLAYER
	assert_eq(Game.build_status("port", shore), "")
	var inland := World.find_tile(func(c, t): return t["t"] == "sand" and not Game.neighbors(c).any(func(n): return Game.tile(n)["t"] == "water"))
	Game.tile(inland)["o"] = Data.PLAYER
	assert_eq(Game.build_status("port", inland), "Must stand on the riverbank")
	var water := World.find_tile(func(c, t): return t["t"] == "water")
	Game.tile(water)["o"] = Data.PLAYER
	assert_eq(Game.build_status("port", water), "Can't build on water")


func test_boats_are_built_and_launched_from_a_port() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false   # no raiders to steal the trade gold
	_ready_to_build_ports()
	assert_eq(Game.vehicle_status("boat"), "Needs a Port")
	var shore := _shore_tile()
	Game.tile(shore)["o"] = Data.PLAYER
	Game.build("port", shore)
	assert_eq(Game.tile(shore)["b"], "port")
	assert_eq(Game.vehicle_status("boat"), "")
	Game.build_vehicle("boat")
	assert_eq(Game.vehicles["boat"], 1)
	assert_eq(Units.send_status("boat", "boat", shore, -1, shore), "")
	Units.send("boat", "boat", shore, -1, shore)
	var boat: Dictionary = Units.units[-1]
	assert_eq(Game.tile(boat.pos)["t"], "water")
	assert_eq(Game.tile(boat.target)["t"], "water")
	assert_true(boat.target.x == 0 or boat.target.x == Game.w - 1, "boats sail to a river mouth at the edge of the map")
	var gold: int = Game.res["gold"]
	for i in 20:
		if Units.units.is_empty():
			break
		Units.season_turn()
	assert_eq(Units.units.size(), 0)
	assert_gt(Game.res["gold"], gold)


## A new game with a port built on the riverbank between x = `from_x` and `to_x`, and one boat.
func _port_between(from_x: int, to_x: int) -> Vector2i:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	_ready_to_build_ports()
	var shore := World.find_tile(func(c, t): return t["t"] != "water" and c.x >= from_x and c.x <= to_x \
		and Game.neighbors(c).any(func(n): return Game.tile(n)["t"] == "water"))
	assert_ne(shore, Vector2i(-1, -1), "needs a riverbank tile in that stretch")
	Game.tile(shore)["o"] = Data.PLAYER
	Game.build("port", shore)
	Game.build_vehicle("boat")
	assert_eq(Game.vehicles["boat"], 1)
	return shore


func test_a_boat_trip_fills_a_tank_and_burns_it_as_it_sails() -> void:
	var shore := _port_between(15, 28)   # close to the west edge, where the river meets the map edge
	var tank: int = Data.VEHICLE_FUEL.boat.tank
	var fuel: int = Game.res["fuel"]
	assert_has(Units.send_cost_text("boat", "boat"), "%d fuel" % tank)
	assert_lt(Units.boat_trip_fuel(shore), float(tank), "a port this close to a river mouth can make the round trip")
	Units.send("boat", "boat", shore, -1, shore)
	var boat: Dictionary = Units.units[-1]
	assert_eq(boat.fuel, float(tank))
	assert_eq(Game.res["fuel"], fuel - tank)
	Units.season_turn()
	assert_lt(boat.fuel, float(tank), "sailing burns fuel")
	var gold: int = Game.res["gold"]
	for i in 20:
		if Units.units.is_empty():
			break
		Units.season_turn()
	assert_eq(Units.units.size(), 0, "it made it home")
	assert_gt(Game.res["gold"], gold)
	assert_eq(Game.vehicles["boat"], 1, "and so did the boat")


func test_boats_refitted_with_sails_need_no_tank() -> void:
	var shore := _port_between(15, 28)
	Game.upgrades.append("fv3")
	assert_eq(Units.tank_size("boat", "boat"), 0)
	var fuel: int = Game.res["fuel"]
	Units.send("boat", "boat", shore, -1, shore)
	assert_false(Units.units[-1].has("fuel"), "no tank, so no gauge")
	assert_eq(Game.res["fuel"], fuel)


func test_a_boat_that_runs_dry_is_lost_and_the_crew_walk_home() -> void:
	var shore := _port_between(15, 28)
	var pop := Game.pop
	Units.send("boat", "boat", shore, -1, shore)
	var boat: Dictionary = Units.units[-1]
	assert_eq(Game.pop, pop - 2)
	Units.season_turn()   # sails to the river mouth and trades
	assert_eq(boat.stage, "back")
	assert_false(boat.carry.is_empty(), "heading home with the gold")
	boat.fuel = 0.001
	Units.season_turn()   # ...and runs dry on the way back
	assert_eq(boat.mover, "foot")
	assert_false(boat.has("fuel"))
	assert_eq(boat.stage, "back", "the crew head home")
	assert_false(boat.path.is_empty(), "a long wade from the river mouth")
	assert_false(boat.carry.is_empty(), "they keep what they traded")
	assert_eq(Game.vehicles["boat"], 0, "the boat is lost")
	assert_eq(boat.crew, 2)
	assert_true(Game.log_lines.any(func(l): return l.contains("boat ran dry")))
	var gold: int = Game.res["gold"]
	for i in 30:
		if Units.units.is_empty():
			break
		Units.season_turn()
	assert_eq(Units.units.size(), 0)
	assert_eq(Game.pop, pop, "the crew got home")
	assert_gt(Game.res["gold"], gold)


func test_a_port_too_far_from_a_river_mouth_runs_its_boat_dry_on_the_way_home() -> void:
	var shore := _port_between(50, 70)
	var tank: int = Data.VEHICLE_FUEL.boat.tank
	assert_gt(Units.boat_trip_fuel(shore), float(tank), "the round trip burns more than the tank holds")
	var pop := Game.pop
	Units.send("boat", "boat", shore, -1, shore)
	var gold: int = Game.res["gold"]
	for i in 30:
		if Units.units.is_empty():
			break
		Units.season_turn()
	assert_eq(Units.units.size(), 0)
	assert_eq(Game.vehicles["boat"], 0, "the boat ran dry and was lost")
	assert_eq(Game.pop, pop, "the crew walked back")
	assert_gt(Game.res["gold"], gold, "with what they'd traded")


func test_boat_trip_fuel_is_zero_away_from_the_river() -> void:
	World.new_game(7)
	assert_eq(Units.boat_trip_fuel(Game.home(Data.PLAYER)), 0.0)


func test_a_boat_cant_leave_from_a_tile_away_from_the_river() -> void:
	World.new_game(7)
	_ready_to_build_ports()
	Game.vehicles["boat"] = 1
	assert_ne(Units.send_status("boat", "boat", Game.home(Data.PLAYER), -1, Game.home(Data.PLAYER)), "")


func test_old_docks_load_as_ports() -> void:
	World.new_game(7)
	var water := World.find_tile(func(c, t): return t["t"] == "water")
	Game.tile(water)["b"] = "dock"
	Game.save_game("dock_test")
	assert_true(Game.load_game("dock_test"))
	assert_eq(Game.tile(water)["b"], "port")
	Game.vehicles["boat"] = 1
	assert_eq(Units.launch_tile(water), water)
	DirAccess.remove_absolute(Game._path("dock_test"))


# ---------------------------------------------------------------- the generation passes

func _is_green(c: Vector2i) -> bool:
	return Game.in_bounds(c) and Game.tile(c)["t"] in ["trees", "grove"]


func test_greenery_is_scarce_and_clumped() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		var green := 0
		var green_neighbors := 0.0
		for y in Game.h:
			for x in Game.w:
				var c := Vector2i(x, y)
				if not _is_green(c):
					continue
				green += 1
				var same := 0
				for dy in [-1, 0, 1]:
					for dx in [-1, 0, 1]:
						if (dx != 0 or dy != 0) and _is_green(c + Vector2i(dx, dy)):
							same += 1
				green_neighbors += same / 8.0
		var share := green / float(Game.tiles.size())
		assert_lt(share, 0.07, "seed %d: green should be scarce, it is %.1f%%" % [sd, share * 100.0])
		assert_gt(share, 0.015, "seed %d has almost no green" % sd)
		assert_gt(green_neighbors / green, 0.5, "seed %d: green should come in clumps" % sd)


func test_groves_are_few_and_sit_away_from_the_ruin_fields() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		var groves := []
		for y in Game.h:
			for x in Game.w:
				if Game.tile(Vector2i(x, y))["t"] == "grove":
					groves.append(Vector2i(x, y))
		assert_gt(groves.size(), 10, "seed %d has no oasis" % sd)
		# Everything within a few tiles of each other is one oasis: there are at most GROVE_COUNT
		var oases := []
		for g in groves:
			if not oases.any(func(o): return o.distance_to(g) < 12.0):
				oases.append(g)
		assert_le(oases.size(), Data.GROVE_COUNT, "seed %d: groves should be clumped into %d oases" % [sd, Data.GROVE_COUNT])
		for g in groves:
			for cat in Game.catastrophes:
				assert_gt(g.distance_to(cat.pos), cat.radius * 1.3, "seed %d: a grove in a ruin field" % sd)


func test_every_epicenter_suffered_a_catastrophe() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		assert_ge(Game.catastrophes.size(), 3, "seed %d" % sd)
		var kinds := {}
		for cat in Game.catastrophes:
			assert_has(Data.CATASTROPHES.keys(), cat.kind)
			assert_ge(cat.year, Data.CATASTROPHE_YEARS[0])
			assert_le(cat.year, Data.CATASTROPHE_YEARS[1])
			assert_true(cat.name.begins_with("The "))
			assert_eq(Game.tile(cat.pos)["t"], "crater", "the epicenter is the crater")
			assert_eq(Game.catastrophe_at(cat.pos), cat)
			kinds[cat.kind] = true
		assert_eq(kinds.size(), mini(Game.catastrophes.size(), Data.CATASTROPHES.size()), "seed %d: each kind should appear" % sd)


func test_firestorm_leaves_no_greenery_nearby() -> void:
	var seen := 0
	for sd in SEEDS:
		World.new_game(sd)
		for cat in Game.catastrophes:
			if cat.kind != "firestorm":
				continue
			seen += 1
			var reach: float = cat.radius * Data.BURN_REACH * 0.8
			for y in range(maxi(cat.pos.y - 30, 0), mini(cat.pos.y + 31, Game.h)):
				for x in range(maxi(cat.pos.x - 30, 0), mini(cat.pos.x + 31, Game.w)):
					var c := Vector2i(x, y)
					if c.distance_to(cat.pos) <= reach:
						assert_false(Game.tile(c)["t"] in ["scrub", "trees", "grove"], "seed %d: green survived the firestorm at %s" % [sd, c])
	assert_gt(seen, 0)


func test_fallout_blows_a_plume_of_waste_away_from_the_camps() -> void:
	var seen := 0
	for sd in SEEDS:
		World.new_game(sd)
		for cat in Game.catastrophes:
			if cat.kind != "fallout":
				continue
			seen += 1
			var waste := 0
			for y in Game.h:
				for x in Game.w:
					var c := Vector2i(x, y)
					if Game.tile(c)["t"] == "waste":
						waste += 1
						assert_true(Game.in_plume(cat, c) or Game.catastrophes.any(func(o): return o.kind == "fallout" and Game.in_plume(o, c)))
			assert_gt(waste, 15, "seed %d: the plume left no waste" % sd)
	assert_gt(seen, 0)


func test_glassing_fuses_the_ground_around_the_crater() -> void:
	var seen := 0
	for sd in SEEDS:
		World.new_game(sd)
		for cat in Game.catastrophes:
			if cat.kind != "glassing":
				continue
			seen += 1
			var glass := 0
			for p in Game._circle(cat.pos, 4):
				glass += 1 if Game.tile(p)["t"] == "glass" else 0
			assert_gt(glass, 10, "seed %d: no glass around the crater" % sd)
	assert_gt(seen, 0)


func test_quakes_split_the_ground_into_faults() -> void:
	var seen := 0
	for sd in SEEDS:
		World.new_game(sd)
		for cat in Game.catastrophes:
			if cat.kind != "quake":
				continue
			seen += 1
			assert_ge(cat.faults.size(), Data.FAULTS[0])
			var steep := 0
			for p in Game._circle(cat.pos, int(cat.radius * Data.FAULT_REACH)):
				steep += 1 if Game.slopes[Game.idx(p)] == "steep" else 0
			assert_gt(steep, 15, "seed %d: the quake left no steep faults" % sd)
	assert_gt(seen, 0)


func test_craters_have_a_raised_rim() -> void:
	World.new_game(7)
	var cat: Dictionary = Game.catastrophes[0]
	var rim := 0.0
	var count := 0
	for p in Game._circle(cat.pos, ceili(cat.crater) + 3):
		var d: float = cat.pos.distance_to(p)
		if d > cat.crater and d <= cat.crater + 1.6:
			rim += Game.tile(p)["z"]
			count += 1
	assert_gt(rim / count, Game.tile(cat.pos)["z"] + 8.0, "the rim should stand above the crater floor")


func test_smoothing_leaves_few_lone_tiles() -> void:
	for sd in SEEDS:
		World.new_game(sd)
		var lone := 0
		var ground := 0
		for y in range(1, Game.h - 1):
			for x in range(1, Game.w - 1):
				var c := Vector2i(x, y)
				var t: String = Game.tile(c)["t"]
				if not t in ["sand", "dunes", "scrub", "rock"]:
					continue
				ground += 1
				if Game.neighbors(c).all(func(n): return Game.tile(n)["t"] != t):
					lone += 1
		assert_lt(lone / float(ground), 0.03, "seed %d: ground should form patches, not speckle" % sd)


func test_catastrophes_survive_saving() -> void:
	World.new_game(7)
	var before := Game.catastrophes.duplicate(true)
	Game.save_game("history_test")
	assert_true(Game.load_game("history_test"))
	DirAccess.remove_absolute(Game._path("history_test"))
	assert_eq(Game.catastrophes.size(), before.size())
	for i in before.size():
		for key in ["pos", "radius", "kind", "year", "name"]:
			assert_eq(Game.catastrophes[i][key], before[i][key])
		assert_almost_eq(Game.catastrophes[i].crater, before[i].crater, 0.0001)
