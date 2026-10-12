extends "res://tests/framework/test_case.gd"
## Simulation tests: map generation, travel, land, seasons, fog and saves.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")


func before_each() -> void:
	World.new_game(7)


func test_same_seed_makes_the_same_map() -> void:
	var first := Game.tiles.duplicate(true)
	World.new_game(7)
	assert_eq(Game.tiles, first)
	World.new_game(8)
	assert_ne(Game.tiles, first)


func test_map_has_all_three_settlements() -> void:
	assert_eq(Game.tiles.size(), Data.MAP_W * Data.MAP_H)
	assert_eq(Game.tile(Data.PLAYER_START)["b"], "hq")
	assert_eq(Game.tile(Data.AI_START)["b"], "ai_hq")
	assert_eq(Game.tile(Data.TOWN_START)["b"], "town")
	assert_gt(Game.owned(Data.PLAYER).size(), 20)


func test_war_rigs_cannot_climb_steep_inclines() -> void:
	var i := Game.slopes.find("steep")
	if i == -1:
		skip("this map has no steep inclines")
		return
	var c := Vector2i(i % Game.w, i / Game.w)
	assert_true(Game.paths["car"].is_point_solid(c))
	assert_false(Game.paths["foot"].is_point_solid(c))
	assert_eq(Game.move_mult("foot", c), Data.MOVERS.foot.steep)


func test_routes_run_from_start_to_goal() -> void:
	var from := Game.home(Data.PLAYER)
	var to := Game.home(Data.TOWN)
	var path := Game.route("foot", from, to)
	assert_eq(path[0], from)
	assert_eq(path[-1], to)
	assert_gt(Game.route_days("foot", path), 0.0)


func test_claiming_a_border_tile_costs_wood() -> void:
	var c := World.claimable_tile()
	var cost := Game.claim_cost(c)
	var wood: int = Game.res.wood
	assert_eq(Game.claim_status(c), "")
	Game.claim(c)
	assert_eq(Game.tile(c)["o"], Data.PLAYER)
	assert_eq(Game.res.wood, wood - cost.wood)
	assert_eq(Game.claim_status(c), "Already yours")


func test_farms_go_on_your_own_sand() -> void:
	var c := World.find_tile(func(_c, t): return t["o"] == Data.PLAYER and t["t"] == "sand" and t["b"] == "")
	Game.build("farm", c)
	assert_eq(Game.tile(c)["b"], "farm")
	assert_eq(Game.build_status("farm", c), "Tile already has a building")
	var far := World.find_tile(func(_c, t): return t["o"] == Data.NONE and t["t"] == "sand")
	assert_eq(Game.build_status("farm", far), "Not your land")


## Free tiles on your land, for putting refineries on.
func _spots(n: int) -> Array:
	return Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "").slice(0, n)


## One season's gathering with `n` refineries on your land, `running` of them switched on: how much
## each store changed. The stores start as `stores` (others keep what they had).
func _gather_with(n: int, running: int, stores: Dictionary) -> Dictionary:
	var spots := _spots(n)
	for i in n:
		Game.tile(spots[i])["b"] = "refinery"
		if i < running:
			Game.set_refinery(spots[i], true)
	Game.res.merge(stores, true)
	var before := Game.res.duplicate()
	Game._gather()
	var change := {}
	for k in Game.res:
		change[k] = Game.res[k] - before[k]
	for c in spots:
		Game.tile(c)["b"] = ""
	Game.refinery_on = {}
	return change


## What `n` refineries (`running` of them switched on) do on their own: the change in each store
## beyond what the land gives anyway.
func _refined(n: int, stores: Dictionary, running := -1) -> Dictionary:
	var plain := _gather_with(0, 0, stores)
	var refined := _gather_with(n, n if running < 0 else running, stores)
	var out := {}
	for k in refined:
		out[k] = refined[k] - plain[k]
	return out


func test_refineries_turn_veg_into_fuel() -> void:
	var r := _refined(1, {"veg": 30, "fuel": 0})
	assert_eq(r["veg"], -4, "4 veg go in")
	assert_eq(r["fuel"], 3, "3 fuel come out")


