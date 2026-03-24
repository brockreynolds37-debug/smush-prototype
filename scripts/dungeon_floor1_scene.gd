extends Node3D

## Dungeon Floor 1 scene script — wires up input, camera, hero, dungeon builder,
## and floor transition system.

var _transition_overlay: ColorRect = null
var _merchant_ui: CanvasLayer = null
var _deep_effects: CanvasLayer = null
var _sponsor_ui: CanvasLayer = null
var _loading_screen: CanvasLayer = null
var _player_spawner: Node = null

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

	# Multiplayer: spawn all players via PlayerSpawner
	if NetworkManager.is_multiplayer_active():
		var spawner_script := preload("res://scripts/player_spawner.gd")
		_player_spawner = Node.new()
		_player_spawner.set_script(spawner_script)
		_player_spawner.name = "PlayerSpawner"
		add_child(_player_spawner)
		_player_spawner.spawn_all_players(builder.get_spawn_position(), $Units)
		# Re-fetch local hero (may have changed)
		hero = GameManager.hero

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

	# Merchant UI between floors
	var merchant_script = preload("res://scripts/merchant_ui.gd")
	_merchant_ui = CanvasLayer.new()
	_merchant_ui.set_script(merchant_script)
	_merchant_ui.name = "MerchantUI"
	add_child(_merchant_ui)
	FloorManager.show_merchant.connect(_on_show_merchant)
	_merchant_ui.merchant_closed.connect(_on_merchant_closed_show_sponsor)

	# Sponsor system between floors (after merchant)
	var sponsor_script = preload("res://scripts/sponsor_system.gd")
	_sponsor_ui = CanvasLayer.new()
	_sponsor_ui.set_script(sponsor_script)
	_sponsor_ui.name = "SponsorSystem"
	add_child(_sponsor_ui)
	_sponsor_ui.sponsor_closed.connect(FloorManager.on_merchant_closed)

	# Loading screen between floors (tips + floor name)
	var loading_script = preload("res://scripts/loading_screen.gd")
	_loading_screen = CanvasLayer.new()
	_loading_screen.set_script(loading_script)
	_loading_screen.name = "LoadingScreen"
	add_child(_loading_screen)
	FloorManager._loading_screen = _loading_screen

	# Wire Smusher Timer to dungeon builder and start it
	SmusherTimer.dungeon_builder = $DungeonBuilder
	# Skip smusher on tutorial floor
	if FloorManager.current_floor != 0:
		SmusherTimer.start_timer()

	# Pause menu (ESC to toggle)
	var pause_menu_script = preload("res://scripts/pause_menu.gd")
	var pause_menu = CanvasLayer.new()
	pause_menu.set_script(pause_menu_script)
	pause_menu.name = "PauseMenu"
	add_child(pause_menu)

	# Skill tree UI (Tab to toggle)
	var skill_tree_ui_script = preload("res://scripts/skill_tree_ui.gd")
	var skill_tree_ui = CanvasLayer.new()
	skill_tree_ui.set_script(skill_tree_ui_script)
	skill_tree_ui.name = "SkillTreeUI"
	add_child(skill_tree_ui)

	# Gamepad handler for controller support
	var gamepad_script = preload("res://scripts/gamepad_handler.gd")
	var gamepad = Node.new()
	gamepad.set_script(gamepad_script)
	gamepad.name = "GamepadHandler"
	add_child(gamepad)

	# Clear scene-baked enemies and spawn fresh for correct floor
	_clear_enemies()
	_spawn_floor_enemies(FloorManager.current_floor)

	# Restore saved hero state if continuing a run
	if GameManager.has_meta("pending_save_data"):
		var save_data: Dictionary = GameManager.get_meta("pending_save_data")
		GameManager.remove_meta("pending_save_data")
		SaveManager.apply_hero_state(save_data)

	# Start dungeon ambience
	AudioManager.start_ambience()

	# Start run timer
	GameManager.start_run()

	# Floor archetype system — pick and start archetype for this floor
	_setup_archetype(FloorManager.current_floor)

	# The Deep effects (Floor 4+) — reality distortion, camera flickers
	var deep_script = preload("res://scripts/deep_effects.gd")
	_deep_effects = CanvasLayer.new()
	_deep_effects.set_script(deep_script)
	_deep_effects.name = "DeepEffects"
	add_child(_deep_effects)
	if FloorManager.current_floor >= 4:
		_deep_effects.activate()
		# Narrator goes quiet in The Deep
		Narrator.set_process(false)

	# Floating damage numbers (3D world-space)
	var dmg_num_script = preload("res://scripts/damage_number.gd")
	var dmg_num = Node3D.new()
	dmg_num.set_script(dmg_num_script)
	dmg_num.name = "DamageNumbers"
	add_child(dmg_num)

	# Tutorial floor — start guided walkthrough with skip button
	if FloorManager.current_floor == 0 and TutorialManager.is_tutorial_active:
		_setup_tutorial_skip_button()
		TutorialManager.tutorial_completed.connect(_on_tutorial_completed)
		TutorialManager.start_tutorial()

	# Forge station — spawn on every 3rd floor (floors 3, 6, 9...) in a side room
	if FloorManager.current_floor > 0 and FloorManager.current_floor % 3 == 0:
		_spawn_forge_station()

