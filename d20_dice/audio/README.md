# D20 dice sound: plain 8-bit roll

The neutral base sound for the roll animation: no damage, no 20 sparkle. Every roll can use it as is, and later variations can swap individual stems.

Made from pulse waves, a stepped triangle for the thud and NES-style LFSR noise, with 4-bit volume steps. Rendered at 22.05 kHz with 8-bit sample depth, stored in standard 16-bit mono WAV files so any tool opens them.

## Files

| File | Length | What it is |
|---|---|---|
| `dice_roll.wav` | 750 ms | The whole roll in one file. Matches the animation at `playback_speed` 1.0. |
| `stems/roll_start.wav` | 300 ms | Press tick, whoosh and the rattle while the die is in the air |
| `stems/impact_1.wav` | 170 ms | First landing: thud and crack, then three scattered ticks while it bounces |
| `stems/impact_2.wav` | 110 ms | Smaller second landing |
| `stems/settle.wav` | 100 ms | Three fading ticks as the die comes to rest |
| `sfx_timing.json` | | Start time of each stem and which animation frame or signal it belongs to |

Put the stems at these times and they rebuild `dice_roll.wav` exactly:

| Stem | Starts at | Hook in `D20Dice` |
|---|---|---|
| `roll_start` | 0 ms | `roll_started` |
| `impact_1` | 290 ms | `impact(result, 0)` |
| `impact_2` | 460 ms | `impact(result, 1)` |
| `settle` | 530 ms | frame 7 of the roll animation (the script has no signal for it yet) |

## Install

Copy the `audio` folder next to the dice scene so it sits at `res://d20_dice/audio/`. Godot imports the WAVs on its own. Leave Loop off.

## Simplest use

Add an `AudioStreamPlayer` named `RollSound` to the scene that holds your dice, set its Stream to `dice_roll.wav`, and play it when a roll starts:

```gdscript
@onready var dice: D20Dice = $D20Dice
@onready var roll_sound: AudioStreamPlayer = $RollSound

func _ready() -> void:
	dice.roll_started.connect(_on_roll_started)

func _on_roll_started(_result: int) -> void:
	roll_sound.pitch_scale = dice.playback_speed   # keeps it roughly in step if you change the speed
	roll_sound.play()
```

The single file stays in sync only at normal speed. If you change `playback_speed` often, use the stems on their own hooks instead, because each stem then fires on its own frame.

## Damage sounds (chips and cracks on low rolls)

Pieces breaking off the die, in the same 8-bit voice as the plain roll. They are layered on top of it at the moments the animation shows new damage, so a chip you see is a chip you hear. Scratches, grime, rust, soot and blood make no sound.

### The set (`damage/`)

| File | Length | What it is |
|---|---|---|
| `damage/crack_hairline_a.wav` | 57 ms | Thin snapping crack, a high zip with a stutter inside |
| `damage/chip_small_a.wav` | 77 ms | Tiny chip: a bright tink and a few bits skittering off |
| `damage/chip_medium_a.wav` | 126 ms | Chip: crack, a small knock, bits falling |
| `damage/chip_large_a.wav` | 179 ms | A real chunk breaking away, with a low thud under the crack |
| `damage/crack_hairline_b.wav` | 57 ms | Thin snapping crack, a high zip with a stutter inside |
| `damage/chip_small_b.wav` | 77 ms | Tiny chip: a bright tink and a few bits skittering off |
| `damage/chip_medium_b.wav` | 126 ms | Chip: crack, a small knock, bits falling |
| `damage/chip_large_b.wav` | 179 ms | A real chunk breaking away, with a low thud under the crack |
| `damage/skitter.wav` | 121 ms | Loose bits bouncing on the floor after a chip |
| `damage/crumble.wav` | 239 ms | A larger piece falling apart |

Each crack and chip has an `_a` and a `_b` version so two breaks in one roll never sound identical.

### Ready-made rolls (`rolls/`)

`dice_roll_01.wav` to `dice_roll_20.wav` are the plain roll with that result's damage sounds already mixed in. `dice_roll_20.wav` is the plain roll. Play the one for the result:

```gdscript
const ROLL_SOUND := "res://d20_dice/audio/rolls/dice_roll_%02d.wav"

func _on_roll_started(result: int) -> void:
	roll_sound.stream = load(ROLL_SOUND % result)
	roll_sound.pitch_scale = dice.playback_speed
	roll_sound.play()
```

### What breaks when

Times are measured from the click: first landing 290 ms, bounce 380 ms, second landing 460 ms. Sounds that belong to the bounce are placed just before it appears (365 ms).

| Roll | First landing | While it bounces | Second landing |
|---|---|---|---|
| 19 | - | - | - |
| 18 | - | - | crack |
| 17 | - | - | medium chip (upper right), crack |
| 16 | - | crack | medium chip (upper right) |
| 15 | - | crack | medium chip (upper right), crack |
| 14 | - | medium chip (upper right), crack | crack |
| 13 | - | medium chip (upper right), crack | large chip (lower left), crack |
| 12 | - | medium chip (upper right), crack | large chip (lower left), crack |
| 11 | - | medium chip (upper right), crack | large chip (lower left), crack |
| 10 | - | medium chip (upper right), crack | large chip (lower left), large chip (bottom point), crack |
| 9 | crack | medium chip (upper right), crack | large chip (lower left), large chip (bottom point), crack |
| 8 | crack | medium chip (upper right), crack | large chip (lower left), large chip (bottom point), crack |
| 7 | crack | medium chip (upper right), crack | large chip (lower left), debris crumbles, large chip (bottom point), medium chip (upper left), crack |
| 6 | crack | large chip (lower left), medium chip (upper right), crack | large chip (bottom point), medium chip (upper left), crack |
| 5 | crack | large chip (lower left), medium chip (upper right), crack | large chip (bottom point), debris crumbles, medium chip (upper left), crack |
| 4 | crack | large chip (lower left), medium chip (upper right), crack | large chip (bottom point), debris crumbles, medium chip (upper left), crack |
| 3 | crack | large chip (lower left), medium chip (upper right), crack | large chip (bottom point), debris crumbles, medium chip (upper left), crack |
| 2 | medium chip (upper right), crack | large chip (lower left), crack | large chip (bottom point), debris crumbles, medium chip (upper left), crack |
| 1 | medium chip (upper right), crack | large chip (lower left), large chip (bottom point), crack | medium chip (upper left), debris crumbles, crack |
| 20 | - | - | - |

Chips come in three sizes (small, medium, large) to match the size of the piece that breaks off in the sprite. A short skitter follows the chips in each stage (not listed above). When three or more chips break in the same stage, the crumble plays instead of the skitter, and the small chips of that stage fold into it. That happens on rolls 7, 5, 4, 3, 2, 1.

### Playing the cues yourself

`roll_cues.json` lists, for every result, which damage sound plays at which millisecond after the click. Use it when you change `playback_speed` often: divide each time by the speed and the sounds stay on their frames. Apply `mix_scale` too if it is below 1.0.
