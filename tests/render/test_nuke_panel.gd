extends "res://tests/framework/test_case.gd"
## The panels of the nukes, driven through the real HUD: a glowing crater's search, the silo with warheads left in it, the Nuclear strike block (hover outlines the
## blast square, the first press arms it, the second sends the bomber), the Bomber in the vehicle list, and the stats line.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const ForcedDice = preload("res://tests/helpers/forced_dice.gd")
const Leaders = preload("res://scripts/leaders.gd")

var main: Node2D
var hud: Node
var home: Vector2i
var crater: Vector2i


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
	Units.animals = []
	Units.wild_spawns = false
	home = Game.home(Data.PLAYER)
	crater = World.find_tile(func(c, t): return t["t"] == "crater" and c.x > 4 and c.y > 4 and c.x < Game.w - 5 and c.y < Game.h - 5)
	assert_ne(crater, Vector2i(-1, -1))


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _tile_button(text: String) -> Button:
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.text.begins_with(text):
			return b
	return null


func _tile_labels() -> String:
	var text := ""
	for l in hud.boxes["Tile"].find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


## Shows tile `c` in the Tile panel, as far as your people have seen it.
func _look_at(c: Vector2i) -> void:
	Game.reveal(Data.PLAYER, c, 2)
	Game.update_fog()
	Game.select(c)
	Game.changed.emit()
	await wait_frames(3)


# ---------------------------------------------------------------- the crater

func test_a_crater_panel_offers_one_search_by_one_party() -> void:
	await _look_at(crater)
	var text := _tile_labels()
	assert_has(text, "SEARCH THE CRATER")
	assert_has(text, "Unsearched")
	assert_has(text, "natural 1")
	assert_has(text, "natural 20")
	assert_not_null(_tile_button("Scavenge on foot"), "a party can be sent")
	Game.tile(crater)["r"] = "picked"
	Game.changed.emit()
	await wait_frames(3)
	assert_has(_tile_labels(), "Picked clean.")
	assert_null(_tile_button("Scavenge on foot"))


func test_a_party_at_the_crater_gets_the_search_panel_and_a_blast_waits_for_the_die() -> void:
	Units.dice = ForcedDice.new([1])
	Game.reveal(Data.PLAYER, crater, 2)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", crater, crater)
	u.home = home
	u.crew = 3
	u.survivors = Units._make_crew(3)
	for s in u.survivors:
		s.traits = []
	Units.units.append(u)
	Units._begin_visit(u)
	Game.select(crater)
	Game.changed.emit()
	await wait_frames(3)
	var text := _tile_labels()
	assert_has(text, "SEARCH THE CRATER")
	assert_has(text, "Crater search, DC 11")
	assert_has(text, "Click the die to roll")
	assert_not_null(_tile_button("Leave without searching"))
	var seen := watch(Game, "blasted")
	hud.dice.clicked.emit()
	await wait_frames(2)
	assert_eq(hud.dice_phase, "rolling")
	assert_eq(Game.held_blasts, [crater], "the blast is in the game already")
	assert_eq(seen.count, 0, "but the explosion waits for the die")
	await wait_seconds(1.1)
	assert_eq(hud.dice_phase, "landed")
	assert_eq(seen.count, 1, "now it plays")
	assert_has(_tile_labels(), "The nuke goes off")


# ---------------------------------------------------------------- the silo

func test_a_silo_with_warheads_left_says_so_and_offers_a_party() -> void:
	var found := World.find_tile(func(c, t): return t["b"] == "poi_missile_silo")
	var silo := Game.poi_anchor(found)
	Game.set_silo_stock(silo, 2)
	await _look_at(silo)
	var text := _tile_labels()
	assert_has(text, "2 unfired nukes are still in the silo")
	assert_has(text, "nothing to roll")
	assert_not_null(_tile_button("Scavenge on"))
	Game.set_silo_stock(silo, 1)
	Game.changed.emit()
	await wait_frames(3)
	assert_has(_tile_labels(), "1 unfired nuke is still in the silo")


# ---------------------------------------------------------------- the strike

func _ready_to_strike() -> Vector2i:
	Game.vehicles["bomber"] = 1
	Game.items["nuke"] = 1
	Game.res["fuel"] = 60
	return home + Vector2i(5, 3)


func test_there_is_no_strike_block_without_a_bomber() -> void:
	var c := home + Vector2i(5, 3)
	await _look_at(c)
	assert_false(_tile_labels().contains("NUCLEAR STRIKE"))
	assert_null(_tile_button("Drop a nuke"))


func test_the_strike_block_shows_the_button_the_square_and_a_confirm_press() -> void:
	var c := _ready_to_strike()
	await _look_at(c)
	assert_has(_tile_labels(), "NUCLEAR STRIKE")
	var b := _tile_button("Drop a nuke here")
	assert_not_null(b)
	assert_eq(b.text, "Drop a nuke here (bomber, 14 fuel in the tank)")
	assert_false(b.disabled)
	assert_has(_tile_labels(), "3 by 3 square")
	assert_has(_tile_labels(), "no recall")
	b.mouse_entered.emit()
	assert_eq(Game.strike_preview, c, "the map outlines the square while the button is hovered")
	b.mouse_exited.emit()
	assert_eq(Game.strike_preview, Vector2i(-1, -1))
	b.pressed.emit()
	await wait_frames(3)
	assert_eq(hud.strike_armed, c)
	assert_eq(Units.units.filter(func(u): return u.job == "bomb").size(), 0, "one press only arms it")
	var confirm := _tile_button("Confirm: drop the nuke on")
	assert_not_null(confirm)
	assert_eq(confirm.text, "Confirm: drop the nuke on %d,%d" % [c.x, c.y])
	confirm.pressed.emit()
	await wait_frames(3)
	var flights := Units.units.filter(func(u): return u.job == "bomb")
	assert_eq(flights.size(), 1, "the second press sends the bomber")
	assert_eq(flights[0].target, c)
	assert_eq(Game.items["nuke"], 0)
	assert_eq(hud.strike_armed, Vector2i(-1, -1))


