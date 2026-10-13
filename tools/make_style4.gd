extends SceneTree
## Bakes the "clean" look (art style 4) into art/atlas.png and art/atlas.json: a fourth column of 8 x 8 pictures beside the
## three that are already there (those are never touched). The grounds and the two slope ledges are drawn here, as text
## rows you can nudge; the units and camps are copies of style 1's.
##
## Run from the project folder (it works without Godot's editor, and can be run again any time):
##     godot --headless --path . -s res://tools/make_style4.gd
## then re-import so the game sees the new picture:   godot --headless --path . --import
##
## Each ground is a solid colour (every pixel of the tile is drawn) with one bold shape on it. The colours are the "dusk" look:
## the mock's bright colours darkened by DUSK and warmed. Letters in the rows: a = dark shade, b = light shade, and for the
## things that glow (o = lit window, g = glow, h = glow centre) the colour is NOT darkened, so danger stands out from matte ground.

const ATLAS_PNG := "res://art/atlas.png"
const ATLAS_JSON := "res://art/atlas.json"
const SIZE := 8
const STYLE := 4
const DUSK := 0.42
const WARM := Color(1.0, 0.97, 0.92)
const LIT := ["o", "g", "h"]

# fill, and the letters each ground's rows use
const GROUNDS := {
	"ash_sand":       {"fill": "cdb98e", "a": "b39c70", "b": "e3d5b3"},
	"dunes":          {"fill": "e2bf7c", "a": "bd8f4c", "b": "f3dca6"},
	"dead_scrub":     {"fill": "8e9552", "a": "656c34", "b": "b4ba76"},
	"petrified_wood": {"fill": "5b4a34", "a": "3d3022", "b": "9a784b"},
	"green_grove":    {"fill": "3f8a45", "a": "2a6030", "b": "86d474"},
	"rock":           {"fill": "8d939e", "a": "5c626e", "b": "c8cdd8"},
	"ruins":          {"fill": "4d5059", "a": "30333b", "b": "737885", "o": "ee8a3c"},
	"crater":         {"fill": "1a3210", "a": "10200a", "g": "7cfc00", "h": "caff7e", "dark_fill": true},
	"fused_glass":    {"fill": "5f45a8", "a": "43307a", "b": "ac92ea", "lit_b": true},
	"fallout_waste":  {"fill": "484b1d", "a": "33360f", "b": "ebe55e", "lit_b": true},
	"river":          {"fill": "2c6f8c", "a": "1d5570", "b": "74bdd4"},
}

const ROWS := {
	"ash_sand":       ["........", ".b....a.", "......b.", "..a.....", "....b...", ".a....b.", "...b....", "......a."],
	"dunes":          ["........", ".bbb....", "b...bb..", "a.....b.", ".aaa....", "a...aa..", "......a.", "........"],
	"dead_scrub":     ["........", "...a....", ".a.a..a.", ".a.a.a..", "..aaa...", "...a..b.", ".b......", "........"],
	"petrified_wood": ["........", ".b...b..", ".bb..bb.", ".b...b..", ".b..ab..", ".a..aa..", "aaa.aaa.", "........"],
	"green_grove":    ["..bbb...", ".bbbbb..", ".bbabb..", "..bbb...", "...a....", "b.......", "bb...bb.", ".....b.."],
	"rock":           ["........", "...bb...", "..bbbb..", "..bbab..", ".bbbaaa.", ".bbaaaa.", "aaaaaaaa", "........"],
	"ruins":          ["........", ".aa.aaa.", ".ao.aoa.", ".aa.aaa.", ".ao.....", ".aa.aao.", "aaaaaaaa", "........"],
	"crater":         ["........", "..gggg..", ".g....g.", ".g.hh.g.", ".g.hh.g.", ".g....g.", "..gggg..", "........"],
	"fused_glass":    ["b..b....", ".bb..b.b", "........", "..b..bb.", ".b......", "...b..b.", "b..bb...", "....b..b"],
	"fallout_waste":  [".b...b..", "...b....", "b....b.b", "..b.....", "....b...", ".b...b..", "......b.", "b...b..."],
	"river":          ["........", ".bb..bb.", "b..bb...", "........", "..bb..bb", ".b..bb..", "........", "........"],
}

