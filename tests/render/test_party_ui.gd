extends "res://tests/framework/test_case.gd"
## Your parties on the real HUD: the numbered party bar along the bottom of the map (click a button, or Shift and its number, or its number on the
## numpad), the keys that go with it ([ and ] cycle, G walks on, B recalls, Q forms a party), a party's card showing the days it has left and a
## Continue button, and the Colony tab's list of every survivor (and the fallen) with the buttons that pick who goes in the next party and form it.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var main: Node2D
var hud: Node
var hq: Vector2i
var near: Vector2i
var far: Vector2i


func before_each() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	for b in main.find_children("*", "Button", true, false):
		if b.text == "New colony":
			b.pressed.emit()
	await wait_frames(2)
	for b in main.find_children("*", "Button", true, false):
		if b.text == "Choose" and b.is_visible_in_tree():
			b.pressed.emit()
			break
	await wait_frames(3)
	SeasonReplay.mode = "off"   # the walks are not what is being looked at here
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	Units.units = []
	hq = Game.home(Data.PLAYER)
	Game.pop = 30
	Game.res["grain"] = 300
	near = World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 8 and c.distance_to(hq) < 14 and Game.poi_kind(c) == "" \
		and not Game.route("foot", hq, c).is_empty())
	far = World.find_tile(func(c, t): return t["t"] != "water" and c.distance_to(hq) > 30 and c.distance_to(hq) < 45 \
		and not Game.route("foot", hq, c).is_empty())
	assert_ne(near, Vector2i(-1, -1))
	assert_ne(far, Vector2i(-1, -1))


func after_each() -> void:
	SeasonReplay.mode = "off"


func _key(keycode: Key, shift := false) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = true
	e.shift_pressed = shift
	hud._input(e)


func _show_tab(tab_name: String) -> void:
	for i in hud.tabs.get_tab_count():
		if hud.tabs.get_tab_title(i) == tab_name:
			hud.tabs.current_tab = i
	Game.changed.emit()
	await wait_frames(3)


func _labels(box: Node) -> String:
	var text := ""
	for l in box.find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


func _button_texts(box: Node) -> Array:
	return box.find_children("*", "Button", true, false).map(func(b): return b.text)


func _press_in(box: Node, start: String) -> void:
	for b in box.find_children("*", "Button", true, false):
		if b.text.begins_with(start) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % start)


func _log_has(text: String) -> bool:
	return Game.log_lines.any(func(l): return l.contains(text))


## Forms `n` parties at the HQ and sends the ones after the first off in different directions.
func _parties(n: int) -> Array:
	var out := []
	for i in n:
		var p := Units.form_party("foot")
		out.append(p)
	Game.changed.emit()
	await wait_frames(3)
	return out


# ---------------------------------------------------------------- the party bar

func test_the_party_bar_has_a_numbered_button_for_each_party_and_none_without_parties() -> void:
	assert_eq(hud.parties_bar.get_child_count(), 0, "no parties, no buttons")
	await _parties(3)
	assert_true(hud.parties_bar.is_visible_in_tree())
	assert_eq(_button_texts(hud.parties_bar), ["1", "2", "3"])
	Units.units = []
	Game.changed.emit()
	await wait_frames(3)
	assert_eq(hud.parties_bar.get_child_count(), 0, "and they go with the parties")


func test_clicking_a_party_button_picks_that_party_and_shows_it() -> void:
	var ps: Array = await _parties(2)
	Units.order_scouts(ps[1].id, near)
	Game.changed.emit()
	await wait_frames(3)
	_press_in(hud.parties_bar, "2")
	assert_eq(Game.selected_scout, ps[1].id)
	assert_eq(Game.selected, ps[1].pos)
	await wait_frames(3)
	assert_true(hud.party_panel.visible, "its card is up")


func test_shift_and_a_digit_or_the_numpad_pick_a_party_and_a_plain_digit_does_not() -> void:
	var ps: Array = await _parties(3)
	Units.order_scouts(ps[1].id, near)
	Units.order_scouts(ps[2].id, near2())
	await wait_frames(2)
	_key(KEY_2, true)
	assert_eq(Game.selected_scout, ps[1].id, "Shift+2")
	_key(KEY_KP_3)
	assert_eq(Game.selected_scout, ps[2].id, "numpad 3")
	Game.selected_scout = ps[0].id
	_key(KEY_2)
	assert_eq(Game.selected_scout, ps[0].id, "a plain 2 presses the panel's second button, not a party")
	Game.log_lines = []
	_key(KEY_9, true)
	assert_true(_log_has("There is no Scavenger Party 9."))
	_key(KEY_0, true)
	assert_true(_log_has("There is no Scavenger Party 10."), "0 is the tenth")


