extends Node3D
## Game.gd - the heart of the gameplay scene.
##
## It is responsible for:
##   * Building and scrolling the endless road.
##   * Spawning, moving and recycling traffic and coins.
##   * Ramping up difficulty over time.
##   * Scoring, near-miss detection, screen shake and the game-over flow.
##
## KEY IDEA - the "treadmill": the player never actually drives forward.
## The player only slides left/right. Everything else (road, traffic, coins)
## moves toward the player. This keeps the maths simple and avoids floating
## point problems over an "endless" distance.

# Scenes we spawn at runtime. Preloaded so they are ready instantly.
const TRAFFIC_SCENE := preload("res://traffic/TrafficVehicle.tscn")
const COIN_SCENE := preload("res://scenes/Coin.tscn")

# Roadside scenery models (Kenney "City Kit", MIT licensed). Buildings and
# trees are placed off to the sides and scroll past for a sense of a city.
const BUILDING_MODELS := [
	preload("res://models/city/building-small-a.glb"),
	preload("res://models/city/building-small-b.glb"),
	preload("res://models/city/building-small-c.glb"),
	preload("res://models/city/building-small-d.glb"),
	preload("res://models/city/building-garage.glb"),
]
const TREE_MODELS := [
	preload("res://models/city/grass-trees.glb"),
	preload("res://models/city/grass-trees-tall.glb"),
]

# --- Lane layout (must match Player.gd) -----------------------------------
const LANE_WIDTH := 2.5
const LANES_X := [-2.5, 0.0, 2.5]   # world X of the three lane centres

# --- Road geometry --------------------------------------------------------
# Short overlapping tiles so hills/bends look smooth rather than blocky.
const SEGMENT_LENGTH := 4.0    # length (in metres) of one road tile
const SEGMENT_COUNT := 44      # how many tiles we keep in the world at once
const ROAD_WIDTH := 9.0
const GROUND_WIDTH := 150.0    # wide grass baked into each tile so it rolls too
const SPAWN_Z := -150.0        # objects appear this far AHEAD of the player
const DESPAWN_Z := 14.0        # objects past this (behind player) are removed

# --- Curvy world: fake hills (vertical) and bends (sideways) --------------
# The LOGICAL track stays straight and flat, so lanes and collisions are
# unaffected. We only DISPLACE the visuals based on how far ahead something is,
# blending to zero at the player so everything lines up where it matters.
# Flip these signs if a hill or bend ever goes the "wrong" way.
const HILL_DIR := 1.0
const BEND_DIR := 1.0

# --- Speed & difficulty ---------------------------------------------------
var base_speed := 16.0         # starting scroll speed (set from the scooter)
var speed := 16.0              # current scroll speed
const MAX_SPEED := 42.0        # difficulty cap so it never gets unfair

# --- Run state ------------------------------------------------------------
var distance := 0.0            # metres travelled this run
var score := 0                 # shown on the HUD (distance + near-miss bonus)
var score_bonus := 0           # extra points from near misses
var run_coins := 0             # coins collected this run
var elapsed := 0.0             # seconds since the run started
var playing := false

# --- Spawn timers ---------------------------------------------------------
var traffic_timer := 0.0
var traffic_interval := 1.5    # seconds between traffic spawns (shrinks over time)
var coin_timer := 0.0
var coin_interval := 1.7
var scenery_timer := 0.0
var scenery_interval := 0.9       # seconds between roadside props
var _scenery_left := true         # alternate sides as we spawn

# --- Screen shake ---------------------------------------------------------
var shake_strength := 0.0
var shake_time := 0.0

# Road tiles we move and recycle.
var _segments: Array[Node3D] = []

# Materials shared by all road pieces (made once to save memory).
var _road_material: StandardMaterial3D
var _dash_material: StandardMaterial3D
var _ground_material: StandardMaterial3D

# Node references (filled in _ready). @onready waits until children exist.
@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var road_container: Node3D = $RoadContainer
@onready var traffic_container: Node3D = $TrafficContainer
@onready var coin_container: Node3D = $CoinContainer
@onready var scenery_container: Node3D = $SceneryContainer
@onready var hud := $HUD
@onready var game_over := $GameOverLayer


func _ready() -> void:
	_make_road_materials()
	_build_road()
	_prewarm_scenery()
	_prewarm_traffic()

	# Aim the sun down and across so the boxes cast nice shadows.
	sun.rotation_degrees = Vector3(-55, -35, 0)

	# Faster scooters start the run faster.
	var scooter := GameData.get_selected_scooter()
	if scooter:
		base_speed = 14.0 + scooter.speed * 4.0
	speed = base_speed

	# Camera: sit behind and above, look slightly down the road.
	camera.rotation_degrees.x = -16.0
	camera.fov = 70.0

	# Listen to the player.
	player.crashed.connect(_on_player_crashed)
	player.coin_collected.connect(_on_coin_collected)

	# Prepare the UI.
	game_over.hide_screen()
	hud.set_total_coins(GameData.total_coins)
	hud.set_run_coins(0)
	hud.set_score(0)

	playing = true


