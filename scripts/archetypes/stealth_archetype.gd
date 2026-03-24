extends FloorArchetype

## StealthArchetype — overwhelming enemy force patrols the floor.
## Enemies have vision cones. Getting spotted triggers alarm → swarm.
## Sneak past, use distractions, find the exit. Backstabs = one-shot kills.
## Win: reach exit without being overwhelmed. Lose: swarmed to death.

class_name StealthArchetype

const PATROL_ENEMY_COUNT := 12
const ALARM_SWARM_COUNT := 8
const VISION_CONE_ANGLE := 45.0  # degrees half-angle
const VISION_CONE_RANGE := 12.0
const BACKSTAB_ANGLE := 60.0  # degrees from enemy's back
const DISTRACTION_COOLDOWN := 8.0
const DISTRACTION_RANGE := 6.0
const DISTRACTION_DURATION := 4.0

var _patrol_enemies: Array[Node3D] = []
var _vision_cones: Array[MeshInstance3D] = []
var _alarm_active: bool = false
var _alarm_timer: float = 0.0
var _alarm_duration: float = 15.0
var _distraction_timer: float = 0.0
var _distraction_ready: bool = true
var _distractions: Array[Node3D] = []
var _hud_overlay: Control = null
var _hero_hidden: bool = false
var _spotted_timer: float = 0.0
var _exit_portal: Node3D = null

func _init() -> void:
	archetype_name = "Stealth"
	flavor_text = "They cannot know you are here."
	accent_color = Color(0.2, 0.8, 0.4)

func setup(p_builder: Node3D, p_units_node: Node3D, p_floor_number: int) -> void:
	super.setup(p_builder, p_units_node, p_floor_number)

func start() -> void:
	super.start()
	show_message("STEALTH — REACH THE EXIT UNSEEN", accent_color, 4.0)
	_spawn_patrol_enemies()
	_distraction_ready = true
	_distraction_timer = 0.0

func _spawn_patrol_enemies() -> void:
	if not builder:
		return

	var spawn_pos := Vector3.ZERO
	if builder.has_method("get_spawn_position"):
		spawn_pos = builder.get_spawn_position()

	# Spread patrol enemies across the floor in a grid-ish pattern
	for i in range(PATROL_ENEMY_COUNT):
		var patrol = CharacterBody3D.new()
		patrol.name = "StealthPatrol_%d" % i

		# Collision
		var col = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.5
		capsule.height = 2.0
		col.shape = capsule
		patrol.add_child(col)

		# Visual: armored sentinel model (dark)
		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.5
		capsule_mesh.height = 2.0
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.15, 0.12, 0.2)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.1, 0.1)
		mat.emission_energy_multiplier = 0.5
		mesh.material_override = mat
		mesh.name = "SentinelMesh"
		patrol.add_child(mesh)

		# Vision cone visual (transparent cone mesh)
		var cone_mesh_inst = MeshInstance3D.new()
		cone_mesh_inst.name = "VisionCone"
		var cone = CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = tan(deg_to_rad(VISION_CONE_ANGLE)) * VISION_CONE_RANGE
		cone.height = VISION_CONE_RANGE
		cone_mesh_inst.mesh = cone
		var cone_mat = StandardMaterial3D.new()
		cone_mat.albedo_color = Color(1.0, 0.3, 0.0, 0.08)
		cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cone_mat.no_depth_test = true
		cone_mesh_inst.material_override = cone_mat
		# Rotate cone to point forward (along -Z)
		cone_mesh_inst.rotation_degrees.x = 90.0
		cone_mesh_inst.position = Vector3(0, 0.5, -VISION_CONE_RANGE * 0.5)
		patrol.add_child(cone_mesh_inst)
		_vision_cones.append(cone_mesh_inst)

		# Detection area (for spotting hero)
		var detect_area = Area3D.new()
		detect_area.name = "DetectArea"
		var detect_shape = CollisionShape3D.new()
		var detect_box = BoxShape3D.new()
		detect_box.size = Vector3(VISION_CONE_RANGE * 0.8, 3.0, VISION_CONE_RANGE)
		detect_shape.shape = detect_box
		detect_area.add_child(detect_shape)
		detect_area.position = Vector3(0, 1.0, -VISION_CONE_RANGE * 0.5)
		patrol.add_child(detect_area)

		# Patrol waypoints stored as metadata
		var angle_offset = (TAU / PATROL_ENEMY_COUNT) * i
		var radius = 8.0 + randf_range(0.0, 12.0)
		var base_pos = spawn_pos + Vector3(
			cos(angle_offset) * radius,
			0,
			sin(angle_offset) * radius + 15.0
		)
		patrol.position = base_pos
		patrol.position.y = 0.0

		# Patrol metadata
		var wp1 = base_pos + Vector3(randf_range(-6, 6), 0, randf_range(-4, 4))
		var wp2 = base_pos + Vector3(randf_range(-6, 6), 0, randf_range(-4, 4))
		patrol.set_meta("waypoints", [base_pos, wp1, wp2])
		patrol.set_meta("waypoint_idx", 0)
		patrol.set_meta("patrol_speed", randf_range(1.5, 3.0))
		patrol.set_meta("wait_timer", 0.0)
		patrol.set_meta("wait_duration", randf_range(1.0, 3.0))
		patrol.set_meta("is_waiting", false)
		patrol.set_meta("is_alerted", false)
		patrol.set_meta("health", 80 + floor_number * 20)

		builder.add_child(patrol)
		_patrol_enemies.append(patrol)

