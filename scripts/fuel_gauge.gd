extends TextureRect
## Pixel-art fuel gauges, 40 x 32 art pixels each. Every kind of vehicle gets the instrument its
## real-life counterpart would carry, so they read as different at a glance:
##   car    a dashboard gauge: a half dial with E and F at its ends, a red zone near empty, an orange
##          needle, and a little fuel pump that lights up when the tank is low
##   plane  a cockpit instrument: a round steel-bezel dial screwed into a panel, a 270 degree sweep
##          with a red arc near empty, a white needle with a counterweight tail, and a lamp
##   boat   a marine tank gauge: a brass sight tube on a teak board, amber fuel in the glass with a
##          float riding the surface, and the level marked F, 1/2 and E
## Each is drawn straight onto an Image (see image()), so tests can look at the pixels, and shown with
## nearest-neighbour filtering to keep them crisp. When the tank is low the warning light blinks.

const Data = preload("res://scripts/data.gd")
const W := 40
const H := 32
const SHOW_SCALE := 3       # screen pixels per art pixel
const KINDS := ["car", "plane", "boat"]
const BLINK_SECONDS := 0.5

const CLEAR := Color(0, 0, 0, 0)
const CREAM := Color("e8dcc0")
const RED_ON := Color("ff3a2a")
const RED_DIM := Color("7a2218")

# car
const CAR_EDGE := Color("14141a")
const CAR_BODY := Color("3b3b44")
const CAR_SHINE := Color("6a6a78")
const CAR_FACE := Color("0b0b0f")
const CAR_RIVET := Color("a0a0b0")
const CAR_TRACK := Color("8a8070")
const CAR_NEEDLE := Color("ff9a3a")
const CAR_TIP := Color("ffe0a0")
const CAR_HUB := Color("505058")
const PUMP_OFF := Color("6b5030")
const PUMP_ON := Color("ff4a2a")
# plane
const PL_EDGE := Color("0c0e0a")
const PL_BODY := Color("1d2118")
const PL_SHINE := Color("3a4030")
const PL_FACE := Color("07080a")
const SCREW := Color("8a8a7a")
const SCREW_SLOT := Color("3a3a30")
const BEZEL_LIGHT := Color("d8dce0")
const BEZEL_MID := Color("b4b8bc")
const BEZEL_DARK := Color("7e8388")
const BEZEL_LIP := Color("30322e")
const PL_TICK := Color("ecece4")
const PL_LABEL := Color("b8b8a8")
const PL_NEEDLE := Color("f4f4ec")
const PL_TIP := Color("ff6a3a")
const PL_HUB := Color("62666a")
const LAMP_OFF := Color("3a1612")
# boat
const BOARD_A := Color("6b4426")
const BOARD_B := Color("5e3b21")
const BOARD_GRAIN := Color("4a2e18")
const BOARD_EDGE := Color("2a1810")
const BRASS := Color("c89a3c")
const BRASS_HI := Color("f0cc70")
const BRASS_DARK := Color("80601c")
const GLASS := Color("1c2a30")
const GLASS_HI := Color("3a5058")
const FUEL := Color("e8a828")
const FUEL_HI := Color("f8c850")
const SURFACE := Color("fff0a0")
const FLOAT_TOP := Color("f4f0e0")
const FLOAT_RED := Color("d03a2a")

# A 3 x 5 pixel font, just the characters the gauges need
const GLYPHS := {
	"E": ["###", "#..", "##.", "#..", "###"],
	"F": ["###", "#..", "##.", "#..", "#.."],
	"U": ["#.#", "#.#", "#.#", "#.#", "###"],
	"L": ["#..", "#..", "#..", "#..", "###"],
	"1": [".#.", "##.", ".#.", ".#.", "###"],
	"2": ["##.", "..#", ".#.", "#..", "###"],
	"/": ["..#", "..#", ".#.", "#..", "#.."],
}
# A little gas pump, 7 x 7: the body with its window, and the hose hanging off the side
const PUMP := [
	".####..",
	".#..#.#",
	".#..#.#",
	".####.#",
	".####.#",
	".####..",
	"######.",
]

var kind := "car"
var fraction := 1.0
var low := false
var _lit := true
var _clock := 0.0


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	custom_minimum_size = Vector2(W, H) * SHOW_SCALE
	set_process(false)


## Shows `level` (0 empty .. 1 full) on the gauge for `vehicle` ("car", "plane" or "boat"). A low
## tank blinks the warning light.
func setup(vehicle: String, level: float, is_low: bool) -> void:
	kind = vehicle
	fraction = clampf(level, 0.0, 1.0)
	low = is_low
	_lit = true
	_clock = 0.0
	set_process(low)
	_refresh()


func _process(delta: float) -> void:
	_clock += delta
	var on := int(_clock / BLINK_SECONDS) % 2 == 0
	if on != _lit:
		_lit = on
		_refresh()


