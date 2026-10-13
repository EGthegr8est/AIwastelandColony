extends "res://tests/framework/test_case.gd"
## The music: which track plays when, that the game tracks cycle and the menu track loops, and the
## volume (where 0 is completely off) and its settings file. Tests never play any sound (Music.audible
## is false), but Music still tracks what would be playing.


func before_each() -> void:
	Music.mode = ""
	Music.track = ""
	Music.starts = 0
	Music._queue = []
	Music._last_game = ""
	Music._playing = ""
	Music.set_volume(Music.DEFAULT_VOLUME)


func after_each() -> void:
	Music.set_volume(Music.DEFAULT_VOLUME)


func _bus() -> int:
	return AudioServer.get_bus_index(Music.BUS)


# ---------------------------------------------------------------- the files

func test_tests_make_no_sound_and_leave_the_players_volume_alone() -> void:
	assert_false(Music.audible)
	assert_ne(Music.settings_path, Music.SETTINGS_PATH, "tests must never write the player's settings")


func test_there_is_a_menu_track_and_all_eight_ost_tracks_are_in_the_game_playlist() -> void:
	assert_eq(Music.GAME.size(), 8)
	assert_has(Music.GAME, Music.OPENING)
	assert_false(Music.GAME.has(Music.MENU), "the menu track is not part of the game playlist")
	for path in Music.GAME:
		assert_true(path.contains("OST"), path)
	assert_true(Music.MENU.ends_with("wasteland_menu.wav"))
	assert_has(Music.GAME, Music.WIN)
	assert_has(Music.GAME, Music.LOSE)


func test_the_playlist_has_every_ost_file_in_the_audio_folder() -> void:
	var found := []
	for file in DirAccess.get_files_at("res://audio"):
		var name := file.trim_suffix(".import").trim_suffix(".remap")
		if name.begins_with("wasteland_OST_") and name.ends_with(".wav") and not "res://audio/" + name in found:
			found.append("res://audio/" + name)
	found.sort()
	var playlist: Array = Music.GAME.duplicate()
	playlist.sort()
	assert_eq(playlist, found, "a new OST track dropped in the folder has to be added to Music.GAME")


func test_every_track_loads_and_is_a_real_piece_of_music() -> void:
	for path in [Music.MENU] + Music.GAME:
		var s := Music.stream_for(path)
		assert_not_null(s, path)
		assert_gt(s.get_length(), 60.0, "%s is a full track" % path)
		assert_lt(s.get_length(), 160.0, path)


func test_the_menu_track_loops_by_itself_and_the_game_tracks_play_once() -> void:
	var menu := Music.stream_for(Music.MENU)
	assert_eq(menu.loop_mode, AudioStreamWAV.LOOP_FORWARD)
	assert_eq(menu.loop_begin, 0)
	assert_almost_eq(float(menu.loop_end), menu.get_length() * menu.mix_rate, 2.0, "the loop covers the whole track")
	for path in Music.GAME:
		assert_eq(Music.stream_for(path, false).loop_mode, AudioStreamWAV.LOOP_DISABLED, path)
	for path in Music.GAME.filter(func(p): return p != Music.WIN and p != Music.LOSE):
		assert_eq(Music.stream_for(path).loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s plays once whichever way it is asked for" % path)


func test_the_ending_tracks_loop_at_the_endings_but_play_once_in_the_game_shuffle() -> void:
	for path in [Music.WIN, Music.LOSE]:
		assert_eq(Music.stream_for(path).loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s loops by default (the ending screens)" % path)
		assert_eq(Music.stream_for(path, false).loop_mode, AudioStreamWAV.LOOP_DISABLED, "%s plays once in the shuffle" % path)
	Music.play_game()
	assert_false(Music.loops(), "the game shuffle plays each track once")
	Music.play_ending(true)
	assert_true(Music.loops())
	Music.play_menu()
	assert_true(Music.loops())


func test_an_ending_that_comes_while_its_track_is_in_the_shuffle_keeps_it_and_loops() -> void:
	for ending in [{"win": true, "track": Music.WIN, "mode": "win"}, {"win": false, "track": Music.LOSE, "mode": "lose"}]:
		Music.mode = "game"
		Music.track = ending.track   # the shuffle happens to be on the victory (or defeat) piece when the game ends
		Music.play_ending(ending.win)
		assert_eq(Music.mode, ending.mode)
		assert_eq(Music.track, ending.track, "the same track, carried on")
		assert_true(Music.loops(), "and from here it repeats until the player leaves the ending screens")


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


func test_the_game_tracks_play_through_all_eight_before_any_repeats() -> void:
	Music.play_game()
	var played := [Music.track]
	for i in 31:
		Music.next_track()
		played.append(Music.track)
	for shuffle in 4:
		var eight := played.slice(shuffle * 8, shuffle * 8 + 8)
		var distinct := {}
		for t in eight:
			distinct[t] = true
		assert_eq(distinct.size(), 8, "shuffle %d plays each track once" % shuffle)
	for i in played.size() - 1:
		assert_ne(played[i], played[i + 1], "the same track never plays twice in a row")


# ---------------------------------------------------------------- the opening track

func test_the_canyon_track_is_a_real_wav_in_the_audio_folder_and_in_the_playlist() -> void:
	assert_eq(Music.OPENING, "res://audio/wasteland_OST_canyon.wav")
	var s := Music.stream_for(Music.OPENING)
	assert_not_null(s)
	assert_gt(s.get_length(), 100.0, "a full track, about two minutes")
	assert_eq(s.loop_mode, AudioStreamWAV.LOOP_DISABLED, "it plays once in the shuffle like the others")


func test_a_new_colony_opens_with_the_canyon_track_whatever_the_shuffle_says() -> void:
	for s in 12:
		seed(s)
		Music.mode = ""
		Music._queue = []
		Music._last_game = Music.GAME[s % Music.GAME.size()]
		Music.play_menu()
		Music.play_opening()
		assert_eq(Music.mode, "game")
		assert_eq(Music.track, Music.OPENING, "seed %d" % s)


func test_after_the_opening_the_other_seven_play_once_each_before_it_comes_round_again() -> void:
	Music.play_menu()
	Music.play_opening()
	var rest := []
	for i in 7:
		Music.next_track()
		rest.append(Music.track)
	var distinct := {}
	for t in rest:
		distinct[t] = true
	assert_eq(distinct.size(), 7, "seven different tracks")
	assert_false(distinct.has(Music.OPENING), "the canyon track is not among them")
	Music.next_track()   # a fresh shuffle of all eight
	assert_ne(Music.track, rest[6], "it never repeats the last one")
	var seen := {Music.track: true}
	for i in 7:
		Music.next_track()
		seen[Music.track] = true
	assert_eq(seen.size(), 8, "and the canyon track is in the next shuffle with the rest")


func test_a_new_colony_started_from_a_game_in_progress_opens_with_it_again() -> void:
	Music.play_game()
	Music.next_track()
	var starts := Music.starts
	Music.play_opening()
	assert_eq(Music.track, Music.OPENING)
	assert_eq(Music.starts, starts + 1, "it starts over, rather than carrying on")


func test_loading_a_game_does_not_play_the_opening_track() -> void:
	Music._queue = [Music.GAME[0], Music.GAME[1]]
	Music.play_menu()
	Music.play_game()   # what loading a colony does
	assert_eq(Music.track, Music.GAME[0], "it carries on with the shuffle")


func test_the_opening_is_saved_with_the_shuffle() -> void:
	Music.play_opening()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Music.settings_path), OK)
	assert_eq(cfg.get_value("audio", "last_game_track"), Music.OPENING)
	assert_eq(cfg.get_value("audio", "game_queue").size(), 7)


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


