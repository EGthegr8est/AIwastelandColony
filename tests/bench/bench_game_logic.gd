extends "res://tests/framework/bench_case.gd"
## What the simulation costs, apart from drawing: a season turn, the whole-map scans many functions do, the raid and leader
## code, saving and loading, and building the leader screens. Run it with
##     .\tests\run.ps1 --bench --save=NAME      (the screens need -Windowed)      and later      --compare=NAME
## Small operations are timed 100 or 1,000 at a time, so the number is the cost of that many calls.

const Data = preload("res://scripts/data.gd")
const Leaders = preload("res://scripts/leaders.gd")
const World = preload("res://tests/helpers/world.gd")

var hq: Vector2i


func before_all() -> void:
	World.new_game(3)
	hq = Game.home(Data.PLAYER)
	Game.ai["truce"] = 999999   # no raid ends the run
	# Mid-game: the map explored, a built-up colony, prisoners and a Rust Kings with plenty of walls
	Game.reveal(Data.PLAYER, Vector2i(Game.w / 2, Game.h / 2), Game.w)
	var ids := ["farm", "lodge", "mine", "outpost", "wall", "tower", "market", "refinery"]
	var n := 0
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water" and n < 36:
			Game.tile(c)["b"] = ids[n % ids.size()]
			n += 1
	Game.ai["walls"] = 60
	Game.prisoners = 8
	for i in 25:
		_feed()
		Game.end_season()


## Stops the colony starving or being raided into the ground while it is measured.
func _feed() -> void:
	for r in ["grain", "veg", "meat", "wood", "stone", "metal", "gold", "fuel"]:
		Game.res[r] = 5000
	Game.pop = mini(Game.pop, 40)
	Game.ai["truce"] = 999999
	Game.ending = {}


func bench_end_season() -> void:
	await measure("end season (mid-game)", func():
		_feed()
		Game.end_season(), 30, 3)


func bench_new_game_and_map_generation() -> void:
	var samples: Array[float] = []
	for i in 5:
		var t0 := Time.get_ticks_usec()
		World.new_game(10 + i)
		samples.append(Time.get_ticks_usec() - t0)
	record_samples("new game (generates the map)", samples, "us")
	World.new_game(3)   # the mid-game colony is gone: later benchmarks run on a fresh one with the buildings put back
	hq = Game.home(Data.PLAYER)
	Game.ai["walls"] = 60
	Game._sync_ai_walls()
	var n := 0
	for c in Game.owned(Data.PLAYER):
		if Game.tile(c)["b"] == "" and Game.tile(c)["t"] != "water" and n < 36:
			Game.tile(c)["b"] = ["farm", "lodge", "mine", "outpost", "wall", "tower", "market", "refinery"][n % 8]
			n += 1
	Game.prisoners = 8


func bench_whole_map_scans_x100() -> void:
	await measure("owned(player) x100", func():
		for i in 100:
			Game.owned(Data.PLAYER), 20)
	await measure("owned(Rust Kings) x100", func():
		for i in 100:
			Game.owned(Data.AI), 20)
	await measure("count_building x100", func():
		for i in 100:
			Game.count_building(Data.PLAYER, "wall"), 20)


func bench_update_fog() -> void:
	await measure("update fog (runs on every change)", func(): Game.update_fog(), 30)


func bench_raid_and_prison_code_x100() -> void:
	await measure("outposts in circle + prison_break_due x100", func():
		for i in 100:
			Game.prison_break_due(), 20)
	await measure("buildings_of (sorted targets) x100", func():
		for i in 100:
			Game.buildings_of(Data.PLAYER, Game.home(Data.AI)), 20)
	await measure("sync Raider wall tiles x100", func():
		for i in 100:
			Game._sync_ai_walls(), 20)
	await measure("building_dc x1000", func():
		for i in 1000:
			Game.building_dc(hq + Vector2i(i % 5 - 2, i % 3 - 1)), 20)


func bench_quirk_checks_x10000() -> void:
	Game.leader_info = Leaders.fill("builder", {"perks": ["haggler", "pack_rat"], "flaw": "slow_marchers"})
	await measure("has_quirk x10000 (it sits in many sums)", func():
		for i in 10000:
			Game.has_quirk("trailblazer"), 20)
	await measure("sell_gold + buy_price x1000", func():
		for i in 1000:
			Game.sell_gold("metal")
			Game.buy_price("metal"), 20)
	Game.leader_info = Leaders.fill("builder")


func bench_leaders() -> void:
	await measure("make three leaders x100", func():
		for i in 100:
			Leaders.make_three(), 20)
	await measure("first portrait load (big and small, 11 pictures)", func():
		Leaders._textures.clear()
		for cls in Data.LEADERS:
			for id in Leaders.pictures(cls):
				Leaders.portrait({"image": id})
				Leaders.portrait({"image": id}, true), 10, 1)
	await measure("portrait x1000 (cached)", func():
		for i in 1000:
			Leaders.portrait({"image": "raider_1"}), 20)


func bench_save_and_load() -> void:
	await measure("save game", func(): Game.save_game("bench_slot"), 15)
	await measure("load game", func(): Game.load_game("bench_slot"), 15)
	var size := FileAccess.get_file_as_bytes(Game._path("bench_slot")).size()
	record("save file size", size / 1024.0, "KB")
	DirAccess.remove_absolute(Game._path("bench_slot"))


func bench_leader_screens() -> void:
	if DisplayServer.get_name() == "headless":
		record("leader screens", 0.0, "", "skipped: they need a window (-Windowed)")
		return
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: Node
	for child in main.get_children():
		if child.has_method("show_new_colony"):
			hud = child
	await measure("open the leader selection screen", func():
		hud.show_new_colony()
		await get_tree().process_frame, 20)
	await measure("reroll the leaders (new faces and texts)", func():
		Leaders.offer(true)
		hud.show_new_colony()
		await get_tree().process_frame, 20)
	# a running colony, then what every click costs: each Game.changed rebuilds the panels
	Game.new_game("raider", Leaders.offer()[0])
	hud._close_menu()
	for i in 4:
		await get_tree().process_frame
	await measure("colony panel with the leader block", func():
		hud._refresh_colony()
		await get_tree().process_frame, 20)
	await measure("refresh the whole HUD", func():
		hud.refresh()
		await get_tree().process_frame, 20)
	await measure("top bar", func(): hud._refresh_top(), 20)
	await measure("tile panel (a tile selected)", func():
		Game.select(Game.home(Data.PLAYER) + Vector2i(1, 1))
		hud._refresh_tile(), 20)
	await measure("upgrades panel", func(): hud._refresh_upgrades(), 20)
	await measure("one whole change: fog, map, panels (Game.changed)", func():
		Game.changed.emit()
		await get_tree().process_frame
		await get_tree().process_frame, 20)
	main.queue_free()