func near2() -> Vector2i:
	return World.find_tile(func(c, t): return t["t"] == "sand" and c.distance_to(hq) > 8 and c.distance_to(hq) < 14 and Game.poi_kind(c) == "" \
		and not Game.route("foot", hq, c).is_empty() and c.distance_to(near) > 6)


func test_the_brackets_go_through_the_parties_by_number() -> void:
	var ps: Array = await _parties(3)
	Units.order_scouts(ps[1].id, near)
	Units.order_scouts(ps[2].id, near2())
	Game.selected_scout = -1
	_key(KEY_BRACKETRIGHT)
	assert_eq(Game.selected_scout, ps[0].id, "the first when none is picked")
	_key(KEY_BRACKETRIGHT)
	assert_eq(Game.selected_scout, ps[1].id)
	_key(KEY_BRACKETRIGHT)
	_key(KEY_BRACKETRIGHT)
	assert_eq(Game.selected_scout, ps[0].id, "and round again")
	_key(KEY_BRACKETLEFT)
	assert_eq(Game.selected_scout, ps[2].id, "backwards")


func test_g_walks_the_picked_party_on_and_says_why_it_cannot() -> void:
	Game.log_lines = []
	_key(KEY_G)
	assert_true(_log_has("Pick a Scavenger Party first"))
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	Game.pick_scout(u.id)
	u.move_left = 0.0
	_key(KEY_G)
	assert_true(_log_has("Scavenger Party 1: No days left this turn."))
	u.move_left = float(Data.SEASON_DAYS)
	var before: Vector2i = u.pos
	_key(KEY_G)
	assert_ne(u.pos, before, "it walked on")


func test_b_recalls_the_picked_party() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	Game.pick_scout(u.id)
	_key(KEY_B)
	assert_eq(u.stage, "back")
	Game.log_lines = []
	_key(KEY_B)
	assert_true(_log_has("already on its way home"))


func test_q_forms_a_party_on_foot_and_picks_it() -> void:
	_key(KEY_Q)
	assert_eq(Units.units.size(), 1)
	var u: Dictionary = Units.units[0]
	assert_eq(u.pos, hq)
	assert_eq(u.stage, "station")
	assert_eq(Game.selected_scout, u.id)
	assert_eq(Game.selected, hq)
	Game.pop = 4
	Game.log_lines = []
	_key(KEY_Q)
	assert_true(_log_has("Form a party: Need 3 colonists to spare."))
	assert_eq(Units.units.size(), 1)


func test_the_key_sheet_lists_the_party_keys() -> void:
	hud.key_sheet.visible = true
	await wait_frames(2)
	var text := _labels(hud.key_sheet)
	assert_has(text, "Pick Scavenger Party")
	assert_has(text, "Form a party at your HQ")
	assert_has(text, "walk on, recall")


# ---------------------------------------------------------------- the party's card

func test_a_party_card_shows_its_number_its_days_and_a_continue_button() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	Game.select(u.pos)
	Game.pick_scout(u.id)
	Game.changed.emit()
	await wait_frames(3)
	var text := _labels(hud.party_row)
	assert_has(text, "Scavenger Party 1")
	assert_has(text, "left this turn")
	assert_has(_button_texts(hud.party_row), "Continue", "its orders are not finished")
	u.move_left = 0.0
	Game.changed.emit()
	await wait_frames(3)
	assert_not_has(_button_texts(hud.party_row), "Continue", "no days left: nothing to continue")
	u.move_left = float(Data.SEASON_DAYS)
	Game.changed.emit()
	await wait_frames(3)
	_press_in(hud.party_row, "Continue")
	assert_lt(u.move_left, float(Data.SEASON_DAYS), "the button walked it on")


# ---------------------------------------------------------------- the Colony tab

