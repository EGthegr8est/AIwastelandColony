extends "res://tests/framework/test_case.gd"
## The d20 roll system: tiers, modifiers, traits, loot and the outcome of each kind of check. Every die is forced
## (tests/helpers/forced_dice.gd), so each number here is exact. The first block is the design doc's own test table.

const D20 = preload("res://scripts/d20.gd")
const Data = preload("res://scripts/d20_data.gd")
const Dice = preload("res://scripts/dice.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")


func before_each() -> void:
	D20.loot_scale = 1.0   # the doc's own dice; the game's loot scale has its own tests


func after_each() -> void:
	D20.permadeath = Data.PERMADEATH
	D20.loot_scale = Data.LOOT_SCALE


func _scout(traits := [], scout_name := "Mara") -> Dictionary:
	return D20.new_scout(scout_name, traits)


## One check with these dice and nothing else: the result dictionary.
func _check(d20: int, traits: Array, check: String, dc: int, situational := 0) -> Dictionary:
	return D20.roll_check(ForcedDice.new([d20]), _scout(traits), check, dc, situational)


# ---------------------------------------------------------------- the design doc's test table

func test_doc_case_1_a_natural_20_always_wins() -> void:
	assert_eq(_check(20, [], "combat", 17, -5).tier, "CRITICAL_SUCCESS")


func test_doc_case_2_a_natural_1_always_fails() -> void:
	assert_eq(_check(1, [], "combat", 8, 5).tier, "CRITICAL_FAILURE")


func test_doc_cases_3_to_7_the_margins() -> void:
	assert_eq(_check(5, [], "combat", 11).tier, "CRITICAL_FAILURE", "margin -6")
	assert_eq(_check(6, [], "combat", 11).tier, "FAILURE", "margin -5")
	assert_eq(_check(10, [], "combat", 11, 2).tier, "SUCCESS", "margin +1")
	assert_eq(_check(16, [], "combat", 11).tier, "SUCCESS", "margin +5")
	assert_eq(_check(17, [], "combat", 11).tier, "CRITICAL_SUCCESS", "margin +6")


func test_doc_case_8_the_modifier_clamps_to_plus_5() -> void:
	var r := _check(10, [], "combat", 11, 8)
	assert_eq(r.mod, 5)
	assert_eq(r.total, 15)
	assert_eq(r.tier, "SUCCESS")


func test_doc_case_9_sharp_eyed_softens_a_natural_1_on_a_trap() -> void:
	var r := _check(1, ["sharp_eyed"], "trap", 11)
	assert_eq(r.mod, 4, "scavenge +2 and trap +2")
	assert_eq(r.raw, "CRITICAL_FAILURE")
	assert_eq(r.tier, "FAILURE")
	assert_true(r.shifted)


func test_doc_case_10_a_veteran_softens_a_critical_failure_in_combat() -> void:
	var r := _check(1, ["veteran"], "combat", 11)
	assert_eq(r.mod, 2)
	assert_eq(r.tier, "FAILURE")


func test_doc_case_11_a_cowardly_scout_gets_no_shift_and_the_injury() -> void:
	var fight := D20.resolve_combat(ForcedDice.new([6]), _scout(["cowardly"]), 11)
	assert_eq(fight.check.mod, -3)
	assert_eq(fight.tier, "CRITICAL_FAILURE", "margin -8, nothing softens it")
	assert_eq(fight.injury, "severe")


func test_doc_case_12_a_cowardly_failure_flees_clean() -> void:
	var fight := D20.resolve_combat(ForcedDice.new([9]), _scout(["cowardly"]), 11)
	assert_eq(fight.tier, "FAILURE", "margin -5")
	assert_has(fight.check.flags, "no_injury")
	assert_eq(fight.injury, "none")


func test_doc_event_table_boundaries() -> void:
	assert_eq(D20.event_for_roll(3), "ambush")
	assert_eq(D20.event_for_roll(4), "trap")
	assert_eq(D20.event_for_roll(11), "cache")
	assert_eq(D20.event_for_roll(12), "minor_find")
	assert_eq(D20.event_for_roll(20), "nothing")


