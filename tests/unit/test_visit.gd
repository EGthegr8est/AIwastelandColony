extends "res://tests/framework/test_case.gd"
## A visit to a ruin as a series of rolls (scripts/d20_visit.gd) and how the game runs one (Units.visit_*): the
## party's traits combine (and a trait two of them share counts once), the best-conditioned survivor rolls, a
## safe/trapped/rogue ruin starts differently, searching deeper, fatal fumbles, and saving mid-visit. Every die is forced.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var ruin: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	ruin = hq + Vector2i(1, -2)   # the ruin every camp starts beside
	D20.loot_scale = D20Data.LOOT_SCALE


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	D20.loot_scale = D20Data.LOOT_SCALE


## A survivor as the game makes one, with these traits.
func _survivor(survivor_name: String, traits := []) -> Dictionary:
	return {"name": survivor_name, "age": 30, "traits": traits.duplicate(), "injury": "none", "hunger": 0, "hp": 100.0,
		"dose": 0.0, "hurt": false, "face": 1, "sick": 0}


func _party(trait_lists := [[]]) -> Array:
	var names := ["Mara", "Dex", "Odo"]
	var out := []
	for i in trait_lists.size():
		out.append(_survivor(names[i], trait_lists[i]))
	return out


## A visit with the doc's own loot scale (1), so package totals are the dice's.
func _start(state: String, party: Array, dice, radiation := 0.0, strength := 3) -> Dictionary:
	return D20Visit.begin(state, {"radiation": radiation, "party_strength": strength}, 1.0, dice, party)


# ---------------------------------------------------------------- the party's traits combine

func test_a_partys_traits_combine_and_a_shared_trait_counts_once() -> void:
	var party := _party([["sharp_eyed"], ["sharp_eyed", "magpie"], ["lucky"]])
	assert_eq(D20.party_traits(party), ["sharp_eyed", "magpie", "lucky"])
	var scout := D20.party_scout(party, party[0])
	assert_eq(D20.mod_for(scout, "cache"), 3, "Sharp-Eyed +2 and Magpie +1, the second Sharp-Eyed adds nothing")
	var magpies := _party([["magpie"], ["magpie"], ["magpie"]])
	assert_eq(D20.mod_for(D20.party_scout(magpies, magpies[0]), "cache"), 1, "three Magpies are worth one")
	assert_eq(D20.loot_multiplier(D20.party_scout(magpies, magpies[0]), "gold"), 1.5, "and their loot bonus is not tripled")


func test_lucky_gives_the_party_one_reroll_however_many_are_lucky() -> void:
	assert_eq(D20.party_rerolls(_party([["lucky"], ["lucky"], []])), 1)
	assert_eq(D20.party_rerolls(_party([[], [], []])), 0)
	var party := _party([["lucky"], ["lucky"]])
	var visit := _start("safe", party, ForcedDice.new())
	assert_eq(visit.rerolls, 1)
	# the cache check fails (3), is rerolled (15, a SUCCESS) and the charge is gone for everyone
	visit["stage"] = "cache"
	visit["resource"] = "fuel"
	D20Visit.step(visit, ForcedDice.new([3, 15], [5]), party)
	assert_eq(visit.rerolls, 0)
	assert_eq(visit.loot, {"fuel": 5}, "the reroll made it a SUCCESS")


func test_the_panel_shows_the_combined_modifier_and_who_rolls() -> void:
	var party := _party([["sharp_eyed"], ["magpie"], []])
	var visit := _start("trapped", party, ForcedDice.new())
	var view := D20Visit.pending(visit, party)
	assert_eq(view.stage, "trap")
	assert_eq(view.check, "Trap check")
	assert_eq(view.dc, 14)
	assert_eq(view.mod, 2 + 2 + 1, "scavenge and trap from Sharp-Eyed, scavenge from Magpie")
	assert_eq(view.traits, "Sharp-Eyed, Magpie")
	assert_eq(view.who, "Mara", "everyone is fit, so the first rolls")
	assert_eq(view.buttons[0].id, "roll")


