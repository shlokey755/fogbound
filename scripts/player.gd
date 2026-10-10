class_name Player
extends CharacterBody2D
## Player
## A single player's body. Movement input is sent by the owning
## client to the host (net_router.gd); the host is authoritative over
## position and broadcasts snapshots back out. pull_velocity/pull_cap
## are written by TetherSystem (host-only) each physics tick.

@export var peer_id: int = 1
@export var team_id: int = 0

var pull_velocity: Vector2 = Vector2.ZERO
var pull_cap: float = 0.0  # fraction of MOVE_SPEED allowed this tick, set by TetherSystem

var input_dir: Vector2 = Vector2.ZERO
var is_local: bool = false
var in_fog: bool = false
var carrying_lantern: bool = false
var eliminated: bool = false

@onready var light: PointLight2D = $PointLight2D
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $PeerLabel


func _ready() -> void:
	is_local = (peer_id == multiplayer.get_unique_id()) or (not multiplayer.has_multiplayer_peer())
	if label:
		label.text = str(peer_id)
	_update_light_radius()


func _physics_process(delta: float) -> void:
	if eliminated:
		return

	# Desktop dev convenience: WASD/arrow keys drive the locally-owned
	# player directly, so you can test with "Run multiple instances"
	# without touching a touchscreen. See docs/WALKTHROUGH.md "Testing".
	if is_local:
		var dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
		if dir != Vector2.ZERO:
			if GameState.is_host():
				set_input(dir)
			else:
				NetRouter.send_input(dir)

	# Host (or offline single-process testing) applies real movement +
	# tether pull. Non-host clients just interpolate toward replicated
	# snapshots (handled by net_router's snapshot apply, not here).
	if GameState.is_host() or not multiplayer.has_multiplayer_peer():
		var move: Vector2 = input_dir.normalized() * GameState.MOVE_SPEED
		var capped_pull: Vector2 = pull_velocity.limit_length(pull_cap * GameState.MOVE_SPEED)
		velocity = move + capped_pull
		move_and_slide()

	pull_velocity -= pull_velocity * GameState.TETHER_PULL_FRICTION * delta
	pull_cap = 0.0

	_update_light_radius()


func set_input(dir: Vector2) -> void:
	input_dir = dir


func _update_light_radius() -> void:
	if not light:
		return
	var base: float = GameState.VISION_FOG if in_fog else GameState.VISION_NORMAL
	if carrying_lantern:
		base += GameState.LANTERN_BONUS
	var target_scale: float = base / 80.0  # texture authored for 80px (normal) radius at scale 1.0
	light.texture_scale = lerp(light.texture_scale, target_scale, 0.15)
