extends Node2D
## FogController
## Owns the darkness layer (CanvasModulate) and toggles each player's
## `in_fog` flag based on overlap with the fog room Area2D. Actual
## vision falloff is handled per-player via PointLight2D + light.
## See design doc section 5.4.

@onready var fog_room_area: Area2D = $FogRoomArea

var _connected := false


## Called once by GameController after it has sized FogRoomArea's
## collision shape to match the generated maze's fog room rect.
## Safe to call multiple times (e.g. on a scene restart).
func setup() -> void:
	if _connected:
		return
	fog_room_area.body_entered.connect(_on_body_entered)
	fog_room_area.body_exited.connect(_on_body_exited)
	_connected = true


func _on_body_entered(body: Node) -> void:
	if body is Player:
		body.in_fog = true


func _on_body_exited(body: Node) -> void:
	if body is Player:
		body.in_fog = false
