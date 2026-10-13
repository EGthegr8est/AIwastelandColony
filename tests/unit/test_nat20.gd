extends "res://tests/framework/test_case.gd"
## A natural 20 on a ruin never leaves a scavenging party empty-handed, and a natural 20 on a trap check is always followed by
## the roll to search the ruins. (A natural 20 on the Search used to find nothing, a trap check's package was followed by a panel
## that said "There was nothing here.", and a natural 20 on an ambush check forced a fight the party could lose.)

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

## Hands out the d20 values it was given first and rolls fairly after them.
class FirstThenFair:
	extends "res://scripts/dice.gd"
	var forced: Array = []

	func d20() -> int:
		if not forced.is_empty():
			return forced.pop_front()
		return randi_range(1, 20)


var hq: Vector2i
var ruin: Vector2i


func before_each() -> void:
	World.new_game(7)
	Units.tribes = []
	Units.wild_spawns = false
	hq = Game.home(Data.PLAYER)
	ruin = hq + Vector2i(1, -2)
	D20.loot_scale = D20Data.LOOT_SCALE


func after_each() -> void:
	D20.permadeath = D20Data.PERMADEATH
	D20.loot_scale = D20Data.LOOT_SCALE
	Units.dice = load("res://scripts/dice.gd").new()


func _party() -> Array:
	var out := []
	for n in ["Mara", "Dex", "Odo"]:
		out.append({"name": n, "age": 30, "traits": [], "injury": "none", "hunger": 0, "hp": 100.0, "dose": 0.0, "hurt": false, "face": 1, "sick": 0})
	return out


## A whole visit to a ruin of this kind whose first roll is `first`, the rest fair, played to the end with the safest choices.
func _whole_visit(state: String, first: int, seed_value: int) -> Dictionary:
	seed(seed_value)
	var party := _party()
	var dice := FirstThenFair.new()
	dice.forced = [first]
	var visit := D20Visit.begin(state, {"radiation": 0.0, "party_strength": 3}, 1.0, dice, party)
	var steps := 0
	while visit.stage != "done" and steps < 40:
		steps += 1
		D20Visit.step(visit, dice, party, {"choice": "fight", "deeper": "home"}.get(visit.stage, "roll"))
	visit["panel"] = D20Visit.pending(visit, party).text
	return visit


func _loot_total(visit: Dictionary) -> int:
	var total := 0
	for r in visit.loot:
		total += int(visit.loot[r])
	return total


# ---------------------------------------------------------------- the search

func test_a_natural_20_on_the_search_finds_a_cache() -> void:
	var party := _party()
	var visit := D20Visit.begin("safe", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new(), party)
	var dice := ForcedDice.new([20, 5, 15], [4])   # search 20, the cache holds metal, the cache check is 15 against DC 11
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "cache")
	assert_true(visit.last[0].contains("a pre-war cache"))
	D20Visit.step(visit, dice, party)
	assert_eq(visit.stage, "done")
	assert_gt(_loot_total(visit), 0)
	assert_ne(visit.outcome, "empty")


func test_a_natural_20_on_the_search_always_finds_a_cache_over_300_visits() -> void:
	for s in 300:
		var visit := _whole_visit("safe", 20, s)
		assert_true(visit.log[0].contains("a pre-war cache"), "seed %d: %s" % [s, visit.log[0]])
		assert_ne(visit.panel, "There was nothing here.", "seed %d" % s)
		# (the cache check that follows is its own roll: a critical miss on it can still ruin the cache, which is a different die)


func test_a_low_search_still_finds_nothing_and_says_so() -> void:
	var party := _party()
	var visit := D20Visit.begin("safe", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new(), party)
	D20Visit.step(visit, ForcedDice.new([8]), party)   # 7 to 10 is "nothing of note"
	assert_eq(visit.outcome, "empty")
	assert_eq(D20Visit.pending(visit, party).text, "There was nothing here.")


# ---------------------------------------------------------------- a natural 20 on a trap check

func test_a_natural_20_on_a_trap_check_is_followed_by_a_roll_to_search_the_ruins() -> void:
	var party := _party()
	var visit := D20Visit.begin("trapped", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new(), party)
	assert_eq(visit.stage, "trap")
	D20Visit.step(visit, ForcedDice.new([20, 5], [3]), party)   # the trap check, then the metal it pays
	assert_eq(visit.stage, "event", "the ruins are open: the search comes next")
	assert_true(visit.last.any(func(l): return l.contains("search them")))
	var view := D20Visit.pending(visit, party)
	assert_true(view.buttons.any(func(b): return b.id == "roll" and b.label == "Search the ruins (d20)"), "and the player gets its die")