# The slope ledges are not solid: they are dark shades the map lays over any ground, along the tile's lower edge.
# Digits are how dark: 1 = light shade, 2 = medium, 3 = deep.
const LEDGES := {
	"gentle_slope":  ["........", "........", "........", "........", "........", "........", "........", "22222222"],
	"steep_incline": ["........", "........", "........", "........", "........", "2.2.2.2.", "22222222", "33333333"],
}
const LEDGE_ALPHA := {"1": 0.25, "2": 0.45, "3": 0.65}


func _initialize() -> void:
	var img := Image.load_from_file(ATLAS_PNG)
	var meta = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
	if img == null or img.is_empty() or typeof(meta) != TYPE_DICTIONARY:
		push_error("make_style4: can't read the atlas")
		quit(1)
		return
	img.convert(Image.FORMAT_RGBA8)
	# Start from the three styles that were there: a taller or already-widened atlas is cut back to them
	var base := Image.create(SIZE * STYLE, img.get_height(), false, Image.FORMAT_RGBA8)
	base.blit_rect(img, Rect2i(0, 0, SIZE * (STYLE - 1), img.get_height()), Vector2i.ZERO)
	for sprite in meta.sprites:
		var options: Array = meta.sprites[sprite].options
		var first: Dictionary = options[0]
		var picture := _picture(sprite, img, first)
		var at := Vector2i(SIZE * (STYLE - 1), int(first.y))
		base.blit_rect(picture, Rect2i(0, 0, SIZE, SIZE), at)
		var record := {"n": STYLE, "x": at.x, "y": at.y, "w": SIZE, "h": SIZE}
		if options.size() >= STYLE:
			options[STYLE - 1] = record
		else:
			options.append(record)
	meta["columns"] = STYLE
	base.save_png(ATLAS_PNG)
	var f := FileAccess.open(ATLAS_JSON, FileAccess.WRITE)
	f.store_string(JSON.stringify(_whole_numbers(meta), "  "))
	f.close()
	print("make_style4: wrote ", base.get_size(), " with ", meta.sprites.size(), " sprites")
	quit()


## One sprite's style-4 picture: a ground, a slope ledge, or (for units and camps) style 1's with an outline.
func _picture(sprite: String, atlas: Image, first: Dictionary) -> Image:
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	if GROUNDS.has(sprite):
		var look: Dictionary = GROUNDS[sprite]
		out.fill(_tone(look, "fill"))
		for y in SIZE:
			for x in SIZE:
				var ch: String = ROWS[sprite][y][x]
				if ch != "." and look.has(ch):
					out.set_pixel(x, y, _tone(look, ch))
	elif LEDGES.has(sprite):
		for y in SIZE:
			for x in SIZE:
				var ch: String = LEDGES[sprite][y][x]
				if ch != ".":
					out.set_pixel(x, y, Color(0.04, 0.03, 0.02, LEDGE_ALPHA[ch]))
	else:
		out.blit_rect(atlas, Rect2i(int(first.x), int(first.y), SIZE, SIZE), Vector2i.ZERO)
	return out


## JSON numbers come back as floats: turn the whole ones into ints again so the file reads 8, not 8.0.
func _whole_numbers(v):
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _whole_numbers(v[k])
		return d
	if v is Array:
		return v.map(_whole_numbers)
	if v is float and v == floorf(v):
		return int(v)
	return v


## A letter's colour in the dusk look: darkened and warmed, except the glowing letters (and a ground's lit shade).
func _tone(look: Dictionary, letter: String) -> Color:
	var c := Color("#" + look[letter])
	var lit: bool = letter in LIT or (letter == "b" and look.get("lit_b", false)) or (letter == "fill" and look.get("dark_fill", false))
	return c if lit else c.darkened(DUSK) * WARM
