class_name PropFactory
extends RefCounted

# Cached loaded PackedScene (or null if the glb doesn't exist).
var _cache: Dictionary = {}

# Shared materials — cached on first use.
var _mat_concrete: StandardMaterial3D
var _mat_metal: StandardMaterial3D
var _mat_wood: StandardMaterial3D
var _mat_orange: StandardMaterial3D
var _mat_green: StandardMaterial3D
var _mat_white: StandardMaterial3D


func _get_mat(color: Color) -> StandardMaterial3D:
	# Returns a cached unshaded-lit material for the given solid color.
	# Key by rounded RGB to avoid floating-point mismatch.
	var key := "%d,%d,%d" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]
	if not _cache.has("mat_" + key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = 0.9
		_cache["mat_" + key] = m
	return _cache["mat_" + key]


## Make a prop with the given key. Adds it to parent; returns the holder Node3D.
## Uses models/custom/<key>.glb if the file exists; otherwise builds a primitive.
func make(key: String, parent: Node3D) -> Node3D:
	var cache_key := "scene_" + key
	if not _cache.has(cache_key):
		var path := "res://models/custom/" + key + ".glb"
		# ResourceLoader.exists() avoids an error log when the file is absent.
		_cache[cache_key] = load(path) if ResourceLoader.exists(path) else null
	var packed = _cache[cache_key]
	if packed != null:
		var sizes := {
			"lamp-post": Vector3(0.5, 5.0, 0.5),
			"utility-pole": Vector3(0.4, 8.0, 0.4),
			"bench": Vector3(1.8, 0.9, 0.6),
			"flower-pot": Vector3(0.8, 0.9, 0.8),
			"trash-bin": Vector3(0.7, 1.0, 0.7),
			"traffic-cone": Vector3(0.5, 0.9, 0.5),
			"construction-barrier": Vector3(2.0, 1.0, 0.4),
			"street-sign": Vector3(0.5, 2.5, 0.5),
			"billboard": Vector3(4.0, 3.0, 0.3),
			"bus-stop": Vector3(3.0, 3.0, 1.0),
			"newspaper-stand": Vector3(1.2, 1.8, 0.8),
		}
		var sz: Vector3 = sizes.get(key, Vector3(1.0, 2.0, 1.0))
		return ModelUtil.instance_fitted(parent, packed, sz, "height", 0.0)
	return _build_primitive(key, parent)


func _add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _get_mat(color)
	mi.position = pos
	parent.add_child(mi)


func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3,
		color: Color, top_r: float = -1.0) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r if top_r >= 0.0 else radius
	cm.bottom_radius = radius
	cm.height = height
	mi.mesh = cm
	mi.material_override = _get_mat(color)
	mi.position = pos
	parent.add_child(mi)


