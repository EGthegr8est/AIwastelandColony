extends "res://tests/framework/test_case.gd"
## Scouting parties: named survivors, staying put, eating, starving and running out of fuel.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var target: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false   # no raiders wander into the middle of a test
	Units.crash_survival = Data.CRASH_SURVIVAL
	Game.res["grain"] = 100
	Game.res["fuel"] = 50
	var hq := Game.home(Data.PLAYER)
	# Dry land a few tiles out that war rigs and planes can both reach
	target = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 6 and c.distance_to(hq) < 10 \
		and not Game.route("car", hq, c).is_empty() and not Game.route("foot", hq, c).is_empty())
	assert_ne(target, Vector2i(-1, -1), "needs a reachable tile near home")


## Sends a party and runs seasons until it reaches the target.
func _send(mover: String) -> Dictionary:
	if mover in Data.VEHICLES:
		Game.vehicles[mover] = 1
	assert_eq(Units.send_status("scout", mover, target), "")
	Units.send("scout", mover, target)
	var u: Dictionary = Units.units[-1]
	World.finish_trip(u)
	return u


func test_survivors_get_names_and_details() -> void:
	var pop := Game.pop
	Units.send("scout", "foot", target)
	var u: Dictionary = Units.units[-1]
	assert_eq(Game.pop, pop - 3)
	assert_eq(u.survivors.size(), 3)
	assert_eq(u.crew, 3)
	assert_ne(u.survivors[0].name, u.survivors[1].name)
	for s in u.survivors:
		assert_has(Data.SURVIVOR_NAMES, s.name)
		assert_gt(s.age, 16)
		assert_eq(s.hunger, 0)
	assert_has(Units.members_text(u), " and ")
	assert_eq(Units.names_text(u), "Scavenger Party 1", "a party is called by its number")


func test_scouts_stay_at_the_tile_until_recalled() -> void:
	var u := _send("foot")
	assert_eq(u.stage, "station")
	assert_eq(u.pos, target)
	u.food = {"grain": 100}   # this test is about staying put, not about the pack running out
	for i in 5:
		Units.season_turn()
	assert_eq(u.pos, target)
	assert_eq(u.stage, "station")
	assert_eq(Units.scouts_out(), 1)
	var pop := Game.pop
	Units.recall_scouts(u.id)
	for i in 12:
		Units.season_turn()
	assert_eq(Units.scouts_out(), 0)
	assert_eq(Game.pop, pop + 3)


func test_scouts_can_be_sent_elsewhere() -> void:
	var u := _send("foot")
	var other := World.find_tile(func(c, t): return t["t"] != "water" and c != target and c.distance_to(target) > 3 \
		and c.distance_to(target) < 8 and not Game.route("foot", target, c).is_empty())
	Units.order_scouts(u.id, other)
	World.finish_trip(u)
	assert_eq(u.pos, other)
	assert_eq(u.stage, "station")


func test_scouts_set_out_with_a_pack_from_the_stores() -> void:
	Game.res["grain"] = 5
	Game.res["veg"] = 10
	Game.res["meat"] = 10
	Units.send("scout", "foot", target)
	var u: Dictionary = Units.units[-1]
	# grain first, then veg
	assert_eq(u.food, {"grain": 5, "veg": Data.SCOUT_PACK - 5})
	assert_eq(Units.food_total(u), Data.SCOUT_PACK)
	assert_eq(Game.res["grain"], 0)
	assert_eq(Game.res["veg"], 10 - (Data.SCOUT_PACK - 5))
	assert_eq(Game.res["meat"], 10)
	assert_eq(Units.food_text(u), "5 grain, %d veg" % (Data.SCOUT_PACK - 5))


func test_scouts_cannot_leave_without_enough_food_for_a_pack() -> void:
	for k in Data.FOOD_KINDS:
		Game.res[k] = 0
	Game.res["grain"] = Data.SCOUT_PACK - 1
	assert_eq(Units.send_status("scout", "foot", target), "Need %d food for the pack (grain, veg or meat)" % Data.SCOUT_PACK)
	Game.res["meat"] = 1   # any mix of food will do
	assert_eq(Units.send_status("scout", "foot", target), "")
	assert_has(Units.send_cost_text("scout", "foot"), "%d food" % Data.SCOUT_PACK)


