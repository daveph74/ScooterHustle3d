extends RefCounted
class_name ModelUtil
## Helper for dropping imported 3D models (.glb) into the game at the right size.
##
## Imported models come in all sorts of native scales and pivot points. Rather
## than hand-tuning numbers for every model, this fits a model to a target size
## automatically: it measures the model's bounding box, scales it uniformly to
## match, centres it left-right and front-back, and sits it on the ground (y=0).
##
## Returns a "holder" Node3D placed at the parent's origin. The CALLER can then
## freely move/rotate that holder (e.g. to position scenery) without disturbing
## the fit, because all the fitting happens on an inner pivot node.

## fit_axis:
##   "length" - scale so the longest horizontal side matches target.z (vehicles)
##   "height" - scale so the height matches target.y (buildings, trees)
static func instance_fitted(parent: Node3D, packed: PackedScene, target: Vector3, fit_axis: String, face_back: bool) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)

	var pivot := Node3D.new()
	holder.add_child(pivot)

	var model := packed.instantiate()
	pivot.add_child(model)

	# Turn the model around if it faces the wrong way.
	if face_back:
		model.rotate_y(PI)

	# Measure the model (in pivot space) and fit it.
	var aabb := _local_aabb(pivot, model)
	if aabb.size.x > 0.0001 or aabb.size.y > 0.0001 or aabb.size.z > 0.0001:
		var scale := 1.0
		if fit_axis == "height":
			scale = target.y / maxf(aabb.size.y, 0.001)
		else:
			scale = target.z / maxf(maxf(aabb.size.x, aabb.size.z), 0.001)
		pivot.scale = Vector3(scale, scale, scale)
		# Centre horizontally, drop bottom to y=0.
		pivot.position = Vector3(
			-scale * (aabb.position.x + aabb.size.x * 0.5),
			-scale * aabb.position.y,
			-scale * (aabb.position.z + aabb.size.z * 0.5)
		)

	return holder


## Half of the model's larger horizontal dimension, in world units, AFTER
## fitting (and any rotation already applied to the holder). Used to place
## scenery so its edge clears the road no matter how big or rotated it is.
static func footprint_radius(holder: Node3D) -> float:
	var aabb := _local_aabb(holder, holder)
	return maxf(aabb.size.x, aabb.size.z) * 0.5


## Merge the bounding boxes of every visual mesh under "root", expressed in
## "reference" node's local space.
static func _local_aabb(reference: Node3D, root: Node3D) -> AABB:
	var visuals: Array[VisualInstance3D] = []
	_gather_visuals(root, visuals)

	var result := AABB()
	var started := false
	var ref_inverse := reference.global_transform.affine_inverse()
	for visual in visuals:
		var box := visual.get_aabb()
		var relative := ref_inverse * visual.global_transform
		var transformed := relative * box
		if not started:
			result = transformed
			started = true
		else:
			result = result.merge(transformed)
	return result


static func _gather_visuals(node: Node, out: Array[VisualInstance3D]) -> void:
	if node is VisualInstance3D:
		out.append(node)
	for child in node.get_children():
		_gather_visuals(child, out)
