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

const TEAM_SHADER := preload("res://shaders/team_palette.gdshader")

@onready var light: PointLight2D = $PointLight2D
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $PeerLabel

var _has_art := false          # false until a sprite sheet loads; the ColorRect placeholder shows meanwhile
var _last_pos := Vector2.ZERO  # for deriving facing/walking from actual motion (works on clients too)
var _facing := "down"          # "down" | "up" | "side"


func _ready() -> void:
	is_local = (peer_id == multiplayer.get_unique_id()) or (not multiplayer.has_multiplayer_peer())
	if label:
		label.text = str(peer_id)
	_setup_sprite()
	_update_light_radius()


## Character look comes from the peer id and scarf colour from the team
## id, so every client agrees with no extra networking. Falls back to the
## flat-colour placeholder if the PNGs haven't been imported yet.
func _setup_sprite() -> void:
	var character := PlayerSprites.character_for_peer(peer_id)
	if not PlayerSprites.has_art(character):
		return
	sprite.sprite_frames = PlayerSprites.build_frames(character)
	var mat := ShaderMaterial.new()
	mat.shader = TEAM_SHADER
	mat.set_shader_parameter("team_color", PlayerSprites.team_color(team_id))
	sprite.material = mat
	sprite.offset = Vector2(0, -2)  # feet sit near the bottom of the collision circle
	$ColorRect.visible = false
	_has_art = true
	_last_pos = position
	sprite.play("idle_down")


## Picks the animation from how the body actually moved this tick, so it
## behaves the same on the host and on clients (which only receive
## positions). "pulled" needs the tether's pull_velocity, which only the
## host/offline instance has, so clients show walk/idle there.
func _update_animation() -> void:
	if not _has_art:
		return
	var moved := position - _last_pos
	_last_pos = position
	var moving := moved.length() > 0.05
	if moving:
		if absf(moved.x) > absf(moved.y):
			_facing = "side"
			sprite.flip_h = moved.x < 0.0
		else:
			_facing = "up" if moved.y < 0.0 else "down"
			sprite.flip_h = false

	var anim: String
	if pull_velocity.length() > 8.0:
		anim = "pulled"
	elif moving:
		anim = "walk_" + _facing
	else:
		anim = "idle_" + _facing
	_play(anim)


func _play(anim: String) -> void:
	if sprite.animation != anim or not sprite.is_playing():
		sprite.play(anim)


func _physics_process(delta: float) -> void:
	if eliminated:
		if _has_art and sprite.animation != "eliminated":
			sprite.flip_h = false
			sprite.play("eliminated")
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

	_update_animation()
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
