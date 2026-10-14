extends "res://tests/framework/test_case.gd"
## Nukes you can find: a glowing crater is searched once with one roll (a natural 1 sets the nuke off, a natural 20 disarms it, anything else is scrap or nothing), the
## missile silo pays 1 warhead on a Success and 2 or 3 on a Critical success, a nuke is a very heavy item that is loaded first, and warheads a party cannot carry stay in
## the silo for a later party. Every die is forced, except in the one test that counts the odds.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const Dice = preload("res://scripts/dice.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	D20.permadeath = D20Data.PERMADEATH
	hq = Game.home(Data.PLAYER)


func after_each() -> void:
	Units.dice = Dice.new()
	D20.permadeath = D20Data.PERMADEATH


func _party(traits := []) -> Array:
	var out := []
	for n in ["Mara", "Dex", "Odo"]:
		out.append({"name": n, "age": 30, "traits": traits.duplicate(), "injury": "none", "hunger": 0, "hp": 100.0, "dose": 0.0,
			"hurt": false, "face": 1, "sick": 0})
	return out


## A crater search by `party` (no radiation unless said), with these dice.
func _search(dice, party := [], radiation := 0.0) -> Dictionary:
	var people: Array = party if not party.is_empty() else _party()
	var visit := D20Visit.begin("crater", {"radiation": radiation, "party_strength": 3}, 1.0, dice, people)
	D20Visit.step(visit, dice, people)
	return visit


func _silo() -> Vector2i:
	var found := World.find_tile(func(c, t): return t["b"] == "poi_missile_silo")
	assert_ne(found, Vector2i(-1, -1), "every map has a silo")
	return Game.poi_anchor(found)


## A scavenger party of `mover` that has just reached `at`: it is at the site with a visit under way.
func _party_at(at: Vector2i, mover := "foot", dice = null) -> Dictionary:
	if dice != null:
		Units.dice = dice
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, mover, at, at)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = []
	Units.units.append(u)
	Units._begin_visit(u)
	return u


# ---------------------------------------------------------------- the crater roll

func test_the_crater_table_has_a_dc_and_all_four_outcomes() -> void:
	assert_eq(D20Data.CRATER.dc, 11)
	assert_gt(D20Data.CRATER.crit_margin, 20, "no margin is critical: only the naturals are")
	for tier in D20Data.TIERS:
		assert_ne(D20Data.CRATER.outcomes[tier].name, "", tier)


func test_a_crater_visit_is_one_search_check_with_a_leave_button() -> void:
	var party := _party()
	var visit := D20Visit.begin("crater", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new(), party)
	assert_eq(visit.stage, "crater")
	var view := D20Visit.pending(visit, party)
	assert_eq(view.check, "Crater search")
	assert_eq(view.dc, 11)
	assert_eq(view.mod, 0)
	assert_has(view.text, "natural 1")
	assert_has(view.text, "natural 20")
	assert_eq(view.buttons.map(func(b): return b.id), ["roll", "home"])


func test_the_radiation_of_a_crater_counts_against_the_roll() -> void:
	var party := _party()
	var visit := D20Visit.begin("crater", {"radiation": 100.0, "party_strength": 3}, 1.0, ForcedDice.new(), party)
	assert_eq(D20Visit.pending(visit, party).mod, -3, "100 R/h costs 3, as anywhere")


func test_leaving_leaves_the_crater_untouched() -> void:
	var party := _party()
	var dice := ForcedDice.new()
	var visit := D20Visit.begin("crater", {"radiation": 0.0, "party_strength": 3}, 1.0, dice, party)
	D20Visit.step(visit, dice, party, "home")
	assert_eq(visit.stage, "done")
	assert_eq(visit.outcome, "left")
	assert_false(visit.blast)
	assert_eq(D20Visit.pending(visit, party).buttons[0].label, "Head home")


func test_a_natural_1_sets_the_nuke_off_and_the_party_is_wiped_out() -> void:
	var visit := _search(ForcedDice.new([1]), _party(["light_footed"]))
	assert_true(visit.blast)
	assert_true(visit.wiped)
	assert_eq(visit.outcome, "wiped")
	assert_eq(visit.stage, "done")
	assert_true(visit.loot.is_empty())
	assert_eq(D20Visit._outcome_text(visit), "The nuke went off. Nobody in the party survived.")


func test_a_natural_20_disarms_it_even_for_a_clumsy_party_in_the_hot_zone() -> void:
	var visit := _search(ForcedDice.new([20]), _party(["clumsy"]), 100.0)
	assert_false(visit.blast)
	assert_eq(visit.loot, {"nuke": 1})
	assert_eq(visit.outcome, "looted")
	assert_has(D20Visit._outcome_text(visit), "1 nuke")