func _build_primitive(key: String, parent: Node3D) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	match key:
		"lamp-post":
			_add_cylinder(holder, 0.06, 4.5, Vector3(0, 2.25, 0), Color(0.25, 0.25, 0.27))
			_add_box(holder, Vector3(0.7, 0.14, 0.28), Vector3(0.0, 4.5, 0.0), Color(0.28, 0.28, 0.30))
			# Emissive yellow lamp head
			var lamp := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(0.25, 0.12)
			lamp.mesh = qm
			var lm := StandardMaterial3D.new()
			lm.albedo_color = Color(1.0, 0.95, 0.6)
			lm.emission_enabled = true
			lm.emission = Color(1.0, 0.85, 0.3) * 1.5
			lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			lamp.material_override = lm
			lamp.position = Vector3(0, 4.44, 0.15)
			holder.add_child(lamp)
		"utility-pole":
			_add_cylinder(holder, 0.09, 6.5, Vector3(0, 3.25, 0), Color(0.40, 0.28, 0.18))
			_add_box(holder, Vector3(1.6, 0.1, 0.1), Vector3(0.0, 6.0, 0.0), Color(0.32, 0.22, 0.14))
			_add_box(holder, Vector3(1.0, 0.08, 0.08), Vector3(0.0, 5.5, 0.0), Color(0.32, 0.22, 0.14))
		"bench":
			_add_box(holder, Vector3(1.8, 0.1, 0.5), Vector3(0.0, 0.46, 0.0), Color(0.55, 0.38, 0.22))
			_add_box(holder, Vector3(0.12, 0.46, 0.5), Vector3(-0.8, 0.23, 0.0), Color(0.45, 0.30, 0.18))
			_add_box(holder, Vector3(0.12, 0.46, 0.5), Vector3(0.8, 0.23, 0.0), Color(0.45, 0.30, 0.18))
		"flower-pot":
			_add_cylinder(holder, 0.28, 0.38, Vector3(0, 0.19, 0), Color(0.72, 0.35, 0.18))
			_add_cylinder(holder, 0.26, 0.25, Vector3(0, 0.54, 0), Color(0.22, 0.50, 0.18))
		"trash-bin":
			_add_cylinder(holder, 0.30, 0.80, Vector3(0, 0.40, 0), Color(0.22, 0.30, 0.24))
			_add_cylinder(holder, 0.32, 0.08, Vector3(0, 0.84, 0), Color(0.18, 0.24, 0.20))
		"traffic-cone":
			_add_cylinder(holder, 0.22, 0.06, Vector3(0, 0.03, 0), Color(0.62, 0.18, 0.05))
			_add_cylinder(holder, 0.0, 0.80, Vector3(0, 0.43, 0), Color(0.90, 0.35, 0.04), 0.0)
		"construction-barrier":
			_add_box(holder, Vector3(0.12, 0.90, 0.12), Vector3(-0.9, 0.45, 0.0), Color(0.30, 0.30, 0.30))
			_add_box(holder, Vector3(0.12, 0.90, 0.12), Vector3(0.9, 0.45, 0.0), Color(0.30, 0.30, 0.30))
			_add_box(holder, Vector3(2.0, 0.14, 0.12), Vector3(0.0, 0.75, 0.0), Color(0.90, 0.55, 0.04))
		"street-sign":
			_add_cylinder(holder, 0.04, 2.2, Vector3(0, 1.1, 0), Color(0.35, 0.35, 0.36))
			_add_box(holder, Vector3(0.55, 0.38, 0.06), Vector3(0.0, 2.1, 0.0), Color(0.90, 0.90, 0.88))
		"billboard":
			_add_cylinder(holder, 0.09, 4.5, Vector3(-1.6, 2.25, 0), Color(0.28, 0.28, 0.30))
			_add_cylinder(holder, 0.09, 4.5, Vector3(1.6, 2.25, 0), Color(0.28, 0.28, 0.30))
			_add_box(holder, Vector3(3.6, 2.2, 0.12), Vector3(0.0, 4.7, 0.0), Color(0.95, 0.95, 0.95))
		"bus-stop":
			_add_box(holder, Vector3(0.1, 2.6, 0.1), Vector3(-1.4, 1.3, 0.5), Color(0.50, 0.52, 0.54))
			_add_box(holder, Vector3(0.1, 2.6, 0.1), Vector3(1.4, 1.3, 0.5), Color(0.50, 0.52, 0.54))
			_add_box(holder, Vector3(3.0, 0.12, 1.2), Vector3(0.0, 2.65, 0.0), Color(0.20, 0.36, 0.60))
			_add_box(holder, Vector3(3.0, 2.6, 0.1), Vector3(0.0, 1.3, -0.55), Color(0.75, 0.82, 0.88))
		"newspaper-stand":
			_add_box(holder, Vector3(1.1, 1.5, 0.65), Vector3(0, 0.75, 0), Color(0.18, 0.28, 0.60))
			_add_box(holder, Vector3(1.15, 0.06, 0.70), Vector3(0, 1.53, 0), Color(0.14, 0.22, 0.50))
		_:
			_add_box(holder, Vector3(1.0, 2.0, 1.0), Vector3(0, 1.0, 0), Color(0.60, 0.60, 0.62))
	return holder