func _process(delta: float) -> void:
	# Even when not playing we keep updating the shake so it settles smoothly.
	if not playing:
		_update_shake(delta)
		return

	elapsed += delta

	# --- Gentle difficulty ramp (no sudden spikes) ------------------------
	speed = minf(base_speed + elapsed * 0.35, MAX_SPEED)
	traffic_interval = maxf(0.7, 1.6 - elapsed * 0.012)

	# --- Advance the world ------------------------------------------------
	var move := speed * delta
	distance += move
	score = int(distance) + score_bonus

	_scroll_road(move)
	# Each vehicle drives at its own speed, so the player overtakes slower
	# traffic - that relative motion is what makes traffic look alive.
	_scroll_traffic(delta)
	_scroll_coins(move)
	_scroll_scenery(move)

	# --- Spawning ---------------------------------------------------------
	traffic_timer -= delta
	if traffic_timer <= 0.0:
		traffic_timer = traffic_interval
		_spawn_traffic()

	coin_timer -= delta
	if coin_timer <= 0.0:
		coin_timer = coin_interval
		_spawn_coin_line()

	scenery_timer -= delta
	if scenery_timer <= 0.0:
		scenery_timer = scenery_interval
		_spawn_scenery_at(SPAWN_Z)

	# --- HUD + camera + shake --------------------------------------------
	hud.set_score(score)
	_update_camera(delta)
	_update_shake(delta)


# ==========================================================================
#  ROAD
# ==========================================================================

func _make_road_materials() -> void:
	_road_material = StandardMaterial3D.new()
	_road_material.albedo_color = Color(0.17, 0.17, 0.19)  # dark asphalt
	_road_material.roughness = 1.0

	_dash_material = StandardMaterial3D.new()
	_dash_material.albedo_color = Color(0.95, 0.95, 0.95)   # white lane paint
	_dash_material.emission_enabled = true
	_dash_material.emission = Color(0.15, 0.15, 0.15)

	_ground_material = StandardMaterial3D.new()
	_ground_material.albedo_color = Color(0.32, 0.42, 0.26)  # grass
	_ground_material.roughness = 1.0


## Create the pool of road tiles once at startup.
func _build_road() -> void:
	for i in range(SEGMENT_COUNT):
		var segment := _make_road_segment()
		# Lay tiles out from just behind the player forward into the distance.
		segment.position.z = DESPAWN_Z - i * SEGMENT_LENGTH
		road_container.add_child(segment)
		_segments.append(segment)


## Build one road tile: grass + asphalt + a dash on each lane divider.
## Tiles are made slightly longer than their spacing so they overlap, which
## hides any little seams once they are tilted along hills.
func _make_road_segment() -> Node3D:
	var segment := Node3D.new()
	var overlap := SEGMENT_LENGTH + 0.6

	# Wide grass, baked into the tile so the ground rolls with the hills.
	var ground := MeshInstance3D.new()
	var ground_plane := PlaneMesh.new()
	ground_plane.size = Vector2(GROUND_WIDTH, overlap)
	ground.mesh = ground_plane
	ground.material_override = _ground_material
	ground.position.y = -0.04
	segment.add_child(ground)

	# Asphalt road on top.
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_WIDTH, overlap)
	road.mesh = plane
	road.material_override = _road_material
	segment.add_child(road)

	# One dash on each lane divider (length = half the tile = dash + gap).
	for divider_x in [-LANE_WIDTH * 0.5, LANE_WIDTH * 0.5]:
		var dash := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.02, SEGMENT_LENGTH * 0.5)
		dash.mesh = box
		dash.material_override = _dash_material
		dash.position = Vector3(divider_x, 0.02, 0.0)
		segment.add_child(dash)

	return segment


## Slide every road tile toward the player; recycle any that fall behind, and
## displace each tile along the hill/bend path.
func _scroll_road(amount: float) -> void:
	var total_length := SEGMENT_COUNT * SEGMENT_LENGTH
	for segment in _segments:
		segment.position.z += amount
		if segment.position.z > DESPAWN_Z + SEGMENT_LENGTH:
			# Jump it back to the far end to make the road feel endless.
			segment.position.z -= total_length
		var off := _path_offset(segment.position.z)
		segment.position.x = off.x
		segment.position.y = off.y


# ==========================================================================
#  CURVY WORLD (fake hills & bends)
# ==========================================================================

# Sideways displacement of the track at world position w (gentle, long bends).
func _path_x(w: float) -> float:
	return (sin(w * 0.0065) * 7.0 + sin(w * 0.017) * 2.5) * BEND_DIR