func test_the_survivor_in_the_best_condition_rolls() -> void:
	var party := _party([[], [], []])
	var ctx := {"radiation": 0.0, "party_strength": 3}
	party[0]["sick"] = 2
	assert_eq(D20Visit.pick_roller(party, "cache", ctx), 1, "Mara is radiation sick, so Dex rolls")
	party[1]["injury"] = "severe"
	assert_eq(D20Visit.pick_roller(party, "cache", ctx), 2, "someone badly hurt cannot roll")
	party[2]["injury"] = "severe"
	party[0]["injury"] = "severe"
	assert_eq(D20Visit.pick_roller(party, "cache", ctx), 1, "if everyone is badly hurt the least unwell rolls")


# ---------------------------------------------------------------- the situation

func test_the_situation_is_worked_out_from_the_game() -> void:
	var scout := {"name": "Mara", "traits": [], "sick": 1, "hunger": 2, "hurt": true, "injury": "light"}
	var ctx := {"radiation": 50.0, "party_strength": 3, "enemy_strength": 5}
	var parts := D20Visit.situation_parts(scout, ctx, "combat")
	var by_label := {}
	for p in parts:
		by_label[p.label] = p.value
	assert_eq(by_label["radiation (50 R/h)"], -2)
	assert_eq(by_label["ill"], -1)
	assert_eq(by_label["starving"], -2)
	assert_eq(by_label["hurt"], -1)
	assert_eq(by_label["light injury"], -1)
	assert_eq(by_label["outnumbered"], -2)
	assert_eq(D20Visit.parts_total(parts), -9)
	assert_eq(D20.clamp_mod(D20Visit.parts_total(parts)), -5, "the clamp still holds")
	var calm := D20Visit.situation_parts(scout, ctx, "cache")
	assert_false(calm.any(func(p): return p.label == "outnumbered"), "only a fight can outnumber you")


func test_radiation_bands_and_the_vehicle_shield() -> void:
	var scout := {"name": "Mara", "traits": []}
	for pair in [[19.0, 0], [20.0, -1], [44.0, -1], [45.0, -2], [79.0, -2], [80.0, -3], [150.0, -3]]:
		var parts := D20Visit.situation_parts(scout, {"radiation": pair[0]}, "cache")
		assert_eq(D20Visit.parts_total(parts), pair[1], "%d R/h" % pair[0])
	# a war rig halves what gets through: 60 R/h at the site is 30 for the crew
	Game.vehicles["car"] = 1
	var u := Units._make_unit("scav", Data.PLAYER, "car", ruin, ruin)
	Game.tile(ruin)["rad"] = 60
	assert_almost_eq(Units.visit_ctx(u).radiation, Game.radiation(ruin) * Data.MOVERS.car.shield, 0.0001)


func test_veteran_ignores_being_outnumbered_and_cowardly_doubles_it() -> void:
	var ctx := {"radiation": 0.0, "party_strength": 3, "enemy_strength": 5}
	assert_eq(D20Visit.parts_total(D20Visit.situation_parts({"traits": []}, ctx, "combat")), -2)
	assert_eq(D20Visit.parts_total(D20Visit.situation_parts({"traits": ["veteran"]}, ctx, "combat")), 0)
	assert_eq(D20Visit.parts_total(D20Visit.situation_parts({"traits": ["cowardly"]}, ctx, "combat")), -4)
	assert_eq(D20Visit.parts_total(D20Visit.situation_parts({"traits": ["veteran"]}, {"party_strength": 6, "enemy_strength": 5}, "combat")), 0)


