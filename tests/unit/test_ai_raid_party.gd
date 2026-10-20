extends "res://tests/framework/test_case.gd"
## The Rust Kings' raid is a party that has to be made and then has to walk to you (Data.AI_RAID): their raid readiness grows each season by their
## troops times how much they dislike you, a party of their troops sets out when it is full, it walks to your land a season at a time (you can see it
## coming, meet it on the road, or be warned by the Watchtower), attacks where it arrives with the guards' roll and then rolls at your buildings and
## your hearth, and what is left of it walks home and rejoins their troops.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var fort: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	fort = Game.home(Data.AI)
	Game.contacts["%d:%d" % [Data.AI, Data.PLAYER]] = true   # they have found you
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.season = 10
	Game.ai["troops"] = 10
	Game.ai["relations"] = 0
	Game.ai["truce"] = 0
	Game.ai["raid_progress"] = 0.0
	for v in ["horse", "car", "boat", "plane"]:
		Game.ai[v] = 0
	D20.loot_scale = D20Data.LOOT_SCALE


func after_each() -> void:
	D20.loot_scale = D20Data.LOOT_SCALE
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


func _log_count(text: String) -> int:
	return Game.log_lines.filter(func(l): return l.contains(text)).size()


## A land tile of nobody's right beside your land.
func _edge_tile() -> Vector2i:
	return World.find_tile(func(c, t): return t["o"] == Data.NONE and t["t"] != "water" and Game.move_mult("foot", c) > 0.0 \
		and Game.neighbors(c).any(func(n): return Game.tile(n)["o"] == Data.PLAYER))


## A farm of yours on a free tile of your land, the `n`th found.
func _farm(n := 0) -> Vector2i:
	var found := 0
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water" and c.distance_to(hq) > 1.5:
			if found == n:
				Game.tile(c)["b"] = "farm"
				return c
			found += 1
	return Vector2i(-1, -1)


## A party launched and standing at `at`.
func _party_at(at: Vector2i) -> Dictionary:
	Units.launch_raid()
	var p: Dictionary = Units.units[-1]
	p.pos = at
	return p


# ---------------------------------------------------------------- making a raid takes time

func test_readiness_grows_each_season_by_their_troops_times_how_much_they_dislike_you() -> void:
	for row in [[0, 7.0, 13.0], [-100, 14.0, 26.0], [50, 3.5, 6.5], [100, 2.1, 3.9]]:   # [relations, least, most]: 10 troops, hostility, luck 0.7 to 1.3
		Game.ai["relations"] = row[0]
		Game.ai["raid_progress"] = 0.0
		Game._ai_raid_readiness()
		assert_ge(Game.ai["raid_progress"], row[1], "relations %d" % row[0])
		assert_le(Game.ai["raid_progress"], row[2], "relations %d" % row[0])


func test_nothing_is_made_before_the_season_or_without_them_knowing_you_or_in_a_truce() -> void:
	Game.season = Data.AI_RAID.min_season - 1
	Game._ai_turn()
	assert_eq(Game.ai["raid_progress"], 0.0, "too early in the game")
	Game.season = 10
	Game.contacts.erase("%d:%d" % [Data.AI, Data.PLAYER])
	Game._ai_turn()
	assert_eq(Game.ai["raid_progress"], 0.0, "they have not found you")
	Game.contacts["%d:%d" % [Data.AI, Data.PLAYER]] = true
	Game.ai["truce"] = 2
	Game._ai_turn()
	assert_eq(Game.ai["raid_progress"], 0.0, "a truce is a season off their readiness")
	Game._ai_turn()
	assert_gt(Game.ai["raid_progress"], 0.0, "and when it ends they start again")


func test_they_make_no_party_with_fewer_than_four_troops() -> void:
	Game.ai["troops"] = 3
	Game.ai["raid_progress"] = 100.0
	Game._ai_raid_readiness()
	assert_eq(Units.raid_parties_out(), 0)
	assert_eq(Game.ai["raid_progress"], 100.0, "nothing changed")