# Vertical displacement of the track at world position w (small rolling hills).
func _path_y(w: float) -> float:
	return (sin(w * 0.020) * 1.4 + cos(w * 0.045) * 0.7) * HILL_DIR

## How far to displace an object that is currently at local z (z < 0 = ahead).
## We subtract the value at the player so the offset is zero right at z = 0.
func _path_offset(z: float) -> Vector2:
	var w := distance - z
	return Vector2(_path_x(w) - _path_x(distance), _path_y(w) - _path_y(distance))

## Apply the hill/bend displacement to a scrolling object, on top of the base
## X/Y it was spawned with (stored in "bx"/"by").
func _apply_path(node: Node3D) -> void:
	var off := _path_offset(node.position.z)
	node.position.x = node.get_meta("bx", 0.0) + off.x
	node.position.y = node.get_meta("by", 0.0) + off.y


# ==========================================================================
#  TRAFFIC
# ==========================================================================

func _spawn_traffic() -> void:
	_spawn_traffic_at(SPAWN_Z)


## Spawn traffic at a given distance ahead. Used both for normal spawning (at
## SPAWN_Z) and for pre-populating the road at startup.
func _spawn_traffic_at(z: float) -> void:
	var types := ["jeepney", "tricycle", "bus", "car"]
	var lane := randi() % 3

	var vehicle := TRAFFIC_SCENE.instantiate()
	traffic_container.add_child(vehicle)
	vehicle.setup(types[randi() % types.size()])
	vehicle.position = Vector3(LANES_X[lane], 0.0, z)
	vehicle.set_meta("bx", LANES_X[lane])
	vehicle.set_meta("by", 0.0)
	vehicle.drive_speed = randf_range(0.35, 0.7) * base_speed

	# Later in the run, sometimes add a second vehicle in a DIFFERENT lane.
	# We never fill all three lanes, so there is always a way through.
	if elapsed > 18.0 and randf() < 0.4:
		var lane2 := (lane + 1 + (randi() % 2)) % 3
		var vehicle2 := TRAFFIC_SCENE.instantiate()
		traffic_container.add_child(vehicle2)
		vehicle2.setup(types[randi() % types.size()])
		vehicle2.position = Vector3(LANES_X[lane2], 0.0, z - randf_range(4.0, 12.0))
		vehicle2.set_meta("bx", LANES_X[lane2])
		vehicle2.set_meta("by", 0.0)
		vehicle2.drive_speed = randf_range(0.35, 0.7) * base_speed


## Put some traffic on the road at startup so it isn't empty for the first few
## seconds while the first spawned vehicles drive in from the distance.
func _prewarm_traffic() -> void:
	var z := -40.0   # far enough that the player has time to react at the start
	while z > -150.0:
		_spawn_traffic_at(z)
		z -= randf_range(20.0, 34.0)


func _scroll_traffic(delta: float) -> void:
	for vehicle in traffic_container.get_children():
		# The world scrolls toward the player at "speed"; the vehicle is also
		# driving forward at its own speed, so it closes on the player at the
		# difference. Since the player is faster, we always overtake it.
		vehicle.position.z += (speed - vehicle.drive_speed) * delta
		_apply_path(vehicle)
		_check_near_miss(vehicle)
		if vehicle.position.z > DESPAWN_Z:
			vehicle.queue_free()


## A "near miss" is when traffic passes the player in an ADJACENT lane without
## hitting them. We give a tiny score bonus and a little juice for the thrill.
func _check_near_miss(vehicle: Node3D) -> void:
	if vehicle.has_meta("passed"):
		return
	if vehicle.position.z >= player.position.z:
		vehicle.set_meta("passed", true)
		var dx := absf(vehicle.position.x - player.position.x)
		# > 1.2 means it did NOT hit us; < 3.2 means it was close (next lane).
		if dx > 1.2 and dx < 3.2:
			_on_near_miss()


# ==========================================================================
#  COINS
# ==========================================================================

## Spawn a short line of coins in one lane - more satisfying than singles.
func _spawn_coin_line() -> void:
	var lane := randi() % 3
	var count := randi_range(3, 5)
	for i in range(count):
		var coin := COIN_SCENE.instantiate()
		coin_container.add_child(coin)
		coin.position = Vector3(LANES_X[lane], 0.7, SPAWN_Z - i * 2.2)
		coin.set_meta("bx", LANES_X[lane])
		coin.set_meta("by", 0.7)


func _scroll_coins(amount: float) -> void:
	for coin in coin_container.get_children():
		coin.position.z += amount
		_apply_path(coin)
		if coin.position.z > DESPAWN_Z:
			coin.queue_free()


# ==========================================================================
#  ROADSIDE SCENERY (buildings & trees)
# ==========================================================================

