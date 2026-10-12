extends CanvasLayer
## All the UI, built in code with an amber terminal look.
## Every panel is rebuilt from scratch when the game changes, which keeps things simple.

const Data = preload("res://scripts/data.gd")
const Portrait = preload("res://scripts/portrait.gd")
const Icons = preload("res://scripts/icons.gd")
const Geiger = preload("res://scripts/geiger.gd")
const FuelGauge = preload("res://scripts/fuel_gauge.gd")
const Sprites = preload("res://scripts/sprites.gd")
const D20 = preload("res://scripts/d20.gd")
const Leaders = preload("res://scripts/leaders.gd")
const D20DiceScene = preload("res://d20_dice/D20Dice.tscn")
const DICE_SCALE := 3          # the pixel-art die is 64 x 80: shown at 3x it is 192 x 240
const DICE_SPEED := 1.25       # playback speed of the roll animation (1.0 is about 0.75 seconds)
const DICE_HOLD_MSEC := 1000   # the landed number stays up at least this long before a click moves on
const LEGEND_ICON_SCALE := 3   # screen pixels per pixel of legend art
const LOGO_WIDTH := 440        # how wide the slab-stack logo is on the character selection screen
const CARD_WIDTH := 440        # one leader card on that screen, and the face on it (480 px pictures shown at half size)
const CARD_FACE := 240
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

var root := Control.new()
var top_text := RichTextLabel.new()
var tabs := TabContainer.new()
var boxes := {}           # tab name -> VBoxContainer
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
var rad_button: Button
var art_button: Button
var dice: Control                        # the one clickable d20 (see d20_dice/), moved into whichever panel shows it
var dice_holder := Control.new()         # gives the scaled die its room in a panel
var dice_phase := "idle"                 # "idle" (the ROLL face), "rolling" or "landed" (the number is up)
var dice_uid := -1                       # the party the die is for
var dice_hold_until := 0                 # when a click may move on from the landed number (msec)
var dice_lines: Array = []               # what the last roll said, shown under the landed die
var ending_screen := ColorRect.new()     # the ending picture, over everything; a click moves on to the stats
var ending_art := TextureRect.new()
var ending_title := Label.new()          # stands in for the picture's own title if the picture can't be read
var stats_screen := ColorRect.new()      # what you did, and the way back to the main menu
var stats_box := VBoxContainer.new()


func _ready() -> void:
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _make_theme()
	add_child(root)
	_build_top_bar()
	_build_side_panel()
	_build_log()
	_build_menu()
	_build_dice()
	_build_ending()
	Game.game_ended.connect(_on_game_ended)
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
	view_button.tooltip_text = "Switch whose knowledge the map shows"
	rad_button = _button(row, "Radiation: off", Game.toggle_radiation_view)
	rad_button.tooltip_text = "Tint the tiles your scouts have measured by how hot they are"
	art_button = _button(row, "Art: style 1", _cycle_art)
	art_button.tooltip_text = "Switch the map and legend between the three pixel-art styles and the old text glyphs"
	_button(row, "END SEASON", Game.end_season)
	_button(row, "Save", show_save_menu)
	_button(row, "Load", show_load_menu)
	_button(row, "Menu", show_main_menu)


func _build_side_panel() -> void:
	var p := _panel([1, 0, 1, 1], [-410, 64, -6, -6])
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
	_refresh_tile()
	_refresh_party()
	_refresh_upgrades()
	_refresh_colony()
	_refresh_diplomacy()
	log_text.text = "\n".join(Game.log_lines)


func _refresh_top() -> void:
	var t := "[color=#ffd88a]%s[/color]   Pop [b]%d[/b]/%d   Troops %d   Prisoners %d   Leader: %s\n" % [
		Game.season_name(), Game.pop, Game.pop_cap(), Game.troops, Game.prisoners, Leaders.label(Game.leader_info)]
	for r in Data.RESOURCES:
		t += "%s [color=#ffd88a]%d[/color]  " % [r, Game.res[r]]
	top_text.text = t
	var views := {Data.PLAYER: "Map: what you know", Data.AI: "Map: what Rust Kings know", Data.NONE: "Map: no fog (debug)"}
	view_button.text = views[Game.view]
	rad_button.text = "Radiation: " + ("on" if Game.show_radiation else "off")
	art_button.text = "Art: " + Sprites.choice_name(Sprites.state())


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
	var kind: Dictionary = Data.UNITS[Units.glyph_kind(u)]
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
	gauge.setup(u.mover, u.fuel / float(tank), low)
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


## Each sprite comes in three styles: these buttons flip the whole legend between them.
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


