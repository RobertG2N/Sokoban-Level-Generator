extends Node2D

# RayCasts are placed on each side of the box to detect player contact and blocked movement.
# The first RayCast in a direction detects the player pushing the box.
# The second RayCast checks whether the opposite side is blocked by a wall or another object.
@onready var box_up: RayCast2D = $boxUp
@onready var box_up_2: RayCast2D = $boxUp2
@onready var box_down: RayCast2D = $boxDown
@onready var box_down_2: RayCast2D = $boxDown2
@onready var box_left: RayCast2D = $boxLeft
@onready var box_left_2: RayCast2D = $boxLeft2
@onready var box_right: RayCast2D = $boxRight
@onready var box_right_2: RayCast2D = $boxRight2

# Stored self-reference used when comparing signal arguments from the main controller.
@onready var box = self

# Textures used to show whether this box is currently on a goal tile.
@export var closed_chest: Texture2D
@export var open_chest: Texture2D
@onready var sprite_2d: Sprite2D = $Sprite2D

# One tile of movement in each grid direction. The project uses a 16-pixel tile size.
const UP = Vector2(0, -16)
const DOWN = Vector2(0, 16)
const LEFT = Vector2(-16, 0)
const RIGHT = Vector2(16, 0)

# Prevents the box from being pushed repeatedly while the same collision is still being detected.
var push_locked := false

# Sent to the player when a push is blocked so the player can step back out of the box.
signal move_back(direction: Vector2)

## Emits the blocked-push signal back to the player.
func notifyPlayer(direction: Vector2):
	emit_signal("move_back", direction)

## Moves the box by one grid cell in the requested direction.
func moveBox(direction: Vector2):
	box.position += direction

## Sets the starting sprite and connects this box to goal-state signals from the main controller.
func _ready() -> void:
	sprite_2d.texture = closed_chest
	var emitter_node = get_parent()
	emitter_node.connect("on_goal", _on_on_goal_signal_received)
	emitter_node.connect("left_goal", _on_left_goal_signal_received)

## Receives the main controller's goal-entered signal and opens this box if the signal is for it.
func _on_on_goal_signal_received(box_pass):
	print("signal box = ", box, " self = ", self)
	if box_pass != self:
		return
	_open_chest(true)

## Receives the main controller's goal-exited signal and closes this box if the signal is for it.
func _on_left_goal_signal_received(box_pass):
	if box_pass != self:
		return
	_open_chest(false)

## Switches the box sprite between its normal and on-goal appearance.
func _open_chest(open: bool) -> void:
	sprite_2d.texture = open_chest if open else closed_chest

## Handles box movement by checking which side the player is pushing from and whether the opposite side is blocked.
func _physics_process(_delta: float) -> void:
	# Wait until the current push collision has cleared before accepting another push.
	if push_locked:
		if not box_down.is_colliding() and not box_up.is_colliding() and not box_left.is_colliding() and not box_right.is_colliding():
			push_locked = false
		return
	
	# Player is pushing from below, so the box should move upward if the top side is free.
	if box_down.is_colliding():
		if box_up_2.is_colliding():
			notifyPlayer(DOWN)
			push_locked = true
			return
		moveBox(UP)
		push_locked = true
		return
	
	# Player is pushing from above, so the box should move downward if the bottom side is free.
	if box_up.is_colliding():
		if box_down_2.is_colliding():
			notifyPlayer(UP)
			push_locked = true
			return
		moveBox(DOWN)
		push_locked = true
		return
	
	# Player is pushing from the left, so the box should move right if the right side is free.
	if box_left.is_colliding():
		if box_right_2.is_colliding():
			notifyPlayer(LEFT)
			push_locked = true
			return
		moveBox(RIGHT)
		push_locked = true
		return
	
	# Player is pushing from the right, so the box should move left if the left side is free.
	if box_right.is_colliding():
		if box_left_2.is_colliding():
			notifyPlayer(RIGHT)
			push_locked = true
			return
		moveBox(LEFT)
		push_locked = true
		return
