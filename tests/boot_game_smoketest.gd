extends Node
## boot_game_smoketest.gd
## Temporary main-scene script used ONLY by tools/run_boot_smoketest.sh
## to verify game.tscn actually boots under a normal (non --script)
## headless run, where [autoload] singletons are real. Not part of
## the shipped game -- see docs/WALKTHROUGH.md "Testing".
##
## Offline mode (one human + bots) is covered by the passes at the bottom:
## wiring, a complete autoplay match, elimination ending the match, and the
## setup screen's limits. They need `--fixed-fps 60` (tests/run_all_tests.sh
## passes it) so a few simulated minutes take seconds of wall time.
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
	_run_offline_config_pass()
	await _run_offline_wiring_pass()
	await _run_offline_autoplay_pass()
	await _run_offline_elimination_pass()
	await _run_offline_menu_pass()

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


# ---------------------------------------------------------------------------
# Offline mode (human + bots)
# ---------------------------------------------------------------------------

## Instantiates game.tscn for an already-configured offline match. The game's
## finish handler swaps to the score screen, which would free THIS test's
## scene tree, so it is unhooked here.
func _spawn_offline_game() -> Node:
	var instance: Node = load("res://scenes/game.tscn").instantiate()
	add_child(instance)
	NetRouter.match_finished.disconnect(instance._on_match_finished)
	return instance


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _total_players(ui: OfflineSetup) -> int:
	return OfflineSetup.total_players(int(ui._teammates.value), int(ui._rivals.value), int(ui._rival_size.value))


