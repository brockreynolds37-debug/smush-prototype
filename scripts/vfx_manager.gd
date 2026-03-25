extends Node

## VFX Manager — centralized visual effects for spell impacts, level-ups,
## healing glow, and Smusher terror. Creates GPUParticles3D and shader
## effects programmatically to add visual weight to gameplay.

func _ready() -> void:
	XpManager.level_up.connect(_on_level_up)
	SmusherTimer.warning_phase_entered.connect(_on_smusher_warning)
	SmusherTimer.critical_phase_entered.connect(_on_smusher_critical)
	SmusherTimer.overtime_started.connect(_on_smusher_overtime)

# ---------- SPELL IMPACT SPARKS ----------

func spawn_impact_sparks(pos: Vector3, color: Color = Color(1.0, 0.8, 0.3), count: int = 12) -> void:
	# Fast-moving sparks radiating outward from impact point
	for i in range(count):
		var spark := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.08, 0.08, 0.2)
		spark.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = 3.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		spark.set_surface_override_material(0, mat)

		spark.global_position = pos
		get_tree().root.add_child(spark)
		PerformanceMonitor.register_temp_vfx(spark)

		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.3, 1.5), randf_range(-1.0, 1.0)).normalized()
		var target := pos + dir * randf_range(1.5, 3.0)

		var tween := spark.create_tween()
		tween.tween_property(spark, "global_position", target, randf_range(0.2, 0.4)).set_ease(Tween.EASE_OUT)
		tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.35)
		tween.parallel().tween_property(spark, "scale", Vector3(0.1, 0.1, 0.1), 0.35)
		tween.tween_callback(spark.queue_free)

func spawn_spell_impact(pos: Vector3, spell_color: Color, radius: float = 2.0) -> void:
	# Ring expanding outward + sparks + screen flash
	spawn_impact_sparks(pos, spell_color, 16)

	# Expanding ring on the ground
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.1
	torus.outer_radius = 0.3
	ring.mesh = torus
	ring.global_position = pos + Vector3.UP * 0.1
	ring.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(spell_color.r, spell_color.g, spell_color.b, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = spell_color
	mat.emission_energy_multiplier = 2.0
	ring.set_surface_override_material(0, mat)
	get_tree().root.add_child(ring)
	PerformanceMonitor.register_temp_vfx(ring)

	var tween := ring.create_tween()
	tween.tween_property(ring, "scale", Vector3(radius, radius, radius), 0.3).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_callback(ring.queue_free)

	# Screen flash
	ScreenEffects.screen_flash(spell_color, 0.1)

# ---------- HEALING WARMTH GLOW ----------

func spawn_heal_glow(target: Node3D) -> void:
	if not is_instance_valid(target):
		return

	# Warm upward-drifting particles around the hero
	for i in range(8):
		var particle := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.1
		mesh.height = 0.2
		particle.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.2, 1.0, 0.4, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.2, 1.0, 0.4)
		mat.emission_energy_multiplier = 2.0
		particle.set_surface_override_material(0, mat)

		var offset := Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
		particle.global_position = target.global_position + offset
		get_tree().root.add_child(particle)
		PerformanceMonitor.register_temp_vfx(particle)

		var rise := particle.global_position + Vector3(0, randf_range(2.0, 3.5), 0)
		var tween := particle.create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "global_position", rise, randf_range(0.8, 1.5)).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "albedo_color:a", 0.0, 1.2)
		tween.tween_property(particle, "scale", Vector3(0.01, 0.01, 0.01), 1.3)
		tween.chain().tween_callback(particle.queue_free)

	# Warm glow light
	var glow := OmniLight3D.new()
	glow.light_color = Color(0.3, 1.0, 0.5)
	glow.light_energy = 2.0
	glow.omni_range = 4.0
	glow.omni_attenuation = 2.0
	glow.global_position = target.global_position + Vector3.UP * 1.0
	get_tree().root.add_child(glow)
	PerformanceMonitor.register_temp_vfx(glow)

	var light_tween := glow.create_tween()
	light_tween.tween_property(glow, "light_energy", 0.0, 1.0)
	light_tween.tween_callback(glow.queue_free)

