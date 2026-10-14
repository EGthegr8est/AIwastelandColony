extends "res://tests/framework/bench_case.gd"
## What the whole game costs a frame at the window sizes players use: the real main scene (map, top bar, side panel, log), windowed at
## 1600 x 900, maximized and fullscreen, by day and by night, standing still, panning and zoomed right out. Frame times are real
## (vsync off); GPU and render CPU come from the window's own viewport. Needs a window:
##     .\tests\run.ps1 -Windowed --bench --filter=bench_fullscreen
## (it really does go fullscreen for a few seconds.)

const Data = preload("res://scripts/data.gd")
const Daylight = preload("res://scripts/daylight.gd")
const Leaders = preload("res://scripts/leaders.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")

var main: Node2D
var hud: Node
var map: Node2D
var vsync := DisplayServer.VSYNC_ENABLED
var max_fps := 0
var mode_before := Window.MODE_WINDOWED
var size_before := Vector2i(1600, 900)


func before_all() -> void:
	if DisplayServer.get_name() == "headless":
		return
	seed(5)
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
		if child.has_method("finish_replay"):
			map = child
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	_press("New colony")
	_press("Choose")
	await get_tree().process_frame
	await get_tree().process_frame
	Game.reveal(Data.PLAYER, Vector2i(Game.w / 2, Game.h / 2), Game.w)
	for i in 6:
		Game.end_season()
		map.finish_replay()
	Game.changed.emit()
	Daylight.enabled = true
	main.cam.position = (Vector2(Game.home(Data.PLAYER)) + Vector2(0.5, 0.5)) * map.CELL
	var window := get_window()
	mode_before = window.mode
	size_before = window.size
	vsync = DisplayServer.window_get_vsync_mode()
	max_fps = Engine.max_fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)   # frame times show the real cost, not the monitor's refresh rate
	Engine.max_fps = 0
	RenderingServer.viewport_set_measure_render_time(window.get_viewport_rid(), true)


func after_all() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	window.mode = Window.MODE_WINDOWED
	window.size = size_before
	if mode_before != Window.MODE_FULLSCREEN:
		window.mode = mode_before
	DisplayServer.window_set_vsync_mode(vsync)
	Engine.max_fps = max_fps
	Daylight.enabled = false
	main.queue_free()


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return


## The window the way a player gets it.
func _set_window(config: String) -> void:
	var window := get_window()
	match config:
		"windowed":
			window.mode = Window.MODE_WINDOWED
			window.size = Vector2i(1600, 900)
		"maximized":
			window.mode = Window.MODE_WINDOWED
			window.mode = Window.MODE_MAXIMIZED
		"fullscreen":
			window.mode = Window.MODE_FULLSCREEN
	for i in 20:
		await get_tree().process_frame


## Frame times for `frames` frames; `each` is called with the frame number first (to move the camera, say).
func _sample(label: String, frames := 90, each := Callable()) -> void:
	var rid := get_window().get_viewport_rid()
	var times: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var t_prev := Time.get_ticks_usec()
	var calls := 0
	for i in frames:
		if each.is_valid():
			each.call(i)
		await get_tree().process_frame
		var t := Time.get_ticks_usec()
		times.append((t - t_prev) / 1000.0)
		t_prev = t
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
		calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	times.sort()
	gpu.sort()
	cpu.sort()
	record(label + ": frame time", times[times.size() / 2], "ms", "p95 %.2f  max %.2f" % [times[int(times.size() * 0.95)], times[-1]])
	record(label + ": GPU", gpu[gpu.size() / 2], "ms")
	record(label + ": render CPU", cpu[cpu.size() / 2], "ms")
	record(label + ": draw calls", calls)


func bench_by_window_size() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a window: run.ps1 -Windowed --bench")
		return
	for config in ["windowed", "maximized", "fullscreen"]:
		await _set_window(config)
		var size := get_window().size
		record("%s: window pixels" % config, size.x * size.y / 1000000.0, "Mpx", "%d x %d" % [size.x, size.y], true)
		for light in ["day", "night"]:
			Game.season = 1 if light == "day" else 2
			for i in 6:
				await get_tree().process_frame
			main.cam.zoom = Vector2.ONE
			await _sample("%s, %s, still" % [config, light])
			var step := Vector2(10, 0)
			await _sample("%s, %s, panning" % [config, light], 90, func(i): main.cam.position += step * (1 if i < 45 else -1))
			main.cam.zoom = Vector2(0.25, 0.25)
			for i in 6:
				await get_tree().process_frame
			await _sample("%s, %s, whole map" % [config, light])
			main.cam.zoom = Vector2.ONE
	await _set_window("windowed")


