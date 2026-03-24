extends FloorArchetype

## InversionArchetype — YOU are the dungeon boss. Defend your room against
## waves of AI crawlers from another civilization. Place traps, command minions,
## set up kill zones. Tower defense meets Dungeon Keeper.

class_name InversionArchetype

const TOTAL_WAVES := 5
const WAVE_INTERVAL := 12.0  # Seconds between waves
const CRAWLERS_BASE := 4
const TRAP_SLOTS := 5
const MINION_SLOTS := 3
const CORE_MAX_HP := 500

# ── State ──
var _current_wave: int = 0
var _wave_active: bool = false
var _crawlers_alive: int = 0
var _between_wave_timer: float = 0.0
var _is_between_waves: bool = false
var _core_hp: int = CORE_MAX_HP
var _core_max_hp: int = CORE_MAX_HP
var _traps_placed: int = 0
var _minions_placed: int = 0
var _placement_mode: String = ""  # "", "trap", "minion"
var _crawlers: Array[Node3D] = []
var _placed_traps: Array[Node3D] = []
var _placed_minions: Array[Node3D] = []
var _core_node: Node3D = null
var _spawn_points: Array[Vector3] = []
var _hud_overlay: Control = null
var _wave_label: Label = null
var _status_label: Label = null
var _core_label: Label = null
var _placement_label: Label = null

func _init() -> void:
	archetype_name = "Inversion"
	flavor_text = "You are the boss now. Defend your dungeon."
	accent_color = Color(0.9, 0.3, 0.6)
	solution_paths = {"combat": true, "speed": false, "social": false, "clever": true}
	audience_favorite_path = "clever"

func _register_solution_paths() -> void:
	SolutionPathTracker.register_floor_paths(
		SolutionPathTracker.paths_inversion(), "clever"
	)

func start() -> void:
	super.start()
	_current_wave = 0
	_wave_active = false
	_crawlers_alive = 0
	_traps_placed = 0
	_minions_placed = 0
	_placement_mode = ""
	_core_max_hp = CORE_MAX_HP + floor_number * 50
	_core_hp = _core_max_hp

	_setup_spawn_points()
	_spawn_core()

	show_message("INVERSION — You are the dungeon boss!", accent_color, 4.0)
	show_message("[1] Place Trap (%d left)  [2] Place Minion (%d left)  [Click] to place" % [TRAP_SLOTS, MINION_SLOTS], Color(0.7, 0.7, 0.7), 4.0)

	GameManager.enemy_died.connect(_on_crawler_died)

	# Start with a preparation phase
	_is_between_waves = true
	_between_wave_timer = WAVE_INTERVAL

func _setup_spawn_points() -> void:
	# Crawlers enter from the edges of the room
	var center = Vector3.ZERO
	if builder:
		center = builder.get_room_center("arena")
		if center == Vector3.ZERO:
			center = builder.get_spawn_position() + Vector3(10, 0, 10)

	_spawn_points = [
		center + Vector3(-18, 0, 0),
		center + Vector3(18, 0, 0),
		center + Vector3(0, 0, -18),
		center + Vector3(0, 0, 18),
		center + Vector3(-14, 0, -14),
		center + Vector3(14, 0, 14),
	]

func _spawn_core() -> void:
	if not builder:
		return

	_core_node = Node3D.new()
	_core_node.name = "DungeonCore"

	# Large glowing crystal
	var mesh = MeshInstance3D.new()
	var box = BoxMesh.new()
	box.size = Vector3(1.5, 3.0, 1.5)
	mesh.mesh = box
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 0.3, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.metallic = 0.6
	mat.roughness = 0.3
	mesh.material_override = mat
	mesh.name = "CoreMesh"
	_core_node.add_child(mesh)

	# Light
	var light = OmniLight3D.new()
	light.light_color = Color(0.8, 0.3, 1.0)
	light.light_energy = 3.0
	light.omni_range = 12.0
	light.position = Vector3(0, 2, 0)
	_core_node.add_child(light)

	# Label
	var label = Label3D.new()
	label.text = "DUNGEON CORE\nHP: %d/%d" % [_core_hp, _core_max_hp]
	label.font_size = 48
	label.position = Vector3(0, 3.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.5, 1.0)
	label.name = "CoreLabel"
	_core_node.add_child(label)

	var center = Vector3.ZERO
	if builder:
		center = builder.get_room_center("arena")
		if center == Vector3.ZERO:
			center = builder.get_spawn_position() + Vector3(10, 0, 10)
	_core_node.position = center
	builder.add_child(_core_node)