func test_doc_loot_case_magpie_turns_8_gold_into_12() -> void:
	# resource d20 15 is gold; the cache check d20 11 plus Magpie's +1 is 12 against 11, a SUCCESS: a medium package
	var out := D20.resolve_cache(ForcedDice.new([15, 11], [8]), _scout(["magpie"]), 11, 11)
	assert_eq(out.tier, "SUCCESS")
	assert_eq(out.packages[0].size, "medium")
	assert_eq(out.loot, {"gold": 12})


func test_doc_a_cache_critical_failure_triggers_one_ambush_check_at_minus_2() -> void:
	var dice := ForcedDice.new([10, 1, 15])   # resource, the cache check (a natural 1), then the ambush check
	var out := D20.resolve_cache(dice, _scout(), 11, 11)
	assert_eq(out.tier, "CRITICAL_FAILURE")
	assert_eq(out.loot, {}, "a ruined cache pays nothing")
	assert_eq(out.steps.size(), 1)
	assert_eq(out.steps[0].kind, "ambush")
	assert_eq(out.steps[0].check.mod, -2)
	assert_eq(dice.d20_calls, 3)


# ---------------------------------------------------------------- the core mechanic

func test_the_tiers_split_25_25_30_20_at_dc_11() -> void:
	var counts := {"CRITICAL_FAILURE": 0, "FAILURE": 0, "SUCCESS": 0, "CRITICAL_SUCCESS": 0}
	for roll in range(1, 21):
		counts[D20.tier_from_roll(roll, 0, 11)] += 1
	assert_eq(counts, {"CRITICAL_FAILURE": 5, "FAILURE": 5, "SUCCESS": 6, "CRITICAL_SUCCESS": 4})


func test_each_plus_1_moves_5_percent_toward_success() -> void:
	var wins := func(mod: int) -> int:
		var n := 0
		for roll in range(1, 21):
			if D20.tier_from_roll(roll, mod, 11) in ["SUCCESS", "CRITICAL_SUCCESS"]:
				n += 1
		return n
	assert_eq(wins.call(1), wins.call(0) + 1)
	assert_eq(wins.call(2), wins.call(0) + 2)


func test_a_natural_1_or_20_beats_any_modifier() -> void:
	for mod in [-5, 0, 5]:
		assert_eq(D20.tier_from_roll(1, mod, 8), "CRITICAL_FAILURE")
		assert_eq(D20.tier_from_roll(20, mod, 17), "CRITICAL_SUCCESS")


func test_modifiers_clamp_to_plus_or_minus_5() -> void:
	assert_eq(D20.clamp_mod(9), 5)
	assert_eq(D20.clamp_mod(-9), -5)
	assert_eq(D20.clamp_mod(3), 3)
	# trigger-happy (+2 combat) and veteran (+2) with a +3 situational bonus would be +7
	assert_eq(_check(10, ["trigger_happy", "veteran"], "combat", 11, 3).mod, 5)


func test_each_kind_of_check_adds_the_right_modifiers() -> void:
	var s := _scout(["sharp_eyed", "light_footed"])
	assert_eq(D20.mod_for(s, "combat"), -1)
	assert_eq(D20.mod_for(s, "ambush"), 2 + 0 + 1 + 3, "scavenge and ambush")
	assert_eq(D20.mod_for(s, "trap"), 2 + 2 + 1 + 0, "scavenge and trap")
	assert_eq(D20.mod_for(s, "cache"), 2 + 1, "scavenge only")


func test_a_tier_shift_moves_a_result_one_tier_once() -> void:
	var s := _scout(["sharp_eyed", "veteran"])
	assert_eq(D20.apply_tier_shifts(s, "trap", "CRITICAL_FAILURE"), {"tier": "FAILURE", "shifted": true})
	assert_eq(D20.apply_tier_shifts(s, "trap", "FAILURE"), {"tier": "FAILURE", "shifted": false}, "only the one tier is softened")
	assert_eq(D20.apply_tier_shifts(s, "cache", "CRITICAL_FAILURE"), {"tier": "CRITICAL_FAILURE", "shifted": false}, "not on a cache")


func test_lucky_rerolls_a_failure_once_and_keeps_the_new_roll() -> void:
	var s := _scout(["lucky"])
	assert_eq(s.rerolls, 1)
	var r := D20.roll_check(ForcedDice.new([3, 15]), s, "combat", 11)
	assert_true(r.rerolled)
	assert_eq(r.d20, 15)
	assert_eq(r.tier, "SUCCESS")
	assert_eq(s.rerolls, 0)
	assert_has(r.log, "rerolled from 3")
	var again := D20.roll_check(ForcedDice.new([3]), s, "combat", 11)
	assert_false(again.rerolled, "the charge is spent")
	assert_eq(again.tier, "CRITICAL_FAILURE")