func _spawn_forge_station() -> void:
	var builder = $DungeonBuilder
	if builder == null:
		return
	# Try to find a non-start, non-exit room to place the forge
	var forge_pos: Vector3 = Vector3.ZERO
	var rooms: Array = builder.rooms if builder.get("rooms") != null else []
	var candidate_rooms: Array = []
	for room in rooms:
		var rname: String = room.get("name", "")
		if not rname.begins_with("corridor") and rname != "start" and rname != "exit":
			candidate_rooms.append(rname)
	if candidate_rooms.size() > 0:
		candidate_rooms.shuffle()
		forge_pos = builder.get_room_center(candidate_rooms[0])
		forge_pos += Vector3(1.5, 0, 1.5)  # Offset from room center
	else:
		forge_pos = builder.get_spawn_position() + Vector3(4, 0, 4)

	var forge_script = preload("res://scripts/forge_station.gd")
	var forge := Node3D.new()
	forge.set_script(forge_script)
	forge.name = "ForgeStation"
	forge.position = forge_pos
	add_child(forge)

	if Narrator:
		Narrator.speak("A forge glows in the shadows. Walk up and press E to combine items.")

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

func _on_show_merchant(floor_number: int) -> void:
	if _merchant_ui:
		_merchant_ui.show_shop(floor_number)

func _on_merchant_closed_show_sponsor() -> void:
	# After merchant closes, show sponsor offer if audience is interested enough
	if _sponsor_ui and AudienceManager.current_mood >= AudienceManager.Mood.INTERESTED:
		_sponsor_ui.show_sponsor_offer(FloorManager.current_floor)
	else:
		FloorManager.on_merchant_closed()

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
		0: builder._define_tutorial_layout()
		1: builder._define_floor1_layout()
		2: builder._define_floor2_layout()
		3: builder._define_floor3_layout()
		4: builder._define_floor4_layout()
		_: builder._generate_procedural_layout()
	builder._build_grid_from_rooms()
	builder._generate_geometry()
	builder._bake_navigation()

	# Update Smusher Timer reference to rebuilt builder
	SmusherTimer.dungeon_builder = builder

	# Reposition hero(es) at new floor's spawn
	if _player_spawner and NetworkManager.is_multiplayer_active():
		_player_spawner.reposition_all(builder.get_spawn_position())
	else:
		var hero = GameManager.hero
		if hero:
			hero.global_position = builder.get_spawn_position()
			hero.is_moving = false
			hero.velocity = Vector3.ZERO
			hero.current_speed = 0.0

