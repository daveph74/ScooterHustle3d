extends Area3D
class_name TrafficVehicle
## A single piece of traffic the player must dodge.
##
## There is deliberately NO AI here. Traffic does not steer, brake, overtake or
## change lanes. It simply sits in its lane while the world scrolls it toward
## the player (the actual movement is handled centrally in Game.gd).
##
## The only job of this script is to assemble a simple low-poly model for one
## of the four Philippine traffic types out of boxes and cylinder wheels, and
## to size the collision box to match.

# Shared colours.
const GLASS := Color(0.55, 0.75, 0.9)   # windows
const TYRE := Color(0.1, 0.1, 0.12)     # wheels


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
			# Long, low and brightly painted - the icon of Philippine roads.
			bounds = Vector3(1.7, 1.7, 3.8)
			_build_boxy(bounds, Color(0.9, 0.3, 0.15))
		"bus":
			# The big, tall, scary one.
			bounds = Vector3(1.9, 2.2, 5.2)
			_build_boxy(bounds, Color(0.2, 0.45, 0.85))
		"tricycle":
			# A motorbike with a passenger sidecar.
			bounds = Vector3(1.5, 1.4, 2.0)
			_build_tricycle(bounds, Color(0.95, 0.8, 0.15))
		_:
			# Default = an ordinary car.
			bounds = Vector3(1.5, 1.4, 2.6)
			_build_car(bounds, Color(0.85, 0.85, 0.9))

	# Collision box = the overall bounds, sitting on the road.
	var shape := BoxShape3D.new()
	shape.size = bounds
	$CollisionShape3D.shape = shape
	$CollisionShape3D.position.y = bounds.y * 0.5


# --- Model builders -------------------------------------------------------

## A tall box vehicle with a window strip, roof and four wheels (jeepney/bus).
func _build_boxy(bounds: Vector3, color: Color) -> void:
	var w := bounds.x
	var h := bounds.y
	var l := bounds.z
	_box(Vector3(w, h * 0.78, l), Vector3(0, h * 0.4, 0), color)                  # body
	_box(Vector3(w * 1.02, h * 0.28, l * 0.9), Vector3(0, h * 0.66, 0), GLASS)    # windows
	_box(Vector3(w, h * 0.14, l), Vector3(0, h * 0.86, 0), color)                 # roof
	_corner_wheels(w, l, 0.36)


## A lower body with a shorter cabin on top (car).
func _build_car(bounds: Vector3, color: Color) -> void:
	var w := bounds.x
	var h := bounds.y
	var l := bounds.z
	_box(Vector3(w, h * 0.5, l), Vector3(0, h * 0.32, 0), color)                  # lower body
	_box(Vector3(w * 0.92, h * 0.42, l * 0.55), Vector3(0, h * 0.68, -0.05), color) # cabin
	_box(Vector3(w * 0.94, h * 0.3, l * 0.5), Vector3(0, h * 0.7, -0.05), GLASS)  # windows
	_corner_wheels(w, l, 0.34)


## A narrow motorbike on the left with a covered passenger sidecar on the right.
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


# --- Small primitive helpers ----------------------------------------------

## Four wheels, one at each corner of a (w long) footprint.
func _corner_wheels(w: float, l: float, radius: float) -> void:
	var x := w * 0.45
	var z := l * 0.32
	for side_x in [-x, x]:
		for side_z in [-z, z]:
			_wheel(radius, Vector3(side_x, radius, side_z), TYRE)


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
