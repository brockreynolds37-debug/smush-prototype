class_name UnitBuilder
extends RefCounted

## Builds RTSUnit scene trees programmatically with placeholder meshes.
## Once real GLB models arrive, swap out ModelRoot contents.

static func create_unit(config: Dictionary) -> RTSUnit:
	var unit := RTSUnit.new()
	unit.name = config.get("name", "Unit")
	unit.unit_name = config.get("name", "Unit")
	unit.team = config.get("team", RTSUnit.Team.PLAYER)
	unit.max_hp = config.get("hp", 100)
	unit.move_speed = config.get("speed", 7.0)
	unit.turn_rate = config.get("turn_rate", 3.0)
	unit.attack_damage = config.get("attack_damage", 12)
	unit.attack_range = config.get("attack_range", 2.0)
	unit.attack_cooldown = config.get("attack_cooldown", 1.5)
	unit.acquisition_range = config.get("acquisition_range", 15.0)
	unit.is_ranged = config.get("is_ranged", false)
	unit.projectile_speed = config.get("projectile_speed", 15.0)
	unit.unit_radius = config.get("radius", 0.5)

	# Collision shape
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.radius = config.get("radius", 0.5)
	capsule.height = config.get("height", 1.8)
	col.shape = capsule
	col.position.y = capsule.height * 0.5
	unit.add_child(col)

	# Model root with placeholder mesh
	var model_root := Node3D.new()
	model_root.name = "ModelRoot"
	unit.add_child(model_root)

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "PlaceholderMesh"
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = config.get("radius", 0.5)
	body_mesh.height = config.get("height", 1.8)
	mesh_inst.mesh = body_mesh
	mesh_inst.position.y = config.get("height", 1.8) * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = config.get("color", Color(0.3, 0.6, 0.2))
	mesh_inst.set_surface_override_material(0, mat)
	model_root.add_child(mesh_inst)

	# AnimationPlayer with basic animations
	var anim_player := AnimationPlayer.new()
	anim_player.name = "AnimationPlayer"
	_create_placeholder_animations(anim_player, config)
	unit.add_child(anim_player)

	# AnimationTree with state machine
	var anim_tree := AnimationTree.new()
	anim_tree.name = "AnimationTree"
	anim_tree.anim_player = anim_player.get_path()
	var state_machine := AnimationNodeStateMachine.new()
	# Add animation nodes
	for anim_name in ["idle", "walk", "attack", "death"]:
		var node := AnimationNodeAnimation.new()
		node.animation = anim_name
		state_machine.add_node(anim_name, node, Vector2(0, 0))
	# Transitions
	_add_transition(state_machine, "idle", "walk")
	_add_transition(state_machine, "walk", "idle")
	_add_transition(state_machine, "idle", "attack")
	_add_transition(state_machine, "walk", "attack")
	_add_transition(state_machine, "attack", "idle")
	# Death from any state
	for from_state in ["idle", "walk", "attack"]:
		_add_transition(state_machine, from_state, "death")
	state_machine.set_graph_offset(Vector2.ZERO)
	anim_tree.tree_root = state_machine
	anim_tree.active = true
	unit.add_child(anim_tree)

	# NavigationAgent3D
	var nav_agent := NavigationAgent3D.new()
	nav_agent.name = "NavigationAgent3D"
	nav_agent.path_desired_distance = 0.5
	nav_agent.target_desired_distance = 0.5
	unit.add_child(nav_agent)

	# Acquisition range area
	var acq_area := Area3D.new()
	acq_area.name = "AcquisitionRange"
	acq_area.collision_layer = 0
	acq_area.collision_mask = 1  # detect bodies on layer 1
	var acq_col := CollisionShape3D.new()
	var acq_sphere := SphereShape3D.new()
	acq_sphere.radius = config.get("acquisition_range", 15.0)
	acq_col.shape = acq_sphere
	acq_area.add_child(acq_col)
	unit.add_child(acq_area)

	# Attack range area
	var atk_area := Area3D.new()
	atk_area.name = "AttackRange"
	atk_area.collision_layer = 0
	atk_area.collision_mask = 1
	var atk_col := CollisionShape3D.new()
	var atk_sphere := SphereShape3D.new()
	atk_sphere.radius = config.get("attack_range", 2.0) + 0.5
	atk_col.shape = atk_sphere
	atk_area.add_child(atk_col)
	unit.add_child(atk_area)

	# Selection ring (flat torus/disc on ground)
	var ring := MeshInstance3D.new()
	ring.name = "SelectionRing"
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = config.get("radius", 0.5) + 0.1
	ring_mesh.outer_radius = config.get("radius", 0.5) + 0.3
	ring_mesh.rings = 16
	ring_mesh.ring_segments = 16
	ring.mesh = ring_mesh
	ring.position.y = 0.05
	ring.rotation_degrees.x = 0  # flat on ground
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.2, 1.0, 0.2, 0.8)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.set_surface_override_material(0, ring_mat)
	ring.visible = false
	unit.add_child(ring)

	# HP bar (billboard)
	_create_hp_bar(unit, config)

	return unit