func test_a_party_sets_out_when_the_readiness_is_full() -> void:
	Game.ai["raid_progress"] = 39.0
	Game._ai_raid_readiness()
	assert_eq(Units.raid_parties_out(), 1)
	var p: Dictionary = Units.units[-1]
	assert_eq(p.job, "band")
	assert_eq(p.owner, Data.AI)
	assert_eq(p.troops, 8, "three quarters of ten troops")
	assert_eq(Game.ai["troops"], 2, "the rest stay in the fort")
	assert_eq(p.stage, "out")
	assert_eq(p.pos, fort)
	assert_eq(p.mover, "foot")
	assert_ge(p.strength, 1)
	assert_true(p.raid)
	assert_ge(Game.ai["raid_progress"], 6.0, "the readiness it cost is taken off, not all of it")
	assert_le(Game.ai["raid_progress"], 12.0)


func test_launching_takes_their_troops_out_of_the_fort_so_it_is_weaker_while_the_party_is_out() -> void:
	var before := Game.ai_attack()
	Units.launch_raid()
	assert_eq(Game.ai["troops"], 2)
	assert_lt(Game.ai_attack(), before)


func test_no_more_than_two_parties_are_out_and_the_readiness_waits_for_the_next() -> void:
	for i in 2:
		Game.ai["troops"] = 40
		Game.ai["raid_progress"] = 60.0
		Game._ai_raid_readiness()
	assert_eq(Units.raid_parties_out(), 2)
	Game.ai["troops"] = 40
	Game.ai["raid_progress"] = 55.0
	Game._ai_raid_readiness()
	assert_eq(Units.raid_parties_out(), 2, "a third has to wait")
	assert_eq(Game.ai["raid_progress"], 60.0, "its readiness waits with it, up to one and a half times the threshold")


func test_the_party_rides_when_they_have_horses_or_war_rigs_and_the_way_allows() -> void:
	Game.ai["horse"] = 2
	Units.launch_raid()
	assert_eq(Units.units[-1].mover, "horse")
	Units.units = []
	Game.ai["troops"] = 10
	Game.ai["car"] = 1
	Units.launch_raid()
	assert_eq(Units.units[-1].mover, "car" if not Game.route("car", fort, hq).is_empty() else "horse")


# ---------------------------------------------------------------- the walk

func test_the_party_walks_toward_your_colony_a_season_at_a_time_and_attacks_when_it_gets_there() -> void:
	Units.launch_raid()
	var p: Dictionary = Units.units[-1]
	var left := Game.route("foot", p.pos, hq).size()
	var seasons := 0
	while p.stage == "out" and seasons < 14 and not p.get("gone", false):
		Units.dice = ForcedDice.new([1, 1, 1])   # if it gets there it misses: a natural 1
		Units.season_turn()
		seasons += 1
		if p.stage == "out":
			var now := Game.route("foot", p.pos, hq).size()
			assert_lt(now, left, "nearer every season")
			left = now
	assert_gt(seasons, 1, "it takes more than a season to walk that far")
	assert_eq(p.stage, "back", "and having attacked it turns for home")
	assert_eq(Game.stats.raids_beaten_back, 1)


func test_the_party_is_seen_marching_in_the_season_replay() -> void:
	Units.launch_raid()
	var p: Dictionary = Units.units[-1]
	Units.season_turn()
	var seen := false
	for a in Units.replay.actors:
		if a.id == p.id:
			seen = true
			assert_eq(a.kind, "band")
			assert_eq(a.owner, Data.AI)
			assert_gt(a.trail.size(), 5, "it walked a season")
	assert_true(seen)


func test_a_party_that_comes_into_sight_is_reported_once() -> void:
	var p := _party_at(hq + Vector2i(9, 0))
	Units.dice = ForcedDice.new([1, 1, 1])
	Game.log_lines = []
	Units._raid_turn(p)
	assert_true(p.get("spotted", false))
	assert_eq(_log_count("is marching on your colony"), 1)
	Units._raid_turn(p)
	assert_eq(_log_count("is marching on your colony"), 1, "once, not every season")


# ---------------------------------------------------------------- the attack

