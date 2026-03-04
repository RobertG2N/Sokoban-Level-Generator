extends Node2D

@onready var box_up: RayCast2D = $boxUp
@onready var box_up_2: RayCast2D = $boxUp2
@onready var box_down: RayCast2D = $boxDown
@onready var box_down_2: RayCast2D = $boxDown2
@onready var box_left: RayCast2D = $boxLeft
@onready var box_left_2: RayCast2D = $boxLeft2
@onready var box_right: RayCast2D = $boxRight
@onready var box_right_2: RayCast2D = $boxRight2
@onready var box: Node2D = $"."

const UP = Vector2(0,-16)
const DOWN = Vector2(0,16)
const LEFT = Vector2(-16,0)
const RIGHT = Vector2(16,0)
var can_move = true
signal move_back(direction: Vector2)

func notifyPlayer(direction: Vector2):
	emit_signal("move_back", direction)

func moveBox(direction: Vector2):
	box.position += direction

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	
	
	if box_down.is_colliding():
		if box_up_2.is_colliding(): 
			can_move = false
			notifyPlayer(DOWN)
		else: 
			can_move = true
		if can_move == false:
			return
		moveBox(UP)
		print("up")
		return
	
	
	if box_up.is_colliding():
		if box_down_2.is_colliding(): 
			can_move = false
			notifyPlayer(UP)
		else: 
			can_move = true
		if can_move == false:
			return
		moveBox(DOWN)
		print("down")
		return
	
	
	if box_left.is_colliding():
		if box_right_2.is_colliding(): 
			can_move = false
			notifyPlayer(LEFT)
		else: 
			can_move = true
		if can_move == false:
			return
		moveBox(RIGHT)
		print("right")
		return
	
	
	if box_right.is_colliding():
		if box_left_2.is_colliding(): 
			can_move = false
			notifyPlayer(RIGHT)
		else: 
			can_move = true
		if can_move == false:
			return
		moveBox(LEFT)
		print("left")
		return