func test_an_enemys_dc_comes_from_its_strength() -> void:
	assert_eq([D20Visit.enemy_dc(2), D20Visit.enemy_dc(3), D20Visit.enemy_dc(4), D20Visit.enemy_dc(5)], [10, 12, 14, 16])
	assert_eq(D20Visit.enemy_dc(1), 8, "never easier than Easy")
	assert_eq(D20Visit.enemy_dc(9), 17, "never harder than Deadly")
	assert_eq(D20Visit.enemy_strength(ForcedDice.new([], [3])), 4, "a 1d4 of 3 is strength 4")


# ---------------------------------------------------------------- a safe ruin

func test_a_safe_ruin_never_rolls_a_hazard() -> void:
	var party := _party()
	var visit := _start("safe", party, ForcedDice.new())
	var dice := ForcedDice.new([3, 4, 8])   # ambush row, trap row, then "nothing"
	D20Visit.step(visit, dice, party)
	assert_eq(dice.d20_calls, 3)
	assert_eq(visit.stage, "done")
	assert_eq(visit.outcome, "empty")
	assert_true(visit.last[0].contains("rerolled"))


func test_a_minor_find_pays_a_small_package_and_ends_the_visit() -> void:
	var party := _party()
	var visit := _start("safe", party, ForcedDice.new())
	D20Visit.step(visit, ForcedDice.new([14, 10], [3]), party)
	assert_eq(visit.loot, {"fuel": 3})
	assert_eq(visit.stage, "done")
	assert_eq(visit.outcome, "looted")


func test_a_cache_pays_by_its_check() -> void:
	var party := _party()
	var dice := ForcedDice.new([17, 10, 13], [6])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "cache")
	assert_eq(visit.resource, "fuel")
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot, {"fuel": 6}, "a SUCCESS is a medium package: 2d4")
	assert_eq(visit.stage, "done")
	assert_eq(visit.shown, 13, "the dice animation lands on the check's d20")


func test_the_loot_scale_multiplies_every_package() -> void:
	var party := _party()
	var dice := ForcedDice.new([14, 10], [3])
	var visit := D20Visit.begin("safe", {"radiation": 0.0, "party_strength": 3}, 3.0, dice, party)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot, {"fuel": 9})


# ---------------------------------------------------------------- searching deeper

func test_a_critical_cache_offers_a_deeper_search_that_pays_more() -> void:
	var party := _party()
	# event cache (17), the cache holds metal (5), check 20 (large 4d6 = 14), the extra resource rerolls metal (3)
	# to fuel (12) for a small 2, then deeper: it holds gold (15), the DC 14 check is 18 (SUCCESS, a large 15)
	var dice := ForcedDice.new([17, 5, 20, 3, 12, 15, 18], [14, 2, 15])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "deeper")
	assert_eq(visit.loot, {"metal": 14, "fuel": 2})
	var view := D20Visit.pending(visit, party)
	assert_has(view.text, "DC 14")
	assert_eq(view.buttons.map(func(b): return b.id), ["deeper", "home"])
	D20Visit.step(visit, dice, party, "deeper")
	assert_eq(visit.depth, 1)
	assert_eq(visit.stage, "cache")
	assert_eq(D20Visit.pending(visit, party).dc, 14)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot, {"metal": 14, "fuel": 2, "gold": 15})
	assert_eq(visit.stage, "done")


func test_heading_home_keeps_everything() -> void:
	var party := _party()
	var dice := ForcedDice.new([17, 5, 20, 3, 12], [14, 2])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party, "home")
	assert_eq(visit.stage, "done")
	assert_eq(visit.loot, {"metal": 14, "fuel": 2})


func test_a_collapse_on_a_deeper_search_loses_half_and_draws_enemies() -> void:
	var party := _party()
	# as above, then deeper: it holds gold (15) and the DC 14 check is a natural 1
	var dice := ForcedDice.new([17, 5, 20, 3, 12, 15, 1], [14, 2, 2])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party, "deeper")
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot, {"metal": 7, "fuel": 1}, "half of each found here is lost, rounded down")
	assert_eq(visit.stage, "ambush")
	assert_eq(visit.enemy, 3, "the noise brings strength 3 (a 1d4 of 2)")
	assert_eq(visit.ambush_sit, -2)