func test_a_won_assault_costs_you_loot_troops_and_a_building_and_the_party_turns_for_home() -> void:
	var edge := _edge_tile()
	assert_ne(edge, Vector2i(-1, -1))
	var farm := _farm()
	var p := _party_at(edge)
	Game.res["gold"] = 100
	Game.troops = 10
	var pop := Game.pop
	Units.dice = ForcedDice.new([20, 20])   # the guards' roll (a natural 20 wins), then the roll at your nearest building
	Units._raid_turn(p)
	assert_eq(Units.dice.d20_calls, 2)
	assert_eq(Game.stats.raids_suffered, 1)
	assert_eq(Game.res["gold"], 70, "a natural 20 takes three tenths")
	assert_eq(Game.troops, 7, "three tenths of your troops")
	assert_eq(Game.pop, pop - 1, "and one of your people")
	assert_eq(Game.tile(farm)["b"], "", "a building came down")
	assert_eq(p.troops, 7, "a fifth of the party's troops fell")
	assert_eq(p.stage, "back")
	assert_false(p.get("gone", false))


func test_a_lost_assault_costs_the_party_its_troops_and_it_still_walks_home() -> void:
	var p := _party_at(_edge_tile())
	var prisoners := Game.prisoners
	Units.dice = ForcedDice.new([1])   # a natural 1: a critical miss
	Units._raid_turn(p)
	assert_eq(Game.stats.raids_beaten_back, 1)
	assert_eq(p.troops, 3, "six tenths of its eight troops are lost")
	assert_eq(Game.prisoners, prisoners + 2, "and two of them are caught")
	assert_eq(p.stage, "back")
	assert_eq(Game.ai["troops"], 2, "the fort's troops are not touched: they were the party's")


func test_a_party_with_no_troops_left_is_gone_for_good() -> void:
	var p := _party_at(_edge_tile())
	p.troops = 1
	Units.dice = ForcedDice.new([1])
	Units._raid_turn(p)
	assert_eq(p.troops, 0)
	assert_true(p.get("gone", false))
	assert_eq(Game.ai["troops"], 2, "it never gets home")


func test_a_party_that_gets_home_gives_its_troops_back_to_the_fort() -> void:
	Units.launch_raid()
	var p: Dictionary = Units.units[-1]
	var near := World.find_tile(func(c, t): return c.distance_to(fort) > 0.5 and c.distance_to(fort) < 2.5 and Game.move_mult("foot", c) > 0.0)
	assert_ne(near, Vector2i(-1, -1))
	p.stage = "back"
	p.pos = near
	p.troops = 6
	Units._raid_turn(p)
	assert_true(p.get("gone", false), "home")
	assert_eq(Game.ai["troops"], 2 + 6)


# ---------------------------------------------------------------- stopping it

func test_a_truce_turns_a_party_that_is_still_on_its_way() -> void:
	var p := _party_at(fort + Vector2i(-3, 0))
	Game.ai["truce"] = 2
	Units._raid_turn(p)
	assert_eq(p.stage, "back")


func test_a_bribe_turns_the_parties_back_and_empties_the_readiness() -> void:
	Game.upgrades = ["c4"]
	Game.res["gold"] = 100
	Units.launch_raid()
	var p: Dictionary = Units.units[-1]
	Game.ai["raid_progress"] = 30.0
	Game.bribe()
	assert_eq(Game.ai["truce"], 3)
	assert_eq(Game.ai["raid_progress"], 0.0)
	assert_eq(p.stage, "back")
	assert_true(_log_has("turns back"))


func test_your_party_beside_it_fights_it_and_a_win_drives_it_off() -> void:
	var p := _party_at(_edge_tile())
	var mine: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", p.pos + Vector2i(1, 0), hq)
	mine.crew = 3
	mine.survivors = Units._make_crew(3)
	Units.units.append(mine)
	Units.dice = ForcedDice.new([20, 5], [3])   # the fight: a natural 20, then the package
	Units._ambushes()
	assert_true(p.get("gone", false), "it is driven off")
	assert_eq(Game.stats.raids_beaten_back, 1)
	assert_true(_log_has("fought off a Rust Kings war party"))
	assert_eq(Game.ai["troops"], 2, "its troops are lost to them")


