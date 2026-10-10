extends Node
## boot_game_smoketest.gd
## Temporary main-scene script used ONLY by tools/run_boot_smoketest.sh
## to verify game.tscn actually boots under a normal (non --script)
## headless run, where [autoload] singletons are real. Not part of
## the shipped game -- see docs/WALKTHROUGH.md "Testing".

func _ready() -> void:
	GameState.reset_match()
	GameState.match_seed = 555
	GameState.maze_w = 21
	GameState.maze_h = 21
	GameState.teams = {
		0: {"name": "Pod A", "original_size": 2, "member_order": [1, 2]}
	}

	var scene: PackedScene = load("res://scenes/game.tscn")
	var instance: Node = scene.instantiate()
	add_child(instance)

	for i in range(120):  # ~2 seconds at 60 ticks, enough to exercise tether states
		await get_tree().process_frame

	var ok := true
	if not instance.player_nodes.has(1) or not instance.player_nodes.has(2):
		print("FAIL: expected 2 player nodes to be spawned, got keys: %s" % [instance.player_nodes.keys()])
		ok = false
	else:
		print("PASS: both players spawned")

	if instance.maze == null or instance.maze.w <= 0:
		print("FAIL: maze was not generated")
		ok = false
	else:
		print("PASS: maze generated (%dx%d)" % [instance.maze.w, instance.maze.h])

	if instance.tether_system == null or instance.tether_system.links.size() != 1:
		print("FAIL: expected exactly 1 tether link for a 2-player team, got %s" %
			(instance.tether_system.links.size() if instance.tether_system else "null tether_system"))
		ok = false
	else:
		print("PASS: tether link created between the 2 teammates")

	print("ALL TESTS PASSED" if ok else "SOME TESTS FAILED")
	get_tree().quit(0 if ok else 1)
