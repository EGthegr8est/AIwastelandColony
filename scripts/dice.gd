extends RefCounted
## The dice. Everything in the d20 system rolls through one of these, so a test can hand it a ForcedDice
## (tests/helpers/forced_dice.gd) and choose every number. This one uses the game's own random numbers, so a
## seeded game rolls the same dice every time.


## One d20: 1 to 20.
func d20() -> int:
	return randi_range(1, 20)


## A dice string such as "2d6" or "d20": the total of that many rolls.
func roll(spec: String) -> int:
	var parsed := parse(spec)
	if parsed.x <= 0:
		push_error("Dice: can't read '%s'" % spec)
		return 0
	var total := 0
	for i in parsed.x:
		total += randi_range(1, parsed.y)
	return total


## "2d6" is Vector2i(2, 6) (two dice of six sides). "d20" is (1, 20). Anything unreadable is (0, 0).
static func parse(spec: String) -> Vector2i:
	var parts := spec.strip_edges().to_lower().split("d")
	if parts.size() != 2 or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var count := 1 if parts[0] == "" else (int(parts[0]) if parts[0].is_valid_int() else 0)
	var sides := int(parts[1])
	if count <= 0 or sides <= 0:
		return Vector2i.ZERO
	return Vector2i(count, sides)