func _on_floor_changed(floor_number: int) -> void:
	# Set up new floor archetype before spawning enemies
	_setup_archetype(floor_number)

	# Spawn enemies for the new floor (if archetype uses default spawning)
	if FloorManager.current_archetype and FloorManager.current_archetype.uses_default_enemy_spawning():
		_spawn_floor_enemies(floor_number)

	# Re-add room lights
	_add_room_lights()

	# Toggle Deep effects on floor 4+
	if _deep_effects:
		if floor_number >= 4:
			_deep_effects.activate()
			Narrator.set_process(false)
		else:
			_deep_effects.deactivate()
			Narrator.set_process(true)

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
	var archer_scene = preload("res://scenes/enemy_goblin_archer.tscn")
	var mage_scene = preload("res://scenes/enemy_mage.tscn")

	# Boss scenes per floor
	var boss_scenes := {
		1: preload("res://scenes/boss_goblin_king.tscn"),
		2: preload("res://scenes/boss_spider_queen.tscn"),
		3: preload("res://scenes/boss_slime_lord.tscn"),
	}

	# Tutorial floor: single weak training dummy
	if floor_number == 0:
		var dummy = orc_scene.instantiate()
		dummy.max_health = 50
		dummy.attack_damage = 5
		var pos = builder.get_room_center("arena")
		if pos != Vector3.ZERO:
			dummy.global_position = pos
			units_node.add_child(dummy)
		return

	# Scale difficulty with floor number
	var enemy_count = 3 + floor_number * 2
	var rooms_with_mobs = ["arena", "guard"]
	# Floor 3+ has extra rooms with enemies
	if floor_number >= 3:
		rooms_with_mobs.append("gauntlet")

	for i in range(enemy_count):
		var room_name = rooms_with_mobs[i % rooms_with_mobs.size()]
		var pos = builder.get_room_random_floor(room_name)
		if pos == Vector3.ZERO:
			continue

		# Mix of melee, ranged, and mage enemies
		var enemy: Node3D
		if floor_number >= 2 and i % 4 == 3:
			# Mage every 4th enemy on floor 2+
			enemy = mage_scene.instantiate()
		elif i % 3 == 2:
			enemy = archer_scene.instantiate()
		elif i % 2 == 0:
			enemy = orc_scene.instantiate()
		else:
			enemy = skeleton_scene.instantiate()

		# Floor 4+ "The Deep" shadow variants — boosted stats, dark tint
		if floor_number >= 4:
			enemy.max_health = int(enemy.max_health * 1.5)
			enemy.current_health = enemy.max_health
			enemy.attack_damage = int(enemy.attack_damage * 1.3)
			enemy.move_speed *= 1.2
			enemy.aggro_range *= 1.5

		# Roll for elite/champion promotion (~15% base, scales with floor)
		EliteModifier.try_promote(enemy, floor_number)

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
			_connect_boss_hud(boss)
	elif floor_number >= 4:
		# Floor 4+ uses slime lord boss with boosted stats as "Void Horror"
		var deep_boss = preload("res://scenes/boss_slime_lord.tscn").instantiate()
		var boss_pos = builder.get_room_center("boss")
		if boss_pos != Vector3.ZERO:
			deep_boss.global_position = boss_pos
			if deep_boss.has_method("set_deep_variant"):
				deep_boss.set_deep_variant()
			else:
				# Boost stats manually for deep variant
				deep_boss.max_health = int(deep_boss.max_health * 2.0)
				deep_boss.current_health = deep_boss.max_health
			units_node.add_child(deep_boss)
			_connect_boss_hud(deep_boss)

func _connect_boss_hud(boss: Node3D) -> void:
	# Find the HUD and tell it about the boss
	var hud = get_tree().current_scene.get_node_or_null("HUD")
	if hud and hud.has_method("show_boss_bar"):
		hud.show_boss_bar(boss)
	# Wire boss defeat to victory check
	if boss.has_signal("boss_defeated"):
		boss.boss_defeated.connect(GameManager.on_boss_defeated)

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

