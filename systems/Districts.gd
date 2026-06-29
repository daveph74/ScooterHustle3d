class_name Districts
extends RefCounted

## Districts — data-driven district system for Scooter Hustle.
##
## Divides the endless run into 6 repeating Philippine-themed districts.
## Each district has its own building/landmark/tree mix and colour palette
## (ground, ambient light, sun, fog). Transitions blend smoothly over
## TRANSITION_BAND metres.

const DISTRICT_LENGTH := 400.0   # metres of each district before cycling
const TRANSITION_BAND := 80.0    # metres over which colours blend at transitions

# 6 Philippine-themed districts. Plain untyped array to satisfy Godot 4.7.
var _districts: Array = [
	# 0: Downtown
	{
		"name": "Downtown",
		"tree_weight": 0.10,
		"landmark_weight": 0.35,
		"landmark_pool": [0, 2, 3, 5, 6, 7, 8, 10, 11],  # jollibee, insal, petron, 711, chowking, lto, pharmacy, bpo, pawnshop
		"ground_color": Color(0.36, 0.36, 0.37),
		"ambient_color": Color(1.00, 0.96, 0.93),
		"sun_color":     Color(1.00, 0.96, 0.86),
		"fog_color":     Color(0.92, 0.86, 0.74),
	},
	# 1: Barangay
	{
		"name": "Barangay",
		"tree_weight": 0.25,
		"landmark_weight": 0.30,
		"landmark_pool": [1, 2, 3, 4, 9],  # church, insal, petron, sari-sari, barangay_hall
		"ground_color": Color(0.36, 0.40, 0.26),
		"ambient_color": Color(1.00, 0.97, 0.88),
		"sun_color":     Color(1.00, 0.97, 0.82),
		"fog_color":     Color(1.00, 0.88, 0.68),
	},
	# 2: Residential
	{
		"name": "Residential",
		"tree_weight": 0.35,
		"landmark_weight": 0.20,
		"landmark_pool": [1, 4, 9, 12],  # church, sari-sari, barangay_hall, school
		"ground_color": Color(0.30, 0.44, 0.22),
		"ambient_color": Color(1.00, 0.98, 0.90),
		"sun_color":     Color(1.00, 0.95, 0.80),
		"fog_color":     Color(0.88, 0.90, 0.70),
	},
	# 3: Provincial
	{
		"name": "Provincial",
		"tree_weight": 0.35,
		"landmark_weight": 0.25,
		"landmark_pool": [1, 3, 4, 12],  # church, petron, sari-sari, school
		"ground_color": Color(0.40, 0.42, 0.24),
		"ambient_color": Color(1.00, 0.96, 0.82),
		"sun_color":     Color(1.00, 0.94, 0.72),
		"fog_color":     Color(1.00, 0.85, 0.62),
	},
	# 4: Beach Road
	{
		"name": "Beach Road",
		"tree_weight": 0.50,
		"landmark_weight": 0.20,
		"landmark_pool": [3, 4, 8],  # petron, sari-sari, pharmacy
		"ground_color": Color(0.80, 0.74, 0.50),
		"ambient_color": Color(1.00, 0.99, 0.93),
		"sun_color":     Color(1.00, 0.97, 0.88),
		"fog_color":     Color(1.00, 0.92, 0.78),
	},
	# 5: Fiesta
	{
		"name": "Fiesta",
		"tree_weight": 0.10,
		"landmark_weight": 0.40,
		"landmark_pool": [0, 1, 2, 4, 6, 8, 11],  # jollibee, church, insal, sari-sari, chowking, pharmacy, pawnshop
		"ground_color": Color(0.40, 0.34, 0.22),
		"ambient_color": Color(1.00, 0.95, 0.78),
		"sun_color":     Color(1.00, 0.92, 0.68),
		"fog_color":     Color(1.00, 0.82, 0.58),
	},
]


## Returns [current_idx, next_idx, blend] for a given travel distance.
## blend is 0.0 at the start of a district, rising to 1.0 at the end
## (over the TRANSITION_BAND window).
func _idx_and_blend(dist: float) -> Array:
	var phase: float = dist / DISTRICT_LENGTH
	var current_idx: int = int(phase) % 6
	var next_idx: int = (current_idx + 1) % 6
	var frac: float = fmod(dist, DISTRICT_LENGTH) / DISTRICT_LENGTH  # 0.0 -> 1.0

	# Smoothstep blend that only rises in the final TRANSITION_BAND metres.
	var edge0: float = 1.0 - TRANSITION_BAND / DISTRICT_LENGTH
	var t: float = clampf((frac - edge0) / (TRANSITION_BAND / DISTRICT_LENGTH), 0.0, 1.0)
	var blend: float = t * t * (3.0 - 2.0 * t)

	return [current_idx, next_idx, blend]


## Returns the name of the current district.
func district_name(dist: float) -> String:
	var info := _idx_and_blend(dist)
	return _districts[info[0]].name


## Pick scenery type: "tree", "landmark", or "building".
## Uses the current district's tree/landmark weights (blends weights at transitions).
func pick_type(dist: float) -> String:
	var info := _idx_and_blend(dist)
	var cur: Dictionary = _districts[info[0]]
	var nxt: Dictionary = _districts[info[1]]
	var blend: float = info[2]
	var tw: float = lerpf(cur.tree_weight, nxt.tree_weight, blend)
	var lw: float = lerpf(cur.landmark_weight, nxt.landmark_weight, blend)
	var r := randf()
	if r < tw:
		return "tree"
	elif r < tw + lw:
		return "landmark"
	return "building"


## Pick a landmark index from the current district's pool.
## Weights toward the next district's pool during transitions.
func pick_landmark_idx(dist: float) -> int:
	var info := _idx_and_blend(dist)
	var cur: Dictionary = _districts[info[0]]
	var nxt: Dictionary = _districts[info[1]]
	var pool: Array = cur.landmark_pool if randf() > info[2] else nxt.landmark_pool
	return pool[randi() % pool.size()]


## Pick a tree variant index (0 = palm-tree, 1 = grass-trees, 2 = grass-trees-tall).
## Beach Road and Residential prefer taller Kenney trees.
func pick_tree_variant(dist: float) -> int:
	var info := _idx_and_blend(dist)
	# Stochastically blend between current and next district at transitions.
	var idx: int = info[1] if randf() < info[2] else info[0]
	if idx == 4:   # Beach Road: all three variants equally
		return randi() % 3
	elif idx == 2: # Residential: 50% palm, 50% Kenney (grass-trees or grass-trees-tall)
		return 0 if randf() < 0.5 else (1 + randi() % 2)
	return 0   # all other districts: palm only


## Lerped ground colour for the current distance.
func get_ground_color(dist: float) -> Color:
	var info := _idx_and_blend(dist)
	return (_districts[info[0]].ground_color as Color).lerp(
		_districts[info[1]].ground_color, info[2])


## Lerped ambient light colour.
func get_ambient_color(dist: float) -> Color:
	var info := _idx_and_blend(dist)
	return (_districts[info[0]].ambient_color as Color).lerp(
		_districts[info[1]].ambient_color, info[2])


## Lerped sun colour.
func get_sun_color(dist: float) -> Color:
	var info := _idx_and_blend(dist)
	return (_districts[info[0]].sun_color as Color).lerp(
		_districts[info[1]].sun_color, info[2])


## Lerped fog colour (used by atmosphere update — not set during rain).
func get_fog_color(dist: float) -> Color:
	var info := _idx_and_blend(dist)
	return (_districts[info[0]].fog_color as Color).lerp(
		_districts[info[1]].fog_color, info[2])
