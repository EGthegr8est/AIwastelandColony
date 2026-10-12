extends Node
## Autoload "Music": what plays and how loud.
##   menu   one track, looping, for the title screen and the character selection screen (and the load
##          screen reached from them). It keeps playing across those screens, and isn't restarted.
##   game   every OST track (the five gameplay pieces and the victory and defeat pieces), one after another in a
##          shuffled order, then shuffled again, for as long as a colony is running. A track never plays twice
##          in a row, and the shuffle is remembered between launches, so a new launch carries on through the
##          tracks it has not played yet instead of starting over.
##   win    the victory track, looping, under the two winning ending screens and the stats screen after them
##   lose   the defeat track, looping, under the losing ending screen and its stats, until the player goes back to the menu
## (The victory and defeat tracks are in the game shuffle too. If one is already playing when its ending comes, it
## simply carries on and loops.)
## Going between them crossfades. Everything goes through the "Music" audio bus, so the volume slider
## only affects music. Volume 0 mutes the bus: completely off, not just very quiet. It's remembered in
## user://settings.cfg between runs.
## Tests set `audible` to false (nothing is played, but what would be playing is still tracked) and point
## `settings_path` at their own file.

signal volume_changed(volume: float)

const MENU := "res://audio/wasteland_menu.wav"
const WIN := "res://audio/wasteland_OST_lastcall_Victory.wav"
const LOSE := "res://audio/wasteland_OST_signallost_DEFEAT.wav"
const GAME := [
	"res://audio/wasteland_OST_dread.wav",
	"res://audio/wasteland_OST_breath.wav",
	"res://audio/wasteland_OST_ashfall.wav",
	"res://audio/wasteland_OST_winter.wav",
	"res://audio/wasteland_OST_dustpunk.wav",
	WIN,
	LOSE,
]
const SETTINGS_PATH := "user://settings.cfg"
const BUS := "Music"
const DEFAULT_VOLUME := 0.6
const FADE_SECONDS := 1.2
const SILENT_DB := -60.0

var settings_path := SETTINGS_PATH
var audible := true
var volume := DEFAULT_VOLUME    # 0 (off) to 1
var mode := ""                  # "menu", "game", "win" or "lose": which kind of music is wanted ("" before any is)
var track := ""                 # the file that's playing (or would be, when not audible)
var starts := 0                 # how many times a track has been started (tests watch it)

var _player := AudioStreamPlayer.new()
var _queue: Array = []          # the game tracks still to come in this shuffle (saved with the settings)
var _last_game := ""            # the last game track chosen (saved too): a fresh shuffle never opens with it
var _playing := ""              # the file the player is playing right now
var _fade: Tween


func _ready() -> void:
	if AudioServer.get_bus_index(BUS) == -1:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, BUS)
		AudioServer.set_bus_send(i, "Master")
	_load_settings()
	_apply_volume()
	_player.bus = BUS
	_player.finished.connect(_on_finished)
	add_child(_player)


# ---------------------------------------------------------------- what plays

## The menu music. Already playing? Nothing changes.
func play_menu() -> void:
	_switch("menu")


## The game music. Already playing? Nothing changes.
func play_game() -> void:
	_switch("game")


## The ending music, looping until something else is asked for: the win track or the defeat track.
func play_ending(win: bool) -> void:
	_switch("win" if win else "lose")


func _switch(next: String) -> void:
	if mode == next:
		return
	mode = next
	_choose_track()
	if audible and not (track == _playing and _player.playing):   # already playing it: it carries on, and loops at its end
		_fade_out_then_start()


## Picks the track for the current mode: the menu's one, or the next in the game shuffle.
func _choose_track() -> void:
	if mode == "menu":
		track = MENU
	elif mode == "win":
		track = WIN
	elif mode == "lose":
		track = LOSE
	else:
		track = _next_game_track()
	starts += 1


