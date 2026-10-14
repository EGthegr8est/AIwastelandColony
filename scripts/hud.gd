extends CanvasLayer
## All the UI, built in code with an amber terminal look.
## Every panel is rebuilt from scratch when the game changes, which keeps things simple.

const Data = preload("res://scripts/data.gd")
const Portrait = preload("res://scripts/portrait.gd")
const Icons = preload("res://scripts/icons.gd")
const Geiger = preload("res://scripts/geiger.gd")
const RadMeter = preload("res://scripts/rad_meter_button.gd")
const FuelGauge = preload("res://scripts/fuel_gauge.gd")
const Sprites = preload("res://scripts/sprites.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")
const Daylight = preload("res://scripts/daylight.gd")
const D20 = preload("res://scripts/d20.gd")
const D20Visit = preload("res://scripts/d20_visit.gd")
const D20Data = preload("res://scripts/d20_data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const D20DiceScene = preload("res://d20_dice/D20Dice.tscn")
const DICE_SCALE := 3          # the pixel-art die is 64 x 80: shown at 3x it is 192 x 240
const DICE_SPEED := 1.25       # playback speed of the roll animation (1.0 is about 0.75 seconds)
const DICE_HOLD_MSEC := 1000   # the landed number stays up at least this long before a click moves on
const LEGEND_ICON_SCALE := 3   # screen pixels per pixel of legend art
const LOGO_WIDTH := 440        # how wide the slab-stack logo is on the character selection screen
const CARD_WIDTH := 440        # one leader card on that screen, and the face on it (480 px pictures shown at half size)
const CARD_FACE := 240
const RESOURCE_ICON := Vector2i(18, 16)   # the little picture beside each resource in the top bar: 8 x 8 doubled, behind a 2 px gap
const LEADER_FACE := 192       # the small picture (48 px) in the colony panel, shown at 4x
const CLASS_COLORS := {"raider": Color("ff8c3c"), "builder": Color("6ad0e8"), "trader": Color("e8d84a")}   # not the perks' green or the flaws' red
const AMBER := Color("ffb642")
const BRIGHT := Color("ffd88a")
const DIM := Color("9a6a2a")
const RED := Color("ff6a4a")
const GREEN := Color("a8d060")
const BG := Color(0.07, 0.05, 0.03, 0.95)
const SLOTS := ["slot1", "slot2", "slot3", "autosave"]
const BOTTOM_HEIGHT := 190
const RAD_METER_SHEET := "res://art/rad_meter_sheet.png"   # the radiation view's switch in the top bar: this meter, laid on its side, 64 x 40 at its own pixel size

var root := Control.new()
var top_text := RichTextLabel.new()
var tabs := TabContainer.new()
var boxes := {}           # tab name -> VBoxContainer
var _icon_tags := {}      # resource id -> the BBCode image tag for it (or "" if it has no picture)
var stale_tabs := {}      # tab names whose contents are out of date: only the tab being looked at is rebuilt on a change
var legend_cache: VBoxContainer   # the legend (what the Tile tab shows with nothing picked), kept between rebuilds: it took about 22 ms to make
var legend_key := ""              # what it was made for: the art style and the Night switch are all that change it
var strike_armed := Vector2i(-1, -1)   # the tile whose Nuclear strike button has been pressed once: the next press sends the bomber
var log_text := RichTextLabel.new()
var bottom := HBoxContainer.new()        # the strip along the bottom: selected party, then the log
var party_panel := PanelContainer.new()  # who you have selected, StarCraft style: a portrait each
var party_row := HBoxContainer.new()
var geiger_panel := PanelContainer.new()  # next to the party: the radiation where a scouting party stands
var geiger := Geiger.new()
var geiger_note := VBoxContainer.new()
var game_ui: Array = []   # panels hidden while the main menu is up
var menu := ColorRect.new()
var menu_panel := PanelContainer.new()   # the box in the middle of the menu overlay
var menu_box := VBoxContainer.new()
var title_screen := ColorRect.new()      # the main menu: the title art, with the buttons over its dark lower edge
var title_art := TextureRect.new()
var title_buttons := HBoxContainer.new()
var music_sliders: Array = []            # [slider, reading] for each volume slider on screen
var view_button: Button
var rad_meter: Control   # the radiation view's switch (a RadMeter): the artist's survey meter, which plays its power-on and power-off animations when clicked
var art_button: Button
var walk_button: Button
var end_button: Button
var dice: Control                       # the one clickable d20 (see d20_dice/), moved into whichever panel shows it
var dice_holder := Control.new()         # gives the scaled die its room in a panel
var dice_phase := "idle"                 # "idle" (the ROLL face), "rolling" or "landed" (the number is up)
var dice_uid := -1                       # the party the die is for
var dice_hold_until := 0                 # when a click may move on from the landed number (msec)
var dice_lines: Array = []               # what the last roll said, shown under the landed die
var ending_screen := ColorRect.new()     # the ending picture, over everything; a click moves on to the stats
var ending_art := TextureRect.new()
var ending_title := Label.new()          # stands in for the picture's own title if the picture can't be read
var hollow_screen := ColorRect.new()     # the Hollow Mile picture, over everything: the first time your scouts see the old highway; a click closes it
var hollow_fit := AspectRatioContainer.new()
var hollow_art := TextureRect.new()
var hollow_title := Label.new()          # a title card that stands in for the picture if it can't be read
var hollow_note := Label.new()
var side_panel: PanelContainer           # the panel of tabs down the right: shorter while a point of interest's picture sits under it
var scene_panel := PanelContainer.new()  # the picture of the point of interest you have picked, in the bottom right corner (see _sync_scene)
var scene_art := TextureRect.new()
var scene_name := Label.new()
var stats_screen := ColorRect.new()      # what you did, and the way back to the main menu
var stats_box := VBoxContainer.new()


## The legend is kept out of the tree between rebuilds (the Tile tab shows a picked tile instead): free it with the HUD.
func _exit_tree() -> void:
	if legend_cache != null and legend_cache.get_parent() == null:
		legend_cache.free()
	legend_cache = null


func _ready() -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_bar()
	_build_side_panel()
	_build_log()
	_build_scene_panel()
	_build_menu()
	_build_dice()
	_build_ending()
	_build_hollow_screen()
	SeasonReplay.load_mode()   # the speed of the season replay you last chose, if you chose one
	Daylight.load_setting()    # and whether you switched the night off
	Game.game_ended.connect(_on_game_ended)
	Game.hollow_mile_found.connect(_on_hollow_found)
	Game.changed.connect(refresh, CONNECT_DEFERRED)
	Music.volume_changed.connect(_sync_music_sliders)
	Game.tile_selected.connect(func(): tabs.current_tab = 0)
	for p in game_ui:
		p.visible = false
	show_main_menu()


# ---------------------------------------------------------------- layout

func _panel(anchors: Array, offsets: Array) -> PanelContainer:
	var p := PanelContainer.new()
	p.anchor_left = anchors[0]
	p.anchor_top = anchors[1]
	p.anchor_right = anchors[2]
	p.anchor_bottom = anchors[3]
	p.offset_left = offsets[0]
	p.offset_top = offsets[1]
	p.offset_right = offsets[2]
	p.offset_bottom = offsets[3]
	root.add_child(p)
	game_ui.append(p)
	return p


func _build_top_bar() -> void:
	var p := _panel([0, 0, 1, 0], [0, 0, 0, 58])
	var row := HBoxContainer.new()
	p.add_child(row)
	top_text.bbcode_enabled = true
	top_text.fit_content = true
	top_text.scroll_active = false
	top_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(top_text)
	_music_row(row, false)   # a fixed size: the resource text beside it needs the room
	view_button = _button(row, "Map: you", Game.cycle_view)
	view_button.tooltip_text = "Switch whose knowledge the map shows: what you know, what the Rust Kings know, or everything (no fog, for debugging)"
	_build_rad_meter(row)
	art_button = _button(row, "Art: style 1", _cycle_art)
	art_button.tooltip_text = "Switch the map and legend between the four pixel-art styles (4 is the clean look) and the old text glyphs"
	walk_button = _button(row, "Walk: Normal", _cycle_walk)
	walk_button.tooltip_text = "How fast the map plays back each season's walking: Normal, Fast or Off (no animation at all). A click, Space or Enter skips it."
	end_button = _button(row, "END SEASON", end_season_pressed)
	_button(row, "Save", show_save_menu)
	_button(row, "Load", show_load_menu)
	_button(row, "Menu", show_main_menu)


## The radiation view's switch: the survey meter lying on its side (a quarter turn clockwise, so its ground shadow still falls downward) to fit the bar. Clicking it flips
## the view at once and plays the meter's power animation; the meter is clickable only on its own pixels.
func _build_rad_meter(row: HBoxContainer) -> void:
	rad_meter = RadMeter.new()
	rad_meter.turn = 1
	rad_meter.pixel_scale = 1
	rad_meter.sheet = Sprites.picture(RAD_METER_SHEET)
	rad_meter.tooltip_text = "Radiation view: tint the tiles your scouts have measured by how hot they are"
	rad_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rad_meter.switched.connect(_on_rad_meter_switched)
	rad_meter.settled.connect(func(_on): _sync_rad_meter())
	row.add_child(rad_meter)


func _on_rad_meter_switched(on: bool) -> void:
	if Game.show_radiation != on:
		Game.toggle_radiation_view()


## The meter shows whether the radiation view is on: if something else changed it (a new game, a load) while no animation is playing, the meter jumps to match.
func _sync_rad_meter() -> void:
	if not rad_meter.is_busy() and rad_meter.is_on != Game.show_radiation:
		rad_meter.set_on(Game.show_radiation, true)


func _build_side_panel() -> void:
	var p := _panel([1, 0, 1, 1], [-410, 64, -6, -6])
	side_panel = p
	p.add_child(tabs)
	for tab_name in ["Tile", "Upgrades", "Colony", "Diplomacy"]:
		var scroll := ScrollContainer.new()
		scroll.name = tab_name
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		tabs.add_child(scroll)
		boxes[tab_name] = box
	tabs.tab_changed.connect(_on_tab_changed)


func _build_log() -> void:
	bottom.anchor_top = 1.0
	bottom.anchor_right = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_left = 6
	bottom.offset_top = -BOTTOM_HEIGHT
	bottom.offset_right = -416
	bottom.offset_bottom = -6
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)
	game_ui.append(bottom)
	party_row.add_theme_constant_override("separation", 14)
	party_panel.add_child(party_row)
	party_panel.visible = false
	bottom.add_child(party_panel)
	var geiger_box := VBoxContainer.new()
	geiger_box.add_theme_constant_override("separation", 0)
	geiger_box.add_child(geiger)
	geiger_box.add_child(geiger_note)
	geiger_panel.add_child(geiger_box)
	geiger_panel.visible = false
	bottom.add_child(geiger_panel)
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_text.bbcode_enabled = true
	log_text.scroll_following = true
	p.add_child(log_text)
	bottom.add_child(p)


## The corner picture: a point of interest's scene in an orange line, as the leader faces have, with the site's name under it. _sync_scene fills it and shows it.
func _build_scene_panel() -> void:
	scene_panel.anchor_left = 1.0
	scene_panel.anchor_top = 1.0
	scene_panel.anchor_right = 1.0
	scene_panel.anchor_bottom = 1.0
	scene_panel.offset_left = -410   # the width of the side panel above it
	scene_panel.offset_right = -6
	scene_panel.offset_top = -6
	scene_panel.offset_bottom = -6
	scene_panel.visible = false   # not in game_ui: _sync_scene says when it shows (and the menus cover it as they cover the rest)
	root.add_child(scene_panel)
	var col := VBoxContainer.new()
	scene_panel.add_child(col)
	var frame := PanelContainer.new()
	frame.name = "SceneFrame"
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = AMBER
	line.set_border_width_all(2)
	line.set_content_margin_all(2)   # the picture sits inside the line, not under it
	frame.add_theme_stylebox_override("panel", line)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(frame)
	scene_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	scene_art.stretch_mode = TextureRect.STRETCH_SCALE
	scene_art.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # crisp: the 1152 x 768 picture is 4 screen pixels to each art pixel, drawn at a quarter size
	scene_art.custom_minimum_size = Data.POI_SCENE_SIZE
	frame.add_child(scene_art)
	scene_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(scene_name)


