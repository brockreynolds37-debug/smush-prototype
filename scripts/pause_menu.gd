extends CanvasLayer

## Pause menu overlay — ESC toggles, pauses game tree.
## Resume / Restart / Quit to Menu.

var is_paused: bool = false
var _overlay: ColorRect
var _panel: PanelContainer
var _resume_btn: Button
var _restart_btn: Button
var _quit_btn: Button
var _settings_menu: Node = null
var _in_settings: bool = false

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_overlay.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _in_settings:
			return  # Settings menu handles its own ESC
		if GameManager.game_state != GameManager.GameState.PLAYING:
			return
		if is_paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	is_paused = true
	_overlay.visible = true
	get_tree().paused = true

func _resume() -> void:
	is_paused = false
	_overlay.visible = false
	get_tree().paused = false

func _on_resume() -> void:
	_resume()

func _on_restart() -> void:
	_resume()
	GameManager.reset_game_state()
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _on_settings() -> void:
	_in_settings = true
	if _settings_menu:
		_settings_menu.show_menu()

func _on_settings_closed() -> void:
	_in_settings = false

func _on_quit_menu() -> void:
	_resume()
	GameManager.reset_game_state()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _build_ui() -> void:
	# Dark overlay
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.65)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Title
	var title = Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 160
	title.offset_bottom = 230
	title.offset_left = -200
	title.offset_right = 200
	_overlay.add_child(title)

	# Button container
	var btn_box = VBoxContainer.new()
	btn_box.set_anchors_preset(Control.PRESET_CENTER)
	btn_box.offset_left = -160
	btn_box.offset_right = 160
	btn_box.offset_top = -40
	btn_box.offset_bottom = 160
	btn_box.add_theme_constant_override("separation", 14)
	_overlay.add_child(btn_box)

	_resume_btn = _make_button("RESUME")
	_resume_btn.pressed.connect(_on_resume)
	btn_box.add_child(_resume_btn)

	_restart_btn = _make_button("RESTART", true)
	_restart_btn.pressed.connect(_on_restart)
	btn_box.add_child(_restart_btn)

	var _settings_btn = _make_button("SETTINGS", true)
	_settings_btn.pressed.connect(_on_settings)
	btn_box.add_child(_settings_btn)

	_quit_btn = _make_button("QUIT TO MENU", true)
	_quit_btn.pressed.connect(_on_quit_menu)
	btn_box.add_child(_quit_btn)

	# Settings menu overlay
	var SettingsMenuScript = load("res://scripts/settings_menu.gd")
	_settings_menu = SettingsMenuScript.new()
	_settings_menu.closed.connect(_on_settings_closed)
	add_child(_settings_menu)

	# Hint
	var hint = Label.new()
	hint.text = "Press ESC to resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.4, 0.38, 0.45))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -50
	hint.offset_bottom = -20
	hint.offset_left = -150
	hint.offset_right = 150
	_overlay.add_child(hint)

func _make_button(text: String, subdued: bool = false) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(320, 52)

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
