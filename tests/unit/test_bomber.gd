extends "res://tests/framework/test_case.gd"
## The bomber: the Strategic bombers upgrade (Warfare, tier 5), the vehicle the Airfield builds with it (dear to build, dear to keep, and good for nothing but carrying
## a nuke), and the strike: the bomber flies to the tile you pick, the nuke goes off over it on the day it gets there, and the bomber flies home.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i
var target: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	for r in Data.RESOURCES:
		Game.res[r] = 500
	Game.items["nuke"] = 2
	Game.vehicles["bomber"] = 1
	# open ground a short flight from home, with no crater or river in its square
	target = World.find_tile(func(c, t): return c.distance_to(hq) > 10 and c.distance_to(hq) < 14 and _open(c))
	assert_ne(target, Vector2i(-1, -1), "needs ground for a strike")


func _open(c: Vector2i) -> bool:
	for p in Game.blast_square(c):
		var t: Dictionary = Game.tile(p)
		if not t["t"] in ["sand", "dunes", "scrub"] or t["b"] != "" or t["o"] != Data.NONE:
			return false
	return Game.blast_square(c).size() == 9


func _upgrade_everything() -> void:
	Game.upgrades = ["w1", "w2", "w3", "w4", "wv4"]


func _party(at: Vector2i) -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", at, at)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.stage = "site"
	Units.units.append(u)
	return u


func _strike() -> Dictionary:
	assert_eq(Units.send_status("bomb", "bomber", target), "")
	Units.send("bomb", "bomber", target)
	return Units.units[-1]


# ---------------------------------------------------------------- the upgrade and the vehicle

func test_the_upgrade_tops_the_warfare_vehicles_and_needs_bombing_runs() -> void:
	var u: Dictionary = Data.UPGRADES.wv5
	assert_eq(u.name, "Strategic bombers")
	assert_eq(u.branch, "warfare")
	assert_eq(u.tier, 5)
	assert_true(u.vehicle)
	assert_eq(u.needs, ["wv4"])
	assert_eq(Game.upgrade_status("wv5"), "Needs Bombing runs")
	_upgrade_everything()
	assert_eq(Game.upgrade_cost("wv5"), {"metal": 60, "fuel": 30, "gold": 60})
	assert_eq(Game.upgrade_status("wv5"), "")
	Game.buy_upgrade("wv5")
	assert_true(Game.has("wv5"))
	assert_eq(Game.highest_tier(), 5)


func test_the_airfield_lists_a_bomber_only_with_the_upgrade() -> void:
	Game.vehicles["bomber"] = 0
	assert_eq(Game.vehicle_status("bomber"), "Needs a Airfield")
	Game.tile(hq + Vector2i(2, 0))["b"] = "airfield"
	Game.tile(hq + Vector2i(2, 0))["o"] = Data.PLAYER
	assert_eq(Game.vehicle_status("bomber"), "Needs Strategic bombers")
	_upgrade_everything()
	Game.buy_upgrade("wv5")
	assert_eq(Game.vehicle_status("bomber"), "")


func test_building_pays_the_price_and_two_is_the_most() -> void:
	Game.vehicles["bomber"] = 0
	Game.tile(hq + Vector2i(2, 0))["b"] = "airfield"
	Game.tile(hq + Vector2i(2, 0))["o"] = Data.PLAYER
	_upgrade_everything()
	Game.buy_upgrade("wv5")
	var before := Game.res.duplicate()
	Game.build_vehicle("bomber")
	assert_eq(Game.vehicles["bomber"], 1)
	assert_eq(before.metal - Game.res.metal, 60)
	assert_eq(before.fuel - Game.res.fuel, 25)
	assert_eq(before.gold - Game.res.gold, 70)
	Game.build_vehicle("bomber")
	assert_eq(Game.vehicles["bomber"], 2)
	assert_eq(Game.vehicle_status("bomber"), "Fleet limit reached")
	Game.build_vehicle("bomber")
	assert_eq(Game.vehicles["bomber"], 2)


