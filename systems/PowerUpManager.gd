extends Node
## PowerUpManager - tracks the player's ACTIVE power-up effects for one run.
##
## A Node child of Game (not an autoload) so it resets each run. Game/Player ask
## it questions ("is the magnet active? what's the coin multiplier?") and it
## drives the HUD duration bars. The shield is special: it lasts until the next
## hit, so the Player owns a `shield_active` flag that this manager sets and the
## Player consumes on impact.

# Effect durations in seconds (the shield is until-hit, so not listed here).
const DURATIONS := {
	"magnet": 10.0,
	"multiplier": 15.0,
	"speed": 8.0,
}
const MAGNET_RANGE := 14.0      # metres ahead within which the magnet pulls coins
const SPEED_BONUS_FRACTION := 0.18   # speed boost adds this fraction of base speed
const SPEED_SCORE_MULT := 1.5        # and this much extra score gain

var _timed := {}   # kind -> remaining seconds
var _player: Player
var _hud: Node
var _base_speed := 16.0


## Wire up references once, from Game._ready.
func setup(player: Player, hud: Node, base_speed: float) -> void:
	_player = player
	_hud = hud
	_base_speed = base_speed


func activate(kind: String) -> void:
	if kind == "shield":
		if _player:
			_player.shield_active = true
		if _hud:
			_hud.show_powerup_duration("shield", 1.0, 1.0)   # static "on" indicator
		return
	if DURATIONS.has(kind):
		_timed[kind] = DURATIONS[kind]


func _process(delta: float) -> void:
	# Count down timed effects and update the HUD bars.
	for kind in _timed.keys():
		_timed[kind] -= delta
		if _timed[kind] <= 0.0:
			_timed.erase(kind)
			if _hud:
				_hud.show_powerup_duration(kind, 0.0, DURATIONS[kind])
		elif _hud:
			_hud.show_powerup_duration(kind, _timed[kind], DURATIONS[kind])

	# Keep the shield indicator in sync (the Player clears the flag on impact).
	if _hud and _player and not _player.shield_active:
		_hud.show_powerup_duration("shield", 0.0, 1.0)


# --- Queries used by Game / Player ---------------------------------------

func magnet_active() -> bool:
	return _timed.has("magnet")


func coin_value_mult() -> int:
	return 2 if _timed.has("multiplier") else 1


func score_mult() -> float:
	return SPEED_SCORE_MULT if _timed.has("speed") else 1.0


func speed_bonus() -> float:
	return _base_speed * SPEED_BONUS_FRACTION if _timed.has("speed") else 0.0
