extends Control
## A pixel-art Geiger counter: a dial whose needle sits on the radiation reading (on a log scale,
## so the low readings still show), a red lamp that flickers faster the hotter it gets, and the
## reading in R/h under it. The needle trembles a little, like the real thing.

const Data = preload("res://scripts/data.gd")
const PIXEL := 3                    # screen pixels per art pixel
const GRID := Vector2i(56, 36)      # art pixels
const CASE := Color("2a2418")
const CASE_EDGE := Color("9a6a2a")
const SCREEN := Color("0f1a0e")
const NEEDLE := Color("ff6a4a")
const LAMP_OFF := Color("4a1a14")
const LAMP_ON := Color("ff5a3a")
const PIVOT := Vector2i(28, 24)     # where the needle turns, in art pixels
const NEEDLE_LENGTH := 15
const TICKS := 12
const ARC_FROM := 160.0             # degrees: the needle's angle at zero...
const ARC_TO := 20.0                # ...and at the top of the scale

var reading := 0.0                  # R/h, the true level of the tile
var known := true                   # false shows dashes: no reading has been taken
var _shown := 0.0
var _lamp := 0.0                    # seconds the lamp stays lit
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	custom_minimum_size = Vector2(GRID) * PIXEL
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	var target := reading if known else 0.0
	# The needle chases the reading and jitters about it
	var shake := _rng.randf_range(-1.0, 1.0) * (0.04 * target + 0.15)
	_shown = maxf(_shown + (target + shake - _shown) * minf(delta * 9.0, 1.0), 0.0)
	_lamp = maxf(_lamp - delta, 0.0)
	if known and _rng.randf() < minf(2.0 + target * 0.9, 45.0) * delta:
		_lamp = 0.05
	queue_redraw()


## How far along the scale (0..1) a reading is. Logarithmic, so 5 R/h and 100 R/h both show.
static func scale_fraction(r: float) -> float:
	return clampf(log(1.0 + r) / log(1.0 + Data.RAD_MAX), 0.0, 1.0)


static func _angle(f: float) -> float:
	return deg_to_rad(lerpf(ARC_FROM, ARC_TO, f))


func _dot(x: int, y: int, c: Color, size := 1) -> void:
	draw_rect(Rect2(Vector2(x, y) * PIXEL, Vector2(size, size) * PIXEL), c)


func _draw() -> void:
	# The case, with a bevel
	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID) * PIXEL), CASE_EDGE)
	draw_rect(Rect2(Vector2(PIXEL, PIXEL), Vector2(GRID - Vector2i(2, 2)) * PIXEL), CASE)
	draw_rect(Rect2(Vector2(3, 3) * PIXEL, Vector2(GRID.x - 6, 29) * PIXEL), SCREEN)
	# The scale: ticks colored by the radiation band they stand for
	for i in TICKS + 1:
		var f := i / float(TICKS)
		var r_at := exp(f * log(1.0 + Data.RAD_MAX)) - 1.0
		var band_color: Color = Game.rad_band(int(r_at))[1]
		var a := _angle(f)
		for step in [NEEDLE_LENGTH + 1, NEEDLE_LENGTH + 2]:
			_dot(PIVOT.x + roundi(cos(a) * step), PIVOT.y - roundi(sin(a) * step), band_color)
	# The needle, one art pixel at a time
	var needle_angle := _angle(scale_fraction(_shown))
	for step in range(2, NEEDLE_LENGTH):
		_dot(PIVOT.x + roundi(cos(needle_angle) * step), PIVOT.y - roundi(sin(needle_angle) * step), NEEDLE)
	_dot(PIVOT.x - 1, PIVOT.y - 1, CASE_EDGE, 3)
	# The lamp
	_dot(GRID.x - 8, 6, LAMP_ON if _lamp > 0.0 else LAMP_OFF, 3)
	# The reading, in the band's color
	var font := get_theme_default_font()
	var text := "%d R/h" % roundi(reading) if known else "-- R/h"
	var color: Color = Game.rad_band(roundi(reading))[1] if known else CASE_EDGE
	draw_string(font, Vector2(0, 28 * PIXEL + 12), text, HORIZONTAL_ALIGNMENT_CENTER, GRID.x * PIXEL, 15, color)
