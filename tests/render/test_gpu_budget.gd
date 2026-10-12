extends "res://tests/framework/test_case.gd"
## Budgets for what the GPU gets each frame. Drawing chunks in batched passes took idle frames
## from ~14,000 draw calls to ~600, and these fail if a change breaks that batching again.
## They need a real renderer:  .\tests\run.ps1 -Windowed --filter=gpu_budget

const Data = preload("res://scripts/data.gd")
const World = preload("res://tests/helpers/world.gd")
const MapFixture = preload("res://tests/helpers/map_fixture.gd")

const BUDGET := {1.0: 1200, 0.25: 1500}   # zoom -> most 2D draw calls allowed (about 2x today's)

var fx: MapFixture


func before_all() -> void:
	World.new_game(3)
	Game.reveal(Data.PLAYER, Vector2i(Game.w / 2, Game.h / 2), Game.w)   # everything explored
	Game.view = Data.PLAYER


func before_each() -> void:
	fx = add_autofree(MapFixture.new())


func test_idle_frames_stay_batched() -> void:
	if DisplayServer.get_name() == "headless":
		skip("needs a GPU: run with run.ps1 -Windowed")
		return
	if not ClassDB.class_has_integer_constant("RenderingServer", "VIEWPORT_RENDER_INFO_TYPE_CANVAS"):
		skip("this Godot can't count 2D draw calls")
		return
	var canvas := ClassDB.class_get_integer_constant("RenderingServer", "VIEWPORT_RENDER_INFO_TYPE_CANVAS")
	for zoom in BUDGET:
		await fx.view_cell(Vector2i(Game.w / 2, Game.h / 2), zoom)
		await fx.settle(5)
		var calls := RenderingServer.viewport_get_render_info(fx.viewport.get_viewport_rid(), canvas,
			RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		assert_gt(calls, 0, "zoom %s: the map should draw something" % zoom)
		assert_le(calls, BUDGET[zoom], "zoom %s: 2D draw calls in an idle frame" % zoom)
