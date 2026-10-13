extends Node2D
## Draws the map: a pixel-art sprite per tile on a dark cell (art/atlas.png, see sprites.gd), or, with
## the text glyphs chosen, Dwarf Fortress style, one colored glyph per tile. Buildings have no sprites
## yet, so they are always drawn as text.

const Data = preload("res://scripts/data.gd")
const Sprites = preload("res://scripts/sprites.gd")
const SeasonReplay = preload("res://scripts/season_replay.gd")
const Daylight = preload("res://scripts/daylight.gd")
# Sprites are 8 x 8, so a 16 pixel cell shows them at exactly 2x: every art pixel the same size,
# and tiles that meet without gaps.
const CELL := Vector2(16, 16)
const FONT_SIZE := 16
# Indexed by owner: none, player, AI, town
const OWNER_BG := [Color("15100b"), Color("1d2814"), Color("33140f"), Color("132030")]
const OWNER_EDGE := [Color(0, 0, 0, 0), Color("8fbf3a"), Color("d0402b"), Color("5a8fc5")]
const SELECT := Color("ffb642")
const LABEL_FONT := 14                       # the hover label's text size on screen, whatever the zoom
const LABEL_BG := Color(0.08, 0.06, 0.04, 0.92)
const LABEL_EDGE := Color(1.0, 0.71, 0.26, 0.6)
const LABEL_TEXT := Color("f0e0c0")
const FOG := Color("050403")
# Where each way of travel puts its route dot inside a tile, so overlapping routes stay visible
const ROUTE_DOT := {"foot": Vector2(3, 13), "horse": Vector2(8, 13), "car": Vector2(13, 13)}
# A picked scouting party's route: white while its pack is full, yellow as it runs down, red once it's empty
const FOOD_FULL := Color("ffffff")
const FOOD_LOW := Color("ffe03a")
const FOOD_OUT := Color("ff3a2a")
const SCOUT_DOT := Vector2(8, 13)
# What sprites are tinted with when the viewer can't see their tile right now (remembered ground, and
# camps and your own parties out of sight)
const SPRITE_DIM := Color(0.4, 0.4, 0.4)
const UNIT_DIM := Color(0.6, 0.6, 0.6)
# Slope marks are bright yellow and would drown out the ground they lie on, so they're half see-through
# (the old contour lines were a quiet shade of the ground too)
const SLOPE_TINT := Color(1, 1, 1, 0.5)
const SLOPE_DIM := Color(0.4, 0.4, 0.4, 0.5)
const CHUNK := 16   # the map is drawn in squares of CHUNK x CHUNK tiles

# The clean look (art style 4): its pictures cover the whole tile, so height and ownership are laid over them as
# faint washes. A third of the land is "low" (a touch darker) and a third "high" (a touch lighter).
const SHADE_LOW := Color(0, 0, 0, 0.07)
const SHADE_HIGH := Color(1, 1, 1, 0.08)
const OWN_TINT := 0.10        # how much of its owner's border colour an owned tile takes on
# A feature (anything but sand, dunes and scrub) gets a thin dark rim on each side that meets plainer ground, so a rock range
# or a lake reads as one shape. Where two features meet, the one with the higher number draws the rim.
const RIM_RANK := {"trees": 1, "grove": 2, "waste": 3, "ruins": 4, "rock": 5, "glass": 6, "crater": 7, "water": 8}
const RIM_INK := Color(0.07, 0.05, 0.03, 0.5)
const RIM := 2.0              # one art pixel, in canvas pixels
enum Shown {HIDDEN, SHOWN, DIM}   # how a unit standing on the map shows, see unit_shown()
# What stands on the map and moves, drawn every frame in a layer of its own (see UnitLayer)
const PATCH := Color(0, 0, 0, 0.7)         # the dark square under a unit
const HOP := 2.0                           # a step: the unit hops this many pixels (one art pixel)
const HOP_HZ := 8.0                        # hops a second while it walks
const IDLE_STEP := 0.6                     # a parked scouting party bobs one art pixel this often, in seconds
const IDLE_REDRAW := 0.1                   # the unit layer redraws this often while something idles
const HALO_REDRAW := 0.1                   # the halos redraw this often at night, so they flicker
const DUST := {"foot": Color(0.95, 0.88, 0.7), "horse": Color(0.95, 0.88, 0.7), "car": Color(0.9, 0.82, 0.68), "boat": Color(0.8, 0.94, 1.0)}
const DUST_ALPHA := 0.7
const EMBER := [Color("ff9a2e"), Color("ffd24a"), Color("e8541c")]   # a camp's cooking fire
const POP_COLOR := Color("ffe9a8")
const BAND_FADE := 5.0                     # how fast a raider band fades in and out at the edge of your sight (per second)

var font := SystemFont.new()
var hover := Vector2i(-1, -1)
var over_panel := false         # the mouse is over a panel or button, not the map: no hover label then
var pipe_scale := Vector2.ONE   # stretches box-drawing glyphs to fill a whole cell
var pipe_ascent := 0.0
var last_view := Transform2D()
var tile_layer := Node2D.new()          # holds the chunks
var chunks: Array[Chunk] = []
var chunk_map_size := Vector2i.ZERO     # the map size the chunks were made for
var chunks_across := 0
var stale := false                      # some chunk has dirty set
var check_needed := false               # the game changed: look for chunks that changed
var checked_view := -1                  # Game.view, Game.map_version and Sprites.state() at the last check
var checked_map := -1
var checked_art := -1
var night_layer := NightLayer.new()     # day and night (daylight.gd): between the ground and everything standing on it
var glow_layer := GlowLayer.new()
var halo_layer := HaloLayer.new()
var unit_layer := UnitLayer.new()       # units and camp fires, above the chunks: they move every frame while a season replays
var overlay_layer := OverlayLayer.new()
var light := 1.0                        # 1 = full day, 0 = full night: fades over the turn change
var _light_from := 1.0
var _light_to := 1.0
var _fade_clock := -1.0                 # real seconds into the fade, or -1 when none is running
var glow_cells := []                    # everything glowing right now: [cell, halo kind or "", how strongly (0 to 1)]
var glow_lit := {}                      # cell -> true: ruins that glow (an enemy party standing there is lit by them)
var glow_batch := Batch.new()           # the glowing tiles, drawn again over the night at full brightness
var glow_dirty := true
var glow_art := -1                      # Sprites.state() and Game.map_version when glow_batch was made
var glow_map := -1
var _glow_ground_map := -1
var _glow_ground: Array = []            # [cell, halo kind or ""] for every crater, and the waste and glass that keep their speckles
var _ruin_cells: Array = []
var _halo_accum := 0.0
var _halo_image: ImageTexture
var replay := {}                        # the season (or march) being played back, empty when none
var playing := false
var clock := 0.0                        # real seconds into it
var replay_secs := 3.0                  # real seconds a whole season takes at the chosen speed
var replay_length := 0.0                # real seconds this replay takes
var replay_season := 0                  # Game.season when it began: a different one means a load or a new game
var replay_ids := {}                    # unit id -> true for every unit the replay draws (the rest stand still)
var _fade := {}                         # actor id -> how visible it is, 0 to 1 (raider bands fade at the edge of sight)
var _last_delta := 0.0
var _idle_accum := 0.0
var _standing := {}                     # cache of _overlay() for the frame in _standing_frame
var _standing_frame := -1
# What each tile shows when nothing is built or standing on it. Terrain and contours only change
# with a new map, so this is worked out once per Game.map_version instead of on every redraw.
var ground_glyphs := PackedStringArray()
var ground_colors := PackedColorArray()   # in sight
var ground_dim := PackedColorArray()      # remembered but out of sight
var ground_pipes := PackedByteArray()     # 1 where the glyph is a contour pipe
var ground_bg := PackedColorArray()       # terrain color and height wash over the owner's background
var ground_bg_dim := PackedColorArray()
var ground_sprite := PackedStringArray()  # the atlas sprite for the terrain
var ground_slope := PackedStringArray()   # the atlas sprite for the slope laid over it, or ""
var ground_shade := PackedColorArray()    # the clean look's height wash: transparent for middling ground and water
var ground_flip := PackedByteArray()      # 1 where the clean look mirrors the ground picture
var ground_map := -1
var bg_dim: Array[Color] = []             # OWNER_BG and OWNER_EDGE for tiles out of sight
var edge_dim: Array[Color] = []
## Render counters for tests and benchmarks: tile-layer redraws, tiles drawn and the CPU time
## spent drawing them, plus overlay (hover, selection, routes) redraws.
var stats := {"tile_draws": 0, "tiles": 0, "usec": 0, "overlay_draws": 0, "unit_draws": 0}