func test_you_can_only_go_deeper_twice() -> void:
	var party := _party()
	var dice := ForcedDice.new([17, 5, 20, 3, 12, 15, 20, 3, 12, 15, 20, 3, 12], [14, 2, 14, 2, 14, 2])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party, "deeper")
	D20Visit.step(visit, dice, party)   # a critical success again: DC 14
	assert_eq(visit.stage, "deeper")
	D20Visit.step(visit, dice, party, "deeper")
	assert_eq(visit.depth, 2)
	assert_eq(D20Visit.pending(visit, party).dc, 17, "11 + 3 + 3")
	D20Visit.step(visit, dice, party)   # a critical success at depth 2 has nowhere deeper to go
	assert_eq(visit.stage, "done")


# ---------------------------------------------------------------- a trapped ruin

func test_a_trapped_ruin_hurts_then_is_searched_like_a_safe_one() -> void:
	var party := _party()
	var dice := ForcedDice.new([1, 14, 10], [3])
	var visit := _start("trapped", party, dice)
	assert_eq(visit.stage, "trap")
	D20Visit.step(visit, dice, party)
	assert_eq(party[0].injury, "severe", "a natural 1 on the trap check")
	assert_eq(visit.injuries, {"Mara": "severe"})
	assert_eq(visit.stage, "event")
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot, {"fuel": 3}, "then the ruin pays like a safe one")


func test_a_clumsy_party_is_badly_hurt_by_a_trap_that_only_catches_them() -> void:
	var party := _party([["clumsy"]])
	var visit := _start("trapped", party, ForcedDice.new())
	D20Visit.step(visit, ForcedDice.new([10]), party)   # -4 total: 6 against 14 is a FAILURE
	assert_eq(party[0].injury, "severe")


# ---------------------------------------------------------------- a rogue-held ruin

func test_a_rogue_held_ruin_has_an_enemy_with_a_strength() -> void:
	var party := _party()
	var visit := _start("rogue", party, ForcedDice.new([], [3]))
	assert_eq(visit.enemy, 4)
	assert_eq(visit.stage, "ambush")


func test_a_won_fight_takes_a_prisoner_and_opens_the_ruin() -> void:
	var party := _party()
	# strength 4 (DC 14, and 3 against 4 is outnumbered); the ambush check is 10 (a FAILURE: a fight at -2); the
	# fight is a natural 20; the enemy's medium package is fuel (10), 5 of it
	var dice := ForcedDice.new([10, 20, 10], [3, 5])
	var visit := _start("rogue", party, dice)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "fight")
	assert_eq(visit.fight_sit, -2)
	var view := D20Visit.pending(visit, party)
	assert_eq(view.dc, 14)
	assert_eq(view.mod, -4, "-2 surprised and -2 outnumbered")
	D20Visit.step(visit, dice, party)
	assert_eq(visit.prisoners, 1)
	assert_true(visit.camp_revealed)
	assert_eq(visit.loot, {"fuel": 5})
	assert_eq(visit.stage, "event", "now the ruins are theirs to search")


func test_spotting_an_ambush_lets_you_slip_away_or_fight() -> void:
	var party := _party()
	var dice := ForcedDice.new([16], [3])   # 16 against 14 is a SUCCESS
	var visit := _start("rogue", party, dice)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "choice")
	assert_eq(D20Visit.pending(visit, party).buttons.map(func(b): return b.id), ["fight", "slip"])
	D20Visit.step(visit, dice, party, "slip")
	assert_eq(visit.stage, "done")
	assert_eq(visit.outcome, "slipped")
	assert_eq(visit.prisoners, 0)