## Switches the legend and the map between the three art styles and the old text glyphs.
func _set_art_style(n: int) -> void:
	Sprites.choose(n)
	Game.changed.emit()   # redraws the map (and, a moment later, every panel)


func _cycle_art() -> void:
	Sprites.cycle()
	Game.changed.emit()


func _refresh_tile() -> void:
	var box: VBoxContainer = boxes["Tile"]
	_detach_dice()   # the die lives on between rebuilds: take it out before the panel is cleared
	_clear(box)
	var c := Game.selected
	if not Game.in_bounds(c):
		_label(box, "Click a tile on the map.\n\nWASD / arrows: pan\nMouse wheel: zoom\nRight-drag: pan")
		_header(box, "Legend")
		_legend_style_row(box)
		for id in Data.TERRAIN:
			var t: Dictionary = Data.TERRAIN[id]
			_legend_row(box, Sprites.terrain(id), t.glyph[0], "%s  %s" % [t.name, Game.cost_text(t.yield) if not t.yield.is_empty() else ""], t.color)
		_legend_row(box, Sprites.slope("gentle"), "─│┌┐", "Gentle slope (a line every 10 m): slows everyone a little", AMBER)
		_legend_row(box, Sprites.slope("steep"), "═║╔╗", "Steep incline: war rigs can't climb it, foot and horses cross slowly", AMBER)
		for mover in Data.TRAVEL_PREVIEW:
			_label(box, " ●    %s route from your HQ to the tile you click" % Data.MOVERS[mover].name, Data.MOVERS[mover].color)
		_label(box, " ●    Click a scouting party to see its route from where it stands: white while its food lasts, yellow as it runs low, red once it's gone", Color("ffe03a"))
		for kind in Data.UNITS:
			_legend_row(box, Sprites.unit(kind), Data.UNITS[kind].glyph, Data.UNITS[kind].name, Data.UNITS[kind].color)
		for cls in Data.TRIBE_CLASSES:
			_legend_row(box, Sprites.camp(cls), Data.TRIBE_CLASSES[cls].glyph, "%s camp" % Data.TRIBE_CLASSES[cls].name, Data.TRIBE_CLASSES[cls].color)
		for kind in Data.POIS:
			var building: Dictionary = Data.BUILDINGS["poi_" + kind]
			_legend_row(box, Sprites.poi_sprite(kind), building.glyph, building.name, building.color, Sprites.POI_SIZE)
		_label(box, "   Black: never explored. Click it to scout.", DIM)
		_label(box, "   Dark: explored but out of sight. Shows what was there last time.", DIM)
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
	_label(box, terrain.name + ("" if seen else "  (out of sight, last seen)"))
	_label(box, "Owner: %s" % owners[known[0]])
	_label(box, "Height: %+d m" % Game.tile(c)["z"])
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
		if known[0] == Data.PLAYER and known[1] == "refinery":
			_refinery_controls(box, c)
		if known[0] == Data.PLAYER and known[1] != "hq" and not b.has("poi"):
			_button(box, "Demolish", func(): Game.demolish(c))
	for u in Units.units_at(c):
		if u.owner == Data.PLAYER or seen:
			var kind: Dictionary = Data.UNITS[Units.glyph_kind(u)]
			if u.job == "band":
				_label(box, "%s Raider band here (strength %d)!" % [kind.glyph, u.strength], kind.color)
			else:
				_label(box, "%s Your %s, %s (%d crew)" % [kind.glyph, Data.EXPEDITIONS[u.job].name.to_lower(),
					Units.stage_text(u), u.crew], kind.color)
				_party_details(box, u)
	var tribe := Units.tribe_at(c)
	if not tribe.is_empty():
		_tribe_info(box, tribe)
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
		_button(box, "Claim tile (%s)" % Game.cost_text(Game.claim_cost(c)), func(): Game.claim(c), why)
		if why != "":
			_label(box, why, DIM)
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
	_label(box, "Unsearched. Takes one party.", DIM)
	_expedition_buttons(box, "scav", anchor)


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


func _on_game_ended(kind: String) -> void:
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		if ending_screen.visible:
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
	_header(box, "Attack" if view.ruin == "building" else "Scavenge")
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
	if u.stage != "back" and u.stage != "site":
		_button(box, "Recall %s to camp" % Units.names_text(u), func(): Units.recall_scouts(uid))


## Scouting from this tile: send a new party, or redirect one that is already out.
func _scout_orders(box: VBoxContainer, c: Vector2i) -> void:
	if Game.tile(c)["o"] == Data.PLAYER:
		return
	_header(box, "Scouting")
	_label(box, "Scouts stay and keep watch until you move them or recall them. They set out with %d food and each eats %d a season, so a party can only stay out so long." % [
		Data.SCOUT_PACK, Data.SCOUT_RATION], DIM)
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
	return Units.arrival_days(u.mover, Game.route(u.mover, u.pos, c), Units.load_slowdown(u))[-1]


