extends FloorArchetype

## RaceArchetype — timed sprint to the exit. Ghost "opponents" (AI ghosts)
## race alongside you. Obstacles, shortcuts, risk/reward paths.
## Fastest time wins bonus loot. Footmen Frenzy energy.

class_name RaceArchetype

const CHECKPOINT_COUNT := 5
const GHOST_COUNT := 3
const OBSTACLE_COUNT := 8

var _race_started: bool = false
var _race_timer: float = 0.0
var _checkpoints_hit: int = 0
var _checkpoints: Array[Node3D] = []
var _ghosts: Array[Node3D] = []
var _obstacles: Array[Node3D] = []
var _finish_portal: Node3D = null
var _race_path: Array[Vector3] = []  # Waypoints for the race track
var _ghost_speeds: Array[float] = []
var _ghost_waypoint_idx: Array[int] = []
var _hud_overlay: Control = null
var _timer_label: Label = null
var _checkpoint_label: Label = null
var _position_label: Label = null
var _best_time: float = 0.0  # Ghost baseline time

func _init() -> void:
	archetype_name = "Race"
	flavor_text = "Sprint to the exit. Beat the ghosts."
	accent_color = Color(0.2, 0.9, 0.6)
	solution_paths = {"combat": true, "speed": true, "social": false, "clever": true}
	audience_favorite_path = "speed"

func _register_solution_paths() -> void:
	SolutionPathTracker.register_floor_paths(
		SolutionPathTracker.paths_race(), "speed"
	)

func start() -> void:
	super.start()
	_race_started = false
	_race_timer = 0.0
	_checkpoints_hit = 0

	_build_race_path()
	_spawn_checkpoints()
	_spawn_obstacles()
	_spawn_ghosts()
	_spawn_finish()

	# Calculate ghost baseline time based on path length
	var total_dist := 0.0
	for i in range(_race_path.size() - 1):
		total_dist += _race_path[i].distance_to(_race_path[i + 1])
	_best_time = total_dist / 7.0  # ~7 units/sec ghost speed baseline

	show_message("RACE — Sprint to the finish!", accent_color, 3.0)
	show_message("Hit checkpoints. Beat the ghosts. Go!", Color(0.7, 0.7, 0.7), 3.0)

	# Race starts after a brief countdown
	_race_started = true
	AudienceManager.grant_vp(15, "Race begins!")

func _build_race_path() -> void:
	# Build a series of waypoints forming the race track
	var start_pos := Vector3.ZERO
	if builder:
		start_pos = builder.get_spawn_position()
		if start_pos == Vector3.ZERO:
			start_pos = Vector3(0, 0, 0)

	_race_path.clear()
	_race_path.append(start_pos)

	# Generate a winding path with some variation
	var current := start_pos
	var direction := Vector3(0, 0, 1)  # Start heading forward

	for i in range(CHECKPOINT_COUNT + 1):
		# Vary the direction (turns)
		var turn_angle := randf_range(-PI / 3, PI / 3)
		direction = direction.rotated(Vector3.UP, turn_angle).normalized()
		var segment_len := randf_range(12.0, 20.0)
		current = current + direction * segment_len
		current.y = 0
		_race_path.append(current)

	# Final stretch to finish
	_race_path.append(current + direction * 15.0)

