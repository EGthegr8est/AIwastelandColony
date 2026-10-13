extends "res://tests/framework/test_case.gd"
## A recon flight in the air shows the plane's cockpit fuel gauge beside its pilot, like a scouting plane, and its button
## says what goes in the tank.

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
	Units.wild_spawns = false
	Game.vehicles["plane"] = 1
	Game.res["fuel"] = 40


func _gauges(node: Node) -> Array:
	var out := []
	for t in node.find_children("*", "TextureRect", true, false):
		if t.get_script() != null and str(t.get_script().resource_path).ends_with("fuel_gauge.gd"):
			out.append(t)
	return out


func test_a_recon_flight_shows_the_plane_gauge_with_its_reading() -> void:
	var target: Vector2i = Game.home(Data.PLAYER) + Vector2i(12, 0)
	Units.send("plane", "plane", target)
	var u: Dictionary = Units.units[-1]
	assert_eq(u.job, "plane")
	var card: Control = hud._party_card(u)
	add_child(card)
	var gauges := _gauges(card)
	assert_eq(gauges.size(), 1, "one gauge on the card")
	assert_eq(gauges[0].kind, "plane", "the cockpit dial")
	var texts := card.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, "Fuel %.1f / %d" % [u.fuel, Data.VEHICLE_FUEL.plane.tank])
	card.queue_free()


func test_the_gauge_follows_the_fuel_down() -> void:
	var target: Vector2i = Game.home(Data.PLAYER) + Vector2i(14, 0)
	Units.send("plane", "plane", target)
	var u: Dictionary = Units.units[-1]
	Units.season_turn()
	var card: Control = hud._party_card(u)
	add_child(card)
	var texts := card.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_lt(u.fuel, float(Data.VEHICLE_FUEL.plane.tank))
	assert_has(texts, "Fuel %.1f / %d" % [u.fuel, Data.VEHICLE_FUEL.plane.tank])
	card.queue_free()


func test_the_fly_recon_button_says_how_much_goes_in_the_tank() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	hud._recon_button(box, Game.home(Data.PLAYER) + Vector2i(10, 0))
	var labels := box.find_children("*", "Button", true, false).map(func(b): return b.text)
	assert_eq(labels.size(), 1)
	assert_has(labels[0], "Fly recon over this tile (%d fuel in the tank)" % Data.VEHICLE_FUEL.plane.tank)
	box.queue_free()
