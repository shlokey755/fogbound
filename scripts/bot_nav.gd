class_name BotNav
extends RefCounted
## BotNav
## Grid helpers shared by the bot code: world <-> cell conversion and a
## line-of-sight test over the maze. No scene dependency, so the bot logic
## can be unit-tested with plain `--script` tests (tests/test_bots.gd).

var maze: MazeGenerator
var tile: float = 16.0


func _init(p_maze: MazeGenerator = null, p_tile: float = 16.0) -> void:
	maze = p_maze
	tile = p_tile


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(int(floorf(p.x / tile)), int(floorf(p.y / tile)))


func center_of(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * tile


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < maze.w and c.y < maze.h


## True when a straight line from world point `from` to the centre of
## `to_cell` crosses no wall before reaching it. The target itself may be a
## wall (a bot can see a wall face), which is how a bot learns that a cell
## is solid rather than just "not looked at yet".
func can_see(from: Vector2, to_cell: Vector2i) -> bool:
	var target := center_of(to_cell)
	var steps := int(from.distance_to(target) / (tile * 0.25)) + 1
	for i in range(steps + 1):
		var c := cell_of(from.lerp(target, float(i) / float(steps)))
		if c == to_cell:
			return true
		if not maze.is_floor(c.x, c.y):
			return false
	return true
