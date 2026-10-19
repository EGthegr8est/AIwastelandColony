extends SceneTree
## Command-line test runner. From the project folder, with Godot's *console* executable:
##
##   godot --headless --path . -s res://tests/run_tests.gd                     every test
##   godot --headless --path . -s res://tests/run_tests.gd -- --filter=render  tests whose path::name contains "render"
##   godot --path . -s res://tests/run_tests.gd -- --bench --save=before       benchmarks (windowed = real GPU numbers)
##   godot --path . -s res://tests/run_tests.gd -- --bench --compare=before    ...and compare with a saved run
##
## More options: --dir=res://tests/unit  --timeout=30  --junit=res://tests/results/junit.xml  --list
## Exit code: 0 all passed, 1 something failed, 2 no tests ran. tests/run.ps1 finds Godot for you.

const Runner = preload("res://tests/framework/runner.gd")


func _initialize() -> void:
	_main()


func _main() -> void:
	await process_frame   # the root viewport only joins the tree after _initialize() returns
	preload("res://scripts/roster.gd").fixed_seed = 4242   # the same survivors in every test run
	var runner := Runner.new(self, OS.get_cmdline_user_args())
	quit(await runner.run())
