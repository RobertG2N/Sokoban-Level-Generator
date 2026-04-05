extends Node2D

@onready var box_up: RayCast2D = $boxUp
@onready var box_up_2: RayCast2D = $boxUp2
@onready var box_down: RayCast2D = $boxDown
@onready var box_down_2: RayCast2D = $boxDown2
@onready var box_left: RayCast2D = $boxLeft
@onready var box_left_2: RayCast2D = $boxLeft2
@onready var box_right: RayCast2D = $boxRight
@onready var box_right_2: RayCast2D = $boxRight2
@onready var box = self

@export var closed_chest: Texture2D
@export var open_chest: Texture2D
@onready var sprite_2d: Sprite2D = $Sprite2D

const UP = Vector2(0, -16)
const DOWN = Vector2(0, 16)
const LEFT = Vector2(-16, 0)
const RIGHT = Vector2(16, 0)

var push_locked := false
signal move_back(direction: Vector2)

func notifyPlayer(direction: Vector2):
	emit_signal("move_back", direction)

func moveBox(direction: Vector2):
	box.position += direction

func _ready() -> void:
	sprite_2d.texture = closed_chest
	var emitter_node = get_parent()
	emitter_node.connect("on_goal", _on_on_goal_signal_received)
	emitter_node.connect("left_goal", _on_left_goal_signal_received)

func _on_on_goal_signal_received(box_pass):
	print("signal box = ", box, " self = ", self)
	if box_pass != self:
		return
	_open_chest(true)

func _on_left_goal_signal_received(box_pass):
	if box_pass != self:
		return
	_open_chest(false)

func _open_chest(open: bool) -> void:
	sprite_2d.texture = open_chest if open else closed_chest

func _physics_process(_delta: float) -> void:
	if push_locked:
		if not box_down.is_colliding() and not box_up.is_colliding() and not box_left.is_colliding() and not box_right.is_colliding():
			push_locked = false
		return

	if box_down.is_colliding():
		if box_up_2.is_colliding():
			notifyPlayer(DOWN)
			push_locked = true
			return
		moveBox(UP)
		push_locked = true
		return

	if box_up.is_colliding():
		if box_down_2.is_colliding():
			notifyPlayer(UP)
			push_locked = true
			return
		moveBox(DOWN)
		push_locked = true
		return

	if box_left.is_colliding():
		if box_right_2.is_colliding():
			notifyPlayer(LEFT)
			push_locked = true
			return
		moveBox(RIGHT)
		push_locked = true
		return

	if box_right.is_colliding():
		if box_left_2.is_colliding():
			notifyPlayer(RIGHT)
			push_locked = true
			return
		moveBox(LEFT)
		push_locked = true
		return