func test_picking_another_tile_disarms_the_strike() -> void:
	var c := _ready_to_strike()
	await _look_at(c)
	_tile_button("Drop a nuke here").pressed.emit()
	await wait_frames(3)
	assert_eq(hud.strike_armed, c)
	await _look_at(c + Vector2i(2, 0))
	assert_eq(hud.strike_armed, Vector2i(-1, -1))
	assert_not_null(_tile_button("Drop a nuke here"), "back to the first press")


func test_the_strike_button_says_why_it_cannot_go() -> void:
	var c := _ready_to_strike()
	Game.items["nuke"] = 0
	await _look_at(c)
	var b := _tile_button("Drop a nuke here")
	assert_true(b.disabled)
	assert_has(_tile_labels(), "No nukes in the stores")


func test_the_block_warns_about_what_you_know_is_in_the_square() -> void:
	var c := _ready_to_strike()
	Game.tile(c)["b"] = "farm"
	Game.tile(c)["o"] = Data.PLAYER
	Game.reveal(Data.PLAYER, c, 3)
	Game.update_fog()
	Game.tile(c + Vector2i(1, 0))["b"] = "ai_wall"
	Game.tile(c + Vector2i(1, 0))["o"] = Data.AI
	var party: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", c + Vector2i(0, 1), c)
	party.crew = 3
	party.survivors = Units._make_crew(3)
	Units.units.append(party)
	await _look_at(c)
	var text := _tile_labels()
	assert_has(text, "WARNING, in the square")
	assert_has(text, "1 of your buildings (farm)")
	assert_has(text, "your scavenger party")
	assert_has(text, "Rust Kings buildings in the square: raider wall")
	assert_has(text, "costs %d relations" % Data.RAID_RELATIONS)


# ---------------------------------------------------------------- the vehicle list and the stats

func test_the_bomber_is_in_the_vehicle_list_with_what_it_needs() -> void:
	Game.vehicles["bomber"] = 0
	hud._refresh_colony()
	var box: VBoxContainer = hud.boxes["Colony"]
	var text := ""
	for l in box.find_children("*", "Label", true, false):
		text += l.text + "\n"
	assert_has(text, "Bombers: 0, 0 out")
	assert_has(text, "upkeep 4 fuel, 3 gold each")
	assert_has(text, "Needs a Airfield")
	var build: Button
	for b in box.find_children("*", "Button", true, false):
		if b.text.begins_with("Build Bombers"):
			build = b
	assert_not_null(build)
	assert_eq(build.text, "Build Bombers (60 metal, 25 fuel, 70 gold)")
	assert_true(build.disabled)


func test_the_upgrade_is_listed_under_warfare() -> void:
	hud._refresh_upgrades()
	var found := false
	for l in hud.boxes["Upgrades"].find_children("*", "Label", true, false):
		if l.text.contains("Strategic bombers"):
			found = true
	for b in hud.boxes["Upgrades"].find_children("*", "Button", true, false):
		if b.text.contains("Strategic bombers"):
			found = true
	assert_true(found, "the upgrades tab lists it")


func test_the_legend_shows_the_ash_and_the_bomber() -> void:
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	var text := _tile_labels()
	assert_has(text, "Scorched ash sand")
	assert_has(text, "Bomber")


# ---------------------------------------------------------------- the traders' warhead and the Rust Kings' airfield

func _diplomacy_text() -> String:
	hud._refresh_diplomacy()
	var text := ""
	for l in hud.boxes["Diplomacy"].find_children("*", "Label", true, false):
		text += l.text + "\n"
	return text


func test_a_trader_camp_with_a_known_warhead_offers_the_run() -> void:
	var at := home + Vector2i(6, 4)
	var camp := {"id": 700, "class": "trader", "name": "Dust Peddlers", "pos": at, "strength": 6, "relations": 0, "found": true, "warhead": true, "warhead_known": false}
	Units.tribes.append(camp)
	Game.vehicles["horse"] = 2
	Game.res["gold"] = 1000
	await _look_at(at)
	assert_false(_tile_labels().contains("WARHEAD FOR SALE"), "not until a caravan has traded there")
	camp["warhead_known"] = true
	Game.changed.emit()
	await wait_frames(3)
	var text := _tile_labels()
	assert_has(text, "WARHEAD FOR SALE: 500 gold")
	assert_has(text, "reaches your HQ")
	var horse := _tile_button("Buy the warhead on horseback")
	var foot := _tile_button("Buy the warhead on foot")
	assert_not_null(horse)
	assert_false(horse.disabled)
	assert_has(horse.text, "500 gold")
	assert_true(foot.disabled, "too heavy for a caravan on foot")
	camp["warhead"] = false
	Game.changed.emit()
	await wait_frames(3)
	assert_false(_tile_labels().contains("WARHEAD FOR SALE"), "sold")
	assert_null(_tile_button("Buy the warhead"))


func test_diplomacy_shows_their_bombers_and_what_you_know_of_their_airfield() -> void:
	Game.contacts["%d:%d" % [Data.PLAYER, Data.AI]] = true
	Game.ai["bomber"] = 1
	assert_has(_diplomacy_text(), "Bombers: 1. Their airfield: not found.")
	Game.ai["airfield_seen"] = 1
	Game.ai["airfield_wait"] = 5
	assert_has(_diplomacy_text(), "Their airfield is destroyed: they rebuild it in 5 seasons.")