func _run_offline_config_pass() -> void:
	var lvl: LevelData.LevelDef = LevelData.levels[2]
	OfflineSetup.configure_match(lvl.id, 2, 1, 3, BotBrain.Skill.HARD, 31337)
	_check("offline config: flags, level and seed land in GameState",
		GameState.offline_mode and GameState.human_id == 1 and GameState.level_id == lvl.id and GameState.match_seed == 31337)
	var bot_ids := GameState.bots.keys()
	bot_ids.sort()
	_check("offline config: you are peer 1 and never a bot; bots take ids 2..6", bot_ids == [2, 3, 4, 5, 6] and not GameState.is_bot(1))
	_check("offline config: every bot carries the chosen skill",
		GameState.bots.values().all(func(b): return b["skill"] == BotBrain.Skill.HARD))
	_check("offline config: your pod is you first, then your bots, original size 3",
		GameState.teams[0]["member_order"] == [1, 2, 3] and GameState.teams[0]["original_size"] == 3)
	_check("offline config: rival pod is its own team of 3", GameState.teams[1]["member_order"] == [4, 5, 6]
		and GameState.teams[1]["name"] == "Rivals A" and GameState.teams[1]["original_size"] == 3)
	_check("offline config: player_team and human_team_id agree",
		GameState.player_team[1] == 0 and GameState.player_team[5] == 1 and GameState.human_team_id() == 0)

	OfflineSetup.configure_match(0, 1, 0, 3, BotBrain.Skill.EASY, 5)
	_check("offline config: zero rivals gives one team and one bot", GameState.teams.size() == 1 and GameState.bots.size() == 1)

	OfflineSetup.configure_match(0, 1, 0, 3, BotBrain.Skill.EASY, 5, true)
	_check("offline config: autoplay hands your slot to a bot too", GameState.is_bot(1) and GameState.bots.size() == 2)

	GameState.reset_match()
	_check("reset_match clears offline mode, bots and the human team",
		not GameState.offline_mode and GameState.bots.is_empty() and GameState.human_team_id() == -1)

	# Setup screen: defaults, and the 16-player cap holds whatever order the
	# three counters are changed in.
	var ui := OfflineSetup.new()
	add_child(ui)
	_check("setup screen: defaults are you + 2 bots vs 1 rival pod of 3 (6 players)", _total_players(ui) == 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var worst := 0
	var in_range := true
	for i in range(600):
		match rng.randi() % 3:
			0: ui._teammates.value = rng.randi_range(1, 7)
			1: ui._rivals.value = rng.randi_range(0, 3)
			2: ui._rival_size.value = rng.randi_range(2, 5)
		worst = maxi(worst, _total_players(ui))
		if ui._teammates.value < 1 or ui._rival_size.value < 2:
			in_range = false
	_check("setup screen: 600 random changes never exceed %d players (worst %d)" % [GameState.MAX_PLAYERS, worst],
		worst <= GameState.MAX_PLAYERS)
	_check("setup screen: you always keep at least one teammate and rival pods at least 2", in_range)
	ui.queue_free()
	GameState.reset_match()


## Offline game scene: who spawns, who is driven, who sees, who follows.
func _run_offline_wiring_pass() -> void:
	OfflineSetup.configure_match(LevelData.default_level_id(), 2, 1, 3, BotBrain.Skill.NORMAL, 9001)
	var game := _spawn_offline_game()
	await _frames(30)

	_check("offline: 6 players spawn (you, 2 bots, 3 rivals)", game.player_nodes.size() == 6)
	_check("offline: you are driven by input, everyone else by a bot",
		not game.player_nodes[1].is_bot and game.player_nodes.keys().filter(func(id): return id != 1)
			.all(func(id): return game.player_nodes[id].is_bot))
	var human: Player = game.player_nodes[1]
	_check("offline: you are the local player and have a camera", human.is_local and _has_camera(human))
	_check("offline: bots are not local and have no camera",
		game.player_nodes.keys().filter(func(id): return id != 1).all(
			func(id): return not game.player_nodes[id].is_local and not _has_camera(game.player_nodes[id])))
	_check("offline: your pod carries light, rival pods do not (fog is fair)",
		game.player_nodes[2].light.enabled and human.light.enabled
		and game.player_nodes[4].light.enabled == false and game.player_nodes[6].light.enabled == false)
	_check("offline: one rope per neighbouring pair (2 + 2 links)", game.tether_system.links.size() == 4)
	var visible_lines := 0
	for line in game.link_lines.values():
		if line.visible:
			visible_lines += 1
	_check("offline: only your own pod's ropes are drawn (%d of %d)" % [visible_lines, game.link_lines.size()],
		visible_lines == 2 and game.link_lines.size() == 4)
	_check("offline: a BotController exists with a brain per bot",
		game.bot_controller != null and game.bot_controller.brains.size() == 5)
	_check("offline: a Menu button is on the HUD to leave the match",
		game.has_node("HUD/QuitButton") and game.get_node("HUD/QuitButton").pressed.get_connections().size() > 0)
	_check("offline: players can walk through each other (no bot deadlocks in corridors)",
		human.get_collision_exceptions().has(game.player_nodes[2]))

	var rival_start: Vector2 = game.player_nodes[4].position

	# Walk the human down the longest open run from the spawn, then stop.
	var nav: BotNav = game.bot_controller.nav
	var cell := nav.cell_of(human.position)
	var best_dir := Vector2i.RIGHT
	var best_run := -1
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		var run := 0
		while game.maze.is_floor(cell.x + d.x * (run + 1), cell.y + d.y * (run + 1)):
			run += 1
		if run > best_run:
			best_run = run
			best_dir = d
	var start: Vector2 = human.position
	NetRouter.send_input(Vector2(best_dir))
	await _frames(60)
	NetRouter.send_input(Vector2.ZERO)
	_check("offline: input reaches the human (moved %.0f px)" % start.distance_to(human.position),
		start.distance_to(human.position) > 20.0)
	await _frames(20)
	var stopped_at: Vector2 = human.position
	await _frames(30)
	_check("offline: releasing the input stops the human", stopped_at.distance_to(human.position) < 0.5)

	await _frames(240)
	var team_links_alive: int = game.tether_system.links.filter(
		func(l): return l.a_id <= 3 and l.b_id <= 3 and l.alive).size()
	_check("offline: your rope chain is intact after the walk", team_links_alive == 2)
	_check("offline: bot teammates tuck in behind you (gaps %.0f and %.0f px)" % [
			human.position.distance_to(game.player_nodes[2].position),
			game.player_nodes[2].position.distance_to(game.player_nodes[3].position)],
		human.position.distance_to(game.player_nodes[2].position) < 48.0
		and game.player_nodes[2].position.distance_to(game.player_nodes[3].position) < 48.0)
	_check("offline: the rival pod is exploring on its own (moved %.0f px)" % rival_start.distance_to(game.player_nodes[4].position),
		rival_start.distance_to(game.player_nodes[4].position) > 16.0)
	_check("offline: the match is still running", not GameState.match_over)

	game.queue_free()
	await get_tree().process_frame
	GameState.reset_match()


func _has_camera(p: Node) -> bool:
	return p.get_children().any(func(c): return c is Camera2D)


## Nobody drives: every player, you included, is a bot. The match has to run
## to its end by itself -- read fragments, open the exit, escape together --
## without a snap.
func _run_offline_autoplay_pass() -> void:
	for setup in [
		{"level": LevelData.default_level_id(), "mates": 1, "rivals": 1, "size": 2, "skill": BotBrain.Skill.NORMAL, "seed": 4242},
		{"level": LevelData.default_level_id(), "mates": 3, "rivals": 0, "size": 2, "skill": BotBrain.Skill.EASY, "seed": 77},
	]:
		OfflineSetup.configure_match(setup["level"], setup["mates"], setup["rivals"], setup["size"], setup["skill"], setup["seed"], true)
		var label := "autoplay seed %d (%d bots, skill %s)" % [setup["seed"], GameState.bots.size(), BotBrain.skill_name(setup["skill"])]
		var game := _spawn_offline_game()
		var frames := 0
		var cap := 60 * 400
		while not GameState.match_over and frames < cap:
			await get_tree().physics_frame
			frames += 1
		_check("%s: match ends on its own (%.0f sim s)" % [label, frames / 60.0], GameState.match_over)
		var yours = GameState.final_scores.filter(func(e): return e["pod"].has(1))
		_check("%s: your pod reached the exit" % label, yours.size() == 1)
		if yours.size() == 1:
			_check("%s: unbroken team scores the top tier" % label,
				yours[0]["points"] == 1200 and yours[0]["pod"].size() == GameState.teams[0]["original_size"])
		var snapped: int = game.tether_system.links.filter(func(l): return not l.alive).size()
		_check("%s: no rope snapped on the way (%d snapped)" % [label, snapped], snapped == 0)
		_check("%s: nobody was eliminated" % label,
			game.player_nodes.values().all(func(p): return not p.eliminated))
		game.queue_free()
		await get_tree().process_frame
		GameState.reset_match()


## The match is about YOUR pod: losing it ends the match once; a rival pod
## being lost does not.
func _run_offline_elimination_pass() -> void:
	OfflineSetup.configure_match(LevelData.default_level_id(), 1, 1, 2, BotBrain.Skill.NORMAL, 77)
	var game := _spawn_offline_game()
	await _frames(10)
	var finished := [0]
	var counter := func(): finished[0] += 1
	NetRouter.match_finished.connect(counter)

	var rival_link = game.tether_system.links.filter(func(l): return l.a_id == 3)[0]
	game.tether_system._snap(rival_link)
	await _frames(3)
	_check("offline: losing a rival pod does not end the match",
		not GameState.match_over and finished[0] == 0 and game.player_nodes[3].eliminated and game.player_nodes[4].eliminated)

	var own_link = game.tether_system.links.filter(func(l): return l.a_id == 1)[0]
	game.tether_system._snap(own_link)
	await _frames(3)
	_check("offline: losing your own pod ends the match", GameState.match_over and game.player_nodes[1].eliminated)
	_check("offline: nobody scored", GameState.final_scores.is_empty())
	game._check_match_finished()
	await _frames(2)
	_check("offline: the finish is announced exactly once", finished[0] == 1)

	NetRouter.match_finished.disconnect(counter)
	game.queue_free()
	await get_tree().process_frame
	GameState.reset_match()


func _run_offline_menu_pass() -> void:
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	var button: Button = menu.get_node("VBox/OfflineButton")
	_check("main menu: has a wired 'Play offline' button", button.text.begins_with("Play offline")
		and button.pressed.get_connections().size() > 0)
	menu.queue_free()

	var setup_scene: PackedScene = load("res://scenes/offline_setup.tscn")
	_check("offline setup scene loads", setup_scene != null and setup_scene.can_instantiate())
	await get_tree().process_frame
