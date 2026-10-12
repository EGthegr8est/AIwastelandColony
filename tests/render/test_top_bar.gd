extends "res://tests/framework/test_case.gd"
## The top bar: each resource has its tiny picture before its name, and the bar still reads without one.

const Data = preload("res://scripts/data.gd")
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


func test_each_resource_has_its_picture_then_its_name_then_its_amount_in_order() -> void:
	var text: String = hud.top_text.text
	var at := 0
	for id in Data.RESOURCES:
		var tag := "[img=18x16]res://art/icons/res_%s_bar.png[/img]%s [color=#ffd88a]%d[/color]" % [id, id, Game.res[id]]
		var found := text.find(tag, at)
		assert_ne(found, -1, "%s: picture, name and amount, after the one before" % id)
		at = found + tag.length()


func test_the_bar_shows_the_names_and_amounts_as_text_with_the_pictures_inline() -> void:
	var shown: String = hud.top_text.get_parsed_text()
	for id in Data.RESOURCES:
		assert_has(shown, "%s %d" % [id, Game.res[id]])


func test_the_bar_is_still_two_lines_with_nothing_wrapped() -> void:
	assert_eq(hud.top_text.get_line_count(), 2, "the status line and the resource line, the pictures do not push an amount down")
	# even with every resource in the hundreds (all eight in the thousands needs about 66 px more than the bar has, and wraps)
	for r in Data.RESOURCES:
		Game.res[r] = 999
	hud._refresh_top()
	await wait_frames(2)
	assert_eq(hud.top_text.get_line_count(), 2, "three-digit amounts in every resource still fit")


func test_a_resource_without_a_picture_is_just_its_name() -> void:
	hud._icon_tags["gold"] = ""
	hud._refresh_top()
	assert_has(hud.top_text.text, " gold [color=#ffd88a]")
	assert_false(hud.top_text.text.contains("res_gold_bar"))
	assert_true(hud.top_text.text.contains("res_wood_bar"), "the others keep theirs")
