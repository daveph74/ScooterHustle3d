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
const POWERUP_SCRIPT := preload("res://powerups/PowerUp.gd")
const PEDESTRIAN_SCRIPT := preload("res://scenes/Pedestrian.gd")
const OBSTACLE_SCRIPT := preload("res://scenes/Obstacle.gd")
const SPEED_LINES_SCRIPT := preload("res://ui/SpeedLines.gd")
const WIND_SHADER: Shader = preload("res://shaders/wind.gdshader")

# Roadside scenery models. These are PATHS (resolved via ModelUtil.hd_load, so
# the PC build uses a models/pc/ HD version when present). Buildings and trees
# are placed off to the sides and scroll past for a sense of a city.
const BUILDING_MODELS := [
	"res://models/city/building-small-a.glb",
	"res://models/city/building-small-b.glb",
	"res://models/city/building-small-c.glb",
	"res://models/city/building-small-d.glb",
	"res://models/city/building-garage.glb",
	"res://models/custom/apartment.glb",
]
const TREE_MODELS := [
	"res://models/custom/palm-tree.glb",
	"res://models/city/grass-trees.glb",
	"res://models/city/grass-trees-tall.glb",
]
# Recognisable landmarks (custom Meshy models). Unlike generic buildings these
# are oriented to FACE THE ROAD so you always see the storefront.
const LANDMARK_MODELS := [
	"res://models/custom/jollibee.glb",
	"res://models/custom/church.glb",
	"res://models/custom/insal.glb",
	"res://models/custom/petron.glb",
	"res://models/custom/sari-sari.glb",
	"res://models/custom/711.glb",
	"res://models/custom/chowking.glb",
	"res://models/custom/lto.glb",
	"res://models/custom/pharmacy.glb",
]
# Existing models repurposed as decorative ambient life on the sidewalk.
const PARKED_SCOOTER_MODEL := "res://models/custom/scooter.glb"
const PARKED_JEEPNEY_MODEL := "res://models/custom/jeepney.glb"
const AMBIENT_PERSON_MODEL  := "res://models/custom/man.glb"
# Base yaw so a landmark's front faces the road on the LEFT side; the right side
# is auto-flipped by 180. Tune this if the storefront faces the wrong way.
const LANDMARK_YAW := 0.0

# --- Dynamic road sections (lanes change between 2 / 3 / 4) ---------------
# RoadManager is the single source of truth for lane positions, road width and
# dividers at any point on the road. Everything below asks road.config_at(world).
var road := RoadManager.new()
var districts := Districts.new()
var _prop_factory := PropFactory.new()
const MAX_ROAD_WIDTH := 11.5   # 4 lanes*2.5 + 2*0.75 shoulder; tiles are built this wide and scaled down per section
const SIDEWALK_WIDTH := 2.6    # raised concrete pavement along each road edge (buildings sit on it)
const DEBUG_LANES := false     # set true to show lane count / section type on the HUD

# --- Road geometry --------------------------------------------------------
# Short overlapping tiles so hills/bends look smooth rather than blocky.
const SEGMENT_LENGTH := 4.0    # length (in metres) of one road tile
const SEGMENT_COUNT := 44      # how many tiles we keep in the world at once
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

# All traffic shares ONE speed (as a fraction of the player's), so vehicles
# keep their formation and never drift into an impossible 3-lane wall.
const TRAFFIC_SPEED_FRACTION := 0.45
# When the road narrows, a car whose lane vanishes steers off to the shoulder at
# this lateral speed and despawns (its collision is disabled first, so it can
# never cause an unfair crash). LANE_MATCH_TOL = how close a car's lane X must be
# to a valid lane centre to still count as "in a lane".
const MERGE_OFF_SPEED := 10.0
const LANE_MATCH_TOL := 0.4
# The lane that is GUARANTEED open in the current row of traffic. It only ever
# moves one lane at a time, so the player can always follow it with one swipe.
var _safe_lane := 1

# --- Run state ------------------------------------------------------------
var distance := 0.0            # metres travelled this run
var score := 0                 # shown on the HUD (int of score_value)
var score_value := 0.0         # accumulated score (distance gain x combo, + bonuses)
var run_coins := 0             # coins collected this run
var elapsed := 0.0             # seconds since the run started
var playing := false

# Combo/streak tracker (fresh per run, so it resets when the scene reloads).
var combo := ComboSystem.new()

# --- Spawn timers ---------------------------------------------------------
var traffic_timer := 0.0
var traffic_interval := 1.5    # seconds between traffic spawns (shrinks over time)
var coin_timer := 0.0
var coin_interval := 1.7
# Roadside scenery is built as a CONTINUOUS "street wall" on each side: buildings
# are packed back-to-back by their footprint depth so the frontage looks joined
# up rather than scattered. These cursors track the far edge (local z) of the row
# already placed on each side; new buildings extend it toward the horizon.
var _wall_z_left := DESPAWN_Z
var _wall_z_right := DESPAWN_Z
const SCENERY_GAP := 0.5          # small spacing between neighbours (0 = touching)
var powerup_timer := 8.0          # first power-up can appear a bit into the run
const POWERUP_MIN_GAP := 12.0     # power-ups are rare: 12-20s apart
const POWERUP_MAX_GAP := 20.0
const POWERUP_KINDS := ["magnet", "shield", "multiplier", "speed"]

# --- Pedestrian crossings -------------------------------------------------
# People occasionally cross the road on a zebra crossing; the player must dodge
# them. Like traffic, a crossing NEVER fills the safe lane, so it's always
# passable. All tuning lives here.
var crossing_timer := 0.0
const CROSSING_FIRST_AT := 600.0   # no crossings until this far into the run
const CROSSING_MIN_GAP := 9.0      # seconds between crossings (early game)
const CROSSING_MAX_GAP := 16.0
const CROSSING_WALK_SPEED := 0.6   # how fast pedestrians stroll across (small = fair)

# --- Lane closures (PH "the outer lane just ends, merge or crash") ----------
# A run of cones funnels into a construction-barrier wall blocking ONE outer
# lane; the player must merge inward. The centre lane is forced open for the
# duration so the road is always passable.
var closure_timer := 0.0
var _closed_lane := -1             # outer lane currently closed (-1 = none)
var _closure_until := 0.0          # distance at which the closure has fully passed
const CLOSURE_FIRST_AT := 300.0    # no closures until this far into the run
const CLOSURE_MIN_GAP := 11.0      # seconds between closures
const CLOSURE_MAX_GAP := 20.0
const CLOSURE_LENGTH := 20.0       # how long the dug-up stretch is (metres)
var _construction_material: StandardMaterial3D   # torn-up dirt surface (lazy)

# --- Camera & shake tuning -----------------------------------------------
# Camera base transform (y=2.6, z=5.8) is set in scenes/Game.tscn on Camera3D.
const FOV_MIN := 72.0                    # camera FOV at base speed (portrait)
const FOV_MAX := 90.0                    # camera FOV at max speed (wider = faster-feel)
# The FOV is VERTICAL, so a tall portrait window needs a wider angle than a wide
# landscape one. These are picked at runtime from the window aspect (see _ready).
const FOV_MIN_WIDE := 52.0               # landscape base FOV
const FOV_MAX_WIDE := 64.0               # landscape max-speed FOV
var _fov_lo := FOV_MIN
var _fov_hi := FOV_MAX
const NEAR_MISS_SHAKE_STRENGTH := 0.22   # camera jolt on near miss
const NEAR_MISS_SHAKE_DURATION := 0.20
const CRASH_SHAKE_STRENGTH  := 0.6    # camera jolt on collision/crash
const CRASH_SHAKE_DURATION  := 0.6
const SHIELD_SHAKE_STRENGTH := 0.25   # camera bump when shield absorbs a hit
const SHIELD_SHAKE_DURATION := 0.25

