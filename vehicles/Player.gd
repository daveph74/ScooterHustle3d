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
# Translucent dome shown around the scooter while a shield is active.
var _shield_bubble: MeshInstance3D
var _shield_spin := 0.0

# --- Lanes (driven by Game's RoadManager) ---------------------------------
# World X of each lane centre on the CURRENT road section. Game pushes this
# every frame via set_lanes(); it changes as the road narrows/widens between
# 2, 3 and 4 lanes. Defaults to a 3-lane road until Game sets it.
var lane_positions: Array = [-2.5, 0.0, 2.5]

# Which lane we are aiming for, as an INDEX into lane_positions (0 = leftmost).
var current_lane := 1
# Lane-change feel, both set from the scooter's handling stat in _ready:
# how fast we slide between lanes, and how hard we lean into the turn. A nimble
# bike changes lanes faster AND leans sharper.
var lane_change_speed := 9.0
var _lean_strength := 0.25
const LANE_SLIDE_PER := 8.0   # lane-slide speed = this * handling
const LEAN_PER := 0.25        # lean amount    = this * handling
# Once we crash we stop responding to input.
var alive := true
# Seconds since the last actual lane change (used to detect a genuine "dodge"
# for near misses, so passively cruising past traffic doesn't count).
var _since_lane_change := 999.0

var _speed_ratio: float = 0.0

# Soft round dust texture (white with a radial alpha falloff) so the exhaust
# puffs read as dust, not hard squares. Tinted dusty-tan in the material.
const DUST_TEXTURE := preload("res://effects/dust.png")
var _dust: GPUParticles3D

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
# The mounted rider model (null until a rider.glb exists). Kept so we can fling
# it off the bike on a crash.
var _rider: Node3D

# --- Swipe detection ------------------------------------------------------
var _touching := false
var _touch_start_x := 0.0
const SWIPE_MIN_PIXELS := 40.0   # how far a finger must move to count as a swipe


func _ready() -> void:
	var scooter := GameData.get_selected_scooter()

	# Drop in the selected bike's model (each bike can name its own .glb; an empty
	# model_path falls back to the default scooter), auto-fitted to the player's
	# size, then apply the equipped cosmetics (paint / helmet / wheels) - visual.
	var packed: PackedScene = SCOOTER_MODEL
	var model_yaw: float = SCOOTER_YAW
	if scooter and scooter.model_path != "" and ResourceLoader.exists(scooter.model_path):
		packed = load(scooter.model_path)
		model_yaw = scooter.model_yaw
	var holder := ModelUtil.instance_fitted($Model, packed, Vector3(0.9, 1.2, 1.9), "length", model_yaw)
	Cosmetics.new().apply(holder, GameData.equipped_cosmetics)

	# Sit a rider on the bike, if the art exists yet.
	_mount_rider()

	# Read the selected scooter's handling so better bikes feel snappier: a
	# higher handling slides between lanes faster and leans harder.
	var handling: float = scooter.handling if scooter else 1.0
	lane_change_speed = LANE_SLIDE_PER * handling
	_lean_strength = LEAN_PER * handling

	_build_dust()
	_build_shield_bubble()

	# Connect collisions. Because traffic and coins are also Area3D nodes,
	# we listen for "area_entered".
	area_entered.connect(_on_area_entered)

	# Snap to the starting lane immediately.
	position.x = _current_lane_x()


func set_speed_ratio(ratio: float) -> void:
	_speed_ratio = ratio
	# Kick out more dust the faster we go; idle = none.
	_dust.emitting = ratio > 0.05
	_dust.amount_ratio = lerpf(0.25, 1.0, ratio)


