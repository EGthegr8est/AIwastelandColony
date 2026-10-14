extends "res://tests/framework/test_case.gd"
## What a roll at each of the ten points of interest does (SITES in d20_data.gd): one check against the site's DC, the
## tier picks that site's outcome, and the outcome pays packages, hurts someone, poisons the party, forces a fight, or
## records a reward the game hands over when the party heads home. Every die is forced.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

const DCS := {
	"weather_station": 11, "water_tower": 11, "gas_station": 11, "cargo_yard": 11,
	"crashed_ship": 14, "chemical_dump": 14, "radio_tower": 14, "bunker": 14, "pumpjack": 14, "missile_silo": 17,
}


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	D20.permadeath = D20Data.PERMADEATH


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH


func _party() -> Array:
	var out := []
	for n in ["Mara", "Dex", "Odo"]:
		out.append({"name": n, "age": 30, "traits": [], "injury": "none", "hunger": 0, "hp": 100.0, "dose": 0.0,
			"hurt": false, "face": 1, "sick": 0})
	return out


## The d20 that lands exactly on a tier of a site's check for a party with no modifier.
func _roll_for(kind: String, tier: String) -> int:
	var dc: int = D20Data.SITES[kind].dc
	return {"CRITICAL_FAILURE": 1, "FAILURE": dc - 1, "SUCCESS": dc, "CRITICAL_SUCCESS": 20}[tier]


## A party of three at a site, strong enough that no fight outnumbers them. The loot scale is 1 so the dice are the totals.
func _visit(kind: String, party: Array, dice, scale := 1.0) -> Dictionary:
	return D20Visit.begin("poi", {"radiation": 0.0, "party_strength": 6}, scale, dice, party, kind)


## One visit to `kind` rolled to `tier`. `extra_d20` are the dice after the check's own, `totals` the package dice.
func _run(kind: String, tier: String, totals := [], extra_d20 := []) -> Dictionary:
	var party := _party()
	var d20s := [_roll_for(kind, tier)]
	d20s.append_array(extra_d20)
	var dice := ForcedDice.new(d20s, totals)
	var visit := _visit(kind, party, dice)
	D20Visit.step(visit, dice, party)
	assert_true(dice.d20_values.is_empty() and dice.totals.is_empty(), "%s %s used every die it was given" % [kind, tier])
	return {"visit": visit, "party": party}


# ---------------------------------------------------------------- the table

func test_every_site_has_its_dc_and_all_four_outcomes() -> void:
	assert_eq(D20Data.SITES.keys().size(), 10)
	for kind in DCS:
		assert_eq(D20Data.SITES[kind].dc, DCS[kind], kind)
		assert_has(Data.POIS, kind)
		for tier in D20Data.TIERS:
			var outcome: Dictionary = D20Data.SITES[kind].outcomes[tier]
			assert_ne(outcome.name, "", "%s %s has a name" % [kind, tier])
			assert_true(outcome["do"] is Array)


func test_a_site_visit_starts_at_the_site_check_with_its_dc() -> void:
	for kind in DCS:
		var visit := _visit(kind, _party(), ForcedDice.new())
		assert_eq(visit.stage, "site", kind)
		assert_eq(visit.poi, kind)
		assert_eq(visit.site_dc, DCS[kind])
	var plain := D20Visit.begin("safe", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new(), _party())
	assert_eq(plain.stage, "event", "an ordinary ruin is unchanged")


func test_the_panel_shows_the_site_check_a_leave_button_and_the_radiation() -> void:
	var party := _party()
	var visit := D20Visit.begin("poi", {"radiation": 50.0, "party_strength": 3}, 1.0, ForcedDice.new(), party, "bunker")
	var view := D20Visit.pending(visit, party)
	assert_eq(view.check, "Site check")
	assert_eq(view.dc, 14)
	assert_eq(view.mod, -2, "50 R/h costs 2")
	assert_eq(view.buttons.map(func(b): return b.id), ["roll", "home"])


