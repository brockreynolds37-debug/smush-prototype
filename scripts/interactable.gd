extends StaticBody3D

## Interactable world object — treasure chests and breakable barrels/crates.
## Chests: hero walks to them, click to open, drops loot.
## Breakables: have HP, hero can attack them, break and drop minor loot.

signal interacted()
signal destroyed()

enum Type { CHEST, BARREL }

@export var interactable_type: Type = Type.CHEST
@export var hit_points: int = 1  # Barrels = 15 HP, chests = 1 (open on interact)

var is_open: bool = false
var is_destroyed: bool = false
var _model_node: Node3D = null
var _glow_light: OmniLight3D = null

# Chest loot table key
var loot_table_key: String = "chest"

func _ready() -> void:
	add_to_group("interactables")
	collision_layer = 4  # Layer 3 for interactables (bit 2 = layer 3)
	collision_mask = 0

	match interactable_type:
		Type.CHEST:
			hit_points = 1
			loot_table_key = "chest"
			_add_chest_glow()
		Type.BARREL:
			hit_points = 15
			loot_table_key = "barrel"

func setup_model(model: Node3D) -> void:
	_model_node = model

func _add_chest_glow() -> void:
	_glow_light = OmniLight3D.new()
	_glow_light.light_color = Color(1.0, 0.85, 0.3)
	_glow_light.light_energy = 0.4
	_glow_light.omni_range = 2.0
	_glow_light.omni_attenuation = 2.0
	_glow_light.shadow_enabled = false
	_glow_light.position = Vector3.UP * 0.5
	add_child(_glow_light)

func _process(_delta: float) -> void:
	if _glow_light and not is_open and not is_destroyed:
		_glow_light.light_energy = 0.3 + sin(Time.get_ticks_msec() * 0.003) * 0.15

## Called when hero clicks on this and is in range (chests)
func interact() -> void:
	if is_open or is_destroyed:
		return
	if interactable_type == Type.CHEST:
		_open_chest()

## Called by hero melee or spell damage
func take_damage(amount: int) -> void:
	if is_open or is_destroyed:
		return

	if interactable_type == Type.CHEST:
		# Attacking a chest just opens it
		_open_chest()
		return

	hit_points -= amount
	_flash_hit()

	if hit_points <= 0:
		_break_apart()

func _open_chest() -> void:
	is_open = true
	AudioManager.play_sfx("chest_open", 0.7, 0.1)

	# Lid-opening visual: tilt the model backward
	if _model_node:
		var tween := create_tween()
		tween.tween_property(_model_node, "rotation_degrees:x", -45.0, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Burst of golden light
	if _glow_light:
		var tween2 := create_tween()
		tween2.tween_property(_glow_light, "light_energy", 3.0, 0.15)
		tween2.tween_property(_glow_light, "light_energy", 0.0, 1.0)

	# Drop loot
	_spawn_chest_loot()
	interacted.emit()
	TutorialManager.notify_event("chest_opened")

	# Fade out after delay
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(self):
		var fade_tween := create_tween()
		if _model_node:
			fade_tween.tween_property(_model_node, "scale", Vector3(0.01, 0.01, 0.01), 0.5)
		fade_tween.tween_callback(queue_free)

func _break_apart() -> void:
	is_destroyed = true
	AudioManager.play_sfx("barrel_break", 0.7, 0.15)

	# Spawn debris particles (small boxes flying outward)
	_spawn_debris()

	# Drop minor loot
	_spawn_barrel_loot()
	destroyed.emit()

	# Remove immediately with a small shrink
	if _model_node:
		var tween := create_tween()
		tween.tween_property(_model_node, "scale", Vector3(0.01, 0.01, 0.01), 0.15)
		tween.tween_callback(queue_free)
	else:
		queue_free()

func _flash_hit() -> void:
	if _model_node == null:
		return
	# Quick white flash by modulating
	var meshes := _find_meshes(_model_node)
	for mi in meshes:
		for i in range(mi.get_surface_override_material_count()):
			var mat = mi.get_surface_override_material(i)
			if mat is StandardMaterial3D:
				var orig_color = mat.albedo_color
				mat.albedo_color = Color.WHITE
				get_tree().create_timer(0.06).timeout.connect(func():
					if is_instance_valid(mi):
						mat.albedo_color = orig_color
				)

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_find_meshes(child))
	return result

func _spawn_chest_loot() -> void:
	# 2-3 items from chest table
	var count := randi_range(2, 3)
	for _i in range(count):
		var item := LootManager._roll_weighted(LootManager.LOOT_TABLES.get(loot_table_key, LootManager.LOOT_TABLES["default"]))
		if item.is_empty():
			continue
		var item_def: Dictionary = LootManager.ITEMS.get(item["item_id"], {})
		if item_def.is_empty():
			continue
		LootManager._spawn_drop(global_position + Vector3.UP * 0.5, item_def)

func _spawn_barrel_loot() -> void:
	# 50% chance to drop something small
	if randf() > 0.5:
		return
	var item := LootManager._roll_weighted(LootManager.LOOT_TABLES.get(loot_table_key, LootManager.LOOT_TABLES["default"]))
	if item.is_empty():
		return
	var item_def: Dictionary = LootManager.ITEMS.get(item["item_id"], {})
	if item_def.is_empty():
		return
	LootManager._spawn_drop(global_position + Vector3.UP * 0.5, item_def)

func _spawn_debris() -> void:
	# 4-6 small box fragments flying outward
	var debris_count := randi_range(4, 6)
	for _i in range(debris_count):
		var piece := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.15, 0.15, 0.15)
		piece.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.45, 0.32, 0.18)  # Wood color
		mat.roughness = 0.9
		piece.set_surface_override_material(0, mat)

		piece.position = global_position + Vector3.UP * 0.5
		get_tree().root.add_child(piece)

		# Fly outward + up with random direction
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.5, 1.5), randf_range(-1.0, 1.0)).normalized()
		var target_pos := piece.position + dir * randf_range(1.0, 2.5)

		var tween := piece.create_tween()
		tween.tween_property(piece, "position", target_pos, 0.4).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(piece, "rotation_degrees", Vector3(randf_range(-360, 360), randf_range(-360, 360), 0), 0.4)
		tween.parallel().tween_property(piece, "scale", Vector3(0.01, 0.01, 0.01), 0.4).set_ease(Tween.EASE_IN).set_delay(0.2)
		tween.tween_callback(piece.queue_free)