func test_refineries_burn_veg_not_metal() -> void:
	var r := _refined(1, {"veg": 0, "metal": 50, "fuel": 0})
	assert_eq(r["metal"], 0)
	assert_eq(r["fuel"], 0, "no veg, no fuel")


func test_each_refinery_takes_its_own_4_veg_and_stops_when_the_veg_runs_out() -> void:
	var r := _refined(3, {"veg": 9, "fuel": 0})   # 9 veg is enough for two, and the third finds only 1 left
	assert_eq(r["veg"], -8)
	assert_eq(r["fuel"], 6)


func test_ethanol_synthesis_makes_4_fuel_from_the_same_veg() -> void:
	Game.upgrades.append("cv3")
	var r := _refined(1, {"veg": 30, "fuel": 0})
	assert_eq(r["veg"], -4, "still 4 veg")
	assert_eq(r["fuel"], 4)


func test_ethanol_does_not_double_up_and_ignores_other_stores() -> void:
	Game.upgrades.append("cv3")
	var r := _refined(1, {"veg": 100, "metal": 100, "fuel": 0})
	assert_eq(r["fuel"], 4, "one conversion per refinery")
	assert_eq(r["metal"], 0)


# ---------------------------------------------------------------- the refinery switch

func test_refineries_start_off_and_make_nothing() -> void:
	Game.res.merge({"metal": 50, "stone": 50}, true)
	var c: Vector2i = _spots(1)[0]
	Game.build("refinery", c)
	assert_eq(Game.tile(c)["b"], "refinery")
	assert_false(Game.refinery_running(c))
	assert_true(Game.log_lines.any(func(l): return l.contains("starts switched off")))
	var r := _refined(2, {"veg": 100, "fuel": 0}, 0)   # two refineries, neither switched on
	assert_eq(r["veg"], 0)
	assert_eq(r["fuel"], 0)


func test_a_switch_turns_one_refinery_on_and_off() -> void:
	var c: Vector2i = _spots(1)[0]
	Game.tile(c)["b"] = "refinery"
	Game.set_refinery(c, true)
	assert_true(Game.refinery_running(c))
	assert_eq(Game.running_refineries(), [c])
	Game.set_refinery(c, false)
	assert_false(Game.refinery_running(c))
	assert_eq(Game.running_refineries(), [])
	Game.set_refinery(_spots(2)[1], true)   # nothing built there: ignored
	assert_eq(Game.running_refineries(), [])


func test_only_the_refineries_you_switched_on_run() -> void:
	var r := _refined(3, {"veg": 100, "fuel": 0}, 2)
	assert_eq(r["veg"], -8)
	assert_eq(r["fuel"], 6)


func test_a_refinery_holds_back_when_it_would_leave_too_little_to_eat() -> void:
	Game.pop = 10
	Game.prisoners = 0
	# 10 people eat 10 food. 13 veg - 4 would leave 9: not enough, so nothing is refined
	var held := _refined(1, {"grain": 0, "veg": 13, "fuel": 0})
	assert_eq(held["veg"], 0)
	assert_eq(held["fuel"], 0)
	assert_true(Game.log_lines.any(func(l): return l.contains("held back")))
	# 14 veg - 4 leaves exactly 10: it runs
	var ran := _refined(1, {"grain": 0, "veg": 14, "fuel": 0})
	assert_eq(ran["veg"], -4)
	assert_eq(ran["fuel"], 3)


func test_grain_counts_toward_the_food_a_refinery_must_leave() -> void:
	Game.pop = 10
	Game.prisoners = 0
	var r := _refined(1, {"grain": 10, "veg": 4, "fuel": 0})   # 10 grain feeds everyone, so the 4 veg are spare
	assert_eq(r["veg"], -4)
	assert_eq(r["fuel"], 3)


func test_prisoners_must_be_fed_too() -> void:
	Game.pop = 10
	Game.prisoners = 5   # 15 mouths
	var held := _refined(1, {"grain": 0, "veg": 18, "fuel": 0})
	assert_eq(held["fuel"], 0)
	var ran := _refined(1, {"grain": 0, "veg": 19, "fuel": 0})
	assert_eq(ran["fuel"], 3)