## Under a "Send X here" button: a warning when the party's pack won't last the trip.
func _food_warning(box: VBoxContainer, u: Dictionary, c: Vector2i) -> void:
	var days := _party_trip_days(u, c)
	var food := Units.food_days(u)
	if days > food:
		_label(box, "   Not enough food: the trip takes %d days and their pack lasts %d." % [ceili(days), int(food)], RED)


func _recon_button(box: VBoxContainer, c: Vector2i) -> void:
	if Game.vehicles["plane"] == 0:
		return
	var e: Dictionary = Data.EXPEDITIONS["plane"]
	_button(box, "%s over this tile (%s)" % [e.verb, Game.cost_text(e.cost)], func(): Units.send("plane", "plane", c),
		Units.send_status("plane", "plane", c))


## One button per way of travel you own, with how long the trip out takes.
func _expedition_buttons(box: VBoxContainer, job: String, target: Vector2i, dest := -1) -> void:
	var e: Dictionary = Data.EXPEDITIONS[job]
	for mover in Data.TRAVEL_PREVIEW:
		if mover in Data.VEHICLES and Game.vehicles[mover] == 0:
			continue
		var why := Units.send_status(job, mover, target, dest)
		var trip := ""
		if why == "":
			trip = ", %d days there" % ceili(Game.party_route_days(mover, Game.route(mover, Game.home(Data.PLAYER), target)))
		_button(box, "%s %s (%d crew, %s%s)" % [e.verb, Data.MOVERS[mover].by, e.crew, Game.cost_text(e.cost), trip],
			func(): Units.send(job, mover, target, dest), why)


func _tribe_info(box: VBoxContainer, t: Dictionary) -> void:
	var cls: Dictionary = Data.TRIBE_CLASSES[t.class]
	_header(box, t.name)
	_label(box, "%s %s at %d,%d. %s" % [cls.glyph, cls.name, t.pos.x, t.pos.y, cls.desc], cls.color)
	match t.class:
		"raider":
			_button(box, "Attack their camp (your attack %.1f vs ~%d)" % [Game.player_attack(t.pos), t.strength],
				func(): Units.attack_tribe(t.id), Units.attack_tribe_status(t))
		"trader":
			_expedition_buttons(box, "caravan", t.pos, t.id)
		"builder":
			_button(box, "Gift food (%s), trust %d/50" % [Game.cost_text(Units.GIFT), t.relations], func(): Units.gift_tribe(t.id),
				"" if Game.can_afford(Units.GIFT) else "Need " + Game.cost_text(Units.GIFT))


## With a scouting party picked: how long its trip to this tile takes, and whether its food lasts.
func _scout_travel_line(box: VBoxContainer, c: Vector2i) -> void:
	var u := Units.unit_by_id(Game.selected_scout)
	if u.is_empty() or u.pos == c or is_inf(Units.food_days(u)):
		return
	var route: Dictionary = Game.scout_route
	_label(box, "Travel for %s, %s:" % [Units.names_text(u), Data.MOVERS[u.mover].name.to_lower()])
	if route.is_empty():
		_label(box, "  ● no way through (steep inclines)", RED)
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
			_label(box, "  ● %s: no way through (steep inclines)" % m.name, m.color)
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
		var kind: Dictionary = Data.UNITS[Units.glyph_kind(u)]
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
	_label(box, "War rigs, planes and river boats carry a tank, shown as a fuel gauge by the portraits. When it runs dry the vehicle is lost and the crew go on foot. A plane crashes: some aboard may die, and the rest are injured.", DIM)


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
	_label(box, "March to their fort (long marches tire troops; war rigs need a way around steep inclines):", DIM)
	_travel_lines(box, _routes_between(Game.home(Data.PLAYER), Game.home(Data.AI)))
	_label(box, "Their raid strength ~%.1f vs your defense %.1f" % [Game.ai_attack(),
		Game.player_wall_defense() + Game.player_troop_defense()], DIM)
	if ai["truce"] > 0:
		_label(box, "Bribed: no raids for %d seasons." % ai["truce"], GREEN)
	_button(box, "RAID them (your attack %.1f vs their defense ~%.1f)" % [Game.player_attack(Game.home(Data.AI)),
		Game.ai_defense(Game.wall_breach())], Game.raid_ai, raid_why)
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
		_button(box, "Conquer (attack %.1f vs 8)" % Game.player_attack(Game.home(Data.TOWN)), Game.conquer_town, raid_why)
	elif town["status"] == "ally":
		_label(box, "Allied: sends 2 gold + 3 grain each season.", GREEN)