# ---------------------------------------------------------------- the Watchtower

func test_the_watchtower_says_when_a_party_sets_out_and_how_long_it_has_to_walk() -> void:
	Game.log_lines = []
	Units.launch_raid()
	assert_false(_log_has("WATCHTOWER"), "no watchtower, no warning")
	Units.units = []
	Game.ai["troops"] = 10
	Game.upgrades = ["f3"]
	Units.launch_raid()
	assert_true(_log_has("WATCHTOWER: a Rust Kings war party of 8 has set out"))
	assert_true(_log_has("about"))


# ---------------------------------------------------------------- the hearth

func test_a_strong_raid_that_finds_your_hearth_unguarded_goes_for_it_first() -> void:
	for c in Game.hearth_guards(hq):
		Game.tile(c)["b"] = ""
	_farm()
	Units.dice = ForcedDice.new([20])
	Game._ai_strikes(30.0, 10.0)   # three times your defence
	assert_eq(Game.ending.kind, "defeat")
	assert_eq(Game.ending.why, "overrun")
	assert_eq(Units.dice.d20_calls, 1, "the first roll was at the hearth and the rest did not matter")


func test_a_wall_beside_the_hearth_keeps_the_raid_off_it() -> void:
	var wall := _farm()
	Game.tile(wall)["b"] = "wall"
	Units.dice = ForcedDice.new([20, 20])
	Game._ai_strikes(30.0, 10.0)
	assert_true(Game.ending.is_empty(), "the hearth was not rolled at")
	assert_eq(Game.tile(hq)["b"], "hq")
	assert_eq(Game.tile(wall)["b"], "", "but the wall came down")
	assert_eq(Units.dice.d20_calls, 1)


func test_a_citadel_keeps_a_raid_from_overrunning_you() -> void:
	var c := _farm()
	Game.tile(c)["b"] = "citadel"
	Units.dice = ForcedDice.new([20, 20, 20])
	Game._ai_strikes(30.0, 10.0)
	assert_true(Game.ending.is_empty())
	assert_eq(Units.dice.d20_calls, 0, "there is nothing they can roll at")


func test_a_weaker_raid_does_not_go_for_the_hearth() -> void:
	for c in Game.hearth_guards(hq):
		Game.tile(c)["b"] = ""
	var farm := _farm()
	Units.dice = ForcedDice.new([20])
	Game._ai_strikes(12.0, 10.0)   # only just stronger than your defence
	assert_true(Game.ending.is_empty())
	assert_eq(Game.tile(farm)["b"], "", "the farm was rolled at instead")


# ---------------------------------------------------------------- saving

func test_a_raiding_party_and_the_readiness_survive_saving_and_loading() -> void:
	Game.ai["raid_progress"] = 12.5
	Units.launch_raid()
	var p: Dictionary = Units.units[-1]
	Units.season_turn()
	Game.save_game("raid_party_test")
	assert_true(Game.load_game("raid_party_test"))
	var loaded: Dictionary = Units.units.filter(func(u): return u.job == "band" and u.owner == Data.AI)[0]
	assert_eq(loaded.troops, p.troops)
	assert_eq(loaded.stage, "out")
	assert_eq(loaded.strength, p.strength)
	assert_eq(loaded.pos, p.pos)
	assert_almost_eq(Game.ai["raid_progress"], 12.5, 0.001, "the fraction is kept")
	assert_false(Game.ai.has("raid_planned"))


func test_an_old_save_with_a_planned_raid_loads_with_no_readiness() -> void:
	Game.save_game("raid_old_test")
	var path: String = Game.save_dir + "raid_old_test.json"
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	data["ai"].erase("raid_progress")
	data["ai"]["raid_planned"] = true
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	assert_true(Game.load_game("raid_old_test"))
	assert_eq(Game.ai["raid_progress"], 0.0)
	assert_false(Game.ai.has("raid_planned"))
