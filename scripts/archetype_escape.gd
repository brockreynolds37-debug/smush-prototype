extends FloorArchetype

## EscapeArchetype — the floor is collapsing behind you.
## Auto-scrolling danger wall chases the player. Dodge obstacles, reach the exit.
## Speed and movement matter more than combat. Timer-based exit.

class_name EscapeArchetype

var _danger_wall: Node3D = null
var _danger_wall_z: float = -5.0
var _wall_speed: float = 3.0  # Units per second — accelerates over time
var _wall_mesh: MeshInstance3D = null
var _warning_shown: bool = false
var _escape_timer: float = 0.0
var _hud_overlay: Control = null

func _init() -> void:
	archetype_name = "Escape"
	flavor_text = "The floor is collapsing. Run."
	accent_color = Color(1.0, 0.3, 0.1)

func start() -> void:
	super.start()
	show_message("ESCAPE! The floor is collapsing behind you — RUN!", accent_color, 4.0)

	# Create the advancing danger wall
	_create_danger_wall()

	# Speed up Smusher timer for extra pressure
	if SmusherTimer:
		SmusherTimer.time_scale = 1.3

func _create_danger_wall() -> void:
	if not builder:
		return

	_danger_wall = Node3D.new()
	_danger_wall.name = "DangerWall"

	# Visual: a tall red/orange wall of destruction
	_wall_mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(60.0, 8.0, 2.0)
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
	box_shape.size = Vector3(60.0, 8.0, 2.0)
	shape.shape = box_shape
	area.add_child(shape)
	area.body_entered.connect(_on_danger_hit)
	_danger_wall.add_child(area)

	# Position behind the spawn
	var spawn_pos = builder.get_spawn_position()
	_danger_wall_z = spawn_pos.z - 6.0
	_danger_wall.position = Vector3(spawn_pos.x, 2.0, _danger_wall_z)

	builder.add_child(_danger_wall)

func update(delta: float) -> void:
	if not _is_active or not _danger_wall:
		return

	_escape_timer += delta

	# Accelerate wall over time
	var current_speed = _wall_speed + (_escape_timer * 0.15)
	_danger_wall_z += current_speed * delta
	_danger_wall.position.z = _danger_wall_z

	# Pulse the emission for drama
	if _wall_mesh and _wall_mesh.material_override:
		var pulse = 2.0 + sin(_escape_timer * 4.0) * 1.5
		_wall_mesh.material_override.emission_energy_multiplier = pulse

	# Warn player when wall is close
	var hero = GameManager.hero
	if hero and not _warning_shown:
		var dist = hero.global_position.z - _danger_wall_z
		if dist < 12.0:
			show_message("IT'S RIGHT BEHIND YOU!", Color(1.0, 0.1, 0.0), 2.0)
			_warning_shown = true

	# Check if hero reached the exit — exit_visible_at_start = true for escape
	# FloorManager handles the actual exit detection

func _on_danger_hit(body: Node3D) -> void:
	if not _is_active:
		return
	if body == GameManager.hero:
		# Instant kill — the wall consumes you
		show_message("CONSUMED BY THE COLLAPSE", Color(1.0, 0.0, 0.0), 3.0)
		if GameManager.hero.has_method("take_damage"):
			GameManager.hero.take_damage(99999)

func stop() -> void:
	super.stop()
	if _danger_wall and is_instance_valid(_danger_wall):
		_danger_wall.queue_free()
		_danger_wall = null
	if SmusherTimer:
		SmusherTimer.time_scale = 1.0

func has_boss() -> bool:
	return false  # No boss — just survive the escape

func has_smusher() -> bool:
	return true  # Smusher adds extra pressure

func exit_visible_at_start() -> bool:
	return true  # You can see the exit — just gotta get there

func uses_default_enemy_spawning() -> bool:
	return true  # Sparse enemies as obstacles, but fewer than crawl

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "EscapeHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	var label = Label.new()
	label.name = "EscapeLabel"
	label.text = "ESCAPE — The floor is collapsing!"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", accent_color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(-150, 8)
	_hud_overlay.add_child(label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
