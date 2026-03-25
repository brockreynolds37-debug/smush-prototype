extends Node3D

## Test scene: spawns units, sets up terrain, nav mesh, lighting.

const GRUNT_CONFIG := {
	"name": "Orc Grunt",
	"hp": 100,
	"speed": 4.5,
	"turn_rate": PI,  # 180 deg/sec
	"attack_damage": 12,
	"attack_range": 2.0,
	"attack_cooldown": 1.5,
	"acquisition_range": 15.0,
	"is_ranged": false,
	"radius": 0.5,
	"height": 1.8,
	"color": Color(0.3, 0.55, 0.15),
}

const PEON_CONFIG := {
	"name": "Orc Peon",
	"hp": 50,
	"speed": 3.25,
	"turn_rate": PI * 1.2,  # ~216 deg/sec (peons are nimbler)
	"attack_damage": 5,
	"attack_range": 2.0,
	"attack_cooldown": 2.0,
	"acquisition_range": 10.0,
	"is_ranged": false,
	"radius": 0.4,
	"height": 1.5,
	"color": Color(0.4, 0.5, 0.2),
}

const SHAMAN_CONFIG := {
	"name": "Orc Shaman",
	"hp": 80,
	"speed": 3.9,
	"turn_rate": PI * 1.1,  # ~198 deg/sec
	"attack_damage": 20,
	"attack_range": 10.0,
	"attack_cooldown": 2.5,
	"acquisition_range": 15.0,
	"is_ranged": true,
	"projectile_speed": 15.0,
	"radius": 0.45,
	"height": 1.7,
	"color": Color(0.2, 0.4, 0.6),
}

func _ready() -> void:
	_create_terrain()
	_create_lighting()
	_create_camera()
	_create_input_controller()
	# Wait a frame for navigation to bake
	await get_tree().physics_frame
	await get_tree().physics_frame
	_spawn_player_units()
	_spawn_enemy_units()

func _create_terrain() -> void:
	# Ground plane
	var ground := StaticBody3D.new()
	ground.name = "Terrain"

	var ground_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.45, 0.2)
	mat.roughness = 0.9
	ground_mesh.set_surface_override_material(0, mat)
	ground.add_child(ground_mesh)

	var ground_col := CollisionShape3D.new()
	var ground_shape := BoxShape3D.new()
	ground_shape.size = Vector3(120, 0.1, 120)
	ground_col.shape = ground_shape
	ground_col.position.y = -0.05
	ground.add_child(ground_col)

	# Navigation region
	var nav_region := NavigationRegion3D.new()
	nav_region.name = "NavigationRegion3D"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.cell_size = 0.5
	nav_mesh.cell_height = 0.2
	nav_mesh.agent_radius = 0.5
	nav_mesh.agent_height = 1.8
	# Create a simple polygon covering the terrain
	var verts := PackedVector3Array([
		Vector3(-55, 0, -55),
		Vector3(55, 0, -55),
		Vector3(55, 0, 55),
		Vector3(-55, 0, 55),
	])
	nav_mesh.add_polygon(PackedInt32Array([0, 1, 2]))
	nav_mesh.add_polygon(PackedInt32Array([0, 2, 3]))
	nav_mesh.set_vertices(verts)
	nav_region.navigation_mesh = nav_mesh
	ground.add_child(nav_region)

	add_child(ground)

func _create_lighting() -> void:
	# Sun
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1.0, 0.95, 0.85)
	sun.shadow_enabled = true
	add_child(sun)

	# Ambient fill
	var env := WorldEnvironment.new()
	env.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.4, 0.55, 0.7)
	environment.ambient_light_color = Color(0.35, 0.35, 0.4)
	environment.ambient_light_energy = 0.6
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.environment = environment
	add_child(env)

func _create_camera() -> void:
	var cam_rig: Node3D = Node3D.new()
	cam_rig.name = "RTSCamera"
	cam_rig.set_script(load("res://scripts/rts_camera.gd"))
	cam_rig.global_position = Vector3(0, 0, 0)

	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.rotation_degrees.x = -55
	cam_rig.add_child(pivot)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = 45
	camera.position.z = 20
	pivot.add_child(camera)

	add_child(cam_rig)

func _create_input_controller() -> void:
	var controller := Node.new()
	controller.name = "InputController"
	controller.set_script(load("res://scripts/rts_input_controller.gd"))
	add_child(controller)
	# Link camera rig (deferred so tree is ready)
	controller.set_deferred("camera_rig", get_node("RTSCamera"))

func _spawn_player_units() -> void:
	# 5 Grunts
	for i in range(5):
		var unit := UnitBuilder.create_unit(GRUNT_CONFIG)
		unit.team = RTSUnit.Team.PLAYER
		add_child(unit)
		unit.global_position = Vector3(-10 + i * 2.5, 0, -5)

	# 3 Peons
	for i in range(3):
		var unit := UnitBuilder.create_unit(PEON_CONFIG)
		unit.team = RTSUnit.Team.PLAYER
		add_child(unit)
		unit.global_position = Vector3(-5 + i * 3.0, 0, -10)

	# 2 Shamans
	for i in range(2):
		var unit := UnitBuilder.create_unit(SHAMAN_CONFIG)
		unit.team = RTSUnit.Team.PLAYER
		add_child(unit)
		unit.global_position = Vector3(-2 + i * 4.0, 0, -15)

func _spawn_enemy_units() -> void:
	var enemy_config := GRUNT_CONFIG.duplicate()
	enemy_config["team"] = RTSUnit.Team.ENEMY
	enemy_config["color"] = Color(0.7, 0.15, 0.1)

	for i in range(5):
		var unit := UnitBuilder.create_unit(enemy_config)
		unit.team = RTSUnit.Team.ENEMY
		add_child(unit)
		unit.global_position = Vector3(-10 + i * 2.5, 0, 20)
