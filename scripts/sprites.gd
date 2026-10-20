extends RefCounted
## The pixel-art sprites (16 x 16 each) from art/atlas16.png, described by art/atlas16.json: one picture for
## every kind of ground, slope, unit and tribe camp. The look fills the whole tile with one colour and one bold
## shape, with its slopes drawn as dark ledges: see tools/make_tiles16.gd. `style` is that look (CLEAN) or 0 for the text
## glyphs (the legend and the field tablet flip between them). The atlas is read with
## Image.load_from_file, like the portraits and icons are drawn in code, so it doesn't need importing.
## Show the textures with nearest-neighbour filtering to keep the pixels crisp.

const SeasonReplay = preload("res://scripts/season_replay.gd")
const ATLAS_PNG := "res://art/atlas16.png"
const ATLAS_JSON := "res://art/atlas16.json"
const SIZE := 16
## The pixel-art look: every ground picture covers its whole tile, so the map skips the ground wash under it, and it
## lays height shades and your territory's tint over the picture instead.
const CLEAN := 1

# Which sprite in the atlas draws each thing in the game
const TERRAIN := {"sand": "ash_sand", "dunes": "dunes", "scrub": "dead_scrub", "trees": "petrified_wood", "grove": "green_grove",
	"rock": "rock", "ruins": "ruins", "crater": "crater", "glass": "fused_glass", "waste": "fallout_waste", "ash": "scorched_ash", "water": "river"}
const SLOPES := {"gentle": "gentle_slope", "steep": "steep_incline"}
## A river tile that can be waded has a picture of its own (it is still terrain "water", with a flag: see Game.is_ford).
const FORD := "ford"
const UNITS := {"scav": "scavenger", "scout": "scout", "caravan": "caravan", "car": "war_rig", "boat": "boat",
	"plane": "recon_plane", "bomber": "bomber", "band": "raider_band"}
const CAMPS := {"raider": "raider_camp", "trader": "trader_camp", "builder": "builder_camp"}

## What the legend and the map show: the pixel art (CLEAN), or 0 for the old text glyphs.
static var style := CLEAN
## The things you can pick: the pixel art and the text glyphs (0), which the map-art tablet in the top bar and the legend's buttons flip between.
const CHOICES := [CLEAN, 0]

static var _atlas: Image
static var _atlas_texture: ImageTexture
static var _meta := {}
static var _loaded := false
static var _cache := {}
static var _rects := {}


## False if the atlas can't be read, in which case everything here returns null and the game shows
## its text glyphs instead.
static func available() -> bool:
	_load()
	return _atlas != null


## Every sprite name the atlas has.
static func names() -> Array:
	_load()
	return _meta.get("sprites", {}).keys()


static func terrain(id: String) -> Texture2D:
	return texture(TERRAIN.get(id, ""))


## A slope's picture for the legend. In the clean look a slope is a see-through dark ledge that only means something
## over ground, so it is shown over a sand tile (on the dark legend panel it would vanish).
static func slope(id: String) -> Texture2D:
	var sprite: String = SLOPES.get(id, "")
	if state() == 0:
		return null
	var key := "%s:on_sand" % sprite
	if not _cache.has(key):
		if not _meta.get("sprites", {}).has(sprite):
			return null
		var img := image(TERRAIN["sand"])
		img.blend_rect(image(sprite), Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]

## True when the clean look (style 4) is showing.
static func clean() -> bool:
	return state() == CLEAN


static func unit(id: String) -> Texture2D:
	if state() != 0 and UNITS32.has(id) and units32_available():
		var key := "unit32:" + id
		if not _cache.has(key):
			var t := AtlasTexture.new()
			t.atlas = picture(UNITS32_PNG)
			t.region = unit32_rect(id)
			_cache[key] = t
		return _cache[key]
	return texture(UNITS.get(id, ""))


## The units drawn at twice the detail (32 x 32 pixels in one tile's space), one row left to right: see tools/make_units32.gd.
const UNITS32_PNG := "res://art/units32.png"
const UNITS32 := {"scav": 0, "scout": 1, "car": 2, "band": 4}
const UNIT32_SIZE := 32


## False if the 32 x 32 unit pictures can't be read: the map then draws these units from the 16 x 16 atlas.
static func units32_available() -> bool:
	return picture(UNITS32_PNG) != null


