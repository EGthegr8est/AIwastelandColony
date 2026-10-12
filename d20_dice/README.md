# D20 Dice for Godot 4

Pixel-art D20 with a click-to-roll animation for every result from 1 to 20.
The die idles on **ROLL**, tumbles when rolled, and lands on the number. The lower the roll, the more chipped, cracked, rusted and dirty the die ends up. A 20 is pristine and a 1 is the worst case.

Written for Godot 4.2 or newer.

## What's in the folder

| File | What it is |
|---|---|
| `d20_atlas.png` | All frames in one sheet (121 unique frames, 64 x 80 px each, 16 columns, 1024 x 640 px) |
| `d20_sprite_frames.tres` | SpriteFrames with the `idle` animation and `roll_1` to `roll_20` |
| `D20Dice.tscn` | Ready-to-use scene: a clickable Control with an AnimatedSprite2D inside |
| `d20_dice.gd` | The script on that scene (`class_name D20Dice`) |
| `d20_demo.tscn` / `d20_demo.gd` | Test bench: click the die, or press 1 to 20 to force a result |
| `d20_frames.json` | Frame layout data, for tools outside Godot |
| `previews/` | A GIF of every roll and an overview of all 20 results (ignored by Godot) |
| `source_frames/` | Every frame as its own PNG (ignored by Godot) |

## Install

1. Copy the `d20_dice` folder into your project so it sits at `res://d20_dice/`.
   The scene and SpriteFrames point at that path. If you put it somewhere else, open `D20Dice.tscn` and reassign the script and sprite frames, or delete the SpriteFrames from the `Sprite` node and the script will build them from the atlas on its own.
2. Keep pixel art sharp: **Project Settings > Rendering > Textures > Default Texture Filter = Nearest**.
   The dice scene already sets its own filter to Nearest, so it stays crisp even if you skip this.
3. Run `res://d20_dice/d20_demo.tscn` (Scene > Run Specific Scene) to see all 20 animations.

## Use it in your game

Drop `D20Dice.tscn` into any scene, then:

```gdscript
@onready var dice: D20Dice = $D20Dice

func _ready() -> void:
	dice.roll_finished.connect(_on_roll_finished)

func attempt_action() -> void:
	var result := randi_range(1, 20)   # or your own dice logic
	dice.roll(result)                  # plays the animation that lands on `result`

func _on_roll_finished(result: int) -> void:
	# the result is on screen, apply the outcome here
	print("rolled ", result)
```

If you want the player to click the die to roll it:

```gdscript
dice.clicked.connect(func(): dice.roll(randi_range(1, 20)))
```

or simply tick **Auto Roll On Click** on the node for a random roll per click.

### API

| Member | Description |
|---|---|
| `roll(result: int) -> bool` | Play the animation for `result` (1 to 20). Returns `false` if a roll is already playing. |
| `roll_random() -> int` | Roll a random result and return it (0 if busy). |
| `show_result(result: int)` | Jump straight to the finished die, no animation. Handy when loading a save. |
| `reset_to_idle()` | Back to the ROLL face. |
| `is_rolling()` / `get_result()` | Current state. |
| signal `clicked` | Player clicked the die. |
| signal `roll_started(result)` | Animation began. |
| signal `impact(result, bounce)` | Die hit the ground. `bounce` is 0 for the first landing and 1 for the second. Use these for sound effects. |
| signal `roll_finished(result)` | Result is showing. |
| `playback_speed` | 1.0 is the designed speed (about 0.75 s). |
| `return_to_idle_after` | Seconds before the die returns to ROLL. 0 keeps the result until you call `reset_to_idle()`. |
| `auto_roll_on_click` | Click rolls a random result. |

### Using the SpriteFrames directly

`d20_sprite_frames.tres` works on any AnimatedSprite2D. Animations: `idle` (the ROLL face) and `roll_1` to `roll_20`. Each roll animation has 9 frames and does not loop:

`0 press, 1 launch, 2 peak, 3 fall, 4 land, 5 bounce, 6 land again, 7 settle, 8 final`

Animation speed is 10 FPS with per-frame durations (70, 70, 80, 70, 90, 80, 70, 110 ms, then a hold on the last frame).

## The damage ladder

Each step adds to the one before it, so a 6 always looks like a 7 plus one more problem.

| Roll | What shows |
|---|---|
| 20 | Pristine, sparkles |
| 19 | Light scratches, small sparkle |
| 18 | + hairline crack across the top |
| 17 | + first small chip (upper right), one sparkle |
| 16 | + dark scratches |
| 15 | + crack on the right |
| 14 | + grime. Dust clouds turn from tan to dirty brown |
| 13 | + chipped lower left corner |
| 12 | + crack on the left |
| 11 | + rust streaks |
| 10 | + chipped bottom point |
| 9 | + crack along the bottom |
| 8 | + heavier grime |
| 7 | + chipped upper left corner |
| 6 | + another long crack |
| 5 | + chipped top point |
| 4 | + crack across the upper left. Smoke starts rising |
| 3 | + faded, dulled paint. The number starts to wear |
| 2 | + chipped lower right corner. More wear on the number |
| 1 | Worst case: soot, dried blood, speckled dirt, heavy smoke. Every chunk it lost lies on the ground |

Chipped pieces appear on the ground as small orange shards, one more for each chip.

## Sizing

- Frames are 64 x 80 px. The die itself is about 37 x 46 px, and the extra height leaves room for the hop.
- Scale it by whole numbers only (2x, 3x, 4x) or the pixels will look uneven. The demo uses 4x.
- The `Sprite` node is centered at (32, 40) inside the 64 x 80 Control. The shadow sits near the bottom of the frame, so line the bottom edge of the Control up with your ground.
- The whole sheet is `d20_atlas.png`. If you re-import it, leave Filter off and Mipmaps off.

## Troubleshooting

- **Blurry die:** set the default texture filter to Nearest (see Install step 2) and scale by whole numbers.
- **`Cannot open file` / missing resource errors:** the folder is not at `res://d20_dice/`. Move it there, or see Install step 1.
- **Exported build is missing the die:** the atlas and `.tres` are normal resources and export by default. Make sure `previews/` and `source_frames/` are not needed; they are ignored on purpose.
- **Clicks do nothing:** the die is a Control, so something above it with a Mouse Filter of Stop will swallow the click.
