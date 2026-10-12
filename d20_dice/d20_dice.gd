class_name D20Dice
extends Control
## Clickable pixel-art D20 that plays ROLL -> tumble -> landing for any result from 1 to 20.
##
## Quick use:
##   $D20Dice.roll(14)                      # plays the animation that lands on 14
##   $D20Dice.roll_finished.connect(...)    # the result is on screen, resolve your action here
##   $D20Dice.clicked.connect(...)          # the player clicked the die: pick a result, then call roll()

## The player clicked the die. Fires on every click, whether or not it is rolling.
signal clicked
## A roll animation just started.
signal roll_started(result: int)
## The die hit the ground. bounce is 0 for the first landing and 1 for the second. Hook sound effects here.
signal impact(result: int, bounce: int)
## The die has settled and the result is showing.
signal roll_finished(result: int)

## Clicking the idle die rolls a random result. Leave this off when your game decides the result.
@export var auto_roll_on_click: bool = false
## 1.0 is the designed speed (about 0.75 seconds from click to settled).
@export_range(0.25, 3.0, 0.05) var playback_speed: float = 1.0
## Seconds to keep the result on screen before returning to ROLL. 0 keeps it until reset_to_idle() is called.
@export var return_to_idle_after: float = 0.0

# Every roll_N animation has the same 9 frames:
# 0 press, 1 launch, 2 peak, 3 fall, 4 land, 5 bounce, 6 land again, 7 settle, 8 final
const FRAME_LAND := 4
const FRAME_LAND_AGAIN := 6

# Generated from the atlas. Only used when the Sprite node has no SpriteFrames assigned.
const FRAME_SIZE := Vector2i(64, 80)
const ATLAS_COLUMNS := 16
const IDLE_FRAME := 0
const FRAME_SECONDS := [0.7, 0.7, 0.8, 0.7, 0.9, 0.8, 0.7, 1.1, 1.0]
const ROLL_FRAMES := {
	1: [1, 2, 3, 4, 5, 6, 7, 8, 9],
	2: [1, 10, 11, 12, 13, 14, 15, 16, 16],
	3: [1, 17, 18, 19, 20, 21, 22, 23, 23],
	4: [1, 24, 25, 19, 26, 27, 28, 29, 29],
	5: [1, 10, 30, 31, 32, 33, 34, 35, 35],
	6: [1, 36, 37, 38, 39, 40, 41, 42, 42],
	7: [1, 43, 11, 44, 45, 46, 47, 48, 48],
	8: [1, 49, 18, 4, 50, 51, 52, 53, 53],
	9: [1, 49, 54, 31, 55, 56, 57, 58, 58],
	10: [1, 43, 37, 59, 60, 61, 62, 63, 63],
	11: [1, 24, 64, 65, 66, 67, 68, 69, 69],
	12: [1, 70, 71, 72, 73, 74, 75, 76, 76],
	13: [1, 43, 64, 72, 77, 78, 79, 80, 80],
	14: [1, 10, 30, 12, 81, 82, 83, 84, 84],
	15: [1, 85, 54, 12, 86, 87, 88, 89, 89],
	16: [1, 90, 11, 91, 92, 93, 94, 95, 96],
	17: [1, 17, 97, 4, 98, 99, 100, 101, 102],
	18: [1, 43, 103, 4, 104, 105, 106, 107, 108],
	19: [1, 109, 11, 110, 111, 112, 113, 114, 115],
	20: [1, 2, 3, 4, 116, 117, 118, 119, 120]
}

@onready var sprite: AnimatedSprite2D = $Sprite

var _rolling := false
var _result := 0
var _return_timer: SceneTreeTimer = null


func _ready() -> void:
	if sprite.sprite_frames == null:
		sprite.sprite_frames = _build_frames()
	sprite.speed_scale = playback_speed
	sprite.frame_changed.connect(_on_frame_changed)
	sprite.animation_finished.connect(_on_animation_finished)
	sprite.play(&"idle")


## Play the animation that lands on result (1-20). Returns false if a roll is already playing.
func roll(result: int) -> bool:
	if _rolling:
		return false
	result = clampi(result, 1, 20)
	var anim := StringName("roll_%d" % result)
	if not sprite.sprite_frames.has_animation(anim):
		push_error("D20Dice: animation %s is missing from the SpriteFrames." % anim)
		return false
	_rolling = true
	_result = result
	_return_timer = null
	sprite.speed_scale = playback_speed
	sprite.play(anim)
	roll_started.emit(result)
	return true


## Roll a random 1-20 and return it. Returns 0 if a roll is already playing.
func roll_random() -> int:
	if _rolling:
		return 0
	var result := randi_range(1, 20)
	roll(result)
	return result


## Jump straight to the finished die for a result, with no animation (for example when loading a save).
func show_result(result: int) -> void:
	result = clampi(result, 1, 20)
	_rolling = false
	_return_timer = null
	_result = result
	sprite.play(StringName("roll_%d" % result))
	sprite.stop()
	sprite.frame = sprite.sprite_frames.get_frame_count(sprite.animation) - 1


## Back to the ROLL face.
func reset_to_idle() -> void:
	_rolling = false
	_return_timer = null
	sprite.play(&"idle")


func is_rolling() -> bool:
	return _rolling


func get_result() -> int:
	return _result


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		clicked.emit()
		if auto_roll_on_click and not _rolling:
			roll(randi_range(1, 20))


func _on_frame_changed() -> void:
	if not _rolling:
		return
	match sprite.frame:
		FRAME_LAND:
			impact.emit(_result, 0)
		FRAME_LAND_AGAIN:
			impact.emit(_result, 1)


func _on_animation_finished() -> void:
	if not _rolling:
		return
	_rolling = false
	roll_finished.emit(_result)
	if return_to_idle_after > 0.0 and is_inside_tree():
		var timer := get_tree().create_timer(return_to_idle_after)
		_return_timer = timer
		await timer.timeout
		if _return_timer == timer and not _rolling:
			reset_to_idle()


func _build_frames() -> SpriteFrames:
	var dir: String = (get_script() as Script).resource_path.get_base_dir()
	var atlas: Texture2D = load(dir.path_join("d20_atlas.png"))
	var frames := SpriteFrames.new()
	frames.remove_animation(&"default")
	frames.add_animation(&"idle")
	frames.set_animation_loop(&"idle", true)
	frames.set_animation_speed(&"idle", 10.0)
	frames.add_frame(&"idle", _atlas_frame(atlas, IDLE_FRAME))
	for n in range(1, 21):
		var anim := StringName("roll_%d" % n)
		frames.add_animation(anim)
		frames.set_animation_loop(anim, false)
		frames.set_animation_speed(anim, 10.0)
		var indices: Array = ROLL_FRAMES[n]
		for i in indices.size():
			frames.add_frame(anim, _atlas_frame(atlas, indices[i]), FRAME_SECONDS[i])
	return frames


func _atlas_frame(atlas: Texture2D, index: int) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = atlas
	tex.region = Rect2(
		(index % ATLAS_COLUMNS) * FRAME_SIZE.x,
		floori(index / float(ATLAS_COLUMNS)) * FRAME_SIZE.y,
		FRAME_SIZE.x,
		FRAME_SIZE.y)
	return tex
