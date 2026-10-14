extends "res://tests/framework/test_case.gd"
## The right panel at a ruin: "Scavenge", the clickable d20 below it, the roll playing at 1.25 speed, and the
## landed number staying up until the player clicks off it. Driven through the real HUD like a player would.

const Data = preload("res://scripts/data.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")
const Leaders = preload("res://scripts/leaders.gd")

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
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]   # no perks, so the tests are not left to luck
	_press("New colony")
	_press("Choose")
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
	await _go_to_ruin(ForcedDice.new([17, 10, 13], [6]))
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
	await _go_to_ruin(ForcedDice.new([17, 10, 13], [6]))
	hud.dice.clicked.emit()
	await wait_frames(2)
	assert_eq(hud.dice_phase, "rolling")
	assert_true(hud.dice.is_rolling())
	assert_eq(hud.dice.sprite.animation, &"roll_17", "it lands on the d20 the search rolled")
	assert_has(_tile_labels(), "Rolling")
	hud.dice.clicked.emit()   # a click mid-roll does nothing
	assert_eq(hud.dice_phase, "rolling")
	await wait_seconds(1.0)   # the roll takes about 0.6 seconds at 1.25x
	assert_eq(hud.dice_phase, "landed")
	assert_eq(hud.dice.get_result(), 17)
	assert_has(_tile_labels(), "Search: d20 17")
	assert_has(_tile_labels(), "Click the die to continue")
	hud.dice.clicked.emit()
	assert_eq(hud.dice_phase, "landed", "the number sits on screen for a second first")
	await wait_seconds(1.1)
	hud.dice.clicked.emit()
	await wait_frames(3)
	assert_eq(hud.dice_phase, "idle")
	assert_has(_tile_labels(), "Cache check")


func test_a_whole_visit_through_the_panel() -> void:
	await _go_to_ruin(ForcedDice.new([17, 10, 13], [6]))
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
	await _go_to_ruin(ForcedDice.new([17, 10, 13], [6]))
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
	assert_has(text, "Site check")
	assert_false(text.contains("DC 11"), "the DC is not on screen")
	assert_false(text.contains("+0") or text.contains("vs DC"), "nor the modifier")
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


func test_a_scout_party_next_to_a_raider_wall_attacks_it_through_the_panel() -> void:
	Game.ai["walls"] = 8
	Game._sync_ai_walls()
	var wall := Vector2i(-1, -1)
	for c in Game.owned(Data.AI):
		if Game.tile(c)["b"] == "ai_wall":
			wall = c
			break
	assert_true(Game.in_bounds(wall), "they have a Raider wall")
	var spot := wall
	for n in Game.neighbors(wall):
		if Game.tile(n)["t"] != "water":
			spot = n
			break
	Units.dice = ForcedDice.new([20, 5], [4])   # a natural 20, then the spoils (5 is metal, 4 on the dice)
	party = Units._make_unit("scout", Data.PLAYER, "foot", spot, spot)
	party.home = Game.home(Data.PLAYER)
	party.crew = 3
	party.survivors = Units._make_crew(3)
	for s in party.survivors:
		s.traits = []
	party.stage = "station"
	party.food = {"grain": 5}
	Units.units.append(party)
	Game.reveal(Data.PLAYER, spot, 3)
	Game.select(spot)
	Game.changed.emit()
	await wait_frames(3)
	_press("Attack the raider wall")
	await wait_frames(3)
	assert_eq(party.stage, "site")
	var text := _tile_labels()
	assert_has(text, "ATTACK")
	assert_has(text, "Attack")
	assert_false(text.contains("DC 12"), "the DC is not on screen")
	assert_has(text, "Click the die to roll")
	hud.dice.clicked.emit()
	await wait_seconds(1.1)
	assert_eq(hud.dice_phase, "landed")
	assert_has(_tile_labels(), "The building comes down.")
	await wait_seconds(1.0)
	hud.dice.clicked.emit()
	await wait_frames(3)
	assert_has(_tile_labels(), "The building came down.")
	assert_eq(Game.tile(wall)["b"], "ai_wall", "it falls when the party presses Continue")
	_press("Continue")
	await wait_frames(3)
	assert_eq(party.stage, "station")
	assert_eq(Game.tile(wall)["b"], "")
	assert_eq(Game.ai["walls"], 4)
	assert_eq(party.carry, {"metal": 12})


func test_choices_that_are_not_rolls_are_buttons() -> void:
	await _go_to_ruin(ForcedDice.new([]))
	var view := Units.visit_view(party)
	assert_eq(view.stage, "event")
	# "Leave without searching" is a button next to the die
	_press("Leave without searching")
	await wait_frames(3)
	assert_eq(party.visit.stage, "done")
	assert_false(hud.boxes["Tile"].is_ancestor_of(hud.dice_holder), "nothing left to roll: no die")


func test_the_roll_shows_the_die_and_what_came_of_it_but_not_the_arithmetic() -> void:
	await _go_to_ruin(ForcedDice.new([17, 10, 13], [6]))
	assert_false(_tile_labels().contains("DC"), "before the roll: no DC")
	assert_false(_tile_labels().contains("vs"), "and no modifier sum")
	for roll in 2:
		hud.dice.clicked.emit()
		await wait_seconds(1.1)
		assert_eq(hud.dice_phase, "landed")
		var panel := _tile_labels()
		assert_false(panel.contains("DC"), "roll %d: no DC on the panel" % roll)
		assert_false(panel.contains(" vs "), "roll %d: no sum against it" % roll)
		assert_false(panel.contains("] "), "roll %d: no list of modifiers" % roll)
		await wait_seconds(1.0)
		hud.dice.clicked.emit()
		await wait_frames(3)
	assert_true(Game.log_lines.any(func(l): return l.contains("vs DC")), "the game's own log keeps the full line")
	assert_false(hud.log_text.text.contains("vs DC"), "the log on screen does not show the DC")
	assert_false(hud.log_text.text.contains("d20 10 +"), "nor the sum")
	assert_true(hud.log_text.text.contains("cache"), "but it still says what was rolled for")


func test_the_numbers_come_back_with_show_math() -> void:
	const D20 = preload("res://scripts/d20.gd")
	D20.show_math = true
	await _go_to_ruin(ForcedDice.new([17, 10, 13], [6]))
	hud.dice.clicked.emit()
	await wait_seconds(1.1)
	await wait_seconds(1.0)
	hud.dice.clicked.emit()
	await wait_frames(3)
	assert_has(_tile_labels(), "DC", "with the switch on, the arithmetic is on the panel")
	D20.show_math = false