func test_a_lost_fight_leaves_the_raider_in_charge() -> void:
	var party := _party()
	# a FAILURE on the ambush, then 8 at -4 (surprised and outnumbered) against 14 is a CRITICAL_FAILURE, so a fumble
	# roll of 15 follows, which the party survives
	var dice := ForcedDice.new([10, 8, 15], [3])
	var visit := _start("rogue", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.outcome, "lost_fight")
	assert_eq(visit.stage, "done")
	assert_false(visit.wiped)
	assert_eq(party[0].injury, "severe")


func test_a_fatal_fumble_can_wipe_out_the_party() -> void:
	var party := _party()
	var dice := ForcedDice.new([10, 1, 3], [3])   # a natural 1 in a DC 14 fight, then a fumble roll of 3
	var visit := _start("rogue", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	assert_true(visit.wiped)
	assert_eq(visit.outcome, "wiped")
	assert_eq(visit.stage, "done")
	assert_eq(D20Visit.pending(visit, party).buttons[0].label, "Continue")
	var spared := ForcedDice.new([10, 1, 9], [3])
	var other := _start("rogue", _party(), ForcedDice.new([], [3]))
	D20Visit.step(other, spared, _party())
	D20Visit.step(other, spared, _party())
	assert_false(other.wiped, "a fumble roll of 9 is survived")


func test_a_visit_with_a_noise_ambush_ends_after_the_fight() -> void:
	var party := _party()
	# a cache check of 1 ruins it; the noise brings strength 2 (DC 10); the ambush check is 15 (SUCCESS: choose);
	# the party fights and wins with a 15 (no loot after: the cache is gone, but the enemy pays a small fuel)
	var dice := ForcedDice.new([17, 10, 1, 15, 15, 10], [1, 4])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "ambush")
	assert_eq(visit.ambush_dc, 11)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "choice")
	D20Visit.step(visit, dice, party, "fight")
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "done", "no more searching after a ruined cache")
	assert_eq(visit.prisoners, 0, "the noise brought no rogue raider to capture")


# ---------------------------------------------------------------- saving a visit

func test_a_visit_survives_json_with_its_numbers_whole() -> void:
	var party := _party()
	var dice := ForcedDice.new([17, 5, 20, 3, 12], [14, 2])
	var visit := _start("safe", party, dice)
	D20Visit.step(visit, dice, party)
	D20Visit.step(visit, dice, party)
	var back: Dictionary = D20Visit.normalize(JSON.parse_string(JSON.stringify(visit)))
	for k in ["depth", "enemy", "site_dc", "hazard_dc", "prisoners", "shown", "rerolls"]:
		assert_eq(typeof(back[k]), TYPE_INT, k)
	for r in back.loot:
		assert_eq(typeof(back.loot[r]), TYPE_INT)
	assert_eq(back.loot, visit.loot)
	assert_eq(back.stage, "deeper")


# ---------------------------------------------------------------- the party at the ruins (Units)

## A scavenger party standing at the ruin beside the camp, ready to roll. Its survivors have these traits.
func _party_at_ruin(state := "safe", traits := [], dice = null) -> Dictionary:
	if dice != null:
		Units.dice = dice
	Game.tile(ruin)["r"] = state
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = traits.duplicate()
	Units.units.append(u)
	Units._begin_visit(u)
	return u


func test_a_party_that_arrives_stops_at_the_ruins_and_waits() -> void:
	Game.pop = 20
	Units.send("scav", "foot", ruin)
	var u: Dictionary = Units.units[-1]
	for i in 6:
		Units.season_turn()
		if u.stage == "site":
			break
	assert_eq(u.stage, "site")
	assert_true(u.has("visit"))
	assert_eq(Units.stage_text(u), "at the ruins")
	assert_true(Game.is_measured(ruin), "arriving takes a reading of the radiation")
	var pos: Vector2i = u.pos
	Units.season_turn()
	Units.season_turn()
	assert_eq(u.stage, "site", "it waits for the player")
	assert_eq(u.pos, pos)
	assert_has(Units.send_status("scav", "foot", ruin), "already heading there")