# --- Screen shake ---------------------------------------------------------
var shake_strength := 0.0
var shake_time := 0.0

# Road tiles we move and recycle.
var _segments: Array[Node3D] = []

# Materials shared by all road pieces (made once to save memory).
var _road_material: StandardMaterial3D
var _dash_material: StandardMaterial3D
var _ground_material: StandardMaterial3D
var _sidewalk_material: StandardMaterial3D
var _curb_material: StandardMaterial3D
var _arrow_material: StandardMaterial3D
var _detail_material: StandardMaterial3D
var _oil_material: StandardMaterial3D
var _shoulder_material: StandardMaterial3D

# Node references (filled in _ready). @onready waits until children exist.
@onready var player: Player = $Player
@onready var camera: Camera3D = $Camera3D
@onready var sun: DirectionalLight3D = $Sun
@onready var road_container: Node3D = $RoadContainer
@onready var traffic_container: Node3D = $TrafficContainer
@onready var crossing_container: Node3D = $CrossingContainer
@onready var coin_container: Node3D = $CoinContainer
@onready var scenery_container: Node3D = $SceneryContainer
@onready var powerup_container: Node3D = $PowerUpContainer
@onready var powerups: PowerUpManager = $PowerUpManager
@onready var events: EventManager = $EventManager
@onready var hud := $HUD
@onready var game_over := $GameOverLayer

# Rainstorm visuals (built in code, active only during a rainstorm event).
var _rain: GPUParticles3D
var _env: Environment
var _speed_lines: Node

const BIRD_COUNT  := 3
# Clouds were flat billboard quads that read as grey smears in the sky; disabled.
# Bump back above 0 only if you replace them with a proper cloud sprite/model.
const CLOUD_COUNT := 0
var _birds:  Array = []
var _clouds: Array = []


func _ready() -> void:
	_make_road_materials()
	_build_road()
	_prewarm_scenery()
	_prewarm_traffic()

	# Aim the sun down and across so the boxes cast nice shadows.
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.86)
	sun.light_energy = 1.4

	# Faster scooters start the run faster.
	var scooter := GameData.get_selected_scooter()
	if scooter:
		base_speed = 14.0 + scooter.speed * 4.0
	speed = base_speed

	# Wire up the power-up manager now that base_speed is known.
	powerups.setup(player, hud, base_speed)

	# Camera: sit behind and above, look slightly down the road. Pick a vertical
	# FOV range to suit the window shape - narrower for wide (landscape/PC),
	# wider for tall (portrait/phone) - so the framing looks right either way.
	camera.rotation_degrees.x = -16.0
	var vp := get_viewport().get_visible_rect().size
	var wide := vp.x > vp.y
	_fov_lo = FOV_MIN_WIDE if wide else FOV_MIN
	_fov_hi = FOV_MAX_WIDE if wide else FOV_MAX
	camera.fov = _fov_lo
	if wide:
		# Bring the camera in a little on widescreen so the action reads bigger,
		# without getting too close to the scooter.
		camera.position.y = 2.55
		camera.position.z = 5.7

	# Listen to the player.
	player.crashed.connect(_on_player_crashed)
	player.coin_collected.connect(_on_coin_collected)
	player.powerup_collected.connect(_on_powerup_collected)
	player.shielded.connect(_on_shielded)

	# Random events + the (idle) rainstorm visuals.
	_env = ($WorldEnvironment as WorldEnvironment).environment
	_build_rain()
	events.event_started.connect(_on_event_started)
	events.event_ended.connect(_on_event_ended)

	# Prepare the UI.
	game_over.hide_screen()
	hud.set_best(GameData.best_score)
	hud.set_run_coins(0)
	hud.set_score(0)

	playing = true

	_speed_lines = SPEED_LINES_SCRIPT.new()
	add_child(_speed_lines)
	_build_birds()
	_build_clouds()


func _process(delta: float) -> void:
	# Even when not playing we keep updating the shake so it settles smoothly.
	if not playing:
		_update_shake(delta)
		return

	elapsed += delta

	# --- Gentle difficulty ramp (no sudden spikes) ------------------------
	speed = minf(base_speed + elapsed * 0.35, MAX_SPEED)
	# The speed-boost power-up adds a small extra bump on top (capped modestly).
	speed += powerups.speed_bonus()
	traffic_interval = maxf(0.85, 1.6 - elapsed * 0.012)

	# --- Advance the world ------------------------------------------------
	var move := speed * delta
	distance += move
	# Score gain scales with the combo multiplier AND the speed-boost score
	# bonus, so keeping a streak / boosting makes the score climb faster.
	score_value += move * combo.multiplier() * powerups.score_mult()
	score = int(score_value)

	# Update the road's lane schedule and tell the player the current lanes.
	road.update(distance)
	var here_cfg := road.config_at(distance)
	player.set_lanes(here_cfg.positions)
	if DEBUG_LANES:
		hud.set_debug("Lanes: %d  (%s)  x=%s" % [here_cfg.count, here_cfg.kind, str(here_cfg.positions)])

	_scroll_road(move)
	# Each vehicle drives at its own speed, so the player overtakes slower
	# traffic - that relative motion is what makes traffic look alive.
	_scroll_traffic(delta)
	_scroll_crossings(move)
	_scroll_coins(move)
	_scroll_scenery(move)
	_scroll_birds(move, delta)
	_scroll_clouds(move, delta)
	_scroll_powerups(move)
	_update_district_atmosphere(delta)

	# --- Spawning ---------------------------------------------------------
	# Spawn intervals are scaled by the active event (denser traffic/coins/etc).
	traffic_timer -= delta
	if traffic_timer <= 0.0:
		traffic_timer = traffic_interval * events.traffic_interval_mult()
		_spawn_traffic()

	coin_timer -= delta
	if coin_timer <= 0.0:
		coin_timer = coin_interval * events.coin_interval_mult()
		_spawn_coin_line()

	powerup_timer -= delta
	if powerup_timer <= 0.0:
		powerup_timer = randf_range(POWERUP_MIN_GAP, POWERUP_MAX_GAP)
		_spawn_powerup()

	# Pedestrian crossings only start later in the run, then get a touch more
	# frequent the further you go.
	if distance >= CROSSING_FIRST_AT:
		crossing_timer -= delta
		if crossing_timer <= 0.0:
			# Ramp the gap down slightly with distance (never below the minimum).
			var gap := randf_range(CROSSING_MIN_GAP, CROSSING_MAX_GAP)
			crossing_timer = maxf(CROSSING_MIN_GAP, gap - distance * 0.001)
			_spawn_crossing()

	# Lane closures: an outer lane ends behind a barrier, merge or crash.
	if _closed_lane >= 0 and distance > _closure_until:
		_closed_lane = -1   # the closure has fully scrolled past; reopen the lane
	if distance >= CLOSURE_FIRST_AT and _closed_lane < 0:
		closure_timer -= delta
		if closure_timer <= 0.0:
			closure_timer = randf_range(CLOSURE_MIN_GAP, CLOSURE_MAX_GAP)
			_spawn_lane_closure()

	# --- HUD + camera + shake --------------------------------------------
	hud.set_score(score)
	# Engine note revs up as we go faster.
	AudioManager.update_engine((speed - base_speed) / (MAX_SPEED - base_speed + 0.001))
	var speed_ratio: float = clampf((speed - base_speed) / (MAX_SPEED - base_speed + 0.001), 0.0, 1.0)
	player.set_speed_ratio(speed_ratio)
	_speed_lines.set_speed_ratio(speed_ratio)
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

	_sidewalk_material = StandardMaterial3D.new()
	_sidewalk_material.albedo_color = Color(0.62, 0.62, 0.64)  # pale concrete
	_sidewalk_material.roughness = 1.0

	_curb_material = StandardMaterial3D.new()
	_curb_material.albedo_color = Color(0.12, 0.12, 0.13)  # dark kerb lip
	_curb_material.roughness = 1.0

	_arrow_material = StandardMaterial3D.new()
	_arrow_material.albedo_color = Color(0.90, 0.90, 0.88)
	_arrow_material.emission_enabled = true
	_arrow_material.emission = Color(0.08, 0.08, 0.08)

	_detail_material = StandardMaterial3D.new()
	_detail_material.albedo_color = Color(0.13, 0.13, 0.14)   # dark grey (manhole/drain)
	_detail_material.roughness = 1.0

	_oil_material = StandardMaterial3D.new()
	_oil_material.albedo_color = Color(0.10, 0.10, 0.12)      # near-black oil stain
	_oil_material.roughness = 0.4
	_oil_material.metallic = 0.1

	_shoulder_material = StandardMaterial3D.new()
	_shoulder_material.albedo_color = Color(0.82, 0.75, 0.60)  # worn shoulder line
	_shoulder_material.emission_enabled = true
	_shoulder_material.emission = Color(0.04, 0.04, 0.04)


