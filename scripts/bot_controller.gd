class_name BotController
extends Node
## BotController
## Drives every bot in an offline match. Lives under the Game scene next to
## the TetherSystem and runs on the host (which is everyone, offline).
##
## Each tick, per pod (a pod is a connected group after any snaps):
##   * LEADER: the human if the pod has one, otherwise the first living
##     member in chain order. A bot leader runs BotMission (collect
##     fragments -> console -> exit, exploring when it knows nothing) and
##     slows with the pod's rope tension.
##   * FOLLOWERS: each follows its chain neighbour on the side of the
##     leader, so the pod trails out as one snake instead of everyone
##     crowding the leader. Once the exit is open and the leader is near
##     it, followers walk onto the gate too (the whole pod must be inside
##     it at once to score).
##
## Bots only use what their team has seen (BotKnowledge) and the same
## notebook the pod's players share. They cannot read the maze for free.

const OBSERVE_EVERY := 1.0   # seconds; also re-observes whenever a player changes cell
const PLAN_EVERY := 0.4      # seconds between leader mission refreshes
const GATHER_PX := 64.0      # leader this close to an open exit -> followers join it

var game: Node               # GameController: player_nodes, tether_system, is_pod_unlocked()
var maze: MazeGenerator
var nav: BotNav
var knowledge: Dictionary = {}   # team_id -> BotKnowledge
var brains: Dictionary = {}      # bot peer_id -> BotBrain
var team_sight: Dictionary = {}  # team_id -> tiles

var last_plan: Dictionary = {}   # pod key -> {"kind", "cell"}  (read by tests / debugging)
var last_state: Dictionary = {}  # bot peer_id -> "go"/"hold"/"arrived"/"blocked"

var _plan_t: Dictionary = {}     # pod key -> seconds until the next mission refresh
var _last_cell: Dictionary = {}  # peer_id -> Vector2i
var _observe_t := 0.0


func setup(p_game: Node, p_maze: MazeGenerator) -> void:
	game = p_game
	maze = p_maze
	nav = BotNav.new(maze, GameState.TILE_SIZE)

	for team_id in GameState.teams:
		knowledge[team_id] = BotKnowledge.new(nav)
		team_sight[team_id] = 0
	for peer_id in game.player_nodes:
		if not GameState.is_bot(peer_id):
			continue
		var p: Player = game.player_nodes[peer_id]
		var skill_index: int = GameState.bots[peer_id].get("skill", BotBrain.Skill.NORMAL)
		var brain := BotBrain.new(nav, knowledge[p.team_id], skill_index)
		brains[peer_id] = brain
		team_sight[p.team_id] = maxi(team_sight[p.team_id], brain.sight())
	for team_id in team_sight:
		if team_sight[team_id] == 0:
			team_sight[team_id] = 3  # a team with no bots (nothing to look through) still gets a default
	_observe_all(true)


func _physics_process(delta: float) -> void:
	_observe_t -= delta
	_observe_all(_observe_t <= 0.0)
	if _observe_t <= 0.0:
		_observe_t = OBSERVE_EVERY
	_drive(delta)


func _observe_all(force: bool) -> void:
	for peer_id in game.player_nodes:
		var p: Player = game.player_nodes[peer_id]
		if p.eliminated or not knowledge.has(p.team_id):
			continue
		var cell := nav.cell_of(p.position)
		if force or _last_cell.get(peer_id, Vector2i(-9, -9)) != cell:
			_last_cell[peer_id] = cell
			knowledge[p.team_id].observe(p.position, team_sight[p.team_id])


func _drive(delta: float) -> void:
	var driven := {}
	for pod in GameState.pods:
		var members := _chain_members(pod)
		if members.is_empty():
			continue
		var key := _pod_key(members)
		var has_human := members.has(GameState.human_id)
		var leader_id: int = GameState.human_id if has_human else members[0]
		var leader: Player = game.player_nodes[leader_id]
		var team_id: int = leader.team_id
		var tension := _pod_tension(members)
		var unlocked: bool = game.is_pod_unlocked(members)
		var exit_pos := nav.center_of(maze.exit_cell)
		var gather := unlocked and leader.position.distance_to(exit_pos) < GATHER_PX
		var li := members.find(leader_id)

		for i in range(members.size()):
			var id: int = members[i]
			if not GameState.is_bot(id):
				continue
			driven[id] = true
			var brain: BotBrain = brains[id]
			var me: Player = game.player_nodes[id]
			var out: Dictionary
			if id == leader_id:
				var plan := _leader_plan(key, members, team_id, leader.position, unlocked, delta)
				var goal_pos := nav.center_of(plan["cell"])
				var speed := brain.leader_speed(tension) if plan["kind"] != BotMission.Kind.WAIT else 0.0
				out = brain.steer(me.position, goal_pos, speed, 0.0, delta)
			elif gather:
				out = brain.steer(me.position, exit_pos, 1.0, 0.0, delta)
			else:
				var follow_id: int = members[i - 1] if i > li else members[i + 1]
				out = brain.steer(me.position, game.player_nodes[follow_id].position, 1.0, BotBrain.HOLD_PX, delta)
			me.set_input(out["dir"])
			me.speed_scale = out["speed"] if out["dir"] != Vector2.ZERO else 1.0
			last_state[id] = out["state"]

	# Bots in no pod (eliminated) just stop.
	for id in brains:
		if not driven.has(id):
			game.player_nodes[id].set_input(Vector2.ZERO)


## Living members of a pod in chain order (the order they were tethered).
func _chain_members(pod: Array) -> Array:
	var any_id: int = pod[0]
	var team_id: int = game.player_nodes[any_id].team_id
	var order: Array = GameState.teams[team_id]["member_order"]
	return order.filter(func(id): return pod.has(id) and game.player_nodes.has(id) and not game.player_nodes[id].eliminated)


func _pod_key(members: Array) -> String:
	return ",".join(members.map(func(x): return str(x)))


func _pod_tension(members: Array) -> float:
	var worst := 0.0
	for link in game.tether_system.links:
		if link.alive and members.has(link.a_id) and members.has(link.b_id):
			worst = maxf(worst, link.tension)
	return worst


func _pod_read(members: Array) -> Dictionary:
	var read := {}
	for id in members:
		for frag_id in GameState.notebook.get(id, {}):
			read[frag_id] = true
	return read


func _leader_plan(key: String, members: Array, team_id: int, pos: Vector2, unlocked: bool, delta: float) -> Dictionary:
	_plan_t[key] = _plan_t.get(key, 0.0) - delta
	if _plan_t[key] > 0.0 and last_plan.has(key):
		return last_plan[key]
	_plan_t[key] = PLAN_EVERY
	var plan := BotMission.choose(knowledge[team_id], {
		"pos": pos,
		"fragment_cells": maze.fragment_cells,
		"read": _pod_read(members),
		"total": GameState.exit_sequence.size(),
		"console_cell": maze.console_cell,
		"exit_cell": maze.exit_cell,
		"unlocked": unlocked,
		"prev": last_plan.get(key, {}),
	})
	last_plan[key] = plan
	return plan