func test_lucky_keeps_a_worse_second_roll_and_ignores_successes() -> void:
	var s := _scout(["lucky"])
	assert_eq(D20.roll_check(ForcedDice.new([14]), s, "combat", 11).tier, "SUCCESS")
	assert_eq(s.rerolls, 1, "nothing spent on a success")
	var r := D20.roll_check(ForcedDice.new([8, 1]), s, "combat", 11)
	assert_eq(r.tier, "CRITICAL_FAILURE", "the new roll stands, good or bad")
	var held := _scout(["lucky"])
	assert_false(D20.roll_check(ForcedDice.new([3]), held, "combat", 11, 0, false).rerolled, "the player can decline")
	assert_eq(held.rerolls, 1)


func test_the_log_line_reads_like_the_design_doc() -> void:
	var r := _check(8, ["sharp_eyed"], "trap", 11)
	assert_eq(r.log, "Mara (Sharp-Eyed) trap: d20 8 +4 = 12 vs DC 11 -> SUCCESS")
	assert_eq(_check(1, ["sharp_eyed"], "trap", 11).log, "Mara (Sharp-Eyed) trap: d20 1 +4 = 5 vs DC 11 -> FAILURE (raw CRITICAL_FAILURE)")
	assert_eq(_check(12, [], "combat", 11, -2).log, "Mara combat: d20 12 -2 = 10 vs DC 11 -> FAILURE")


# ---------------------------------------------------------------- loot

func test_loot_multipliers_multiply_and_cap_at_x2() -> void:
	assert_eq(D20.loot_multiplier(_scout(["magpie"]), "gold"), 1.5)
	assert_eq(D20.loot_multiplier(_scout(["magpie"]), "fuel"), 1.0)
	assert_almost_eq(D20.loot_multiplier(_scout(["paranoid"]), "veg"), 0.85, 0.0001)
	assert_almost_eq(D20.loot_multiplier(_scout(["magpie", "paranoid"]), "gold"), 1.275, 0.0001)
	assert_eq(D20.loot_multiplier(_scout(["gearhead", "gearhead"]), "fuel"), 2.0, "2.25 is capped")


func test_packages_round_to_the_nearest_unit_and_never_pay_nothing() -> void:
	var rolled := D20.roll_package(ForcedDice.new([], [3]), _scout(["magpie"]), "small", "gold")
	assert_eq(rolled.amount, 5, "3 x 1.5 = 4.5 rounds up")
	assert_eq(D20.roll_package(ForcedDice.new([], [0]), _scout(), "small", "fuel").amount, 1)


func test_packages_grow_with_their_size() -> void:
	assert_eq(Data.PACKAGES["small"]["fuel"], "1d4")
	assert_eq(Data.PACKAGES["medium"]["gold"], "2d6")
	assert_eq(Data.PACKAGES["large"]["veg"], "4d6")


func test_trigger_happy_wins_pay_a_size_larger_on_a_critical_success_only() -> void:
	var s := _scout(["trigger_happy"])
	assert_eq(D20.size_shifted(s, "combat", "CRITICAL_SUCCESS", "medium"), "large")
	assert_eq(D20.size_shifted(s, "combat", "CRITICAL_SUCCESS", "large"), "large", "never past large")
	assert_eq(D20.size_shifted(s, "combat", "SUCCESS", "small"), "small")
	assert_eq(D20.size_shifted(s, "trap", "CRITICAL_SUCCESS", "small"), "small")
	var fight := D20.resolve_combat(ForcedDice.new([20, 10], [9]), s, 11)
	assert_eq(fight.packages[0].size, "large")


func test_lost_loot_is_a_share_of_each_resource_rounded_down() -> void:
	var r := D20.lose_share({"fuel": 10, "gold": 7, "veg": 3}, 0.25)
	assert_eq(r.lost, {"fuel": 2, "gold": 1})
	assert_eq(r.kept, {"fuel": 8, "gold": 6, "veg": 3})


# ---------------------------------------------------------------- combat

