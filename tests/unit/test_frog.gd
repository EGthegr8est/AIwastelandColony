extends "res://tests/framework/test_case.gd"
## The Giant Frog: asleep under the biggest city, woken by a natural 1 near it, the run-or-fight choice for the party that woke it, the
## boss fight in rounds (three survivors cannot win, six can), its hides, and its rampage on your colony or the Rust Kings.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	D20.loot_scale = D20Data.LOOT_SCALE
	D20.permadeath = D20Data.PERMADEATH
	Game.res["grain"] = 100
	# the city is hot, and the radiation would change every roll: take it away around the lair
	var lair: Vector2i = Units.frog.lair
	for y in range(lair.y - 14, lair.y + 15):
		for x in range(lair.x - 14, lair.x + 15):
			if Game.in_bounds(Vector2i(x, y)):
				Game.tile(Vector2i(x, y))["rad"] = 0


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


func _party(at: Vector2i, crew := 3, job := "scav") -> Dictionary:
	var u: Dictionary = Units._make_unit(job, Data.PLAYER, "foot", at, hq)
	u.crew = crew
	u.survivors = Units._make_crew(crew)
	for s in u.survivors:
		s.traits = []
	Units.units.append(u)
	return u


## A party at a trapped ruin `dx` tiles east of the frog's lair, about to make the trap check.
func _at_the_city(dx := 3) -> Dictionary:
	var u := _party(Units.frog.lair + Vector2i(dx, 0))
	u.stage = "site"
	u["visit"] = D20Visit.begin("trapped", Units.visit_ctx(u), 3.0, Units.dice, u.survivors)
	return u


## The frog awake on `at`, as if a party had woken it there.
func _loose_frog(at: Vector2i, target := "player") -> void:
	Units.frog["state"] = "loose"
	Units.frog["pos"] = at
	Units.frog["target"] = target
	Units.frog["wounds"] = 0
	Units.frog["rest"] = 0


## A party that has tracked the frog and waits beside it.
func _waiting(at: Vector2i, crew := 3) -> Dictionary:
	var u := _party(at, crew)
	u.stage = "site"
	u["visit"] = D20Visit.begin_hunt(Units.visit_ctx(u), 3.0, Units.dice, u.survivors, "frog", Units.FROG_ID, "giant frog")
	u.visit["stage"] = "frog_wait"
	return u


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


# ---------------------------------------------------------------- waking it

func test_a_natural_1_at_a_ruin_near_the_city_can_wake_the_frog() -> void:
	var u := _at_the_city()
	Units.dice = ForcedDice.new([1, 2, 4], [])   # the trap check's natural 1, the wake roll (a 2 is 3 or less), the coin flip (4: your colony)
	Units.visit_do(u.id)
	assert_eq(Units.frog.state, "loose")
	assert_eq(Units.frog.pos, u.pos, "it tears out of the ground where they stand")
	assert_eq(Units.frog.target, "player")
	assert_eq(u.visit.stage, "frog_run")
	assert_true(_log_has("THE GIANT FROG woke"))


func test_a_high_coin_flip_sends_it_for_the_rust_kings() -> void:
	var u := _at_the_city()
	Units.dice = ForcedDice.new([1, 3, 15], [])
	Units.visit_do(u.id)
	assert_eq(Units.frog.target, "ai")


func test_a_wake_roll_above_the_limit_leaves_it_asleep() -> void:
	var u := _at_the_city()
	Units.dice = ForcedDice.new([1, 4], [])
	Units.visit_do(u.id)
	assert_eq(Units.frog.state, "dormant")
	assert_ne(u.visit.stage, "frog_run")


func test_a_natural_1_far_from_the_city_rolls_nothing_extra() -> void:
	var u := _at_the_city(Data.FROG.wake_radius + 3)
	Units.dice = ForcedDice.new([1], [])   # only the check's d20: a second one would be an error
	Units.visit_do(u.id)
	assert_eq(Units.frog.state, "dormant")


func test_other_rolls_near_the_city_do_not_wake_it() -> void:
	var u := _at_the_city()
	Units.dice = ForcedDice.new([2], [])   # a 2 on the check is not a natural 1
	Units.visit_do(u.id)
	assert_eq(Units.frog.state, "dormant")


func test_a_hunt_near_the_city_does_not_wake_it() -> void:
	var u := _party(Units.frog.lair + Vector2i(2, 0))
	Units.animals = []
	var deer: Dictionary = Units._add_animal("deer", u.pos)
	Units.dice = ForcedDice.new([1], [])
	Units._start_hunt(u, deer)
	Units.visit_do(u.id)
	assert_eq(Units.frog.state, "dormant", "only scavenging wakes it")


