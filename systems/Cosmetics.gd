extends RefCounted
class_name Cosmetics
## Cosmetic catalogue + applier. PURELY visual - cosmetics never change stats.
##
## Designed to be model-agnostic so it keeps working when the art is swapped for
## custom assets later:
##   * Paint recolours every mesh under the scooter model (works on any model).
##   * Wheel colour tints any child mesh whose name contains "wheel" (a no-op if
##     the current baked model has no such named parts - it'll light up once a
##     custom model exposes named wheels).
##   * Helmet attaches a primitive at ATTACH.helmet, expressed in PLAYER space
##     (game units), so it's independent of the model's internal scale. Retune
##     these offsets in ONE place when the custom scooter arrives.

## The single place to retune attachment offsets for a new model (player-space).
const ATTACH := {
	"helmet": Vector3(0.0, 1.4, 0.2),
}

# Catalogue per slot. id -> {name, color (null = leave as-is), price}.
# The "_default"/"_none" entries are free and always owned (see GameData).
const PAINT := {
	"paint_default": {"name": "Factory", "color": null, "price": 0},
	"paint_red": {"name": "Chili Red", "color": Color(0.85, 0.15, 0.15), "price": 150},
	"paint_blue": {"name": "Ocean Blue", "color": Color(0.15, 0.4, 0.85), "price": 150},
	"paint_green": {"name": "Jeepney Green", "color": Color(0.15, 0.7, 0.4), "price": 200},
	"paint_pink": {"name": "Manila Pink", "color": Color(0.95, 0.4, 0.7), "price": 250},
	"paint_black": {"name": "Midnight", "color": Color(0.12, 0.12, 0.14), "price": 200},
}
const HELMET := {
	"helmet_none": {"name": "No Helmet", "color": null, "price": 0},
	"helmet_white": {"name": "Classic White", "color": Color(0.95, 0.95, 0.95), "price": 100},
	"helmet_red": {"name": "Racer Red", "color": Color(0.85, 0.2, 0.2), "price": 120},
	"helmet_gold": {"name": "Gold Lid", "color": Color(1.0, 0.84, 0.0), "price": 250},
}
const WHEEL := {
	"wheel_default": {"name": "Stock", "color": null, "price": 0},
	"wheel_neon": {"name": "Neon", "color": Color(0.1, 0.95, 0.8), "price": 150},
	"wheel_gold": {"name": "Gold Rims", "color": Color(1.0, 0.84, 0.0), "price": 220},
}


static func _slot_dict(slot: String) -> Dictionary:
	match slot:
		"helmet": return HELMET
		"wheel": return WHEEL
		_: return PAINT


## Catalogue entries for one slot, for the garage list.
func list_for_slot(slot: String) -> Array:
	var out := []
	var src := _slot_dict(slot)
	for id in src:
		var d: Dictionary = src[id]
		out.append({"slot": slot, "id": id, "name": d.name, "price": d.price, "color": d.color})
	return out


## Apply the equipped cosmetics to a freshly-instanced scooter holder
## (the Node3D returned by ModelUtil.instance_fitted).
func apply(holder: Node3D, equipped: Dictionary) -> void:
	# Paint: recolour the whole model.
	var paint: Dictionary = PAINT.get(equipped.get("paint", "paint_default"), PAINT["paint_default"])
	if paint.color != null:
		_tint(holder, paint.color, "")

	# Wheels: tint only wheel-named meshes (forward-compatible with custom models).
	var wheel: Dictionary = WHEEL.get(equipped.get("wheel", "wheel_default"), WHEEL["wheel_default"])
	if wheel.color != null:
		_tint(holder, wheel.color, "wheel")

	# Helmet: attach a primitive at the helmet offset.
	var helmet: Dictionary = HELMET.get(equipped.get("helmet", "helmet_none"), HELMET["helmet_none"])
	if helmet.color != null:
		_attach_helmet(holder, helmet.color)


## Recursively override the material of MeshInstance3D nodes. If name_filter is
## non-empty, only meshes whose name contains it (case-insensitive) are tinted.
static func _tint(node: Node, color: Color, name_filter: String) -> void:
	if node is MeshInstance3D:
		if name_filter == "" or name_filter.to_lower() in String(node.name).to_lower():
			var material := StandardMaterial3D.new()
			material.albedo_color = color
			material.roughness = 0.6
			material.metallic = 0.2
			node.material_override = material
	for child in node.get_children():
		_tint(child, color, name_filter)


static func _attach_helmet(holder: Node3D, color: Color) -> void:
	var helmet := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.34
	helmet.mesh = mesh
	helmet.position = ATTACH.helmet
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.4
	helmet.material_override = material
	holder.add_child(helmet)
