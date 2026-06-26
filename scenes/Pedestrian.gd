extends Area3D
class_name Pedestrian
## A person crossing the road that the player must avoid.
##
## Uses the custom Meshy `man.glb`, auto-fitted by ModelUtil (swap the model
## below for a different figure any time).
##
## It lives in the "traffic" group on collision layer 2, so the Player's
## existing `_on_area_entered` already treats touching one as a crash (and a
## shield absorbs it) with ZERO new collision code.
##
## Movement toward the player (the treadmill scroll) is handled centrally in
## Game.gd's _scroll_traffic, just like vehicles. This script only adds the
## gentle sideways WALK and a little bob, so it feels alive.

# The walking person. ModelUtil scales it to roughly human height and grounds it.
const PEDESTRIAN_MODEL := preload("res://models/custom/man.glb")
# Rotate the model so it faces across the road. Tune in 90 steps if it ends up
# facing the wrong way.
const PEDESTRIAN_YAW := 0.0
const PEDESTRIAN_HEIGHT := 1.7

## Sideways walk speed in world units/second (set by Game at spawn; sign chooses
## the direction). Kept small on purpose so the guaranteed safe lane stays open
## long enough for the player to slip through - fairness is preserved.
var walk_speed := 0.0

## Forward drive speed, like a vehicle. Pedestrians don't drive, so this stays 0,
## which means Game's _scroll_traffic carries them toward the player at the full
## world scroll speed (they share the traffic pipeline for movement + collision).
var drive_speed := 0.0

# Child node holding the visible figure, so we can bob it without fighting the
# curvy-world path code (which drives the ROOT node's x/y via the bx/by metas).
var _figure: Node3D
var _bob := 0.0
# Lane centre we spawned on; the walk drifts around it but never strays far
# enough to wander into the (always-open) safe lane - fairness is preserved.
var _origin_x := 0.0
const WALK_RANGE := 0.8   # max sideways drift from the spawn lane (world units)


func _ready() -> void:
	# Same group + layer as a vehicle, so hitting one is a normal "traffic" crash.
	add_to_group("traffic")
	collision_layer = 2
	collision_mask = 0
	monitoring = false   # the player detects us; we don't detect anything

	_build_figure()

	# Box collider roughly the size of a person, standing on the road.
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.55, 1.7, 0.55)
	shape.shape = box
	shape.position.y = 0.85
	add_child(shape)

	# Random start phase so a row of pedestrians doesn't bob in lockstep.
	_bob = randf() * TAU
	_origin_x = get_meta("bx", position.x)


## Drop in the man model, auto-fitted to human height under a holder we can bob.
func _build_figure() -> void:
	_figure = Node3D.new()
	add_child(_figure)
	ModelUtil.instance_fitted(
		_figure, PEDESTRIAN_MODEL,
		Vector3(0.5, PEDESTRIAN_HEIGHT, 0.5), "height", PEDESTRIAN_YAW)


func _process(delta: float) -> void:
	# Walk sideways by drifting our BASE x (the "bx" meta). Game's _apply_path
	# adds the curvy-world offset on top, so the walk and the bends compose.
	# Reverse at the edge of WALK_RANGE so the pedestrian paces within its lane
	# and never wanders into the safe lane.
	var bx: float = get_meta("bx", position.x)
	bx += walk_speed * delta
	if absf(bx - _origin_x) > WALK_RANGE:
		bx = _origin_x + signf(bx - _origin_x) * WALK_RANGE
		walk_speed = -walk_speed
	set_meta("bx", bx)

	# A gentle up/down bob on the figure only (the root y is owned by _apply_path).
	_bob += delta * 6.0
	_figure.position.y = absf(sin(_bob)) * 0.06