func test_the_frog_wakes_only_once() -> void:
	var u := _at_the_city()
	Units.dice = ForcedDice.new([1, 1, 4], [])
	Units.visit_do(u.id)
	var v := _at_the_city(4)
	Units.dice = ForcedDice.new([1], [])   # asleep no more: nothing more to roll
	Units.visit_do(v.id)
	assert_ne(v.visit.stage, "frog_run")


# ---------------------------------------------------------------- run or fight

func _woken_party() -> Dictionary:
	var u := _at_the_city()
	Units.dice = ForcedDice.new([1, 2, 4], [])
	Units.visit_do(u.id)
	for s in u.survivors:   # the trap check that woke it hurt someone: start the fight with everybody fit
		s["injury"] = "none"
	u.visit["injuries"] = {}
	return u


func test_the_party_that_woke_it_can_run_or_stand_and_fight() -> void:
	var u := _woken_party()
	var view := Units.visit_view(u)
	assert_eq(view.ruin, "frog", "the panel says Hunt")
	assert_eq(view.dc, D20Data.FROG_FIGHT.run_dc)
	assert_true(view.buttons.any(func(b): return b.id == "roll"))
	assert_true(view.buttons.any(func(b): return b.id == "fight"))


func test_a_good_run_roll_gets_them_away_with_what_they_found() -> void:
	var u := _woken_party()
	u.visit.loot = {"metal": 9}
	Units.dice = ForcedDice.new([15], [])
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done")
	assert_eq(u.visit.outcome, "left")
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station")
	assert_eq(u.carry, {"metal": 9})
	assert_eq(Units.frog.state, "loose", "the frog is out and the party is gone")


func test_a_bad_run_roll_lets_the_frog_slam_the_party() -> void:
	var u := _woken_party()
	# run: d20 5 misses. Slam 1 picks the first survivor, who dodges (15); slam 2 picks the second (8: felled); slam 3 picks the last of the two standing (1: killed).
	Units.dice = ForcedDice.new([5, 15, 8, 1], [1, 2, 2])
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "frog_run", "still facing it")
	assert_eq(u.crew, 2, "one was killed")
	var felled: Array = u.survivors.filter(func(s): return s.injury == "severe")
	assert_eq(felled.size(), 1, "one was felled")


func test_three_survivors_alone_cannot_do_it() -> void:
	var u := _woken_party()
	Units.visit_do(u.id, "fight")
	assert_eq(u.visit.stage, "frog_fight")
	# a round of three hits (a 14: 1 wound each); the slams then take them one by one
	var hits := 0
	var rounds := 0
	while u.visit.stage == "frog_fight" and rounds < 8:
		rounds += 1
		var standing: int = u.survivors.filter(func(s): return s.injury != "severe").size()
		var d20s := []
		for i in standing:
			d20s.append(14)
		for i in 3:   # three slams, each a failed dodge (8: felled)
			d20s.append(8)
		Units.dice = ForcedDice.new(d20s, [1, 1, 1])
		Units.visit_do(u.id)
		hits += standing
	assert_lt(int(Units.frog.wounds), int(D20Data.FROG_FIGHT.wounds), "the frog is alive")
	assert_eq(Units.frog.state, "loose")
	assert_eq(u.visit.stage, "done", "nobody is left on their feet")
	assert_eq(u.visit.outcome, "left")


# ---------------------------------------------------------------- tracking and the boss fight

func test_a_party_sent_after_the_frog_walks_there_and_tracks_it() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var u := _party(Units.frog.pos)
	u.dest = Units.FROG_ID
	u.target = u.pos
	u.stage = "out"
	Units._arrive(u)
	assert_eq(u.stage, "site")
	assert_eq(u.visit.animal, "frog")
	assert_eq(Units.visit_view(u).dc, D20Data.FROG_FIGHT.track_dc)
	Units.dice = ForcedDice.new([16], [])
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "frog_wait", "tracked: it waits for the others")


func test_a_failed_track_roll_loses_the_frog() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var u := _party(Units.frog.pos)
	Units.dice = ForcedDice.new([10], [])   # DC 14: a miss, but not by 6
	Units._start_hunt(u, Units.frog_target())
	Units.visit_do(u.id)
	assert_eq(u.visit.outcome, "cold")
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station")


func test_a_natural_1_on_the_track_roll_brings_the_frog_down_on_them() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var u := _party(Units.frog.pos)
	Units.dice = ForcedDice.new([1], [])
	Units._start_hunt(u, Units.frog_target())
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "frog_run")