func test_rolling_a_safe_ruin_end_to_end() -> void:
	var u := _party_at_ruin("safe", [], ForcedDice.new([17, 10, 13], [6]))
	var view := Units.visit_view(u)
	assert_eq(view.stage, "event")
	assert_eq(Units.visit_do(u.id), 17, "the search rolled a 17: a cache")
	assert_eq(Units.visit_do(u.id), 13, "the cache check rolled a 13")
	assert_eq(Units.visit_view(u).stage, "done")
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station")
	assert_eq(u.carry, {"fuel": 18}, "6 fuel from the dice times the loot scale of 3")
	assert_eq(Game.tile(ruin)["r"], "picked")
	assert_false(u.has("visit"))
	assert_true(Game.log_lines.any(func(l): return l.contains("stripped the ruins")))


func test_you_can_only_finish_once_the_rolls_are_done() -> void:
	var u := _party_at_ruin("safe", [], ForcedDice.new())
	Units.visit_finish(u.id)
	assert_eq(u.stage, "site", "still rolling")
	assert_eq(Units.visit_do(9999), 0)


func test_leaving_without_searching_leaves_the_ruin_alone() -> void:
	var u := _party_at_ruin("safe", [], ForcedDice.new())
	Units.visit_do(u.id, "home")
	Units.visit_finish(u.id)
	assert_eq(u.stage, "station")
	assert_eq(Game.tile(ruin)["r"], "safe")
	assert_eq(u.carry, {})


func test_a_trapped_ruin_stays_marked_until_it_is_looted() -> void:
	var u := _party_at_ruin("trap", [], ForcedDice.new([13, 14, 10], [3]))
	assert_eq(Units.visit_view(u).stage, "trap")
	Units.visit_do(u.id)   # 13 against 14: a FAILURE, a light injury
	assert_eq(u.survivors[0].injury, "light")
	Units.visit_do(u.id)   # then the search
	Units.visit_finish(u.id)
	assert_eq(Game.tile(ruin)["r"], "picked")
	assert_eq(u.carry, {"fuel": 9})


func test_a_rogue_ruin_stays_rogue_held_after_a_slip_or_a_lost_fight() -> void:
	var u := _party_at_ruin("rogue", [], ForcedDice.new([16], [3]))
	Units.visit_do(u.id)
	Units.visit_do(u.id, "slip")
	Units.visit_finish(u.id)
	assert_eq(Game.tile(ruin)["r"], "rogue_seen")
	assert_eq(u.carry, {})
	var again := _party_at_ruin("rogue_seen", [], ForcedDice.new([10, 8, 15], [3]))
	Units.visit_do(again.id)
	Units.visit_do(again.id)
	Units.visit_finish(again.id)
	assert_eq(Game.tile(ruin)["r"], "rogue_seen")


func test_beating_a_rogue_takes_a_prisoner() -> void:
	var prisoners: int = Game.prisoners
	var u := _party_at_ruin("rogue", [], ForcedDice.new([10, 20, 10, 14, 10], [3, 5, 2]))
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	Units.visit_do(u.id)   # the ruins are open: a minor find
	Units.visit_finish(u.id)
	assert_eq(Game.prisoners, prisoners + 1)
	assert_eq(Game.tile(ruin)["r"], "picked")


func test_a_wiped_out_party_is_gone_for_good() -> void:
	var u := _party_at_ruin("rogue", [], ForcedDice.new([10, 1, 3], [3]))
	var pop: int = Game.pop
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	Units.visit_finish(u.id)
	assert_true(u.get("gone", false))
	assert_eq(u.crew, 0)
	assert_eq(Game.pop, pop, "nobody comes home")
	assert_true(Game.log_lines.any(func(l): return l.contains("wiped out")))


