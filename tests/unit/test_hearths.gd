extends "res://tests/framework/test_case.gd"
## The hearths (D20Data.HEARTHS): your HQ, the Rust Kings' fort and Dustwell. Each is attacked like any building, one roll a press against its
## DC, but only once the defences round it are down and never while its owner has a citadel; bringing one down ends a colony.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var fort: Vector2i
var town: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	fort = Game.home(Data.AI)
	town = Game.home(Data.TOWN)
	D20.loot_scale = D20Data.LOOT_SCALE
	Game.reveal(Data.PLAYER, town, 3)   # Dustwell found


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	D20.loot_scale = D20Data.LOOT_SCALE
	Units.dice = load("res://scripts/dice.gd").new()


## A free tile of `owner`'s within `reach` of `centre`, the `n`th found.
func _free(owner: int, centre: Vector2i, n := 0, reach := 3) -> Vector2i:
	var found := 0
	for c in Game.owned(owner):
		if c != centre and c.distance_to(centre) <= reach and Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water":
			if found == n:
				return c
			found += 1
	return Vector2i(-1, -1)


func _build(owner: int, centre: Vector2i, id: String, n := 0) -> Vector2i:
	var c := _free(owner, centre, n)
	assert_ne(c, Vector2i(-1, -1), "room for a %s" % id)
	Game.tile(c)["b"] = id
	return c


func _clear_guards(c: Vector2i) -> void:
	for p in Game.hearth_guards(c):
		Game.tile(p)["b"] = ""


func test_the_three_hearths_are_known_and_have_dcs() -> void:
	assert_eq(D20Data.HEARTHS, ["hq", "ai_hq", "town"])
	assert_true(Game.is_hearth(hq))
	assert_true(Game.is_hearth(fort))
	assert_true(Game.is_hearth(town))
	assert_false(Game.is_hearth(_free(Data.PLAYER, hq)))
	assert_eq(Game.building_dc(fort), 16)
	assert_eq(Game.building_dc(hq), 16)
	assert_eq(Game.building_dc(town), 14)


func test_a_hearth_cannot_be_attacked_while_defences_stand_round_it() -> void:
	_clear_guards(fort)
	assert_true(Game.can_hit(fort), "nothing guards it")
	var wall := _build(Data.AI, fort, "ai_wall")
	assert_false(Game.can_hit(fort), "a wall stands by it")
	assert_eq(Game.hearth_guards(fort), [wall])
	Game.tile(wall)["b"] = ""
	assert_true(Game.can_hit(fort), "the wall came down")


func test_every_kind_of_defence_counts_as_a_guard() -> void:
	_clear_guards(hq)
	for i in D20Data.HEARTH_GUARDS.size():
		var id: String = D20Data.HEARTH_GUARDS[i]
		var owner: int = Data.AI if id == "ai_wall" else Data.PLAYER
		var centre: Vector2i = fort if owner == Data.AI else hq
		_clear_guards(centre)
		var c := _build(owner, centre, id)
		assert_false(Game.can_hit(centre), id)
		Game.tile(c)["b"] = ""


func test_a_defence_beyond_the_radius_does_not_guard() -> void:
	_clear_guards(fort)
	var far: Vector2i = Vector2i(-1, -1)
	for c in Game.owned(Data.AI):
		if c.distance_to(fort) > D20Data.HEARTH_GUARD_RADIUS + 1 and Game.tile(c)["b"] == "":
			far = c
			break
	if far != Vector2i(-1, -1):
		Game.tile(far)["b"] = "ai_wall"
		assert_true(Game.can_hit(fort))


func test_a_citadel_keeps_its_owners_hearth_safe() -> void:
	_clear_guards(hq)
	assert_true(Game.can_hit(hq))
	var c := _build(Data.PLAYER, hq, "citadel")
	assert_false(Game.can_hit(hq), "the last stand")
	assert_false(Game.can_hit(c), "and the citadel itself cannot be attacked")
	Units.dice = ForcedDice.new([])
	assert_false(Game.attack_building(hq, 5, "A test party"), "no dice are rolled")