func test_through_the_game_a_natural_20_trap_roll_is_followed_by_a_search_that_finds_things() -> void:
	Units.dice = ForcedDice.new([20, 5, 17, 9, 14], [3, 4])   # trap 20, metal for the trap, search 17 (a cache), fuel, check 14
	var u := _party_at_ruin("trap")
	assert_eq(Units.visit_do(u.id), 20, "the trap check")
	var view := Units.visit_view(u)
	assert_eq(view.stage, "event", "the party stays at the ruins for the search")
	assert_true(view.buttons.any(func(b): return b.id == "roll"))
	assert_eq(Units.visit_do(u.id), 17, "the search roll")
	assert_true(Game.log_lines.any(func(l): return l.contains("Search: d20 17")))
	Units.visit_do(u.id)   # the cache check
	assert_eq(Units.visit_view(u).stage, "done")
	Units.visit_finish(u.id)
	assert_true(u.carry.has("metal"), "the trap's package is hauled home")
	assert_true(u.carry.has("fuel"), "and so is the cache")


func test_a_search_that_finds_nothing_after_a_natural_20_trap_keeps_the_trap_package_and_the_panel_says_so() -> void:
	Units.dice = ForcedDice.new([20, 5, 8], [3])   # trap 20, metal, then a search of 8: nothing more
	var u := _party_at_ruin("trap")
	Units.visit_do(u.id)
	Units.visit_do(u.id)
	assert_eq(u.visit.stage, "done")
	assert_eq(u.visit.outcome, "looted", "not an empty visit: it found the trap's package")
	var text: String = Units.visit_view(u).text
	assert_false(text.contains("There was nothing here"), text)
	assert_true(text.contains("The party carries 9 metal"), text)
	assert_true(u.visit.log.any(func(l): return l == "Nothing more turns up."))
	Units.visit_finish(u.id)
	assert_true(u.carry.has("metal"))
	assert_false(Game.log_lines.any(func(l): return l.contains("carry no loot") or l.contains("with nothing")))


func test_a_natural_20_on_a_trap_check_never_ends_empty_handed_over_300_visits() -> void:
	for s in 300:
		var visit := _whole_visit("trapped", 20, s)
		assert_gt(_loot_total(visit), 0, "seed %d" % s)
		assert_false(visit.panel.begins_with("There was nothing here"), "seed %d: %s" % [s, visit.panel])
		assert_eq(visit.stage, "done")
		assert_true(visit.log.any(func(l): return l.begins_with("Search: d20")), "a search roll followed the trap check (seed %d)" % s)


# ---------------------------------------------------------------- a natural 20 on an ambush check

func test_a_natural_20_on_an_ambush_check_beats_the_raiders_outright() -> void:
	var party := _party()
	var visit := D20Visit.begin("rogue", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new([], [3]), party)
	assert_eq(visit.stage, "ambush")
	D20Visit.step(visit, ForcedDice.new([20, 5, 17], [3, 5]), party)   # the check, the enemy's package (metal), the bonus (gold)
	assert_eq(visit.stage, "event", "no fight to lose: the ruins are theirs to search")
	assert_eq(visit.prisoners, 1)
	assert_true(visit.camp_revealed)
	assert_eq(visit.packages.size(), 2, "the enemy's package and the ambush's bonus")
	assert_true(visit.last.any(func(l): return l.contains("turn the ambush on them")))
	assert_false(visit.last.any(func(l): return l.contains("driven off")))


func test_a_natural_20_on_an_ambush_check_can_never_be_driven_off_over_300_visits() -> void:
	for s in 300:
		var visit := _whole_visit("rogue", 20, s)
		assert_ne(visit.outcome, "lost_fight", "seed %d" % s)
		assert_ge(visit.packages.size(), 2, "the enemy's package and the bonus, seed %d" % s)
		assert_eq(visit.prisoners, 1)
		assert_true(visit.camp_revealed)


func test_an_ordinary_win_at_the_ruins_still_reveals_nothing_extra() -> void:
	var party := _party()
	var visit := D20Visit.begin("rogue", {"radiation": 0.0, "party_strength": 3}, 1.0, ForcedDice.new([], [3]), party)
	D20Visit.step(visit, ForcedDice.new([15]), party)   # an ambush check of 15 against DC 14: a SUCCESS, so the party may fight or slip away
	assert_eq(visit.stage, "choice")
	assert_false(visit.camp_revealed)


# ---------------------------------------------------------------- helper

func _party_at_ruin(state: String) -> Dictionary:
	Game.tile(ruin)["r"] = state
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	u.home = hq
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = []
	Units.units.append(u)
	Units._begin_visit(u)
	return u
