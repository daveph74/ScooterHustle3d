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

var _collected := false


func _ready() -> void:
	add_to_group("coin")

	# Stand the disc up so its flat face points toward the camera, which makes
	# the spin read as a satisfying "flip".
	$Mesh.rotation_degrees = Vector3(90, 0, 0)

	# Give it a shiny gold look. Built in code so we don't need image files.
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