# ---------------------------------------------------------------- the shuffle is remembered between launches

func _launch_again() -> void:
	# What a fresh launch does: forget what is in memory and read the settings file.
	Music._queue = []
	Music._last_game = ""
	Music._load_settings()


func test_the_shuffle_is_saved_as_it_goes() -> void:
	Music.play_game()
	Music.next_track()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Music.settings_path), OK)
	assert_eq(cfg.get_value("audio", "last_game_track"), Music.track)
	assert_eq(cfg.get_value("audio", "game_queue"), Music._queue)
	assert_eq(Music._queue.size(), 6, "8 tracks, 2 played")
	assert_almost_eq(float(cfg.get_value("audio", "music_volume")), Music.volume, 0.001, "the volume is still kept alongside")


func test_a_new_launch_carries_on_through_the_tracks_it_has_not_played() -> void:
	Music.play_game()
	Music.next_track()
	Music.next_track()
	for i in 3:
		Music.next_track()
	var left: Array = Music._queue.duplicate()
	var last := Music.track
	_launch_again()
	assert_eq(Music._queue, left)
	assert_eq(Music._last_game, last)
	Music.mode = ""
	Music.play_game()
	var next := [Music.track]
	for i in left.size() - 1:
		Music.next_track()
		next.append(Music.track)
	var wanted := left.duplicate()
	wanted.sort()
	next.sort()
	assert_eq(next, wanted, "the rest of that shuffle, nothing heard again before it is used up")


func test_a_new_shuffle_never_opens_with_the_track_that_was_playing_last() -> void:
	for s in range(1, 60):
		seed(s)
		Music._queue = []
		Music._last_game = Music.GAME[s % Music.GAME.size()]
		var first: String = Music._next_game_track()
		assert_ne(first, Music.GAME[s % Music.GAME.size()], "seed %d" % s)


func test_a_settings_file_with_a_stranger_in_its_queue_loads_only_the_real_tracks() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", 0.4)
	cfg.set_value("audio", "game_queue", [Music.GAME[2], "res://audio/not_a_track.wav", Music.GAME[2], Music.GAME[4]])
	cfg.set_value("audio", "last_game_track", Music.GAME[0])
	cfg.save(Music.settings_path)
	_launch_again()
	assert_eq(Music._queue, [Music.GAME[2], Music.GAME[4]], "the stranger and the repeat are dropped")
	assert_eq(Music._last_game, Music.GAME[0])
	assert_almost_eq(Music.volume, 0.4, 0.001)


func test_a_settings_file_from_before_the_shuffle_was_saved_still_loads() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_volume", 0.3)
	cfg.save(Music.settings_path)
	_launch_again()
	assert_eq(Music._queue, [])
	assert_eq(Music._last_game, "")
	assert_almost_eq(Music.volume, 0.3, 0.001)
	Music.play_game()
	assert_has(Music.GAME, Music.track)
