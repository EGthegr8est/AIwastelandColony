extends "res://tests/framework/test_case.gd"
## The keys of the interface, through the real HUD (docs: "UI: Cleaner Panels, Bigger Buttons, Hotkeys", decisions 11, 12, 13, 15 and 16): the digits 1 to 9 and 0 press the
## open tab's first ten buttons, F, P, O and L build and Z, X and C send scavengers, a hunting party or scouts (by what the picked tile is), Backspace leaves a party's panel, Del demolishes, E, G, M, N, F5, F9 and Esc do the
## global things, key caps show each key, and the Key hints switch turns them off. Keys do nothing over a menu.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")
const Daylight = preload("res://scripts/daylight.gd")
const KeyHints = preload("res://scripts/key_hints.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")

var main: Node2D
var hud: Node
var home: Vector2i
var free_tile: Vector2i   # one of your tiles with nothing on it, sand


func before_each() -> void:
	Sprites.style = Sprites.CLEAN
	KeyHints.enabled = true
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
	free_tile = _own_tile("sand", 0)
	assert_ne(free_tile, Vector2i(-1, -1), "one of your tiles is bare sand")


func after_each() -> void:
	KeyHints.enabled = true
	Sprites.style = 1
	Daylight.enabled = false
	DirAccess.remove_absolute(Music.settings_path)


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


## The nth of your tiles that is bare ground of this kind.
func _own_tile(ground: String, skip: int) -> Vector2i:
	var seen := 0
	for c in Game.owned(Data.PLAYER):
		var t: Dictionary = Game.tile(c)
		if t["t"] == ground and t["b"] == "" and c != home:
			if seen == skip:
				return c
			seen += 1
	return Vector2i(-1, -1)


