extends Control
## TouchJoystick
## Minimal on-screen virtual joystick for mobile input (design doc
## section 5.8). Emits a normalized direction via NetRouter.send_input
## every frame it's held; the owning Player also reads it directly
## when running in a single local process (offline testing).

signal direction_changed(dir: Vector2)

@export var max_radius: float = 30.0
@onready var base: Control = $Base
@onready var knob: Control = $Base/Knob

var _touch_index := -1
var _origin := Vector2.ZERO
var current_dir: Vector2 = Vector2.ZERO


func _ready() -> void:
	knob.position = base.size * 0.5 - knob.size * 0.5


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch_index == -1:
			_touch_index = event.index
			_origin = event.position
		elif not event.pressed and event.index == _touch_index:
			_touch_index = -1
			current_dir = Vector2.ZERO
			knob.position = base.size * 0.5 - knob.size * 0.5
			direction_changed.emit(current_dir)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		var delta: Vector2 = event.position - _origin
		var clamped: Vector2 = delta.limit_length(max_radius)
		knob.position = base.size * 0.5 - knob.size * 0.5 + clamped
		current_dir = clamped / max_radius
		direction_changed.emit(current_dir)


func _process(_delta: float) -> void:
	if current_dir != Vector2.ZERO or _touch_index != -1:
		NetRouter.send_input(current_dir)