func test_a_picked_ruin_leaves_the_party_waiting_for_orders() -> void:
	Game.tile(ruin)["r"] = "picked"
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	Units.units.append(u)
	Units._begin_visit(u)
	assert_eq(u.stage, "station")
	assert_false(u.has("visit"))


func test_a_visit_in_progress_survives_saving() -> void:
	var u := _party_at_ruin("safe", ["magpie"], ForcedDice.new([17, 10], [6]))
	Units.visit_do(u.id)   # found a cache
	Game.save_game("visit_test")
	World.new_game(99)
	assert_true(Game.load_game("visit_test"))
	DirAccess.remove_absolute(Game._path("visit_test"))
	var loaded: Dictionary = Units.units[0]
	assert_eq(loaded.stage, "site")
	assert_eq(loaded.visit.stage, "cache")
	assert_eq(loaded.visit.resource, "fuel")
	assert_eq(typeof(loaded.visit.depth), TYPE_INT)
	assert_eq(loaded.survivors[0].traits, ["magpie"])
	assert_eq(Units.visit_view(loaded).stage, "cache", "the panel can still be built")


# ---------------------------------------------------------------- traits on survivors

func test_every_new_survivor_has_one_to_three_different_traits() -> void:
	var seen := {}
	for i in 60:
		for s in Units._make_crew(3):
			assert_true(s.traits.size() >= 1 and s.traits.size() <= 3)
			assert_eq(s.traits.size(), s.traits.duplicate().size())
			for id in s.traits:
				assert_true(D20Data.TRAITS.has(id))
				seen[id] = true
			var distinct := {}
			for id in s.traits:
				distinct[id] = true
			assert_eq(distinct.size(), s.traits.size(), "no repeats")
			assert_eq(s.injury, "none")
	assert_eq(seen.size(), D20Data.TRAITS.size(), "all 11 turn up")


func test_traits_show_in_a_survivors_line_and_are_saved() -> void:
	var u := _party_at_ruin("safe", ["sharp_eyed", "lucky"], ForcedDice.new())
	u.survivors[0]["name"] = "Mara"
	u.survivors[0]["age"] = 34
	assert_eq(Units.survivor_line(u.survivors[0]), "Mara, 34, Sharp-Eyed, Lucky (fed)")
	Game.save_game("trait_test")
	World.new_game(99)
	assert_true(Game.load_game("trait_test"))
	DirAccess.remove_absolute(Game._path("trait_test"))
	assert_eq(Units.units[0].survivors[0].traits, ["sharp_eyed", "lucky"])


func test_a_save_from_before_traits_still_loads() -> void:
	var u := _party_at_ruin("safe", [], ForcedDice.new())
	Game.save_game("old_trait_test")
	var path: String = Game._path("old_trait_test")
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	for s in data["units"]["units"][0]["survivors"]:
		s.erase("traits")
		s["trait"] = "tough"   # how an older save spelled its one word
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	World.new_game(99)
	assert_true(Game.load_game("old_trait_test"))
	DirAccess.remove_absolute(path)
	assert_eq(Units.units[0].survivors[0].traits, [])
	assert_eq(u.crew, Units.units[0].crew)


func test_food_found_at_the_ruins_goes_into_the_pack_and_the_log_still_says_so() -> void:
	var u := _party_at_ruin("safe", [], ForcedDice.new([17, 10, 13], [6]))
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	u.food = {"grain": 4}
	u.visit.loot = {"veg": 6, "fuel": 2}
	Units.visit_finish(u.id)
	assert_eq(u.food, {"grain": 4, "veg": 6}, "the vegetables feed the party")
	assert_eq(u.carry, {"fuel": 2}, "the fuel is hauled home")
	assert_true(Game.log_lines.any(func(l): return l.contains("stripped the ruins") and l.contains("6 veg")), "it is not reported as 'no loot'")
