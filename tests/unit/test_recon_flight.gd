extends "res://tests/framework/test_case.gd"
## Recon flights carry a tank like a scouting plane does: the tank is what the flight costs, the trip burns it, what is
## left comes home, and a flight that runs dry crashes.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var target: Vector2i
var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	Units.crash_survival = Data.CRASH_SURVIVAL
	Game.res["fuel"] = 50
	Game.vehicles["plane"] = 1
	hq = Game.home(Data.PLAYER)
	# Any land a good way out: a plane flies over everything
	target = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 14 and c.distance_to(hq) < 22)
	assert_ne(target, Vector2i(-1, -1), "needs a tile a flight away")


func _fly() -> Dictionary:
	assert_eq(Units.send_status("plane", "plane", target), "")
	Units.send("plane", "plane", target)
	return Units.units[-1]


func _path_length(path: Array) -> float:
	var length := 0.0
	for i in range(1, path.size()):
		length += Vector2(path[i] - path[i - 1]).length()
	return length


func test_a_recon_flight_has_the_planes_tank_and_filling_it_is_what_it_costs() -> void:
	assert_eq(Units.tank_size("plane", "plane"), Data.VEHICLE_FUEL.plane.tank)
	assert_eq(Units.send_cost("plane", "plane"), {"fuel": Data.VEHICLE_FUEL.plane.tank}, "no flat fee on top of the tank")
	var u := _fly()
	assert_eq(Game.res["fuel"], 50 - Data.VEHICLE_FUEL.plane.tank)
	assert_true(u.has("fuel"), "so it has a gauge")
	assert_eq(u.fuel, float(Data.VEHICLE_FUEL.plane.tank))


func test_a_flight_needs_the_whole_tank_in_the_stores() -> void:
	Game.res["fuel"] = Data.VEHICLE_FUEL.plane.tank - 1
	assert_true(Units.send_status("plane", "plane", target).begins_with("Need"))
	Game.res["fuel"] = Data.VEHICLE_FUEL.plane.tank
	assert_eq(Units.send_status("plane", "plane", target), "")


func test_the_other_expeditions_keep_the_tanks_they_had() -> void:
	assert_eq(Units.tank_size("scout", "car"), Data.VEHICLE_FUEL.car.tank)
	assert_eq(Units.tank_size("scout", "plane"), Data.VEHICLE_FUEL.plane.tank)
	assert_eq(Units.tank_size("scav", "car"), 0, "a scavenging war rig pays a flat fee, not a tank")
	assert_eq(Units.tank_size("caravan", "horse"), 0)
	assert_eq(Units.tank_size("scav", "foot"), 0)


func test_the_trip_burns_fuel_by_how_far_it_goes() -> void:
	var u := _fly()
	var out := _path_length([hq] + u.path)
	Units.season_turn()   # a plane covers a season's flight in a go
	assert_eq(u.stage, "back", "it has been there and turned for home")
	var burn: float = Data.VEHICLE_FUEL.plane.burn * Units.fuel_mult()
	assert_almost_eq(u.fuel, Data.VEHICLE_FUEL.plane.tank - burn * out, 0.001, "burned per tile, out")


func test_what_is_left_in_the_tank_comes_home_with_the_flight() -> void:
	var u := _fly()
	var burn: float = Data.VEHICLE_FUEL.plane.burn * Units.fuel_mult()
	var total := burn * (_path_length([hq] + u.path) + _path_length(Game.route("plane", target, hq)))
	var left: float = Data.VEHICLE_FUEL.plane.tank - total
	assert_gt(left, 1.0, "this trip leaves a good deal in the tank")
	for i in 6:
		if not Units.units.has(u):
			break
		Units.season_turn()
	assert_false(Units.units.has(u), "the flight is home")
	var expected := 50 - Data.VEHICLE_FUEL.plane.tank
	assert_true(Game.res["fuel"] in [expected + int(left - 0.001), expected + int(left + 0.001)],
		"only whole units: %d left of %.2f, stores %d" % [int(left), left, Game.res["fuel"]])
	assert_lt(Game.res["fuel"], 50, "and the trip was not free")


func test_a_flight_that_runs_dry_crashes_and_the_pilot_walks_home_hurt() -> void:
	Units.crash_survival = 1.0
	var u := _fly()
	u.fuel = 0.2
	Units.season_turn()
	assert_eq(u.mover, "foot")
	assert_false(u.has("fuel"), "no tank, no gauge")
	assert_eq(Game.vehicles["plane"], 0, "the plane is lost")
	assert_eq(u.survivors.size(), 1)
	assert_true(u.survivors[0].hurt)
	assert_eq(u.stage, "back", "a recon flight does not wait: the pilot walks home")
	assert_true(Game.log_lines.any(func(l): return l.contains("plane crashed") and l.contains("survived, injured")))


func test_nobody_may_walk_away_from_a_recon_crash() -> void:
	Units.crash_survival = 0.0
	var pop := Game.pop
	var u := _fly()
	assert_eq(Game.pop, pop - 1, "the pilot has left the colony")
	u.fuel = 0.2
	Units.season_turn()
	assert_false(Units.units.has(u), "the flight is gone")
	assert_eq(Game.vehicles["plane"], 0)
	assert_eq(Game.pop, pop - 1, "and the pilot never comes back")
	assert_true(Game.log_lines.any(func(l): return l.contains("Nobody walked away")))
