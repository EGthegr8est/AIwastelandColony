extends "res://tests/framework/test_case.gd"
## How the game ends: the three endings and what triggers each, that it only ever ends once, and the stats
## the screen after it shows (counted through play, saved, and loaded back).

const Data = preload("res://scripts/data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var fired: Array = []
var _on_end: Callable


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	fired = []
	_on_end = func(kind): fired.append(kind)
	Game.game_ended.connect(_on_end)


func after_each() -> void:
	if Game.game_ended.is_connected(_on_end):
		Game.game_ended.disconnect(_on_end)
	D20.permadeath = D20Data.PERMADEATH


## Player raids until the game ends (or 40 tries), as a player would, one a season.
func _raid_until_over() -> void:
	for i in 40:
		if Game.ended():
			return
		Game.raided_this_season = false
		Game.raid_ai()


# ---------------------------------------------------------------- the start

func test_a_new_game_has_not_ended_and_has_clean_stats() -> void:
	assert_false(Game.ended())
	assert_eq(Game.ending, {})
	assert_eq(Game.stats.raids_won, 0)
	assert_eq(Game.stats.peak_pop, Game.pop)
	assert_eq(Game.stats.sent, {"scav": 0, "scout": 0, "caravan": 0, "boat": 0, "plane": 0})
	assert_eq(Game.prosper_streak, 0)


func test_every_ending_has_its_picture_and_its_music_side() -> void:
	assert_eq(Data.ENDING_SCREENS.keys().size(), 3)
	assert_true(Data.ENDING_SCREENS["raiders_defeated"].win)
	assert_true(Data.ENDING_SCREENS["colony_prospers"].win)
	assert_false(Data.ENDING_SCREENS["defeat"].win)
	for kind in Data.ENDING_SCREENS:
		var art: Texture2D = load(Data.ENDING_SCREENS[kind].art)
		assert_not_null(art, kind)
		assert_eq(art.get_size(), Vector2(1200, 980), kind)
	for why in ["stormed", "broken", "long game", "overrun", "starved"]:
		assert_true(Data.ENDING_WHY.has(why), why)


# ---------------------------------------------------------------- you win by force

func test_an_overwhelming_raid_storms_the_fort() -> void:
	Game.troops = 500   # attack far past 2.5 times their defense
	_raid_until_over()
	assert_true(Game.ended())
	assert_eq(Game.ending.kind, "raiders_defeated")
	assert_eq(Game.ending.why, "stormed")
	assert_eq(fired, ["raiders_defeated"])
	assert_true(Game.log_lines.any(func(l): return l.contains("fort has fallen")))


func test_an_ordinary_raid_win_does_not_end_the_game() -> void:
	Game.troops = 8   # about 1.2 times their defense: a win is not decisive
	for i in 30:
		Game.raided_this_season = false
		Game.troops = 8
		Game.ai["troops"] = 6
		Game.raid_ai()
	assert_false(Game.ended())
	assert_gt(Game.stats.raids_won, 0)
	assert_gt(Game.stats.raids_lost, 0)


func test_leaving_the_rust_kings_almost_no_land_ends_the_game() -> void:
	var land := Game.owned(Data.AI)
	for i in range(Data.ENDINGS.broken_land, land.size()):
		Game.tile(land[i])["o"] = Data.NONE
	Game.check_ending()
	assert_eq(Game.ending.kind, "raiders_defeated")
	assert_eq(Game.ending.why, "broken")


# ---------------------------------------------------------------- you lose

func test_an_overwhelming_rust_kings_raid_overruns_the_colony() -> void:
	Game.ai["troops"] = 400
	for i in 40:
		if Game.ended():
			break
		Game._ai_raid()
	assert_eq(Game.ending.kind, "defeat")
	assert_eq(Game.ending.why, "overrun")
	assert_eq(fired, ["defeat"])


func test_a_citadel_stops_the_colony_being_overrun() -> void:
	var spot: Vector2i = Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "")[0]
	Game.tile(spot)["b"] = "citadel"
	Game.ai["troops"] = 400
	for i in 20:
		Game._ai_raid()
	assert_false(Game.ended())


