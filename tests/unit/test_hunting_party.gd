extends "res://tests/framework/test_case.gd"
## The hunting party: your troops (not your people) sent hunting. It is a party of three Veterans drawn from the troops, it goes after animals and the
## Giant Frog like a scavenger party does, and its troops come back to being troops, minus anyone who died.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var target: Vector2i


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
	Game.troops = 6
	target = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 5 and c.distance_to(hq) < 9 \
		and not Game.route("foot", hq, c).is_empty() and Units._animal_can_stand(c))


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


func _send(dest := -1) -> Dictionary:
	Units.send("hunters", "foot", target, dest)
	return Units.units[-1]


func test_a_war_party_is_three_troops_and_three_grain() -> void:
	var e: Dictionary = Data.EXPEDITIONS["hunters"]
	assert_eq(e.crew, 3)
	assert_eq(e.cost, {"grain": 3})
	var pop: int = Game.pop
	var grain: int = Game.res["grain"]
	var u := _send()
	assert_eq(u.job, "hunters")
	assert_eq(u.crew, 3)
	assert_eq(Game.troops, 3, "three troops left home")
	assert_eq(Game.pop, pop, "and not a colonist")
	assert_eq(Game.res["grain"], grain - 3)


func test_it_needs_three_troops_to_spare() -> void:
	Game.troops = 2
	assert_eq(Units.send_status("hunters", "foot", target), "Need 3 troops to spare")
	Game.troops = 3
	assert_eq(Units.send_status("hunters", "foot", target), "")


func test_every_soldier_is_a_veteran() -> void:
	var u := _send()
	for s in u.survivors:
		assert_has(s.traits, "veteran")
		assert_ge(s.traits.size(), 1)
		assert_le(s.traits.size(), 3)
	assert_eq(Units.glyph_kind(u), "soldier")
	assert_eq(Units.kind_info("soldier").name, "Hunting party")


func test_a_war_party_on_a_war_rig_is_drawn_as_the_rig() -> void:
	Game.vehicles["car"] = 1
	Game.res["fuel"] = 50
	Units.send("hunters", "car", target)
	assert_eq(Units.glyph_kind(Units.units[-1]), "car")


func test_a_war_party_hunts_what_it_is_sent_after() -> void:
	var a: Dictionary = Units._add_animal("deer", target)
	var u := _send(a.id)
	for i in 12:
		if u.stage == "site":
			break
		a.pos = target
		Units.season_turn()
	assert_eq(u.stage, "site")
	assert_eq(u.visit.ruin, "hunt")
	assert_eq(Units.stage_text(u), "hunting")
	Units.dice = ForcedDice.new([12, 14], [7])
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	assert_eq(u.carry, {"meat": 21})
	assert_eq(u.stage, "back")


func test_the_troops_come_home_and_are_troops_again() -> void:
	var u := _send()
	u.carry = {"meat": 10}
	var meat: int = Game.res["meat"]
	var pop: int = Game.pop
	Units._come_home(u)
	assert_eq(Game.troops, 6)
	assert_eq(Game.pop, pop)
	assert_eq(Game.res["meat"], meat + 10)


func test_a_soldier_who_died_is_a_troop_lost_for_good() -> void:
	var u := _send()
	Units._casualty(u)
	Units._come_home(u)
	assert_eq(Game.troops, 5)


func test_a_wiped_out_war_party_takes_its_troops_with_it() -> void:
	var u := _send()
	u.crew = 0
	u.survivors = []
	Units._lost(u)
	assert_eq(Game.troops, 3)
	assert_true(Game.log_lines.any(func(l): return l.contains("hunting party was wiped out")))


func test_veterans_do_not_die_of_a_natural_1_on_the_kill_shot() -> void:
	var u := _send()
	u.stage = "site"
	u.pos = target
	for s in u.survivors:
		s.traits.erase("lucky")   # the other traits are drawn at random, and a Lucky hunter would reroll the natural 1 and need a third die
	var a: Dictionary = Units._add_animal("brown_bear", target)
	Units.dice = ForcedDice.new([16, 1], [])   # found it, then a natural 1 on a DC 16 kill shot: for anyone else a fumble that can wipe them out
	Units._start_hunt(u, a)
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_false(u.visit.wiped, "the Veteran trait turns a critical failure into a plain one")
	assert_eq(u.visit.outcome, "escaped")


func test_two_war_parties_cannot_go_after_the_same_animal_but_can_both_go_after_the_frog() -> void:
	Game.troops = 12
	var a: Dictionary = Units._add_animal("deer", target)
	Units.send("hunters", "foot", a.pos, a.id)
	assert_eq(Units.send_status("hunters", "foot", a.pos, a.id), "A party is already heading there")
	assert_eq(Units.send_status("scav", "foot", a.pos, a.id), "A party is already heading there", "a scavenger party either")
	Units.frog["state"] = "loose"
	Units.frog["pos"] = target
	Units.send("hunters", "foot", target, Units.FROG_ID)
	assert_eq(Units.send_status("hunters", "foot", target, Units.FROG_ID), "", "but nobody is stopped from joining the frog fight")
	assert_eq(Units.send_status("scav", "foot", target, Units.FROG_ID), "")


func test_a_war_party_counts_toward_the_six_it_takes_to_kill_the_frog() -> void:
	Units.frog["state"] = "loose"
	Units.frog["pos"] = target
	var a := _send(Units.FROG_ID)
	var b: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", target, hq)
	b.crew = 3
	b.survivors = Units._make_crew(3)
	b.stage = "site"
	Units.units.append(b)
	a.stage = "site"
	a.pos = target
	for p in [a, b]:
		p["visit"] = load("res://scripts/d20_visit.gd").begin_hunt(Units.visit_ctx(p), 3.0, Units.dice, p.survivors, "frog", Units.FROG_ID, "giant frog")
		p.visit["stage"] = "frog_wait"
	Units.visit_do(a.id, "frog_attack")
	assert_eq(a.visit.stage, "frog_fight")
	assert_eq(b.visit.stage, "frog_fight")
	Units.dice = ForcedDice.new([20, 20, 20, 20, 20, 20], [])
	Units.visit_do(a.id)
	assert_eq(Units.frog.state, "dead")
	Units.visit_finish(a.id)
	assert_eq(a.stage, "back")


func test_a_war_party_survives_saving() -> void:
	var u := _send()
	Game.save_game("war_test")
	assert_true(Game.load_game("war_test"))
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.job, "hunters")
	assert_has(loaded.survivors[0].traits, "veteran")
	assert_eq(Game.troops, 3)
	assert_ne(u.id, 0)