func _spawn_checkpoints() -> void:
	if not builder:
		return

	for i in range(CHECKPOINT_COUNT):
		var idx = i + 1  # Skip start position
		if idx >= _race_path.size():
			break

		var cp = Node3D.new()
		cp.name = "Checkpoint_%d" % (i + 1)

		# Ring visual
		var mesh = MeshInstance3D.new()
		var torus = TorusMesh.new()
		torus.inner_radius = 1.0
		torus.outer_radius = 1.6
		mesh.mesh = torus
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 0.8, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.9, 0.4)
		mat.emission_energy_multiplier = 1.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.7
		mesh.material_override = mat
		mesh.name = "CPMesh"
		cp.add_child(mesh)

		var label = Label3D.new()
		label.text = "CP %d" % (i + 1)
		label.font_size = 40
		label.position = Vector3(0, 2.5, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color(0.3, 1.0, 0.5)
		label.name = "CPLabel"
		cp.add_child(label)

		cp.set_meta("checkpoint_idx", i)
		cp.set_meta("hit", false)
		cp.position = _race_path[idx]
		builder.add_child(cp)
		_checkpoints.append(cp)

func _spawn_obstacles() -> void:
	if not builder:
		return

	for i in range(OBSTACLE_COUNT):
		var obs = Node3D.new()
		obs.name = "Obstacle_%d" % i

		# Random obstacle type
		var obs_type := randi() % 3

		var mesh = MeshInstance3D.new()
		var mat = StandardMaterial3D.new()

		match obs_type:
			0:  # Boulder
				var sphere_mesh = SphereMesh.new()
				sphere_mesh.radius = 1.0
				sphere_mesh.height = 2.0
				mesh.mesh = sphere_mesh
				mat.albedo_color = Color(0.4, 0.3, 0.2)
				obs.set_meta("type", "boulder")
			1:  # Spike wall
				var box_mesh = BoxMesh.new()
				box_mesh.size = Vector3(3.0, 2.0, 0.5)
				mesh.mesh = box_mesh
				mat.albedo_color = Color(0.5, 0.2, 0.1)
				mat.emission_enabled = true
				mat.emission = Color(0.6, 0.1, 0.0)
				mat.emission_energy_multiplier = 0.5
				obs.set_meta("type", "spike")
				obs.set_meta("damage", 20 + floor_number * 5)
			2:  # Speed boost pad
				var plane_mesh = PlaneMesh.new()
				plane_mesh.size = Vector2(2.0, 2.0)
				mesh.mesh = plane_mesh
				mat.albedo_color = Color(0.2, 0.8, 1.0)
				mat.emission_enabled = true
				mat.emission = Color(0.2, 0.9, 1.0)
				mat.emission_energy_multiplier = 2.0
				obs.set_meta("type", "boost")

		mesh.material_override = mat
		obs.add_child(mesh)

		# Place between waypoints randomly
		var path_idx = randi() % maxi(_race_path.size() - 1, 1)
		var t = randf()
		var pos = _race_path[path_idx].lerp(_race_path[mini(path_idx + 1, _race_path.size() - 1)], t)
		pos += Vector3(randf_range(-4, 4), 0, randf_range(-4, 4))
		pos.y = 0
		obs.position = pos
		builder.add_child(obs)
		_obstacles.append(obs)

func _spawn_ghosts() -> void:
	if not builder:
		return

	_ghost_speeds.clear()
	_ghost_waypoint_idx.clear()

	var ghost_colors := [
		Color(0.5, 0.5, 1.0, 0.4),
		Color(1.0, 0.5, 0.5, 0.4),
		Color(0.5, 1.0, 0.5, 0.4),
	]

	for i in range(GHOST_COUNT):
		var ghost = Node3D.new()
		ghost.name = "Ghost_%d" % i

		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.3
		capsule_mesh.height = 1.6
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = ghost_colors[i % ghost_colors.size()]
		mat.emission_enabled = true
		mat.emission = ghost_colors[i % ghost_colors.size()]
		mat.emission_energy_multiplier = 1.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mesh.material_override = mat
		ghost.add_child(mesh)

		var label = Label3D.new()
		label.text = "Ghost %d" % (i + 1)
		label.font_size = 28
		label.position = Vector3(0, 1.4, 0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = ghost_colors[i % ghost_colors.size()]
		ghost.add_child(label)

		ghost.position = _race_path[0]
		builder.add_child(ghost)
		_ghosts.append(ghost)

		# Each ghost has a different speed — some faster, some slower
		var base_speed := 5.0 + floor_number * 0.3
		_ghost_speeds.append(base_speed + randf_range(-1.5, 2.0))
		_ghost_waypoint_idx.append(0)

func _spawn_finish() -> void:
	if not builder or _race_path.is_empty():
		return

	_finish_portal = Node3D.new()
	_finish_portal.name = "FinishLine"

	var mesh = MeshInstance3D.new()
	var torus = TorusMesh.new()
	torus.inner_radius = 1.5
	torus.outer_radius = 2.2
	mesh.mesh = torus
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.0)
	mat.emission_energy_multiplier = 3.0
	mesh.material_override = mat
	_finish_portal.add_child(mesh)

	var label = Label3D.new()
	label.text = "FINISH"
	label.font_size = 64
	label.position = Vector3(0, 3.0, 0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1.0, 0.9, 0.2)
	label.name = "FinishLabel"
	_finish_portal.add_child(label)

	_finish_portal.position = _race_path[_race_path.size() - 1]
	builder.add_child(_finish_portal)

# ── UPDATE ──

func update(delta: float) -> void:
	if not _is_active or not _race_started:
		return

	_race_timer += delta

	var hero = GameManager.hero
	if not hero or hero.is_dead:
		return

	# Update ghost positions
	_update_ghosts(delta)

	# Check checkpoint hits
	_check_checkpoints(hero)

	# Check obstacle interactions
	_check_obstacles(hero)

	# Check finish line
	if is_instance_valid(_finish_portal):
		var dist = hero.global_position.distance_to(_finish_portal.global_position)
		if dist < 3.0 and _checkpoints_hit >= CHECKPOINT_COUNT:
			_finish_race()

	# Check if any ghost finishes first
	for i in range(_ghosts.size()):
		if _ghost_waypoint_idx[i] >= _race_path.size():
			# Ghost finished — penalty
			if is_instance_valid(_ghosts[i]):
				show_message("Ghost %d finished first!" % (i + 1), Color(1.0, 0.4, 0.3), 2.0)
				_ghosts[i].queue_free()
				_ghost_waypoint_idx[i] = 999  # Mark done

	_update_hud(hero)

func _update_ghosts(delta: float) -> void:
	for i in range(_ghosts.size()):
		if not is_instance_valid(_ghosts[i]):
			continue
		if _ghost_waypoint_idx[i] >= _race_path.size():
			continue

		var target = _race_path[_ghost_waypoint_idx[i]]
		var ghost = _ghosts[i]
		var dir = (target - ghost.global_position).normalized()
		dir.y = 0
		ghost.position += dir * _ghost_speeds[i] * delta

		if ghost.global_position.distance_to(target) < 2.0:
			_ghost_waypoint_idx[i] += 1

func _check_checkpoints(hero: Node3D) -> void:
	for cp in _checkpoints:
		if not is_instance_valid(cp):
			continue
		if cp.get_meta("hit", false):
			continue

		var dist = hero.global_position.distance_to(cp.global_position)
		if dist < 3.0:
			cp.set_meta("hit", true)
			_checkpoints_hit += 1

			# Visual feedback — dim the checkpoint
			var mesh = cp.get_node_or_null("CPMesh")
			if mesh and mesh.material_override:
				mesh.material_override.albedo_color = Color(0.3, 0.3, 0.3, 0.3)
				mesh.material_override.emission = Color(0.2, 0.2, 0.2)
				mesh.material_override.emission_energy_multiplier = 0.3
			var label = cp.get_node_or_null("CPLabel")
			if label:
				label.modulate = Color(0.5, 0.5, 0.5)

			show_message("Checkpoint %d/%d!" % [_checkpoints_hit, CHECKPOINT_COUNT], accent_color, 1.5)
			AudienceManager.grant_vp(10, "Checkpoint hit!")

func _check_obstacles(hero: Node3D) -> void:
	for obs in _obstacles:
		if not is_instance_valid(obs):
			continue
		var dist = hero.global_position.distance_to(obs.global_position)
		if dist > 3.0:
			continue

		var obs_type: String = obs.get_meta("type", "boulder")
		match obs_type:
			"spike":
				if dist < 2.0:
					var dmg: int = obs.get_meta("damage", 20)
					if hero.has_method("take_damage"):
						hero.take_damage(dmg)
					show_message("Hit spikes! -%d HP" % dmg, Color(1.0, 0.2, 0.1), 1.0)
					# Remove obstacle after hitting
					obs.queue_free()
			"boost":
				if dist < 2.0:
					# Speed boost — add velocity in hero's direction
					hero.set_meta("speed_boost_timer", 3.0)
					show_message("SPEED BOOST!", Color(0.2, 0.9, 1.0), 1.5)
					AudienceManager.grant_vp(5, "Speed boost!")
					obs.queue_free()

func _finish_race() -> void:
	_race_started = false

	# Determine placement vs ghosts
	var ghosts_finished := 0
	for i in range(_ghost_waypoint_idx.size()):
		if _ghost_waypoint_idx[i] >= _race_path.size():
			ghosts_finished += 1

	var place := ghosts_finished + 1  # 1st if no ghosts finished

	show_message("RACE COMPLETE! Time: %.1fs — Place: #%d" % [_race_timer, place], Color(0.2, 1.0, 0.4), 4.0)

	# VP based on placement
	var vp_reward := 30
	if place == 1:
		vp_reward = 80
		show_message("FIRST PLACE! Bonus loot!", accent_color, 3.0)
		# Grant bonus loot
		LootManager.gold += 50 + floor_number * 10
		LootManager.gold_changed.emit(LootManager.gold)
	elif place == 2:
		vp_reward = 50
	elif place == 3:
		vp_reward = 35

	AudienceManager.grant_vp(vp_reward, "Race finished #%d!" % place)

	# Heal based on placement
	if GameManager.hero and GameManager.hero.has_method("heal"):
		GameManager.hero.heal(int(GameManager.hero.max_health * (0.3 / place)))

	complete()

func _update_hud(hero: Node3D) -> void:
	if not _hud_overlay:
		return

	if _timer_label:
		_timer_label.text = "Time: %.1fs" % _race_timer

	if _checkpoint_label:
		_checkpoint_label.text = "Checkpoints: %d / %d" % [_checkpoints_hit, CHECKPOINT_COUNT]
		if _checkpoints_hit >= CHECKPOINT_COUNT:
			_checkpoint_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
		else:
			_checkpoint_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))

	if _position_label:
		# Calculate position based on hero progress vs ghosts
		var hero_progress := 0.0
		if not _race_path.is_empty():
			var min_dist := 9999.0
			for i in range(_race_path.size()):
				var d = hero.global_position.distance_to(_race_path[i])
				if d < min_dist:
					min_dist = d
					hero_progress = float(i) / float(_race_path.size())

		var ghosts_ahead := 0
		for i in range(_ghost_waypoint_idx.size()):
			var ghost_progress := float(_ghost_waypoint_idx[i]) / float(_race_path.size())
			if ghost_progress > hero_progress:
				ghosts_ahead += 1

		_position_label.text = "Position: #%d / %d" % [ghosts_ahead + 1, GHOST_COUNT + 1]