## Where a unit's 32 x 32 picture is in art/units32.png, or an empty rectangle if it has none (or the file is missing).
static func unit32_rect(kind: String) -> Rect2:
	if not UNITS32.has(kind) or not units32_available():
		return Rect2()
	return Rect2(UNITS32[kind] * UNIT32_SIZE, 0, UNIT32_SIZE, UNIT32_SIZE)


static func camp(tribe_class: String) -> Texture2D:
	return texture(CAMPS.get(tribe_class, ""))


## What's showing right now: CLEAN, or 0 for the text glyphs, which is also what you get
## if the atlas couldn't be read.
static func state() -> int:
	_load()
	return style if _atlas != null else 0


## Picks what the legend and the map show: the pixel art (any n above 0) or 0 for the text glyphs.
static func choose(n: int) -> void:
	style = CLEAN if n > 0 else 0


## Moves on to the other choice: the clean pixel art, then the text glyphs, then the pixel art again.
static func cycle() -> void:
	style = CHOICES[(CHOICES.find(style) + 1) % CHOICES.size()]


## The whole atlas as one texture. The map draws every sprite from it, so they all batch together.
static func atlas_texture() -> Texture2D:
	_load()
	if _atlas == null:
		return null
	if _atlas_texture == null:
		_atlas_texture = ImageTexture.create_from_image(_atlas)
	return _atlas_texture


## Where each sprite is in the atlas: {"ash_sand": Rect2(0, 0, 16, 16), ...}. Empty when the text glyphs are showing.
static func rects() -> Dictionary:
	if state() == 0:
		return {}
	if _rects.is_empty():
		for sprite in _meta.sprites:
			_rects[sprite] = rect(sprite)
	return _rects


## Where one sprite is in the atlas.
static func rect(sprite: String) -> Rect2:
	_load()
	if _atlas == null or not _meta.get("sprites", {}).has(sprite):
		return Rect2()
	var o: Dictionary = _meta.sprites[sprite]
	return Rect2(float(o.x), float(o.y), float(o.w), float(o.h))


## The sprite called `sprite`, or null if there's no such sprite, or if the text glyphs are showing.
static func texture(sprite: String) -> Texture2D:
	_load()
	if _atlas == null or not _meta.get("sprites", {}).has(sprite):
		return null
	if style == 0:
		return null
	if not _cache.has(sprite):
		_cache[sprite] = ImageTexture.create_from_image(image(sprite))
	return _cache[sprite]


## The pixels of one sprite.
static func image(sprite: String) -> Image:
	_load()
	var o: Dictionary = _meta.sprites[sprite]
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	img.blit_rect(_atlas, Rect2i(int(o.x), int(o.y), int(o.w), int(o.h)), Vector2i.ZERO)
	return img


# ---------------------------------------------------------------- animals

const ANIMALS := ["deer", "black_bear", "brown_bear", "frog"]   # the order of the pictures in art/animals.png: three 16 x 16, then the frog's 32 x 32
const ANIMALS_PNG := "res://art/animals.png"
const ANIMAL_SIZE := 16
const FROG_RECT := Rect2(48, 0, 32, 32)
static var _animal_cache := {}


## False if the animals' picture can't be read: the map then shows each animal's letter.
static func animals_available() -> bool:
	return picture(ANIMALS_PNG) != null


## The whole animals picture as one texture, for the map to draw from (they are not part of the atlas: they are
## drawn at their own size, the deer and bears 16 x 16 on one tile, the frog 32 x 32 across 2 x 2 tiles).
static func animals_texture() -> Texture2D:
	return picture(ANIMALS_PNG)


## Where an animal's picture is in that texture, or an empty rectangle for an unknown kind.
static func animal_rect(kind: String) -> Rect2:
	if kind == "frog":
		return FROG_RECT
	var i := ANIMALS.find(kind)
	return Rect2(i * ANIMAL_SIZE, 0, ANIMAL_SIZE, ANIMAL_SIZE) if i >= 0 and i < 3 else Rect2()


