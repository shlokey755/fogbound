class_name ClueSpawner
extends Node2D
## ClueSpawner
## Instantiates fragment clue objects at the positions chosen by
## MazeGenerator (already seeded, so identical on host and clients).
## Reading a fragment is reported to the host via RPC; see
## net_router.gd net_read_fragment().

const ClueScene := preload("res://scenes/clue.tscn")

var fragments: Dictionary = {}  # fragment_id (int) -> Node (Clue instance)


func spawn_fragments(maze: MazeGenerator) -> void:
	for i in range(maze.fragment_cells.size()):
		var cell: Vector2i = maze.fragment_cells[i]
		var clue := ClueScene.instantiate()
		clue.fragment_id = i
		clue.position = Vector2(
			(cell.x + 0.5) * GameState.TILE_SIZE,
			(cell.y + 0.5) * GameState.TILE_SIZE
		)
		add_child(clue)
		fragments[i] = clue


## Call when GameState.exit_sequence[i] becomes known to the LOCAL
## client (i.e. this client's pod has read fragment i), so the clue's
## visual can show its symbol. Purely cosmetic -- the host already
## knows the full sequence from the seed.
func reveal_symbol(fragment_id: int, symbol: String) -> void:
	if fragments.has(fragment_id):
		fragments[fragment_id].show_symbol(symbol)
