extends Area2D

## Goal trigger used by the main controller script to detect when a box is on a goal tile.
## The goal itself does not contain completion logic, it stores its grid cell and
## lets the controller respond to Area2D body_entered/body_exited signals.


# Layout-local grid position of this goal. The controller sets this when the
# generated level is applied to the scene, so goal events can be tied back to
# the corresponding generated cell.
var cell: Vector2i
