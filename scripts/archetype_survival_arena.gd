extends FloorArchetype

## SurvivalArenaArchetype — locked in a circular arena. Survive X waves to unlock exit.
## Wave counter HUD. Difficulty ramps per wave. Brief heal window between waves.

class_name SurvivalArenaArchetype

var _current_wave: int = 0
var _total_waves: int = 5
var _wave_active: bool = false
var _enemies_this_wave: int = 0
var _enemies_killed_this_wave: int = 0
var _between_wave_timer: float = 0.0
var _between_wave_duration: float = 5.0  # Seconds of breathing room
var _is_between_waves: bool = false
var _hud_overlay: Control = null
var _wave_label: Label = null
var _status_label: Label = null

func _init() -> void:
	archetype_name = "Survival Arena"
	flavor_text = "Survive the waves. No escape until they stop."
	accent_color = Color(1.0, 0.7, 0.1)

func start() -> void:
	super.start()
	_total_waves = 3 + floor_number  # More waves on higher floors
	show_message("SURVIVAL ARENA — Survive %d waves!" % _total_waves, accent_color, 4.0)

	# Start first wave after a brief delay
	_is_between_waves = true
	_between_wave_timer = 3.0  # 3 second grace period before wave 1

	# Connect enemy death tracking
	GameManager.enemy_died.connect(_on_enemy_killed)

func update(delta: float) -> void:
	if not _is_active:
		return

	if _is_between_waves:
		_between_wave_timer -= delta
		if _status_label:
			if _between_wave_timer > 0:
				_status_label.text = "Next wave in %.0f..." % ceil(_between_wave_timer)
				_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			else:
				_status_label.text = ""

		if _between_wave_timer <= 0:
			_is_between_waves = false
			_start_next_wave()

	elif _wave_active:
		# Check if all enemies this wave are dead
		if _enemies_killed_this_wave >= _enemies_this_wave:
			_wave_active = false
			_on_wave_cleared()

func _start_next_wave() -> void:
	_current_wave += 1
	_wave_active = true
	_enemies_killed_this_wave = 0

	# Enemy count scales with wave and floor
	_enemies_this_wave = 2 + _current_wave * 2 + floor_number

	show_message("WAVE %d / %d" % [_current_wave, _total_waves], accent_color, 2.5)

	if _wave_label:
		_wave_label.text = "Wave %d / %d" % [_current_wave, _total_waves]

	# Spawn wave enemies
	_spawn_wave_enemies()

func _spawn_wave_enemies() -> void:
	if not units_node or not builder:
		return

	var orc_scene = preload("res://scenes/enemy.tscn")
	var skeleton_scene = preload("res://scenes/enemy_skeleton.tscn")
	var archer_scene = preload("res://scenes/enemy_goblin_archer.tscn")
	var mage_scene = preload("res://scenes/enemy_mage.tscn")

	var arena_center = builder.get_room_center("arena")
	if arena_center == Vector3.ZERO:
		arena_center = builder.get_spawn_position() + Vector3(10, 0, 10)

	for i in range(_enemies_this_wave):
		var enemy: Node3D
		# Later waves introduce tougher enemy types
		if _current_wave >= 3 and i % 4 == 3:
			enemy = mage_scene.instantiate()
		elif _current_wave >= 2 and i % 3 == 2:
			enemy = archer_scene.instantiate()
		elif i % 2 == 0:
			enemy = orc_scene.instantiate()
		else:
			enemy = skeleton_scene.instantiate()

		# Scale enemy stats with wave number
		var wave_scale = 1.0 + (_current_wave - 1) * 0.2
		enemy.max_health = int(enemy.max_health * wave_scale)
		enemy.current_health = enemy.max_health
		enemy.attack_damage = int(enemy.attack_damage * wave_scale)

		# Elite chance increases per wave
		EliteModifier.try_promote(enemy, floor_number + _current_wave)

		# Spawn at arena edges in a rough circle
		var angle = (float(i) / _enemies_this_wave) * TAU
		var radius = 8.0 + randf() * 4.0
		var spawn_pos = arena_center + Vector3(cos(angle) * radius, 0, sin(angle) * radius)
		enemy.global_position = spawn_pos
		units_node.add_child(enemy)

func _on_enemy_killed(_enemy: Node3D = null) -> void:
	if not _is_active or not _wave_active:
		return
	_enemies_killed_this_wave += 1

	if _status_label:
		var remaining = _enemies_this_wave - _enemies_killed_this_wave
		_status_label.text = "%d enemies remaining" % remaining
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))

func _on_wave_cleared() -> void:
	if _current_wave >= _total_waves:
		# All waves complete — victory!
		show_message("ALL WAVES SURVIVED! EXIT UNLOCKED!", Color(0.2, 1.0, 0.4), 3.0)
		if _status_label:
			_status_label.text = "COMPLETE!"
			_status_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))

		# Heal hero as reward
		if GameManager.hero and GameManager.hero.has_method("heal"):
			GameManager.hero.heal(int(GameManager.hero.max_health * 0.3))

		complete()
	else:
		# Brief rest between waves — partial heal
		show_message("Wave %d cleared! Breathe..." % _current_wave, Color(0.5, 1.0, 0.5), 2.5)

		if GameManager.hero and GameManager.hero.has_method("heal"):
			GameManager.hero.heal(int(GameManager.hero.max_health * 0.15))

		_is_between_waves = true
		_between_wave_timer = _between_wave_duration

func stop() -> void:
	super.stop()
	if GameManager.enemy_died.is_connected(_on_enemy_killed):
		GameManager.enemy_died.disconnect(_on_enemy_killed)

func has_boss() -> bool:
	return false  # Waves ARE the challenge

func has_smusher() -> bool:
	return true  # Smusher still runs — adds urgency

func exit_visible_at_start() -> bool:
	return false  # Exit only appears after all waves

func uses_default_enemy_spawning() -> bool:
	return false  # We handle our own spawning per wave

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "ArenaHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_CENTER_TOP)

	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.text = "Wave 0 / %d" % _total_waves
	_wave_label.add_theme_font_size_override("font_size", 22)
	_wave_label.add_theme_color_override("font_color", accent_color)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.position = Vector2(-100, 8)
	_hud_overlay.add_child(_wave_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "Preparing..."
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(-100, 36)
	_hud_overlay.add_child(_status_label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
