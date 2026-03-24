extends Node3D

## Character selection screen — 3D character preview with UI overlay.
## Rotate through available characters, see stats, then enter the dungeon.

var current_index: int = 0
var character_model: Node3D = null
var platform: MeshInstance3D = null
var platform_rotation: float = 0.0

# UI references
var name_label: Label = null
var class_label: Label = null
var desc_label: Label = null
var trait_label: Label = null
var stat_labels: Dictionary = {}
var start_button: Button = null
var left_button: Button = null
var right_button: Button = null
var title_label: Label = null

# Camera
var cam: Camera3D = null

# 3D scene elements
var model_container: Node3D = null
var spotlight: SpotLight3D = null
var env: WorldEnvironment = null

# Transition
var is_transitioning: bool = false

func _ready() -> void:
	_build_3d_scene()
	_build_ui()
	_load_character(0)

func _process(delta: float) -> void:
	# Rotate platform slowly
	platform_rotation += delta * 0.5
	if model_container:
		model_container.rotation.y = platform_rotation

	# Subtle spotlight sway
	if spotlight:
		spotlight.position.x = sin(platform_rotation * 0.7) * 0.5

func _build_3d_scene() -> void:
	# Camera
	cam = Camera3D.new()
	cam.position = Vector3(0, 2.0, 4.5)
	cam.rotation_degrees = Vector3(-10, 0, 0)
	cam.fov = 40.0
	cam.current = true
	add_child(cam)

	# Environment
	env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.05, 0.05, 0.08)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.15, 0.12, 0.2)
	environment.ambient_light_energy = 0.3
	environment.tonemap_mode = Environment.TONE_MAP_ACES
	environment.glow_enabled = true
	environment.glow_intensity = 0.4
	environment.glow_bloom = 0.1
	env.environment = environment
	add_child(env)

	# Circular platform
	platform = MeshInstance3D.new()
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 1.5
	cylinder.bottom_radius = 1.8
	cylinder.height = 0.3
	cylinder.radial_segments = 32
	platform.mesh = cylinder
	platform.position = Vector3(0, -0.15, 0)
	var plat_mat = StandardMaterial3D.new()
	plat_mat.albedo_color = Color(0.2, 0.18, 0.25)
	plat_mat.roughness = 0.3
	plat_mat.metallic = 0.6
	plat_mat.emission_enabled = true
	plat_mat.emission = Color(0.15, 0.1, 0.25)
	plat_mat.emission_energy_multiplier = 0.3
	platform.set_surface_override_material(0, plat_mat)
	add_child(platform)

	# Model container (rotates)
	model_container = Node3D.new()
	model_container.position = Vector3(0, 0.0, 0)
	add_child(model_container)

	# Spotlight from above-front
	spotlight = SpotLight3D.new()
	spotlight.position = Vector3(0, 5, 3)
	spotlight.rotation_degrees = Vector3(-55, 0, 0)
	spotlight.light_color = Color(1.0, 0.95, 0.85)
	spotlight.light_energy = 4.0
	spotlight.spot_range = 12.0
	spotlight.spot_angle = 35.0
	spotlight.spot_attenuation = 0.8
	spotlight.shadow_enabled = true
	add_child(spotlight)

	# Subtle rim light from behind
	var rim_light = SpotLight3D.new()
	rim_light.position = Vector3(0, 3, -3)
	rim_light.rotation_degrees = Vector3(35, 180, 0)
	rim_light.light_color = Color(0.4, 0.5, 0.9)
	rim_light.light_energy = 2.0
	rim_light.spot_range = 10.0
	rim_light.spot_angle = 40.0
	rim_light.shadow_enabled = false
	add_child(rim_light)

	# Ground plane (dark, barely visible)
	var ground = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	ground.position = Vector3(0, -0.3, 0)
	var ground_mat = StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.03, 0.03, 0.05)
	ground_mat.roughness = 0.9
	ground.set_surface_override_material(0, ground_mat)
	add_child(ground)