## What the corner picture shows for the tile you have picked: {"art", "name", "color"}, or {} for nothing. A point of interest your colony has seen shows its own picture
## (a party searching the site shows none: its panel, with the die and what the roll found, is longer than the side already and needs all the room). A seen tile of the old
## highway shows the Hollow Mile picture by the same rules as the first sighting's: the grey one in a day season (always, with the night switched off), at night the orange dusk
## one, or the green one when the tile's reading, once your scouts have measured it, is high radiation. No picture on file, no picture.
func _picked_scene() -> Dictionary:
	var c := Game.selected
	if not Game.in_bounds(c) or not Game.knows_tile(Data.PLAYER, c):
		return {}
	var building: String = Game.memory[Data.PLAYER][Game.idx(c)][1]
	if building in Data.HOLLOW_MILE.tiles:
		var spec: Dictionary = Data.HOLLOW_MILE
		var version := _hollow_version(Game.is_measured(c) and Game.radiation(c) >= spec.rad_high)
		var mile := Sprites.picture(spec[version])
		return {} if mile == null else {"art": mile, "name": spec.name, "color": spec[version + "_color"]}
	if building == "" or not Data.BUILDINGS[building].has("poi"):
		return {}
	var kind: String = Data.BUILDINGS[building].poi
	var anchor := Game.poi_anchor(c)
	if Units.units.any(func(p): return p.job == "scav" and p.target == anchor and p.stage == "site"):
		return {}
	var art: Texture2D = Sprites.picture(Data.POI_SCENES[kind]) if Data.POI_SCENES.has(kind) else null
	return {} if art == null else {"art": art, "name": Data.BUILDINGS[building].name, "color": Data.BUILDINGS[building].color}


## The picture of the point of interest or old highway you have picked goes in the bottom right corner, under the Tile panel, and the Tile panel gets that much shorter.
## Only while the Tile tab is showing: the other tabs keep the whole side.
func _sync_scene() -> void:
	var scene := _picked_scene() if Game.in_game and tabs.get_tab_title(tabs.current_tab) == "Tile" else {}
	scene_panel.visible = not scene.is_empty()
	if scene.is_empty():
		side_panel.offset_bottom = -6
		return
	scene_art.texture = scene.art
	scene_name.text = scene.name
	scene_name.add_theme_color_override("font_color", scene.color)
	var height := scene_panel.get_combined_minimum_size().y
	scene_panel.offset_top = -6.0 - height
	side_panel.offset_bottom = -6.0 - height - 6.0


func _build_menu() -> void:
	menu.color = Color(0, 0, 0, 0.75)
	menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(menu)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu.add_child(center)
	menu_panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(menu_panel)
	menu_panel.add_child(menu_box)
	_build_title()


## The title screen. The art is 16:9, so it sits in a 16:9 box that the window fits around it (black bars
## if the window is another shape), and the buttons are placed as fractions of that box: over the dark
## band between the COLONY lettering and the credit line.
func _build_title() -> void:
	title_screen.color = Color.BLACK
	title_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_screen.visible = false
	root.add_child(title_screen)
	var fit := AspectRatioContainer.new()
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	fit.ratio = 16.0 / 9.0
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	title_screen.add_child(fit)
	var stage := Control.new()
	fit.add_child(stage)
	title_art.texture = Sprites.title()
	title_art.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	title_art.stretch_mode = TextureRect.STRETCH_SCALE
	title_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # a picture, not pixel art: smooth it when it's scaled
	title_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(title_art)
	title_buttons.anchor_left = 0.3
	title_buttons.anchor_right = 0.7
	title_buttons.anchor_top = 0.885
	title_buttons.anchor_bottom = 0.93
	title_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	title_buttons.add_theme_constant_override("separation", 14)
	stage.add_child(title_buttons)
	# The volume slider, in the dark bottom corner beside the credit line
	var volume := _music_row(stage)
	volume.anchor_left = 0.74
	volume.anchor_right = 0.98
	volume.anchor_top = 0.945
	volume.anchor_bottom = 0.985
	volume.offset_left = 0
	volume.offset_right = 0
	volume.offset_top = 0
	volume.offset_bottom = 0


# ---------------------------------------------------------------- widgets

func _clear(box: Container) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _label(box: Container, text: String, color := AMBER) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", color)
	box.add_child(l)
	return l


func _header(box: Container, text: String) -> void:
	box.add_child(HSeparator.new())
	_label(box, "== %s ==" % text.to_upper(), BRIGHT)


## A button that runs `action`. If `blocked` isn't empty the button is disabled and shows why.
func _button(box: Container, text: String, action: Callable, blocked := "") -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = blocked != ""
	b.tooltip_text = blocked
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if box is VBoxContainer:
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.pressed.connect(action)
	box.add_child(b)
	return b


func _make_theme() -> Theme:
	var th := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	th.default_font = font
	th.default_font_size = 15

	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.border_color = DIM
	panel.set_border_width_all(1)
	panel.set_content_margin_all(8)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())

	var btn := StyleBoxFlat.new()
	btn.bg_color = Color("2a1d0e")
	btn.border_color = DIM
	btn.set_border_width_all(1)
	btn.content_margin_left = 8
	btn.content_margin_right = 8
	btn.content_margin_top = 3
	btn.content_margin_bottom = 3
	var hover: StyleBoxFlat = btn.duplicate()
	hover.bg_color = Color("4a3214")
	hover.border_color = AMBER
	var off: StyleBoxFlat = btn.duplicate()
	off.bg_color = Color("16110a")
	off.border_color = Color("3a2a14")
	for type in ["Button"]:
		th.set_stylebox("normal", type, btn)
		th.set_stylebox("hover", type, hover)
		th.set_stylebox("pressed", type, hover)
		th.set_stylebox("disabled", type, off)
		th.set_stylebox("focus", type, StyleBoxEmpty.new())
	# Sliders: a dark groove that fills with amber up to the grabber
	var groove := StyleBoxFlat.new()
	groove.bg_color = Color("2a1d0e")
	groove.border_color = DIM
	groove.set_border_width_all(1)
	groove.content_margin_top = 3
	groove.content_margin_bottom = 3
	var filled: StyleBoxFlat = groove.duplicate()
	filled.bg_color = DIM
	var filled_bright: StyleBoxFlat = groove.duplicate()
	filled_bright.bg_color = AMBER
	th.set_stylebox("slider", "HSlider", groove)
	th.set_stylebox("grabber_area", "HSlider", filled)
	th.set_stylebox("grabber_area_highlight", "HSlider", filled_bright)
	for icon in ["grabber", "grabber_highlight", "grabber_disabled"]:
		var knob := Image.create(8, 16, false, Image.FORMAT_RGBA8)
		knob.fill(BRIGHT if icon == "grabber_highlight" else AMBER)
		th.set_icon(icon, "HSlider", ImageTexture.create_from_image(knob))
	th.set_stylebox("tab_selected", "TabContainer", hover)
	th.set_stylebox("tab_unselected", "TabContainer", btn)
	th.set_stylebox("tab_hovered", "TabContainer", hover)

	th.set_color("font_color", "Button", AMBER)
	th.set_color("font_hover_color", "Button", BRIGHT)
	th.set_color("font_pressed_color", "Button", BRIGHT)
	th.set_color("font_disabled_color", "Button", Color("6b5230"))
	th.set_color("font_color", "Label", AMBER)
	th.set_color("default_color", "RichTextLabel", AMBER)
	th.set_color("font_selected_color", "TabContainer", BRIGHT)
	th.set_color("font_unselected_color", "TabContainer", DIM)
	th.set_color("font_hovered_color", "TabContainer", BRIGHT)
	th.set_color("font_color", "TooltipLabel", AMBER)
	var tip: StyleBoxFlat = panel.duplicate()
	th.set_stylebox("panel", "TooltipPanel", tip)
	return th


# ---------------------------------------------------------------- menus

## Opens the menu panel (in the middle of the screen) under `heading`. `with_logo` puts the slab-stack
## logo at the top instead of the text banner.
func _open_menu(heading: String, with_logo := false) -> void:
	_clear(menu_box)
	menu_panel.custom_minimum_size = Vector2(520, 0)
	title_screen.visible = false
	menu.visible = true
	var logo: Texture2D = Sprites.logo() if with_logo else null
	menu_panel.remove_theme_stylebox_override("panel")
	if logo != null:
		# The logo has its own near-black background: paint the panel the same, so it doesn't show as a box
		var style: StyleBoxFlat = root.theme.get_stylebox("panel", "PanelContainer").duplicate()
		style.bg_color = Sprites.logo_background()
		menu_panel.add_theme_stylebox_override("panel", style)
		var pic := TextureRect.new()
		pic.texture = logo
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		pic.custom_minimum_size = Vector2(LOGO_WIDTH, float(LOGO_WIDTH) * logo.get_height() / logo.get_width())
		menu_box.add_child(pic)
	else:
		var art := _label(menu_box, "▲ ░▒▓ WASTELAND COLONY ▓▒░ ▲", BRIGHT)
		art.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := _label(menu_box, heading, DIM)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_box.add_child(HSeparator.new())


func _close_menu() -> void:
	menu.visible = false
	title_screen.visible = false
	for p in game_ui:
		p.visible = Game.in_game
	if Game.in_game:
		Music.play_game()   # a colony is running: the game music (if it's already on, it carries on)
	refresh()


## The main menu: the title screen, with Resume (if a colony is running), New colony, Load game and Quit.
## Without the title art it's the same choices in a plain panel. Before a colony is running it plays the
## menu music.
func show_main_menu() -> void:
	if not Game.in_game:
		Music.play_menu()
	if title_art.texture == null:
		_open_menu("A post-nuclear colony sandbox")
		_add_title_buttons(menu_box)
		return
	menu.visible = false
	title_screen.visible = true
	_clear(title_buttons)
	_add_title_buttons(title_buttons)
	for b in title_buttons.get_children():
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_buttons.get_child(0).grab_focus()   # so Enter picks the first one


func _add_title_buttons(box: Container) -> void:
	if Game.in_game:
		_button(box, "Resume", _close_menu)
	_button(box, "New colony", show_new_colony)
	_button(box, "Load game", func(): show_load_menu(true))
	_button(box, "Quit", get_tree().quit)


## Character selection: the logo above three randomly made leaders side by side, each with a face, a name, the class's
## buffs, two perks and a flaw. The three are made once per launch (Leaders.offer) and Reroll draws new ones.
func show_new_colony() -> void:
	if not Game.in_game:
		Music.play_menu()   # already playing, from the title screen: it carries on
	_open_menu("Choose your leader", true)
	menu_panel.custom_minimum_size = Vector2((CARD_WIDTH + 10) * 3 + 30, 0)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	menu_box.add_child(row)
	for leader in Leaders.offer():
		_leader_card(row, leader)
	menu_box.add_child(HSeparator.new())
	_music_row(menu_box)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	menu_box.add_child(bottom)
	_button(bottom, "Reroll leaders", func(): Leaders.offer(true); show_new_colony())
	_button(bottom, "Back", show_main_menu)


## One leader on the selection screen. Clicking anywhere on the card picks them.
func _leader_card(row: HBoxContainer, leader: Dictionary) -> void:
	var card := PanelContainer.new()
	card.set_meta("leader_card", true)
	card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.add_theme_stylebox_override("panel", _card_style(false))
	card.mouse_entered.connect(func(): card.add_theme_stylebox_override("panel", _card_style(true)))
	card.mouse_exited.connect(func(): card.add_theme_stylebox_override("panel", _card_style(false)))
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_pick_leader(leader))
	row.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	_leader_face(box, leader, CARD_FACE, false)
	var who := _label(box, leader.name, BRIGHT)
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	who.add_theme_font_size_override("font_size", 18)
	var cls: Dictionary = Data.LEADERS[leader["class"]]
	var kind := _label(box, cls.name, CLASS_COLORS[leader["class"]])
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for buff in cls.buffs:
		_label(box, buff).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(HSeparator.new())
	for line in Leaders.quirk_lines(leader):
		var perk: bool = line.kind == "perk"
		_label(box, "%s %s: %s" % ["+" if perk else "-", line.name, line.text], GREEN if perk else RED)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	_button(box, "Choose", func(): _pick_leader(leader))


