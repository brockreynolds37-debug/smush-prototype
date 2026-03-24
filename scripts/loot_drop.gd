extends Area3D

## World loot drop — rotating 3D item with glow effect.
## Auto-pickup when hero enters detection radius.

var item_data: Dictionary = {}
var _time: float = 0.0
var _model_node: Node3D = null
var _glow_light: OmniLight3D = null
var _picked_up: bool = false
var _spawn_tween_done: bool = false

# Despawn after 60 seconds if not picked up
var _despawn_timer: float = 60.0

func _ready() -> void:
	# Read item data from meta (set by LootManager before adding to tree)
	item_data = get_meta("item_data", {})

	# Collision setup — detect hero entering pickup radius
	collision_layer = 0
	collision_mask = 2  # Hero layer (if set), otherwise we check manually

	# Build the visual
	_build_visual()

	# Build collision shape for pickup detection
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	add_child(col)

	# Connect body entered
	body_entered.connect(_on_body_entered)

	# Spawn animation — pop up from ground
	if _model_node:
		_model_node.scale = Vector3.ZERO
		var tween := create_tween()
		tween.tween_property(_model_node, "scale", Vector3.ONE * 0.6, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tween.tween_callback(func(): _spawn_tween_done = true)

func _build_visual() -> void:
	_model_node = Node3D.new()
	_model_node.name = "Model"
	add_child(_model_node)

	var rarity: int = item_data.get("rarity", 0)
	var mesh_color: Color = item_data.get("mesh_color", Color.WHITE)
	var model_path: String = item_data.get("model", "")

	if model_path != "" and ResourceLoader.exists(model_path):
		# Use actual GLB model
		var scene := load(model_path) as PackedScene
		if scene:
			var instance := scene.instantiate()
			instance.scale = Vector3(0.5, 0.5, 0.5)
			_model_node.add_child(instance)
	else:
		# Generate a simple mesh based on item type
		var mi := MeshInstance3D.new()
		var item_type: String = item_data.get("type", "consumable")
		match item_type:
			"currency":
				# Gold = flat cylinder (coin)
				var mesh := CylinderMesh.new()
				mesh.top_radius = 0.25
				mesh.bottom_radius = 0.25
				mesh.height = 0.08
				mi.mesh = mesh
			"consumable":
				# Potion = capsule
				var mesh := CapsuleMesh.new()
				mesh.radius = 0.15
				mesh.height = 0.4
				mi.mesh = mesh
			_:
				var mesh := BoxMesh.new()
				mesh.size = Vector3(0.3, 0.3, 0.3)
				mi.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = mesh_color
		mat.emission_enabled = true
		mat.emission = mesh_color
		mat.emission_energy_multiplier = 0.8
		mat.roughness = 0.3
		mat.metallic = 0.4 if item_type == "currency" else 0.1
		mi.set_surface_override_material(0, mat)
		_model_node.add_child(mi)

	# Glow light matching rarity color
	_glow_light = OmniLight3D.new()
	var glow_color: Color = LootManager.RARITY_COLORS.get(rarity, Color.WHITE)
	_glow_light.light_color = glow_color
	_glow_light.light_energy = 0.8
	_glow_light.omni_range = 2.5
	_glow_light.omni_attenuation = 2.0
	_glow_light.shadow_enabled = false
	_glow_light.position = Vector3.UP * 0.3
	add_child(_glow_light)

func _process(delta: float) -> void:
	if _picked_up:
		return

	_time += delta

	# Rotate and bob
	if _model_node and _spawn_tween_done:
		_model_node.rotation.y += delta * 2.0
		_model_node.position.y = sin(_time * 3.0) * 0.1 + 0.3

	# Pulse glow
	if _glow_light:
		_glow_light.light_energy = 0.6 + sin(_time * 4.0) * 0.3

	# Despawn timer
	_despawn_timer -= delta
	if _despawn_timer <= 0:
		_fade_out_and_free()

	# Manual proximity check (fallback if collision layers don't match)
	if GameManager.hero and not GameManager.hero.is_dead:
		var dist := global_position.distance_to(GameManager.hero.global_position)
		if dist < 1.8:
			_pickup()

func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.hero and not _picked_up:
		_pickup()

func _pickup() -> void:
	if _picked_up:
		return
	_picked_up = true

	LootManager.pickup_item(item_data)
	var rarity_name: String = LootManager.RARITY_NAMES.get(item_data.get("rarity", 0), "Common").to_lower()
	AudioManager.on_loot_pickup(rarity_name)

	# Pickup animation — fly up and shrink
	var tween := create_tween()
	tween.tween_property(self, "position:y", position.y + 1.5, 0.25).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_model_node, "scale", Vector3.ZERO, 0.25).set_ease(Tween.EASE_IN)
	if _glow_light:
		tween.parallel().tween_property(_glow_light, "light_energy", 3.0, 0.1)
		tween.tween_property(_glow_light, "light_energy", 0.0, 0.15)
	tween.tween_callback(queue_free)

func _fade_out_and_free() -> void:
	_picked_up = true
	var tween := create_tween()
	if _model_node:
		tween.tween_property(_model_node, "scale", Vector3.ZERO, 0.5)
	if _glow_light:
		tween.parallel().tween_property(_glow_light, "light_energy", 0.0, 0.5)
	tween.tween_callback(queue_free)
