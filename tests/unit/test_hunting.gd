extends "res://tests/framework/test_case.gd"
## Wild animals (deer, black bears, brown bears) and hunting them: where they start and how they wander, the two rolls of a hunt (track,
## then the kill shot), what a hunt pays, bears attacking parties that come too close, and the animals in a save.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var open: Vector2i   # a patch of open ground (four tiles each way) where an animal can run


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	D20.loot_scale = D20Data.LOOT_SCALE
	D20.permadeath = D20Data.PERMADEATH
	Game.res["grain"] = 100
	Game.res["meat"] = 0
	open = World.find_tile(func(c, t): return _open_ground(c))
	assert_ne(open, Vector2i(-1, -1), "needs a patch of open ground")


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


func _open_ground(c: Vector2i) -> bool:
	for y in range(c.y - 4, c.y + 5):
		for x in range(c.x - 4, c.x + 5):
			if not Units._animal_can_stand(Vector2i(x, y)):
				return false
	return true


## A party standing at `at` with no traits (so the rolls are just the d20 and the situation).
func _party(job := "scav", at := Vector2i(-1, -1), mover := "foot") -> Dictionary:
	var spot: Vector2i = at if Game.in_bounds(at) else open
	var u: Dictionary = Units._make_unit(job, Data.PLAYER, mover, spot, hq)
	u.crew = 3 if job == "scav" else 2
	u.survivors = Units._make_crew(u.crew)
	for s in u.survivors:
		s.traits = []
	if job == "scout":
		u.food = {"grain": Data.SCOUT_PACK}
		u.stage = "station"
	Units.units.append(u)
	return u


## The only animal in the world: one of `kind` at `at`.
func _animal(kind: String, at: Vector2i) -> Dictionary:
	Units.animals = []
	return Units._add_animal(kind, at)


func _hunt(u: Dictionary, a: Dictionary, d20s: Array, totals := []) -> void:
	Units.dice = ForcedDice.new(d20s, totals)
	Units._start_hunt(u, a)


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


# ---------------------------------------------------------------- the animals on the map

func test_a_new_game_starts_with_every_kind_of_animal_on_its_own_sort_of_ground() -> void:
	for kind in Data.ANIMALS:
		var of_kind: Array = Units.animals.filter(func(a): return a.kind == kind)
		assert_eq(of_kind.size(), Data.ANIMALS[kind].start, kind)
		for a in of_kind:
			var t: Dictionary = Game.tile(a.pos)
			assert_has(Data.ANIMALS[kind].terrain, t["t"], "%s stands on %s" % [kind, t["t"]])
			assert_eq(t["o"], Data.NONE, "nobody's land")
			assert_eq(t["b"], "", "nothing built there")
			assert_ne(Game.slopes[Game.idx(a.pos)], "steep")


func test_no_animal_starts_close_to_a_colony() -> void:
	for a in Units.animals:
		for owner in [Data.PLAYER, Data.AI, Data.TOWN]:
			assert_ge(Vector2(a.pos - Game.home(owner)).length(), Data.ANIMAL_MIN_GAP, "%s is clear of the colonies" % a.kind)


func test_no_two_animals_share_a_tile_and_each_has_its_own_id() -> void:
	var tiles := {}
	var ids := {}
	for a in Units.animals:
		assert_false(tiles.has(a.pos))
		assert_false(ids.has(a.id))
		tiles[a.pos] = true
		ids[a.id] = true
	assert_false(ids.has(Units.FROG_ID), "id 1 is the frog's")


func test_the_frog_sleeps_under_the_biggest_ruin_field() -> void:
	assert_eq(Units.frog.state, "dormant")
	var best := -1
	var lair := Vector2i(-1, -1)
	for cat in Game.catastrophes:
		var n := 0
		var r: int = int(cat.radius) + 1
		for y in range(cat.pos.y - r, cat.pos.y + r + 1):
			for x in range(cat.pos.x - r, cat.pos.x + r + 1):
				var c := Vector2i(x, y)
				if Game.in_bounds(c) and Game.tile(c)["t"] == "ruins" and Vector2(c - cat.pos).length() <= r:
					n += 1
		if n > best:
			best = n
			lair = cat.pos
	assert_eq(Units.frog.lair, lair)
	assert_ne(lair, Vector2i(-1, -1))


