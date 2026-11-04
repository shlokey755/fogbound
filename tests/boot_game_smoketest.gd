extends Node
## boot_game_smoketest.gd
## Temporary main-scene script used ONLY by tools/run_boot_smoketest.sh
## to verify game.tscn actually boots under a normal (non --script)
## headless run, where [autoload] singletons are real. Not part of
## the shipped game -- see docs/WALKTHROUGH.md "Testing".
##
## Covers two passes:
##   1. A normal 2-player match on the default level -- players spawn,
##      the maze generates, exactly one tether link forms.
##   (0. A level-table pass: every LevelData entry generates a solvable
##      maze with its puzzle rooms placed and a 3-tile TileSet.)
##   2. A full match on the secret-level unlock SOURCE level
##      (LevelData.SECRET_LEVEL_UNLOCK_SOURCE_ID) ending in a
##      simulated 1200-point finish, verifying the secret level
##      actually unlocks in SaveData as a result -- the one part of
##      the unlock flow that only exercises correctly inside a real
##      RPC call (net_match_finished is call_local, so it genuinely
##      fires here even single-process).

var ok := true


func _ready() -> void:
	# Redirect SaveData at a throwaway file so this test never reads or
	# writes a real player's unlock progress.
	SaveData.save_path_override = "user://fogbound_boot_smoketest_save.cfg"
	var test_save_abs := ProjectSettings.globalize_path(SaveData.save_path_override)
	if FileAccess.file_exists(test_save_abs):
		DirAccess.remove_absolute(test_save_abs)
	SaveData.reload_for_test()

	_check("GameState.DEFAULT_LEVEL_ID and LevelData.default_level_id() agree (see both constants' comments)",
		GameState.DEFAULT_LEVEL_ID == LevelData.default_level_id())

	_run_json_int_roundtrip_regression_pass()
	_run_level_table_pass()
	await _run_basic_match_pass()
	await _run_secret_level_unlock_pass()

	print("ALL TESTS PASSED" if ok else "SOME TESTS FAILED")
	get_tree().quit(0 if ok else 1)


func _check(label: String, condition: bool) -> bool:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		ok = false
	return condition


## Regression test for a real bug the secret-level unlock pass below
## caught: Godot's JSON.parse_string() decodes every number as a
## float and every Dictionary key as a String, so a naive
## JSON.stringify()/JSON.parse_string() round trip of GameState.teams
## or GameState.final_scores silently breaks every later int-keyed
## lookup against that data (Array.has(1) is false against [1.0, 2.0];
## a Dictionary lookup with int key 0 is false against key "0") even
## though int(1) == float(1.0) with the == operator. NetRouter's RPC
## handlers now route every such payload through _parse_json_with_ints()
## instead of a bare JSON.parse_string() -- this exercises that helper
## directly against exactly the shapes net_router.gd actually sends.
func _run_json_int_roundtrip_regression_pass() -> void:
	var teams_json := JSON.stringify({0: {"name": "Pod A", "member_order": [1, 2]}})
	var teams = NetRouter._parse_json_with_ints(teams_json)
	_check("JSON round-trip: team id key comes back as an int you can .has()/index with",
		teams.has(0) and teams[0]["name"] == "Pod A")
	_check("JSON round-trip: member_order peer ids come back as ints you can .has() with",
		teams[0]["member_order"].has(1) and teams[0]["member_order"].has(2))

	var scores_json := JSON.stringify([{"pod": [1, 2], "team_id": 0, "points": 1200}])
	var scores = NetRouter._parse_json_with_ints(scores_json)
	_check("JSON round-trip: a pod array's peer ids come back as ints you can .has() with",
		scores[0]["pod"].has(1) and scores[0]["pod"].has(2))
	_check("JSON round-trip: points stays usable as an int (no fractional part introduced)",
		scores[0]["points"] == 1200)

	# A real fractional float must NOT get coerced into an int --
	# only values that round-tripped cleanly from an original int do.
	var mixed = NetRouter._parse_json_with_ints(JSON.stringify({"ratio": 0.5}))
	_check("JSON round-trip: a genuine fractional float is left as a float, not truncated",
		mixed["ratio"] is float and mixed["ratio"] == 0.5)


## Runs against the real LevelData autoload (which --script tests can't
## see): every level, a few seeds each, must build a maze where all its
## puzzle rooms are placed, every fragment/exit is reachable, and the
## number of rooms never exceeds the number of fragments.
func _run_level_table_pass() -> void:
	for lvl in LevelData.levels:
		var placed_all := true
		var reachable := true
		for seed_value in [11, 222, 3333, 44444]:
			var m := MazeGenerator.new()
			m.generate(seed_value, lvl.width, lvl.height, lvl.fragment_count, 3, lvl.puzzle_rooms, lvl.puzzle_room_size)
			if m.puzzle_rooms.size() != lvl.puzzle_rooms:
				placed_all = false
			var reach := m.reachable_from(m.spawn_cell)
			if not reach.has(m.exit_cell):
				reachable = false
			for f in m.fragment_cells:
				if not reach.has(f):
					reachable = false
		_check("level %d (%s): all %d puzzle rooms placed on 4 seeds" % [lvl.id, lvl.name, lvl.puzzle_rooms], placed_all)
		_check("level %d (%s): fragments and exit reachable" % [lvl.id, lvl.name], reachable)
		_check("level %d (%s): puzzle rooms <= fragment count" % [lvl.id, lvl.name],
			lvl.puzzle_rooms <= lvl.fragment_count)

	var ts: TileSet = MazeTileSetBuilder.build()
	var src: TileSetAtlasSource = ts.get_source(0)
	_check("tileset has floor, wall and puzzle-floor tiles",
		src.has_tile(Vector2i(0, 0)) and src.has_tile(Vector2i(1, 0)) and src.has_tile(Vector2i(2, 0)))
	_check("puzzle-floor tile is walkable (no collision polygon)",
		src.get_tile_data(Vector2i(2, 0), 0).get_collision_polygons_count(0) == 0)
	_check("wall tile still collides",
		src.get_tile_data(Vector2i(1, 0), 0).get_collision_polygons_count(0) == 1)