func _key(keycode: Key, ctrl := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.ctrl_pressed = ctrl
	hud._input(e)


func _look_at(c: Vector2i) -> void:
	Game.select(c)
	Game.changed.emit()
	await wait_frames(3)


func _cap_of(b: Button) -> String:
	var cap := b.get_node_or_null("KeyCap")
	return "" if cap == null else (cap.get_child(0) as Label).text


func _row(text: String) -> Button:
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.text.strip_edges().ends_with(text):
			return b
	return null


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


# ---------------------------------------------------------------- the digits and the caps

func test_the_build_rows_carry_key_caps_priority_letters_where_they_have_them() -> void:
	await _look_at(free_tile)
	var list: Array = hud.numbered["Tile"]
	assert_gt(list.size(), 9, "a bare sand tile has ten buildings or more")
	assert_eq(_cap_of(_row("Farm")), "F", "the farm's cap is its priority letter")
	assert_eq(_cap_of(_row("Hunting lodge")), "L")
	assert_eq(_cap_of(_row("Refinery")), "3", "the third row")
	assert_eq(_cap_of(_row("Wall")), "P", "the wall's letter, though it is locked")
	assert_eq(_cap_of(list[9]), "0", "the tenth button is 0")
	if list.size() > 10:
		assert_true(_cap_of(list[10]) in ["", "O", "F", "P", "L"], "no digit after the tenth")


func test_a_digit_presses_that_button() -> void:
	await _look_at(free_tile)
	_key(KEY_1)
	assert_eq(Game.tile(free_tile)["b"], "farm", "1 is the first button, the Farm")


func test_zero_presses_the_tenth_button() -> void:
	await _look_at(free_tile)
	var tenth: Button = hud.numbered["Tile"][9]
	var spent: Dictionary = Game.res.duplicate()
	_key(KEY_0)
	if tenth.disabled:
		assert_eq(Game.res, spent, "a locked tenth button builds nothing")
	else:
		assert_ne(Game.tile(free_tile)["b"], "", "the tenth button was pressed")


func test_a_locked_row_keeps_its_digit_and_says_why_in_the_log() -> void:
	await _look_at(free_tile)
	var wall := _row("Wall")
	assert_true(wall.disabled)
	var index: int = hud.numbered["Tile"].find(wall)
	_key(KEY_0 + ((index + 1) % 10))
	assert_eq(Game.tile(free_tile)["b"], "", "nothing was built")
	assert_true(_log_has("Wall"), "the log names the wall")
	assert_true(_log_has("Needs upgrade"), "and why")


func test_a_digit_with_no_button_does_nothing() -> void:
	await _look_at(Vector2i(-1, -1))
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	var handled: bool = hud._hotkey(_event(KEY_9))
	assert_false(handled, "the legend has no numbered buttons, so the key is left alone")


func _event(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	return e


func test_the_upgrades_tab_numbers_its_rows_and_not_its_headers() -> void:
	hud.tabs.current_tab = 1
	hud.refresh()
	await wait_frames(3)
	var list: Array = hud.numbered["Upgrades"]
	assert_gt(list.size(), 3)
	for b in list:
		assert_false(b.name.begins_with("Branch_"), "a branch header is not a numbered button")
		assert_eq(b.get_node_or_null("KeyCap") != null, list.find(b) < 10)
	for b in hud.boxes["Upgrades"].find_children("Branch_*", "Button", true, false):
		assert_null(b.get_node_or_null("KeyCap"), "no cap on a header")
	var first: Button = list[0]
	var before: Array = Game.upgrades.duplicate()
	_key(KEY_1)
	assert_true(first.disabled or Game.upgrades.size() == before.size() + 1, "1 bought the first upgrade (or said why not)")


# ---------------------------------------------------------------- the priority letters

func test_f_builds_a_farm_on_the_picked_tile() -> void:
	await _look_at(free_tile)
	_key(KEY_F)
	assert_eq(Game.tile(free_tile)["b"], "farm")


func test_l_builds_a_hunting_lodge() -> void:
	await _look_at(free_tile)
	_key(KEY_L)
	assert_eq(Game.tile(free_tile)["b"], "lodge")


func test_p_builds_a_wall_once_palisades_is_bought_and_says_why_before() -> void:
	await _look_at(free_tile)
	_key(KEY_P)
	assert_eq(Game.tile(free_tile)["b"], "", "no Palisades yet")
	assert_true(_log_has("Wall: Needs upgrade"), "the log says so")
	Game.upgrades.append("f1")
	Game.changed.emit()
	await wait_frames(3)
	_key(KEY_P)
	assert_eq(Game.tile(free_tile)["b"], "wall")


func test_o_builds_a_road_on_free_land_beside_yours() -> void:
	var c := World.claimable_tile()
	assert_ne(c, Vector2i(-1, -1))
	await _look_at(c)
	_key(KEY_O)
	assert_eq(Game.tile(c)["b"], "road")


func test_a_letter_that_cannot_build_here_says_why() -> void:
	var rock := _own_tile("sand", 1)
	Game.tile(rock)["t"] = "rock"
	await _look_at(rock)
	_key(KEY_F)
	assert_eq(Game.tile(rock)["b"], "")
	assert_true(_log_has("Farm: needs"), "a farm needs sand or scrub: %s" % str(Game.log_lines.slice(-2)))
	assert_true(_log_has("Ash sand"))


func test_a_build_letter_with_no_tile_picked_says_so() -> void:
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	_key(KEY_F)
	assert_true(_log_has("Pick a tile to build on first"))


func _ruin() -> Vector2i:
	var ruin := World.find_tile(func(c, t): return t["t"] == "ruins" and t["r"] != "picked")
	Game.reveal(Data.PLAYER, ruin, 2)
	return ruin


func test_z_sends_scavengers_on_foot_to_the_picked_ruin() -> void:
	var ruin := _ruin()
	await _look_at(ruin)
	assert_eq(_cap_of(_row("Scavenge on foot")), "Z", "the row's cap is its letter")
	var before := Units.units.size()
	_key(KEY_Z)
	assert_eq(Units.units.size(), before + 1, "a party set out")
	assert_eq(Units.units[-1].job, "scav")
	assert_eq(Units.units[-1].mover, "foot")
	assert_eq(Units.units[-1].target, ruin)


func test_x_and_c_say_why_without_a_horse_or_a_war_rig_and_send_with_them() -> void:
	var ruin := _ruin()
	await _look_at(ruin)
	_key(KEY_X)
	assert_true(_log_has("Scavengers on horseback"), "no horse yet: %s" % str(Game.log_lines.slice(-2)))
	_key(KEY_C)
	assert_true(_log_has("Scavengers by war rig"))
	var before := Units.units.size()
	Game.vehicles["horse"] = 2
	Game.vehicles["car"] = 2
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(_cap_of(_row("Scavenge on horseback")), "X")
	_key(KEY_X)
	assert_eq(Units.units.size(), before + 1)
	assert_eq(Units.units[-1].mover, "horse")


func test_z_on_ground_that_is_yours_with_nothing_on_it_says_so() -> void:
	await _look_at(free_tile)
	_key(KEY_Z)
	assert_true(_log_has("Pick a ruin, a site, a crater, an animal or ground outside your land"))
	assert_eq(Units.units.size(), 0, "nothing set out")


func test_z_on_picked_ruins_says_so_and_sends_nothing() -> void:
	var ruin := _ruin()
	Game.tile(ruin)["r"] = "picked"
	await _look_at(ruin)
	_key(KEY_Z)
	assert_true(_log_has("Picked clean"))
	assert_eq(Units.units.size(), 0, "nobody is sent to ruins with nothing left")


## A bare, explored tile that is nobody's, which a scouting party on foot can walk to.
func _outside_tile() -> Vector2i:
	for r in range(4, 14):
		for dx in range(-r, r + 1):
			for dy in [-r, r]:
				var c := home + Vector2i(dx, dy)
				if Game.in_bounds(c) and Game.tile(c)["o"] == Data.NONE and Game.tile(c)["b"] == "" and Game.tile(c)["t"] == "sand" and Units.send_status("scout", "foot", c) == "":
					Game.reveal(Data.PLAYER, c, 1)
					return c
	return Vector2i(-1, -1)


func test_z_sends_a_hunting_party_to_the_animal_on_the_picked_tile() -> void:
	var deer: Dictionary = Units._add_animal("deer", free_tile)
	Game.update_fog()
	await _look_at(free_tile)
	assert_eq(_cap_of(_row("Send hunting party on foot")), "Z", "the hunting party's row wears the letter")
	assert_eq(_cap_of(_row("Hunt with scavengers on foot")), "1", "scavengers hunting keep their digit, not the letter")
	var troops := Game.troops
	_key(KEY_Z)
	assert_eq(Units.units.size(), 1)
	var party: Dictionary = Units.units[-1]
	assert_eq(party.job, "hunters")
	assert_eq(party.mover, "foot")
	assert_eq(party.dest, deer.id, "they go after that animal")
	assert_eq(Game.troops, troops - Data.EXPEDITIONS["hunters"].crew, "a hunting party is troops")


func test_the_hunting_keys_say_why_without_troops_or_a_horse() -> void:
	Units._add_animal("deer", free_tile)
	Game.update_fog()
	await _look_at(free_tile)
	Game.troops = 0
	_key(KEY_Z)
	assert_true(_log_has("A hunting party on foot: Need"), "no troops: %s" % str(Game.log_lines.slice(-2)))
	_key(KEY_X)
	assert_true(_log_has("A hunting party on horseback"))
	assert_eq(Units.units.size(), 0)


func test_z_sends_scouts_to_ground_outside_your_land() -> void:
	var out := _outside_tile()
	assert_ne(out, Vector2i(-1, -1), "a bare tile beside your land to scout")
	await _look_at(out)
	assert_eq(_cap_of(_row("Send scouts on foot")), "Z", "the scouting row wears the letter")
	_key(KEY_Z)
	assert_eq(Units.units.size(), 1)
	var party: Dictionary = Units.units[-1]
	assert_eq(party.job, "scout")
	assert_eq(party.mover, "foot")
	assert_eq(party.target, out)


func test_the_scouting_keys_say_why_without_a_horse() -> void:
	var out := _outside_tile()
	await _look_at(out)
	_key(KEY_X)
	assert_true(_log_has("Scouts on horseback"), "no horse yet: %s" % str(Game.log_lines.slice(-2)))
	assert_eq(Units.units.size(), 0)


func test_an_unexplored_tile_is_scouted_by_the_keys_too() -> void:
	var far := World.find_tile(func(c, t): return not Game.knows_tile(Data.PLAYER, c))
	assert_eq(hud._send_plan(far).job, "scout")


func test_ruins_still_send_scavengers_not_scouts() -> void:
	var ruin := _ruin()
	assert_eq(hud._send_plan(ruin).job, "scav")
	assert_eq(hud._send_plan(ruin).target, ruin)


func test_z_sends_to_a_site_from_any_of_its_four_tiles() -> void:
	var site := World.find_tile(func(c, t): return t["b"].begins_with("poi_") and Game.poi_anchor(c) == c)
	Game.reveal(Data.PLAYER, site, 3)
	await _look_at(site + Vector2i(1, 1))
	_key(KEY_Z)
	assert_eq(Units.units[-1].target, site, "the party goes to the site's top left tile")


# ---------------------------------------------------------------- Backspace and Del

func test_backspace_leaves_without_searching_and_del_demolishes() -> void:
	await _look_at(free_tile)
	_key(KEY_F)
	await wait_frames(3)
	await _look_at(free_tile)
	assert_eq(Game.tile(free_tile)["b"], "farm")
	var demolish := _row("Demolish")
	assert_not_null(demolish)
	assert_eq(_cap_of(demolish), "Del")
	_key(KEY_DELETE)
	assert_eq(Game.tile(free_tile)["b"], "", "Del demolished the farm")
	# a party at a site: Backspace is "Leave without searching"
	var site := World.find_tile(func(c, t): return t["b"].begins_with("poi_") and Game.poi_anchor(c) == c)
	Game.reveal(Data.PLAYER, site, 3)
	Units.dice = ForcedDice.new([12], [2])
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", site, site)
	u.home = home
	u.crew = 3
	u.survivors = Units._make_crew(3)
	Units.units.append(u)
	Units._begin_visit(u)
	await _look_at(site)
	var leave: Button = null
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.has_meta("back"):
			leave = b
	assert_not_null(leave, "the panel has a leave button")
	assert_eq(_cap_of(leave), "Bksp")
	assert_ne(u.visit.stage, "done")
	_key(KEY_BACKSPACE)
	assert_eq(u.visit.stage, "done", "Backspace left without searching: the visit is over")


func test_backspace_and_del_do_nothing_when_there_is_nothing_to_leave_or_demolish() -> void:
	await _look_at(free_tile)
	assert_false(hud._hotkey(_event(KEY_BACKSPACE)))
	assert_false(hud._hotkey(_event(KEY_DELETE)))


# ---------------------------------------------------------------- the global keys

func test_e_ends_the_season() -> void:
	Daylight.enabled = true
	var season := Game.season
	_key(KEY_E)
	assert_eq(Game.season, season + 1)
	assert_true(hud.end_button.is_night, "and the window sets into the night, as if it had been clicked")


func test_m_switches_the_map_between_pixel_art_and_glyphs() -> void:
	_key(KEY_M)
	assert_eq(Sprites.state(), 0)
	assert_true(hud.sonar_tablet.is_on)
	await wait_seconds(1.6)
	_key(KEY_M)
	assert_eq(Sprites.state(), Sprites.CLEAN)


func test_g_is_free_now_the_tablet_is_on_m() -> void:
	var state: int = Sprites.state()
	var view: int = Game.view
	_key(KEY_G)
	assert_eq(Sprites.state(), state, "G no longer flips the map art")
	assert_eq(Game.view, view)
	assert_false(hud.sonar_tablet.is_on)


func test_n_flips_the_night() -> void:
	Daylight.enabled = false
	_key(KEY_N)
	assert_true(Daylight.enabled)
	_key(KEY_N)
	assert_false(Daylight.enabled)


func test_f5_and_f9_open_the_save_and_load_menus() -> void:
	_key(KEY_F5)
	assert_true(hud.menu.visible)
	assert_true(_menu_text().contains("slot1"), "the save menu lists the slots")
	hud._close_menu()
	_key(KEY_F9)
	assert_true(hud.menu.visible)
	assert_true(_menu_text().contains("slot1"))
	hud._close_menu()


func _menu_text() -> String:
	var text := ""
	for b in hud.menu_box.find_children("*", "Button", true, false):
		text += b.text + "\n"
	return text


func test_esc_lets_go_of_a_party_then_opens_the_menu_then_resumes() -> void:
	var u: Dictionary = Units._make_unit("scout", Data.PLAYER, "foot", home, home)
	u.crew = 2
	u.survivors = Units._make_crew(2)
	u.stage = "station"
	Units.units.append(u)
	Game.pick_scout(u.id)
	assert_eq(Game.selected_scout, u.id)
	_key(KEY_ESCAPE)
	assert_eq(Game.selected_scout, -1, "the first Esc lets go of the party")
	assert_false(hud.title_screen.visible or hud.menu.visible)
	_key(KEY_ESCAPE)
	assert_true(hud.title_screen.visible or hud.menu.visible, "the next one opens the menu")
	_key(KEY_ESCAPE)
	assert_false(hud.title_screen.visible or hud.menu.visible, "and the next resumes the game")
	assert_true(Game.in_game)


# ---------------------------------------------------------------- the tabs and the key sheet (decision 14)

func _key_shifted(keycode: Key) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.shift_pressed = true
	hud._input(e)


func test_f1_to_f4_open_the_tabs() -> void:
	for i in 4:
		_key([KEY_F1, KEY_F2, KEY_F3, KEY_F4][i])
		assert_eq(hud.tabs.current_tab, i, "F%d" % (i + 1))
		assert_eq(hud.tabs.get_tab_title(hud.tabs.current_tab), ["Tile", "Upgrades", "Colony", "Diplomacy"][i])


func test_tab_and_shift_tab_cycle_the_tabs_and_wrap() -> void:
	_key(KEY_F1)
	_key(KEY_TAB)
	assert_eq(hud.tabs.current_tab, 1)
	_key(KEY_TAB)
	_key(KEY_TAB)
	assert_eq(hud.tabs.current_tab, 3)
	_key(KEY_TAB)
	assert_eq(hud.tabs.current_tab, 0, "after the last tab comes the first")
	_key_shifted(KEY_TAB)
	assert_eq(hud.tabs.current_tab, 3, "Shift+Tab from the first goes to the last")
	_key_shifted(KEY_TAB)
	assert_eq(hud.tabs.current_tab, 2)


func test_the_tabs_say_their_keys_on_hover() -> void:
	assert_true(hud.tabs.get_tab_tooltip(2).contains("F3"))


func test_the_question_mark_opens_the_sheet_and_closes_it() -> void:
	assert_false(hud.key_sheet.visible)
	_key(KEY_QUESTION)
	assert_true(hud.key_sheet.visible, "?")
	_key(KEY_QUESTION)
	assert_false(hud.key_sheet.visible, "? again closes it")
	_key_shifted(KEY_SLASH)
	assert_true(hud.key_sheet.visible, "Shift and the slash key is a ? on most keyboards")
	_key(KEY_ESCAPE)
	assert_false(hud.key_sheet.visible, "Esc closes it")
	assert_false(hud.menu.visible or hud.title_screen.visible, "and does not open the menu on top of it")


func test_the_sheet_lists_every_key_the_game_answers() -> void:
	var texts := []
	for l in hud.key_sheet.find_children("*", "Label", true, false):
		texts.append(l.text)
	for key in ["E", "Enter", "Space", "R", "M", "N", "F5  F9", "Esc", "F11", "W A S D  arrows", "F1 - F4", "Tab", "1 - 9, 0", "Backspace", "Del", "F  P  O  L", "Z  X  C", "?"]:
		assert_true(texts.has(key), "the sheet shows %s" % key)
	assert_false(texts.has("T"), "there is no Walk key any more")


func test_no_other_key_answers_while_the_sheet_is_up() -> void:
	_key(KEY_QUESTION)
	var season := Game.season
	_key(KEY_E)
	assert_eq(Game.season, season, "E does not end the season over the sheet")
	_key(KEY_F2)
	assert_eq(hud.tabs.current_tab, 0, "F2 does not change the tab")
	_key(KEY_QUESTION)
	_key(KEY_F2)
	assert_eq(hud.tabs.current_tab, 1, "once it is closed the keys work again")


func test_a_click_closes_the_sheet() -> void:
	_key(KEY_QUESTION)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	hud.key_sheet.gui_input.emit(click)
	assert_false(hud.key_sheet.visible)


func test_the_legend_has_an_all_the_keys_button_that_opens_the_sheet() -> void:
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	var b := _row("All the keys (?)")
	assert_not_null(b, "the legend has the button")
	b.pressed.emit()
	assert_true(hud.key_sheet.visible)
	_key(KEY_QUESTION)


func test_the_sheet_does_not_open_over_a_menu_or_with_ctrl_held() -> void:
	_key(KEY_QUESTION, true)
	assert_false(hud.key_sheet.visible, "Ctrl and ? does nothing")
	hud.show_main_menu()
	_key(KEY_QUESTION)
	assert_false(hud.key_sheet.visible, "no sheet behind the title")
	hud._close_menu()


# ---------------------------------------------------------------- the guards

func test_keys_do_nothing_over_a_menu() -> void:
	hud.show_main_menu()
	var season := Game.season
	_key(KEY_E)
	assert_eq(Game.season, season, "E does not end the season behind the title")
	_key(KEY_N)
	assert_false(Daylight.enabled)
	hud._close_menu()


func test_keys_with_ctrl_held_do_nothing() -> void:
	var season := Game.season
	_key(KEY_E, true)
	assert_eq(Game.season, season)
	await _look_at(free_tile)
	_key(KEY_F, true)
	assert_eq(Game.tile(free_tile)["b"], "")


func test_keys_do_nothing_over_the_ending() -> void:
	hud.ending_screen.visible = true
	var season := Game.season
	_key(KEY_E)
	assert_eq(Game.season, season)
	hud.ending_screen.visible = false


# ---------------------------------------------------------------- key hints

func test_the_top_bar_buttons_carry_their_keys() -> void:
	assert_eq(_cap_of(hud.save_button), "F5")
	assert_eq(_cap_of(hud.load_button), "F9")
	assert_eq(_cap_of(hud.menu_button), "Esc")
	assert_eq(hud.loose_caps.size(), 3, "caps stand on the meter (R), on the tablet (M) and beside the END SEASON window (E)")
	assert_eq((hud.loose_caps[0].get_child(0) as Label).text, "R")
	assert_eq((hud.loose_caps[1].get_child(0) as Label).text, "M")
	assert_eq((hud.loose_caps[2].get_child(0) as Label).text, "E")
	assert_eq(hud.loose_caps[2].get_parent().get_child(hud.loose_caps[2].get_index() + 1), hud.end_button, "the E cap is right beside the window")


func test_the_key_hints_switch_turns_the_caps_off_and_on_and_is_remembered() -> void:
	await _look_at(free_tile)
	assert_ne(_cap_of(_row("Farm")), "")
	KeyHints.set_enabled(false)
	hud._apply_key_hints()
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(_cap_of(_row("Farm")), "", "no cap on the farm row")
	assert_eq(_cap_of(hud.save_button), "", "none on the top bar")
	for cap in hud.loose_caps:
		assert_false(cap.visible)
	KeyHints.enabled = true
	KeyHints.load_setting()
	assert_false(KeyHints.enabled, "it was saved")
	KeyHints.set_enabled(true)
	hud._apply_key_hints()
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(_cap_of(hud.save_button), "F5")
	for cap in hud.loose_caps:
		assert_true(cap.visible)
	assert_eq(_cap_of(_row("Farm")), "F")


func test_the_keys_still_work_with_the_hints_off() -> void:
	KeyHints.set_enabled(false)
	hud._apply_key_hints()
	Game.changed.emit()
	await _look_at(free_tile)
	_key(KEY_F)
	assert_eq(Game.tile(free_tile)["b"], "farm")


func test_the_legend_and_the_menus_have_the_switch() -> void:
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	var found := false
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.text.begins_with("Key hints:"):
			found = true
			var was := KeyHints.enabled
			b.pressed.emit()
			assert_eq(KeyHints.enabled, not was)
			assert_eq(b.text, "Key hints: " + ("On" if KeyHints.enabled else "Off"))
	assert_true(found, "a Key hints button in the legend")
	KeyHints.set_enabled(true)
	hud.show_load_menu()
	assert_true(_menu_text().contains("Key hints:"), "and in the load menu")
	hud._close_menu()


func test_the_legend_switches_are_not_numbered() -> void:
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(hud.numbered["Tile"].size(), 0, "nothing to press by number while nothing is picked")