## Create the pool of road tiles once at startup.
func _build_road() -> void:
	for i in range(SEGMENT_COUNT):
		var segment := _make_road_segment()
		# Lay tiles out from just behind the player forward into the distance.
		segment.position.z = DESPAWN_Z - i * SEGMENT_LENGTH
		road_container.add_child(segment)
		_segments.append(segment)


## Build one road tile: grass + asphalt + a dash on each lane divider.
## The grass overlaps generously (green-on-green is invisible) while the road
## barely overlaps; tiles are tilted to the slope in _scroll_road so they join
## into a continuous ribbon with no seams.
func _make_road_segment() -> Node3D:
	var segment := Node3D.new()

	# Wide grass, baked into the tile so the ground rolls with the hills.
	var ground := MeshInstance3D.new()
	var ground_plane := PlaneMesh.new()
	ground_plane.size = Vector2(GROUND_WIDTH, SEGMENT_LENGTH + 1.0)
	ground.mesh = ground_plane
	ground.material_override = _ground_material
	ground.position.y = -0.04
	segment.add_child(ground)

	# Asphalt road on top, built at the WIDEST road and scaled down per section
	# in _scroll_road (tiny z overlap so tilted tiles meet without a seam).
	var road_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(MAX_ROAD_WIDTH, SEGMENT_LENGTH + 0.08)
	road_mesh.mesh = plane
	road_mesh.material_override = _road_material
	segment.add_child(road_mesh)
	segment.set_meta("asphalt", road_mesh)

	# A raised concrete sidewalk down each edge, bridging the gap between the
	# asphalt and the buildings so the street reads as one piece. _scroll_road
	# slides each one flush to the current section's road edge (narrow/widen).
	var sidewalks: Array = []
	var curbs: Array = []
	for s in [-1.0, 1.0]:
		var walk := MeshInstance3D.new()
		var slab := BoxMesh.new()
		# Slightly longer than the tile (z overlap) so tilted tiles meet seamlessly.
		slab.size = Vector3(SIDEWALK_WIDTH, 0.18, SEGMENT_LENGTH + 0.08)
		walk.mesh = slab
		walk.material_override = _sidewalk_material
		walk.set_meta("side", s)
		segment.add_child(walk)
		sidewalks.append(walk)

		# A dark kerb lip riding the road edge, proud of the pavement, to crisply
		# separate road from sidewalk.
		var curb := MeshInstance3D.new()
		var lip := BoxMesh.new()
		lip.size = Vector3(0.16, 0.24, SEGMENT_LENGTH + 0.08)
		curb.mesh = lip
		curb.material_override = _curb_material
		curb.set_meta("side", s)
		segment.add_child(curb)
		curbs.append(curb)
	segment.set_meta("sidewalks", sidewalks)
	segment.set_meta("curbs", curbs)

	# Up to 3 lane-divider dashes (enough for a 4-lane road). _scroll_road shows
	# and positions the right number for the current section's lane count.
	var dashes: Array = []
	for i in range(3):
		var dash := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.18, 0.02, SEGMENT_LENGTH * 0.5)
		dash.mesh = box
		dash.material_override = _dash_material
		dash.position = Vector3(0, 0.02, 0)
		segment.add_child(dash)
		dashes.append(dash)
	segment.set_meta("dashes", dashes)

	# Lamp posts — one per side, flushed to the road edge in _scroll_road.
	var lamp_posts: Array = []
	for s in [-1.0, 1.0]:
		var lp := _prop_factory.make("lamp-post", segment)
		lp.set_meta("side", s)
		lamp_posts.append(lp)
	segment.set_meta("lamp_posts", lamp_posts)

	# Random sidewalk clutter (bench / bin / pot / cone — 0 or 1 per tile side).
	var clutter_keys := ["bench", "trash-bin", "flower-pot", "traffic-cone", "construction-barrier"]
	for s in [-1.0, 1.0]:
		if randi() % 3 == 0:   # ~33% chance each side
			var key: String = clutter_keys[randi() % clutter_keys.size()]
			var prop := _prop_factory.make(key, segment)
			prop.set_meta("side", s)
			# Turn the prop so its long axis runs ALONG the kerb (not across the
			# road) and faces the road - otherwise benches/barriers sit sideways.
			prop.rotation_degrees.y = 90.0 if s < 0.0 else -90.0
			# Position along the tile (random z within the tile, on the sidewalk).
			prop.position.z = randf_range(-SEGMENT_LENGTH * 0.35, SEGMENT_LENGTH * 0.35)
			# X will be updated in _scroll_road like the sidewalks. Store base offset.
			prop.set_meta("sidewalk_prop", true)
			prop.set_meta("sidewalk_offset", randf_range(0.3, SIDEWALK_WIDTH - 0.5))

	# Shoulder/edge lines — two MeshInstance3Ds (one per side), x updated in _scroll_road.
	var shoulder_lines: Array = []
	for s in [-1.0, 1.0]:
		var sl := MeshInstance3D.new()
		var slm := BoxMesh.new()
		slm.size = Vector3(0.16, 0.015, SEGMENT_LENGTH + 0.08)
		sl.mesh = slm
		sl.material_override = _shoulder_material
		sl.position.y = 0.012
		sl.set_meta("side", s)
		segment.add_child(sl)
		shoulder_lines.append(sl)
	segment.set_meta("shoulder_lines", shoulder_lines)

	# Random road surface details (re-randomized on every tile recycle).
	_add_road_details(segment)

	return segment


