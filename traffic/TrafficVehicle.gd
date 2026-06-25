extends Area3D
class_name TrafficVehicle
## A single piece of traffic the player must dodge.
##
## There is deliberately NO AI here. Traffic does not steer, brake, overtake or
## change lanes. It simply sits in its lane while the world scrolls it toward
## the player (movement is handled centrally in Game.gd).
##
## Most types use Kenney "Car Kit" vehicle models (MIT licensed), auto-fitted to
## size. The tricycle has no off-the-shelf model, so it is still hand-built from
## primitives - a motorbike with a covered passenger sidecar.

# Kenney truck models, re-used (with different colours) for the larger vehicles.
const TRUCK_RED := preload("res://models/vehicle-truck-red.glb")
const TRUCK_YELLOW := preload("res://models/vehicle-truck-yellow.glb")
const TRUCK_GREEN := preload("res://models/vehicle-truck-green.glb")

# Traffic drives toward the player, so the models are turned to face +Z.
# Flip this if a model ends up pointing the wrong way.
const TRAFFIC_FACES_BACK := true

# Colours for the hand-built tricycle.
const GLASS := Color(0.55, 0.75, 0.9)
const TYRE := Color(0.1, 0.1, 0.12)


func _ready() -> void:
	# Put every vehicle in the "traffic" group so the player can recognise a
	# collision as "hit traffic".
	add_to_group("traffic")


## Configure this vehicle as one of the four Philippine traffic types.
## Called by Game.gd right after the vehicle is spawned.
func setup(vehicle_type: String) -> void:
	var bounds: Vector3   # overall size, used for the collision box

	match vehicle_type:
		"jeepney":
			bounds = Vector3(1.7, 1.7, 3.8)
			_use_model(TRUCK_GREEN, bounds)
		"bus":
			bounds = Vector3(1.9, 2.2, 5.2)
			_use_model(TRUCK_RED, bounds)
		"tricycle":
			bounds = Vector3(1.5, 1.4, 2.0)
			_build_tricycle(bounds, Color(0.95, 0.8, 0.15))
		_:
			# Default = an ordinary car.
			bounds = Vector3(1.5, 1.4, 2.6)
			_use_model(TRUCK_YELLOW, bounds)

	# Collision box = the overall bounds, sitting on the road.
	var shape := BoxShape3D.new()
	shape.size = bounds
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position.y = bounds.y * 0.5


## Drop in an imported model, auto-fitted to the given bounds.
func _use_model(packed: PackedScene, bounds: Vector3) -> void:
	ModelUtil.instance_fitted($Model, packed, bounds, "length", TRAFFIC_FACES_BACK)


# --- Hand-built tricycle: a motorbike on the left, sidecar on the right ----
func _build_tricycle(bounds: Vector3, color: Color) -> void:
	var w := bounds.x
	var h := bounds.y
	var l := bounds.z
	# Motorbike (left side).
	_box(Vector3(0.4, h * 0.5, l * 0.9), Vector3(-w * 0.25, h * 0.35, 0), TYRE)
	_box(Vector3(0.4, 0.16, 0.6), Vector3(-w * 0.25, h * 0.6, 0.2), color)        # seat
	_box(Vector3(0.14, 0.6, 0.16), Vector3(-w * 0.25, h * 0.55, -l * 0.4), TYRE)  # column
	# Sidecar (right side).
	_box(Vector3(w * 0.55, h * 0.7, l * 0.7), Vector3(w * 0.22, h * 0.42, 0), color)
	_box(Vector3(w * 0.5, h * 0.25, l * 0.6), Vector3(w * 0.22, h * 0.72, 0), GLASS)
	# Wheels: bike front + rear, plus the sidecar wheel.
	_wheel(0.3, Vector3(-w * 0.25, 0.3, -l * 0.35), TYRE)
	_wheel(0.3, Vector3(-w * 0.25, 0.3, l * 0.3), TYRE)
	_wheel(0.28, Vector3(w * 0.4, 0.28, l * 0.15), TYRE)


# --- Small primitive helpers (used by the tricycle) -----------------------
func _box(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.7
	mesh_instance.material_override = material
	$Model.add_child(mesh_instance)
	return mesh_instance


# A wheel: a cylinder turned so its axle runs left-right across the vehicle.
func _wheel(radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.2
	mesh.radial_segments = 16
	mesh_instance.mesh = mesh
	mesh_instance.position = pos
	mesh_instance.rotation_degrees = Vector3(0, 0, 90)
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh_instance.material_override = material
	$Model.add_child(mesh_instance)
	return mesh_instance