func test_it_costs_and_keeps_more_than_a_plane() -> void:
	var plane: Dictionary = Data.VEHICLES.plane
	var bomber: Dictionary = Data.VEHICLES.bomber
	for k in plane.cost:
		assert_ge(bomber.cost[k], plane.cost[k] * 2, "to build: %s" % k)
	assert_gt(bomber.upkeep.fuel, plane.upkeep.fuel * 1)
	assert_gt(bomber.upkeep.gold, plane.upkeep.gold * 2)
	assert_lt(bomber.max, plane.max)


func test_the_upkeep_is_paid_every_season_and_a_bomber_that_cannot_be_kept_is_lost() -> void:
	Game.vehicles["bomber"] = 2
	Game.res["fuel"] = 100
	Game.res["gold"] = 100
	Game._upkeep()
	assert_eq(Game.res["fuel"], 100 - 8)
	assert_eq(Game.res["gold"], 100 - 6)
	Game.res["fuel"] = 3
	Game._upkeep()
	assert_eq(Game.vehicles["bomber"], 0, "not even one tankful of the upkeep")
	assert_true(Game.log_lines.any(func(l): return l.contains("Couldn't maintain Bombers")))


func test_a_bomber_does_nothing_but_carry_a_nuke() -> void:
	Game.vehicles["bomber"] = 0
	var attack := Game.player_attack()
	Game.vehicles["bomber"] = 2
	assert_eq(Game.vehicle_attack("bomber"), 0)
	assert_eq(Game.vehicle_trade("bomber"), 0)
	assert_eq(Game.player_attack(), attack, "no raid strength")
	Game.upgrades = ["w1", "w2", "w3", "w4", "wv4"]
	assert_eq(Game.vehicle_attack("bomber"), 0, "and Bombing runs does nothing for it")


# ---------------------------------------------------------------- sending one

func test_a_strike_needs_a_free_bomber_a_nuke_fuel_hands_and_a_tank_that_reaches() -> void:
	Game.vehicles["bomber"] = 0
	assert_eq(Units.send_status("bomb", "bomber", target), "No free bombers")
	Game.vehicles["bomber"] = 1
	Game.items["nuke"] = 0
	assert_eq(Units.send_status("bomb", "bomber", target), "No nukes in the stores")
	Game.items["nuke"] = 1
	Game.res["fuel"] = 13
	assert_eq(Units.send_status("bomb", "bomber", target), "Need 14 fuel")
	Game.res["fuel"] = 500
	Game.pop = 3
	assert_eq(Units.send_status("bomb", "bomber", target), "Need 2 colonists to spare")
	Game.pop = 10
	assert_eq(Units.send_status("bomb", "bomber", target), "")
	var far := Units.send_status("bomb", "bomber", Vector2i(Game.w - 1, Game.h - 1), -1, Vector2i(0, 0))
	assert_true(far.begins_with("Too far: the round trip burns"), far)
	assert_has(far, "the tank holds 14")


func test_any_tile_will_do_even_water_and_ground_nobody_has_seen() -> void:
	var water := World.find_tile(func(c, t): return t["t"] == "water")
	assert_eq(Units.send_status("bomb", "bomber", water), "")
	assert_null(Game.memory[Data.PLAYER][Game.idx(Vector2i(Game.w - 1, Game.h - 1))], "never seen")
	assert_eq(Units.send_status("bomb", "bomber", Vector2i(Game.w - 1, Game.h - 1)), "", "even the far corner is in reach of a full tank")
	assert_eq(Units.send_status("bomb", "bomber", Vector2i(Game.w - 1, 0)), "")