func _refresh() -> void:
	texture = ImageTexture.create_from_image(image(kind, fraction, low and _lit))


## The gauge for `kind` with the tank `fraction` full (0..1). `warn` lights the warning light.
static func image(kind_name: String, level: float, warn := false) -> Image:
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var f := clampf(level, 0.0, 1.0)
	match kind_name:
		"plane":
			_plane(img, f, warn)
		"boat":
			_boat(img, f, warn)
		_:
			_car(img, f, warn)
	return img


# ---------------------------------------------------------------- the car: a dashboard half dial

## Degrees: the needle points at 165 (left, E) when empty and 15 (right, F) when full.
static func _car_angle(f: float) -> float:
	return lerpf(165.0, 15.0, f)


static func _car(img: Image, f: float, warn: bool) -> void:
	_rect(img, 0, 0, W, H, CAR_EDGE)
	_rect(img, 1, 1, W - 2, H - 2, CAR_BODY)
	_rect(img, 2, 1, W - 4, 1, CAR_SHINE)
	_rect(img, 1, 2, 1, H - 4, CAR_SHINE)
	for c in [Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1)]:
		_px(img, c.x, c.y, CLEAR)
	_rect(img, 5, 5, 30, 22, CAR_FACE)
	for c in [Vector2i(5, 5), Vector2i(34, 5), Vector2i(5, 26), Vector2i(34, 26)]:
		_px(img, c.x, c.y, CAR_BODY)
	for c in [Vector2i(3, 3), Vector2i(36, 3), Vector2i(3, 28), Vector2i(36, 28)]:
		_px(img, c.x, c.y, CAR_RIVET)
	var pivot := Vector2i(20, 23)
	# The scale: an arc track from E to F, red over the last of the tank, with a tick at empty,
	# quarter, half, three quarters and full stepping in from it
	var deg := _car_angle(0.0)
	while deg >= _car_angle(1.0):
		_ray(img, pivot, deg, 14.0, 14.0, RED_ON if deg >= _car_angle(Data.FUEL_LOW) else CAR_TRACK)
		deg -= 2.0
	for i in 5:
		_ray(img, pivot, _car_angle(i / 4.0), 10.0 if i % 2 == 0 else 12.0, 14.0, RED_ON if i == 0 else CREAM)
	_text(img, "E", 7, 21, CREAM)
	_text(img, "F", 30, 21, CREAM)
	_bitmap(img, PUMP, 17, 13, PUMP_ON if warn else PUMP_OFF)
	_ray(img, pivot, _car_angle(f), 1.0, 12.0, CAR_NEEDLE)
	_ray(img, pivot, _car_angle(f), 11.0, 12.0, CAR_TIP)
	_rect(img, pivot.x - 1, pivot.y - 1, 3, 3, CAR_HUB)
	_px(img, pivot.x, pivot.y, CAR_RIVET)


# ---------------------------------------------------------------- the plane: a round cockpit dial

## Degrees: a 270 degree sweep from lower left (empty) over the top to lower right (full).
static func _plane_angle(f: float) -> float:
	return 225.0 - 270.0 * f


static func _plane(img: Image, f: float, warn: bool) -> void:
	_rect(img, 0, 0, W, H, PL_EDGE)
	_rect(img, 1, 1, W - 2, H - 2, PL_BODY)
	_rect(img, 2, 1, W - 4, 1, PL_SHINE)
	_rect(img, 1, 2, 1, H - 4, PL_SHINE)
	for c in [Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1)]:
		_px(img, c.x, c.y, CLEAR)
	for c in [Vector2i(2, 2), Vector2i(36, 2), Vector2i(2, 28), Vector2i(36, 28)]:
		_rect(img, c.x, c.y, 2, 2, SCREW)
		_px(img, c.x, c.y, SCREW_SLOT)
	var pivot := Vector2i(20, 16)
	# The bezel, lit from the upper left, around a black face
	for y in H:
		for x in W:
			var dx := x - pivot.x
			var dy := y - pivot.y
			var d := sqrt(float(dx * dx + dy * dy))
			if d > 14.5:
				continue
			if d > 12.5:
				var shade := dx + dy
				var c := BEZEL_LIGHT if shade < -6 else (BEZEL_DARK if shade > 6 else BEZEL_MID)
				_px(img, x, y, BEZEL_LIP if d <= 13.4 else c)
			else:
				_px(img, x, y, PL_FACE)
	# The scale: ticks every eighth, long ones at empty, half and full, and a red arc near empty
	for i in 9:
		_ray(img, pivot, _plane_angle(i / 8.0), 8.0 if i % 4 == 0 else 10.0, 12.0, PL_TICK)
	var deg := _plane_angle(0.0)
	while deg >= _plane_angle(Data.FUEL_LOW):
		_ray(img, pivot, deg, 10.0, 11.0, RED_ON if warn else RED_DIM)
		deg -= 3.0
	_text(img, "FUEL", 13, 10, PL_LABEL)
	_text(img, "E", 15, 22, PL_TICK)
	_text(img, "F", 23, 22, PL_TICK)
	_rect(img, 18, 24, 4, 2, RED_ON if warn else LAMP_OFF)
	# The needle, with a short tail behind the pivot
	var a := _plane_angle(f)
	_ray(img, pivot, a, -3.0, 10.0, PL_NEEDLE)
	_ray(img, pivot, a, 8.0, 10.0, PL_TIP)
	_rect(img, pivot.x - 1, pivot.y - 1, 3, 3, PL_HUB)
	_px(img, pivot.x, pivot.y, BEZEL_LIGHT)


