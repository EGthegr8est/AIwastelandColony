extends SceneTree
## Adds the two pictures the nukes need to the end of art/atlas.png and art/atlas.json, in all four styles: "scorched_ash"
## (the ground a blast leaves: ash sand gone grey, with green-yellow glowing flecks like fallout waste has) and "bomber" (the
## Bomber, drawn from rows of letters like the building pictures; the units are the same in every style). Safe to run again:
## it rewrites those two rows and nothing else.
##
## Run from the project folder, then re-import:
##     godot --headless --path . -s res://tools/make_nuke_sprites.gd
##     godot --headless --path . --import

const PNG := "res://art/atlas.png"
const JSON_FILE := "res://art/atlas.json"
const SIZE := 8
const NEW := ["scorched_ash", "bomber"]

const PALETTE := {"r": Color("d8442c"), "R": Color("8a2a1c"), "k": Color("1c1511"), "w": Color("e8e4d8")}
const BOMBER := [
	"...rr...",
	"...rr...",
	"..rRRr..",
	"rrrRRrrr",
	"RRRwwRRR",
	"..rRRr..",
	"...RR...",
	"..rrrr..",
]


func _init() -> void:
	var atlas := Image.load_from_file(PNG)
	atlas.convert(Image.FORMAT_RGBA8)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JSON_FILE))
	for name in NEW:
		meta.sprites.erase(name)
	# the atlas without any earlier copy of the new rows: they always sit below every other sprite
	var rows := 0
	for name in meta.sprites:
		for o in meta.sprites[name].options:
			rows = maxi(rows, int(o.y) + int(o.h))
	var grown := Image.create(atlas.get_width(), rows + SIZE * NEW.size(), false, Image.FORMAT_RGBA8)
	grown.blit_rect(atlas, Rect2i(0, 0, atlas.get_width(), rows), Vector2i.ZERO)
	for i in NEW.size():
		var y := rows + i * SIZE
		var options := []
		for style in range(1, 5):
			var img := _scorched(style) if NEW[i] == "scorched_ash" else _bomber()
			grown.blit_rect(img, Rect2i(0, 0, SIZE, SIZE), Vector2i((style - 1) * SIZE, y))
			options.append({"h": SIZE, "n": style, "w": SIZE, "x": (style - 1) * SIZE, "y": y})
		meta.sprites[NEW[i]] = {"kind": "terrain" if NEW[i] == "scorched_ash" else "unit",
			"legend": "Scorched ash sand" if NEW[i] == "scorched_ash" else "Bomber", "options": options}
	grown.save_png(ProjectSettings.globalize_path(PNG))
	var f := FileAccess.open(JSON_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  ", true))
	f.close()
	print("ATLAS ", grown.get_size(), " sprites ", meta.sprites.size())
	quit()


## Ash sand gone grey. Style 4 fills the whole tile (dark ash, pale flecks, a few green-yellow glowing ones); the sparse styles
## 1 to 3 have see-through ground, like ash sand's, with the same flecks.
func _scorched(style: int) -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var ground := Color(0.30, 0.285, 0.265) if style == 4 else Color(0, 0, 0, 0)
	img.fill(ground)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7700 + style
	var pale := Color(0.62, 0.60, 0.56)
	var dark := Color(0.17, 0.16, 0.15)
	var glow := Color(0.78, 0.92, 0.24)
	var flecks: int = {1: 5, 2: 4, 3: 7, 4: 6}[style]
	for i in flecks:
		img.set_pixel(rng.randi_range(0, 7), rng.randi_range(0, 7), pale)
	if style == 4:
		for i in 5:
			img.set_pixel(rng.randi_range(0, 7), rng.randi_range(0, 7), dark)
	for i in 3:
		img.set_pixel(rng.randi_range(0, 7), rng.randi_range(0, 7), glow)
	return img


func _bomber() -> Image:
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	for y in SIZE:
		for x in SIZE:
			var ch: String = BOMBER[y][x]
			img.set_pixel(x, y, PALETTE.get(ch, Color(0, 0, 0, 0)))
	return img