func _build_ui() -> void:
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	# --- Title ---
	title_label = Label.new()
	title_label.text = "CHOOSE YOUR CHAMPION"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 36)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_top = 40
	title_label.offset_bottom = 90
	canvas.add_child(title_label)

	# --- Left arrow ---
	left_button = Button.new()
	left_button.text = "<"
	left_button.add_theme_font_size_override("font_size", 48)
	left_button.custom_minimum_size = Vector2(80, 80)
	left_button.position = Vector2(40, 400)
	left_button.flat = true
	left_button.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	left_button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	left_button.pressed.connect(_on_prev)
	canvas.add_child(left_button)

	# --- Right arrow ---
	right_button = Button.new()
	right_button.text = ">"
	right_button.add_theme_font_size_override("font_size", 48)
	right_button.custom_minimum_size = Vector2(80, 80)
	right_button.position = Vector2(1800, 400)
	right_button.flat = true
	right_button.add_theme_color_override("font_color", Color(0.8, 0.7, 0.5))
	right_button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.6))
	right_button.pressed.connect(_on_next)
	canvas.add_child(right_button)

	# --- Character info panel (bottom center) ---
	var info_panel = PanelContainer.new()
	var info_style = StyleBoxFlat.new()
	info_style.bg_color = Color(0.05, 0.05, 0.1, 0.85)
	info_style.border_color = Color(0.4, 0.35, 0.25, 0.6)
	info_style.set_border_width_all(2)
	info_style.set_corner_radius_all(8)
	info_style.set_content_margin_all(20)
	info_panel.add_theme_stylebox_override("panel", info_style)
	info_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	info_panel.offset_left = -300
	info_panel.offset_right = 300
	info_panel.offset_top = -280
	info_panel.offset_bottom = -30
	canvas.add_child(info_panel)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	info_panel.add_child(vbox)

	# Character name
	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 28)
	name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.6))
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)

	# Class
	class_label = Label.new()
	class_label.add_theme_font_size_override("font_size", 18)
	class_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9))
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(class_label)

	# Separator
	var sep = HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.3, 0.3, 0.4, 0.5))
	vbox.add_child(sep)

	# Description
	desc_label = Label.new()
	desc_label.add_theme_font_size_override("font_size", 14)
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	desc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_label)

	# Innate trait
	trait_label = Label.new()
	trait_label.add_theme_font_size_override("font_size", 13)
	trait_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.3))
	trait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	trait_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(trait_label)

	# Stats grid
	var stat_grid = GridContainer.new()
	stat_grid.columns = 6
	stat_grid.add_theme_constant_override("h_separation", 12)
	stat_grid.add_theme_constant_override("v_separation", 4)
	vbox.add_child(stat_grid)

	var stat_colors := {
		"HP": Color(0.9, 0.3, 0.3),
		"Mana": Color(0.3, 0.5, 0.9),
		"STR": Color(0.9, 0.6, 0.3),
		"DEX": Color(0.3, 0.9, 0.5),
		"CON": Color(0.8, 0.7, 0.3),
		"INT": Color(0.6, 0.4, 0.9),
	}

	for stat_name in ["HP", "Mana", "STR", "DEX", "CON", "INT"]:
		var stat_container = VBoxContainer.new()
		stat_container.add_theme_constant_override("separation", 2)
		stat_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var stat_title = Label.new()
		stat_title.text = stat_name
		stat_title.add_theme_font_size_override("font_size", 11)
		stat_title.add_theme_color_override("font_color", stat_colors[stat_name].lerp(Color.WHITE, 0.3))
		stat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_container.add_child(stat_title)

		var stat_value = Label.new()
		stat_value.add_theme_font_size_override("font_size", 20)
		stat_value.add_theme_color_override("font_color", stat_colors[stat_name])
		stat_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_container.add_child(stat_value)

		stat_grid.add_child(stat_container)
		stat_labels[stat_name] = stat_value

	# --- Start button ---
	start_button = Button.new()
	start_button.text = "ENTER THE ARENA"
	start_button.add_theme_font_size_override("font_size", 22)
	start_button.custom_minimum_size = Vector2(300, 60)
	start_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	start_button.offset_left = -150
	start_button.offset_right = 150
	start_button.offset_top = -310
	start_button.offset_bottom = -260
	var btn_style = StyleBoxFlat.new()
	btn_style.bg_color = Color(0.5, 0.35, 0.1, 0.9)
	btn_style.set_border_width_all(2)
	btn_style.border_color = Color(0.8, 0.6, 0.2)
	btn_style.set_corner_radius_all(6)
	start_button.add_theme_stylebox_override("normal", btn_style)
	var btn_hover = btn_style.duplicate()
	btn_hover.bg_color = Color(0.65, 0.45, 0.15, 0.95)
	btn_hover.border_color = Color(1.0, 0.8, 0.3)
	start_button.add_theme_stylebox_override("hover", btn_hover)
	var btn_pressed = btn_style.duplicate()
	btn_pressed.bg_color = Color(0.4, 0.25, 0.05)
	start_button.add_theme_stylebox_override("pressed", btn_pressed)
	start_button.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	start_button.pressed.connect(_on_start)
	canvas.add_child(start_button)

	# Character counter dots
	var dot_container = HBoxContainer.new()
	dot_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
	dot_container.offset_top = 90
	dot_container.offset_bottom = 110
	dot_container.alignment = BoxContainer.ALIGNMENT_CENTER
	dot_container.add_theme_constant_override("separation", 12)
	dot_container.name = "DotContainer"
	canvas.add_child(dot_container)

	for i in range(CharacterData.characters.size()):
		var dot = Label.new()
		dot.text = "o"
		dot.add_theme_font_size_override("font_size", 16)
		dot.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		dot.name = "Dot_%d" % i
		dot_container.add_child(dot)

