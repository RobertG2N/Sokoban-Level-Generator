extends Node2D

@onready var tile_map: TileMap = $"../TileMap"
@onready var down: RayCast2D = $Down
@onready var left: RayCast2D = $Left
@onready var up: RayCast2D = $Up
@onready var right: RayCast2D = $Right
@onready var up_collider: CollisionShape2D = $StaticBody2D/UpCollider
@onready var down_collider: CollisionShape2D = $StaticBody2D/DownCollider
@onready var left_collider: CollisionShape2D = $StaticBody2D/LeftCollider
@onready var right_collider: CollisionShape2D = $StaticBody2D/RightCollider


var playerPos: Vector2 
const UP = Vector2(0,-16)
const DOWN = Vector2(0,16)
const LEFT = Vector2(-16,0)
const RIGHT = Vector2(16,0)
var localPos
var tile_coords: Vector2i
var is_moving: bool = false
var can_move: bool = true

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	up_collider.disabled = true
	down_collider.disabled = true
	left_collider.disabled = true
	right_collider.disabled = true
func _on_can_box_move(notifier: bool):
	can_move = notifier
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:

	if is_moving:
		return
	if Input.is_action_just_pressed("ui_up") and !up.is_colliding() and can_move:
		is_moving = true
		down_collider.disabled = false
		up_collider.disabled = true
		left_collider.disabled = true
		right_collider.disabled = true
		self.position += UP
		is_moving = false
		return
		
	if Input.is_action_just_pressed("ui_down") and !down.is_colliding() and can_move:
		is_moving = true
		up_collider.disabled = false
		down_collider.disabled = true
		left_collider.disabled = true
		right_collider.disabled = true
		self.position += DOWN
		is_moving = false
		return
		
	if Input.is_action_just_pressed("ui_left") and !left.is_colliding() and can_move :
		is_moving = true
		right_collider.disabled = false
		up_collider.disabled = true
		down_collider.disabled = true
		left_collider.disabled = true
		self.position += LEFT
		is_moving = false
		return
	
	if Input.is_action_just_pressed("ui_right") and !right.is_colliding() and can_move:
		is_moving = true
		left_collider.disabled = false
		right_collider.disabled = true
		up_collider.disabled = true
		down_collider.disabled = true
		self.position += RIGHT
		is_moving = false
		return


func _on_box_move_back(direction):
	self.position += direction/2
