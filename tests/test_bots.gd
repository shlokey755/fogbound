extends SceneTree
## test_bots.gd
## Logic tests for the bot AI (BotNav, BotKnowledge, BotMission, BotBrain).
## None of these need the scene tree: the "world" is a real MazeGenerator
## maze plus a tiny kinematic body that slides along walls, driven by the
## same brain/mission code the game uses. Run with:
##   godot --headless --script res://tests/test_bots.gd

const TILE := 16.0
const DT := 1.0 / 60.0
const MOVE := 64.0       # GameState.MOVE_SPEED
const DMAX := 96.0       # GameState.TETHER_DMAX

var failures := 0


class Body:
	extends RefCounted
	var pos := Vector2.ZERO

	func try_move(maze: MazeGenerator, step: Vector2) -> void:
		# Axis-separated, so the body slides along a wall like move_and_slide does.
		var nx := pos + Vector2(step.x, 0.0)
		if not _hits(maze, nx):
			pos = nx
		var ny := pos + Vector2(0.0, step.y)
		if not _hits(maze, ny):
			pos = ny

	func _hits(maze: MazeGenerator, p: Vector2) -> bool:
		var r := 5.5  # the player's collision circle is radius 6
		for off in [Vector2(-r, -r), Vector2(r, -r), Vector2(-r, r), Vector2(r, r)]:
			var c := Vector2i(int(floorf((p.x + off.x) / 16.0)), int(floorf((p.y + off.y) / 16.0)))
			if not maze.is_floor(c.x, c.y):
				return true
		return false


func _init() -> void:
	_test_nav()
	_test_knowledge_is_fog_fair()
	_test_frontier_exploration()
	_test_mission_priorities()
	_test_mission_stickiness()
	_test_brain_speed_and_hold()
	_test_solo_bot_finishes_the_maze()
	_test_follower_keeps_the_rope_safe()
	_test_skill_table()

	if failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("%d TEST(S) FAILED" % failures)
		quit(1)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failures += 1


func _maze(seed_value: int, size: int = 31, frags: int = 8, rooms: int = 4) -> MazeGenerator:
	var m := MazeGenerator.new()
	m.generate(seed_value, size, size, frags, 0, rooms, 3)
	return m


# ---------------------------------------------------------------------------

func _test_nav() -> void:
	var m := _maze(5)
	var nav := BotNav.new(m, TILE)
	var c := Vector2i(7, 9)
	_check("cell_of(center_of(c)) round-trips", nav.cell_of(nav.center_of(c)) == c)
	_check("cell_of handles a point at the very top-left of a cell", nav.cell_of(Vector2(16.0, 32.0)) == Vector2i(1, 2))

	# Along the fog room's middle row the view is clear; through the maze's solid border it is not.
	var mid := nav.center_of(m.spawn_cell)
	var east := m.spawn_cell + Vector2i(1, 0)
	_check("can see an adjacent floor cell", nav.can_see(mid, east))
	_check("a wall face is visible when nothing is in the way", nav.can_see(nav.center_of(Vector2i(1, 1)), Vector2i(0, 1)))

	# Find floor | wall | floor on one row: the far side must be hidden by the wall.
	var blocked_found := false
	for y in range(1, m.h - 1):
		for x in range(1, m.w - 3):
			if m.is_floor(x, y) and not m.is_floor(x + 1, y) and m.is_floor(x + 2, y):
				blocked_found = true
				_check("cannot see a floor cell through a wall in between", not nav.can_see(nav.center_of(Vector2i(x, y)), Vector2i(x + 2, y)))
				_check("but can see the wall itself", nav.can_see(nav.center_of(Vector2i(x, y)), Vector2i(x + 1, y)))
				break
		if blocked_found:
			break
	_check("test maze has a wall between two floor cells", blocked_found)
	_check("in_bounds rejects negative and too-large cells",
		not nav.in_bounds(Vector2i(-1, 0)) and not nav.in_bounds(Vector2i(m.w, 0)) and nav.in_bounds(Vector2i(0, 0)))


