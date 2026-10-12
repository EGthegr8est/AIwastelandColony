extends RefCounted
## Project hooks for the test runner: before_run() runs once before any test, after_run() once at the end.

const TEST_SAVE_DIR := "user://test_saves/"
const TEST_SETTINGS := "user://test_settings.cfg"


func before_run(tree: SceneTree) -> void:
	# end_season() autosaves, so point every save at a scratch folder before any test runs
	Game.save_dir = TEST_SAVE_DIR
	# Likewise the music: no sound out of the speakers, and the player's volume setting stays as it is
	Music.audible = false
	Music.settings_path = TEST_SETTINGS
	# Headless runs start with a 64x64 window; give the root the game's real screen size
	tree.root.size = Vector2i(ProjectSettings.get_setting("display/window/size/viewport_width"),
		ProjectSettings.get_setting("display/window/size/viewport_height"))


func after_run(_tree: SceneTree) -> void:
	var dir := DirAccess.open(TEST_SAVE_DIR)
	if dir:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(TEST_SAVE_DIR)
	Game.save_dir = Game.SAVE_DIR
	DirAccess.remove_absolute(TEST_SETTINGS)
	Music.settings_path = Music.SETTINGS_PATH
	Music.audible = true
