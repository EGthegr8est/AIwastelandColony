extends "res://tests/framework/test_case.gd"
## The map-art switch in the top bar: the field tablet (art/sonar_tablet_sheet.png) laid on its side, where the Art button was. Off, the map is the clean pixel art; click it and
## its screen turns to a green sonar sweep, with a short blip, and the map is drawn in text glyphs; click it again and it turns back. Styles 1 to 3 are not offered any more.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const Sprites = preload("res://scripts/sprites.gd")
const SonarTablet = preload("res://scripts/sonar_tablet_button.gd")

var main: Node2D
var hud: Node
var tablet: Control


func before_each() -> void:
	Sprites.style = Sprites.CLEAN
	seed(5)
	main = add_autofree(load("res://scenes/main.tscn").instantiate())
	await wait_frames(2)
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	Leaders.offered = [Leaders.fill("builder"), Leaders.fill("raider"), Leaders.fill("trader")]
	_press("New colony")
	_press("Choose")
	await wait_frames(3)
	tablet = hud.sonar_tablet


func after_each() -> void:
	Sprites.style = Sprites.CLEAN   # what the other tests start on
	DirAccess.remove_absolute(Music.settings_path)


func _press(text: String) -> void:
	for b in main.find_children("*", "Button", true, false):
		if b.text.begins_with(text) and b.is_visible_in_tree() and not b.disabled:
			b.pressed.emit()
			return
	fail("no visible button starting with \"%s\"" % text)


func _click(control: Control) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = true
	control._gui_input(e)


# ---------------------------------------------------------------- in the top bar

func test_the_tablet_took_the_art_buttons_place() -> void:
	assert_not_null(tablet)
	assert_eq(tablet.get_script(), SonarTablet)
	for b in main.find_children("*", "Button", true, false):
		assert_false(b.text.begins_with("Art:"), "the Art button is gone")
	var row: Node = tablet.get_parent()
	assert_eq(row.get_child(tablet.get_index() - 1), hud.rad_meter, "after the radiation meter")
	assert_eq(row.get_child(tablet.get_index() + 2), hud.end_button, "then the E cap and the END SEASON window (the Map and Walk buttons are gone)")


func test_it_lies_on_its_side_and_fits_the_bar() -> void:
	assert_almost_eq(tablet.size.x, 76.8, 0.5, "40 x 64 turned a quarter to 64 x 40, drawn 20% bigger in the bar")
	assert_eq(tablet.size.y, 48.0)
	var bar: Rect2 = hud.game_ui[0].get_global_rect()
	assert_true(bar.encloses(tablet.get_global_rect()), "inside the top bar")
	assert_almost_eq(tablet.get_global_rect().get_center().y, bar.get_center().y, 1.5, "in the middle of the bar")
	assert_ne(tablet.tooltip_text, "")


func test_it_is_off_on_the_pixel_art_and_clean_is_what_the_game_starts_on() -> void:
	assert_eq(Sprites.state(), Sprites.CLEAN)
	assert_false(tablet.is_on)
	assert_eq(tablet._sprite.animation, &"off")
	assert_eq(Sprites.style, Sprites.CLEAN)


# ---------------------------------------------------------------- the click

func test_a_click_turns_the_map_to_text_glyphs_and_plays_the_power_on() -> void:
	var flips := [0]
	tablet.switched.connect(func(_on): flips[0] += 1)
	_click(tablet)
	assert_eq(Sprites.state(), 0, "the map is text glyphs at once")
	assert_true(tablet.is_on)
	assert_eq(tablet._sprite.animation, &"power_on")
	assert_eq(flips[0], 1)
	assert_true(tablet.is_busy())
	await wait_seconds(1.6)
	assert_false(tablet.is_busy())
	assert_eq(tablet._sprite.animation, &"on", "and the sonar sweep idles")
	assert_true(tablet._sprite.sprite_frames.get_animation_loop(&"on"))
	assert_eq(Sprites.state(), 0)


func test_a_second_click_turns_it_back_to_the_pixel_art() -> void:
	_click(tablet)
	await wait_seconds(1.6)
	_click(tablet)
	assert_eq(Sprites.state(), Sprites.CLEAN, "the pixel art")
	assert_false(tablet.is_on)
	assert_eq(tablet._sprite.animation, &"power_off")
	await wait_seconds(0.8)
	assert_eq(tablet._sprite.animation, &"off")


func test_a_click_during_the_animation_does_nothing() -> void:
	_click(tablet)
	_click(tablet)
	_click(tablet)
	assert_eq(Sprites.state(), 0)
	assert_true(tablet.is_on)


