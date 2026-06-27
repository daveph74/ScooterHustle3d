extends Area3D
class_name Coin
## A collectible coin.
##
## Coins spin in place (handled here) and scroll toward the player (handled in
## Game.gd, like the traffic). When the player's Area3D overlaps a coin, the
## player calls collect() on it.

## Emitted the moment a coin is picked up (handy for sounds/particles later).
signal collected

# How fast the coin spins, in radians per second.
const SPIN_SPEED := 4.0

# Custom coin model. Loaded at runtime so the game still runs without it, and
# falls back to the procedural gold disc if it's missing. Tune these if the coin
# sits the wrong way: PITCH stands the disc up, YAW turns it, SIZE scales it.
const COIN_MODEL_PATH := "res://models/custom/coin.glb"
const COIN_SIZE := 0.9
const COIN_YAW := 0.0
const COIN_PITCH := 0.0

var _collected := false


func _ready() -> void:
	add_to_group("coin")

	if ResourceLoader.exists(COIN_MODEL_PATH):
		# Use the custom coin model; hide the procedural disc.
		$Mesh.visible = false
		var holder := ModelUtil.instance_fitted(
			self, load(COIN_MODEL_PATH), Vector3(COIN_SIZE, COIN_SIZE, COIN_SIZE),
			"height", COIN_YAW)
		holder.rotation_degrees.x = COIN_PITCH
	else:
		# Fallback: procedural shiny gold disc, stood up so the Y-spin "flips".
		$Mesh.rotation_degrees = Vector3(90, 0, 0)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.84, 0.0)
		material.metallic = 0.6
		material.roughness = 0.25
		material.emission_enabled = true              # a soft glow so coins pop
		material.emission = Color(0.55, 0.42, 0.0)
		$Mesh.material_override = material


func _process(delta: float) -> void:
	# Continuous spin = "come and grab me" feedback.
	rotate_y(SPIN_SPEED * delta)


## Whether this coin was picked up (used to detect a "missed" coin when it
## scrolls past the player, which breaks the combo streak).
func is_collected() -> bool:
	return _collected


## Play a quick pickup animation, then remove the coin.
func collect() -> void:
	if _collected:
		return
	_collected = true

	# Stop any further collisions while the animation plays.
	$CollisionShape3D.set_deferred("disabled", true)

	collected.emit()

	# A short "pop": scale up and float upward, then delete.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.8, 1.8, 1.8), 0.12)
	tween.tween_property(self, "position:y", position.y + 1.0, 0.12)
	tween.chain().tween_callback(queue_free)
