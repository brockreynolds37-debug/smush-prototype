extends CanvasLayer

## FloorCinematic — brief dramatic reveal of the next floor's archetype.
## Shows "The Collective has prepared..." + archetype name + flavor text.
## Skippable with any key. Camera orbits the floor while text displays.

signal cinematic_finished

var _panel: Control = null
var _collective_label: Label = null
var _archetype_label: Label = null
var _flavor_label: Label = null
var _skip_label: Label = null
var _is_playing: bool = false
var _timer: float = 0.0
var _duration: float = 4.0  # Total cinematic length
var _skip_enabled: bool = false
var _skip_delay: float = 0.5  # Brief delay before skip is available

func _ready() -> void:
	layer = 98  # Below loading screen
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false

func _process(delta: float) -> void:
	if not _is_playing:
		return

	_timer += delta

	# Animate text reveals
	_update_animations()

	# Enable skip after brief delay
	if _timer >= _skip_delay and not _skip_enabled:
		_skip_enabled = true
		_skip_label.visible = true

	# Auto-finish
	if _timer >= _duration:
		_finish()

func _unhandled_input(event: InputEvent) -> void:
	if not _is_playing or not _skip_enabled:
		return
	if event is InputEventKey and event.pressed:
		_finish()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		_finish()
		get_viewport().set_input_as_handled()

func play(archetype: FloorArchetype, floor_number: int) -> void:
	if archetype == null:
		cinematic_finished.emit()
		return

	# Skip cinematic for standard crawl on early floors
	if archetype.archetype_name == "Dungeon Crawl" and floor_number <= 2:
		cinematic_finished.emit()
		return

	_is_playing = true
	_skip_enabled = false
	_timer = 0.0

	# Set text
	_collective_label.text = "The Collective has prepared..."
	_archetype_label.text = archetype.archetype_name.to_upper()
	_flavor_label.text = "\"%s\"" % archetype.flavor_text

	# Color theme from archetype
	_archetype_label.add_theme_color_override("font_color", archetype.accent_color)

	# Start invisible — will animate in
	_collective_label.modulate = Color(1, 1, 1, 0)
	_archetype_label.modulate = Color(1, 1, 1, 0)
	_flavor_label.modulate = Color(1, 1, 1, 0)
	_skip_label.visible = false

	_panel.visible = true
	_panel.modulate = Color(1, 1, 1, 1)

	# Camera orbit effect (if camera available)
	_start_camera_orbit()

func _update_animations() -> void:
	# Phase 1 (0-1s): "The Collective has prepared..." fades in
	if _timer < 1.0:
		_collective_label.modulate.a = clampf(_timer / 0.6, 0.0, 1.0)

	# Phase 2 (1-2s): archetype name slams in
	elif _timer < 2.0:
		_collective_label.modulate.a = 1.0
		var t := (_timer - 1.0) / 0.4
		_archetype_label.modulate.a = clampf(t, 0.0, 1.0)
		# Scale punch effect
		var scale_t := clampf(t, 0.0, 1.0)
		var punch := 1.0 + (1.0 - scale_t) * 0.3
		_archetype_label.scale = Vector2(punch, punch)

	# Phase 3 (2-3s): flavor text fades in
	elif _timer < 3.0:
		_archetype_label.scale = Vector2(1, 1)
		_archetype_label.modulate.a = 1.0
		var t := (_timer - 2.0) / 0.5
		_flavor_label.modulate.a = clampf(t, 0.0, 1.0)

	# Phase 4 (3-4s): hold, then fade out
	elif _timer < _duration:
		_flavor_label.modulate.a = 1.0
		var fade_t := (_timer - 3.5) / 0.5
		if fade_t > 0:
			_panel.modulate.a = clampf(1.0 - fade_t, 0.0, 1.0)

func _finish() -> void:
	_is_playing = false
	_panel.visible = false
	_stop_camera_orbit()
	cinematic_finished.emit()

func _start_camera_orbit() -> void:
	var cam = GameManager.camera
	if cam and cam.has_method("set_cinematic_mode"):
		cam.set_cinematic_mode(true)

func _stop_camera_orbit() -> void:
	var cam = GameManager.camera
	if cam and cam.has_method("set_cinematic_mode"):
		cam.set_cinematic_mode(false)

func _build_ui() -> void:
	_panel = Control.new()
	_panel.name = "CinematicPanel"
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Dark background
	var bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.85)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(bg)

	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel.add_child(center)

	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	# "The Collective has prepared..."
	_collective_label = Label.new()
	_collective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_collective_label.add_theme_font_size_override("font_size", 22)
	_collective_label.add_theme_color_override("font_color", Color(0.6, 0.55, 0.5))
	vbox.add_child(_collective_label)

	# Archetype name (big, dramatic)
	_archetype_label = Label.new()
	_archetype_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_archetype_label.add_theme_font_size_override("font_size", 56)
	_archetype_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_archetype_label.add_theme_constant_override("shadow_offset_x", 3)
	_archetype_label.add_theme_constant_override("shadow_offset_y", 3)
	_archetype_label.pivot_offset = Vector2(400, 30)  # Center pivot for scale
	vbox.add_child(_archetype_label)

	# Flavor text (italic feel)
	_flavor_label = Label.new()
	_flavor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_flavor_label.add_theme_font_size_override("font_size", 18)
	_flavor_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.45))
	vbox.add_child(_flavor_label)

	# Skip hint (bottom)
	_skip_label = Label.new()
	_skip_label.text = "Press any key to skip"
	_skip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_skip_label.add_theme_font_size_override("font_size", 13)
	_skip_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
	_skip_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skip_label.position = Vector2(-80, -40)
	_skip_label.visible = false
	_panel.add_child(_skip_label)

	add_child(_panel)