## Re-populate one road tile with random surface details (markings, stains, covers).
## Called once on creation and again every time the tile recycles to the far end.
func _add_road_details(segment: Node3D) -> void:
	# Remove any details from a previous cycle.
	var prior: Array = segment.get_meta("detail_nodes", [])
	for n in prior:
		if is_instance_valid(n):
			n.queue_free()

	var detail_nodes: Array = []

	# (Lane arrows removed — the plain white box read as a stray block in the lane.)

	# --- Manhole cover (occasional, kept near the road edge) ---
	# Dark blobs in the driving lanes read as potholes/obstacles, so we keep only
	# the recognisable round manhole, rarely, and push it toward the kerb so the
	# centre lanes stay clean. (Asphalt patches / oil stains / storm drains were
	# removed for the same reason.)
	if randf() < 0.18:
		var mh := MeshInstance3D.new()
		var mhm := CylinderMesh.new()
		mhm.top_radius = 0.42
		mhm.bottom_radius = 0.42
		mhm.height = 0.018
		mhm.radial_segments = 12
		mh.mesh = mhm
		mh.material_override = _detail_material
		var asphalt_mi: MeshInstance3D = segment.get_meta("asphalt")
		var road_half: float = (asphalt_mi.scale.x * MAX_ROAD_WIDTH) * 0.5
		# Outer third of the road only (near the shoulder, not the racing line).
		var lane_offset: float = (1.0 if randf() < 0.5 else -1.0) * randf_range(road_half * 0.6, road_half * 0.9)
		mh.position = Vector3(lane_offset, 0.01, randf_range(-1.2, 1.2))
		segment.add_child(mh)
		detail_nodes.append(mh)

	segment.set_meta("detail_nodes", detail_nodes)


## Slide every road tile toward the player; recycle any that fall behind, and
## sit + tilt each tile on the hill/bend path so the road is one smooth ribbon.
func _scroll_road(amount: float) -> void:
	var total_length := SEGMENT_COUNT * SEGMENT_LENGTH
	var half := SEGMENT_LENGTH * 0.5
	for segment in _segments:
		segment.position.z += amount
		if segment.position.z > DESPAWN_Z + SEGMENT_LENGTH:
			# Jump it back to the far end to make the road feel endless.
			segment.position.z -= total_length
			_add_road_details(segment)   # re-randomize surface markings

		var c := segment.position.z
		var here := _path_offset(c)
		var near := _path_offset(c + half)   # edge toward the player
		var far := _path_offset(c - half)    # edge toward the horizon

		segment.position.x = here.x
		segment.position.y = here.y
		# Pitch to the slope and yaw into the bend so neighbours line up.
		segment.rotation.x = atan2(far.y - near.y, SEGMENT_LENGTH)
		segment.rotation.y = atan2(near.x - far.x, SEGMENT_LENGTH)

		# Width + lane markings for this tile's spot on the road (narrow/widen).
		var cfg := road.config_at(distance - c)
		var asphalt: MeshInstance3D = segment.get_meta("asphalt")
		asphalt.scale.x = cfg.road_width / MAX_ROAD_WIDTH

		# Sit each sidewalk just outside the (current) road edge, top a touch
		# above the asphalt so it reads as a raised kerb.
		var road_edge: float = cfg.road_width * 0.5
		var sidewalks: Array = segment.get_meta("sidewalks")
		for walk in sidewalks:
			var sgn: float = walk.get_meta("side")
			walk.position = Vector3(sgn * (road_edge + SIDEWALK_WIDTH * 0.5), 0.05, 0.0)
		var curbs: Array = segment.get_meta("curbs")
		for curb in curbs:
			var csgn: float = curb.get_meta("side")
			curb.position = Vector3(csgn * road_edge, 0.06, 0.0)

		# Keep lamp posts at the outer edge of the sidewalk.
		var lamp_posts_arr: Array = segment.get_meta("lamp_posts", [])
		for lp in lamp_posts_arr:
			var lp_sgn: float = lp.get_meta("side")
			lp.position.x = lp_sgn * (road_edge + SIDEWALK_WIDTH * 0.85)
			lp.position.y = 0.0

		# Keep sidewalk clutter props on the sidewalk.
		for child in segment.get_children():
			if child.has_meta("sidewalk_prop"):
				var sp_sgn: float = child.get_meta("side")
				var sp_off: float = child.get_meta("sidewalk_offset")
				child.position.x = sp_sgn * (road_edge + sp_off)
				child.position.y = 0.0

		# Keep shoulder/edge lines flush to the road edge.
		var shoulder_lines_arr: Array = segment.get_meta("shoulder_lines", [])
		for sl in shoulder_lines_arr:
			var sl_sgn: float = sl.get_meta("side")
			sl.position.x = sl_sgn * road_edge * 0.985   # just inside the road edge
			sl.position.y = 0.012

		var dashes: Array = segment.get_meta("dashes")
		var dividers: Array = cfg.dividers
		for i in range(dashes.size()):
			var dash: MeshInstance3D = dashes[i]
			dash.visible = i < dividers.size()
			if dash.visible:
				dash.position.x = dividers[i]


# ==========================================================================
#  CURVY WORLD (fake hills & bends)
# ==========================================================================

# Sideways displacement of the track at world position w (sweeping, sharper bends).
func _path_x(w: float) -> float:
	return (sin(w * 0.006) * 8.0 + sin(w * 0.015) * 3.5) * BEND_DIR

# Vertical displacement of the track at world position w (steeper rolling hills).
func _path_y(w: float) -> float:
	return (sin(w * 0.020) * 2.4 + cos(w * 0.045) * 1.0) * HILL_DIR

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


## Spawn a "row" of traffic at the given distance ahead. A row NEVER blocks the
## safe lane, so the road is always passable - whatever the current lane count.
## Used both for normal spawning (at SPAWN_Z) and for startup pre-population.
func _spawn_traffic_at(z: float) -> void:
	var cfg := road.config_at(distance - z)
	if cfg.is_transition:
		return   # leave the narrow/widen buffer zone clear of obstacles
	var count: int = cfg.count
	var positions: Array = cfg.positions
	var types := ["jeepney", "tricycle", "bus", "car"]

	# During a lane closure the centre lane is the guaranteed-open path, and we
	# never spawn traffic in the closed (barriered) lane.
	var closure_active := _closed_lane >= 0 and _closed_lane < count
	if closure_active:
		_safe_lane = 1
	else:
		_safe_lane = clampi(_safe_lane, 0, count - 1)

	# Lanes that are neither the guaranteed-open one nor the closed lane.
	var other_lanes: Array = []
	for lane in range(count):
		if lane != _safe_lane and lane != _closed_lane:
			other_lanes.append(lane)
	if other_lanes.is_empty():
		return   # nothing left to block (the safe lane stays open)

	# On a 2-lane road only ever block ONE lane (the other stays open). On wider
	# roads, later in the run, sometimes block ALL non-safe lanes. The safe lane
	# is NEVER blocked, so the row is always solvable.
	var block_all := count >= 3 and elapsed > 20.0 and randf() < (0.5 + events.block_both_bias())
	var blocked: Array = []
	if block_all:
		blocked = other_lanes
	else:
		blocked.append(other_lanes[randi() % other_lanes.size()])

	var traffic_speed := TRAFFIC_SPEED_FRACTION * base_speed * events.traffic_speed_mult()
	for lane in blocked:
		var vehicle := TRAFFIC_SCENE.instantiate()
		traffic_container.add_child(vehicle)
		vehicle.setup(types[randi() % types.size()])
		vehicle.position = Vector3(positions[lane], 0.0, z)
		vehicle.set_meta("bx", positions[lane])
		vehicle.set_meta("by", 0.0)
		vehicle.drive_speed = traffic_speed

	# Shift the open lane by at most one, only when more than one lane is open,
	# so the player can always follow it with a single swipe. (Pinned to centre
	# during a closure.)
	if not block_all and not closure_active:
		_safe_lane = clampi(_safe_lane + (randi() % 3 - 1), 0, count - 1)


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

		# Vehicles (not pedestrians, who don't drive forward) slowly drift through
		# the world as they're overtaken. If one drifts into a transition or into a
		# section where its lane no longer exists, it would become an unfair,
		# undodgeable block - so it steers off to the shoulder and leaves.
		if vehicle is TrafficVehicle:
			_handle_lane_merge(vehicle, delta)

		_apply_path(vehicle)
		_check_near_miss(vehicle)
		if vehicle.position.z > DESPAWN_Z:
			vehicle.queue_free()