# ── UPDATE ──

func update(delta: float) -> void:
	if not _is_active:
		return

	var hero = GameManager.hero
	if not hero or hero.is_dead:
		return

	# Placement mode input
	if Input.is_action_just_pressed("spell_1"):
		_toggle_placement("trap")
	elif Input.is_action_just_pressed("spell_2"):
		_toggle_placement("minion")

	# Click to place
	if _placement_mode != "" and Input.is_action_just_pressed("attack"):
		_place_at_hero_position(hero)

	# Between waves timer
	if _is_between_waves:
		_between_wave_timer -= delta
		if _status_label:
			if _between_wave_timer > 0:
				_status_label.text = "Wave %d in %.0f... PLACE DEFENSES!" % [_current_wave + 1, ceil(_between_wave_timer)]
				_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
			else:
				_status_label.text = ""
		if _between_wave_timer <= 0:
			_is_between_waves = false
			_start_next_wave()

	elif _wave_active:
		# Update crawlers — move toward core
		_update_crawlers(delta)

		# Check if wave is cleared
		if _crawlers_alive <= 0:
			_wave_active = false
			_on_wave_cleared()

	# Update core HP display
	_update_core_label()
	_update_hud()

	# Check for core destruction (game over condition for this archetype)
	if _core_hp <= 0:
		_on_core_destroyed()

# ── PLACEMENT ──

func _toggle_placement(mode: String) -> void:
	if _placement_mode == mode:
		_placement_mode = ""
		show_message("Placement cancelled.", Color(0.6, 0.6, 0.6), 1.0)
	else:
		if mode == "trap" and _traps_placed >= TRAP_SLOTS:
			show_message("No trap slots left!", Color(1.0, 0.3, 0.2), 1.5)
			return
		if mode == "minion" and _minions_placed >= MINION_SLOTS:
			show_message("No minion slots left!", Color(1.0, 0.3, 0.2), 1.5)
			return
		_placement_mode = mode
		show_message("Click to place %s..." % mode, accent_color, 2.0)

	if _placement_label:
		if _placement_mode != "":
			_placement_label.text = "PLACING: %s (click to confirm)" % _placement_mode.to_upper()
			_placement_label.add_theme_color_override("font_color", accent_color)
		else:
			_placement_label.text = "[1] Trap (%d left)  [2] Minion (%d left)" % [TRAP_SLOTS - _traps_placed, MINION_SLOTS - _minions_placed]
			_placement_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

func _place_at_hero_position(hero: Node3D) -> void:
	var pos = hero.global_position

	if _placement_mode == "trap":
		_place_trap(pos)
	elif _placement_mode == "minion":
		_place_minion(pos)

	_placement_mode = ""
	if _placement_label:
		_placement_label.text = "[1] Trap (%d left)  [2] Minion (%d left)" % [TRAP_SLOTS - _traps_placed, MINION_SLOTS - _minions_placed]
		_placement_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))

func _place_trap(pos: Vector3) -> void:
	if _traps_placed >= TRAP_SLOTS:
		return

	_traps_placed += 1

	var trap = Area3D.new()
	trap.name = "PlacedTrap_%d" % _traps_placed

	# Visual — spike-like mesh
	var mesh = MeshInstance3D.new()
	var cone = CylinderMesh.new()
	cone.top_radius = 0.05
	cone.bottom_radius = 0.6
	cone.height = 1.2
	mesh.mesh = cone
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.2, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.3, 0.1)
	mat.emission_energy_multiplier = 1.0
	mesh.material_override = mat
	trap.add_child(mesh)

	# Collision for detecting crawlers
	var col = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.0
	col.shape = sphere
	trap.add_child(col)

	# Trap damage config
	trap.set_meta("damage", 30 + floor_number * 10)
	trap.set_meta("cooldown", 0.0)
	trap.set_meta("cooldown_max", 1.5)

	var label = Label3D.new()
	label.text = "TRAP"
	label.font_size = 28
	label.position = Vector3(0, 1.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.4, 0.2)
	trap.add_child(label)

	trap.position = pos
	trap.position.y = 0.0
	builder.add_child(trap)
	_placed_traps.append(trap)

	show_message("Trap placed! (%d/%d)" % [_traps_placed, TRAP_SLOTS], Color(0.8, 0.4, 0.2), 1.5)
	AudienceManager.grant_vp(5, "Trap placed!")