## A square of tiles that draws itself once and keeps the result until the map changes. The
## renderer skips chunks that are off screen, so panning and zooming cost nothing.
class Chunk:
	extends Node2D
	var map: Node2D
	var tiles: Rect2i     # which tiles it covers
	var area: Rect2       # the same, in pixels, grown a cell for glyphs and borders that spill over
	var dirty := false    # out of date: redraw it next time it's on screen
	var signature := 0    # hash of everything it shows, from the last check

	func _draw() -> void:
		map.draw_chunk(self)


## What one chunk will draw, collected tile by tile and then drawn in passes (see draw_chunk).
class Batch:
	var rects := {}                              # atlas sprite -> its rectangle in the atlas, or empty for text glyphs
	var glyphs := []                             # [position, glyph, color, is pipe] per piece of text
	var lines := PackedVector2Array()            # border segments, two points each
	var line_colors := PackedColorArray()        # one per segment
	var sprite_pos := PackedVector2Array()       # where each sprite goes
	var sprite_src: Array[Rect2] = []            # which part of the atlas it is
	var sprite_tint := PackedColorArray()        # dimmed when out of sight
	var poi_pos := PackedVector2Array()          # where each quarter of a point-of-interest sprite goes
	var poi_src: Array[Rect2] = []               # which 8 x 8 piece of the points-of-interest atlas it is
	var poi_tint := PackedColorArray()           # dimmed when out of sight
	var heat_pos := PackedVector2Array()         # radiation tints that go over the sprites
	var heat_color := PackedColorArray()
	# The clean look draws in more passes: ground sprites, then the height and ownership washes, then (above the wash)
	# the dark patch under a camp and the camps themselves.
	var sprite_flip := PackedByteArray()         # 1 where the sprite is drawn mirrored, for a little variety
	var shade_pos := PackedVector2Array()
	var shade_color := PackedColorArray()
	var patch_pos := PackedVector2Array()
	var top_pos := PackedVector2Array()          # sprites that go over the wash
	var top_src: Array[Rect2] = []
	var top_tint := PackedColorArray()
	var bld_pos := PackedVector2Array()          # building pictures (their own atlas), over everything else on the tile
	var bld_src: Array[Rect2] = []
	var bld_tint := PackedColorArray()
	var edge_rects: Array[Rect2] = []            # the dark rim a feature (rock, water, ruins...) gets where it meets plainer ground
	var edge_colors := PackedColorArray()

	func add_building(pos: Vector2, src: Rect2, tint: Color) -> void:
		bld_pos.append(pos)
		bld_src.append(src)
		bld_tint.append(tint)

	func add_sprite(pos: Vector2, sprite: String, tint: Color, flip := false) -> void:
		sprite_pos.append(pos)
		sprite_src.append(rects[sprite])
		sprite_tint.append(tint)
		sprite_flip.append(1 if flip else 0)

	func add_top(pos: Vector2, sprite: String, tint: Color) -> void:
		top_pos.append(pos)
		top_src.append(rects[sprite])
		top_tint.append(tint)

	func add_poi(pos: Vector2, src: Rect2, tint: Color) -> void:
		poi_pos.append(pos)
		poi_src.append(src)
		poi_tint.append(tint)


## Draws the hover box, selection box and route dots over the tiles. It's a canvas item of its
## own, so moving the mouse redraws a handful of shapes instead of every tile on screen.
class OverlayLayer:
	extends Node2D
	var map: Node2D

	func _draw() -> void:
		map.draw_overlay(self)


## Draws the units (and the camp fires) over the cached chunks. The chunks only redraw when the ground changes, so a
## unit standing, hopping or walking across the map costs a few sprites a frame and no chunk redraws.
class UnitLayer:
	extends Node2D
	var map: Node2D

	func _draw() -> void:
		map.draw_units(self)


## The night: one white rectangle over the map, multiplied into the ground under it (its strength is its self_modulate).
class NightLayer:
	extends Node2D
	var map: Node2D

	func _ready() -> void:
		var multiply := CanvasItemMaterial.new()
		multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
		material = multiply

	func _draw() -> void:
		draw_rect(map.map_pixels().grow(512.0), Color.WHITE)


## The glowing tiles, drawn again over the night at full brightness (the clean look only: the other looks keep them dark).
class GlowLayer:
	extends Node2D
	var map: Node2D

	func _draw() -> void:
		map.draw_glow_tiles(self)


## The soft light round glowing things and your own parties. A layer of its own, smooth-filtered: the map's layers are pixel art.
class HaloLayer:
	extends Node2D
	var map: Node2D

	func _draw() -> void:
		map.draw_halos(self)