func update(delta: float) -> void:
	if not _is_active:
		return

	# Update distraction cooldown
	if not _distraction_ready:
		_distraction_timer += delta
		if _distraction_timer >= DISTRACTION_COOLDOWN:
			_distraction_ready = true
			_distraction_timer = 0.0
			show_message("Distraction ready [D]", Color(0.5, 1.0, 0.5), 1.5)

	# Update distractions (expire them)
	var expired: Array[Node3D] = []
	for d in _distractions:
		if not is_instance_valid(d):
			expired.append(d)
			continue
		var remaining: float = d.get_meta("lifetime", 0.0) - delta
		d.set_meta("lifetime", remaining)
		if remaining <= 0:
			expired.append(d)
			d.queue_free()
	for d in expired:
		_distractions.erase(d)

	# Update alarm state
	if _alarm_active:
		_alarm_timer += delta
		if _alarm_timer >= _alarm_duration:
			_alarm_active = false
			_alarm_timer = 0.0
			show_message("Guards return to patrol...", Color(0.6, 0.6, 0.3), 2.0)
			_reset_patrol_alert()

	# Process each patrol enemy
	var hero = GameManager.hero
	if not hero or hero.is_dead:
		return

	var any_spotted := false

	for patrol in _patrol_enemies:
		if not is_instance_valid(patrol):
			continue

		var is_alerted: bool = patrol.get_meta("is_alerted", false)

		if _alarm_active or is_alerted:
			# Chase hero
			var dir_to_hero = (hero.global_position - patrol.global_position).normalized()
			dir_to_hero.y = 0
			var speed: float = patrol.get_meta("patrol_speed", 2.0) * 2.5
			patrol.velocity = dir_to_hero * speed
			patrol.move_and_slide()
			_face_toward(patrol, hero.global_position, delta)

			# Melee attack if close
			if patrol.global_position.distance_to(hero.global_position) < 2.5:
				if not patrol.has_meta("attack_cd") or patrol.get_meta("attack_cd") <= 0:
					if hero.has_method("take_damage"):
						hero.take_damage(25 + floor_number * 5)
					patrol.set_meta("attack_cd", 1.2)
				else:
					patrol.set_meta("attack_cd", patrol.get_meta("attack_cd") - delta)
			_set_cone_color(patrol, Color(1.0, 0.0, 0.0, 0.15))
		else:
			# Patrol between waypoints
			_update_patrol_movement(patrol, delta)

			# Check if hero is in vision cone
			if _is_hero_in_vision(patrol, hero):
				# Check for distraction — if a distraction is closer, investigate that instead
				var distracted := false
				for d in _distractions:
					if is_instance_valid(d):
						var dist_to_d = patrol.global_position.distance_to(d.global_position)
						if dist_to_d < DISTRACTION_RANGE * 1.5:
							_face_toward(patrol, d.global_position, delta)
							distracted = true
							break

				if not distracted:
					any_spotted = true
					_spotted_timer += delta
					if _spotted_timer > 0.6:
						_trigger_alarm(patrol)
						_spotted_timer = 0.0
					_set_cone_color(patrol, Color(1.0, 1.0, 0.0, 0.12))
			else:
				_set_cone_color(patrol, Color(1.0, 0.3, 0.0, 0.08))

	if not any_spotted:
		_spotted_timer = maxf(_spotted_timer - delta * 2.0, 0.0)

	# Update HUD
	_update_stealth_hud()

	# Check for backstab input
	if Input.is_action_just_pressed("attack"):
		_try_backstab(hero)

	# Check for distraction input (D key)
	if Input.is_key_pressed(KEY_D) and _distraction_ready:
		_throw_distraction(hero)