func _test_knowledge_is_fog_fair() -> void:
	var m := _maze(11)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	_check("a fresh bot team knows no floor at all", k.floor_known == 0)

	var far := Vector2i(-1, -1)
	for y in range(m.h):
		for x in range(m.w):
			if m.is_floor(x, y) and Vector2(x - m.spawn_cell.x, y - m.spawn_cell.y).length() > 9.0:
				far = Vector2i(x, y)
	_check("the maze has a floor cell well away from the spawn", far != Vector2i(-1, -1))

	k.observe(nav.center_of(m.spawn_cell), 3)
	_check("observing marks the cell it stands on", k.is_seen(m.spawn_cell))
	_check("observing marks cells in sight", k.floor_known > 5)
	_check("cells beyond sight radius stay unknown", not k.is_seen(far))
	_check("no path to a cell the team has never looked at", k.path(m.spawn_cell, far).is_empty())
	_check("a known cell has a trivial path to itself", k.path(m.spawn_cell, m.spawn_cell).size() == 1)

	var before := k.floor_known
	k.observe(nav.center_of(m.spawn_cell), 3)
	_check("observing the same spot twice adds nothing new", k.floor_known == before)


func _test_frontier_exploration() -> void:
	var m := _maze(21)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	_check("with nothing seen there is no frontier to walk to", k.nearest_frontier(m.spawn_cell) == BotKnowledge.NONE)
	k.observe(nav.center_of(m.spawn_cell), 3)
	var f := k.nearest_frontier(m.spawn_cell)
	_check("after a first look there IS a frontier", f != BotKnowledge.NONE)
	_check("the frontier is a known floor cell", m.is_floor(f.x, f.y) and k.is_seen(f))
	_check("the frontier touches something unseen", k.is_frontier(f))
	_check("the frontier is reachable through known cells", not k.path(m.spawn_cell, f).is_empty())

	# Fully revealing the maze leaves nothing to explore.
	_reveal_all(k)
	_check("a fully known maze has no frontier", k.nearest_frontier(m.spawn_cell) == BotKnowledge.NONE)
	_check("explored_fraction reaches 1.0 when everything is known", is_equal_approx(k.explored_fraction(), 1.0))


func _reveal_all(k: BotKnowledge) -> void:
	for y in range(k.nav.maze.h):
		for x in range(k.nav.maze.w):
			if not k.is_seen(Vector2i(x, y)):
				k._mark(Vector2i(x, y))


func _ctx(m: MazeGenerator, pos: Vector2, read: Dictionary, unlocked: bool, prev: Dictionary = {}) -> Dictionary:
	return {
		"pos": pos, "fragment_cells": m.fragment_cells, "read": read, "total": m.fragment_cells.size(),
		"console_cell": m.console_cell, "exit_cell": m.exit_cell, "unlocked": unlocked, "prev": prev,
	}


func _test_mission_priorities() -> void:
	var m := _maze(33)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	_reveal_all(k)
	var start := nav.center_of(m.spawn_cell)
	var n := m.fragment_cells.size()

	var all_read := {}
	for i in range(n):
		all_read[i] = true

	var g := BotMission.choose(k, _ctx(m, start, all_read, true))
	_check("unlocked + exit known -> EXIT", g["kind"] == BotMission.Kind.EXIT and g["cell"] == m.exit_cell)
	g = BotMission.choose(k, _ctx(m, start, all_read, false))
	_check("every fragment read but not unlocked -> CONSOLE", g["kind"] == BotMission.Kind.CONSOLE and g["cell"] == m.console_cell)
	g = BotMission.choose(k, _ctx(m, start, {}, false))
	_check("fragments known and unread -> COLLECT", g["kind"] == BotMission.Kind.COLLECT)
	_check("COLLECT targets an actual fragment cell", m.fragment_cells.has(g["cell"]))

	# It picks the NEAREST unread one by walking distance.
	var best_len := 1 << 30
	for c in m.fragment_cells:
		best_len = mini(best_len, k.path(m.spawn_cell, c).size())
	_check("COLLECT picks the closest unread fragment by path length",
		k.path(m.spawn_cell, g["cell"]).size() == best_len)

	# A fragment already read is skipped.
	var read_one := {}
	var first_id: int = m.fragment_cells.find(g["cell"])
	read_one[first_id] = true
	var g2 := BotMission.choose(k, _ctx(m, start, read_one, false))
	_check("an already-read fragment is not chosen again", g2["cell"] != g["cell"])

	# Fog-fair: a team that has only seen the fog room cannot collect what it has not seen.
	var k2 := BotKnowledge.new(nav)
	k2.observe(start, 2)
	var g3 := BotMission.choose(k2, _ctx(m, start, {}, false))
	_check("with no fragment seen yet the bot EXPLOREs", g3["kind"] == BotMission.Kind.EXPLORE)
	var g4 := BotMission.choose(k2, _ctx(m, start, all_read, true))
	_check("unlocked but the exit not found yet -> keeps EXPLORing", g4["kind"] == BotMission.Kind.EXPLORE)

	var g5 := BotMission.choose(k, _ctx(m, start, {}, false))
	var k3 := BotKnowledge.new(nav)  # knows nothing: nowhere to go
	var g6 := BotMission.choose(k3, _ctx(m, start, {}, false))
	_check("a bot that knows nothing and cannot move waits", g6["kind"] == BotMission.Kind.WAIT)
	_check("plan is always a dictionary with kind and cell", g5.has("kind") and g5.has("cell"))


