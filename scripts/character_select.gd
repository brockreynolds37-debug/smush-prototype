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
var spell_set_button: Button = null
var spell_set_label: Label = null
var spell_names_label: Label = null
var current_spell_set: int = 0

# Modifier selection
var _modifier_btn: Button = null
var _modifier_overlay: PanelContainer = null
var _modifier_offered: Array[Dictionary] = []
var _modifier_selected: Array[Dictionary] = []
var _modifier_buttons: Array[Button] = []
var _modifier_summary_label: Label = null

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
	environment.tonemap_mode = Environment.TONE_MAPPER_ACES
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

	# --- Spell Set Toggle ---
	var spell_sep = HSeparator.new()
	spell_sep.add_theme_color_override("separator", Color(0.3, 0.3, 0.4, 0.5))
	vbox.add_child(spell_sep)

	var spell_set_row = HBoxContainer.new()
	spell_set_row.alignment = BoxContainer.ALIGNMENT_CENTER
	spell_set_row.add_theme_constant_override("separation", 12)
	vbox.add_child(spell_set_row)

	var spell_header = Label.new()
	spell_header.text = "Spell Set:"
	spell_header.add_theme_font_size_override("font_size", 14)
	spell_header.add_theme_color_override("font_color", Color(0.6, 0.55, 0.7))
	spell_set_row.add_child(spell_header)

	spell_set_button = Button.new()
	spell_set_button.add_theme_font_size_override("font_size", 16)
	spell_set_button.custom_minimum_size = Vector2(180, 30)
	spell_set_button.flat = true
	spell_set_button.add_theme_color_override("font_color", Color(0.9, 0.75, 0.4))
	spell_set_button.add_theme_color_override("font_hover_color", Color(1.0, 0.9, 0.5))
	spell_set_button.pressed.connect(_on_spell_set_toggle)
	spell_set_row.add_child(spell_set_button)

	spell_names_label = Label.new()
	spell_names_label.add_theme_font_size_override("font_size", 12)
	spell_names_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	spell_names_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spell_names_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(spell_names_label)

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

	# --- Modifier button (below start) ---
	_modifier_btn = Button.new()
	_modifier_btn.text = "MODIFIERS (0/2)"
	_modifier_btn.add_theme_font_size_override("font_size", 14)
	_modifier_btn.custom_minimum_size = Vector2(200, 35)
	_modifier_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_modifier_btn.offset_left = -100
	_modifier_btn.offset_right = 100
	_modifier_btn.offset_top = -248
	_modifier_btn.offset_bottom = -218
	_modifier_btn.flat = true
	_modifier_btn.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
	_modifier_btn.add_theme_color_override("font_hover_color", Color(0.9, 0.6, 1.0))
	_modifier_btn.pressed.connect(_on_modifier_btn)
	canvas.add_child(_modifier_btn)

	# Modifier summary label
	_modifier_summary_label = Label.new()
	_modifier_summary_label.text = "No modifiers selected"
	_modifier_summary_label.add_theme_font_size_override("font_size", 11)
	_modifier_summary_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	_modifier_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_modifier_summary_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_modifier_summary_label.offset_left = -200
	_modifier_summary_label.offset_right = 200
	_modifier_summary_label.offset_top = -215
	_modifier_summary_label.offset_bottom = -200
	canvas.add_child(_modifier_summary_label)

	# Build modifier overlay (hidden)
	_build_modifier_overlay(canvas)

	# Pre-roll offered modifiers
	_modifier_offered = RunModifiers.get_offered_modifiers()

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

	# Reset spell set to default when switching characters
	current_spell_set = 0
	_update_spell_set_display(data)

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
	CharacterData.select(data["id"], current_spell_set)

	# Apply run modifiers
	RunModifiers.set_active_modifiers(_modifier_selected)
	RunModifiers.apply_modifiers()

	# Route to tutorial floor (Floor 0) on first play, otherwise Floor 1
	if TutorialManager.should_show_tutorial():
		FloorManager.current_floor = 0
		TutorialManager.is_tutorial_active = true
	else:
		FloorManager.current_floor = 1

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

func _on_spell_set_toggle() -> void:
	var data = CharacterData.characters[current_index]
	var sets = data.get("spell_sets", [])
	if sets.size() <= 1:
		return
	current_spell_set = (current_spell_set + 1) % sets.size()
	_update_spell_set_display(data)

func _update_spell_set_display(data: Dictionary) -> void:
	var sets = data.get("spell_sets", [])
	if sets.size() == 0:
		if spell_set_button:
			spell_set_button.text = "Default"
		if spell_names_label:
			spell_names_label.text = ""
		return
	var active_set = sets[current_spell_set]
	if spell_set_button:
		spell_set_button.text = "%s  [%d/%d]" % [active_set.get("label", "Set %d" % (current_spell_set + 1)), current_spell_set + 1, sets.size()]
	if spell_names_label:
		var names: PackedStringArray = active_set.get("names", [])
		var k0: String = KeybindingManager.get_key_label(0)
		var k1: String = KeybindingManager.get_key_label(1)
		var k2: String = KeybindingManager.get_key_label(2)
		var k3: String = KeybindingManager.get_key_label(3)
		spell_names_label.text = "%s: %s  |  %s: %s  |  %s: %s  |  %s: %s" % [k0, names[0] if names.size() > 0 else "?", k1, names[1] if names.size() > 1 else "?", k2, names[2] if names.size() > 2 else "?", k3, names[3] if names.size() > 3 else "?"]