func test_animals_wander_but_stay_near_home_on_open_ground_and_never_pile_up() -> void:
	for season in 40:
		Units._animals_turn()
	var tiles := {}
	for a in Units.animals:
		assert_le(Vector2(a.pos - a.home).length(), Data.ANIMAL_HOME_RANGE + 1.5, "%s stays near where it started" % a.kind)
		assert_false(tiles.has(a.pos), "two animals on one tile")
		tiles[a.pos] = true
		var t: Dictionary = Game.tile(a.pos)
		assert_eq(t["o"], Data.NONE)
		assert_ne(t["t"], "water")
		assert_eq(t["b"], "")


func test_a_killed_animal_is_replaced_in_time_by_one_from_far_away() -> void:
	var before: int = Units.animals.filter(func(a): return a.kind == "black_bear").size()
	var bear: Dictionary = Units.animals.filter(func(a): return a.kind == "black_bear")[0]
	Units.animals.erase(bear)
	var back := false
	for season in 600:
		Units._animals_turn()
		if Units.animals.filter(func(a): return a.kind == "black_bear").size() == before:
			back = true
			break
	assert_true(back, "another bear wandered in")
	for a in Units.animals:
		if a.kind == "black_bear":
			assert_false(Game.in_sight(Data.PLAYER, a.pos) and Vector2(a.pos - hq).length() < Data.ANIMAL_ARRIVE_GAP, "it did not appear in front of you")


func test_an_animal_never_moves_onto_your_land() -> void:
	var edge := hq + Vector2i(Data.ANIMAL_MIN_GAP + 1, 0)
	var a := _animal("deer", edge)
	for tile in Game.owned(Data.PLAYER):
		assert_ne(tile, a.pos)
	for season in 30:
		Units._animals_turn()
		assert_eq(Game.tile(a.pos)["o"], Data.NONE)


# ---------------------------------------------------------------- the rolls of a hunt

func test_a_hunt_is_a_track_roll_then_a_kill_shot_and_the_panel_says_hunt() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [12, 14], [7])
	assert_eq(u.stage, "site")
	assert_eq(u.visit.ruin, "hunt")
	assert_eq(u.visit.stage, "track")
	var view := Units.visit_view(u)
	assert_eq(view.ruin, "hunt")
	assert_eq(view.check, "Track")
	assert_eq(view.dc, 8)
	assert_true(view.buttons.any(func(b): return b.id == "roll"))
	assert_true(view.buttons.any(func(b): return b.id == "home"), "you can give up")
	assert_gt(Units.visit_do(u.id), 0, "the first press rolls the die")
	assert_eq(u.visit.stage, "kill")
	view = Units.visit_view(u)
	assert_eq(view.check, "Kill shot")
	assert_eq(view.dc, 10)
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done")
	assert_eq(u.visit.outcome, "killed")


func test_a_deer_pays_a_medium_package_of_meat_at_the_loot_scale() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [12, 14], [7])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(u.visit.loot, {"meat": 21}, "2d6 came to 7, times the loot scale of 3")
	Units.visit_finish(u.id)
	assert_eq(u.carry, {}, "the meat is food: it went in the pack")
	assert_eq(int(u.food.get("meat", 0)), 21)
	assert_eq(u.stage, "station", "a scavenger party waits for orders with it")
	assert_true(Units.animals.is_empty(), "the deer is gone")
	assert_true(_log_has("brought down the deer"))


func test_a_critical_kill_pays_one_size_more() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [12, 20], [14])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(u.visit.loot, {"meat": 42}, "a large package: 4d6 came to 14")