func _test_mission_stickiness() -> void:
	var m := _maze(33)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	_reveal_all(k)
	var start := nav.center_of(m.spawn_cell)
	var first := BotMission.choose(k, _ctx(m, start, {}, false))

	# Move the leader right next to a DIFFERENT fragment; the old target should stick.
	var other := Vector2i(-1, -1)
	for c in m.fragment_cells:
		if c != first["cell"]:
			other = c
	var near_other := nav.center_of(other)
	var kept := BotMission.choose(k, _ctx(m, near_other, {}, false, first))
	_check("COLLECT target sticks until read, even when another fragment is nearer", kept["cell"] == first["cell"])

	var id: int = m.fragment_cells.find(first["cell"])
	var moved_on := BotMission.choose(k, _ctx(m, near_other, {id: true}, false, first))
	_check("once the sticky fragment is read the plan moves on", moved_on["cell"] != first["cell"])


func _test_brain_speed_and_hold() -> void:
	var m := _maze(2)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	_reveal_all(k)
	for skill in [BotBrain.Skill.EASY, BotBrain.Skill.NORMAL, BotBrain.Skill.HARD]:
		var b := BotBrain.new(nav, k, skill)
		var top: float = BotBrain.SKILLS[skill]["speed"]
		_check("%s leader runs at top speed on a loose rope" % BotBrain.skill_name(skill), is_equal_approx(b.leader_speed(0.1), top))
		_check("%s leader has stopped before the rope can snap (tension 0.85)" % BotBrain.skill_name(skill), b.leader_speed(0.85) == 0.0)
		_check("%s leader slows monotonically as tension rises" % BotBrain.skill_name(skill),
			b.leader_speed(0.3) >= b.leader_speed(0.55) and b.leader_speed(0.55) >= b.leader_speed(0.7) and b.leader_speed(0.7) >= b.leader_speed(0.8))

	var careful := BotBrain.new(nav, k, BotBrain.Skill.HARD)
	var sloppy := BotBrain.new(nav, k, BotBrain.Skill.EASY)
	_check("a careful (Hard) leader brakes earlier than a sloppy (Easy) one", careful.leader_speed(0.55) / 1.0 < sloppy.leader_speed(0.55) / 0.7)

	# Follower hold + hysteresis on a straight run of corridor/room.
	var leader_pos := nav.center_of(m.spawn_cell)
	var follower := BotBrain.new(nav, k, BotBrain.Skill.NORMAL)
	var out := follower.steer(leader_pos + Vector2(-12.0, 0.0), leader_pos, 1.0, BotBrain.HOLD_PX, DT)
	_check("a follower closer than the hold distance stands still", out["state"] == "hold" and out["dir"] == Vector2.ZERO)
	out = follower.steer(leader_pos + Vector2(-24.0, 0.0), leader_pos, 1.0, BotBrain.HOLD_PX, DT)
	_check("hysteresis: a bit further out it is still holding (no jitter)", out["state"] == "hold")
	out = follower.steer(leader_pos + Vector2(-36.0, 0.0), leader_pos, 1.0, BotBrain.HOLD_PX, DT)
	_check("far enough away it moves again", out["state"] == "go" and out["dir"].x > 0.5)


# ---------------------------------------------------------------------------
# End-to-end (no physics engine): one bot leader plays a whole match.
# ---------------------------------------------------------------------------