func _unhandled_input(event: InputEvent) -> void:
	if is_transitioning:
		return
	# Close modifier overlay with ESC
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _modifier_overlay and _modifier_overlay.visible:
			_modifier_overlay.visible = false
			return
	if event is InputEventKey and event.pressed:
		if _modifier_overlay and _modifier_overlay.visible:
			return  # Block other keys while modifier overlay is open
		match event.keycode:
			KEY_LEFT, KEY_A:
				_on_prev()
			KEY_RIGHT, KEY_D:
				_on_next()
			KEY_ENTER, KEY_SPACE:
				_on_start()
			KEY_TAB:
				_on_spell_set_toggle()
			KEY_M:
				_on_modifier_btn()

# ── MODIFIER SELECTION ──

func _build_modifier_overlay(canvas: CanvasLayer) -> void:
	_modifier_overlay = PanelContainer.new()
	_modifier_overlay.name = "ModifierOverlay"
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.08, 0.95)
	style.border_color = Color(0.5, 0.3, 0.7)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	_modifier_overlay.add_theme_stylebox_override("panel", style)
	_modifier_overlay.set_anchors_preset(Control.PRESET_CENTER)
	_modifier_overlay.custom_minimum_size = Vector2(500, 400)
	_modifier_overlay.offset_left = -250
	_modifier_overlay.offset_right = 250
	_modifier_overlay.offset_top = -200
	_modifier_overlay.offset_bottom = 200
	_modifier_overlay.visible = false
	canvas.add_child(_modifier_overlay)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_modifier_overlay.add_child(vbox)

	var title = Label.new()
	title.text = "RUN MODIFIERS (pick 0-2)"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var desc = Label.new()
	desc.text = "Click to toggle. Modifiers add challenge and variety."
	desc.add_theme_font_size_override("font_size", 12)
	desc.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(desc)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# Modifier buttons will be populated when overlay opens
	var mod_container = VBoxContainer.new()
	mod_container.name = "ModContainer"
	mod_container.add_theme_constant_override("separation", 6)
	vbox.add_child(mod_container)

	var close_btn = Button.new()
	close_btn.text = "CLOSE"
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.custom_minimum_size = Vector2(120, 35)
	close_btn.pressed.connect(func(): _modifier_overlay.visible = false)
	vbox.add_child(close_btn)

func _on_modifier_btn() -> void:
	if _modifier_overlay.visible:
		_modifier_overlay.visible = false
		return

	# Populate modifier buttons
	var container = _modifier_overlay.get_node("VBoxContainer/ModContainer") if _modifier_overlay.has_node("VBoxContainer/ModContainer") else null
	if container == null:
		# Find it manually
		for child in _modifier_overlay.get_children():
			if child is VBoxContainer:
				container = child.get_node_or_null("ModContainer")
				break

	if container:
		# Clear old buttons
		for child in container.get_children():
			child.queue_free()
		_modifier_buttons.clear()

		for mod in _modifier_offered:
			var btn = Button.new()
			var is_selected := mod in _modifier_selected
			btn.text = "%s %s — %s" % ["[X]" if is_selected else "[ ]", mod.get("name", "?"), mod.get("description", "")]
			btn.add_theme_font_size_override("font_size", 13)
			btn.add_theme_color_override("font_color", mod.get("color", Color.WHITE) if is_selected else Color(0.6, 0.6, 0.6))
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.custom_minimum_size = Vector2(460, 40)
			btn.pressed.connect(_on_modifier_toggled.bind(mod, btn))
			container.add_child(btn)
			_modifier_buttons.append(btn)

	_modifier_overlay.visible = true

func _on_modifier_toggled(mod: Dictionary, btn: Button) -> void:
	if mod in _modifier_selected:
		_modifier_selected.erase(mod)
	elif _modifier_selected.size() < RunModifiers.MAX_ACTIVE:
		_modifier_selected.append(mod)
	else:
		return  # Can't select more

	# Update button appearance
	var is_selected := mod in _modifier_selected
	btn.text = "%s %s — %s" % ["[X]" if is_selected else "[ ]", mod.get("name", "?"), mod.get("description", "")]
	btn.add_theme_color_override("font_color", mod.get("color", Color.WHITE) if is_selected else Color(0.6, 0.6, 0.6))

	# Update summary
	_update_modifier_summary()

func _update_modifier_summary() -> void:
	if _modifier_btn:
		_modifier_btn.text = "MODIFIERS (%d/%d)" % [_modifier_selected.size(), RunModifiers.MAX_ACTIVE]

	if _modifier_summary_label:
		if _modifier_selected.is_empty():
			_modifier_summary_label.text = "No modifiers selected"
			_modifier_summary_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			var names: Array[String] = []
			for m in _modifier_selected:
				names.append(m.get("name", "?"))
			_modifier_summary_label.text = ", ".join(names)
			_modifier_summary_label.add_theme_color_override("font_color", Color(0.7, 0.5, 0.9))
