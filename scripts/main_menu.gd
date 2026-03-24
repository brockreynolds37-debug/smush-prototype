extends Node3D

## Main menu — dark dungeon backdrop with title + buttons.
## Entry point before character select.

var cam: Camera3D = null
var cam_angle: float = 0.0
var is_transitioning: bool = false
var _settings_menu: Node = null
var _continue_btn: Button = null
var _difficulty_label: Label = null
var _leaderboard_overlay: CanvasLayer = null

func _ready() -> void:
	_build_3d_scene()
	_build_ui()
	if AudioManager:
		AudioManager.play_ambient()

func _process(delta: float) -> void:
	# Slow camera orbit around center
	cam_angle += delta * 0.15
	if cam:
		cam.position.x = sin(cam_angle) * 8.0
		cam.position.z = cos(cam_angle) * 8.0
		cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)

func _build_3d_scene() -> void:
	# Camera
	cam = Camera3D.new()
	cam.position = Vector3(0, 4.0, 8.0)
	cam.fov = 45.0
	cam.current = true
	add_child(cam)

	# Environment
	var world_env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.02, 0.04)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.08, 0.06, 0.12)
	environment.ambient_light_energy = 0.2
	environment.tonemap_mode = Environment.TONE_MAP_ACES
	environment.glow_enabled = true
	environment.glow_intensity = 0.6
	environment.glow_bloom = 0.15
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.05, 0.03, 0.08)
	environment.fog_density = 0.02
	world_env.environment = environment
	add_child(world_env)

	# Ground — dark stone floor
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.06, 0.05, 0.08)
	ground_mat.roughness = 0.95
	ground.set_surface_override_material(0, ground_mat)
	add_child(ground)

	# Pillars in a circle
	for i in range(8):
		var angle = i * TAU / 8.0
		var pillar = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.5
		cyl.height = 5.0
		cyl.radial_segments = 8
		pillar.mesh = cyl
		pillar.position = Vector3(cos(angle) * 5.0, 2.5, sin(angle) * 5.0)
		var pillar_mat = StandardMaterial3D.new()
		pillar_mat.albedo_color = Color(0.12, 0.1, 0.14)
		pillar_mat.roughness = 0.8
		pillar.set_surface_override_material(0, pillar_mat)
		add_child(pillar)

	# Center pedestal with glow
	var pedestal = MeshInstance3D.new()
	var ped_mesh = CylinderMesh.new()
	ped_mesh.top_radius = 1.0
	ped_mesh.bottom_radius = 1.2
	ped_mesh.height = 0.5
	ped_mesh.radial_segments = 16
	pedestal.mesh = ped_mesh
	pedestal.position = Vector3(0, 0.25, 0)
	var ped_mat = StandardMaterial3D.new()
	ped_mat.albedo_color = Color(0.15, 0.1, 0.2)
	ped_mat.roughness = 0.3
	ped_mat.metallic = 0.5
	ped_mat.emission_enabled = true
	ped_mat.emission = Color(0.3, 0.15, 0.4)
	ped_mat.emission_energy_multiplier = 0.5
	pedestal.set_surface_override_material(0, ped_mat)
	add_child(pedestal)

	# Warm key light from above
	var key_light = SpotLight3D.new()
	key_light.position = Vector3(0, 8, 0)
	key_light.rotation_degrees = Vector3(-90, 0, 0)
	key_light.light_color = Color(0.9, 0.7, 0.4)
	key_light.light_energy = 3.0
	key_light.spot_range = 15.0
	key_light.spot_angle = 40.0
	key_light.shadow_enabled = true
	add_child(key_light)

	# Flickering torches on alternating pillars
	for i in range(0, 8, 2):
		var angle = i * TAU / 8.0
		var torch = OmniLight3D.new()
		torch.position = Vector3(cos(angle) * 4.5, 3.5, sin(angle) * 4.5)
		torch.light_color = Color(1.0, 0.6, 0.2)
		torch.light_energy = 1.5
		torch.omni_range = 5.0
		torch.omni_attenuation = 1.5
		add_child(torch)
		# Flicker via tween
		var tw = create_tween().set_loops()
		tw.tween_property(torch, "light_energy", 1.0 + randf() * 0.5, 0.3 + randf() * 0.4)
		tw.tween_property(torch, "light_energy", 1.5 + randf() * 0.5, 0.3 + randf() * 0.4)

