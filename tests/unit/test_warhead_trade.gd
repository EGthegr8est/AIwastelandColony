extends "res://tests/framework/test_case.gd"
## Buying a warhead from a trader camp: rare (about 15% of the camps), told to you by a first trade there, 500 gold (250 for a Trader leader), fetched by a caravan on
## horseback or in a war rig, slowed by the crate, and yours only when it gets home. No tribe ever launches a nuke.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i
var camp: Dictionary


func before_each() -> void:
	_new_game("builder")


func _new_game(leader: String) -> void:
	World.new_game(7, leader)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	for r in Data.RESOURCES:
		Game.res[r] = 1000
	Game.upgrades = []
	Game.vehicles["horse"] = 5
	Game.vehicles["car"] = 5
	# a trader camp with a warhead, a short way from home
	var at := World.find_tile(func(c, t): return c.distance_to(hq) > 8 and c.distance_to(hq) < 13 and t["t"] in ["sand", "dunes", "scrub"] and Game.slopes[Game.idx(c)] == "" and t["o"] == Data.NONE)
	camp = {"id": 700, "class": "trader", "name": "Dust Peddlers", "pos": at, "strength": 6, "relations": 0, "found": true, "warhead": true, "warhead_known": true}
	Units.tribes.append(camp)


func _buy(mover := "horse") -> Dictionary:
	assert_eq(Units.send_status("deal", mover, camp.pos, camp.id), "")
	Units.send("deal", mover, camp.pos, camp.id)
	return Units.units[-1]


# ---------------------------------------------------------------- rare, and told to you

func test_about_fifteen_in_a_hundred_trader_camps_hold_a_warhead() -> void:
	var yes := 0
	var n := 3000
	for i in n:
		if Units.holds_warhead(2 + i, Vector2i(5 + i % 100, 5 + (i * 7) % 60)):
			yes += 1
	assert_ge(yes, int(n * 0.12))
	assert_le(yes, int(n * 0.18))
	assert_eq(Units.holds_warhead(55, Vector2i(30, 30)), Units.holds_warhead(55, Vector2i(30, 30)), "the same camp always answers the same")


func test_only_trader_camps_have_one_and_none_is_known_at_first() -> void:
	seed(11)
	Units.tribes = []
	var kinds := {}
	for i in 400:
		var t := Units._spawn_tribe()
		if t.is_empty():
			continue
		kinds[t["class"]] = true
		assert_false(t["warhead_known"], "you have to be told")
		if t["class"] != "trader":
			assert_false(t["warhead"], "%s camps have none" % t["class"])
		Units.tribes.erase(t)
	assert_eq(kinds.size(), 3, "all three kinds were made")


func test_a_first_trade_tells_you_once() -> void:
	camp["warhead_known"] = false
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "horse", camp.pos, camp.pos)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.dest = camp.id
	Units._trade(u)
	assert_true(camp["warhead_known"])
	assert_true(Game.log_lines.any(func(l): return l.contains("Dust Peddlers let slip") and l.contains("500 gold")))
	var lines := Game.log_lines.filter(func(l): return l.contains("let slip")).size()
	Units._trade(u)
	assert_eq(Game.log_lines.filter(func(l): return l.contains("let slip")).size(), lines, "only the first time")


func test_a_camp_without_one_says_nothing() -> void:
	camp["warhead"] = false
	camp["warhead_known"] = false
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "horse", camp.pos, camp.pos)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.dest = camp.id
	Units._trade(u)
	assert_false(camp["warhead_known"])
	assert_false(Game.log_lines.any(func(l): return l.contains("warhead")))


# ---------------------------------------------------------------- the price and the run

func test_the_price_is_500_and_a_trader_leader_pays_half() -> void:
	assert_eq(Game.warhead_price(), 500)
	_new_game("trader")
	assert_eq(Game.warhead_price(), 250)


func test_the_run_needs_a_known_warhead_a_horse_or_a_war_rig_gold_and_a_free_slot() -> void:
	camp["warhead_known"] = false
	assert_eq(Units.send_status("deal", "horse", camp.pos, camp.id), "They have no warhead for sale", "not told yet")
	camp["warhead_known"] = true
	assert_eq(Units.send_status("deal", "foot", camp.pos, camp.id), "A warhead is too heavy for a caravan on foot")
	assert_eq(Units.send_status("deal", "horse", camp.pos, camp.id), "")
	assert_eq(Units.send_status("deal", "car", camp.pos, camp.id), "")
	Game.res["gold"] = 499
	var poor := Units.send_status("deal", "horse", camp.pos, camp.id)
	assert_true(poor.begins_with("Need") and poor.contains("500 gold"), poor)
	Game.res["gold"] = 1000
	assert_eq(Units.send_cost("deal", "horse"), {"grain": 5, "wood": 3, "gold": 500})
	camp["warhead"] = false
	assert_eq(Units.send_status("deal", "horse", camp.pos, camp.id), "They have no warhead for sale", "bought already")