func test_between_the_naturals_the_total_decides_scrap_or_nothing() -> void:
	var nothing := _search(ForcedDice.new([10]))
	assert_true(nothing.loot.is_empty(), "10 is under the DC of 11")
	assert_eq(nothing.outcome, "empty")
	assert_eq(D20Visit._outcome_text(nothing), "Nothing but slag: the crater is picked clean.")
	var scrap := _search(ForcedDice.new([11], [4]))
	assert_eq(scrap.loot, {"metal": 4}, "11 meets it: a small package of metal")
	var edge := _search(ForcedDice.new([19], [2]))
	assert_eq(edge.loot, {"metal": 2}, "19 is still only scrap")
	var helped := _search(ForcedDice.new([10], [5]), _party(["light_footed"]))
	assert_eq(helped.loot, {"metal": 5}, "a +1 turns a 10 into scrap")


func test_a_bad_roll_is_not_a_blast_unless_it_is_a_natural_1() -> void:
	var visit := _search(ForcedDice.new([2]), _party(["clumsy"]), 100.0)   # -5 after the clamp: the usual margin would call this a critical failure
	assert_false(visit.blast)
	assert_true(visit.loot.is_empty())
	assert_eq(visit.outcome, "empty")


func test_a_sharp_eyed_survivor_spots_the_trigger() -> void:
	var visit := _search(ForcedDice.new([1]), _party(["sharp_eyed"]))
	assert_false(visit.blast, "Sharp-Eyed turns a critical failure on a trap-type roll into a plain failure")
	assert_false(visit.wiped)
	assert_eq(visit.outcome, "empty")


func test_lucky_rerolls_a_natural_1_once() -> void:
	var visit := _search(ForcedDice.new([1, 12], [3]), _party(["lucky"]))
	assert_false(visit.blast)
	assert_eq(visit.loot, {"metal": 3}, "the new roll of 12 is scrap")


func test_a_natural_1_and_a_natural_20_are_about_one_search_in_twenty_each() -> void:
	seed(4242)
	var dice := Dice.new()
	var blasts := 0
	var nukes := 0
	var scrap := 0
	var runs := 4000
	for i in runs:
		var party := _party()
		var visit := D20Visit.begin("crater", {"radiation": 0.0, "party_strength": 3}, 1.0, dice, party)
		D20Visit.step(visit, dice, party)
		if visit.blast:
			blasts += 1
		elif visit.loot.has("nuke"):
			nukes += 1
		elif visit.loot.has("metal"):
			scrap += 1
	assert_ge(blasts, 140, "about 200 of 4000")
	assert_le(blasts, 260)
	assert_ge(nukes, 140)
	assert_le(nukes, 260)
	assert_ge(scrap, 1650, "nine d20 faces in twenty at modifier 0: about 1800")
	assert_le(scrap, 1950)


# ---------------------------------------------------------------- the missile silo

func _silo_visit(d20s: Array, totals := []) -> Dictionary:
	var party := _party()
	var dice := ForcedDice.new(d20s, totals)
	var visit := D20Visit.begin("poi", {"radiation": 0.0, "party_strength": 6}, 1.0, dice, party, "missile_silo")
	D20Visit.step(visit, dice, party)
	assert_true(dice.d20_values.is_empty() and dice.totals.is_empty(), "every die was used")
	return visit


func test_a_success_at_the_silo_adds_one_warhead_to_the_fuel_store() -> void:
	var visit := _silo_visit([17], [10])
	assert_eq(visit.loot, {"fuel": 10, "nuke": 1})
	assert_eq(visit.outcome, "looted")


func test_a_critical_success_adds_two_or_three_warheads() -> void:
	assert_eq(_silo_visit([20, 12], [7]).loot, {"metal": 7, "nuke": 2}, "a second d20 of 12 or less: two")
	assert_eq(_silo_visit([20, 1], [7]).loot, {"metal": 7, "nuke": 2})
	assert_eq(_silo_visit([20, 13], [7]).loot, {"metal": 7, "nuke": 3}, "13 or more: three, the most there are")
	assert_eq(_silo_visit([20, 20], [7]).loot, {"metal": 7, "nuke": 3})
	assert_true(_silo_visit([20, 13], [7]).reveal_fort, "the targeting data is still there")


func test_a_failure_pays_no_warheads() -> void:
	assert_true(_silo_visit([16]).loot.is_empty(), "locked down")
	var fight := _silo_visit([1])
	assert_eq(fight.stage, "fight", "automated defenses are still a fight")
	assert_false(fight.loot.has("nuke"))


