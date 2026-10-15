extends RefCounted
## A quick check that everything the game reads while it runs is really there: the pixel-art atlas, the title
## screen and logo, every music track, the data. It's for a built copy of the game, where files can be
## missing or end up somewhere the game can't read them (the game then quietly falls back to text glyphs, or
## plays no music). Run it from a command prompt:
##     WastelandColony.console.exe -- --selftest
## It prints one line per check ("ok ..." or "FAIL ...") and exits with 1 if any failed.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")


static func requested() -> bool:
	return "--selftest" in OS.get_cmdline_user_args()


## One line per check.
static func run() -> Array:
	var out := []
	_check(out, Sprites.available(), "pixel-art atlas loads (art/atlas16.png and atlas16.json)")
	_check(out, Sprites.names().size() == 26, "the atlas has all 26 sprites (has %d)" % Sprites.names().size())
	_check(out, not Sprites.rects().is_empty() or Sprites.style == 0, "sprite rectangles are ready for the map")
	_check(out, Sprites.animals_available() and Sprites.animals_texture().get_size() == Vector2(80, 32), "the animals' picture loads (art/animals.png, 3 pictures of 16 x 16 and the frog's 32 x 32)")
	_check(out, Sprites.building_atlas_texture() != null and Sprites.building_ids().size() == 22, "the building pictures load (art/building_atlas.png and .json, 22 of them)")
	_check(out, Sprites.poi_available(), "points-of-interest atlas loads (art/poi_atlas.png and .json)")
	_check(out, Sprites.poi_kinds().size() == Data.POIS.size(), "a sprite for each of the %d kinds of site" % Data.POIS.size())
	var frames = load("res://d20_dice/d20_sprite_frames.tres") if ResourceLoader.exists("res://d20_dice/d20_sprite_frames.tres") else null
	_check(out, frames is SpriteFrames and frames.has_animation(&"roll_20") and frames.has_animation(&"idle"), "the d20 roll animations load")
	var title := Sprites.title()
	_check(out, title != null and title.get_size() == Vector2(1920, 1080), "title screen picture loads (1920 x 1080)")
	var logo := Sprites.logo()
	_check(out, logo != null and logo.get_size() == Sprites.LOGO_CROP.size, "logo picture loads and crops")
	var tracks := [Music.MENU] + Music.GAME
	for path in tracks:
		var stream := Music.stream_for(path)
		_check(out, stream != null and stream.get_length() > 30.0, "music track loads: %s" % path.get_file())
	for path in [Music.WIN, Music.LOSE]:
		var ending_track := Music.stream_for(path)
		_check(out, ending_track != null and ending_track.get_length() > 30.0 and ending_track.loop_mode == AudioStreamWAV.LOOP_FORWARD,
			"ending track loads and loops: %s" % path.get_file())
	for kind in Data.ENDING_SCREENS:
		var pic := Sprites.picture(Data.ENDING_SCREENS[kind].art)
		_check(out, pic != null and pic.get_size() == Vector2(1200, 980), "ending picture loads (1200 x 980): %s" % kind)
	for version in ["day", "night", "fallout"]:
		var mile := Sprites.picture(Data.HOLLOW_MILE[version])
		_check(out, mile != null and mile.get_size() == Vector2(1152, 768), "Hollow Mile picture loads (1152 x 768): %s" % version)
	var menu := Music.stream_for(Music.MENU)
	_check(out, menu != null and menu.loop_mode == AudioStreamWAV.LOOP_FORWARD, "the menu track loops")
	_check(out, Data.LEADERS.size() == 3 and Data.TERRAIN.size() == 12, "game data is there")
	_check(out, _can_write_settings(), "can write to the user folder (saves and settings go there)")
	out.append("info: Godot %s, %s, %s, %s" % [Engine.get_version_info().string, OS.get_name(),
		RenderingServer.get_video_adapter_name(), "exported build" if OS.has_feature("template") else "run from the editor"])
	return out


static func failed(lines: Array) -> bool:
	return lines.any(func(l): return l.begins_with("FAIL"))


static func _check(out: Array, ok: bool, what: String) -> void:
	out.append(("ok   " if ok else "FAIL ") + what)


## The saves and the music setting live in the user folder: make sure the game can write there.
static func _can_write_settings() -> bool:
	var path := "user://selftest.tmp"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("ok")
	f.close()
	DirAccess.remove_absolute(path)
	return true