func test_a_black_bear_pays_a_large_package_and_a_brown_bear_adds_hide_gold() -> void:
	var u := _party()
	var a := _animal("black_bear", u.pos)
	_hunt(u, a, [14, 16], [14])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(u.visit.loot, {"meat": 42})
	var v := _party("scav", open + Vector2i(1, 0))
	var b := _animal("brown_bear", v.pos)
	_hunt(v, b, [16, 19], [14, 4])
	Units.visit_do(v.id)
	Units.visit_do(v.id)
	assert_eq(v.visit.loot, {"meat": 42, "gold": 12}, "a large package of meat and a small one of gold for the hide")


func test_a_creeping_approach_makes_the_kill_shot_easier() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [20], [])
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "kill")
	assert_eq(u.visit.kill_sit, D20Data.HUNT_UNSEEN)
	var view := Units.visit_view(u)
	assert_eq(view.mod, D20Data.HUNT_UNSEEN, "+3 on the kill shot")


func test_a_missed_track_roll_loses_the_trail_and_the_animal_wanders_off() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	var start: Vector2i = a.pos
	_hunt(u, a, [5], [])
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done")
	assert_eq(u.visit.outcome, "cold")
	Units.visit_finish(u.id)
	assert_eq(Units.animals.size(), 1, "the deer is still out there")
	assert_ne(a.pos, start, "but it has gone")
	assert_eq(u.stage, "station")
	assert_true(u.carry.is_empty())


func test_a_natural_1_on_the_track_roll_sends_a_deer_bolting_and_a_bear_charging() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [1], [])
	Units.visit_do(u.id)
	assert_eq(u.visit.outcome, "bolted")
	var v := _party("scav", open + Vector2i(1, 0))
	var b := _animal("black_bear", v.pos)
	_hunt(v, b, [1, 16], [14])
	Units.visit_do(v.id)
	assert_eq(v.visit.stage, "kill", "the bear charges: the kill shot is forced")
	assert_eq(v.visit.kill_sit, D20Data.HUNT_CHARGED)
	var view := Units.visit_view(v)
	assert_eq(view.mod, D20Data.HUNT_CHARGED, "at a penalty")
	assert_false(view.buttons.any(func(b2): return b2.id == "home"), "there is no giving up with a bear on you")


func test_giving_up_the_hunt_leaves_the_animal_alone() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [], [])
	Units.visit_do(u.id, "home")
	assert_eq(u.visit.outcome, "left")
	Units.visit_finish(u.id)
	assert_eq(a.pos, u.pos, "it never knew")
	assert_eq(Units.animals.size(), 1)


func test_a_missed_kill_shot_on_a_deer_costs_the_party_nothing() -> void:
	var u := _party()
	var a := _animal("deer", u.pos)
	_hunt(u, a, [12, 3], [])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(u.visit.outcome, "escaped")
	assert_eq(u.visit.injuries, {}, "nobody is hurt by a deer")
	assert_eq(float(u.visit.carried_loss), 0.0)


func test_a_missed_kill_shot_on_a_bear_mauls_the_party() -> void:
	var u := _party()
	u.carry = {"gold": 8}
	var a := _animal("black_bear", u.pos)
	_hunt(u, a, [14, 8], [])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(u.visit.outcome, "escaped")
	assert_eq(float(u.visit.carried_loss), 0.25, "a quarter of the load")
	assert_eq(u.visit.injuries.size(), 1, "someone is hurt")
	Units.visit_finish(u.id)
	assert_eq(u.carry, {"gold": 6})
	assert_eq(Units.animals.size(), 1, "the bear lives")
	assert_ne(a.pos, u.pos, "and has run off")


func test_a_natural_1_on_a_brown_bear_can_wipe_the_party_out() -> void:
	var u := _party()
	var a := _animal("brown_bear", u.pos)
	_hunt(u, a, [16, 1, 3], [])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_true(u.visit.wiped, "the fatal fumble: a d20 of 3 is 5 or less")
	Units.visit_finish(u.id)
	assert_true(u.get("gone", false))
	assert_eq(Units.animals.size(), 1)


func test_the_kill_dc_of_a_bear_is_the_dc_of_a_raider_of_its_strength() -> void:
	assert_eq(Units.kill_dc("black_bear"), D20Visit.enemy_dc(3))
	assert_eq(Units.kill_dc("brown_bear"), D20Visit.enemy_dc(5))
	assert_eq(Units.kill_dc("deer"), 10)


