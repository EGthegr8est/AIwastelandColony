extends "res://tests/framework/test_case.gd"
## The resource economy: metal is the ruin resource (scrap is gone), gold is the one currency (silver is
## gone), and fuel is scarce but comes home with the party that didn't burn it.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Dice = preload("res://scripts/dice.gd")

const RETIRED := ["scrap", "silver"]

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


## Every place inside `v` (dictionaries, arrays, strings) that names a retired resource.
func _mentions(v, path: String, out: Array) -> void:
	if v is Dictionary:
		for k in v:
			if str(k) in RETIRED:
				out.append("%s.%s" % [path, k])
			_mentions(v[k], "%s.%s" % [path, k], out)
	elif v is Array:
		for i in v.size():
			_mentions(v[i], "%s[%d]" % [path, i], out)
	elif v is String and v in RETIRED:
		out.append(path)


## One whole safe-ruin visit with real dice, by a party of one scout with no traits, always slipping away from
## fights and heading home from a deeper search. Returns the finished visit.
func _visit(scale: float) -> Dictionary:
	var party := [D20.new_scout("Mara", [])]
	var v := D20Visit.begin("safe", {"radiation": 0.0, "party_strength": 3}, scale, Dice.new())
	var guard := 0
	while v.stage != "done" and guard < 30:
		guard += 1
		D20Visit.step(v, Dice.new(), party, {"deeper": "home", "choice": "slip", "event": "roll"}.get(v.stage, "roll"))
	return v


# ---------------------------------------------------------------- scrap and silver are gone

func test_scrap_and_silver_are_named_nowhere_in_the_game_data() -> void:
	var found := []
	var tables := {"RESOURCES": Data.RESOURCES, "TERRAIN": Data.TERRAIN, "BUILDINGS": Data.BUILDINGS, "UPGRADES": Data.UPGRADES,
		"VEHICLES": Data.VEHICLES, "AI_VEHICLES": Data.AI_VEHICLES, "EXPEDITIONS": Data.EXPEDITIONS, "WEIGHT": Data.WEIGHT,
		"MARKET": Data.MARKET, "RESOURCE_TABLE": D20Data.RESOURCE_TABLE, "PACKAGES": D20Data.PACKAGES, "TRIBE_GOODS": Data.TRIBE_GOODS}
	for name in tables:
		_mentions(tables[name], name, found)
	assert_eq(found, [], "still mentioned: %s" % ", ".join(found))


func test_no_description_talks_about_scrap_or_silver() -> void:
	for table in [Data.BUILDINGS, Data.UPGRADES, Data.VEHICLES, Data.TERRAIN, Data.EXPEDITIONS]:
		for id in table:
			var text: String = (str(table[id].get("desc", "")) + " " + str(table[id].get("name", ""))).to_lower()
			for word in RETIRED:
				assert_false(text.contains(word), "%s mentions %s" % [id, word])


func test_a_new_game_keeps_no_scrap_or_silver() -> void:
	for r in RETIRED:
		assert_false(Game.res.has(r), r)
	assert_eq(Game.res.keys().size(), Data.RESOURCES.size())
	assert_eq(Data.RESOURCES.size(), 8)


func test_every_resource_has_a_weight_and_no_weight_is_left_over() -> void:
	for r in Data.RESOURCES:
		assert_true(Data.WEIGHT.has(r), "%s needs a weight" % r)
	assert_eq(Data.WEIGHT.keys().size(), Data.RESOURCES.size(), "no weights for resources that don't exist")


func test_the_silver_exchange_is_gone() -> void:
	assert_false(Game.has_method("exchange"))
	assert_eq(Data.UPGRADES["c2"].name, "Trade contracts")


# ---------------------------------------------------------------- metal does what scrap did

func test_ruins_and_salvage_yards_give_metal() -> void:
	assert_eq(Data.TERRAIN["ruins"].yield, {"metal": 1})
	assert_eq(Data.BUILDINGS["salvage"].yield, {"metal": 3})


func test_war_rigs_and_their_workshops_are_paid_in_metal() -> void:
	assert_eq(Data.VEHICLES["car"].cost, {"metal": 11, "wood": 4})
	assert_eq(Data.UPGRADES["wv2"].cost, {"metal": 20})
	Game.upgrades.append_array(["f1", "f2"])   # tier 2: war rigs unlock
	var spot: Vector2i = Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "")[0]
	Game.tile(spot)["b"] = "motor_pool"
	Game.res.merge({"metal": 10, "wood": 4}, true)
	assert_has(Game.vehicle_status("car"), "metal", "10 metal is one short")
	Game.res["metal"] = 11
	assert_eq(Game.vehicle_status("car"), "")
	Game.build_vehicle("car")
	assert_eq(Game.vehicles["car"], 1)
	assert_eq(Game.res["metal"], 0)
	assert_eq(Game.res["wood"], 0)


func test_war_rig_workshops_take_a_quarter_off_in_metal() -> void:
	Game.upgrades.append("wv2")
	assert_eq(Game.vehicle_cost("car"), {"metal": 9, "wood": 3})


