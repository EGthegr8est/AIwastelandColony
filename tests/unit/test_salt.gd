extends "res://tests/framework/test_case.gd"
## The Drug Factory and Salt: the factory turns raw frog hides into Salt a season, adds a little defense, its panel shows what you hold; Salt
## halves a survivor's radiation for five seasons when a party takes it; it sells for a lot and the Rust Kings rarely have any for sale.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	Game.leader_info["perks"] = []   # no Haggler to change the prices
	Game.leader_info["flaw"] = ""
	Game.res["grain"] = 100


func _factory(n := 1) -> Array:
	var tiles := []
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "" and tiles.size() < n:
			Game.tile(c)["b"] = "drug_factory"
			tiles.append(c)
	assert_eq(tiles.size(), n, "needs free tiles of yours")
	return tiles


func _party(crew := 3) -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq + Vector2i(1, 0), hq)
	u.crew = crew
	u.survivors = Units._make_crew(crew)
	Units.units.append(u)
	return u


# ---------------------------------------------------------------- the factory

func test_the_drug_factory_is_a_building_you_can_build_on_any_land_of_yours() -> void:
	var b: Dictionary = Data.BUILDINGS["drug_factory"]
	assert_eq(b.cost, {"wood": 10, "metal": 15, "stone": 10})
	assert_eq(b.defense, 1)
	Game.res["wood"] = 50
	Game.res["metal"] = 50
	Game.res["stone"] = 50
	var free: Vector2i = Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water")[0]
	assert_eq(Game.build_status("drug_factory", free), "")
	Game.build("drug_factory", free)
	assert_eq(Game.tile(free)["b"], "drug_factory")
	assert_eq(Game.res["metal"], 35)


func test_a_drug_factory_adds_one_to_the_colonys_defense() -> void:
	var before := Game.player_wall_defense()
	_factory()
	assert_almost_eq(Game.player_wall_defense(), before + 1.0, 0.001)


func test_it_can_be_attacked_like_a_building() -> void:
	assert_eq(D20Data.BUILDING_DC["drug_factory"], 10)


func test_each_season_a_factory_turns_one_hide_into_two_salt() -> void:
	_factory()
	Game.items["hide"] = 3
	Game._drug_factories()
	assert_eq(Game.items["hide"], 2)
	assert_eq(Game.items["salt"], 2)
	Game._drug_factories()
	Game._drug_factories()
	assert_eq(Game.items["hide"], 0)
	assert_eq(Game.items["salt"], 6, "one frog, six Salt")
	Game._drug_factories()
	assert_eq(Game.items["salt"], 6, "and then there is nothing to process")


func test_two_factories_work_twice_as_fast_but_never_past_the_hides() -> void:
	_factory(2)
	Game.items["hide"] = 3
	Game._drug_factories()
	assert_eq(Game.items["hide"], 1)
	assert_eq(Game.items["salt"], 4)
	Game._drug_factories()
	assert_eq(Game.items["hide"], 0)
	assert_eq(Game.items["salt"], 6)


func test_without_a_factory_the_hides_just_sit_in_the_stores() -> void:
	Game.items["hide"] = 3
	Game._drug_factories()
	assert_eq(Game.items["hide"], 3)
	assert_eq(Game.items["salt"], 0)


func test_ending_the_season_runs_the_factories() -> void:
	_factory()
	Game.items["hide"] = 1
	Game.end_season()
	assert_eq(Game.items["salt"], 2)
	assert_true(Game.log_lines.any(func(l): return l.contains("Drug Factory")))


func test_hides_and_salt_are_not_resources_and_have_no_line_in_the_top_bar() -> void:
	assert_false(Data.RESOURCES.has("hide"))
	assert_false(Data.RESOURCES.has("salt"))
	assert_true(Data.ITEMS.has("hide") and Data.ITEMS.has("salt"))
	assert_eq(Game.items, {"hide": 0, "salt": 0})


func test_hides_and_salt_are_carried_and_weigh_something() -> void:
	var u := _party()
	assert_gt(Units.goods_weight({"hide": 1}), Units.goods_weight({"metal": 1}), "a raw hide is heavy")
	assert_gt(Units.goods_weight({"salt": 2}), 0.0)


# ---------------------------------------------------------------- taking Salt on a trip

func test_salt_is_not_taken_unless_you_switch_it_on() -> void:
	Game.items["salt"] = 10
	assert_false(Game.salt_on)
	var target := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 4 and c.distance_to(hq) < 8 and not Game.route("foot", hq, c).is_empty())
	Units.send("scav", "foot", target)
	assert_eq(Game.items["salt"], 10)
	for s in Units.units[-1].survivors:
		assert_eq(s.salted, 0)


func test_a_party_takes_a_dose_for_each_survivor_when_salt_is_on() -> void:
	Game.items["salt"] = 10
	Game.salt_on = true
	var target := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 4 and c.distance_to(hq) < 8 and not Game.route("foot", hq, c).is_empty())
	assert_eq(Units.salt_doses("scav"), 3)
	assert_has(Units.send_cost_text("scav", "foot"), "3 Salt")
	Units.send("scav", "foot", target)
	assert_eq(Game.items["salt"], 7)
	for s in Units.units[-1].survivors:
		assert_eq(s.salted, Data.SALT_SEASONS)


