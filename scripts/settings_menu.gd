extends CanvasLayer

## Settings menu — volume sliders + controls reference.
## Used from both main menu and pause menu.
## Persists to user://settings.cfg.

signal closed

var _overlay: ColorRect
var _master_slider: HSlider
var _sfx_slider: HSlider
var _ambience_slider: HSlider
var _master_label: Label
var _sfx_label: Label
var _ambience_label: Label

const SETTINGS_PATH := "user://settings.cfg"

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_overlay.visible = false
	_load_settings()

func show_menu() -> void:
	_overlay.visible = true
	_sync_sliders()

func hide_menu() -> void:
	_overlay.visible = false
	_save_settings()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _overlay.visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide_menu()
		get_viewport().set_input_as_handled()

func _sync_sliders() -> void:
	if AudioManager:
		_master_slider.value = AudioManager.master_volume
		_sfx_slider.value = AudioManager.sfx_volume
		_ambience_slider.value = AudioManager.ambience_volume
		_update_label(_master_label, AudioManager.master_volume)
		_update_label(_sfx_label, AudioManager.sfx_volume)
		_update_label(_ambience_label, AudioManager.ambience_volume)

func _update_label(lbl: Label, val: float) -> void:
	lbl.text = str(int(val * 100)) + "%"

func _on_master_changed(val: float) -> void:
	if AudioManager:
		AudioManager.master_volume = val
		# Update live ambience volume
		if AudioManager.ambience_player and AudioManager.ambience_player.playing:
			AudioManager.ambience_player.volume_db = linear_to_db(AudioManager.ambience_volume * val)
	_update_label(_master_label, val)

func _on_sfx_changed(val: float) -> void:
	if AudioManager:
		AudioManager.sfx_volume = val
	_update_label(_sfx_label, val)

func _on_ambience_changed(val: float) -> void:
	if AudioManager:
		AudioManager.ambience_volume = val
		if AudioManager.ambience_player and AudioManager.ambience_player.playing:
			AudioManager.ambience_player.volume_db = linear_to_db(val * AudioManager.master_volume)
	_update_label(_ambience_label, val)

func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "master", AudioManager.master_volume if AudioManager else 0.7)
	config.set_value("audio", "sfx", AudioManager.sfx_volume if AudioManager else 0.8)
	config.set_value("audio", "ambience", AudioManager.ambience_volume if AudioManager else 0.3)
	config.save(SETTINGS_PATH)

func _load_settings() -> void:
	var config = ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	if AudioManager:
		AudioManager.master_volume = config.get_value("audio", "master", 0.7)
		AudioManager.sfx_volume = config.get_value("audio", "sfx", 0.8)
		AudioManager.ambience_volume = config.get_value("audio", "ambience", 0.3)

func _on_back() -> void:
	hide_menu()