func _build_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	# Title: SMUSH
	var title = Label.new()
	title.text = "SMUSH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 96)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 140
	title.offset_bottom = 260
	canvas.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Enter the Arena. Entertain the Crowd. Survive."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.5, 0.65))
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 250
	subtitle.offset_bottom = 280
	canvas.add_child(subtitle)

	# Button container
	var btn_box = VBoxContainer.new()
	btn_box.set_anchors_preset(Control.PRESET_CENTER)
	btn_box.offset_left = -160
	btn_box.offset_right = 160
	btn_box.offset_top = 80
	btn_box.offset_bottom = 260
	btn_box.add_theme_constant_override("separation", 16)
	canvas.add_child(btn_box)

	# Continue button (only if save exists)
	if SaveManager.has_save():
		_continue_btn = _make_button("CONTINUE")
		_continue_btn.pressed.connect(_on_continue)
		btn_box.add_child(_continue_btn)

	# New Game button
	var new_game_btn = _make_button("NEW GAME", SaveManager.has_save())
	new_game_btn.pressed.connect(_on_new_game)
	btn_box.add_child(new_game_btn)

	# Difficulty selector row
	var diff_row = HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	btn_box.add_child(diff_row)

	var diff_left = _make_small_button("<")
	diff_left.pressed.connect(_cycle_difficulty.bind(-1))
	diff_row.add_child(diff_left)

	_difficulty_label = Label.new()
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_label.add_theme_font_size_override("font_size", 20)
	_difficulty_label.custom_minimum_size = Vector2(200, 0)
	diff_row.add_child(_difficulty_label)
	_update_difficulty_label()

	var diff_right = _make_small_button(">")
	diff_right.pressed.connect(_cycle_difficulty.bind(1))
	diff_row.add_child(diff_right)

	# Multiplayer button
	var mp_btn = _make_button("MULTIPLAYER", true)
	mp_btn.pressed.connect(_on_multiplayer)
	btn_box.add_child(mp_btn)

	# Settings button
	var settings_btn = _make_button("SETTINGS", true)
	settings_btn.pressed.connect(_on_settings)
	btn_box.add_child(settings_btn)

	# Leaderboard button
	var lb_btn = _make_button("LEADERBOARD", true)
	lb_btn.pressed.connect(_on_leaderboard)
	btn_box.add_child(lb_btn)

	# Quit button
	var quit_btn = _make_button("QUIT", true)
	quit_btn.pressed.connect(_on_quit)
	btn_box.add_child(quit_btn)

	# Settings menu overlay
	var SettingsMenuScript = load("res://scripts/settings_menu.gd")
	_settings_menu = SettingsMenuScript.new()
	add_child(_settings_menu)

	# Version label
	var version = Label.new()
	version.text = "v0.1.0 — Prototype"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(0.3, 0.3, 0.35))
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -200
	version.offset_top = -30
	version.offset_right = -10
	canvas.add_child(version)

func _make_button(text: String, subdued: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 24)
	btn.custom_minimum_size = Vector2(320, 56)

	var style_normal = StyleBoxFlat.new()
	if subdued:
		style_normal.bg_color = Color(0.12, 0.1, 0.15, 0.85)
		style_normal.border_color = Color(0.3, 0.25, 0.35, 0.5)
	else:
		style_normal.bg_color = Color(0.45, 0.3, 0.1, 0.9)
		style_normal.border_color = Color(0.75, 0.55, 0.2)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	if subdued:
		style_hover.bg_color = Color(0.18, 0.15, 0.22, 0.9)
		style_hover.border_color = Color(0.5, 0.4, 0.55, 0.7)
	else:
		style_hover.bg_color = Color(0.6, 0.42, 0.15, 0.95)
		style_hover.border_color = Color(1.0, 0.8, 0.3)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = style_normal.bg_color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	var font_color = Color(1.0, 0.9, 0.7) if not subdued else Color(0.6, 0.55, 0.65)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", font_color.lightened(0.2))

	return btn

func _make_small_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(44, 44)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.12, 0.2, 0.85)
	style.border_color = Color(0.4, 0.35, 0.5, 0.6)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	var hover = style.duplicate()
	hover.bg_color = Color(0.25, 0.2, 0.3, 0.9)
	hover.border_color = Color(0.6, 0.5, 0.7)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_color_override("font_color", Color(0.8, 0.75, 0.9))
	return btn

func _cycle_difficulty(direction: int) -> void:
	var current := int(GameManager.difficulty)
	var count := GameManager.DIFFICULTY_NAMES.size()
	current = (current + direction + count) % count
	GameManager.difficulty = current as GameManager.Difficulty
	_update_difficulty_label()

func _update_difficulty_label() -> void:
	if not _difficulty_label:
		return
	var name := GameManager.get_difficulty_name()
	var colors := {
		"Easy": Color(0.4, 0.9, 0.4),
		"Normal": Color(0.9, 0.85, 0.5),
		"Hard": Color(1.0, 0.5, 0.2),
		"Insane": Color(1.0, 0.15, 0.15),
	}
	var suffix := ""
	if GameManager.is_permadeath():
		suffix = " (Permadeath)"
	_difficulty_label.text = name + suffix
	_difficulty_label.add_theme_color_override("font_color", colors.get(name, Color.WHITE))