func _load_character(index: int) -> void:
	current_index = index
	var data = CharacterData.characters[index]

	# Update UI
	name_label.text = data["name"]
	class_label.text = "- %s -" % data["class"]
	desc_label.text = data["description"]
	trait_label.text = "[%s] %s" % [data.get("trait_name", ""), data.get("trait_desc", "")]

	for stat_name in data["stats"]:
		if stat_labels.has(stat_name):
			stat_labels[stat_name].text = str(data["stats"][stat_name])

	# Update dots
	var dot_container = get_node_or_null("CanvasLayer/DotContainer")
	if not dot_container:
		# Search through children
		for child in get_children():
			if child is CanvasLayer:
				dot_container = child.get_node_or_null("DotContainer")
				break

	if dot_container:
		for i in range(dot_container.get_child_count()):
			var dot = dot_container.get_child(i)
			if i == index:
				dot.text = "O"
				dot.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
			else:
				dot.text = "o"
				dot.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))

	# Load 3D model
	_swap_character_model(data)

	# Platform glow matches character primary color
	var plat_mat = platform.get_surface_override_material(0) as StandardMaterial3D
	if plat_mat:
		plat_mat.emission = data["color_primary"].lerp(Color(0.15, 0.1, 0.25), 0.5)

	# Reset rotation for fresh look
	platform_rotation = 0.0

func _swap_character_model(data: Dictionary) -> void:
	# Clear existing model
	for child in model_container.get_children():
		child.queue_free()

	# Load the GLB
	var model_res = load(data["model_path"])
	if model_res == null:
		return

	character_model = model_res.instantiate()
	model_container.add_child(character_model)

	# Find and play any animation
	var anim_player = _find_animation_player(character_model)
	if anim_player:
		var anims = anim_player.get_animation_list()
		if anims.size() > 0:
			anim_player.play(anims[0])
			anim_player.speed_scale = 0.6

	# Apply character colors
	_apply_character_colors(character_model, data["color_primary"], data["color_secondary"])

func _apply_character_colors(node: Node, primary: Color, secondary: Color) -> void:
	if node is MeshInstance3D:
		var mi = node as MeshInstance3D
		for i in range(mi.mesh.get_surface_count() if mi.mesh else 0):
			var mat = StandardMaterial3D.new()
			# Alternate between primary/secondary based on surface index
			mat.albedo_color = primary if i % 2 == 0 else secondary
			mat.roughness = 0.7
			mat.emission_enabled = true
			mat.emission = mat.albedo_color * 0.1
			mat.emission_energy_multiplier = 0.2
			mi.set_surface_override_material(i, mat)
	for child in node.get_children():
		_apply_character_colors(child, primary, secondary)

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var result = _find_animation_player(child)
		if result:
			return result
	return null

func _on_prev() -> void:
	if is_transitioning:
		return
	current_index = (current_index - 1 + CharacterData.characters.size()) % CharacterData.characters.size()
	_load_character(current_index)

func _on_next() -> void:
	if is_transitioning:
		return
	current_index = (current_index + 1) % CharacterData.characters.size()
	_load_character(current_index)

func _on_start() -> void:
	if is_transitioning:
		return
	is_transitioning = true

	# Save selection
	var data = CharacterData.characters[current_index]
	CharacterData.select(data["id"])

	# Fade to black and load dungeon
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var canvas = CanvasLayer.new()
	canvas.layer = 100
	add_child(canvas)
	canvas.add_child(overlay)

	var tween = create_tween()
	tween.tween_property(overlay, "color:a", 1.0, 0.8)
	tween.tween_callback(func():
		get_tree().change_scene_to_file("res://scenes/dungeon_floor1.tscn")
	)

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT, KEY_A:
				_on_prev()
			KEY_RIGHT, KEY_D:
				_on_next()
			KEY_ENTER, KEY_SPACE:
				_on_start()