func test_leaving_a_site_unsearched_does_not_use_it_up() -> void:
	var party := _party()
	var visit := _visit("bunker", party, ForcedDice.new())
	D20Visit.step(visit, ForcedDice.new(), party, "home")
	assert_eq(visit.stage, "done")
	assert_eq(visit.outcome, "left")
	assert_eq(visit.loot, {})


func test_a_sites_packages_use_the_loot_scale() -> void:
	var party := _party()
	var dice := ForcedDice.new([_roll_for("weather_station", "SUCCESS")], [2])
	var visit := _visit("weather_station", party, dice, 3.0 * Data.POI_LOOT_MULT)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot, {"metal": 9}, "a small metal of 2, times the scale of 3 and the site's 1.5")
	assert_eq(Data.POI_LOOT_MULT, 1.5)


# ---------------------------------------------------------------- the ten sites

func test_crashed_ship() -> void:
	var win := _run("crashed_ship", "SUCCESS", [7, 3])
	assert_eq(win.visit.loot, {"metal": 7, "fuel": 3})
	var crit := _run("crashed_ship", "CRITICAL_SUCCESS", [8])
	assert_eq(crit.visit.loot, {"metal": 8})
	assert_eq(crit.visit.reveal, 15)
	var miss := _run("crashed_ship", "FAILURE", [4])
	assert_eq(miss.visit.loot, {"metal": 4})
	assert_eq(miss.visit.injuries, {"Mara": "light"})
	var leak := _run("crashed_ship", "CRITICAL_FAILURE")
	assert_eq(leak.visit.injuries, {"Mara": "severe"})
	for s in leak.party:
		assert_eq(s.dose, 40.0, "the reactor leak poisons everyone")
	assert_eq(leak.visit.loot, {})


func test_weather_station() -> void:
	var win := _run("weather_station", "SUCCESS", [4])
	assert_eq(win.visit.loot, {"metal": 4})
	assert_eq(win.visit.reveal, 10)
	var crit := _run("weather_station", "CRITICAL_SUCCESS", [9])
	assert_eq(crit.visit.loot, {"metal": 9})
	assert_eq(crit.visit.reveal, 20)
	var miss := _run("weather_station", "FAILURE")
	assert_eq(miss.visit.loot, {})
	assert_eq(miss.visit.injuries, {}, "nothing salvageable, and nobody hurt")
	assert_eq(miss.visit.outcome, "empty")
	var fall := _run("weather_station", "CRITICAL_FAILURE")
	assert_eq(fall.visit.injuries, {"Mara": "severe"})


func test_chemical_dump() -> void:
	assert_eq(_run("chemical_dump", "SUCCESS", [6, 2]).visit.loot, {"fuel": 6, "gold": 2})
	assert_eq(_run("chemical_dump", "CRITICAL_SUCCESS", [14]).visit.loot, {"fuel": 14})
	var fumes := _run("chemical_dump", "FAILURE", [3])
	assert_eq(fumes.visit.loot, {"fuel": 3})
	assert_eq(fumes.visit.injuries, {"Mara": "light"})
	assert_eq(fumes.party[1].dose, 10.0)
	var spill := _run("chemical_dump", "CRITICAL_FAILURE")
	assert_eq(spill.visit.injuries, {"Mara": "severe"})
	assert_eq([spill.party[0].dose, spill.party[1].dose, spill.party[2].dose], [50.0, 50.0, 50.0])


func test_radio_tower_charts_the_map_and_wins_dustwells_trust() -> void:
	var win := _run("radio_tower", "SUCCESS")
	assert_eq(win.visit.reveal, 15)
	assert_eq(win.visit.loot, {})
	assert_eq(win.visit.outcome, "looted", "charting the ground counts as a find: it is not 'nothing here'")
	var crit := _run("radio_tower", "CRITICAL_SUCCESS")
	assert_eq(crit.visit.reveal, 25)
	assert_eq(crit.visit.trust, 20)
	var slip := _run("radio_tower", "FAILURE")
	assert_eq(slip.visit.injuries, {"Mara": "light"})


