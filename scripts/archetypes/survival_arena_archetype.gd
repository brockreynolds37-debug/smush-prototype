extends FloorArchetype

## SurvivalArenaArchetype — locked arena, survive 5 waves of enemies.
## Exit locked until all waves are defeated. Enemies spawn from 4 corners.
## Each wave +30% enemy count. 5-second rest between waves with countdown.

class_name SurvivalArenaArchetype

const TOTAL_WAVES: int = 5
const BASE_ENEMIES_PER_WAVE: int = 3
const WAVE_SCALE: float = 1.3
const REST_DURATION: float = 5.0

var _current_wave: int = 0
var _wave_enemies_alive: int = 0
var _rest_timer: float = 0.0
var _is_resting: bool = false
var _hud_overlay: Control = null
var _wave_label: Label = null
var _enemy_label: Label = null
var _countdown_label: Label = null
var _enemy_types := ["goblin_warrior", "skeleton", "orc", "spider", "wolf"]
var _spawn_corners: Array[Vector3] = []

func _init() -> void:
	archetype_name = "Survival Arena"
	flavor_text = "The exits are sealed. Survive the onslaught."
	accent_color = Color(0.9, 0.2, 0.2)
	solution_paths = {"combat": true, "speed": true, "social": false, "clever": true}
	audience_favorite_path = "combat"

func setup(p_builder: Node3D, p_units_node: Node3D, p_floor_number: int) -> void:
	super.setup(p_builder, p_units_node, p_floor_number)
	# Define 4 spawn corners relative to arena center
	var center := Vector3.ZERO
	if builder and builder.has_method("get_spawn_position"):
		center = builder.get_spawn_position()
	var offset := 12.0
	_spawn_corners = [
		center + Vector3(-offset, 0, -offset),
		center + Vector3(offset, 0, -offset),
		center + Vector3(-offset, 0, offset),
		center + Vector3(offset, 0, offset),
	]

func _register_solution_paths() -> void:
	SolutionPathTracker.register_floor_paths(
		SolutionPathTracker.paths_survival(), "combat"
	)

func start() -> void:
	super.start()
	show_message("SURVIVAL ARENA — Defeat all waves to escape!", accent_color, 3.0)
	GameManager.enemy_died.connect(_on_arena_enemy_died)
	# Start first wave after brief delay
	_current_wave = 0
	_is_resting = true
	_rest_timer = 3.0  # Short initial delay

func update(delta: float) -> void:
	if not _is_active:
		return

	if _is_resting:
		_rest_timer -= delta
		if _countdown_label:
			_countdown_label.text = "Next wave in %d..." % ceili(_rest_timer)
			_countdown_label.visible = true
		if _rest_timer <= 0.0:
			_is_resting = false
			if _countdown_label:
				_countdown_label.visible = false
			_spawn_next_wave()
	else:
		# Update HUD
		if _enemy_label:
			_enemy_label.text = "Enemies: %d" % _wave_enemies_alive

func _spawn_next_wave() -> void:
	_current_wave += 1
	if _current_wave > TOTAL_WAVES:
		_on_all_waves_cleared()
		return

	var count := int(BASE_ENEMIES_PER_WAVE * pow(WAVE_SCALE, _current_wave - 1))
	_wave_enemies_alive = count

	show_message("WAVE %d/%d" % [_current_wave, TOTAL_WAVES], accent_color, 2.0)

	if _wave_label:
		_wave_label.text = "Wave %d/%d" % [_current_wave, TOTAL_WAVES]

	# Spawn enemies from 4 corners
	for i in range(count):
		var corner = _spawn_corners[i % _spawn_corners.size()]
		var jitter = Vector3(randf_range(-2.0, 2.0), 0, randf_range(-2.0, 2.0))
		var spawn_pos = corner + jitter

		var enemy_scene = preload("res://scenes/enemy.tscn")
		var enemy = enemy_scene.instantiate()
		enemy.enemy_type = _enemy_types[randi() % _enemy_types.size()]
		enemy.position = spawn_pos

		if units_node:
			units_node.add_child(enemy)
		elif builder:
			builder.add_child(enemy)

func _on_arena_enemy_died(_enemy: Node3D) -> void:
	if not _is_active:
		return
	_wave_enemies_alive = maxi(_wave_enemies_alive - 1, 0)

	if _wave_enemies_alive <= 0:
		if _current_wave >= TOTAL_WAVES:
			_on_all_waves_cleared()
		else:
			_is_resting = true
			_rest_timer = REST_DURATION
			show_message("WAVE CLEARED!", Color(0.2, 1.0, 0.4), 2.0)

func _on_all_waves_cleared() -> void:
	show_message("ALL WAVES DEFEATED — EXIT UNLOCKED!", Color(0.2, 1.0, 0.4), 3.0)
	complete()

func stop() -> void:
	super.stop()
	if GameManager.enemy_died.is_connected(_on_arena_enemy_died):
		GameManager.enemy_died.disconnect(_on_arena_enemy_died)

func has_boss() -> bool:
	return false

func has_smusher() -> bool:
	return false

func exit_visible_at_start() -> bool:
	return false

func uses_default_enemy_spawning() -> bool:
	return false

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "ArenaHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.text = "Wave 0/%d" % TOTAL_WAVES
	_wave_label.add_theme_font_size_override("font_size", 24)
	_wave_label.add_theme_color_override("font_color", accent_color)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.position = Vector2(-100, 8)
	_hud_overlay.add_child(_wave_label)

	_enemy_label = Label.new()
	_enemy_label.name = "EnemyLabel"
	_enemy_label.text = "Enemies: 0"
	_enemy_label.add_theme_font_size_override("font_size", 18)
	_enemy_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.5))
	_enemy_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enemy_label.position = Vector2(-80, 36)
	_hud_overlay.add_child(_enemy_label)

	_countdown_label = Label.new()
	_countdown_label.name = "CountdownLabel"
	_countdown_label.text = ""
	_countdown_label.add_theme_font_size_override("font_size", 32)
	_countdown_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.3))
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.position = Vector2(-120, 60)
	_countdown_label.visible = false
	_hud_overlay.add_child(_countdown_label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
	_wave_label = null
	_enemy_label = null
	_countdown_label = null
