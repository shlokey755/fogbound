class_name CommentarySpawner
extends Node2D
## CommentarySpawner
## Instantiates developer-commentary pickups at the dead-end cells
## MazeGenerator chose (identical on every client, same seed). Each
## maze gets a handful of notes assigned round-robin from
## CommentaryData so repeat matches don't always surface the exact
## same note in the exact same spot.

const CommentaryNodeScene := preload("res://scenes/commentary_node.tscn")

signal note_activated(note: CommentaryData.Note)


func spawn(maze: MazeGenerator, match_seed: int) -> void:
	if maze.commentary_cells.is_empty() or CommentaryData.notes.is_empty():
		return

	# Which notes appear (and in what order) is itself seeded, so
	# every client's maze shows the same notes in the same dead ends
	# -- purely cosmetic, but still worth keeping deterministic so
	# teammates can talk about "the note by the east dead end"
	# and mean the same thing.
	var rng := RandomNumberGenerator.new()
	rng.seed = match_seed + 2  # +1 is already used by the exit-sequence RNG in game_controller.gd
	var note_ids: Array = CommentaryData.notes.map(func(n): return n.id)
	var shuffled := note_ids.duplicate()
	for i in range(shuffled.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = tmp

	for i in range(maze.commentary_cells.size()):
		var cell: Vector2i = maze.commentary_cells[i]
		var node_scene := CommentaryNodeScene.instantiate()
		node_scene.note_id = shuffled[i % shuffled.size()]
		node_scene.position = Vector2(
			(cell.x + 0.5) * GameState.TILE_SIZE,
			(cell.y + 0.5) * GameState.TILE_SIZE
		)
		node_scene.activated.connect(func(note): note_activated.emit(note))
		add_child(node_scene)