func _place_minion(pos: Vector3) -> void:
	if _minions_placed >= MINION_SLOTS:
		return

	_minions_placed += 1

	var minion = CharacterBody3D.new()
	minion.name = "DefenseMinion_%d" % _minions_placed

	var col = CollisionShape3D.new()
	var capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.5
	col.shape = capsule
	minion.add_child(col)

	var mesh = MeshInstance3D.new()
	var capsule_mesh = CapsuleMesh.new()
	capsule_mesh.radius = 0.35
	capsule_mesh.height = 1.5
	mesh.mesh = capsule_mesh
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 0.3, 0.9)
	mat.emission_energy_multiplier = 0.8
	mesh.material_override = mat
	minion.add_child(mesh)

	var label = Label3D.new()
	label.text = "MINION"
	label.font_size = 28
	label.position = Vector3(0, 1.5, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.7, 0.3, 0.9)
	minion.add_child(label)

	minion.set_meta("max_health", 80 + floor_number * 15)
	minion.set_meta("current_health", 80 + floor_number * 15)
	minion.set_meta("damage", 20 + floor_number * 5)
	minion.set_meta("attack_cd", 0.0)
	minion.set_meta("home_pos", pos)

	minion.position = pos
	minion.position.y = 0.0
	builder.add_child(minion)
	_placed_minions.append(minion)

	show_message("Minion deployed! (%d/%d)" % [_minions_placed, MINION_SLOTS], Color(0.6, 0.3, 0.9), 1.5)
	AudienceManager.grant_vp(5, "Minion deployed!")

# ── WAVES ──

func _start_next_wave() -> void:
	_current_wave += 1
	_wave_active = true

	var count = CRAWLERS_BASE + _current_wave * 2 + floor_number
	_crawlers_alive = count

	show_message("WAVE %d / %d — %d crawlers incoming!" % [_current_wave, TOTAL_WAVES, count], accent_color, 3.0)

	if _wave_label:
		_wave_label.text = "Wave %d / %d" % [_current_wave, TOTAL_WAVES]

	_spawn_crawlers(count)

func _spawn_crawlers(count: int) -> void:
	if not builder or not units_node:
		return

	var enemy_scenes := [
		preload("res://scenes/enemy.tscn"),
		preload("res://scenes/enemy_skeleton.tscn"),
		preload("res://scenes/enemy_goblin_archer.tscn"),
	]

	for i in range(count):
		var scene = enemy_scenes[i % enemy_scenes.size()]
		var crawler: Node3D = scene.instantiate()

		# Scale with wave
		var wave_scale := 1.0 + (_current_wave - 1) * 0.15
		crawler.max_health = int(crawler.max_health * wave_scale)
		crawler.current_health = crawler.max_health

		# Apply difficulty multiplier
		var diff_mult := GameManager.get_difficulty_multiplier()
		if diff_mult != 1.0:
			crawler.max_health = int(crawler.max_health * diff_mult)
			crawler.current_health = crawler.max_health

		# Spawn at random edge point
		var spawn_pt = _spawn_points[randi() % _spawn_points.size()]
		var offset = Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		crawler.global_position = spawn_pt + offset

		# Mark as crawler so we know they target the core
		crawler.set_meta("is_crawler", true)
		crawler.set_meta("target_core", true)

		units_node.add_child(crawler)
		_crawlers.append(crawler)