func _card_style(hover: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1c1610") if hover else Color("140f0a")
	box.border_color = AMBER if hover else DIM
	box.set_border_width_all(2)
	box.set_content_margin_all(10)
	return box


## A leader's face, centred and scaled with crisp pixels. `small` uses their small picture (the colony panel).
func _leader_face(box: Container, leader: Dictionary, size: int, small: bool) -> void:
	var frame := PanelContainer.new()   # an orange line round the picture, like the rest of the UI's lines
	frame.name = "LeaderFrame"
	var line := StyleBoxFlat.new()
	line.bg_color = Color(0, 0, 0, 0)
	line.border_color = AMBER
	line.set_border_width_all(2)
	line.set_content_margin_all(2)   # the picture sits inside the line, not under it
	frame.add_theme_stylebox_override("panel", line)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(frame)
	var face := TextureRect.new()
	face.texture = Leaders.portrait(leader, small)
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	face.custom_minimum_size = Vector2(size, size)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(face)


func _pick_leader(leader: Dictionary) -> void:
	Game.new_game(leader["class"], leader)
	Music.play_opening()   # a new colony opens with the canyon track; _close_menu then finds the game music already on
	_close_menu()


## Who leads the colony, for the colony panel: their face, name and class buffs, and below them what each perk and the
## flaw is doing for (and against) the colony, so it can be looked up mid game.
func _leader_block(box: VBoxContainer) -> void:
	var info: Dictionary = Game.leader_info
	var cls: Dictionary = Data.LEADERS[Game.leader]
	if info.get("name", "") != "":
		_leader_face(box, info, LEADER_FACE, true)
		_label(box, info.name, BRIGHT).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(box, "%s: %s" % [cls.name, ", ".join(cls.buffs)], CLASS_COLORS[Game.leader])
	for line in Leaders.quirk_lines(info):
		var perk: bool = line.kind == "perk"
		_label(box, "%s %s: %s" % ["+" if perk else "-", line.name, line.text], GREEN if perk else RED)
	box.add_child(HSeparator.new())


func show_save_menu() -> void:
	_open_menu("Save game")
	for slot in SLOTS:
		if slot == "autosave":
			continue
		_button(menu_box, "%s  [%s]" % [slot, Game.save_info(slot)], func(): Game.save_game(slot); _close_menu())
	_button(menu_box, "Back", _close_menu)


## `from_title`: opened from the main menu, so Back goes back there (the top bar's Load button goes
## back to the game).
func show_load_menu(from_title := false) -> void:
	if not Game.in_game:
		Music.play_menu()
	_open_menu("Load game")
	for slot in SLOTS:
		var info := Game.save_info(slot)
		_button(menu_box, "%s  [%s]" % [slot, info], func(): Game.load_game(slot); _close_menu(),
			"No save here" if info == "empty" else "")
	_music_row(menu_box)
	_button(menu_box, "Back", show_main_menu if from_title or not Game.in_game else _close_menu)


# ---------------------------------------------------------------- refresh

func refresh() -> void:
	if not Game.in_game:
		return
	_refresh_top()
	# Rebuilding all four panels cost about 90 ms a change, three of them out of sight. Only the tab being looked
	# at is rebuilt now; the others are marked stale and rebuild when you switch to them.
	for tab_name in boxes:
		stale_tabs[tab_name] = true
	_refresh_tab(tabs.current_tab)
	_sync_scene()
	_refresh_party()
	log_text.text = "\n".join(Game.log_lines)


## Rebuilds one side panel tab (by its position) and marks it up to date.
func _refresh_tab(index: int) -> void:
	if index < 0 or index >= tabs.get_tab_count():
		return
	var tab_name := tabs.get_tab_title(index)
	match tab_name:
		"Tile":
			_refresh_tile()
		"Upgrades":
			_refresh_upgrades()
		"Colony":
			_refresh_colony()
		"Diplomacy":
			_refresh_diplomacy()
	stale_tabs.erase(tab_name)


## Switching to a tab that changed while it was out of sight brings it up to date.
func _on_tab_changed(index: int) -> void:
	if Game.in_game and stale_tabs.has(tabs.get_tab_title(index)):
		_refresh_tab(index)
	_sync_scene()


## The tiny picture after a resource's amount in the top bar, as BBCode: art/icons/res_<id>_bar.png, the 8 x 8 picture
## doubled with a 2 px clear gap on its left, so the amount does not touch it. Nothing if the picture is missing, so the bar
## still reads. (The gap is all that sits between the amount and the picture: the pictures already use up room the bar needs.)
func _resource_icon(id: String) -> String:
	if not _icon_tags.has(id):
		var path := "res://art/icons/res_%s_bar.png" % id
		_icon_tags[id] = "[img=%dx%d]%s[/img]" % [RESOURCE_ICON.x, RESOURCE_ICON.y, path] if ResourceLoader.exists(path) else ""
	return _icon_tags[id]


## "Year 3, Autumn (day)": the season and whether the map is in daylight or moonlight (just the season with the Night switch off).
func _season_text() -> String:
	return Game.season_name() + (" (%s)" % Daylight.word(Game.season) if Daylight.enabled else "")


func _refresh_top() -> void:
	var t := "[color=#ffd88a]%s[/color]   Pop [b]%d[/b]/%d   Troops %d   Prisoners %d   Leader: %s\n" % [
		_season_text(), Game.pop, Game.pop_cap(), Game.troops, Game.prisoners, Leaders.label(Game.leader_info)]
	for r in Data.RESOURCES:
		t += "%s [color=#ffd88a]%d[/color]%s " % [r, Game.res[r], _resource_icon(r)]   # name, amount, picture; one space before the next
	top_text.text = t
	var views := {Data.PLAYER: "Map: you", Data.AI: "Map: Rust Kings", Data.NONE: "Map: no fog"}   # short: the top bar is full
	view_button.text = views[Game.view]
	_sync_rad_meter()
	art_button.text = "Art: " + Sprites.choice_name(Sprites.state())
	walk_button.text = "Walk: " + SeasonReplay.mode_text()


## The parties of yours standing on the selected tile, each with a portrait per survivor.
func _refresh_party() -> void:
	_clear(party_row)
	var parties := []
	if Game.in_bounds(Game.selected):
		parties = Units.units_at(Game.selected).filter(func(u): return u.owner == Data.PLAYER and not u.survivors.is_empty())
	var here := parties.duplicate()   # the ones standing on the selected tile
	# A picked scouting party stays in the panel while you look around for somewhere to send it
	var picked := Units.unit_by_id(Game.selected_scout)
	if not picked.is_empty() and not picked.survivors.is_empty() and not parties.any(func(p): return p.id == picked.id):
		parties.push_front(picked)
	party_panel.visible = not parties.is_empty()
	for i in parties.size():
		if i > 0:
			party_row.add_child(VSeparator.new())
		party_row.add_child(_party_card(parties[i]))
	_refresh_geiger(here.filter(func(u): return u.job == "scout"))


## The Geiger counter shows the radiation of the tile a scouting party is standing on, and
## what staying there would do to them.
func _refresh_geiger(scouts: Array) -> void:
	_clear(geiger_note)
	geiger_panel.visible = not scouts.is_empty()
	if scouts.is_empty():
		return
	var c := Game.selected
	var r := Game.radiation(c)
	geiger.reading = r
	geiger.known = Game.is_measured(c)
	var band: Array = Game.rad_band(r)
	var shield: float = Data.MOVERS[scouts[0].mover].shield
	var per_season := maxf(r * shield - Data.RAD_SAFE, 0.0) * Game.dose_rate()
	_small_label(geiger_note, band[0].to_upper() + ("  shield x%.1f" % shield if shield < 1.0 else ""), band[1])
	if per_season <= 0.0:
		_small_label(geiger_note, "safe to stay", GREEN)
	else:
		_small_label(geiger_note, "+%d poison/season" % roundi(per_season), band[1])


func _party_card(u: Dictionary) -> HBoxContainer:
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 10)
	for s in u.survivors:
		card.add_child(_portrait_slot(s))
	card.add_child(_mover_badge(u))
	if u.has("fuel"):
		card.add_child(_gauge_box(u))
	var kind: Dictionary = Units.kind_info(Units.glyph_kind(u))
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(210, 0)
	card.add_child(info)
	var is_picked: bool = u.id == Game.selected_scout
	_label(info, "%s %s%s" % [kind.glyph, Data.EXPEDITIONS[u.job].name, "  [picked]" if is_picked else ""], BRIGHT)
	_label(info, "%s, %s" % [Data.MOVERS[u.mover].name, Units.stage_text(u)], DIM)
	for s in u.survivors:
		var bad: bool = s.hunger >= Data.STARVING_AT or Units.sick_level(s) >= 2
		_label(info, Units.survivor_line(s), RED if bad else AMBER)
	if u.job == "scout":
		var uid: int = u.id
		var buttons := HBoxContainer.new()
		buttons.add_theme_constant_override("separation", 4)
		info.add_child(buttons)
		if u.stage != "back":
			_button(buttons, "Recall to camp", func(): Units.recall_scouts(uid))
		if is_picked:
			_button(buttons, "Deselect", Game.deselect_scout).tooltip_text = "Esc. Go back to routes from your HQ"
		else:
			_button(buttons, "Pick", func(): Game.pick_scout(uid)).tooltip_text = "Show its route, coloured by how far its food goes"
	if u.job == "scout" or not u.carry.is_empty():
		card.add_child(VSeparator.new())
		card.add_child(_inventory_box(u))
	return card


## What a party is carrying: a scouting party's food pack and how long it feeds them, whatever it's
## hauling home, and how heavy that is against what it can carry.
func _inventory_box(u: Dictionary) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(170, 0)
	box.add_theme_constant_override("separation", 2)
	_label(box, "Inventory", BRIGHT)
	if u.job == "scout":
		var total := Units.food_total(u)
		var days := Units.food_days(u)
		var tone := GREEN if days > 2.0 * Data.SEASON_DAYS else (AMBER if days > Data.SEASON_DAYS else RED)
		_label(box, "Food: %s" % Units.food_text(u), tone)
		box.add_child(_bar(clampf(total / float(Data.SCOUT_PACK), 0.0, 1.0), tone, "%d food in the pack" % total))
		_small_label(box, "lasts %d days" % int(days) if total > 0 else "pack empty: going hungry", tone)
	if not u.carry.is_empty():
		_label(box, "Hauling: %s" % Game.cost_text(u.carry))
	var weight := Units.load_weight(u)
	var capacity := Units.load_capacity(u)
	var slow := Units.load_slowdown(u)
	var ratio := weight / capacity if capacity > 0.0 else INF
	var load_tone := GREEN if ratio <= 0.75 else (AMBER if ratio <= 1.0 else RED)
	_label(box, "Load %d / %d" % [roundi(weight), roundi(capacity)], load_tone)
	box.add_child(_bar(clampf(ratio, 0.0, 1.0), load_tone,
		"Carrying %d of the %d this party can carry (%d per person, plus %d for how it travels). Past that it walks slower." % [
			roundi(weight), roundi(capacity), roundi(Data.CARRY_PER_PERSON), roundi(Data.CARRY_BY_MOVER.get(u.mover, 0.0))]))
	if slow > 1.0:
		_small_label(box, "overloaded: x%.1f slower" % slow, RED)
	return box


## The vehicle's fuel gauge (a dashboard dial for a war rig, a cockpit dial for a plane, a brass
## sight tube for a boat) with the reading under it. The warning light blinks when the tank is low.
func _gauge_box(u: Dictionary) -> VBoxContainer:
	var tank: int = Data.VEHICLE_FUEL[u.mover].tank
	var low := Units.fuel_low(u)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.tooltip_text = "%s fuel: %.1f of %d. Run dry and the %s is lost, and the crew go on foot." % [
		Data.MOVERS[u.mover].name, u.fuel, tank, Data.MOVERS[u.mover].name.to_lower()]
	var gauge := FuelGauge.new()
	gauge.setup("plane" if u.mover == "bomber" else u.mover, u.fuel / float(tank), low)   # a bomber has the cockpit dial too
	col.add_child(gauge)
	var reading := _label(col, "Fuel %.1f / %d" % [u.fuel, tank], RED if low else DIM)
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return col