func test_scouts_eat_from_their_pack_every_season() -> void:
	var u := _send("foot")
	var stores := Game.res.duplicate()
	var pack := Units.food_total(u)
	Units.season_turn()
	assert_eq(Units.food_total(u), pack - u.crew * Data.SCOUT_RATION)
	assert_eq(Game.res, stores, "the stores aren't touched once they've left")


func test_the_pack_feeds_a_party_for_pack_over_crew_seasons() -> void:
	var u := _send("foot")
	u.food = {"grain": 4, "veg": 2}
	assert_almost_eq(Units.food_days(u), 6.0 * Data.SEASON_DAYS / (3 * Data.SCOUT_RATION), 0.001)
	u.food = {}
	assert_eq(Units.food_days(u), 0.0)
	u.survivors = []
	assert_true(is_inf(Units.food_days(u)), "nobody left to feed")


func test_scouts_starve_once_the_pack_is_empty() -> void:
	var u := _send("foot")
	u.food = {}
	assert_gt(Units.food_stock(), 50, "the stores are full, but they're a long way off")
	Units.season_turn()
	assert_eq(u.survivors[0].hunger, 1)
	Units.season_turn()
	assert_eq(Units.hunger_text(u.survivors[0]), "STARVING")
	Units.season_turn()
	assert_eq(u.survivors.size(), 0)
	assert_eq(Units.scouts_out(), 0)


func test_eating_again_ends_the_hunger() -> void:
	var u := _send("foot")
	u.food = {}
	Units.season_turn()
	assert_eq(u.survivors[0].hunger, 1)
	u.food = {"grain": 20}
	Units.season_turn()
	assert_eq(u.survivors[0].hunger, 0)


func test_unspent_food_goes_back_to_the_stores_when_they_come_home() -> void:
	var u := _send("foot")
	var stock := Units.food_stock()
	Units.recall_scouts(u.id)
	for i in 12:
		Units.season_turn()
	assert_eq(Units.scouts_out(), 0)
	assert_gt(Units.food_stock(), stock, "the rest of the pack came home")
	var grain: int = Game.res["grain"]
	var home := _send("foot")
	home.food = {"grain": 3, "veg": 1}
	var before := Units.food_stock()
	Units._come_home(home)
	assert_eq(Units.food_stock(), before + 4)
	assert_eq(Game.res["grain"], grain - Data.SCOUT_PACK + 3)


func test_war_rig_that_runs_dry_becomes_a_party_on_foot() -> void:
	Game.vehicles["car"] = 1
	Units.send("scout", "car", target)
	var u: Dictionary = Units.units[-1]
	assert_le(u.fuel, float(Data.VEHICLE_FUEL.car.tank), "it has burned some on its first day's walk")
	assert_eq(Game.res["fuel"], 50 - Data.VEHICLE_FUEL.car.tank)
	u.fuel = 0.05
	u.move_left = float(Data.SEASON_DAYS)
	Units.continue_orders(u.id)
	Units.season_turn()
	assert_eq(u.mover, "foot")
	assert_false(u.has("fuel"))
	assert_eq(u.stage, "station")
	assert_eq(Game.vehicles["car"], 0)
	assert_eq(u.crew, 3)
	assert_eq(Units.units.size(), 1)


func test_war_rig_that_runs_dry_is_lost_and_nobody_is_hurt() -> void:
	var u := _send("car")
	u.fuel = 0.0
	Units.season_turn()
	assert_eq(u.mover, "foot")
	assert_eq(Game.vehicles["car"], 0)
	assert_eq(u.survivors.size(), 3)
	for s in u.survivors:
		assert_false(s.hurt)
		assert_eq(s.hp, Data.SURVIVOR_HP)
	assert_true(Game.log_lines.any(func(l): return l.contains("war rig ran dry")))