func test_refineries_share_the_veg_the_colony_can_spare() -> void:
	Game.pop = 10
	Game.prisoners = 0
	# 20 veg: the first refinery leaves 16, the second 12, the third would leave 8 (< 10) so it holds back
	var r := _refined(3, {"grain": 0, "veg": 20, "fuel": 0})
	assert_eq(r["veg"], -8)
	assert_eq(r["fuel"], 6)


func test_demolishing_resets_a_refinery_so_a_new_one_starts_off() -> void:
	Game.res.merge({"metal": 50, "stone": 50}, true)
	var c: Vector2i = _spots(1)[0]
	Game.build("refinery", c)
	Game.set_refinery(c, true)
	Game.demolish(c)
	assert_false(Game.refinery_on.has(Game.idx(c)))
	Game.build("refinery", c)
	assert_false(Game.refinery_running(c), "the rebuilt one is off again")


func test_a_captured_refinery_stops_running() -> void:
	var c: Vector2i = _spots(1)[0]
	Game.tile(c)["b"] = "refinery"
	Game.set_refinery(c, true)
	Game.tile(c)["o"] = Data.AI
	assert_false(Game.refinery_running(c))
	Game.res["veg"] = 100
	Game._gather()
	assert_false(Game.refinery_on.has(Game.idx(c)), "the stale switch is dropped")


func test_the_refinery_switch_survives_saving() -> void:
	var spots := _spots(2)
	for c in spots:
		Game.tile(c)["b"] = "refinery"
	Game.set_refinery(spots[0], true)
	Game.save_game("refinery_test")
	World.new_game(99)
	assert_true(Game.load_game("refinery_test"))
	DirAccess.remove_absolute(Game._path("refinery_test"))
	assert_true(Game.refinery_running(spots[0]))
	assert_false(Game.refinery_running(spots[1]))


func test_saves_from_before_the_switch_load_with_refineries_off() -> void:
	var c: Vector2i = _spots(1)[0]
	Game.tile(c)["b"] = "refinery"
	Game.set_refinery(c, true)
	Game.save_game("old_refinery_test")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Game._path("old_refinery_test")))
	data.erase("refineries_on")
	var f := FileAccess.open(Game._path("old_refinery_test"), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("old_refinery_test"))
	DirAccess.remove_absolute(Game._path("old_refinery_test"))
	assert_eq(Game.tile(c)["b"], "refinery")
	assert_false(Game.refinery_running(c))


func test_fog_hides_the_enemy_at_the_start() -> void:
	assert_true(Game.in_sight(Data.PLAYER, Game.home(Data.PLAYER)))
	assert_false(Game.knows_tile(Data.PLAYER, Game.home(Data.AI)))
	assert_false(Game.knows(Data.PLAYER, Data.AI))
	Game.reveal(Data.PLAYER, Game.home(Data.AI), 2)
	assert_true(Game.knows(Data.PLAYER, Data.AI), "seeing their land counts as first contact")


func test_end_season_moves_time_on_and_autosaves_to_the_test_folder() -> void:
	assert_ne(Game.save_dir, Game.SAVE_DIR, "tests must never write the player's saves")
	Game.end_season()
	assert_eq(Game.season, 2)
	assert_true(FileAccess.file_exists(Game.save_dir + "autosave.json"))


func test_the_players_real_saves_are_untouched() -> void:
	var before := _real_saves()
	Game.end_season()
	Game.save_game("slot1")
	assert_eq(_real_saves(), before)


func test_save_and_load_round_trip() -> void:
	Game.end_season()
	var tiles := Game.tiles.duplicate(true)
	var res := Game.res.duplicate()
	var memory: Array = Game.memory[Data.PLAYER].duplicate(true)
	Game.save_game("test_round_trip")
	World.new_game(99)
	assert_true(Game.load_game("test_round_trip"))
	assert_eq(Game.season, 2)
	assert_eq(Game.res, res)
	assert_eq(Game.tiles, tiles)
	assert_eq(Game.memory[Data.PLAYER], memory)


## File name -> modified time for everything in the real save folder.
func _real_saves() -> Dictionary:
	var out := {}
	for f in DirAccess.get_files_at(Game.SAVE_DIR):
		out[f] = FileAccess.get_modified_time(Game.SAVE_DIR + f)
	return out
