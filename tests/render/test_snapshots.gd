extends "res://tests/framework/test_case.gd"
## Pixel snapshots of the map. Rendering optimizations must not change what the player sees, so
## each of these views has to match its baseline image in tests/render/snapshots/.
## They need a real GPU, so headless runs skip them:  .\tests\run.ps1 -Windowed --filter=snapshot

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")
const Snapshots = preload("res://tests/helpers/snapshots.gd")
const Sprites = preload("res://scripts/sprites.gd")

var fx: MapFixture


func before_all() -> void:
	Sprites.choose(1)   # the baselines are the map in pixel-art style 1 (one is in text glyphs)
	World.new_game(3)
	var hq := Game.home(Data.PLAYER)
	# Something of every kind on the move near home, so the overlays show up
	Units.units = []
	for spot in [["scav", "foot", Vector2i(4, -2)], ["caravan", "horse", Vector2i(6, 1)],
			["scav", "car", Vector2i(7, 3)], ["band", "foot", Vector2i(9, -1)]]:
		var u: Dictionary = Units._make_unit(spot[0], Data.NONE if spot[0] == "band" else Data.PLAYER,
			spot[1], hq + spot[2], hq + spot[2])
		Units.units.append(u)
	# Explored but out of sight: the Rust Kings' fort shows dimmed, as last seen
	Game.reveal(Data.PLAYER, Game.home(Data.AI), 5)
	Game.update_fog()


func before_each() -> void:
	Sprites.choose(1)
	Game.view = Data.PLAYER
	Game.selected = Vector2i(-1, -1)
	Game.preview = {}
	fx = add_autofree(MapFixture.new(Vector2i(800, 450)))


func after_all() -> void:
	Sprites.choose(1)


func test_snapshot_home() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	await _snap("home")


func test_snapshot_home_in_text_glyphs() -> void:
	Sprites.choose(0)
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	await _snap("home_text")


func test_snapshot_home_in_each_pixel_art_style() -> void:
	for style in [2, 3, 4]:
		Sprites.choose(style)
		Game.changed.emit()   # the map only redraws when told the game changed
		await fx.view_cell(Game.home(Data.PLAYER), 1.0)
		await _snap("home_style%d" % style)


func test_snapshot_whole_map_without_fog() -> void:
	Game.view = Data.NONE
	await fx.view_cell(Vector2i(Game.w / 2, Game.h / 2), 0.34)
	await _snap("whole_map")


## The clean look (art style 4): the whole map with no fog, where telling the grounds apart matters most.
func test_snapshot_clean_look_whole_map() -> void:
	Sprites.choose(Sprites.CLEAN)
	Game.view = Data.NONE
	Game.changed.emit()
	await fx.view_cell(Vector2i(Game.w / 2, Game.h / 2), 0.7)
	await _snap("clean_whole_map")


## The clean look close up, with a row of buildings on real ground: the pictures, the dark rims and the slope ledges.
func test_snapshot_clean_look_buildings_and_rims() -> void:
	Sprites.choose(Sprites.CLEAN)
	Game.view = Data.NONE
	var hq := Game.home(Data.PLAYER)
	var ids := ["hq", "ai_hq", "town", "ai_wall", "farm", "lodge", "mine", "salvage", "refinery", "outpost", "market", "wall",
		"tower", "keep", "citadel", "drug_factory", "horse_farm", "motor_pool", "port", "airfield"]
	var cells := []
	for n in ids.size():
		var cell := hq + Vector2i(-5 + n % 10, 3 + (n / 10) * 2)
		cells.append([cell, Game.tile(cell)["b"]])
		Game.tiles[cell.y * Game.w + cell.x]["b"] = ids[n]
	Game.changed.emit()
	await fx.view_cell(hq + Vector2i(0, 3), 3.0)
	await _snap("clean_buildings")
	for entry in cells:
		Game.tiles[entry[0].y * Game.w + entry[0].x]["b"] = entry[1]
	Game.changed.emit()


## The old highway running onto the old bridge, and a road of your own: the strips join up and carry on over the bridge's deck.
func test_snapshot_clean_look_highway_bridge_and_road() -> void:
	Sprites.choose(Sprites.CLEAN)
	Game.view = Data.NONE
	var hq := Game.home(Data.PLAYER)
	var made := []
	for k in range(2, 12):
		made.append(hq + Vector2i(k, 3))
	for k in range(3, 8):
		made.append(hq + Vector2i(11, k))
	var was := {}
	for c in made:
		was[c] = Game.tile(c)["b"]
		Game.tile(c)["b"] = "road"
	Game.changed.emit()
	var bridge := World.find_tile(func(c, t): return t["b"] == "old_bridge")
	await fx.view_cell(bridge + Vector2i(0, -3), 3.0)
	await _snap("clean_highway")
	await fx.view_cell(hq + Vector2i(7, 5), 3.0)
	await _snap("clean_roads")
	for c in made:
		Game.tile(c)["b"] = was[c]
	Game.changed.emit()


