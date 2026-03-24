extends CanvasLayer

## Settings menu — volume sliders + controls reference.
## Used from both main menu and pause menu.
## Persists to user://settings.cfg.

signal closed

var _overlay: ColorRect
var _master_slider: HSlider
var _sfx_slider: HSlider
var _music_slider: HSlider
var _ambience_slider: HSlider
var _voice_slider: HSlider
var _master_label: Label
var _sfx_label: Label
var _music_label: Label
var _ambience_label: Label
var _voice_label: Label

# Accessibility controls
var _colorblind_button: Button
var _shake_slider: HSlider
var _shake_label: Label
var _text_scale_button: Button
var _flash_slider: HSlider
var _flash_label: Label

# Keybinding controls
var _spell_bind_buttons: Array[Button] = []
var _rebinding_index: int = -1  # -1 = not rebinding, 0-3 = which spell slot

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
	_sync_accessibility_controls()

func hide_menu() -> void:
	_overlay.visible = false
	_save_settings()
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not _overlay.visible:
		return
	# Rebinding mode: capture next key press
	if _rebinding_index >= 0 and event is InputEventKey and event.pressed:
		KeybindingManager.rebind_spell(_rebinding_index, event.keycode)
		_refresh_bind_buttons()
		_rebinding_index = -1
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		if _rebinding_index >= 0:
			# Cancel rebinding
			_spell_bind_buttons[_rebinding_index].text = KeybindingManager.get_key_label(_rebinding_index)
			_rebinding_index = -1
			get_viewport().set_input_as_handled()
			return
		hide_menu()
		get_viewport().set_input_as_handled()

func _sync_sliders() -> void:
	if AudioManager:
		_master_slider.value = AudioManager.master_volume
		_sfx_slider.value = AudioManager.sfx_volume
		_music_slider.value = AudioManager.music_volume
		_ambience_slider.value = AudioManager.ambience_volume
		_voice_slider.value = AudioManager.voice_volume
		_update_label(_master_label, AudioManager.master_volume)
		_update_label(_sfx_label, AudioManager.sfx_volume)
		_update_label(_music_label, AudioManager.music_volume)
		_update_label(_ambience_label, AudioManager.ambience_volume)
		_update_label(_voice_label, AudioManager.voice_volume)

func _update_label(lbl: Label, val: float) -> void:
	lbl.text = str(int(val * 100)) + "%"

func _on_master_changed(val: float) -> void:
	if AudioManager:
		AudioManager.set_master_volume(val)
	_update_label(_master_label, val)

func _on_sfx_changed(val: float) -> void:
	if AudioManager:
		AudioManager.set_sfx_volume(val)
	_update_label(_sfx_label, val)

func _on_music_changed(val: float) -> void:
	if AudioManager:
		AudioManager.set_music_volume(val)
	_update_label(_music_label, val)

func _on_ambience_changed(val: float) -> void:
	if AudioManager:
		AudioManager.ambience_volume = val
		if AudioManager.ambience_player and AudioManager.ambience_player.playing:
			AudioManager.ambience_player.volume_db = linear_to_db(val)
	_update_label(_ambience_label, val)

func _on_voice_changed(val: float) -> void:
	if AudioManager:
		AudioManager.set_voice_volume(val)
	_update_label(_voice_label, val)

func _save_settings() -> void:
	if AudioManager:
		AudioManager.save_volume_settings()
	AccessibilitySettings.save_settings()

