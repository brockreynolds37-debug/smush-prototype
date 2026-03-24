extends StaticBody3D

## EnvInteractable — environmental objects that can be used creatively in combat.
## Oil barrels (ignite for fire AoE), hanging cages (release for distraction/chaos),
## pressure plates (trigger trap for enemies), support pillars (destroy to collapse area).
## Audience gives huge VP bonus for killing enemies with environment instead of spells.

enum EnvType { OIL_BARREL, HANGING_CAGE, PRESSURE_PLATE, SUPPORT_PILLAR }

@export var env_type: EnvType = EnvType.OIL_BARREL

## Shared state
var _hp: int = 30
var _activated: bool = false
var _mesh: MeshInstance3D = null
var _glow: OmniLight3D = null

## Type-specific
const OIL_BARREL_DAMAGE := 80
const OIL_BARREL_RADIUS := 5.0
const PILLAR_DAMAGE := 120
const PILLAR_RADIUS := 4.0
const PRESSURE_PLATE_DAMAGE := 60
const PRESSURE_PLATE_RADIUS := 3.5
const CAGE_DISTRACTION_DURATION := 5.0
const CAGE_AGGRO_RADIUS := 8.0

func _ready() -> void:
	collision_layer = 4  # Interactables layer
	collision_mask = 0
	add_to_group("env_interactables")
	_build_visual()

func _build_visual() -> void:
	_mesh = MeshInstance3D.new()

	var mat := StandardMaterial3D.new()
	mat.emission_enabled = true

	match env_type:
		EnvType.OIL_BARREL:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.5
			cyl.bottom_radius = 0.5
			cyl.height = 1.0
			_mesh.mesh = cyl
			mat.albedo_color = Color(0.3, 0.15, 0.05)
			mat.emission = Color(0.5, 0.2, 0.0)
			mat.emission_energy_multiplier = 0.3
			_mesh.position.y = 0.5
			_hp = 20
		EnvType.HANGING_CAGE:
			var box := BoxMesh.new()
			box.size = Vector3(0.8, 1.2, 0.8)
			_mesh.mesh = box
			mat.albedo_color = Color(0.4, 0.4, 0.4)
			mat.emission = Color(0.2, 0.2, 0.2)
			mat.emission_energy_multiplier = 0.2
			_mesh.position.y = 2.0
			_hp = 15
		EnvType.PRESSURE_PLATE:
			var box := BoxMesh.new()
			box.size = Vector3(1.5, 0.1, 1.5)
			_mesh.mesh = box
			mat.albedo_color = Color(0.5, 0.5, 0.3)
			mat.emission = Color(0.6, 0.5, 0.1)
			mat.emission_energy_multiplier = 0.4
			_mesh.position.y = 0.05
			_hp = 999  # Plates activate on step, not damage
		EnvType.SUPPORT_PILLAR:
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.4
			cyl.bottom_radius = 0.5
			cyl.height = 3.0
			_mesh.mesh = cyl
			mat.albedo_color = Color(0.6, 0.55, 0.45)
			mat.emission = Color(0.3, 0.25, 0.2)
			mat.emission_energy_multiplier = 0.1
			_mesh.position.y = 1.5
			_hp = 50

	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)

	# Glow indicator
	_glow = OmniLight3D.new()
	_glow.light_energy = 0.3
	_glow.omni_range = 2.0
	match env_type:
		EnvType.OIL_BARREL:
			_glow.light_color = Color(1.0, 0.5, 0.1)
		EnvType.HANGING_CAGE:
			_glow.light_color = Color(0.5, 0.5, 0.6)
		EnvType.PRESSURE_PLATE:
			_glow.light_color = Color(0.8, 0.7, 0.2)
		EnvType.SUPPORT_PILLAR:
			_glow.light_color = Color(0.6, 0.5, 0.3)
	_glow.position.y = 1.0
	add_child(_glow)

	# Collision shape
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	match env_type:
		EnvType.OIL_BARREL:
			shape.size = Vector3(1.0, 1.0, 1.0)
			col.position.y = 0.5
		EnvType.HANGING_CAGE:
			shape.size = Vector3(0.8, 1.2, 0.8)
			col.position.y = 2.0
		EnvType.PRESSURE_PLATE:
			shape.size = Vector3(1.5, 0.2, 1.5)
			col.position.y = 0.1
		EnvType.SUPPORT_PILLAR:
			shape.size = Vector3(1.0, 3.0, 1.0)
			col.position.y = 1.5
	col.shape = shape
	add_child(col)

# ── Damage / Activation ──

func take_damage(amount: int, _source: Node3D = null) -> void:
	if _activated:
		return
	_hp -= amount
	# Flash white briefly
	if _mesh and _mesh.get_surface_override_material(0):
		var mat: StandardMaterial3D = _mesh.get_surface_override_material(0)
		var original_color: Color = mat.albedo_color
		mat.albedo_color = Color.WHITE
		var tw := create_tween()
		tw.tween_property(mat, "albedo_color", original_color, 0.2)

	if _hp <= 0:
		activate()

func activate() -> void:
	if _activated:
		return
	_activated = true

	match env_type:
		EnvType.OIL_BARREL:
			_explode_oil()
		EnvType.HANGING_CAGE:
			_release_cage()
		EnvType.PRESSURE_PLATE:
			_trigger_plate()
		EnvType.SUPPORT_PILLAR:
			_collapse_pillar()

