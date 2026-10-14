extends "res://tests/framework/test_case.gd"
## The picture of a point of interest, through the real HUD: it sits in the bottom right corner, under the Tile panel (which gets shorter to make room), while one of the
## site's four tiles is picked and your colony has seen it. Every kind has its own picture, the other tabs and the other tiles do not show one, and a party searching the
## site has its own panel with the room to itself. A seen tile of the old highway shows the Hollow Mile picture there too, with the day, night and high-radiation versions
## of the first sighting's screen.

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")
const Daylight = preload("res://scripts/daylight.gd")

var main: Node2D
var hud: Node
var home: Vector2i


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
	Game.hollow_found = true   # no picture of the old highway over the panel
	Units.tribes = []
	Units.animals = []
	Units.wild_spawns = false
	home = Game.home(Data.PLAYER)


func after_each() -> void:
	Daylight.enabled = false


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


## A 2 x 2 site of `kind` on open ground well away from home, top left tile returned. Your colony has not seen it.
func _site(kind: String, skip := 0) -> Vector2i:
	var seen := 0
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if c.distance_to(home) < 18 or c.x > Game.w - 4 or c.y > Game.h - 4:
			continue
		var free := true
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			var t: Dictionary = Game.tile(c + d)
			if t["t"] != "sand" or t["b"] != "" or t["o"] != Data.NONE:
				free = false
		if not free:
			continue
		if seen < skip:
			seen += 1
			continue
		for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
			Game.tile(c + d)["b"] = "poi_" + kind
			Game.memory[Data.PLAYER][Game.idx(c + d)] = null
		return c
	fail("no room for a %s" % kind)
	return Vector2i(-1, -1)


## Your people see the site: a ring of tiles round `c` is remembered.
func _discover(c: Vector2i) -> void:
	Game.reveal(Data.PLAYER, c, 2)
	Game.update_fog()


func _pick(c: Vector2i) -> void:
	Game.select(c)
	Game.changed.emit()
	await wait_frames(3)


func _window() -> Rect2:
	return Rect2(Vector2.ZERO, main.get_viewport().get_visible_rect().size)


# ---------------------------------------------------------------- the pictures

func test_every_kind_of_site_has_a_picture_of_the_right_size() -> void:
	for kind in Data.POIS:
		assert_true(Data.POI_SCENES.has(kind), "%s has a picture" % kind)
		var art := Sprites.picture(Data.POI_SCENES[kind])
		assert_not_null(art, "%s: %s loads" % [kind, Data.POI_SCENES[kind]])
		if art != null:
			assert_eq(Vector2(art.get_size()), Data.POI_SCENE_SIZE * 4.0, "%s is the art at 4 times its size" % kind)
	for kind in Data.POI_SCENES:
		assert_true(Data.POIS.has(kind), "%s is a kind of site" % kind)


# ---------------------------------------------------------------- when it shows

func test_a_site_your_colony_has_not_seen_shows_no_picture() -> void:
	var c := _site("bunker")
	await _pick(c)
	assert_false(hud.scene_panel.visible)
	assert_eq(hud.side_panel.offset_bottom, -6.0, "the Tile panel keeps the whole side")
	_discover(c)
	await _pick(c)
	assert_true(hud.scene_panel.visible, "seen, it does")


func test_each_kind_shows_its_own_picture_and_name() -> void:
	var skip := 0
	for kind in Data.POIS:
		var c := _site(kind, skip)
		skip += 1
		_discover(c)
		await _pick(c)
		assert_true(hud.scene_panel.visible, kind)
		assert_eq(hud.scene_art.texture, Sprites.picture(Data.POI_SCENES[kind]), "%s: its own picture" % kind)
		assert_eq(hud.scene_name.text, Data.BUILDINGS["poi_" + kind].name)


func test_any_of_the_four_tiles_shows_it() -> void:
	var c := _site("water_tower")
	_discover(c)
	for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)]:
		await _pick(c + d)
		assert_true(hud.scene_panel.visible, "tile %s" % str(c + d))
		assert_eq(hud.scene_name.text, "Water tower")