## What toggling fullscreen costs: the frames just after the switch.
func bench_going_fullscreen_and_back() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a window: run.ps1 -Windowed --bench")
		return
	await _set_window("windowed")
	Game.season = 1
	main.cam.zoom = Vector2.ONE
	for round in 2:
		for config in ["fullscreen", "windowed"]:
			var times: Array[float] = []
			var window := get_window()
			var t_prev := Time.get_ticks_usec()
			if config == "fullscreen":
				window.mode = Window.MODE_FULLSCREEN
			else:
				window.mode = Window.MODE_WINDOWED
				window.size = Vector2i(1600, 900)
			for i in 40:
				await get_tree().process_frame
				var t := Time.get_ticks_usec()
				times.append((t - t_prev) / 1000.0)
				t_prev = t
			var slow := times.duplicate()
			slow.sort()
			record("round %d, to %s: slowest frame" % [round + 1, config], slow[-1], "ms", "next %.1f  %.1f" % [slow[-2], slow[-3]])
			var over := times.filter(func(t): return t > 50.0).size()
			record("round %d, to %s: frames over 50 ms (of 40)" % [round + 1, config], over)


## Frame times for `frames` frames, as a spike count too: how many were slower than 8, 16.7 and 33 ms.
func _spikes(label: String, frames := 400, each := Callable()) -> void:
	var times: Array[float] = []
	var t_prev := Time.get_ticks_usec()
	for i in frames:
		if each.is_valid():
			each.call(i)
		await get_tree().process_frame
		var t := Time.get_ticks_usec()
		times.append((t - t_prev) / 1000.0)
		t_prev = t
	var over8 := times.filter(func(t): return t > 8.0).size()
	var over17 := times.filter(func(t): return t > 16.7).size()
	var over33 := times.filter(func(t): return t > 33.0).size()
	var sorted := times.duplicate()
	sorted.sort()
	record(label + ": median", sorted[sorted.size() / 2], "ms", "p99 %.2f  max %.2f" % [sorted[int(sorted.size() * 0.99)], sorted[-1]])
	record(label + ": frames over 8 / 16.7 / 33 ms (of %d)" % frames, over8, "", "%d / %d / %d" % [over8, over17, over33])


## Hovering, selecting, and a whole season walking, windowed and fullscreen, day into night.
func bench_interactions() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a window: run.ps1 -Windowed --bench")
		return
	var home := Game.home(Data.PLAYER)
	for config in ["windowed", "fullscreen"]:
		await _set_window(config)
		Game.season = 1
		main.cam.zoom = Vector2.ONE
		main.cam.position = (Vector2(home) + Vector2(0.5, 0.5)) * map.CELL
		for i in 6:
			await get_tree().process_frame
		await _spikes("%s, idle, day" % config)
		await _spikes("%s, hovering" % config, 120, func(i):
			map.hover = home + Vector2i(i % 30 - 15, i / 30 - 2)
			map.overlay_layer.queue_redraw())
		await _spikes("%s, selecting a tile each frame" % config, 60, func(i): Game.select(home + Vector2i(i % 20 - 10, i / 20 - 1)))
		await _spikes("%s, picking a tile and clearing it, each frame (the legend comes and goes)" % config, 60, func(i): Game.select(home + Vector2i(2, 2) if i % 2 == 0 else Vector2i(-1, -1)))
		Game.select(Vector2i(-1, -1))
		# a season walking, day into night
		SeasonReplay.mode = "normal"
		var far := Vector2i(Game.w / 2, Game.h / 2)
		Game.pop += 6
		Game.res.merge({"grain": 100, "fuel": 50, "meat": 50}, true)
		Units.send("scout", "foot", far)
		Units.send("scout", "horse", far + Vector2i(5, 3))
		Game.end_season()
		var frames := 0
		var times: Array[float] = []
		var t_prev := Time.get_ticks_usec()
		while map.playing and frames < 900:
			await get_tree().process_frame
			var t := Time.get_ticks_usec()
			times.append((t - t_prev) / 1000.0)
			t_prev = t
			frames += 1
		if times.size() > 2:
			var sorted := times.duplicate()
			sorted.sort()
			record("%s, a season walking (day to night): median frame" % config, sorted[sorted.size() / 2], "ms", "p99 %.2f  max %.2f over %d frames" % [sorted[int(sorted.size() * 0.99)], sorted[-1], times.size()])
			record("%s, a season walking: frames over 16.7 ms" % config, times.filter(func(t): return t > 16.7).size())
		else:
			record("%s, a season walking: frames" % config, times.size(), "", "the replay did not play")
		SeasonReplay.mode = "off"
		map.finish_replay()
		await _spikes("%s, idle, night" % config)
	await _set_window("windowed")