func test_not_enough_salt_for_the_whole_party_means_none_is_taken() -> void:
	Game.items["salt"] = 2
	Game.salt_on = true
	assert_eq(Units.salt_doses("scav"), 0, "three survivors need three doses")
	assert_eq(Units.salt_doses("scout"), 2)


func test_salt_halves_the_radiation_a_survivor_takes_in() -> void:
	var plain := _party(1)
	var salted := _party(1)
	salted.survivors[0]["salted"] = Data.SALT_SEASONS
	for u in [plain, salted]:
		u.rad_days = 40.0 * 60.0   # a season spent in 60 R/h
		u.moved = true
	Units._expose(plain)
	Units._expose(salted)
	assert_gt(plain.survivors[0].dose, 0.0)
	assert_almost_eq(salted.survivors[0].dose, plain.survivors[0].dose * Data.SALT_RESIST, 0.01)


func test_a_dose_lasts_five_seasons() -> void:
	var u := _party(1)
	u.survivors[0]["salted"] = Data.SALT_SEASONS
	for i in Data.SALT_SEASONS:
		assert_gt(u.survivors[0].salted, 0)
		Units._expose(u)
	assert_eq(u.survivors[0].salted, 0)


func test_a_whole_salted_party_feels_the_radiation_half_as_much_in_its_rolls() -> void:
	var u := _party(3)
	u.pos = Game.owned(Data.PLAYER)[0]
	Game.tile(u.pos)["rad"] = 60
	var plain: float = Units.visit_ctx(u).radiation
	for s in u.survivors:
		s["salted"] = 3
	assert_almost_eq(Units.visit_ctx(u).radiation, plain * Data.SALT_RESIST, 0.001)
	u.survivors[0]["salted"] = 0
	assert_almost_eq(Units.visit_ctx(u).radiation, plain, 0.001, "only if everyone is")


func test_a_salted_survivor_shows_it_in_the_party_panel() -> void:
	var u := _party(1)
	u.survivors[0]["salted"] = 4
	assert_has(Units.survivor_line(u.survivors[0]), "salted (4 seasons)")


func test_salt_in_a_survivor_survives_saving() -> void:
	var u := _party(2)
	u.survivors[0]["salted"] = 3
	Game.items["salt"] = 4
	Game.items["hide"] = 2
	Game.salt_on = true
	Game.save_game("salt_test")
	assert_true(Game.load_game("salt_test"))
	assert_eq(Units.units[0].survivors[0].salted, 3)
	assert_eq(Game.items, {"hide": 2, "salt": 4})
	assert_true(Game.salt_on)


# ---------------------------------------------------------------- trade

func test_salt_sells_for_thirty_gold_and_costs_sixty() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	assert_eq(Game.salt_sell_gold(), 30)
	assert_eq(Game.salt_buy_price(), 60)
	Game.items["salt"] = 2
	var gold: int = Game.res["gold"]
	Game.sell_salt()
	assert_eq(Game.items["salt"], 1)
	assert_eq(Game.res["gold"], gold + 30)


func test_the_market_sells_salt_only_when_it_has_some() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.res["gold"] = 200
	Game.buy_salt()
	assert_eq(Game.items["salt"], 0, "none for sale")
	Game.ai["salt_stock"] = 2
	Game.buy_salt()
	assert_eq(Game.items["salt"], 1)
	assert_eq(Game.res["gold"], 140)
	assert_eq(Game.salt_for_sale(), 1)


func test_you_cannot_buy_salt_you_cannot_afford() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.ai["salt_stock"] = 1
	Game.res["gold"] = 59
	Game.buy_salt()
	assert_eq(Game.items["salt"], 0)


func test_the_rust_kings_stock_salt_about_one_season_in_ten() -> void:
	var stocked := 0
	var seasons := 2000
	for i in seasons:
		Game.ai["salt_stock"] = 0
		Game._restock_salt()
		if Game.salt_for_sale() > 0:
			stocked += 1
			assert_true(Game.salt_for_sale() >= Data.SALT_STOCK_DOSES[0] and Game.salt_for_sale() <= Data.SALT_STOCK_DOSES[1])
	assert_gt(stocked, int(seasons * 0.07))
	assert_lt(stocked, int(seasons * 0.13))


func test_a_caravan_to_a_trader_camp_rarely_brings_a_dose_home() -> void:
	Units.tribes.append({"id": 40, "class": "trader", "name": "Traders", "pos": hq + Vector2i(9, 0), "strength": 1, "relations": 0, "found": true})
	var doses := 0
	var trips := 1500
	for i in trips:
		var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq + Vector2i(9, 0), hq)
		u.crew = 2
		u.survivors = Units._make_crew(2)
		u.dest = 40
		Units._trade(u)
		if u.carry.has("salt"):
			doses += 1
			assert_eq(u.carry["salt"], 1)
	assert_gt(doses, int(trips * 0.03))
	assert_lt(doses, int(trips * 0.08))
