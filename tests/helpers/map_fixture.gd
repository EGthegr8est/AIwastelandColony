extends Node
## The map the way main.gd sets it up (map view + camera), inside a SubViewport of a fixed size
## so tests see the same screen headless and windowed. Add it to the tree, then drive it:
##     fx = add_autofree(MapFixture.new())
##     await fx.view_cell(Game.home(Data.PLAYER), 1.0)
##     fx.reset_stats()
##     ... do something, await fx.settle() ...
##     assert_eq(fx.map.stats.tile_draws, 0)

const MapView = preload("res://scripts/map_view.gd")

var viewport := SubViewport.new()
var camera := Camera2D.new()
var map: Node2D = MapView.new()


func _init(size := Vector2i(1600, 900)) -> void:
	viewport.size = size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.add_child(map)
	viewport.add_child(camera)
	add_child(viewport)


func _ready() -> void:
	camera.make_current()


## Centers the camera on `cell` at `zoom` and waits for the map to catch up.
func view_cell(cell: Vector2i, zoom := 1.0) -> void:
	camera.position = (Vector2(cell) + Vector2(0.5, 0.5)) * MapView.CELL
	camera.zoom = Vector2(zoom, zoom)
	await settle()


## Waits a few frames, so camera moves, queued redraws and rendering have all happened.
func settle(frames := 3) -> void:
	for i in frames:
		await get_tree().process_frame


func reset_stats() -> void:
	for k in map.stats:
		map.stats[k] = 0


## Moves the mouse over `cell`, like the player hovering it.
func hover(cell: Vector2i) -> void:
	var e := InputEventMouseMotion.new()
	e.position = screen_pos(cell)
	viewport.push_input(e)


## Left-clicks `cell`, like the player selecting it.
func click(cell: Vector2i) -> void:
	hover(cell)
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = screen_pos(cell)
		viewport.push_input(e)


## Where the center of `cell` is on screen.
func screen_pos(cell: Vector2i) -> Vector2:
	return map.get_canvas_transform() * ((Vector2(cell) + Vector2(0.5, 0.5)) * MapView.CELL)


## How many map tiles are at least partly on screen.
func visible_tile_count() -> int:
	var inv := map.get_canvas_transform().affine_inverse()
	var rect := Rect2(inv * Vector2.ZERO, Vector2(viewport.size) / camera.zoom)
	var first := Vector2i((rect.position / MapView.CELL).floor()).clamp(Vector2i.ZERO, Vector2i(Game.w, Game.h))
	var last := Vector2i((rect.end / MapView.CELL).ceil()).clamp(Vector2i.ZERO, Vector2i(Game.w, Game.h))
	return (last.x - first.x) * (last.y - first.y)


## What the viewport shows right now. Needs a real renderer: returns null when headless.
func capture() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
