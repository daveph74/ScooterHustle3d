extends Area3D
class_name Obstacle
## A static road hazard — a construction barrier or traffic cone used to close a
## lane. It lives in the "traffic" group on collision layer 2, so the Player's
## existing collision treats hitting one as a crash (a shield still absorbs it).
##
## Movement toward the player is handled by Game's _scroll_traffic, exactly like
## a vehicle. drive_speed stays 0, so it approaches at the full world scroll
## speed (it's parked on the road).

var drive_speed := 0.0


## Build the visual (via PropFactory, so it auto-uses models/custom/<key>.glb if
## present) and a box collider of the given size.
func setup(factory: PropFactory, model_key: String, collision: Vector3) -> void:
	add_to_group("traffic")
	collision_layer = 2
	collision_mask = 0
	monitoring = false   # the player detects us; we don't detect anything

	factory.make(model_key, self)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = collision
	shape.shape = box
	shape.position.y = collision.y * 0.5
	add_child(shape)