func test_the_silos_odds_of_warheads_by_modifier() -> void:
	# Counted over the 20 faces of the die: any warhead is a Success or a Critical success.
	var any := {0: 4, 3: 7, 5: 9}   # faces out of 20: 20% at 0, 35% at +3, 45% at +5
	for mod in any:
		var n := 0
		for d in range(1, 21):
			var tier := D20.tier_from_roll(d, mod, 17)
			if tier == D20Data.SUCCESS or tier == D20Data.CRITICAL_SUCCESS:
				n += 1
		assert_eq(n, any[mod], "modifier %+d" % mod)


# ---------------------------------------------------------------- weight

func _carrier(mover: String) -> Dictionary:
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, mover, hq, hq)
	u.crew = 3
	u.survivors = Units._make_crew(3)
	return u


func test_a_nuke_is_a_very_heavy_item() -> void:
	assert_has(Data.ITEMS, "nuke")
	assert_eq(Data.ITEM_WEIGHT.nuke, 50.0)
	assert_eq(Units.goods_weight({"nuke": 2}), 100.0)
	assert_eq(Game.cost_text({"nuke": 1}), "1 nuke")
	assert_eq(Game.cost_text({"nuke": 2}), "2 nukes")


func test_how_many_nukes_each_way_of_travel_can_pick_up() -> void:
	assert_eq(Units.fit_load(_carrier("foot"), {"nuke": 3}), {"nuke": 1}, "a party on foot lifts one")
	assert_eq(Units.fit_load(_carrier("horse"), {"nuke": 3}), {"nuke": 2}, "horses two")
	assert_eq(Units.fit_load(_carrier("car"), {"nuke": 3}), {"nuke": 3}, "a war rig all three")
	assert_true(Game.log_lines.any(func(l): return l.contains("can't carry it all") and l.contains("nukes")))


func test_how_much_longer_the_trip_home_takes_with_nukes_aboard() -> void:
	var foot := _carrier("foot")
	foot.carry = {"nuke": 1}
	assert_almost_eq(Units.load_slowdown(foot), 1.0 + (50.0 / 30.0 - 1.0), 0.0001, "1.7 times as long on foot")
	var horse := _carrier("horse")
	horse.carry = {"nuke": 1}
	assert_eq(Units.load_slowdown(horse), 1.0)
	horse.carry = {"nuke": 2}
	assert_almost_eq(Units.load_slowdown(horse), 2.0, 0.0001)
	var rig := _carrier("car")
	rig.carry = {"nuke": 3}
	assert_almost_eq(Units.load_slowdown(rig), 150.0 / 80.0, 0.0001, "1.9 times as long, but all three get home")


func test_nukes_are_loaded_first_and_the_rest_is_trimmed() -> void:
	var kept := Units.fit_load(_carrier("foot"), {"nuke": 1, "fuel": 45})
	assert_eq(kept.nuke, 1, "a big fuel package does not crowd the warhead out")
	assert_ge(kept.fuel, 4, "the 10 of room left holds about 5 fuel")
	assert_le(kept.fuel, 5)
	var fits := Units.fit_load(_carrier("car"), {"nuke": 1, "fuel": 20})
	assert_eq(fits, {"nuke": 1, "fuel": 20}, "all of it fits a war rig")


# ---------------------------------------------------------------- a visit to a crater and to the silo

func _crater() -> Vector2i:
	var found := World.find_tile(func(c, t): return t["t"] == "crater" and c.x > 4 and c.y > 4 and c.x < Game.w - 5 and c.y < Game.h - 5)
	assert_ne(found, Vector2i(-1, -1))
	return found


func test_a_party_at_a_crater_starts_a_crater_visit() -> void:
	var at := _crater()
	var u := _party_at(at)
	assert_eq(u.stage, "site")
	assert_eq(u.visit.ruin, "crater")
	assert_eq(u.visit.stage, "crater")
	assert_true(Game.log_lines.any(func(l): return l.contains("reached the crater")))


func test_a_blast_from_a_crater_search_goes_off_at_once_and_waits_for_the_die() -> void:
	var at := _crater()
	var u := _party_at(at, "foot", ForcedDice.new([1]))
	var other: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", at + Vector2i(1, 0), at)
	other.crew = 3
	other.survivors = Units._make_crew(3)
	Units.units.append(other)
	var shown := Units.visit_do(u.id, "roll")
	assert_eq(shown, 1)
	assert_true(u.visit.blast_done)
	assert_eq(Game.tile(at)["r"], "picked", "the crater is spent")
	assert_eq(Game.stats.blasts, 1)
	assert_false(Units.units.has(other), "the other party in the square died")
	assert_true(Units.units.has(u), "the party that rolled is finished off when its visit ends")
	assert_eq(Game.held_blasts, [at], "the explosion waits for the die to land")
	var seen := watch(Game, "blasted")
	Game.release_blasts()
	assert_eq(seen.count, 1)
	assert_eq(seen.emissions[0][0], at)
	var pop := Game.pop
	Units.visit_finish(u.id)
	assert_true(u.get("gone", false))
	assert_eq(u.crew, 0)
	assert_eq(Game.pop, pop, "nobody comes home")
	assert_true(Game.log_lines.any(func(l): return l.contains("wiped out at the crater")))


