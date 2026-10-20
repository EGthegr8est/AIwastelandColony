extends "res://tests/framework/test_case.gd"
## Your parties walk when you order it, spending the days they have left this turn (40 a turn, Data.SEASON_DAYS), and END SEASON gives
## the days back without walking anyone. A search or a fight is not limited by days: only the walk is.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var ruin: Vector2i
var far: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	ruin = hq + Vector2i(1, -2)   # the ruin every camp starts beside
	Game.pop = 30
	Game.res["grain"] = 200
	D20.loot_scale = D20Data.LOOT_SCALE
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 30 and c.distance_to(hq) < 45 \
		and not Game.route("foot", hq, c).is_empty())
	assert_ne(far, Vector2i(-1, -1), "needs a tile a long walk away")


func after_each() -> void:
	D20.loot_scale = D20Data.LOOT_SCALE
	Units.dice = load("res://scripts/dice.gd").new()


func test_a_party_walks_as_soon_as_it_is_sent_and_spends_days() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	assert_ne(u.pos, hq, "it is already on its way")
	assert_eq(u.stage, "out", "but the walk is longer than a turn")
	assert_false(u.path.is_empty())
	assert_lt(u.move_left, 12.0, "a day's allowance is nearly spent")
	assert_ge(u.move_left, 0.0)
	assert_lt(Game.route("foot", hq, far).size() - u.path.size(), Game.route("foot", hq, far).size())


func test_end_season_gives_the_days_back_and_does_not_walk_anyone() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	var where: Vector2i = u.pos
	var left: Array = [u.path.size()]
	Units.season_turn()
	assert_eq(u.pos, where, "the party stays where you left it")
	assert_eq(u.path.size(), left[0], "with its orders still to carry out")
	assert_eq(u.move_left, float(Data.SEASON_DAYS), "and a whole new turn's days")


func test_continue_walks_on_with_the_days_it_has() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	assert_eq(Units.continue_status(u), "", "days left to spend")
	u.move_left = 0.0
	assert_eq(Units.continue_status(u), "No days left this turn")
	Units.season_turn()
	var before: Vector2i = u.pos
	assert_eq(Units.continue_status(u), "")
	Units.continue_orders(u.id)
	assert_ne(u.pos, before, "it walked a turn's worth")
	assert_lt(u.move_left, 12.0)


func test_continuing_until_it_gets_there_takes_as_many_turns_as_the_route_needs() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	var turns := 1
	while u.stage == "out" and turns < 40:
		Units.season_turn()
		Units.continue_orders(u.id)
		turns += 1
	assert_eq(u.stage, "station")
	assert_eq(u.pos, far)
	assert_gt(turns, 1)
	assert_eq(turns, ceili(Units.arrival_days("foot", Game.route("foot", hq, far))[-1] / Data.SEASON_DAYS), "the preview's turns are the real ones")


func test_a_party_cannot_continue_in_the_middle_of_a_search_or_with_nowhere_to_go() -> void:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.stage = "site"
	assert_eq(Units.continue_status(u), "In the middle of a search")
	u.stage = "station"
	assert_eq(Units.continue_status(u), "No orders to carry on with")
	var caravan: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", ruin, ruin)
	assert_eq(Units.continue_status(caravan), "Not one of your parties")


func test_a_party_that_reaches_its_ruin_in_the_turn_starts_searching_at_once() -> void:
	Game.tile(ruin)["r"] = "safe"
	Units.send("scav", "foot", ruin)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.stage, "site", "no END SEASON needed")
	assert_true(u.has("visit"))
	assert_eq(u.pos, ruin)


func test_rolls_cost_no_days_and_can_go_on_as_long_as_the_party_is_alive() -> void:
	Game.tile(ruin)["r"] = "safe"
	Units.dice = ForcedDice.new([17, 14, 12, 15, 11, 13], [6, 6, 6, 6])
	Units.send("scav", "foot", ruin)
	var u: Dictionary = Units.units[-1]
	var days: float = u.move_left
	var rolls := 0
	while u.visit.stage != "done" and rolls < 12:
		Units.visit_do(u.id, "deeper" if u.visit.stage == "search_more" else "roll")
		rolls += 1
	assert_gt(rolls, 1, "more than one roll was made")
	assert_eq(u.move_left, days, "and none of them cost a day")


func test_a_new_order_walks_at_once_and_a_recall_brings_the_party_home_within_the_days_it_has() -> void:
	var near := hq + Vector2i(0, 3)
	Units.send("scout", "foot", near)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.stage, "station")
	var survivors: Array = u.survivors.duplicate()
	var pop := Game.pop
	Units.recall_scouts(u.id)
	assert_false(Units.units.has(u), "it was close enough to be home within the turn")
	assert_eq(Game.pop, pop + 3)
	for s in survivors:
		assert_eq(s.state, "home")


func test_the_days_a_party_did_not_walk_count_as_time_where_it_stands() -> void:
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", hq + Vector2i(3, 0), hq + Vector2i(3, 0))
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.food = {"grain": 30}
	u.stage = "station"
	Units.units.append(u)
	Game.tiles[Game.idx(u.pos)]["rad"] = 20
	u["moved"] = true
	u["rad_days"] = 0.0
	u["move_left"] = 10.0
	Units._scout_turn(u)
	assert_almost_eq(u.rad_days, Game.radiation(u.pos) * 10.0, 0.001, "ten idle days in the radiation")
	assert_eq(u.move_left, float(Data.SEASON_DAYS))


func test_a_caravan_still_walks_at_end_season() -> void:
	var u: Dictionary = Units._make_unit("caravan", Data.PLAYER, "foot", hq, far)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "out"
	u.path = Game.route("foot", hq, far).slice(1)
	Units.units.append(u)
	Units.season_turn()
	assert_ne(u.pos, hq, "only your Scavenger Parties walk on your orders")


func test_the_days_left_are_saved_with_the_party() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	var left: float = u.move_left
	Game.save_game("move_test")
	assert_true(Game.load_game("move_test"))
	var loaded: Dictionary = Units.units[0]
	assert_almost_eq(loaded.move_left, left, 0.001)
	assert_false(loaded.path.is_empty(), "and its route is rebuilt")
	assert_eq(Units.days_left_text(loaded), "%d days left this turn" % floori(left))


func test_the_preview_starts_from_the_days_a_party_has_left_this_turn() -> void:
	var path := Game.route("foot", hq, far)
	var fresh := Units.arrival_days("foot", path)
	assert_eq(Units.arrival_days("foot", path, 1.0, float(Data.SEASON_DAYS)), fresh, "a whole turn's days is what no argument means")
	var tired := Units.arrival_days("foot", path, 1.0, 0.5)   # half a day left: the first step waits for the next turn
	assert_almost_eq(tired[1], 0.5 + fresh[1], 0.0001)
	assert_almost_eq(tired[-1], fresh[-1] + 0.5, 0.0001, "everything after it is that much later")
