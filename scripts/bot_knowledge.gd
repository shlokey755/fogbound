class_name BotKnowledge
extends RefCounted
## BotKnowledge
## What one bot team has actually seen of the maze. Bots are fog-fair: they
## do not get the layout for free. Every cell they have line of sight to
## (within their sight radius) is remembered, and ALL path planning runs on
## the remembered floor only -- so a bot cannot take a shortcut through a
## corridor it has never looked at, and it has to explore to find
## fragments and the exit, the same as a human does.
##
## One instance per team (pods of one team share what they have seen; they
## walked out of the same fog room together).

const NONE := Vector2i(-1, -1)
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

var nav: BotNav
var seen: Dictionary = {}      # Vector2i -> true (floor and wall cells both)
var floor_known: int = 0
var astar := AStarGrid2D.new() # solid everywhere except remembered floor


func _init(p_nav: BotNav) -> void:
	nav = p_nav
	var m := nav.maze
	astar.region = Rect2i(0, 0, m.w, m.h)
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	astar.fill_solid_region(astar.region, true)


## Remember everything in line of sight within `radius_tiles` of `pos`.
func observe(pos: Vector2, radius_tiles: int) -> void:
	var c0 := nav.cell_of(pos)
	var r2 := radius_tiles * radius_tiles
	for dy in range(-radius_tiles, radius_tiles + 1):
		for dx in range(-radius_tiles, radius_tiles + 1):
			if dx * dx + dy * dy > r2:
				continue
			var c := Vector2i(c0.x + dx, c0.y + dy)
			if seen.has(c) or not nav.in_bounds(c):
				continue
			if (dx == 0 and dy == 0) or nav.can_see(pos, c):
				_mark(c)


func _mark(c: Vector2i) -> void:
	seen[c] = true
	if nav.maze.is_floor(c.x, c.y):
		astar.set_point_solid(c, false)
		floor_known += 1


func is_seen(c: Vector2i) -> bool:
	return seen.has(c)


func _is_open(c: Vector2i) -> bool:
	return nav.in_bounds(c) and not astar.is_point_solid(c)


## Known-floor path (inclusive of both ends), or [] if there isn't one
## through cells this team has seen.
func path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not _is_open(from) or not _is_open(to):
		return out
	if from == to:
		out.append(from)
		return out
	out.assign(astar.get_id_path(from, to))
	return out


## A known floor cell next to something not yet looked at.
func is_frontier(c: Vector2i) -> bool:
	if not _is_open(c):
		return false
	for d in DIRS:
		var n := c + d
		if nav.in_bounds(n) and not seen.has(n):
			return true
	return false


## Breadth-first search over known floor for the closest frontier cell
## (never `from` itself, unless it is the only one). NONE if everything
## reachable has been explored.
func nearest_frontier(from: Vector2i) -> Vector2i:
	if not _is_open(from):
		return NONE
	var queue: Array[Vector2i] = [from]
	var visited := {from: true}
	var head := 0
	while head < queue.size():
		var cur: Vector2i = queue[head]
		head += 1
		if cur != from and is_frontier(cur):
			return cur
		for d in DIRS:
			var n: Vector2i = cur + d
			if visited.has(n) or not _is_open(n):
				continue
			visited[n] = true
			queue.append(n)
	return from if is_frontier(from) else NONE


func explored_fraction() -> float:
	var total := 0
	for y in range(nav.maze.h):
		for x in range(nav.maze.w):
			if nav.maze.is_floor(x, y):
				total += 1
	return float(floor_known) / float(maxi(total, 1))
