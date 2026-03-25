extends Area3D

## Trap/Hazard — placed in dungeon rooms by DungeonBuilder.
## Three types:
##   SPIKE_TRAP — timed: retracts/extends on a cycle, deals burst damage when active
##   POISON_POOL — always active, applies poison DOT while hero stands in it
##   FIRE_VENT — periodic burst of flame, heavy damage on hit
##
## Attach to a Node3D in the scene tree. Uses Area3D to detect hero overlap.

enum TrapType { SPIKE_TRAP, POISON_POOL, FIRE_VENT }

@export var trap_type: TrapType = TrapType.SPIKE_TRAP

# Spike trap config
var spike_active_time: float = 1.5
var spike_retracted_time: float = 3.0
var spike_damage: int = 40
var _spike_timer: float = 0.0
var _spike_is_up: bool = false

# Poison pool config
var poison_tick_interval: float = 0.8
var poison_damage_per_tick: int = 6
var _poison_tick_timer: float = 0.0

# Fire vent config
var fire_burst_interval: float = 4.0
var fire_warn_time: float = 0.8  # glow before burst
var fire_burst_damage: int = 65
var fire_burst_duration: float = 0.5
var _fire_timer: float = 0.0
var _fire_is_bursting: bool = false
var _fire_burst_timer: float = 0.0

# Visuals
var _mesh: MeshInstance3D = null
var _light: OmniLight3D = null
var _warning_light: OmniLight3D = null
var _hero_inside: bool = false
var _hero_ref: Node3D = null

# Damage cooldown to prevent per-frame spam
var _damage_cooldown: float = 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2  # Hero layer

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	match trap_type:
		TrapType.SPIKE_TRAP:
			_setup_spike_visuals()
			_spike_timer = randf_range(0.0, spike_retracted_time)  # Stagger traps
		TrapType.POISON_POOL:
			_setup_poison_visuals()
		TrapType.FIRE_VENT:
			_setup_fire_visuals()
			_fire_timer = randf_range(0.0, fire_burst_interval)  # Stagger

func _setup_spike_visuals() -> void:
	# Base plate (dark metal)
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.7
	base_mesh.bottom_radius = 0.8
	base_mesh.height = 0.1
	base.mesh = base_mesh
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color(0.25, 0.22, 0.2)
	base_mat.metallic = 0.6
	base_mat.roughness = 0.4
	base.set_surface_override_material(0, base_mat)
	base.position.y = 0.05
	add_child(base)

	# Spike mesh (hidden when retracted)
	_mesh = MeshInstance3D.new()
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.05
	spike_mesh.bottom_radius = 0.15
	spike_mesh.height = 1.2
	_mesh.mesh = spike_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.45, 0.4)
	mat.metallic = 0.8
	mat.roughness = 0.3
	_mesh.set_surface_override_material(0, mat)
	_mesh.position.y = -0.5  # Start retracted
	_mesh.visible = false
	add_child(_mesh)

	# Warning glow when about to extend
	_warning_light = OmniLight3D.new()
	_warning_light.light_color = Color(1.0, 0.3, 0.1)
	_warning_light.light_energy = 0.0
	_warning_light.omni_range = 2.0
	_warning_light.shadow_enabled = false
	_warning_light.position.y = 0.2
	add_child(_warning_light)

func _setup_poison_visuals() -> void:
	# Flat green pool on the ground
	_mesh = MeshInstance3D.new()
	var pool_mesh := CylinderMesh.new()
	pool_mesh.top_radius = 1.0
	pool_mesh.bottom_radius = 1.0
	pool_mesh.height = 0.05
	_mesh.mesh = pool_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.6, 0.1, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.8, 0.05)
	mat.emission_energy_multiplier = 0.6
	mat.roughness = 0.2
	_mesh.set_surface_override_material(0, mat)
	_mesh.position.y = 0.03
	add_child(_mesh)

	# Subtle green glow
	_light = OmniLight3D.new()
	_light.light_color = Color(0.2, 0.85, 0.15)
	_light.light_energy = 1.2
	_light.omni_range = 2.5
	_light.shadow_enabled = false
	_light.position.y = 0.5
	add_child(_light)

func _setup_fire_visuals() -> void:
	# Vent grate on the floor
	_mesh = MeshInstance3D.new()
	var grate_mesh := BoxMesh.new()
	grate_mesh.size = Vector3(1.0, 0.1, 1.0)
	_mesh.mesh = grate_mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.25, 0.2)
	mat.metallic = 0.7
	mat.roughness = 0.4
	_mesh.set_surface_override_material(0, mat)
	_mesh.position.y = 0.05
	add_child(_mesh)

	# Fire glow (intensifies on burst)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.4, 0.05)
	_light.light_energy = 0.3
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	_light.position.y = 0.5
	add_child(_light)

	# Warning glow
	_warning_light = OmniLight3D.new()
	_warning_light.light_color = Color(1.0, 0.6, 0.0)
	_warning_light.light_energy = 0.0
	_warning_light.omni_range = 2.0
	_warning_light.shadow_enabled = false
	_warning_light.position.y = 0.3
	add_child(_warning_light)

func _physics_process(delta: float) -> void:
	_damage_cooldown = maxf(_damage_cooldown - delta, 0.0)

	match trap_type:
		TrapType.SPIKE_TRAP:
			_process_spike(delta)
		TrapType.POISON_POOL:
			_process_poison(delta)
		TrapType.FIRE_VENT:
			_process_fire(delta)

