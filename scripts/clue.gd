class_name Clue
extends Area2D
## Clue
## A single fragment pickup in the world. Stays in the world after
## being read (not consumed) so a pod that lost its notebook in a
## split can walk back and re-read it (design doc section 3.9).

@export var fragment_id: int = -1
@export var symbol: String = "?"

@onready var sprite: Sprite2D = $Sprite2D
@onready var label: Label = $Label


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body is Player and body.is_local:
		NetRouter.request_read_fragment(fragment_id)


func show_symbol(s: String) -> void:
	symbol = s
	if label:
		label.text = s
		label.visible = true