## The next game track: every OST track in a shuffled order, then a fresh shuffle that doesn't open with the
## one that just finished.
func _next_game_track() -> String:
	if _queue.is_empty():
		_queue = GAME.duplicate()
		_queue.shuffle()
		if _queue.size() > 1 and _queue[0] == _last_game:
			_queue.push_back(_queue.pop_front())
	var next: String = _queue.pop_front()
	_last_game = next
	_save_settings()   # so the next launch carries on from here
	return next


## Moves on to the next game track, as if the one playing had finished.
func next_track() -> void:
	if mode != "game":
		return
	_choose_track()
	if audible:
		_start_stream()


## Does the music wanted now repeat by itself? The menu and ending screens' tracks do. In the game shuffle every track plays
## once, the victory and defeat ones too, then the next one starts.
func loops() -> bool:
	return mode != "game"


func _on_finished() -> void:
	if mode == "game":
		next_track()
	elif mode in ["menu", "win", "lose"]:
		_start_stream()   # a track that didn't loop by itself


func _fade_out_then_start() -> void:
	if _fade != null:
		_fade.kill()
	if _player.playing:
		_fade = create_tween()
		_fade.tween_property(_player, "volume_db", SILENT_DB, FADE_SECONDS)
		_fade.tween_callback(_start_stream)
	else:
		_start_stream()


func _start_stream() -> void:
	var stream := stream_for(track, loops())
	if stream == null:
		return
	if _fade != null:
		_fade.kill()
	_player.stream = stream
	_playing = track
	_player.volume_db = SILENT_DB
	_player.play()
	_fade = create_tween()
	_fade.tween_property(_player, "volume_db", 0.0, FADE_SECONDS)


## A track from the project, ready to play. `looping` says whether it repeats by itself: by default the menu and ending
## tracks do and the rest play once, but the game shuffle asks for the ending tracks to play once too. Once
## Godot has imported the file it loads like any resource. A fresh copy of the project that hasn't been
## opened in the editor yet has no import, so fall back to reading the file directly.
func stream_for(path: String, looping := path in [MENU, WIN, LOSE]) -> AudioStreamWAV:
	var wav: AudioStreamWAV = null
	if ResourceLoader.exists(path):
		var loaded = load(path)
		if loaded is AudioStreamWAV:
			wav = loaded.duplicate()
	if wav == null and FileAccess.file_exists(path) and ClassDB.class_has_method("AudioStreamWAV", "load_from_file"):
		wav = AudioStreamWAV.load_from_file(path)
	if wav == null:
		return null
	if looping:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = roundi(wav.get_length() * wav.mix_rate)   # the whole track, whatever format it was imported as
	else:
		wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	return wav


# ---------------------------------------------------------------- volume

## Sets the music volume, 0 (completely off) to 1, and remembers it.
func set_volume(v: float) -> void:
	volume = clampf(snappedf(v, 0.01), 0.0, 1.0)
	_apply_volume()
	_save_settings()
	volume_changed.emit(volume)


## "off", or "60%".
func volume_text() -> String:
	return "off" if volume <= 0.0 else "%d%%" % roundi(volume * 100.0)


## Volume 0 mutes the bus, so it's silent rather than just quiet.
func _apply_volume() -> void:
	var i := AudioServer.get_bus_index(BUS)
	AudioServer.set_bus_mute(i, volume <= 0.0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(volume, 0.001)))


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		volume = clampf(float(cfg.get_value("audio", "music_volume", DEFAULT_VOLUME)), 0.0, 1.0)
		_last_game = str(cfg.get_value("audio", "last_game_track", ""))
		_queue = []
		for path in cfg.get_value("audio", "game_queue", []):   # the tracks still to come, if they are all ones we have
			if str(path) in GAME and not str(path) in _queue:
				_queue.append(str(path))


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)   # keep anything else in there
	cfg.set_value("audio", "music_volume", volume)
	cfg.set_value("audio", "last_game_track", _last_game)
	cfg.set_value("audio", "game_queue", _queue)
	cfg.save(settings_path)