func test_the_motor_pool_builds_war_rigs() -> void:
	assert_eq(Data.BUILDINGS["motor_pool"].name, "Motor pool")
	assert_false(Data.BUILDINGS.has("scrapyard"))
	assert_eq(Data.VEHICLES["car"].building, "motor_pool")


func test_a_save_with_a_scrapyard_loads_it_as_a_motor_pool() -> void:
	var spot: Vector2i = Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "")[0]
	Game.tile(spot)["b"] = "motor_pool"
	Game.save_game("pool_test")
	var path: String = Game._path("pool_test")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["tiles"][Game.idx(spot)][2] = "scrapyard"   # how an older save spelled it
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	World.new_game(99)
	assert_true(Game.load_game("pool_test"))
	DirAccess.remove_absolute(path)
	assert_eq(Game.tile(spot)["b"], "motor_pool")


func test_the_trader_tribes_pay_in_the_goods_that_are_left() -> void:
	assert_eq(Data.TRIBE_GOODS, ["grain", "veg", "meat", "metal", "fuel"])


# ---------------------------------------------------------------- what a ruin gives

func test_a_ruin_pays_in_metal_fuel_gold_and_veg_and_never_in_retired_goods() -> void:
	seed(4)
	var totals := {}
	for i in 600:
		var v := _visit(D20.loot_scale)
		for r in v.loot:
			assert_has(["metal", "fuel", "gold", "veg"], r)
			totals[r] = totals.get(r, 0) + v.loot[r]
	assert_gt(totals.get("metal", 0), totals.get("fuel", 0), "metal is the main ruin resource")
	assert_gt(totals.get("metal", 0), totals.get("veg", 0))
	for r in RETIRED:
		assert_false(totals.has(r))


func test_an_average_safe_ruin_is_worth_a_bit_under_what_it_used_to_pay() -> void:
	seed(9)
	var value := 0.0
	var prices := {"metal": 0.8, "fuel": 0.8, "gold": 1.0, "veg": 0.2}   # the Rust Kings' sell prices
	var n := 3000
	for i in n:
		var v := _visit(D20.loot_scale)
		for r in v.loot:
			value += v.loot[r] * prices[r]
	assert_true(value / n >= 6.5 and value / n <= 11.5, "about 9 gold-equivalent a visit for a party with no traits (it was 11.4 before), got %.2f" % (value / n))


func test_a_war_rig_brings_back_half_as_much_again() -> void:
	var ruin := hq + Vector2i(1, -2)
	Game.vehicles["car"] = 1
	Game.res["fuel"] = 10
	Game.pop = 20
	Units.send("scav", "car", ruin)
	var u: Dictionary = Units.units[-1]
	Units._begin_visit(u)
	assert_almost_eq(u.visit.scale, D20.loot_scale * Data.SCAV_CAR_MULT, 0.0001)
	var foot_party := Units._make_unit("scav", Data.PLAYER, "foot", hq, ruin)
	foot_party.crew = 3
	foot_party.survivors = Units._make_crew(3)
	foot_party.target = ruin
	Game.tile(ruin)["r"] = "safe"
	Units._begin_visit(foot_party)
	assert_almost_eq(foot_party.visit.scale, D20.loot_scale, 0.0001)


func test_a_war_rig_run_costs_a_flat_2_fuel_and_a_foot_party_none() -> void:
	assert_eq(Units.send_cost("scav", "car"), {"grain": 3, "fuel": Data.SCAV_CAR_FUEL})
	assert_eq(Units.send_cost("scav", "foot"), {"grain": 3})
	assert_eq(Units.send_cost("scav", "horse"), {"grain": 3})
	Game.vehicles["car"] = 1
	var ruin := hq + Vector2i(1, -2)   # the ruin that every camp starts beside
	assert_eq(Game.tile(ruin)["t"], "ruins")
	Game.res["fuel"] = 1
	assert_has(Units.send_status("scav", "car", ruin), "fuel", "one fuel is not enough")
	Game.res["fuel"] = 5
	assert_eq(Units.send_status("scav", "car", ruin), "")
	Units.send("scav", "car", ruin)
	assert_eq(Game.res["fuel"], 5 - Data.SCAV_CAR_FUEL)
	assert_false(Units.units[-1].has("fuel"), "a flat fee, not a tank")


# ---------------------------------------------------------------- fuel

func test_a_refinerys_fuel_is_worth_no_more_gold_than_before() -> void:
	var gold_per_fuel: float = float(Data.MARKET["fuel"][1]) / Data.MARKET["fuel"][0]
	assert_le(Data.REFINERY_FUEL * gold_per_fuel, 2.4 + 0.0001, "selling a refinery's fuel must not out-earn a trading post")
	assert_eq(Data.MARKET["fuel"], [5, 4])