func test_the_frog_is_a_target_for_a_scouting_party_beside_it() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var u := _party(hq + Vector2i(5, 0), 2, "scout")
	u.stage = "station"
	u.food = {"grain": Data.SCOUT_PACK}
	var targets := Units.hunt_targets(u)
	assert_eq(targets.size(), 1)
	assert_eq(targets[0].kind, "frog")
	assert_true(Units.begin_hunt(u.id, Units.FROG_ID))
	assert_eq(u.visit.animal, "frog")


func test_two_parties_of_three_can_kill_it_and_split_its_hides() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var a := _waiting(Units.frog.pos)
	var b := _waiting(Units.frog.pos + Vector2i(1, 1))
	var view := Units.visit_view(a)
	assert_true(view.buttons.any(func(x): return x.id == "frog_attack"))
	Units.visit_do(a.id, "frog_attack")
	assert_eq(a.visit.stage, "frog_fight")
	assert_eq(b.visit.stage, "frog_fight", "everyone at the frog goes in together")
	assert_true(Units.visit_view(b).buttons.is_empty(), "only the first party has the die")
	# six natural 20s: two wounds each, twelve in one round
	Units.dice = ForcedDice.new([20, 20, 20, 20, 20, 20], [])
	Units.visit_do(a.id)
	assert_eq(Units.frog.state, "dead")
	assert_eq(a.visit.outcome, "killed")
	assert_eq(b.visit.outcome, "killed")
	assert_eq(int(a.visit.loot.get("hide", 0)) + int(b.visit.loot.get("hide", 0)), Data.FROG.hides)
	Units.visit_finish(a.id)
	Units.visit_finish(b.id)
	assert_eq(a.stage, "station")
	assert_eq(int(a.carry.get("hide", 0)) + int(b.carry.get("hide", 0)), Data.FROG.hides)
	assert_true(_log_has("GIANT FROG IS DEAD"))


func test_the_hides_come_home_into_the_colonys_items_not_its_resources() -> void:
	var u := _party(hq + Vector2i(2, 0))
	u.carry = {"hide": 2, "metal": 3}
	var metal: int = Game.res["metal"]
	Units._come_home(u)
	assert_eq(Game.items["hide"], 2)
	assert_eq(Game.res["metal"], metal + 3)
	assert_false(Game.res.has("hide"), "no line in the top bar")


func test_a_hit_is_a_wound_and_a_natural_20_two() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var a := _waiting(Units.frog.pos)
	Units.visit_do(a.id, "frog_attack")
	# 14 hits (DC 12), 20 is critical, 5 misses: 3 wounds; then three slams all dodged (15)
	Units.dice = ForcedDice.new([14, 20, 5, 15, 15, 15], [1, 1, 1])
	Units.visit_do(a.id)
	assert_eq(Units.frog.wounds, 3)
	assert_eq(a.visit.stage, "frog_fight", "the fight goes on")
	assert_eq(a.survivors.filter(func(s): return s.injury == "severe").size(), 0)


func test_the_wounds_carry_over_from_round_to_round() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var a := _waiting(Units.frog.pos)
	Units.visit_do(a.id, "frog_attack")
	for r in 2:
		Units.dice = ForcedDice.new([14, 14, 14, 15, 15, 15], [1, 1, 1])
		Units.visit_do(a.id)
	assert_eq(Units.frog.wounds, 6)


func test_a_slam_that_misses_fells_and_a_natural_1_kills() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var a := _waiting(Units.frog.pos)
	Units.visit_do(a.id, "frog_attack")
	# nobody hits; slam 1 picks the first survivor (8: felled), slam 2 the first of the two standing (1: killed), slam 3 the last (15: dodged)
	Units.dice = ForcedDice.new([2, 2, 2, 8, 1, 15], [1, 1, 1])
	Units.visit_do(a.id)
	assert_eq(a.crew, 2, "one was killed")
	assert_eq(a.survivors.filter(func(s): return s.injury == "severe").size(), 1, "and one felled")


func test_pulling_back_ends_the_fight_and_the_frog_keeps_its_wounds_until_the_season_turns() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	var a := _waiting(Units.frog.pos)
	Units.visit_do(a.id, "frog_attack")
	Units.dice = ForcedDice.new([14, 14, 14, 15, 15, 15], [1, 1, 1])
	Units.visit_do(a.id)
	Units.visit_do(a.id, "pull")
	assert_eq(a.visit.stage, "done")
	assert_eq(a.visit.outcome, "pulled")
	assert_eq(Units.frog.wounds, 3)
	Units.visit_finish(a.id)
	assert_eq(a.stage, "station")
	Units.dice = load("res://scripts/dice.gd").new()   # the season rolls its own dice (the frog may reach your colony)
	Units.season_turn()
	assert_eq(Units.frog.wounds, 0, "it heals fully each season")