func _on_continue() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	# Load saved data and restore state before scene transition
	var save_data := SaveManager.load_game()
	if save_data.is_empty():
		_on_new_game()
		return
	SaveManager.apply_save_data(save_data)

	# Store save data in GameManager meta so scene script can apply hero state after spawn
	GameManager.set_meta("pending_save_data", save_data)

	_fade_to_scene("res://scenes/dungeon_floor1_scene.tscn")

func _on_new_game() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	SaveManager.delete_save()
	# First-time players get a tutorial floor before character select
	if TutorialManager.should_show_tutorial():
		GameManager.reset_game_state()
		FloorManager.current_floor = 0
		TutorialManager.is_tutorial_active = true
		_fade_to_scene("res://scenes/character_select.tscn")
	else:
		_fade_to_scene("res://scenes/character_select.tscn")

func _fade_to_scene(scene_path: String) -> void:
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fade_canvas = CanvasLayer.new()
	fade_canvas.layer = 100
	add_child(fade_canvas)
	fade_canvas.add_child(overlay)

	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.6)
	tween.tween_callback(func():
		get_tree().change_scene_to_file(scene_path)
	)

func _on_multiplayer() -> void:
	if is_transitioning:
		return
	is_transitioning = true
	_fade_to_scene("res://scenes/multiplayer_lobby.tscn")

func _on_settings() -> void:
	if _settings_menu:
		_settings_menu.show_menu()

func _on_leaderboard() -> void:
	if _leaderboard_overlay and is_instance_valid(_leaderboard_overlay):
		_leaderboard_overlay.queue_free()
		_leaderboard_overlay = null
		return

	_leaderboard_overlay = CanvasLayer.new()
	_leaderboard_overlay.layer = 50
	add_child(_leaderboard_overlay)

	# Background dim
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.8)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_leaderboard_overlay.queue_free()
			_leaderboard_overlay = null
	)
	_leaderboard_overlay.add_child(bg)

	# Panel
	var panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -280
	panel.offset_bottom = 280
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.06, 0.12, 0.95)
	style.border_color = Color(0.5, 0.4, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	_leaderboard_overlay.add_child(panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "LEADERBOARD — TOP 10"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.8, 0.4))
	vbox.add_child(title)

	# Header row
	var header = Label.new()
	header.text = "  #   Score    Floor  Kills  Time   Character       Difficulty"
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(0.6, 0.55, 0.7))
	vbox.add_child(header)

	# Entries
	var lb_entries := Leaderboard.get_entries()
	if lb_entries.is_empty():
		var empty_label = Label.new()
		empty_label.text = "\n  No runs recorded yet.\n  Complete a run to appear here!"
		empty_label.add_theme_font_size_override("font_size", 16)
		empty_label.add_theme_color_override("font_color", Color(0.5, 0.45, 0.55))
		vbox.add_child(empty_label)
	else:
		for i in range(lb_entries.size()):
			var e: Dictionary = lb_entries[i]
			var row = Label.new()
			var rank_str := "%2d." % (i + 1)
			var score_str := "%7d" % e.get("score", 0)
			var floor_str := "F%d" % e.get("floors", 0)
			var kills_str := "%4d" % e.get("kills", 0)
			var char_str: String = e.get("character", "?")
			if char_str.length() > 14:
				char_str = char_str.left(14)
			char_str = char_str.rpad(14)
			var time_str: String = e.get("time_str", "")
			if time_str == "":
				var t: float = e.get("time", 0.0)
				time_str = "%d:%02d" % [int(t) / 60, int(t) % 60]
			var diff_str: String = e.get("difficulty_name", "Normal")
			var won: bool = e.get("won", false)
			row.text = "  %s  %s    %s   %s  %s  %s  %s%s" % [rank_str, score_str, floor_str, kills_str, time_str.rpad(5), char_str, diff_str, " W" if won else ""]
			row.add_theme_font_size_override("font_size", 15)
			var color := Color(0.85, 0.8, 0.7) if i > 0 else Color(1.0, 0.9, 0.4)
			if i == 1:
				color = Color(0.8, 0.8, 0.85)
			elif i == 2:
				color = Color(0.75, 0.55, 0.3)
			row.add_theme_color_override("font_color", color)
			vbox.add_child(row)

	# Close hint
	var hint = Label.new()
	hint.text = "\nClick anywhere to close"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.4, 0.4, 0.45))
	vbox.add_child(hint)

func _on_quit() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if event is InputEventKey and event.pressed:
		# Close leaderboard on ESC
		if event.keycode == KEY_ESCAPE:
			if _leaderboard_overlay and is_instance_valid(_leaderboard_overlay):
				_leaderboard_overlay.queue_free()
				_leaderboard_overlay = null
				return
			_on_quit()
			return
		# Don't process other keys while leaderboard is open
		if _leaderboard_overlay and is_instance_valid(_leaderboard_overlay):
			return
		match event.keycode:
			KEY_ENTER, KEY_SPACE:
				if SaveManager.has_save():
					_on_continue()
				else:
					_on_new_game()
