extends "res://tests/framework/test_case.gd"
## The bigger, thinner UI, through the real HUD (docs: "UI: Cleaner Panels, Bigger Buttons, Hotkeys", decisions 1 to 4, 6 to 10): 40 px buttons with 17 px text, a 76 px top bar with
## 56 px buttons, a 460 px side panel, a log that shows 5 lines until you click it, one row a building with its cost on the right and what it does on hover, a Tile header of two
## lines and one travel line, the Upgrades tab by branch, the Colony vehicles as rows, and a "?" on each tab for what used to be paragraphs.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")

var main: Node2D
var hud: Node
var home: Vector2i
var free_tile: Vector2i


func before_each() -> void:
	Sprites.style = Sprites.CLEAN
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
	Game.hollow_found = true
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	for r in Data.RESOURCES:
		Game.res[r] = 500
	home = Game.home(Data.PLAYER)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var c := home + Vector2i(dx, dy)
			if Game.in_bounds(c) and Game.claim_status(c) == "":
				Game.claim(c)
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["t"] == "sand" and Game.tile(c)["b"] == "" and c != home:
			free_tile = c
			break


func after_each() -> void:
	Sprites.style = 1


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _look_at(c: Vector2i) -> void:
	Game.select(c)
	Game.changed.emit()
	await wait_frames(3)


func _show_tab(index: int) -> void:
	hud.tabs.current_tab = index
	hud.refresh()
	await wait_frames(3)


## The text lines of a tab (not the costs and key caps drawn inside its buttons).
func _labels(tab: String) -> Array:
	return hud.boxes[tab].find_children("*", "Label", true, false).filter(func(l): return not (l.get_parent() is Button or l.get_parent().name == "KeyCap")).map(func(l): return l.text)


func _buttons(tab: String) -> Array:
	return hud.boxes[tab].find_children("*", "Button", true, false)


# ---------------------------------------------------------------- the sizes

func test_the_top_bar_is_76_px_with_56_px_buttons() -> void:
	var bar: Rect2 = hud.game_ui[0].get_global_rect()
	assert_eq(bar.size.y, 76.0)
	for b in [hud.save_button, hud.load_button, hud.menu_button]:
		assert_ge(b.size.y, 56.0, b.text)
		assert_true(bar.encloses(b.get_global_rect()), "%s is inside the bar" % b.text)
	assert_eq(hud.save_button.get_theme_font_size("font_size"), 18)
	assert_almost_eq(hud.end_button.size.x, 76.8, 0.5, "END SEASON is the window, 20% bigger than its art")
	assert_eq(hud.end_button.size.y, 48.0)
	assert_true(bar.encloses(hud.end_button.get_global_rect()), "inside the bar")


func test_the_side_panel_is_460_wide_below_the_bar() -> void:
	var side: Rect2 = hud.side_panel.get_global_rect()
	var window: Vector2 = main.get_viewport().get_visible_rect().size
	assert_eq(side.size.x, 460.0)
	assert_eq(side.end.x, window.x - 6.0, "6 px from the right edge")
	assert_eq(side.position.y, 82.0, "6 px under the 76 px bar")
	var strip: Rect2 = hud.bottom.get_global_rect()
	assert_le(strip.end.x, side.position.x - 6.0, "the log strip stops before the side panel")


func test_buttons_in_the_panels_are_40_px_tall_with_17_px_text() -> void:
	await _look_at(free_tile)
	assert_eq(hud.root.theme.get_font_size("font_size", "Button"), 17)
	var seen := 0
	for b in _buttons("Tile"):
		if b.text == "?":
			continue
		assert_ge(b.size.y, 40.0, b.text)
		seen += 1
	assert_gt(seen, 5)


# ---------------------------------------------------------------- the log