func _update_crawlers(delta: float) -> void:
	if not is_instance_valid(_core_node):
		return

	var core_pos = _core_node.global_position

	# Process traps
	for trap in _placed_traps:
		if not is_instance_valid(trap):
			continue
		var cd: float = trap.get_meta("cooldown", 0.0) - delta
		trap.set_meta("cooldown", maxf(cd, 0.0))
		if cd > 0:
			continue

		var trap_dmg: int = trap.get_meta("damage", 30)
		for crawler in _crawlers:
			if not is_instance_valid(crawler):
				continue
			var dist = crawler.global_position.distance_to(trap.global_position)
			if dist < 2.0:
				if crawler.has_method("take_damage"):
					crawler.take_damage(trap_dmg)
				trap.set_meta("cooldown", trap.get_meta("cooldown_max", 1.5))
				break

	# Process minions (attack nearest crawler)
	for minion in _placed_minions:
		if not is_instance_valid(minion):
			continue

		var atk_cd: float = minion.get_meta("attack_cd", 0.0) - delta
		minion.set_meta("attack_cd", maxf(atk_cd, 0.0))

		var nearest: Node3D = null
		var nearest_dist := 999.0
		for crawler in _crawlers:
			if not is_instance_valid(crawler):
				continue
			var d = crawler.global_position.distance_to(minion.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = crawler

		if nearest and nearest_dist < 6.0:
			# Move toward nearest crawler
			var dir = (nearest.global_position - minion.global_position).normalized()
			dir.y = 0
			minion.velocity = dir * 4.0
			minion.move_and_slide()

			# Attack if close enough
			if nearest_dist < 2.5 and atk_cd <= 0:
				var dmg: int = minion.get_meta("damage", 20)
				if nearest.has_method("take_damage"):
					nearest.take_damage(dmg)
				minion.set_meta("attack_cd", 1.2)
		else:
			# Return to home position
			var home: Vector3 = minion.get_meta("home_pos", minion.global_position)
			if minion.global_position.distance_to(home) > 1.0:
				var dir = (home - minion.global_position).normalized()
				dir.y = 0
				minion.velocity = dir * 2.0
				minion.move_and_slide()
			else:
				minion.velocity = Vector3.ZERO

	# Crawlers that reach the core deal damage to it
	for crawler in _crawlers:
		if not is_instance_valid(crawler):
			continue
		var dist = crawler.global_position.distance_to(core_pos)
		if dist < 3.0:
			# Crawler damages core and is destroyed
			var dmg := 15 + _current_wave * 5
			_core_hp -= dmg
			show_message("Core hit! -%d HP" % dmg, Color(1.0, 0.3, 0.3), 1.0)
			if crawler.has_method("take_damage"):
				crawler.take_damage(9999)  # Kill the crawler

func _on_crawler_died(_enemy: Node3D) -> void:
	if not _is_active or not _wave_active:
		return
	_crawlers_alive -= 1

	# Remove from our tracking
	for i in range(_crawlers.size()):
		if _crawlers[i] == _enemy:
			_crawlers.remove_at(i)
			break

	AudienceManager.grant_vp(8, "Crawler eliminated!")

	if _status_label:
		_status_label.text = "%d crawlers remaining" % _crawlers_alive
		_status_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))

func _on_wave_cleared() -> void:
	if _current_wave >= TOTAL_WAVES:
		_on_all_waves_survived()
	else:
		show_message("Wave %d cleared! Prepare defenses!" % _current_wave, Color(0.5, 1.0, 0.5), 2.5)

		# Grant bonus trap/minion slots per wave cleared
		if _current_wave % 2 == 0:
			show_message("+1 Trap slot!", Color(0.8, 0.4, 0.2), 2.0)

		# Partial core heal between waves
		_core_hp = mini(_core_hp + int(_core_max_hp * 0.1), _core_max_hp)

		_is_between_waves = true
		_between_wave_timer = WAVE_INTERVAL

		if _status_label:
			_status_label.text = "Prepare defenses!"
			_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))

func _on_all_waves_survived() -> void:
	show_message("ALL WAVES REPELLED! Your dungeon stands!", Color(0.2, 1.0, 0.4), 4.0)
	AudienceManager.grant_vp(80, "Dungeon defended!")
	GameManager.request_screen_shake(3.0, 0.2)

	# Heal hero as reward
	if GameManager.hero and GameManager.hero.has_method("heal"):
		GameManager.hero.heal(int(GameManager.hero.max_health * 0.3))

	complete()