func _ready() -> void:
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	Game.changed.connect(func():
		check_needed = true
		glow_dirty = true)
	add_child(tile_layer)
	night_layer.map = self
	add_child(night_layer)
	glow_layer.map = self
	add_child(glow_layer)
	halo_layer.map = self
	halo_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(halo_layer)
	unit_layer.map = self
	add_child(unit_layer)
	overlay_layer.map = self
	add_child(overlay_layer)
	Game.changed.connect(overlay_layer.queue_redraw)
	Game.changed.connect(unit_layer.queue_redraw)
	Game.season_played.connect(_on_season_played)
	Game.troops_marched.connect(_on_troops_marched)
	Game.replay_skip.connect(finish_replay)
	# A monospace glyph is narrower than our square cell, so pipes would leave gaps.
	# Scale them so the glyph box exactly covers the cell, like a square DF tileset.
	var glyph_box := font.get_string_size("─", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	pipe_scale = CELL / glyph_box
	pipe_ascent = font.get_ascent(FONT_SIZE)
	for owner in OWNER_BG.size():
		bg_dim.append(OWNER_BG[owner].darkened(0.4))
		edge_dim.append(OWNER_EDGE[owner].darkened(0.5))


## Chunks keep what they drew, so moving the camera redraws nothing. When the game changes,
## the chunks on screen redraw right away and the rest wait until they scroll into view.
func _process(delta: float) -> void:
	tile_layer.visible = Game.in_game
	unit_layer.visible = Game.in_game
	_sync_night_layers()
	if not Game.in_game:
		if playing:
			finish_replay()
		return
	_tick_replay(delta)
	_tick_light(delta)
	var on_panel := get_viewport().gui_get_hovered_control() != null
	if on_panel != over_panel:
		over_panel = on_panel
		overlay_layer.queue_redraw()
	if chunk_map_size != Vector2i(Game.w, Game.h):
		_make_chunks()
	if check_needed:
		_find_changed_chunks()
	if not stale and get_canvas_transform() == last_view:
		return
	last_view = get_canvas_transform()
	var inv := last_view.affine_inverse()
	var screen := get_viewport_rect()
	var on_screen := Rect2(inv * screen.position, Vector2.ZERO).expand(inv * screen.end)
	stale = false
	for chunk in chunks:
		if not chunk.dirty:
			continue
		if chunk.area.intersects(on_screen):
			chunk.dirty = false
			chunk.queue_redraw()
		else:
			stale = true


## One chunk per CHUNK x CHUNK tiles (smaller at the right and bottom edges).
func _make_chunks() -> void:
	for chunk in chunks:
		chunk.free()
	chunks = []
	chunk_map_size = Vector2i(Game.w, Game.h)
	chunks_across = ceili(Game.w / float(CHUNK))
	for y in range(0, Game.h, CHUNK):
		for x in range(0, Game.w, CHUNK):
			var chunk := Chunk.new()
			chunk.map = self
			chunk.tiles = Rect2i(x, y, mini(CHUNK, Game.w - x), mini(CHUNK, Game.h - y))
			chunk.area = Rect2(Vector2(chunk.tiles.position) * CELL, Vector2(chunk.tiles.size) * CELL).grow(CELL.x)
			chunks.append(chunk)
			tile_layer.add_child(chunk)   # entering the tree draws it
	_find_changed_chunks()   # note what they're drawing now, so the next change compares against it


## Marks the chunks whose look changed. Most game changes (selecting a tile, trading, training
## troops) leave the map alone, and hashing what each chunk shows costs far less than drawing it.
func _find_changed_chunks() -> void:
	var t0 := Time.get_ticks_usec()
	check_needed = false
	# A new view, a new map, or a different art style (or none) changes every tile
	var art := Sprites.state()
	var everything := Game.view != checked_view or Game.map_version != checked_map or art != checked_art
	checked_view = Game.view
	checked_map = Game.map_version
	if art != checked_art:
		checked_art = art
		# Pixel art needs nearest-neighbour filtering to stay crisp. The text glyphs keep the default.
		tile_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if art > 0 else CanvasItem.TEXTURE_FILTER_PARENT_NODE
		unit_layer.texture_filter = tile_layer.texture_filter
		unit_layer.queue_redraw()
	var standing := {}   # chunk index -> what stands in it
	var on_tiles := _standing_now()
	for c in on_tiles:
		var i: int = (c.y / CHUNK) * chunks_across + c.x / CHUNK
		if not standing.has(i):
			standing[i] = []
		standing[i].append([c, on_tiles[c]])
	for i in chunks.size():
		var sig := _signature(chunks[i], standing.get(i, []))
		if everything or sig != chunks[i].signature:
			chunks[i].signature = sig
			chunks[i].dirty = true
			stale = true
	stats.usec += Time.get_ticks_usec() - t0


## A hash of everything that decides how a chunk looks: what the viewer knows and sees of its
## tiles, plus the ring around it (border lines depend on neighbours), and what stands in it.
## Terrain and contours only change with a new map, which redraws everything anyway.
func _signature(chunk: Chunk, standing: Array) -> int:
	var r := chunk.tiles.grow(1).intersection(Rect2i(0, 0, Game.w, Game.h))
	var parts := [standing, Game.show_radiation]
	for y in range(r.position.y, r.end.y):
		var a := y * Game.w + r.position.x
		if Game.show_radiation:
			parts.append(Game.measured.slice(a, a + r.size.x))
		if Game.view == Data.NONE:
			parts.append(Game.tiles.slice(a, a + r.size.x))
		else:
			parts.append(Game.memory[Game.view].slice(a, a + r.size.x))
			parts.append(Game.sight[Game.view].slice(a, a + r.size.x))
	return hash(parts)


func _mark_all_stale() -> void:
	for chunk in chunks:
		chunk.dirty = true
	stale = true


## A chunk's drawing: every tile it covers. It goes in passes (all backgrounds, then all sprites,
## then all glyphs, then all border lines in one command) because the renderer can only batch runs
## of the same kind of primitive. Interleaving them tile by tile cost about one draw call per
## primitive. Every sprite comes from the one atlas texture, so they batch together too.
func draw_chunk(chunk: Chunk) -> void:
	if not Game.in_game:
		chunk.dirty = true
		return
	var t0 := Time.get_ticks_usec()
	if ground_map != Game.map_version:
		_build_ground()
	var standing := _standing_now()
	# The viewer's memory and sight, fetched once: empty for the no-fog debug view
	var mem: Array = [] if Game.view == Data.NONE else Game.memory[Game.view]
	var seen: PackedByteArray = PackedByteArray() if Game.view == Data.NONE else Game.sight[Game.view]
	var batch := Batch.new()
	batch.rects = Sprites.rects()
	var r := chunk.tiles
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			_draw_tile(chunk, Vector2i(x, y), mem, seen, standing, batch)
	_paint_art(chunk, batch)
	for k in batch.heat_pos.size():
		chunk.draw_rect(Rect2(batch.heat_pos[k], CELL), batch.heat_color[k])
	for g in batch.glyphs:
		if g[3]:
			chunk.draw_set_transform(g[0] + Vector2(0, pipe_ascent * pipe_scale.y), 0.0, pipe_scale)
			chunk.draw_string(font, Vector2.ZERO, g[1], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, g[2])
			chunk.draw_set_transform(Vector2.ZERO)
		else:
			chunk.draw_string(font, g[0] + Vector2(0, CELL.y * 0.8), g[1], HORIZONTAL_ALIGNMENT_CENTER, CELL.x, FONT_SIZE, g[2])
	if not batch.lines.is_empty():
		chunk.draw_multiline_colors(batch.lines, batch.line_colors, 1.0)
	chunk.dirty = false
	stats.tile_draws += 1
	stats.tiles += r.get_area()
	stats.usec += Time.get_ticks_usec() - t0


## The art passes of a batch, in order: ground sprites, the wash over them, the rims, sites, the dark patches under camps, camps and
## buildings. (The chunks draw this, and so does the night's glow layer for the glowing tiles it shows at full brightness.)
func _paint_art(canvas: CanvasItem, batch: Batch) -> void:
	if not batch.sprite_pos.is_empty():
		var atlas := Sprites.atlas_texture()
		for k in batch.sprite_pos.size():
			var at := Rect2(batch.sprite_pos[k], CELL)
			if batch.sprite_flip[k] == 1:
				at = Rect2(at.position, Vector2(-CELL.x, CELL.y))   # a negative width mirrors it, in place
			canvas.draw_texture_rect_region(atlas, at, batch.sprite_src[k], batch.sprite_tint[k])
	for k in batch.shade_pos.size():
		canvas.draw_rect(Rect2(batch.shade_pos[k], CELL), batch.shade_color[k])
	for k in batch.edge_rects.size():
		canvas.draw_rect(batch.edge_rects[k], batch.edge_colors[k])
	if not batch.poi_pos.is_empty():
		var poi_atlas := Sprites.poi_atlas_texture()
		for k in batch.poi_pos.size():
			canvas.draw_texture_rect_region(poi_atlas, Rect2(batch.poi_pos[k], CELL), batch.poi_src[k], batch.poi_tint[k])
	for p in batch.patch_pos:
		canvas.draw_rect(Rect2(p + Vector2(2, 2), CELL - Vector2(4, 4)), PATCH)
	if not batch.top_pos.is_empty():
		var top_atlas := Sprites.atlas_texture()
		for k in batch.top_pos.size():
			canvas.draw_texture_rect_region(top_atlas, Rect2(batch.top_pos[k], CELL), batch.top_src[k], batch.top_tint[k])
	if not batch.bld_pos.is_empty():
		var building_atlas := Sprites.building_atlas_texture()
		for k in batch.bld_pos.size():
			canvas.draw_texture_rect_region(building_atlas, Rect2(batch.bld_pos[k], CELL), batch.bld_src[k], batch.bld_tint[k])


## The color of a route dot once `ratio` of the party's food would be eaten (0 = none, 1 = all of it):
## white to yellow by FOOD_WARN, then yellow to red at 1, and red beyond.
static func food_color(ratio: float) -> Color:
	if ratio >= 1.0:
		return FOOD_OUT
	if ratio <= Data.FOOD_WARN:
		return FOOD_FULL.lerp(FOOD_LOW, ratio / Data.FOOD_WARN)
	return FOOD_LOW.lerp(FOOD_OUT, (ratio - Data.FOOD_WARN) / (1.0 - Data.FOOD_WARN))


## The overlay layer's drawing: routes from your HQ to the selected tile (one dotted line per
## way of travel) or, with a scouting party picked, its own route coloured by its food, then the
## hover and selection boxes.
func draw_overlay(layer: CanvasItem) -> void:
	if not Game.in_game:
		return
	var t0 := Time.get_ticks_usec()
	for mover in Game.preview:
		for p in Game.preview[mover].slice(1):
			if _known(p) != null:
				layer.draw_circle(Vector2(p) * CELL + ROUTE_DOT[mover], 2.0, Data.MOVERS[mover].color)
	_draw_scout_route(layer)
	if Game.in_bounds(hover):
		layer.draw_rect(Rect2(Vector2(hover) * CELL, CELL), Color(1, 0.8, 0.4, 0.35), false, 1.0)
	if Game.in_bounds(Game.selected):
		layer.draw_rect(Rect2(Vector2(Game.selected) * CELL, CELL), SELECT, false, 2.0)
	if not over_panel:
		_draw_hover_label(layer)
	stats.overlay_draws += 1
	stats.usec += Time.get_ticks_usec() - t0


## What the hover label says about tile `c`: what stands on it (if anything), its ground and its height, as far as the viewer
## knows. "Unexplored" for ground the viewer has never seen, and empty off the map.
func hover_text(c: Vector2i) -> String:
	if not Game.in_bounds(c):
		return ""
	var known = _known(c)
	if known == null:
		return "Unexplored"
	var ground: String = Data.TERRAIN[Game.tile(c)["t"]].name
	if known[1] != "":
		ground = "%s on %s" % [Data.BUILDINGS[known[1]].name, ground]
	return "%s, %+d m" % [ground, Game.tile(c)["z"]]


## Where the hover label's top-left corner goes, in screen pixels: below and to the right of the tile, or above and to the left
## of it where that would run off the window (never off the top or left edge).
static func label_position(cell_at: Vector2, cell_size: Vector2, box: Vector2, view: Vector2) -> Vector2:
	var at := cell_at + Vector2(cell_size.x + 6, cell_size.y + 4)
	if at.x + box.x > view.x:
		at.x = cell_at.x - box.x - 6
	if at.y + box.y > view.y:
		at.y = cell_at.y - box.y - 4
	return at.max(Vector2.ZERO)


## The hover label: a small box by the cursor's tile, drawn at a fixed size on screen (so it reads at any zoom) and kept
## inside the window.
func _draw_hover_label(layer: CanvasItem) -> void:
	var text := hover_text(hover)
	if text == "":
		return
	var to_screen := get_canvas_transform()
	var cell_at := to_screen * (Vector2(hover) * CELL)
	var cell_size := CELL * to_screen.get_scale()
	var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT) + Vector2(12, 8)
	var at := label_position(cell_at, cell_size, box, get_viewport_rect().size)
	layer.draw_set_transform_matrix(to_screen.affine_inverse())   # draw in screen pixels
	layer.draw_rect(Rect2(at, box), LABEL_BG)
	layer.draw_rect(Rect2(at, box), LABEL_EDGE, false, 1.0)
	layer.draw_string(font, at + Vector2(6, 4 + font.get_ascent(LABEL_FONT)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, LABEL_TEXT)
	layer.draw_set_transform_matrix(Transform2D.IDENTITY)


## The picked party's route, a dot per tile from where it stands. Unlike the HQ routes it is drawn
## through unexplored ground too, because the point is to see how far the food goes. A ring marks
## the tile where the pack runs out.
func _draw_scout_route(layer: CanvasItem) -> void:
	var route: Dictionary = Game.scout_route
	if route.is_empty():
		return
	var ringed := false
	for i in range(1, route.path.size()):
		var ratio: float = route.ratio[i]
		var at: Vector2 = Vector2(route.path[i]) * CELL
		layer.draw_circle(at + SCOUT_DOT, 2.5, food_color(ratio))
		if ratio >= 1.0 and not ringed:
			ringed = true
			layer.draw_arc(at + CELL * 0.5, CELL.x * 0.5, 0.0, TAU, 20, FOOD_OUT, 1.5)


# ---------------------------------------------------------------- units, and the season replay

func _on_season_played(r: Dictionary) -> void:
	finish_replay()   # one still playing from the last season is over
	_start_fade()     # the light changes with the season, whether or not anything walks
	if SeasonReplay.mode == "off" or not SeasonReplay.has_motion(r):
		return
	_begin_replay(r, SeasonReplay.seconds())


func _on_troops_marched(path: Array, count: int) -> void:
	finish_replay()
	if SeasonReplay.mode == "off":
		return
	_begin_replay(SeasonReplay.march(path, count), SeasonReplay.seconds())


func _begin_replay(r: Dictionary, secs: float) -> void:
	replay = r
	replay_secs = secs
	replay_length = SeasonReplay.length(r, secs)
	replay_season = Game.season
	clock = 0.0
	replay_ids = {}
	for a in r.actors:
		replay_ids[a.id] = true
	_fade = {}
	r.reveals.sort_custom(func(a, b): return a[1] < b[1])
	playing = true
	Game.replaying = true
	_update_fades()
	unit_layer.queue_redraw()


## A map taken out of the tree mid-replay must not leave the game thinking one is still playing.
func _exit_tree() -> void:
	if playing:
		finish_replay()


## Ends the replay (or skips the rest of it): the units stand where the season left them.
func finish_replay() -> void:
	if not playing:
		return
	playing = false
	replay = {}
	replay_ids = {}
	_fade = {}
	Game.replaying = false
	unit_layer.queue_redraw()
	Game.replay_done.emit()


## Which day of the season the replay has got to (-1 when none is playing).
func replay_day() -> float:
	return clock * Data.SEASON_DAYS / replay_secs if playing else -1.0


## Once a frame: runs the replay clock, or, with nothing playing, keeps parked parties bobbing and camp fires flickering.
func _tick_replay(delta: float) -> void:
	if playing:
		clock += delta
		if clock >= replay_length or Game.season != replay_season:
			finish_replay()
			return
		_update_fades(delta)
		unit_layer.queue_redraw()
		return
	if SeasonReplay.mode == "off":
		return
	_idle_accum += delta
	if _idle_accum >= IDLE_REDRAW:
		_idle_accum = 0.0
		if not Units.tribes.is_empty() or Units.units.any(_is_parked):
			unit_layer.queue_redraw()


static func _is_parked(u: Dictionary) -> bool:
	return u.job == "scout" and u.stage == "station"


## Raider bands fade in and out as they cross the edge of what you can see; your own parties are always there.
func _update_fades(delta := 0.0) -> void:
	var day := replay_day()
	for a in replay.actors:
		if Game.view == Data.NONE or a.owner == Game.view:
			continue
		var target := 1.0 if _seen(Vector2i(SeasonReplay.position_at(a.trail, day).round())) else 0.0
		_fade[a.id] = target if not _fade.has(a.id) else move_toward(_fade[a.id], target, delta * BAND_FADE)


## Can the viewer see this tile: in sight now, or (for the player) in sight when the season began?
func _seen(cell: Vector2i) -> bool:
	if not Game.in_bounds(cell):
		return false
	var i := Game.idx(cell)
	if Game.sight[Game.view][i] == 1:
		return true
	return Game.view == Data.PLAYER and i < replay.sight_before.size() and replay.sight_before[i] == 1


## How visible an actor is now: faded by the edge of your sight, and fading away once it has left the map.
func _actor_alpha(a: Dictionary, day: float) -> float:
	var alpha: float = _fade.get(a.id, 1.0)
	if a.gone_day >= 0.0 and day > a.gone_day:
		alpha *= 1.0 - (day - a.gone_day) / SeasonReplay.FADE_DAYS
	return alpha


## The unit layer's drawing: camp fires, then (while a replay plays) the ground still to be uncovered, dust, and every
## unit where its walk has put it, then the flashes; otherwise just the units where they stand.
func draw_units(layer: CanvasItem) -> void:
	if not Game.in_game:
		return
	var t0 := Time.get_ticks_usec()
	var rects := Sprites.rects()
	var art := not rects.is_empty()
	_draw_fires(layer)
	if playing:
		var day := replay_day()
		_draw_fog_lift(layer, day)
		for a in replay.actors:
			_draw_dust(layer, a, day)
		_draw_standing(layer, rects, art, replay_ids)
		for a in replay.actors:
			_draw_actor(layer, a, day, rects, art)
		_draw_pops(layer)
	else:
		_draw_standing(layer, rects, art, {})
	stats.unit_draws += 1
	stats.usec += Time.get_ticks_usec() - t0


## Units that stand where they are (all of them when nothing replays; during a replay only the ones it doesn't know,
## like a party you have just sent out). `skip` holds the ids to leave out.
func _draw_standing(layer: CanvasItem, rects: Dictionary, art: bool, skip: Dictionary) -> void:
	var idle := SeasonReplay.mode != "off"
	var beat := int(Time.get_ticks_msec() / (IDLE_STEP * 1000.0))
	for u in Units.units:
		if skip.has(u.id):
			continue
		var shown := unit_shown(u)
		if shown == Shown.HIDDEN:
			continue
		var hop := HOP if idle and _is_parked(u) and (beat + u.id) % 2 == 0 else 0.0
		var tint := (UNIT_DIM if shown == Shown.DIM else Color.WHITE) * _night_tint(u.get("owner", Data.NONE), u.pos)
		_draw_unit(layer, Units.glyph_kind(u), Vector2(u.pos) * CELL, hop, tint, rects, art)
	for a in Units.animals:   # wild animals: shown only where you can see them, like raider bands
		if not skip.has(a.id) and unit_shown(a) == Shown.SHOWN:
			_draw_unit(layer, a.kind, Vector2(a.pos) * CELL, 0.0, _night_tint(Data.NONE, a.pos), rects, art)
	if Units.frog.get("state", "") == "loose" and not skip.has(Units.FROG_ID) and frog_shown():
		_draw_unit(layer, "frog", Vector2(Units.frog.pos) * CELL, 0.0, _night_tint(Data.NONE, Units.frog.pos), rects, art)


## How a unit that stands where it is shows to the viewer: not at all (on ground they have not explored, or a raider band
## out of their sight), dimmed (their own party, out of their sight right now) or as it is. With no fog everything shows.
func unit_shown(u: Dictionary) -> Shown:
	if Game.view == Data.NONE:
		return Shown.SHOWN
	if not Game.knows_tile(Game.view, u.pos):
		return Shown.HIDDEN
	if Game.in_sight(Game.view, u.pos):
		return Shown.SHOWN
	return Shown.DIM if u.get("owner", Data.NONE) == Game.view else Shown.HIDDEN


func _draw_actor(layer: CanvasItem, a: Dictionary, day: float, rects: Dictionary, art: bool) -> void:
	var alpha := _actor_alpha(a, day)
	if alpha <= 0.0:
		return
	var at: Vector2 = (SeasonReplay.position_at(a.trail, day) * CELL).round()
	var hop := 0.0
	if SeasonReplay.moving_at(a.trail, day):
		hop = HOP if (int(clock * HOP_HZ) + absi(a.id)) % 2 == 0 else 0.0
	elif a.parked:
		hop = HOP if (int(Time.get_ticks_msec() / (IDLE_STEP * 1000.0)) + a.id) % 2 == 0 else 0.0
	var tint := Color(1, 1, 1, alpha) * _night_tint(a.get("owner", Data.NONE), Vector2i((at / CELL).round()))
	_draw_unit(layer, a.kind, at, hop, tint, rects, art)


## Can the viewer see the Giant Frog (any of the four tiles it stands across), while it is loose?
func frog_shown() -> bool:
	if Game.view == Data.NONE:
		return true
	var p: Vector2i = Units.frog.pos
	for c in [p, p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(1, 1)]:
		if Game.in_bounds(c) and Game.in_sight(Game.view, c):
			return true
	return false


## An animal, from its own 16 x 16 picture (the frog across 2 x 2 tiles), or its letter in text mode. No dark patch: the pictures are drawn to stand on the ground.
func _draw_animal(layer: CanvasItem, kind: String, at: Vector2, hop: float, tint: Color, art: bool) -> void:
	var size := CELL * (2.0 if kind == "frog" else 1.0)
	var up := Vector2(0, -hop)
	if art and Sprites.animals_available():
		layer.draw_texture_rect_region(Sprites.animals_texture(), Rect2(at + up, size), Sprites.animal_rect(kind), tint)
		return
	var spec: Dictionary = Data.FROG if kind == "frog" else Data.ANIMALS[kind]
	var shift := Vector2(CELL.x * 0.5, CELL.y * 0.5) if kind == "frog" else Vector2.ZERO
	layer.draw_string(font, at + up + shift + Vector2(0, CELL.y * 0.8), spec.glyph, HORIZONTAL_ALIGNMENT_CENTER, CELL.x, FONT_SIZE, spec.color * tint)


## One unit: the dark patch it stands on and its sprite (or glyph), `hop` pixels up.
func _draw_unit(layer: CanvasItem, kind: String, at: Vector2, hop: float, tint: Color, rects: Dictionary, art: bool) -> void:
	if kind == "frog" or Data.ANIMALS.has(kind):
		_draw_animal(layer, kind, at, hop, tint, art)
		return
	layer.draw_rect(Rect2(at + Vector2(2, 2), CELL - Vector2(4, 4)), Color(PATCH.r, PATCH.g, PATCH.b, PATCH.a * tint.a))
	var up := Vector2(0, -hop)
	if kind == "soldier":
		if art:
			layer.draw_texture_rect(_soldier(), Rect2(at + up, CELL), false, tint)
		else:
			layer.draw_string(font, at + up + Vector2(0, CELL.y * 0.8), "♠", HORIZONTAL_ALIGNMENT_CENTER, CELL.x, FONT_SIZE, SeasonReplay.SOLDIER_COLORS["1"] * tint)
		return
	if art:
		layer.draw_texture_rect_region(Sprites.atlas_texture(), Rect2(at + up, CELL), rects[Sprites.UNITS[kind]], tint)
	else:
		var info: Dictionary = Units.kind_info(kind)
		layer.draw_string(font, at + up + Vector2(0, CELL.y * 0.8), info.glyph, HORIZONTAL_ALIGNMENT_CENTER, CELL.x, FONT_SIZE, info.color * tint)


## The troop marker as a texture (see Sprites.soldier).
func _soldier() -> ImageTexture:
	return Sprites.soldier()


## A few faint dots behind a unit that is walking, where it has just been.
func _draw_dust(layer: CanvasItem, a: Dictionary, day: float) -> void:
	if not DUST.has(a.mover) or not SeasonReplay.moving_at(a.trail, day):
		return
	var alpha := _actor_alpha(a, day)
	if alpha <= 0.0:
		return
	for p in SeasonReplay.recent(a.trail, day, SeasonReplay.DUST_DAYS):
		var cell: Vector2i = p[0]
		var h := absi(hash(cell))
		var at := (Vector2(cell) * CELL + CELL * 0.5 + Vector2(h % 9 - 4, (h / 9) % 9 - 4)).round()
		at = (at / 2.0).floor() * 2.0   # on the art pixel grid
		var c: Color = DUST[a.mover]
		c.a = DUST_ALPHA * (1.0 - p[1] / SeasonReplay.DUST_DAYS) * alpha
		layer.draw_rect(Rect2(at, Vector2(2, 2)), c)


## The tiles your parties uncover after `day` of the replay: they stay dark until then.
func pending_reveals(day: float) -> Array:
	var out := []
	if Game.view != Data.PLAYER:
		return out
	var reveals: Array = replay.get("reveals", [])
	for i in range(reveals.size() - 1, -1, -1):
		if reveals[i][1] <= day:
			break   # sorted by day: the rest were uncovered already
		out.append(reveals[i][0])
	return out


## Ground a party uncovered this season stays dark until it gets there.
func _draw_fog_lift(layer: CanvasItem, day: float) -> void:
	for c in pending_reveals(day):
		layer.draw_rect(Rect2(Vector2(c) * CELL, CELL), FOG)


## Each camp's cooking fire: a spark that flickers between embers (so the map moves even when nothing walks).
func _draw_fires(layer: CanvasItem) -> void:
	if SeasonReplay.mode == "off":
		return
	var step := int(Time.get_ticks_msec() / 140)
	for t in Units.tribes:
		if Game.view != Data.NONE and not Game.knows_tile(Game.view, t.pos):
			continue
		var n := posmod(step + t.id * 5, 4)
		if n == 3:
			continue   # a gap between flickers
		var c: Color = EMBER[n]
		if Game.view != Data.NONE and not Game.in_sight(Game.view, t.pos):
			c = c.darkened(0.5)
		layer.draw_rect(Rect2(Vector2(t.pos) * CELL + Vector2(10, 4 - n % 2 * 2), Vector2(2, 2)), c)


# ---------------------------------------------------------------- day and night (the rules are in daylight.gd)

## The whole map in pixels (what the night layer covers).
func map_pixels() -> Rect2:
	return Rect2(Vector2.ZERO, Vector2(Game.w, Game.h) * CELL)


## Is it any darker than full day?
func is_dark() -> bool:
	return light < 0.999


## Starts the fade to the light the new season has. A season that leaves the light as it was (the switch off) does nothing.
func _start_fade() -> void:
	var target := Daylight.target_light(Game.season)
	if absf(target - light) < 0.001:
		_fade_clock = -1.0
		return
	_light_from = light
	_light_to = target
	_fade_clock = 0.0


## Moves the light along its fade. With no fade running the light simply goes to what the season says (a new game, a loaded
## one, or the Night switch): no fade there.
func _tick_light(delta: float) -> void:
	var target := Daylight.target_light(Game.season)
	var before := light
	if _fade_clock >= 0.0 and absf(target - _light_to) < 0.001:
		_fade_clock += delta
		var k := clampf(_fade_clock / maxf(Daylight.fade_seconds(), 0.01), 0.0, 1.0)
		light = lerpf(_light_from, _light_to, smoothstep(0.0, 1.0, k))
		if k >= 1.0:
			_fade_clock = -1.0
			light = _light_to
	else:
		_fade_clock = -1.0
		light = target
	if light != before:
		unit_layer.queue_redraw()
		halo_layer.queue_redraw()
	if is_dark() and Game.in_game:
		if glow_dirty or glow_art != Sprites.state() or glow_map != Game.map_version:
			_build_glows()
		_halo_accum += delta
		if playing or _fade_clock >= 0.0 or _halo_accum >= HALO_REDRAW:
			_halo_accum = 0.0
			halo_layer.queue_redraw()   # the halos flicker


func _sync_night_layers() -> void:
	var dark := Game.in_game and is_dark()
	night_layer.visible = dark
	glow_layer.visible = dark and Sprites.clean()
	halo_layer.visible = dark
	night_layer.self_modulate = Daylight.ground(light)


## What the night does to something standing on the map that is not the ground. Your own parties keep their colours (and carry a
## small glow: see draw_halos). Wild animals and enemy parties take part of the dimness and never glow, unless they stand in ruins
## that glow, which light them.
func _night_tint(owner: int, cell: Vector2i) -> Color:
	if not is_dark() or owner == Data.PLAYER or glow_lit.has(cell):
		return Color.WHITE
	return Daylight.things(light)


## How strongly the viewer can make out a glowing tile: fully if they see it now, a little if they only remember it, not at all
## if they have never seen it.
func _glow_strength(c: Vector2i) -> float:
	if Game.view == Data.NONE:
		return 1.0
	if not Game.knows_tile(Game.view, c):
		return 0.0
	return 1.0 if Game.in_sight(Game.view, c) else Daylight.REMEMBERED_GLOW


func _sees(c: Vector2i) -> bool:
	return Game.view == Data.NONE or Game.in_sight(Game.view, c)


## Finds, once per map, the tiles that can glow: craters (with a halo), fallout waste and fused glass (their speckles stay bright, no halo),
## and every ruins tile (some are held by raiders).
func _find_glow_ground() -> void:
	_glow_ground_map = Game.map_version
	_glow_ground = []
	_ruin_cells = []
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		match Game.tiles[i]["t"]:
			"crater":
				_glow_ground.append([c, "crater"])
			"glass", "waste":
				_glow_ground.append([c, ""])
			"ruins":
				_ruin_cells.append(c)


## Works out what glows right now: craters, waste and glass the viewer knows of; ruins that raiders hold (once found out) or an enemy party
## stands in; the camps the viewer can see. In the clean look each is also drawn again at full brightness over the night.
func _build_glows() -> void:
	glow_dirty = false
	glow_art = Sprites.state()
	glow_map = Game.map_version
	if _glow_ground_map != Game.map_version:
		_find_glow_ground()
	glow_cells = []
	glow_lit = {}
	glow_batch = Batch.new()
	glow_batch.rects = Sprites.rects()
	var mem: Array = [] if Game.view == Data.NONE else Game.memory[Game.view]
	var seen: PackedByteArray = PackedByteArray() if Game.view == Data.NONE else Game.sight[Game.view]
	var camps := _overlay()
	for g in _glow_ground:
		var strength := _glow_strength(g[0])
		if strength > 0.0:
			_add_glow(g[0], g[1], strength, mem, seen, camps)
	for c in _ruin_cells:
		if Game.tile(c)["r"] == "rogue_seen" and _sees(c):
			_add_glow(c, "ruins", 1.0, mem, seen, camps)
	for u in Units.units:
		if u.get("owner", Data.NONE) != Data.PLAYER and unit_shown(u) == Shown.SHOWN and Game.tile(u.pos)["t"] == "ruins" \
				and not glow_lit.has(u.pos):
			_add_glow(u.pos, "ruins", 1.0, mem, seen, camps)
	for t in Units.tribes:
		if t.found and _sees(t.pos):
			_add_glow(t.pos, t["class"], 1.0, mem, seen, camps)
	glow_layer.queue_redraw()
	halo_layer.queue_redraw()


func _add_glow(c: Vector2i, kind: String, strength: float, mem: Array, seen: PackedByteArray, camps: Dictionary) -> void:
	glow_cells.append([c, kind, strength])
	if kind == "ruins":
		glow_lit[c] = true
	if not Sprites.clean():
		return
	var i := c.y * Game.w + c.x
	var owner: int
	var building: String
	if mem.is_empty():
		owner = Game.tiles[i]["o"]
		building = Game.tiles[i]["b"]
	elif mem[i] == null:
		return
	else:
		owner = mem[i][0]
		building = mem[i][1]
	var out_of_sight := not seen.is_empty() and seen[i] == 0
	_draw_clean(c, i, owner, building, out_of_sight, {c: camps[c]} if camps.has(c) else {}, mem, glow_batch)


func draw_glow_tiles(layer: CanvasItem) -> void:
	_paint_art(layer, glow_batch)


## The edge of what the camera sees, in map pixels.
func _view_rect() -> Rect2:
	var inv := get_canvas_transform().affine_inverse()
	var screen := get_viewport_rect()
	return Rect2(inv * screen.position, Vector2.ZERO).expand(inv * screen.end)


## A soft round light, white in the middle and clear at the edge, made once.
func _halo() -> ImageTexture:
	if _halo_image == null:
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in n:
			for x in n:
				var d := Vector2(x + 0.5 - n / 2.0, y + 0.5 - n / 2.0).length() / (n / 2.0)
				img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.8)))
		_halo_image = ImageTexture.create_from_image(img)
	return _halo_image


