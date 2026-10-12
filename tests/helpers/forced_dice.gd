extends "res://scripts/dice.gd"
## Dice that roll exactly what a test says. `d20_values` are handed out, in order, to every d20() call and
## `totals` to every roll("2d6") call (as the whole total). Asking for more than were given is an error, so a
## test fails if the game rolls a die it didn't expect.

var d20_values: Array = []
var totals: Array = []
var d20_calls := 0


func _init(d20_list: Array = [], total_list: Array = []) -> void:
	d20_values = d20_list.duplicate()
	totals = total_list.duplicate()


func d20() -> int:
	d20_calls += 1
	if d20_values.is_empty():
		push_error("ForcedDice: ran out of d20 values")
		return 10
	return d20_values.pop_front()


func roll(spec: String) -> int:
	if totals.is_empty():
		push_error("ForcedDice: ran out of totals for %s" % spec)
		return 0
	return totals.pop_front()