func test_a_brown_bear_outnumbers_a_small_party_but_not_a_war_rig() -> void:
	var u := _party()
	var a := _animal("brown_bear", u.pos)
	_hunt(u, a, [16, 16], [])
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "kill")
	var parts: Array = Units.visit_view(u).parts
	assert_true(parts.any(func(p): return p.label == "outnumbered"), "strength 5 against a party of 3")
	var rig := _party("scav", open + Vector2i(2, 0), "car")
	var b := _animal("brown_bear", rig.pos)
	_hunt(rig, b, [16, 16], [])
	Units.visit_do(rig.id)
	assert_false(Units.visit_view(rig).parts.any(func(p): return p.label == "outnumbered"), "a war rig adds its 3 to the party's strength")


# ---------------------------------------------------------------- who hunts and how they get there

func test_a_scouting_party_can_hunt_what_is_beside_it_and_goes_back_to_keeping_watch() -> void:
	var u := _party("scout")
	var a := _animal("deer", u.pos + Vector2i(1, 0))
	assert_eq(Units.hunt_targets(u).size(), 1)
	Units.dice = ForcedDice.new([12, 14], [7])
	assert_true(Units.begin_hunt(u.id, a.id))
	assert_eq(u.stage, "site")
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station", "a scouting party stays where it is")
	assert_eq(u.carry, {}, "the meat is food: it went in the pack")
	assert_eq(int(u.food.get("meat", 0)), 21)


func test_planes_and_boats_cannot_hunt_and_animals_out_of_reach_are_not_targets() -> void:
	var plane := _party("scout", open, "plane")
	var a := _animal("deer", plane.pos)
	assert_true(Units.hunt_targets(plane).is_empty(), "a plane has no gun")
	var far := _party("scout", open + Vector2i(3, 0))
	assert_true(Units.hunt_targets(far).is_empty(), "the deer is not beside this party")
	assert_false(Units.begin_hunt(far.id, a.id))


func test_hunters_sent_after_a_deer_walk_there_and_start_the_hunt() -> void:
	var target := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
		and not Game.route("foot", hq, c).is_empty())
	var a := _animal("deer", target)
	a.home = target
	assert_eq(Units.send_status("scav", "foot", a.pos, a.id), "")
	Units.send("scav", "foot", a.pos, a.id)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.dest, a.id)
	for i in 12:
		if u.stage == "site":
			break
		a.pos = target   # it stays put while they walk
		Units.season_turn()
	assert_eq(u.stage, "site")
	assert_eq(u.visit.ruin, "hunt")
	assert_eq(u.visit.animal_id, a.id)


func test_hunters_who_arrive_to_find_the_tracks_gone_cold_wait_for_orders() -> void:
	var u := _party()
	u.dest = 999
	u.target = u.pos
	u.stage = "out"
	Units._arrive(u)
	assert_eq(u.stage, "station")
	assert_false(u.has("visit"))
	assert_true(_log_has("tracks have gone cold"))


func test_a_party_cannot_be_sent_after_an_animal_a_party_is_already_heading_for() -> void:
	var target := World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
		and not Game.route("foot", hq, c).is_empty())
	var a := _animal("deer", target)
	Units.send("scav", "foot", a.pos, a.id)
	assert_eq(Units.send_status("scav", "foot", a.pos, a.id), "A party is already heading there")


# ---------------------------------------------------------------- bears attack parties that come too close

func test_a_bear_beside_a_party_attacks_it_at_the_end_of_the_season_and_a_win_drives_it_off() -> void:
	var u := _party()
	var bear := _animal("black_bear", u.pos + Vector2i(1, 0))
	Units.dice = ForcedDice.new([16, 5], [3])   # the party's best fighter beats DC 12, then the package roll
	Units._bear_attacks()
	assert_true(_log_has("drove off a black bear"))
	assert_gt(Vector2(bear.pos - u.pos).length(), Data.BEAR_REACH, "the bear has been driven back")
	assert_eq(Units.animals.size(), 1, "but it is not dead")