var _skip_tutorial_btn: Button = null

func _setup_tutorial_skip_button() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 50
	canvas.name = "TutorialSkipLayer"
	add_child(canvas)

	_skip_tutorial_btn = Button.new()
	_skip_tutorial_btn.text = "SKIP TUTORIAL"
	_skip_tutorial_btn.add_theme_font_size_override("font_size", 16)
	_skip_tutorial_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_skip_tutorial_btn.offset_left = -180
	_skip_tutorial_btn.offset_top = -50
	_skip_tutorial_btn.offset_right = -10
	_skip_tutorial_btn.offset_bottom = -10

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.15, 0.1, 0.8)
	style.border_color = Color(0.6, 0.45, 0.2, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	_skip_tutorial_btn.add_theme_stylebox_override("normal", style)
	_skip_tutorial_btn.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	_skip_tutorial_btn.pressed.connect(_on_skip_tutorial)
	canvas.add_child(_skip_tutorial_btn)

func _on_skip_tutorial() -> void:
	TutorialManager.skip_tutorial()

func _on_tutorial_completed() -> void:
	# Remove skip button
	if _skip_tutorial_btn and is_instance_valid(_skip_tutorial_btn):
		var parent_canvas = _skip_tutorial_btn.get_parent()
		if parent_canvas:
			parent_canvas.queue_free()
	# Transition to floor 1 — set current_floor to 0 so go_to_next_floor goes to 1
	FloorManager.current_floor = 0
	SmusherTimer.dungeon_builder = $DungeonBuilder
	SmusherTimer.start_timer()
	FloorManager.go_to_next_floor()

# ---------- ARCHETYPE SYSTEM ----------

func _process(delta: float) -> void:
	# Update active floor archetype each frame
	if FloorManager.current_archetype and FloorManager.current_archetype._is_active:
		FloorManager.current_archetype.update(delta)

func _setup_archetype(floor_num: int) -> void:
	# Tear down previous archetype
	_teardown_archetype()

	# Pick new archetype
	var archetype = FloorManager.pick_archetype(floor_num)
	FloorManager.current_archetype = archetype

	# Set up with dungeon references
	archetype.setup($DungeonBuilder, $Units, floor_num)

	# Connect archetype UI messages to HUD
	archetype.archetype_ui_message.connect(_on_archetype_message)

	# Connect floor completion to exit unlock
	archetype.floor_completed.connect(_on_archetype_completed)

	# Add archetype HUD overlay
	var overlay = archetype.create_hud_overlay()
	if overlay:
		var hud = get_tree().current_scene.get_node_or_null("HUD")
		if hud:
			hud.add_child(overlay)

	# If archetype doesn't use default spawning, clear default enemies
	if not archetype.uses_default_enemy_spawning():
		_clear_enemies()

	# Start the archetype
	archetype.start()

func _teardown_archetype() -> void:
	if FloorManager.current_archetype:
		FloorManager.current_archetype.stop()
		FloorManager.current_archetype.destroy_hud_overlay()
		if FloorManager.current_archetype.archetype_ui_message.is_connected(_on_archetype_message):
			FloorManager.current_archetype.archetype_ui_message.disconnect(_on_archetype_message)
		if FloorManager.current_archetype.floor_completed.is_connected(_on_archetype_completed):
			FloorManager.current_archetype.floor_completed.disconnect(_on_archetype_completed)
		FloorManager.current_archetype = null

func _on_archetype_message(text: String, color: Color, duration: float) -> void:
	# Route archetype messages to the Narrator for floating text
	if Narrator and Narrator.has_method("show_commentary"):
		Narrator.show_commentary(text)

func _on_archetype_completed() -> void:
	# Archetype win condition met — unlock exit
	var builder = $DungeonBuilder
	if builder and builder.exit_zone:
		# Make exit portal visible/active
		builder.exit_zone.monitoring = true
		builder.exit_zone.visible = true
