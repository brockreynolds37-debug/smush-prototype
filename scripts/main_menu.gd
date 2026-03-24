extends Node3D

## Main menu — dark dungeon backdrop with title + buttons.
## Entry point before character select.

var cam: Camera3D = null
var cam_angle: float = 0.0
var is_transitioning: bool = false
var _settings_menu: Node = null
var _continue_btn: Button = null

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

	# Settings button
	var settings_btn = _make_button("SETTINGS", true)
	settings_btn.pressed.connect(_on_settings)
	btn_box.add_child(settings_btn)

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

func _on_settings() -> void:
	if _settings_menu:
		_settings_menu.show_menu()

func _on_quit() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ENTER, KEY_SPACE:
				if SaveManager.has_save():
					_on_continue()
				else:
					_on_new_game()
			KEY_ESCAPE:
				_on_quit()