func _load_settings() -> void:
	# AudioManager loads its own settings in _ready()
	pass

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
	main_box.offset_top = -220
	main_box.offset_bottom = 300
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

	# Music volume
	var music_row = _make_slider_row("Music")
	_music_slider = music_row[0]
	_music_label = music_row[1]
	_music_slider.value_changed.connect(_on_music_changed)
	main_box.add_child(music_row[2])

	# Ambience volume
	var amb_row = _make_slider_row("Ambience")
	_ambience_slider = amb_row[0]
	_ambience_label = amb_row[1]
	_ambience_slider.value_changed.connect(_on_ambience_changed)
	main_box.add_child(amb_row[2])

	# Voice/Narrator volume
	var voice_row = _make_slider_row("Voice")
	_voice_slider = voice_row[0]
	_voice_label = voice_row[1]
	_voice_slider.value_changed.connect(_on_voice_changed)
	main_box.add_child(voice_row[2])

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

	# Static bindings (non-rebindable)
	var static_bindings = [
		["Move", "Left Click"],
		["Attack", "Left Click (on enemy)"],
		["Camera Pan", "WASD / Arrow Keys"],
		["Camera Zoom", "Scroll Wheel"],
		["Inventory", "I / Tab"],
		["Pause", "ESC"],
	]
	for b in static_bindings:
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

	# Spell hotkey rebinding
	var spell_header = Label.new()
	spell_header.text = "SPELL HOTKEYS (click to rebind)"
	spell_header.add_theme_font_size_override("font_size", 18)
	spell_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	main_box.add_child(spell_header)

	var spell_grid = GridContainer.new()
	spell_grid.columns = 2
	spell_grid.add_theme_constant_override("h_separation", 24)
	spell_grid.add_theme_constant_override("v_separation", 6)
	main_box.add_child(spell_grid)

	var spell_names := ["Spell 1", "Spell 2", "Spell 3", "Spell 4"]
	_spell_bind_buttons.clear()
	for i in range(4):
		var slot_label = Label.new()
		slot_label.text = spell_names[i]
		slot_label.add_theme_font_size_override("font_size", 16)
		slot_label.add_theme_color_override("font_color", Color(0.6, 0.58, 0.65))
		slot_label.custom_minimum_size.x = 140
		spell_grid.add_child(slot_label)

		var bind_btn = Button.new()
		bind_btn.text = KeybindingManager.get_key_label(i)
		bind_btn.custom_minimum_size = Vector2(80, 30)
		bind_btn.add_theme_font_size_override("font_size", 16)
		bind_btn.pressed.connect(_on_rebind_pressed.bind(i))
		spell_grid.add_child(bind_btn)
		_spell_bind_buttons.append(bind_btn)

	var reset_btn = Button.new()
	reset_btn.text = "Reset Defaults"
	reset_btn.custom_minimum_size = Vector2(140, 32)
	reset_btn.add_theme_font_size_override("font_size", 14)
	reset_btn.pressed.connect(_on_reset_keybinds)
	main_box.add_child(reset_btn)

	# ---- SEPARATOR 2 ----
	var sep2 = HSeparator.new()
	sep2.add_theme_constant_override("separation", 16)
	sep2.add_theme_stylebox_override("separator", StyleBoxLine.new())
	main_box.add_child(sep2)

	# ---- ACCESSIBILITY SECTION ----
	var access_header = Label.new()
	access_header.text = "ACCESSIBILITY"
	access_header.add_theme_font_size_override("font_size", 22)
	access_header.add_theme_color_override("font_color", Color(0.7, 0.65, 0.8))
	main_box.add_child(access_header)

	# Colorblind mode cycle button
	var cb_row = HBoxContainer.new()
	cb_row.add_theme_constant_override("separation", 12)
	var cb_lbl = Label.new()
	cb_lbl.text = "Colorblind"
	cb_lbl.add_theme_font_size_override("font_size", 18)
	cb_lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.8))
	cb_lbl.custom_minimum_size.x = 100
	cb_row.add_child(cb_lbl)
	_colorblind_button = _make_cycle_button()
	_colorblind_button.pressed.connect(_on_colorblind_cycle)
	cb_row.add_child(_colorblind_button)
	main_box.add_child(cb_row)

	# Text scale cycle button
	var ts_row = HBoxContainer.new()
	ts_row.add_theme_constant_override("separation", 12)
	var ts_lbl = Label.new()
	ts_lbl.text = "Text Size"
	ts_lbl.add_theme_font_size_override("font_size", 18)
	ts_lbl.add_theme_color_override("font_color", Color(0.75, 0.7, 0.8))
	ts_lbl.custom_minimum_size.x = 100
	ts_row.add_child(ts_lbl)
	_text_scale_button = _make_cycle_button()
	_text_scale_button.pressed.connect(_on_text_scale_cycle)
	ts_row.add_child(_text_scale_button)
	main_box.add_child(ts_row)

	# Screen shake slider
	var shake_row = _make_slider_row("Shake")
	_shake_slider = shake_row[0]
	_shake_label = shake_row[1]
	_shake_slider.value = AccessibilitySettings.screen_shake_scale
	_shake_slider.value_changed.connect(_on_shake_changed)
	_update_label(_shake_label, AccessibilitySettings.screen_shake_scale)
	main_box.add_child(shake_row[2])

	# Screen flash slider
	var flash_row = _make_slider_row("Flash")
	_flash_slider = flash_row[0]
	_flash_label = flash_row[1]
	_flash_slider.value = AccessibilitySettings.screen_flash_scale
	_flash_slider.value_changed.connect(_on_flash_changed)
	_update_label(_flash_label, AccessibilitySettings.screen_flash_scale)
	main_box.add_child(flash_row[2])

	# Sync accessibility button labels
	_sync_colorblind_label()
	_sync_text_scale_label()

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