## True if `bx` is (close to) a valid lane centre at this world config and we're
## not in a transition - i.e. a car sitting at bx is in a real, drivable lane.
func _lane_valid_at(bx: float, cfg: Dictionary) -> bool:
	if cfg.is_transition:
		return false
	for x in cfg.positions:
		if absf(bx - x) <= LANE_MATCH_TOL:
			return true
	return false


## If a vehicle's lane has vanished (road narrowing), retire it gracefully: kill
## its collision immediately (so it can never cause an unfair hit) and steer it
## off toward the nearest shoulder, then free it once it's clear of the asphalt.
func _handle_lane_merge(vehicle: TrafficVehicle, delta: float) -> void:
	var bx: float = vehicle.get_meta("bx", 0.0)

	if not vehicle.has_meta("merge_dir"):
		# Only react while the car is still AHEAD of the player (z < 0); cars are
		# always ahead until overtaken, so this fires near the narrowing, never
		# right beside the player.
		if vehicle.position.z >= 0.0:
			return
		var cfg := road.config_at(distance - vehicle.position.z)
		if _lane_valid_at(bx, cfg):
			return
		# Doomed: pick the nearer shoulder and disable collision so it's harmless.
		vehicle.set_meta("merge_dir", signf(bx) if absf(bx) > 0.01 else -1.0)
		vehicle.collision_layer = 0

	# Slide outward toward the shoulder; free once fully off the road.
	var dir: float = vehicle.get_meta("merge_dir")
	bx += dir * MERGE_OFF_SPEED * delta
	vehicle.set_meta("bx", bx)
	var edge: float = road.config_at(distance - vehicle.position.z).road_width * 0.5
	if absf(bx) > edge + 2.0:
		vehicle.queue_free()


## A "near miss" is when traffic passes the player in an ADJACENT lane without
## hitting them. We give a tiny score bonus and a little juice for the thrill.
func _check_near_miss(vehicle: Node3D) -> void:
	if vehicle.has_meta("passed"):
		return
	if vehicle.position.z >= player.position.z:
		vehicle.set_meta("passed", true)
		var dx := absf(vehicle.position.x - player.position.x)
		# Only a genuine dodge counts: the vehicle is in the adjacent lane
		# (> 1.2 = not a hit, < 3.2 = next lane, not two away) AND the player
		# actually swerved lanes just now. Cruising past traffic no longer fires.
		if dx > 1.2 and dx < 3.2 and player.recently_changed_lane():
			_on_near_miss()


# ==========================================================================
#  PEDESTRIAN CROSSINGS
# ==========================================================================

## Spawn a zebra crossing with a few people walking across it. Like a traffic
## row it leaves the safe lane clear, so there is always a way through, and it
## never appears inside a road transition.
func _spawn_crossing() -> void:
	var cfg := road.config_at(distance - SPAWN_Z)
	if cfg.is_transition:
		return   # keep the narrow/widen buffer clear
	var count: int = cfg.count
	var positions: Array = cfg.positions

	# Keep the guaranteed-open lane valid for this section's lane count.
	_safe_lane = clampi(_safe_lane, 0, count - 1)

	# Paint the zebra crossing across the road at this spot (purely visual; it
	# scrolls with the world via the crossing container).
	_spawn_zebra(cfg.road_width, SPAWN_Z)

	# A person in every lane EXCEPT the safe one, so the crossing is passable.
	for lane in range(count):
		if lane == _safe_lane:
			continue
		var ped := PEDESTRIAN_SCRIPT.new()
		# Set position + base x BEFORE adding to the tree so the pedestrian's
		# _ready picks up its true spawn lane as the centre of its walk.
		ped.position = Vector3(positions[lane], 0.0, SPAWN_Z)
		ped.set_meta("bx", positions[lane])
		ped.set_meta("by", 0.0)
		# Stroll slowly left or right (random direction) for a bit of life.
		ped.walk_speed = CROSSING_WALK_SPEED * (1.0 if randf() < 0.5 else -1.0)
		traffic_container.add_child(ped)

	# Let the open lane drift by one so consecutive hazards still flow naturally.
	_safe_lane = clampi(_safe_lane + (randi() % 3 - 1), 0, count - 1)


## Build the white zebra stripes spanning the road width at world position z.
func _spawn_zebra(width: float, z: float) -> void:
	var holder := Node3D.new()
	crossing_container.add_child(holder)
	# Stripes run along the travel direction (Z) and repeat across the road (X).
	var stripe_count := int(width / 0.7)
	for i in range(stripe_count):
		var stripe := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.32, 0.02, 3.4)
		stripe.mesh = box
		stripe.material_override = _dash_material
		stripe.position = Vector3((i - (stripe_count - 1) * 0.5) * 0.7, 0.03, 0.0)
		holder.add_child(stripe)
	holder.position = Vector3(0.0, 0.0, z)
	holder.set_meta("bx", 0.0)
	holder.set_meta("by", 0.0)


func _scroll_crossings(amount: float) -> void:
	for mark in crossing_container.get_children():
		mark.position.z += amount
		_apply_path(mark)
		# Long flat surfaces (the construction patch) pitch/yaw to the road's
		# slope at their position so they hug the hills/bends instead of lifting
		# off at the ends. (Set via a "tilt_len" meta = the surface's length.)
		var tl: float = mark.get_meta("tilt_len", 0.0)
		if tl > 0.0:
			var c: float = mark.position.z
			var half := tl * 0.5
			var near := _path_offset(c + half)
			var far := _path_offset(c - half)
			mark.rotation.x = atan2(far.y - near.y, tl)
			mark.rotation.y = atan2(near.x - far.x, tl)
		# Long surfaces set a bigger despawn_z so they don't vanish while a chunk
		# is still in view.
		var dz: float = mark.get_meta("despawn_z", DESPAWN_Z)
		if mark.position.z > dz:
			mark.queue_free()


# ==========================================================================
#  LANE CLOSURES  ("the outer lane just ends - merge or crash")
# ==========================================================================