## One animal's picture as its own texture (for the legend), or null.
static func animal(kind: String) -> Texture2D:
	var atlas := animals_texture()
	var r := animal_rect(kind)
	if atlas == null or r.size == Vector2.ZERO:
		return null
	if not _animal_cache.has(kind):
		var t := AtlasTexture.new()
		t.atlas = atlas
		t.region = r
		_animal_cache[kind] = t
	return _animal_cache[kind]


# ---------------------------------------------------------------- points of interest

const POI_PNG := "res://art/poi_atlas.png"     # one row of 32 x 32 sprites: each is a 2 x 2 tile site
const POI_JSON := "res://art/poi_atlas.json"
const POI_SIZE := 32
static var _poi_meta := {}
static var _poi_loaded := false
static var _poi_cache := {}


## False if the points-of-interest atlas can't be read: the map then shows each site's letter instead.
static func poi_available() -> bool:
	_load_poi()
	return not _poi_meta.is_empty() and poi_atlas_texture() != null


## The whole points-of-interest atlas as one texture, for the map to draw from.
static func poi_atlas_texture() -> Texture2D:
	return picture(POI_PNG)


## Where a site's 16 x 16 sprite is in the atlas, or an empty rectangle for an unknown kind.
static func poi_rect(kind: String) -> Rect2:
	_load_poi()
	var sprites: Dictionary = _poi_meta.get("sprites", {})
	if not sprites.has(kind):
		return Rect2()
	var o: Dictionary = sprites[kind]
	return Rect2(float(o.x), float(o.y), float(o.w), float(o.h))


## One quarter of a site's sprite (`q` is Vector2i(0..1, 0..1)): the 16 x 16 piece one of its four tiles draws.
static func poi_quadrant_rect(kind: String, q: Vector2i) -> Rect2:
	var r := poi_rect(kind)
	if r.size == Vector2.ZERO:
		return r
	return Rect2(r.position + Vector2(q) * (POI_SIZE / 2.0), Vector2(POI_SIZE / 2.0, POI_SIZE / 2.0))


## A site's whole sprite as its own texture (for the legend), or null.
static func poi_sprite(kind: String) -> Texture2D:
	var atlas := poi_atlas_texture()
	var r := poi_rect(kind)
	if atlas == null or r.size == Vector2.ZERO:
		return null
	if not _poi_cache.has(kind):
		var t := AtlasTexture.new()
		t.atlas = atlas
		t.region = r
		_poi_cache[kind] = t
	return _poi_cache[kind]


## Every kind of site the atlas has a sprite for.
static func poi_kinds() -> Array:
	_load_poi()
	return _poi_meta.get("sprites", {}).keys()


static func _load_poi() -> void:
	if _poi_loaded:
		return
	_poi_loaded = true
	if not FileAccess.file_exists(POI_JSON):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(POI_JSON))
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("sprites"):
		_poi_meta = parsed


# ---------------------------------------------------------------- buildings (clean look only)

const BUILDING_PNG := "res://art/building_atlas.png"    # one row of 16 x 16 pictures, see tools/make_buildings.gd
const BUILDING_JSON := "res://art/building_atlas.json"
static var _building_meta := {}
static var _building_loaded := false


## The whole building atlas as one texture, for the map to draw from (null if it can't be read).
static func building_atlas_texture() -> Texture2D:
	return picture(BUILDING_PNG)


## The legend's picture of a road (a pale strip) or of the old highway (grey, with a dash): 16 x 16, drawn here, or null with the text glyphs.
static func road_icon(highway: bool) -> Texture2D:
	if state() == 0:
		return null
	var key := "road_icon:%s" % highway
	if not _cache.has(key):
		var fill := Color("7e7b75") if highway else Color("b3a37a")
		var edge := Color("2b2926") if highway else Color("4a4030")
		var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		for y in SIZE:
			img.set_pixel(3, y, edge)
			img.set_pixel(12, y, edge)
			for x in range(4, 12):
				img.set_pixel(x, y, fill)
		if highway:
			for y in [2, 3, 4, 10, 11, 12]:
				img.set_pixel(7, y, Color("c8c4b8"))
				img.set_pixel(8, y, Color("c8c4b8"))
		_cache[key] = ImageTexture.create_from_image(img)
	return _cache[key]