func test_the_log_shows_5_lines_until_you_click_it() -> void:
	var closed: float = hud.log_panel.custom_minimum_size.y
	var strip: float = hud.BOTTOM_HEIGHT - 6.0
	assert_lt(closed, strip, "shorter than the strip")
	assert_ge(closed, 5.0 * 15.0, "but tall enough for 5 lines")
	assert_le(closed, 5.0 * 24.0 + 16.0)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud._on_log_input(click)
	assert_eq(hud.log_panel.custom_minimum_size.y, strip, "a click gives it the whole strip")
	hud._on_log_input(click)
	assert_eq(hud.log_panel.custom_minimum_size.y, closed, "and another takes it back")
	assert_ne(hud.log_text.tooltip_text, "")


# ---------------------------------------------------------------- the Tile tab

func test_the_tile_header_is_two_lines_and_one_travel_line() -> void:
	await _look_at(free_tile)
	var labels: Array = _labels("Tile")
	assert_true(labels[0].begins_with("Tile %d,%d" % [free_tile.x, free_tile.y]), labels[0])
	assert_true(labels[0].contains("Ash sand") and labels[0].contains("You") and labels[0].contains(" m"), "tile, ground, owner and height on one line: %s" % labels[0])
	assert_true(labels[1].begins_with("Radiation:"), "the radiation is the second line")
	assert_true(labels[2].begins_with("HQ:"), "then one line of travel times")
	assert_true(labels[2].contains("On foot") and labels[2].contains(" d"))
	for old in ["Owner:", "Height:", "Ground:", "Travel from your HQ:"]:
		assert_false(labels.any(func(l): return l.begins_with(old)), "no %s line any more" % old)


func test_a_building_is_one_row_with_its_cost_on_the_right_and_its_description_on_hover() -> void:
	await _look_at(free_tile)
	var farm: Button = null
	for b in _buttons("Tile"):
		if b.text.strip_edges().ends_with("Farm"):
			farm = b
	assert_not_null(farm)
	assert_eq((farm.get_node("Cost") as Label).text, Game.cost_text(Data.BUILDINGS.farm.cost), "the cost, on the right")
	assert_eq((farm.get_node("Cost") as Label).horizontal_alignment, HORIZONTAL_ALIGNMENT_RIGHT)
	assert_eq(farm.tooltip_text, Data.BUILDINGS.farm.desc, "what it does is on hover")
	assert_false(_labels("Tile").any(func(l): return l.contains(Data.BUILDINGS.farm.desc)), "and not in a paragraph under the button")


func test_a_building_you_cannot_build_yet_is_a_dim_row_that_says_why() -> void:
	await _look_at(free_tile)
	var wall: Button = null
	for b in _buttons("Tile"):
		if b.text.strip_edges().ends_with("Wall"):
			wall = b
	assert_not_null(wall)
	assert_true(wall.disabled)
	assert_true((wall.get_node("Cost") as Label).text.begins_with("Needs upgrade"), "the reason is where the cost was")
	assert_false(_labels("Tile").any(func(l): return l.begins_with("   ")), "no description lines under the buttons")


func test_the_tile_tab_is_much_shorter_than_before() -> void:
	await _look_at(free_tile)
	var height: float = hud.boxes["Tile"].get_combined_minimum_size().y
	assert_lt(height, 900.0, "it was 1,076 px with the old header and descriptions: %d" % int(height))
	assert_lt(_labels("Tile").size(), 12, "it had 24 labels")


func test_a_long_name_and_a_long_reason_take_two_lines_instead_of_overlapping() -> void:
	var b: Button = hud._row_button(hud.boxes["Colony"], "Vehicles: T1 Horse cavalry", "", func(): pass, "Needs Raiding parties")
	assert_true(b.text.contains("\n"), "two lines")
	var short: Button = hud._row_button(hud.boxes["Colony"], "Farm", "5 wood", func(): pass)
	assert_false(short.text.contains("\n"), "a short one stays on one line")
	b.queue_free()
	short.queue_free()


# ---------------------------------------------------------------- the Upgrades tab

