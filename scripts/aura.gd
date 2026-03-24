extends Node3D

## Aura — visual ring mesh that applies effects to units in radius.
## Effect types: HEAL, DAMAGE, SPEED.

class_name Aura

enum EffectType { HEAL, DAMAGE, SPEED }

@export var radius: float = 4.0
@export var effect_type: EffectType = EffectType.HEAL
@export var effect_value: float = 5.0  # HP/sec for HEAL, DPS for DAMAGE, speed mult for SPEED

var _ring_mesh: MeshInstance3D = null
var _owner_node: Node3D = null

func _init(p_effect_type: EffectType = EffectType.HEAL, p_radius: float = 4.0, p_value: float = 5.0) -> void:
	effect_type = p_effect_type
	radius = p_radius
	effect_value = p_value

func _ready() -> void:
	_owner_node = get_parent()
	_build_ring_visual()

	# Register with AuraManager
	if AuraManager:
		AuraManager.register_aura(self)

func _build_ring_visual() -> void:
	_ring_mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = radius - 0.15
	torus.outer_radius = radius
	torus.rings = 32
	torus.ring_segments = 16
	_ring_mesh.mesh = torus

	var mat = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	match effect_type:
		EffectType.HEAL:
			mat.albedo_color = Color(0.2, 0.9, 0.3, 0.4)
			mat.emission_enabled = true
			mat.emission = Color(0.1, 0.8, 0.2)
			mat.emission_energy_multiplier = 2.0
		EffectType.DAMAGE:
			mat.albedo_color = Color(0.9, 0.2, 0.1, 0.4)
			mat.emission_enabled = true
			mat.emission = Color(0.9, 0.1, 0.0)
			mat.emission_energy_multiplier = 2.0
		EffectType.SPEED:
			mat.albedo_color = Color(0.3, 0.6, 1.0, 0.4)
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.5, 1.0)
			mat.emission_energy_multiplier = 2.0
	_ring_mesh.material_override = mat
	_ring_mesh.position.y = 0.1
	add_child(_ring_mesh)

	# Slow rotation for visual effect
	var tween = create_tween().set_loops()
	tween.tween_property(_ring_mesh, "rotation:y", TAU, 4.0).from(0.0)

func get_world_center() -> Vector3:
	if _owner_node and is_instance_valid(_owner_node):
		return _owner_node.global_position
	return global_position

func _exit_tree() -> void:
	if AuraManager:
		AuraManager.unregister_aura(self)