func _update_patrol_movement(patrol: CharacterBody3D, delta: float) -> void:
	var is_waiting: bool = patrol.get_meta("is_waiting", false)

	if is_waiting:
		var wait = patrol.get_meta("wait_timer", 0.0) + delta
		patrol.set_meta("wait_timer", wait)
		patrol.velocity = Vector3.ZERO
		patrol.move_and_slide()
		if wait >= patrol.get_meta("wait_duration", 2.0):
			patrol.set_meta("is_waiting", false)
			patrol.set_meta("wait_timer", 0.0)
			var idx: int = (patrol.get_meta("waypoint_idx", 0) + 1) % patrol.get_meta("waypoints").size()
			patrol.set_meta("waypoint_idx", idx)
		return

	var waypoints: Array = patrol.get_meta("waypoints", [])
	if waypoints.is_empty():
		return
	var idx: int = patrol.get_meta("waypoint_idx", 0)
	var target: Vector3 = waypoints[idx]
	target.y = 0

	var dist = patrol.global_position.distance_to(target)
	if dist < 1.0:
		patrol.set_meta("is_waiting", true)
		patrol.set_meta("wait_timer", 0.0)
		patrol.velocity = Vector3.ZERO
		patrol.move_and_slide()
		return

	var dir = (target - patrol.global_position).normalized()
	dir.y = 0
	var speed: float = patrol.get_meta("patrol_speed", 2.0)
	patrol.velocity = dir * speed
	patrol.move_and_slide()
	_face_toward(patrol, target, delta)

func _is_hero_in_vision(patrol: CharacterBody3D, hero: Node3D) -> bool:
	var to_hero = hero.global_position - patrol.global_position
	to_hero.y = 0
	var dist = to_hero.length()
	if dist > VISION_CONE_RANGE or dist < 0.5:
		return false

	var forward = -patrol.global_transform.basis.z.normalized()
	forward.y = 0
	forward = forward.normalized()
	var dir = to_hero.normalized()

	var angle = rad_to_deg(acos(clampf(forward.dot(dir), -1.0, 1.0)))
	return angle < VISION_CONE_ANGLE

func _trigger_alarm(spotter: CharacterBody3D) -> void:
	if _alarm_active:
		return

	_alarm_active = true
	_alarm_timer = 0.0

	show_message("ALARM! YOU'VE BEEN SPOTTED!", Color(1.0, 0.0, 0.0), 3.0)
	GameManager.request_screen_shake(6.0, 0.3)

	if AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("alert")

	# Alert all patrol enemies
	for patrol in _patrol_enemies:
		if is_instance_valid(patrol):
			patrol.set_meta("is_alerted", true)

	# Spawn alarm reinforcements
	_spawn_alarm_reinforcements()

func _spawn_alarm_reinforcements() -> void:
	if not builder:
		return
	var hero = GameManager.hero
	if not hero:
		return

	for i in range(ALARM_SWARM_COUNT):
		var angle = (TAU / ALARM_SWARM_COUNT) * i
		var spawn_pos = hero.global_position + Vector3(cos(angle) * 15.0, 0, sin(angle) * 15.0)

		var reinforcement = CharacterBody3D.new()
		reinforcement.name = "AlarmSwarm_%d" % i

		var col = CollisionShape3D.new()
		var capsule = CapsuleShape3D.new()
		capsule.radius = 0.4
		capsule.height = 1.8
		col.shape = capsule
		reinforcement.add_child(col)

		var mesh = MeshInstance3D.new()
		var capsule_mesh = CapsuleMesh.new()
		capsule_mesh.radius = 0.4
		capsule_mesh.height = 1.8
		mesh.mesh = capsule_mesh
		var mat = StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.05, 0.05)
		mat.emission_enabled = true
		mat.emission = Color(0.8, 0.1, 0.0)
		mat.emission_energy_multiplier = 1.5
		mesh.material_override = mat
		reinforcement.add_child(mesh)

		reinforcement.position = spawn_pos
		reinforcement.position.y = 0.0
		reinforcement.set_meta("is_alerted", true)
		reinforcement.set_meta("patrol_speed", 4.0)
		reinforcement.set_meta("health", 60)
		reinforcement.set_meta("attack_cd", 0.0)
		builder.add_child(reinforcement)
		_patrol_enemies.append(reinforcement)