# ---------------------------------------------------------------- the boat: a brass sight tube

## The row of the fuel's surface in the glass tube: 25 (the bottom) when empty, 6 (the top) when full.
static func _boat_level(f: float) -> int:
	return 25 - roundi(f * 19.0)


static func _boat(img: Image, f: float, warn: bool) -> void:
	# The teak board, with its grain
	for y in H:
		for x in W:
			var plank := BOARD_A if ((y >> 1) & 1) == 0 else BOARD_B
			if (x * 7 + y * 13) % 11 == 0:
				plank = BOARD_GRAIN
			_px(img, x, y, plank)
	_rect(img, 0, 0, W, 1, BOARD_EDGE)
	_rect(img, 0, H - 1, W, 1, BOARD_EDGE)
	_rect(img, 0, 0, 1, H, BOARD_EDGE)
	_rect(img, W - 1, 0, 1, H, BOARD_EDGE)
	for c in [Vector2i(0, 0), Vector2i(W - 1, 0), Vector2i(0, H - 1), Vector2i(W - 1, H - 1)]:
		_px(img, c.x, c.y, CLEAR)
	for c in [Vector2i(3, 3), Vector2i(35, 3), Vector2i(3, 27), Vector2i(35, 27)]:
		_rect(img, c.x, c.y, 2, 2, BRASS)
		_px(img, c.x + 1, c.y + 1, BRASS_DARK)
	# The brass fittings and the glass between them
	_rect(img, 15, 2, 10, 3, BRASS)
	_rect(img, 15, 27, 10, 3, BRASS)
	_rect(img, 16, 5, 8, 22, BRASS)
	_rect(img, 15, 2, 10, 1, BRASS_HI)
	_rect(img, 15, 29, 10, 1, BRASS_DARK)
	_rect(img, 16, 5, 1, 22, BRASS_HI)
	_rect(img, 23, 5, 1, 22, BRASS_DARK)
	_rect(img, 18, 6, 4, 20, GLASS)
	_rect(img, 18, 6, 1, 20, GLASS_HI)
	# The fuel and the float on top of it
	var level := _boat_level(f)
	if f > 0.0:
		_rect(img, 18, level, 4, 26 - level, FUEL)
		_rect(img, 18, level, 1, 26 - level, FUEL_HI)
		_rect(img, 18, level, 4, 1, SURFACE)
	var bob := maxi(level - 1, 6)
	_rect(img, 18, bob, 4, 1, FLOAT_TOP)
	_rect(img, 18, bob + 1, 4, 1, FLOAT_RED)
	# The scale beside the tube: ticks at each quarter, a red band over the last of the tank
	for i in 5:
		_rect(img, 25, _boat_level(i / 4.0), 4 if i % 2 == 0 else 3, 1, RED_ON if i == 0 else CREAM)
	var band_top := _boat_level(Data.FUEL_LOW)
	_rect(img, 29, band_top, 1, 26 - band_top, RED_ON if warn else RED_DIM)
	_text(img, "F", 8, 4, CREAM)
	_text(img, "1/2", 3, 13, CREAM)
	_text(img, "E", 8, 23, CREAM)


# ---------------------------------------------------------------- pixel helpers

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	if x >= 0 and y >= 0 and x < W and y < H:
		img.set_pixel(x, y, c)


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(y, y + h):
		for xx in range(x, x + w):
			_px(img, xx, yy, c)


## A line of pixels leaving `from` at `degrees` (0 = right, 90 = up), between two distances.
static func _ray(img: Image, from: Vector2i, degrees: float, from_r: float, to_r: float, c: Color) -> void:
	var a := deg_to_rad(degrees)
	var r := from_r
	while r <= to_r + 0.001:
		_px(img, roundi(from.x + cos(a) * r), roundi(from.y - sin(a) * r), c)
		r += 0.5


## Rows of "#" and "." drawn with `c` where there's a "#".
static func _bitmap(img: Image, rows: Array, x: int, y: int, c: Color) -> void:
	for row in rows.size():
		for col in rows[row].length():
			if rows[row][col] == "#":
				_px(img, x + col, y + row, c)


static func _text(img: Image, text: String, x: int, y: int, c: Color) -> void:
	for ch in text:
		_bitmap(img, GLYPHS[ch], x, y, c)
		x += 4
