extends RefCounted
class_name RoadManager
## The single source of truth for "what lanes exist at a point on the road".
##
## The road is a SCHEDULE of sections (3, 2 or 4 lanes) joined by short
## obstacle-free TRANSITION zones where the road visibly narrows/widens. Lane
## layout is tied to WORLD POSITION (metres travelled), not to live nodes:
## something spawned at world W keeps W as it scrolls toward the player, so its
## lanes never change mid-flight and automatically match the player (who is
## always at world = distance) when they meet. Everything just asks
## config_at(world).
##
## To add a new road type later, return its lane count from _pick_next_count();
## lane_positions()/road_width()/divider_positions() handle any count for free.

const LANE_WIDTH := 2.5
const SHOULDER := 0.75           # grass margin each side of the lanes
const MIN_LANES := 2
const MAX_LANES := 4
const TRANSITION_LEN := 14.0     # obstacle-free warning/blend zone between counts

# --- Difficulty knobs (tune road variety here) ----------------------------
const ALL_3_UNTIL := 400.0       # only plain 3-lane road before this distance
const ALLOW_4_AFTER := 1000.0    # 4-lane sections only appear after this
const SECTION_MIN := 55.0        # length range of a normal section (metres)
const SECTION_MAX := 95.0

var _sections: Array = []        # {start, end, count, kind, from_count, to_count}
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()
	# Start on a comfortable stretch of 3-lane road.
	_sections.append({
		"start": 0.0, "end": SECTION_MAX, "count": 3,
		"kind": "road", "from_count": 3, "to_count": 3,
	})


# --- Pure lane math (any count) -------------------------------------------

## World X of each lane centre for a given lane count, centred on the road.
static func lane_positions(count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append((i - (count - 1) * 0.5) * LANE_WIDTH)
	return out


## Total asphalt width for a lane count (lanes + a shoulder each side).
static func road_width(count: int) -> float:
	return count * LANE_WIDTH + 2.0 * SHOULDER


## X of each lane divider (there are count-1 of them, between the lanes).
static func divider_positions(count: int) -> Array:
	var out: Array = []
	for i in range(count - 1):
		out.append((i + 0.5 - (count - 1) * 0.5) * LANE_WIDTH)
	return out


func max_road_width() -> float:
	return road_width(MAX_LANES)


# --- Schedule generation --------------------------------------------------

func _last_road_count() -> int:
	for i in range(_sections.size() - 1, -1, -1):
		if _sections[i].kind == "road":
			return _sections[i].count
	return 3


## Choose the next section's lane count. The road is kept at a FIXED 3 lanes -
## instead of changing width, lanes are "closed" with construction barriers in
## Game.gd (an outer lane ends and you must merge). Return a varying count here
## to bring dynamic 2/4-lane sections back.
func _pick_next_count(_start: float) -> int:
	return 3


func _append_section() -> void:
	var prev_count := _last_road_count()
	var cursor: float = _sections[-1].end
	var next_count := _pick_next_count(cursor)

	# A change in lane count gets a short transition zone first (no obstacles
	# spawn there - it's the warning/widen-narrow buffer).
	if next_count != prev_count:
		_sections.append({
			"start": cursor, "end": cursor + TRANSITION_LEN, "count": next_count,
			"kind": "transition", "from_count": prev_count, "to_count": next_count,
		})
		cursor += TRANSITION_LEN

	var length := _rng.randf_range(SECTION_MIN, SECTION_MAX)
	_sections.append({
		"start": cursor, "end": cursor + length, "count": next_count,
		"kind": "road", "from_count": next_count, "to_count": next_count,
	})


func _ensure(world: float) -> void:
	while _sections[-1].end < world:
		_append_section()


## Call once per frame with the distance travelled. Extends the schedule far
## enough ahead and forgets sections well behind the player.
func update(distance: float) -> void:
	_ensure(distance + 220.0)   # cover the spawn distance + lookahead
	while _sections.size() > 1 and _sections[0].end < distance - 40.0:
		_sections.remove_at(0)


# --- The query everything uses --------------------------------------------

## Lane config at a world position: {count, positions, dividers, road_width,
## is_transition, blend, kind}. During a transition the count/positions are the
## UPCOMING section's (so the player pre-aligns), while road_width lerps for the
## visible narrow/widen.
func config_at(world: float) -> Dictionary:
	_ensure(world)
	for s in _sections:
		if world >= s.start and world < s.end:
			if s.kind == "transition":
				var blend: float = clampf((world - s.start) / TRANSITION_LEN, 0.0, 1.0)
				return {
					"count": s.to_count,
					"positions": lane_positions(s.to_count),
					"dividers": divider_positions(s.to_count),
					"road_width": lerp(road_width(s.from_count), road_width(s.to_count), blend),
					"is_transition": true, "blend": blend, "kind": "transition",
				}
			return {
				"count": s.count,
				"positions": lane_positions(s.count),
				"dividers": divider_positions(s.count),
				"road_width": road_width(s.count),
				"is_transition": false, "blend": 0.0, "kind": "road",
			}
	# Fallback (shouldn't happen because _ensure covers `world`).
	return {
		"count": 3, "positions": lane_positions(3), "dividers": divider_positions(3),
		"road_width": road_width(3), "is_transition": false, "blend": 0.0, "kind": "road",
	}