## Close one OUTER lane: a run of cones funnels into a construction-barrier wall
## that blocks the lane. The player must merge inward before reaching the wall.
## The centre lane is forced open for the whole closure, so it's always passable.
## The cone/barrier obstacles live in traffic_container (so they scroll, collide
## and despawn like traffic) and are static (drive_speed 0).
func _spawn_lane_closure() -> void:
	var cfg := road.config_at(distance - SPAWN_Z)
	if cfg.is_transition:
		return
	var count: int = cfg.count
	if count < 3:
		return   # need a spare outer lane to close while keeping the road open
	var positions: Array = cfg.positions

	# Pick an outer lane (leftmost or rightmost) and pin the centre lane open.
	_closed_lane = 0 if randf() < 0.5 else count - 1
	_safe_lane = 1
	_closure_until = distance + 210.0   # ~a full SPAWN_Z -> DESPAWN_Z pass
	var lane_x: float = positions[_closed_lane]
	var lane_w: float = RoadManager.LANE_WIDTH

	# The barrier wall faces the player at the NEAR end of the closure (reached
	# first); the dug-up road stretches behind it toward the horizon.
	var wall_z := SPAWN_Z + CLOSURE_LENGTH

	# Clear any traffic already sitting in the dug-up part of the closing lane
	# (it's far ahead, so removal is unseen) - otherwise a vehicle drives over
	# the dirt and through the barriers, which looks like a bug.
	for v in traffic_container.get_children():
		if v is TrafficVehicle and v.position.z <= wall_z + 8.0 \
				and absf(v.get_meta("bx", 999.0) - lane_x) < 1.0:
			v.queue_free()
	# Same for coins already in the closing lane, so none sit on the dirt.
	for c in coin_container.get_children():
		if c.position.z <= wall_z + 8.0 and absf(c.get_meta("bx", 999.0) - lane_x) < 1.0:
			c.queue_free()

	# Torn-up "under construction" dirt road filling the closed lane behind the
	# barrier (visual only; scrolls with the world via crossing_container).
	var surf := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(lane_w * 0.92, CLOSURE_LENGTH)
	surf.mesh = pm
	surf.material_override = _get_construction_material()
	crossing_container.add_child(surf)
	surf.position = Vector3(lane_x, 0.013, SPAWN_Z + CLOSURE_LENGTH * 0.5)
	surf.set_meta("bx", lane_x)
	surf.set_meta("by", 0.013)
	surf.set_meta("despawn_z", DESPAWN_Z + CLOSURE_LENGTH * 0.5 + 4.0)
	surf.set_meta("tilt_len", CLOSURE_LENGTH)   # hug the road's slope

	# The barrier wall that ends the lane (collider spans the lane - no squeezing
	# past). It's a normal "traffic" obstacle, so hitting it crashes you.
	var wall := OBSTACLE_SCRIPT.new()
	wall.setup(_prop_factory, "construction-barrier", Vector3(lane_w, 1.0, 0.6))
	traffic_container.add_child(wall)
	wall.position = Vector3(lane_x, 0.0, wall_z)
	wall.set_meta("bx", lane_x)
	wall.set_meta("by", 0.0)

	# A couple more barriers lining the dug-up stretch behind the wall for the
	# construction-zone look (the player never reaches them - they merge first).
	for i in range(2):
		var b := OBSTACLE_SCRIPT.new()
		b.setup(_prop_factory, "construction-barrier", Vector3(lane_w * 0.9, 1.0, 0.6))
		traffic_container.add_child(b)
		var bz := wall_z - 12.0 - i * 12.0
		b.position = Vector3(lane_x, 0.0, bz)
		b.set_meta("bx", lane_x)
		b.set_meta("by", 0.0)


## Dirt/rubble surface for a closed (under-construction) lane. Built once. Uses a
## tiled noise texture so it reads as real dug-up ground, not a flat slab.
func _get_construction_material() -> StandardMaterial3D:
	if _construction_material == null:
		_construction_material = StandardMaterial3D.new()
		_construction_material.roughness = 1.0
		if ResourceLoader.exists("res://effects/dirt.png"):
			_construction_material.albedo_texture = load("res://effects/dirt.png")
			# Tile the texture down the strip so it isn't stretched.
			var reps: float = CLOSURE_LENGTH / (RoadManager.LANE_WIDTH * 0.92)
			_construction_material.uv1_scale = Vector3(1.0, reps, 0.0)
		else:
			_construction_material.albedo_color = Color(0.42, 0.32, 0.18)  # fallback brown
	return _construction_material


# ==========================================================================
#  COINS
# ==========================================================================

## Spawn a short line of coins in one lane - more satisfying than singles.
## We use the safe lane so the coins gently guide the player along the open path.
func _spawn_coin_line() -> void:
	var cfg := road.config_at(distance - SPAWN_Z)
	if cfg.is_transition:
		return
	var lane_x: float = cfg.positions[clampi(_safe_lane, 0, cfg.count - 1)]
	# Coin-rich events (fiesta/market) add extra coins to each line.
	var count := randi_range(3, 5) + events.coin_line_bonus()
	for i in range(count):
		var coin := COIN_SCENE.instantiate()
		coin_container.add_child(coin)
		coin.position = Vector3(lane_x, 0.7, SPAWN_Z - i * 2.2)
		coin.set_meta("bx", lane_x)
		coin.set_meta("by", 0.7)


func _scroll_coins(amount: float) -> void:
	var magnet := powerups.magnet_active()
	for coin in coin_container.get_children():
		coin.position.z += amount
		_apply_path(coin)
		# Coin magnet: pull nearby (ahead) coins toward the player so the
		# existing area_entered collection picks them up.
		if magnet and not coin.is_collected():
			var dz: float = coin.position.z - player.position.z
			if dz < powerups.magnet_range() and dz > -3.0:
				coin.position.x = lerp(coin.position.x, player.position.x, 0.18)
				coin.position.z = lerp(coin.position.z, player.position.z, 0.18)
		if coin.position.z > DESPAWN_Z:
			# A coin that scrolled past uncollected breaks the combo streak.
			if not coin.is_collected():
				combo.on_miss()
				hud.set_combo(0, 1)
			coin.queue_free()


func _spawn_powerup() -> void:
	# Power-ups appear in the current safe lane so they're always reachable.
	var cfg := road.config_at(distance - SPAWN_Z)
	if cfg.is_transition:
		return
	var lane_x: float = cfg.positions[clampi(_safe_lane, 0, cfg.count - 1)]
	var pu = POWERUP_SCRIPT.new()
	powerup_container.add_child(pu)
	pu.setup(POWERUP_KINDS[randi() % POWERUP_KINDS.size()])
	pu.position = Vector3(lane_x, 0.0, SPAWN_Z)
	pu.set_meta("bx", lane_x)
	pu.set_meta("by", 0.0)


func _scroll_powerups(amount: float) -> void:
	for pu in powerup_container.get_children():
		pu.position.z += amount
		_apply_path(pu)
		if pu.position.z > DESPAWN_Z:
			pu.queue_free()