func test_a_plane_that_runs_dry_crashes_and_the_survivors_walk_on_injured() -> void:
	Units.crash_survival = 1.0   # everyone lives through this one
	var u := _send("plane")
	assert_eq(u.mover, "plane")
	u.fuel = 1.0
	Units.season_turn()
	assert_eq(u.mover, "foot")
	assert_false(u.has("fuel"))
	assert_eq(Game.vehicles["plane"], 0, "the plane is lost")
	assert_eq(u.survivors.size(), 3)
	assert_eq(u.pos, target)
	assert_eq(u.stage, "station")
	for s in u.survivors:
		assert_true(s.hurt)
		assert_lt(s.hp, Data.SURVIVOR_HP)
		assert_ge(s.hp, Data.SURVIVOR_HP - Data.CRASH_INJURY.y)
		assert_le(s.hp, Data.SURVIVOR_HP - Data.CRASH_INJURY.x + Data.RAD_RECOVERY)
		assert_has(Units.survivor_line(s), "injured")
	assert_true(Game.log_lines.any(func(l): return l.contains("plane crashed") and l.contains("survived, injured")))


func test_nobody_need_walk_away_from_a_crash() -> void:
	Units.crash_survival = 0.0
	var u := _send("plane")
	var pop := Game.pop
	u.fuel = 1.0
	Units.season_turn()
	assert_eq(Units.scouts_out(), 0, "the whole party is gone")
	assert_eq(Game.vehicles["plane"], 0, "and so is the plane, only once")
	assert_eq(Game.pop, pop, "nobody comes home")
	assert_true(Game.log_lines.any(func(l): return l.contains("Nobody walked away")))


func test_crash_survival_is_a_chance_for_each_person_aboard() -> void:
	seed(11)
	var lived := 0
	var total := 0
	for i in 200:
		var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "plane", target, target)
		u.survivors = Units._make_crew(2)
		u.crew = 2
		u.stage = "station"
		u.fuel = 0.0
		Units.units.append(u)
		Game.vehicles["plane"] = 1
		Units._strand(u)
		total += 2
		lived += u.survivors.size()
		for s in u.survivors:
			assert_true(s.hurt, "everyone who lives is hurt")
		Units.units.erase(u)
	var share := lived / float(total)
	assert_gt(share, Data.CRASH_SURVIVAL - 0.1)
	assert_lt(share, Data.CRASH_SURVIVAL + 0.1)


func test_injured_survivors_heal_and_the_bandage_comes_off() -> void:
	var u := _send("foot")
	var s: Dictionary = u.survivors[0]
	s.hp = Data.SURVIVOR_HP - 1.0
	s.hurt = true
	Units._expose(u)
	assert_eq(s.hp, Data.SURVIVOR_HP)
	assert_false(s.hurt)
	s.hp = 40.0
	s.hurt = true
	Units._expose(u)
	assert_true(s.hurt, "still healing")
	assert_almost_eq(s.hp, 40.0 + Data.RAD_RECOVERY, 0.001)


func test_the_gauge_goes_low_before_the_tank_is_dry() -> void:
	var u := {"fuel": 1.9, "mover": "car"}   # idle 1.0 a season: low under two seasons' worth
	assert_true(Units.fuel_low(u))
	u.fuel = 2.0
	assert_false(Units.fuel_low(u))
	u = {"fuel": 3.9, "mover": "plane"}   # idle 2.0 a season: low under 4
	assert_true(Units.fuel_low(u))
	u.fuel = 4.0
	assert_false(Units.fuel_low(u))
	u = {"fuel": 0.5, "mover": "boat"}   # never idles: low under a fifth of the tank
	assert_true(Units.fuel_low(u))
	u.fuel = 0.7
	assert_false(Units.fuel_low(u))
	assert_false(Units.fuel_low({"mover": "foot"}), "no tank, never low")


func test_stranded_party_on_the_way_home_keeps_walking_home() -> void:
	Game.vehicles["car"] = 1
	var faraway := _far_tile("car", Game.home(Data.PLAYER), 12.0, 18.0)
	assert_ne(faraway, Vector2i(-1, -1))
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "car", faraway, faraway)   # keeping watch out in the wastes, with a full tank
	u.home = Game.home(Data.PLAYER)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.food = {"grain": 30}
	u.stage = "station"
	u.fuel = 0.0   # the tank runs dry on the first step home
	Units.units.append(u)
	Units.recall_scouts(u.id)
	assert_eq(u.mover, "foot", "the rig was abandoned")
	assert_false(u.has("fuel"))
	assert_eq(u.stage, "back", "and the party keeps walking home")
	World.finish_trip(u)
	assert_eq(Units.scouts_out(), 0)


