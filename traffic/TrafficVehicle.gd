extends Area3D
class_name TrafficVehicle
## A single piece of traffic the player must dodge.
##
## There is deliberately NO AI here. Traffic does not steer, brake, overtake or
## change lanes. It simply sits in its lane while the world scrolls it toward
## the player (the actual movement is handled centrally in Game.gd, which keeps
## the spawn/recycle logic in one easy-to-read place).
##
## The only job of this script is to make the same scene LOOK like four
## different vehicle types by resizing its box and recolouring it.

func _ready() -> void:
	# Put every vehicle in the "traffic" group so the player can recognise a
	# collision as "hit traffic".
	add_to_group("traffic")


## Configure this vehicle as one of the four Philippine traffic types.
## Called by Game.gd right after the vehicle is spawned.
func setup(vehicle_type: String) -> void:
	var box_size: Vector3
	var color: Color

	match vehicle_type:
		"jeepney":
			# Long and colourful - the icon of Philippine roads.
			box_size = Vector3(1.7, 1.6, 3.6)
			color = Color(0.90, 0.35, 0.18)
		"bus":
			# The big, scary one.
			box_size = Vector3(1.9, 2.1, 5.2)
			color = Color(0.20, 0.50, 0.85)
		"tricycle":
			# Small and nimble looking.
			box_size = Vector3(1.3, 1.3, 1.8)
			color = Color(0.95, 0.80, 0.20)
		_:
			# Default = ordinary car.
			box_size = Vector3(1.4, 1.3, 2.5)
			color = Color(0.82, 0.82, 0.86)

	# Build a fresh mesh + collision shape for this instance so resizing one
	# vehicle never affects the others.
	var mesh := BoxMesh.new()
	mesh.size = box_size
	$Mesh.mesh = mesh
	$Mesh.position.y = box_size.y * 0.5   # sit the box on the road

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	$Mesh.material_override = material

	var collision := BoxShape3D.new()
	collision.size = box_size
	$CollisionShape3D.shape = collision
	$CollisionShape3D.position.y = box_size.y * 0.5