func test_a_colony_that_starves_to_almost_nobody_is_finished() -> void:
	Game.pop = 2
	Game.res["grain"] = 0
	Game.res["veg"] = 0
	Game._upkeep()
	assert_true(Game.starved_now)
	assert_gt(Game.stats.colonists_starved, 0)
	Game.check_ending()
	assert_eq(Game.ending.kind, "defeat")
	assert_eq(Game.ending.why, "starved")


func test_a_hungry_colony_that_is_still_big_is_not_finished() -> void:
	Game.pop = 10
	Game.res["grain"] = 0
	Game.res["veg"] = 0
	Game._upkeep()
	Game.check_ending()
	assert_false(Game.ended())


func test_losing_nearly_all_your_land_is_the_end() -> void:
	var land := Game.owned(Data.PLAYER)
	for i in range(Data.ENDINGS.lose_land, land.size()):
		Game.tile(land[i])["o"] = Data.AI
	Game.check_ending()
	assert_eq(Game.ending.kind, "defeat")


# ---------------------------------------------------------------- the long game

func _long_game_state() -> void:
	Game.season = Data.ENDINGS.prosper.season
	Game.pop = 25
	Game.stats["raids_won"] = 2
	Game.ai["troops"] = 0
	for v in ["horse", "car", "boat", "plane"]:
		Game.ai[v] = 0


func test_the_colony_prospers_after_the_rust_kings_stay_broken_for_a_run_of_seasons() -> void:
	_long_game_state()
	assert_true(Game.rust_kings_broken())
	var streak: int = Data.ENDINGS.prosper.streak
	for i in streak - 1:
		Game.check_ending()
		assert_false(Game.ended(), "season %d of the run" % (i + 1))
	Game.check_ending()
	assert_eq(Game.ending.kind, "colony_prospers")
	assert_eq(Game.ending.why, "long game")


func test_a_setback_resets_the_run() -> void:
	_long_game_state()
	for i in 3:
		Game.check_ending()
	assert_eq(Game.prosper_streak, 3)
	Game.pop = 5   # the colony is no longer thriving
	Game.check_ending()
	assert_eq(Game.prosper_streak, 0)
	Game.pop = 25
	Game.ai["troops"] = 300   # or the Rust Kings are strong again
	Game.check_ending()
	assert_eq(Game.prosper_streak, 0)


func test_it_needs_the_late_game_and_a_war_behind_you() -> void:
	_long_game_state()
	Game.season = Data.ENDINGS.prosper.season - 1
	Game.check_ending()
	assert_eq(Game.prosper_streak, 0, "too early in the game")
	Game.season = Data.ENDINGS.prosper.season
	Game.stats["raids_won"] = 0
	Game.check_ending()
	assert_eq(Game.prosper_streak, 0, "no battle has been fought")


# ---------------------------------------------------------------- once only

func test_the_game_ends_once_and_stays_ended() -> void:
	Game._end("defeat", "starved")
	Game._end("raiders_defeated", "stormed")
	Game.check_ending()
	assert_eq(Game.ending.kind, "defeat")
	assert_eq(fired, ["defeat"], "the screen is shown once")


func test_a_finished_game_does_not_play_on_or_overwrite_the_autosave() -> void:
	DirAccess.remove_absolute(Game._path("autosave"))
	var land := Game.owned(Data.PLAYER)
	for i in range(Data.ENDINGS.lose_land, land.size()):
		Game.tile(land[i])["o"] = Data.AI
	Game.end_season()
	assert_eq(Game.ending.kind, "defeat")
	assert_false(FileAccess.file_exists(Game._path("autosave")), "no autosave of a finished game")
	var season: int = Game.season
	Game.end_season()
	assert_eq(Game.season, season, "the season does not advance after the end")


func test_leaving_the_game_clears_it() -> void:
	Game._end("defeat", "overrun")
	Game.leave_game()
	assert_false(Game.in_game)
	assert_eq(Game.ending, {})


func test_a_new_game_after_an_ending_starts_fresh() -> void:
	Game.stats["raids_won"] = 9
	Game._end("defeat", "overrun")
	World.new_game(8)
	assert_false(Game.ended())
	assert_eq(Game.stats.raids_won, 0)