func test_scouts_survive_save_and_load() -> void:
	var u := _send("car")
	u.survivors[0].hunger = 1
	u.survivors[1].hurt = true
	u.survivors[1].hp = 62.0
	Game.save_game("scout_test")
	assert_true(Game.load_game("scout_test"))
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.survivors, u.survivors)
	assert_almost_eq(loaded.fuel, u.fuel, 0.001)
	assert_eq(loaded.food, u.food)
	assert_eq(Units.food_total(loaded), Units.food_total(u))
	assert_eq(loaded.stage, "station")
	assert_eq(loaded.pos, target)
	DirAccess.remove_absolute(Game._path("scout_test"))


func test_scouts_from_an_old_save_get_a_pack() -> void:
	_send("foot")
	Game.save_game("old_scout_test")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game._path("old_scout_test")))
	for u in data.units.units:
		u.erase("food")   # saves from before food packs
	var f := FileAccess.open(Game._path("old_scout_test"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("old_scout_test"))
	assert_eq(Units.food_total(Units.units[0]), Data.SCOUT_PACK)
	DirAccess.remove_absolute(Game._path("old_scout_test"))


# ---------------------------------------------------------------- how far the food goes

## A land tile `from_tile` is `near`..`far` tiles from, that `mover` can reach.
func _far_tile(mover: String, from_tile: Vector2i, near: float, far: float) -> Vector2i:
	return World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(from_tile) > near and c.distance_to(from_tile) < far \
		and not Game.route(mover, from_tile, c).is_empty())


func test_route_timing_matches_the_trip_the_party_really_takes() -> void:
	var hq := Game.home(Data.PLAYER)
	for mover in ["foot", "horse"]:
		World.new_game(7)
		Units.tribes = []
		Units.wild_spawns = false
		Game.res["grain"] = 100
		Game.vehicles["horse"] = 1
		var far := _far_tile(mover, hq, 45.0, 60.0)
		assert_ne(far, Vector2i(-1, -1))
		Units.send("scout", mover, far)
		var u: Dictionary = Units.units[-1]
		u.food = {"grain": 16}   # eight seasons of food, and no more than two people can carry without slowing down
		assert_eq(Units.load_slowdown(u), 1.0, "a light load, so the preview and the real trip agree")
		for s in u.survivors:
			s.hp = 100000.0   # radiation on the way mustn't end the test
		var days := Units.arrival_days(mover, Game.route(mover, hq, far))
		var seasons := 1   # the walk that set out
		while u.stage != "station" and seasons < 30:
			u.move_left = float(Data.SEASON_DAYS)
			Units._go(u)
			seasons += 1
		assert_eq(u.pos, far)
		if mover == "foot":
			assert_gt(seasons, 1, "needs a trip longer than one season")
		assert_eq(seasons, ceili(days[-1] / Data.SEASON_DAYS), "%s: the preview says what the trip really takes" % mover)


func test_route_timing_loses_the_rest_of_a_season_when_a_step_does_not_fit() -> void:
	# A diagonal step over flat ground costs 1.414 days on foot. 28 of them take 39.6 of a season's
	# 40 days, and the 29th doesn't fit in the 0.4 left, so it waits for the next season to start.
	var path := []
	for i in 31:
		var c := Vector2i(i, i)
		Game.tiles[Game.idx(c)]["t"] = "sand"
		Game.slopes[Game.idx(c)] = ""
		path.append(c)
	var days := Units.arrival_days("foot", path)
	assert_eq(days.size(), path.size())
	assert_eq(days[0], 0.0)
	assert_almost_eq(days[1], sqrt(2.0), 0.0001)
	assert_almost_eq(days[28], 28.0 * sqrt(2.0), 0.0001)
	assert_almost_eq(days[29], Data.SEASON_DAYS + sqrt(2.0), 0.0001)


func test_ratios_reach_one_where_the_pack_runs_out() -> void:
	var u := _send("foot")
	u.food = {"grain": 2}   # two eaters, so the pack lasts SEASON_DAYS / SCOUT_RATION days
	var lasts := Units.food_days(u)
	var ratios := Units.food_ratios(u, [0.0, lasts / 2.0, lasts, lasts * 1.5])
	assert_eq(ratios, [0.0, 0.5, 1.0, 1.5])
	u.food = {}
	assert_eq(Units.food_ratios(u, [0.0, 5.0]), [0.0, INF], "an empty pack is out of food everywhere but where they stand")
	u.survivors = []
	assert_eq(Units.food_ratios(u, [0.0, 99.0]), [0.0, 0.0], "nobody to feed, nobody goes hungry")