## How the party travels, as a small icon in a frame with its name under it.
func _mover_badge(u: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("1a120a")
	style.border_color = DIM
	style.set_border_width_all(2)
	style.set_content_margin_all(3)
	frame.add_theme_stylebox_override("panel", style)
	var pic := TextureRect.new()
	pic.texture = Icons.texture(u.mover)
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = Vector2(Icons.SIZE, Icons.SIZE) * 3
	frame.add_child(pic)
	col.add_child(frame)
	var name_label := _label(col, Data.MOVERS[u.mover].name, DIM)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.tooltip_text = "Travelling %s" % Data.MOVERS[u.mover].by
	return col


## A framed portrait with the survivor's name, a health bar and a hunger bar under it.
func _portrait_slot(s: Dictionary) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.tooltip_text = Units.survivor_line(s)
	var starving: bool = s.hunger >= Data.STARVING_AT or Units.sick_level(s) >= 3
	var frame := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Portrait.BG
	style.border_color = RED if starving else AMBER
	style.set_border_width_all(2)
	style.set_content_margin_all(2)
	frame.add_theme_stylebox_override("panel", style)
	var pic := TextureRect.new()
	pic.texture = Portrait.texture(s.face, s.age, s.hunger, Units.sick_level(s), s.get("hurt", false))
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = Vector2(Portrait.W, Portrait.H) * Portrait.SHOW_SCALE
	frame.add_child(pic)
	col.add_child(frame)
	var name_label := _label(col, s.name, RED if starving else BRIGHT)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Health (radiation poisons it away), then food: full when fed, a third left means starving
	var sick := Units.sick_level(s)
	col.add_child(_bar(s.hp / Data.SURVIVOR_HP, Color("e0506a") if sick == 0 else Color("c060e8"),
		"Health %d/%d%s" % [ceili(s.hp), Data.SURVIVOR_HP, ", " + Units.sick_text(s) if sick > 0 else ""]))
	col.add_child(_bar(1.0 - s.hunger / float(Data.STARVE_DEATH), GREEN if s.hunger == 0 else (AMBER if s.hunger < Data.STARVING_AT else RED),
		"Food: " + Units.hunger_text(s)))
	return col


func _small_label(box: Container, text: String, color := AMBER) -> Label:
	var l := _label(box, text, color)
	l.add_theme_font_size_override("font_size", 13)
	return l


## A thin bar, `fill` (0..1) of it colored.
func _bar(fill: float, color: Color, tip: String) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	bar.custom_minimum_size = Vector2(0, 6)
	bar.tooltip_text = tip
	var full := ColorRect.new()
	full.color = color
	full.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full.size_flags_stretch_ratio = maxf(fill, 0.001)
	bar.add_child(full)
	var empty := ColorRect.new()
	empty.color = Color("2a1d0e")
	empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty.size_flags_stretch_ratio = maxf(1.0 - fill, 0.001)
	bar.add_child(empty)
	return bar


## One legend line: the pixel-art sprite and what it means. If the art can't be loaded it falls back to
## the old text glyph.
func _legend_row(box: VBoxContainer, sprite: Texture2D, glyph: String, text: String, color: Color, px := Sprites.SIZE) -> void:
	if sprite == null:
		_label(box, "%s  %s" % [glyph, text], color)
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var pic := TextureRect.new()
	pic.texture = sprite
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.custom_minimum_size = Vector2(px, px) * (LEGEND_ICON_SCALE if px == Sprites.SIZE else 2)
	pic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(pic)
	var label := _label(row, text, color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## A "Music" volume slider with its reading ("off", or "60%"). Slide it all the way down for no music at
## all. Every slider (title screen, top bar, menus) shows the same volume.
func _music_row(box: Control, fill_width := true) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var title := _label(row, "Music" if fill_width else "♪", DIM)   # the top bar is short of room: just a note
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.set_value_no_signal(Music.volume)
	slider.custom_minimum_size = Vector2(110 if fill_width else 64, 0)
	if fill_width:
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.tooltip_text = "Music volume. All the way down is completely off."
	slider.value_changed.connect(Music.set_volume)
	row.add_child(slider)
	var reading := _label(row, Music.volume_text(), DIM)
	reading.autowrap_mode = TextServer.AUTOWRAP_OFF
	reading.custom_minimum_size = Vector2(44 if fill_width else 40, 0)
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	reading.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_sliders.append([slider, reading])
	return row


## Moves every music slider (and its reading) to the current volume. The ones in menus that have been
## closed are gone by now: forget them.
func _sync_music_sliders(_volume: float) -> void:
	music_sliders = music_sliders.filter(func(s): return is_instance_valid(s[0]))
	for s in music_sliders:
		s[0].set_value_no_signal(Music.volume)
		s[1].text = Music.volume_text()
		s[1].add_theme_color_override("font_color", RED if Music.volume <= 0.0 else DIM)


## Each sprite comes in four styles: these buttons flip the whole legend between them.
func _legend_style_row(box: VBoxContainer) -> void:
	if not Sprites.available():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var title := _label(row, "Art style:", DIM)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF   # it would squash into a column of single letters
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for n in Sprites.CHOICES:
		var b := _button(row, "%d" % n if n > 0 else "ASCII", func(): _set_art_style(n),
			"Showing this" if n == Sprites.state() else "")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER


## The Night switch: on fades the map between day and night each season, off keeps it day.
func _legend_night_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var title := _label(row, "Night:", DIM)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title.tooltip_text = "Each season the map fades between daylight and moonlight. Switch it off to keep it day."
	for on in [true, false]:
		var b := _button(row, "On" if on else "Off", func(): _set_night(on), "Showing this" if on == Daylight.enabled else "")
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _set_night(on: bool) -> void:
	Daylight.set_enabled(on)
	Game.changed.emit()


## Switches the legend and the map between the four art styles and the old text glyphs.
func _set_art_style(n: int) -> void:
	Sprites.choose(n)
	Game.changed.emit()   # redraws the map (and, a moment later, every panel)


func _cycle_art() -> void:
	Sprites.cycle()
	Game.changed.emit()


## Normal, Fast or Off for the season replay.
func _cycle_walk() -> void:
	SeasonReplay.cycle()
	walk_button.text = "Walk: " + SeasonReplay.mode_text()
	Game.skip_replay()


## END SEASON. While the map is still playing the last season (or a march) back, the press only skips that: it does not
## end another season behind your back.
func end_season_pressed() -> void:
	if Game.replaying:
		Game.skip_replay()
	else:
		Game.end_season()


## The legend: what each picture on the map means. It stays the same until the art style or the Night switch changes (they are all that does,
## and the buttons in it show them), so it is made once for each and kept: building it took about 22 ms, on every change of the game while
## nothing was picked.
func _legend() -> VBoxContainer:
	var key := "%d %s" % [Sprites.state(), Daylight.enabled]
	if legend_cache != null and legend_key == key:
		return legend_cache
	if legend_cache != null:
		legend_cache.free()   # not in the tree: _refresh_tile took it out
	legend_cache = VBoxContainer.new()
	legend_cache.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	legend_key = key
	var box := legend_cache
	_legend_style_row(box)
	_legend_night_row(box)
	for id in Data.TERRAIN:
		var t: Dictionary = Data.TERRAIN[id]
		var slow := Game.speed_text(id)
		_legend_row(box, Sprites.terrain(id), t.glyph[0], "%s  %s%s" % [t.name, Game.cost_text(t.yield) if not t.yield.is_empty() else "", "  (%s)" % slow if slow != "" else ""], t.color)
	_legend_row(box, Sprites.texture(Sprites.FORD), Data.FORD.glyph, "%s: foot and horseback can wade it" % Data.FORD.name, Data.FORD.color)
	_legend_row(box, Sprites.road_icon(false), Data.BUILDINGS["road"].glyph, "Road: ground parties take 0.6 times as long (you and the Rust Kings build them, and anyone can use them)", Data.BUILDINGS["road"].color)
	_legend_row(box, Sprites.road_icon(true), Data.BUILDINGS["old_road"].glyph, "Old highway: 0.8 times as long, but raiders lie in wait on it", Data.BUILDINGS["old_road"].color)
	for id in ["bridge", "old_bridge"]:
		var span: Dictionary = Data.BUILDINGS[id]
		_legend_row(box, Sprites.building(id), span.glyph, "%s: %s" % [span.name, "every ground party can cross (you build it out from your bank)" if id == "bridge" else "the one place every kind of party can cross"], span.color)
	_legend_row(box, Sprites.slope("gentle"), "─│┌┐", "Gentle slope (a %s every 10 m): slows everyone a little" % ("ledge" if Sprites.clean() else "line"), AMBER)
	_legend_row(box, Sprites.slope("steep"), "═║╔╗", "Steep incline: war rigs can't climb it, foot and horses cross slowly", AMBER)
	for mover in Data.TRAVEL_PREVIEW:
		_label(box, " ●    %s route from your HQ to the tile you click" % Data.MOVERS[mover].name, Data.MOVERS[mover].color)
	_label(box, " ●    Click a scouting party to see its route from where it stands: white while its food lasts, yellow as it runs low, red once it's gone", Color("ffe03a"))
	for kind in Data.UNITS:
		_legend_row(box, Sprites.unit(kind), Data.UNITS[kind].glyph, Data.UNITS[kind].name, Data.UNITS[kind].color)
	_legend_row(box, null, Data.SOLDIER.glyph, Data.SOLDIER.name + " (your troops: hunt with them)", Data.SOLDIER.color)
	for cls in Data.TRIBE_CLASSES:
		_legend_row(box, Sprites.camp(cls), Data.TRIBE_CLASSES[cls].glyph, "%s camp" % Data.TRIBE_CLASSES[cls].name, Data.TRIBE_CLASSES[cls].color)
	for kind in Data.ANIMALS:
		var spec: Dictionary = Data.ANIMALS[kind]
		_legend_row(box, Sprites.animal(kind), spec.glyph, spec.name + (" (hunt it for meat)" if kind == "deer" else " (dangerous: hunt it to make the land safe)"), spec.color, Sprites.ANIMAL_SIZE)
	_legend_row(box, Sprites.animal("frog"), Data.FROG.glyph, Data.FROG.name + " (a boss: only one, and it sleeps)", Data.FROG.color, Sprites.ANIMAL_SIZE)
	for kind in Data.POIS:
		var building: Dictionary = Data.BUILDINGS["poi_" + kind]
		_legend_row(box, Sprites.poi_sprite(kind), building.glyph, building.name, building.color, Sprites.POI_SIZE)
	_label(box, "   Black: never explored. Click it to scout.", DIM)
	_label(box, "   Dark: explored but out of sight. Shows what was there last time.", DIM)
	return legend_cache


func _refresh_tile() -> void:
	var box: VBoxContainer = boxes["Tile"]
	_detach_dice()   # the die lives on between rebuilds: take it out before the panel is cleared
	if legend_cache != null and legend_cache.get_parent() == box:
		box.remove_child(legend_cache)   # and so does the legend
	_clear(box)
	var c := Game.selected
	Game.set_strike_preview(Vector2i(-1, -1))   # the red square goes with the button that showed it
	if strike_armed != c:
		strike_armed = Vector2i(-1, -1)
	if not Game.in_bounds(c):
		_label(box, "Click a tile on the map.\n\nWASD / arrows: pan\nMouse wheel: zoom\nRight-drag: pan\nF11: fullscreen")
		_header(box, "Legend")
		box.add_child(_legend())
		return
	_label(box, "Tile %d,%d" % [c.x, c.y], BRIGHT)
	# The panel always shows what YOUR colony knows about the tile
	if not Game.knows_tile(Data.PLAYER, c):
		_label(box, "Unexplored wasteland. Anything could be out there.")
		_scout_travel_line(box, c)
		_scout_orders(box, c)
		_recon_button(box, c)
		return
	var known: Array = Game.memory[Data.PLAYER][Game.idx(c)]
	var seen := Game.in_sight(Data.PLAYER, c)
	var terrain: Dictionary = Data.TERRAIN[Game.tile(c)["t"]]
	var owners := ["Nobody", "You", "The Rust Kings", "Dustwell"]
	_label(box, Game.terrain_name(c) + ("" if seen else "  (out of sight, last seen)"))
	if Game.is_ford(c):
		_label(box, Data.FORD.desc, DIM)
	elif Game.tile(c)["t"] == "water":
		_label(box, "Deep water: only boats and planes cross it. Foot, horseback and war rigs need a ford or a bridge.", DIM)
	_label(box, "Owner: %s" % owners[known[0]])
	_label(box, "Height: %+d m" % Game.tile(c)["z"])
	var ground_speed := Game.speed_text(Game.tile(c)["t"]) if not Game.is_ford(c) else ""
	if ground_speed != "":
		_label(box, "Ground: " + ground_speed, DIM)
	_label(box, "Radiation: " + Game.reading_text(c), Game.rad_band(Game.radiation(c))[1] if Game.is_measured(c) else DIM)
	var slope: String = Game.slopes[Game.idx(c)]
	if slope == "steep":
		_label(box, "Steep incline: war rigs can't climb it. Foot and horses cross slowly.", RED)
	elif slope == "gentle":
		_label(box, "Gentle slope: slows everyone a little.", DIM)
	_scout_travel_line(box, c)
	if not Game.preview.is_empty():
		_label(box, "Travel from your HQ:")
		_travel_lines(box, Game.preview)
	if not terrain.yield.is_empty():
		_label(box, "Yields: %s per season" % Game.cost_text(terrain.yield))
	var cat := Game.catastrophe_at(c)
	if not cat.is_empty():
		var kind: Dictionary = Data.CATASTROPHES[cat.kind]
		_label(box, "%s, %d: %s. %s" % [cat.name, cat.year, kind.name, kind.desc], DIM)
	if known[1] != "":
		var b: Dictionary = Data.BUILDINGS[known[1]]
		_label(box, "%s %s: %s" % [b.glyph, b.name, b.desc], b.color)
		if known[1] == "old_road" and seen and known[0] in [Data.NONE, Data.PLAYER]:
			_repair_controls(box, c)
		if known[0] == Data.PLAYER and known[1] == "refinery":
			_refinery_controls(box, c)
		if known[0] == Data.PLAYER and known[1] == "drug_factory":
			_drug_factory_block(box)
		if known[0] == Data.PLAYER and known[1] != "hq" and not b.has("poi") and b.get("buildable", true):
			_button(box, "Demolish", func(): Game.demolish(c))
	for u in Units.units_at(c):
		if u.owner == Data.PLAYER or seen:
			var kind: Dictionary = Units.kind_info(Units.glyph_kind(u))
			if u.job == "band":
				_label(box, "%s Raider band here (strength %d)!" % [kind.glyph, u.strength], kind.color)
			else:
				_label(box, "%s Your %s, %s (%d crew)" % [kind.glyph, Data.EXPEDITIONS[u.job].name.to_lower(),
					Units.stage_text(u), u.crew], kind.color)
				_party_details(box, u)
	var tribe := Units.tribe_at(c)
	if not tribe.is_empty():
		_tribe_info(box, tribe)
	var animal := Units.animal_at(c)
	if not animal.is_empty() and seen:
		_animal_block(box, animal)
	if Units.frog_at(c) and seen:
		_frog_block(box)
	if known[1] != "" and Data.BUILDINGS[known[1]].has("poi"):
		_poi_block(box, c)
	var party_here: bool = Units.units.any(func(p): return p.job == "scav" and p.target == c and p.stage == "site")
	if Game.tile(c)["t"] == "ruins" and not party_here:   # a party at the ruins has its own Scavenge panel above
		_header(box, "Scavenge")
		var state: String = Game.tile(c)["r"]
		if state == "picked":
			_label(box, "Picked clean.", DIM)
		else:
			if state == "rogue_seen":
				_label(box, "A rogue raider holds these ruins.", RED)
			else:
				_label(box, "Unsearched. Pre-war ruins can hide booby traps or rogue raiders.", DIM)
			_expedition_buttons(box, "scav", c)
	if Game.tile(c)["t"] == "crater" and not party_here:   # a party at the crater has its own panel above
		_crater_block(box, c)
	if known[0] == Data.PLAYER and known[1] == "port":
		_header(box, "River trade")
		var e: Dictionary = Data.EXPEDITIONS["boat"]
		_button(box, "%s (%d crew, %s)" % [e.verb, e.crew, Units.send_cost_text("boat", "boat")],
			func(): Units.send("boat", "boat", c, -1, c), Units.send_status("boat", "boat", c, -1, c))
		var tank := Units.tank_size("boat", "boat")
		if tank > 0 and Units.boat_trip_fuel(c) > tank:
			_label(box, "   Too far from a river mouth: the trip burns about %.1f fuel and the tank holds %d. The boat would run dry on the way home, be lost, and the crew walk back." % [
				Units.boat_trip_fuel(c), tank], RED)
	if not seen:
		_scout_orders(box, c)
		_recon_button(box, c)
		return
	_recon_button(box, c)
	_scout_orders(box, c)

	var t: Dictionary = Game.tile(c)
	if t["o"] != Data.PLAYER:
		var why := Game.claim_status(c)
		if t["b"] != "old_bridge":
			_button(box, "Claim tile (%s)" % Game.cost_text(Game.claim_cost(c)), func(): Game.claim(c), why)
			if why != "":
				_label(box, why, DIM)
		if t["b"] == "" and t["o"] == Data.NONE:
			# free ground beside your land (or a road that reaches it): a bridge over water, a road over land
			var options := []
			for id in ["bridge", "road"]:
				var here := Game.build_status(id, c)
				if not here in ["Not your land", "Wrong terrain", "Can't build on water", "Can't be built", "Tile already has a building"]:
					options.append([id, here])
			if not options.is_empty():
				_header(box, "Build")
				for option in options:
					var span: Dictionary = Data.BUILDINGS[option[0]]
					_button(box, "%s %s (%s)" % [span.glyph, span.name, Game.cost_text(span.cost)], func(): Game.build(option[0], c), option[1])
					_label(box, "   " + (span.desc if option[1] == "" else option[1]), DIM)
	elif t["b"] == "":
		_header(box, "Build")
		for id in Data.BUILDINGS:
			var b: Dictionary = Data.BUILDINGS[id]
			var why := Game.build_status(id, c)
			if why in ["Can't be built", "Wrong terrain", "Can't build on water", "Must stand on the riverbank"]:
				continue
			_button(box, "%s %s (%s)" % [b.glyph, b.name, Game.cost_text(b.cost)], func(): Game.build(id, c), why)
			_label(box, "   " + (b.desc if why == "" else why), DIM)


## A point of interest: scavenged as one tile whichever of its four tiles you click. Its picked-clean state is
## on all four, and a party goes to its top-left tile.
func _poi_block(box: VBoxContainer, c: Vector2i) -> void:
	var anchor := Game.poi_anchor(c)
	_header(box, "Scavenge")
	if Game.tile(anchor)["r"] == "picked":
		_label(box, "Picked clean.", DIM)
		return
	if Units.units.any(func(p): return p.job == "scav" and p.target == anchor and p.stage == "site"):
		return   # the party standing here has its own panel above
	var stock := Game.silo_stock(anchor)
	if stock > 0:   # an earlier party found more warheads than it could carry
		_label(box, "Searched. %d unfired %s still in the silo: send a party that can carry %s (a nuke weighs %d). There is nothing to roll." % [
			stock, "nuke is" if stock == 1 else "nukes are", "it" if stock == 1 else "them", int(Data.ITEM_WEIGHT.nuke)], AMBER)
		_expedition_buttons(box, "scav", anchor)
		return
	_label(box, "Unsearched. Takes one party.", DIM)
	_expedition_buttons(box, "scav", anchor)


## The old highway can be repaired into a road for a little stone: the ambushes there end, and the tile is quicker.
func _repair_controls(box: VBoxContainer, c: Vector2i) -> void:
	var why := Game.repair_status(c)
	_button(box, "Repair into a road (%s)" % Game.cost_text(Data.HIGHWAY.repair), func(): Game.repair(c), why)
	_label(box, "   " + ("Ends the ambushes on this tile and makes it 0.6 times as long, for everyone." if why == "" else why), DIM)


## A refinery's switch: whether it's running, and the button that turns it on or off.
func _refinery_controls(box: VBoxContainer, c: Vector2i) -> void:
	var on := Game.refinery_running(c)
	if on:
		_label(box, "   RUNNING: turns %d veg into %d fuel each season, unless that would leave too little to eat." % [
			Data.REFINERY_VEG, Game.refinery_fuel()], GREEN)
	else:
		_label(box, "   OFF: makes no fuel and uses no veg until you start it.", RED)
	_button(box, "Stop refinery" if on else "Start refinery (%d veg a season)" % Data.REFINERY_VEG,
		func(): Game.set_refinery(c, not on))


# ---------------------------------------------------------------- the ending

## The ending picture and the stats screen, both over everything else and hidden until the game ends.
func _build_ending() -> void:
	ending_screen.color = Color.BLACK
	ending_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	ending_screen.visible = false
	ending_screen.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under it can be clicked
	ending_screen.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_ending_next())
	root.add_child(ending_screen)
	var fit := AspectRatioContainer.new()   # the pictures are 1200 x 980: black bars if the window is another shape
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	fit.ratio = 1200.0 / 980.0
	fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_screen.add_child(fit)
	ending_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ending_art.stretch_mode = TextureRect.STRETCH_SCALE
	ending_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ending_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fit.add_child(ending_art)
	ending_title.set_anchors_preset(Control.PRESET_CENTER)
	ending_title.add_theme_font_size_override("font_size", 40)
	ending_title.add_theme_color_override("font_color", BRIGHT)
	ending_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_screen.add_child(ending_title)
	var hint := Label.new()
	hint.text = "Click to continue"
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.position.y = 8
	hint.add_theme_color_override("font_color", BRIGHT)
	hint.add_theme_stylebox_override("normal", _hint_box())
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ending_screen.add_child(hint)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH

	stats_screen.color = Color(0.03, 0.02, 0.01, 0.97)
	stats_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	stats_screen.visible = false
	stats_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(stats_screen)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	stats_screen.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	center.add_child(panel)
	panel.add_child(stats_box)


func _hint_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.65)
	box.set_content_margin_all(6)
	return box


