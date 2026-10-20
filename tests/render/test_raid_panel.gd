extends "res://tests/framework/test_case.gd"
## The raid screens: the camp, fort and Dustwell buttons show the DC and the chance, a stationed scouting party attacks a camp with
## the pixel die, and after a natural 20 on a trap check the panel offers the die to search the ruins. Driven through the real HUD.

const Data = preload("res://scripts/data.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const D20 = preload("res://scripts/d20.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")
const Leaders = preload("res://scripts/leaders.gd")

var main: Node2D
var hud: Node
var hq: Vector2i


func before_each() -> void:
	seed(5)
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	Units.tribes = []
	Units.wild_spawns = false
	D20.loot_scale = D20Data.LOOT_SCALE
	hq = Game.home(Data.PLAYER)


func after_each() -> void:
	Units.dice = load("res://scripts/dice.gd").new()


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _show_tab(tab_name: String) -> void:
	for i in hud.tabs.get_tab_count():
		if hud.tabs.get_tab_title(i) == tab_name:
			hud.tabs.current_tab = i
	await wait_frames(2)


func _labels(tab: String) -> String:
	var text := ""
	for l in hud.boxes[tab].find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


func _button_texts(tab: String) -> Array:
	return hud.boxes[tab].find_children("*", "Button", true, false).map(func(b): return b.text)


func _button_with(tab: String, start: String) -> String:
	for t in _button_texts(tab):
		if t.begins_with(start):
			return t
	return ""


## Lets a die roll land and clicks it off.
func _roll_and_continue() -> void:
	hud.dice.clicked.emit()
	await wait_seconds(1.1)
	assert_eq(hud.dice_phase, "landed")
	await wait_seconds(1.0)
	hud.dice.clicked.emit()
	await wait_frames(3)


# ---------------------------------------------------------------- the buttons

func test_the_camp_attack_button_shows_the_dc_and_the_chance() -> void:
	var t: Dictionary = Units._spawn_tribe()
	t["class"] = "raider"
	t["strength"] = 6
	t["found"] = true
	Game.troops = 10
	Game.changed.emit()
	await _show_tab("Diplomacy")   # known camps are listed there
	var text := _button_with("Diplomacy", "Attack their camp")
	var att := Game.player_attack(t.pos)
	assert_ne(text, "", "the button is there")
	assert_has(text, D20.plain(Game.raid_odds_text(att, 6.0)))
	assert_has(text, "% to win")


func test_the_fort_raid_and_dustwell_buttons_show_the_dc_and_the_chance() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.contacts["%d:%d" % [Data.PLAYER, Data.TOWN]] = true
	Game.troops = 10
	Game.changed.emit()
	await _show_tab("Diplomacy")
	var raid := _button_with("Diplomacy", "RAID them")
	assert_ne(raid, "")
	assert_has(raid, D20.plain(Game.raid_odds_text(Game.player_attack(Game.home(Data.AI)), Game.ai_defense(Game.wall_breach()))))
	var conquer := _button_with("Diplomacy", "Conquer")
	assert_ne(conquer, "")
	assert_has(conquer, D20.plain(Game.raid_odds_text(Game.player_attack(Game.home(Data.TOWN)), Game.TOWN_DEFENSE)))


# ---------------------------------------------------------------- a scouting party attacks a camp

func _scouts_beside_a_camp() -> Dictionary:
	var pos := hq + Vector2i(6, 0)
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", pos, hq)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	for s in u.survivors:
		s.traits = []
	u.stage = "station"
	u.food = {"grain": 8}
	Units.units.append(u)
	var camp: Dictionary = Units._spawn_tribe()
	camp["class"] = "raider"
	camp["strength"] = 5
	camp["pos"] = pos + Vector2i(1, 0)
	camp["found"] = true
	Game.select(pos)
	Game.changed.emit()
	await wait_frames(3)
	return u


func test_a_stationed_party_beside_a_camp_gets_an_attack_button_and_a_die() -> void:
	var u := await _scouts_beside_a_camp()
	var camp: Dictionary = Units.tribes[-1]
	var text := _button_with("Tile", "Attack the %s" % camp.name)
	assert_ne(text, "", "an attack button for the camp")
	assert_false(text.contains("DC 16"), "the DC is not on the button")
	assert_has(text, "strength 5")
	Units.dice = ForcedDice.new([18, 5], [3])
	_press("Attack the %s" % camp.name)
	await wait_frames(3)
	assert_eq(u.stage, "site")
	assert_has(_labels("Tile"), "Attack")
	assert_has(_labels("Tile"), "Click the die to roll")
	assert_has(_labels("Tile"), "enemy strength 5")
	await _roll_and_continue()
	assert_has(_labels("Tile"), "The camp is scattered.")
	_press("Continue")
	await wait_frames(3)
	assert_false(Units.tribes.has(camp), "the camp is gone")
	assert_eq(u.stage, "station")


# ---------------------------------------------------------------- a natural 20 on a trap check

func test_after_a_natural_20_trap_roll_the_panel_offers_the_die_to_search_the_ruins() -> void:
	var ruin := hq + Vector2i(1, -2)
	Units.dice = ForcedDice.new([20, 5, 8], [3])   # the trap check, the metal it pays, then a search that finds nothing more
	Game.tile(ruin)["r"] = "trap"
	var party: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	party.home = hq
	party.crew = 3
	party.survivors = Units._make_crew(3)
	for s in party.survivors:
		s.traits = []
	Units.units.append(party)
	Units._begin_visit(party)
	Game.select(ruin)
	Game.changed.emit()
	await wait_frames(3)
	assert_has(_labels("Tile"), "Trap check")
	await _roll_and_continue()   # the natural 20
	assert_eq(party.visit.stage, "event", "the party is still at the ruins")
	assert_has(_labels("Tile"), "Search the ruins: a plain d20", "the panel asks for the search roll")
	assert_has(_labels("Tile"), "Click the die to roll")
	await _roll_and_continue()   # the search
	assert_has(_labels("Tile"), "The ruins are stripped. The party carries", "and says what the trap paid")
	assert_false(_labels("Tile").contains("There was nothing here"))
	_press("Continue")
	await wait_frames(3)
	assert_eq(party.stage, "station")
	assert_true(party.carry.has("metal"))
