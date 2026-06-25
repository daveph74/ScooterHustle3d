extends Area3D
class_name PowerUp
## A collectible power-up.
##
## One reusable base for all power-up kinds (magnet, shield, multiplier, speed).
## The kind is just a string; the look is built procedurally (no art assets), and
## the EFFECT lives in PowerUpManager - this node only carries the kind and gets
## collected. Add a new kind by extending _KINDS below and handling it in
## PowerUpManager.activate(); no new scene needed.

signal collected

const SPIN_SPEED := 2.0
const FLOAT_HEIGHT := 0.9   # how high above the road the icon hovers

# kind -> {color, shape}. shape is one of: box, sphere, prism, torus.
const _KINDS := {
	"magnet": {"color": Color(0.95, 0.25, 0.25), "shape": "torus"},
	"shield": {"color": Color(0.25, 0.55, 1.0), "shape": "sphere"},
	"multiplier": {"color": Color(1.0, 0.84, 0.0), "shape": "box"},
	"speed": {"color": Color(0.2, 0.95, 0.95), "shape": "prism"},
}

var kind := "magnet"
var _collected := false


func _ready() -> void:
	add_to_group("powerup")
	collision_layer = 8     # unique "powerup" layer (player's mask includes it)
	collision_mask = 0
	monitoring = false      # the player detects us, we don't detect anything

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8     # generous so it's easy to grab
	shape.shape = sphere
	shape.position.y = FLOAT_HEIGHT
	add_child(shape)


## Pick which power-up this is and build its icon. Call right after spawning.
func setup(new_kind: String) -> void:
	kind = new_kind
	var info: Dictionary = _KINDS.get(kind, _KINDS["magnet"])
	_build_icon(info.color, info.shape)


func _build_icon(color: Color, shape_name: String) -> void:
	var mesh_instance := MeshInstance3D.new()
	match shape_name:
		"sphere":
			var m := SphereMesh.new(); m.radius = 0.45; m.height = 0.9
			mesh_instance.mesh = m
		"box":
			var m := BoxMesh.new(); m.size = Vector3(0.7, 0.7, 0.7)
			mesh_instance.mesh = m
		"prism":
			var m := PrismMesh.new(); m.size = Vector3(0.8, 0.8, 0.8)
			mesh_instance.mesh = m
		_:  # torus (magnet)
			var m := TorusMesh.new(); m.inner_radius = 0.25; m.outer_radius = 0.5
			mesh_instance.mesh = m
	mesh_instance.position.y = FLOAT_HEIGHT

	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = 0.4
	material.roughness = 0.25
	material.emission_enabled = true   # glow so power-ups read as special
	material.emission = color * 0.6
	mesh_instance.material_override = material
	add_child(mesh_instance)


func _process(delta: float) -> void:
	rotate_y(SPIN_SPEED * delta)


func is_collected() -> bool:
	return _collected


## Pickup animation, then remove (mirrors Coin.collect()).
func collect() -> void:
	if _collected:
		return
	_collected = true
	collected.emit()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector3(1.8, 1.8, 1.8), 0.15)
	tween.tween_property(self, "position:y", position.y + 1.2, 0.15)
	tween.chain().tween_callback(queue_free)