func test_sending_it_pays_the_gold_up_front_and_one_run_at_a_time() -> void:
	Game.upgrades = ["c1"]   # a second caravan slot, so the slots are not what says no
	var gold: int = Game.res["gold"]
	var pop := Game.pop
	var u := _buy("horse")
	assert_eq(gold - Game.res["gold"], 500)
	assert_eq(Game.pop, pop - 2)
	assert_eq(u.job, "deal")
	assert_eq(u.paid, 500)
	assert_eq(Units.glyph_kind(u), "caravan", "drawn as a caravan")
	assert_eq(Game.stats.sent.deal, 1)
	assert_eq(Units.send_status("deal", "car", camp.pos, camp.id), "A caravan is already on its way for it")
	assert_eq(Units.trade_runs(), 1, "it uses a caravan slot")


func test_it_uses_up_the_caravan_slots() -> void:
	for i in Game.caravan_slots():
		var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq, hq)
		u.crew = 2
		Units.units.append(u)
	assert_true(Units.send_status("deal", "horse", camp.pos, camp.id).begins_with("All"))


func test_a_trader_leader_pays_250_up_front() -> void:
	_new_game("trader")
	var gold: int = Game.res["gold"]
	_buy("horse")
	assert_eq(gold - Game.res["gold"], 250)


# ---------------------------------------------------------------- the way home

func test_the_caravan_buys_it_crates_it_and_the_trip_home_is_slow() -> void:
	var u := _buy("horse")
	Units.season_turn()
	assert_false(camp["warhead"], "sold")
	assert_eq(u.carry, {"nuke": 1})
	assert_true(u.crated)
	assert_eq(u.stage, "back")
	assert_eq(Game.stats.nukes_bought, 1)
	assert_true(Game.log_lines.any(func(l): return l.contains("bought a warhead from the Dust Peddlers for 500 gold")))
	assert_almost_eq(Units.load_slowdown(u), 1.25, 0.0001, "50 on a capacity of 40")
	assert_almost_eq(Units.party_slowdown(u), 1.25 * 1.5, 0.0001, "and the crate on top: about 1.9 times as long")
	assert_eq(Game.items["nuke"], 0, "not yours until it is home")
	for i in 6:
		if not Units.units.has(u):
			break
		Units.season_turn()
	assert_false(Units.units.has(u))
	assert_eq(Game.items["nuke"], 1, "home")


func test_a_war_rig_is_slowed_by_the_crate_alone() -> void:
	var u := _buy("car")
	Units.season_turn()
	assert_eq(u.carry, {"nuke": 1})
	assert_eq(Units.load_slowdown(u), 1.0)
	assert_almost_eq(Units.party_slowdown(u), 1.5, 0.0001)


func test_a_caravan_that_is_lost_on_the_way_home_loses_the_warhead_and_the_gold() -> void:
	var u := _buy("horse")
	Units.season_turn()
	assert_eq(u.carry, {"nuke": 1})
	u.crew = 0
	u.survivors = []
	Units._lost(u)   # an ambush on the road
	Units.season_turn()
	assert_eq(Game.items["nuke"], 0)
	assert_eq(Game.res["gold"], 1000 - 500)


func test_if_the_camp_is_gone_or_the_warhead_was_taken_the_gold_comes_back() -> void:
	var u := _buy("horse")
	var gold: int = Game.res["gold"]
	Units.tribes.erase(camp)
	Units.season_turn()
	assert_eq(Game.res["gold"], gold + 500)
	assert_true(u.carry.is_empty())
	assert_true(Game.log_lines.any(func(l): return l.contains("no warhead for sale") and l.contains("500 gold came back")))


func test_a_warhead_run_survives_a_save() -> void:
	var u := _buy("car")
	Units.season_turn()
	Game.save_game("deal")
	World.new_game(3)
	assert_true(Game.load_game("deal"))
	var back: Dictionary = Units.units[0]
	assert_eq(back.job, "deal")
	assert_eq(back.paid, 500)
	assert_true(back.crated)
	assert_eq(back.carry, {"nuke": 1})
	assert_true(Units.tribes.any(func(t): return t.name == "Dust Peddlers" and t.warhead == false and t.warhead_known == true))
	DirAccess.remove_absolute(Game.save_dir + "deal.json")
	assert_eq(u.job, "deal")
