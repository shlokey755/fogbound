class_name CommentaryNode
extends Area2D
## CommentaryNode
## A single developer-commentary pickup, tucked into a maze dead end
## (see MazeGenerator.dead_end_cells()). Unlike Clue, this is purely
## cosmetic flavor text with no effect on the match -- so it needs no
## host authority or RPC at all. Every client places these nodes
## identically from the shared maze seed and reads them purely
## locally; only which notes a given PLAYER has seen is remembered
## (per-device, via SaveData), not which notes exist in the world.

signal activated(note: CommentaryData.Note)

@export var note_id: String = ""

@onready var icon: Label = $Icon


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	if icon:
		icon.text = "✎"  # small pencil/note glyph -- a hand-left note, not a game clue


func _on_body_entered(body: Node) -> void:
	if not (body is Player and body.is_local):
		return
	var note: CommentaryData.Note = CommentaryData.get_note(note_id)
	if note == null:
		return
	SaveData.mark_commentary_seen(note_id)
	activated.emit(note)
