extends "res://tests/framework/test_case.gd"
## Your parties walk the moment you order it (see test_movement), and every walk is noted like a season's: one actor whose trail
## counts the days from the start of that walk, with the flashes and the ground it uncovered. Units hands it to the map
## (Game.walk_played), which plays it at the normal pace, so every unit still walks on screen.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var hq: Vector2i
var ruin: Vector2i
var far: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	Units.crash_survival = Data.CRASH_SURVIVAL
	hq = Game.home(Data.PLAYER)
	ruin = hq + Vector2i(1, -2)   # the ruin every camp starts beside
	Game.pop = 30
	Game.res["grain"] = 200
	Game.res["fuel"] = 50
	D20.loot_scale = D20Data.LOOT_SCALE
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 30 and c.distance_to(hq) < 45 \
		and not Game.route("foot", hq, c).is_empty())
	assert_ne(far, Vector2i(-1, -1), "needs a tile a long walk away")


func after_each() -> void:
	D20.loot_scale = D20Data.LOOT_SCALE
	Units._recording = false


## A party of yours keeping watch at `at`.
func _party_at(at: Vector2i, job := "scout") -> Dictionary:
	var u: Dictionary = Units._make_unit(job, Data.PLAYER, "foot", at, at)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.food = {"grain": Data.SCOUT_PACK}
	u["number"] = 1
	u.stage = "station"
	Units.units.append(u)
	return u


func test_a_walk_is_handed_to_the_map_with_the_days_it_took() -> void:
	var w := watch(Game, "walk_played")
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	assert_eq(w.count, 1, "one walk")
	var r: Dictionary = w.emissions[0][0]
	assert_true(r.walk, "it is marked as a party's walk, not a season's")
	assert_eq(r.actors.size(), 1, "just the party that walked")
	var a: Dictionary = r.actors[0]
	assert_eq(a.id, u.id)
	assert_eq(a.kind, "scav", "every party is drawn as a Scavenger Party")
	assert_eq(a.owner, Data.PLAYER)
	assert_false(a.get("wild", false))
	assert_eq(a.trail[0], [hq, 0.0], "it starts where it was, on day 0 of its own walk")
	assert_gt(a.trail.size(), 5, "a day's walk is many tiles")
	for i in range(1, a.trail.size()):
		assert_ge(a.trail[i][1], a.trail[i - 1][1], "the days only go up")
		assert_le(Vector2(a.trail[i][0] - a.trail[i - 1][0]).length(), 1.5, "one tile at a time")
	assert_eq(a.trail.back()[0], u.pos, "and ends where the party now stands")
	assert_almost_eq(a.trail.back()[1], Data.SEASON_DAYS - u.move_left, 0.001, "the days it walked are the days it spent")
	assert_eq(r.end_day, a.trail.back()[1])
	assert_le(r.end_day, float(Data.SEASON_DAYS))


func test_each_walk_counts_its_days_from_its_own_start() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	Units.season_turn()   # a new turn: the party has its days again
	var from: Vector2i = u.pos
	var w := watch(Game, "walk_played")
	Units.continue_orders(u.id)
	assert_eq(w.count, 1)
	var a: Dictionary = w.emissions[0][0].actors[0]
	assert_eq(a.trail[0], [from, 0.0], "day 0 of this walk, at the tile the last one ended on")
	assert_ne(a.trail.back()[0], from, "and it went somewhere")


func test_a_walk_leaves_the_seasons_own_notes_alone() -> void:
	Units.replay = {"marker": 7}
	assert_false(Units.is_recording())
	Units.send("scout", "foot", far)
	assert_eq(Units.replay, {"marker": 7}, "the season's notes were not written to")
	assert_false(Units.is_recording())
	Units._record_start()   # a season is being noted...
	var notes: Dictionary = Units.replay
	var u: Dictionary = Units.units[-1]
	u.move_left = float(Data.SEASON_DAYS)
	Units.continue_orders(u.id)   # ...and a walk happens in the middle of it
	assert_true(Units.is_recording(), "the season's notes are still being made")
	assert_false(notes.has("walk"), "and they are the season's, not the walk's")
	Units._recording = false