func _solo_run(seed_value: int, size: int, frags: int, rooms: int, skill: int, max_ticks: int) -> Dictionary:
	var m := _maze_sized(seed_value, size, frags, rooms)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	var brain := BotBrain.new(nav, k, skill)
	var body := Body.new()
	body.pos = nav.center_of(m.spawn_cell)
	var read := {}
	var unlocked := false
	var plan := {}
	var plan_t := 0.0
	var last_cell := Vector2i(-9, -9)
	var total := m.fragment_cells.size()

	for tick in range(max_ticks):
		var c := nav.cell_of(body.pos)
		if c != last_cell:
			last_cell = c
			k.observe(body.pos, brain.sight())
		plan_t -= DT
		if plan_t <= 0.0:
			plan_t = 0.4
			plan = BotMission.choose(k, {
				"pos": body.pos, "fragment_cells": m.fragment_cells, "read": read, "total": total,
				"console_cell": m.console_cell, "exit_cell": m.exit_cell, "unlocked": unlocked, "prev": plan,
			})
		var speed := brain.leader_speed(0.0) if plan["kind"] != BotMission.Kind.WAIT else 0.0
		var out := brain.steer(body.pos, nav.center_of(plan["cell"]), speed, 0.0, DT)
		body.try_move(m, out["dir"] * MOVE * out["speed"] * DT)

		for id in range(total):
			if not read.has(id) and body.pos.distance_to(nav.center_of(m.fragment_cells[id])) < 8.0:
				read[id] = true
		if not unlocked and read.size() >= total and body.pos.distance_to(nav.center_of(m.console_cell)) < 8.0:
			unlocked = true
		if unlocked and body.pos.distance_to(nav.center_of(m.exit_cell)) < 10.0:
			return {"done": true, "ticks": tick, "explored": k.explored_fraction(), "fragments": read.size(), "total": total}
	return {"done": false, "ticks": max_ticks, "explored": k.explored_fraction(), "fragments": read.size(), "total": total}


func _maze_sized(seed_value: int, size: int, frags: int, rooms: int) -> MazeGenerator:
	var m := MazeGenerator.new()
	m.generate(seed_value, size, size, frags, 0, rooms, 3)
	return m


func _test_solo_bot_finishes_the_maze() -> void:
	# [maze size, fragments, puzzle rooms, label]
	var classes := [[19, 5, 2, "Antechamber"], [31, 8, 4, "Understreets"], [45, 12, 6, "Long Fog"]]
	for c in classes:
		var done := 0
		var worst := 0
		var tried := 6
		for seed_value in range(1, tried + 1):
			var r := _solo_run(seed_value * 97, c[0], c[1], c[2], BotBrain.Skill.NORMAL, 60 * 60 * 12)
			if r["done"] and r["fragments"] == r["total"]:
				done += 1
				worst = maxi(worst, r["ticks"])
			else:
				print("   (seed %d did not finish: %d/%d fragments after %d ticks, %.0f%% explored)" % [seed_value * 97, r["fragments"], r["total"], r["ticks"], r["explored"] * 100.0])
		print("   %s: %d/%d finished, slowest %.0f s of game time" % [c[3], done, tried, worst / 60.0])
		_check("a Normal bot reads every fragment, unlocks and exits %s on all %d seeds" % [c[3], tried], done == tried)

	var easy := _solo_run(1234, 31, 8, 4, BotBrain.Skill.EASY, 60 * 60 * 15)
	var hard := _solo_run(1234, 31, 8, 4, BotBrain.Skill.HARD, 60 * 60 * 15)
	_check("Easy and Hard bots both finish the same maze", easy["done"] and hard["done"])
	_check("a Hard bot is faster than an Easy one on the same maze (%d vs %d ticks)" % [hard["ticks"], easy["ticks"]],
		hard["ticks"] < easy["ticks"])


# ---------------------------------------------------------------------------
# Two bots on a rope: a leader on a mission, a follower behind. The rope
# is approximated by the walking distance between them (what the real
# rope's taut path is), and must never reach the snap length.
# ---------------------------------------------------------------------------

