extends "res://tests/framework/test_case.gd"
## The right panel at a ruin: "Scavenge", the clickable d20 below it, the roll playing at 1.25 speed, and the
## landed number staying up until the player clicks off it. Driven through the real HUD like a player would.

const Data = preload("res://scripts/data.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var main: Node2D
var hud: Node
var ruin: Vector2i
var party: Dictionary


func before_each() -> void:
	seed(5)
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	_press("New colony")
	_press("Builder")
	await wait_frames(3)
	Units.tribes = []
	Units.wild_spawns = false
	ruin = Game.home(Data.PLAYER) + Vector2i(1, -2)


## A party at the ruin beside the camp, with these dice, and the ruin selected so the panel shows it.
func _go_to_ruin(dice) -> void:
	Units.dice = dice
	Game.tile(ruin)["r"] = "safe"
	party = Units._make_unit("scav", Data.PLAYER, "foot", ruin, ruin)
	party.home = Game.home(Data.PLAYER)
	party.crew = 3
	party.survivors = Units._make_crew(3)
	for s in party.survivors:
		s.traits = []
	Units.units.append(party)
	Units._begin_visit(party)
	Game.select(ruin)
	Game.changed.emit()
	await wait_frames(3)


func _tile_labels() -> String:
	var text := ""
	for l in hud.boxes["Tile"].find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func test_the_panel_shows_scavenge_with_a_clickable_die_below_it() -> void:
	await _go_to_ruin(ForcedDice.new([9, 10, 13], [6]))
	var text := _tile_labels()
	assert_has(text, "SCAVENGE")
	assert_has(text, "Click the die to roll")
	assert_eq(hud.dice.get_parent(), hud.dice_holder)
	assert_true(hud.dice_holder.is_inside_tree())
	assert_true(hud.boxes["Tile"].is_ancestor_of(hud.dice_holder))
	assert_eq(hud.dice.playback_speed, 1.25)
	assert_eq(hud.dice.scale, Vector2(3, 3))
	assert_eq(hud.dice.return_to_idle_after, 0.0, "the number stays until the player clicks off it")
	var order: Array = hud.boxes["Tile"].get_children()
	var heading := -1
	var die := -1
	for i in order.size():
		if order[i] is Label and order[i].text.contains("SCAVENGE") and heading == -1:
			heading = i
		if order[i] == hud.dice_holder:
			die = i
	assert_gt(die, heading, "the die sits below the Scavenge heading")


func test_clicking_the_die_rolls_it_and_the_number_sits_until_the_player_clicks_off() -> void:
	await _go_to_ruin(ForcedDice.new([9, 10, 13], [6]))
	hud.dice.clicked.emit()
	await wait_frames(2)
	assert_eq(hud.dice_phase, "rolling")
	assert_true(hud.dice.is_rolling())
	assert_eq(hud.dice.sprite.animation, &"roll_9", "it lands on the d20 the search rolled")
	assert_has(_tile_labels(), "Rolling")
	hud.dice.clicked.emit()   # a click mid-roll does nothing
	assert_eq(hud.dice_phase, "rolling")
	await wait_seconds(1.0)   # the roll takes about 0.6 seconds at 1.25x
	assert_eq(hud.dice_phase, "landed")
	assert_eq(hud.dice.get_result(), 9)
	assert_has(_tile_labels(), "Search: d20 9")
	assert_has(_tile_labels(), "Click the die to continue")
	hud.dice.clicked.emit()
	assert_eq(hud.dice_phase, "landed", "the number sits on screen for a second first")
	await wait_seconds(1.1)
	hud.dice.clicked.emit()
	await wait_frames(3)
	assert_eq(hud.dice_phase, "idle")
	assert_has(_tile_labels(), "Cache check")


func test_a_whole_visit_through_the_panel() -> void:
	await _go_to_ruin(ForcedDice.new([9, 10, 13], [6]))
	for roll in 2:
		hud.dice.clicked.emit()
		await wait_seconds(1.1)
		assert_eq(hud.dice_phase, "landed")
		await wait_seconds(1.0)
		hud.dice.clicked.emit()
		await wait_frames(3)
	assert_has(_tile_labels(), "stripped", "the panel says what the ruins gave up")
	_press("Head home")
	await wait_frames(3)
	assert_eq(party.stage, "back")
	assert_eq(party.carry, {"fuel": 18})


func test_the_die_survives_the_panel_being_rebuilt_mid_roll() -> void:
	await _go_to_ruin(ForcedDice.new([9, 10, 13], [6]))
	hud.dice.clicked.emit()
	await wait_frames(2)
	Game.changed.emit()
	await wait_frames(3)
	assert_true(hud.dice.is_rolling(), "the animation carries on")
	assert_eq(hud.dice.get_parent(), hud.dice_holder)
	assert_true(hud.boxes["Tile"].is_ancestor_of(hud.dice_holder))
	await wait_seconds(1.0)
	assert_eq(hud.dice_phase, "landed")


func test_a_site_is_one_check_in_the_panel_and_the_panel_says_what_it_gave() -> void:
	var site := Vector2i(-1, -1)
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if Game.poi_kind(c) == "weather_station" and Game.poi_anchor(c) == c:
			site = c
	assert_true(Game.in_bounds(site), "the map has a weather station")
	Units.dice = ForcedDice.new([15], [2])
	party = Units._make_unit("scav", Data.PLAYER, "foot", site, site)
	party.home = Game.home(Data.PLAYER)
	party.crew = 3
	party.survivors = Units._make_crew(3)
	for s in party.survivors:
		s.traits = []
	Units.units.append(party)
	Units._begin_visit(party)
	Game.select(site)
	Game.changed.emit()
	await wait_frames(3)
	var text := _tile_labels()
	assert_has(text, "SCAVENGE")
	assert_has(text, "Site check, DC 11")
	assert_has(text, "Click the die to roll")
	hud.dice.clicked.emit()
	await wait_seconds(1.1)
	assert_eq(hud.dice_phase, "landed")
	assert_has(_tile_labels(), "Logbook.", "the outcome's name")
	assert_has(_tile_labels(), "The map within 10 tiles is charted.")
	await wait_seconds(1.0)
	hud.dice.clicked.emit()
	await wait_frames(3)
	assert_has(_tile_labels(), "picked clean")
	_press("Head home")
	await wait_frames(3)
	assert_eq(party.stage, "back")
	assert_eq(party.carry, {"metal": 9})


func test_choices_that_are_not_rolls_are_buttons() -> void:
	await _go_to_ruin(ForcedDice.new([]))
	var view := Units.visit_view(party)
	assert_eq(view.stage, "event")
	# "Leave without searching" is a button next to the die
	_press("Leave without searching")
	await wait_frames(3)
	assert_eq(party.visit.stage, "done")
	assert_false(hud.boxes["Tile"].is_ancestor_of(hud.dice_holder), "nothing left to roll: no die")