## Soft exhaust/road dust kicked up behind the rear wheel. Uses a round alpha
## texture so the puffs are soft, small and faint - subtle, not blocky.
func _build_dust() -> void:
	_dust = GPUParticles3D.new()
	_dust.amount = 16
	_dust.lifetime = 0.5
	_dust.emitting = false
	_dust.local_coords = false   # puffs stay in the world as the bike moves on
	_dust.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 4, 6))

	var dpm := ParticleProcessMaterial.new()
	dpm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dpm.emission_box_extents = Vector3(0.18, 0.03, 0.1)
	dpm.direction = Vector3(0, 0.6, 1)          # up and a little backward
	dpm.spread = 25.0
	dpm.gravity = Vector3(0, -1.2, 0)
	dpm.initial_velocity_min = 0.6
	dpm.initial_velocity_max = 1.4
	dpm.scale_min = 0.08
	dpm.scale_max = 0.22
	# Grow as they rise, and fade their alpha out over their lifetime.
	dpm.scale_curve = _ramp_curve()
	dpm.alpha_curve = _fade_curve()
	_dust.process_material = dpm

	var dq := QuadMesh.new()
	dq.size = Vector2(0.5, 0.5)
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.78, 0.72, 0.6, 0.5)   # faint dusty tan
	dm.albedo_texture = DUST_TEXTURE                # <-- soft round edge
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dq.material = dm
	_dust.draw_pass_1 = dq

	_dust.position = Vector3(0.0, 0.12, 0.55)   # just behind/below the scooter
	add_child(_dust)


## A glowing translucent dome around the scooter, shown while a shield is active
## so the player can see they're protected. Hidden until shield_active is set.
func _build_shield_bubble() -> void:
	_shield_bubble = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.15
	sphere.height = 2.3
	_shield_bubble.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.65, 1.0, 0.28)      # translucent blue
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED        # see both sides of the dome
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.6, 1.0) * 0.5
	_shield_bubble.material_override = mat
	_shield_bubble.position.y = 0.9
	_shield_bubble.visible = false
	add_child(_shield_bubble)


## A 0->1 rising curve (particles grow as they rise).
func _ramp_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.6))
	c.add_point(Vector2(1.0, 1.2))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


## A 1->0 alpha curve (particles fade out near the end of their life).
func _fade_curve() -> CurveTexture:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 0.0))
	c.add_point(Vector2(0.25, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


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
	_rider = rider


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

	# Lean the scooter into the turn for a bit of flavour (sharper on nimble bikes).
	var lean := (target_x - position.x) * _lean_strength
	rotation.z = lerp(rotation.z, lean, clamp(10.0 * delta, 0.0, 1.0))

	# Show the shield dome while a shield is active, with a gentle spin + pulse.
	_shield_bubble.visible = shield_active
	if shield_active:
		_shield_spin += delta
		_shield_bubble.rotation.y = _shield_spin * 1.5
		var pulse := 1.0 + sin(_shield_spin * 4.0) * 0.04
		_shield_bubble.scale = Vector3(pulse, pulse, pulse)


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
	_eject_rider()
	crashed.emit()


## Fling the rider off the bike in a tumbling arc on a crash (purely visual).
func _eject_rider() -> void:
	if _rider == null:
		return

	# Where he lands: launched well forward over the handlebars (-z = down the
	# road) with a random sideways spray, then back down to the road.
	var land_x: float = _rider.position.x + randf_range(-2.5, 2.5)
	var land_z: float = _rider.position.z - 9.0

	# Slide forward + sideways and tumble, all in parallel over ~1.1s.
	var fling := create_tween()
	fling.set_parallel(true)
	fling.tween_property(_rider, "position:x", land_x, 1.1)
	fling.tween_property(_rider, "position:z", land_z, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	fling.tween_property(_rider, "rotation:x", _rider.rotation.x + TAU * 2.5, 1.1)
	fling.tween_property(_rider, "rotation:z", _rider.rotation.z + randf_range(-6.0, 6.0), 1.1)

	# A separate up-then-down arc for the height (pop up high, fall under gravity).
	var arc := create_tween()
	arc.tween_property(_rider, "position:y", _rider.position.y + 4.0, 0.45) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	arc.tween_property(_rider, "position:y", 0.05, 0.65) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