## Scroll birds with the world and add a gentle drift + fake flap.
func _scroll_birds(amount: float, delta: float) -> void:
	for bird in _birds:
		var b := bird as MeshInstance3D
		b.position.z += amount
		b.position.x += (b.get_meta("drift_x") as float) * delta
		# Fake wing-flap by oscillating the y-scale.
		var phase: float = b.get_meta("flap_phase")
		b.scale.y = 1.0 + 0.40 * sin(elapsed * 5.8 + phase)
		# Wrap behind camera → respawn at horizon.
		if b.position.z > DESPAWN_Z + 5.0:
			b.position.z = SPAWN_Z - randf_range(0.0, 50.0)
			b.position.x = randf_range(-12.0, 12.0)
			b.position.y = randf_range(14.0, 22.0)
			b.set_meta("drift_x", randf_range(-0.9, 0.9))


## Scroll clouds with the world and a gentle horizontal drift.
func _scroll_clouds(amount: float, delta: float) -> void:
	for cloud in _clouds:
		var c := cloud as MeshInstance3D
		c.position.z += amount
		c.position.x += (c.get_meta("drift_x") as float) * delta
		if c.position.z > DESPAWN_Z + 20.0:
			c.position.z = SPAWN_Z - randf_range(0.0, 40.0)
			c.position.x = randf_range(-20.0, 20.0)
			c.position.y = randf_range(28.0, 46.0)
			c.set_meta("drift_x", randf_range(-0.35, 0.35))


# ==========================================================================
#  ROADSIDE SCENERY (buildings & trees)
# ==========================================================================

## Fill both road sides with a continuous wall of scenery at startup.
func _prewarm_scenery() -> void:
	_fill_scenery()


## Recursively apply the wind ShaderMaterial to every MeshInstance3D under root.
## Copies albedo_color and albedo_texture from the original StandardMaterial3D.
func _apply_wind_to_tree(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		var sm := ShaderMaterial.new()
		sm.shader = WIND_SHADER
		var orig = mi.get_active_material(0)
		if orig != null and orig is StandardMaterial3D:
			var std_mat := orig as StandardMaterial3D
			sm.set_shader_parameter("albedo_color", std_mat.albedo_color)
			if std_mat.albedo_texture != null:
				sm.set_shader_parameter("albedo_tex", std_mat.albedo_texture)
		mi.material_override = sm
	for child in root.get_children():
		_apply_wind_to_tree(child)


## Top up each side's street wall so buildings always reach out to SPAWN_Z. As
## the world scrolls the far edge of each row drifts toward the player, opening a
## gap at the horizon that we immediately refill - giving a seamless frontage.
func _fill_scenery() -> void:
	_wall_z_left = _fill_side(-1.0, _wall_z_left)
	_wall_z_right = _fill_side(1.0, _wall_z_right)


func _fill_side(side: float, wall_z: float) -> float:
	# Keep extending this side's row toward the horizon until it passes SPAWN_Z.
	while wall_z > SPAWN_Z:
		wall_z = _spawn_scenery(side, wall_z)
	return wall_z


## Place ONE prop on the given side whose NEAR edge sits at wall_z, and return the
## new far edge (so the next prop butts up against this one). Buildings face the
## road so the row reads as a real street rather than scattered boxes.
func _spawn_scenery(side: float, wall_z: float) -> float:
	var holder: Node3D
	var gap: float          # extra setback from the road edge
	var faces_road := true  # buildings/landmarks turn their front to the street
	var scene_type := districts.pick_type(distance)
	if scene_type == "tree":
		# A clump of trees right at the kerb (small, breaks up the frontage).
		var variant := districts.pick_tree_variant(distance)
		var model := ModelUtil.hd_load(TREE_MODELS[clampi(variant, 0, TREE_MODELS.size() - 1)])
		holder = ModelUtil.instance_fitted(scenery_container, model, Vector3(3, randf_range(3.0, 5.0), 3), "height", 0.0)
		gap = randf_range(0.2, 1.0)
		faces_road = false
		_apply_wind_to_tree(holder)
	elif scene_type == "landmark" and LANDMARK_MODELS.size() > 0:
		# A recognisable landmark (Jollibee, church, Petron...), facing the road.
		var lm_idx := districts.pick_landmark_idx(distance)
		var model := ModelUtil.hd_load(LANDMARK_MODELS[clampi(lm_idx, 0, LANDMARK_MODELS.size() - 1)])
		holder = ModelUtil.instance_fitted(scenery_container, model, Vector3(9, randf_range(8.0, 11.0), 9), "height", 0.0)
		gap = randf_range(0.6, 1.4)
	else:
		# A generic building, hugging the road to form the street wall.
		var model := ModelUtil.hd_load(BUILDING_MODELS[randi() % BUILDING_MODELS.size()])
		holder = ModelUtil.instance_fitted(scenery_container, model, Vector3(8, randf_range(7.0, 16.0), 8), "height", 0.0)
		gap = randf_range(0.5, 1.8)

	if faces_road:
		# Front toward the road (auto-flip on the right side), with a tiny jitter
		# so the row isn't unnaturally perfect.
		var flip := 0.0 if side < 0.0 else 180.0
		holder.rotation_degrees.y = LANDMARK_YAW + flip + randf_range(-4.0, 4.0)
	else:
		holder.rotate_y(randf_range(0.0, TAU))

	# Pack along Z by the prop's own footprint depth so neighbours touch. The
	# floor guarantees the cursor always advances (no stuck fill loop).
	var radius := ModelUtil.footprint_radius(holder)
	var depth: float = maxf(radius * 2.0, 2.0)
	var center_z := wall_z - depth * 0.5

	# Push out by the footprint so the edge always clears the (variable-width) road.
	var road_edge: float = road.config_at(distance - center_z).road_width * 0.5
	holder.position = Vector3(side * (road_edge + gap + radius), 0.0, center_z)
	holder.set_meta("bx", holder.position.x)
	holder.set_meta("by", 0.0)

	# Occasionally park a scooter or jeepney alongside buildings (not trees).
	if faces_road and randf() < 0.18:
		var ambient_model := ""
		var r2 := randf()
		if r2 < 0.5:
			ambient_model = PARKED_SCOOTER_MODEL
		elif r2 < 0.75:
			ambient_model = PARKED_JEEPNEY_MODEL
		else:
			ambient_model = AMBIENT_PERSON_MODEL
		var is_vehicle := r2 < 0.75   # scooter or jeepney (the person is not)
		var ambient := ModelUtil.instance_fitted(scenery_container, ModelUtil.hd_load(ambient_model),
			Vector3(2, 1.8, 2), "height", 0.0)
		# Park right at the kerb (just past the road edge), well in FRONT of the
		# building. A conservative half-width keeps even the wide jeepney clear.
		var park_half := 0.9
		ambient.position = Vector3(
			side * (road_edge + 0.25 + park_half),
			0.0, center_z + randf_range(-depth * 0.2, depth * 0.2))
		ambient.set_meta("bx", ambient.position.x)
		ambient.set_meta("by", 0.0)
		if is_vehicle:
			# Set THIS building back so the parked vehicle can't clip into it, and
			# keep its bx meta in sync (the scroll re-reads bx every frame, so a
			# stale value would snap the building forward again).
			var min_center: float = road_edge + 0.25 + 2.0 * park_half + 0.3 + radius
			holder.position.x = side * maxf(road_edge + gap + radius, min_center)
			holder.set_meta("bx", holder.position.x)
			# A parked vehicle sits PARALLEL to the road, facing the way traffic
			# flows (yaw 270), occasionally the other way.
			var heading := 270.0 if randf() < 0.7 else 90.0
			ambient.rotation_degrees.y = heading + randf_range(-5.0, 5.0)
		else:
			# A person stands FACING the road (auto-flip per side).
			var af := 0.0 if side < 0.0 else 180.0
			ambient.rotation_degrees.y = af + randf_range(-15.0, 15.0)

	return wall_z - depth - SCENERY_GAP


func _scroll_scenery(amount: float) -> void:
	# The far-edge cursors ride along with the row as it scrolls.
	_wall_z_left += amount
	_wall_z_right += amount
	for prop in scenery_container.get_children():
		prop.position.z += amount
		_apply_path(prop)
		if prop.position.z > DESPAWN_Z + 6.0:
			prop.queue_free()
	# Refill the horizon end now that everything has moved forward.
	_fill_scenery()


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

	# Widen the field of view as we speed up = sense of speed (range chosen for
	# the window's aspect in _ready).
	var speed_ratio: float = clamp((speed - base_speed) / (MAX_SPEED - base_speed + 0.001), 0.0, 1.0)
	camera.fov = lerp(_fov_lo, _fov_hi, speed_ratio)


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
	score_value += 25.0 * combo.multiplier()
	_add_shake(NEAR_MISS_SHAKE_STRENGTH, NEAR_MISS_SHAKE_DURATION)
	hud.flash_near_miss()
	AudioManager.play_sfx("near_miss")
	MissionManager.report("near_miss", 1)


func _on_coin_collected(amount: int) -> void:
	# The coin-multiplier power-up doubles the coins each pickup is worth.
	var added := amount * powerups.coin_value_mult()
	run_coins += added
	hud.set_run_coins(run_coins)
	hud.pulse_coin()
	MissionManager.report("coins", added)

	# Grow the combo and raise the coin pitch with the multiplier.
	var milestone := combo.on_coin()
	hud.set_combo(combo.count, combo.multiplier(), milestone)
	AudioManager.play_sfx("coin", 1.0 + combo.multiplier() * 0.08)


func _on_powerup_collected(kind: String) -> void:
	powerups.activate(kind)
	AudioManager.play_sfx("powerup")


func _on_shielded() -> void:
	AudioManager.play_sfx("shield")
	_add_shake(SHIELD_SHAKE_STRENGTH, SHIELD_SHAKE_DURATION)


# ==========================================================================
#  RANDOM EVENTS (banner + rainstorm visuals)
# ==========================================================================

func _on_event_started(display_name: String) -> void:
	hud.show_event_banner(display_name)
	if events.is_raining():
		_set_rain(true)


func _on_event_ended() -> void:
	_set_rain(false)


## Smoothly shift ground, ambient and sun colours to match the current district.
## Fog colour is also shifted unless a rainstorm is overriding it.
func _update_district_atmosphere(delta: float) -> void:
	var rate: float = delta * 0.4   # slow lerp so transitions are never jarring

	_ground_material.albedo_color = _ground_material.albedo_color.lerp(
		districts.get_ground_color(distance), rate)

	_env.ambient_light_color = _env.ambient_light_color.lerp(
		districts.get_ambient_color(distance), rate)

	sun.light_color = sun.light_color.lerp(
		districts.get_sun_color(distance), rate)

	if not events.is_raining():
		_env.fog_light_color = _env.fog_light_color.lerp(
			districts.get_fog_color(distance), rate)


## Build the rain emitter once (idle until a rainstorm event). Parented to the
## camera so it always falls in view; modest particle count for mobile.
func _build_rain() -> void:
	_rain = GPUParticles3D.new()
	_rain.amount = 220
	_rain.lifetime = 1.2
	_rain.emitting = false
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-24, -16, -30), Vector3(48, 32, 48))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16, 0.5, 20)
	pm.direction = Vector3(0, -1, 0)
	pm.gravity = Vector3(0, -35, 0)
	pm.initial_velocity_min = 14.0
	pm.initial_velocity_max = 18.0
	_rain.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.8, 0.95, 0.7)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	_rain.draw_pass_1 = quad

	_rain.position = Vector3(0, 12, -12)   # above and ahead of the camera
	camera.add_child(_rain)


