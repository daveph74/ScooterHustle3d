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

# --- Lane layout (must match Player.gd) -----------------------------------
const LANE_WIDTH := 2.5
const LANES_X := [-2.5, 0.0, 2.5]   # world X of the three lane centres

# --- Road geometry --------------------------------------------------------
const SEGMENT_LENGTH := 20.0   # length (in metres) of one road tile
const SEGMENT_COUNT := 12      # how many tiles we keep in the world at once
const ROAD_WIDTH := 9.0
const SPAWN_Z := -160.0        # objects appear this far AHEAD of the player
const DESPAWN_Z := 14.0        # objects past this (behind player) are removed

# --- Speed & difficulty ---------------------------------------------------
var base_speed := 16.0         # starting scroll speed (set from the scooter)
var speed := 16.0              # current scroll speed
const MAX_SPEED := 42.0        # difficulty cap so it never gets unfair
var traffic_extra_speed := 1.0 # traffic comes at us a touch faster than the road

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

# --- Screen shake ---------------------------------------------------------
var shake_strength := 0.0
var shake_time := 0.0

# Road tiles we move and recycle.
var _segments: Array[Node3D] = []

# Materials shared by all road pieces (made once to save memory).
var _road_material: StandardMaterial3D
var _dash_material: StandardMaterial3D

# Node references (filled in _ready). @onready waits until children exist.
@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var road_container: Node3D = $RoadContainer
@onready var traffic_container: Node3D = $TrafficContainer
@onready var coin_container: Node3D = $CoinContainer
@onready var hud := $HUD
@onready var game_over := $GameOverLayer


func _ready() -> void:
	_make_road_materials()
	_build_road()

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
	traffic_extra_speed = minf(6.0, 1.0 + elapsed * 0.03)

	# --- Advance the world ------------------------------------------------
	var move := speed * delta
	distance += move
	score = int(distance) + score_bonus

	_scroll_road(move)
	# Traffic moves a little faster than the road so it feels like oncoming.
	_scroll_traffic((speed + traffic_extra_speed) * delta)
	_scroll_coins(move)

	# --- Spawning ---------------------------------------------------------
	traffic_timer -= delta
	if traffic_timer <= 0.0:
		traffic_timer = traffic_interval
		_spawn_traffic()

	coin_timer -= delta
	if coin_timer <= 0.0:
		coin_timer = coin_interval
		_spawn_coin_line()

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


## Create the pool of road tiles once at startup.
func _build_road() -> void:
	for i in range(SEGMENT_COUNT):
		var segment := _make_road_segment()
		# Lay tiles out from just behind the player forward into the distance.
		segment.position.z = DESPAWN_Z - i * SEGMENT_LENGTH
		road_container.add_child(segment)
		_segments.append(segment)


## Build one road tile: a flat asphalt plane plus dashed lane markings.
func _make_road_segment() -> Node3D:
	var segment := Node3D.new()

	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(ROAD_WIDTH, SEGMENT_LENGTH)
	road.mesh = plane
	road.material_override = _road_material
	segment.add_child(road)

	# Two dashed dividers, one between each pair of lanes.
	const DASHES_PER_SEGMENT := 4
	for divider_x in [-LANE_WIDTH * 0.5, LANE_WIDTH * 0.5]:
		for d in range(DASHES_PER_SEGMENT):
			var dash := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(0.18, 0.02, 2.0)
			dash.mesh = box
			dash.material_override = _dash_material
			var z_offset := -SEGMENT_LENGTH * 0.5 + (d + 0.5) * (SEGMENT_LENGTH / DASHES_PER_SEGMENT)
			dash.position = Vector3(divider_x, 0.02, z_offset)
			segment.add_child(dash)

	return segment


## Slide every road tile toward the player; recycle any that fall behind.
func _scroll_road(amount: float) -> void:
	var total_length := SEGMENT_COUNT * SEGMENT_LENGTH
	for segment in _segments:
		segment.position.z += amount
		if segment.position.z > DESPAWN_Z + SEGMENT_LENGTH:
			# Jump it back to the far end to make the road feel endless.
			segment.position.z -= total_length


# ==========================================================================
#  TRAFFIC
# ==========================================================================

func _spawn_traffic() -> void:
	var types := ["jeepney", "tricycle", "bus", "car"]
	var lane := randi() % 3

	var vehicle := TRAFFIC_SCENE.instantiate()
	traffic_container.add_child(vehicle)
	vehicle.setup(types[randi() % types.size()])
	vehicle.position = Vector3(LANES_X[lane], 0.0, SPAWN_Z)

	# Later in the run, sometimes add a second vehicle in a DIFFERENT lane.
	# We never fill all three lanes, so there is always a way through.
	if elapsed > 18.0 and randf() < 0.4:
		var lane2 := (lane + 1 + (randi() % 2)) % 3
		var vehicle2 := TRAFFIC_SCENE.instantiate()
		traffic_container.add_child(vehicle2)
		vehicle2.setup(types[randi() % types.size()])
		vehicle2.position = Vector3(LANES_X[lane2], 0.0, SPAWN_Z - randf_range(4.0, 12.0))


func _scroll_traffic(amount: float) -> void:
	for vehicle in traffic_container.get_children():
		vehicle.position.z += amount
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


func _scroll_coins(amount: float) -> void:
	for coin in coin_container.get_children():
		coin.position.z += amount
		if coin.position.z > DESPAWN_Z:
			coin.queue_free()


# ==========================================================================
#  CAMERA, SHAKE & FEEDBACK
# ==========================================================================

func _update_camera(delta: float) -> void:
	# Follow the player's lane a little (not all the way) for a subtle drift.
	var target_x := player.position.x * 0.55
	var follow: float = clamp(6.0 * delta, 0.0, 1.0)
	camera.position.x = lerp(camera.position.x, target_x, follow)

	# Tilt the camera slightly into lane changes.
	var target_roll := -player.position.x * 0.02
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
