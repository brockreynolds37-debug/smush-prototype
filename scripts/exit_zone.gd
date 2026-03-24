extends Area3D

## Exit zone — placed at dungeon exit stairs.
## When the hero enters, triggers a floor transition.

signal hero_entered_exit

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Layer 2 = Units
	body_entered.connect(_on_body_entered)

	# Visual indicator — glowing circle on the stairs
	var indicator := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.5
	mesh.bottom_radius = 1.5
	mesh.height = 0.05
	indicator.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	indicator.set_surface_override_material(0, mat)
	indicator.position.y = 0.1
	add_child(indicator)

	# Gentle pulse animation
	var tween := create_tween().set_loops()
	tween.tween_property(indicator, "scale", Vector3(1.15, 1.0, 1.15), 1.0).set_trans(Tween.TRANS_SINE)
	tween.tween_property(indicator, "scale", Vector3(0.9, 1.0, 0.9), 1.0).set_trans(Tween.TRANS_SINE)

func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.hero and not FloorManager.is_transitioning:
		hero_entered_exit.emit()
		FloorManager.go_to_next_floor()