# ---------------------------------------------------------------- the stats

func test_playing_counts_what_you_do() -> void:
	var spot: Vector2i = Game.owned(Data.PLAYER).filter(func(c): return Game.tile(c)["b"] == "" and Game.tile(c)["t"] == "sand")[0]
	Game.res["wood"] = 100
	Game.build("farm", spot)
	assert_eq(Game.stats.buildings_built, 1)
	var claim := World.claimable_tile()
	Game.res["gold"] = 50
	Game.claim(claim)
	assert_eq(Game.stats.tiles_claimed, 1)
	Game.res["wood"] = 100
	Game.buy_upgrade("farming")
	assert_eq(Game.stats.upgrades, 1)
	Game.res["metal"] = 20
	Game.res["meat"] = 20
	Game.train_troop()
	assert_eq(Game.stats.troops_trained, 1)
	Game.pop = 20
	Units.send("scav", "foot", Game.home(Data.PLAYER) + Vector2i(1, -2))
	assert_eq(Game.stats.sent.scav, 1)


func test_rolls_and_natural_20s_are_counted() -> void:
	var ruin := Game.home(Data.PLAYER) + Vector2i(1, -2)
	Units.dice = ForcedDice.new([17, 10, 20, 3], [6, 4])   # a cache of fuel, a natural 20 (large), a small metal extra
	Game.tile(ruin)["r"] = "safe"
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	u.home = Game.home(Data.PLAYER)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	Units.units.append(u)
	Units._begin_visit(u)
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(Game.stats.rolls, 2)
	assert_eq(Game.stats.natural_20s, 1)
	Units.visit_do(u.id, "home")   # a natural 20 offers searching deeper: head home with it
	Units.visit_finish(u.id)
	assert_eq(Game.stats.ruins_scavenged, 1)


func test_raids_both_ways_are_counted() -> void:
	Game.ai["troops"] = 0
	Game.troops = 20
	for i in 5:
		Game.raided_this_season = false
		Game.raid_ai()
		if Game.ended():
			break
	assert_gt(Game.stats.raids_won + Game.stats.raids_lost, 0)
	assert_eq(Game.battles(), Game.stats.raids_won + Game.stats.raids_lost)
	Game.ending = {}
	Game.ai["troops"] = 1
	Game.troops = 100
	for i in 10:
		Game._ai_raid()
	assert_gt(Game.stats.raids_beaten_back + Game.stats.raids_suffered, 0)


func test_starvation_peaks_and_gathering_are_counted() -> void:
	Game.pop = 30
	Game.res["grain"] = 100
	Game._gather()
	assert_gt(Game.stats.gathered.size(), 0)
	Game._update_peaks()
	assert_eq(Game.stats.peak_pop, 30)
	Game.pop = 12
	Game._update_peaks()
	assert_eq(Game.stats.peak_pop, 30, "the peak does not fall")


func test_stats_survive_saving_as_whole_numbers() -> void:
	Game.stats["raids_won"] = 4
	Game.stats["sent"]["scav"] = 7
	Game.stats["gathered"]["wood"] = 99
	Game.save_game("stats_test")
	World.new_game(99)
	assert_true(Game.load_game("stats_test"))
	DirAccess.remove_absolute(Game._path("stats_test"))
	assert_eq(Game.stats.raids_won, 4)
	assert_eq(typeof(Game.stats.raids_won), TYPE_INT)
	assert_eq(Game.stats.sent.scav, 7)
	assert_eq(typeof(Game.stats.sent.scav), TYPE_INT)
	assert_eq(Game.stats.gathered.wood, 99)


func test_a_save_from_before_stats_loads_with_zeroes() -> void:
	Game.save_game("old_stats_test")
	var path: String = Game._path("old_stats_test")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.erase("stats")
	data.erase("prosper_streak")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	World.new_game(99)
	assert_true(Game.load_game("old_stats_test"))
	DirAccess.remove_absolute(path)
	assert_eq(Game.stats.raids_won, 0)
	assert_false(Game.ended())
