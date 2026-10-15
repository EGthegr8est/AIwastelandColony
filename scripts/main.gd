extends Node2D
## Sets up the map, camera and UI. WASD/arrows pan, mouse wheel zooms, right-drag pans, F11 toggles fullscreen.

const MapView = preload("res://scripts/map_view.gd")
const Hud = preload("res://scripts/hud.gd")
const SelfTest = preload("res://scripts/selftest.gd")
const PAN_SPEED := 700.0
## The wheel zooms between these, so every art pixel is a whole number of screen pixels (or, below 1, an even half).
const ZOOM_STEPS := [0.25, 0.5, 1.0, 2.0, 3.0]

var cam := Camera2D.new()
var _mode_before_fullscreen := Window.MODE_WINDOWED   # what F11 goes back to


func _ready() -> void:
	if SelfTest.requested():   # "WastelandColony.console.exe -- --selftest": check the build, don't play
		var lines := SelfTest.run()
		for line in lines:
			print(line)
		cam.free()   # never added to the scene: don't leave it to be reported as a leak
		get_tree().quit(1 if SelfTest.failed(lines) else 0)
		return
	_fit_window()
	add_child(MapView.new())
	add_child(cam)
	cam.make_current()
	add_child(Hud.new())
	Game.focus.connect(func(c: Vector2i): cam.position = (Vector2(c) + Vector2(0.5, 0.5)) * MapView.CELL)


## The panels are laid out for a 1600 x 900 window, and that layout is always scaled to whatever size the window is:
## maximize it or go fullscreen and everything grows to fill the screen (a 4K screen shows it 2.4 times as big, with the
## same layout, the type and the pictures included), and shrink it and everything shrinks with it. On a screen too small
## for 1600 x 900 (a lot of laptops are 1366 x 768) the game also opens maximized, scaled down to fit, instead of
## hanging off the edges or squeezing the panels into each other.
func _fit_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	scale_to_fit(window)
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen).size
	if too_small(usable, design_size()):
		window.mode = Window.MODE_MAXIMIZED


## The window size the panels are designed for (the project's setting).
static func design_size() -> Vector2i:
	return Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))


## Is a screen with this much usable room smaller than the design size?
static func too_small(usable: Vector2i, design: Vector2i) -> bool:
	return usable.x < design.x or usable.y < design.y


## F11: fullscreen, and F11 again goes back to whatever the window was (windowed or maximized).
func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var window := get_window()
	if window.mode != Window.MODE_FULLSCREEN:
		_mode_before_fullscreen = window.mode
	window.mode = next_window_mode(window.mode, _mode_before_fullscreen)


## The mode F11 asks for: fullscreen, unless it already is, then the mode it was in before.
static func next_window_mode(current: Window.Mode, before: Window.Mode) -> Window.Mode:
	if current == Window.MODE_FULLSCREEN:
		return before if before != Window.MODE_FULLSCREEN else Window.MODE_WINDOWED
	return Window.MODE_FULLSCREEN


## Lays `window` out for the design size and scales that to the window, adding room on the longer side.
static func scale_to_fit(window: Window) -> void:
	window.content_scale_size = design_size()
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	cam.position += dir * PAN_SPEED * delta / cam.zoom.x


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		toggle_fullscreen()
		get_viewport().set_input_as_handled()


## The zoom one wheel notch from `zoom`: the next step in or out (the nearest end if it is already there).
static func zoom_step(zoom: float, in_: bool) -> float:
	if in_:
		for s in ZOOM_STEPS:
			if s > zoom + 0.001:
				return s
		return ZOOM_STEPS[ZOOM_STEPS.size() - 1]
	for i in range(ZOOM_STEPS.size() - 1, -1, -1):
		if ZOOM_STEPS[i] < zoom - 0.001:
			return ZOOM_STEPS[i]
	return ZOOM_STEPS[0]


func _zoom_to(z: float) -> void:
	cam.zoom = Vector2(z, z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_to(zoom_step(cam.zoom.x, true))
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_to(zoom_step(cam.zoom.x, false))
	elif event is InputEventMouseMotion and event.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		cam.position -= event.relative / cam.zoom.x
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and Game.in_game:
		Game.deselect_scout()
