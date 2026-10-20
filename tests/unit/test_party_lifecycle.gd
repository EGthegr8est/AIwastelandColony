extends "res://tests/framework/test_case.gd"
## What a Scavenger Party does once it is out: whatever it was sent for, it searches the ruins it stands on, hunts, strikes and keeps
## watch like any other, stays where it is (with what it carries) until it is given orders, is fed from its pack every season, and
## is brought home by a recall.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var ruin: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	ruin = hq + Vector2i(1, -2)   # the ruin every camp starts beside
	Game.pop = 30
	Game.res["grain"] = 100
	D20.loot_scale = D20Data.LOOT_SCALE


func after_each() -> void:
	D20.loot_scale = D20Data.LOOT_SCALE
	Units.dice = load("res://scripts/dice.gd").new()


func _party(job: String, at: Vector2i) -> Dictionary:
	var u: Dictionary = Units._make_unit(job, Data.PLAYER, "foot", at, at)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.food = {"grain": Data.SCOUT_PACK}
	u["number"] = 1
	u.stage = "station"
	Units.units.append(u)
	return u


func test_every_party_takes_a_food_pack_whatever_it_is_sent_for() -> void:
	for job in ["scav", "scout", "hunters"]:
		var grain: int = Game.res["grain"]
		Units.units = []
		var far := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
			and not Game.route("foot", hq, c).is_empty() and Units._animal_can_stand(c))
		Units.send(job, "foot", far)
		var u: Dictionary = Units.units[-1]
		assert_eq(Units.food_total(u), Data.SCOUT_PACK, job)
		assert_eq(Game.res["grain"], grain - Data.SCOUT_PACK, "%s: the pack came from the stores" % job)


func test_a_scavenger_party_is_fed_every_season_like_scouts_are() -> void:
	var u := _party("scav", hq + Vector2i(3, 0))
	var pack := Units.food_total(u)
	Units.season_turn()
	assert_eq(Units.food_total(u), pack - 3 * Data.SCOUT_RATION)


func test_a_party_stands_on_the_ruins_and_can_search_them() -> void:
	var u := _party("scout", ruin)
	assert_eq(Units.scavenge_place(ruin), "ruins")
	assert_eq(Units.scavenge_status(u), "")
	Game.tile(ruin)["r"] = "safe"
	Units.dice = ForcedDice.new([17, 10, 13], [6])
	assert_true(Units.begin_scavenge(u.id))
	assert_eq(u.stage, "site")
	assert_true(u.has("visit"))
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station", "it waits where it searched")
	assert_eq(u.carry, {"fuel": 18}, "with what it found")
	assert_eq(Game.tile(ruin)["r"], "picked")
	assert_eq(Units.scavenge_status(u), "Nothing to search here", "picked clean")


func test_ground_with_nothing_on_it_cannot_be_searched() -> void:
	var plain := World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 5 and Game.poi_kind(c) == "")
	var u := _party("scav", plain)
	assert_eq(Units.scavenge_place(plain), "")
	assert_eq(Units.scavenge_status(u), "Nothing to search here")
	assert_false(Units.begin_scavenge(u.id))
	u.stage = "out"
	assert_eq(Units.scavenge_status(u), "Not waiting for orders")


func test_two_parties_cannot_search_the_same_ruin_at_once() -> void:
	var a := _party("scav", ruin)
	var b := _party("scout", ruin)
	Game.tile(ruin)["r"] = "safe"
	Units.dice = ForcedDice.new([17], [])
	assert_true(Units.begin_scavenge(a.id))
	assert_eq(Units.scavenge_status(b), "A party is already searching here")


func test_a_party_sent_to_a_ruin_searches_it_and_one_sent_to_open_ground_keeps_watch() -> void:
	Game.tile(ruin)["r"] = "safe"
	Units.send("scav", "foot", ruin)
	var u: Dictionary = Units.units[-1]
	for i in 8:
		if u.stage == "site":
			break
		Units.season_turn()
	assert_eq(u.stage, "site", "it began the visit on arriving")
	var plain := World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
		and Game.poi_kind(c) == "" and not Game.route("foot", hq, c).is_empty())
	Units.send("scav", "foot", plain)
	var v: Dictionary = Units.units[-1]
	for i in 8:
		if v.stage == "station":
			break
		Units.season_turn()
	assert_eq(v.stage, "station", "nothing there to search: it keeps watch")
	assert_false(v.has("visit"))


func test_new_orders_cancel_the_animal_a_hunting_party_was_sent_after() -> void:
	var far := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
		and not Game.route("foot", hq, c).is_empty() and Units._animal_can_stand(c))
	var deer: Dictionary = Units._add_animal("deer", far)
	Units.send("hunters", "foot", far, deer.id)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.dest, deer.id)
	Units.order_scouts(u.id, hq + Vector2i(0, 2))
	assert_eq(u.dest, -1, "no longer after the deer")


func test_a_party_that_finishes_stays_until_recalled_and_then_brings_its_loot_home() -> void:
	var u := _party("scav", ruin)
	Game.tile(ruin)["r"] = "safe"
	Units.dice = ForcedDice.new([17, 10, 13], [6])
	Units.begin_scavenge(u.id)
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	for i in 3:
		Units.season_turn()
	assert_eq(u.pos, ruin, "it did not wander off")
	assert_eq(u.stage, "station")
	var fuel: int = Game.res["fuel"]
	var pop: int = Game.pop
	Units.recall_scouts(u.id)
	assert_eq(u.stage, "back")
	for i in 8:
		Units.season_turn()
	assert_true(Units.units.is_empty() or not Units.units.has(u), "it is home")
	assert_eq(Game.res["fuel"], fuel + 18, "the loot is in the stores")
	assert_eq(Game.pop, pop + 3, "and the survivors are home")


func test_every_kind_of_party_can_strike_hunt_and_attack_camps() -> void:
	for job in ["scav", "scout", "hunters"]:
		var u := _party(job, hq)
		u.stage = "station"
		assert_true(Units.strike_targets(u) is Array, job)
		assert_true(Units.camp_targets(u) is Array, job)
		assert_true(Units.hunt_targets(u) is Array, job)
		Units.units.erase(u)


func test_a_party_that_is_picked_clean_waits_for_orders() -> void:
	Game.tile(ruin)["r"] = "picked"
	var u := _party("scav", ruin)
	u.target = ruin
	u.stage = "out"
	Units._begin_visit(u)
	assert_eq(u.stage, "station")
	assert_false(u.has("visit"))