func test_a_site_fight_is_forced_at_the_sites_strength_and_pays_the_enemys_package_when_won() -> void:
	var party := _party()
	var dice := ForcedDice.new([1, 14, 5], [4])   # the check fumbles, the fight (DC 14) just wins, the spoils are metal
	var visit := _visit("radio_tower", party, dice)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "fight")
	assert_eq(visit.enemy, 4)
	assert_eq(visit.after, "end", "winning ends the visit: the site is spent")
	var view := D20Visit.pending(visit, party)
	assert_eq(view.dc, 14)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "done")
	assert_eq(visit.loot, {"metal": 4})
	assert_eq(visit.outcome, "looted")
	assert_true(dice.d20_values.is_empty() and dice.totals.is_empty())


func test_losing_a_site_fight_drives_the_party_off_and_spends_the_site() -> void:
	var party := _party()
	var dice := ForcedDice.new([1, 8], [])   # the check fumbles, the fight (DC 12) is lost by a few points
	var visit := _visit("gas_station", party, dice)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.enemy, 3)
	assert_eq(D20Visit.pending(visit, party).dc, 12)
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "done")
	assert_false(visit.wiped)
	assert_eq(visit.outcome, "empty", "no ruin is left held by raiders here: the site is simply spent")


func test_a_strength_3_fight_cannot_wipe_a_party_but_a_strength_4_or_5_one_can() -> void:
	var easy_party := _party()
	var easy_dice := ForcedDice.new([1, 1], [])   # nat 1 on the check, nat 1 in the DC 12 fight: no fumble roll
	var easy := _visit("gas_station", easy_party, easy_dice)
	D20Visit.step(easy, easy_dice, easy_party)
	D20Visit.step(easy, easy_dice, easy_party)
	assert_false(easy.wiped)
	assert_true(easy_dice.d20_values.is_empty())
	var hard_party := _party()
	var hard_dice := ForcedDice.new([1, 1, 3], [])   # the same, at DC 16, and the fumble roll is 3
	var hard := _visit("bunker", hard_party, hard_dice)
	D20Visit.step(hard, hard_dice, hard_party)
	assert_eq(hard.enemy, 5)
	D20Visit.step(hard, hard_dice, hard_party)
	assert_true(hard.wiped)
	assert_eq(hard.outcome, "wiped")
	assert_true(hard_dice.d20_values.is_empty())


func test_bunker() -> void:
	assert_eq(_run("bunker", "SUCCESS", [7, 5]).visit.loot, {"metal": 7, "veg": 5})
	var crit := _run("bunker", "CRITICAL_SUCCESS", [9])
	assert_eq(crit.visit.troops, 4)
	assert_eq(crit.visit.loot, {"metal": 9})
	var jam := _run("bunker", "FAILURE", [3])
	assert_eq(jam.visit.injuries, {"Mara": "light"})
	assert_eq(jam.visit.loot, {"metal": 3})
	var squatters := _run("bunker", "CRITICAL_FAILURE")
	assert_eq(squatters.visit.stage, "fight")
	assert_eq(squatters.visit.enemy, 5)


func test_pumpjack() -> void:
	assert_eq(_run("pumpjack", "SUCCESS", [6]).visit.loot, {"fuel": 6})
	assert_eq(_run("pumpjack", "CRITICAL_SUCCESS", [14, 9]).visit.loot, {"fuel": 14, "gold": 9})
	assert_eq(_run("pumpjack", "FAILURE").visit.injuries, {"Mara": "light"})
	var fire := _run("pumpjack", "CRITICAL_FAILURE")
	assert_eq(fire.visit.injuries, {"Mara": "severe"})
	assert_eq(fire.visit.loot, {})