func test_a_bear_that_wins_costs_an_injury_and_a_share_of_the_load() -> void:
	var u := _party()
	u.carry = {"metal": 8}
	var bear := _animal("black_bear", u.pos + Vector2i(0, 1))
	Units.dice = ForcedDice.new([8], [])   # a miss, but not a natural 1 and not by 6
	Units._bear_attacks()
	assert_true(_log_has("mauled your scavenger party"))
	assert_eq(u.carry, {"metal": 6})
	assert_eq(u.survivors.filter(func(s): return s.injury != "none").size(), 1)
	assert_eq(bear.pos, u.pos + Vector2i(0, 1), "the bear stays")
	assert_eq(u.crew, 3, "nobody died")


func test_a_natural_1_against_a_bear_kills_someone() -> void:
	D20.permadeath = false
	var u := _party()
	_animal("black_bear", u.pos + Vector2i(1, 0))
	Units.dice = ForcedDice.new([1], [])
	Units._bear_attacks()
	assert_eq(u.crew, 2)
	assert_eq(u.survivors.size(), 2)


func test_a_bear_two_tiles_away_still_attacks_but_three_does_not() -> void:
	var u := _party()
	var bear := _animal("black_bear", u.pos + Vector2i(3, 0))
	Units.dice = ForcedDice.new([], [])
	Units._bear_attacks()
	assert_eq(bear.pos, u.pos + Vector2i(3, 0), "out of reach: nothing happened")
	assert_false(_log_has("black bear"))
	bear.pos = u.pos + Vector2i(2, 0)
	Units.dice = ForcedDice.new([16, 5], [3])
	Units._bear_attacks()
	assert_true(_log_has("drove off a black bear"))


func test_deer_do_not_attack_and_planes_and_boats_are_never_attacked() -> void:
	var u := _party()
	_animal("deer", u.pos + Vector2i(1, 0))
	Units.dice = ForcedDice.new([], [])
	Units._bear_attacks()
	assert_true(Game.log_lines.is_empty() or not _log_has("deer"))
	var plane := _party("scout", open + Vector2i(4, 0), "plane")
	_animal("brown_bear", plane.pos)
	Units._bear_attacks()
	assert_eq(plane.crew, 2)


func test_a_party_hunting_a_bear_is_not_attacked_by_it_as_well() -> void:
	var u := _party()
	var bear := _animal("black_bear", u.pos)
	_hunt(u, bear, [], [])
	Units._bear_attacks()
	assert_false(_log_has("mauled"))
	assert_false(_log_has("drove off"))


func test_a_bear_that_kills_the_party_ends_it() -> void:
	var u := _party()
	_animal("brown_bear", u.pos)
	Units.dice = ForcedDice.new([1, 2], [])   # a natural 1, and a fumble of 2
	Units._bear_attacks()
	assert_true(u.get("gone", false))
	assert_true(_log_has("killed your scavenger party"))


# ---------------------------------------------------------------- saving

func test_the_animals_and_a_hunt_in_progress_survive_saving() -> void:
	var u := _party()
	var a := _animal("black_bear", u.pos)
	var other: Dictionary = Units._add_animal("deer", hq + Vector2i(15, 3))
	_hunt(u, a, [14], [])
	Units.visit_do(u.id)
	Game.save_game("hunt_test")
	var animals_before: Array = Units.animals.duplicate(true)
	assert_true(Game.load_game("hunt_test"))
	assert_eq(Units.animals.size(), 2)
	for i in animals_before.size():
		assert_eq(Units.animals[i].pos, animals_before[i].pos)
		assert_eq(Units.animals[i].kind, animals_before[i].kind)
		assert_eq(Units.animals[i].id, animals_before[i].id)
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.visit.ruin, "hunt")
	assert_eq(loaded.visit.stage, "kill")
	assert_eq(typeof(loaded.visit.animal_id), TYPE_INT)
	assert_eq(typeof(loaded.visit.kill_dc), TYPE_INT)
	assert_eq(Units.frog.state, "dormant")
	assert_ne(other.id, 0)