func test_upgrades_show_one_row_per_branch_and_dots_for_the_tiers() -> void:
	await _show_tab(1)
	var headers: Array = hud.boxes["Upgrades"].find_children("Branch_*", "Button", true, false)
	assert_eq(headers.size(), ["core"].size() + Data.BRANCHES.size() + 1, "a header for core, each branch and the bridge")
	var rows: Array = _buttons("Upgrades").filter(func(b): return not b.name.begins_with("Branch_") and b.text != "?")
	assert_lt(rows.size(), 16, "about one row a branch, not 36 buttons: %d" % rows.size())
	var core: Button = hud.boxes["Upgrades"].find_child("Branch_core", true, false)
	assert_true(core.text.contains("○"), "dots for the tiers: %s" % core.text)
	assert_true(core.text.begins_with("▾"), "open")
	assert_ne(core.tooltip_text, "")


func test_clicking_a_branch_closes_it_and_clicking_again_opens_it() -> void:
	await _show_tab(1)
	var before: int = _buttons("Upgrades").size()
	var core: Button = hud.boxes["Upgrades"].find_child("Branch_core", true, false)
	core.pressed.emit()
	await wait_frames(3)
	assert_false(hud.open_branches.get("core", true))
	assert_lt(_buttons("Upgrades").size(), before, "its row is gone")
	core = hud.boxes["Upgrades"].find_child("Branch_core", true, false)
	assert_true(core.text.begins_with("▸"), "closed")
	core.pressed.emit()
	await wait_frames(3)
	assert_eq(_buttons("Upgrades").size(), before)


func test_buying_the_next_tier_fills_a_dot_and_shows_the_one_after() -> void:
	await _show_tab(1)
	var core: Button = hud.boxes["Upgrades"].find_child("Branch_core", true, false)
	var dots_before: int = core.text.count("●")
	var row: Button = null
	for b in hud.numbered["Upgrades"]:
		if b.text.begins_with("T1 "):
			row = b
			break
	assert_not_null(row)
	var name: String = row.text.strip_edges()
	row.pressed.emit()
	await wait_frames(3)
	core = hud.boxes["Upgrades"].find_child("Branch_core", true, false)
	assert_eq(core.text.count("●"), dots_before + 1, "a dot filled")
	assert_false(_buttons("Upgrades").any(func(b): return b.text.strip_edges() == name), "the bought one is not offered again")


# ---------------------------------------------------------------- the Colony tab

func test_the_vehicles_are_rows_with_what_they_do_on_hover() -> void:
	await _show_tab(2)
	var rows: Array = _buttons("Colony").filter(func(b): return b.text.contains("(0 out)"))
	assert_eq(rows.size(), Data.VEHICLES.size(), "a row for every vehicle")
	for b in rows:
		assert_true(b.tooltip_text.contains("attack") and b.tooltip_text.contains("upkeep"), b.tooltip_text)
	assert_false(_labels("Colony").any(func(l): return l.contains("upkeep")), "no paragraph per vehicle")


# ---------------------------------------------------------------- the "?"

func test_each_tab_has_a_question_mark_that_shows_and_hides_its_explanations() -> void:
	var cases := [[0, "Tile", "Scouts stay and keep watch"], [1, "Upgrades", "commits you"], [2, "Colony", "Everyone eats"]]
	for case in cases:
		if case[0] == 0:
			await _look_at(free_tile)
		else:
			await _show_tab(case[0])
		var tab: String = case[1]
		assert_false(_labels(tab).any(func(l): return l.contains(case[2])), "%s: hidden at first" % tab)
		var help: Button = null
		for b in _buttons(tab):
			if b.text == "?":
				help = b
		assert_not_null(help, "%s has a ?" % tab)
		assert_null(help.get_node_or_null("KeyCap"), "the ? has no key cap")
		help.pressed.emit()
		await wait_frames(3)
		assert_true(_labels(tab).any(func(l): return l.contains(case[2])), "%s: shown after the ?" % tab)
		for b in _buttons(tab):
			if b.text == "?":
				b.pressed.emit()
		await wait_frames(3)
		assert_false(_labels(tab).any(func(l): return l.contains(case[2])), "%s: hidden again" % tab)
