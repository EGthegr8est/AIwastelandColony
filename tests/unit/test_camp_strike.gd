extends "res://tests/framework/test_case.gd"
## A stationed scouting party can attack a raider camp beside it, the way it attacks a Raider wall: one roll a press (the pixel
## die in the panel) against the camp's DC, and what a hit, a miss and a wipe-out do.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var hq: Vector2i
var scouts: Dictionary
var camp: Dictionary


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	D20.loot_scale = D20Data.LOOT_SCALE
	var pos := hq + Vector2i(6, 0)
	scouts = Units._make_unit("scout", Data.PLAYER, "foot", pos, hq)
	scouts.crew = 2
	scouts.survivors = Units._make_crew(2)
	for s in scouts.survivors:
		s.traits = []
	scouts.stage = "station"
	scouts.food = {"grain": 8}
	Units.units.append(scouts)
	camp = Units._spawn_tribe()
	camp["class"] = "raider"
	camp["strength"] = 5
	camp["pos"] = pos + Vector2i(1, 0)


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	Units.dice = load("res://scripts/dice.gd").new()


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


func test_a_raider_camp_beside_a_stationed_party_is_a_target() -> void:
	assert_eq(Units.camp_targets(scouts), [camp])
	camp["pos"] = scouts.pos   # on its own tile too
	assert_eq(Units.camp_targets(scouts), [camp])


func test_other_camps_and_other_parties_are_not_targets() -> void:
	camp["class"] = "trader"
	assert_eq(Units.camp_targets(scouts), [], "trader camps are for trade")
	camp["class"] = "builder"
	assert_eq(Units.camp_targets(scouts), [], "builder camps are for gifts")
	camp["class"] = "raider"
	camp["pos"] = scouts.pos + Vector2i(5, 0)
	assert_eq(Units.camp_targets(scouts), [], "too far")
	camp["pos"] = scouts.pos + Vector2i(1, 0)
	scouts.stage = "out"
	assert_eq(Units.camp_targets(scouts), [], "only a party keeping watch")
	scouts.stage = "station"
	scouts.job = "scav"
	assert_eq(Units.camp_targets(scouts), [], "only scouting parties")


func test_starting_the_attack_opens_a_visit_against_the_camps_dc() -> void:
	assert_true(Units.begin_camp_strike(scouts.id, camp.id))
	assert_eq(scouts.stage, "site")
	assert_eq(scouts.visit.ruin, "camp")
	assert_eq(scouts.visit.strike_dc, D20Visit.enemy_dc(5), "a strength 5 camp is DC 16")
	assert_eq(Units.stage_text(scouts), "attacking a camp")
	var view := Units.visit_view(scouts)
	assert_eq(view.ruin, "camp")
	assert_true(view.text.contains("DC 16"))
	assert_true(view.text.contains("enemy strength 5"))
	assert_true(view.buttons.any(func(b): return b.id == "roll"))
	assert_true(view.buttons.any(func(b): return b.id == "home" and b.label == "Back off"))


func test_a_camp_that_is_not_beside_the_party_cannot_be_attacked() -> void:
	camp["pos"] = scouts.pos + Vector2i(6, 0)
	assert_false(Units.begin_camp_strike(scouts.id, camp.id))
	assert_false(Units.begin_camp_strike(scouts.id, 9999))
	assert_eq(scouts.stage, "station")


func test_a_hit_scatters_the_camp_catches_a_raider_and_pays_a_package() -> void:
	Units.dice = ForcedDice.new([18, 5], [3])   # 18 against DC 16: a SUCCESS, then a metal package
	var prisoners := Game.prisoners
	Units.begin_camp_strike(scouts.id, camp.id)
	assert_eq(Units.visit_do(scouts.id), 18)
	assert_eq(scouts.visit.stage, "done")
	assert_true(scouts.visit.destroyed)
	assert_eq(Units.visit_view(scouts).text, "The camp is scattered.")
	Units.visit_finish(scouts.id)
	assert_false(Units.tribes.has(camp), "the camp is gone")
	assert_eq(Game.prisoners, prisoners + 1)
	assert_eq(Game.stats.tribes_scattered, 1)
	assert_eq(scouts.stage, "station", "back to keeping watch")
	assert_false(scouts.carry.is_empty())
	assert_true(_log_has("scattered the %s and caught 1 of the raiders" % camp.name))


func test_a_miss_leaves_the_camp_hurts_the_roller_and_costs_a_quarter_of_the_load() -> void:
	scouts.carry = {"metal": 8}
	Units.dice = ForcedDice.new([14])   # 14 -2 (two against a strength 5 camp) = 12 against DC 16: margin -4, a FAILURE
	Units.begin_camp_strike(scouts.id, camp.id)
	Units.visit_do(scouts.id)
	assert_false(scouts.visit.destroyed)
	assert_eq(Units.visit_view(scouts).text, "The camp held.")
	Units.visit_finish(scouts.id)
	assert_true(Units.tribes.has(camp), "the camp stands")
	assert_eq(scouts.carry, {"metal": 6})
	assert_eq(scouts.survivors.filter(func(s): return s.injury == "light").size(), 1)
	assert_true(_log_has("could not break the %s" % camp.name))
	assert_eq(scouts.stage, "station", "and it can try again")


func test_a_natural_1_against_a_hard_camp_can_wipe_the_party_out() -> void:
	Units.dice = ForcedDice.new([1, 3])
	Units.begin_camp_strike(scouts.id, camp.id)
	Units.visit_do(scouts.id)
	assert_true(scouts.visit.wiped)
	Units.visit_finish(scouts.id)
	assert_true(scouts.get("gone", false))
	assert_true(Units.tribes.has(camp))
	assert_true(_log_has("wiped out attacking the %s" % camp.name))


func test_backing_off_costs_nothing_and_leaves_the_camp() -> void:
	Units.dice = ForcedDice.new([])
	Units.begin_camp_strike(scouts.id, camp.id)
	Units.visit_do(scouts.id, "home")
	assert_eq(Units.visit_view(scouts).text, "You backed off.")
	Units.visit_finish(scouts.id)
	assert_true(Units.tribes.has(camp))
	assert_eq(scouts.stage, "station")
	assert_eq(Units.dice.d20_calls, 0)


func test_a_camp_scattered_by_a_raid_meanwhile_does_not_break_the_visit() -> void:
	Units.dice = ForcedDice.new([18, 5], [3])
	Units.begin_camp_strike(scouts.id, camp.id)
	Units.visit_do(scouts.id)
	Units.tribes.erase(camp)   # the troops got there first
	Units.visit_finish(scouts.id)
	assert_eq(scouts.stage, "station")


func test_a_camp_attack_survives_saving_mid_visit() -> void:
	Units.begin_camp_strike(scouts.id, camp.id)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(scouts.visit))
	var back := D20Visit.normalize(saved)
	assert_eq(back.ruin, "camp")
	assert_eq(typeof(back.camp), TYPE_INT)
	assert_eq(back.camp, camp.id)
	assert_eq(back.strike_dc, 16)
	assert_eq(typeof(back.enemy), TYPE_INT)
