extends "res://tests/framework/test_case.gd"
## The side panel only rebuilds the tab being looked at on a change (rebuilding all four cost about 90 ms a change); the
## others are marked stale and catch up the moment they are opened.

const Leaders = preload("res://scripts/leaders.gd")

var main: Node2D
var hud: Node


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
	await wait_frames(4)


func _marker(box: Control) -> Control:
	var m := Control.new()
	m.name = "Marker"
	box.add_child(m)
	return m


func _has_marker(box: Control) -> bool:
	return box.find_child("Marker", true, false) != null


func _show_tab(tab_name: String) -> void:
	for i in hud.tabs.get_tab_count():
		if hud.tabs.get_tab_title(i) == tab_name:
			hud.tabs.current_tab = i
	await wait_frames(2)


func test_a_change_rebuilds_the_tab_in_view_and_leaves_the_others_alone() -> void:
	await _show_tab("Tile")
	_marker(hud.boxes["Tile"])
	_marker(hud.boxes["Colony"])
	_marker(hud.boxes["Upgrades"])
	_marker(hud.boxes["Diplomacy"])
	Game.changed.emit()
	await wait_frames(3)
	assert_false(_has_marker(hud.boxes["Tile"]), "the tab in view is rebuilt")
	for tab_name in ["Colony", "Upgrades", "Diplomacy"]:
		assert_true(_has_marker(hud.boxes[tab_name]), "%s is out of sight and left alone" % tab_name)
		assert_true(hud.stale_tabs.has(tab_name), "%s is marked stale" % tab_name)
	assert_false(hud.stale_tabs.has("Tile"))


func test_opening_a_stale_tab_brings_it_up_to_date_once() -> void:
	await _show_tab("Tile")
	_marker(hud.boxes["Colony"])
	Game.pop += 3
	Game.changed.emit()
	await wait_frames(3)
	assert_true(hud.stale_tabs.has("Colony"))
	await _show_tab("Colony")
	assert_false(_has_marker(hud.boxes["Colony"]), "rebuilt on opening")
	assert_false(hud.stale_tabs.has("Colony"))
	var text := ""
	for l in hud.boxes["Colony"].find_children("*", "Label", true, false):
		text += l.text + "\n"
	assert_has(text, "Population: %d" % Game.pop, "and it shows what changed while it was away")
	_marker(hud.boxes["Colony"])
	await _show_tab("Upgrades")
	await _show_tab("Colony")
	assert_true(_has_marker(hud.boxes["Colony"]), "an up to date tab is not rebuilt again just for being opened")


func test_the_tab_in_view_keeps_following_changes_whichever_it_is() -> void:
	await _show_tab("Colony")
	_marker(hud.boxes["Colony"])
	Game.changed.emit()
	await wait_frames(3)
	assert_false(_has_marker(hud.boxes["Colony"]), "the Colony tab is rebuilt while it is the one in view")
	_marker(hud.boxes["Tile"])
	Game.changed.emit()
	await wait_frames(3)
	assert_true(_has_marker(hud.boxes["Tile"]), "and the Tile tab is now the one left alone")


func test_selecting_a_tile_switches_to_the_tile_tab_and_shows_it() -> void:
	await _show_tab("Diplomacy")
	var c: Vector2i = Game.home(0 + 1) + Vector2i(1, 0)   # a tile of yours
	Game.select(c)
	Game.tile_selected.emit()
	await wait_frames(4)
	assert_eq(hud.tabs.get_tab_title(hud.tabs.current_tab), "Tile")
	var text := ""
	for l in hud.boxes["Tile"].find_children("*", "Label", true, false):
		text += l.text + "\n"
	assert_has(text, "Tile %d,%d" % [c.x, c.y])
