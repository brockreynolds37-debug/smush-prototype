extends Node3D

## Dungeon Floor 1 scene script — wires up input, camera, hero, dungeon builder,
## and floor transition system.

var _transition_overlay: ColorRect = null

func _ready() -> void:
	# Connect input handler to camera
	var input_handler = $InputHandler
	var camera_rig = $CameraRig
	if input_handler and camera_rig:
		input_handler.set_camera(camera_rig)

	# Create transition overlay (full-screen black rect on a CanvasLayer)
	_setup_transition_overlay()

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

	# Wire floor transition — rebuild dungeon when floor changes
	FloorManager.transition_fade_midpoint.connect(_on_floor_transition_midpoint)
	FloorManager.floor_changed.connect(_on_floor_changed)

func _setup_transition_overlay() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 100  # Above everything
	canvas.name = "TransitionLayer"
	add_child(canvas)

	_transition_overlay = ColorRect.new()
	_transition_overlay.color = Color(0, 0, 0, 1)
	_transition_overlay.anchors_preset = Control.PRESET_FULL_RECT
	_transition_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.visible = false
	canvas.add_child(_transition_overlay)

	FloorManager.set_overlay(_transition_overlay)

func _on_floor_transition_midpoint() -> void:
	# Screen is black — rebuild the dungeon for the new floor
	var builder = $DungeonBuilder

	# Clear existing dungeon geometry
	for child_name in ["Floors", "Walls", "Props", "NavRegion"]:
		var child = builder.get_node_or_null(child_name)
		if child:
			builder.remove_child(child)
			child.queue_free()
	if builder.exit_zone:
		if builder.exit_zone.get_parent():
			builder.exit_zone.get_parent().remove_child(builder.exit_zone)
		builder.exit_zone.queue_free()
		builder.exit_zone = null

	# Remove old room lights
	for child in get_children():
		if child is OmniLight3D:
			child.queue_free()

	# Clear and respawn enemies
	_clear_enemies()

	# Update floor number and regenerate
	builder.floor_number = FloorManager.current_floor
	builder.rooms.clear()
	builder.grid.clear()
	match builder.floor_number:
		1: builder._define_floor1_layout()
		2: builder._define_floor2_layout()
		3: builder._define_floor3_layout()
		_: builder._define_floor1_layout()
	builder._build_grid_from_rooms()
	builder._generate_geometry()
	builder._bake_navigation()

	# Reposition hero at new floor's spawn
	var hero = GameManager.hero
	if hero:
		hero.global_position = builder.get_spawn_position()
		hero.is_moving = false
		hero.velocity = Vector3.ZERO
		hero.current_speed = 0.0

func _on_floor_changed(floor_number: int) -> void:
	# Spawn enemies for the new floor
	_spawn_floor_enemies(floor_number)

	# Re-add room lights
	_add_room_lights()

func _clear_enemies() -> void:
	var units_node = $Units
	# Remove all enemies but keep hero
	for child in units_node.get_children():
		if child != GameManager.hero:
			GameManager.unregister_enemy(child)
			child.queue_free()
	GameManager.enemies.clear()
	GameManager.total_enemies_spawned = 0

func _spawn_floor_enemies(floor_number: int) -> void:
	var builder = $DungeonBuilder
	var units_node = $Units

	# Enemy scenes
	var orc_scene = preload("res://scenes/enemy.tscn")
	var skeleton_scene = preload("res://scenes/enemy_skeleton.tscn")

	# Boss scenes per floor
	var boss_scenes := {
		1: preload("res://scenes/boss_goblin_king.tscn"),
		2: preload("res://scenes/boss_spider_queen.tscn"),
		3: preload("res://scenes/boss_slime_lord.tscn"),
	}

	# Scale difficulty with floor number
	var enemy_count = 3 + floor_number * 2
	var rooms_with_mobs = ["arena", "guard"]
	# Floor 3 has a gauntlet room with extra enemies
	if floor_number >= 3:
		rooms_with_mobs.append("gauntlet")

	for i in range(enemy_count):
		var room_name = rooms_with_mobs[i % rooms_with_mobs.size()]
		var pos = builder.get_room_random_floor(room_name)
		if pos == Vector3.ZERO:
			continue

		# Alternate enemy types
		var enemy: Node3D
		if i % 2 == 0:
			enemy = orc_scene.instantiate()
		else:
			enemy = skeleton_scene.instantiate()

		enemy.global_position = pos
		units_node.add_child(enemy)

	# Spawn boss in boss room
	if boss_scenes.has(floor_number):
		var boss_scene = boss_scenes[floor_number]
		var boss = boss_scene.instantiate()
		var boss_pos = builder.get_room_center("boss")
		if boss_pos != Vector3.ZERO:
			boss.global_position = boss_pos
			units_node.add_child(boss)
			# Connect boss health to HUD
			_connect_boss_hud(boss)

func _connect_boss_hud(boss: Node3D) -> void:
	# Find the HUD and tell it about the boss
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("show_boss_bar"):
		hud.show_boss_bar(boss)

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
