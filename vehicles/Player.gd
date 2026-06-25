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
## Emitted when a power-up is picked up. Carries its kind ("magnet"/"shield"/...).
signal powerup_collected(kind: String)
## Emitted when a shield absorbs a hit (instead of crashing).
signal shielded

# Set true by the PowerUpManager when a shield power-up is active. The next
# traffic hit consumes it instead of ending the run.
var shield_active := false

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

# --- Visual model ---------------------------------------------------------
# The scooter mesh (Kenney "Car Kit" motorcycle, MIT licensed). The model is
# auto-scaled to fit, so we only ever tweak this facing flag if it points the
# wrong way down the road.
const SCOOTER_MODEL := preload("res://models/racing/vehicle-motorcycle.glb")
const SCOOTER_FACES_BACK := true

# --- Swipe detection ------------------------------------------------------
var _touching := false
var _touch_start_x := 0.0
const SWIPE_MIN_PIXELS := 40.0   # how far a finger must move to count as a swipe


func _ready() -> void:
	# Drop in the scooter model, auto-fitted to the player's size, then apply the
	# equipped cosmetics (paint / helmet / wheels) - purely visual.
	var holder := ModelUtil.instance_fitted($Model, SCOOTER_MODEL, Vector3(0.9, 1.2, 1.9), "length", SCOOTER_FACES_BACK)
	Cosmetics.new().apply(holder, GameData.equipped_cosmetics)

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
		# A shield absorbs one hit instead of crashing.
		if shield_active:
			shield_active = false
			shielded.emit()
			return
		_die()
	elif area.is_in_group("coin"):
		# Tell the coin to play its pickup animation, then count it.
		area.collect()
		coin_collected.emit(1)
	elif area.is_in_group("powerup"):
		var pu := area as PowerUp
		pu.collect()
		powerup_collected.emit(pu.kind)


func _die() -> void:
	alive = false
	crashed.emit()