func test_a_disarmed_nuke_comes_home_into_the_stores() -> void:
	var at := _crater()
	var u := _party_at(at, "foot", ForcedDice.new([20]))
	Units.visit_do(u.id, "roll")
	assert_false(u.visit.get("blast", false))
	Units.visit_finish(u.id)
	assert_eq(u.carry, {"nuke": 1})
	assert_eq(Game.tile(at)["r"], "picked")
	assert_eq(Game.stats.nukes_found, 1)
	assert_eq(Game.stats.craters_searched, 1)
	Units._come_home(u)
	assert_eq(Game.items.nuke, 1, "an item, like the frog hides")
	assert_true(Game.log_lines.any(func(l): return l.contains("came home with 1 nuke")))


func test_a_searched_crater_is_picked_clean_whatever_came_of_it() -> void:
	var at := _crater()
	var u := _party_at(at, "foot", ForcedDice.new([10]))
	Units.visit_do(u.id, "roll")
	Units.visit_finish(u.id)
	assert_eq(Game.tile(at)["r"], "picked")
	var second := _party_at(at)
	assert_eq(second.stage, "back", "a second party turns round")
	assert_true(Game.log_lines.any(func(l): return l.contains("crater at") and l.contains("already picked clean")))


func test_a_party_that_leaves_without_searching_leaves_the_crater_unsearched() -> void:
	var at := _crater()
	var u := _party_at(at, "foot", ForcedDice.new())
	Units.visit_do(u.id, "home")
	Units.visit_finish(u.id)
	assert_ne(Game.tile(at)["r"], "picked")


func test_warheads_a_party_cannot_carry_stay_in_the_silo_for_a_later_party() -> void:
	var silo := _silo()
	var u := _party_at(silo, "foot", ForcedDice.new([20, 13], [7]))
	assert_eq(u.visit.ruin, "poi")
	Units.visit_do(u.id, "roll")
	assert_eq(u.visit.loot.nuke, 3)
	Units.visit_finish(u.id)
	assert_eq(u.carry.nuke, 1, "a party on foot lifts one")
	assert_eq(Game.silo_stock(silo), 2)
	for p in Game.poi_footprint(silo):
		assert_eq(Game.tile(p)["r"], "stock2", "all four tiles of the site say so")
	assert_true(Game.log_lines.any(func(l): return l.contains("2 unfired nukes stay in the silo")))
	# a war rig party comes for them: nothing to roll
	var rig := _party_at(silo, "car")
	assert_eq(rig.stage, "back", "it loads and turns for home at once")
	assert_eq(rig.carry.nuke, 2)
	assert_eq(Game.silo_stock(silo), 0)
	for p in Game.poi_footprint(silo):
		assert_eq(Game.tile(p)["r"], "picked", "and then it really is picked clean")
	assert_false(rig.has("visit"), "no visit, no roll")
	var third := _party_at(silo)
	assert_eq(third.stage, "back")
	assert_true(third.carry.is_empty())


func test_a_party_that_cannot_lift_one_leaves_the_stock_where_it_is() -> void:
	var silo := _silo()
	Game.set_silo_stock(silo, 2)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", silo, silo)
	u.home = hq
	u.crew = 1   # one person lifts 10, and no more than 20: not even half a nuke
	u.survivors = Units._make_crew(1)
	Units.units.append(u)
	Units._begin_visit(u)
	assert_eq(Game.silo_stock(silo), 2)
	assert_eq(u.stage, "back")
	assert_true(Game.log_lines.any(func(l): return l.contains("could not lift a nuke")))


func test_a_silo_that_pays_a_nuke_to_a_foot_party_leaves_nothing_behind() -> void:
	var silo := _silo()
	var u := _party_at(silo, "foot", ForcedDice.new([17], [4]))
	Units.visit_do(u.id, "roll")
	Units.visit_finish(u.id)
	assert_eq(u.carry.nuke, 1)
	assert_eq(Game.silo_stock(silo), 0)
	assert_eq(Game.tile(silo)["r"], "picked")
