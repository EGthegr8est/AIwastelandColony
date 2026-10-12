extends "res://tests/framework/bench_case.gd"
## What the map costs to draw in the situations players hit most: redraws, panning, hovering and
## ending a season. "map CPU" is the time spent building the map's draw commands, from the map's
## own counters. Frame times, GPU times and draw calls need a window:
##     .\tests\run.ps1 -Windowed --bench --save=NAME      and later      --compare=NAME

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")

var fx: MapFixture
var vsync := DisplayServer.VSYNC_ENABLED
var max_fps := 0


func before_all() -> void:
	# Mid-game: the whole map explored (most of it remembered, out of sight) and units about
	World.new_game(3)
	Game.reveal(Data.PLAYER, Vector2i(Game.w / 2, Game.h / 2), Game.w)
	for i in 6:
		Game.end_season()
	Game.view = Data.PLAYER
	fx = MapFixture.new()
	add_child(fx)
	RenderingServer.viewport_set_measure_render_time(fx.viewport.get_viewport_rid(), true)
	# Unthrottled frames, so frame times show real cost instead of the monitor's refresh rate
	vsync = DisplayServer.window_get_vsync_mode()
	max_fps = Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0


func after_all() -> void:
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	fx.queue_free()


func bench_redraw_at_zoom_1() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	await _redraws("redraw, zoom 1")


func bench_redraw_whole_map() -> void:
	await fx.view_cell(Vector2i(Game.w / 2, Game.h / 2), 0.25)
	await _redraws("redraw, zoom 0.25 (whole map)")


func bench_pan_at_zoom_1() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	await _pan("pan, zoom 1", Vector2(12, 0), 120)


func bench_pan_zoomed_out() -> void:
	await fx.view_cell(Vector2i(Game.w / 2, Game.h / 2), 0.5)
	await _pan("pan, zoom 0.5", Vector2(24, 6), 120)


func bench_hover_sweep() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	fx.reset_stats()
	var frames := 60
	var t0 := Time.get_ticks_usec()
	for i in frames:
		fx.hover(Game.home(Data.PLAYER) + Vector2i(i % 30 - 15, i / 30))
		await get_tree().process_frame
	_frame_results("hover sweep", frames, t0)


func bench_select_tile() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	var samples: Array[float] = []
	for i in 8:
		fx.reset_stats()
		fx.click(Game.home(Data.PLAYER) + Vector2i(3 + i, 2))
		await fx.settle(2)
		samples.append(fx.map.stats.usec)
	record_samples("select a tile: map CPU", samples, "us")


func bench_train_troop() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	Game.res.metal += 100
	Game.res.meat += 100
	Game.pop += 10
	var samples: Array[float] = []
	for i in 5:
		fx.reset_stats()
		Game.train_troop()
		await fx.settle(2)
		samples.append(fx.map.stats.usec)
	record_samples("train a troop: map CPU", samples, "us")


func bench_end_season() -> void:
	await fx.view_cell(Game.home(Data.PLAYER), 1.0)
	var samples: Array[float] = []
	for i in 4:
		fx.reset_stats()
		Game.end_season()
		await fx.settle(2)
		samples.append(fx.map.stats.usec)
	record_samples("end season: map CPU", samples, "us")


func bench_steady_frame() -> void:
	if DisplayServer.get_name() == "headless":
		skip("GPU numbers need a window: run.ps1 -Windowed --bench")
		return
	for zoom in [1.0, 0.25]:
		await fx.view_cell(Vector2i(Game.w / 2, Game.h / 2), zoom)
		await fx.settle(30)
		var rid := fx.viewport.get_viewport_rid()
		var label := "steady frame, zoom %s" % zoom
		record(label + ": GPU", RenderingServer.viewport_get_measured_render_time_gpu(rid), "ms")
		record(label + ": render CPU", RenderingServer.viewport_get_measured_render_time_cpu(rid), "ms")
		var calls := _draw_calls()
		if calls >= 0:
			record(label + ": draw calls", calls)


## Forces `count` full redraws and records the median map CPU per redraw.
func _redraws(metric: String, count := 15) -> void:
	var samples: Array[float] = []
	var tiles := 0
	for i in count:
		fx.reset_stats()
		fx.map.redraw_all()
		await fx.settle(2)
		samples.append(fx.map.stats.usec)
		tiles = fx.map.stats.tiles
	record_samples(metric + ": map CPU", samples, "us")
	record(metric + ": tiles drawn", tiles)


## Moves the camera `step` pixels a frame for `frames` frames, like holding an arrow key.
func _pan(metric: String, step: Vector2, frames: int) -> void:
	fx.reset_stats()
	var t0 := Time.get_ticks_usec()
	for i in frames:
		fx.camera.position += step * (1 if i < frames / 2 else -1)
		await get_tree().process_frame
	_frame_results(metric, frames, t0)


func _frame_results(metric: String, frames: int, t0: int) -> void:
	var s: Dictionary = fx.map.stats
	record(metric + ": map CPU per frame", s.usec / float(frames), "us")
	record(metric + ": tile redraws", s.tile_draws)
	record(metric + ": overlay redraws", s.overlay_draws)
	if DisplayServer.get_name() != "headless":
		record(metric + ": frame time", (Time.get_ticks_usec() - t0) / 1000.0 / frames, "ms")


## 2D draw calls in the map viewport's last frame, or -1 if this Godot can't say.
func _draw_calls() -> int:
	if not ClassDB.class_has_integer_constant("RenderingServer", "VIEWPORT_RENDER_INFO_TYPE_CANVAS"):
		return -1
	var canvas := ClassDB.class_get_integer_constant("RenderingServer", "VIEWPORT_RENDER_INFO_TYPE_CANVAS")
	return RenderingServer.viewport_get_render_info(fx.viewport.get_viewport_rid(), canvas,
		RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