## Where your own parties are right now (centres, in map pixels), for their small glow: the replay's positions while it plays.
func _party_spots() -> PackedVector2Array:
	var out := PackedVector2Array()
	var half := CELL * 0.5
	if playing:
		var day := replay_day()
		for a in replay.actors:
			if a.owner == Data.PLAYER and not a.get("wild", false) and _actor_alpha(a, day) > 0.0:
				out.append((SeasonReplay.position_at(a.trail, day) * CELL).round() + half)
	for u in Units.units:
		if u.get("owner", Data.NONE) == Data.PLAYER and not (playing and replay_ids.has(u.id)) and unit_shown(u) != Shown.HIDDEN:
			out.append(Vector2(u.pos) * CELL + half)
	return out


## The halos: a soft glow round every glowing thing (flickering a little) and a small, dim one round each of your own parties.
func draw_halos(layer: CanvasItem) -> void:
	if not Game.in_game or not is_dark():
		return
	var dark := Daylight.darkness(light)
	var seconds := Time.get_ticks_msec() / 1000.0
	var view := _view_rect().grow(CELL.x * 4.0)
	var tex := _halo()
	for g in glow_cells:
		var h := Daylight.halo(g[1])
		if h.is_empty():
			continue
		var centre := (Vector2(g[0]) + Vector2(0.5, 0.5)) * CELL
		if not view.has_point(centre):
			continue
		var r: float = h.radius * CELL.x
		var a: float = h.alpha * dark * g[2] * Daylight.flicker(seconds, g[0].x * 31 + g[0].y)
		layer.draw_texture_rect(tex, Rect2(centre - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(h.color, a))
	var party := Daylight.halo("party")
	var pr: float = party.radius * CELL.x
	for at in _party_spots():
		if view.has_point(at):
			layer.draw_texture_rect(tex, Rect2(at - Vector2(pr, pr), Vector2(pr, pr) * 2.0), false, Color(party.color, party.alpha * dark))


## The flashes showing right now, as [event, how far through it (0 to 1)].
func active_pops() -> Array:
	var out := []
	if not playing or Game.view == Data.AI:
		return out
	var per_day := replay_secs / Data.SEASON_DAYS
	for e in replay.events:
		var age: float = clock - e.day * per_day
		if age >= 0.0 and age < SeasonReplay.POP_SECONDS:
			out.append([e, age / SeasonReplay.POP_SECONDS])
	return out


## Flashes and puffs where things happened, once the walking is done: crossed swords, an exclamation mark at a ruin,
## a gold glint for a party home with loot, a smoke puff where a vehicle gave out.
func _draw_pops(layer: CanvasItem) -> void:
	for p in active_pops():
		var e: Dictionary = p[0]
		var t: float = p[1]
		var o := Vector2(e.cell) * CELL
		var fade := 1.0 - t
		match e.kind:
			"clash":
				layer.draw_line(o + Vector2(3, 3), o + Vector2(13, 13), Color(POP_COLOR, fade), 2.0)
				layer.draw_line(o + Vector2(13, 3), o + Vector2(3, 13), Color(POP_COLOR, fade), 2.0)
				layer.draw_arc(o + CELL * 0.5, 4.0 + 8.0 * t, 0.0, TAU, 16, Color("ff7a3a", fade), 2.0)
			"ruin":
				var y := -12.0 - 6.0 * t
				layer.draw_rect(Rect2(o + Vector2(7, y), Vector2(2, 6)), Color(SELECT, fade))
				layer.draw_rect(Rect2(o + Vector2(7, y + 8), Vector2(2, 2)), Color(SELECT, fade))
			"home":
				for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
					layer.draw_rect(Rect2(o + CELL * 0.5 + dir * (3.0 + 9.0 * t) - Vector2(1, 1), Vector2(2, 2)), Color("ffe066", fade))
			"smoke":
				for i in 3:
					layer.draw_circle(o + Vector2(5 + i * 3, 6.0 - 10.0 * t - i * 3), 2.0 + 3.0 * t + i * 0.6, Color(0.62, 0.6, 0.58, 0.7 * fade))


## Throw away anything cached and redraw the whole map.
func redraw_all() -> void:
	_mark_all_stale()
	overlay_layer.queue_redraw()


## What the current viewer believes is on a tile: [owner, building], or null if never seen.
## Tiles out of sight show what was there last time, so enemy land can change behind the fog.
func _known(c: Vector2i):
	if Game.view == Data.NONE:
		return [Game.tile(c)["o"], Game.tile(c)["b"]]
	return Game.memory[Game.view][Game.idx(c)]


## _overlay(), worked out once per frame however many chunks redraw.
func _standing_now() -> Dictionary:
	if _standing_frame != Engine.get_process_frames():
		_standing_frame = Engine.get_process_frames()
		_standing = _overlay()
	return _standing


## Tribe camps by cell: [glyph, color, sprite]. Camps show on explored tiles. (Units are not here: they are drawn by the
## unit layer, every frame, over the chunks.)
func _overlay() -> Dictionary:
	var out := {}
	for t in Units.tribes:
		if Game.view == Data.NONE or Game.knows_tile(Game.view, t.pos):
			var cls: Dictionary = Data.TRIBE_CLASSES[t.class]
			out[t.pos] = [cls.glyph, cls.color, Sprites.CAMPS[t.class]]
	return out


## The ground glyph and shades of every tile, for the current map.
func _build_ground() -> void:
	ground_map = Game.map_version
	var n := Game.w * Game.h
	ground_glyphs.resize(n)
	ground_colors.resize(n)
	ground_dim.resize(n)
	ground_pipes.resize(n)
	ground_bg.resize(n)
	ground_bg_dim.resize(n)
	ground_sprite.resize(n)
	ground_slope.resize(n)
	ground_shade.resize(n)
	ground_flip.resize(n)
	var z_min := 1000000
	var z_max := -1000000
	var land_z := PackedInt32Array()
	for t in Game.tiles:
		if t["t"] != "water":
			z_min = mini(z_min, t["z"])
			z_max = maxi(z_max, t["z"])
			land_z.append(t["z"])
	# the clean look's three steps hold a third of the land each (a few tall peaks stretch the height range, so equal slices of
	# it would leave almost nothing "high")
	land_z.sort()
	var z_low: int = land_z[land_z.size() / 3] if land_z.size() > 0 else 0
	var z_high: int = land_z[land_z.size() * 2 / 3] if land_z.size() > 0 else 0
	for i in n:
		var terrain_id: String = Game.tiles[i]["t"]
		var contour: String = Game.contours[i]
		var color: Color
		if contour != "" and terrain_id != "water":
			# Height contour: drawn in the terrain's color so you can still tell rock from sand
			ground_glyphs[i] = contour
			color = Data.TERRAIN[terrain_id].color.lightened(0.1)
			ground_pipes[i] = 1
		else:
			# Pick a glyph and shade from a hash of the position so the ground looks varied
			var terrain: Dictionary = Data.TERRAIN[terrain_id]
			var hash_val := absi(i % Game.w * 73856093 ^ i / Game.w * 19349663)
			ground_glyphs[i] = terrain.glyph[hash_val % terrain.glyph.length()]
			color = terrain.color.darkened((hash_val % 5) * 0.07)
			ground_pipes[i] = 0
		ground_sprite[i] = Sprites.TERRAIN[terrain_id]
		ground_slope[i] = Sprites.SLOPES.get(Game.slopes[i], "")   # slopes[i] is "" where no contour runs
		ground_colors[i] = color
		ground_dim[i] = color.darkened(0.6)   # remembered, not currently seen
		var height := inverse_lerp(z_min, z_max, Game.tiles[i]["z"])
		var bg := _ground_bg(terrain_id, height)
		ground_bg[i] = bg
		ground_bg_dim[i] = Color(bg.r * 0.4, bg.g * 0.4, bg.b * 0.4, bg.a)
		# The clean look: three steps of height instead of the smooth wash (water has none), and a mirrored
		# picture on about half the tiles so a wide field of one ground doesn't look like wallpaper
		var z: int = Game.tiles[i]["z"]
		ground_shade[i] = Color(0, 0, 0, 0) if terrain_id == "water" else (SHADE_LOW if z < z_low
			else (SHADE_HIGH if z > z_high else Color(0, 0, 0, 0)))
		ground_flip[i] = 1 if ((i % Game.w) * 73856093 ^ (i / Game.w) * 19349663) & 1 == 1 else 0


## The wash drawn over a tile's background: the terrain's own color (if it has one) with sand
## on top whose opacity grows with height. `height` runs 0 (lowest land) to 1 (highest).
static func _ground_bg(terrain_id: String, height: float) -> Color:
	var base: Color = Data.TERRAIN[terrain_id].get("bg", Color(0, 0, 0, 0))
	if terrain_id == "water":
		return base   # water has no height wash
	var alpha := lerpf(Data.SAND_ALPHA.x, Data.SAND_ALPHA.y, clampf(height, 0.0, 1.0))
	if base.a > 0.0:
		alpha *= Data.SAND_OVER_BG
	else:
		base = Color(Data.SAND, 0.0)
	# Composite sand over the base into one color, so a tile needs just one extra rectangle
	var out_a := alpha + base.a * (1.0 - alpha)
	var rgb := (Vector3(Data.SAND.r, Data.SAND.g, Data.SAND.b) * alpha
		+ Vector3(base.r, base.g, base.b) * base.a * (1.0 - alpha)) / out_a
	return Color(rgb.x, rgb.y, rgb.z, out_a)


## The radiation overlay's tint for tile i: its band's color, only where the viewer has a reading
## (the no-fog debug view shows everything).
func _rad_tint(i: int) -> Color:
	var r := -1
	if Game.view == Data.NONE or (Game.view == Data.PLAYER and Game.measured[i] == 1):
		r = Game.tiles[i]["rad"]
	if r < 0:
		return Color(0, 0, 0, 0)
	return Color(Game.rad_band(r)[1], 0.3 if r < Data.RAD_SAFE else 0.5)


## Who the viewer believes owns tile i, or -1 if they've never seen it. `mem` is the viewer's
## memory, or empty for the no-fog view.
func _owner_at(i: int, mem: Array) -> int:
	if mem.is_empty():
		return Game.tiles[i]["o"]
	return -1 if mem[i] == null else mem[i][0]


## Draws a tile's background now and queues its sprites, glyph and border lines for the later passes.
## `mem` and `seen` are the viewer's memory and sight, both empty for the no-fog view.
func _draw_tile(canvas: CanvasItem, c: Vector2i, mem: Array, seen: PackedByteArray,
		overlay: Dictionary, batch: Batch) -> void:
	var pos := Vector2(c) * CELL
	var w := Game.w
	var i := c.y * w + c.x
	var owner: int
	var building: String
	if mem.is_empty():
		owner = Game.tiles[i]["o"]
		building = Game.tiles[i]["b"]
	elif mem[i] == null:
		canvas.draw_rect(Rect2(pos, CELL), FOG)
		return
	else:
		owner = mem[i][0]
		building = mem[i][1]
	var out_of_sight := not seen.is_empty() and seen[i] == 0
	var pixel_art := not batch.rects.is_empty()
	var clean := pixel_art and Sprites.clean()   # its pictures cover the tile: no background or wash under them
	if not clean:
		canvas.draw_rect(Rect2(pos, CELL), bg_dim[owner] if out_of_sight else OWNER_BG[owner])
		var wash: Color = ground_bg_dim[i] if out_of_sight else ground_bg[i]
		if wash.a > 0.0:
			canvas.draw_rect(Rect2(pos, CELL), wash)
	if Game.show_radiation:
		var heat := _rad_tint(i)
		if heat.a > 0.0:
			if out_of_sight:
				heat = Color(heat.r * 0.5, heat.g * 0.5, heat.b * 0.5, heat.a)
			if pixel_art:
				batch.heat_pos.append(pos)   # over the sprite, which would hide it from underneath
				batch.heat_color.append(heat)
			else:
				canvas.draw_rect(Rect2(pos, CELL), heat)

	var glyph: String
	var color: Color
	var is_pipe := false
	if clean:
		var shown := _draw_clean(c, i, owner, building, out_of_sight, overlay, mem, batch)
		if not shown.is_empty():
			glyph = shown[0]
			color = shown[1]
	elif overlay.has(c):
		# Something is standing here: draw it over the ground, like a creature in Dwarf Fortress
		canvas.draw_rect(Rect2(pos + Vector2(2, 2), CELL - Vector2(4, 4)), Color(0, 0, 0, 0.7))
		if pixel_art:
			batch.add_sprite(pos, overlay[c][2], UNIT_DIM if out_of_sight else Color.WHITE)
		else:
			glyph = overlay[c][0]
			color = overlay[c][1].darkened(0.4 if out_of_sight else 0.0)
	elif building != "" and Data.BUILDINGS[building].has("poi"):
		# A point of interest: each of its four tiles draws its quarter of the 16 x 16 sprite over the ground
		# (in text mode just the top-left tile shows the site's letter)
		var q := Game.poi_quadrant(c)
		var src := Sprites.poi_quadrant_rect(Data.BUILDINGS[building].poi, q) if pixel_art else Rect2()
		if src.size != Vector2.ZERO:
			batch.add_sprite(pos, ground_sprite[i], SPRITE_DIM if out_of_sight else Color.WHITE)
			if ground_slope[i] != "":
				batch.add_sprite(pos, ground_slope[i], SLOPE_DIM if out_of_sight else SLOPE_TINT)
			batch.add_poi(pos, src, SPRITE_DIM if out_of_sight else Color.WHITE)
		elif q == Vector2i.ZERO:
			glyph = Data.BUILDINGS[building].glyph
			color = Data.BUILDINGS[building].color.darkened(0.6 if out_of_sight else 0.0)
		else:
			glyph = ground_glyphs[i]
			color = ground_dim[i] if out_of_sight else ground_colors[i]
			is_pipe = ground_pipes[i] == 1
	elif building != "":
		# No building art yet: they stay text, on the plain ground
		glyph = Data.BUILDINGS[building].glyph
		color = Data.BUILDINGS[building].color
		if out_of_sight:
			color = color.darkened(0.6)
	elif pixel_art:
		var tint := SPRITE_DIM if out_of_sight else Color.WHITE
		batch.add_sprite(pos, ground_sprite[i], tint)
		if ground_slope[i] != "":
			batch.add_sprite(pos, ground_slope[i], SLOPE_DIM if out_of_sight else SLOPE_TINT)
	else:
		glyph = ground_glyphs[i]
		color = ground_dim[i] if out_of_sight else ground_colors[i]
		is_pipe = ground_pipes[i] == 1
	if glyph != "":
		batch.glyphs.append([pos, glyph, color, is_pipe])

	# Territory border lines where (known) ownership changes, and at the map edge
	if owner == Data.NONE:
		return
	var edge: Color = edge_dim[owner] if out_of_sight else OWNER_EDGE[owner]
	if c.y == 0 or _owner_at(i - w, mem) != owner:
		_add_line(batch.lines, batch.line_colors, pos, pos + Vector2(CELL.x, 0), edge)
	if c.y == Game.h - 1 or _owner_at(i + w, mem) != owner:
		_add_line(batch.lines, batch.line_colors, pos + Vector2(0, CELL.y), pos + CELL, edge)
	if c.x == 0 or _owner_at(i - 1, mem) != owner:
		_add_line(batch.lines, batch.line_colors, pos, pos + Vector2(0, CELL.y), edge)
	if c.x == w - 1 or _owner_at(i + 1, mem) != owner:
		_add_line(batch.lines, batch.line_colors, pos + Vector2(CELL.x, 0), pos + CELL, edge)


## One tile in the clean look: the ground picture over the whole tile (mirrored on about half of them), its slope ledge, one wash
## for its height and its owner, then what stands on it. A building with no picture yet comes back as [glyph, color] to
## be written over the ground; anything else comes back empty.
func _draw_clean(c: Vector2i, i: int, owner: int, building: String, out_of_sight: bool, overlay: Dictionary, mem: Array, batch: Batch) -> Array:
	var pos := Vector2(c) * CELL
	var tint := SPRITE_DIM if out_of_sight else Color.WHITE
	batch.add_sprite(pos, ground_sprite[i], tint, ground_flip[i] == 1)
	if ground_slope[i] != "" and not overlay.has(c):
		batch.add_sprite(pos, ground_slope[i], tint)
	var rank: int = RIM_RANK.get(Game.tiles[i]["t"], 0)
	if rank > 0:
		_add_rim(pos, c, rank, mem, batch)
	var wash := ground_shade[i]
	if owner != Data.NONE:
		wash = _wash_over(wash, Color(OWNER_EDGE[owner], OWN_TINT))
	if wash.a > 0.0:
		if out_of_sight:
			wash = Color(wash.r * 0.4, wash.g * 0.4, wash.b * 0.4, wash.a)
		batch.shade_pos.append(pos)
		batch.shade_color.append(wash)
	if overlay.has(c):
		batch.patch_pos.append(pos)
		batch.add_top(pos, overlay[c][2], UNIT_DIM if out_of_sight else Color.WHITE)
	elif building != "" and Data.BUILDINGS[building].has("poi"):
		# each of a site's four tiles draws its quarter of the 16 x 16 picture
		var q := Game.poi_quadrant(c)
		var src := Sprites.poi_quadrant_rect(Data.BUILDINGS[building].poi, q)
		if src.size != Vector2.ZERO:
			batch.add_poi(pos, src, SPRITE_DIM if out_of_sight else Color.WHITE)
		elif q == Vector2i.ZERO:
			return [Data.BUILDINGS[building].glyph, Data.BUILDINGS[building].color.darkened(0.6 if out_of_sight else 0.0)]
	elif building != "":
		var src := Sprites.building_rect(building)
		if src.size != Vector2.ZERO:
			batch.add_building(pos, src, SPRITE_DIM if out_of_sight else Color.WHITE)
		else:
			return [Data.BUILDINGS[building].glyph, Data.BUILDINGS[building].color.darkened(0.6 if out_of_sight else 0.0)]
	return []


## The dark rim along the sides of tile `c` that meet plainer ground the viewer knows about (an unexplored neighbour is
## never peeked at). Vertical rims stop short of the corners that a horizontal rim already covers.
func _add_rim(pos: Vector2, c: Vector2i, rank: int, mem: Array, batch: Batch) -> void:
	var up := _rim_beside(c + Vector2i(0, -1), rank, mem)
	var down := _rim_beside(c + Vector2i(0, 1), rank, mem)
	var left := _rim_beside(c + Vector2i(-1, 0), rank, mem)
	var right := _rim_beside(c + Vector2i(1, 0), rank, mem)
	var top := RIM if up else 0.0
	var side_height := CELL.y - top - (RIM if down else 0.0)
	if up:
		_rim(batch, Rect2(pos, Vector2(CELL.x, RIM)))
	if down:
		_rim(batch, Rect2(pos + Vector2(0, CELL.y - RIM), Vector2(CELL.x, RIM)))
	if left:
		_rim(batch, Rect2(pos + Vector2(0, top), Vector2(RIM, side_height)))
	if right:
		_rim(batch, Rect2(pos + Vector2(CELL.x - RIM, top), Vector2(RIM, side_height)))


func _rim(batch: Batch, r: Rect2) -> void:
	batch.edge_rects.append(r)
	batch.edge_colors.append(RIM_INK)


## True if the tile at `n` is known to the viewer and plainer than a feature of rank `rank`.
func _rim_beside(n: Vector2i, rank: int, mem: Array) -> bool:
	if not Game.in_bounds(n):
		return false
	var j := n.y * Game.w + n.x
	if not mem.is_empty() and mem[j] == null:
		return false
	return RIM_RANK.get(Game.tiles[j]["t"], 0) < rank


## `top` laid over `under`, both with their own opacity, as one color (so a tile needs just one wash rectangle).
static func _wash_over(top: Color, under: Color) -> Color:
	if top.a <= 0.0:
		return under
	var a := top.a + under.a * (1.0 - top.a)
	var rgb := (Vector3(top.r, top.g, top.b) * top.a + Vector3(under.r, under.g, under.b) * under.a * (1.0 - top.a)) / a
	return Color(rgb.x, rgb.y, rgb.z, a)


static func _add_line(lines: PackedVector2Array, colors: PackedColorArray, from: Vector2, to: Vector2, color: Color) -> void:
	lines.append(from)
	lines.append(to)
	colors.append(color)


func _unhandled_input(event: InputEvent) -> void:
	if not Game.in_game:
		return
	if playing and ((event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
			or (event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER])):
		finish_replay()   # a click, Space or Enter skips what is playing
	if event is InputEventMouseMotion:
		var c := Vector2i((get_global_mouse_position() / CELL).floor())
		if c != hover:
			hover = c
			overlay_layer.queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var c := Vector2i((get_global_mouse_position() / CELL).floor())
		if Game.in_bounds(c):
			Game.select(c)