func _reset_patrol_alert() -> void:
	for patrol in _patrol_enemies:
		if is_instance_valid(patrol):
			patrol.set_meta("is_alerted", false)

func _try_backstab(hero: Node3D) -> void:
	var best_target: CharacterBody3D = null
	var best_dist := 3.5  # backstab range

	for patrol in _patrol_enemies:
		if not is_instance_valid(patrol):
			continue
		var dist = hero.global_position.distance_to(patrol.global_position)
		if dist > best_dist:
			continue

		# Check if hero is behind the enemy
		var enemy_forward = -patrol.global_transform.basis.z.normalized()
		enemy_forward.y = 0
		enemy_forward = enemy_forward.normalized()
		var to_hero = (hero.global_position - patrol.global_position).normalized()
		to_hero.y = 0

		var angle = rad_to_deg(acos(clampf(enemy_forward.dot(to_hero), -1.0, 1.0)))
		# Hero is behind if the angle between enemy forward and direction-to-hero is > 120°
		if angle > (180.0 - BACKSTAB_ANGLE):
			best_target = patrol
			best_dist = dist

	if best_target:
		# One-shot kill!
		show_message("BACKSTAB!", Color(1.0, 0.8, 0.0), 2.0)
		GameManager.request_screen_shake(4.0, 0.15)
		GameManager.request_damage_number(best_target.global_position + Vector3.UP * 2.0, 9999, true)

		# Kill the patrol enemy
		_kill_patrol(best_target)

		# Award XP
		if hero.has_method("add_xp"):
			hero.add_xp(50)

func _kill_patrol(patrol: CharacterBody3D) -> void:
	if not is_instance_valid(patrol):
		return

	# Remove vision cone
	var cone = patrol.get_node_or_null("VisionCone")
	if cone and cone in _vision_cones:
		_vision_cones.erase(cone)

	# Death animation
	var tween = patrol.create_tween()
	tween.tween_property(patrol, "scale", Vector3(1.3, 0.1, 1.3), 0.2)
	tween.tween_callback(func():
		if is_instance_valid(patrol):
			_patrol_enemies.erase(patrol)
			patrol.queue_free()
	)

func _throw_distraction(hero: Node3D) -> void:
	if not _distraction_ready or not builder:
		return

	_distraction_ready = false
	_distraction_timer = 0.0

	# Throw a rock in the direction hero is facing
	var throw_dir = -hero.global_transform.basis.z.normalized()
	throw_dir.y = 0
	var throw_pos = hero.global_position + throw_dir * 8.0

	var rock = Node3D.new()
	rock.name = "Distraction"

	var mesh = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = 0.3
	mesh.mesh = sphere
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.4)
	mesh.material_override = mat
	rock.add_child(mesh)

	# Pulse light to attract guards
	var light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.3)
	light.light_energy = 3.0
	light.omni_range = DISTRACTION_RANGE
	rock.add_child(light)

	rock.position = throw_pos
	rock.position.y = 0.5
	rock.set_meta("lifetime", DISTRACTION_DURATION)
	builder.add_child(rock)
	_distractions.append(rock)

	show_message("Rock thrown! Guards investigating...", Color(0.7, 0.7, 0.3), 2.0)

	# Attract nearby patrols to the distraction
	for patrol in _patrol_enemies:
		if not is_instance_valid(patrol):
			continue
		if patrol.get_meta("is_alerted", false):
			continue
		var dist = patrol.global_position.distance_to(throw_pos)
		if dist < DISTRACTION_RANGE * 2.0:
			# Override current waypoint to investigate
			var waypoints: Array = patrol.get_meta("waypoints", [])
			if waypoints.size() > 0:
				waypoints[patrol.get_meta("waypoint_idx", 0)] = throw_pos
				patrol.set_meta("waypoints", waypoints)
				patrol.set_meta("is_waiting", false)