func test_unspent_tank_fuel_comes_home_in_whole_units() -> void:
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "car", hq, hq)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.fuel = 5.7
	Game.res["fuel"] = 10
	Units._come_home(u)
	assert_eq(Game.res["fuel"], 15, "5 whole units come back")
	assert_false(u.has("fuel"))
	assert_true(Game.log_lines.any(func(l): return l.contains("fuel left in the tank")))


func test_a_nearly_dry_tank_returns_nothing() -> void:
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "plane", hq, hq)
	u.crew = 1
	u.survivors = Units._make_crew(1)
	u.fuel = 0.9
	Game.res["fuel"] = 10
	Units._come_home(u)
	assert_eq(Game.res["fuel"], 10)


func test_a_recalled_war_rig_scout_gets_its_fuel_back() -> void:
	Game.res["fuel"] = 50
	Game.res["grain"] = 100
	Game.vehicles["car"] = 1
	var target := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 4 and c.distance_to(hq) < 8 \
		and not Game.route("car", hq, c).is_empty())
	Units.send("scout", "car", target)
	var u: Dictionary = Units.units[-1]
	var filled: int = 50 - Data.VEHICLE_FUEL.car.tank
	assert_eq(Game.res["fuel"], filled)
	Units.season_turn()   # it drives out and parks
	assert_eq(u.stage, "station")
	Units.recall_scouts(u.id)
	for i in 8:
		Units.season_turn()
	assert_eq(Units.scouts_out(), 0)
	assert_gt(Game.res["fuel"], filled + 3, "what the tank still held came home")
	assert_lt(Game.res["fuel"], 50, "but the drive and the wait cost something")


func test_vehicles_pay_upkeep_only_while_they_are_at_home() -> void:
	Game.vehicles["car"] = 2
	var away: Dictionary = Units._make_unit("scav", Data.PLAYER, "car", hq, hq)
	away.crew = 2
	away.survivors = Units._make_crew(2)
	Units.units.append(away)
	Game.res["fuel"] = 10
	Game._upkeep()
	assert_eq(Game.res["fuel"], 9, "only the rig at home burns its 1 fuel")
	Units.units.erase(away)
	Game._upkeep()
	assert_eq(Game.res["fuel"], 7, "both at home: 2 fuel")


# ---------------------------------------------------------------- gold is the one currency

func test_what_silver_used_to_buy_is_paid_in_gold_at_the_old_rate() -> void:
	# 10 gold used to swap for 8 silver, so one silver is worth 1.25 gold
	assert_eq(Data.UPGRADES["c4"].cost, {"gold": 63}, "Bribery: 50 gold and 10 silver were 62.5")
	assert_eq(Data.UPGRADES["c5"].cost, {"gold": 128}, "Merchant empire: 90 gold and 30 silver were 127.5")
	assert_eq(Data.VEHICLES["plane"].cost, {"metal": 20, "fuel": 10, "gold": 28}, "planes: 15 gold and 10 silver were 27.5")


func test_trade_contracts_add_gold_to_every_caravan() -> void:
	var plain := _caravan_gold()
	Game.upgrades.append_array(["c1", "c2"])
	assert_eq(_caravan_gold(), plain + Data.CONTRACT_GOLD)
	assert_eq(Data.CONTRACT_GOLD, 4)


## The gold a foot caravan brings home from the Rust Kings (and a check that it brings nothing else).
func _caravan_gold() -> int:
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq, hq)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	Game.ai["relations"] = 0
	Units._trade(u)
	assert_eq(u.carry.keys(), ["gold"], "gold and nothing else")
	return u.carry["gold"]


func test_toll_roads_pay_1_gold_for_every_2_walls() -> void:
	Game.pop = 100   # plenty of workers, so no tile goes untended
	Game.upgrades.append("b_fc")
	Game.res["gold"] = 0
	Game._gather()
	var base: int = Game.res["gold"]
	var spots: Array = Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "")
	for i in 5:
		Game.tile(spots[i])["b"] = "wall"
	Game.res["gold"] = 0
	Game._gather()
	assert_eq(Game.res["gold"], base + 2, "5 walls pay 2 gold")


# ---------------------------------------------------------------- old saves

func test_a_save_with_scrap_and_silver_loads_without_them() -> void:
	var carrier: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq, hq)
	carrier.crew = 2
	carrier.survivors = Units._make_crew(2)
	carrier.carry = {"metal": 3}
	Units.units.append(carrier)
	Game.save_game("economy_test")
	var path: String = Game._path("economy_test")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["res"]["scrap"] = 12
	data["res"]["silver"] = 3
	data["units"]["units"][0]["carry"]["scrap"] = 4
	data["units"]["units"][0]["carry"]["silver"] = 2
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	World.new_game(99)
	assert_true(Game.load_game("economy_test"))
	DirAccess.remove_absolute(path)
	for r in RETIRED:
		assert_false(Game.res.has(r), "%s was dropped from the stores" % r)
		assert_false(Units.units[0].carry.has(r), "%s was dropped from the pack" % r)
	assert_eq(Units.units[0].carry["metal"], 3)