## The Hollow Mile screen: the picture, over everything, hidden until your scouts first see the old highway. A click (or Enter, Space, Escape) closes it.
func _build_hollow_screen() -> void:
	hollow_screen.color = Color.BLACK
	hollow_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	hollow_screen.visible = false
	hollow_screen.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing under it can be clicked
	hollow_screen.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_hollow_next())
	root.add_child(hollow_screen)
	hollow_fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	hollow_fit.ratio = Data.HOLLOW_MILE.ratio   # set again from the picture when it is shown: black bars if the window is another shape
	hollow_fit.stretch_mode = AspectRatioContainer.STRETCH_FIT
	hollow_fit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hollow_screen.add_child(hollow_fit)
	hollow_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hollow_art.stretch_mode = TextureRect.STRETCH_SCALE
	hollow_art.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	hollow_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hollow_fit.add_child(hollow_art)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hollow_screen.add_child(center)
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 18)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(card)
	hollow_title.add_theme_font_size_override("font_size", 40)
	hollow_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hollow_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hollow_title)
	hollow_note.custom_minimum_size.x = 560
	hollow_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hollow_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hollow_note.add_theme_color_override("font_color", DIM)
	hollow_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hollow_note)
	var hint := Label.new()
	hint.text = "Click to continue"
	hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
	hint.position.y = 8
	hint.add_theme_color_override("font_color", BRIGHT)
	hint.add_theme_stylebox_override("normal", _hint_box())
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hollow_screen.add_child(hint)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH


## Your scouts have just seen the Hollow Mile (`hot`: the party that found it is taking high radiation). A season that is just ending plays its walk
## first, then the picture comes.
func _on_hollow_found(_cell: Vector2i, hot: bool) -> void:
	await get_tree().process_frame   # END SEASON starts its replay in this same frame
	if Game.replaying:
		await Game.replay_done
	show_hollow_mile(hot)


## The picture for the light of the season on screen: the grey one in a day season (and always with the night switched off), high radiation or not; in a night
## season the orange dusk one, or the green one when the party that found the Mile is taking high radiation (`hot`).
func show_hollow_mile(hot := false) -> void:
	if not Game.in_game or ending_screen.visible or stats_screen.visible:
		return
	var spec: Dictionary = Data.HOLLOW_MILE
	var version := _hollow_version(hot)
	var art := Sprites.picture(spec[version])
	hollow_art.texture = art
	if art != null:
		hollow_fit.ratio = float(art.get_width()) / float(art.get_height())
	hollow_title.text = "" if art != null else str(spec.name).to_upper()
	hollow_title.add_theme_color_override("font_color", spec[version + "_color"])
	hollow_note.text = "" if art != null else spec.note
	hollow_screen.visible = true


