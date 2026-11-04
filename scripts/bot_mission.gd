class_name BotMission
extends RefCounted
## BotMission
## Decides what a bot-led pod's leader is trying to do right now, from plain
## data only (no nodes), so it can be unit-tested. Priority order, which is
## also the order the match is played in:
##
##   1. pod has unlocked the exit      -> EXIT   (if the gate has been found)
##   2. pod has read every fragment    -> CONSOLE (unlocks the exit)
##   3. a known, unread fragment       -> COLLECT (nearest by walking distance)
##   4. otherwise                      -> EXPLORE (nearest unexplored edge)
##   5. nothing left to do             -> WAIT
##
## "Known" means the team's BotKnowledge has seen it. Fragments are not
## looked up from the maze data.

enum Kind { COLLECT, CONSOLE, EXIT, EXPLORE, WAIT }

## ctx keys:
##   pos            Vector2   leader position
##   fragment_cells Array     Vector2i per fragment id
##   read           Dictionary fragment id -> true, the POD's combined notebook
##   total          int       number of fragments in the exit sequence
##   console_cell, exit_cell  Vector2i
##   unlocked       bool      pod has already opened the exit
##   prev           Dictionary {"kind", "cell"} from the last decision, or {}
static func choose(k: BotKnowledge, ctx: Dictionary) -> Dictionary:
	var nav: BotNav = k.nav
	var from: Vector2i = nav.cell_of(ctx["pos"])
	var read: Dictionary = ctx["read"]
	var prev: Dictionary = ctx.get("prev", {})

	if ctx["unlocked"]:
		if k.is_seen(ctx["exit_cell"]) and _reachable(k, from, ctx["exit_cell"]):
			return _goal(Kind.EXIT, ctx["exit_cell"])
	elif read.size() >= int(ctx["total"]):
		if _reachable(k, from, ctx["console_cell"]):
			return _goal(Kind.CONSOLE, ctx["console_cell"])
	else:
		var frag := _pick_fragment(k, from, ctx, prev)
		if frag != BotKnowledge.NONE:
			return _goal(Kind.COLLECT, frag)

	# Keep heading for the same unexplored edge until it has been explored,
	# otherwise two equally-near edges make the leader dither between them.
	if prev.get("kind", -1) == Kind.EXPLORE and k.is_frontier(prev["cell"]) and _reachable(k, from, prev["cell"]):
		return prev
	var edge := k.nearest_frontier(from)
	if edge != BotKnowledge.NONE:
		return _goal(Kind.EXPLORE, edge)
	return _goal(Kind.WAIT, from)


static func _pick_fragment(k: BotKnowledge, from: Vector2i, ctx: Dictionary, prev: Dictionary) -> Vector2i:
	var cells: Array = ctx["fragment_cells"]
	var read: Dictionary = ctx["read"]

	# Sticky: finish walking to the fragment we already chose.
	if prev.get("kind", -1) == Kind.COLLECT:
		var id: int = cells.find(prev["cell"])
		if id != -1 and not read.has(id) and _reachable(k, from, prev["cell"]):
			return prev["cell"]

	var best := BotKnowledge.NONE
	var best_len := 1 << 30
	for id in range(cells.size()):
		if read.has(id):
			continue
		var c: Vector2i = cells[id]
		if not k.is_seen(c):
			continue
		var p := k.path(from, c)
		if p.is_empty():
			continue
		if p.size() < best_len:
			best_len = p.size()
			best = c
	return best


static func _reachable(k: BotKnowledge, from: Vector2i, to: Vector2i) -> bool:
	return from == to or not k.path(from, to).is_empty()


static func _goal(kind: int, cell: Vector2i) -> Dictionary:
	return {"kind": kind, "cell": cell}