# ── OVERRIDES ──

func stop() -> void:
	super.stop()
	for cp in _checkpoints:
		if is_instance_valid(cp):
			cp.queue_free()
	_checkpoints.clear()
	for ghost in _ghosts:
		if is_instance_valid(ghost):
			ghost.queue_free()
	_ghosts.clear()
	for obs in _obstacles:
		if is_instance_valid(obs):
			obs.queue_free()
	_obstacles.clear()
	if is_instance_valid(_finish_portal):
		_finish_portal.queue_free()
	_finish_portal = null

func has_boss() -> bool:
	return false

func has_merchant() -> bool:
	return true

func has_smusher() -> bool:
	return false  # Race timer is the pressure

func exit_visible_at_start() -> bool:
	return false  # Finish portal is the exit

func uses_default_enemy_spawning() -> bool:
	return false  # No enemies — obstacles and ghosts only

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "RaceHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	var title = Label.new()
	title.name = "TitleLabel"
	title.text = "RACE"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-60, 8)
	_hud_overlay.add_child(title)

	_timer_label = Label.new()
	_timer_label.name = "TimerLabel"
	_timer_label.text = "Time: 0.0s"
	_timer_label.add_theme_font_size_override("font_size", 18)
	_timer_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_timer_label.position = Vector2(-80, 32)
	_hud_overlay.add_child(_timer_label)

	_checkpoint_label = Label.new()
	_checkpoint_label.name = "CheckpointLabel"
	_checkpoint_label.text = "Checkpoints: 0 / %d" % CHECKPOINT_COUNT
	_checkpoint_label.add_theme_font_size_override("font_size", 15)
	_checkpoint_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	_checkpoint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_checkpoint_label.position = Vector2(-100, 54)
	_hud_overlay.add_child(_checkpoint_label)

	_position_label = Label.new()
	_position_label.name = "PositionLabel"
	_position_label.text = "Position: #1 / %d" % (GHOST_COUNT + 1)
	_position_label.add_theme_font_size_override("font_size", 14)
	_position_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	_position_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_position_label.position = Vector2(-100, 74)
	_hud_overlay.add_child(_position_label)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