## Which Hollow Mile picture the light of the season on screen calls for: "day" in a day season (and always with the night switched off), in a night season "night",
## or "fallout" when `hot` (high radiation).
func _hollow_version(hot: bool) -> String:
	if Daylight.target_light(Game.season) >= 0.5:
		return "day"
	return "fallout" if hot else "night"


## A click on the picture (or Enter, Space or Escape): back to the map.
func _hollow_next() -> void:
	hollow_screen.visible = false


func _on_game_ended(kind: String) -> void:
	if Game.replaying:   # the season that ended the game finishes walking (or is skipped) first
		await Game.replay_done
	var screen: Dictionary = Data.ENDING_SCREENS[kind]
	Music.play_ending(screen.win)
	var art := Sprites.picture(screen.art)
	ending_art.texture = art
	ending_title.text = screen.title.to_upper() if art == null else ""
	menu.visible = false
	title_screen.visible = false
	stats_screen.visible = false
	ending_screen.visible = true


## A click on the ending picture (or Enter or Space): on to the stats.
func _ending_next() -> void:
	if not ending_screen.visible:
		return
	ending_screen.visible = false
	_fill_stats()
	stats_screen.visible = true


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
		if hollow_screen.visible:
			_hollow_next()
			get_viewport().set_input_as_handled()
		elif ending_screen.visible and event.keycode != KEY_ESCAPE:
			_ending_next()
			get_viewport().set_input_as_handled()


## From the stats screen back to the main menu: no game is running, and the menu music takes over from the ending's.
func _leave_to_menu() -> void:
	stats_screen.visible = false
	ending_screen.visible = false
	Game.leave_game()
	show_main_menu()


func _fill_stats() -> void:
	_clear(stats_box)
	var kind: String = Game.ending.get("kind", "defeat")
	var screen: Dictionary = Data.ENDING_SCREENS[kind]
	var title := _label(stats_box, screen.title.to_upper(), BRIGHT if screen.win else RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	var why := _label(stats_box, Data.ENDING_WHY.get(Game.ending.get("why", ""), ""), DIM)
	why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var seasons: int = Game.ending.get("season", Game.season) - 1
	var s: Dictionary = Game.stats
	var sent: Dictionary = s.get("sent", {})
	var gathered := 0
	for k in s.get("gathered", {}):
		gathered += int(s.gathered[k])
	var sections := [
		["The colony", [
			["Seasons survived", "%d (%d years)" % [seasons, seasons / 4]],
			["Most colonists at once", str(s.peak_pop)], ["Most land held", "%d tiles" % s.peak_land],
			["Buildings built", str(s.buildings_built)], ["Upgrades researched", str(s.upgrades)],
			["Vehicles built", str(s.vehicles_built)], ["Resources gathered", str(gathered)]]],
		["War", [
			["Raids on the Rust Kings", "%d won, %d lost" % [s.raids_won, s.raids_lost]],
			["Their raids on you", "%d beaten back, %d got through" % [s.raids_beaten_back, s.raids_suffered]],
			["Raider bands driven off", str(s.bands_driven_off)], ["Tribe camps scattered", str(s.tribes_scattered)],
			["Troops trained", str(s.troops_trained)], ["Prisoners taken", str(s.prisoners_taken)],
			["Survivors lost", str(s.survivors_lost + s.colonists_starved)],
			["Buildings", "%d lost, %d of theirs destroyed" % [s.buildings_lost, s.enemy_buildings_destroyed]]]],
		["Expeditions", [
			["Parties sent", "%d scavenging, %d scouting, %d caravans, %d boats, %d flights" % [
				sent.get("scav", 0), sent.get("scout", 0), sent.get("caravan", 0), sent.get("boat", 0), sent.get("plane", 0)]],
			["Ruins and sites stripped", "%d ruins, %d sites" % [s.ruins_scavenged, s.sites_scavenged]],
			["Craters and nukes", "%d craters searched, %d nukes found, %d bought, %d dropped, %d blasts, %d suffered, %d airfields destroyed" % [s.craters_searched, s.nukes_found, s.nukes_bought, s.nukes_dropped, s.blasts, s.nukes_suffered, s.airfields_destroyed]],
			["d20 rolls", "%d (%d natural 20s, %d natural 1s)" % [s.rolls, s.natural_20s, s.natural_1s]],
			["Trade runs", str(s.trade_runs)]]],
	]
	for section in sections:
		stats_box.add_child(HSeparator.new())
		_label(stats_box, section[0].to_upper(), BRIGHT)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 24)
		stats_box.add_child(grid)
		for row in section[1]:
			var name_label := _label(grid, row[0], DIM)
			name_label.custom_minimum_size.x = 260
			var value := _label(grid, row[1])
			value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.add_child(HSeparator.new())
	var back := _button(stats_box, "Return to main menu", _leave_to_menu)
	back.alignment = HORIZONTAL_ALIGNMENT_CENTER
	back.grab_focus()


# ---------------------------------------------------------------- the d20 at a ruin

## The die is built once and moved between panel rebuilds, so a roll in progress isn't lost when the panel redraws.
func _build_dice() -> void:
	dice = D20DiceScene.instantiate()
	dice.playback_speed = DICE_SPEED
	dice.return_to_idle_after = 0.0   # the landed number stays until the player clicks off it
	dice.scale = Vector2(DICE_SCALE, DICE_SCALE)
	dice_holder.custom_minimum_size = Vector2(64, 80) * DICE_SCALE
	dice_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dice_holder.mouse_filter = Control.MOUSE_FILTER_PASS
	dice_holder.add_child(dice)
	dice.clicked.connect(_on_dice_clicked)
	dice.roll_finished.connect(_on_dice_finished)


func _detach_dice() -> void:
	if dice_holder.get_parent() != null:
		dice_holder.get_parent().remove_child(dice_holder)