func test_a_fight_at_each_tier() -> void:
	var carried := {"fuel": 10, "gold": 7}
	var crit_fail := D20.resolve_combat(ForcedDice.new([1]), _scout(), 11, 0, carried)
	assert_eq([crit_fail.injury, crit_fail.lost], ["severe", {"fuel": 5, "gold": 3}])
	assert_eq(crit_fail.loot, {})
	var fail := D20.resolve_combat(ForcedDice.new([8]), _scout(), 11, 0, carried)
	assert_eq([fail.injury, fail.lost], ["light", {"fuel": 2, "gold": 1}])
	var win := D20.resolve_combat(ForcedDice.new([12, 10], [3]), _scout(), 11, 0, carried)
	assert_eq([win.tier, win.injury, win.lost], ["SUCCESS", "none", {}])
	assert_eq(win.loot, {"fuel": 3})
	assert_eq(win.packages[0].size, "small")
	assert_false(win.camp_revealed)
	var rout := D20.resolve_combat(ForcedDice.new([18, 17], [9]), _scout(), 11)
	assert_eq(rout.packages[0].size, "medium")
	assert_eq(rout.loot, {"gold": 9})
	assert_true(rout.camp_revealed, "the enemy camp is marked on the map")


func test_permadeath_is_on_and_a_fumble_in_a_hard_fight_can_kill_the_whole_party() -> void:
	assert_true(D20.permadeath)
	var dead := D20.resolve_combat(ForcedDice.new([1, 5]), _scout(), 14)
	assert_true(dead.wiped, "a fumble of 5 or less kills the party")
	assert_true(dead.died)
	assert_has(dead.log, "The whole party is dead.")
	var lives := D20.resolve_combat(ForcedDice.new([1, 6]), _scout(), 14)
	assert_false(lives.wiped)
	assert_eq(lives.injury, "severe", "a 6 or more is only the severe injury")
	var easy := ForcedDice.new([1])
	assert_false(D20.resolve_combat(easy, _scout(), 11).wiped)
	assert_eq(easy.d20_calls, 1, "no fumble roll against an enemy below DC 14")
	var softened := ForcedDice.new([1])
	assert_false(D20.resolve_combat(softened, _scout(["veteran"]), 14).wiped, "a Veteran's CRITICAL_FAILURE is a FAILURE")
	assert_eq(softened.d20_calls, 1)


func test_with_permadeath_off_nobody_dies() -> void:
	D20.permadeath = false
	var off := ForcedDice.new([1])
	assert_false(D20.resolve_combat(off, _scout(), 17).died)
	assert_eq(off.d20_calls, 1, "no fumble roll when it's off")


# ---------------------------------------------------------------- traps

func test_a_trap_at_each_tier() -> void:
	var carried := {"fuel": 8}
	var boom := D20.resolve_trap(ForcedDice.new([1]), _scout(), 11, carried)
	assert_eq([boom.injury, boom.lost], ["severe", {"fuel": 2}])
	var caught := D20.resolve_trap(ForcedDice.new([8]), _scout(), 11, carried)
	assert_eq([caught.injury, caught.lost], ["light", {}])
	var spotted := D20.resolve_trap(ForcedDice.new([13]), _scout(), 11)
	assert_eq([spotted.injury, spotted.loot], ["none", {}])
	var stripped := D20.resolve_trap(ForcedDice.new([19, 12], [3]), _scout(), 11)
	assert_eq(stripped.loot, {"fuel": 3}, "a small package of the rolled resource")


func test_a_clumsy_scout_caught_by_a_trap_is_badly_hurt() -> void:
	var out := D20.resolve_trap(ForcedDice.new([10]), _scout(["clumsy"]), 11)
	assert_eq(out.tier, "FAILURE")
	assert_eq(out.injury, "severe")


# ---------------------------------------------------------------- ambushes

func test_a_failed_ambush_check_forces_a_fight_at_minus_2() -> void:
	# the ambush check is 6 (a FAILURE), the fight 13 at -2 = 11 (a win), then the enemy loot: fuel (10), 3 of it
	var out := D20.resolve_ambush(ForcedDice.new([6, 13, 10], [3]), _scout(), 11, 11)
	assert_eq(out.tier, "FAILURE")
	assert_eq(out.steps.size(), 1)
	assert_eq(out.steps[0].check.mod, -2)
	assert_eq(out.steps[0].tier, "SUCCESS", "the scout wins the fight anyway: 13 - 2 = 11")
	assert_eq(out.loot, {"fuel": 3})


