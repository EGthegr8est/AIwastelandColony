extends "res://tests/framework/test_case.gd"
## The fights between armies on the d20 (the Raiding Dice plan): attacks on a raider camp, the Rust Kings' fort and Dustwell,
## their raids on you, and raider bands at the edge of your land. One die each, against a DC that keeps today's odds; a natural
## 20 pays an extra and a natural 1 costs more. Every die is forced.

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


func test_a_camp_attack_is_one_die_and_a_win_loots_and_scatters() -> void:
	var t := _camp()
	Game.troops = 200   # a DC of 2
	Game.res["gold"] = 0
	Units.dice = ForcedDice.new([10])
	var prisoners := Game.prisoners
	Units.attack_tribe(t.id)
	assert_eq(Units.dice.d20_calls, 1, "one die")
	assert_false(Units.tribes.has(t), "the camp is scattered")
	assert_eq(Game.prisoners, prisoners + 2)
	_between(Game.res["gold"], 5, 15)
	assert_true(_log_has("Your attack on the %s: d20 10 vs DC" % t.name))
	assert_eq(Game.stats.tribes_scattered, 1)


func test_a_natural_20_on_a_camp_attack_brings_half_again_the_loot_and_a_third_prisoner() -> void:
	var t := _camp()
	Game.troops = 200
	Game.res["gold"] = 0
	Units.dice = ForcedDice.new([20])
	var prisoners := Game.prisoners
	Units.attack_tribe(t.id)
	assert_eq(Game.prisoners, prisoners + 3)
	_between(Game.res["gold"], 7, 22, "5 to 15, half again")


func test_a_missed_camp_attack_costs_40_percent_of_the_troops_and_a_natural_1_costs_60() -> void:
	var t := _camp(1000)   # a DC of 20
	Game.troops = 10
	Units.dice = ForcedDice.new([10])
	Units.attack_tribe(t.id)
	assert_eq(Game.troops, 6, "40% of 10 lost")
	assert_true(Units.tribes.has(t), "the camp stands")
	assert_eq(t.strength, 1000)
	Game.raided_this_season = false
	Game.troops = 10
	Units.dice = ForcedDice.new([1])
	Units.attack_tribe(t.id)
	assert_eq(Game.troops, 4, "60% of 10 lost")
	assert_eq(t.strength, 1001, "and the camp grows bolder")


# ---------------------------------------------------------------- the Rust Kings' fort

func _raid_setup(ratio: float) -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.troops = 1
	var per_troop := Game.player_attack(Game.home(Data.AI))
	Game.troops = ceili(ratio * Game.ai_defense(Game.wall_breach()) / per_troop)


func test_a_fort_raid_is_one_die_and_a_win_loots_and_takes_prisoners() -> void:
	_raid_setup(1.2)
	Units.dice = ForcedDice.new([15])
	var gold: int = Game.res["gold"]
	var prisoners := Game.prisoners
	seed(3)
	var caught := 1 + randi() % 3
	seed(3)
	Game.raid_ai()
	assert_eq(Units.dice.d20_calls, 1, "one die, and no buildings of theirs to roll at yet")
	assert_eq(Game.stats.raids_won, 1)
	assert_eq(Game.prisoners, prisoners + caught + (2 if Game.has("w2") else 0))
	assert_true(_log_has("Your raid on the Rust Kings: d20 15 vs DC"))
	assert_gt(Game.res["gold"], gold - 1)


func test_a_natural_20_on_the_fort_raid_adds_a_prisoner_and_a_roll_at_their_buildings() -> void:
	_raid_setup(1.2)
	Game.ai["walls"] = 8
	Game._sync_ai_walls()
	Units.dice = ForcedDice.new([20, 20, 20])   # the raid, then the one extra roll the natural 20 earns and the one a 1.2 raid has
	var prisoners := Game.prisoners
	seed(3)
	var caught := 1 + randi() % 3
	seed(3)
	Game.raid_ai()
	assert_eq(Game.prisoners, prisoners + caught + 1 + (2 if Game.has("w2") else 0), "one more prisoner")
	assert_eq(Units.dice.d20_calls, 3, "the raid and two rolls at their walls (one is the extra)")
	assert_eq(Game.ai["walls"], 0, "both rolls took a wall tile down")
	assert_false(Game.ended(), "the fort still only falls to the 2.5 times rule")


func test_a_missed_fort_raid_costs_40_percent_and_a_natural_1_60() -> void:
	_raid_setup(1.2)
	var troops := Game.troops
	Units.dice = ForcedDice.new([5])
	Game.raid_ai()
	assert_eq(Game.stats.raids_lost, 1)
	assert_eq(Game.troops, troops - int(ceil(troops * 0.4)))
	Game.raided_this_season = false
	troops = Game.troops
	Units.dice = ForcedDice.new([1])
	Game.raid_ai()
	assert_eq(Game.troops, troops - int(ceil(troops * 0.6)))


func test_a_fort_raid_still_costs_relations_and_the_truce_whatever_the_die_says() -> void:
	_raid_setup(1.2)
	Game.ai["relations"] = 40
	Game.ai["truce"] = 3
	Units.dice = ForcedDice.new([5])
	Game.raid_ai()
	assert_eq(Game.ai["relations"], 10)
	assert_eq(Game.ai["truce"], 0)


func test_a_decisive_win_still_storms_the_fort_by_the_2_and_a_half_times_rule() -> void:
	_raid_setup(3.0)
	Units.dice = ForcedDice.new([10])
	Game.raid_ai()
	assert_true(Game.ended(), "a won raid at 3 times their defense")
	assert_eq(Game.ending.kind, "raiders_defeated")
	assert_eq(Game.ending.why, "stormed")


# ---------------------------------------------------------------- Dustwell

func test_conquering_dustwell_is_one_die_and_a_natural_20_brings_two_more_prisoners() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.TOWN]] = true
	Game.troops = 200
	Units.dice = ForcedDice.new([10])
	var prisoners := Game.prisoners
	Game.conquer_town()
	assert_eq(Units.dice.d20_calls, 1)
	assert_eq(Game.town["status"], "conquered")
	assert_eq(Game.prisoners, prisoners + 5)
	assert_true(_log_has("Your attack on Dustwell: d20 10"))
	World.new_game(7)
	Game.contacts["%d:%d" % [Data.PLAYER, Data.TOWN]] = true
	Game.troops = 200
	Units.dice = ForcedDice.new([20])
	prisoners = Game.prisoners
	Game.conquer_town()
	assert_eq(Game.prisoners, prisoners + 7)


func test_a_missed_attack_on_dustwell_costs_40_percent_and_a_natural_1_60() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.TOWN]] = true
	Game.troops = 10
	assert_gt(Game.raid_dc(Game.player_attack(Game.home(Data.TOWN)), Game.TOWN_DEFENSE), 5, "a 5 misses")
	Units.dice = ForcedDice.new([5])
	var trust: int = Game.town["relations"]
	Game.conquer_town()
	assert_ne(Game.town["status"], "conquered")
	assert_eq(Game.town["relations"], trust - 30)
	assert_eq(Game.troops, 6, "40% of 10 lost")
	Game.raided_this_season = false
	Game.troops = 10
	Units.dice = ForcedDice.new([1])
	Game.conquer_town()
	assert_eq(Game.troops, 4, "60% of 10 lost")


# ---------------------------------------------------------------- a Rust Kings raid on you

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