func activate_by_step() -> void:
	## Called when hero or enemy walks onto a pressure plate.
	if env_type == EnvType.PRESSURE_PLATE:
		activate()

# ── Type-Specific Effects ──

func _explode_oil() -> void:
	# AoE fire damage to all enemies in radius
	var enemies_hit := _damage_enemies_in_radius(OIL_BARREL_RADIUS, OIL_BARREL_DAMAGE)

	# VFX — expanding orange sphere
	_spawn_explosion_vfx(Color(1.0, 0.4, 0.0), OIL_BARREL_RADIUS)

	# Screen shake
	GameManager.request_screen_shake(0.4, 0.3)
	AudioManager.play_sfx("fireball_explode")

	_grant_env_kill_vp(enemies_hit, "Oil Barrel Explosion")

	# Remove after short delay
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3.ZERO, 0.3)
	tw.tween_callback(queue_free)

func _release_cage() -> void:
	# Drop the cage — creates a distraction point that draws enemy aggro
	var distraction_pos := global_position + Vector3(0, -1.5, 0)

	# Move cage mesh down
	var tw := create_tween()
	tw.tween_property(_mesh, "position:y", 0.3, 0.4).set_ease(Tween.EASE_IN)

	# Draw enemies toward the crash site
	var enemies := GameManager.get_enemies_in_range(distraction_pos, CAGE_AGGRO_RADIUS)
	for e in enemies:
		if e.has_method("set_distraction_target"):
			e.set_distraction_target(distraction_pos, CAGE_DISTRACTION_DURATION)

	AudienceManager.grant_vp(20, "Cage released — chaos!")
	SolutionPathTracker.record_creative_item_use()

	# Clean up after distraction ends
	var timer := get_tree().create_timer(CAGE_DISTRACTION_DURATION + 1.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)

func _trigger_plate() -> void:
	# Spike trap effect — damages enemies standing on the plate
	var enemies_hit := _damage_enemies_in_radius(PRESSURE_PLATE_RADIUS, PRESSURE_PLATE_DAMAGE)

	# Visual: plate sinks + spikes pop up
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "position:y", -0.1, 0.1)
		tw.tween_callback(func() -> void:
			# Spawn spike visual
			var spike := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.05
			cone.bottom_radius = 0.2
			cone.height = 1.0
			spike.mesh = cone
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(0.7, 0.7, 0.7)
			spike.set_surface_override_material(0, mat)
			spike.position.y = 0.5
			add_child(spike)
		)

	AudioManager.play_sfx("spike_trap")
	_grant_env_kill_vp(enemies_hit, "Pressure Plate Trap")

	# Rearm after 8 seconds
	var timer := get_tree().create_timer(8.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			_activated = false
			if _mesh:
				_mesh.position.y = 0.05
	)

func _collapse_pillar() -> void:
	# Heavy AoE — pillar falls in a direction and crushes enemies
	var enemies_hit := _damage_enemies_in_radius(PILLAR_RADIUS, PILLAR_DAMAGE)

	# VFX — pillar tips over
	if _mesh:
		var tw := create_tween()
		tw.tween_property(_mesh, "rotation:x", deg_to_rad(90), 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(func() -> void:
			# Spawn rubble
			for i in range(4):
				var rubble := MeshInstance3D.new()
				var box := BoxMesh.new()
				box.size = Vector3(0.3, 0.3, 0.3)
				rubble.mesh = box
				var mat := StandardMaterial3D.new()
				mat.albedo_color = Color(0.5, 0.45, 0.35)
				rubble.set_surface_override_material(0, mat)
				rubble.position = Vector3(randf_range(-1, 1), 0.15, randf_range(-1, 1))
				add_child(rubble)
		)

	GameManager.request_screen_shake(0.6, 0.4)
	AudioManager.play_sfx("ground_slam")

	_grant_env_kill_vp(enemies_hit, "Pillar Collapse")

# ── Shared Helpers ──

func _damage_enemies_in_radius(radius: float, damage: int) -> int:
	var enemies := GameManager.get_enemies_in_range(global_position, radius)
	var killed := 0
	for e in enemies:
		if e.has_method("take_damage"):
			var was_alive := not e.is_dead if "is_dead" in e else true
			e.take_damage(damage)
			GameManager.request_damage_number(e.global_position, damage, false)
			var is_now_dead := e.is_dead if "is_dead" in e else false
			if was_alive and is_now_dead:
				killed += 1
	return killed

func _grant_env_kill_vp(enemies_killed: int, reason: String) -> void:
	if enemies_killed > 0:
		# Huge VP bonus for environmental kills
		var vp := enemies_killed * 40
		AudienceManager.grant_vp(vp, "%s x%d!" % [reason, enemies_killed])
		for _i in range(enemies_killed):
			SolutionPathTracker.record_environmental_kill()

func _spawn_explosion_vfx(color: Color, radius: float) -> void:
	var sphere := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	sphere.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	sphere.set_surface_override_material(0, mat)
	sphere.global_position = global_position + Vector3(0, 0.5, 0)
	get_tree().root.add_child(sphere)

	var tw := create_tween()
	tw.tween_property(sphere, "scale", Vector3.ONE * radius * 0.5, 0.3)
	tw.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.5)
	tw.tween_callback(sphere.queue_free)