func test_the_legend_follows_the_map_into_glyphs() -> void:
	_click(tablet)
	await wait_frames(3)
	assert_eq(Sprites.state(), 0)
	assert_true(hud.boxes["Tile"].find_children("*", "TextureRect", true, false).filter(func(r): return r.texture != null and r.texture.get_size() == Vector2(16, 16) and not (r.texture is AtlasTexture and r.texture.atlas == Sprites.animals_texture())).is_empty(), "the legend has no pictures left")


func test_only_the_tablets_own_pixels_are_clickable() -> void:
	var k: float = hud.BAR_ART_SCALE
	for corner in [Vector2(0, 0), Vector2(63, 0), Vector2(0, 39), Vector2(63, 39)]:
		assert_false(tablet._has_point(corner * k), "the empty corner %s" % str(corner))
	assert_true(tablet._has_point(Vector2(32, 20) * k), "the middle of it")
	assert_false(tablet._has_point(Vector2(64, 20) * k))


# ---------------------------------------------------------------- it follows the game

func test_the_legends_buttons_move_the_tablet_without_a_sound() -> void:
	_press("ASCII")
	await wait_frames(3)
	assert_eq(Sprites.state(), 0)
	assert_true(tablet.is_on, "the tablet is on to match")
	assert_eq(tablet._sprite.animation, &"on", "straight into the sweep, no power-on")
	assert_false(tablet.is_busy())
	assert_false(tablet._sfx_on.playing, "no blip: nothing was clicked")
	_press("Pixel art")
	await wait_frames(3)
	assert_false(tablet.is_on)
	assert_eq(tablet._sprite.animation, &"off")
	assert_false(tablet._sfx_off.playing)


func test_the_pixel_art_means_the_tablet_is_off() -> void:
	Sprites.choose(Sprites.CLEAN)
	hud.refresh()
	assert_false(tablet.is_on)
	_click(tablet)
	assert_eq(Sprites.state(), 0)
	await wait_seconds(1.6)
	_click(tablet)
	assert_eq(Sprites.state(), Sprites.CLEAN, "and back from the glyphs it is the pixel art")


# ---------------------------------------------------------------- the blip

func test_the_blip_is_a_short_8_bit_sound_made_for_the_click() -> void:
	var blip: AudioStreamWAV = load(hud.SONAR_TABLET_BLIP)
	assert_not_null(blip)
	assert_eq(blip.mix_rate, 22050)
	assert_eq(blip.loop_mode, AudioStreamWAV.LOOP_DISABLED, "it plays once")
	assert_almost_eq(blip.get_length(), 0.09, 0.01, "about 90 ms")
	assert_eq(tablet.on_sound, blip)
	assert_eq(tablet.off_sound, blip)
	assert_eq(tablet.sound_bus, Music.BUS, "on the music bus: the slider covers it")


func test_a_click_plays_the_blip_either_way() -> void:
	_click(tablet)
	assert_true(tablet._sfx_on.playing, "turning on blips")
	assert_eq(tablet._sfx_on.stream, tablet.on_sound)
	await wait_seconds(1.6)
	assert_false(tablet.is_humming(), "a blip is not a hum: it does not go on")
	_click(tablet)
	assert_true(tablet._sfx_off.playing, "turning off blips")


# ---------------------------------------------------------------- the sheet

func test_every_animation_frame_is_on_the_sheet() -> void:
	var sheet: Texture2D = Sprites.picture(hud.SONAR_TABLET_SHEET)
	assert_eq(sheet.get_size(), Vector2(640, 256), "16 by 4 frames of 40 by 64")
	var cell: Vector2i = tablet.cell_size()
	assert_eq(cell, Vector2i(64, 40))
	var atlas_size := Vector2(tablet._atlas.get_size())
	assert_eq(atlas_size, Vector2(16 * 64, 4 * 40))
	for anim in SonarTablet.TABLET_ANIMS:
		var frames: Array = SonarTablet.TABLET_ANIMS[anim].frames
		assert_eq(tablet._sprite.sprite_frames.get_frame_count(anim), frames.size(), anim)
		for i in frames.size():
			var region: Rect2 = tablet._sprite.sprite_frames.get_frame_texture(anim, i).region
			assert_eq(region.size, Vector2(cell), "%s %d" % [anim, i])
			assert_true(Rect2(Vector2.ZERO, atlas_size).encloses(region), "%s %d is inside the sheet" % [anim, i])
	assert_eq(SonarTablet.TABLET_ANIMS.on.frames.size(), 16, "a sixteen-frame sweep")


func test_the_meter_still_plays_its_own_frames() -> void:
	assert_eq(hud.rad_meter._get_anims(), hud.RadMeter.ANIMS, "the base class's table")
	assert_eq(tablet._get_anims(), SonarTablet.TABLET_ANIMS)
	assert_eq(hud.rad_meter._sprite.sprite_frames.get_frame_count("on"), 8)
	assert_eq(tablet._sprite.sprite_frames.get_frame_count("on"), 16)