## Fill the road sides with scenery at startup so the world isn't empty.
func _prewarm_scenery() -> void:
	var z := SPAWN_Z
	while z < DESPAWN_Z:
		_spawn_scenery_at(z)
		z += randf_range(5.0, 9.0)


## Spawn one building or tree just off the road, on alternating sides.
func _spawn_scenery_at(z: float) -> void:
	_scenery_left = not _scenery_left
	var side := -1.0 if _scenery_left else 1.0

	var holder: Node3D
	var gap: float   # extra space between the road edge and this prop
	if randf() < 0.45:
		# A clump of trees, sitting close to the road edge.
		var model: PackedScene = TREE_MODELS[randi() % TREE_MODELS.size()]
		holder = ModelUtil.instance_fitted(scenery_container, model, Vector3(3, randf_range(3.0, 5.0), 3), "height", false)
		gap = randf_range(1.0, 3.0)
	else:
		# A building, set back a little further.
		var model: PackedScene = BUILDING_MODELS[randi() % BUILDING_MODELS.size()]
		holder = ModelUtil.instance_fitted(scenery_container, model, Vector3(8, randf_range(7.0, 16.0), 8), "height", false)
		gap = randf_range(2.5, 6.0)

	holder.rotate_y(randf_range(0.0, TAU))

	# Push the prop out by its own footprint so its edge always clears the road,
	# no matter how big the model was scaled or how it was rotated.
	var road_edge := ROAD_WIDTH * 0.5
	var radius := ModelUtil.footprint_radius(holder)
	holder.position = Vector3(side * (road_edge + gap + radius), 0.0, z)
	holder.set_meta("bx", holder.position.x)
	holder.set_meta("by", 0.0)


func _scroll_scenery(amount: float) -> void:
	for prop in scenery_container.get_children():
		prop.position.z += amount
		_apply_path(prop)
		if prop.position.z > DESPAWN_Z + 6.0:
			prop.queue_free()


# ==========================================================================
#  CAMERA, SHAKE & FEEDBACK
# ==========================================================================

func _update_camera(delta: float) -> void:
	var follow: float = clamp(6.0 * delta, 0.0, 1.0)

	# Where does the road go a little way ahead? Aim the camera there so bends
	# and hills feel like we are driving into them.
	var look := 22.0
	var ahead := _path_offset(-look)

	# Follow the player's lane a little, and drift toward the bend.
	var target_x := player.position.x * 0.55 + ahead.x * 0.25
	camera.position.x = lerp(camera.position.x, target_x, follow)

	# Yaw toward the bend, pitch with the hill (on top of the base downward tilt).
	var target_yaw := atan2(-ahead.x, look) * 0.6
	camera.rotation.y = lerp(camera.rotation.y, target_yaw, follow)
	var target_pitch := deg_to_rad(-16.0) + atan2(ahead.y, look) * 0.5
	camera.rotation.x = lerp(camera.rotation.x, target_pitch, follow)

	# Bank into lane changes and bends.
	var target_roll := -player.position.x * 0.02 - ahead.x * 0.01
	camera.rotation.z = lerp(camera.rotation.z, target_roll, follow)

	# Widen the field of view as we speed up = sense of speed.
	var speed_ratio: float = clamp((speed - base_speed) / (MAX_SPEED - base_speed + 0.001), 0.0, 1.0)
	camera.fov = lerp(70.0, 82.0, speed_ratio)


func _add_shake(strength: float, duration: float) -> void:
	shake_strength = maxf(shake_strength, strength)
	shake_time = maxf(shake_time, duration)


func _update_shake(delta: float) -> void:
	if shake_time <= 0.0:
		return
	shake_time -= delta
	# Shake fades out as the timer runs down. We use the camera's h/v offset so
	# we don't fight the position lerp in _update_camera.
	var amount := shake_strength * maxf(shake_time, 0.0)
	camera.h_offset = randf_range(-amount, amount)
	camera.v_offset = randf_range(-amount, amount)
	if shake_time <= 0.0:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _on_near_miss() -> void:
	score_bonus += 25
	_add_shake(0.15, 0.15)
	hud.flash_near_miss()


func _on_coin_collected(amount: int) -> void:
	run_coins += amount
	hud.set_run_coins(run_coins)
	hud.pulse_coin()


# ==========================================================================
#  GAME OVER
# ==========================================================================

func _on_player_crashed() -> void:
	if not playing:
		return
	playing = false
	_add_shake(0.6, 0.6)   # a hard jolt on impact

	# Bank the coins from this run into the player's permanent total (saves).
	GameData.add_coins(run_coins)

	# Small pause so the crash registers, then show the game-over screen.
	await get_tree().create_timer(0.7).timeout
	game_over.show_screen(score, run_coins, GameData.total_coins)