static func _create_placeholder_animations(player: AnimationPlayer, config: Dictionary) -> void:
	var lib := AnimationLibrary.new()

	# Idle: subtle bob
	var idle := Animation.new()
	idle.length = 1.0
	idle.loop_mode = Animation.LOOP_LINEAR
	var idle_track := idle.add_track(Animation.TYPE_POSITION_3D)
	idle.track_set_path(idle_track, "ModelRoot:position")
	idle.track_insert_key(idle_track, 0.0, Vector3(0, 0, 0))
	idle.track_insert_key(idle_track, 0.5, Vector3(0, 0.05, 0))
	idle.track_insert_key(idle_track, 1.0, Vector3(0, 0, 0))
	lib.add_animation("idle", idle)

	# Walk: bob + lean
	var walk := Animation.new()
	walk.length = 0.6
	walk.loop_mode = Animation.LOOP_LINEAR
	var walk_track := walk.add_track(Animation.TYPE_POSITION_3D)
	walk.track_set_path(walk_track, "ModelRoot:position")
	walk.track_insert_key(walk_track, 0.0, Vector3(0, 0, 0))
	walk.track_insert_key(walk_track, 0.15, Vector3(0, 0.08, 0))
	walk.track_insert_key(walk_track, 0.3, Vector3(0, 0, 0))
	walk.track_insert_key(walk_track, 0.45, Vector3(0, 0.08, 0))
	walk.track_insert_key(walk_track, 0.6, Vector3(0, 0, 0))
	lib.add_animation("walk", walk)

	# Attack: lunge forward
	var attack := Animation.new()
	attack.length = config.get("attack_cooldown", 1.5) * 0.6
	attack.loop_mode = Animation.LOOP_NONE
	var atk_track := attack.add_track(Animation.TYPE_POSITION_3D)
	attack.track_set_path(atk_track, "ModelRoot:position")
	attack.track_insert_key(atk_track, 0.0, Vector3(0, 0, 0))
	attack.track_insert_key(atk_track, attack.length * 0.3, Vector3(0, 0.1, -0.3))
	attack.track_insert_key(atk_track, attack.length * 0.5, Vector3(0, 0, -0.5))
	attack.track_insert_key(atk_track, attack.length, Vector3(0, 0, 0))
	lib.add_animation("attack", attack)

	# Death: fall over
	var death := Animation.new()
	death.length = 1.0
	death.loop_mode = Animation.LOOP_NONE
	var death_track := death.add_track(Animation.TYPE_ROTATION_3D)
	death.track_set_path(death_track, "ModelRoot:rotation")
	death.track_insert_key(death_track, 0.0, Quaternion.IDENTITY)
	death.track_insert_key(death_track, 0.6, Quaternion(Vector3.RIGHT, deg_to_rad(-90)))
	death.track_insert_key(death_track, 1.0, Quaternion(Vector3.RIGHT, deg_to_rad(-90)))
	lib.add_animation("death", death)

	player.add_animation_library("", lib)

static func _add_transition(sm: AnimationNodeStateMachine, from: String, to: String) -> void:
	var t := AnimationNodeStateMachineTransition.new()
	t.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
	t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	if to == "death":
		t.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
		t.priority = 10
	sm.add_transition(from, to, t)

static func _create_hp_bar(unit: Node3D, config: Dictionary) -> void:
	var bar_height: float = config.get("height", 1.8) + 0.4

	# BG
	var bg := MeshInstance3D.new()
	bg.name = "HPBarBG"
	var bg_mesh := BoxMesh.new()
	bg_mesh.size = Vector3(1.0, 0.08, 0.02)
	bg.mesh = bg_mesh
	bg.position = Vector3(0, bar_height, 0)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = Color(0.15, 0.05, 0.05)
	bg_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bg_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bg.set_surface_override_material(0, bg_mat)
	unit.add_child(bg)

	# Fill
	var fill := MeshInstance3D.new()
	fill.name = "HPBarFill"
	var fill_mesh := BoxMesh.new()
	fill_mesh.size = Vector3(0.96, 0.06, 0.025)
	fill.mesh = fill_mesh
	fill.position = Vector3(0, bar_height, 0)
	var fill_mat := StandardMaterial3D.new()
	fill_mat.albedo_color = Color(0.1, 0.8, 0.1)
	fill_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fill.set_surface_override_material(0, fill_mat)
	unit.add_child(fill)
