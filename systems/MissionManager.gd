extends Node
## MissionManager - daily missions singleton (autoload).
##
## Generates 3 missions each day, tracks live progress during a run, lets the
## player claim coin rewards, and resets automatically when the date changes.
## All state lives in GameData.daily_missions so it is saved with everything
## else (see GameData save schema v2). Logic is kept here, OUT of Game.gd - the
## game just calls report() when something happens.

## The pool missions are drawn from. type is one of:
##   coins / near_miss / runs   -> additive (accumulates across the day)
##   distance                   -> additive metres across the day
##   score                      -> best single-run score (uses max)
## reward is in coins, kept within the 25-250 range.
const MISSION_POOL := [
	{"id": "coins_50", "type": "coins", "name": "Collect 50 coins", "target": 50, "reward": 75},
	{"id": "coins_120", "type": "coins", "name": "Collect 120 coins", "target": 120, "reward": 150},
	{"id": "dist_2000", "type": "distance", "name": "Travel 2,000 m", "target": 2000, "reward": 120},
	{"id": "dist_3500", "type": "distance", "name": "Travel 3,500 m", "target": 3500, "reward": 200},
	{"id": "near_10", "type": "near_miss", "name": "Perform 10 near misses", "target": 10, "reward": 100},
	{"id": "near_25", "type": "near_miss", "name": "Perform 25 near misses", "target": 25, "reward": 180},
	{"id": "runs_3", "type": "runs", "name": "Complete 3 runs", "target": 3, "reward": 60},
	{"id": "score_1500", "type": "score", "name": "Reach a score of 1,500", "target": 1500, "reward": 130},
	{"id": "score_3000", "type": "score", "name": "Reach a score of 3,000", "target": 3000, "reward": 250},
]

const MISSIONS_PER_DAY := 3


func _ready() -> void:
	_ensure_today()


## Today's date as "YYYY-MM-DD" (local time).
func _today() -> String:
	return Time.get_date_string_from_system()


## (Re)generate the day's missions if the saved date is not today.
func _ensure_today() -> void:
	if GameData.daily_missions.get("date", "") == _today():
		return  # already have today's missions

	# Pick MISSIONS_PER_DAY distinct templates, deterministically for the day so
	# the same 3 missions persist all day even across app restarts.
	var rng := RandomNumberGenerator.new()
	rng.seed = abs(hash(_today()))
	var indices := range(MISSION_POOL.size())
	# Fisher-Yates shuffle driven by the seeded rng (Array.shuffle uses the
	# global rng, which we don't want to disturb).
	for i in range(indices.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = indices[i]
		indices[i] = indices[j]
		indices[j] = tmp

	var missions := []
	for k in range(MISSIONS_PER_DAY):
		var template: Dictionary = MISSION_POOL[indices[k]]
		missions.append({
			"id": template.id,
			"type": template.type,
			"name": template.name,
			"target": template.target,
			"reward": template.reward,
			"progress": 0,
			"completed": false,
			"claimed": false,
		})

	GameData.daily_missions = {"date": _today(), "missions": missions}
	GameData.save_game()


## The current day's missions (an Array of Dictionaries).
func active_missions() -> Array:
	_ensure_today()
	return GameData.daily_missions.get("missions", [])


## Report progress for a mission type. Does NOT save every call (would thrash on
## every coin); the caller saves at a sensible point via save_now().
func report(type: String, amount: int) -> void:
	for mission in active_missions():
		if mission.type != type or mission.completed:
			continue
		if type == "score":
			mission.progress = maxi(mission.progress, amount)   # best single run
		else:
			mission.progress += amount                          # accumulate
		if mission.progress >= mission.target:
			mission.progress = mission.target
			mission.completed = true


## Persist current progress (call at run end and after a claim).
func save_now() -> void:
	GameData.save_game()


## Claim a completed-but-unclaimed mission. Returns the coins awarded (0 if not
## claimable).
func claim(mission_id: String) -> int:
	for mission in active_missions():
		if mission.id == mission_id and mission.completed and not mission.claimed:
			mission.claimed = true
			GameData.add_coins(mission.reward)   # add_coins already saves
			return mission.reward
	return 0


## True if any mission can be claimed right now (for the menu badge).
func has_claimable() -> bool:
	for mission in active_missions():
		if mission.completed and not mission.claimed:
			return true
	return false