## The same, deep into a long game: 80 seasons in, the map full of walls, buildings and parties, a long log. What a click, a hover and a season cost
## there, windowed and fullscreen.
func bench_late_game() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a window: run.ps1 -Windowed --bench")
		return
	var home := Game.home(Data.PLAYER)
	var t0 := Time.get_ticks_usec()
	var season_times: Array[float] = []
	var played := 0
	for i in 80:
		if not Game.ending.is_empty():
			break
		played += 1
		# something to do with the stores each season, so the colony grows like a played one
		Game.res.merge({"wood": 400, "stone": 400, "metal": 200, "grain": 300, "veg": 100, "meat": 100, "gold": 300}, true)
		Game.pop = maxi(Game.pop, 12)
		Game.troops = maxi(Game.troops, 8)
		var cell := home + Vector2i(i % 9 - 4, i / 9 % 9 - 4)
		if Game.in_bounds(cell) and Game.build_status("wall", cell) == "":
			Game.build("wall", cell)
		var s0 := Time.get_ticks_usec()
		Game.end_season()
		season_times.append((Time.get_ticks_usec() - s0) / 1000.0)
		map.finish_replay()
		if i % 20 == 0:
			await get_tree().process_frame
	season_times.sort()
	record("late game: end_season (%d of them), median" % played, season_times[season_times.size() / 2], "ms", "p95 %.1f  max %.1f  ending: %s" % [season_times[int(season_times.size() * 0.95)], season_times[-1], Game.ending])
	Game.changed.emit()
	for i in 6:
		await get_tree().process_frame
	record("late game: log lines", Game.log_lines.size())
	record("late game: seasons played", Game.season)
	for config in ["windowed", "fullscreen"]:
		await _set_window(config)
		Game.season = 1
		main.cam.zoom = Vector2.ONE
		main.cam.position = (Vector2(home) + Vector2(0.5, 0.5)) * map.CELL
		for i in 6:
			await get_tree().process_frame
		await _spikes("%s, late game, idle" % config, 200)
		await _spikes("%s, late game, selecting a tile each frame" % config, 60, func(i): Game.select(home + Vector2i(i % 20 - 10, i / 20 - 1)))
		Game.select(Vector2i(-1, -1))
		var tabs: Array = hud.find_children("*", "TabContainer", true, false)
		if not tabs.is_empty():
			var tab_times: Array[float] = []
			for round in 3:
				for t in tabs[0].get_tab_count():
					tabs[0].current_tab = t
					var a := Time.get_ticks_usec()
					await get_tree().process_frame
					tab_times.append((Time.get_ticks_usec() - a) / 1000.0)
			tab_times.sort()
			record("%s, late game, switching side-panel tabs: median / max frame" % config, tab_times[tab_times.size() / 2], "ms", "max %.1f" % tab_times[-1])
		var s0 := Time.get_ticks_usec()
		Game.end_season()
		var spike := (Time.get_ticks_usec() - s0) / 1000.0
		await get_tree().process_frame
		record("%s, late game, end season: the call, then the next frame" % config, spike, "ms")
		map.finish_replay()
	await _set_window("windowed")