func test_dustwell_is_a_target_only_while_it_is_a_neutral_settlement_you_have_found() -> void:
	assert_true(Game.can_hit(town))
	Game.town["status"] = "ally"
	assert_false(Game.can_hit(town), "an ally is not attacked")
	Game.town["status"] = "neutral"
	Game.memory[Data.PLAYER][Game.idx(town)] = null
	Game.contacts = {}
	assert_false(Game.can_hit(town), "a settlement you have not found")


func test_the_cap_on_your_losses_protects_your_hearth_too() -> void:
	_clear_guards(hq)
	Game.buildings_lost = Data.RAID_LOSS_CAP
	assert_false(Game.can_hit(hq))
	Game.buildings_lost = 0
	assert_true(Game.can_hit(hq))


func test_a_party_beside_a_guarded_hearth_cannot_attack_it_and_is_told_why() -> void:
	_clear_guards(fort)
	var wall := _build(Data.AI, fort, "ai_wall")
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", fort + Vector2i(1, 0), fort + Vector2i(1, 0))
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.stage = "station"
	Units.units.append(u)
	assert_false(Units.strike_targets(u).has(fort))
	var blocked: Array = Units.guarded_hearths(u)
	assert_eq(blocked.size(), 1)
	assert_eq(blocked[0].cell, fort)
	assert_has(blocked[0].guards, wall)
	Game.tile(wall)["b"] = ""
	assert_true(Units.strike_targets(u).has(fort), "now it is open")
	assert_eq(Units.guarded_hearths(u), [])


func test_a_band_or_the_frog_does_not_go_for_a_hearth() -> void:
	_clear_guards(hq)
	for c in Game.buildings_of(Data.PLAYER, hq):
		assert_false(Game.is_hearth(c))
	assert_true(Game.buildings_of(Data.PLAYER, hq, true).has(hq), "unless asked for")


func test_the_fort_falling_ends_the_game_as_a_win() -> void:
	_clear_guards(fort)
	Units.dice = ForcedDice.new([20])
	assert_true(Game.attack_building(fort, 0, "A test party"))
	assert_eq(Game.tile(fort)["b"], "")
	assert_eq(Game.ending.kind, "raiders_defeated")
	assert_eq(Game.ending.why, "stormed")


func test_your_hearth_falling_ends_the_game_as_a_loss() -> void:
	_clear_guards(hq)
	Units.dice = ForcedDice.new([20])
	assert_true(Game.attack_building(hq, 0, "A test band"))
	assert_eq(Game.ending.kind, "defeat")
	assert_eq(Game.ending.why, "overrun")


func test_a_roll_that_misses_leaves_the_hearth_standing() -> void:
	_clear_guards(fort)
	Units.dice = ForcedDice.new([5])
	assert_false(Game.attack_building(fort, 0, "A test party"))
	assert_eq(Game.tile(fort)["b"], "ai_hq")
	assert_true(Game.ending.is_empty())


func test_dustwell_falling_makes_it_conquered_and_hands_over_its_land_and_prisoners() -> void:
	var land: Array = Game.owned(Data.TOWN)
	assert_gt(land.size(), 0)
	var prisoners := Game.prisoners
	var relations: int = Game.ai["relations"]
	Units.dice = ForcedDice.new([20])
	assert_true(Game.attack_building(town, 0, "A test party"))
	assert_eq(Game.town["status"], "conquered")
	for c in land:
		assert_eq(Game.tile(c)["o"], Data.PLAYER)
	assert_eq(Game.prisoners, prisoners + int(D20Data.RAID_DICE.town.prisoners))
	assert_eq(Game.ai["relations"], relations - 15)
	assert_true(Game.ending.is_empty(), "the game goes on")


func test_a_party_can_take_the_fort_through_the_visit_rolls() -> void:
	_clear_guards(fort)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", fort + Vector2i(1, 0), fort + Vector2i(1, 0))
	u.crew = 3
	u.survivors = Units._make_crew(3)
	u.stage = "station"
	u.food = {"grain": 10}
	Units.units.append(u)
	Units.dice = ForcedDice.new([20, 10, 10], [6, 6])
	assert_true(Units.begin_strike(u.id, fort))
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done")
	assert_true(u.visit.destroyed, "a natural 20 brings it down")
	Units.visit_finish(u.id)
	assert_eq(Game.ending.kind, "raiders_defeated")
