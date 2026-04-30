extends Node2D

## Handles grid-based player movement and receives signals from boxes when a push is blocked.
## The script keeps movement aligned to the Sokoban tile size and switches collision checks
## depending on the direction the player last moved.

# TileMap is kept so the player can share the same grid context as the generated level.
@onready var tile_map: TileMap = $"../TileMap"

# Directional raycasts check whether the next tile is blocked before movement is applied.
@onready var down: RayCast2D = $Down
@onready var left: RayCast2D = $Left
@onready var up: RayCast2D = $Up
@onready var right: RayCast2D = $Right

# Directional collision shapes are enabled/disabled so boxes can detect which side
# of the player is currently pushing them.
@onready var up_collider: CollisionShape2D = $StaticBody2D/UpCollider
@onready var down_collider: CollisionShape2D = $StaticBody2D/DownCollider
@onready var left_collider: CollisionShape2D = $StaticBody2D/LeftCollider
@onready var right_collider: CollisionShape2D = $StaticBody2D/RightCollider

# Sprite reference used to flip the player visually when moving left or right.
@onready var sprite_2d: Sprite2D = $Sprite2D

# Stores the player's position when needed by other movement/grid logic.
var playerPos: Vector2 

# One-tile movement offsets. The project uses a 16 pixel grid.
const UP = Vector2(0,-16)
const DOWN = Vector2(0,16)
const LEFT = Vector2(-16,0)
const RIGHT = Vector2(16,0)

# Grid conversion values kept for compatibility with the generated TileMap layout.
var localPos
var tile_coords: Vector2i

# Prevents overlapping movement checks during the same physics frame.
var is_moving: bool = false

# Set by box signals. False prevents the player from moving through a box that failed to move.
var can_move: bool = true

# Called when the node enters the scene tree for the first time.
## Sets the initial push direction state when the player enters the scene.
func _ready() -> void:
	down_collider.disabled = false
	up_collider.disabled = true
	left_collider.disabled = true
	right_collider.disabled = true

## Receives the box movement result and controls whether the player is allowed to move.
## This is used when a box push is blocked so the player does not pass through the box.
func _on_can_box_move(notifier: bool):
	can_move = notifier


# Called every frame. 'delta' is the elapsed time since the previous frame.
## Reads movement input and moves the player by exactly one grid cell when the target tile is clear.
## Each direction also enables the collider used for box-push detection from that side.
func _physics_process(delta: float) -> void:

	if is_moving:
		return
	if Input.is_action_just_pressed("up") and !up.is_colliding() and can_move:
		is_moving = true
		down_collider.disabled = false
		up_collider.disabled = true
		left_collider.disabled = true
		right_collider.disabled = true
		self.position += UP
		is_moving = false
		return
		
	if Input.is_action_just_pressed("down") and !down.is_colliding() and can_move:
		is_moving = true
		up_collider.disabled = false
		down_collider.disabled = true
		left_collider.disabled = true
		right_collider.disabled = true
		self.position += DOWN
		is_moving = false
		return
		
	if Input.is_action_just_pressed("left") and !left.is_colliding() and can_move :
		sprite_2d.flip_h = true
		is_moving = true
		right_collider.disabled = true
		up_collider.disabled = true
		down_collider.disabled = true
		left_collider.disabled = false
		self.position += LEFT
		is_moving = false
		return
	
	if Input.is_action_just_pressed("right") and !right.is_colliding() and can_move:
		sprite_2d.flip_h = false
		is_moving = true
		left_collider.disabled = true
		right_collider.disabled = false
		up_collider.disabled = true
		down_collider.disabled = true
		self.position += RIGHT
		is_moving = false
		return

## Moves the player back after a box reports that it could not be pushed.
## The direction is supplied by the box signal so the player returns to the previous tile.
func _on_box_move_back(direction):
	self.position += direction