func test_an_outcome_that_loses_the_find_takes_what_was_already_found_at_the_site() -> void:
	var party := _party()
	var dice := ForcedDice.new([1], [])
	var visit := _visit("pumpjack", party, dice)
	visit.loot = {"fuel": 10}
	visit.site_loot = {"fuel": 10}
	D20Visit.step(visit, dice, party)
	assert_eq(visit.loot.get("fuel", 0), 0)


func test_water_tower() -> void:
	assert_eq(_run("water_tower", "SUCCESS", [6]).visit.loot, {"veg": 6})
	var crit := _run("water_tower", "CRITICAL_SUCCESS", [15])
	assert_eq(crit.visit.loot, {"veg": 15})
	assert_eq(crit.visit.colonists, 2)
	var miss := _run("water_tower", "FAILURE")
	assert_eq(miss.visit.injuries, {})
	assert_eq(miss.visit.outcome, "empty")
	assert_eq(_run("water_tower", "CRITICAL_FAILURE").visit.injuries, {"Mara": "severe"})


func test_gas_station() -> void:
	assert_eq(_run("gas_station", "SUCCESS", [5]).visit.loot, {"fuel": 5})
	assert_eq(_run("gas_station", "CRITICAL_SUCCESS", [13, 6]).visit.loot, {"fuel": 13, "metal": 6})
	assert_eq(_run("gas_station", "FAILURE").visit.outcome, "empty")
	var ambush := _run("gas_station", "CRITICAL_FAILURE")
	assert_eq(ambush.visit.stage, "fight")
	assert_eq(ambush.visit.enemy, 3)


func test_missile_silo_is_the_deadly_one() -> void:
	assert_eq(_run("missile_silo", "SUCCESS", [9]).visit.loot, {"fuel": 9, "nuke": 1}, "and one unfired nuke")
	var crit := _run("missile_silo", "CRITICAL_SUCCESS", [8], [12])   # the second d20 of 12 or less: two warheads
	assert_true(crit.visit.reveal_fort)
	assert_eq(crit.visit.loot, {"metal": 8, "nuke": 2})
	assert_eq(_run("missile_silo", "CRITICAL_SUCCESS", [8], [13]).visit.loot, {"metal": 8, "nuke": 3}, "13 or more: three")
	assert_eq(_run("missile_silo", "FAILURE").visit.outcome, "empty")
	var defenses := _run("missile_silo", "CRITICAL_FAILURE")
	assert_eq(defenses.visit.stage, "fight")
	assert_eq(defenses.visit.enemy, 5)


func test_cargo_yard() -> void:
	assert_eq(_run("cargo_yard", "SUCCESS", [3, 2, 4, 1]).visit.loot, {"metal": 3, "fuel": 2, "gold": 4, "veg": 1})
	# the sealed container: a large package of a rolled resource (a 2 is metal), then a medium one of another (a 3 is
	# metal again, so it rolls on: a 15 is gold)
	var crit := _run("cargo_yard", "CRITICAL_SUCCESS", [15, 9], [2, 3, 15])
	assert_eq(crit.visit.loot, {"metal": 15, "gold": 9})
	assert_eq(_run("cargo_yard", "FAILURE").visit.injuries, {"Mara": "light"})
	assert_eq(_run("cargo_yard", "CRITICAL_FAILURE").visit.injuries, {"Mara": "severe"})


# ---------------------------------------------------------------- saving

func test_a_site_visit_survives_a_json_round_trip() -> void:
	var run := _run("radio_tower", "CRITICAL_SUCCESS")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(run.visit))
	D20Visit.normalize(saved)
	assert_eq(saved.reveal, 25)
	assert_true(saved.reveal is int)
	assert_eq(saved.trust, 20)
	assert_eq(saved.poi, "radio_tower")
	var old: Dictionary = run.visit.duplicate(true)
	for k in ["reveal", "reveal_fort", "trust", "colonists", "troops"]:
		old.erase(k)
	D20Visit.normalize(old)
	assert_eq([old.reveal, old.trust, old.colonists, old.troops, old.reveal_fort], [0, 0, 0, 0, false], "a visit saved before outcomes existed loads")
