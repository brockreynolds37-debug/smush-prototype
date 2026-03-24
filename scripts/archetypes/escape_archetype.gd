extends FloorArchetype

## EscapeArchetype — auto-scrolling danger wall chases the hero.
## 3 boulder obstacles (deflect hero), 2 spike pits (instant damage).
## Win: reach exit. Lose: wall touches hero.
## HUD hint: "ESCAPE — REACH THE EXIT"

class_name EscapeArchetype

var _danger_wall: Node3D = null
var _danger_wall_z: float = -5.0
var _wall_base_speed: float = 5.0  # 5 units/sec, accelerating
var _wall_mesh: MeshInstance3D = null
var _escape_timer: float = 0.0
var _hud_overlay: Control = null
var _obstacles: Array[Node3D] = []

func _init() -> void:
	archetype_name = "Escape"
	flavor_text = "The floor is collapsing. Run."
	accent_color = Color(1.0, 0.3, 0.1)

func setup(p_builder: Node3D, p_units_node: Node3D, p_floor_number: int) -> void:
	super.setup(p_builder, p_units_node, p_floor_number)

func start() -> void:
	super.start()
	show_message("ESCAPE — REACH THE EXIT!", accent_color, 4.0)
	_create_danger_wall()
	_spawn_obstacles()

func _create_danger_wall() -> void:
	if not builder:
		return

	_danger_wall = Node3D.new()
	_danger_wall.name = "DangerWall"

	# Visual: tall red/orange wall of destruction
	_wall_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(60.0, 10.0, 3.0)
	_wall_mesh.mesh = box

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wall_mesh.material_override = mat
	_danger_wall.add_child(_wall_mesh)

	# Damage area — kills hero on contact
	var area = Area3D.new()
	area.name = "DangerArea"
	var shape = CollisionShape3D.new()
	var box_shape = BoxShape3D.new()
	box_shape.size = Vector3(60.0, 10.0, 3.0)
	shape.shape = box_shape
	area.add_child(shape)
	area.body_entered.connect(_on_danger_hit)
	_danger_wall.add_child(area)

	# Position behind the spawn
	var spawn_pos := Vector3.ZERO
	if builder.has_method("get_spawn_position"):
		spawn_pos = builder.get_spawn_position()
	_danger_wall_z = spawn_pos.z - 8.0
	_danger_wall.position = Vector3(spawn_pos.x, 3.0, _danger_wall_z)

	builder.add_child(_danger_wall)

func _spawn_obstacles() -> void:
	if not builder:
		return

	var spawn_pos := Vector3.ZERO
	if builder.has_method("get_spawn_position"):
		spawn_pos = builder.get_spawn_position()

	# 3 boulders spread along escape path
	for i in range(3):
		var boulder = StaticBody3D.new()
		boulder.name = "Boulder_%d" % i

		var mesh = MeshInstance3D.new()
		var sphere = SphereMesh.new()
		sphere.radius = 1.2
		sphere.height = 2.4
		mesh.mesh = sphere
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.35, 0.3)
		mesh.material_override = mat
		boulder.add_child(mesh)

		var col = CollisionShape3D.new()
		var col_shape = SphereShape3D.new()
		col_shape.radius = 1.2
		col.shape = col_shape
		boulder.add_child(col)

		var offset_x = randf_range(-6.0, 6.0)
		var offset_z = spawn_pos.z + 8.0 + (i * 10.0)
		boulder.position = Vector3(spawn_pos.x + offset_x, 1.2, offset_z)
		builder.add_child(boulder)
		_obstacles.append(boulder)

	# 2 spike pits (Area3D that deals damage)
	for i in range(2):
		var pit = Area3D.new()
		pit.name = "SpikePit_%d" % i

		var mesh = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(3.0, 0.3, 3.0)
		mesh.mesh = box
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.1, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.1, 0.0)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat
		pit.add_child(mesh)

		var col = CollisionShape3D.new()
		var col_shape = BoxShape3D.new()
		col_shape.size = Vector3(3.0, 1.0, 3.0)
		col.shape = col_shape
		pit.add_child(col)

		pit.body_entered.connect(_on_spike_hit)

		var offset_x = randf_range(-5.0, 5.0)
		var offset_z = spawn_pos.z + 14.0 + (i * 12.0)
		pit.position = Vector3(spawn_pos.x + offset_x, 0.15, offset_z)
		builder.add_child(pit)
		_obstacles.append(pit)

func update(delta: float) -> void:
	if not _is_active or not _danger_wall:
		return

	_escape_timer += delta

	# Accelerate wall: starts at 5 u/s, gains 0.2 u/s per second
	var current_speed = _wall_base_speed + (_escape_timer * 0.2)
	_danger_wall_z += current_speed * delta
	_danger_wall.position.z = _danger_wall_z

	# Pulse emission
	if _wall_mesh and _wall_mesh.material_override:
		var pulse = 2.0 + sin(_escape_timer * 4.0) * 1.5
		_wall_mesh.material_override.emission_energy_multiplier = pulse

	# Update HUD distance
	var hero = GameManager.hero
	if hero and _hud_overlay:
		var dist = hero.global_position.z - _danger_wall_z
		var label = _hud_overlay.get_node_or_null("DistLabel")
		if label:
			label.text = "Wall: %.0fm behind" % maxf(dist, 0.0)

func _on_danger_hit(body: Node3D) -> void:
	if not _is_active:
		return
	if body == GameManager.hero:
		show_message("CONSUMED BY THE COLLAPSE!", Color(1.0, 0.0, 0.0), 3.0)
		if GameManager.hero.has_method("take_damage"):
			GameManager.hero.take_damage(99999)

func _on_spike_hit(body: Node3D) -> void:
	if not _is_active:
		return
	if body == GameManager.hero and GameManager.hero.has_method("take_damage"):
		GameManager.hero.take_damage(80)
		show_message("SPIKE PIT!", Color(1.0, 0.3, 0.0), 1.5)
		GameManager.request_screen_shake(4.0, 0.2)

func stop() -> void:
	super.stop()
	if _danger_wall and is_instance_valid(_danger_wall):
		_danger_wall.queue_free()
		_danger_wall = null
	for obs in _obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	_obstacles.clear()

func has_boss() -> bool:
	return false

func has_smusher() -> bool:
	return true

func exit_visible_at_start() -> bool:
	return true

func uses_default_enemy_spawning() -> bool:
	return true

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "EscapeHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	var label = Label.new()
	label.name = "EscapeLabel"
	label.text = "ESCAPE — REACH THE EXIT"
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", accent_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-150, 8)
	_hud_overlay.add_child(label)

	var dist_label = Label.new()
	dist_label.name = "DistLabel"
	dist_label.text = ""
	dist_label.add_theme_font_size_override("font_size", 16)
	dist_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dist_label.position = Vector2(-100, 34)
	_hud_overlay.add_child(dist_label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
