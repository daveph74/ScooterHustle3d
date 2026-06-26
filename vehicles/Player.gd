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

# --- Lanes (driven by Game's RoadManager) ---------------------------------
# World X of each lane centre on the CURRENT road section. Game pushes this
# every frame via set_lanes(); it changes as the road narrows/widens between
# 2, 3 and 4 lanes. Defaults to a 3-lane road until Game sets it.
var lane_positions: Array = [-2.5, 0.0, 2.5]

# Which lane we are aiming for, as an INDEX into lane_positions (0 = leftmost).
var current_lane := 1
# How quickly we slide between lanes. Set from the scooter's handling stat.
var lane_change_speed := 9.0
# Once we crash we stop responding to input.
var alive := true
# Seconds since the last actual lane change (used to detect a genuine "dodge"
# for near misses, so passively cruising past traffic doesn't count).
var _since_lane_change := 999.0

# --- Visual model ---------------------------------------------------------
# Custom "Pilipinas Hustle" scooter (generated on Meshy, optimised to ~30k tris
# / 1K textures). ModelUtil auto-scales it to fit, so we only ever tweak this
# facing flag if it points the wrong way down the road.
const SCOOTER_MODEL := preload("res://models/custom/scooter.glb")
# Rotate the model so it faces down the road. Tune in 90° steps if needed.
const SCOOTER_YAW := 270.0

# --- Rider --------------------------------------------------------------------
# A rider sat on the scooter. Loaded at RUNTIME (not preloaded) so the game still
# runs before the art exists - just drop a rider.glb into models/custom and it
# appears. Tune the three knobs below once you can see it on the bike:
#   RIDER_YAW    - turn the rider to face down the road (90 deg steps).
#   RIDER_HEIGHT - how tall to scale the rider.
#   RIDER_OFFSET - nudge them onto the seat (y up, z back/forward).
const RIDER_MODEL_PATH := "res://models/custom/rider.glb"
const RIDER_YAW := 180.0
const RIDER_HEIGHT := 1.2
# +z moves him back toward the seat (away from the handlebars); y lifts him.
const RIDER_OFFSET := Vector3(0.0, 0.32, 0.45)

# --- Swipe detection ------------------------------------------------------
var _touching := false
var _touch_start_x := 0.0
const SWIPE_MIN_PIXELS := 40.0   # how far a finger must move to count as a swipe


func _ready() -> void:
	# Drop in the scooter model, auto-fitted to the player's size, then apply the
	# equipped cosmetics (paint / helmet / wheels) - purely visual.
	var holder := ModelUtil.instance_fitted($Model, SCOOTER_MODEL, Vector3(0.9, 1.2, 1.9), "length", SCOOTER_YAW)
	Cosmetics.new().apply(holder, GameData.equipped_cosmetics)

	# Sit a rider on the bike, if the art exists yet.
	_mount_rider()

	# Read the selected scooter's handling so better bikes feel snappier.
	var scooter := GameData.get_selected_scooter()
	if scooter:
		lane_change_speed = 7.0 * scooter.handling

	# Connect collisions. Because traffic and coins are also Area3D nodes,
	# we listen for "area_entered".
	area_entered.connect(_on_area_entered)

	# Snap to the starting lane immediately.
	position.x = _current_lane_x()


## Load and seat the rider on the scooter. Does nothing (silently) until a
## rider.glb is added, so the game runs fine without it.
func _mount_rider() -> void:
	if not ResourceLoader.exists(RIDER_MODEL_PATH):
		return
	var rider_scene: PackedScene = load(RIDER_MODEL_PATH)
	var rider := ModelUtil.instance_fitted(
		$Model, rider_scene, Vector3(0.6, RIDER_HEIGHT, 0.6), "height", RIDER_YAW)
	# Lift/nudge them onto the seat (the model is grounded at y=0 by ModelUtil).
	rider.position += RIDER_OFFSET


## World X of the lane we're aiming for. Clamps current_lane so a lane that
## disappeared (road narrowed) resolves to the nearest valid lane - the
## position lerp in _process then slides us there smoothly (no death).
func _current_lane_x() -> float:
	current_lane = clampi(current_lane, 0, lane_positions.size() - 1)
	return lane_positions[current_lane]


## Called by Game every frame with the current section's lane positions.
func set_lanes(positions: Array) -> void:
	lane_positions = positions
	current_lane = clampi(current_lane, 0, lane_positions.size() - 1)


func _process(delta: float) -> void:
	if not alive:
		return

	_since_lane_change += delta

	# Keyboard testing controls.
	if Input.is_action_just_pressed("move_left"):
		change_lane(-1)
	if Input.is_action_just_pressed("move_right"):
		change_lane(1)

	# Smoothly slide toward the target lane (this is what makes lane changes
	# feel nice instead of teleporting).
	var target_x := _current_lane_x()
	var t: float = clamp(lane_change_speed * delta, 0.0, 1.0)
	position.x = lerp(position.x, target_x, t)

	# Lean the scooter into the turn for a bit of flavour.
	var lean := (target_x - position.x) * 0.25
	rotation.z = lerp(rotation.z, lean, clamp(10.0 * delta, 0.0, 1.0))


## Move one lane left (dir = -1) or right (dir = +1), clamped to the road.
func change_lane(dir: int) -> void:
	var next_lane: int = clampi(current_lane + dir, 0, lane_positions.size() - 1)
	if next_lane != current_lane:
		current_lane = next_lane
		_since_lane_change = 0.0   # reset the dodge timer on a real lane change


## True if the player swerved lanes within the given window (a real "dodge").
func recently_changed_lane(window: float = 1.0) -> bool:
	return _since_lane_change <= window


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