# ---------- ACCESSIBILITY CALLBACKS ----------

const CB_MODES := ["off", "deuteranopia", "protanopia", "tritanopia"]
const CB_LABELS := {"off": "Off", "deuteranopia": "Deuteranopia (Red-Green)", "protanopia": "Protanopia (Red-Green)", "tritanopia": "Tritanopia (Blue-Yellow)"}

const TEXT_SCALES := [1.0, 1.3, 1.6]
const TEXT_SCALE_LABELS := {1.0: "Normal", 1.3: "Large", 1.6: "Extra Large"}

func _on_colorblind_cycle() -> void:
	var idx = CB_MODES.find(AccessibilitySettings.colorblind_mode)
	idx = (idx + 1) % CB_MODES.size()
	AccessibilitySettings.colorblind_mode = CB_MODES[idx]
	_sync_colorblind_label()
	AccessibilitySettings.settings_changed.emit()

func _sync_colorblind_label() -> void:
	if _colorblind_button:
		_colorblind_button.text = CB_LABELS.get(AccessibilitySettings.colorblind_mode, "Off")

func _on_text_scale_cycle() -> void:
	var idx = TEXT_SCALES.find(AccessibilitySettings.ui_text_scale)
	idx = (idx + 1) % TEXT_SCALES.size()
	AccessibilitySettings.ui_text_scale = TEXT_SCALES[idx]
	_sync_text_scale_label()
	AccessibilitySettings.settings_changed.emit()

func _sync_text_scale_label() -> void:
	if _text_scale_button:
		_text_scale_button.text = TEXT_SCALE_LABELS.get(AccessibilitySettings.ui_text_scale, "Normal")

func _on_shake_changed(val: float) -> void:
	AccessibilitySettings.screen_shake_scale = val
	_update_label(_shake_label, val)

func _on_flash_changed(val: float) -> void:
	AccessibilitySettings.screen_flash_scale = val
	_update_label(_flash_label, val)

func _sync_accessibility_controls() -> void:
	_sync_colorblind_label()
	_sync_text_scale_label()
	if _shake_slider:
		_shake_slider.value = AccessibilitySettings.screen_shake_scale
		_update_label(_shake_label, AccessibilitySettings.screen_shake_scale)
	if _flash_slider:
		_flash_slider.value = AccessibilitySettings.screen_flash_scale
		_update_label(_flash_label, AccessibilitySettings.screen_flash_scale)

func _make_cycle_button() -> Button:
	var btn = Button.new()
	btn.text = "Off"
	btn.add_theme_font_size_override("font_size", 16)
	btn.custom_minimum_size = Vector2(280, 32)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.18, 0.25)
	style.border_color = Color(0.5, 0.45, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", style)
	var style_hover = style.duplicate()
	style_hover.bg_color = Color(0.3, 0.26, 0.35)
	style_hover.border_color = Color(0.75, 0.55, 0.2)
	btn.add_theme_stylebox_override("hover", style_hover)
	btn.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.85))
	return btn

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

# ── KEYBINDING ──

func _on_rebind_pressed(spell_index: int) -> void:
	_rebinding_index = spell_index
	_spell_bind_buttons[spell_index].text = "..."

func _on_reset_keybinds() -> void:
	KeybindingManager.reset_defaults()
	_refresh_bind_buttons()

func _refresh_bind_buttons() -> void:
	for i in range(_spell_bind_buttons.size()):
		_spell_bind_buttons[i].text = KeybindingManager.get_key_label(i)