func test_a_party_waiting_at_the_frog_loses_it_when_it_moves_on() -> void:
	_loose_frog(Game.home(Data.PLAYER) + Vector2i(30, 0), "player")
	var a := _waiting(Units.frog.pos)
	Units.season_turn()
	assert_eq(a.visit.stage, "done")
	assert_eq(a.visit.outcome, "cold")
	assert_true(_log_has("moved on"))


# ---------------------------------------------------------------- the rampage

func test_the_loose_frog_walks_toward_its_target_a_tile_a_day() -> void:
	var start := hq + Vector2i(60, 0)
	if not Game.in_bounds(start):
		start = hq - Vector2i(40, 0)
	_loose_frog(start, "player")
	var before: float = Vector2(Units.frog.pos - hq).length()
	Units.season_turn()
	var after: float = Vector2(Units.frog.pos - hq).length()
	assert_lt(after, before - 10.0, "a season's walk brought it a good way nearer")
	assert_le(before - after, float(Data.SEASON_DAYS) * 1.5 + 1.0, "but not faster than about a tile a day")


func test_the_frog_walk_is_in_the_season_replay() -> void:
	_loose_frog(hq + Vector2i(40, 0), "player")
	Units.season_turn()
	var actor := {}
	for a in Units.replay.actors:
		if a.kind == "frog":
			actor = a
	assert_false(actor.is_empty())
	assert_gt(actor.trail.size(), 10)
	assert_false(actor.get("wild", false), "the frog's walk is what the replay is about")


func test_a_frog_at_your_colony_raids_it_and_a_win_destroys_buildings_and_troops() -> void:
	var farm := World.claimable_tile()
	Game.tile(farm)["o"] = Data.PLAYER
	Game.tile(farm)["b"] = "farm"
	Game.troops = 10
	_loose_frog(farm, "player")
	Units.dice = ForcedDice.new([19], [])   # the raid roll
	Units._frog_raid(Data.PLAYER)
	assert_eq(Game.tile(farm)["b"], "", "the farm was smashed")
	assert_eq(Game.troops, 8, "a fifth of the troops")
	assert_true(_log_has("Giant Frog tore through your colony"))


func test_a_frog_driven_back_rests_a_season() -> void:
	_loose_frog(hq, "player")
	Game.troops = 40
	Units.dice = ForcedDice.new([2], [])
	Units._frog_raid(Data.PLAYER)
	assert_eq(Units.frog.rest, 1)
	assert_eq(Game.troops, 40)
	Units.season_turn()
	assert_eq(Units.frog.rest, 0, "and it sits out the season")


func test_a_frog_at_the_rust_kings_costs_them_troops_and_walls() -> void:
	_loose_frog(Game.home(Data.AI), "ai")
	Game.ai["troops"] = 20
	Game.ai["walls"] = 6
	Units.dice = ForcedDice.new([20], [])
	Units._frog_raid(Data.AI)
	assert_eq(Game.ai["troops"], 16)
	assert_lt(Game.ai["walls"], 6)


func test_the_frog_dead_stays_dead() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	Units.frog["state"] = "dead"
	Units.season_turn()
	assert_eq(Units.frog.state, "dead")
	assert_true(Units.frog_target().is_empty())
	assert_false(Units.frog_at(hq + Vector2i(6, 0)))


func test_the_frog_stands_across_four_tiles() -> void:
	_loose_frog(hq + Vector2i(6, 0))
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		assert_true(Units.frog_at(hq + Vector2i(6, 0) + d))
	assert_false(Units.frog_at(hq + Vector2i(8, 0)))
	assert_false(Units.frog_at(hq + Vector2i(5, 0)))


func test_the_frog_and_a_fight_in_progress_survive_saving() -> void:
	_loose_frog(hq + Vector2i(6, 0), "ai")
	Units.frog["wounds"] = 4
	var a := _waiting(Units.frog.pos)
	Units.visit_do(a.id, "frog_attack")
	Game.save_game("frog_test")
	assert_true(Game.load_game("frog_test"))
	assert_eq(Units.frog.state, "loose")
	assert_eq(Units.frog.pos, hq + Vector2i(6, 0))
	assert_eq(Units.frog.target, "ai")
	assert_eq(Units.frog.wounds, 4)
	assert_eq(Units.units[0].visit.stage, "frog_fight")
	assert_ne(Units.frog.lair, Vector2i(-1, -1), "and where it slept")
