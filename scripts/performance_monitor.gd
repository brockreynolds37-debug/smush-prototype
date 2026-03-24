extends Node

## PerformanceMonitor — FPS overlay, LOD management, particle limiter, frame time stats.
## Toggle FPS counter via -fps chat command.

var _fps_label: Label = null
var _fps_canvas: CanvasLayer = null
var _fps_visible: bool = false

# Frame time tracking
var _frame_times: Array[float] = []
var _frame_time_window: float = 2.0  # seconds of history
var _log_timer: float = 0.0
var _log_interval: float = 30.0  # log average every 30s

# LOD
const LOD_DISTANCE_HIGH := 15.0  # Full detail
const LOD_DISTANCE_MED := 25.0   # Reduced detail
const LOD_DISTANCE_LOW := 40.0   # Minimal (hide particles, simplify)
const LOD_CHECK_INTERVAL := 0.5  # Check every 0.5s, not every frame
var _lod_timer: float = 0.0

# Particle limiter
const MAX_ACTIVE_PARTICLES := 8
var _active_particle_systems: Array[GPUParticles3D] = []

func _ready() -> void:
	_build_fps_overlay()

func _process(delta: float) -> void:
	# Track frame time
	_frame_times.append(delta)
	var cutoff := Time.get_ticks_msec() / 1000.0 - _frame_time_window
	while _frame_times.size() > 0 and _frame_times.size() > 300:
		_frame_times.remove_at(0)

	# Update FPS display
	if _fps_visible and _fps_label:
		var fps := Performance.get_monitor(Performance.TIME_FPS)
		var frame_ms := delta * 1000.0
		var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		var objects := Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		_fps_label.text = "FPS: %d | %.1fms | Draw: %d | Obj: %d" % [
			fps, frame_ms, draw_calls, objects
		]
		# Color by FPS
		if fps >= 55:
			_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
		elif fps >= 30:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
		else:
			_fps_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	# LOD checks + particle cull
	_lod_timer += delta
	if _lod_timer >= LOD_CHECK_INTERVAL:
		_lod_timer = 0.0
		_update_lod()
		_enforce_particle_limit()

	# Periodic frame time logging
	_log_timer += delta
	if _log_timer >= _log_interval:
		_log_timer = 0.0
		_log_frame_stats()

func _build_fps_overlay() -> void:
	_fps_canvas = CanvasLayer.new()
	_fps_canvas.layer = 120
	add_child(_fps_canvas)

	_fps_label = Label.new()
	_fps_label.text = "FPS: --"
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	_fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_fps_label.offset_left = -320
	_fps_label.offset_right = -8
	_fps_label.offset_top = 8
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_canvas.add_child(_fps_label)

	_fps_label.visible = false

func toggle_fps() -> void:
	_fps_visible = not _fps_visible
	if _fps_label:
		_fps_label.visible = _fps_visible

func is_fps_visible() -> bool:
	return _fps_visible

# ── LOD MANAGEMENT ──

func _update_lod() -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var cam_pos := camera.global_position

	# Apply LOD to all enemies
	var enemies := get_tree().get_nodes_in_group("enemies")
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy is Node3D:
			continue
		var dist := cam_pos.distance_to(enemy.global_position)
		_apply_enemy_lod(enemy, dist)

func _apply_enemy_lod(enemy: Node3D, distance: float) -> void:
	if distance > LOD_DISTANCE_LOW:
		# Beyond 40m — hide entirely (shouldn't be visible anyway)
		enemy.visible = false
	elif distance > LOD_DISTANCE_MED:
		# 25-40m — show but disable particles and shadow casting
		enemy.visible = true
		_set_shadow_casting(enemy, false)
		_set_particles_active(enemy, false)
	elif distance > LOD_DISTANCE_HIGH:
		# 15-25m — show with shadows but no particles
		enemy.visible = true
		_set_shadow_casting(enemy, true)
		_set_particles_active(enemy, false)
	else:
		# < 15m — full detail
		enemy.visible = true
		_set_shadow_casting(enemy, true)
		_set_particles_active(enemy, true)

func _set_shadow_casting(node: Node3D, enabled: bool) -> void:
	for child in node.get_children():
		if child is MeshInstance3D:
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if enabled else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if child is Node3D:
			_set_shadow_casting(child, enabled)

func _set_particles_active(node: Node3D, enabled: bool) -> void:
	for child in node.get_children():
		if child is GPUParticles3D:
			child.emitting = enabled
		if child is Node3D:
			_set_particles_active(child, enabled)

# ── PARTICLE LIMITER ──

func register_particle_system(particles: GPUParticles3D) -> bool:
	# Clean up dead references
	_active_particle_systems = _active_particle_systems.filter(
		func(p): return is_instance_valid(p) and p.emitting
	)
	if _active_particle_systems.size() >= MAX_ACTIVE_PARTICLES:
		# Kill the oldest particle system
		if _active_particle_systems.size() > 0:
			var oldest: GPUParticles3D = _active_particle_systems[0]
			if is_instance_valid(oldest):
				oldest.emitting = false
			_active_particle_systems.remove_at(0)
	_active_particle_systems.append(particles)
	return true

func _enforce_particle_limit() -> void:
	## Auto-scan the scene tree for emitting GPUParticles3D and enforce the cap.
	## Called during LOD checks so no manual registration is required.
	var all_particles := get_tree().get_nodes_in_group("particles")
	if all_particles.is_empty():
		return  # Nothing registered; skip scan
	var emitting: Array[GPUParticles3D] = []
	for node in all_particles:
		if node is GPUParticles3D and is_instance_valid(node) and node.emitting:
			emitting.append(node)
	# Sort by distance from camera — keep closest, cull farthest
	var camera := get_viewport().get_camera_3d()
	if camera and emitting.size() > MAX_ACTIVE_PARTICLES:
		emitting.sort_custom(func(a, b):
			return camera.global_position.distance_to(a.global_position) < \
			       camera.global_position.distance_to(b.global_position)
		)
		for i in range(MAX_ACTIVE_PARTICLES, emitting.size()):
			emitting[i].emitting = false

func get_active_particle_count() -> int:
	_active_particle_systems = _active_particle_systems.filter(
		func(p): return is_instance_valid(p) and p.emitting
	)
	return _active_particle_systems.size()

# ── FRAME TIME STATS ──

func get_avg_frame_time() -> float:
	if _frame_times.is_empty():
		return 0.0
	var total := 0.0
	for t in _frame_times:
		total += t
	return total / _frame_times.size()

func get_avg_fps() -> float:
	var avg := get_avg_frame_time()
	return 1.0 / avg if avg > 0.0 else 0.0

func get_frame_stats_summary() -> String:
	var avg_ms := get_avg_frame_time() * 1000.0
	var avg_fps := get_avg_fps()
	var min_fps := 999.0
	var max_fps := 0.0
	for t in _frame_times:
		var f: float = 1.0 / t if t > 0 else 0.0
		min_fps = min(min_fps, f)
		max_fps = max(max_fps, f)
	if _frame_times.is_empty():
		min_fps = 0.0
	return "Avg: %.1f FPS (%.1fms) | Min: %.0f | Max: %.0f | Particles: %d/%d" % [
		avg_fps, avg_ms, min_fps, max_fps,
		get_active_particle_count(), MAX_ACTIVE_PARTICLES
	]

func _log_frame_stats() -> void:
	# Silently log — useful for profiling
	var summary := get_frame_stats_summary()
	print("[PerfMon] ", summary)