func _build_ui() -> void:
	_overlay = ColorRect.new()
	_overlay.color = Color(0.0, 0.0, 0.0, 0.75)
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_overlay)

	# Title
	var title = Label.new()
	title.text = "SETTINGS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.35))
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_top = 80
	title.offset_bottom = 140
	title.offset_left = -200
	title.offset_right = 200
	_overlay.add_child(title)

	# Main container — centered
	var main_box = VBoxContainer.new()
	main_box.set_anchors_preset(Control.PRESET_CENTER)
	main_box.offset_left = -260
	main_box.offset_right = 260
	main_box.offset_top = -120
	main_box.offset_bottom = 200
	main_box.add_theme_constant_override("separation", 8)
	_overlay.add_child(main_box)

	# ---- AUDIO SECTION ----
	var audio_header = Label.new()
	audio_header.text = "AUDIO"
	audio_header.add_theme_font_size_override("font_size", 22)
	audio_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	main_box.add_child(audio_header)

	# Master volume
	var master_row = _make_slider_row("Master")
	_master_slider = master_row[0]
	_master_label = master_row[1]
	_master_slider.value_changed.connect(_on_master_changed)
	main_box.add_child(master_row[2])

	# SFX volume
	var sfx_row = _make_slider_row("SFX")
	_sfx_slider = sfx_row[0]
	_sfx_label = sfx_row[1]
	_sfx_slider.value_changed.connect(_on_sfx_changed)
	main_box.add_child(sfx_row[2])

	# Ambience volume
	var amb_row = _make_slider_row("Ambience")
	_ambience_slider = amb_row[0]
	_ambience_label = amb_row[1]
	_ambience_slider.value_changed.connect(_on_ambience_changed)
	main_box.add_child(amb_row[2])

	# ---- SEPARATOR ----
	var sep = HSeparator.new()
	sep.add_theme_constant_override("separation", 16)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	main_box.add_child(sep)

	# ---- CONTROLS SECTION ----
	var controls_header = Label.new()
	controls_header.text = "CONTROLS"
	controls_header.add_theme_font_size_override("font_size", 22)
	controls_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	main_box.add_child(controls_header)

	var controls_grid = GridContainer.new()
	controls_grid.columns = 2
	controls_grid.add_theme_constant_override("h_separation", 24)
	controls_grid.add_theme_constant_override("v_separation", 4)
	main_box.add_child(controls_grid)

	var bindings = [
		["Move", "Left Click"],
		["Attack", "Left Click (on enemy)"],
		["Spells", "Q / W / E / R"],
		["Camera Pan", "WASD / Arrow Keys"],
		["Camera Zoom", "Scroll Wheel"],
		["Inventory", "I / Tab"],
		["Pause", "ESC"],
	]
	for b in bindings:
		var action_label = Label.new()
		action_label.text = b[0]
		action_label.add_theme_font_size_override("font_size", 16)
		action_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.65))
		action_label.custom_minimum_size.x = 140
		controls_grid.add_child(action_label)

		var key_label = Label.new()
		key_label.text = b[1]
		key_label.add_theme_font_size_override("font_size", 16)
		key_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
		controls_grid.add_child(key_label)

	# ---- BACK BUTTON ----
	var back_btn = _make_button("BACK")
	back_btn.pressed.connect(_on_back)
	main_box.add_child(back_btn)

## Returns [slider, value_label, container_hbox]
func _make_slider_row(label_text: String) -> Array:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)

	var lbl = Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.8))
	lbl.custom_minimum_size.x = 100
	hbox.add_child(lbl)

	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = 0.7
	slider.custom_minimum_size = Vector2(260, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Style the slider
	var grabber_style = StyleBoxFlat.new()
	grabber_style.bg_color = Color(0.85, 0.65, 0.2)
	grabber_style.set_corner_radius_all(4)
	grabber_style.content_margin_left = 8
	grabber_style.content_margin_right = 8
	grabber_style.content_margin_top = 8
	grabber_style.content_margin_bottom = 8
	slider.add_theme_stylebox_override("grabber_area", grabber_style)

	var slider_style = StyleBoxFlat.new()
	slider_style.bg_color = Color(0.2, 0.18, 0.25)
	slider_style.set_corner_radius_all(3)
	slider.add_theme_stylebox_override("slider", slider_style)

	hbox.add_child(slider)

	var val_label = Label.new()
	val_label.text = "70%"
	val_label.add_theme_font_size_override("font_size", 16)
	val_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	val_label.custom_minimum_size.x = 50
	val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(val_label)

	return [slider, val_label, hbox]

func _make_button(text: String) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 22)
	btn.custom_minimum_size = Vector2(320, 52)

	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.45, 0.3, 0.1, 0.9)
	style_normal.border_color = Color(0.75, 0.55, 0.2)
	style_normal.set_border_width_all(2)
	style_normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", style_normal)

	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.6, 0.42, 0.15, 0.95)
	style_hover.border_color = Color(1.0, 0.8, 0.3)
	btn.add_theme_stylebox_override("hover", style_hover)

	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = style_normal.bg_color.darkened(0.3)
	btn.add_theme_stylebox_override("pressed", style_pressed)

	btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85))

	return btn