## A building's picture as its own texture (for the legend), or null where the other looks show it as a letter.
static func building(id: String) -> Texture2D:
	var atlas := building_atlas_texture()
	var r := building_rect(id)
	if atlas == null or r.size == Vector2.ZERO or not clean():
		return null
	var key := "building:" + id
	if not _cache.has(key):
		var t := AtlasTexture.new()
		t.atlas = atlas
		t.region = r
		_cache[key] = t
	return _cache[key]


## Where a building's 16 x 16 picture is in that texture, or an empty rectangle if it has none (it is then drawn as its letter).
static func building_rect(id: String) -> Rect2:
	if id == "ai_airfield":
		id = "airfield"   # the Rust Kings' airfield is drawn like yours (the map tints it their colour)
	_load_buildings()
	var sprites: Dictionary = _building_meta.get("sprites", {})
	if not sprites.has(id) or building_atlas_texture() == null:
		return Rect2()
	var o: Dictionary = sprites[id]
	return Rect2(float(o.x), float(o.y), float(o.w), float(o.h))


## Every building that has a picture.
static func building_ids() -> Array:
	_load_buildings()
	return _building_meta.get("sprites", {}).keys()


static func _load_buildings() -> void:
	if _building_loaded:
		return
	_building_loaded = true
	if not FileAccess.file_exists(BUILDING_JSON):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(BUILDING_JSON))
	if typeof(parsed) == TYPE_DICTIONARY and parsed.has("sprites"):
		_building_meta = parsed


# ---------------------------------------------------------------- the title screen and the logo

const TITLE_PNG := "res://art/title.png"      # 1920 x 1080: fills the screen behind the main menu's buttons
const LOGO_PNG := "res://art/logo.png"        # the "slab stack" logo, with a frame and sparkles around it
const LOGO_CROP := Rect2(82, 103, 803, 306)   # just the logo and its shadow
static var _pictures := {}


## The title screen, or null if it can't be read (the main menu then falls back to a plain panel).
static func title() -> Texture2D:
	return picture(TITLE_PNG)


## The slab-stack logo (WASTELAND over COLONY), cropped from its frame, or null if it can't be read.
static func logo() -> Texture2D:
	if not _pictures.has("logo"):
		var whole := picture(LOGO_PNG)
		var cropped: AtlasTexture = null
		if whole != null:
			cropped = AtlasTexture.new()
			cropped.atlas = whole
			cropped.region = LOGO_CROP
		_pictures["logo"] = cropped
	return _pictures["logo"]


## The color of the logo's background (it isn't pure black), so what the logo sits on can match it.
static func logo_background() -> Color:
	if not _pictures.has("logo_bg"):
		var shown := logo()
		var c := Color.BLACK
		if shown != null:
			c = shown.get_image().get_pixel(0, 0)
		_pictures["logo_bg"] = Color(c.r, c.g, c.b, 1.0)
	return _pictures["logo_bg"]


## A whole picture from the project, or null if it isn't there. Once Godot has imported it, it loads
## like any resource (this also works in an exported game). A fresh copy of the project that hasn't
## been opened in the editor yet has no import, so fall back to reading the file directly.
static func picture(path: String) -> Texture2D:
	if not _pictures.has(path):
		_pictures[path] = _read_picture(path)
	return _pictures[path]


static func _read_picture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var imported = load(path)
		if imported is Texture2D:
			return imported
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	# In an exported game the original PNG isn't shipped, only Godot's imported copy of it, so
	# FileAccess can't see it but ResourceLoader can. (The JSON is shipped as it is.)
	if not (ResourceLoader.exists(ATLAS_PNG) or FileAccess.file_exists(ATLAS_PNG)) or not FileAccess.file_exists(ATLAS_JSON):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(ATLAS_JSON))
	# Once Godot has imported the picture, load it like any resource (this also works in an exported
	# game). A fresh copy of the project that hasn't been opened in the editor yet has no import, so
	# fall back to reading the file directly.
	var img: Image = null
	if ResourceLoader.exists(ATLAS_PNG):
		var imported = load(ATLAS_PNG)
		if imported is Texture2D:
			img = imported.get_image()
	if img == null:
		img = Image.load_from_file(ATLAS_PNG)
	if typeof(parsed) != TYPE_DICTIONARY or img == null or img.is_empty():
		return
	img.convert(Image.FORMAT_RGBA8)
	_meta = parsed
	_atlas = img
