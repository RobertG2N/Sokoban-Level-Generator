extends CanvasLayer

## Handles the credits overlay.
## This scene is added on top of the current game scene and removed when the player closes it.

## Closes the credits menu when the button is pressed.
func _on_button_pressed() -> void:
	queue_free()
