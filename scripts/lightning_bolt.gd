extends Node3D

## Lightning Bolt — instant strike at target position, chains to nearby enemies.
## Spawned at impact point. Creates visual bolt lines + spark particles.

@export var damage: int = 55
@export var chain_range: float = 5.0
@export var max_chains: int = 3
@export var chain_damage_falloff: float = 0.7

@onready var spark_particles: GPUParticles3D = $SparkParticles
@onready var bolt_light: OmniLight3D = $BoltLight

var chain_targets: Array[Node3D] = []

func strike(origin_pos: Vector3) -> void:
	global_position = origin_pos

	# Find initial target — nearest enemy to strike point
	var primary = GameManager.get_nearest_enemy(global_position, 3.0)
	if primary == null:
		# Still show VFX even if no direct hit
		_play_impact_vfx()
		return

	# Damage primary target
	if primary.has_method("take_damage"):
		primary.take_damage(damage)
	chain_targets.append(primary)

	# Draw bolt line from sky to target
	_draw_bolt_line(global_position + Vector3.UP * 15.0, primary.global_position + Vector3.UP * 1.0)

	# Chain to nearby enemies
	var current_pos = primary.global_position
	var current_damage = damage
	for i in range(max_chains):
		current_damage = int(current_damage * chain_damage_falloff)
		var next_target = _find_chain_target(current_pos)
		if next_target == null:
			break
		if next_target.has_method("take_damage"):
			next_target.take_damage(current_damage)
		_draw_bolt_line(current_pos + Vector3.UP * 1.0, next_target.global_position + Vector3.UP * 1.0)
		# Spawn sparks at chain point
		_spawn_chain_sparks(next_target.global_position)
		chain_targets.append(next_target)
		current_pos = next_target.global_position

	_play_impact_vfx()

	# Screen shake
	GameManager.request_screen_shake(4.0, 0.2)

func _find_chain_target(from_pos: Vector3) -> Node3D:
	var enemies = GameManager.get_enemies_in_range(from_pos, chain_range)
	var best: Node3D = null
	var best_dist: float = chain_range
	for e in enemies:
		if e in chain_targets or e.is_dead:
			continue
		var dist = from_pos.distance_to(e.global_position)
		if dist < best_dist:
			best_dist = dist
			best = e
	return best

func _draw_bolt_line(from: Vector3, to: Vector3) -> void:
	# Create a jagged bolt using a series of small cylinders
	var segments := 6
	var direction = to - from
	var segment_len = direction.length() / segments
	var current = from

	for i in range(segments):
		var next: Vector3
		if i == segments - 1:
			next = to
		else:
			# Add random jitter for jagged look
			var t = float(i + 1) / segments
			var base_pos = from + direction * t
			var jitter = Vector3(
				randf_range(-0.5, 0.5),
				randf_range(-0.3, 0.3),
				randf_range(-0.5, 0.5)
			)
			next = base_pos + jitter

		var seg = _create_bolt_segment(current, next)
		add_child(seg)
		current = next

	# Fade out bolt after brief flash
	var fade_tween = create_tween()
	fade_tween.tween_interval(0.1)
	fade_tween.tween_callback(func():
		for child in get_children():
			if child is MeshInstance3D:
				var mat = child.get_surface_override_material(0) as StandardMaterial3D
				if mat:
					var t = create_tween()
					t.tween_property(mat, "albedo_color:a", 0.0, 0.2)
	)

func _create_bolt_segment(from: Vector3, to: Vector3) -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cyl = CylinderMesh.new()
	var length = from.distance_to(to)
	cyl.height = length
	cyl.top_radius = 0.04
	cyl.bottom_radius = 0.06
	mi.mesh = cyl

	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.6, 1.0, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.4, 1.0, 1)
	mat.emission_energy_multiplier = 5.0
	mat.no_depth_test = true
	mi.set_surface_override_material(0, mat)

	# Position and orient the cylinder between from and to
	var center = (from + to) / 2.0
	mi.global_position = center
	var dir = (to - from).normalized()
	if dir.length() > 0.001:
		# Align Y-axis of cylinder with the direction
		mi.look_at(to, Vector3.RIGHT)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)

	return mi

func _spawn_chain_sparks(pos: Vector3) -> void:
	var sparks = $SparkParticles.duplicate() as GPUParticles3D
	add_child(sparks)
	sparks.global_position = pos
	sparks.emitting = true

func _play_impact_vfx() -> void:
	if spark_particles:
		spark_particles.emitting = true

	# Fade out light
	if bolt_light:
		var tween = create_tween()
		tween.tween_property(bolt_light, "light_energy", 0.0, 0.4)

	# Self destruct
	await get_tree().create_timer(2.0).timeout
	queue_free()