func test_route_color_fades_from_white_to_yellow_to_red() -> void:
	var MapView = preload("res://scripts/map_view.gd")
	assert_true(MapView.food_color(0.0).is_equal_approx(MapView.FOOD_FULL))
	assert_true(MapView.food_color(Data.FOOD_WARN).is_equal_approx(MapView.FOOD_LOW))
	assert_true(MapView.food_color(1.0).is_equal_approx(MapView.FOOD_OUT))
	assert_eq(MapView.food_color(3.0), MapView.FOOD_OUT)
	assert_eq(MapView.food_color(INF), MapView.FOOD_OUT)
	var halfway_to_yellow: Color = MapView.food_color(Data.FOOD_WARN / 2.0)
	assert_lt(halfway_to_yellow.b, 1.0)
	assert_gt(halfway_to_yellow.b, MapView.FOOD_LOW.b)
	var halfway_to_red: Color = MapView.food_color((Data.FOOD_WARN + 1.0) / 2.0)
	assert_lt(halfway_to_red.g, MapView.FOOD_LOW.g)
	assert_gt(halfway_to_red.g, MapView.FOOD_OUT.g)


# ---------------------------------------------------------------- the pack is any food you have, and food found joins it

func test_the_pack_is_whatever_food_the_colony_has_meat_veg_or_grain() -> void:
	Game.res["grain"] = 0
	Game.res["veg"] = 0
	Game.res["meat"] = 12
	assert_eq(Units.send_status("scout", "foot", target), "", "meat alone will do")
	Units.send("scout", "foot", target)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.food, {"meat": Data.SCOUT_PACK})
	assert_eq(Game.res["meat"], 12 - Data.SCOUT_PACK)
	assert_eq(Units.food_text(u), "%d meat" % Data.SCOUT_PACK)
	Game.res["grain"] = 3
	Game.res["veg"] = 4
	Game.res["meat"] = 20
	Units.send("scout", "foot", target)
	var v: Dictionary = Units.units[-1]
	assert_eq(v.food, {"grain": 3, "veg": 4, "meat": Data.SCOUT_PACK - 7}, "a mix of all three, grain first")


func test_food_a_party_finds_joins_its_pack_and_is_eaten_after_what_it_left_with() -> void:
	var u := _send("foot")
	var loaded: Dictionary = Units._haul(u, {"veg": 6, "metal": 2})
	assert_eq(loaded, {"veg": 6, "metal": 2}, "it says what it took, the food too")
	assert_eq(u.food, {"grain": Data.SCOUT_PACK, "veg": 6})
	assert_eq(u.carry, {"metal": 2}, "only the rest is hauled")
	assert_almost_eq(Units.food_days(u), (Data.SCOUT_PACK + 6) * Data.SEASON_DAYS / (3.0 * Data.SCOUT_RATION), 0.001, "it can stay out that much longer")
	for i in 4:   # three people eat three a season: the grain goes first
		Units._feed(u)
	assert_eq(int(u.food.get("grain", 0)), 0)
	assert_eq(int(u.food.get("veg", 0)), 4)
	assert_eq(Units.food_total(u), Data.SCOUT_PACK + 6 - 12)


func test_a_party_with_an_empty_pack_is_fed_by_what_it_scavenges() -> void:
	var u := _send("foot")
	u.food = {}
	Units.season_turn()
	assert_eq(u.survivors[0].hunger, 1, "an empty pack means hunger")
	Units._haul(u, {"meat": 9})
	Units.season_turn()
	assert_eq(u.survivors[0].hunger, 0, "food found in the field feeds them")
	assert_eq(u.food, {"meat": 6})


func test_found_food_that_was_not_eaten_comes_home_with_the_party() -> void:
	var veg: int = Game.res["veg"]
	var u := _send("foot")
	Units._haul(u, {"veg": 5})
	Units._come_home(u)
	assert_eq(Game.res["veg"], veg + 5)