func test_walking_into_an_ambush_costs_a_quarter_of_the_carried_loot_first() -> void:
	# a natural 1 on the ambush check, then a fight of 12 at -4 = 8 against 11: a FAILURE
	var out := D20.resolve_ambush(ForcedDice.new([1, 12]), _scout(), 11, 11, {"gold": 8})
	assert_eq(out.tier, "CRITICAL_FAILURE")
	assert_eq(out.steps[0].check.mod, -4)
	assert_eq(out.steps[0].tier, "FAILURE")
	assert_eq(out.lost["gold"], 2 + 1, "a quarter before the fight (2 of 8), then a quarter of the 6 left (1) for the lost fight")
	var worse := D20.resolve_ambush(ForcedDice.new([1, 8]), _scout(), 11, 11, {"gold": 8})
	assert_eq(worse.steps[0].tier, "CRITICAL_FAILURE", "8 at -4 is margin -7")
	assert_eq(worse.lost["gold"], 2 + 3, "a quarter, then half of the 6 left")


func test_spotting_an_ambush_lets_the_scout_choose() -> void:
	var asked := D20.resolve_ambush(ForcedDice.new([13]), _scout(), 11, 11)
	assert_eq(asked.tier, "SUCCESS")
	assert_true(asked.choice)
	assert_eq(asked.steps, [], "no fight is rolled until they choose")
	var slipped := D20.resolve_ambush(ForcedDice.new([13]), _scout(), 11, 11, {"gold": 8}, 0, "slip")
	assert_eq([slipped.steps, slipped.lost], [[], {}], "slipping away costs nothing")
	var fought := D20.resolve_ambush(ForcedDice.new([13, 12, 10], [2]), _scout(), 11, 11, {}, 0, "fight")
	assert_eq(fought.steps[0].check.mod, 0, "a fight at +0")
	assert_eq(fought.loot, {"fuel": 2})


func test_springing_a_counter_ambush_pays_a_bonus_package_on_a_win() -> void:
	# ambush check 20, then a combat check of 15 at +3, then the enemy loot (metal) and the bonus (gold)
	var out := D20.resolve_ambush(ForcedDice.new([20, 15, 4, 17], [2, 5]), _scout(), 11, 11)
	assert_eq(out.tier, "CRITICAL_SUCCESS")
	assert_eq(out.steps[0].check.mod, 3)
	assert_eq(out.packages.size(), 2)
	assert_eq(out.loot, {"metal": 2, "gold": 5})


# ---------------------------------------------------------------- caches

func test_a_cache_at_each_tier() -> void:
	var weak := D20.resolve_cache(ForcedDice.new([10, 8], [3]), _scout(), 11, 11)
	assert_eq([weak.tier, weak.packages[0].size, weak.loot], ["FAILURE", "small", {"fuel": 3}])
	var good := D20.resolve_cache(ForcedDice.new([10, 12], [6]), _scout(), 11, 11)
	assert_eq([good.tier, good.packages[0].size, good.loot], ["SUCCESS", "medium", {"fuel": 6}])


func test_a_critical_success_cache_adds_a_small_package_of_a_different_resource() -> void:
	# the cache holds metal (5); the extra resource rolls metal again (3), so it rerolls to fuel (12)
	var out := D20.resolve_cache(ForcedDice.new([5, 20, 3, 12], [14, 2]), _scout(), 11, 11)
	assert_eq(out.tier, "CRITICAL_SUCCESS")
	assert_eq(out.packages[0].size, "large")
	assert_eq(out.packages[1].size, "small")
	assert_eq(out.loot, {"metal": 14, "fuel": 2})


# ---------------------------------------------------------------- a whole visit

func test_a_visit_rolls_the_event_first() -> void:
	var nothing := D20.scavenge_site(ForcedDice.new([20]), _scout(), 11, 11)
	assert_eq([nothing.event, nothing.loot, nothing.injury], ["nothing", {}, "none"])
	var find := D20.scavenge_site(ForcedDice.new([12, 10], [2]), _scout(), 11, 11)
	assert_eq([find.event, find.loot], ["minor_find", {"fuel": 2}])
	var trap := D20.scavenge_site(ForcedDice.new([5, 1]), _scout(), 11, 11)
	assert_eq([trap.event, trap.tier, trap.injury], ["trap", "CRITICAL_FAILURE", "severe"])
	var cache := D20.scavenge_site(ForcedDice.new([8, 15, 14], [4]), _scout(), 11, 11)
	assert_eq([cache.event, cache.tier, cache.loot], ["cache", "SUCCESS", {"gold": 4}])
	var fight := D20.scavenge_site(ForcedDice.new([2, 6, 13, 10], [3]), _scout(), 11, 11)
	assert_eq([fight.event, fight.tier, fight.steps[0].tier, fight.loot], ["ambush", "FAILURE", "SUCCESS", {"fuel": 3}])


