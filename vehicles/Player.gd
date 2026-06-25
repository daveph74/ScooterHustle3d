extends Area3D
class_name Player
## The player's scooter.
##
## In this game the player NEVER moves forward by themselves - the world
## scrolls toward them (a classic endless-runner "treadmill"). So the only
## thing this script controls is the LEFT/RIGHT lane the scooter sits in.
##
## Input is read two ways:
##   * Keyboard (arrow keys / A / D) for testing on a PC.
##   * Touch swipes for playing on a phone.

## Emitted when the scooter hits a traffic vehicle.
signal crashed
## Emitted when a coin is picked up. Carries how many coins were collected.
signal coin_collected(amount: int)

# --- Lane layout (must match Game.gd) -------------------------------------
const LANE_WIDTH := 2.5     # distance between lane centres
const LANE_COUNT := 3
const MIDDLE_LANE := 1      # lanes are 0,1,2 - we start in the middle

# Which lane we are currently aiming for (0 = left, 1 = middle, 2 = right).
var current_lane := MIDDLE_LANE
# How quickly we slide between lanes. Set from the scooter's handling stat.
var lane_change_speed := 9.0
# Once we crash we stop responding to input.
var alive := true

# --- Swipe detection ------------------------------------------------------
var _touching := false
var _touch_start_x := 0.0
const SWIPE_MIN_PIXELS := 40.0   # how far a finger must move to count as a swipe


func _ready() -> void:
	# Build the low-poly scooter + rider out of simple primitives.
	_build_scooter()

	# Read the selected scooter's handling so better bikes feel snappier.
	var scooter := GameData.get_selected_scooter()
	if scooter:
		lane_change_speed = 7.0 * scooter.handling

	# Connect collisions. Because traffic and coins are also Area3D nodes,
	# we listen for "area_entered".
	area_entered.connect(_on_area_entered)

	# Snap to the starting lane immediately.
	position.x = _lane_to_x(current_lane)


## Convert a lane index (0,1,2) into a world X position.
func _lane_to_x(lane: int) -> float:
	return (lane - MIDDLE_LANE) * LANE_WIDTH


func _process(delta: float) -> void:
	if not alive:
		return

	# Keyboard testing controls.
	if Input.is_action_just_pressed("move_left"):
		change_lane(-1)
	if Input.is_action_just_pressed("move_right"):
		change_lane(1)

	# Smoothly slide toward the target lane (this is what makes lane changes
	# feel nice instead of teleporting).
	var target_x := _lane_to_x(current_lane)
	var t: float = clamp(lane_change_speed * delta, 0.0, 1.0)
	position.x = lerp(position.x, target_x, t)

	# Lean the scooter into the turn for a bit of flavour.
	var lean := (target_x - position.x) * 0.25
	rotation.z = lerp(rotation.z, lean, clamp(10.0 * delta, 0.0, 1.0))


## Move one lane left (dir = -1) or right (dir = +1), clamped to the road.
func change_lane(dir: int) -> void:
	var next_lane: int = clamp(current_lane + dir, 0, LANE_COUNT - 1)
	current_lane = next_lane


# --- Touch / swipe input --------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not alive:
		return

	if event is InputEventScreenTouch:
		# Cast to the specific event type so the compiler knows it has a
		# "position" property (otherwise the type can't be inferred).
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			# Finger went down - remember where.
			_touching = true
			_touch_start_x = touch.position.x
		else:
			_touching = false

	elif event is InputEventScreenDrag and _touching:
		# Finger is moving - did it travel far enough sideways to be a swipe?
		var drag := event as InputEventScreenDrag
		var dx := drag.position.x - _touch_start_x
		if absf(dx) > SWIPE_MIN_PIXELS:
			change_lane(1 if dx > 0.0 else -1)
			# Require lifting the finger before another swipe so one drag only
			# moves one lane.
			_touching = false


# --- Collisions -----------------------------------------------------------
func _on_area_entered(area: Area3D) -> void:
	if not alive:
		return
	if area.is_in_group("traffic"):
		_die()
	elif area.is_in_group("coin"):
		# Tell the coin to play its pickup animation, then count it.
		area.collect()
		coin_collected.emit(1)


func _die() -> void:
	alive = false
	crashed.emit()


# --- Building the scooter model (forward is -Z, so the front is at -Z) -----
func _build_scooter() -> void:
	var body := Color(0.85, 0.2, 0.25)        # red scooter paint
	var dark := Color(0.12, 0.12, 0.14)        # tyres / seat
	var helmet := Color(0.95, 0.82, 0.15)      # rider helmet

	# Floor deck the rider stands on.
	_box(Vector3(0.42, 0.12, 1.0), Vector3(0, 0.34, 0.05), body)
	# Rear body / engine cover.
	_box(Vector3(0.46, 0.5, 0.7), Vector3(0, 0.6, 0.35), body)
	# Seat.
	_box(Vector3(0.42, 0.16, 0.5), Vector3(0, 0.86, 0.4), dark)
	# Front steering column.
	_box(Vector3(0.16, 0.7, 0.18), Vector3(0, 0.72, -0.6), body)
	# Handlebars.
	_box(Vector3(0.6, 0.08, 0.08), Vector3(0, 1.02, -0.58), dark)
	# Headlight.
	_box(Vector3(0.2, 0.18, 0.1), Vector3(0, 0.78, -0.72), Color(1, 0.95, 0.7))
	# Wheels.
	_wheel(0.32, Vector3(0, 0.32, -0.66), dark)
	_wheel(0.34, Vector3(0, 0.34, 0.6), dark)

	# Rider sitting on the seat.
	_box(Vector3(0.34, 0.5, 0.32), Vector3(0, 1.12, 0.2), Color(0.2, 0.35, 0.7))   # torso
	_box(Vector3(0.26, 0.28, 0.28), Vector3(0, 1.48, 0.12), helmet)                # head


# Add a coloured box to the Model node and return it.
func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	mesh_instance.material_override = material
	$Model.add_child(mesh_instance)
	return mesh_instance


# Add a wheel (a cylinder turned so its axle runs left-right across the bike).
func _wheel(radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.18
	mesh.radial_segments = 16
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = Vector3(0, 0, 90)   # spin axis -> X (left-right)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh_instance.material_override = material
	$Model.add_child(mesh_instance)
	return mesh_instance