func test_another_tile_or_no_tile_takes_it_away() -> void:
	var c := _site("missile_silo")
	_discover(c)
	await _pick(c)
	assert_true(hud.scene_panel.visible)
	await _pick(c + Vector2i(3, 0))
	assert_false(hud.scene_panel.visible, "a plain tile")
	assert_eq(hud.side_panel.offset_bottom, -6.0)
	await _pick(c)
	assert_true(hud.scene_panel.visible)
	Game.select(Vector2i(-1, -1))
	Game.changed.emit()
	await wait_frames(3)
	assert_false(hud.scene_panel.visible, "nothing picked")


func test_it_belongs_to_the_tile_tab() -> void:
	var c := _site("radio_tower")
	_discover(c)
	await _pick(c)
	assert_true(hud.scene_panel.visible)
	hud.tabs.current_tab = 1
	await wait_frames(2)
	assert_false(hud.scene_panel.visible, "the Upgrades tab keeps the whole side")
	assert_eq(hud.side_panel.offset_bottom, -6.0)
	hud.tabs.current_tab = 0
	await wait_frames(2)
	assert_true(hud.scene_panel.visible, "and the Tile tab has it back")


func test_a_party_searching_the_site_has_the_room_to_itself() -> void:
	var c := _site("bunker")
	_discover(c)
	await _pick(c)
	assert_true(hud.scene_panel.visible)
	var u: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", c, c)
	u.home = home
	u.crew = 3
	u.survivors = Units._make_crew(3)
	Units.units.append(u)
	Units._begin_visit(u)
	await _pick(c + Vector2i(1, 1))
	assert_eq(u.stage, "site")
	assert_false(hud.scene_panel.visible, "searching: the panel has the die to show")
	assert_eq(hud.side_panel.offset_bottom, -6.0)
	Units.units.erase(u)
	await _pick(c)
	assert_true(hud.scene_panel.visible, "and the picture is back when the party has gone")


# ---------------------------------------------------------------- where it sits

func test_it_sits_in_the_bottom_right_corner_under_the_tile_panel() -> void:
	var c := _site("cargo_yard")
	_discover(c)
	await _pick(c)
	var win := _window()
	var scene: Rect2 = hud.scene_panel.get_global_rect()
	var side: Rect2 = hud.side_panel.get_global_rect()
	assert_eq(scene.end, win.end - Vector2(6, 6), "in the corner, 6 px from both edges")
	assert_eq(scene.position.x, side.position.x, "as wide as the side panel above it")
	assert_eq(scene.size.x, side.size.x)
	assert_le(side.end.y, scene.position.y, "the Tile panel stops where the picture starts")
	assert_ge(scene.position.y - side.end.y, 5.0, "with a gap between them")
	var art: Rect2 = hud.scene_art.get_global_rect()
	assert_eq(art.size, Data.POI_SCENE_SIZE, "the picture is drawn at 288 x 192: one screen pixel to an art pixel")
	assert_true(scene.encloses(art))
	assert_eq(hud.scene_art.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "crisp")


func test_it_does_not_cover_the_scavenge_button() -> void:
	var c := _site("gas_station")
	_discover(c)
	await _pick(c)
	var button: Button = null
	for b in hud.boxes["Tile"].find_children("*", "Button", true, false):
		if b.text.begins_with("Scavenge on foot"):
			button = b
	assert_not_null(button, "a party can be sent")
	var scene: Rect2 = hud.scene_panel.get_global_rect()
	assert_false(scene.intersects(button.get_global_rect()), "the picture is clear of the button")
	assert_le(button.get_global_rect().end.y, hud.side_panel.get_global_rect().end.y, "and the button is inside the Tile panel without scrolling")


func test_a_new_game_starts_with_no_picture() -> void:
	var c := _site("pumpjack")
	_discover(c)
	await _pick(c)
	assert_true(hud.scene_panel.visible)
	World.new_game(3)
	hud.refresh()
	assert_false(hud.scene_panel.visible)
	assert_eq(hud.side_panel.offset_bottom, -6.0)


# ---------------------------------------------------------------- the old highway

## A tile of the old highway, as your colony has not seen it.
func _highway(building := "old_road") -> Vector2i:
	var c := World.find_tile(func(cc, t): return t["b"] == building)
	assert_ne(c, Vector2i(-1, -1), "this map has an %s" % building)
	Game.memory[Data.PLAYER][Game.idx(c)] = null
	return c


