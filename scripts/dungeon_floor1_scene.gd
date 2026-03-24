extends Node3D

## Dungeon Floor 1 scene script — wires up input, camera, hero, and dungeon builder.
## Replaces main_scene.gd for the dungeon environment.

func _ready() -> void:
	# Connect input handler to camera
	var input_handler = $InputHandler
	var camera_rig = $CameraRig
	if input_handler and camera_rig:
		input_handler.set_camera(camera_rig)

	# Wait a frame for nodes to initialize
	await get_tree().process_frame

	# Position hero at dungeon spawn point
	var builder = $DungeonBuilder
	var hero = GameManager.hero
	if builder and hero:
		hero.global_position = builder.get_spawn_position()

	# Connect hero health bar
	if hero:
		var health_bar_node = hero.get_node_or_null("HealthBar")
		if health_bar_node:
			hero.health_changed.connect(health_bar_node.update_health)
			hero.mana_changed.connect(health_bar_node.update_mana)

	# Add torch lights in key rooms for atmosphere
	_add_room_lights()

func _add_room_lights() -> void:
	var builder = $DungeonBuilder

	# Warm point lights in each room
	var light_positions := [
		builder.get_room_center("spawn"),
		builder.get_room_center("arena"),
		builder.get_room_center("arena") + Vector3(8, 0, 0),
		builder.get_room_center("arena") + Vector3(-8, 0, 0),
		builder.get_room_center("loot"),
		builder.get_room_center("guard"),
		builder.get_room_center("boss"),
		builder.get_room_center("boss") + Vector3(10, 0, 0),
		builder.get_room_center("boss") + Vector3(-10, 0, 0),
	]

	for pos in light_positions:
		if pos == Vector3.ZERO:
			continue
		var light := OmniLight3D.new()
		light.position = pos + Vector3.UP * 3.5
		light.light_color = Color(1.0, 0.8, 0.5)
		light.light_energy = 2.0
		light.omni_range = 12.0
		light.omni_attenuation = 1.5
		light.shadow_enabled = false  # Performance: skip shadow for point lights
		add_child(light)