func _chain_run(seed_value: int, skill: int, ticks: int) -> Dictionary:
	var m := _maze_sized(seed_value, 31, 8, 4)
	var nav := BotNav.new(m, TILE)
	var k := BotKnowledge.new(nav)
	var lead_brain := BotBrain.new(nav, k, skill)
	var follow_brain := BotBrain.new(nav, k, skill)
	var lead := Body.new()
	var follow := Body.new()
	lead.pos = nav.center_of(m.spawn_cell)
	follow.pos = lead.pos + Vector2(-8.0, 0.0)
	var plan := {}
	var plan_t := 0.0
	var read := {}
	var worst := 0.0
	var lc := Vector2i(-9, -9)
	var fc := Vector2i(-9, -9)
	var moved := 0.0
	var start := lead.pos

	for tick in range(ticks):
		var c1 := nav.cell_of(lead.pos)
		var c2 := nav.cell_of(follow.pos)
		if c1 != lc:
			lc = c1
			k.observe(lead.pos, lead_brain.sight())
		if c2 != fc:
			fc = c2
			k.observe(follow.pos, lead_brain.sight())

		var rope := _rope_len(k, nav, lead.pos, follow.pos)
		worst = maxf(worst, rope)
		var tension := rope / DMAX

		plan_t -= DT
		if plan_t <= 0.0:
			plan_t = 0.4
			plan = BotMission.choose(k, {
				"pos": lead.pos, "fragment_cells": m.fragment_cells, "read": read, "total": m.fragment_cells.size(),
				"console_cell": m.console_cell, "exit_cell": m.exit_cell, "unlocked": false, "prev": plan,
			})
		var speed := lead_brain.leader_speed(tension) if plan["kind"] != BotMission.Kind.WAIT else 0.0
		var lo := lead_brain.steer(lead.pos, nav.center_of(plan["cell"]), speed, 0.0, DT)
		lead.try_move(m, lo["dir"] * MOVE * lo["speed"] * DT)
		var fo := follow_brain.steer(follow.pos, lead.pos, 1.0, BotBrain.HOLD_PX, DT)
		follow.try_move(m, fo["dir"] * MOVE * fo["speed"] * DT)
		moved = maxf(moved, lead.pos.distance_to(start))
	return {"worst_rope": worst, "moved": moved, "final_gap": lead.pos.distance_to(follow.pos)}


func _rope_len(k: BotKnowledge, nav: BotNav, a: Vector2, b: Vector2) -> float:
	var p := k.path(nav.cell_of(a), nav.cell_of(b))
	if p.is_empty():
		return a.distance_to(b)
	return maxf(a.distance_to(b), float(p.size() - 1) * TILE - TILE * 0.5)


func _test_follower_keeps_the_rope_safe() -> void:
	for skill in [BotBrain.Skill.EASY, BotBrain.Skill.NORMAL, BotBrain.Skill.HARD]:
		var worst := 0.0
		var travelled := 1e9
		for seed_value in [3, 14, 159, 2653]:
			var r := _chain_run(seed_value, skill, 60 * 90)
			worst = maxf(worst, r["worst_rope"])
			travelled = minf(travelled, r["moved"])
		print("   %s: longest rope %.0f px of %.0f, leader got at least %.0f px from the start" % [BotBrain.skill_name(skill), worst, DMAX, travelled])
		_check("%s pod: the rope never reaches the snap length over 4 mazes x 90 s" % BotBrain.skill_name(skill), worst < DMAX - 4.0)
		_check("%s pod: the leader still makes real progress (>100 px)" % BotBrain.skill_name(skill), travelled > 100.0)


func _test_skill_table() -> void:
	_check("three skill levels exist", BotBrain.skill_count() == 3)
	_check("skill names are Easy/Normal/Hard", BotBrain.skill_name(0) == "Easy" and BotBrain.skill_name(1) == "Normal" and BotBrain.skill_name(2) == "Hard")
	_check("skill_name clamps an out-of-range index", BotBrain.skill_name(99) == "Hard" and BotBrain.skill_name(-5) == "Easy")
	var speeds_rise := true
	var sight_rises := true
	for i in range(BotBrain.skill_count() - 1):
		if BotBrain.SKILLS[i]["speed"] >= BotBrain.SKILLS[i + 1]["speed"]:
			speeds_rise = false
		if BotBrain.SKILLS[i]["sight"] >= BotBrain.SKILLS[i + 1]["sight"]:
			sight_rises = false
	_check("harder bots are faster", speeds_rise)
	_check("harder bots see further", sight_rises)
	_check("the fastest bot is never faster than a player (speed <= 1.0)", BotBrain.SKILLS[2]["speed"] <= 1.0)
