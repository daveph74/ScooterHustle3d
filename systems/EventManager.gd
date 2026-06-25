extends Node
## EventManager - drives short, flavourful "Philippine road" events.
##
## A Node child of Game (resets each run). Only ONE event is active at a time;
## between events there is a cooldown of 30-90s. Events never spawn anything
## themselves - they just expose MULTIPLIERS that Game applies to its existing
## spawners, so the safe-lane guarantee is untouched (we only nudge density,
## speed and intervals; the open lane is still always open).

signal event_started(display_name: String)
signal event_ended

# Per-event tuning. Any key left out defaults to "no change" (see the _val
# defaults below). Events must NOT raise world speed (that would cut reaction
# time); they only change spawn density / traffic drive speed / scenery.
const EVENTS := {
	"traffic_jam": {
		"name": "TRAFFIC JAM!", "dur": 12.0,
		"traffic_interval_mult": 0.6,   # more vehicles
		"block_both_bias": 0.35,        # more two-lane rows (safe lane still open)
	},
	"fiesta": {
		"name": "FIESTA!", "dur": 12.0,
		"coin_interval_mult": 0.5,      # coin-rich
		"coin_line_bonus": 3,
	},
	"rainstorm": {
		"name": "RAINSTORM!", "dur": 12.0,
		"rain": true,
		"traffic_speed_mult": 0.9,      # slightly calmer in the rain
	},
	"market": {
		"name": "MARKET DISTRICT", "dur": 12.0,
		"scenery_interval_mult": 0.45,  # dense roadside stalls/buildings
		"coin_interval_mult": 0.7,
		"coin_line_bonus": 2,
	},
	"school_zone": {
		"name": "SCHOOL ZONE", "dur": 12.0,
		"traffic_speed_mult": 0.6,      # slower traffic = easier
		"traffic_interval_mult": 1.2,
	},
}

var _active := ""        # "" when no event is running
var _time_left := 0.0
var _cooldown := 0.0


func _ready() -> void:
	# First event comes a little sooner so players see the feature early.
	_cooldown = randf_range(20.0, 35.0)


func _process(delta: float) -> void:
	if _active != "":
		_time_left -= delta
		if _time_left <= 0.0:
			_active = ""
			_cooldown = randf_range(30.0, 90.0)
			event_ended.emit()
	else:
		_cooldown -= delta
		if _cooldown <= 0.0:
			_start_random_event()


func _start_random_event() -> void:
	var keys := EVENTS.keys()
	_active = keys[randi() % keys.size()]
	_time_left = EVENTS[_active].get("dur", 12.0)
	event_started.emit(EVENTS[_active].get("name", "EVENT"))


# Read a tuning value from the active event, or a default when idle.
func _val(key: String, default):
	if _active == "":
		return default
	return EVENTS[_active].get(key, default)


# --- Query API read by Game ----------------------------------------------

func traffic_interval_mult() -> float:
	return _val("traffic_interval_mult", 1.0)


func traffic_speed_mult() -> float:
	return _val("traffic_speed_mult", 1.0)


func block_both_bias() -> float:
	return _val("block_both_bias", 0.0)


func coin_interval_mult() -> float:
	return _val("coin_interval_mult", 1.0)


func coin_line_bonus() -> int:
	return int(_val("coin_line_bonus", 0))


func scenery_interval_mult() -> float:
	return _val("scenery_interval_mult", 1.0)


func is_raining() -> bool:
	return bool(_val("rain", false))
