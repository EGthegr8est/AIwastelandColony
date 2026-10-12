extends "res://tests/framework/test_case.gd"
## The music: which track plays when, that the game tracks cycle and the menu track loops, and the
## volume (where 0 is completely off) and its settings file. Tests never play any sound (Music.audible
## is false), but Music still tracks what would be playing.


func before_each() -> void:
	Music.mode = ""
	Music.track = ""
	Music.starts = 0
	Music._queue = []
	Music.set_volume(Music.DEFAULT_VOLUME)


func after_each() -> void:
	Music.set_volume(Music.DEFAULT_VOLUME)


func _bus() -> int:
	return AudioServer.get_bus_index(Music.BUS)


# ---------------------------------------------------------------- the files

func test_tests_make_no_sound_and_leave_the_players_volume_alone() -> void:
	assert_false(Music.audible)
	assert_ne(Music.settings_path, Music.SETTINGS_PATH, "tests must never write the player's settings")


func test_there_is_a_menu_track_and_five_game_tracks() -> void:
	assert_eq(Music.GAME.size(), 5)
	assert_false(Music.GAME.has(Music.MENU), "the menu track isn't part of the game playlist")
	for path in Music.GAME:
		assert_true(path.contains("OST"), path)
	assert_true(Music.MENU.ends_with("wasteland_menu.wav"))


func test_every_track_loads_and_is_a_real_piece_of_music() -> void:
	for path in [Music.MENU] + Music.GAME:
		var s := Music.stream_for(path)
		assert_not_null(s, path)
		assert_gt(s.get_length(), 60.0, "%s is a full track" % path)
		assert_lt(s.get_length(), 130.0, path)


func test_the_menu_track_loops_by_itself_and_the_game_tracks_play_once() -> void:
	var menu := Music.stream_for(Music.MENU)
	assert_eq(menu.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(menu.loop_begin, 0)
	assert_almost_eq(float(menu.loop_end), menu.get_length() * menu.mix_rate, 2.0, "the loop covers the whole track")
	for path in Music.GAME:
		assert_eq(Music.stream_for(path).loop_mode, AudioStreamWAV.LOOP_DISABLED, path)


func test_a_missing_track_is_just_null() -> void:
	assert_null(Music.stream_for("res://audio/no_such_track.wav"))


# ---------------------------------------------------------------- what plays when

func test_the_menu_music_plays_once_and_carries_on() -> void:
	Music.play_menu()
	Music.play_menu()
	Music.play_menu()
	assert_eq(Music.mode, "menu")
	assert_eq(Music.track, Music.MENU)
	assert_eq(Music.starts, 1, "asking again doesn't restart it")


func test_the_game_music_is_never_the_menu_track() -> void:
	Music.play_game()
	for i in 12:
		assert_has(Music.GAME, Music.track)
		Music.next_track()


func test_the_game_tracks_play_through_all_five_before_any_repeats() -> void:
	Music.play_game()
	var played := [Music.track]
	for i in 14:
		Music.next_track()
		played.append(Music.track)
	for shuffle in 3:
		var five := played.slice(shuffle * 5, shuffle * 5 + 5)
		var distinct := {}
		for t in five:
			distinct[t] = true
		assert_eq(distinct.size(), 5, "shuffle %d plays each track once" % shuffle)
	for i in played.size() - 1:
		assert_ne(played[i], played[i + 1], "the same track never plays twice in a row")


func test_asking_for_the_game_music_again_does_not_restart_it() -> void:
	Music.play_game()
	var first := Music.track
	Music.play_game()
	assert_eq(Music.track, first)
	assert_eq(Music.starts, 1)


func test_going_between_the_menu_and_the_game_changes_the_track() -> void:
	Music.play_menu()
	Music.play_game()
	assert_eq(Music.mode, "game")
	assert_has(Music.GAME, Music.track)
	Music.play_menu()
	assert_eq(Music.track, Music.MENU)
	assert_eq(Music.starts, 3)


func test_next_track_only_means_something_in_a_game() -> void:
	Music.play_menu()
	Music.next_track()
	assert_eq(Music.track, Music.MENU)
	assert_eq(Music.starts, 1)


# ---------------------------------------------------------------- the volume

func test_volume_zero_is_completely_off() -> void:
	Music.set_volume(0.0)
	assert_true(AudioServer.is_bus_mute(_bus()), "muted, not just quiet")
	assert_eq(Music.volume_text(), "off")
	Music.set_volume(0.05)
	assert_false(AudioServer.is_bus_mute(_bus()))
	assert_eq(Music.volume_text(), "5%")


func test_the_volume_sets_the_music_bus_and_nothing_else() -> void:
	Music.set_volume(1.0)
	assert_almost_eq(AudioServer.get_bus_volume_db(_bus()), 0.0, 0.01)
	Music.set_volume(0.5)
	assert_almost_eq(AudioServer.get_bus_volume_db(_bus()), -6.02, 0.05, "half the amplitude")
	assert_eq(AudioServer.get_bus_send(_bus()), "Master")
	assert_eq(Music._player.bus, Music.BUS)
	assert_eq(AudioServer.get_bus_volume_db(0), 0.0, "the master bus is left alone")


func test_the_volume_stays_between_off_and_full() -> void:
	Music.set_volume(7.0)
	assert_eq(Music.volume, 1.0)
	Music.set_volume(-3.0)
	assert_eq(Music.volume, 0.0)
	assert_eq(Music.volume_text(), "off")


func test_changing_the_volume_says_so() -> void:
	var seen := watch(Music, "volume_changed")
	Music.set_volume(0.3)
	Music.set_volume(0.0)
	assert_eq(seen.count, 2)


func test_the_volume_is_remembered_between_runs() -> void:
	Music.set_volume(0.35)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Music.settings_path), OK)
	assert_almost_eq(float(cfg.get_value("audio", "music_volume")), 0.35, 0.001)
	Music.volume = 0.9   # as if the game had just started with another volume in it
	Music._load_settings()
	assert_almost_eq(Music.volume, 0.35, 0.001)


func test_off_is_remembered_too() -> void:
	Music.set_volume(0.0)
	Music.volume = 0.9
	Music._load_settings()
	assert_eq(Music.volume, 0.0)


func test_a_nonsense_setting_is_clamped_and_other_settings_are_kept() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", 7.0)
	cfg.set_value("other", "something", "kept")
	cfg.save(Music.settings_path)
	Music._load_settings()
	assert_eq(Music.volume, 1.0)
	Music.set_volume(0.4)
	var again := ConfigFile.new()
	again.load(Music.settings_path)
	assert_eq(again.get_value("other", "something"), "kept")


# ---------------------------------------------------------------- the ending music

func test_the_win_and_defeat_tracks_are_there_and_loop() -> void:
	for path in [Music.WIN, Music.LOSE]:
		var stream := Music.stream_for(path)
		assert_not_null(stream, path)
		assert_gt(stream.get_length(), 30.0, "%s is a whole track" % path.get_file())
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops until the player moves on" % path.get_file())
	assert_ne(Music.WIN, Music.LOSE)


func test_an_ending_starts_its_own_track_and_the_menu_takes_over_after() -> void:
	Music.play_game()
	Music.play_ending(true)
	assert_eq(Music.mode, "win")
	assert_eq(Music.track, Music.WIN)
	var starts := Music.starts
	Music.play_ending(true)
	assert_eq(Music.starts, starts, "the same ending music is not restarted")
	Music.play_ending(false)
	assert_eq(Music.track, Music.LOSE)
	Music.play_menu()
	assert_eq(Music.mode, "menu")
	assert_eq(Music.track, Music.MENU)