func test_a_visit_logs_every_roll_and_reports_what_is_left_of_the_load() -> void:
	var out := D20.scavenge_site(ForcedDice.new([5, 1]), _scout(), 11, 11, {"fuel": 8})
	assert_eq(out.log[0], "Mara scavenges: d20 5 -> trap")
	assert_true(out.log.any(func(l): return l.contains("trap: d20 1")))
	assert_eq(out.carried, {"fuel": 6}, "a quarter was destroyed")


# ---------------------------------------------------------------- the data and the dice

func test_the_event_and_resource_tables_cover_every_roll_once() -> void:
	for table in [Data.EVENT_TABLE, Data.RESOURCE_TABLE]:
		var seen := {}
		for row in table:
			for roll in range(row.min, row.max + 1):
				assert_false(seen.has(roll), "roll %d is listed twice" % roll)
				seen[roll] = true
		assert_eq(seen.size(), 20)
		assert_eq(seen.keys().min(), 1)
		assert_eq(seen.keys().max(), 20)


func test_the_event_odds_are_15_15_25_25_20() -> void:
	var counts := {}
	for roll in range(1, 21):
		var e := D20.event_for_roll(roll)
		counts[e] = counts.get(e, 0) + 1
	assert_eq(counts, {"ambush": 3, "trap": 3, "cache": 5, "minor_find": 5, "nothing": 4})


func test_the_resource_odds_are_40_20_25_15() -> void:
	var counts := {}
	for roll in range(1, 21):
		var r := D20.resource_for_roll(roll)
		counts[r] = counts.get(r, 0) + 1
	assert_eq(counts, {"metal": 8, "fuel": 4, "gold": 5, "veg": 3})


func test_every_trait_is_complete_and_every_package_exists() -> void:
	for id in Data.TRAITS:
		var t: Dictionary = Data.TRAITS[id]
		assert_true(t.has("name"), id)
		for kind in ["combat", "scavenge", "ambush", "trap"]:
			assert_true(t.mods.has(kind), "%s needs a %s modifier" % [id, kind])
		for shift in t.get("tier_shifts", []):
			assert_has(Data.TIERS, shift["from"])
			assert_has(Data.TIERS, shift["to"])
			assert_true(Data.CHECK_MODS.has(shift["check"]))
	for size in Data.SIZES:
		for resource in ["metal", "fuel", "gold", "veg"]:
			assert_gt(Dice.parse(Data.PACKAGES[size][resource]).x, 0, "%s %s" % [size, resource])
	assert_eq(Data.TRAITS.size(), 11)
	assert_eq(Data.TIERS, ["CRITICAL_FAILURE", "FAILURE", "SUCCESS", "CRITICAL_SUCCESS"])


func test_dice_strings_parse() -> void:
	assert_eq(Dice.parse("2d6"), Vector2i(2, 6))
	assert_eq(Dice.parse("d20"), Vector2i(1, 20))
	assert_eq(Dice.parse("4D4"), Vector2i(4, 4))
	assert_eq(Dice.parse("six"), Vector2i.ZERO)
	assert_eq(Dice.parse("0d6"), Vector2i.ZERO)


func test_the_real_dice_stay_in_range_and_follow_the_games_seed() -> void:
	var dice := Dice.new()
	for i in 200:
		var n: int = dice.d20()
		assert_true(n >= 1 and n <= 20)
		var total: int = dice.roll("2d6")
		assert_true(total >= 2 and total <= 12)
	seed(11)
	var first := [dice.d20(), dice.roll("4d4")]
	seed(11)
	assert_eq([dice.d20(), dice.roll("4d4")], first)


func test_only_lucky_scouts_start_with_a_reroll() -> void:
	for id in Data.TRAITS:
		assert_eq(D20.new_scout("x", [id]).rerolls, 1 if id == "lucky" else 0, id)