func _set_cone_color(patrol: CharacterBody3D, color: Color) -> void:
	var cone = patrol.get_node_or_null("VisionCone")
	if cone and cone is MeshInstance3D and cone.material_override:
		cone.material_override.albedo_color = color

func _face_toward(body: Node3D, target: Vector3, delta: float) -> void:
	var look_dir = (target - body.global_position)
	look_dir.y = 0
	if look_dir.length_squared() < 0.01:
		return
	var target_rot = atan2(look_dir.x, look_dir.z)
	body.rotation.y = lerp_angle(body.rotation.y, target_rot, 8.0 * delta)

func _update_stealth_hud() -> void:
	if not _hud_overlay:
		return

	var status_label = _hud_overlay.get_node_or_null("StatusLabel")
	if status_label:
		if _alarm_active:
			var remaining = _alarm_duration - _alarm_timer
			status_label.text = "ALARM! (%.0fs)" % remaining
			status_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.1))
		elif _spotted_timer > 0.2:
			status_label.text = "BEING SPOTTED..."
			status_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.0))
		else:
			status_label.text = "HIDDEN"
			status_label.add_theme_color_override("font_color", accent_color)

	var distraction_label = _hud_overlay.get_node_or_null("DistractionLabel")
	if distraction_label:
		if _distraction_ready:
			distraction_label.text = "[D] Throw Rock"
			distraction_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
		else:
			var cd_left = DISTRACTION_COOLDOWN - _distraction_timer
			distraction_label.text = "[D] Distraction (%.0fs)" % cd_left
			distraction_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))

	var enemies_label = _hud_overlay.get_node_or_null("EnemiesLabel")
	if enemies_label:
		var alive = 0
		for p in _patrol_enemies:
			if is_instance_valid(p):
				alive += 1
		enemies_label.text = "Sentinels: %d" % alive

func stop() -> void:
	super.stop()
	for patrol in _patrol_enemies:
		if is_instance_valid(patrol):
			patrol.queue_free()
	_patrol_enemies.clear()
	_vision_cones.clear()
	for d in _distractions:
		if is_instance_valid(d):
			d.queue_free()
	_distractions.clear()

func has_boss() -> bool:
	return false

func has_smusher() -> bool:
	return true

func exit_visible_at_start() -> bool:
	return true

func uses_default_enemy_spawning() -> bool:
	return false  # We handle our own enemies

func create_hud_overlay() -> Control:
	_hud_overlay = Control.new()
	_hud_overlay.name = "StealthHUD"
	_hud_overlay.set_anchors_preset(Control.PRESET_TOP_CENTER)

	var title = Label.new()
	title.name = "ArchetypeLabel"
	title.text = "STEALTH — REACH THE EXIT"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", accent_color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(-150, 8)
	_hud_overlay.add_child(title)

	var status = Label.new()
	status.name = "StatusLabel"
	status.text = "HIDDEN"
	status.add_theme_font_size_override("font_size", 18)
	status.add_theme_color_override("font_color", accent_color)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.position = Vector2(-80, 34)
	_hud_overlay.add_child(status)

	var distraction = Label.new()
	distraction.name = "DistractionLabel"
	distraction.text = "[D] Throw Rock"
	distraction.add_theme_font_size_override("font_size", 14)
	distraction.add_theme_color_override("font_color", Color(0.8, 0.8, 0.3))
	distraction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	distraction.position = Vector2(-80, 56)
	_hud_overlay.add_child(distraction)

	var enemies = Label.new()
	enemies.name = "EnemiesLabel"
	enemies.text = "Sentinels: %d" % PATROL_ENEMY_COUNT
	enemies.add_theme_font_size_override("font_size", 14)
	enemies.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	enemies.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemies.position = Vector2(-80, 74)
	_hud_overlay.add_child(enemies)

	return _hud_overlay

func destroy_hud_overlay() -> void:
	if _hud_overlay and is_instance_valid(_hud_overlay):
		_hud_overlay.queue_free()
		_hud_overlay = null