func _on_core_destroyed() -> void:
	if not _is_active:
		return

	show_message("DUNGEON CORE DESTROYED! You failed as a boss.", Color(1.0, 0.1, 0.1), 4.0)
	AudienceManager.grant_vp(20, "Core destroyed — dramatic failure!")

	# Core destruction = floor failed, but hero survives — just complete the floor
	# (The Collective finds failure entertaining too)
	complete()

func _update_core_label() -> void:
	if not is_instance_valid(_core_node):
		return
	var label = _core_node.get_node_or_null("CoreLabel")
	if label:
		var pct = float(_core_hp) / float(_core_max_hp)
		label.text = "DUNGEON CORE\nHP: %d/%d" % [_core_hp, _core_max_hp]
		if pct < 0.3:
			label.modulate = Color(1.0, 0.2, 0.2)
		elif pct < 0.6:
			label.modulate = Color(1.0, 0.7, 0.3)
		else:
			label.modulate = Color(1.0, 0.5, 1.0)

# ── HUD ──

func _update_hud() -> void:
	if not _hud_overlay:
		return

	if _core_label:
		var pct = float(_core_hp) / float(_core_max_hp)
		_core_label.text = "Core HP: %d/%d (%.0f%%)" % [_core_hp, _core_max_hp, pct * 100]
		if pct < 0.3:
			_core_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
		elif pct < 0.6:
			_core_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
		else:
			_core_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))

# ── OVERRIDES ──

func stop() -> void:
	super.stop()
	if GameManager.enemy_died.is_connected(_on_crawler_died):
		GameManager.enemy_died.disconnect(_on_crawler_died)

	for trap in _placed_traps:
		if is_instance_valid(trap):
			trap.queue_free()
	_placed_traps.clear()
	for minion in _placed_minions:
		if is_instance_valid(minion):
			minion.queue_free()
	_placed_minions.clear()
	for crawler in _crawlers:
		if is_instance_valid(crawler):
			crawler.queue_free()
	_crawlers.clear()
	if is_instance_valid(_core_node):
		_core_node.queue_free()
	_core_node = null

func has_boss() -> bool:
	return false

func has_merchant() -> bool:
	return true

func has_smusher() -> bool:
	return false  # Waves are the pressure mechanic

func exit_visible_at_start() -> bool:
	return false  # Exit appears after all waves

func uses_default_enemy_spawning() -> bool:
	return false  # We spawn crawlers ourselves

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "InversionHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	_wave_label = Label.new()
	_wave_label.name = "WaveLabel"
	_wave_label.text = "INVERSION — Wave 0 / %d" % TOTAL_WAVES
	_wave_label.add_theme_font_size_override("font_size", 22)
	_wave_label.add_theme_color_override("font_color", accent_color)
	_wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wave_label.position = Vector2(-120, 8)
	_hud_overlay.add_child(_wave_label)

	_core_label = Label.new()
	_core_label.name = "CoreLabel"
	_core_label.text = "Core HP: %d/%d" % [_core_hp, _core_max_hp]
	_core_label.add_theme_font_size_override("font_size", 16)
	_core_label.add_theme_color_override("font_color", Color(0.8, 0.5, 1.0))
	_core_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_core_label.position = Vector2(-100, 34)
	_hud_overlay.add_child(_core_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.text = "Place defenses before the crawlers arrive!"
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.5))
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.position = Vector2(-160, 56)
	_hud_overlay.add_child(_status_label)

	_placement_label = Label.new()
	_placement_label.name = "PlacementLabel"
	_placement_label.text = "[1] Trap (%d left)  [2] Minion (%d left)" % [TRAP_SLOTS - _traps_placed, MINION_SLOTS - _minions_placed]
	_placement_label.add_theme_font_size_override("font_size", 12)
	_placement_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_placement_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placement_label.position = Vector2(-160, 76)
	_hud_overlay.add_child(_placement_label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
