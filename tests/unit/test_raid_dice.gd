extends "res://tests/framework/test_case.gd"
## The fights between armies on the d20 (the Raiding Dice plan): the Rust Kings' raids on you and raider bands at the edge of your
## land. One die each, against a DC that keeps today's odds; a natural 20 pays an extra and a natural 1 costs more. Every die is
## forced. (Your own attacks are not armies: a Scavenger Party attacks with building rolls, see test_building_raids and test_hearths.)

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)


func after_each() -> void:
	Units.dice = load("res://scripts/dice.gd").new()


func _between(value: int, low: int, high: int, message := "") -> void:
	assert_ge(value, low, message)
	assert_le(value, high, message)


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


# ---------------------------------------------------------------- the rule

func test_the_dc_keeps_todays_odds_to_the_nearest_5_percent() -> void:
	# [attack / defense, DC, chance]
	for row in [[0.25, 17, 20], [0.5, 14, 35], [1.0, 11, 50], [1.5, 9, 60], [2.0, 8, 65], [2.5, 7, 70], [3.0, 6, 75], [5.0, 4, 85]]:
		var dc := Game.raid_dc(row[0] * 10.0, 10.0)
		assert_eq(dc, row[1], "attack %.2f times defense" % row[0])
		assert_eq(Game.raid_chance(dc), row[2])
		var today: float = row[0] / (1.0 + row[0]) * 100.0
		assert_le(absf(Game.raid_chance(dc) - today), 2.6, "within half a step of the old chance (%.1f%%)" % today)


func test_the_dc_is_kept_between_2_and_20_and_copes_with_nothing_on_a_side() -> void:
	assert_eq(Game.raid_dc(0.0, 10.0), 20, "no attack: only a natural 20 wins")
	assert_eq(Game.raid_dc(10.0, 0.0), 2, "no defense: only a natural 1 loses")
	assert_eq(Game.raid_dc(0.01, 500.0), 20)
	assert_eq(Game.raid_dc(1000.0, 1.0), 2)
	assert_eq(Game.raid_chance(20), 5)
	assert_eq(Game.raid_chance(2), 95)
	assert_eq(Game.raid_odds_text(10.0, 10.0), "DC 11, 50% to win")


func test_a_natural_20_always_wins_and_a_natural_1_never_does() -> void:
	Units.dice = ForcedDice.new([20])
	var win := Game.raid_roll(0.0, 10.0, "A hopeless attack")
	assert_true(win.won)
	assert_eq(win.crit, "success")
	Units.dice = ForcedDice.new([1])
	var loss := Game.raid_roll(1000.0, 1.0, "A sure thing")
	assert_false(loss.won)
	assert_eq(loss.crit, "fail")
	Units.dice = ForcedDice.new([10])
	var plain := Game.raid_roll(10.0, 10.0, "Even odds")
	assert_false(plain.won, "10 against DC 11")
	assert_eq(plain.crit, "")
	Units.dice = ForcedDice.new([11])
	assert_true(Game.raid_roll(10.0, 10.0, "Even odds").won, "11 against DC 11")


func test_the_roll_is_written_in_the_log_with_its_numbers() -> void:
	Units.dice = ForcedDice.new([14])
	Game.raid_roll(15.0, 10.0, "Your raid on the Ash Walkers")   # ratio 1.5: DC 9, 60%
	assert_true(_log_has("Your raid on the Ash Walkers: d20 14 vs DC 9 (60% to win), won."))
	Units.dice = ForcedDice.new([20])
	Game.raid_roll(15.0, 10.0, "Your raid")
	assert_true(_log_has("natural 20, a critical win"))
	Units.dice = ForcedDice.new([1])
	Game.raid_roll(15.0, 10.0, "Your raid")
	assert_true(_log_has("natural 1, a critical loss"))


# ---------------------------------------------------------------- a raider camp

func _camp(strength := 6) -> Dictionary:
	var t: Dictionary = Units._spawn_tribe()
	t["class"] = "raider"
	t["strength"] = strength
	return t


func test_their_raid_is_one_die_and_a_win_takes_a_fifth_a_natural_20_takes_three_tenths() -> void:
	Game.ai["troops"] = 1000
	for k in ["wood", "stone", "metal", "gold", "grain", "fuel"]:
		Game.res[k] = 100
	Units.dice = ForcedDice.new([10])
	Game._ai_raid()
	assert_eq(Units.dice.d20_calls, 1, "one die (no buildings are rolled at before season 6)")
	assert_eq(Game.res["wood"], 80)
	assert_true(_log_has("The Rust Kings' raid on your colony: d20 10"))
	for k in ["wood", "stone", "metal", "gold", "grain", "fuel"]:
		Game.res[k] = 100
	Units.dice = ForcedDice.new([20])
	Game._ai_raid()
	assert_eq(Game.res["wood"], 70, "30% taken")


func test_a_beaten_raid_costs_them_40_percent_and_a_natural_1_60_and_you_catch_raiders() -> void:
	Game.troops = 500   # a DC of 20 against their little raid
	Game.ai["troops"] = 10
	var prisoners := Game.prisoners
	Units.dice = ForcedDice.new([10])
	Game._ai_raid()
	assert_eq(Game.ai["troops"], 6)
	assert_eq(Game.prisoners, prisoners + 1)
	assert_true(_log_has("You captured a raider."))
	Game.ai["troops"] = 10
	Units.dice = ForcedDice.new([1])
	Game._ai_raid()
	assert_eq(Game.ai["troops"], 4)
	assert_eq(Game.prisoners, prisoners + 3, "two more")
	assert_true(_log_has("You captured 2 raiders."))


# ---------------------------------------------------------------- bands at your land

func _band_at_your_land(strength: int) -> Dictionary:
	Units._spawn_band(hq, strength)
	return Units.units[-1]


func test_a_band_at_your_land_rolls_once_and_a_win_takes_a_tenth_a_natural_20_a_fifth() -> void:
	var band := _band_at_your_land(100)
	for k in ["grain", "meat", "metal", "gold"]:
		Game.res[k] = 100
	Units.dice = ForcedDice.new([10, 20, 20])   # the band's die, then whatever rolls it makes at a building
	Units._band_turn(band)
	assert_eq(Game.res["grain"], 90)
	assert_true(band.get("gone", false))
	assert_true(_log_has("A raider band at the edge of your land: d20 10"))
	band = _band_at_your_land(100)
	for k in ["grain", "meat", "metal", "gold"]:
		Game.res[k] = 100
	Units.dice = ForcedDice.new([20, 20, 20])
	Units._band_turn(band)
	assert_eq(Game.res["grain"], 80)


func test_a_band_that_misses_is_driven_off_and_a_natural_1_catches_two() -> void:
	Game.troops = 500
	var band := _band_at_your_land(1)
	var prisoners := Game.prisoners
	Units.dice = ForcedDice.new([10])
	Units._band_turn(band)
	assert_eq(Game.prisoners, prisoners + 1)
	assert_eq(Units.dice.d20_calls, 1)
	assert_true(_log_has("caught one of them"))
	band = _band_at_your_land(1)
	Units.dice = ForcedDice.new([1])
	Units._band_turn(band)
	assert_eq(Game.prisoners, prisoners + 3)
	assert_true(_log_has("caught two of them"))