func _run_basic_match_pass() -> void:
	GameState.reset_match()
	GameState.match_seed = 555
	GameState.level_id = LevelData.default_level_id()
	GameState.teams = {
		0: {"name": "Pod A", "original_size": 2, "member_order": [1, 2]}
	}

	var scene: PackedScene = load("res://scenes/game.tscn")
	var instance: Node = scene.instantiate()
	add_child(instance)

	for i in range(120):  # ~2 seconds at 60 ticks, enough to exercise tether states
		await get_tree().process_frame

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

	_check("puzzle rooms were generated for the default level",
		instance.maze.puzzle_rooms.size() == LevelData.get_level(LevelData.default_level_id()).puzzle_rooms)
	var painted_puzzle_tile := false
	for room in instance.maze.puzzle_rooms:
		var c: Vector2i = room.get_center()
		if instance.maze_layer.get_cell_atlas_coords(c) == Vector2i(2, 0):
			painted_puzzle_tile = true
	_check("puzzle-room floor is painted with its own tile (2,0)", painted_puzzle_tile)

	_check("commentary nodes were spawned into the world (dead ends exist on this level)",
		instance.commentary_spawner != null and instance.commentary_spawner.get_child_count() > 0)

	_check_sprite_pipeline(instance)

	instance.queue_free()
	await get_tree().process_frame


## Character art: every sheet imports, matches the layout PlayerSprites
## assumes, still carries the scarf marker colour the team shader swaps,
## and a spawned player actually ends up using it.
func _check_sprite_pipeline(game: Node) -> void:
	var expected_w: int = PlayerSprites.FRAME * 6
	var expected_h: int = PlayerSprites.FRAME * PlayerSprites.ANIMS.size()
	for c in range(PlayerSprites.character_count()):
		var path := PlayerSprites.sheet_path(c)
		if not _check("character %d sheet is imported (run with --import first if this fails)" % c, PlayerSprites.has_art(c)):
			continue
		var tex: Texture2D = load(path)
		_check("character %d sheet is %dx%d" % [c, expected_w, expected_h],
			tex.get_width() == expected_w and tex.get_height() == expected_h)
		var img: Image = tex.get_image()
		var has_marker := false
		for y in range(img.get_height()):
			for x in range(img.get_width()):
				var px: Color = img.get_pixel(x, y)
				if px.a > 0.0 and px.to_html(false) == "ff00ff":
					has_marker = true
					break
			if has_marker:
				break
		_check("character %d keeps the magenta team-scarf marker" % c, has_marker)

	var p1: Player = game.player_nodes[1]
	var frames: SpriteFrames = p1.sprite.sprite_frames
	_check("spawned player has sprite frames", frames != null)
	if frames:
		var all_anims := true
		for anim_name in PlayerSprites.ANIMS:
			if not frames.has_animation(anim_name) or frames.get_frame_count(anim_name) != PlayerSprites.ANIMS[anim_name][1]:
				all_anims = false
		_check("every animation exists with the expected frame count", all_anims)
	_check("team palette shader is applied to the player sprite", p1.sprite.material is ShaderMaterial)
	_check("placeholder ColorRect is hidden once art is active", not p1.get_node("ColorRect").visible)
	_check("two players on different teams get different scarf colours",
		PlayerSprites.team_color(0) != PlayerSprites.team_color(1))


func _run_secret_level_unlock_pass() -> void:
	_check("secret level starts locked", not SaveData.is_unlocked(LevelData.SECRET_LEVEL_ID))
	_check("secret level is absent from the selectable list while locked",
		not _selectable_ids().has(LevelData.SECRET_LEVEL_ID))

	GameState.reset_match()
	GameState.match_seed = 777
	GameState.level_id = LevelData.SECRET_LEVEL_UNLOCK_SOURCE_ID
	GameState.teams = {
		0: {"name": "Pod A", "original_size": 2, "member_order": [1, 2]}
	}

	# Simulate the host reporting a full-team (1200-point) finish on
	# the unlock-source level, exactly as game_controller.gd's
	# _on_exit_body_entered would after both teammates reach the exit
	# together. Going through the real RPC entry point (net_match_finished,
	# call_local) rather than calling _check_secret_level_unlock()
	# directly means this test exercises the actual code path a real
	# match result travels, not a reimplementation of it.
	GameState.final_scores = [{"pod": [1, 2], "team_id": 0, "points": 1200}]
	NetRouter.net_match_finished(JSON.stringify(GameState.final_scores))
	await get_tree().process_frame

	_check("secret level unlocks after a 1200-point finish on its source level",
		SaveData.is_unlocked(LevelData.SECRET_LEVEL_ID))
	_check("secret level is now in the selectable list", _selectable_ids().has(LevelData.SECRET_LEVEL_ID))
	_check("consume_just_unlocked reports the secret level exactly once",
		SaveData.consume_just_unlocked() == LevelData.SECRET_LEVEL_ID)
	_check("a second consume_just_unlocked call returns -1 (already consumed)",
		SaveData.consume_just_unlocked() == -1)


func _selectable_ids() -> Array:
	return LevelData.selectable_levels().map(func(lvl): return lvl.id)