func _process_spike(delta: float) -> void:
	_spike_timer += delta

	if _spike_is_up:
		# Warning glow fades out while spikes are up
		if _warning_light:
			_warning_light.light_energy = lerpf(_warning_light.light_energy, 0.0, delta * 4.0)

		if _spike_timer >= spike_active_time:
			# Retract spikes
			_spike_is_up = false
			_spike_timer = 0.0
			_retract_spikes()
		elif _hero_inside and _damage_cooldown <= 0.0:
			_deal_damage_to_hero(spike_damage)
			_damage_cooldown = spike_active_time  # Only hit once per extension
	else:
		# Warning glow ramps up in last 0.6s before extension
		var warn_start := spike_retracted_time - 0.6
		if _spike_timer > warn_start and _warning_light:
			var warn_ratio := (_spike_timer - warn_start) / 0.6
			_warning_light.light_energy = warn_ratio * 3.0

		if _spike_timer >= spike_retracted_time:
			# Extend spikes
			_spike_is_up = true
			_spike_timer = 0.0
			_extend_spikes()
			AudioManager.play_sfx("spike_trap")
			if _hero_inside and _damage_cooldown <= 0.0:
				_deal_damage_to_hero(spike_damage)
				_damage_cooldown = spike_active_time

func _extend_spikes() -> void:
	if _mesh:
		_mesh.visible = true
		var tween = create_tween()
		tween.tween_property(_mesh, "position:y", 0.6, 0.08)

func _retract_spikes() -> void:
	if _mesh:
		var tween = create_tween()
		tween.tween_property(_mesh, "position:y", -0.5, 0.15)
		tween.tween_callback(func(): _mesh.visible = false)

func _process_poison(delta: float) -> void:
	# Steady poison glow
	if _light:
		_light.light_energy = 1.2

	if _hero_inside:
		_poison_tick_timer += delta
		if _poison_tick_timer >= poison_tick_interval:
			_poison_tick_timer = 0.0
			# Apply poison status effect rather than raw damage
			var hero = GameManager.hero
			if hero and is_instance_valid(hero) and not hero.is_dead:
				StatusEffectManager.apply_poison(hero, 3.0, poison_damage_per_tick, 1.0)

func _process_fire(delta: float) -> void:
	_fire_timer += delta

	if _fire_is_bursting:
		_fire_burst_timer += delta
		# Steady intense light during burst
		if _light:
			_light.light_energy = 6.0
		if _fire_burst_timer >= fire_burst_duration:
			_fire_is_bursting = false
			_fire_burst_timer = 0.0
			_fire_timer = 0.0
			if _light:
				_light.light_energy = 0.3
			# Remove flame pillar mesh
			_hide_flame_pillar()
	else:
		# Warning phase
		var warn_start := fire_burst_interval - fire_warn_time
		if _fire_timer > warn_start and _warning_light:
			var warn_ratio := (_fire_timer - warn_start) / fire_warn_time
			_warning_light.light_energy = warn_ratio * 4.0
			# Grate starts glowing
			if _mesh:
				var mat = _mesh.get_surface_override_material(0)
				if mat is StandardMaterial3D:
					mat.emission_enabled = true
					mat.emission = Color(1.0, 0.3, 0.0) * warn_ratio
					mat.emission_energy_multiplier = warn_ratio * 2.0
		else:
			if _warning_light:
				_warning_light.light_energy = 0.0

		if _fire_timer >= fire_burst_interval:
			# BURST!
			_fire_is_bursting = true
			_fire_burst_timer = 0.0
			AudioManager.play_sfx("fire_vent")
			_show_flame_pillar()
			if _warning_light:
				_warning_light.light_energy = 0.0
			# Reset grate emission
			if _mesh:
				var mat = _mesh.get_surface_override_material(0)
				if mat is StandardMaterial3D:
					mat.emission_enabled = false
			if _hero_inside and _damage_cooldown <= 0.0:
				_deal_damage_to_hero(fire_burst_damage)
				_damage_cooldown = fire_burst_duration + 0.5

var _flame_pillar: MeshInstance3D = null

func _show_flame_pillar() -> void:
	if _flame_pillar:
		_flame_pillar.visible = true
		return
	_flame_pillar = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.2
	cyl.bottom_radius = 0.5
	cyl.height = 3.0
	_flame_pillar.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.35, 0.0)
	mat.emission_energy_multiplier = 3.0
	mat.no_depth_test = true
	_flame_pillar.set_surface_override_material(0, mat)
	_flame_pillar.position.y = 1.5
	add_child(_flame_pillar)
	# Pop-in animation
	_flame_pillar.scale = Vector3(0.1, 0.1, 0.1)
	var tween = create_tween()
	tween.tween_property(_flame_pillar, "scale", Vector3.ONE, 0.1)

func _hide_flame_pillar() -> void:
	if _flame_pillar:
		var tween = create_tween()
		tween.tween_property(_flame_pillar, "scale", Vector3(0.1, 2.0, 0.1), 0.2)
		tween.tween_callback(func():
			if is_instance_valid(_flame_pillar):
				_flame_pillar.visible = false
				_flame_pillar.scale = Vector3.ONE
		)

func _deal_damage_to_hero(amount: int) -> void:
	var hero = GameManager.hero
	if hero and is_instance_valid(hero) and not hero.is_dead:
		hero.take_damage(amount)
		# Screen shake for trap damage
		GameManager.request_screen_shake(4.0, 0.2)

func _on_body_entered(body: Node3D) -> void:
	if body == GameManager.hero:
		_hero_inside = true
		_hero_ref = body
		_poison_tick_timer = 0.0  # Reset tick on enter

func _on_body_exited(body: Node3D) -> void:
	if body == GameManager.hero:
		_hero_inside = false
		_hero_ref = null
