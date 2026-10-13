extends "res://tests/framework/test_case.gd"
## A raider band meeting a party on the road is a ruin fight (d20_visit.gd): the party's best fighter rolls d20 plus traits and
## conditions against the band's DC, a plain miss costs an injury and a share of the load, and only a natural 1 kills someone.

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
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	D20.loot_scale = D20Data.LOOT_SCALE


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


func _party(traits := []) -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq + Vector2i(4, 0), hq)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = traits.duplicate()
	Units.units.append(u)
	return u


func _band(strength: int, at := Vector2i(5, 0)) -> Dictionary:
	Units._spawn_band(hq + at, strength)
	return Units.units[-1]


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


func _hurt(u: Dictionary, level: String) -> int:
	return u.survivors.filter(func(s): return s.injury == level).size()


func test_a_band_of_strength_2_is_a_dc_of_10_and_a_5_is_16() -> void:
	assert_eq(D20Visit.enemy_dc(2), 10)
	assert_eq(D20Visit.enemy_dc(5), 16)


func test_beating_the_band_catches_one_and_pays_a_package() -> void:
	var u := _party()
	var band := _band(2)
	Units.dice = ForcedDice.new([15, 5], [3])   # the fight: 15 against DC 10 is a SUCCESS, then metal for the package
	var prisoners := Game.prisoners
	Units._fight(band, u)
	assert_true(band.get("gone", false), "the band is driven off")
	assert_eq(Game.prisoners, prisoners + 1)
	assert_false(u.carry.is_empty(), "with a package for the win")
	assert_eq(u.crew, 3)
	assert_eq(_hurt(u, "light") + _hurt(u, "severe"), 0, "nobody hurt")
	assert_true(_log_has("fought off a raider band and caught one of them"))


func test_a_plain_miss_hurts_one_person_and_costs_a_quarter_of_the_load_but_kills_nobody() -> void:
	var u := _party()
	u.carry = {"metal": 8}
	var band := _band(2)
	Units.dice = ForcedDice.new([5])   # 5 against DC 10: margin -5, a FAILURE
	Units._fight(band, u)
	assert_eq(Units.dice.d20_calls, 1, "one die")
	assert_eq(u.crew, 3, "nobody dies on a plain miss")
	assert_eq(u.survivors.size(), 3)
	assert_eq(_hurt(u, "light"), 1, "the one who rolled is hurt")
	assert_eq(u.carry, {"metal": 6}, "a quarter of 8 is taken")
	assert_eq(band.strength, 3, "and the band grows bolder")
	assert_false(band.get("gone", false))
	assert_true(_log_has("Nobody was killed"))
	assert_true(_log_has("took 2 metal"))


func test_a_natural_1_is_a_severe_injury_half_the_load_and_one_death() -> void:
	var u := _party()
	u.carry = {"metal": 8}
	var band := _band(2)
	Units.dice = ForcedDice.new([1])
	Units._fight(band, u)
	assert_eq(u.crew, 2, "one person killed")
	assert_eq(u.survivors.size(), 2)
	assert_eq(u.carry, {"metal": 4}, "half of 8 is taken")
	assert_eq(_hurt(u, "severe") + _hurt(u, "light"), 1 if u.survivors.any(func(s): return s.injury != "none") else 0)
	assert_true(_log_has("was killed"))


func test_a_cowardly_party_that_misses_runs_clean_without_an_injury() -> void:
	var u := _party(["cowardly"])
	u.carry = {"metal": 8}
	var band := _band(2)
	Units.dice = ForcedDice.new([10])   # 10 -3 = 7 against DC 10: a FAILURE that a coward flees from
	Units._fight(band, u)
	assert_eq(_hurt(u, "light") + _hurt(u, "severe"), 0, "traits count: a coward flees without a scratch")
	assert_eq(u.crew, 3)


func test_a_critical_miss_against_a_hard_band_can_wipe_the_party_out() -> void:
	var u := _party()
	var band := _band(5)   # DC 16, hard enough for the fatal fumble
	Units.dice = ForcedDice.new([1, 3])   # a natural 1, then a fumble roll of 3
	Units._fight(band, u)
	assert_true(u.get("gone", false), "everyone is dead")
	assert_true(_log_has("wiped out"))
	assert_eq(Units.dice.d20_calls, 2)


func test_a_fumble_roll_of_6_or_more_spares_the_party() -> void:
	var u := _party()
	var band := _band(5)
	Units.dice = ForcedDice.new([1, 9])
	Units._fight(band, u)
	assert_false(u.get("gone", false))
	assert_eq(u.crew, 2, "the natural 1 still costs one life")


func test_an_outnumbered_party_rolls_with_a_penalty() -> void:
	var u := _party()
	u.crew = 1
	u.survivors = [u.survivors[0]]   # a party of one against a strength 5 band
	var band := _band(5)
	Units.dice = ForcedDice.new([10, 10])   # the fight (a critical miss against DC 16), then a fumble roll that spares them
	Units._fight(band, u)
	assert_true(_log_has("-2 outnumbered"), "the log shows the penalty")


func test_a_band_beside_a_party_fights_it_in_the_season_turn() -> void:
	var u := _party()
	var band := _band(2, Vector2i(5, 0))   # one tile from the party at (4, 0)
	Units.dice = ForcedDice.new([15, 5], [3])
	Units._ambushes()
	assert_true(band.get("gone", false))
	assert_eq(Units.dice.d20_calls, 2, "the fight and the package")


func test_planes_and_boats_are_never_ambushed() -> void:
	var u := _party()
	u.mover = "plane"
	var band := _band(2)
	Units.dice = ForcedDice.new([])
	Units._ambushes()
	assert_false(band.get("gone", false))
	assert_eq(Units.dice.d20_calls, 0)
