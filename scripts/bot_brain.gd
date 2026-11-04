class_name BotBrain
extends RefCounted
## BotBrain
## Steering for ONE bot: turns "get to this point" into a movement direction
## and speed, one physics tick at a time. Deciding WHERE to go is BotMission
## (for a pod's leader) or BotController (for followers); this class only
## walks there, and it does so tether-aware:
##
##   * a leader slows down as the pod's rope tension rises and stops before
##     the rope can snap (how early depends on skill);
##   * a follower runs at full speed to close the gap, then holds still at
##     a short distance so it does not crowd its teammate.
##
## Pure logic over BotNav/BotKnowledge -- no nodes -- so it is unit-tested in
## tests/test_bots.gd by driving a point around a real generated maze.

enum Skill { EASY, NORMAL, HARD }

## speed: top speed as a fraction of MOVE_SPEED
## sight: how far (tiles) the bot looks when exploring
## slack: pod tension at which a leader starts to slow down
const SKILLS := [
	{"name": "Easy", "speed": 0.70, "sight": 2, "slack": 0.62},
	{"name": "Normal", "speed": 0.85, "sight": 3, "slack": 0.50},
	{"name": "Hard", "speed": 1.00, "sight": 4, "slack": 0.42},
]
const SLOW_BAND := 0.20       # tension range over which a leader goes from full speed to a stop
const HOLD_PX := 20.0         # a follower stops this close to who it follows...
const HOLD_RESUME_PX := 28.0  # ...and starts again once the gap is this big (no jitter)
const ARRIVE_PX := 1.5
const CENTRE_TOL := 2.5       # px off a corridor's centre line before squaring up
const REPATH_EVERY := 0.5     # seconds between path refreshes
const STUCK_AFTER := 0.8      # seconds of not moving while trying to, before re-routing

var nav: BotNav
var knowledge: BotKnowledge
var skill: Dictionary

var _path: Array[Vector2i] = []
var _goal := BotKnowledge.NONE
var _repath_in := 0.0
var _holding := false
var _wanted_move := false
var _last_pos := Vector2.INF
var _still_t := 0.0
var _nudge_t := 0.0


static func skill_count() -> int:
	return SKILLS.size()


static func skill_name(index: int) -> String:
	return SKILLS[clampi(index, 0, SKILLS.size() - 1)]["name"]


func _init(p_nav: BotNav, p_knowledge: BotKnowledge, skill_index: int = Skill.NORMAL) -> void:
	nav = p_nav
	knowledge = p_knowledge
	skill = SKILLS[clampi(skill_index, 0, SKILLS.size() - 1)]


func sight() -> int:
	return skill["sight"]


## Speed (fraction of MOVE_SPEED) a LEADER may use given the highest rope
## tension in its pod: full speed while the ropes are loose, easing to a
## stop over SLOW_BAND once tension passes this skill's slack.
func leader_speed(pod_tension: float) -> float:
	var t := clampf((pod_tension - float(skill["slack"])) / SLOW_BAND, 0.0, 1.0)
	return float(skill["speed"]) * (1.0 - t)


## One tick. `goal_pos` is where to end up (a cell centre for fixed goals,
## the target's real position when following). `stop_px` > 0 makes this a
## follower that holds at that distance; 0 walks all the way onto the goal.
## Returns {"dir": Vector2, "speed": float, "state": "go"|"hold"|"arrived"|"blocked"}.
func steer(pos: Vector2, goal_pos: Vector2, speed: float, stop_px: float, delta: float) -> Dictionary:
	var here := nav.cell_of(pos)
	var goal_cell := nav.cell_of(goal_pos)
	_track_stuck(pos, delta)

	_repath_in -= delta
	if goal_cell != _goal or _repath_in <= 0.0 or not _path.has(here):
		_goal = goal_cell
		_path = knowledge.path(here, goal_cell)
		_repath_in = REPATH_EVERY

	if _path.is_empty():
		# No route through cells this team has mapped (the target may be
		# somewhere not looked at yet). If it is close, just walk at it;
		# otherwise wait for exploration to catch up.
		var d := pos.distance_to(goal_pos)
		if d < nav.tile * 4.0 and d > maxf(stop_px, ARRIVE_PX):
			return _go((goal_pos - pos).normalized(), speed)
		return _stop("blocked")

	var remaining := _remaining_px(pos, here, goal_pos)
	if stop_px > 0.0:
		if _holding:
			if remaining > stop_px + (HOLD_RESUME_PX - HOLD_PX):
				_holding = false
		elif remaining <= stop_px:
			_holding = true
		if _holding:
			return _stop("hold")
	elif remaining <= ARRIVE_PX:
		return _stop("arrived")

	var to := _steer_point(pos, here, goal_pos) - pos
	if to.length() < 0.4:
		to = goal_pos - pos
	return _go(to.normalized(), speed)


# ---------------------------------------------------------------------------

func _go(dir: Vector2, speed: float) -> Dictionary:
	_wanted_move = dir != Vector2.ZERO and speed > 0.01
	return {"dir": dir, "speed": speed, "state": "go"}


func _stop(state: String) -> Dictionary:
	_wanted_move = false
	return {"dir": Vector2.ZERO, "speed": 0.0, "state": state}


## Walking distance left, following the cached path.
func _remaining_px(pos: Vector2, here: Vector2i, goal_pos: Vector2) -> float:
	var idx := _path.find(here)
	if idx == -1:
		return pos.distance_to(goal_pos)
	var left := _path.size() - 1 - idx
	if left <= 0:
		return pos.distance_to(goal_pos)
	return pos.distance_to(nav.center_of(_path[idx + 1])) \
		+ float(left - 1) * nav.tile \
		+ nav.center_of(_path[-1]).distance_to(goal_pos)


## Where to aim this tick. Walks cell centre to cell centre, but first
## squares up with the corridor's centre line so a turn is taken from the
## middle of the corner cell instead of clipping the wall.
func _steer_point(pos: Vector2, here: Vector2i, goal_pos: Vector2) -> Vector2:
	if _nudge_t > 0.0:
		return nav.center_of(here)
	var idx := _path.find(here)
	if idx == -1 or idx >= _path.size() - 1:
		return goal_pos
	var c_here := nav.center_of(_path[idx])
	var c_next := nav.center_of(_path[idx + 1])
	var move := c_next - c_here
	var off_line: float = absf(pos.y - c_here.y) if absf(move.x) > absf(move.y) else absf(pos.x - c_here.x)
	if off_line > CENTRE_TOL:
		return c_here
	return c_next


## If the bot keeps asking to move but is not going anywhere (wedged on a
## corner), re-route and aim for its cell centre for a moment.
func _track_stuck(pos: Vector2, delta: float) -> void:
	if _nudge_t > 0.0:
		_nudge_t -= delta
	if _wanted_move and _last_pos != Vector2.INF and pos.distance_to(_last_pos) < 0.05:
		_still_t += delta
	else:
		_still_t = 0.0
	_last_pos = pos
	if _still_t > STUCK_AFTER:
		_still_t = 0.0
		_nudge_t = 0.5
		_repath_in = 0.0
