extends "res://tests/framework/test_case.gd"
## The Drug Factory in the side panel: clicking it shows how many frog hides and how much Salt the colony holds (neither has a line in the top
## bar), "Take Salt" appears beside the send buttons once there is Salt, and the market sells it.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var main: Node2D
var hud: Node
var hq: Vector2i
var factory: Vector2i


func before_each() -> void:
	seed(5)
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	_press("New colony")
	await wait_frames(2)
	_press("Choose")
	await wait_frames(3)
	SeasonReplay.mode = "off"
	hq = Game.home(Data.PLAYER)
	Units.units = []
	Units.tribes = []
	Units.animals = []
	Game.leader_info["perks"] = []
	Game.leader_info["flaw"] = ""
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "":
			factory = c
			Game.tile(c)["b"] = "drug_factory"
			break


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text == text and b.is_visible_in_tree():
			b.pressed.emit()
			return


func _texts(tab := "Tile") -> Array:
	return hud.boxes[tab].find_children("*", "Label", true, false).map(func(l): return l.text)


func _button_texts(tab := "Tile") -> Array:
	return hud.boxes[tab].find_children("*", "Button", true, false).map(func(b): return b.text)


func test_clicking_the_drug_factory_shows_the_hides_and_the_salt_in_the_stores() -> void:
	Game.items["hide"] = 2
	Game.items["salt"] = 5
	Game.select(factory)
	await wait_frames(3)
	var texts := _texts()
	assert_true(texts.any(func(t): return t.contains("DRUG FACTORY")), "a header")
	assert_true(texts.has("Frog hides in the stores: 2"))
	assert_true(texts.has("Salt in the stores: 5"))
	assert_true(texts.any(func(t): return t.contains("turns 1 frog hide into 2 Salt")))


func test_neither_the_hides_nor_the_salt_has_a_line_in_the_top_bar() -> void:
	Game.items["hide"] = 3
	Game.items["salt"] = 6
	Game.changed.emit()
	await wait_frames(3)
	var shown: String = hud.top_text.get_parsed_text().to_lower()
	assert_false(shown.contains("salt"))
	assert_false(shown.contains("hide"))
	assert_eq(hud.top_text.get_line_count(), 2, "and the bar is still two lines")


func test_the_factory_panel_says_none_when_you_hold_none() -> void:
	Game.select(factory)
	await wait_frames(3)
	assert_true(_texts().has("Salt in the stores: 0"))


func test_take_salt_shows_beside_the_send_buttons_only_once_you_have_some() -> void:
	var spot := hq + Vector2i(6, 0)
	Game.reveal(Data.PLAYER, spot, 3)
	Game.select(spot)
	await wait_frames(3)
	assert_false(_button_texts().any(func(t): return t.begins_with("Take Salt")), "no Salt, no toggle")
	Game.items["salt"] = 6
	Game.changed.emit()
	await wait_frames(3)
	assert_true(_button_texts().any(func(t): return t.begins_with("Take Salt: off (6 in the stores)")))


func test_switching_take_salt_on_puts_the_doses_on_the_scouting_buttons() -> void:
	var spot := hq + Vector2i(6, 0)
	Game.reveal(Data.PLAYER, spot, 3)
	Game.items["salt"] = 6
	Game.select(spot)
	await wait_frames(3)
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.text.begins_with("Take Salt"):
			b.pressed.emit()
			break
	await wait_frames(3)
	assert_true(Game.salt_on)
	assert_true(_button_texts().any(func(t): return t.begins_with("Take Salt: on")))
	assert_true(_button_texts().any(func(t): return t.contains("2 Salt")), "a scouting party of two takes two doses")


func test_the_market_row_for_salt_sells_and_buys() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.items["salt"] = 2
	Game.ai["salt_stock"] = 1
	Game.res["gold"] = 100
	hud.tabs.current_tab = 3
	Game.changed.emit()
	await wait_frames(4)
	var buttons := _button_texts("Diplomacy")
	assert_true(buttons.any(func(t): return t == "Sell 1 +30g"))
	assert_true(buttons.any(func(t): return t == "Buy 1 -60g (1 for sale)"))
	for b in hud.boxes["Diplomacy"].find_children("*", "Button", true, false):
		if b.text == "Sell 1 +30g":
			b.pressed.emit()
			break
	assert_eq(Game.items["salt"], 1)
	assert_eq(Game.res["gold"], 130)


func test_the_market_shows_no_salt_row_when_there_is_none_to_trade() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	hud.tabs.current_tab = 3
	Game.changed.emit()
	await wait_frames(4)
	assert_false(_texts("Diplomacy").has("Salt"))