# ---------- LEVEL-UP BURST ----------

func _on_level_up(_new_level: int) -> void:
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return

	# Golden burst expanding outward
	_spawn_level_up_burst(hero)

func _spawn_level_up_burst(target: Node3D) -> void:
	# Ring of golden sparks
	spawn_impact_sparks(target.global_position + Vector3.UP * 1.5, Color(1.0, 0.85, 0.2), 24)

	# Vertical pillar of light
	var pillar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.5
	cyl.bottom_radius = 1.0
	cyl.height = 6.0
	pillar.mesh = cyl
	pillar.global_position = target.global_position + Vector3.UP * 3.0

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.3, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.3)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	pillar.set_surface_override_material(0, mat)
	get_tree().root.add_child(pillar)
	PerformanceMonitor.register_temp_vfx(pillar)

	var tween := pillar.create_tween()
	tween.tween_property(pillar, "scale", Vector3(2.0, 1.5, 2.0), 0.3).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tween.tween_callback(pillar.queue_free)

	# Golden flash
	ScreenEffects.screen_flash(Color(1.0, 0.9, 0.3), 0.15)
	GameManager.request_screen_shake(3.0, 0.2)

	# Burst light
	var burst_light := OmniLight3D.new()
	burst_light.light_color = Color(1.0, 0.85, 0.3)
	burst_light.light_energy = 5.0
	burst_light.omni_range = 10.0
	burst_light.global_position = target.global_position + Vector3.UP * 2.0
	get_tree().root.add_child(burst_light)
	PerformanceMonitor.register_temp_vfx(burst_light)

	var lt := burst_light.create_tween()
	lt.tween_property(burst_light, "light_energy", 0.0, 0.6)
	lt.tween_callback(burst_light.queue_free)

# ---------- SMUSHER VISUAL TERROR ----------

var _smusher_pulse_active: bool = false

func _on_smusher_warning() -> void:
	_start_smusher_pulse(Color(1.0, 0.6, 0.0, 0.08), 1.5)

func _on_smusher_critical() -> void:
	_start_smusher_pulse(Color(1.0, 0.0, 0.0, 0.12), 0.8)
	_spawn_dust_burst()

func _on_smusher_overtime() -> void:
	_start_smusher_pulse(Color(1.0, 0.0, 0.0, 0.2), 0.4)
	_spawn_dust_burst()
	_spawn_dust_burst()
	ScreenEffects.screen_flash(Color(1.0, 0.0, 0.0), 0.3)

func _start_smusher_pulse(_color: Color, _speed: float) -> void:
	# Disabled — no screen pulsing during gameplay
	pass

func _spawn_dust_burst() -> void:
	# Dust/debris particles at hero's position
	var hero = GameManager.hero
	if hero == null or not is_instance_valid(hero):
		return

	for i in range(8):
		var dust := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.2, 0.2, 0.2)
		dust.mesh = mesh

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.4, 0.35, 0.3, 0.6)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.roughness = 1.0
		dust.set_surface_override_material(0, mat)

		var start: Vector3 = hero.global_position + Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
		get_tree().root.add_child(dust)
		dust.global_position = start
		PerformanceMonitor.register_temp_vfx(dust)

		var target: Vector3 = start + Vector3(randf_range(-1.0, 1.0), randf_range(1.0, 3.0), randf_range(-1.0, 1.0))
		var tween := dust.create_tween()
		tween.tween_property(dust, "global_position", target, randf_range(0.5, 1.0))
		tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.8)
		tween.parallel().tween_property(dust, "rotation_degrees", Vector3(randf_range(-180, 180), randf_range(-180, 180), 0), 0.8)
		tween.tween_callback(dust.queue_free)