## A party standing at a ruin: "Scavenge", the die below it (click the die to roll), what the roll is, and once
## it has landed what it did. Buttons only for the choices that aren't a roll.
func _visit_panel(box: VBoxContainer, u: Dictionary) -> void:
	var view := Units.visit_view(u)
	if view.is_empty():
		return
	var uid: int = u.id
	if dice_uid != uid and dice_phase != "idle":
		dice_phase = "idle"   # the die was busy for another party: its result is already in the game
		dice_lines = []
	dice_uid = uid
	_header(box, "Hunt" if view.ruin in ["hunt", "frog"] else ("Attack" if view.ruin in ["building", "camp"] else ("Search the crater" if view.ruin == "crater" else "Scavenge")))
	var wants_roll: bool = view.buttons.any(func(b): return b.id == "roll")
	if dice_phase == "landed" or dice_phase == "rolling":
		box.add_child(dice_holder)
		if dice_phase == "rolling":
			_label(box, "Rolling...", DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		else:
			for line in dice_lines:
				_label(box, line)
			var hint := _label(box, "Click the die to continue", DIM)
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	if wants_roll:
		box.add_child(dice_holder)
		dice.reset_to_idle()
		_label(box, view.text, BRIGHT)
		if view.traits != "":
			_label(box, "Traits: %s" % view.traits, DIM)
		if not view.parts.is_empty():
			_label(box, D20.parts_text(view.parts), DIM)
		_label(box, "Click the die to roll", DIM).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	else:
		_label(box, view.text, BRIGHT)
	for b in view.buttons:
		if b.id == "roll":
			continue
		var bid: String = b.id
		_button(box, b.label, func(): _visit_press(uid, bid))


func _visit_press(uid: int, id: String) -> void:
	if id == "finish":
		Units.visit_finish(uid)
	else:
		Units.visit_do(uid, id)
	Game.changed.emit()


func _on_dice_clicked() -> void:
	if dice_phase == "rolling":
		return
	if dice_phase == "landed":
		if Time.get_ticks_msec() < dice_hold_until:
			return   # let the number sit for a moment first
		dice_phase = "idle"
		dice_lines = []
		refresh()
		return
	var u := Units.unit_by_id(dice_uid)
	if u.is_empty() or not Units.visit_view(u).get("buttons", []).any(func(b): return b.id == "roll"):
		return
	var shown := Units.visit_do(dice_uid, "roll")
	dice_lines = u.visit.last.duplicate() if u.has("visit") else []
	if shown <= 0:
		refresh()
		return
	dice_phase = "rolling"
	dice.roll(shown)
	refresh()


func _on_dice_finished(_result: int) -> void:
	Game.release_blasts()   # a nuke that went off with this roll goes off on the map now
	dice_phase = "landed"
	dice_hold_until = Time.get_ticks_msec() + DICE_HOLD_MSEC
	refresh()


## Names, ages and moods of the survivors in one of your parties, plus food, fuel and orders for scouts.
func _party_details(box: VBoxContainer, u: Dictionary) -> void:
	if u.owner != Data.PLAYER:
		return
	if u.get("stage", "") == "site":
		_visit_panel(box, u)
	for s in u.survivors:
		_label(box, "   " + Units.survivor_line(s), RED if s.hunger >= Data.STARVING_AT else DIM)
	if u.job == "scout":
		var food := Units.food_total(u)
		_label(box, "   Food: %s (%s)" % [Units.food_text(u), "lasts %d days" % int(Units.food_days(u)) if food > 0 else "going hungry"],
			DIM if Units.food_days(u) > 2.0 * Data.SEASON_DAYS else RED)
	if u.has("fuel"):
		var tank: Dictionary = Data.VEHICLE_FUEL[u.mover]
		var left: String
		var idle: float = tank.idle * Units.fuel_mult()
		if idle > 0.0:
			left = "%.1f seasons idle" % (u.fuel / idle) if u.stage == "station" else "burns %.1f a season waiting" % idle
		else:
			left = "enough for about %d tiles" % int(u.fuel / (tank.burn * Units.fuel_mult()))
		_label(box, "   Fuel: %.1f / %d (%s)" % [u.fuel, tank.tank, left], RED if Units.fuel_low(u) else DIM)
	if Units.load_weight(u) > 0.0:
		var slow := Units.load_slowdown(u)
		_label(box, "   Load: %d / %d%s" % [roundi(Units.load_weight(u)), roundi(Units.load_capacity(u)),
			" (overloaded: x%.1f slower)" % slow if slow > 1.0 else ""], RED if slow > 1.0 else DIM)
	if u.job != "scout":
		return
	var uid: int = u.id
	for target in Units.strike_targets(u):
		var cell: Vector2i = target
		_button(box, "Attack the %s at %d,%d (DC %d)" % [Data.BUILDINGS[Game.tile(cell)["b"]].name.to_lower(), cell.x, cell.y, Game.building_dc(cell)],
			func(): Units.begin_strike(uid, cell))
	for camp in Units.camp_targets(u):
		var camp_id: int = camp.id
		_button(box, "Attack the %s at %d,%d (DC %d, strength %d)" % [camp.name, camp.pos.x, camp.pos.y, D20Visit.enemy_dc(int(camp.strength)), camp.strength],
			func(): Units.begin_camp_strike(uid, camp_id))
	for animal in Units.hunt_targets(u):
		var animal_id: int = animal.id
		_button(box, "Hunt the %s at %d,%d (track DC %d, kill DC %d)" % [Units.animal_name(animal), animal.pos.x, animal.pos.y,
			D20Data.HUNT[animal.kind].track_dc, Units.kill_dc(animal.kind)], func(): Units.begin_hunt(uid, animal_id))
	if u.stage != "back" and u.stage != "site":
		_button(box, "Recall %s to camp" % Units.names_text(u), func(): Units.recall_scouts(uid))


## Scouting from this tile: send a new party, or redirect one that is already out.
func _scout_orders(box: VBoxContainer, c: Vector2i) -> void:
	if Game.tile(c)["o"] == Data.PLAYER:
		return
	_header(box, "Scouting")
	_label(box, "Scouts stay and keep watch until you move them or recall them. They set out with %d food and each eats %d a season, so a party can only stay out so long." % [
		Data.SCOUT_PACK, Data.SCOUT_RATION], DIM)
	_salt_toggle(box)
	for u in Units.units:
		if u.owner == Data.PLAYER and u.job == "scout" and not (u.pos == c and u.stage == "station"):
			var uid: int = u.id
			var why := Units.order_status(u, c)
			var trip := ""
			if why == "":
				trip = ", %d days" % ceili(_party_trip_days(u, c))
			_button(box, "Send %s here%s" % [Units.names_text(u), trip], func(): Units.order_scouts(uid, c), why)
			if why == "":
				_food_warning(box, u, c)
	var e: Dictionary = Data.EXPEDITIONS["scout"]
	for mover in Data.SCOUT_MOVERS:
		if mover in Data.VEHICLES and Game.vehicles[mover] == 0:
			continue
		var why := Units.send_status("scout", mover, c)
		var trip := ""
		if why == "":
			trip = ", %d days there" % ceili(Game.party_route_days(mover, Game.route(mover, Game.home(Data.PLAYER), c)))
		_button(box, "%s %s (%d crew, %s%s)" % [e.verb, Data.MOVERS[mover].by, e.crew, Units.send_cost_text("scout", mover), trip],
			func(): Units.send("scout", mover, c), why)
	_label(box, "   Parties out: %d/%d" % [Units.scouts_out(), Game.scout_parties()], DIM)


## Days for a party already in the field to reach `c`, counting the time lost at the end of each season.
func _party_trip_days(u: Dictionary, c: Vector2i) -> float:
	return Units.arrival_days(u.mover, Game.route(u.mover, u.pos, c), Units.party_slowdown(u))[-1]


## Under a "Send X here" button: a warning when the party's pack won't last the trip.
func _food_warning(box: VBoxContainer, u: Dictionary, c: Vector2i) -> void:
	var days := _party_trip_days(u, c)
	var food := Units.food_days(u)
	if days > food:
		_label(box, "   Not enough food: the trip takes %d days and their pack lasts %d." % [ceili(days), int(food)], RED)


func _recon_button(box: VBoxContainer, c: Vector2i) -> void:
	if Game.vehicles["plane"] > 0:
		var e: Dictionary = Data.EXPEDITIONS["plane"]
		_button(box, "%s over this tile (%s in the tank)" % [e.verb, Game.cost_text(Units.send_cost("plane", "plane"))],
			func(): Units.send("plane", "plane", c), Units.send_status("plane", "plane", c))
	_strike_block(box, c)


## A glowing crater: one search for a live nuke, by one scavenger party.
func _crater_block(box: VBoxContainer, c: Vector2i) -> void:
	_header(box, "Search the crater")
	if Game.tile(c)["r"] == "picked":
		_label(box, "Picked clean.", DIM)
		return
	_label(box, "Unsearched. A glowing crater can hide a live nuke. One roll: a natural 1 sets it off (the whole party dies and the 3 by 3 square turns to hot ash), a natural 20 disarms it. A nuke weighs %d: a party on foot can lift one, slowly." % int(Data.ITEM_WEIGHT.nuke), DIM)
	_expedition_buttons(box, "scav", c)


## The Nuclear strike block, once you own a bomber: any tile can be bombed. Hovering the button outlines the 3 x 3 square in red on the map and lists what you know is in it;
## the first press arms it and the second sends the bomber (there is no recall).
func _strike_block(box: VBoxContainer, c: Vector2i) -> void:
	if int(Game.vehicles.get("bomber", 0)) <= 0:
		return
	_header(box, "Nuclear strike")
	var why := Units.send_status("bomb", "bomber", c)
	var armed := strike_armed == c and why == ""
	var label := "Confirm: drop the nuke on %d,%d" % [c.x, c.y] if armed else "Drop a nuke here (bomber, %s in the tank)" % Game.cost_text(Units.send_cost("bomb", "bomber"))
	var press := func():
		if strike_armed == c:
			strike_armed = Vector2i(-1, -1)
			Units.send("bomb", "bomber", c)
		else:
			strike_armed = c
			refresh()
	var b := _button(box, label, press, why)
	b.mouse_entered.connect(func(): Game.set_strike_preview(c))
	b.mouse_exited.connect(func(): Game.set_strike_preview(Vector2i(-1, -1)))
	if why != "":
		_label(box, "   " + why, DIM)
		return
	_label(box, "   You hold %d. The blast wipes the 3 by 3 square round %d,%d: it turns to scorched ash (%d R/h), every party in it dies, and every building falls but an HQ, a fort, Dustwell and the old bridge. There is no recall." % [
		int(Game.items.get("nuke", 0)), c.x, c.y, int(Data.NUKE.rad)], DIM)
	var report := Game.blast_report(c)
	if not report.yours.is_empty() or not report.parties.is_empty():
		var mine: Array = report.parties.duplicate()
		if not report.yours.is_empty():
			mine.append("%d of your buildings (%s)" % [report.yours.size(), ", ".join(report.yours)])
		_label(box, "   WARNING, in the square: " + "; ".join(mine) + ".", RED)
	if not report.theirs.is_empty():
		_label(box, "   Rust Kings buildings in the square: %s. Each one costs %d relations." % [", ".join(report.theirs), Data.RAID_RELATIONS], AMBER)
	if not report.camps.is_empty():
		_label(box, "   Camps in the square: %s." % ", ".join(report.camps), AMBER)


## One button per way of travel you own, with how long the trip out takes.
func _expedition_buttons(box: VBoxContainer, job: String, target: Vector2i, dest := -1, verb := "") -> void:
	var e: Dictionary = Data.EXPEDITIONS[job]
	_salt_toggle(box)
	for mover in Data.TRAVEL_PREVIEW:
		if mover in Data.VEHICLES and Game.vehicles[mover] == 0:
			continue
		var why := Units.send_status(job, mover, target, dest)
		var trip := ""
		if why == "":
			trip = ", %d days there" % ceili(Game.party_route_days(mover, Game.route(mover, Game.home(Data.PLAYER), target)))
		var cost_text := Game.cost_text(Units.send_cost(job, mover) if job == "deal" else e.cost)
		if Units.salt_doses(job) > 0:
			cost_text = ("%d Salt" if cost_text == "free" else cost_text + ", %d Salt") % Units.salt_doses(job)
		_button(box, "%s %s (%d crew, %s%s)" % [verb if verb != "" else e.verb, Data.MOVERS[mover].by, e.crew, cost_text, trip],
			func(): Units.send(job, mover, target, dest), why)


## The Drug Factory you clicked: how many raw frog hides and how much Salt the colony holds (they have no line in the top bar).
func _drug_factory_block(box: VBoxContainer) -> void:
	_header(box, "Drug Factory")
	_label(box, "Frog hides in the stores: %d" % int(Game.items.get("hide", 0)), BRIGHT)
	_label(box, "Salt in the stores: %d" % int(Game.items.get("salt", 0)), BRIGHT)
	_label(box, "Each season every Drug Factory turns 1 frog hide into %d Salt. You have %d." % [Data.HIDE_TO_SALT, Game.count_building(Data.PLAYER, "drug_factory")], DIM)


## "Take Salt" beside the send buttons, once there is Salt to take.
func _salt_toggle(box: VBoxContainer) -> void:
	if int(Game.items.get("salt", 0)) <= 0:
		return
	var b := _button(box, "Take Salt: %s (%d in the stores)" % ["on" if Game.salt_on else "off", int(Game.items["salt"])], func():
		Game.salt_on = not Game.salt_on
		Game.changed.emit())
	b.tooltip_text = "A party takes one dose of Salt for each survivor when it leaves: for %d seasons they take in half the radiation." % Data.SALT_SEASONS


## The awake Giant Frog on the selected tile: what it is doing, and the way to hunt it.
func _frog_block(box: VBoxContainer) -> void:
	var rule: Dictionary = D20Data.FROG_FIGHT
	_header(box, Data.FROG.name)
	_label(box, "%s The Giant Frog, awake. It is heading for %s and raids it once a season. It heals fully every season." % [
		Data.FROG.glyph, "your colony" if Units.frog.target == "player" else "the Rust Kings' fort"], RED)
	_label(box, "Track it (DC %d) with each party, then attack with everyone who found it: %d wounds to take, and it slams %d times a round. Six survivors can just do it; nine nearly always." % [
		int(rule.track_dc), int(rule.wounds), int(rule.slams)], DIM)
	_expedition_buttons(box, "scav", Units.frog.pos, Units.FROG_ID, "Hunt with scavengers")
	_expedition_buttons(box, "hunters", Units.frog.pos, Units.FROG_ID, "Send hunting party")


## A wild animal on the selected tile: what it is, and the way to hunt it.
func _animal_block(box: VBoxContainer, a: Dictionary) -> void:
	var spec: Dictionary = Data.ANIMALS[a.kind]
	var hunt: Dictionary = D20Data.HUNT[a.kind]
	_header(box, spec.name)
	if int(hunt.strength) > 0:
		_label(box, "%s %s (strength %d). It attacks a party that comes within %d tiles at the end of a season. Hunting it makes the land safer." % [
			spec.glyph, spec.name, int(hunt.strength), int(Data.BEAR_REACH)], RED)
	else:
		_label(box, "%s A deer. Hunt it for meat." % spec.glyph, spec.color)
	_label(box, "Two rolls: track it (DC %d), then the kill shot (DC %d)." % [int(hunt.track_dc), Units.kill_dc(a.kind)], DIM)
	_expedition_buttons(box, "scav", a.pos, a.id, "Hunt with scavengers")
	_expedition_buttons(box, "hunters", a.pos, a.id, "Send hunting party")


func _tribe_info(box: VBoxContainer, t: Dictionary) -> void:
	var cls: Dictionary = Data.TRIBE_CLASSES[t.class]
	_header(box, t.name)
	_label(box, "%s %s at %d,%d. %s" % [cls.glyph, cls.name, t.pos.x, t.pos.y, cls.desc], cls.color)
	match t.class:
		"raider":
			var att := Game.player_attack(t.pos)
			_button(box, "Attack their camp (your attack %.1f vs ~%d, %s)" % [att, t.strength, Game.raid_odds_text(att, float(t.strength))],
				func(): Units.attack_tribe(t.id), Units.attack_tribe_status(t))
		"trader":
			_expedition_buttons(box, "caravan", t.pos, t.id)
			if t.get("warhead_known", false) and t.get("warhead", false):
				_label(box, "WARHEAD FOR SALE: %d gold%s. It needs a caravan on horseback or in a war rig, the crate slows the way home, and it only counts once it reaches your HQ." % [
					Game.warhead_price(), " (the Trader leader's price)" if Game.leader == "trader" else ""], RED)
				_expedition_buttons(box, "deal", t.pos, t.id)
		"builder":
			_button(box, "Gift food (%s), trust %d/50" % [Game.cost_text(Units.GIFT), t.relations], func(): Units.gift_tribe(t.id),
				"" if Game.can_afford(Units.GIFT) else "Need " + Game.cost_text(Units.GIFT))


## " (the river)" or " (steep inclines)" after "no way through", or nothing.
func _no_way_suffix(mover: String, from: Vector2i, to: Vector2i) -> String:
	var why := Game.no_way_reason(mover, from, to)
	return " (%s)" % why if why != "" else ""


## With a scouting party picked: how long its trip to this tile takes, and whether its food lasts.
func _scout_travel_line(box: VBoxContainer, c: Vector2i) -> void:
	var u := Units.unit_by_id(Game.selected_scout)
	if u.is_empty() or u.pos == c or is_inf(Units.food_days(u)):
		return
	var route: Dictionary = Game.scout_route
	_label(box, "Travel for %s, %s:" % [Units.names_text(u), Data.MOVERS[u.mover].name.to_lower()])
	if route.is_empty():
		_label(box, "  ● no way through%s" % _no_way_suffix(u.mover, u.pos, c), RED)
		return
	var days: float = route.days[-1]
	var food := Units.food_days(u)
	if days <= food:
		_label(box, "  ● %d days. Their food lasts %d." % [ceili(days), int(food)], GREEN)
	else:
		_label(box, "  ● %d days, but their food runs out after %d (%d days short)." % [ceili(days), int(food), ceili(days - food)], RED)


## One colored line per way of travel: how many days the route takes, or why there isn't one.
func _travel_lines(box: VBoxContainer, routes: Dictionary) -> void:
	for mover in routes:
		var m: Dictionary = Data.MOVERS[mover]
		var path: Array = routes[mover]
		if path.is_empty():
			_label(box, "  ● %s: no way through%s" % [m.name, _no_way_suffix(mover, Game.home(Data.PLAYER), Game.selected)], m.color)
		else:
			_label(box, "  ● %s: %d days" % [m.name, ceili(Game.party_route_days(mover, path))], m.color)


func _routes_between(from: Vector2i, to: Vector2i) -> Dictionary:
	var out := {}
	for mover in Data.TRAVEL_PREVIEW:
		out[mover] = Game.route(mover, from, to)
	return out


func _upgrade_row(box: VBoxContainer, id: String) -> void:
	var u: Dictionary = Data.UPGRADES[id]
	var why := Game.upgrade_status(id)
	if why == "Owned":
		_label(box, "[x] T%d %s - %s" % [u.tier, u.name, u.desc], GREEN)
		return
	_button(box, "T%d %s (%s)" % [u.tier, u.name, Game.cost_text(Game.upgrade_cost(id))], func(): Game.buy_upgrade(id), why)
	_label(box, "   " + u.desc + ("" if why == "" else "  [%s]" % why), DIM)


func _refresh_upgrades() -> void:
	var box: VBoxContainer = boxes["Upgrades"]
	_clear(box)
	var committed := Game.committed_branches()
	_label(box, "Home branch: %s (25%% off)" % Data.LEADERS[Game.leader].branch)
	_label(box, "Committed: %s" % (", ".join(committed) if committed.size() > 0 else "none"))
	_label(box, "Tier 3+ in a branch commits you. Each extra committed branch adds +30% to all tier 4-5 costs.", DIM)
	for branch in ["core"] + Data.BRANCHES + ["bridge"]:
		_header(box, branch)
		for id in Data.UPGRADES:
			var u: Dictionary = Data.UPGRADES[id]
			if u.branch == branch and not u.get("vehicle", false):
				_upgrade_row(box, id)
		# Each leader branch has its own vehicle line
		if branch in Data.BRANCHES:
			_label(box, "-- %s vehicles --" % branch, BRIGHT)
			for id in Data.UPGRADES:
				var u: Dictionary = Data.UPGRADES[id]
				if u.branch == branch and u.get("vehicle", false):
					_upgrade_row(box, id)


func _refresh_colony() -> void:
	var box: VBoxContainer = boxes["Colony"]
	_clear(box)
	_leader_block(box)
	_label(box, "Land: %d tiles   Population: %d / %d" % [Game.owned(Data.PLAYER).size(), Game.pop, Game.pop_cap()])
	_label(box, "Everyone eats 1 grain/veg a season%s. A surplus of %d+ grows the colony. Prisoners work but must be fed." % [
		", and 1 more for every 5 colonists" if Game.has_quirk("big_appetites") else "", 6 if Game.has_quirk("big_families") else 10], DIM)
	_header(box, "Military")
	_label(box, "Troops: %d (each eats %d meat/season)" % [Game.troops, 2 if Game.has("w3") else 1])
	_label(box, "Attack %.1f   Defense %.1f (walls %.1f)" % [Game.player_attack(),
		Game.player_wall_defense() + Game.player_troop_defense(), Game.player_wall_defense()])
	_button(box, "Train troop (1 pop, %s)" % Game.cost_text(Game.train_troop_cost()), Game.train_troop,
		"" if Game.pop > 2 and Game.can_afford(Game.train_troop_cost()) else "Need 3+ pop and " + Game.cost_text(Game.train_troop_cost()))
	_button(box, "Disband troop (back to pop)", Game.disband_troop, "" if Game.troops > 0 else "No troops")
	if Game.prisoners > Game.troops * Game.guard_ratio():
		_label(box, "WARNING: too few guards. Prisoners may revolt.", RED)
	_header(box, "Vehicles")
	_label(box, "Vehicle upgrades are in each branch on the Upgrades tab.", DIM)
	for v in Data.VEHICLES:
		var d: Dictionary = Data.VEHICLES[v]
		var why := Game.vehicle_status(v)
		var upkeep := Game.vehicle_upkeep(v)
		_label(box, "%s: %d, %d out   (+%d attack, +%d caravan gold, upkeep %s each)" % [d.name, Game.vehicles[v], Units.vehicles_out(v),
			Game.vehicle_attack(v), Game.vehicle_trade(v), Game.cost_text(upkeep) if not upkeep.is_empty() else "none"])
		_button(box, "Build %s (%s)" % [d.name, Game.cost_text(Game.vehicle_cost(v))], func(): Game.build_vehicle(v), why)
		if why != "":
			_label(box, "   " + why, DIM)
		elif d.has("desc"):
			_label(box, "   " + d.desc, DIM)
	var refineries := Game.count_building(Data.PLAYER, "refinery")
	if refineries > 0:
		_header(box, "Refineries")
		var running := Game.running_refineries().size()
		_label(box, "%d built, %d running. Each running one turns %d veg into %d fuel a season, unless that would leave too little to eat. Click a refinery on the map to switch it." % [
			refineries, running, Data.REFINERY_VEG, Game.refinery_fuel()], GREEN if running > 0 else RED)
	_header(box, "Expeditions")
	var mine := Units.units.filter(func(u): return u.owner == Data.PLAYER)
	if mine.is_empty():
		_label(box, "None out. Click pre-war ruins to send scavengers, or any tile to send scouts.", DIM)
	for u in mine:
		var kind: Dictionary = Units.kind_info(Units.glyph_kind(u))
		var pos: Vector2i = u.pos
		_button(box, "%s %s %s, %s at %d,%d (%d crew)" % [kind.glyph, Data.EXPEDITIONS[u.job].name, Data.MOVERS[u.mover].by,
			Units.stage_text(u), pos.x, pos.y, u.crew],
			func(): Game.focus.emit(pos); Game.select(pos))
		_label(box, "   " + Units.names_text(u) + (" (starving!)" if u.survivors.any(func(s): return s.hunger >= Data.STARVING_AT) else ""), DIM)
	_header(box, "Scouting")
	_label(box, "Parties out: %d/%d. Click a tile to send scouts or move a party there; they stay and keep watch." % [
		Units.scouts_out(), Game.scout_parties()])
	_label(box, "A party leaves with %d food from your stores, and each survivor eats %d of it a season. When the pack is empty they starve, so recall them in time: whatever is left comes home with them. Horses and war rigs add parties and range." % [
		Data.SCOUT_PACK, Data.SCOUT_RATION], DIM)
	_label(box, "War rigs, planes (recon flights too) and river boats carry a tank, shown as a fuel gauge by the portraits. When it runs dry the vehicle is lost and the crew go on foot. A plane crashes: some aboard may die, and the rest are injured.", DIM)


func _refresh_diplomacy() -> void:
	var box: VBoxContainer = boxes["Diplomacy"]
	_clear(box)
	var ai := Game.ai
	var raid_why := "No troops" if Game.troops <= 0 else ("Already attacked this season" if Game.raided_this_season else "")
	if not Game.knows(Data.PLAYER, Data.AI):
		_header(box, "Unknown colony")
		_label(box, "Your scouts haven't found any other colony yet. Scout east through the fog.", DIM)
	else:
		_diplomacy_ai(box, ai, raid_why)
	_diplomacy_town(box, raid_why)
	var found := Units.known_tribes()
	if found.is_empty():
		_header(box, "Tribes")
		_label(box, "No tribes found yet. Their camps show as Δ once explored.", DIM)
	for t in found:
		_tribe_info(box, t)


func _diplomacy_ai(box: VBoxContainer, ai: Dictionary, raid_why: String) -> void:
	_header(box, ai["name"])
	_label(box, "Relations: %d   Troops: ~%d   Walls: %d" % [ai["relations"], ai["troops"], ai["walls"]],
		RED if ai["relations"] < 0 else AMBER)
	_label(box, "Vehicles: %d horses, %d war rigs, %d boats, %d planes" % [ai["horse"], ai["car"], ai["boat"], ai["plane"]])
	_label(box, "Bombers: %d. %s" % [int(ai.get("bomber", 0)), Game.airfield_text()], RED if int(ai.get("bomber", 0)) > 0 else DIM)
	_label(box, "March to their fort (long marches tire troops; war rigs need a way around steep inclines):", DIM)
	_travel_lines(box, _routes_between(Game.home(Data.PLAYER), Game.home(Data.AI)))
	_label(box, "Their raid strength ~%.1f vs your defense %.1f" % [Game.ai_attack(),
		Game.player_wall_defense() + Game.player_troop_defense()], DIM)
	if ai["truce"] > 0:
		_label(box, "Bribed: no raids for %d seasons." % ai["truce"], GREEN)
	var raid_att := Game.player_attack(Game.home(Data.AI))
	var raid_def := Game.ai_defense(Game.wall_breach())
	_button(box, "RAID them (your attack %.1f vs their defense ~%.1f, %s)" % [raid_att, raid_def, Game.raid_odds_text(raid_att, raid_def)],
		Game.raid_ai, raid_why)
	_label(box, "Caravans out: %d/%d. Gold comes home with them; raider bands may ambush them on the road." % [
		Units.trade_runs(), Game.caravan_slots()], DIM)
	_expedition_buttons(box, "caravan", Game.home(Data.AI))
	_button(box, "Ransom %d prisoners (%d gold each)" % [Game.prisoners, Game.ransom_price()], Game.ransom_prisoners,
		"" if Game.prisoners > 0 else "No prisoners")
	if Game.has("c4"):
		_button(box, "Bribe for 3 seasons of peace (20 gold)", Game.bribe, "" if Game.res["gold"] >= 20 else "Need 20 gold")

	_header(box, "Market")
	if not Game.can_trade():
		_label(box, "Relations too low to trade (must be above -30).", RED)
	else:
		for r in Data.MARKET:
			var amount: int = Data.MARKET[r][0]
			var pays := Game.sell_gold(r)
			var costs := Game.buy_price(r)
			var row := HBoxContainer.new()
			box.add_child(row)
			var name_label := _label(row, r)
			name_label.custom_minimum_size.x = 60
			_button(row, "Sell %d +%dg" % [amount, pays], func(): Game.sell(r), "" if Game.res[r] >= amount else "Not enough")
			_button(row, "Buy %d -%dg" % [amount, costs], func(): Game.buy(r), "" if Game.res["gold"] >= costs else "Not enough gold")
		if int(Game.items.get("salt", 0)) > 0 or Game.salt_for_sale() > 0:   # Salt: rare, and worth a lot
			var salt_row := HBoxContainer.new()
			box.add_child(salt_row)
			var salt_label := _label(salt_row, "Salt")
			salt_label.custom_minimum_size.x = 60
			_button(salt_row, "Sell 1 +%dg" % Game.salt_sell_gold(), Game.sell_salt, "" if int(Game.items.get("salt", 0)) >= 1 else "None to sell")
			var stock := Game.salt_for_sale()
			var buy_price := Game.salt_buy_price()
			_button(salt_row, "Buy 1 -%dg (%d for sale)" % [buy_price, stock], Game.buy_salt, "" if stock > 0 and Game.res["gold"] >= buy_price else ("None for sale" if stock <= 0 else "Not enough gold"))


func _diplomacy_town(box: VBoxContainer, raid_why: String) -> void:
	var town := Game.town
	if not Game.knows(Data.PLAYER, Data.TOWN):
		_header(box, "Unknown settlement")
		_label(box, "Traders speak of a settlement to the north. Scout to find it.", DIM)
		return
	_header(box, town["name"])
	_label(box, "Status: %s   Relations: %d" % [town["status"], town["relations"]])
	if town["status"] == "neutral":
		_label(box, "Befriend them for tribute and an ally, or take their land and people by force.", DIM)
		_button(box, "Send gifts (%s)" % Game.cost_text(Game.befriend_cost()), Game.befriend_town,
			"" if Game.can_afford(Game.befriend_cost()) else "Need " + Game.cost_text(Game.befriend_cost()))
		_travel_lines(box, _routes_between(Game.home(Data.PLAYER), Game.home(Data.TOWN)))
		var town_att := Game.player_attack(Game.home(Data.TOWN))
		_button(box, "Conquer (attack %.1f vs %d, %s)" % [town_att, int(Game.TOWN_DEFENSE), Game.raid_odds_text(town_att, Game.TOWN_DEFENSE)],
			Game.conquer_town, raid_why)
	elif town["status"] == "ally":
		_label(box, "Allied: sends 2 gold + 3 grain each season.", GREEN)