## What the corner shows now: the Hollow Mile picture that goes with `version` ("day", "night" or "fallout").
func _shows_mile(version: String) -> void:
	assert_true(hud.scene_panel.visible, "the Hollow Mile picture is up (%s)" % version)
	assert_eq(hud.scene_art.texture, Sprites.picture(Data.HOLLOW_MILE[version]), version)
	assert_eq(hud.scene_name.text, "The Hollow Mile")
	assert_eq(hud.scene_name.get_theme_color("font_color"), Data.HOLLOW_MILE[version + "_color"])


func test_a_highway_tile_your_colony_has_not_seen_shows_nothing() -> void:
	var c := _highway()
	await _pick(c)
	assert_false(hud.scene_panel.visible)


func test_a_seen_highway_tile_shows_the_hollow_mile_in_the_corner() -> void:
	Game.season = 1
	var c := _highway()
	_discover(c)
	await _pick(c)
	_shows_mile("day")
	assert_eq(hud.scene_art.get_global_rect().size, Data.POI_SCENE_SIZE, "drawn like the site pictures")
	assert_eq(hud.scene_panel.get_global_rect().end, _window().end - Vector2(6, 6))


func test_the_old_bridge_is_part_of_the_mile() -> void:
	Game.season = 1
	var c := _highway("old_bridge")
	_discover(c)
	await _pick(c)
	_shows_mile("day")


func test_a_night_season_shows_the_dusk_picture() -> void:
	Daylight.enabled = true
	Game.season = 2
	assert_false(Daylight.is_day(Game.season))
	var c := _highway()
	_discover(c)
	await _pick(c)
	_shows_mile("night")


func test_with_the_night_switched_off_it_is_always_the_day_picture() -> void:
	Daylight.enabled = false
	Game.season = 2
	var c := _highway()
	_discover(c)
	await _pick(c)
	_shows_mile("day")


func test_high_radiation_changes_the_night_picture_but_not_the_day_one() -> void:
	Daylight.enabled = true
	var c := _highway()
	_discover(c)
	Game.tile(c)["rad"] = Data.HOLLOW_MILE.rad_high
	Game.measure(c)
	Game.season = 2
	await _pick(c)
	_shows_mile("fallout")
	Game.season = 1
	Game.changed.emit()
	await wait_frames(3)
	_shows_mile("day")
	Game.season = 2
	Game.tile(c)["rad"] = Data.HOLLOW_MILE.rad_high - 1
	Game.changed.emit()
	await wait_frames(3)
	_shows_mile("night")


func test_a_reading_your_scouts_have_not_taken_gives_nothing_away() -> void:
	Daylight.enabled = true
	Game.season = 2
	var c := _highway()
	_discover(c)
	Game.tile(c)["rad"] = 90
	assert_false(Game.is_measured(c), "not measured")
	await _pick(c)
	_shows_mile("night")
	Game.measure(c)
	Game.changed.emit()
	await wait_frames(3)
	_shows_mile("fallout")


func test_the_picture_follows_the_light_when_you_switch_the_night() -> void:
	Daylight.enabled = true
	Game.season = 2
	var c := _highway()
	_discover(c)
	await _pick(c)
	_shows_mile("night")
	hud._set_night(false)
	await wait_frames(3)
	_shows_mile("day")


func test_a_repaired_stretch_is_a_road_and_shows_nothing() -> void:
	var c := _highway()
	_discover(c)
	Game.tile(c)["b"] = "road"
	Game.reveal(Data.PLAYER, c, 1)
	await _pick(c)
	assert_false(hud.scene_panel.visible)


func test_a_missing_picture_leaves_the_corner_empty() -> void:
	Game.season = 1
	var c := _highway()
	_discover(c)
	Sprites._pictures[Data.HOLLOW_MILE.day] = null   # as if the file were not there
	await _pick(c)
	Sprites._pictures.erase(Data.HOLLOW_MILE.day)
	assert_false(hud.scene_panel.visible)
	assert_eq(hud.side_panel.offset_bottom, -6.0)


func test_the_first_sighting_screen_still_works_the_same() -> void:
	Game.season = 2
	Daylight.enabled = true
	hud.show_hollow_mile(true)
	assert_eq(hud.hollow_art.texture, Sprites.picture(Data.HOLLOW_MILE.fallout))
	hud.show_hollow_mile(false)
	assert_eq(hud.hollow_art.texture, Sprites.picture(Data.HOLLOW_MILE.night))
	hud._hollow_next()
