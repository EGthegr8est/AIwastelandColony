extends RefCounted
## Shared setup for tests that need a game in progress.

const Data = preload("res://scripts/data.gd")


## Starts a new game from a fixed random seed: the same seed always makes the same map.
static func new_game(seed_value := 1, leader := "builder") -> void:
	seed(seed_value)
	Game.new_game(leader)


## The first tile, row by row, where `pred.call(cell, tile)` is true, or (-1, -1) if none is.
static func find_tile(pred: Callable) -> Vector2i:
	for i in Game.tiles.size():
		var c := Vector2i(i % Game.w, i / Game.w)
		if pred.call(c, Game.tiles[i]):
			return c
	return Vector2i(-1, -1)


## The first free land tile on your border: one you could claim, given the wood.
static func claimable_tile() -> Vector2i:
	return find_tile(func(c, t): return t["o"] == Data.NONE and t["t"] != "water" \
		and Game.borders(c, Data.PLAYER))