func test_nothing_is_handed_over_when_a_party_does_not_walk() -> void:
	var u := _party_at(hq + Vector2i(3, 0))
	var w := watch(Game, "walk_played")
	assert_false(Units._go(u), "no orders, no walk")
	assert_eq(w.count, 0)
	Units.send("scout", "foot", far)
	var p: Dictionary = Units.units[-1]
	p.move_left = 0.0
	var later := watch(Game, "walk_played")
	Units.continue_orders(p.id)
	assert_eq(later.count, 0, "no days left, so it stays where it is")


func test_a_party_that_reaches_its_ruin_flashes_there_when_the_walk_ends() -> void:
	Game.tile(ruin)["r"] = "safe"
	var w := watch(Game, "walk_played")
	Units.send("scav", "foot", ruin)
	var r: Dictionary = w.emissions[0][0]
	var flashes: Array = r.events.filter(func(e): return e.kind == "ruin")
	assert_eq(flashes.size(), 1)
	assert_eq(flashes[0].cell, ruin)
	assert_eq(flashes[0].day, r.actors[0].trail.back()[1], "when it gets there")
	assert_false(r.actors[0].parked, "it is busy searching, not waiting")


func test_a_party_that_gets_home_with_loot_leaves_the_map_with_a_glint() -> void:
	var u := _party_at(hq + Vector2i(3, 0))
	u.carry = {"gold": 5}
	var w := watch(Game, "walk_played")
	Units.recall_scouts(u.id)
	assert_false(Units.units.has(u), "it got home")
	var r: Dictionary = w.emissions[0][0]
	var a: Dictionary = r.actors[0]
	assert_eq(a.trail.back()[0], hq)
	assert_eq(a.gone_day, a.trail.back()[1], "it leaves the map the moment it arrives")
	var home: Array = r.events.filter(func(e): return e.kind == "home")
	assert_eq(home.size(), 1)
	assert_eq(home[0].cell, hq)
	assert_eq(home[0].day, a.gone_day)


func test_ground_a_walk_uncovers_is_noted_with_the_day_it_was_reached() -> void:
	var w := watch(Game, "walk_played")
	Units.send("scout", "foot", far)
	var r: Dictionary = w.emissions[0][0]
	var reveals: Array = r.reveals
	assert_gt(reveals.size(), 20, "a party walking into the unknown uncovers ground")
	var last := 0.0
	for reveal in reveals:
		assert_ge(reveal[1], last, "in the order it was reached")
		assert_le(reveal[1], r.end_day, "all within the walk")
		last = reveal[1]


func test_a_vehicle_that_runs_dry_on_the_walk_puffs_smoke_and_its_days_are_spent() -> void:
	Game.vehicles["car"] = 1
	var rig_far := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 25 and c.distance_to(hq) < 40 \
		and not Game.route("car", hq + Vector2i(2, 0), c).is_empty())
	assert_ne(rig_far, Vector2i(-1, -1))
	var start := hq + Vector2i(2, 0)
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "car", start, rig_far)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.food = {"grain": Data.SCOUT_PACK}
	u.stage = "out"
	u.path = Game.route("car", start, rig_far).slice(1)
	u.fuel = Data.VEHICLE_FUEL.car.burn * Units.fuel_mult() * 2.5   # enough for two steps
	Units.units.append(u)
	var w := watch(Game, "walk_played")
	Units._go(u)
	assert_eq(u.mover, "foot", "the rig was abandoned")
	var smoke: Array = w.emissions[0][0].events.filter(func(e): return e.kind == "smoke")
	assert_eq(smoke.size(), 1, "a puff where it gave out")
	assert_lt(u.move_left, float(Data.SEASON_DAYS), "the two steps it drove cost days")
	assert_true(u.moved, "so the rest of the season is not counted as standing still")


func test_a_party_waiting_for_orders_is_parked_and_one_in_a_search_is_not() -> void:
	var u := _party_at(hq + Vector2i(3, 0))
	for stage in ["station", "out", "back"]:
		u.stage = stage
		assert_true(Units.is_parked(u), "%s: waiting for orders" % stage)
	u.stage = "site"
	assert_false(Units.is_parked(u), "busy with a visit")
	var caravan: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq, hq)
	caravan.stage = "station"
	assert_false(Units.is_parked(caravan), "only your parties wait about")
	u.stage = "out"
	Units._record_start()
	var noted := false
	for a in Units.replay.actors:
		if a.id == u.id:
			noted = true
			assert_true(a.parked, "the season's replay bobs it like any waiting party")
	assert_true(noted)
	Units._recording = false