func test_sending_it_loads_the_nuke_and_fills_the_tank() -> void:
	var pop := Game.pop
	var fuel: int = Game.res["fuel"]
	var u := _strike()
	assert_eq(u.job, "bomb")
	assert_eq(u.mover, "bomber")
	assert_eq(u.crew, 2)
	assert_eq(Game.pop, pop - 2)
	assert_eq(Game.res["fuel"], fuel - 14)
	assert_eq(u.fuel, 14.0)
	assert_eq(Game.items["nuke"], 1, "it leaves the stores now")
	assert_eq(Game.stats.sent.bomb, 1)
	assert_eq(Units.vehicles_out("bomber"), 1)
	assert_eq(Units.send_status("bomb", "bomber", target), "No free bombers")
	assert_eq(Units.stage_text(u), "flying to the target")
	assert_eq(Units.glyph_kind(u), "bomber")


func test_the_nuke_goes_off_over_the_tile_and_the_bomber_flies_home() -> void:
	var pop := Game.pop
	var fuel: int = Game.res["fuel"]
	var victim := _party(target + Vector2i(1, 1))
	var far := _party(target + Vector2i(4, 0))
	var u := _strike()
	Units.season_turn()
	assert_eq(u.stage, "back", "it has dropped it and turned for home")
	assert_false(u.get("gone", false), "the bomber is not in its own blast")
	assert_eq(Game.tile(target)["t"], "ash")
	assert_eq(Game.stats.nukes_dropped, 1)
	assert_eq(Game.stats.blasts, 1)
	assert_true(victim.get("gone", false), "a party in the square died")
	assert_false(far.get("gone", false))
	assert_true(Game.log_lines.any(func(l): return l.contains("released its nuke over")))
	var blasts: Array = Units.replay.events.filter(func(e): return e.kind == "blast")
	assert_eq(blasts.size(), 1, "the season's replay plays the explosion")
	assert_eq(blasts[0].cell, target)
	assert_gt(blasts[0].day, 0.0, "on the day it got there")
	assert_eq(Units.stage_text(u), "heading home")
	for i in 4:
		if not Units.units.has(u):
			break
		Units.season_turn()
	assert_false(Units.units.has(u), "home")
	assert_eq(Game.pop, pop, "the crew are back")
	assert_eq(Game.vehicles["bomber"], 1)
	assert_eq(Units.free_vehicles("bomber"), 1, "and it can fly again")
	assert_eq(Game.items["nuke"], 1)
	assert_gt(Game.res["fuel"], fuel - 14, "what was left in the tank came home")


func test_a_strike_on_the_rust_kings_costs_relations() -> void:
	Game.tile(target)["b"] = "ai_wall"
	Game.tile(target)["o"] = Data.AI
	Game.ai["walls"] = 4
	Game.ai["relations"] = 0
	_strike()
	Units.season_turn()
	assert_eq(Game.ai["relations"], -10)
	assert_eq(Game.tile(target)["b"], "")


func test_it_never_runs_dry_even_on_the_farthest_flight() -> void:
	var farthest := hq
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if Vector2(c).distance_to(Vector2(hq)) > Vector2(farthest).distance_to(Vector2(hq)):
			farthest = c
	target = farthest
	var u := _strike()
	for i in 6:
		if not Units.units.has(u):
			break
		Units.season_turn()
	assert_false(Units.units.has(u), "it got home")
	assert_eq(Game.vehicles["bomber"], 1, "and was not lost")
	assert_eq(Game.stats.blasts, 1)
	assert_false(Game.log_lines.any(func(l): return l.contains("OUT OF FUEL")))


func test_a_flight_in_the_air_survives_a_save() -> void:
	var u := _strike()
	var fuel: float = u.fuel
	Game.save_game("flight")
	World.new_game(3)
	assert_true(Game.load_game("flight"))
	assert_eq(Units.units.size(), 1)
	var back: Dictionary = Units.units[0]
	assert_eq(back.job, "bomb")
	assert_eq(back.mover, "bomber")
	assert_eq(back.fuel, fuel)
	assert_false(back.path.is_empty(), "the way is found again")
	Units.season_turn()
	assert_eq(Game.tile(target)["t"], "ash")
	assert_eq(Game.stats.blasts, 1)
	DirAccess.remove_absolute(Game.save_dir + "flight.json")
