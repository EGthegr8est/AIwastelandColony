extends "res://tests/framework/test_case.gd"
## The screen after "New colony": three random leaders side by side, each a face, a name, the class's buffs, two perks and a
## flaw; a click picks one; Reroll draws new people; and once the colony is running its leader is in the colony panel with
## every perk and the flaw and what they do.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")

var main: Node2D
var hud: Node


func before_each() -> void:
	seed(11)
	Leaders.offered = []
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	_press("New colony")
	await wait_frames(3)


func after_each() -> void:
	Leaders.offered = []


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


## Looks at one of the side panel's tabs (only the tab being looked at is kept up to date).
func _show_tab(tab_name: String) -> void:
	for i in hud.tabs.get_tab_count():
		if hud.tabs.get_tab_title(i) == tab_name:
			hud.tabs.current_tab = i
	await wait_frames(2)


func _cards() -> Array:
	return hud.menu_box.find_children("*", "PanelContainer", true, false).filter(func(p): return p.has_meta("leader_card"))


func _texts(node: Node) -> String:
	var text := ""
	for l in node.find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


func _click(control: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	control.gui_input.emit(e)


func test_three_cards_stand_side_by_side_inside_the_window() -> void:
	var cards := _cards()
	assert_eq(cards.size(), 3)
	for i in 3:
		assert_true(Rect2(0, 0, 1600, 900).encloses(cards[i].get_global_rect()), "card %d fits the window: %s" % [i, cards[i].get_global_rect()])
	assert_lt(cards[0].global_position.x, cards[1].global_position.x)
	assert_lt(cards[1].global_position.x, cards[2].global_position.x)
	assert_eq(cards[0].global_position.y, cards[1].global_position.y, "in a row")
	assert_eq(cards[1].global_position.y, cards[2].global_position.y)
	assert_lt(cards[0].get_global_rect().end.x, cards[1].global_position.x + 1.0, "they do not overlap")


func test_each_card_shows_the_leaders_face_name_class_buffs_perks_and_flaw() -> void:
	var cards := _cards()
	var offered := Leaders.offer()
	for i in 3:
		var leader: Dictionary = offered[i]
		var text := _texts(cards[i])
		assert_has(text, leader.name)
		var cls: Dictionary = Data.LEADERS[leader["class"]]
		assert_has(text, cls.name)
		for buff in cls.buffs:
			assert_has(text, buff)
		for line in Leaders.quirk_lines(leader):
			assert_has(text, "%s %s: %s" % ["+" if line.kind == "perk" else "-", line.name, line.text])
		var faces: Array = cards[i].find_children("*", "TextureRect", true, false)
		assert_eq(faces.size(), 1)
		assert_eq(faces[0].texture.get_size(), Vector2(480, 480), "their picture")
		assert_eq(faces[0].texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp pixels")
		assert_gt(faces[0].size.x, 200.0, "big enough to see")
	assert_eq(offered.map(func(l): return l["class"]), ["raider", "builder", "trader"])


func test_every_card_has_a_choose_button_and_there_is_a_reroll() -> void:
	var chooses: Array = hud.menu_box.find_children("*", "Button", true, false).filter(func(b): return b.text == "Choose")
	assert_eq(chooses.size(), 3)
	var texts: Array = hud.menu_box.find_children("*", "Button", true, false).map(func(b): return b.text)
	assert_has(texts, "Reroll leaders")
	assert_has(texts, "Back")


func test_clicking_anywhere_on_a_card_starts_a_colony_led_by_that_person() -> void:
	var offered := Leaders.offer().duplicate(true)
	_click(_cards()[1])
	await wait_frames(3)
	assert_true(Game.in_game)
	assert_eq(Game.leader, "builder")
	assert_eq(Game.leader_info.name, offered[1].name)
	assert_eq(Game.leader_info.perks, offered[1].perks)
	assert_eq(Game.leader_info.flaw, offered[1].flaw)
	assert_eq(Game.leader_info.image, offered[1].image)
	assert_false(hud.menu.visible, "the menu closed")


func test_the_choose_button_also_picks_that_leader() -> void:
	var offered := Leaders.offer().duplicate(true)
	var chooses: Array = hud.menu_box.find_children("*", "Button", true, false).filter(func(b): return b.text == "Choose")
	chooses[2].pressed.emit()
	await wait_frames(3)
	assert_eq(Game.leader, "trader")
	assert_eq(Game.leader_info.name, offered[2].name)


func test_reroll_draws_three_new_leaders_and_they_stay_until_the_next_reroll() -> void:
	var before: Array = Leaders.offer().map(func(l): return l.name)
	_press("Reroll leaders")
	await wait_frames(3)
	assert_eq(_cards().size(), 3)
	var after: Array = Leaders.offer().map(func(l): return l.name)
	assert_ne(before, after)
	assert_has(_texts(_cards()[0]), after[0])
	_press("Back")
	await wait_frames(2)
	_press("New colony")
	await wait_frames(3)
	assert_has(_texts(_cards()[0]), after[0], "going back and coming again keeps them")


func test_the_colony_panel_shows_the_leaders_face_and_what_every_perk_and_the_flaw_do() -> void:
	var leader: Dictionary = Leaders.offer()[0].duplicate(true)
	_click(_cards()[0])
	await wait_frames(4)
	await _show_tab("Colony")
	var box: Control = hud.boxes["Colony"]
	var text := _texts(box)
	assert_has(text, leader.name)
	for line in Leaders.quirk_lines(leader):
		assert_has(text, "%s %s: %s" % ["+" if line.kind == "perk" else "-", line.name, line.text])
	var faces: Array = box.find_children("*", "TextureRect", true, false)
	assert_eq(faces.size(), 1)
	assert_eq(faces[0].texture.get_size(), Vector2(48, 48), "the small picture")
	assert_eq(faces[0].custom_minimum_size, Vector2(192, 192))
	assert_eq(faces[0].texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST)
	var top := ""
	for l in main.find_children("*", "RichTextLabel", true, false):
		top += l.text
	assert_has(top, Leaders.label(Game.leader_info), "the top bar names the leader")


func test_the_effects_listed_are_the_live_ones_after_a_change() -> void:
	Game.new_game("raider", {"name": "General Test Case", "perks": ["haggler", "sharp_nose"], "flaw": "short_sight", "image": "raider_3"})
	await wait_frames(4)
	await _show_tab("Colony")
	var text := _texts(hud.boxes["Colony"])
	assert_has(text, "General Test Case")
	assert_has(text, "+ Haggler: Market sales pay 25% more gold, purchases cost 20% less.")
	assert_has(text, "- Short sight: Scouting parties see 1 tile less.")
	assert_has(text, "Raider: Attack x1.25, Warfare upgrades 25% off")


func test_a_colony_with_no_named_leader_just_shows_its_class() -> void:
	Game.new_game("trader")
	await wait_frames(4)
	await _show_tab("Colony")
	var box: Control = hud.boxes["Colony"]
	assert_eq(box.find_children("*", "TextureRect", true, false).size(), 0)
	assert_has(_texts(box), "Trader: 2 caravan slots, Commerce upgrades 25% off")


func test_every_portrait_has_an_orange_line_round_it_and_the_picture_sits_inside() -> void:
	var frames: Array = hud.menu_box.find_children("LeaderFrame*", "PanelContainer", true, false)
	assert_eq(frames.size(), 3, "one on each card")
	for frame in frames:
		var line: StyleBoxFlat = frame.get_theme_stylebox("panel")
		assert_eq(line.border_color, hud.AMBER, "the UI's orange")
		assert_eq(line.get_border_width(SIDE_LEFT), 2)
		var face: TextureRect = frame.get_child(0)
		assert_eq(face.get_global_rect().position, frame.global_position + Vector2(2, 2), "inside the line, not under it")
		assert_eq(frame.size, face.size + Vector2(4, 4))
	_click(_cards()[0])
	await wait_frames(4)
	await _show_tab("Colony")
	var colony_frames: Array = hud.boxes["Colony"].find_children("LeaderFrame*", "PanelContainer", true, false)
	assert_eq(colony_frames.size(), 1, "and round the one in the colony panel")
	assert_eq(colony_frames[0].get_theme_stylebox("panel").border_color, hud.AMBER)
