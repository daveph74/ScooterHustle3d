extends Area3D
class_name TrafficVehicle
## A single piece of traffic the player must dodge.
##
## There is deliberately NO AI here. Traffic does not steer, brake, overtake or
## change lanes. It simply sits in its lane while the world scrolls it toward
## the player (movement is handled centrally in Game.gd).
##
## Every type uses a custom model (generated on Meshy, optimised for mobile),
## auto-fitted to its collision bounds by ModelUtil.

# Per-type config: the model, its collision bounds (also the fit target), and
# the yaw that turns it to face the player (+Z). Tune a type's "yaw" in 90°
# steps if that vehicle ends up pointing the wrong way down the road.
# "model" is a PATH (resolved via ModelUtil.hd_load so the PC build can use a
# models/pc/ HD version).
const TYPES := {
	"jeepney": {
		"model": "res://models/custom/jeepney.glb",
		"bounds": Vector3(1.7, 1.7, 3.8), "yaw": 270.0,
	},
	"bus": {
		"model": "res://models/custom/bus.glb",
		"bounds": Vector3(1.9, 2.2, 5.2), "yaw": 270.0,
	},
	"car": {
		"model": "res://models/custom/taxi.glb",
		"bounds": Vector3(1.5, 1.4, 2.6), "yaw": 270.0,
	},
	"tricycle": {
		"model": "res://models/custom/tricycle.glb",
		"bounds": Vector3(1.5, 1.4, 2.0), "yaw": 270.0,
	},
}

## How fast this vehicle drives forward (away from the player), in world units
## per second. Set by Game.gd at spawn. Because the player is faster, the player
## overtakes traffic - which is what makes the traffic look like it's moving.
var drive_speed := 0.0


func _ready() -> void:
	# Put every vehicle in the "traffic" group so the player can recognise a
	# collision as "hit traffic".
	add_to_group("traffic")


## Configure this vehicle as one of the four Philippine traffic types.
## Called by Game.gd right after the vehicle is spawned.
func setup(vehicle_type: String) -> void:
	var cfg: Dictionary = TYPES.get(vehicle_type, TYPES["car"])
	var bounds: Vector3 = cfg.bounds

	# Drop in the model, auto-fitted to the bounds and turned to face the player.
	ModelUtil.instance_fitted($Model, ModelUtil.hd_load(cfg.model), bounds, "length", cfg.yaw)

	# Collision box = the overall bounds, sitting on the road.
	var shape := BoxShape3D.new()
	shape.size = bounds
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position.y = bounds.y * 0.5