func test_the_colony_tab_lists_every_survivor_and_the_fallen() -> void:
	Game.lose_home(2, "starved")
	await _show_tab("Colony")
	var box: Node = hud.boxes["Colony"]
	var text := _labels(box)
	assert_has(text, "== SURVIVORS (%d) ==" % Game.living_survivors().size())
	for s in Game.living_survivors():
		assert_has(text, "%s, %d" % [s.name, s.age])
	assert_has(text, "== FALLEN (2) ==")
	for s in Game.fallen_survivors():
		assert_has(text, "† %s, %d: starved (%s)" % [s.name, s.age, Game.season_text(Game.season)])


func test_a_survivor_out_in_a_party_says_which() -> void:
	var u := Units.form_party("foot")
	await _show_tab("Colony")
	var text := _labels(hud.boxes["Colony"])
	assert_has(text, "in Scavenger Party 1")
	assert_has(text, "at home")
	assert_eq(u.number, 1)


func test_picking_survivors_for_the_next_party_and_forming_it() -> void:
	await _show_tab("Colony")
	var box: Node = hud.boxes["Colony"]
	var a: Dictionary = Game.home_survivors()[3]
	var b: Dictionary = Game.home_survivors()[5]
	var picks: Array = box.find_children("*", "Button", true, false).filter(func(x): return x.text == "Pick")
	picks[3].pressed.emit()
	await wait_frames(3)
	picks = box.find_children("*", "Button", true, false).filter(func(x): return x.text == "Pick")
	assert_eq(hud.draft, [a.sid])
	assert_has(_button_texts(box), "Picked")
	var all := Game.home_survivors()
	hud._toggle_draft(b.sid)
	assert_eq(hud.draft, [a.sid, b.sid])
	hud._toggle_draft(a.sid)
	assert_eq(hud.draft, [b.sid], "a second press leaves them out again")
	hud._toggle_draft(a.sid)
	await _show_tab("Colony")
	_press_in(box, "Form a party on foot")
	assert_eq(Units.units.size(), 1)
	assert_eq(Units.units[0].survivors.map(func(s): return s.sid), [b.sid, a.sid], "just the two picked")
	assert_eq(hud.draft, [], "and the pick starts again")
	assert_eq(all.size(), Game.home_survivors().size() + 2)


func test_no_more_than_a_party_takes_can_be_picked() -> void:
	var sids: Array = Game.home_survivors().slice(0, 4).map(func(s): return s.sid)
	for i in 3:
		hud._toggle_draft(sids[i])
	Game.log_lines = []
	hud._toggle_draft(sids[3])
	assert_eq(hud.draft.size(), 3)
	assert_true(_log_has("A party takes at most 3 survivors."))


func test_the_survivor_buttons_take_no_digit_key_so_the_other_buttons_keep_theirs() -> void:
	await _show_tab("Colony")
	var numbered: Array = hud.numbered["Colony"]
	assert_false(numbered.is_empty())
	assert_true(numbered[0].text.begins_with("Train troop"), "1 still trains a troop")
	for b in numbered:
		assert_ne(b.text, "Pick")
		assert_false(b.text.begins_with("Form a party"))


func test_a_party_standing_on_the_picked_tile_offers_to_stop_there_not_to_be_sent_there() -> void:
	Units.send("scout", "foot", far)
	var u: Dictionary = Units.units[-1]
	Game.select(u.pos)
	Game.changed.emit()
	await wait_frames(3)
	var texts: Array = _button_texts(hud.boxes["Tile"])
	assert_true(texts.any(func(t): return t.begins_with("Stop Scavenger Party 1 here")), "keep watch where it stands")
	assert_false(texts.any(func(t): return t.begins_with("Send Scavenger Party 1 here")))


func test_the_pick_forgets_people_who_left_and_starts_again_with_a_new_game() -> void:
	var a: Dictionary = Game.home_survivors()[2]
	var b: Dictionary = Game.home_survivors()[4]
	hud._toggle_draft(a.sid)
	hud._toggle_draft(b.sid)
	assert_eq(hud.draft, [a.sid, b.sid])
	b.state = "away"   # somebody else took them
	hud._clean_draft()
	assert_eq(hud.draft, [a.sid], "only people at home can be picked")
	Game.map_version += 1   # a new game or a load
	hud._clean_draft()
	assert_eq(hud.draft, [], "a new game or a load starts the pick again")