## Creates BIRD_COUNT billboard quad "birds" high in the sky.
func _build_birds() -> void:
	for i in range(BIRD_COUNT):
		var bird := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(randf_range(0.5, 0.9), randf_range(0.18, 0.32))
		bird.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.14, 0.14, 0.16)
		mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		bird.material_override = mat
		bird.position = Vector3(
			randf_range(-12.0, 12.0),
			randf_range(14.0, 22.0),
			randf_range(SPAWN_Z, SPAWN_Z - 40.0)
		)
		bird.set_meta("drift_x", randf_range(-0.9, 0.9))
		bird.set_meta("flap_phase", randf() * TAU)
		add_child(bird)
		_birds.append(bird)


## Creates CLOUD_COUNT semi-transparent billboard quads high in the sky.
func _build_clouds() -> void:
	for i in range(CLOUD_COUNT):
		var cloud := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(randf_range(5.0, 9.0), randf_range(1.8, 3.2))
		cloud.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_color  = Color(0.97, 0.97, 0.98, 0.55)
		mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		cloud.material_override = mat
		# Spread across the full visible Z range so there's no all-at-once pop-in.
		cloud.position = Vector3(
			randf_range(-20.0, 20.0),
			randf_range(28.0, 46.0),
			randf_range(SPAWN_Z - 10.0, DESPAWN_Z)
		)
		cloud.set_meta("drift_x", randf_range(-0.35, 0.35))
		add_child(cloud)
		_clouds.append(cloud)


## Toggle the rainstorm look: rain particles + a light fog faded in/out. This is
## the ONLY place fog is used - normal play stays clear (fog is off by default).
func _set_rain(on: bool) -> void:
	_rain.emitting = on
	if on:
		_env.fog_light_color = Color(0.6, 0.65, 0.72)
		_env.fog_density = 0.0
		_env.fog_enabled = true
	var tween := create_tween()
	tween.tween_property(_env, "fog_density", 0.035 if on else 0.0, 0.8)
	if not on:
		tween.tween_callback(func(): _env.fog_enabled = false)


# ==========================================================================
#  GAME OVER
# ==========================================================================

func _on_player_crashed() -> void:
	if not playing:
		return
	playing = false
	_add_shake(CRASH_SHAKE_STRENGTH, CRASH_SHAKE_DURATION)   # a hard jolt on impact
	AudioManager.stop_engine()        # the engine cuts out on impact
	AudioManager.play_sfx("crash")
	AudioManager.play_sfx("scream")   # the rider yelps as he's flung off
	combo.on_crash()
	hud.set_combo(0, 1)
	hud.hide_pause_button()   # can't pause once the run is over

	# Bank the coins from this run into the player's permanent total (saves).
	GameData.add_coins(run_coins)

	# Record a new best score (persisted) and update the HUD badge.
	if GameData.record_score(score):
		GameData.save_game()
		hud.set_best(GameData.best_score)

	# Record run-based mission progress, then persist it once.
	MissionManager.report("distance", int(distance))
	MissionManager.report("score", score)
	MissionManager.report("runs", 1)
	MissionManager.save_now()

	# Pause so the crash + rider tumble play out, then show the game-over screen.
	await get_tree().create_timer(1.2).timeout
	game_over.show_screen(score, run_coins, GameData.total_coins)