func test_snapshot_contours_close_up() -> void:
	Game.view = Data.NONE
	var i := Game.slopes.find("steep")
	await fx.view_cell(Vector2i(i % Game.w, i / Game.w), 2.5)
	await _snap("contours")


func test_snapshot_selection_hover_and_routes() -> void:
	var hq := Game.home(Data.PLAYER)
	await fx.view_cell(hq + Vector2i(4, 0), 1.0)
	fx.click(hq + Vector2i(9, 3))
	fx.hover(hq + Vector2i(-3, 2))
	await fx.settle()
	await _snap("selection")


func test_snapshot_remembered_enemy_land() -> void:
	await fx.view_cell(Game.home(Data.AI), 1.0)
	await _snap("remembered")


func test_snapshot_units_without_fog() -> void:
	Game.view = Data.NONE
	await fx.view_cell(Game.home(Data.PLAYER) + Vector2i(5, 0), 1.5)
	await _snap("units")


## The map only redraws the chunks whose look changed, so after each kind of game change a
## long-lived map view must look exactly like a brand-new one drawn from scratch. Each step
## targets one way a chunk could be missed, and is checked on its own so the others can't
## hide it. (No view switches: those redraw everything.)
func test_redrawing_only_what_changed_matches_a_fresh_draw() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	var hq := Game.home(Data.PLAYER)
	await fx.view_cell(hq, 1.0)
	Game.res.wood += 200
	# Claims marching west across a chunk edge: the chunk they leave must redraw its border lines
	var x := hq.x - 3
	while x > (hq.x / fx.map.CHUNK) * fx.map.CHUNK - 3:
		x -= 1
		Game.claim(Vector2i(x, hq.y))
		await fx.settle(1)
	assert_eq(Game.tile(Vector2i(x, hq.y))["o"], Data.PLAYER, "the claims should have worked")
	await _assert_matches_fresh_draw("claims across a chunk edge", hq)
	# A raider band walking through land you can see: only the glyphs on the map change
	var band: Dictionary = Units._make_unit("band", Data.NONE, "foot", hq + Vector2i(-2, -3), hq)
	Units.units.append(band)
	for i in 4:
		band.pos += Vector2i(1, 0)
		Game.changed.emit()
		await fx.settle(1)
	await _assert_matches_fresh_draw("a band moving in sight", hq)
	# A scout walking away: what it saw drops out of sight but stays remembered (dimmed)
	var scout: Dictionary = Units._make_unit("scav", Data.PLAYER, "foot", hq + Vector2i(4, 4), hq)
	Units.units.append(scout)
	for i in 6:
		scout.pos += Vector2i(1, 1)
		Game.changed.emit()
		await fx.settle(1)
	await _assert_matches_fresh_draw("a scout walking away", hq)
	# Seasons pass, one while the camera is away and the chunks it left go stale
	Game.end_season()
	await fx.view_cell(Game.home(Data.AI), 0.5)
	Game.end_season()
	await fx.view_cell(hq, 1.0)
	await _assert_matches_fresh_draw("seasons passing off screen", hq)
	Units.units.erase(band)
	Units.units.erase(scout)


## Changing the art redraws every chunk, so a map that has been switched between styles must look
## exactly like one that was drawn in that style from the start, with units and a camp on it.
func test_switching_the_art_matches_a_fresh_draw() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	var hq := Game.home(Data.PLAYER)
	Game.view = Data.NONE
	await fx.view_cell(hq, 1.0)
	for choice in [2, 0, 3, 1]:
		Sprites.choose(choice)
		Game.changed.emit()
		await fx.settle(2)
		await _assert_matches_fresh_draw("switching to art %d" % choice, hq)


func _assert_matches_fresh_draw(after: String, cell: Vector2i) -> void:
	var lived := await fx.capture()
	var fresh := MapFixture.new(Vector2i(800, 450))
	add_child(fresh)
	await fresh.view_cell(cell, fx.camera.zoom.x)
	var bad := Snapshots.count_differences(lived, await fresh.capture())
	fresh.free()
	assert_eq(bad, 0, "after %s, pixels that differ from a fresh draw" % after)


func _snap(name: String) -> void:
	var image := await fx.capture()
	if image == null:
		skip("pixel snapshots need a GPU: run with run.ps1 -Windowed")
		return
	var result := Snapshots.check(name, image)
	if result[0] == "differs":
		fail(result[1])
	elif result[0] == "created":
		skip(result[1])
