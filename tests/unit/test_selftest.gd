extends "res://tests/framework/test_case.gd"
## The built-copy self-check (scripts/selftest.gd): it passes here, and it really does notice when something
## the game reads at run time is missing.

const SelfTest = preload("res://scripts/selftest.gd")
const Sprites = preload("res://scripts/sprites.gd")


func test_it_is_only_asked_for_on_the_command_line() -> void:
	assert_false(SelfTest.requested(), "normal play and the tests don't pass --selftest")


func test_a_healthy_game_passes_every_check() -> void:
	var lines := SelfTest.run()
	assert_false(SelfTest.failed(lines), "\n".join(lines))
	assert_gt(lines.size(), 12, "atlas, pictures, six tracks, data, folder and the info line")
	assert_true(lines[-1].begins_with("info:"))


func test_it_checks_all_six_music_tracks_by_name() -> void:
	var text := "\n".join(SelfTest.run())
	assert_has(text, "wasteland_menu.wav")
	for path in Music.GAME:
		assert_has(text, path.get_file())


func test_it_notices_a_missing_atlas() -> void:
	var atlas = Sprites._atlas
	Sprites._atlas = null
	var lines := SelfTest.run()
	Sprites._atlas = atlas
	assert_true(SelfTest.failed(lines))
	assert_true(lines.any(func(l): return l.begins_with("FAIL") and l.contains("atlas")))


func test_it_notices_a_missing_picture_or_track() -> void:
	var cache := Sprites._pictures.duplicate()
	Sprites._pictures[Sprites.TITLE_PNG] = null
	var lines := SelfTest.run()
	Sprites._pictures = cache
	assert_true(lines.any(func(l): return l.begins_with("FAIL") and l.contains("title screen")))


func test_it_leaves_no_scratch_file_behind() -> void:
	SelfTest.run()
	assert_false(FileAccess.file_exists("user://selftest.tmp"))


# ---------------------------------------------------------------- small screens

const Main = preload("res://scripts/main.gd")


func test_the_design_size_is_the_projects_window_size() -> void:
	assert_eq(Main.design_size(), Vector2i(1600, 900))


func test_a_screen_smaller_than_the_design_size_gets_the_scaled_layout() -> void:
	var design := Main.design_size()
	assert_true(Main.too_small(Vector2i(1366, 728), design), "a typical 1366 x 768 laptop, less its taskbar")
	assert_true(Main.too_small(Vector2i(1440, 860), design), "a 16:10 laptop is too short")
	assert_false(Main.too_small(Vector2i(1920, 1040), design), "a 1080p screen, less its taskbar, is fine")
	assert_false(Main.too_small(Vector2i(2560, 1400), design))
	assert_false(Main.too_small(design, design), "exactly the design size is fine")


func test_scaling_to_fit_keeps_the_designed_layout() -> void:
	var window := Window.new()
	add_autofree(window)
	Main.scale_to_fit(window)
	assert_eq(window.content_scale_size, Main.design_size())
	assert_eq(window.content_scale_mode, Window.CONTENT_SCALE_MODE_CANVAS_ITEMS)
	assert_eq(window.content_scale_aspect, Window.CONTENT_SCALE_ASPECT_EXPAND)


func test_f11_goes_to_fullscreen_and_back_to_the_mode_it_came_from() -> void:
	assert_eq(Main.next_window_mode(Window.MODE_WINDOWED, Window.MODE_WINDOWED), Window.MODE_FULLSCREEN)
	assert_eq(Main.next_window_mode(Window.MODE_MAXIMIZED, Window.MODE_WINDOWED), Window.MODE_FULLSCREEN)
	assert_eq(Main.next_window_mode(Window.MODE_FULLSCREEN, Window.MODE_MAXIMIZED), Window.MODE_MAXIMIZED, "back to maximized")
	assert_eq(Main.next_window_mode(Window.MODE_FULLSCREEN, Window.MODE_WINDOWED), Window.MODE_WINDOWED, "back to windowed")
	assert_eq(Main.next_window_mode(Window.MODE_FULLSCREEN, Window.MODE_FULLSCREEN), Window.MODE_WINDOWED, "never stuck in fullscreen")
